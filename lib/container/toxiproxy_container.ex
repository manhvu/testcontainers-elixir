# SPDX-License-Identifier: MIT
defmodule TestcontainerEx.ToxiproxyContainer do
  @moduledoc """
  Provides functionality for creating and managing Toxiproxy container configurations.
  """

  alias TestcontainerEx.Container.Builder
  alias TestcontainerEx.Container.Config
  alias TestcontainerEx.HttpWaitStrategy
  alias TestcontainerEx.ToxiproxyContainer

  @default_image "ghcr.io/shopify/toxiproxy"
  @default_tag "2.9.0"
  @default_image_with_tag "#{@default_image}:#{@default_tag}"
  @control_port 8474
  @first_proxy_port 8666
  @proxy_port_count 31
  @default_wait_timeout 60_000
  @max_retries 3
  @retry_delay_ms 500

  @type t :: %__MODULE__{}

  @enforce_keys [:image, :wait_timeout]
  defstruct [:image, :wait_timeout, :name, check_image: @default_image, reuse: false]

  use TestcontainerEx.ContainerConfig

  def new, do: %__MODULE__{image: @default_image_with_tag, wait_timeout: @default_wait_timeout}
  def with_image(%__MODULE__{} = c, image) when is_binary(image), do: %{c | image: image}
  def with_wait_timeout(%__MODULE__{} = c, t) when is_integer(t), do: %{c | wait_timeout: t}

  @doc """
  Sets the container name.
  """
  @spec with_name(t(), String.t()) :: t()
  def with_name(%__MODULE__{} = config, name) when is_binary(name) do
    %__MODULE__{config | name: name}
  end

  def default_image, do: @default_image_with_tag
  def control_port, do: @control_port
  def first_proxy_port, do: @first_proxy_port
  def proxy_port_count, do: @proxy_port_count

  def mapped_control_port(%Config{} = container),
    do: TestcontainerEx.get_port(container, @control_port)

  def api_url(%Config{} = container) do
    host = TestcontainerEx.get_host(container)
    port = mapped_control_port(container)
    "http://#{host}:#{port}"
  end

  def configure_toxiproxy_ex(%Config{} = container) do
    Application.put_env(:toxiproxy_ex, :host, api_url(container))
    :ok
  end

  def create_proxy(%Config{} = container, name, upstream, opts \\ []) do
    listen_port = Keyword.get(opts, :listen_port, @first_proxy_port)
    host = TestcontainerEx.get_host(container)
    api_port = mapped_control_port(container)
    :inets.start()

    url = ~c"http://#{host}:#{api_port}/proxies"
    body = Jason.encode!(%{name: name, listen: "0.0.0.0:#{listen_port}", upstream: upstream})
    headers = [{~c"content-type", ~c"application/json"}]

    case httpc_request_with_retry(:post, {url, headers, ~c"application/json", body}) do
      {:ok, {{_, code, _}, _, _}} when code in [200, 201] ->
        {:ok, TestcontainerEx.get_port(container, listen_port)}

      {:ok, {{_, 409, _}, _, _}} ->
        {:ok, TestcontainerEx.get_port(container, listen_port)}

      {:ok, {{_, code, _}, _, response_body}} ->
        {:error, {:http_error, code, response_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def create_proxy_for_container(
        %Config{} = toxiproxy,
        name,
        %Config{} = target,
        target_port,
        opts \\ []
      ) do
    upstream = "#{target.ip_address}:#{target_port}"
    create_proxy(toxiproxy, name, upstream, opts)
  end

  def delete_proxy(%Config{} = container, name) do
    host = TestcontainerEx.get_host(container)
    api_port = mapped_control_port(container)
    :inets.start()
    url = ~c"http://#{host}:#{api_port}/proxies/#{URI.encode_www_form(name)}"

    case httpc_request_with_retry(:delete, {url, []}) do
      {:ok, {{_, 204, _}, _, _}} -> :ok
      {:ok, {{_, 404, _}, _, _}} -> {:error, :not_found}
      {:ok, {{_, code, _}, _, body}} -> {:error, {:http_error, code, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  def reset(%Config{} = container) do
    host = TestcontainerEx.get_host(container)
    api_port = mapped_control_port(container)
    :inets.start()
    url = ~c"http://#{host}:#{api_port}/reset"

    case httpc_request_with_retry(:post, {url, [], ~c"application/json", "{}"}) do
      {:ok, {{_, 204, _}, _, _}} -> :ok
      {:ok, {{_, code, _}, _, body}} -> {:error, {:http_error, code, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  def list_proxies(%Config{} = container) do
    host = TestcontainerEx.get_host(container)
    api_port = mapped_control_port(container)
    :inets.start()
    url = ~c"http://#{host}:#{api_port}/proxies"

    case httpc_request_with_retry(:get, {url, []}) do
      {:ok, {{_, 200, _}, _, body}} -> {:ok, Jason.decode!(to_string(body))}
      {:ok, {{_, code, _}, _, body}} -> {:error, {:http_error, code, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp httpc_request_with_retry(method, request, retries_left \\ @max_retries) do
    http_opts = [timeout: 5_000, connect_timeout: 5_000]
    result = :httpc.request(method, request, http_opts, [])

    case result do
      {:error, reason} when retries_left > 0 ->
        retryable =
          case reason do
            :socket_closed_remotely -> true
            {:failed_connect, _} -> true
            :econnrefused -> true
            _ -> false
          end

        if retryable do
          Process.sleep(@retry_delay_ms)
          httpc_request_with_retry(method, request, retries_left - 1)
        else
          result
        end

      _ ->
        result
    end
  end

  defimpl Builder do
    @impl true
    def build(%ToxiproxyContainer{} = config) do
      proxy_ports =
        Enum.to_list(
          ToxiproxyContainer.first_proxy_port()..(ToxiproxyContainer.first_proxy_port() +
                                                    ToxiproxyContainer.proxy_port_count() - 1)
        )

      all_ports = [ToxiproxyContainer.control_port() | proxy_ports]

      Config.new(config.image)
      |> Config.with_exposed_ports(all_ports)
      |> Config.with_waiting_strategy(
        HttpWaitStrategy.new("/version", ToxiproxyContainer.control_port(),
          timeout: config.wait_timeout
        )
      )
      |> Config.with_reuse(config.reuse)
      |> then(fn cfg ->
        if config.name, do: Config.with_name(cfg, config.name), else: cfg
      end)
    end

    @impl true
    def after_start(_config, _container, _conn), do: :ok
  end
end
