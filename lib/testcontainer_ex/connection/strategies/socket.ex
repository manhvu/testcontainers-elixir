defmodule TestcontainerEx.Connection.Strategies.Socket do
  @moduledoc """
  Resolves the container engine host by scanning well-known Unix socket paths.

  Checks standard Docker, Podman, and minikube socket locations.
  Only paths that actually exist are probed.
  """

  @behaviour TestcontainerEx.Connection.Strategies.Behaviour

  @default_paths [
    "/var/run/docker.sock",
    "~/.docker/run/docker.sock",
    "~/.docker/desktop/docker.sock",
    "~/.colima/default/docker.sock"
  ]

  @impl true
  def resolve do
    paths =
      @default_paths ++
        xdg_socket_paths() ++
        minikube_socket_paths() ++
        docker_context_socket_paths()

    paths
    |> Enum.map(&Path.expand/1)
    |> Enum.filter(&socket_accessible?/1)
    |> case do
      [] ->
        {:error, :no_socket_found}

      existing ->
        try_sockets(existing)
    end
  end

  defp try_sockets([]), do: {:error, :all_sockets_failed}

  defp try_sockets([path | rest]) do
    url = "unix://#{path}"

    if socket_accessible?(path) do
      require Logger
      Logger.info("Docker host detected via socket: #{url}")
      {:ok, url}
    else
      try_sockets(rest)
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

  defp xdg_socket_paths do
    case System.get_env("XDG_RUNTIME_DIR") do
      nil ->
        []

      path ->
        ["#{path}/podman/podman.sock", "#{path}/containers/podman.sock", "#{path}/docker.sock"]
    end
  end

  defp minikube_socket_paths do
    ["/var/run/minikube/docker.sock", "/var/run/minikube.sock"]
  end

  # Extract Docker socket path from `docker context inspect` output.
  # This is the most reliable way to find the socket on modern Docker
  # setups (Docker Desktop, Colima, etc.).
  defp docker_context_socket_paths do
    case System.find_executable("docker") do
      nil ->
        []

      bin ->
        # Try to get the socket path from the active Docker context.
        # We enumerate all contexts and check each one for a docker endpoint.
        case System.cmd(bin, ["context", "ls", "--format", "{{.Name}}"], stderr_to_stdout: true) do
          {output, 0} ->
            output
            |> String.split("\n")
            |> Enum.map(&String.trim/1)
            |> Enum.reject(&(&1 == ""))
            |> Enum.flat_map(fn context ->
              case System.cmd(
                     bin,
                     [
                       "context",
                       "inspect",
                       context,
                       "--format",
                       "{{.Endpoints.docker.Host}}"
                     ],
                     stderr_to_stdout: true
                   ) do
                {"unix://" <> path, 0} -> [path]
                {path, 0} when is_binary(path) and path != "" -> [path]
                _ -> []
              end
            end)

          _ ->
            []
        end
    end
  end
end
