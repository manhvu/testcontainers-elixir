defmodule TestcontainerEx.ContainerBuilder do
  @moduledoc """
  Convenience module for building container configurations.

  Delegates to the `TestcontainerEx.Container.Builder` protocol.
  """

  def build(builder), do: TestcontainerEx.Container.Builder.build(builder)
end
