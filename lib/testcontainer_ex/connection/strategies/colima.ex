defmodule TestcontainerEx.Connection.Strategies.Colima do
  @moduledoc """
  Resolves the container engine host by querying `colima status`.

  When Colima is installed and running, this strategy parses the socket
  path from the `colima status` output (e.g. `docker socket: unix:///...`).
  This is more reliable than guessing the socket path because Colima may
  use a named profile or a non-default location.

  Only activates on macOS and Linux when the `colima` binary is available.
  """

  @behaviour TestcontainerEx.Connection.Strategies.Behaviour

  require Logger

  @impl true
  def resolve do
    with {:ok, output} <- colima_status(),
         {:ok, socket_path} <- parse_socket(output) do
      url = "unix://#{socket_path}"

      if socket_accessible?(socket_path) do
        Logger.info("Docker host detected via colima status: #{url}")
        {:ok, url}
      else
        Logger.warning("Colima socket not found at #{socket_path}")
        {:error, :colima_socket_not_found}
      end
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  # Run `colima status` and capture output.
  defp colima_status do
    case System.find_executable("colima") do
      nil ->
        {:error, :colima_not_installed}

      bin ->
        case System.cmd(bin, ["status"], stderr_to_stdout: true) do
          {output, 0} ->
            {:ok, output}

          {output, _} ->
            Logger.debug("colima status exited non-zero: #{String.trim(output)}")
            {:error, :colima_not_running}
        end
    end
  end

  # Check if a path is a readable Unix socket.
  # Uses file mode bits (not File.stat type field) because some
  # filesystems (e.g. virtiofs on macOS) report sockets as :other.
  # The Unix socket type is indicated by mode bits 0o140000.
  defp socket_accessible?(path) do
    case File.stat(path) do
      {:ok, stat} -> :erlang.band(stat.mode, 0o170000) == 0o140000
      _ -> false
    end
  end

  # Parse the Docker socket path from `colima status` output.
  # Matches lines like:
  #   "docker socket: unix:///Users/.../.colima/default/docker.sock"
  #   "Docker socket: unix:///Users/.../.colima/default/docker.sock"
  #   "/Users/.../.colima/default/docker.sock"
  defp parse_socket(output) do
    output
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.find_value(fn
      line when is_binary(line) ->
        regex = ~r/^[Dd]ocker\s+socket:\s*(.+)$/

        case Regex.run(regex, line) do
          [_, path] ->
            path =
              path
              |> String.trim()
              |> String.replace_prefix("unix://", "")

            {:ok, path}

          _ ->
            nil
        end
    end)
    |> case do
      nil -> {:error, :colima_socket_not_found}
      result -> result
    end
  end
end
