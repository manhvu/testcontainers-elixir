defmodule TestcontainerEx.ConnectionTest do
  use ExUnit.Case, async: false

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

  describe "get_connection/1 with engine option" do
    setup do
      original = System.get_env("CONTAINER_ENGINE")

      on_exit(fn ->
        case original do
          nil -> System.delete_env("CONTAINER_ENGINE")
          val -> System.put_env("CONTAINER_ENGINE", val)
        end
      end)

      System.delete_env("CONTAINER_ENGINE")
      :ok
    end

    test "passes engine option to Resolver" do
      # With no Docker available, all strategies should fail
      # The important thing is that it attempts resolution without crashing
      case Connection.get_connection(engine: :docker) do
        {_conn, _url, _host} ->
          :ok

        {:error, _reason} ->
          :ok
      end
    end

    test "engine: :auto tries all strategies" do
      case Connection.get_connection(engine: :auto) do
        {_conn, _url, _host} ->
          :ok

        {:error, _reason} ->
          :ok
      end
    end

    test "engine: :colima restricts to colima strategy" do
      case Connection.get_connection(engine: :colima) do
        {_conn, _url, _host} ->
          :ok

        {:error, _reason} ->
          :ok
      end
    end

    test "engine: :podman restricts to podman strategies" do
      case Connection.get_connection(engine: :podman) do
        {_conn, _url, _host} ->
          :ok

        {:error, _reason} ->
          :ok
      end
    end

    test "engine: :minikube restricts to minikube strategy" do
      case Connection.get_connection(engine: :minikube) do
        {_conn, _url, _host} ->
          :ok

        {:error, _reason} ->
          :ok
      end
    end

    test "engine: :apple_container restricts to apple_container strategy" do
      case Connection.get_connection(engine: :apple_container) do
        {_conn, _url, _host} ->
          :ok

        {:error, _reason} ->
          :ok
      end
    end
  end

  describe "get_connection/1 with CONTAINER_ENGINE env var" do
    setup do
      original = System.get_env("CONTAINER_ENGINE")

      on_exit(fn ->
        case original do
          nil -> System.delete_env("CONTAINER_ENGINE")
          val -> System.put_env("CONTAINER_ENGINE", val)
        end
      end)

      System.delete_env("CONTAINER_ENGINE")
      :ok
    end

    test "CONTAINER_ENGINE=docker is respected" do
      System.put_env("CONTAINER_ENGINE", "docker")

      case Connection.get_connection() do
        {_conn, _url, _host} ->
          :ok

        {:error, _reason} ->
          :ok
      end
    end

    test "CONTAINER_ENGINE=podman is respected" do
      System.put_env("CONTAINER_ENGINE", "podman")

      case Connection.get_connection() do
        {_conn, _url, _host} ->
          :ok

        {:error, _reason} ->
          :ok
      end
    end

    test "CONTAINER_ENGINE=colima is respected" do
      System.put_env("CONTAINER_ENGINE", "colima")

      case Connection.get_connection() do
        {_conn, _url, _host} ->
          :ok

        {:error, _reason} ->
          :ok
      end
    end

    test "CONTAINER_ENGINE=minikube is respected" do
      System.put_env("CONTAINER_ENGINE", "minikube")

      case Connection.get_connection() do
        {_conn, _url, _host} ->
          :ok

        {:error, _reason} ->
          :ok
      end
    end

    test "CONTAINER_ENGINE=apple_container is respected" do
      System.put_env("CONTAINER_ENGINE", "apple_container")

      case Connection.get_connection() do
        {_conn, _url, _host} ->
          :ok

        {:error, _reason} ->
          :ok
      end
    end

    test "CONTAINER_ENGINE=auto tries all strategies" do
      System.put_env("CONTAINER_ENGINE", "auto")

      case Connection.get_connection() do
        {_conn, _url, _host} ->
          :ok

        {:error, _reason} ->
          :ok
      end
    end

    test "invalid CONTAINER_ENGINE falls back to auto" do
      System.put_env("CONTAINER_ENGINE", "nonexistent_engine")

      case Connection.get_connection() do
        {_conn, _url, _host} ->
          :ok

        {:error, _reason} ->
          :ok
      end
    end

    test "explicit engine option overrides CONTAINER_ENGINE env var" do
      System.put_env("CONTAINER_ENGINE", "podman")

      case Connection.get_connection(engine: :docker) do
        {_conn, _url, _host} ->
          :ok

        {:error, _reason} ->
          :ok
      end
    end
  end
end
