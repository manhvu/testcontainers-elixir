# SPDX-License-Identifier: MIT
defmodule TestcontainerEx.LogWaitStrategy do
  @moduledoc """
  Considers the container as ready as soon as a specific log message is detected in the container's log stream.
  """
  require Logger

  @retry_delay 200
  defstruct [:log_regex, :timeout, retry_delay: @retry_delay]

  # Public interface

  @doc """
  Creates a new LogWaitStrategy.
  This strategy waits until a specific log message, matching the provided regex, appears in the container's log.
  """
  def new(log_regex, timeout \\ 5000, retry_delay \\ @retry_delay) do
    %__MODULE__{log_regex: log_regex, timeout: timeout, retry_delay: retry_delay}
  end

  # Private functions and implementations

  defimpl TestcontainerEx.WaitStrategy do
    alias TestcontainerEx.Engine

    @impl true
    def wait_until_container_is_ready(wait_strategy, container, conn) do
      started_at = get_current_time_millis()
      wait_for_log_message(wait_strategy, container.container_id, conn, started_at)
    end

    # Main loop for waiting strategy
    defp wait_for_log_message(wait_strategy, container_id, conn, start_time) do
      if reached_timeout?(start_time, wait_strategy.timeout) do
        {:error, fail_with_logs(wait_strategy, container_id, conn, start_time), wait_strategy}
      else
        process_log(wait_strategy, container_id, conn, start_time)
      end
    end

    defp process_log(wait_strategy, container_id, conn, start_time) do
      attempt = 0
      do_process_log(wait_strategy, container_id, conn, start_time, attempt)
    end

    defp do_process_log(wait_strategy, container_id, conn, start_time, attempt) do
      case log_matches?(container_id, wait_strategy.log_regex, conn) do
        true ->
          elapsed_ms = get_current_time_millis() - start_time

          :telemetry.execute(
            [:testcontainer_ex, :wait_strategy, :poll],
            %{attempt: attempt + 1, elapsed_ms: elapsed_ms},
            %{strategy: :log_wait, container_id: container_id, result: :ok}
          )

          :ok

        false ->
          elapsed_ms = get_current_time_millis() - start_time

          :telemetry.execute(
            [:testcontainer_ex, :wait_strategy, :poll],
            %{attempt: attempt + 1, elapsed_ms: elapsed_ms},
            %{strategy: :log_wait, container_id: container_id, result: {:error, :log_not_matched}}
          )

          log_retry_message(container_id, wait_strategy.log_regex, wait_strategy.retry_delay)
          :timer.sleep(wait_strategy.retry_delay)
          do_process_log(wait_strategy, container_id, conn, start_time, attempt + 1)
      end
    end

    defp log_matches?(container_id, log_regex, conn) do
      case Engine.Api.stdout_logs(container_id, conn) do
        {:ok, log_output} -> Regex.match?(log_regex, log_output)
        _ -> false
      end
    catch
      # If the log stream crashes (e.g. hackney chunked encoding error),
      # treat as not matched and retry.
      :error, _ -> false
    end

    defp get_current_time_millis, do: System.monotonic_time(:millisecond)

    defp reached_timeout?(start_time, timeout),
      do: get_current_time_millis() - start_time > timeout

    defp fail_with_logs(_wait_strategy, container_id, conn, start_time) do
      elapsed_ms = get_current_time_millis() - start_time

      last_logs =
        case Engine.Api.stdout_logs(container_id, conn) do
          {:ok, log_output} -> String.split(log_output, "\n", trim: true) |> Enum.take(-50)
          _ -> []
        end

      TestcontainerEx.Error.wait_strategy_failed(:log_wait, elapsed_ms, last_logs)
    end

    defp log_retry_message(container_id, log_regex, delay) do
      Logger.debug(
        "Logs in container #{container_id} didn't match regex #{inspect(log_regex)}, retrying in #{delay}ms."
      )
    end
  end
end
