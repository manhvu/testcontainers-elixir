# SPDX-License-Identifier: MIT
defmodule TestcontainerEx.Engine.Api do
  @moduledoc """
  Internal Docker API client. All functions require a Req connection.
  """

  alias TestcontainerEx.Container.Config
  alias TestcontainerEx.Util.Constants

  # ── Container operations ──────────────────────────────────────────

  def get_container(container_id, conn) when is_binary(container_id) do
    case get(conn, "/containers/#{container_id}/json") do
      {:ok, %{status: 200, body: body}} ->
        {:ok, from_container_inspect(parse_body(body))}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:ok, body} when is_map(body) ->
        {:error, {:failed_to_get_container, body}}

      {:error, %Req.Response{status: other}} ->
        {:error, {:http_error, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_container_by_hash(hash, conn) do
    filters =
      Jason.encode!(%{
        "label" => ["#{Constants.container_reuse_hash_label()}=#{hash}"]
      })

    case get(conn, "/containers/json?filters=#{URI.encode_www_form(filters)}") do
      {:ok, %{status: 200, body: body}} ->
        case parse_body(body) do
          [] -> {:error, :no_container}
          [container | _] -> get_container(container["Id"], conn)
          _ -> {:error, :no_container}
        end

      {:ok, %{body: body}} when is_map(body) ->
        {:error, {:failed_to_get_container, body}}

      {:error, %Req.Response{status: other}} ->
        {:error, {:http_error, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def create_container(%Config{} = container, conn) do
    body = container_create_request(container)
    query = if container.name, do: "?name=#{URI.encode_www_form(container.name)}", else: ""

    case post(conn, "/containers/create#{query}", body) do
      {:ok, %{status: 201, body: body}} ->
        case parse_body(body) do
          %{"Id" => id} -> {:ok, id}
          _ -> {:error, {:failed_to_create_container, body}}
        end

      {:ok, %{status: 200, body: body}} ->
        case parse_body(body) do
          %{"Id" => id} -> {:ok, id}
          _ -> {:error, {:failed_to_create_container, body}}
        end

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:ok, %{body: body}} when is_map(body) ->
        {:error, {:failed_to_create_container, body}}

      {:error, %Req.Response{status: other}} ->
        {:error, {:http_error, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def start_container(id, conn) when is_binary(id) do
    case post(conn, "/containers/#{id}/start", nil) do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, %{status: 204}} ->
        :ok

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:ok, %{body: body}} when is_map(body) ->
        {:error, {:failed_to_start_container, body}}

      {:error, %Req.Response{status: other}} ->
        {:error, {:http_error, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def stop_container(container_id, conn) when is_binary(container_id) do
    case delete(conn, "/containers/#{container_id}?force=true") do
      {:ok, %{status: status}} when status in [200, 204] ->
        :ok

      {:ok, %{status: 404}} ->
        # Container already removed
        :ok

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def put_file(container_id, conn, path, file_name, file_contents) do
    with {:ok, tar} <- create_tar(file_name, file_contents) do
      put_raw(conn, "/containers/#{container_id}/archive?path=#{URI.encode_www_form(path)}", tar,
        headers: [{"content-type", "application/x-tar"}]
      )
    end
  end

  # ── Image operations ──────────────────────────────────────────────

  def pull_image(image, conn, opts \\ []) when is_binary(image) do
    auth = Keyword.get(opts, :auth, nil)
    headers = if auth, do: [{"x-registry-auth", auth}], else: []

    query =
      "fromImage=#{URI.encode_www_form(image)}"

    case post(conn, "/images/create?#{query}", nil, headers: headers) do
      {:ok, %{status: 200}} ->
        {:ok, nil}

      # Docker returns NDJSON for image pulls; Req may fail
      # to decode the streaming body as a single JSON object. A 200 status
      # still means the pull succeeded.
      {:error, {Req, :decode, _}} ->
        {:ok, nil}

      {:error, %Jason.DecodeError{}} ->
        {:ok, nil}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, %Req.Response{status: other}} ->
        {:error, {:http_error, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def image_exists?(image, conn) when is_binary(image) do
    case get(conn, "/images/#{image}/json") do
      {:ok, %{status: 200}} ->
        {:ok, true}

      {:ok, %{status: 404}} ->
        {:ok, false}

      {:ok, %{status: 500}} ->
        {:error, {:http_error, 500}}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, %Req.Response{status: 404}} ->
        {:ok, false}

      {:error, %Req.Response{status: 500}} ->
        {:error, {:http_error, 500}}

      {:error, %Req.Response{status: other}} ->
        {:error, {:http_error, other}}

      {:error, _reason} ->
        {:ok, false}
    end
  end

  def delete_image(image, conn) when is_binary(image) do
    case delete(conn, "/images/#{image}?force=true") do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, _} = error -> error
    end
  end

  def tag_image(image, repo, tag, conn) do
    query = "repo=#{URI.encode_www_form(repo)}&tag=#{URI.encode_www_form(tag)}"

    case post(conn, "/images/#{image}/tag?#{query}", nil) do
      {:ok, %{status: 201}} ->
        {:ok, "#{repo}:#{tag}"}

      {:ok, %{status: 200}} ->
        {:ok, "#{repo}:#{tag}"}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:ok, %{body: %{"message" => msg}}} ->
        {:error, msg}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── Exec operations ───────────────────────────────────────────────

  def inspect_exec(exec_id, conn) do
    case get(conn, "/exec/#{exec_id}/json") do
      {:ok, %{status: 200, body: body}} ->
        parsed = parse_body(body)
        {:ok, %{running: parsed["Running"], exit_code: parsed["ExitCode"]}}

      {:ok, %{body: %{"message" => msg}}} ->
        {:error, msg}

      {:error, msg} ->
        {:error, msg}
    end
  end

  def start_exec(container_id, command, conn) do
    with {:ok, exec_id} <- create_exec(container_id, command, conn),
         :ok <- do_start_exec(exec_id, conn) do
      {:ok, exec_id}
    end
  end

  def logs(container_id, conn, opts \\ []) when is_binary(container_id) do
    stdout? = Keyword.get(opts, :stdout, true)
    stderr? = Keyword.get(opts, :stderr, true)
    timestamps? = Keyword.get(opts, :timestamps, false)
    follow? = Keyword.get(opts, :follow, false)

    query_params = [
      {"stdout", bool_query(stdout?)},
      {"stderr", bool_query(stderr?)},
      {"timestamps", bool_query(timestamps?)},
      {"follow", bool_query(follow?)}
    ]

    query_params =
      opts
      |> Keyword.take([:tail, :since, :until_time])
      |> Enum.reduce(query_params, fn
        {:tail, value}, acc -> [{"tail", to_string(value)} | acc]
        {:since, value}, acc -> [{"since", to_string(value)} | acc]
        {:until_time, value}, acc -> [{"until", to_string(value)} | acc]
        _, acc -> acc
      end)

    query = URI.encode_query(query_params)

    case get(conn, "/containers/#{container_id}/logs?#{query}") do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        {:ok, parse_log_body(body, stdout?: stdout?, stderr?: stderr?)}

      {:ok, %{body: %{"message" => msg}}} ->
        {:error, msg}

      {:ok, %{body: body}} ->
        {:error, {:failed_to_get_container_logs, body}}

      {:error, %Req.Response{status: other}} ->
        {:error, {:http_error, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def stdout_logs(container_id, conn) do
    case logs(container_id, conn, stderr: false) do
      {:ok, %{stdout: stdout}} -> {:ok, stdout}
      error -> error
    end
  end

  def stderr_logs(container_id, conn) do
    case logs(container_id, conn, stdout: false) do
      {:ok, %{stderr: stderr}} -> {:ok, stderr}
      error -> error
    end
  end

  @doc false
  def parse_log_body(body, opts \\ []) when is_binary(body) do
    stdout? = Keyword.get(opts, :stdout?, Keyword.get(opts, :stdout, true))
    stderr? = Keyword.get(opts, :stderr?, Keyword.get(opts, :stderr, true))

    case decode_log_frames(body) do
      {:ok, decoded} ->
        stdout = if(stdout?, do: decoded.stdout, else: "")
        stderr = if(stderr?, do: decoded.stderr, else: "")
        %{stdout: stdout, stderr: stderr}

      :raw ->
        if stdout?, do: %{stdout: body, stderr: ""}, else: %{stdout: "", stderr: body}
    end
  end

  defp decode_log_frames(body), do: collect_log_frames(body, %{stdout: "", stderr: ""})

  defp collect_log_frames(<<>>, acc), do: {:ok, acc}

  defp collect_log_frames(
         <<type::8, _stream::24, size::32, payload::binary-size(size), rest::binary>>,
         acc
       )
       when type in [1, 2] do
    acc =
      case type do
        1 -> %{acc | stdout: acc.stdout <> payload}
        2 -> %{acc | stderr: acc.stderr <> payload}
      end

    collect_log_frames(rest, acc)
  end

  defp collect_log_frames(_body, _acc), do: :raw

  defp bool_query(true), do: "true"
  defp bool_query(false), do: "false"

  # ── Network operations ────────────────────────────────────────────

  def get_bridge_gateway(conn) do
    case get(conn, "/networks/bridge") do
      {:ok, %{status: 200, body: body}} ->
        with {:ok, config} <- parse_bridge_gateway_config(body),
             {:ok, gateway} <- first_gateway(config) do
          {:ok, gateway}
        else
          _ -> {:error, :no_gateway}
        end

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_bridge_gateway_config(body) do
    case parse_body(body) do
      %{"IPAM" => %{"Config" => config}} when is_list(config) -> {:ok, config}
      _ -> :error
    end
  end

  defp first_gateway(config) do
    config
    |> Enum.find_value(fn
      %{"Gateway" => gateway} when is_binary(gateway) and gateway != "" -> {:ok, gateway}
      _ -> nil
    end)
    |> case do
      nil -> :error
      gateway -> gateway
    end
  end

  def create_network(name, conn, opts \\ []) when is_binary(name) do
    body = %{
      "Name" => name,
      "Driver" => Keyword.get(opts, :driver, "bridge"),
      "CheckDuplicate" => true,
      "Labels" => Keyword.get(opts, :labels, %{})
    }

    case post(conn, "/networks/create", body) do
      {:ok, %{status: status, body: body}} when status in [200, 201] ->
        extract_network_id(body)

      {:ok, %{status: 409}} ->
        {:ok, :already_exists}

      {:ok, %{body: %{"message" => msg}}} ->
        {:error, {:failed_to_create_network, msg}}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, %Req.Response{status: 409}} ->
        {:ok, :already_exists}

      {:error, %Req.Response{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_network_id(body) do
    case parse_body(body) do
      %{"Id" => id} -> {:ok, id}
      _ -> {:error, {:failed_to_create_network, body}}
    end
  end

  def remove_network(name, conn) when is_binary(name) do
    case delete(conn, "/networks/#{name}") do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, %{status: 204}} ->
        :ok

      {:ok, %{status: 404}} ->
        {:error, :network_not_found}

      {:ok, %{body: %{"message" => msg}}} ->
        {:error, {:failed_to_remove_network, msg}}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, %Req.Response{status: 404}} ->
        {:error, :network_not_found}

      {:error, %Req.Response{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def network_exists?(name, conn) when is_binary(name) do
    case get(conn, "/networks/#{name}") do
      {:ok, %{status: 200}} -> true
      _ -> false
    end
  end

  # ── Response mapping ──────────────────────────────────────────────

  defp from_container_inspect(%{"ExecIDs" => nil} = inspect) do
    from_container_inspect(%{inspect | "ExecIDs" => []})
  end

  # With Name and full NetworkSettings
  defp from_container_inspect(%{
         "Id" => id,
         "Image" => image,
         "Name" => name,
         "NetworkSettings" => %{"IPAddress" => ip, "Ports" => ports, "Networks" => networks},
         "Config" => %{"Env" => env, "Labels" => labels}
       }) do
    %Config{
      container_id: id,
      image: image,
      name: parse_container_name(name),
      labels: labels,
      ip_address: resolve_ip(ip, networks),
      exposed_ports: map_ports(ports),
      environment: parse_env(env)
    }
  end

  # With Name and NetworkSettings without Networks
  defp from_container_inspect(%{
         "Id" => id,
         "Image" => image,
         "Name" => name,
         "NetworkSettings" => %{"IPAddress" => ip, "Ports" => ports},
         "Config" => %{"Env" => env, "Labels" => labels}
       }) do
    %Config{
      container_id: id,
      image: image,
      name: parse_container_name(name),
      labels: labels,
      ip_address: ip,
      exposed_ports: map_ports(ports),
      environment: parse_env(env)
    }
  end

  # With Name and network_settings as a map (no guaranteed keys)
  defp from_container_inspect(%{
         "Id" => id,
         "Image" => image,
         "Name" => name,
         "NetworkSettings" => network_settings,
         "Config" => %{"Env" => env, "Labels" => labels}
       }) do
    ip = Map.get(network_settings, "IPAddress")
    ports = Map.get(network_settings, "Ports") || %{}
    networks = Map.get(network_settings, "Networks") || %{}

    %Config{
      container_id: id,
      image: image,
      name: parse_container_name(name),
      labels: labels,
      ip_address: resolve_ip(ip, networks),
      exposed_ports: map_ports(ports),
      environment: parse_env(env)
    }
  end

  # Without Name — fallback clauses for backward compatibility

  defp from_container_inspect(%{
         "Id" => id,
         "Image" => image,
         "NetworkSettings" => %{"IPAddress" => ip, "Ports" => ports, "Networks" => networks},
         "Config" => %{"Env" => env, "Labels" => labels}
       }) do
    %Config{
      container_id: id,
      image: image,
      labels: labels,
      ip_address: resolve_ip(ip, networks),
      exposed_ports: map_ports(ports),
      environment: parse_env(env)
    }
  end

  defp from_container_inspect(%{
         "Id" => id,
         "Image" => image,
         "NetworkSettings" => %{"IPAddress" => ip, "Ports" => ports},
         "Config" => %{"Env" => env, "Labels" => labels}
       }) do
    %Config{
      container_id: id,
      image: image,
      labels: labels,
      ip_address: ip,
      exposed_ports: map_ports(ports),
      environment: parse_env(env)
    }
  end

  defp from_container_inspect(%{
         "Id" => id,
         "Image" => image,
         "NetworkSettings" => network_settings,
         "Config" => %{"Env" => env, "Labels" => labels}
       }) do
    ip = Map.get(network_settings, "IPAddress")
    ports = Map.get(network_settings, "Ports") || %{}
    networks = Map.get(network_settings, "Networks") || %{}

    %Config{
      container_id: id,
      image: image,
      labels: labels,
      ip_address: resolve_ip(ip, networks),
      exposed_ports: map_ports(ports),
      environment: parse_env(env)
    }
  end

  defp from_container_inspect(%{
         "Id" => id,
         "Image" => image,
         "Config" => %{"Env" => env, "Labels" => labels}
       }) do
    %Config{
      container_id: id,
      image: image,
      labels: labels,
      ip_address: nil,
      exposed_ports: [],
      environment: parse_env(env)
    }
  end

  # Docker returns names with a leading "/" prefix, e.g. "/my-container".
  # Strip it for consistency.
  defp parse_container_name("/" <> name), do: name
  defp parse_container_name(name), do: name

  # ── Private helpers ───────────────────────────────────────────────

  defp container_create_request(%Config{} = cfg) do
    base_container_request(cfg)
    |> maybe_put_networking_config(cfg)
  end

  defp maybe_put_networking_config(request, %Config{network: nil}), do: request

  defp maybe_put_networking_config(request, %Config{network: network}) do
    Map.put(request, "NetworkingConfig", %{"EndpointsConfig" => %{network => %{}}})
  end

  defp base_container_request(%Config{} = cfg) do
    %{
      "Image" => cfg.image,
      "Cmd" => cfg.cmd,
      "ExposedPorts" => map_exposed_ports(cfg),
      "Env" => map_env(cfg.environment),
      "Labels" => cfg.labels,
      "Hostname" => cfg.hostname,
      "Domainname" => cfg.domainname,
      "User" => cfg.user,
      "WorkingDir" => cfg.working_dir,
      "StopSignal" => cfg.stop_signal,
      "HostConfig" => host_config(cfg)
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp host_config(%Config{} = cfg) do
    %{
      "AutoRemove" => cfg.auto_remove,
      "PortBindings" => map_port_bindings(cfg),
      "Privileged" => cfg.privileged,
      "Binds" => map_binds(cfg),
      "Mounts" => map_volumes(cfg),
      "NetworkMode" => cfg.network_mode || cfg.network,
      "Memory" => cfg.memory,
      "NanoCpus" => cfg.nano_cpus,
      "RestartPolicy" => format_restart_policy(cfg.restart_policy),
      "Dns" => if(cfg.dns == [], do: nil, else: cfg.dns),
      "ExtraHosts" => format_extra_hosts(cfg.extra_hosts),
      "StopTimeout" => cfg.stop_timeout
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp format_restart_policy(nil), do: nil
  defp format_restart_policy(policy) when is_binary(policy), do: %{"Name" => policy}

  defp format_extra_hosts([]), do: nil
  defp format_extra_hosts(hosts), do: Enum.map(hosts, fn {h, ip} -> "#{h}:#{ip}" end)

  defp map_exposed_ports(%Config{exposed_ports: ports}) do
    Enum.map(ports, fn {port, _} -> {to_string(port), %{}} end) |> Enum.into(%{})
  end

  defp map_env(nil), do: []

  # Convert Config.environment (map) to Docker API format (list of "KEY=STRING" strings)
  defp map_env(env) when is_map(env) do
    Enum.map(env, fn
      {key, value} when is_binary(key) ->
        "#{key}=#{value}"

      {key, value} when is_atom(key) ->
        "#{key}=#{value}"

      {key, value} ->
        "#{key}=#{value}"
    end)
  end

  # Parse Docker API response (list of "KEY=STRING" strings) into a keyword list
  defp parse_env(nil), do: []

  defp parse_env(env) when is_list(env) do
    Enum.map(env, fn
      str when is_binary(str) ->
        case String.split(str, "=", parts: 2) do
          [key, value] -> {String.to_atom(key), value}
          [key] -> {String.to_atom(key), ""}
        end

      {key, value} when is_binary(key) ->
        {String.to_atom(key), to_string(value)}

      other ->
        {to_string(other), ""}
    end)
  end

  defp map_port_bindings(%Config{exposed_ports: ports}) do
    Enum.map(ports, fn
      {port, nil} -> {"#{port}/tcp", [%{"HostIp" => "0.0.0.0", "HostPort" => ""}]}
      {port, host} -> {"#{port}/tcp", [%{"HostIp" => "0.0.0.0", "HostPort" => to_string(host)}]}
    end)
    |> Enum.into(%{})
  end

  defp map_binds(%Config{bind_mounts: mounts}) do
    Enum.map(mounts, &"#{&1.host_src}:#{&1.container_dest}:#{&1.options}")
  end

  defp map_volumes(%Config{bind_volumes: volumes}) do
    Enum.map(
      volumes,
      &%{
        "Target" => &1.container_dest,
        "Source" => &1.volume,
        "Type" => "volume",
        "ReadOnly" => &1.read_only
      }
    )
  end

  defp map_ports(nil), do: []

  defp map_ports(ports) do
    Enum.reduce(ports, [], fn {key, mappings}, acc ->
      acc ++
        Enum.map(mappings || [], fn %{"HostPort" => hp} ->
          {String.replace(key, "/tcp", "") |> String.to_integer(), String.to_integer(hp)}
        end)
    end)
  end

  defp resolve_ip(nil, networks), do: get_ip_from_networks(networks)
  defp resolve_ip("", networks), do: get_ip_from_networks(networks)
  defp resolve_ip(ip, _) when is_binary(ip) and ip != "", do: ip

  defp get_ip_from_networks(nil), do: nil

  defp get_ip_from_networks(networks) when is_map(networks) do
    Enum.find_value(networks, fn
      {_name, %{"IPAddress" => ip}} when is_binary(ip) and ip != "" -> ip
      _ -> nil
    end)
  end

  defp create_tar(file_name, contents) do
    tar_path =
      Path.join(
        System.tmp_dir!(),
        "#{:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)}-#{file_name}.tar"
      )

    :ok = :erl_tar.create(tar_path, [{String.to_charlist(file_name), contents}], [:compressed])

    with {:ok, data} <- File.read(tar_path),
         :ok <- File.rm(tar_path) do
      {:ok, data}
    end
  end

  def create_exec(container_id, command, conn) do
    body = %{"Cmd" => command}

    case post(conn, "/containers/#{container_id}/exec", body) do
      {:ok, %{status: status, body: body}} when status in [200, 201] ->
        case parse_body(body) do
          %{"Id" => id} -> {:ok, id}
          _ -> {:error, {:failed_to_create_exec, body}}
        end

      {:ok, %{body: %{"message" => msg}}} ->
        {:error, msg}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, msg} ->
        {:error, msg}
    end
  end

  defp do_start_exec(exec_id, conn) do
    body = %{"Detach" => true}

    case post(conn, "/exec/#{exec_id}/start", body) do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, %{status: s}} ->
        {:error, {:http_error, s}}

      {:ok, %{body: %{"message" => msg}}} ->
        {:error, msg}

      {:error, msg} ->
        {:error, msg}
    end
  end

  # ── HTTP helpers ──────────────────────────────────────────────────

  defp get(conn, path) do
    Req.get(conn, url: path)
  end

  defp post(conn, path, body, opts \\ []) do
    body = encode_body(body)
    headers = Keyword.get(opts, :headers, [])

    options =
      if body == nil do
        [url: path, headers: headers]
      else
        [url: path, body: body, headers: headers ++ [{"content-type", "application/json"}]]
      end

    Req.post(conn, options)
  end

  defp encode_body(nil), do: nil
  defp encode_body(body) when is_map(body), do: Jason.encode!(body)
  defp encode_body(body) when is_list(body), do: Jason.encode!(body)
  defp encode_body(body), do: body

  defp put_raw(conn, path, body, opts) do
    headers = Keyword.get(opts, :headers, [])
    Req.put(conn, url: path, body: body, headers: headers)
  end

  defp delete(conn, path) do
    Req.delete(conn, url: path)
  end

  # ── Body parsing ─────────────────────────────────────────────────

  defp parse_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, parsed} -> parsed
      {:error, _} -> body
    end
  end

  defp parse_body(body) when is_map(body), do: body
  defp parse_body(body) when is_list(body), do: body
  defp parse_body(_body), do: %{}
end
