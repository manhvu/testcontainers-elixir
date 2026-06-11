defmodule TestcontainerEx.ConnectionTest do
  use ExUnit.Case, async: true

  alias TestcontainerEx.Connection

  describe "build_client/1" do
    test "builds a Tesla client with default options" do
      client = Connection.build_client(base_url: "http://localhost:2375")
      assert %Tesla.Client{} = client
    end

    test "builds a Tesla client with unix socket URL" do
      client = Connection.build_client(base_url: "http+unix://%2Fvar%2Frun%2Fdocker.sock")
      assert %Tesla.Client{} = client
    end

    test "builds a Tesla client with custom user agent" do
      client =
        Connection.build_client(
          base_url: "http://localhost:2375",
          user_agent: "TestcontainerEx/1.0"
        )

      assert %Tesla.Client{} = client
    end

    test "builds a Tesla client with custom recv_timeout" do
      client =
        Connection.build_client(
          base_url: "http://localhost:2375",
          recv_timeout: 60_000
        )

      assert %Tesla.Client{} = client
    end
  end

  describe "build_adapter/2" do
    test "returns Hackney adapter with default options" do
      adapter = Connection.build_adapter([], 300_000)
      assert {Tesla.Adapter.Hackney, opts} = adapter
      assert opts[:recv_timeout] == 300_000
      refute Keyword.has_key?(opts, :ssl_options)
    end

    test "returns Hackney adapter with SSL options for HTTPS" do
      ssl_opts = [certfile: "cert.pem", keyfile: "key.pem"]
      adapter = Connection.build_adapter([ssl_options: ssl_opts], 300_000)
      assert {Tesla.Adapter.Hackney, opts} = adapter
      assert opts[:recv_timeout] == 300_000
      assert opts[:ssl_options] == ssl_opts
    end

    test "returns custom adapter when specified" do
      adapter =
        Connection.build_adapter([adapter: {Tesla.Adapter.Hackney, recv_timeout: 5000}], 300_000)

      assert {Tesla.Adapter.Hackney, recv_timeout: 5000} = adapter
    end
  end

  describe "build_ssl_options/0" do
    test "delegates to Ssl.build_options/0" do
      opts = Connection.build_ssl_options()
      assert is_list(opts)
    end
  end
end
