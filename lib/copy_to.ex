defmodule TestcontainerEx.CopyTo do
  @moduledoc false
  alias TestcontainerEx.Engine

  @doc """
  Copy a string of contents into a file at target
  """
  def copy_to(conn, id, %{"target" => target, "contents" => contents})
      when is_binary(target) and is_binary(contents) do
    Engine.Api.put_file(id, conn, Path.dirname(target), Path.basename(target), contents)
  end

  # add more implementation for copy_to as you need them, eg.
  # - copy a dir into a dir
  # - copy a file into a file
  # - copy an archive into a file
end
