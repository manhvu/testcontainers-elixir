defmodule TestcontainerEx.Constants do
  @moduledoc false

  def library_name, do: :testcontainer_ex
  def library_version, do: "2.3.1"
  def ryuk_version, do: "0.14.0"
  def container_label, do: "org.testcontainer_ex"
  def container_lang_label, do: "org.testcontainer_ex.lang"
  def container_reuse_hash_label, do: "org.testcontainer_ex.reuse-hash"
  def container_reuse, do: "org.testcontainer_ex.reuse"
  def container_lang_value, do: Elixir |> Atom.to_string() |> String.downcase()
  def container_session_id_label, do: "org.testcontainer_ex.session-id"
  def container_version_label, do: "org.testcontainer_ex.version"
  def user_agent, do: "tc-elixir/" <> __MODULE__.library_version()

  @doc """
  Detects which container engine is in use.

  Returns one of:

  - `:podman` — if `CONTAINER_HOST` is set or the daemon identifies as Podman.
  - `:minikube` — if `MINIKUBE_ACTIVE_DOCKERD` is set or the Docker host
    resolves to a minikube IP/profile.
  - `:docker` — default fallback.

  The result is cached after the first call.
  """
  def container_engine do
    case :persistent_term.get({__MODULE__, :container_engine}, nil) do
      nil ->
        engine = detect_container_engine()
        :persistent_term.put({__MODULE__, :container_engine}, engine)
        engine

      engine ->
        engine
    end
  end

  defp detect_container_engine do
    cond do
      System.get_env("CONTAINER_HOST") ->
        :podman

      podman_ping?() ->
        :podman

      minikube_env?() ->
        :minikube

      true ->
        :docker
    end
  end

  @doc """
  Returns `true` when running in a minikube environment.

  Checks for:
  - The `MINIKUBE_ACTIVE_DOCKERD` environment variable (set by `minikube docker-env`)
  - The `MINIKUBE_PROFILE` environment variable
  - A `DOCKER_HOST` value that resolves to a minikube IP (192.168.49.0/24)
  """
  def minikube_env? do
    cond do
      System.get_env("MINIKUBE_ACTIVE_DOCKERD") ->
        true

      System.get_env("MINIKUBE_PROFILE") ->
        true

      minikube_docker_host?() ->
        true

      true ->
        false
    end
  end

  defp minikube_docker_host? do
    case System.get_env("DOCKER_HOST") do
      nil ->
        false

      docker_host ->
        case URI.parse(docker_host) do
          %URI{host: host} when is_binary(host) ->
            # minikube's default subnet is 192.168.49.0/24 (docker driver)
            # or 192.168.59.0/24 (podman driver)
            String.starts_with?(host, "192.168.49.") or
              String.starts_with?(host, "192.168.59.") or
              String.starts_with?(host, "192.168.69.") or
              String.starts_with?(host, "10.0.0.") or
              String.ends_with?(".minikube", host)

          _ ->
            false
        end
    end
  end

  defp podman_ping? do
    test_client = Tesla.client([], Tesla.Adapter.Hackney)

    case System.get_env("DOCKER_HOST") do
      nil ->
        case Tesla.get(test_client, "http://d/v1.43/_ping") do
          {:ok, %{headers: headers}} ->
            Enum.any?(headers, fn {_, v} -> String.contains?(v, "Podman") end)

          _ ->
            false
        end

      docker_host ->
        url = TestcontainerEx.DockerUrl.construct(docker_host)

        case Tesla.get(test_client, "#{url}/_ping") do
          {:ok, %{headers: headers}} ->
            Enum.any?(headers, fn {_, v} -> String.contains?(v, "Podman") end)

          _ ->
            false
        end
    end
  rescue
    _ -> false
  end
end
