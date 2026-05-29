# SPDX-License-Identifier: MIT
defmodule TestcontainerEx.MinikubeDockerEnvStrategy do
  @moduledoc """
  Strategy that detects a minikube Docker environment by evaluating
  `minikube docker-env` and extracting the `DOCKER_HOST` value.

  This is useful when:
  - minikube is running but `DOCKER_HOST` is not yet set in the environment
  - Running inside a minikube pod where the Docker daemon is accessible via
    the minikube VM's IP

  The strategy checks for the `MINIKUBE_ACTIVE_DOCKERD` or `MINIKUBE_PROFILE`
  environment variables, or for the presence of the `minikube` binary.
  """

  require Logger

  alias TestcontainerEx.DockerUrl

  defstruct minikube_bin: "minikube"

  defimpl TestcontainerEx.DockerHostStrategy do
    def execute(strategy, _input) do
      with {:ok, docker_host} <- get_minikube_docker_host(strategy) do
        case DockerUrl.test_docker_host(docker_host) do
          :ok ->
            Logger.info("Connected to Docker via minikube: #{docker_host}")
            {:ok, docker_host}

          {:error, reason} ->
            {:error,
             minikube_docker_env:
               {:ping_failed, docker_host: docker_host, reason: reason}}
        end
      end
    end

    defp get_minikube_docker_host(strategy) do
      cond do
        # Already have DOCKER_HOST set by minikube docker-env
        System.get_env("MINIKUBE_ACTIVE_DOCKERD") && System.get_env("DOCKER_HOST") ->
          {:ok, System.get_env("DOCKER_HOST")}

        # minikube is available, try to eval docker-env
        minikube_available?(strategy.minikube_bin) ->
          eval_minikube_docker_env(strategy.minikube_bin)

        true ->
          {:error, :minikube_not_available}
      end
    end

    defp minikube_available?(bin) do
      case System.cmd("which", [bin], stderr_to_stdout: true) do
        {_, 0} -> true
        _ -> false
      end
    rescue
      ErlangError -> false
    end

    defp eval_minikube_docker_env(bin) do
      # `minikube docker-env --shell none` outputs key=value pairs
      case System.cmd(bin, ["docker-env", "--shell", "none"], stderr_to_stdout: true) do
        {output, 0} ->
          output
          |> String.split("\n")
          |> Enum.map(&String.trim/1)
          |> Enum.find_value({:error, :no_docker_host_in_output}, fn
            "DOCKER_HOST=" <> rest ->
              host = String.trim(rest) |> String.trim("\"")

              if host != "" do
                {:ok, host}
              else
                nil
              end

            _ ->
              nil
          end)

        {_output, _exit_code} ->
          {:error, :minikube_docker_env_failed}
      end
    end
  end
end
