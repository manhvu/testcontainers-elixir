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
    Docker.Api,
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
  @spec start(Tesla.Env.client(), String.t(), map(), String.t(), String.t()) ::
          {:ok} | {:error, term()}
  def start(conn, session_id, properties, docker_host, docker_hostname) do
    ryuk_disabled = Map.get(properties, "ryuk.disabled", "false") == "true"

    if ryuk_disabled do
      Logger.warning("""
      Ryuk has been disabled. This can cause unexpected behavior in your environment.
      Containers will not be automatically cleaned up after tests.
      """)

      {:ok}
    else
      do_start(conn, session_id, properties, docker_host, docker_hostname)
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

  # ── Private ───────────────────────────────────────────────────────

  defp do_start(conn, session_id, properties, docker_host, docker_hostname) do
    ryuk_privileged = privileged?(properties)

    config =
      Config.new("#{@ryuk_image}:#{ryuk_version()}")
      |> Config.with_exposed_port(@ryuk_port)
      |> apply_docker_socket_mount(docker_host)
      |> Config.with_auto_remove(true)
      |> Config.with_privileged(ryuk_privileged)

    config = TestcontainerEx.Container.Lifecycle.resolve_pull_policy(config, properties)

    with :ok <- Api.pull_image(config.image, conn),
         {:ok, id} <- Api.create_container(config, conn),
         :ok <- Api.start_container(id, conn),
         {:ok, container} <- Api.get_container(id, conn),
         :ok <- connect_and_register(container, docker_hostname, session_id) do
      {:ok}
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
      case TestcontainerEx.Docker.Engine.detect() do
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

  defp apply_docker_socket_mount(config, docker_host) do
    override = System.get_env("TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE")

    if override do
      Config.with_bind_mount(config, override, "/var/run/docker.sock", "rw")
    else
      case {Config.os_type(), URI.parse(docker_host)} do
        {:linux, %URI{scheme: "unix", path: path}} ->
          Config.with_bind_mount(config, path, "/var/run/docker.sock", "rw")

        {:macos, %URI{scheme: "unix", path: path}} ->
          Config.with_bind_mount(config, path, "/var/run/docker.sock", "rw")

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
