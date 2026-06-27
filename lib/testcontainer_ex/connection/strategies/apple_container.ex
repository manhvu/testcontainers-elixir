defmodule TestcontainerEx.Connection.Strategies.AppleContainer do
  @moduledoc """
  Resolves the container engine host for Apple Container (https://github.com/apple/container).

  Apple Container is a macOS-native container runtime for Apple silicon Macs.
  It runs a lightweight VM per container using the open source Containerization
  package, providing VM-level isolation with container-like performance.

  Unlike Docker/Podman, Apple Container does not expose a Docker-compatible HTTP API.
  Instead, it uses XPC for interprocess communication between the `container` CLI
  and the `container-apiserver` launch agent. The apiserver manages container
  and network resources via XPC helpers:

    - `container-core-images` — image management and local content store
    - `container-network-vmnet` — virtual network management
    - `container-runtime-linux` — per-container runtime management

  This strategy activates when:
  - The `container` binary is available on PATH (or via `CONTAINER_BIN` env var)
  - The host is running macOS 26+ (Apple Container requires macOS 26 or later)
  - The `container-apiserver` launch agent is registered with launchd
  - The Apple Container system service reports "running" status
  - The API server socket exists at `/var/run/com.apple.container.apiserver`

  The strategy returns a special URL scheme `apple-container://` that downstream
  code uses to route operations through the `container` CLI.

  ## System requirements

  - macOS 26+ (Apple silicon Mac)
  - `container` CLI installed (https://github.com/apple/container)

  ## Configuration

  No special configuration is required beyond having `container` installed and
  running on an Apple silicon Mac.

  ## Environment variables

  - `CONTAINER_BIN` — override the path to the `container` binary
    (default: searches PATH for `container`)
  - `CONTAINER_ENGINE=apple_container` — explicitly select Apple Container

  ## Apple Container architecture

  Apple Container uses a fundamentally different architecture than Docker:

  - Each container runs in its own lightweight VM (not a shared VM)
  - The `container-apiserver` is a launch agent (not a daemon)
  - Communication is via XPC, not HTTP REST API
  - Images are standard OCI images (interoperable with Docker)
  - Networking uses vmnet framework with per-container isolation

  See https://github.com/apple/container/blob/main/docs/technical-overview.md
  for the full technical overview.
  """

  @behaviour TestcontainerEx.Connection.Strategies.Behaviour

  require Logger

  @default_bin "container"
  @apple_container_url "apple-container://"
  @apple_container_socket "/var/run/com.apple.container.apiserver"
  @apiserver_service "com.apple.container.container-apiserver"
  @min_macos_version "26.0"

  @impl true
  def resolve do
    with :ok <- verify_platform(),
         {:ok, bin} <- find_binary(),
         :ok <- verify_apiserver_registered(bin),
         :ok <- verify_running(bin),
         :ok <- verify_socket() do
      Logger.info("Container engine detected via Apple Container: #{@apple_container_url}")
      {:ok, @apple_container_url}
    end
  end

  # ── Platform verification ────────────────────────────────────────────────────

  defp verify_platform do
    case :os.type() do
      {:unix, :darwin} ->
        case System.cmd("sw_vers", ["-productVersion"], stderr_to_stdout: true) do
          {version, 0} ->
            version = String.trim(version)

            if version_gte?(version, @min_macos_version) do
              :ok
            else
              {:error, {:apple_container_unsupported_macos, version, @min_macos_version}}
            end

          _ ->
            {:error, :apple_container_cannot_detect_macos_version}
        end

      _ ->
        {:error, :apple_container_not_macos}
    end
  end

  defp version_gte?(version, min_version) do
    {{v1, v2, v3}, {m1, m2, m3}} = {parse_version(version), parse_version(min_version)}
    v1 > m1 or (v1 == m1 and v2 > m2) or (v1 == m1 and v2 == m2 and v3 >= m3)
  end

  defp parse_version(version_string) do
    case String.split(version_string, ".") do
      [major, minor, patch | _] ->
        {to_integer(major), to_integer(minor), to_integer(patch)}

      [major, minor] ->
        {to_integer(major), to_integer(minor), 0}

      [major] ->
        {to_integer(major), 0, 0}

      _ ->
        {0, 0, 0}
    end
  end

  defp to_integer(string) do
    case Integer.parse(String.trim(string)) do
      {int, _} -> int
      :error -> 0
    end
  end

  # ── Binary detection ─────────────────────────────────────────────────────────

  defp find_binary do
    case System.get_env("CONTAINER_BIN") do
      nil ->
        case System.find_executable(@default_bin) do
          nil -> {:error, :apple_container_not_installed}
          bin -> {:ok, bin}
        end

      "" ->
        {:error, :apple_container_not_installed}

      bin ->
        if File.exists?(bin) do
          {:ok, bin}
        else
          {:error, {:apple_container_bin_not_found, bin}}
        end
    end
  end

  # ── Launch agent verification ────────────────────────────────────────────────

  defp verify_apiserver_registered(bin) do
    # Check if the apiserver launch agent is registered with launchd.
    # Apple Container registers com.apple.container.container-apiserver as a
    # LaunchAgent that starts on demand when `container system start` is run.
    case System.cmd("launchctl", ["list"], stderr_to_stdout: true) do
      {output, 0} ->
        if String.contains?(output, @apiserver_service) do
          :ok
        else
          # Not registered — try to start it
          Logger.info("Apple Container apiserver not registered, attempting to start...")
          start_apiserver(bin)
        end

      _ ->
        # launchctl list failed, try starting anyway
        start_apiserver(bin)
    end
  end

  defp start_apiserver(bin) do
    case System.cmd(bin, ["system", "start"], stderr_to_stdout: true) do
      {_output, 0} ->
        Logger.info("Apple Container apiserver started successfully")
        # Give it a moment to register
        Process.sleep(500)
        :ok

      {output, _exit_code} ->
        Logger.warning("Failed to start Apple Container apiserver: #{output}")
        {:error, :apple_container_start_failed}
    end
  end

  # ── Running verification ─────────────────────────────────────────────────────

  defp verify_running(bin) do
    case System.cmd(bin, ["system", "status"], stderr_to_stdout: true) do
      {output, 0} ->
        if String.contains?(output, "running") or String.contains?(output, "Running") do
          :ok
        else
          {:error, :apple_container_not_running}
        end

      {_output, _exit_code} ->
        {:error, :apple_container_not_running}
    end
  rescue
    ErlangError -> {:error, :apple_container_not_running}
  end

  # ── Socket verification ──────────────────────────────────────────────────────

  defp verify_socket do
    case File.stat(@apple_container_socket) do
      {:ok, stat} ->
        if :erlang.band(stat.mode, 0o170000) == 0o140000 do
          :ok
        else
          {:error, {:apple_container_socket_not_socket, @apple_container_socket}}
        end

      {:error, reason} ->
        {:error, {:apple_container_socket_not_found, @apple_container_socket, reason}}
    end
  end
end
