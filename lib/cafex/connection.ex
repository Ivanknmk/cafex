defmodule Cafex.Connection do
  use GenServer

  require Logger

  alias Cafex.Protocol.Decoder

  defmodule State do
    @moduledoc false
    defstruct client_id: nil,
              correlation_id: 0,
              host: nil,
              port: nil,
              send_buffer: nil,
              timeout: nil,
              socket: nil
  end

  @default_client_id "cafex"
  @default_send_buffer 10_000_000
  @default_timeout 5000

  @type conn     :: pid
  @type request  :: Cafex.Protocol.Request.t
  @type receiver :: {:fsm, pid} | {:server, pid} | pid
  @type response :: Decoder.response

  # ===================================================================
  # API
  # ===================================================================

  def start_link(host, port, opts \\ []) do
    GenServer.start_link __MODULE__, [host, port, opts]
  end

  def start(host, port, opts \\ []) do
    GenServer.start __MODULE__, [host, port, opts]
  end

  @spec request(conn, request) :: :ok | {:ok, response} | {:error, term}
  def request(pid, request) do
    GenServer.call pid, {:request, request}
  end

  @spec async_request(conn, request, receiver) :: :ok
  def async_request(pid, request, receiver) do
    GenServer.cast pid, {:async_request, request, receiver}
  end

  def close(pid) do
    GenServer.call pid, :close
  end

  # ===================================================================
  #  GenServer callbacks
  # ===================================================================

  def init([host, port, opts]) do
    client_id = Keyword.get(opts, :client_id, @default_client_id)
    buffer    = Keyword.get(opts, :send_buffer, @default_send_buffer)
    timeout   = Keyword.get(opts, :timeout, @default_timeout)

    state = %State{ client_id: client_id,
                    host: host,
                    port: port,
                    send_buffer: buffer,
                    timeout: timeout } |> maybe_open_socket
    {:ok, state}
  end

  def handle_call({:request, request}, _from, state) do
    case do_request(request, state) do
      {:ok, state} ->
        {:reply, :ok, state}
      {{:ok, reply}, state} ->
        {:reply, {:ok, reply}, state}
      {{:error, reason}, state} ->
        {:stop, reason, state}
    end
  end

  def handle_call(:close, _from, state) do
    {:stop, :normal, :ok, state}
  end

  def handle_cast({:async_request, request, receiver}, state) do
    case do_request(request, state) do
      {:ok, state} ->
        {:noreply, state}
      {{:ok, reply}, state} ->
        send_reply(receiver, {:ok, reply})
        {:noreply, state}
      {{:error, reason}, state} ->
        {:stop, reason, state}
    end
  end

  def handle_info({:tcp_closed, socket}, %{socket: socket} = state) do
    Logger.info fn -> "Connection closed by peer" end
    {:noreply, %{state | socket: nil}}
  end

  def terminate(reason, %{host: host, port: port, socket: socket}) do
    Logger.debug "Connection closed: #{host}:#{port}, reason: #{inspect reason}"
    if socket, do: :gen_tcp.close(socket)
    :ok
  end

  # ===================================================================
  #  Internal functions
  # ===================================================================

  defp maybe_open_socket(%{socket: nil, host: host, port: port, send_buffer: buffer} = state) do
    case :gen_tcp.connect(:erlang.bitstring_to_list(host), port,
                          [:binary, {:packet, 4}, {:sndbuf, buffer}]) do
      {:ok, socket} ->
        %{state | socket: socket}
      {:error, reason} ->
        throw reason
    end
  end
  defp maybe_open_socket(state), do: state

  defp send_sync_request(socket, data, timeout, has_response) do
    case :gen_tcp.send(socket, data) do
      :ok ->
        case has_response do
          true -> recv_response(socket, timeout)
          false -> :ok
        end
      {:error, _reason} = error ->
        error
    end
  end

  defp recv_response(socket, timeout) do
    receive do
      {:tcp, ^socket, data} ->
        {:ok, data}
      {:tcp_closed, ^socket} ->
        {:error, :closed}
    after
      timeout ->
        {:error, :timeout}
    end
  end

  defp do_request(request, %{client_id: client_id,
                             correlation_id: correlation_id,
                             timeout: timeout} = state) do
    data = Cafex.Protocol.encode_request(client_id, correlation_id, request)
    has_response = Cafex.Protocol.has_response?(request)
    decoder = Cafex.Protocol.Request.decoder(request)

    state = %{state | correlation_id: correlation_id + 1} |> maybe_open_socket

    case send_sync_request(state.socket, data, timeout, has_response) do
      :ok ->
        {:ok, state}
      {:ok, data} ->
        {_, reply} = Cafex.Protocol.Codec.decode_response(decoder, data)
        {{:ok, reply}, state}
      {:error, reason} ->
        Logger.error "Error sending request to broker: #{state.host}:#{state.port}: #{inspect reason}"
        {{:error, reason}, state}
    end
  end

  defp send_reply({:fsm, pid}, reply) when is_pid(pid) do
    cast_send pid, {:"$gen_event", {:kafka_response, reply}}
  end
  defp send_reply({:server, pid}, reply) when is_pid(pid) do
    cast_send pid, {:"$gen_cast", {:kafka_response, reply}}
  end
  defp send_reply(pid, reply) when is_pid(pid) do
    cast_send pid, {:kafka_response, reply}
  end

  defp cast_send(dest, msg) do
    try do
      :erlang.send dest, msg, [:noconnect, :nosuspend]
    catch
      _, reason -> {:error, reason}
    end
  end
end
