defmodule Cafex.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link do
    Supervisor.start_link __MODULE__, nil, [name: __MODULE__]
  end

  def start_producer(topic, opts \\ []) do
    :ok = ensure_started(Cafex.Producer.Supervisor, [])
    Cafex.Producer.Supervisor.start_producer(topic, opts)
  end

  defdelegate stop_producer(pid), to: Cafex.Producer.Supervisor

  def start_consumer(name, opts \\ []) do
    :ok = ensure_started(Cafex.Consumer.Supervisor, [])
    Cafex.Consumer.Supervisor.start_consumer(name, opts)
  end

  defdelegate stop_consumer(name), to: Cafex.Consumer.Supervisor

  def start_topic(name, brokers, opts \\ []) do
    :ok = ensure_started(Cafex.Topic.Supervisor, []) # Deprecated
    Cafex.Topic.Supervisor.start_topic(name, brokers, opts)
  end

  def init(_) do
    children = [
      # supervisor(Cafex.Topic.Supervisor, []), # Deprecated
      # supervisor(Cafex.Producer.Supervisor, []),
      # supervisor(Cafex.Consumer.Supervisor, [])
    ]
    supervise children, strategy: :one_for_one,
                    max_restarts: 10,
                     max_seconds: 60
  end

  defp ensure_started(sup, args) do
    case Supervisor.start_child __MODULE__, supervisor(sup, args) do
      {:ok, _} -> :ok
      {:ok, _, _} -> :ok
      {:error, {:already_started, _}} -> :ok
      error -> error
    end
  end
end
