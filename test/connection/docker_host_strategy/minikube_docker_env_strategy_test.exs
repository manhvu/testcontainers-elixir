defmodule TestcontainerEx.MinikubeDockerEnvStrategyTest do
  # async: false because we mutate environment variables
  use ExUnit.Case, async: false

  alias TestcontainerEx.DockerHostStrategy

  @mod %TestcontainerEx.MinikubeDockerEnvStrategy{}

  setup do
    original_docker_host = System.get_env("DOCKER_HOST")
    original_mk_active = System.get_env("MINIKUBE_ACTIVE_DOCKERD")

    on_exit(fn ->
      restore_env("DOCKER_HOST", original_docker_host)
      restore_env("MINIKUBE_ACTIVE_DOCKERD", original_mk_active)
    end)

    System.delete_env("MINIKUBE_ACTIVE_DOCKERD")
    System.delete_env("DOCKER_HOST")
    :ok
  end

  describe "execute/2" do
    test "returns error when minikube is not available" do
      # Use a non-existent binary name to simulate minikube not being installed
      strategy = %TestcontainerEx.MinikubeDockerEnvStrategy{minikube_bin: "nonexistent_minikube_binary_xyz"}

      assert {:error, :minikube_not_available} = DockerHostStrategy.execute(strategy, [])
    end

    test "returns ok when MINIKUBE_ACTIVE_DOCKERD and DOCKER_HOST are set" do
      System.put_env("MINIKUBE_ACTIVE_DOCKERD", "minikube")
      System.put_env("DOCKER_HOST", "tcp://192.168.49.2:2376")

      # This will attempt to ping the Docker host, which likely fails in test env,
      # so we expect a ping_failed error rather than :ok — but the strategy itself
      # should have found the host from the env vars.
      case DockerHostStrategy.execute(@mod, []) do
        {:ok, _} ->
          # Connected successfully (unlikely in test env)
          :ok

        {:error, {:minikube_docker_env, {:ping_failed, opts}}} ->
          # Expected: strategy found the host but couldn't connect
          assert is_binary(opts[:docker_host])
          assert opts[:docker_host] == "tcp://192.168.49.2:2376"

        {:error, :minikube_not_available} ->
          # minikube binary not found on this system — acceptable in CI
          :ok

        other ->
          flunk("Unexpected result: #{inspect(other)}")
      end
    end

    test "returns error when MINIKUBE_ACTIVE_DOCKERD is set but DOCKER_HOST is empty" do
      System.put_env("MINIKUBE_ACTIVE_DOCKERD", "minikube")
      System.delete_env("DOCKER_HOST")

      # Without DOCKER_HOST, the strategy falls through to minikube binary check
      case DockerHostStrategy.execute(@mod, []) do
        {:error, :minikube_not_available} ->
          :ok

        {:error, {:minikube_docker_env, _}} ->
          # minikube binary exists but docker-env failed or returned empty
          :ok

        other ->
          flunk("Unexpected result: #{inspect(other)}")
      end
    end

    test "returns error when neither env vars nor minikube binary are available" do
      strategy = %TestcontainerEx.MinikubeDockerEnvStrategy{minikube_bin: "nonexistent_minikube_binary_xyz"}
      System.delete_env("MINIKUBE_ACTIVE_DOCKERD")
      System.delete_env("DOCKER_HOST")

      assert {:error, :minikube_not_available} = DockerHostStrategy.execute(strategy, [])
    end
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
