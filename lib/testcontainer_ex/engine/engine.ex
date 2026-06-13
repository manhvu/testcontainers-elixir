defmodule TestcontainerEx.Engine do
  @moduledoc """
  Detects which container engine is in use: Docker, Podman, minikube, or Apple Container.

  Detection is cached after the first call via `:persistent_term`.

  ## Precedence

  1. `CONTAINER_ENGINE` env var — explicit selection (`docker`, `podman`, `colima`,
     `minikube`, `apple_container`). When set, auto-detection is skipped entirely.
  2. `CONTAINER_ENGINE_HOST` / `CONTAINER_HOST` env vars — if the URL contains
     `podman` or matches minikube subnets, the engine is inferred from the URL.
  3. `MINIKUBE_ACTIVE_DOCKERD` / `MINIKUBE_PROFILE` env vars.
  4. Apple Container — only when the `container` binary exists, the service reports
     "running", **and** the API socket exists.
  5. Podman ping — HTTP ping to the daemon checking for a Podman header.
  6. Default — `:docker`.
  """

  alias TestcontainerEx.Connection.Url

  @apple_container_socket "/var/run/com.apple.container.apiserver"

  @doc """
  Detects the container engine type.

  Returns one of:
  - `:apple_container` — Apple Container runtime
  - `:podman` — Podman
  - `:minikube` — Minikube
  - `:docker` — Docker (default)

  Results are cached after the first call.
  """
  @spec detect() :: :docker | :podman | :minikube | :apple_container
  def detect do
    case :persistent_term.get({__MODULE__, :engine}, nil) do
      nil ->
        engine = do_detect()
        :persistent_term.put({__MODULE__, :engine}, engine)
        engine

      engine ->
        engine
    end
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
    case {System.get_env("CONTAINER_ENGINE_HOST"), System.get_env("DOCKER_HOST")} do
      {nil, nil} -> false
      {url, _} when is_binary(url) and url != "" -> minikube_subnet?(url)
      {_, url} when is_binary(url) and url != "" -> minikube_subnet?(url)
      _ -> false
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
      case {System.get_env("CONTAINER_ENGINE_HOST"), System.get_env("DOCKER_HOST")} do
        {nil, nil} -> "http://d/v1.43/_ping"
        {host, _} when is_binary(host) and host != "" -> "#{Url.construct(host)}/_ping"
        {_, host} when is_binary(host) and host != "" -> "#{Url.construct(host)}/_ping"
        _ -> "http://d/v1.43/_ping"
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
