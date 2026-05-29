# SPDX-License-Identifier: MIT
defmodule TestcontainerEx.Container.SeleniumContainerTest do
  use ExUnit.Case, async: true
  import TestcontainerEx.ExUnit

  alias TestcontainerEx.Container
  alias TestcontainerEx.SeleniumContainer

  describe "with default configuration" do
    container(:selenium, SeleniumContainer.new())

    @tag :dood_limitation
    test "provides a ready-to-use selenium container", %{selenium: selenium} do
      assert Container.mapped_port(selenium, 4400) > 0
      assert Container.mapped_port(selenium, 4400) != 4400
      assert Container.mapped_port(selenium, 7900) > 0
      assert Container.mapped_port(selenium, 7900) != 7900
    end
  end
end
