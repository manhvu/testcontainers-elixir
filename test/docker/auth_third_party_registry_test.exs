defmodule TestcontainerEx.Engine.AuthThirdPartyRegistryTest do
  use ExUnit.Case, async: true

  alias TestcontainerEx.Engine.Auth

  @fixture Path.expand("../fixtures/docker_config_third_party.json", __DIR__)

  describe "registry_for_image/1 — third-party registries" do
    test "quay.io images resolve to quay.io" do
      assert Auth.registry_for_image("quay.io/coreos/etcd:v3.5.0") == "quay.io"
      assert Auth.registry_for_image("quay.io/myorg/myimage:latest") == "quay.io"
    end

    test "ghcr.io images resolve to ghcr.io" do
      assert Auth.registry_for_image("ghcr.io/owner/image:tag") == "ghcr.io"
      assert Auth.registry_for_image("ghcr.io/myorg/myapp:v1.0.0") == "ghcr.io"
    end

    test "gcr.io images resolve to gcr.io" do
      assert Auth.registry_for_image("gcr.io/my-project/my-image:tag") == "gcr.io"
    end

    test "gcr.io regional registries resolve correctly" do
      assert Auth.registry_for_image("us.gcr.io/project/image:tag") == "us.gcr.io"
      assert Auth.registry_for_image("eu.gcr.io/project/image:tag") == "eu.gcr.io"
      assert Auth.registry_for_image("asia.gcr.io/project/image:tag") == "asia.gcr.io"
    end

    test "registry.gitlab.com images resolve correctly" do
      assert Auth.registry_for_image("registry.gitlab.com/group/project/image:tag") ==
               "registry.gitlab.com"
    end

    test "AWS ECR registries resolve correctly" do
      assert Auth.registry_for_image("123456789.dkr.ecr.us-east-1.amazonaws.com/myimage:tag") ==
               "123456789.dkr.ecr.us-east-1.amazonaws.com"
    end

    test "Azure Container Registry resolves correctly" do
      assert Auth.registry_for_image("myregistry.azurecr.io/myimage:tag") ==
               "myregistry.azurecr.io"
    end

    test "GitHub Package Registry (old format) resolves correctly" do
      assert Auth.registry_for_image("docker.pkg.github.com/owner/repo/image:tag") ==
               "docker.pkg.github.com"
    end

    test "Google Artifact Registry resolves correctly" do
      assert Auth.registry_for_image("us-docker.pkg.dev/project/repo/image:tag") ==
               "us-docker.pkg.dev"
    end

    test "Elastic Container Registry resolves correctly" do
      assert Auth.registry_for_image("docker.elastic.co/elasticsearch/elasticsearch:8.0.0") ==
               "docker.elastic.co"
    end

    test "Microsoft Container Registry resolves correctly" do
      assert Auth.registry_for_image("mcr.microsoft.com/dotnet/sdk:6.0") == "mcr.microsoft.com"
    end

    test "NVIDIA NGC resolves correctly" do
      assert Auth.registry_for_image("nvcr.io/nvidia/pytorch:22.01-py3") == "nvcr.io"
    end

    test "Kubernetes registry resolves correctly" do
      assert Auth.registry_for_image("registry.k8s.io/pause:3.9") == "registry.k8s.io"
    end

    test "public ECR resolves correctly" do
      assert Auth.registry_for_image("public.ecr.aws/amazonlinux/amazonlinux:2") ==
               "public.ecr.aws"
    end

    test "self-hosted registry with port resolves correctly" do
      assert Auth.registry_for_image("myregistry.example.com:5000/myimage:tag") ==
               "myregistry.example.com:5000"
    end

    test "localhost registry resolves correctly" do
      assert Auth.registry_for_image("localhost/myimage:tag") == "localhost"
      assert Auth.registry_for_image("localhost:5000/myimage:tag") == "localhost:5000"
    end

    test "Docker Hub images still resolve correctly" do
      assert Auth.registry_for_image("nginx") == "https://index.docker.io/v1/"
      assert Auth.registry_for_image("library/nginx") == "https://index.docker.io/v1/"
      assert Auth.registry_for_image("docker.io/library/nginx") == "https://index.docker.io/v1/"
    end
  end

  describe "resolve/2 — third-party registry credentials" do
    test "resolves quay.io credentials" do
      header = Auth.resolve("quay.io/myorg/myimage:latest", @fixture)
      assert is_binary(header)
      decoded = decode_header(header)

      assert decoded == %{
               "username" => "quay-user",
               "password" => "quay-token",
               "serveraddress" => "quay.io"
             }
    end

    test "resolves ghcr.io credentials" do
      header = Auth.resolve("ghcr.io/myorg/myimage:latest", @fixture)
      assert is_binary(header)
      decoded = decode_header(header)

      assert decoded == %{
               "username" => "ghcr-user",
               "password" => "ghcr-pat",
               "serveraddress" => "ghcr.io"
             }
    end

    test "resolves gcr.io credentials" do
      header = Auth.resolve("gcr.io/my-project/image:tag", @fixture)
      assert is_binary(header)
      decoded = decode_header(header)

      assert decoded == %{
               "username" => "_json_key",
               "password" => "gcr-service-account",
               "serveraddress" => "gcr.io"
             }
    end

    test "resolves registry.gitlab.com credentials" do
      header = Auth.resolve("registry.gitlab.com/group/project:tag", @fixture)
      assert is_binary(header)
      decoded = decode_header(header)

      assert decoded == %{
               "username" => "gitlab-ci-token",
               "password" => "gitlab-token",
               "serveraddress" => "registry.gitlab.com"
             }
    end

    test "resolves AWS ECR credentials" do
      header = Auth.resolve("123456789.dkr.ecr.us-east-1.amazonaws.com/myimage:tag", @fixture)
      assert is_binary(header)
      decoded = decode_header(header)

      assert decoded == %{
               "username" => "AWS",
               "password" => "ecr-token",
               "serveraddress" => "123456789.dkr.ecr.us-east-1.amazonaws.com"
             }
    end

    test "resolves self-hosted registry with port" do
      header = Auth.resolve("myregistry.example.com:5000/myimage:tag", @fixture)
      assert is_binary(header)
      decoded = decode_header(header)

      assert decoded == %{
               "username" => "admin",
               "password" => "registry-pass",
               "serveraddress" => "myregistry.example.com:5000"
             }
    end

    test "returns nil for unknown third-party registry" do
      assert Auth.resolve("unknown.registry.io/image:tag", @fixture) == nil
    end

    test "serveraddress for third-party registries never contains scheme" do
      for image <- [
            "quay.io/org/img:tag",
            "ghcr.io/org/img:tag",
            "gcr.io/proj/img:tag",
            "registry.gitlab.com/g/p:tag"
          ] do
        header = Auth.resolve(image, @fixture)
        %{"serveraddress" => addr} = decode_header(header)
        refute String.contains?(addr, "://"), "serveraddress should not contain scheme: #{addr}"
        refute String.contains?(addr, "/"), "serveraddress should not contain path: #{addr}"
      end
    end
  end

  describe "candidate_keys/1 — third-party registry key generation" do
    test "generates correct candidate keys for quay.io" do
      keys = Auth.candidate_keys("quay.io")

      assert "quay.io" in keys
      assert "https://quay.io" in keys
      assert "http://quay.io" in keys
    end

    test "generates correct candidate keys for registry with port" do
      keys = Auth.candidate_keys("myregistry:5000")

      assert "myregistry:5000" in keys
      assert "https://myregistry:5000" in keys
      assert "http://myregistry:5000" in keys
    end

    test "generates correct candidate keys for Docker Hub" do
      keys = Auth.candidate_keys("https://index.docker.io/v1/")

      assert "https://index.docker.io/v1/" in keys
      assert "index.docker.io" in keys
      assert "docker.io" in keys
    end
  end

  describe "normalize_server_address/1 — third-party registries" do
    test "strips scheme from third-party registry URLs" do
      assert Auth.normalize_server_address("https://quay.io") == "quay.io"
      assert Auth.normalize_server_address("http://quay.io") == "quay.io"
      assert Auth.normalize_server_address("https://ghcr.io") == "ghcr.io"
      assert Auth.normalize_server_address("https://gcr.io") == "gcr.io"
    end

    test "strips scheme and path from third-party registry URLs" do
      assert Auth.normalize_server_address("https://quay.io/v1/") == "quay.io"

      assert Auth.normalize_server_address("https://registry.gitlab.com/") ==
               "registry.gitlab.com"
    end

    test "passes through bare third-party registry hosts" do
      assert Auth.normalize_server_address("quay.io") == "quay.io"
      assert Auth.normalize_server_address("ghcr.io") == "ghcr.io"
      assert Auth.normalize_server_address("gcr.io") == "gcr.io"
      assert Auth.normalize_server_address("myregistry:5000") == "myregistry:5000"
    end

    test "does not canonicalize third-party registries to docker.io" do
      assert Auth.normalize_server_address("quay.io") == "quay.io"
      assert Auth.normalize_server_address("ghcr.io") == "ghcr.io"
      assert Auth.normalize_server_address("gcr.io") == "gcr.io"
    end
  end

  defp decode_header(header) do
    header
    |> Base.url_decode64!(padding: false)
    |> Jason.decode!()
  end
end
