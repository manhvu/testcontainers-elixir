defmodule Mix.Tasks.TestcontainerEx.Test do
  @moduledoc false
  use Mix.Task

  @shortdoc "Runs mix test with TestcontainerEx (backward compatibility)"

  def run(args) do
    Mix.Task.run("testcontainer_ex.run", ["test" | args])
  end
end
