defprotocol TestcontainerEx.ContainerBuilder do
  @moduledoc """
  All types of predefined containers must implement this protocol.
  """
  @spec build(t()) :: TestcontainerEx.Container.t()
  def build(builder)

  @doc """
  Do stuff after container has started.
  """
  @spec after_start(t(), TestcontainerEx.Container.t(), Tesla.Env.t()) :: :ok | {:error, term()}
  def after_start(builder, container, connection)
end
