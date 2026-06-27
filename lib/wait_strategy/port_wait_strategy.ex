# SPDX-License-Identifier: MIT
defmodule TestcontainerEx.PortWaitStrategy do
  @moduledoc """
  Considers the container as ready when it successfully accepts connections on the specified port.
  """

  require Logger

  @retry_delay 200
  defstruct [:ip, :port, :timeout, retry_delay: @retry_delay]

  # Public interface

  @doc """
  Creates a new PortWaitStrategy to wait until a specified port is open and accepting connections.
  """
  def new(ip, port, timeout \\ 5000, retry_delay \\ @retry_delay) do
    %__MODULE__{ip: ip, port: port, timeout: timeout, retry_delay: retry_delay}
  end

  # Private functions and implementations

  defimpl TestcontainerEx.WaitStrategy do
    @impl true
    def wait_until_container_is_ready(wait_strategy, container, _conn) do
      host = TestcontainerEx.get_host(container)
      host_port = TestcontainerEx.get_port(container, wait_strategy.port)

      case {host, host_port} do
        {_, nil} ->
          {:error, TestcontainerEx.Error.port_not_mapped(wait_strategy.port), wait_strategy}

        _ ->
          perform_port_check(%{wait_strategy | ip: host}, host_port)
      end
    end

    defp perform_port_check(wait_strategy, host_port) do
      started_at = current_time_millis()
      attempt = 0

      case wait_for_open_port(wait_strategy, host_port, started_at, attempt) do
        :port_is_open ->
          :ok

        {:error, reason} ->
          {:error, reason, wait_strategy}
      end
    end

    defp wait_for_open_port(wait_strategy, host_port, start_time, attempt) do
      if reached_timeout?(wait_strategy.timeout, start_time) do
        {:error, fail_with_logs(wait_strategy, host_port, start_time, attempt)}
      else
        check_port_status(wait_strategy, host_port, start_time, attempt)
      end
    end

    defp check_port_status(wait_strategy, host_port, start_time, attempt) do
      poll_result = port_open?(wait_strategy.ip, host_port)

      elapsed_ms = current_time_millis() - start_time

      :telemetry.execute(
        [:testcontainer_ex, :wait_strategy, :poll],
        %{attempt: attempt + 1, elapsed_ms: elapsed_ms},
        %{
          strategy: :port_wait,
          container_id: nil,
          result: if(poll_result, do: :ok, else: {:error, :port_not_open})
        }
      )

      if poll_result do
        :port_is_open
      else
        log_retry_message(wait_strategy, host_port)
        :timer.sleep(wait_strategy.retry_delay)
        wait_for_open_port(wait_strategy, host_port, start_time, attempt + 1)
      end
    end

    defp port_open?(ip, port, timeout \\ 1000) do
      case :gen_tcp.connect(to_charlist(ip), port, [:binary, active: false], timeout) do
        {:ok, socket} ->
          :gen_tcp.close(socket)
          true

        {:error, _} ->
          false
      end
    end

    defp current_time_millis, do: System.monotonic_time(:millisecond)

    defp reached_timeout?(timeout, start_time), do: current_time_millis() - start_time > timeout

    defp fail_with_logs(_wait_strategy, _host_port, start_time, _attempt) do
      elapsed_ms = current_time_millis() - start_time
      TestcontainerEx.Error.wait_strategy_failed(:port_wait, elapsed_ms)
    end

    defp log_retry_message(wait_strategy, host_port) do
      Logger.debug(
        "Port #{wait_strategy.port} (host port #{host_port}) not open on IP #{wait_strategy.ip}, retrying in #{wait_strategy.retry_delay}ms."
      )
    end
  end
end
