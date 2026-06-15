defmodule TestcontainerEx.DockerHostDetectionTest do
  use ExUnit.Case, async: false

  # ── Gateway parsing from /proc/net/route ──────────────────────────

  describe "parse_gateway_from_proc_route/1" do
    test "parses hex-encoded gateway from /proc/net/route content" do
      content = """
      Iface\tDestination\tGateway\tFlags\tRefCnt\tUse\tMetric\tMask\tMTU\tWindow\tIRTT
      eth0\t00000000\t0102A8C0\t0003\t0\t0\t0\t00000000\t0\t0\t0
      eth0\t0002A8C0\t00000000\t0001\t0\t0\t0\t00FFFFFF\t0\t0\t0
      """

      assert {:ok, "192.168.2.1"} = TestcontainerEx.parse_gateway_from_proc_route(content)
    end

    test "parses another gateway address" do
      content = """
      Iface\tDestination\tGateway\tFlags\tRefCnt\tUse\tMetric\tMask\tMTU\tWindow\tIRTT
      eth0\t00000000\t0100000A\t0003\t0\t0\t0\t00000000\t0\t0\t0
      """

      assert {:ok, "10.0.0.1"} = TestcontainerEx.parse_gateway_from_proc_route(content)
    end

    test "returns error when no default route exists" do
      content = """
      Iface\tDestination\tGateway\tFlags\tRefCnt\tUse\tMetric\tMask\tMTU\tWindow\tIRTT
      eth0\t0002A8C0\t00000000\t0001\t0\t0\t0\t00FFFFFF\t0\t0\t0
      """

      assert {:error, :no_default_route} = TestcontainerEx.parse_gateway_from_proc_route(content)
    end

    test "returns error for empty content" do
      assert {:error, :no_default_route} = TestcontainerEx.parse_gateway_from_proc_route("")
    end
  end

  # ── Container environment detection ───────────────────────────────

  describe "running_in_container?/2 — file-based detection" do
    test "returns true when .dockerenv file exists" do
      tmp = tmp_path("dockerenv")
      File.write!(tmp, "")

      try do
        assert TestcontainerEx.running_in_container?(tmp, "/nonexistent/cgroup")
      after
        File.rm(tmp)
      end
    end

    test "returns true when /var/run/secrets/kubernetes.io exists (minikube/k8s pod)" do
      tmp = tmp_path("k8s_secrets")
      File.mkdir_p!(tmp)

      try do
        assert TestcontainerEx.running_in_container?(
                 "/nonexistent/dockerenv",
                 "/nonexistent/cgroup",
                 tmp,
                 "/nonexistent/containerenv"
               )
      after
        File.rm_rf(tmp)
      end
    end

    test "returns true when .containerenv exists (Podman)" do
      tmp = tmp_path("containerenv")
      File.write!(tmp, "")

      try do
        assert TestcontainerEx.running_in_container?(
                 "/nonexistent/dockerenv",
                 "/nonexistent/cgroup",
                 "/nonexistent/k8s",
                 tmp
               )
      after
        File.rm(tmp)
      end
    end

    test "dockerenv takes precedence over other checks" do
      dockerenv = tmp_path("dockerenv_precedence")
      File.write!(dockerenv, "")

      cgroup = tmp_path("cgroup_precedence")
      File.write!(cgroup, "12:memory:/user.slice/user-1000.slice")

      try do
        assert TestcontainerEx.running_in_container?(dockerenv, cgroup)
      after
        File.rm(dockerenv)
        File.rm(cgroup)
      end
    end
  end

  describe "running_in_container?/2 — cgroup pattern detection" do
    test "returns true when cgroup contains docker pattern" do
      tmp = tmp_path("cgroup_docker")

      File.write!(tmp, """
      12:memory:/docker/abc123def456
      11:cpu:/docker/abc123def456
      """)

      try do
        assert TestcontainerEx.running_in_container?("/nonexistent/dockerenv", tmp)
      after
        File.rm(tmp)
      end
    end

    test "returns true when cgroup contains kubepods pattern (minikube/k8s)" do
      tmp = tmp_path("cgroup_kube")

      File.write!(tmp, """
      12:memory:/kubepods/besteffort/pod123
      """)

      try do
        assert TestcontainerEx.running_in_container?("/nonexistent/dockerenv", tmp)
      after
        File.rm(tmp)
      end
    end

    test "returns true when cgroup contains podman pattern" do
      tmp = tmp_path("cgroup_podman")

      File.write!(tmp, """
      12:memory:/podman/container-abc123
      11:cpu:/podman/container-abc123
      """)

      try do
        assert TestcontainerEx.running_in_container?("/nonexistent/dockerenv", tmp)
      after
        File.rm(tmp)
      end
    end

    test "returns true when cgroup contains lxc pattern" do
      tmp = tmp_path("cgroup_lxc")

      File.write!(tmp, """
      12:memory:/lxc/container-name
      """)

      try do
        assert TestcontainerEx.running_in_container?("/nonexistent/dockerenv", tmp)
      after
        File.rm(tmp)
      end
    end

    test "returns true when cgroup contains containerd pattern" do
      tmp = tmp_path("cgroup_containerd")

      File.write!(tmp, """
      12:memory:/system.slice/containerd.service
      """)

      try do
        assert TestcontainerEx.running_in_container?("/nonexistent/dockerenv", tmp)
      after
        File.rm(tmp)
      end
    end

    test "returns false when neither dockerenv nor cgroup exist" do
      refute TestcontainerEx.running_in_container?(
               "/nonexistent/dockerenv",
               "/nonexistent/cgroup"
             )
    end

    test "returns false when cgroup exists but has no container patterns" do
      tmp = tmp_path("cgroup_empty")

      File.write!(tmp, """
      12:memory:/user.slice/user-1000.slice
      11:cpu:/user.slice/user-1000.slice
      """)

      try do
        refute TestcontainerEx.running_in_container?("/nonexistent/dockerenv", tmp)
      after
        File.rm(tmp)
      end
    end
  end

  # ── Container engine detection ────────────────────────────────────

  describe "container_engine/0" do
    setup do
      :persistent_term.erase({TestcontainerEx.Engine, :cached_engine})
      on_exit(fn -> :persistent_term.erase({TestcontainerEx.Engine, :cached_engine}) end)
      :ok
    end

    test "returns :docker by default" do
      System.delete_env("CONTAINER_HOST")
      System.delete_env("MINIKUBE_ACTIVE_DOCKERD")
      System.delete_env("MINIKUBE_PROFILE")
      System.delete_env("DOCKER_HOST")

      assert TestcontainerEx.Constants.container_engine() == :docker
    end

    test "returns :podman when CONTAINER_HOST is set" do
      System.put_env("CONTAINER_HOST", "unix:///run/user/1000/podman/podman.sock")
      System.delete_env("MINIKUBE_ACTIVE_DOCKERD")
      System.delete_env("MINIKUBE_PROFILE")

      assert TestcontainerEx.Constants.container_engine() == :podman
    end

    test "CONTAINER_HOST takes precedence over minikube detection" do
      System.put_env("CONTAINER_HOST", "unix:///run/user/1000/podman/podman.sock")
      System.put_env("MINIKUBE_ACTIVE_DOCKERD", "minikube")

      assert TestcontainerEx.Constants.container_engine() == :podman
    end

    test "caches the result" do
      System.delete_env("CONTAINER_HOST")
      System.delete_env("MINIKUBE_ACTIVE_DOCKERD")
      System.delete_env("MINIKUBE_PROFILE")

      first = TestcontainerEx.Constants.container_engine()
      System.put_env("CONTAINER_HOST", "unix:///tmp/podman.sock")
      second = TestcontainerEx.Constants.container_engine()

      assert first == second
    end
  end

  # ── Runtime engine override ──────────────────────────────────────

  describe "set_engine/1 and clear_engine/0" do
    setup do
      TestcontainerEx.Engine.clear_engine()
      on_exit(fn -> TestcontainerEx.Engine.clear_engine() end)
      :ok
    end

    test "set_engine/1 overrides auto-detection" do
      TestcontainerEx.Engine.set_engine(:podman)
      assert TestcontainerEx.Engine.detect() == :podman
    end

    test "set_engine/1 works for all supported engines" do
      for eng <- [:docker, :podman, :colima, :minikube, :apple_container] do
        TestcontainerEx.Engine.set_engine(eng)
        assert TestcontainerEx.Engine.detect() == eng
      end
    end

    test "set_engine/1 returns :ok" do
      assert TestcontainerEx.Engine.set_engine(:docker) == :ok
    end

    test "clear_engine/0 removes the override" do
      TestcontainerEx.Engine.set_engine(:podman)
      assert TestcontainerEx.Engine.detect() == :podman

      TestcontainerEx.Engine.clear_engine()
      assert TestcontainerEx.Engine.runtime_override() == nil

      System.delete_env("CONTAINER_HOST")
      System.delete_env("MINIKUBE_ACTIVE_DOCKERD")
      System.delete_env("MINIKUBE_PROFILE")
      assert TestcontainerEx.Engine.detect() == :docker
    end

    test "runtime_override/0 returns nil when no override is set" do
      TestcontainerEx.Engine.clear_engine()
      assert TestcontainerEx.Engine.runtime_override() == nil
    end

    test "runtime_override/0 returns the set engine" do
      TestcontainerEx.Engine.set_engine(:apple_container)
      assert TestcontainerEx.Engine.runtime_override() == :apple_container
    end

    test "override is per-process" do
      TestcontainerEx.Engine.set_engine(:podman)
      assert TestcontainerEx.Engine.detect() == :podman

      result =
        Task.async(fn ->
          TestcontainerEx.Engine.runtime_override()
        end)
        |> Task.await()

      assert result == nil
    end

    test "override takes precedence over CONTAINER_ENGINE env var" do
      System.put_env("CONTAINER_ENGINE", "podman")
      TestcontainerEx.Engine.set_engine(:docker)
      assert TestcontainerEx.Engine.detect() == :docker
    after
      System.delete_env("CONTAINER_ENGINE")
    end
  end

  # ── CONTAINER_ENGINE env var detection ────────────────────────────

  describe "engine_from_env via CONTAINER_ENGINE env var" do
    setup do
      original = System.get_env("CONTAINER_ENGINE")
      :persistent_term.erase({TestcontainerEx.Engine, :cached_engine})

      on_exit(fn ->
        case original do
          nil -> System.delete_env("CONTAINER_ENGINE")
          val -> System.put_env("CONTAINER_ENGINE", val)
        end

        :persistent_term.erase({TestcontainerEx.Engine, :cached_engine})
      end)

      System.delete_env("CONTAINER_ENGINE")
      :ok
    end

    test "nil CONTAINER_ENGINE falls back to auto-detection" do
      System.delete_env("CONTAINER_HOST")
      System.delete_env("MINIKUBE_ACTIVE_DOCKERD")
      System.delete_env("MINIKUBE_PROFILE")

      assert TestcontainerEx.Constants.container_engine() == :docker
    end

    test "empty string CONTAINER_ENGINE falls back to auto-detection" do
      System.put_env("CONTAINER_ENGINE", "")
      System.delete_env("CONTAINER_HOST")
      System.delete_env("MINIKUBE_ACTIVE_DOCKERD")
      System.delete_env("MINIKUBE_PROFILE")

      assert TestcontainerEx.Constants.container_engine() == :docker
    end

    test "CONTAINER_ENGINE=docker returns :docker" do
      System.put_env("CONTAINER_ENGINE", "docker")
      assert TestcontainerEx.Constants.container_engine() == :docker
    end

    test "CONTAINER_ENGINE=podman returns :podman" do
      System.put_env("CONTAINER_ENGINE", "podman")
      assert TestcontainerEx.Constants.container_engine() == :podman
    end

    test "CONTAINER_ENGINE=colima returns :docker (colima runs Docker)" do
      System.put_env("CONTAINER_ENGINE", "colima")
      assert TestcontainerEx.Constants.container_engine() == :docker
    end

    test "CONTAINER_ENGINE=minikube returns :minikube" do
      System.put_env("CONTAINER_ENGINE", "minikube")
      assert TestcontainerEx.Constants.container_engine() == :minikube
    end

    test "CONTAINER_ENGINE=apple_container returns :apple_container" do
      System.put_env("CONTAINER_ENGINE", "apple_container")
      assert TestcontainerEx.Constants.container_engine() == :apple_container
    end

    test "CONTAINER_ENGINE=auto falls back to auto-detection" do
      System.put_env("CONTAINER_ENGINE", "auto")
      System.delete_env("CONTAINER_HOST")
      System.delete_env("MINIKUBE_ACTIVE_DOCKERD")
      System.delete_env("MINIKUBE_PROFILE")

      assert TestcontainerEx.Constants.container_engine() == :docker
    end

    test "invalid CONTAINER_ENGINE value falls back to auto-detection" do
      System.put_env("CONTAINER_ENGINE", "not_a_real_engine")
      System.delete_env("CONTAINER_HOST")
      System.delete_env("MINIKUBE_ACTIVE_DOCKERD")
      System.delete_env("MINIKUBE_PROFILE")

      assert TestcontainerEx.Constants.container_engine() == :docker
    end

    test "CONTAINER_ENGINE is cached in persistent_term" do
      System.put_env("CONTAINER_ENGINE", "podman")
      first = TestcontainerEx.Constants.container_engine()
      assert first == :podman

      # Changing env var should not affect cached result
      System.put_env("CONTAINER_ENGINE", "docker")
      second = TestcontainerEx.Constants.container_engine()
      assert second == :podman
    end

    test "clear_engine clears the cache and re-reads env" do
      System.put_env("CONTAINER_ENGINE", "podman")
      assert TestcontainerEx.Constants.container_engine() == :podman

      TestcontainerEx.Engine.clear_engine()
      System.put_env("CONTAINER_ENGINE", "minikube")
      assert TestcontainerEx.Constants.container_engine() == :minikube
    end
  end

  # ── Combined override precedence ─────────────────────────────────

  describe "override precedence: set_engine > env var > auto-detect" do
    setup do
      TestcontainerEx.Engine.clear_engine()
      original_env = System.get_env("CONTAINER_ENGINE")

      on_exit(fn ->
        TestcontainerEx.Engine.clear_engine()

        case original_env do
          nil -> System.delete_env("CONTAINER_ENGINE")
          val -> System.put_env("CONTAINER_ENGINE", val)
        end
      end)

      System.delete_env("CONTAINER_ENGINE")
      System.delete_env("CONTAINER_HOST")
      System.delete_env("MINIKUBE_ACTIVE_DOCKERD")
      System.delete_env("MINIKUBE_PROFILE")
      :ok
    end

    test "set_engine wins over CONTAINER_ENGINE env var" do
      System.put_env("CONTAINER_ENGINE", "podman")
      TestcontainerEx.Engine.set_engine(:docker)
      assert TestcontainerEx.Engine.detect() == :docker
    end

    test "set_engine wins over auto-detection" do
      TestcontainerEx.Engine.set_engine(:apple_container)
      assert TestcontainerEx.Engine.detect() == :apple_container
    end

    test "CONTAINER_ENGINE env var wins over auto-detection" do
      System.put_env("CONTAINER_ENGINE", "minikube")
      assert TestcontainerEx.Engine.detect() == :minikube
    end

    test "clear_engine falls back to CONTAINER_ENGINE env var" do
      System.put_env("CONTAINER_ENGINE", "podman")
      TestcontainerEx.Engine.set_engine(:docker)
      assert TestcontainerEx.Engine.detect() == :docker

      TestcontainerEx.Engine.clear_engine()
      # After clearing, should re-read from env var
      assert TestcontainerEx.Engine.detect() == :podman
    end

    test "clear_engine with no env var falls back to auto-detection" do
      System.delete_env("CONTAINER_ENGINE")
      TestcontainerEx.Engine.set_engine(:apple_container)
      assert TestcontainerEx.Engine.detect() == :apple_container

      TestcontainerEx.Engine.clear_engine()
      assert TestcontainerEx.Engine.detect() == :docker
    end
  end

  # ── Minikube environment detection ────────────────────────────────

  describe "minikube_env?/0" do
    setup do
      original_dh = System.get_env("DOCKER_HOST")
      original_mka = System.get_env("MINIKUBE_ACTIVE_DOCKERD")
      original_mkp = System.get_env("MINIKUBE_PROFILE")

      on_exit(fn ->
        restore_env("DOCKER_HOST", original_dh)
        restore_env("MINIKUBE_ACTIVE_DOCKERD", original_mka)
        restore_env("MINIKUBE_PROFILE", original_mkp)
      end)

      System.delete_env("MINIKUBE_ACTIVE_DOCKERD")
      System.delete_env("MINIKUBE_PROFILE")
      System.delete_env("DOCKER_HOST")
      :ok
    end

    test "returns true when MINIKUBE_ACTIVE_DOCKERD is set" do
      System.put_env("MINIKUBE_ACTIVE_DOCKERD", "minikube")
      assert TestcontainerEx.Constants.minikube_env?()
    end

    test "returns true when MINIKUBE_PROFILE is set" do
      System.put_env("MINIKUBE_PROFILE", "minikube")
      assert TestcontainerEx.Constants.minikube_env?()
    end

    test "returns true when DOCKER_HOST is in minikube subnet 192.168.49.0/24" do
      System.put_env("DOCKER_HOST", "tcp://192.168.49.2:2376")
      assert TestcontainerEx.Constants.minikube_env?()
    end

    test "returns true when DOCKER_HOST is in minikube subnet 192.168.59.0/24" do
      System.put_env("DOCKER_HOST", "tcp://192.168.59.1:2376")
      assert TestcontainerEx.Constants.minikube_env?()
    end

    test "returns true when DOCKER_HOST is in minikube subnet 192.168.69.0/24" do
      System.put_env("DOCKER_HOST", "tcp://192.168.69.1:2376")
      assert TestcontainerEx.Constants.minikube_env?()
    end

    test "returns true when DOCKER_HOST ends with .minikube" do
      System.put_env("DOCKER_HOST", "tcp://myhost.minikube:2376")
      assert TestcontainerEx.Constants.minikube_env?()
    end

    test "returns false for non-minikube DOCKER_HOST" do
      System.put_env("DOCKER_HOST", "tcp://10.0.1.5:2376")
      refute TestcontainerEx.Constants.minikube_env?()
    end

    test "returns false for local DOCKER_HOST" do
      System.put_env("DOCKER_HOST", "tcp://127.0.0.1:2375")
      refute TestcontainerEx.Constants.minikube_env?()
    end

    test "returns false for unix socket DOCKER_HOST" do
      System.put_env("DOCKER_HOST", "unix:///var/run/docker.sock")
      refute TestcontainerEx.Constants.minikube_env?()
    end

    test "returns false when no env vars are set" do
      refute TestcontainerEx.Constants.minikube_env?()
    end

    test "returns false when DOCKER_HOST is nil" do
      System.delete_env("DOCKER_HOST")
      refute TestcontainerEx.Constants.minikube_env?()
    end
  end

  # ── Helpers ───────────────────────────────────────────────────────

  defp tmp_path(prefix) do
    Path.join(System.tmp_dir!(), "#{prefix}_#{:rand.uniform(100_000)}")
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
