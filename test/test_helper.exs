# Ensures Colima/Docker is in a good state before running tests.
# Colima's Docker daemon can die or become unresponsive, especially under load.
# A fresh restart gives every test run the best chance of success.
if System.find_executable("colima") do
  IO.puts("==> Ensuring Colima is running...")

  {_, status} = System.cmd("colima", ["status"], stderr_to_stdout: true)

  colima_ok =
    if status == 0 do
      # Colima reports running — verify Docker daemon actually responds
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

# Detect whether a Docker/Podman daemon is reachable before starting the
# TestcontainerEx GenServer. We avoid calling Connection.get_connection/1
# because it calls exit/1 on failure. Instead we do a quick probe of the
# well-known socket paths and env vars.
docker_reachable? =
  Enum.any?(
    [
      "/var/run/docker.sock",
      Path.expand("~/.docker/run/docker.sock"),
      Path.expand("~/.docker/desktop/docker.sock")
    ],
    fn path ->
      case File.stat(path) do
        {:ok, stat} -> :erlang.band(stat.mode, 0o170000) == 0o140000
        _ -> false
      end
    end
  ) or
    System.get_env("DOCKER_HOST") != nil or
    System.get_env("CONTAINER_HOST") != nil

exclude =
  if TestcontainerEx.running_in_container?() do
    [:dood_limitation]
  else
    if docker_reachable? do
      # Try to start the GenServer; if it fails (e.g. daemon not responding),
      # exclude dock-dependent tests.
      try do
        case TestcontainerEx.start_link() do
          {:ok, pid} ->
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

ExUnit.start(timeout: 300_000, exclude: exclude)
