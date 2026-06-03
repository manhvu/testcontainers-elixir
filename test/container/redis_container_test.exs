# SPDX-License-Identifier: MIT
# Original by: Marco Dallagiacoma @ 2023 in https://github.com/dallagi/excontainers
# Modified by: Jarl André Hübenthal @ 2023
defmodule TestcontainerEx.Container.RedisContainerTest do
  use ExUnit.Case, async: true

  @moduletag :needs_dock
  import TestcontainerEx.ExUnit

  alias TestcontainerEx.RedisContainer

  describe "with default configuration" do
    container(:redis, RedisContainer.new())

    test "provides a ready-to-use redis container", %{redis: redis} do
      {:ok, conn} = Redix.start_link(RedisContainer.connection_url(redis))

      assert Redix.command!(conn, ["PING"]) == "PONG"
    end
  end

  describe "with password configuration" do
    container(:redis, RedisContainer.new() |> RedisContainer.with_password("secret"))

    test "provides a ready-to-use redis container with password", %{redis: redis} do
      {:ok, conn} = Redix.start_link(RedisContainer.connection_url(redis))

      assert Redix.command!(conn, ["PING"]) == "PONG"
    end
  end
end
