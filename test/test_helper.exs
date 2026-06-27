# Ensures the selected container engine is in a good state before running tests.
# When CONTAINER_ENGINE is set (and not "auto"), only that engine is started.
# In auto mode, falls back to the existing Colima-first behaviour.

# --- Colima startup (shared by auto/colima modes) ------------------------------

ensure_colima = fn ->
  if System.find_executable("colima") do
    IO.puts("==> Ensuring Colima is running...")

    {_, status} = System.cmd("colima", ["status"], stderr_to_stdout: true)

    colima_ok =
      if status == 0 do
        case System.cmd("docker", ["ps"], stderr_to_stdout: true) do
          {_, 0} -> true
          _ -> false
        end
      else
        false
      end

    unless colima_ok do
      IO.puts("==> Restarting Colima (colima stop --force && colima start)...")
      System.cmd("colima", ["stop", "--force"], stderr_to_stdout: true)
      {_, start_status} = System.cmd("colima", ["start"], stderr_to_stdout: true)

      if start_status != 0 do
        raise "Failed to start Colima. Run `colima stop --force && colima start` manually."
      end

      IO.puts("==> Colima restarted successfully.")
    end
  end
end

# --- Engine-specific checks ----------------------------------------------------

ensure_docker = fn ->
  if System.find_executable("docker") do
    case System.cmd("docker", ["info"], stderr_to_stdout: true) do
      {_, 0} ->
        IO.puts("==> Docker daemon is ready")

      _ ->
        IO.puts("==> WARNING: Docker daemon not responding. Please start Docker Desktop.")
    end
  else
    IO.puts("==> WARNING: docker command not found. Is Docker installed?")
  end
end

ensure_podman = fn ->
  if System.find_executable("podman") do
    case System.cmd("podman", ["machine", "list", "--format", "{{.Running}}"],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        if String.trim(output) == "true" do
          IO.puts("==> Podman machine is running")
        else
          IO.puts("==> Starting Podman machine...")
          System.cmd("podman", ["machine", "start"], stderr_to_stdout: true)
        end

      _ ->
        IO.puts("==> WARNING: Could not check Podman machine status")
    end
  else
    IO.puts("==> WARNING: podman command not found. Is Podman installed?")
  end
end

ensure_minikube = fn ->
  if System.find_executable("minikube") do
    case System.cmd("minikube", ["status", "--format", "{{.Host}}"], stderr_to_stdout: true) do
      {"Running", 0} ->
        IO.puts("==> Minikube is running")

      _ ->
        IO.puts("==> Starting Minikube...")
        System.cmd("minikube", ["start"], stderr_to_stdout: true)
    end
  else
    IO.puts("==> WARNING: minikube command not found. Is Minikube installed?")
  end
end

ensure_apple_container = fn ->
  if System.find_executable("container") do
    case System.cmd("container", ["system", "status"], stderr_to_stdout: true) do
      {output, 0} ->
        if String.contains?(output, "running") or String.contains?(output, "Running") do
          IO.puts("==> Apple Container is running")
        else
          IO.puts("==> Starting Apple Container...")
          System.cmd("container", ["system", "start"], stderr_to_stdout: true)
        end

      _ ->
        IO.puts("==> WARNING: Could not check Apple Container status")
    end
  else
    IO.puts("==> WARNING: container command not found. Is Apple Container installed?")
  end
end

# --- Dispatch ------------------------------------------------------------------

case System.get_env("CONTAINER_ENGINE") do
  nil ->
    ensure_colima.()

  "" ->
    ensure_colima.()

  "auto" ->
    ensure_colima.()

  "colima" ->
    IO.puts("==> CONTAINER_ENGINE=colima: starting Colima only")
    ensure_colima.()

  "docker" ->
    IO.puts("==> CONTAINER_ENGINE=docker: ensuring Docker is running")
    ensure_docker.()

  "podman" ->
    IO.puts("==> CONTAINER_ENGINE=podman: ensuring Podman is running")
    ensure_podman.()

  "minikube" ->
    IO.puts("==> CONTAINER_ENGINE=minikube: ensuring Minikube is running")
    ensure_minikube.()

  "apple_container" ->
    IO.puts("==> CONTAINER_ENGINE=apple_container: ensuring Apple Container is running")
    ensure_apple_container.()

  other ->
    IO.puts("==> Unknown CONTAINER_ENGINE=#{other}, falling back to auto mode")
    ensure_colima.()
end

# Detect whether a container engine daemon is reachable before starting the
# TestcontainerEx GenServer. We avoid calling Connection.get_connection/1
# because it returns {:error, _} on failure. Instead we do a quick probe of the
# well-known socket paths and env vars.
docker_reachable? =
  Enum.any?(
    [
      "/var/run/docker.sock",
      Path.expand("~/.docker/run/docker.sock"),
      Path.expand("~/.docker/desktop/docker.sock"),
      Path.expand("~/.colima/default/docker.sock"),
      Path.expand("~/.colima/docker.sock")
    ],
    fn path ->
      case File.stat(path) do
        {:ok, stat} -> :erlang.band(stat.mode, 0o170000) == 0o140000
        _ -> false
      end
    end
  ) or
    System.get_env("CONTAINER_HOST") != nil or
    case System.find_executable("container") do
      nil ->
        false

      bin ->
        case System.cmd(bin, ["system", "status"], stderr_to_stdout: true) do
          {output, 0} ->
            String.contains?(output, "running") or String.contains?(output, "Running")

          _ ->
            false
        end
    end

exclude =
  if TestcontainerEx.running_in_container?() do
    [:dood_limitation]
  else
    if docker_reachable? do
      # Try to start the GenServer with a timeout; if it fails (e.g. daemon not
      # responding), exclude dock-dependent tests.
      try do
        task = Task.async(fn -> TestcontainerEx.start_link() end)

        case Task.yield(task, 10_000) || Task.shutdown(task) do
          {:ok, {:ok, pid}} ->
            if TestcontainerEx.connected?() do
              [:dood_limitation]
            else
              TestcontainerEx.stop(pid)
              [:needs_dock, :dood_limitation]
            end

          _ ->
            [:needs_dock, :dood_limitation]
        end
      rescue
        _ -> [:needs_dock, :dood_limitation]
      catch
        :exit, _ -> [:needs_dock, :dood_limitation]
        _ -> [:needs_dock, :dood_limitation]
      end
    else
      [:needs_dock, :dood_limitation]
    end
  end

# Warm up the Docker daemon before starting tests.
# A quick docker info call ensures the daemon is responsive and any
# lazy-initialized subsystems (network, registry connections) are ready.
IO.puts("==> Warming up Docker daemon...")
case System.cmd("docker", ["info"], stderr_to_stdout: true) do
  {_, 0} -> IO.puts("==> Docker daemon is ready")
  {output, _} -> IO.puts("==> WARNING: Docker daemon info returned:\n#{output}")
end

ExUnit.start(timeout: 300_000, exclude: exclude)
