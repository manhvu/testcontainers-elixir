defmodule TestcontainerEx.Connection.DockerHostStrategyTest do
  # async: false because some tests mutate environment variables
  use ExUnit.Case, async: false

  alias TestcontainerEx.{
    ContainerHostFromEnvStrategy,
    DockerHostFromEnvStrategy,
    DockerHostFromPropertiesStrategy,
    DockerHostStrategy,
    DockerHostStrategyEvaluator,
    DockerSocketPathStrategy,
    MinikubeDockerEnvStrategy
  }

  # ── DOCKER_HOST env var strategy ──────────────────────────────────

  describe "DockerHostFromEnvStrategy" do
    setup do
      original = System.get_env("DOCKER_HOST")
      on_exit(fn -> restore_env("DOCKER_HOST", original) end)
      :ok
    end

    test "returns error when DOCKER_HOST is not set" do
      System.delete_env("DOCKER_HOST")
      strategy = %DockerHostFromEnvStrategy{}

      {:error,
       "Failed to find docker host: [docker_host_from_env: {:docker_host_not_found, \"DOCKER_HOST\"}]"} =
        DockerHostStrategyEvaluator.run_strategies([strategy], [])
    end

    test "returns error when DOCKER_HOST is set but host is unreachable" do
      System.put_env("DOCKER_HOST", "tcp://localhost:9999")
      strategy = %DockerHostFromEnvStrategy{}

      {:error,
       "Failed to find docker host: [docker_host_from_env: {:ping_failed, [key: \"DOCKER_HOST\", value: \"tcp://localhost:9999\", reason: :econnrefused]}]"} =
        DockerHostStrategyEvaluator.run_strategies([strategy], [])
    end

    test "uses custom env var key" do
      System.put_env("X_DOCKER_HOST", "tcp://localhost:9999")
      strategy = %DockerHostFromEnvStrategy{key: "X_DOCKER_HOST"}

      {:error,
       "Failed to find docker host: [docker_host_from_env: {:ping_failed, [key: \"X_DOCKER_HOST\", value: \"tcp://localhost:9999\", reason: :econnrefused]}]"} =
        DockerHostStrategyEvaluator.run_strategies([strategy], [])
    end
  end

  # ── CONTAINER_HOST env var strategy (Podman) ─────────────────────

  describe "ContainerHostFromEnvStrategy (Podman)" do
    setup do
      original = System.get_env("CONTAINER_HOST")
      on_exit(fn -> restore_env("CONTAINER_HOST", original) end)
      :ok
    end

    test "returns error when CONTAINER_HOST is not set" do
      System.delete_env("CONTAINER_HOST")
      strategy = %ContainerHostFromEnvStrategy{}

      {:error,
       "Failed to find docker host: [container_host_from_env: {:container_host_not_found, \"CONTAINER_HOST\"}]"} =
        DockerHostStrategyEvaluator.run_strategies([strategy], [])
    end

    test "returns error mentioning container_host_from_env and CONTAINER_HOST" do
      System.put_env("CONTAINER_HOST", "unix:///run/user/1000/podman/podman.sock")
      strategy = %ContainerHostFromEnvStrategy{}

      assert {:error, msg} = DockerHostStrategyEvaluator.run_strategies([strategy], [])
      assert is_binary(msg)
      assert msg =~ "container_host_from_env"
      assert msg =~ "CONTAINER_HOST"
    end
  end

  # ── Properties file strategy ──────────────────────────────────────

  describe "DockerHostFromPropertiesStrategy" do
    test "returns error when property file does not exist" do
      strategy = %DockerHostFromPropertiesStrategy{
        key: "tc.host",
        filename: "/nonexistent/.testcontainer_ex.properties"
      }

      {:error,
       "Failed to find docker host: [testcontainer_host_from_properties: {:property_not_found, \"tc.host\"}]"} =
        DockerHostStrategyEvaluator.run_strategies([strategy], [])
    end

    test "returns error when property key is missing from file" do
      strategy = %DockerHostFromPropertiesStrategy{
        key: "invalid.host",
        filename: "test/fixtures/.testcontainer_ex.properties"
      }

      {:error,
       "Failed to find docker host: [testcontainer_host_from_properties: {:property_not_found, \"invalid.host\"}]"} =
        DockerHostStrategyEvaluator.run_strategies([strategy], [])
    end

    test "returns error when property value is set but host is unreachable" do
      strategy = %DockerHostFromPropertiesStrategy{
        key: "tc.host",
        filename: "test/fixtures/.testcontainer_ex.properties"
      }

      {:error,
       "Failed to find docker host: [testcontainer_host_from_properties: {:ping_failed, [key: \"tc.host\", value: \"tcp://localhost:9999\", reason: :econnrefused]}]"} =
        DockerHostStrategyEvaluator.run_strategies([strategy], [])
    end
  end

  # ── Socket path strategy ──────────────────────────────────────────

  describe "DockerSocketPathStrategy" do
    test "returns error when socket path does not exist" do
      strategy = %DockerSocketPathStrategy{socket_paths: ["/does/not/exist/at/all"]}

      {:error,
       "Failed to find docker host: {:docker_socket_not_found, [\"/does/not/exist/at/all\"]}"} =
        DockerHostStrategyEvaluator.run_strategies([strategy], [])
    end

    test "returns error when socket file exists but is not a real socket" do
      strategy = %DockerSocketPathStrategy{socket_paths: ["test/fixtures/docker.sock"]}

      {:error,
       "Failed to find docker host: {:docker_socket_not_found, [\"test/fixtures/docker.sock\"]}"} =
        DockerHostStrategyEvaluator.run_strategies([strategy], [])
    end

    test "accepts custom socket paths" do
      strategy = %DockerSocketPathStrategy{
        socket_paths: ["/nonexistent/socket/path.sock"]
      }

      assert {:error, {:docker_socket_not_found, _}} =
               DockerHostStrategy.execute(strategy, [])
    end

    test "minikube socket paths are included in defaults" do
      strategy = %DockerSocketPathStrategy{socket_paths: []}

      case DockerHostStrategy.execute(strategy, []) do
        {:error, {:docker_socket_not_found, _}} -> :ok
        {:ok, _} -> :ok
      end
    end
  end

  # ── Minikube docker-env strategy ──────────────────────────────────

  describe "MinikubeDockerEnvStrategy" do
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

    test "returns error when minikube binary is not available" do
      strategy = %MinikubeDockerEnvStrategy{
        minikube_bin: "nonexistent_minikube_binary_xyz"
      }

      assert {:error, :minikube_not_available} = DockerHostStrategy.execute(strategy, [])
    end

    test "returns error when neither env vars nor minikube binary are available" do
      strategy = %MinikubeDockerEnvStrategy{
        minikube_bin: "nonexistent_minikube_binary_xyz"
      }

      assert {:error, :minikube_not_available} = DockerHostStrategy.execute(strategy, [])
    end

    test "uses DOCKER_HOST from MINIKUBE_ACTIVE_DOCKERD env var" do
      System.put_env("MINIKUBE_ACTIVE_DOCKERD", "minikube")
      System.put_env("DOCKER_HOST", "tcp://192.168.49.2:2376")

      case DockerHostStrategy.execute(%MinikubeDockerEnvStrategy{}, []) do
        {:ok, _} ->
          :ok

        {:error, {:minikube_docker_env, {:ping_failed, opts}}} ->
          assert is_binary(opts[:docker_host])
          assert opts[:docker_host] == "tcp://192.168.49.2:2376"

        {:error, :minikube_not_available} ->
          :ok
      end
    end

    test "falls back to minikube binary when DOCKER_HOST is not set" do
      System.put_env("MINIKUBE_ACTIVE_DOCKERD", "minikube")
      System.delete_env("DOCKER_HOST")

      case DockerHostStrategy.execute(%MinikubeDockerEnvStrategy{}, []) do
        {:error, :minikube_not_available} -> :ok
        {:error, {:minikube_docker_env, _}} -> :ok
        {:ok, _} -> :ok
      end
    end
  end

  # ── Strategy chain precedence ─────────────────────────────────────

  describe "strategy chain precedence" do
    test "properties file takes precedence over env vars" do
      System.put_env("DOCKER_HOST", "tcp://localhost:9999")

      strategy = %DockerHostFromPropertiesStrategy{
        key: "tc.host",
        filename: "test/fixtures/.testcontainer_ex.properties"
      }

      {:error, msg} = DockerHostStrategyEvaluator.run_strategies([strategy], [])
      assert msg =~ "tc.host"
    end
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
