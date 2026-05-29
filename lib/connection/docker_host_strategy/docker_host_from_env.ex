# SPDX-License-Identifier: MIT
defmodule TestcontainerEx.DockerHostFromEnvStrategy do
  @moduledoc false

  defstruct key: "DOCKER_HOST"

  alias TestcontainerEx.DockerUrl

  defimpl TestcontainerEx.DockerHostStrategy do
    def execute(strategy, _input) do
      with {:ok, docker_host} <- get_docker_host(strategy) do
        case docker_host |> DockerUrl.test_docker_host() do
          :ok ->
            {:ok, docker_host}

          {:error, reason} ->
            {:error,
             docker_host_from_env:
               {:ping_failed, key: strategy.key, value: docker_host, reason: reason}}
        end
      end
    end

    defp get_docker_host(strategy) do
      case System.get_env(strategy.key) do
        nil ->
          {:error, docker_host_from_env: {:docker_host_not_found, strategy.key}}

        "" ->
          {:error, docker_host_from_env: {:docker_host_empty, strategy.key}}

        docker_host when is_binary(docker_host) ->
          {:ok, docker_host}
      end
    end
  end
end

# SPDX-License-Identifier: MIT
defmodule TestcontainerEx.ContainerHostFromEnvStrategy do
  @moduledoc """
  Strategy that reads the `CONTAINER_HOST` environment variable.

  Podman uses `CONTAINER_HOST` as the equivalent of Docker's `DOCKER_HOST`.
  When set, it points to the Podman service socket, e.g.
  `unix:///run/user/1000/podman/podman.sock`.
  """

  defstruct key: "CONTAINER_HOST"

  alias TestcontainerEx.DockerUrl

  defimpl TestcontainerEx.DockerHostStrategy do
    def execute(strategy, _input) do
      with {:ok, container_host} <- get_container_host(strategy) do
        case container_host |> DockerUrl.test_docker_host() do
          :ok ->
            {:ok, container_host}

          {:error, reason} ->
            {:error,
             container_host_from_env:
               {:ping_failed, key: strategy.key, value: container_host, reason: reason}}
        end
      end
    end

    defp get_container_host(strategy) do
      case System.get_env(strategy.key) do
        nil ->
          {:error, container_host_from_env: {:container_host_not_found, strategy.key}}

        "" ->
          {:error, container_host_from_env: {:container_host_empty, strategy.key}}

        container_host when is_binary(container_host) ->
          {:ok, container_host}
      end
    end
  end
end
