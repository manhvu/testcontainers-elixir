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

  Returns `:podman` if the daemon responds with a `Server: Podman` header
  on the `/_ping` endpoint, or if the `CONTAINER_HOST` env var is set.
  Returns `:docker` otherwise.

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

      true ->
        :docker
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
