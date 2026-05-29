defmodule TestcontainerEx.Util.ContainerEngineTest do
  # async: false because we mutate environment variables and persistent_term
  use ExUnit.Case, async: false

  alias TestcontainerEx.Constants

  setup do
    # Clear the cached engine detection so each test starts fresh
    :persistent_term.erase({Constants, :container_engine})

    on_exit(fn ->
      :persistent_term.erase({Constants, :container_engine})
    end)

    :ok
  end

  describe "container_engine/0" do
    test "returns :docker by default when no special env vars are set" do
      System.delete_env("CONTAINER_HOST")
      System.delete_env("MINIKUBE_ACTIVE_DOCKERD")
      System.delete_env("MINIKUBE_PROFILE")
      System.delete_env("DOCKER_HOST")

      assert Constants.container_engine() == :docker
    end

    test "returns :podman when CONTAINER_HOST is set" do
      System.put_env("CONTAINER_HOST", "unix:///run/user/1000/podman/podman.sock")
      System.delete_env("MINIKUBE_ACTIVE_DOCKERD")
      System.delete_env("MINIKUBE_PROFILE")

      assert Constants.container_engine() == :podman
    end

    test "CONTAINER_HOST takes precedence over minikube detection" do
      System.put_env("CONTAINER_HOST", "unix:///run/user/1000/podman/podman.sock")
      System.put_env("MINIKUBE_ACTIVE_DOCKERD", "minikube")

      assert Constants.container_engine() == :podman
    end

    test "caches the result after first call" do
      System.delete_env("CONTAINER_HOST")
      System.delete_env("MINIKUBE_ACTIVE_DOCKERD")
      System.delete_env("MINIKUBE_PROFILE")

      first = Constants.container_engine()
      # Even if we change env vars, the cached value is returned
      System.put_env("CONTAINER_HOST", "unix:///tmp/podman.sock")
      second = Constants.container_engine()

      assert first == second
    end
  end

  describe "minikube_env?/0" do
    setup do
      original_docker_host = System.get_env("DOCKER_HOST")
      original_mk_active = System.get_env("MINIKUBE_ACTIVE_DOCKERD")
      original_mk_profile = System.get_env("MINIKUBE_PROFILE")

      on_exit(fn ->
        restore_env("DOCKER_HOST", original_docker_host)
        restore_env("MINIKUBE_ACTIVE_DOCKERD", original_mk_active)
        restore_env("MINIKUBE_PROFILE", original_mk_profile)
      end)

      System.delete_env("MINIKUBE_ACTIVE_DOCKERD")
      System.delete_env("MINIKUBE_PROFILE")
      System.delete_env("DOCKER_HOST")
      :ok
    end

    test "returns true when MINIKUBE_ACTIVE_DOCKERD is set" do
      System.put_env("MINIKUBE_ACTIVE_DOCKERD", "minikube")
      assert Constants.minikube_env?()
    end

    test "returns true when MINIKUBE_PROFILE is set" do
      System.put_env("MINIKUBE_PROFILE", "minikube")
      assert Constants.minikube_env?()
    end

    test "returns true when DOCKER_HOST is in minikube subnet 192.168.49.0/24" do
      System.put_env("DOCKER_HOST", "tcp://192.168.49.2:2376")
      assert Constants.minikube_env?()
    end

    test "returns true when DOCKER_HOST is in minikube subnet 192.168.59.0/24" do
      System.put_env("DOCKER_HOST", "tcp://192.168.59.1:2376")
      assert Constants.minikube_env?()
    end

    test "returns true when DOCKER_HOST is in minikube subnet 192.168.69.0/24" do
      System.put_env("DOCKER_HOST", "tcp://192.168.69.1:2376")
      assert Constants.minikube_env?()
    end

    test "returns true when DOCKER_HOST ends with .minikube" do
      System.put_env("DOCKER_HOST", "tcp://myhost.minikube:2376")
      assert Constants.minikube_env?()
    end

    test "returns false when DOCKER_HOST is a non-minikube address" do
      System.put_env("DOCKER_HOST", "tcp://10.0.1.5:2376")
      refute Constants.minikube_env?()
    end

    test "returns false when DOCKER_HOST is a local address" do
      System.put_env("DOCKER_HOST", "tcp://127.0.0.1:2375")
      refute Constants.minikube_env?()
    end

    test "returns false when DOCKER_HOST is a unix socket" do
      System.put_env("DOCKER_HOST", "unix:///var/run/docker.sock")
      refute Constants.minikube_env?()
    end

    test "returns false when no env vars are set" do
      refute Constants.minikube_env?()
    end

    test "returns false when DOCKER_HOST is nil" do
      System.delete_env("DOCKER_HOST")
      refute Constants.minikube_env?()
    end
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
