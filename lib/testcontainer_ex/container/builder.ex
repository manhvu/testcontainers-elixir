defprotocol TestcontainerEx.Container.Builder do
  @moduledoc """
  Protocol for building container configurations from domain-specific
  container types (e.g. RedisContainer, PostgresContainer).

  Implementations transform a domain struct into a `Container.Config`
  with appropriate image, ports, wait strategies, etc.
  """
  @spec build(t()) :: TestcontainerEx.Container.Config.t()
  def build(builder)

  @doc """
  Hook called after the container has started successfully.
  Use for post-start validation or configuration.
  """
  @spec after_start(t(), TestcontainerEx.Container.Config.t(), Tesla.Env.t()) ::
          :ok | {:error, term()}
  def after_start(builder, container, connection)
end
