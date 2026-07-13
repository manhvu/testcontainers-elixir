defmodule TestcontainerEx.Ryuk do
  @moduledoc """
  Manages the Ryuk reaper container for automatic cleanup of test containers.

  Ryuk is a sidecar container that watches for labeled containers and removes
  them when the test process exits. It is started during GenServer init and
  registered with a filter matching the current session.
  """

  require Logger

  alias TestcontainerEx.{
    Container.Config,
    Container.Lifecycle,
    Engine.Api,
    Util.Constants
  }

  import Constants

  @ryuk_image "testcontainers/ryuk"
  @ryuk_port 8080

  @doc """
  Starts the Ryuk reaper and registers the session filter.

  Returns `{:ok}` on success or `{:error, reason}` on failure.
  Ryuk failures are non-fatal — tests can still run without auto-cleanup.
  """
  @spec start(Req.Request.t(), String.t(), map(), String.t(), String.t()) ::
          {:ok} | {:error, term()}
  def start(conn, session_id, properties, container_engine_host, docker_hostname) do
    ryuk_disabled = Map.get(properties, "ryuk.disabled", "false") == "true"

    if ryuk_disabled do
      Logger.warning("""
      Ryuk has been disabled. This can cause unexpected behavior in your environment.
      Containers will not be automatically cleaned up after tests.
      """)

      {:ok}
    else
      do_start(conn, session_id, properties, container_engine_host, docker_hostname)
    end
  end

  @doc """
  Returns whether Ryuk should run in privileged mode.

  Checks `TESTCONTAINERS_RYUK_CONTAINER_PRIVILEGED` env var first,
  then `ryuk.container.privileged` property. Values `"true"` and `"1"`
  are truthy. The env var takes precedence.
  """
  @spec privileged?(map()) :: boolean()
  def privileged?(properties) do
    env = System.get_env("TESTCONTAINERS_RYUK_CONTAINER_PRIVILEGED")
    prop = Map.get(properties, "ryuk.container.privileged")
    value = env || prop
    truthy?(value)
  end

  # ── Host-based reaper (for macOS/Colima where container can't reach Docker) ──

  @doc """
  Starts a host-based reaper that watches for labeled containers and removes
  them when the test process exits.

  On macOS with Colima/Docker Desktop, the Ryuk container can't reach the
  Docker daemon inside the VM. This function runs the reaper logic directly
  on the host process instead.

  Returns `{:ok}` on success or `{:error, reason}` on failure.
  """
  @spec start_host_reaper(Req.Request.t(), String.t(), map()) :: {:ok} | {:error, term()}
  def start_host_reaper(conn, session_id, properties) do
    ryuk_disabled = Map.get(properties, "ryuk.disabled", "false") == "true"

    if ryuk_disabled do
      Logger.warning("Ryuk has been disabled.")
      {:ok}
    else
      do_start_host_reaper(conn, session_id)
    end
  end

  defp do_start_host_reaper(conn, session_id) do
    # Spawn a linked process that will die when the parent dies.
    # On exit, it cleans up all containers labeled with our session.
    parent = self()

    pid =
      spawn_link(fn ->
        # Wait for parent to exit
        monitor_ref = Process.monitor(parent)

        receive do
          {:DOWN, ^monitor_ref, :process, ^parent, _reason} ->
            Logger.info("Host reaper: parent process exited, cleaning up session #{session_id}")
            cleanup_labeled_containers(conn, session_id)
        end
      end)

    # Store the reaper PID so we can clean up on explicit stop
    :persistent_term.put({__MODULE__, session_id}, pid)

    Logger.info(
      "Host-based Ryuk reaper started for session #{session_id} (reaper PID: #{inspect(pid)})"
    )

    {:ok}
  end

  @doc """
  Stops the host-based reaper for a given session.
  """
  def stop_host_reaper(session_id) do
    case :persistent_term.get({__MODULE__, session_id}, nil) do
      nil ->
        :ok

      pid ->
        Process.exit(pid, :normal)
        :persistent_term.erase({__MODULE__, session_id})
    end
  end

  defp cleanup_labeled_containers(conn, session_id) do
    label = container_session_id_label()
    filters = Jason.encode!(%{"label" => ["#{label}=#{session_id}"]})

    case get(conn, "/containers/json?filters=#{URI.encode_www_form(filters)}") do
      {:ok, %{status: 200, body: body}} ->
        containers =
          case body do
            body when is_binary(body) ->
              case Jason.decode(body) do
                {:ok, parsed} -> parsed
                {:error, _} -> []
              end

            body when is_list(body) ->
              body

            _ ->
              []
          end

        Enum.each(containers, fn
          %{"Id" => id} ->
            Logger.debug("Host reaper: removing container #{String.slice(id, 0, 12)}")
            delete(conn, "/containers/#{id}?force=true")

          _ ->
            :ok
        end)

      _ ->
        :ok
    end
  end

  defp get(conn, path), do: Req.get(conn, url: path)
  defp delete(conn, path), do: Req.delete(conn, url: path)

  # ── Private ───────────────────────────────────────────────────────

  defp do_start(conn, session_id, properties, container_engine_host, docker_hostname) do
    # On macOS with Colima/Docker Desktop, the Docker daemon runs inside a VM.
    # Containers can't bind-mount the host's unix socket, so the Ryuk container
    # can't reach Docker. Use a host-based reaper instead.
    if Config.os_type() == :macos do
      Logger.info("Using host-based Ryuk reaper on macOS (Colima/Docker Desktop)")
      start_host_reaper(conn, session_id, properties)
    else
      do_start_container_reaper(
        conn,
        session_id,
        properties,
        container_engine_host,
        docker_hostname
      )
    end
  end

  defp do_start_container_reaper(
         conn,
         session_id,
         properties,
         container_engine_host,
         docker_hostname
       ) do
    ryuk_privileged = privileged?(properties)

    config =
      Config.new("#{@ryuk_image}:#{ryuk_version()}")
      |> Config.with_exposed_port(@ryuk_port)
      |> apply_docker_socket_mount(container_engine_host)
      |> Config.with_auto_remove(true)
      |> Config.with_privileged(ryuk_privileged)

    config = Lifecycle.resolve_pull_policy(config, properties)

    # Retry starting Ryuk up to 3 times with exponential backoff.
    # Transient connection errors (e.g. Docker daemon still starting) are common
    # in CI and Colima environments.
    case retry(fn -> start_ryuk_pipeline(config, conn, docker_hostname, session_id) end, 3) do
      {:ok} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "Ryuk failed to start after retries: #{inspect(reason)}. Containers will not be automatically cleaned up."
        )

        {:ok}
    end
  end

  defp start_ryuk_pipeline(config, conn, docker_hostname, session_id) do
    with {:ok, _} <- Api.pull_image(config.image, conn),
         {:ok, id} <- Api.create_container(config, conn),
         :ok <- Api.start_container(id, conn),
         {:ok, container} <- Api.get_container(id, conn),
         :ok <- connect_and_register(container, docker_hostname, session_id) do
      {:ok}
    end
  end

  defp retry(fun, max_retries, attempt \\ 1) do
    case fun.() do
      {:ok} = ok ->
        ok

      {:error, reason} when attempt < max_retries ->
        delay = :timer.seconds(attempt)

        Logger.info(
          "Ryuk start attempt #{attempt}/#{max_retries} failed (#{inspect(reason)}), retrying in #{delay}ms"
        )

        :timer.sleep(delay)
        retry(fun, max_retries, attempt + 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp connect_and_register(container, docker_hostname, session_id, attempt \\ 1)

  defp connect_and_register(container, docker_hostname, session_id, attempt) when attempt <= 5 do
    with {:ok, socket} <- create_socket(container, docker_hostname),
         :ok <- register_filter(session_id, socket) do
      :ok
    else
      error ->
        Logger.info("Ryuk registration failed (attempt #{attempt}/5): #{inspect(error)}")
        :timer.sleep(1000)
        connect_and_register(container, docker_hostname, session_id, attempt + 1)
    end
  end

  defp connect_and_register(_, _, _, _), do: {:error, :ryuk_connection_failed}

  defp create_socket(container, docker_hostname, reattempt \\ 0)

  defp create_socket(%Config{} = container, docker_hostname, reattempt) when reattempt < 5 do
    host_port = Config.mapped_port(container, @ryuk_port)

    case try_tcp_connect(docker_hostname, host_port) do
      {:ok, connected} ->
        {:ok, connected}

      {:error, reason} ->
        case try_container_internal_connect(container, @ryuk_port, reason) do
          {:ok, connected} ->
            {:ok, connected}

          {:error, _} ->
            Logger.info("Ryuk connection failed (attempt #{reattempt + 1}/5)")
            :timer.sleep(1000)
            create_socket(container, docker_hostname, reattempt + 1)
        end
    end
  end

  defp create_socket(_, _, _), do: {:error, :econnrefused}

  defp try_container_internal_connect(%Config{ip_address: ip}, port, original_reason)
       when is_binary(ip) and ip != "" do
    if Config.running_in_container?() do
      Logger.info("Trying container internal IP #{ip}:#{port}")
      try_tcp_connect(ip, port)
    else
      {:error, original_reason}
    end
  end

  defp try_container_internal_connect(_, _, original_reason), do: {:error, original_reason}

  defp try_tcp_connect(host, port) do
    :gen_tcp.connect(
      ~c"#{host}",
      port,
      [:binary, active: false, packet: :line, send_timeout: 10_000],
      5000
    )
  end

  defp register_filter(value, socket) do
    engine_label =
      case TestcontainerEx.Engine.detect() do
        :podman -> "label=io.container.manager=podman&"
        _ -> ""
      end

    :gen_tcp.send(
      socket,
      "label=#{container_session_id_label()}=#{value}&" <>
        "label=#{container_version_label()}=#{library_version()}&" <>
        "label=#{container_lang_label()}=#{container_lang_value()}&" <>
        "label=#{container_label()}=#{true}&" <>
        "label=#{container_reuse()}=#{false}&" <>
        engine_label <>
        "\n"
    )

    case :gen_tcp.recv(socket, 0, 2_000) do
      {:ok, "ACK\n"} -> :ok
      {:error, reason} -> {:error, {:failed_to_register_filter, reason}}
    end
  end

  defp apply_docker_socket_mount(config, container_engine_host) do
    override = System.get_env("TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE")

    if override do
      Config.with_bind_mount(config, override, "/var/run/docker.sock", "rw")
    else
      case {Config.os_type(), URI.parse(container_engine_host)} do
        {:linux, %URI{scheme: "unix", path: path}} ->
          Config.with_bind_mount(config, path, "/var/run/docker.sock", "rw")

        {:macos, %URI{scheme: "unix", path: _path}} ->
          # On macOS the Docker daemon runs inside a VM (Docker Desktop, Colima).
          # The unix socket exists on the host but cannot be bind-mounted into
          # containers because the VM cannot see macOS filesystem paths.
          # Ryuk will connect via the exposed TCP port instead.
          Logger.debug("Skipping Docker socket bind mount on macOS (daemon runs in VM)")

          config

        {:windows, _} ->
          Config.with_bind_mount(config, "//var/run/docker.sock", "/var/run/docker.sock", "rw")

        _ ->
          config
      end
    end
  end

  defp truthy?(value) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "true" -> true
      "1" -> true
      _ -> false
    end
  end

  defp truthy?(_), do: false
end
