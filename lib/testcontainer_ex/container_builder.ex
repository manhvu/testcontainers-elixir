defmodule TestcontainerEx.ContainerBuilder do
  @moduledoc """
  Convenience module for building container configurations.

  Delegates to the `TestcontainerEx.Container.Builder` protocol.
  """

  alias TestcontainerEx.Container.Builder

  def build(builder), do: Builder.build(builder)
end
