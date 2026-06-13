# SPDX-License-Identifier: MIT
defmodule TestcontainerEx.Engine.Auth do
  @moduledoc """
  Resolves Docker registry credentials from the user's Docker config file
  (typically `~/.docker/config.json`) and returns a ready-to-send
  `X-Registry-Auth` header value.

  Scope:

    * Only the `auths` map in `config.json` is supported.
    * Credential helpers (`credsStore`, `credHelpers`) are intentionally out
      of scope — if encountered, a debug log is emitted and `nil` is returned
      so the caller can fall back to anonymous access.

  The `DOCKER_CONFIG` environment variable is honoured: when set, the config
  file is read from `$DOCKER_CONFIG/config.json`; otherwise the default path
  `~/.docker/config.json` is used.

  The header value is a URL-safe base64 encoding (without padding) of a JSON
  document describing the credentials, as specified by the Docker Engine API.

  Third-party registries (quay.io, ghcr.io, gcr.io, registry.gitlab.com, etc.)
  are fully supported. The registry key is extracted from the image reference
  and looked up directly in the `auths` map.
  """

  require Logger

  @docker_hub_key "https://index.docker.io/v1/"

  # Known third-party registry hostnames for candidate key generation
  @known_registries ~w(
    quay.io
    ghcr.io
    gcr.io
    registry.gitlab.com
    us.gcr.io
    eu.gcr.io
    asia.gcr.io
    pkg.dev
    docker.elastic.co
    mcr.microsoft.com
    public.ecr.aws
    nvcr.io
    registry.k8s.io
  )

  @doc """
  Resolves registry credentials for the given `image` and returns the
  ready-to-send `X-Registry-Auth` header value, or `nil` if no matching
  credentials can be found.

  `config_path` may be `nil`, in which case the default lookup logic is used
  (respecting the `DOCKER_CONFIG` environment variable).
  """
  @spec resolve(String.t(), String.t() | nil) :: String.t() | nil
  def resolve(image, config_path \\ nil) when is_binary(image) do
    case read_config(config_path) do
      {:ok, config} ->
        registry = registry_for_image(image)
        resolve_from_config(config, registry)

      :error ->
        nil
    end
  end

  @doc """
  Returns the registry key that should be used for looking up credentials
  for the given `image` (Docker config convention).

  Unnamespaced or explicitly `docker.io`-hosted images resolve to
  `https://index.docker.io/v1/`; everything else resolves to the registry
  host component of the image reference.

  ## Examples

      iex> TestcontainerEx.Engine.Auth.registry_for_image("nginx")
      "https://index.docker.io/v1/"

      iex> TestcontainerEx.Engine.Auth.registry_for_image("library/nginx")
      "https://index.docker.io/v1/"

      iex> TestcontainerEx.Engine.Auth.registry_for_image("docker.io/library/nginx")
      "https://index.docker.io/v1/"

      iex> TestcontainerEx.Engine.Auth.registry_for_image("quay.io/org/image")
      "quay.io"

      iex> TestcontainerEx.Engine.Auth.registry_for_image("ghcr.io/org/image")
      "ghcr.io"

      iex> TestcontainerEx.Engine.Auth.registry_for_image("gcr.io/project/image")
      "gcr.io"

      iex> TestcontainerEx.Engine.Auth.registry_for_image("registry.gitlab.com/org/image")
      "registry.gitlab.com"

      iex> TestcontainerEx.Engine.Auth.registry_for_image("myregistry:5000/image")
      "myregistry:5000"
  """
  @spec registry_for_image(String.t()) :: String.t()
  def registry_for_image(image) when is_binary(image) do
    case String.split(image, "/", parts: 2) do
      [_single] ->
        @docker_hub_key

      [maybe_host, _rest] ->
        registry_from_host_component(maybe_host)
    end
  end

  defp registry_from_host_component(component) do
    cond do
      not host?(component) ->
        @docker_hub_key

      component in ["docker.io", "index.docker.io"] ->
        @docker_hub_key

      true ->
        component
    end
  end

  # A registry host contains a "." or ":" or is exactly "localhost".
  defp host?(component) do
    component == "localhost" or String.contains?(component, ".") or
      String.contains?(component, ":")
  end

  defp read_config(nil), do: read_config(default_config_path())

  defp read_config(path) when is_binary(path) do
    with {:ok, contents} <- File.read(path),
         {:ok, decoded} <- Jason.decode(contents) do
      {:ok, decoded}
    else
      {:error, reason} ->
        Logger.debug(
          "TestcontainerEx.Engine.Auth: could not read Docker config at #{path}: #{inspect(reason)}"
        )

        :error
    end
  end

  defp default_config_path do
    case System.get_env("DOCKER_CONFIG") do
      nil -> Path.join(System.user_home() || "", ".docker/config.json")
      "" -> Path.join(System.user_home() || "", ".docker/config.json")
      dir -> Path.join(dir, "config.json")
    end
  end

  defp resolve_from_config(config, registry) do
    auths = Map.get(config, "auths", %{})

    case find_auth_entry(auths, registry) do
      {matched_key, %{"auth" => encoded}} when is_binary(encoded) and encoded != "" ->
        build_header(encoded, matched_key)

      {_matched_key, _entry} ->
        maybe_warn_cred_helper(config, registry)
        nil

      :not_found ->
        maybe_warn_cred_helper(config, registry)
        nil
    end
  end

  defp find_auth_entry(auths, registry) when is_map(auths) do
    candidates = candidate_keys(registry)

    Enum.find_value(candidates, :not_found, fn key ->
      case Map.get(auths, key) do
        nil -> nil
        entry when is_map(entry) -> {key, entry}
        _ -> nil
      end
    end)
  end

  defp find_auth_entry(_auths, _registry), do: :not_found

  # Docker config.json keys are sometimes stored with scheme/path prefixes and
  # sometimes as plain hostnames. We try the most specific form first and fall
  # back to the bare host.
  @doc """
  Returns the list of candidate keys to try when looking up credentials
  for a given registry in the Docker config.json `auths` map.

  Docker config files may store registry keys in various formats (with or
  without scheme, with or without trailing slash). This function generates
  all plausible variants so that lookups succeed regardless of how the key
  was originally stored.

  ## Examples

      iex> TestcontainerEx.Engine.Auth.candidate_keys("quay.io")
      ["quay.io", "https://quay.io", "http://quay.io", "https://quay.io/", "http://quay.io/"]

      iex> TestcontainerEx.Engine.Auth.candidate_keys("https://index.docker.io/v1/")
      ["https://index.docker.io/v1/", "index.docker.io", "docker.io", "https://index.docker.io/v1", "https://index.docker.io", "https://docker.io"]
  """
  @spec candidate_keys(String.t()) :: [String.t()]
  def candidate_keys(@docker_hub_key) do
    [
      @docker_hub_key,
      "index.docker.io",
      "docker.io",
      "https://index.docker.io/v1",
      "https://index.docker.io",
      "https://docker.io"
    ]
  end

  def candidate_keys(registry) do
    # For known registries, try the registry name with various prefixes
    # For ECR-style registries (dkr.ecr.*.amazonaws.com), also try the full hostname
    base_candidates = [
      registry,
      "https://" <> registry,
      "http://" <> registry,
      "https://" <> registry <> "/",
      "http://" <> registry <> "/"
    ]

    # For registries with port (e.g., myregistry:5000), also try without scheme
    base_candidates =
      if String.contains?(registry, ":") do
        [registry | base_candidates]
      else
        base_candidates
      end

    # For known registries, also try the registry name as-is first
    base_candidates =
      if registry in @known_registries do
        [registry | base_candidates]
      else
        base_candidates
      end

    Enum.uniq(base_candidates)
  end

  defp build_header(encoded, server_address) do
    with {:ok, decoded} <- Base.decode64(encoded),
         [username, password] <- String.split(decoded, ":", parts: 2) do
      payload = %{
        "username" => username,
        "password" => password,
        "serveraddress" => normalize_server_address(server_address)
      }

      payload
      |> Jason.encode!()
      |> Base.url_encode64(padding: false)
    else
      _ ->
        Logger.debug(
          "TestcontainerEx.Engine.Auth: could not decode auth entry for #{server_address}"
        )

        nil
    end
  end

  # Docker config.json keys are often stored as URLs (e.g.
  # "https://index.docker.io/v1/") but the Docker Engine API's
  # `serveraddress` field expects a bare domain/IP (optionally with port) —
  # podman in particular rejects a full URL with HTTP 400.
  @doc false
  @spec normalize_server_address(String.t()) :: String.t()
  def normalize_server_address(address) when is_binary(address) do
    address
    |> strip_scheme()
    |> strip_trailing_path()
    |> canonicalize_docker_hub()
  end

  defp strip_scheme(address) do
    case String.split(address, "://", parts: 2) do
      [_scheme, rest] -> rest
      [single] -> single
    end
  end

  defp strip_trailing_path(address) do
    address
    |> String.split("/", parts: 2)
    |> List.first()
  end

  defp canonicalize_docker_hub("index.docker.io"), do: "docker.io"
  defp canonicalize_docker_hub(host), do: host

  defp maybe_warn_cred_helper(config, registry) do
    cond do
      Map.has_key?(config, "credsStore") ->
        Logger.debug(
          "TestcontainerEx.Engine.Auth: credsStore present in Docker config; " <>
            "credential helpers are not supported, returning nil for #{registry}"
        )

      is_map(Map.get(config, "credHelpers")) and
          Map.has_key?(config["credHelpers"], registry) ->
        Logger.debug(
          "TestcontainerEx.Engine.Auth: credHelpers entry for #{registry} present; " <>
            "credential helpers are not supported, returning nil"
        )

      true ->
        :ok
    end
  end
end
