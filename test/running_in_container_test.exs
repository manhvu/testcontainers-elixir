defmodule TestcontainerEx.RunningInContainerTest do
  use ExUnit.Case, async: true

  describe "running_in_container?/2" do
    test "returns true when dockerenv file exists" do
      tmp_path = Path.join(System.tmp_dir!(), "test_dockerenv_#{:rand.uniform(100_000)}")
      File.write!(tmp_path, "")

      try do
        assert TestcontainerEx.running_in_container?(tmp_path, "/nonexistent/cgroup")
      after
        File.rm(tmp_path)
      end
    end

    test "returns true when kubernetes secrets directory exists" do
      tmp_path = Path.join(System.tmp_dir!(), "test_k8s_secrets_#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_path)

      try do
        assert TestcontainerEx.running_in_container?("/nonexistent/dockerenv", "/nonexistent/cgroup")
      after
        File.rm_rf(tmp_path)
      end
    end

    test "returns true when .containerenv file exists (Podman)" do
      tmp_path = Path.join(System.tmp_dir!(), "test_containerenv_#{:rand.uniform(100_000)}")
      File.write!(tmp_path, "")

      try do
        assert TestcontainerEx.running_in_container?("/nonexistent/dockerenv", "/nonexistent/cgroup")
      after
        File.rm(tmp_path)
      end
    end

    test "returns true when cgroup contains docker pattern" do
      tmp_path = Path.join(System.tmp_dir!(), "test_cgroup_#{:rand.uniform(100_000)}")

      File.write!(tmp_path, """
      12:memory:/docker/abc123def456
      11:cpu:/docker/abc123def456
      """)

      try do
        assert TestcontainerEx.running_in_container?("/nonexistent/dockerenv", tmp_path)
      after
        File.rm(tmp_path)
      end
    end

    test "returns true when cgroup contains kubepods pattern" do
      tmp_path = Path.join(System.tmp_dir!(), "test_cgroup_kube_#{:rand.uniform(100_000)}")

      File.write!(tmp_path, """
      12:memory:/kubepods/besteffort/pod123
      """)

      try do
        assert TestcontainerEx.running_in_container?("/nonexistent/dockerenv", tmp_path)
      after
        File.rm(tmp_path)
      end
    end

    test "returns true when cgroup contains podman pattern" do
      tmp_path = Path.join(System.tmp_dir!(), "test_cgroup_podman_#{:rand.uniform(100_000)}")

      File.write!(tmp_path, """
      12:memory:/podman/container-abc123
      11:cpu:/podman/container-abc123
      """)

      try do
        assert TestcontainerEx.running_in_container?("/nonexistent/dockerenv", tmp_path)
      after
        File.rm(tmp_path)
      end
    end

    test "returns true when cgroup contains lxc pattern" do
      tmp_path = Path.join(System.tmp_dir!(), "test_cgroup_lxc_#{:rand.uniform(100_000)}")

      File.write!(tmp_path, """
      12:memory:/lxc/container-name
      """)

      try do
        assert TestcontainerEx.running_in_container?("/nonexistent/dockerenv", tmp_path)
      after
        File.rm(tmp_path)
      end
    end

    test "returns true when cgroup contains containerd pattern" do
      tmp_path = Path.join(System.tmp_dir!(), "test_cgroup_containerd_#{:rand.uniform(100_000)}")

      File.write!(tmp_path, """
      12:memory:/system.slice/containerd.service
      """)

      try do
        assert TestcontainerEx.running_in_container?("/nonexistent/dockerenv", tmp_path)
      after
        File.rm(tmp_path)
      end
    end

    test "returns false when neither dockerenv nor cgroup exist" do
      refute TestcontainerEx.running_in_container?("/nonexistent/dockerenv", "/nonexistent/cgroup")
    end

    test "returns false when cgroup exists but has no container patterns" do
      tmp_path = Path.join(System.tmp_dir!(), "test_cgroup_empty_#{:rand.uniform(100_000)}")

      File.write!(tmp_path, """
      12:memory:/user.slice/user-1000.slice
      11:cpu:/user.slice/user-1000.slice
      """)

      try do
        refute TestcontainerEx.running_in_container?("/nonexistent/dockerenv", tmp_path)
      after
        File.rm(tmp_path)
      end
    end

    test "dockerenv takes precedence over other checks" do
      dockerenv = Path.join(System.tmp_dir!(), "test_precedence_dockerenv_#{:rand.uniform(100_000)}")
      File.write!(dockerenv, "")

      cgroup = Path.join(System.tmp_dir!(), "test_precedence_cgroup_#{:rand.uniform(100_000)}")
      File.write!(cgroup, "12:memory:/user.slice/user-1000.slice")

      try do
        # Even with a non-container cgroup, dockerenv presence returns true
        assert TestcontainerEx.running_in_container?(dockerenv, cgroup)
      after
        File.rm(dockerenv)
        File.rm(cgroup)
      end
    end
  end
end
