# Detect whether a Docker/Podman daemon is reachable before starting the
# TestcontainerEx GenServer.  We avoid calling Connection.get_connection/1
# because it calls exit/1 on failure.  Instead we do a quick probe of the
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
        {:ok, %{type: :socket}} -> true
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
          {:ok, _pid} -> [:dood_limitation]
          _ -> [:needs_dock, :dood_limitation]
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
