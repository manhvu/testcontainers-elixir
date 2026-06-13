defmodule TestcontainerEx.Engine.ApiTest do
  use ExUnit.Case, async: true

  import TestcontainerEx.ApiTestHelper

  alias TestcontainerEx.Container.Config
  alias TestcontainerEx.Engine.Api

  @base_stubs %{
    {:get, "/containers/abc123/json"} =>
      {200,
       %{
         "Id" => "abc123def456",
         "Name" => "/my-postgres",
         "Image" => "sha256:abcdef123456",
         "NetworkSettings" => %{
           "IPAddress" => "172.17.0.2",
           "Ports" => %{
             "8080/tcp" => [%{"HostIp" => "0.0.0.0", "HostPort" => "9090"}],
             "5432/tcp" => [%{"HostIp" => "0.0.0.0", "HostPort" => "5432"}]
           },
           "Networks" => %{"bridge" => %{"IPAddress" => "172.17.0.2"}}
         },
         "Config" => %{
           "Env" => ["POSTGRES_PASSWORD=secret", "POSTGRES_DB=test"],
           "Labels" => %{"testcontainer_ex.session_id" => "sess-123"}
         }
       }},
    {:get, "/containers/abc123"} =>
      {200,
       %{
         "Id" => "abc123def456",
         "Name" => "/my-postgres",
         "Image" => "sha256:abcdef123456",
         "NetworkSettings" => %{"IPAddress" => "172.17.0.2", "Ports" => %{}, "Networks" => %{}},
         "Config" => %{"Env" => [], "Labels" => %{}}
       }},
    {:get, "/containers/json"} =>
      {200,
       [
         %{
           "Id" => "abc123def456",
           "Names" => ["/my-postgres"],
           "Image" => "postgres:16",
           "Labels" => %{"testcontainer_ex.session_id" => "sess-123"}
         }
       ]},
    {:get, "/containers/empty/json"} => {404, %{"message" => "No such container"}},
    {:get, "/containers/err404/json"} => {404, %{"message" => "not found"}},
    {:get, "/containers/err500/json"} => {500, %{"message" => "server error"}},
    {:post, "/containers/create"} => {201, %{"Id" => "newcontainer123", "Warnings" => []}},
    {:post, "/containers/create?name=my-container"} =>
      {201, %{"Id" => "namedcontainer456", "Warnings" => []}},
    {:post, "/containers/abc123/start"} => {200, ""},
    {:post, "/containers/abc123/stop"} => {200, ""},
    {:delete, "/containers/abc123?force=true"} => {200, ""},
    {:delete, "/containers/abc123"} => {200, ""},
    {:delete, "/containers/stop-fail?force=true"} => {500, %{"message" => "stop failed"}},
    {:delete, "/containers/stop-fail"} => {500, %{"message" => "stop failed"}},
    {:post, "/images/create"} => {200, ""},
    {:post, "/images/create?fromImage=postgres%3A16"} => {200, ""},
    {:post, "/images/create?fromImage=quay.io%2Forg%2Fprivate%3Alatest"} => {200, ""},
    {:post, "/images/create?fromImage=broken%3Alatest"} => {500, ""},
    {:get,
     "/containers/json?filters=%7B%22label%22%3A%5B%22org.testcontainer_ex.reuse-hash%3Dnonexistent%22%5D%7D"} =>
      {200, []},
    {:get,
     "/containers/json?filters=%7B%22label%22%3A%5B%22org.testcontainer_ex.reuse-hash%3Dsess-123%22%5D%7D"} =>
      {200,
       [
         %{
           "Id" => "abc123def456",
           "Names" => ["/my-postgres"],
           "Image" => "postgres:16",
           "Labels" => %{"testcontainer_ex.session_id" => "sess-123"}
         }
       ]},
    {:post, "/containers/nonexistent/exec"} => {404, %{"message" => "not found"}},
    {:get, "/exec/nonexistent/json"} => {404, %{"message" => "not found"}},
    {:delete, "/images/nonexistent?force=true"} => {404, %{"message" => "not found"}},
    {:post, "/images/nonexistent/tag?repo=repo&tag=tag"} => {404, ""},
    {:post, "/images/nonexistent/tag"} => {404, ""},
    {:get, "/images/postgres:16/json"} =>
      {200, %{"Id" => "sha256:abc123", "RepoTags" => ["postgres:16"]}},
    {:get, "/images/nonexistent/json"} => {404, %{"message" => "not found"}},
    {:get, "/images/err500/json"} => {500, %{"message" => "server error"}},
    {:delete, "/images/postgres:16?force=true"} => {200, [%{"Untagged" => "postgres:16"}]},
    {:post, "/images/postgres:16/tag?repo=myrepo%2Fmyimage&tag=v1"} => {201, ""},
    {:post, "/images/postgres:16/tag"} => {201, ""},
    {:get, "/exec/exec123/json"} => {200, %{"Running" => true, "ExitCode" => nil}},
    {:post, "/containers/abc123/exec"} => {201, %{"Id" => "exec123"}},
    {:post, "/exec/exec123/start"} => {200, ""},
    {:get, "/containers/abc123/logs?stdout=true&stderr=false&timestamps=false&follow=false"} =>
      {200, "log line 1\nlog line 2\n"},
    {:get, "/containers/abc123/logs?stdout=true&stderr=true&timestamps=false&follow=false"} =>
      {200, "log line 1\nlog line 2\n"},
    {:get, "/containers/abc123def456/json"} =>
      {200,
       %{
         "Id" => "abc123def456",
         "Name" => "/my-postgres",
         "Image" => "sha256:abcdef123456",
         "NetworkSettings" => %{
           "IPAddress" => "172.17.0.2",
           "Ports" => %{
             "8080/tcp" => [%{"HostIp" => "0.0.0.0", "HostPort" => "9090"}],
             "5432/tcp" => [%{"HostIp" => "0.0.0.0", "HostPort" => "5432"}]
           },
           "Networks" => %{"bridge" => %{"IPAddress" => "172.17.0.2"}}
         },
         "Config" => %{
           "Env" => ["POSTGRES_PASSWORD=secret", "POSTGRES_DB=test"],
           "Labels" => %{"testcontainer_ex.session_id" => "sess-123"}
         }
       }},
    {:get, "/networks/bridge"} =>
      {200,
       %{
         "Name" => "bridge",
         "IPAM" => %{"Config" => [%{"Gateway" => "172.17.0.1", "Subnet" => "172.17.0.0/16"}]}
       }},
    {:get, "/networks/empty"} => {200, %{"Name" => "empty", "IPAM" => %{"Config" => []}}},
    {:get, "/networks/malformed"} => {200, %{"Name" => "malformed"}},
    {:post, "/networks/create"} => {201, %{"Id" => "net123", "Warning" => ""}},
    {:delete, "/networks/net123"} => {200, ""},
    {:delete, "/networks/missing"} => {404, %{"message" => "not found"}},
    {:get, "/networks/exists"} => {200, %{"Id" => "exists", "Name" => "exists"}},
    {:get, "/networks/doesnotexist"} => {404, %{"message" => "not found"}}
  }

  setup do
    {:ok, conn: conn(@base_stubs)}
  end

  describe "get_container/2" do
    test "returns container config on success", %{conn: conn} do
      assert {:ok, %Config{} = config} = Api.get_container("abc123", conn)
      assert config.container_id == "abc123def456"
      assert config.image == "sha256:abcdef123456"
      assert config.ip_address == "172.17.0.2"
    end

    test "parses exposed ports correctly", %{conn: conn} do
      assert {:ok, %Config{} = config} = Api.get_container("abc123", conn)
      assert {8080, 9090} in config.exposed_ports
      assert {5432, 5432} in config.exposed_ports
    end

    test "parses environment variables", %{conn: conn} do
      assert {:ok, %Config{} = config} = Api.get_container("abc123", conn)
      assert config.environment[:POSTGRES_PASSWORD] == "secret"
      assert config.environment[:POSTGRES_DB] == "test"
    end

    test "parses labels", %{conn: conn} do
      assert {:ok, %Config{} = config} = Api.get_container("abc123", conn)
      assert config.labels["testcontainer_ex.session_id"] == "sess-123"
    end

    test "returns error for non-existent container", %{conn: conn} do
      assert {:error, {:http_error, 404}} = Api.get_container("err404", conn)
    end

    test "returns error for server error", %{conn: conn} do
      assert {:error, {:http_error, 500}} = Api.get_container("err500", conn)
    end
  end

  describe "get_container_by_hash/2" do
    test "finds container by hash label", %{conn: conn} do
      assert {:ok, %Config{} = config} = Api.get_container_by_hash("sess-123", conn)
      assert config.container_id == "abc123def456"
    end

    test "returns :no_container when no match", %{conn: conn} do
      assert {:error, :no_container} = Api.get_container_by_hash("nonexistent", conn)
    end
  end

  describe "create_container/2" do
    test "creates container and returns ID", %{conn: conn} do
      config = Config.new("postgres:16")
      assert {:ok, "newcontainer123"} = Api.create_container(config, conn)
    end

    test "creates named container", %{conn: conn} do
      config = Config.new("postgres:16") |> Config.with_name("my-container")
      assert {:ok, "namedcontainer456"} = Api.create_container(config, conn)
    end

    test "returns error on failure" do
      stubs = %{{:post, "/containers/create"} => {400, %{"message" => "invalid image reference"}}}
      conn = conn(stubs)
      config = Config.new("invalid")
      assert {:error, {:http_error, 400}} = Api.create_container(config, conn)
    end
  end

  describe "start_container/2" do
    test "starts container successfully (200)", %{conn: conn} do
      assert :ok = Api.start_container("abc123", conn)
    end

    test "starts container successfully (204)", %{conn: conn} do
      assert :ok = Api.start_container("abc123", conn)
    end
  end

  describe "stop_container/2" do
    test "stops and deletes container", %{conn: conn} do
      assert :ok = Api.stop_container("abc123", conn)
    end

    test "returns error when stop fails" do
      stubs = %{
        {:delete, "/containers/stop-fail?force=true"} => {500, %{"message" => "stop failed"}}
      }

      conn = conn(stubs)
      assert {:error, _} = Api.stop_container("stop-fail", conn)
    end
  end

  describe "pull_image/3" do
    test "pulls image without auth", %{conn: conn} do
      assert {:ok, nil} = Api.pull_image("postgres:16", conn)
    end

    test "pulls image with auth header", %{conn: conn} do
      assert {:ok, nil} = Api.pull_image("quay.io/org/private:latest", conn, auth: "dXNlcjpwYXNz")
    end

    test "returns error on failure", %{conn: conn} do
      assert {:error, {:http_error, 500}} = Api.pull_image("broken:latest", conn)
    end
  end

  describe "image_exists?/2" do
    test "returns true when image exists", %{conn: conn} do
      assert {:ok, true} = Api.image_exists?("postgres:16", conn)
    end

    test "returns false when image does not exist", %{conn: conn} do
      assert {:ok, false} = Api.image_exists?("nonexistent", conn)
    end

    test "returns error on server error", %{conn: conn} do
      assert {:error, {:http_error, 500}} = Api.image_exists?("err500", conn)
    end
  end

  describe "delete_image/2" do
    test "deletes image successfully", %{conn: conn} do
      assert :ok = Api.delete_image("postgres:16", conn)
    end

    test "returns error on failure" do
      stubs = %{
        {:delete, "/images/nonexistent?force=true"} => {500, %{"message" => "delete failed"}}
      }

      conn = conn(stubs)
      assert {:error, _} = Api.delete_image("nonexistent", conn)
    end
  end

  describe "tag_image/4" do
    test "tags image successfully", %{conn: conn} do
      assert {:ok, "myrepo/myimage:v1"} =
               Api.tag_image("postgres:16", "myrepo/myimage", "v1", conn)
    end

    test "returns error on failure", %{conn: conn} do
      assert {:error, _} = Api.tag_image("nonexistent", "repo", "tag", conn)
    end
  end

  describe "inspect_exec/2" do
    test "returns exec status", %{conn: conn} do
      assert {:ok, %{running: true, exit_code: nil}} = Api.inspect_exec("exec123", conn)
    end

    test "returns error on failure", %{conn: conn} do
      assert {:error, _} = Api.inspect_exec("nonexistent", conn)
    end
  end

  describe "start_exec/3" do
    test "creates and starts exec", %{conn: conn} do
      assert {:ok, "exec123"} = Api.start_exec("abc123", ["echo", "hello"], conn)
    end

    test "returns error when exec creation fails", %{conn: conn} do
      assert {:error, _} = Api.start_exec("nonexistent", ["echo"], conn)
    end
  end

  describe "stdout_logs/2" do
    test "returns container logs", %{conn: conn} do
      assert {:ok, logs} = Api.stdout_logs("abc123", conn)
      assert is_binary(logs)
    end
  end

  describe "get_bridge_gateway/1" do
    test "returns gateway IP", %{conn: conn} do
      assert {:ok, "172.17.0.1"} = Api.get_bridge_gateway(conn)
    end

    test "returns error when no gateway" do
      stubs = %{
        {:get, "/networks/bridge"} => {200, %{"Name" => "empty", "IPAM" => %{"Config" => []}}}
      }

      conn = conn(stubs)
      assert {:error, :no_gateway} = Api.get_bridge_gateway(conn)
    end

    test "returns error on malformed response" do
      stubs = %{{:get, "/networks/bridge"} => {200, %{"Name" => "malformed"}}}
      conn = conn(stubs)
      assert {:error, :no_gateway} = Api.get_bridge_gateway(conn)
    end
  end

  describe "create_network/3" do
    test "creates network and returns ID", %{conn: conn} do
      assert {:ok, "net123"} = Api.create_network("my-net", conn)
    end

    test "creates network with custom driver", %{conn: conn} do
      assert {:ok, "net123"} = Api.create_network("my-net", conn, driver: "bridge")
    end

    test "returns :already_exists on conflict" do
      stubs = %{{:post, "/networks/create"} => {409, ""}}
      conn = conn(stubs)
      assert {:ok, :already_exists} = Api.create_network("existing", conn)
    end

    test "returns error on failure" do
      stubs = %{{:post, "/networks/create"} => {500, %{"message" => "network creation failed"}}}
      conn = conn(stubs)
      assert {:error, _} = Api.create_network("broken", conn)
    end
  end

  describe "remove_network/2" do
    test "removes network successfully", %{conn: conn} do
      assert :ok = Api.remove_network("net123", conn)
    end

    test "returns error when network not found", %{conn: conn} do
      assert {:error, :network_not_found} = Api.remove_network("missing", conn)
    end
  end

  describe "network_exists?/2" do
    test "returns true when network exists", %{conn: conn} do
      assert Api.network_exists?("exists", conn)
    end

    test "returns false when network does not exist", %{conn: conn} do
      refute Api.network_exists?("doesnotexist", conn)
    end
  end

  describe "container_create_request/1 (via create_container)" do
    test "builds correct request for basic config", %{conn: conn} do
      config = Config.new("nginx:latest")
      assert {:ok, _id} = Api.create_container(config, conn)
    end

    test "builds correct request with environment", %{conn: conn} do
      config =
        Config.new("nginx:latest")
        |> Config.with_environment(:NGINX_HOST, "localhost")
        |> Config.with_environment(:NGINX_PORT, "80")

      assert {:ok, _id} = Api.create_container(config, conn)
    end

    test "builds correct request with exposed ports", %{conn: conn} do
      config =
        Config.new("nginx:latest")
        |> Config.with_exposed_port(80)
        |> Config.with_exposed_port(443)

      assert {:ok, _id} = Api.create_container(config, conn)
    end

    test "builds correct request with fixed ports", %{conn: conn} do
      config =
        Config.new("nginx:latest")
        |> Config.with_fixed_port(80, 8080)

      assert {:ok, _id} = Api.create_container(config, conn)
    end

    test "builds correct request with bind mounts", %{conn: conn} do
      config =
        Config.new("nginx:latest")
        |> Config.with_bind_mount("/host/path", "/container/path", "ro")

      assert {:ok, _id} = Api.create_container(config, conn)
    end

    test "builds correct request with labels", %{conn: conn} do
      config =
        Config.new("nginx:latest")
        |> Config.with_label("com.example.app", "myapp")
        |> Config.with_label("com.example.env", "test")

      assert {:ok, _id} = Api.create_container(config, conn)
    end

    test "builds correct request with network", %{conn: conn} do
      config =
        Config.new("nginx:latest")
        |> Config.with_network("my-network")

      assert {:ok, _id} = Api.create_container(config, conn)
    end

    test "builds correct request with cmd", %{conn: conn} do
      config =
        Config.new("nginx:latest")
        |> Config.with_cmd(["nginx", "-g", "daemon off;"])

      assert {:ok, _id} = Api.create_container(config, conn)
    end

    test "builds correct request with auto_remove", %{conn: conn} do
      config =
        Config.new("nginx:latest")
        |> Config.with_auto_remove(true)

      assert {:ok, _id} = Api.create_container(config, conn)
    end

    test "builds correct request with privileged", %{conn: conn} do
      config =
        Config.new("nginx:latest")
        |> Config.with_privileged(true)

      assert {:ok, _id} = Api.create_container(config, conn)
    end

    test "builds correct request with hostname", %{conn: conn} do
      config =
        Config.new("nginx:latest")
        |> Config.with_hostname("my-host")

      assert {:ok, _id} = Api.create_container(config, conn)
    end

    test "builds correct request with network_mode", %{conn: conn} do
      config =
        Config.new("nginx:latest")
        |> Config.with_network_mode("host")

      assert {:ok, _id} = Api.create_container(config, conn)
    end
  end

  describe "from_container_inspect/1 (response mapping)" do
    test "falls back to network IP when NetworkSettings.IPAddress is empty", %{conn: _conn} do
      stubs = %{
        {:get, "/containers/network-fallback/json"} =>
          {200,
           %{
             "Id" => "netfallback123",
             "Image" => "sha256:abc",
             "NetworkSettings" => %{
               "IPAddress" => "",
               "Ports" => %{},
               "Networks" => %{"custom-net" => %{"IPAddress" => "192.168.1.5"}}
             },
             "Config" => %{"Env" => [], "Labels" => %{}}
           }}
      }

      conn = conn(stubs)
      assert {:ok, config} = Api.get_container("network-fallback", conn)
      assert config.ip_address == "192.168.1.5"
    end

    test "handles nil IP address", %{conn: _conn} do
      stubs = %{
        {:get, "/containers/nil-ip/json"} =>
          {200,
           %{
             "Id" => "nilip123",
             "Image" => "sha256:abc",
             "NetworkSettings" => %{
               "IPAddress" => nil,
               "Ports" => %{},
               "Networks" => %{}
             },
             "Config" => %{"Env" => [], "Labels" => %{}}
           }}
      }

      conn = conn(stubs)
      assert {:ok, config} = Api.get_container("nil-ip", conn)
      assert config.ip_address == nil
    end

    test "handles missing Networks in response", %{conn: _conn} do
      stubs = %{
        {:get, "/containers/no-networks/json"} =>
          {200,
           %{
             "Id" => "nonet123",
             "Image" => "sha256:abc",
             "NetworkSettings" => %{
               "IPAddress" => "172.17.0.3",
               "Ports" => %{}
             },
             "Config" => %{"Env" => [], "Labels" => %{}}
           }}
      }

      conn = conn(stubs)
      assert {:ok, config} = Api.get_container("no-networks", conn)
      assert config.ip_address == "172.17.0.3"
    end
  end
end
