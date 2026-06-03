defmodule TestcontainerEx.Connection.Strategies.Socket do
  @moduledoc """
  Resolves the container engine host by scanning well-known Unix socket paths.

  Checks standard Docker, Podman, and minikube socket locations.
  Only paths that actually exist are probed.
  """

  @behaviour TestcontainerEx.Connection.Strategies.Behaviour

  @default_paths [
    "/var/run/docker.sock",
    "~/.docker/run/docker.sock",
    "~/.docker/desktop/docker.sock",
    "~/.colima/default/docker.sock"
  ]

  @impl true
  def resolve do
    paths =
      @default_paths ++
        xdg_socket_paths() ++
        minikube_socket_paths()

    paths
    |> Enum.map(&Path.expand/1)
    |> Enum.filter(&File.exists?/1)
    |> case do
      [] ->
        {:error, :no_socket_found}

      existing ->
        try_sockets(existing)
    end
  end

  defp try_sockets([]), do: {:error, :all_sockets_failed}

  defp try_sockets([path | rest]) do
    url = "unix://#{path}"

    case Tesla.get(test_client(), "#{TestcontainerEx.Connection.Url.construct(url)}/_ping") do
      {:ok, _} -> {:ok, url}
      {:error, _} -> try_sockets(rest)
    end
  end

  defp xdg_socket_paths do
    case System.get_env("XDG_RUNTIME_DIR") do
      nil ->
        []

      path ->
        ["#{path}/podman/podman.sock", "#{path}/containers/podman.sock", "#{path}/docker.sock"]
    end
  end

  defp minikube_socket_paths do
    ["/var/run/minikube/docker.sock", "/var/run/minikube.sock"]
  end

  defp test_client, do: Tesla.client([], Tesla.Adapter.Hackney)
end
