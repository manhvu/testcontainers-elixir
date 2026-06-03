defmodule TestcontainerEx.ContainerBuilderHelper do
  @moduledoc """
  Public alias for `TestcontainerEx.Container.BuilderHelper`.

  Keeps backward compatibility with code that references the flat module name.
  """

  alias TestcontainerEx.Container.BuilderHelper

  defdelegate build(builder, state), to: BuilderHelper
end
