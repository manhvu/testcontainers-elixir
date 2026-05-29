defmodule ElixirSampleProjectWithTestcontainerExTest do
  use ExUnit.Case
  doctest ElixirSampleProjectWithTestcontainerEx
  import TestcontainerEx.ExUnit

  alias TestcontainerEx.Container
  alias TestcontainerEx.MySqlContainer

  container(:mysql, MySqlContainer.new(), shared: true)

  test "asserts mysql container major version", %{mysql: mysql} do
    assert Container.mapped_port(mysql, 3306) > 1
  end

  test "greets the world" do
    assert ElixirSampleProjectWithTestcontainerEx.hello() == :world
  end
end
