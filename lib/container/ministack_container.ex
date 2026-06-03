defmodule TestcontainerEx.MinistackContainer do
  @moduledoc """
  Provides functionality for creating and managing Ministack container configurations.
  """

  alias TestcontainerEx.Container.Builder
  alias TestcontainerEx.Container.Config
  alias TestcontainerEx.LogWaitStrategy
  alias TestcontainerEx.MinistackContainer

  @default_image "ministackorg/ministack"
  @default_tag "1.3.42"
  @default_image_with_tag "#{@default_image}:#{@default_tag}"
  @default_username "111111111111"
  @default_password "anything"
  @default_s3_port 4566
  @default_ui_port 2222
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

  def with_reuse(%__MODULE__{} = c, reuse) when is_boolean(reuse),
    do: %__MODULE__{c | reuse: reuse}

  def get_username, do: @default_username
  def get_password, do: @default_password
  def default_ui_port, do: @default_ui_port
  def default_s3_port, do: @default_s3_port

  def port(%Config{} = c), do: TestcontainerEx.get_port(c, @default_s3_port)

  def connection_url(%Config{} = c) do
    "http://#{TestcontainerEx.get_host(c)}:#{port(c)}"
  end

  def connection_opts(%Config{} = c) do
    [
      port: MinistackContainer.port(c),
      scheme: "http://",
      host: TestcontainerEx.get_host(c),
      access_key_id: c.environment[:AWS_ACCESS_KEY_ID],
      secret_access_key: c.environment[:AWS_SECRET_ACCESS_KEY]
    ]
  end

  defimpl Builder do
    @spec build(MinistackContainer.t()) :: Config.t()
    @impl true
    def build(%MinistackContainer{} = config) do
      Config.new(config.image)
      |> Config.with_exposed_ports([
        MinistackContainer.default_s3_port(),
        MinistackContainer.default_ui_port()
      ])
      |> Config.with_environment(:AWS_ACCESS_KEY_ID, config.username)
      |> Config.with_environment(:AWS_SECRET_ACCESS_KEY, config.password)
      |> Config.with_reuse(config.reuse)
      |> Config.with_waiting_strategy(
        LogWaitStrategy.new(
          ~r/.*Ready .* services available on port #{MinistackContainer.default_s3_port()}\./,
          config.wait_timeout,
          1000
        )
      )
    end

    @impl true
    def after_start(_config, _container, _conn), do: :ok
  end
end
