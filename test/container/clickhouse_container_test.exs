# SPDX-License-Identifier: MIT
defmodule TestcontainerEx.Container.ClickHouseContainerTest do
  use ExUnit.Case, async: true

  @moduletag :needs_dock
  import TestcontainerEx.ExUnit

  alias TestcontainerEx.ClickHouseContainer

  describe "with default configuration" do
    container(:clickhouse, ClickHouseContainer.new())

    test "provides a ready-to-use clickhouse container", %{clickhouse: clickhouse} do
      url = ClickHouseContainer.connection_url(clickhouse)
      user = ClickHouseContainer.connection_parameters(clickhouse)[:user]
      password = ClickHouseContainer.connection_parameters(clickhouse)[:password]

      assert {:ok, %{status: 200, body: "1\n"}} =
               Req.get(url, auth: {:basic, "#{user}:#{password}"}, params: [query: "SELECT 1"])
    end

    test "exposes the native port", %{clickhouse: clickhouse} do
      assert is_integer(ClickHouseContainer.native_port(clickhouse))
    end
  end

  describe "with custom configuration" do
    import ClickHouseContainer

    @custom_clickhouse new()
                       |> with_user("custom-user")
                       |> with_password("custom-password")
                       |> with_database("custom-database")

    container(:clickhouse, @custom_clickhouse)

    test "provides a clickhouse container compliant with specified configuration", %{
      clickhouse: clickhouse
    } do
      url = ClickHouseContainer.connection_url(clickhouse)
      user = ClickHouseContainer.connection_parameters(clickhouse)[:user]
      password = ClickHouseContainer.connection_parameters(clickhouse)[:password]

      assert {:ok, %{status: 200}} =
               Req.get(url,
                 auth: {:basic, "#{user}:#{password}"},
                 params: [query: "SELECT currentUser()"]
               )
    end
  end
end
