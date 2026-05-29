# SPDX-License-Identifier: MIT
defmodule TestcontainerEx.DockerSocketPathStrategy do
  @moduledoc false

  require Logger

  defstruct socket_paths: []

  defimpl TestcontainerEx.DockerHostStrategy do
    alias TestcontainerEx.DockerUrl

    defp default_socket_paths do
      [
        "/var/run/docker.sock",
        Path.expand("~/.docker/run/docker.sock"),
        Path.expand("~/.docker/desktop/docker.sock")
      ] ++
        minikube_socket_paths() ++
        case System.get_env("XDG_RUNTIME_DIR") do
          nil ->
            []

          path ->
            [
              "#{path}/podman/podman.sock",
              "#{path}/containers/podman.sock",
              "#{path}/docker.sock"
            ]
        end
    end

    # minikube with the none driver uses the host's Docker socket directly.
    # With the docker driver, the socket is inside the VM and accessed via TCP,
    # but when running inside a minikube pod, the in-pod socket path may be
    # mounted at the standard location or at a custom path.
    defp minikube_socket_paths do
      [
        # minikube none-driver: standard host socket (already listed above)
        # minikube docker-driver: socket inside the VM
        "/var/run/minikube/docker.sock",
        # minikube pod mount (when Docker socket is mounted into a pod)
        "/var/run/minikube.sock"
      ]
      |> Enum.filter(&File.exists?/1)
    end

    def execute(strategy, _input) do
      paths =
        case strategy.socket_paths do
          [] -> default_socket_paths()
          paths -> paths
        end

      Enum.reduce_while(paths, {:error, {:docker_socket_not_found, []}}, &try_socket_path/2)
    end

    defp try_socket_path(path, {:error, {:docker_socket_not_found, tried_paths}}) do
      if path != nil && File.exists?(path) do
        probe_socket(path, tried_paths)
      else
        {:cont, {:error, {:docker_socket_not_found, tried_paths ++ [path]}}}
      end
    end

    defp probe_socket(path, tried_paths) do
      path_with_scheme = "unix://" <> path

      case DockerUrl.test_docker_host(path_with_scheme) do
        :ok ->
          {:halt, {:ok, path_with_scheme}}

        {:error, reason} ->
          Logger.debug("Docker socket path #{path} failed: #{reason}")
          {:cont, {:error, {:docker_socket_not_found, tried_paths ++ [path]}}}
      end
    end
  end
end
