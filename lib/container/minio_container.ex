defmodule TestcontainerEx.MinioContainer do
  @moduledoc """
  Provides functionality for creating and managing Minio container configurations.
  """

  alias TestcontainerEx.Container.Builder
  alias TestcontainerEx.Container.Config
  alias TestcontainerEx.LogWaitStrategy
  alias TestcontainerEx.MinioContainer

  @default_image "minio/minio"
  @default_tag "RELEASE.2023-11-11T08-14-41Z"
  @default_image_with_tag "#{@default_image}:#{@default_tag}"
  @default_username "minioadmin"
  @default_password "minioadmin"
  @default_s3_port 9000
  @default_ui_port 9001
  @default_wait_timeout 60_000

  @type t :: %__MODULE__{}

  @enforce_keys [:image, :username, :password, :wait_timeout]
  defstruct [:image, :username, :password, :wait_timeout, reuse: false]

  def new,
    do: %__MODULE__{
      image: @default_image_with_tag,
      username: @default_username,
      password: @default_password,
      wait_timeout: @default_wait_timeout
    }

  def with_reuse(%__MODULE__{} = config, reuse) when is_boolean(reuse),
    do: %__MODULE__{config | reuse: reuse}

  def get_username, do: @default_username
  def get_password, do: @default_password
  def default_ui_port, do: @default_ui_port
  def default_s3_port, do: @default_s3_port

  def port(%Config{} = container), do: TestcontainerEx.get_port(container, @default_s3_port)

  def connection_url(%Config{} = container) do
    "http://#{TestcontainerEx.get_host(container)}:#{port(container)}"
  end

  def connection_opts(%Config{} = container) do
    [
      port: MinioContainer.port(container),
      scheme: "http://",
      host: TestcontainerEx.get_host(container),
      access_key_id: container.environment[:MINIO_ROOT_USER],
      secret_access_key: container.environment[:MINIO_ROOT_PASSWORD]
    ]
  end

  defimpl Builder do
    @spec build(MinioContainer.t()) :: Config.t()
    @impl true
    def build(%MinioContainer{} = config) do
      Config.new(config.image)
      |> Config.with_exposed_ports([
        MinioContainer.default_s3_port(),
        MinioContainer.default_ui_port()
      ])
      |> Config.with_environment(:MINIO_ROOT_USER, config.username)
      |> Config.with_environment(:MINIO_ROOT_PASSWORD, config.password)
      |> Config.with_reuse(config.reuse)
      |> Config.with_cmd([
        "server",
        "--console-address",
        ":#{MinioContainer.default_ui_port()}",
        "/data"
      ])
      |> Config.with_waiting_strategy(
        LogWaitStrategy.new(~r/.*Status:         1 Online, 0 Offline..*/, config.wait_timeout)
      )
    end

    @impl true
    def after_start(_config, _container, _conn), do: :ok
  end
end
