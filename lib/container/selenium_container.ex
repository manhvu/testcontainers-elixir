# SPDX-License-Identifier: MIT
defmodule TestcontainerEx.SeleniumContainer do
  @moduledoc """
  Work in progress. Not stable for use yet.
  """

  alias TestcontainerEx.Container.Builder
  alias TestcontainerEx.Container.Config
  alias TestcontainerEx.LogWaitStrategy
  alias TestcontainerEx.PortWaitStrategy
  alias TestcontainerEx.SeleniumContainer

  use TestcontainerEx.ContainerConfig

  @default_image "selenium/standalone-chrome"
  @default_tag "118.0"
  @default_image_with_tag "#{@default_image}:#{@default_tag}"
  @default_port1 7900
  @default_port2 4400
  @default_wait_timeout 120_000

  @type t :: %__MODULE__{}

  @enforce_keys [:image, :port1, :port2, :wait_timeout]
  defstruct [
    :image,
    :port1,
    :port2,
    :wait_timeout,
    :name,
    check_image: @default_image,
    reuse: false
  ]

  def new,
    do: %__MODULE__{
      image: @default_image_with_tag,
      wait_timeout: @default_wait_timeout,
      port1: @default_port1,
      port2: @default_port2
    }

  def with_image(%__MODULE__{} = c, image) when is_binary(image), do: %{c | image: image}
  def with_port1(%__MODULE__{} = c, p) when is_integer(p), do: %{c | port1: p}
  def with_port2(%__MODULE__{} = c, p) when is_integer(p), do: %{c | port2: p}
  def with_wait_timeout(%__MODULE__{} = c, t) when is_integer(t), do: %{c | wait_timeout: t}

  @doc """
  Sets the container name.
  """
  @spec with_name(t(), String.t()) :: t()
  def with_name(%__MODULE__{} = config, name) when is_binary(name) do
    %__MODULE__{config | name: name}
  end

  def default_image, do: @default_image

  defimpl Builder do
    @spec build(SeleniumContainer.t()) :: Config.t()
    @impl true
    def build(%SeleniumContainer{} = config) do
      Config.new(config.image)
      |> Config.with_exposed_ports([config.port1, config.port2])
      |> Config.with_waiting_strategies([
        LogWaitStrategy.new(
          ~r/.*(RemoteWebDriver instances should connect to|Selenium Server is up and running|Started Selenium Standalone).*\n/,
          config.wait_timeout,
          1000
        ),
        PortWaitStrategy.new("127.0.0.1", config.port1, config.wait_timeout, 1000),
        PortWaitStrategy.new("127.0.0.1", config.port2, config.wait_timeout, 1000)
      ])
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
