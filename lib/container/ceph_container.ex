# SPDX-License-Identifier: MIT
defmodule TestcontainerEx.CephContainer do
  @moduledoc """
  Provides functionality for creating and managing Ceph container configurations.
  """

  alias TestcontainerEx.CephContainer
  alias TestcontainerEx.Container.Builder
  alias TestcontainerEx.Container.Config
  alias TestcontainerEx.LogWaitStrategy

  use TestcontainerEx.ContainerConfig

  @default_image "quay.io/ceph/demo"
  @default_tag "latest-quincy"
  @default_image_with_tag "#{@default_image}:#{@default_tag}"
  @default_bucket "test"
  @default_access_key "test"
  @default_secret_key :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  @default_port 8080
  @default_wait_timeout 300_000

  @type t :: %__MODULE__{}

  @enforce_keys [:image, :access_key, :secret_key, :bucket, :port, :wait_timeout]
  defstruct [
    :image,
    :access_key,
    :secret_key,
    :bucket,
    :port,
    :wait_timeout,
    :name,
    check_image: @default_image,
    reuse: false
  ]

  def new,
    do: %__MODULE__{
      image: @default_image_with_tag,
      wait_timeout: @default_wait_timeout,
      port: @default_port,
      access_key: @default_access_key,
      secret_key: @default_secret_key,
      bucket: @default_bucket
    }

  def with_image(%__MODULE__{} = config, image) when is_binary(image) do
    %{config | image: image}
  end

  def with_access_key(%__MODULE__{} = config, access_key) when is_binary(access_key) do
    %{config | access_key: access_key}
  end

  def with_secret_key(%__MODULE__{} = config, secret_key) when is_binary(secret_key) do
    %{config | secret_key: secret_key}
  end

  def with_bucket(%__MODULE__{} = config, bucket) when is_binary(bucket) do
    %{config | bucket: bucket}
  end

  def with_port(%__MODULE__{} = config, port) when is_integer(port) do
    %{config | port: port}
  end

  def with_wait_timeout(%__MODULE__{} = config, wait_timeout) when is_integer(wait_timeout) do
    %{config | wait_timeout: wait_timeout}
  end

  @doc """
  Sets the container name.
  """
  @spec with_name(t(), String.t()) :: t()
  def with_name(%__MODULE__{} = config, name) when is_binary(name) do
    %__MODULE__{config | name: name}
  end

  def default_image, do: @default_image

  def port(%Config{} = container), do: TestcontainerEx.get_port(container, @default_port)

  def connection_url(%Config{} = container) do
    "http://#{TestcontainerEx.get_host(container)}:#{port(container)}"
  end

  def connection_opts(%Config{} = container) do
    [
      port: CephContainer.port(container),
      scheme: "http://",
      host: TestcontainerEx.get_host(container),
      access_key_id: container.environment[:CEPH_DEMO_ACCESS_KEY],
      secret_access_key: container.environment[:CEPH_DEMO_SECRET_KEY]
    ]
  end

  defimpl Builder do
    @spec build(CephContainer.t()) :: Config.t()
    @impl true
    def build(%CephContainer{} = config) do
      Config.new(config.image)
      |> Config.with_exposed_port(config.port)
      |> Config.with_environment(:CEPH_DEMO_UID, "demo")
      |> Config.with_environment(:CEPH_DEMO_BUCKET, config.bucket)
      |> Config.with_environment(:CEPH_DEMO_ACCESS_KEY, config.access_key)
      |> Config.with_environment(:CEPH_DEMO_SECRET_KEY, config.secret_key)
      |> Config.with_environment(:CEPH_PUBLIC_NETWORK, "0.0.0.0/0")
      |> Config.with_environment(:MON_IP, "127.0.0.1")
      |> Config.with_environment(:RGW_NAME, "localhost")
      |> Config.with_waiting_strategy(
        LogWaitStrategy.new(
          ~r/.*Bucket 's3:\/\/#{config.bucket}\/' created.*/,
          config.wait_timeout,
          5000
        )
      )
      |> Config.with_check_image(config.check_image)
      |> Config.with_reuse(config.reuse)
      |> then(fn cfg ->
        if config.name, do: Config.with_name(cfg, config.name), else: cfg
      end)
      |> Config.valid_image!()
    end

    @impl true
    def after_start(_config, _container, _conn), do: :ok
  end
end
