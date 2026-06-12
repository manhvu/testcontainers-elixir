# SPDX-License-Identifier: MIT
defmodule TestcontainerEx.Docker.Status do
  @moduledoc """
  Query runtime status of container engines (Docker, Podman, Minikube, Colima)
  directly via their APIs or CLI.

  Each function returns a normalized status map that downstream libraries can
  consume without needing to know the specifics of each engine.

  ## Status map format

      %{
        engine: :docker | :podman | :minikube | :colima,
        running: boolean(),
        version: String.t() | nil,
        api_version: String.t() | nil,
        os: String.t() | nil,
        arch: String.t() | nil,
        cpus: integer() | nil,
        memory_bytes: integer() | nil,
        hostname: String.t() | nil,
        kernel_version: String.t() | nil,
        storage_driver: String.t() | nil,
        logging_driver: String.t() | nil,
        cgroup_driver: String.t() | nil,
        cgroup_version: String.t() | nil,
        plugins: [String.t()],
        registries: [String.t()],
        server_time: DateTime.t() | nil,
        labels: %{String.t() => String.t()},
        experimental: boolean(),
        raw: map() | nil
      }

  ## Usage

      # Quick check — is any container engine reachable?
      TestcontainerEx.Docker.Status.reachable?()
      # => true

      # Full status of the detected engine
      TestcontainerEx.Docker.Status.status()
      # => %{engine: :docker, running: true, version: "27.0.3", ...}

      # Query a specific engine
      TestcontainerEx.Docker.Status.status(:podman)
      # => %{engine: :podman, running: true, ...}

      # Engine-specific details
      TestcontainerEx.Docker.Status.colima_status()
      # => %{running: true, profile: "default", cpu: 2, memory: 4294967296, ...}

      TestcontainerEx.Docker.Status.minikube_status()
      # => %{running: true, profile: "minikube", cpus: 2, memory: 4096, ...}
  """

  alias TestcontainerEx.Connection.Url

  @type engine :: :docker | :podman | :minikube | :colima
  @type status_map :: %{
          engine: engine(),
          running: boolean(),
          version: String.t() | nil,
          api_version: String.t() | nil,
          os: String.t() | nil,
          arch: String.t() | nil,
          cpus: integer() | nil,
          memory_bytes: integer() | nil,
          hostname: String.t() | nil,
          kernel_version: String.t() | nil,
          storage_driver: String.t() | nil,
          logging_driver: String.t() | nil,
          cgroup_driver: String.t() | nil,
          cgroup_version: String.t() | nil,
          plugins: [String.t()],
          registries: [String.t()],
          server_time: DateTime.t() | nil,
          labels: %{String.t() => String.t()},
          experimental: boolean(),
          raw: map() | nil
        }

  # ── Public API ────────────────────────────────────────────────────

  @doc """
  Returns `true` if any container engine (Docker, Podman, Minikube, Colima)
  is reachable and responding to API calls.
  """
  @spec reachable?() :: boolean()
  def reachable? do
    case status() do
      %{running: true} -> true
      _ -> false
    end
  end

  @doc """
  Returns a normalized status map for the given engine, or the auto-detected
  engine when no argument is passed.

  Returns `%{engine: nil, running: false}` when the engine is not available.
  """
  @spec status(engine() | nil) :: status_map()
  def status(engine \\ nil)

  def status(nil) do
    engine = TestcontainerEx.Docker.Engine.detect()
    status(engine)
  end

  def status(:colima) do
    from_colima()
  end

  def status(:minikube) do
    from_minikube()
  end

  def status(:podman) do
    from_engine(:podman)
  end

  def status(:docker) do
    from_engine(:docker)
  end

  @doc """
  Returns detailed Colima status by querying the `colima` CLI.

  Returns a map with Colima-specific fields:

      %{
        running: boolean(),
        profile: String.t(),
        colima_version: String.t() | nil,
        socket_path: String.t() | nil,
        kubernetes: boolean(),
        cpu: integer() | nil,
        memory_bytes: integer() | nil,
        disk_bytes: integer() | nil,
        arch: String.t() | nil,
        runtime: String.t() | nil,
        network_address: String.t() | nil,
        raw: String.t()
      }
  """
  @spec colima_status() :: map()
  def colima_status do
    with {:ok, output} <- exec_cmd("colima", ["status", "--output", "json"]),
         {:ok, parsed} <- Jason.decode(output) do
      parse_colima_json(parsed)
    else
      {:error, :not_installed} ->
        %{running: false, error: :colima_not_installed}

      {:error, :not_running} ->
        %{running: false, error: :colima_not_running}

      {:error, reason} ->
        %{running: false, error: reason}
    end
  end

  @doc """
  Returns detailed Minikube status by querying the `minikube` CLI.

  Returns a map with Minikube-specific fields:

      %{
        running: boolean(),
        profile: String.t(),
        minikube_version: String.t() | nil,
        cpus: integer() | nil,
        memory_mb: integer() | nil,
        disk_mb: integer() | nil,
        driver: String.t() | nil,
        container_runtime: String() | nil,
        kubernetes_version: String.t() | nil,
        apiserver: boolean(),
        raw: map()
      }
  """
  @spec minikube_status() :: map()
  def minikube_status do
    with {:ok, output} <- exec_cmd("minikube", ["status", "--output", "json"]),
         {:ok, parsed} <- Jason.decode(output) do
      parse_minikube_json(parsed)
    else
      {:error, :not_installed} ->
        %{running: false, error: :minikube_not_installed}

      {:error, :not_running} ->
        %{running: false, error: :minikube_not_running}

      {:error, reason} ->
        %{running: false, error: reason}
    end
  end

  @doc """
  Returns Docker daemon info by querying the Docker Engine API `/info` endpoint.

  This works for Docker and Podman (which both implement the Docker Engine API).
  """
  @spec engine_info(String.t() | nil) :: {:ok, map()} | {:error, term()}
  def engine_info(base_url \\ nil) do
    url = base_url || default_engine_url()
    client = Req.new()

    case Req.get(client, url: "#{url}/_ping") do
      {:ok, %{status: 200}} ->
        case Req.get(client, url: "#{url}/info") do
          {:ok, %{status: 200, body: body}} when is_binary(body) ->
            case Jason.decode(body) do
              {:ok, parsed} -> {:ok, parsed}
              {:error, reason} -> {:error, {:json_decode, reason}}
            end

          {:ok, %{status: status}} ->
            {:error, {:http_error, status}}

          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        {:error, :engine_not_reachable}
    end
  end

  @doc """
  Returns the Docker Engine API version by querying the `/version` endpoint.
  """
  @spec engine_version(String.t() | nil) :: {:ok, map()} | {:error, term()}
  def engine_version(base_url \\ nil) do
    url = base_url || default_engine_url()
    client = Req.new()

    case Req.get(client, url: "#{url}/version") do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, parsed} -> {:ok, parsed}
          {:error, reason} -> {:error, {:json_decode, reason}}
        end

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Lists all containers via the Docker Engine API.

  Options:
    * `:all` — include stopped containers (default: `false`)
    * `:limit` — maximum number of containers to return
    * `:filters` — map of label filters
  """
  @spec list_containers(keyword(), String.t() | nil) :: {:ok, [map()]} | {:error, term()}
  def list_containers(opts \\ [], base_url \\ nil) do
    url = base_url || default_engine_url()
    client = Req.new()

    query =
      [
        {"all", to_string(Keyword.get(opts, :all, false))},
        {"limit", if(l = Keyword.get(opts, :limit), do: to_string(l), else: "")},
        {"filters", encode_filters(Keyword.get(opts, :filters, %{}))}
      ]
      |> Enum.reject(fn {_, v} -> v == "" end)
      |> URI.encode_query()

    case Req.get(client, url: "#{url}/containers/json?#{query}") do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, parsed} -> {:ok, parsed}
          {:error, reason} -> {:error, {:json_decode, reason}}
        end

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Lists all images via the Docker Engine API.

  Options:
    * `:all` — include intermediate images (default: `false`)
    * `:filters` — map of filters
  """
  @spec list_images(keyword(), String.t() | nil) :: {:ok, [map()]} | {:error, term()}
  def list_images(opts \\ [], base_url \\ nil) do
    url = base_url || default_engine_url()
    client = Req.new()

    query =
      [
        {"all", to_string(Keyword.get(opts, :all, false))},
        {"filters", encode_filters(Keyword.get(opts, :filters, %{}))}
      ]
      |> Enum.reject(fn {_, v} -> v == "" end)
      |> URI.encode_query()

    case Req.get(client, url: "#{url}/images/json?#{query}") do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, parsed} -> {:ok, parsed}
          {:error, reason} -> {:error, {:json_decode, reason}}
        end

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Lists all networks via the Docker Engine API.
  """
  @spec list_networks(String.t() | nil) :: {:ok, [map()]} | {:error, term()}
  def list_networks(base_url \\ nil) do
    url = base_url || default_engine_url()
    client = Req.new()

    case Req.get(client, url: "#{url}/networks") do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, parsed} -> {:ok, parsed}
          {:error, reason} -> {:error, {:json_decode, reason}}
        end

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Lists all volumes via the Docker Engine API.
  """
  @spec list_volumes(String.t() | nil) :: {:ok, map()} | {:error, term()}
  def list_volumes(base_url \\ nil) do
    url = base_url || default_engine_url()
    client = Req.new()

    case Req.get(client, url: "#{url}/volumes") do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, parsed} -> {:ok, parsed}
          {:error, reason} -> {:error, {:json_decode, reason}}
        end

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Returns disk usage summary via the Docker Engine API `/system/df` endpoint.
  """
  @spec disk_usage(String.t() | nil) :: {:ok, map()} | {:error, term()}
  def disk_usage(base_url \\ nil) do
    url = base_url || default_engine_url()
    client = Req.new()

    case Req.get(client, url: "#{url}/system/df") do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, parsed} -> {:ok, parsed}
          {:error, reason} -> {:error, {:json_decode, reason}}
        end

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Pings the Docker Engine API to check if it is responsive.
  """
  @spec ping(String.t() | nil) :: :ok | {:error, term()}
  def ping(base_url \\ nil) do
    url = base_url || default_engine_url()
    client = Req.new()

    case Req.get(client, url: "#{url}/_ping") do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Returns the events stream from the Docker Engine API as a Req response.

  Options:
    * `:since` — show events since this timestamp
    * `:until` — show events until this timestamp
    * `:filters` — map of event filters

  Returns `{:ok, reference()}` on success.
  """
  @spec events(keyword(), String.t() | nil) :: {:ok, reference()} | {:error, term()}
  def events(opts \\ [], base_url \\ nil) do
    url = base_url || default_engine_url()
    client = Req.new()

    query =
      [
        {"since", if(s = Keyword.get(opts, :since), do: to_string(s), else: "")},
        {"until", if(u = Keyword.get(opts, :until), do: to_string(u), else: "")},
        {"filters", encode_filters(Keyword.get(opts, :filters, %{}))}
      ]
      |> Enum.reject(fn {_, v} -> v == "" end)
      |> URI.encode_query()

    stream_url = "#{url}/events?#{query}"

    case Req.get(client, url: stream_url, receive_timeout: :infinity) do
      {:ok, %{status: 200, body: body}} when is_reference(body) -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  # ── Private — Engine status builders ──────────────────────────────

  defp from_colima do
    colima = colima_status()

    if colima.running do
      base = %{
        engine: :colima,
        running: true,
        version: Map.get(colima, :colima_version),
        api_version: nil,
        os: nil,
        arch: Map.get(colima, :arch),
        cpus: Map.get(colima, :cpu),
        memory_bytes: Map.get(colima, :memory_bytes),
        hostname: nil,
        kernel_version: nil,
        storage_driver: nil,
        logging_driver: nil,
        cgroup_driver: nil,
        cgroup_version: nil,
        plugins: [],
        registries: [],
        server_time: nil,
        labels: %{},
        experimental: false,
        raw: colima
      }

      # Colima runs Docker/Podman underneath — try to get engine info too
      case colima_engine_info(Map.get(colima, :runtime, "docker")) do
        {:ok, info} -> merge_engine_info(base, info)
        _ -> base
      end
    else
      %{
        engine: :colima,
        running: false,
        version: nil,
        api_version: nil,
        os: nil,
        arch: nil,
        cpus: nil,
        memory_bytes: nil,
        hostname: nil,
        kernel_version: nil,
        storage_driver: nil,
        logging_driver: nil,
        cgroup_driver: nil,
        cgroup_version: nil,
        plugins: [],
        registries: [],
        server_time: nil,
        labels: %{},
        experimental: false,
        raw: colima
      }
    end
  end

  defp from_minikube do
    minikube = minikube_status()

    if minikube.running do
      base = %{
        engine: :minikube,
        running: true,
        version: Map.get(minikube, :minikube_version),
        api_version: nil,
        os: nil,
        arch: nil,
        cpus: Map.get(minikube, :cpus),
        memory_bytes: minikube_memory_bytes(minikube),
        hostname: nil,
        kernel_version: nil,
        storage_driver: nil,
        logging_driver: nil,
        cgroup_driver: nil,
        cgroup_version: nil,
        plugins: [],
        registries: [],
        server_time: nil,
        labels: %{},
        experimental: false,
        raw: minikube
      }

      # Minikube runs Docker underneath — try to get engine info
      case minikube_engine_url() do
        nil -> base
        url -> merge_engine_info(base, url)
      end
    else
      %{
        engine: :minikube,
        running: false,
        version: nil,
        api_version: nil,
        os: nil,
        arch: nil,
        cpus: nil,
        memory_bytes: nil,
        hostname: nil,
        kernel_version: nil,
        storage_driver: nil,
        logging_driver: nil,
        cgroup_driver: nil,
        cgroup_version: nil,
        plugins: [],
        registries: [],
        server_time: nil,
        labels: %{},
        experimental: false,
        raw: minikube
      }
    end
  end

  defp from_engine(engine) do
    case engine_info() do
      {:ok, info} ->
        now =
          case info["SystemTime"] do
            nil -> nil
            ts -> parse_iso8601(ts)
          end

        %{
          engine: engine,
          running: true,
          version: info["ServerVersion"] || info["Version"],
          api_version: info["ApiVersion"],
          os: info["OperatingSystem"] || info["OSType"],
          arch: info["Architecture"],
          cpus: info["NCPU"],
          memory_bytes: info["MemTotal"],
          hostname: info["Name"],
          kernel_version: info["KernelVersion"],
          storage_driver: info["Driver"],
          logging_driver: info["LoggingDriver"],
          cgroup_driver: info["CgroupDriver"],
          cgroup_version: info["CgroupVersion"],
          plugins: extract_plugins(info["Plugins"]),
          registries: extract_registries(info),
          server_time: now,
          labels: info["Labels"] || %{},
          experimental: info["ExperimentalBuild"] || false,
          raw: info
        }

      {:error, reason} ->
        %{
          engine: engine,
          running: false,
          version: nil,
          api_version: nil,
          os: nil,
          arch: nil,
          cpus: nil,
          memory_bytes: nil,
          hostname: nil,
          kernel_version: nil,
          storage_driver: nil,
          logging_driver: nil,
          cgroup_driver: nil,
          cgroup_version: nil,
          plugins: [],
          registries: [],
          server_time: nil,
          labels: %{},
          experimental: false,
          raw: %{error: reason}
        }
    end
  end

  # ── Private — Colima helpers ──────────────────────────────────────

  defp parse_colima_json(parsed) when is_map(parsed) do
    %{
      running: Map.get(parsed, "running", false),
      profile: Map.get(parsed, "profile", "default"),
      colima_version: Map.get(parsed, "colima_version"),
      socket_path: Map.get(parsed, "socket"),
      kubernetes: Map.get(parsed, "kubernetes", false),
      cpu: Map.get(parsed, "cpu"),
      memory_bytes: parse_bytes(Map.get(parsed, "memory")),
      disk_bytes: parse_bytes(Map.get(parsed, "disk")),
      arch: Map.get(parsed, "arch"),
      runtime: Map.get(parsed, "runtime", "docker"),
      network_address: Map.get(parsed, "network_address"),
      raw: parsed
    }
  end

  defp parse_colima_json(_), do: %{running: false, error: :invalid_json}

  defp colima_engine_info("docker") do
    colima = colima_status()

    case Map.get(colima, :socket_path) do
      nil -> {:error, :no_socket}
      path -> engine_info("unix://#{path}")
    end
  end

  defp colima_engine_info("containerd") do
    {:error, :containerd_no_docker_api}
  end

  defp colima_engine_info(_), do: {:error, :unknown_runtime}

  # ── Private — Minikube helpers ────────────────────────────────────

  defp parse_minikube_json(parsed) when is_map(parsed) do
    %{
      running: Map.get(parsed, "running", false),
      profile: Map.get(parsed, "profile", "minikube"),
      minikube_version: Map.get(parsed, "minikube_version"),
      cpus: Map.get(parsed, "cpus"),
      memory_mb: Map.get(parsed, "memory"),
      disk_mb: Map.get(parsed, "disk"),
      driver: Map.get(parsed, "driver"),
      container_runtime: Map.get(parsed, "container_runtime"),
      kubernetes_version: Map.get(parsed, "kubernetes_version"),
      apiserver: Map.get(parsed, "apiserver", false),
      raw: parsed
    }
  end

  defp parse_minikube_json(_), do: %{running: false, error: :invalid_json}

  defp minikube_memory_bytes(%{memory_mb: mb}) when is_integer(mb), do: mb * 1_048_576
  defp minikube_memory_bytes(_), do: nil

  defp minikube_engine_url do
    case System.cmd("minikube", ["docker-env", "--shell", "none"], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.find_value(fn
          "CONTAINER_ENGINE_HOST=" <> rest ->
            url = String.trim(rest) |> String.trim("\"")
            if url != "", do: url, else: nil

          "DOCKER_HOST=" <> rest ->
            url = String.trim(rest) |> String.trim("\"")
            if url != "", do: url, else: nil

          _ ->
            nil
        end)

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  # ── Private — Engine info merging ─────────────────────────────────

  defp merge_engine_info(base, info) when is_map(info) do
    now =
      case info["SystemTime"] do
        nil -> nil
        ts -> parse_iso8601(ts)
      end

    base
    |> Map.put(:version, info["ServerVersion"] || info["Version"] || base.version)
    |> Map.put(:api_version, info["ApiVersion"])
    |> Map.put(:os, info["OperatingSystem"] || info["OSType"])
    |> Map.put(:arch, info["Architecture"] || base.arch)
    |> Map.put(:cpus, info["NCPU"] || base.cpus)
    |> Map.put(:memory_bytes, info["MemTotal"] || base.memory_bytes)
    |> Map.put(:hostname, info["Name"])
    |> Map.put(:kernel_version, info["KernelVersion"])
    |> Map.put(:storage_driver, info["Driver"])
    |> Map.put(:logging_driver, info["LoggingDriver"])
    |> Map.put(:cgroup_driver, info["CgroupDriver"])
    |> Map.put(:cgroup_version, info["CgroupVersion"])
    |> Map.put(:plugins, extract_plugins(info["Plugins"]))
    |> Map.put(:registries, extract_registries(info))
    |> Map.put(:server_time, now)
    |> Map.put(:labels, info["Labels"] || %{})
    |> Map.put(:experimental, info["ExperimentalBuild"] || false)
  end

  defp merge_engine_info(base, url) when is_binary(url) do
    case engine_info(url) do
      {:ok, info} -> merge_engine_info(base, info)
      _ -> base
    end
  end

  # ── Private — Utilities ───────────────────────────────────────────

  defp default_engine_url do
    case {System.get_env("CONTAINER_ENGINE_HOST"), System.get_env("DOCKER_HOST")} do
      {nil, nil} -> "http://d"
      {url, _} when is_binary(url) and url != "" -> Url.construct(url)
      {_, url} when is_binary(url) and url != "" -> Url.construct(url)
      _ -> "http://d"
    end
  end

  defp exec_cmd(bin, args) do
    case System.find_executable(bin) do
      nil ->
        {:error, :not_installed}

      path ->
        case System.cmd(path, args, stderr_to_stdout: true) do
          {output, 0} -> {:ok, output}
          {_output, _} -> {:error, :not_running}
        end
    end
  rescue
    ErlangError -> {:error, :exec_failed}
  end

  defp encode_filters(filters) when map_size(filters) == 0, do: ""

  defp encode_filters(filters) do
    Jason.encode!(filters)
  end

  defp extract_plugins(nil), do: []

  defp extract_plugins(plugins) when is_map(plugins) do
    plugins
    |> Map.values()
    |> List.flatten()
    |> Enum.flat_map(fn
      p when is_map(p) ->
        case p["Name"] || p["name"] do
          nil -> []
          name -> [name]
        end

      _ ->
        []
    end)
    |> Enum.uniq()
  end

  defp extract_plugins(_), do: []

  defp extract_registries(info) do
    case info["RegistryConfig"] do
      nil -> []
      reg when is_map(reg) -> Map.get(reg, "IndexConfigs", []) |> Map.keys()
      _ -> []
    end
  end

  defp parse_bytes(nil), do: nil

  defp parse_bytes(bytes) when is_integer(bytes), do: bytes

  defp parse_bytes(bytes) when is_binary(bytes) do
    case Integer.parse(bytes) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_iso8601(ts) when is_binary(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end
end
