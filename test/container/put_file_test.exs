defmodule TestcontainerEx.Container.PutFileTest do
  use ExUnit.Case, async: true

  import TestcontainerEx.ExUnit

  container(:nginx, %Test.NginxContainer{})

  test "upload file", %{nginx: _nginx} do
    # should succeed
  end
end
