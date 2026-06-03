# SPDX-License-Identifier: MIT
defmodule TestcontainerEx.Docker.Api do
  @moduledoc """
  Internal Docker API client. All functions require a Tesla connection.
  """

  alias TestcontainerEx.Container.Config

  # ── Container operations ──────────────────────────────────────────

  def get_container(container_id, conn) when is_binary(container_id) do
    case get(conn, "/containers/#{container_id}/json") do
      {:ok, %{status: 200, body: body}} ->
        {:ok, from_container_inspect(parse_body(body))}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:ok, body} when is_map(body) ->
        {:error, {:failed_to_get_container, body}}

      {:error, %Tesla.Env{status: other}} ->
        {:error, {:http_error, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_container_by_hash(hash, conn) do
    filters =
      Jason.encode!(%{
        "label" => ["#{TestcontainerEx.Util.Constants.container_reuse_hash_label()}=#{hash}"]
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

      {:error, %Tesla.Env{status: other}} ->
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

      {:ok, %{body: body}} when is_map(body) ->
        {:error, {:failed_to_create_container, body}}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, %Tesla.Env{status: other}} ->
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

      {:ok, %{body: body}} when is_map(body) ->
        {:error, {:failed_to_start_container, body}}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, %Tesla.Env{status: other}} ->
        {:error, {:http_error, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def stop_container(container_id, conn) when is_binary(container_id) do
    with {:ok, %{status: 200}} <- delete(conn, "/containers/#{container_id}?force=true"),
         {:ok, %{status: 200}} <- delete(conn, "/containers/#{container_id}") do
      :ok
    else
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
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

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, %Tesla.Env{status: other}} ->
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

      {:error, %Tesla.Env{status: 404}} ->
        {:ok, false}

      {:error, %Tesla.Env{status: 500}} ->
        {:error, {:http_error, 500}}

      {:error, %Tesla.Env{status: other}} ->
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

  def stdout_logs(container_id, conn) do
    case get(conn,
           "/containers/#{container_id}/logs?stdout=true&stderr=true&timestamps=false"
         ) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        {:ok, body}

      {:ok, %{body: %{"message" => msg}}} ->
        {:error, msg}

      {:ok, %{body: body}} ->
        {:error, body}

      {:error, error} ->
        {:error, :unknown, error}
    end
  end

  # ── Network operations ────────────────────────────────────────────

  def get_bridge_gateway(conn) do
    case get(conn, "/networks/bridge") do
      {:ok, %{status: 200, body: body}} ->
        case parse_body(body) do
          %{"IPAM" => %{"Config" => config}} ->
            case Enum.filter(config, &Map.get(&1, "Gateway")) do
              [] -> {:error, :no_gateway}
              [first | _] -> {:ok, Map.get(first, "Gateway")}
            end

          _ ->
            {:error, :unexpected_response}
        end

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
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
      {:ok, %{status: 201, body: body}} ->
        case parse_body(body) do
          %{"Id" => id} -> {:ok, id}
          _ -> {:error, {:failed_to_create_network, body}}
        end
      {:ok, %{status: 200, body: body}} ->
        case parse_body(body) do
          %{"Id" => id} -> {:ok, id}
          _ -> {:error, {:failed_to_create_network, body}}
        end

      {:ok, %{body: %{"message" => msg}}} ->
        {:error, {:failed_to_create_network, msg}}

      {:ok, %{status: 409}} ->
        {:ok, :already_exists}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, %Tesla.Env{status: 409}} ->
        {:ok, :already_exists}

      {:error, %Tesla.Env{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
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

      {:error, %Tesla.Env{status: 404}} ->
        {:error, :network_not_found}

      {:error, %Tesla.Env{status: status}} ->
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
      environment: map_env(env)
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
      environment: map_env(env)
    }
  end

  # ── Private helpers ───────────────────────────────────────────────

  defp container_create_request(%Config{} = cfg) do
    base = %{
      "Image" => cfg.image,
      "Cmd" => cfg.cmd,
      "ExposedPorts" => map_exposed_ports(cfg),
      "Env" => map_env(cfg.environment),
      "Labels" => cfg.labels,
      "Hostname" => cfg.hostname,
      "HostConfig" => %{
        "AutoRemove" => cfg.auto_remove,
        "PortBindings" => map_port_bindings(cfg),
        "Privileged" => cfg.privileged,
        "Binds" => map_binds(cfg),
        "Mounts" => map_volumes(cfg),
        "NetworkMode" => cfg.network_mode || cfg.network
      }
    }

    base =
      if cfg.network do
        endpoint = %{cfg.network => %{}}

        Map.put(base, "NetworkingConfig", %{
          "EndpointsConfig" => endpoint
        })
      else
        base
      end

    base
  end

  defp map_exposed_ports(%Config{exposed_ports: ports}) do
    Enum.map(ports, fn {port, _} -> {to_string(port), %{}} end) |> Enum.into(%{})
  end

  defp map_env(nil), do: []
  defp map_env(env) when is_list(env), do: env
  defp map_env(env) when is_map(env), do: Enum.map(env, fn {k, v} -> "#{k}=#{v}" end)

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
      &%{"Target" => &1.container_dest, "Source" => &1.volume, "Type" => "volume",
        "ReadOnly" => &1.read_only}
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
    tar_path = Path.join(System.tmp_dir!(), "#{Uniq.UUID.uuid4()}-#{file_name}.tar")

    :ok = :erl_tar.create(tar_path, [{String.to_charlist(file_name), contents}], [:compressed])

    with {:ok, data} <- File.read(tar_path),
         :ok <- File.rm(tar_path) do
      {:ok, data}
    end
  end

  defp create_exec(container_id, command, conn) do
    body = %{"Cmd" => command}

    case post(conn, "/containers/#{container_id}/exec", body) do
      {:ok, %{status: 201, body: body}} ->
        case parse_body(body) do
          %{"Id" => id} -> {:ok, id}
          _ -> {:error, {:failed_to_create_exec, body}}
        end
      {:ok, %{status: 200, body: body}} ->
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
    Tesla.get(conn, path)
  end

  defp post(conn, path, body, opts \\ []) do
    Tesla.post(conn, path, body || "", opts)
  end

  defp put_raw(conn, path, body, opts) do
    Tesla.put(conn, path, body, opts)
  end

  defp delete(conn, path) do
    Tesla.delete(conn, path)
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
