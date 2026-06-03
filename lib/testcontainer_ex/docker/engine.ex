defmodule TestcontainerEx.Docker.Engine do
  @moduledoc """
  Detects which container engine is in use: Docker, Podman, or minikube.

  Detection is cached after the first call via `:persistent_term`.
  """

  alias TestcontainerEx.Connection.Url

  @doc """
  Detects the container engine type.

  Returns one of:
  - `:podman` — if `CONTAINER_HOST` is set or the daemon identifies as Podman
  - `:minikube` — if minikube env vars are set or DOCKER_HOST matches minikube subnets
  - `:docker` — default fallback

  Results are cached after the first call.
  """
  @spec detect() :: :docker | :podman | :minikube
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

  # ── Private ───────────────────────────────────────────────────────

  defp do_detect do
    cond do
      podman?() -> :podman
      minikube?() -> :minikube
      true -> :docker
    end
  end

  defp minikube_env_var? do
    System.get_env("MINIKUBE_ACTIVE_DOCKERD") != nil ||
      System.get_env("MINIKUBE_PROFILE") != nil
  end

  defp minikube_docker_host? do
    case System.get_env("DOCKER_HOST") do
      nil -> false
      url -> minikube_subnet?(url)
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

  defp podman_ping? do
    client = Tesla.client([], Tesla.Adapter.Hackney)

    url =
      case System.get_env("DOCKER_HOST") do
        nil -> "http://d/v1.43/_ping"
        host -> "#{Url.construct(host)}/_ping"
      end

    case Tesla.get(client, url) do
      {:ok, %{headers: headers}} ->
        Enum.any?(headers, fn {_, v} -> String.contains?(v, "Podman") end)

      _ ->
        false
    end
  rescue
    _ -> false
  end
end
