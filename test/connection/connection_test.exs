defmodule TestcontainerEx.ConnectionTest do
  use ExUnit.Case, async: true

  alias TestcontainerEx.Connection

  describe "build_client/1" do
    test "builds a Req client with default options" do
      client = Connection.build_client(base_url: "http://localhost:2375")
      assert %Req.Request{} = client
    end

    test "builds a Req client with unix socket URL" do
      client = Connection.build_client(base_url: "http+unix://%2Fvar%2Frun%2Fdocker.sock")
      assert %Req.Request{} = client
    end

    test "builds a Req client with custom user agent" do
      client =
        Connection.build_client(
          base_url: "http://localhost:2375",
          user_agent: "TestcontainerEx/1.0"
        )

      assert %Req.Request{} = client
    end

    test "builds a Req client with custom recv_timeout" do
      client =
        Connection.build_client(
          base_url: "http://localhost:2375",
          recv_timeout: 60_000
        )

      assert %Req.Request{} = client
    end
  end

  describe "build_ssl_options/0" do
    test "delegates to Ssl.build_options/0" do
      opts = Connection.build_ssl_options()
      assert is_list(opts)
    end
  end
end
