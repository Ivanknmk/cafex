defmodule Cafex.Lock.Consul do
  @moduledoc """
  Distributed Lock implementation with Consul
  """

  use Cafex.Lock

  require Logger

  alias Cafex.Lock.Consul.Watch
  alias Cafex.Lock.Consul.Session

  defmodule State do
    @moduledoc false
    defstruct [:session, :path, :lock, :watcher]
  end

  # ===================================================================
  # API
  # ===================================================================

  @doc """
  ## Options

  All this options are defined as the Session's request body,
  see more [Session](https://www.consul.io/docs/agent/http/session.html)

    * `:ttl`          Optional, based on millisecond, default is 10*1000
    * `:lock_delay`   Optional, based on millisecond, default is 0, no delay
    * `:behavior`     Optional, default is `:release`
  """
  @spec acquire(String.t, Keyword.t) :: {:ok, pid} | {:error, term}
  def acquire(path, opts \\ []) do
    Cafex.Lock.acquire __MODULE__, [path, opts], :infinity
  end

  def release(pid) do
    Cafex.Lock.release pid
  end

  # ===================================================================
  # Cafex.Lock callbacks
  # ===================================================================

  def init([path, opts]) do
    {:ok, pid} = Session.start_link(opts)
    path = Path.join ["service", "cafex", path, "lock"]
    {:ok, %State{session: pid, path: path}}
  end

  def handle_acquire(%{path: path, session: pid} = state) do
    case Consul.Kv.put(path, "", acquire: Session.get(pid)) do
      true ->
        Logger.debug "Held the lock '#{path}'"
        {:ok, wait_change(%{state | lock: true})}
      false ->
        {:wait, wait_change(state)}
    end
  end

  def handle_release(%{lock: nil} = state), do: {:ok, state}
  def handle_release(%{path: path, session: pid} = state) do
    Logger.debug "Release the lock '#{path}'"
    case Consul.Kv.put(path, "", release: Session.get(pid)) do
      true ->
        {:ok, %{state | lock: nil}}
      error ->
        Logger.error("Consul error on putting release session request: #{inspect error}")
        {:error, :consul_error}
    end
  end

  def terminate(%{session: pid} = state) do
    handle_release state
    Session.stop pid
    :ok
  end

  # ===================================================================
  #  Internal functions
  # ===================================================================

  defp wait_change(%{path: path} = state) do
    {:ok, %{body: [body]} = response} = Consul.Kv.fetch(path)
    if is_nil(body["Session"]) do
      send self, :lock_changed
      state
    else
      index = Consul.Response.consul_index response
      start_watcher(index, state)
    end
  end

  defp start_watcher(index, %{watcher: pid, path: path} = state) do
    if is_nil(pid) or not Process.alive?(pid) do
      {:ok, pid} = Watch.start_link(path, index, self)
      %{state | watcher: pid}
    else
      state
    end
  end
end
