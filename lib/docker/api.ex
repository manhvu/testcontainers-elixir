# SPDX-License-Identifier: MIT
defmodule TestcontainerEx.Docker.Api do
  @moduledoc """
  Internal Docker API client. All functions require a Tesla connection.
  """

  alias DockerEngineAPI.Api
  alias DockerEngineAPI.Model.ExecConfig
  alias DockerEngineAPI.Model.HostConfig
  alias TestcontainerEx.Container.Config

  # ── Container operations ──────────────────────────────────────────

  def get_container(container_id, conn) when is_binary(container_id) do
    case Api.Container.container_inspect(conn, container_id) do
      {:error, %Tesla.Env{status: other}} ->
        {:error, {:http_error, other}}

      {:ok, %DockerEngineAPI.Model.ErrorResponse{} = error} ->
        {:error, {:failed_to_get_container, error}}

      {:ok, response} ->
        {:ok, from(response)}
    end
  end

  def get_container_by_hash(hash, conn) do
    filters =
      Jason.encode!(%{
        "label" => ["#{TestcontainerEx.Util.Constants.container_reuse_hash_label()}=#{hash}"]
      })

    case Api.Container.container_list(conn, filters: filters) do
      {:ok, %DockerEngineAPI.Model.ErrorResponse{} = error} ->
        {:error, {:failed_to_get_container, error}}

      {:error, error} ->
        {:error, error}

      {:ok, []} ->
        {:error, :no_container}

      {:ok, [container | _]} ->
        get_container(container."Id", conn)
    end
  end

  def create_container(%Config{} = container, conn) do
    opts = if container.name, do: [name: container.name], else: []

    case Api.Container.container_create(conn, container_create_request(container), opts) do
      {:error, %Tesla.Env{status: other}} ->
        {:error, {:http_error, other}}

      {:ok, %{Id: id}} ->
        {:ok, id}

      {:ok, %DockerEngineAPI.Model.ErrorResponse{} = error} ->
        {:error, {:failed_to_create_container, error}}
    end
  end

  def start_container(id, conn) when is_binary(id) do
    case Api.Container.container_start(conn, id) do
      {:ok, %Tesla.Env{status: 204}} ->
        :ok

      {:error, %Tesla.Env{status: other}} ->
        {:error, {:http_error, other}}

      {:ok, %DockerEngineAPI.Model.ErrorResponse{} = error} ->
        {:error, {:failed_to_start_container, error}}
    end
  end

  def stop_container(container_id, conn) when is_binary(container_id) do
    with {:ok, _} <- Api.Container.container_kill(conn, container_id),
         {:ok, _} <- Api.Container.container_delete(conn, container_id) do
      :ok
    end
  end

  def put_file(container_id, conn, path, file_name, file_contents) do
    with {:ok, tar} <- create_tar(file_name, file_contents),
         {:ok, %Tesla.Env{}} <- Api.Container.put_container_archive(conn, container_id, path, tar) do
      :ok
    end
  end

  # ── Image operations ──────────────────────────────────────────────

  def pull_image(image, conn, opts \\ []) when is_binary(image) do
    auth = Keyword.get(opts, :auth, nil)
    headers = if auth, do: ["X-Registry-Auth": auth], else: []

    case Api.Image.image_create(conn, Keyword.merge([fromImage: image], headers)) do
      {:ok, %Tesla.Env{status: 200}} ->
        {:ok, nil}

      {:error, %Tesla.Env{status: other}} ->
        {:error, {:http_error, other}}

      {:ok, %DockerEngineAPI.Model.ErrorResponse{} = error} ->
        {:error, {:failed_to_pull_image, error}}
    end
  end

  def image_exists?(image, conn) when is_binary(image) do
    case Api.Image.image_inspect(conn, image) do
      {:ok, %DockerEngineAPI.Model.ImageInspect{}} -> {:ok, true}
      {:ok, %DockerEngineAPI.Model.ErrorResponse{}} -> {:ok, false}
      {:error, %Tesla.Env{status: 404}} -> {:ok, false}
      {:error, %Tesla.Env{status: other}} -> {:error, {:http_error, other}}
    end
  end

  def delete_image(image, conn) when is_binary(image) do
    case Api.Image.image_delete(conn, image, force: true) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  def tag_image(image, repo, tag, conn) do
    case Api.Image.image_tag(conn, image, repo: repo, tag: tag) do
      {:ok, %Tesla.Env{status: 201}} -> {:ok, "#{repo}:#{tag}"}
      {:ok, %Tesla.Env{status: status}} -> {:error, {:http_error, status}}
      {:ok, %DockerEngineAPI.Model.ErrorResponse{message: msg}} -> {:error, msg}
      {:error, reason} -> {:error, reason}
    end
  end

  # ── Exec operations ───────────────────────────────────────────────

  def inspect_exec(exec_id, conn) do
    case Api.Exec.exec_inspect(conn, exec_id) do
      {:ok, %DockerEngineAPI.Model.ExecInspectResponse{} = body} ->
        {:ok, %{running: body."Running", exit_code: body."ExitCode"}}

      {:ok, %DockerEngineAPI.Model.ErrorResponse{message: msg}} ->
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
    case Api.Container.container_logs(conn, container_id, stdout: true, stderr: true) do
      {:ok, %Tesla.Env{body: body}} -> {:ok, body}
      {:ok, %DockerEngineAPI.Model.ErrorResponse{message: msg}} -> {:error, msg}
      {:error, error} -> {:error, :unknown, error}
    end
  end

  # ── Network operations ────────────────────────────────────────────

  def get_bridge_gateway(conn) do
    case Api.Network.network_inspect(conn, "bridge") do
      {:ok, %DockerEngineAPI.Model.Network{IPAM: %DockerEngineAPI.Model.Ipam{Config: config}}} ->
        case Enum.filter(config, &Map.get(&1, :Gateway)) do
          [] -> {:error, :no_gateway}
          [first | _] -> {:ok, Map.get(first, :Gateway)}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def create_network(name, conn, opts \\ []) when is_binary(name) do
    body = %DockerEngineAPI.Model.NetworkCreateRequest{
      Name: name,
      Driver: Keyword.get(opts, :driver, "bridge"),
      CheckDuplicate: true,
      Labels: Keyword.get(opts, :labels, %{})
    }

    case Api.Network.network_create(conn, body) do
      {:ok, %DockerEngineAPI.Model.NetworkCreateResponse{Id: id}} ->
        {:ok, id}

      {:ok, %DockerEngineAPI.Model.ErrorResponse{message: msg}} ->
        {:error, {:failed_to_create_network, msg}}

      {_, %Tesla.Env{status: 409}} ->
        {:ok, :already_exists}

      {_, %Tesla.Env{status: status}} ->
        {:error, {:http_error, status}}
    end
  end

  def remove_network(name, conn) when is_binary(name) do
    case Api.Network.network_delete(conn, name) do
      {:ok, nil} ->
        :ok

      {_, %Tesla.Env{status: 204}} ->
        :ok

      {_, %Tesla.Env{status: 404}} ->
        {:error, :network_not_found}

      {:ok, %DockerEngineAPI.Model.ErrorResponse{message: msg}} ->
        {:error, {:failed_to_remove_network, msg}}

      {_, %Tesla.Env{status: status}} ->
        {:error, {:http_error, status}}
    end
  end

  def network_exists?(name, conn) when is_binary(name) do
    case Api.Network.network_inspect(conn, name) do
      {:ok, %DockerEngineAPI.Model.Network{}} -> true
      _ -> false
    end
  end

  # ── Response mapping ──────────────────────────────────────────────

  defp from(%DockerEngineAPI.Model.ContainerInspectResponse{
         Id: id,
         Image: image,
         NetworkSettings: %{IPAddress: ip, Ports: ports, Networks: networks},
         Config: %{Env: env, Labels: labels}
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

  defp from(%DockerEngineAPI.Model.ContainerInspectResponse{
         Id: id,
         Image: image,
         NetworkSettings: %{IPAddress: ip, Ports: ports},
         Config: %{Env: env, Labels: labels}
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
    base = %DockerEngineAPI.Model.ContainerCreateRequest{
      Image: cfg.image,
      Cmd: cfg.cmd,
      ExposedPorts: map_exposed_ports(cfg),
      Env: map_env(cfg.environment),
      Labels: cfg.labels,
      Hostname: cfg.hostname,
      HostConfig: %HostConfig{
        AutoRemove: cfg.auto_remove,
        PortBindings: map_port_bindings(cfg),
        Privileged: cfg.privileged,
        Binds: map_binds(cfg),
        Mounts: map_volumes(cfg),
        NetworkMode: cfg.network_mode || cfg.network
      }
    }

    if cfg.network do
      endpoint = %{cfg.network => %DockerEngineAPI.Model.EndpointSettings{}}

      Map.put(base, :NetworkingConfig, %DockerEngineAPI.Model.NetworkingConfig{
        EndpointsConfig: endpoint
      })
    else
      base
    end
  end

  defp map_exposed_ports(%Config{exposed_ports: ports}) do
    Enum.map(ports, fn {port, _} -> {port, %{}} end) |> Enum.into(%{})
  end

  defp map_env(nil), do: []
  defp map_env(env), do: Enum.map(env, fn {k, v} -> "#{k}=#{v}" end)

  defp map_port_bindings(%Config{exposed_ports: ports}) do
    Enum.map(ports, fn
      {port, nil} -> {port, [%{"HostIp" => "0.0.0.0", "HostPort" => ""}]}
      {port, host} -> {port, [%{"HostIp" => "0.0.0.0", "HostPort" => to_string(host)}]}
    end)
    |> Enum.into(%{})
  end

  defp map_binds(%Config{bind_mounts: mounts}) do
    Enum.map(mounts, &"#{&1.host_src}:#{&1.container_dest}:#{&1.options}")
  end

  defp map_volumes(%Config{bind_volumes: volumes}) do
    Enum.map(
      volumes,
      &%{Target: &1.container_dest, Source: &1.volume, Type: "volume", ReadOnly: &1.read_only}
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
      {_name, %{IPAddress: ip}} when is_binary(ip) and ip != "" -> ip
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
    case Api.Exec.container_exec(conn, container_id, %ExecConfig{Cmd: command}) do
      {:ok, %DockerEngineAPI.Model.IdResponse{Id: id}} -> {:ok, id}
      {:ok, %DockerEngineAPI.Model.ErrorResponse{message: msg}} -> {:error, msg}
      {:error, msg} -> {:error, msg}
    end
  end

  defp do_start_exec(exec_id, conn) do
    case Api.Exec.exec_start(conn, exec_id, body: %{:Detach => true}) do
      {:ok, %Tesla.Env{status: 200}} -> :ok
      {:ok, %Tesla.Env{status: s}} -> {:error, {:http_error, s}}
      {:ok, %DockerEngineAPI.Model.ErrorResponse{message: msg}} -> {:error, msg}
      {:error, msg} -> {:error, msg}
    end
  end
end
