defmodule TestcontainerEx.LogConsumer do
  @moduledoc """
  Streams container stdout/stderr to Elixir's Logger.

  Attach via `TestcontainerEx.Container.with_log_consumer/2` on the container config,
  then call `start_link/3` after the container is running.

  ## Example

      config =
        TestcontainerEx.Container.new("postgres:15-alpine")
        |> TestcontainerEx.Container.with_log_consumer(:debug)

      {:ok, container} = TestcontainerEx.start_container(config)
  """

  require Logger

  @doc """
  Starts a linked task that streams container logs to Logger.

  ## Parameters

    * `container_id` — the Docker container ID
    * `conn` — the Req connection to the Docker API
    * `level` — Logger level (`:debug`, `:info`, `:warning`, `:error`), default `:debug`
  """
  @spec start_link(String.t(), Req.Request.t(), Logger.level()) :: {:ok, pid()}
  def start_link(container_id, conn, level \\ :debug) do
    Task.start_link(fn -> stream(container_id, conn, level) end)
  end

  defp stream(id, conn, level) do
    alias TestcontainerEx.Engine.Api

    case Api.logs(id, conn, follow: true, stdout: true, stderr: true) do
      {:ok, %{stdout: stdout, stderr: stderr}} ->
        for line <- String.split(stdout <> stderr, "\n", trim: true) do
          Logger.log(level, line, testcontainer_ex: true, container_id: id)
        end

      {:error, reason} ->
        Logger.warning("LogConsumer failed to stream logs for #{id}: #{inspect(reason)}")
    end
  end
end
