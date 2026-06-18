defmodule TestcontainerEx.Engine do
  @moduledoc """
  Detects which container engine is in use: Docker, Podman, minikube, or Apple Container.

  ## Precedence

  1. Runtime override — set via `set_engine/1` (highest priority, per-process).
  2. `CONTAINER_ENGINE` env var — explicit selection (`docker`, `podman`, `colima`,
     `minikube`, `apple_container`). When set, auto-detection is skipped entirely.
  3. `CONTAINER_ENGINE_HOST` / `CONTAINER_HOST` env vars — if the URL contains
     `podman` or matches minikube subnets, the engine is inferred from the URL.
  4. `MINIKUBE_ACTIVE_DOCKERD` / `MINIKUBE_PROFILE` env vars.
  5. Apple Container — only when the `container` binary exists, the service reports
     "running", **and** the API socket exists.
  6. Podman ping — HTTP ping to the daemon checking for a Podman header.
  7. Default — `:docker`.

  ## Runtime engine selection

  You can override the auto-detected engine at runtime:

      TestcontainerEx.set_engine(:podman)
      TestcontainerEx.container_engine() # => :podman

  To reset back to auto-detection:

      TestcontainerEx.clear_engine()

  The override is stored per-process in the process dictionary, so it does not
  affect other processes and is cleaned up automatically when the calling process
  exits.
  """

  alias TestcontainerEx.Connection.Url

  @apple_container_socket "/var/run/com.apple.container.apiserver"

  @engine_key {__MODULE__, :runtime_override}

  @doc """
  Detects the container engine type.

  Returns one of:
  - `:apple_container` — Apple Container runtime
  - `:podman` — Podman
  - `:minikube` — Minikube
  - `:docker` — Docker (default)

  Resolution order:
  1. Runtime override (set via `set_engine/1`) — per-process, highest priority
  2. Cached auto-detection result (stored in `:persistent_term`)
  3. Fresh auto-detection (cached for subsequent calls)

  When `CONTAINER_ENGINE` env var is set to a valid engine, auto-detection
  is skipped entirely and that value is used directly.
  """
  @spec detect() :: :docker | :podman | :minikube | :apple_container
  def detect do
    case Process.get(@engine_key) do
      nil ->
        case :persistent_term.get({__MODULE__, :cached_engine}, nil) do
          nil ->
            engine = do_detect()
            :persistent_term.put({__MODULE__, :cached_engine}, engine)
            engine

          engine ->
            engine
        end

      engine ->
        engine
    end
  end

  @doc """
  Overrides the auto-detected engine at runtime.

  The override is stored in the calling process's dictionary, so it:
  - Takes precedence over `CONTAINER_ENGINE` env var and auto-detection
  - Only affects the calling process (and its children via `Process.info/1` inheritance)
  - Is cleaned up automatically when the process exits

  ## Examples

      iex> TestcontainerEx.set_engine(:podman)
      :ok
      iex> TestcontainerEx.container_engine()
      :podman

  """
  @spec set_engine(:docker | :podman | :colima | :minikube | :apple_container) :: :ok
  def set_engine(engine)
      when engine in [:docker, :podman, :colima, :minikube, :apple_container] do
    Process.put(@engine_key, engine)
    :ok
  end

  @doc """
  Clears a runtime engine override, restoring auto-detection.

  Also clears the `:persistent_term` cache so the next `detect/0` call
  re-runs the full auto-detection sequence.

  ## Examples

      iex> TestcontainerEx.clear_engine()
      :ok

  """
  @spec clear_engine() :: :ok
  def clear_engine do
    Process.delete(@engine_key)
    :persistent_term.erase({__MODULE__, :cached_engine})
    :ok
  end

  @doc """
  Returns the runtime override for the calling process, or `nil` if no
  override has been set.
  """
  @spec runtime_override() :: :docker | :podman | :colima | :minikube | :apple_container | nil
  def runtime_override do
    Process.get(@engine_key)
  end

  @doc """
  Returns `true` when running in a minikube environment.
  """
  @spec minikube?() :: boolean()
  def minikube? do
    minikube_env_var?() || minikube_docker_host?()
  end

  @doc """
  Returns `true` when running with Podman.
  """
  @spec podman?() :: boolean()
  def podman? do
    System.get_env("CONTAINER_HOST") != nil || podman_ping?()
  end

  @doc """
  Returns `true` when running with Apple Container.
  """
  @spec apple_container?() :: boolean()
  def apple_container? do
    apple_container_available?() && apple_container_running?()
  end

  # ── Private ───────────────────────────────────────────────────────

  defp do_detect do
    cond do
      explicit_engine() -> explicit_engine()
      podman_env?() -> :podman
      minikube?() -> :minikube
      apple_container?() -> :apple_container
      podman?() -> :podman
      true -> :docker
    end
  end

  # Explicit engine selection via CONTAINER_ENGINE env var.
  defp explicit_engine do
    case System.get_env("CONTAINER_ENGINE") do
      nil -> false
      "" -> false
      "auto" -> false
      "docker" -> :docker
      "podman" -> :podman
      "colima" -> :docker
      "minikube" -> :minikube
      "apple_container" -> :apple_container
      _ -> false
    end
  end

  # Check if CONTAINER_HOST or CONTAINER_ENGINE_HOST points to Podman.
  defp podman_env? do
    env_url = System.get_env("CONTAINER_HOST") || System.get_env("CONTAINER_ENGINE_HOST")

    if is_binary(env_url) and env_url != "" do
      url = String.downcase(env_url)
      String.contains?(url, "podman") or String.contains?(url, "containers")
    else
      false
    end
  end

  defp minikube_env_var? do
    System.get_env("MINIKUBE_ACTIVE_DOCKERD") != nil ||
      System.get_env("MINIKUBE_PROFILE") != nil
  end

  defp minikube_docker_host? do
    case System.get_env("CONTAINER_ENGINE_HOST") || System.get_env("DOCKER_HOST") do
      nil -> false
      "" -> false
      url when is_binary(url) -> minikube_subnet?(url)
    end
  end

  defp minikube_subnet?(url) do
    host = URI.parse(url).host

    is_binary(host) and
      (String.starts_with?(host, "192.168.49.") or
         String.starts_with?(host, "192.168.59.") or
         String.starts_with?(host, "192.168.69.") or
         String.starts_with?(host, "10.0.0.") or
         String.ends_with?(host, ".minikube"))
  end

  defp apple_container_available? do
    case System.find_executable("container") do
      nil -> false
      _ -> true
    end
  rescue
    ErlangError -> false
  end

  defp apple_container_running? do
    with {output, 0} <- System.cmd("container", ["system", "status"], stderr_to_stdout: true),
         true <- String.contains?(output, "running") or String.contains?(output, "Running"),
         true <- File.exists?(@apple_container_socket) do
      true
    else
      _ -> false
    end
  rescue
    ErlangError -> false
  end

  defp podman_ping? do
    client = Req.new()

    url =
      case System.get_env("CONTAINER_ENGINE_HOST") do
        nil -> "http://d/v1.43/_ping"
        "" -> "http://d/v1.43/_ping"
        host when is_binary(host) -> "#{Url.construct(host)}/_ping"
      end

    case Req.get(client, url: url) do
      {:ok, %{headers: headers}} ->
        Enum.any?(headers, fn {_, v} -> String.contains?(v, "Podman") end)

      _ ->
        false
    end
  rescue
    _ -> false
  end
end
