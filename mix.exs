defmodule TestcontainerEx.MixProject do
  use Mix.Project

  @app :testcontainer_ex
  @version "0.5.1"
  @source_url "https://github.com/manhvu/testcontainers-elixir"

  def project do
    [
      app: @app,
      name: "#{@app}",
      version: @version,
      description:
        "TestcontainerEx is an Elixir library for integration testing with containerized services. Start, stop, and monitor Docker, Podman, Minikube, or Colima containers with a unified API. Supports custom containers.",
      elixir: "~> 1.18",
      source_url: @source_url,
      homepage_url: @source_url,
      aliases: aliases(),
      deps: deps(),
      dialyzer: [plt_add_apps: [:mix]],
      package: [
        files: ~w(lib guides .formatter.exs mix.exs README* LICENSE*),
        links: %{"GitHub" => @source_url},
        licenses: ["MIT"]
      ],
      test_coverage: [
        summary: [threshold: 80],
        ignore_modules: [
          TestHelper,
          Inspect.TestcontainerEx.TestUser
        ]
      ],
      elixirc_paths: elixirc_paths(Mix.env()),
      docs: docs()
    ]
  end

  def cli do
    [preferred_envs: [test: :test, citest: :test, "testcontainer_ex.test": :test]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger],
      mod: {TestcontainerEx.Application, []}
    ]
  end

  defp docs do
    [
      main: "TestcontainerEx",
      extras: [
        "README.md",
        "guides/connection_helpers.md",
        "guides/container_control.md",
        "guides/custom_containers.md",
        "guides/engine_status.md",
        "guides/getting_started.md",
        "guides/wait_strategies.md"
      ],
      groups_for_modules: [
        "Core API": [
          TestcontainerEx,
          TestcontainerEx.Application,
          TestcontainerEx.Server
        ],
        "Container Management": [
          TestcontainerEx.Container,
          TestcontainerEx.ContainerBuilder,
          TestcontainerEx.ContainerBuilderHelper,
          TestcontainerEx.Container.Config,
          TestcontainerEx.Container.Info,
          TestcontainerEx.Container.Lifecycle,
          TestcontainerEx.Container.CustomContainer,
          TestcontainerEx.Container.Builder,
          TestcontainerEx.Container.BuilderHelper
        ],
        "Pre-built Containers": [
          TestcontainerEx.CassandraContainer,
          TestcontainerEx.CephContainer,
          TestcontainerEx.ElixirContainer,
          TestcontainerEx.EmqxContainer,
          TestcontainerEx.KafkaContainer,
          TestcontainerEx.MinioContainer,
          TestcontainerEx.MiniStackContainer,
          TestcontainerEx.MongoContainer,
          TestcontainerEx.MysqlContainer,
          TestcontainerEx.PostgresContainer,
          TestcontainerEx.RabbitmqContainer,
          TestcontainerEx.RedisContainer,
          TestcontainerEx.ScyllaContainer,
          TestcontainerEx.SeleniumContainer,
          TestcontainerEx.ToxiproxyContainer
        ],
        "Docker Engine": [
          TestcontainerEx.Docker.Control,
          TestcontainerEx.Docker.Engine,
          TestcontainerEx.Docker.Status,
          TestcontainerEx.DockerUrl
        ],
        "Docker API": [
          TestcontainerEx.Docker.Api,
          TestcontainerEx.Docker.Auth
        ],
        "Connection & Resolution": [
          TestcontainerEx.Connection.Connection,
          TestcontainerEx.Connection.Resolver,
          TestcontainerEx.Connection.Ssl,
          TestcontainerEx.Connection.Url
        ],
        "Connection Strategies": [
          TestcontainerEx.Connection.Strategies.Behaviour,
          TestcontainerEx.Connection.Strategies.Colima,
          TestcontainerEx.Connection.Strategies.ContainerEnv,
          TestcontainerEx.Connection.Strategies.Dotenv,
          TestcontainerEx.Connection.Strategies.Env,
          TestcontainerEx.Connection.Strategies.Minikube,
          TestcontainerEx.Connection.Strategies.Properties,
          TestcontainerEx.Connection.Strategies.Socket
        ],
        "Compose": [
          TestcontainerEx.Compose.Cli,
          TestcontainerEx.Compose.ComposeEnvironment,
          TestcontainerEx.Compose.ComposeService,
          TestcontainerEx.Compose.DockerCompose
        ],
        "Wait Strategies": [
          TestcontainerEx.WaitStrategy.CommandWaitStrategy,
          TestcontainerEx.WaitStrategy.HttpWaitStrategy,
          TestcontainerEx.WaitStrategy.LogWaitStrategy,
          TestcontainerEx.WaitStrategy.PortWaitStrategy,
          TestcontainerEx.WaitStrategy.Protocols.WaitStrategy,
          TestcontainerEx.Wait.Wait
        ],
        "Networking": [
          TestcontainerEx.Network.Network
        ],
        "Utilities": [
          TestcontainerEx.Util.Constants,
          TestcontainerEx.Util.Hash,
          TestcontainerEx.Util.Properties,
          TestcontainerEx.Util.Struct,
          TestcontainerEx.Constants,
          TestcontainerEx.Log,
          TestcontainerEx.PullPolicy,
          TestcontainerEx.CopyTo
        ],
        "Testing & Observability": [
          TestcontainerEx.ExUnit,
          TestcontainerEx.Telemetry,
          TestcontainerEx.Debug,
          TestcontainerEx.Recon
        ],
        "Reaper (Ryuk)": [
          TestcontainerEx.Ryuk
        ],
        "Mix Tasks": [
          Mix.Tasks.Testcontainers.Run,
          Mix.Tasks.Testcontainers.Test
        ]
      ]
    ]
  end

  defp deps do
    [
      {:uniq, "~> 0.6"},
      {:telemetry, "~> 1.4"},
      {:recon, "~> 2.5", only: [:dev, :test]},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:req, "~> 0.5"},
      {:plug, "~> 1.15", only: [:dev, :test]},
      {:jason, "~> 1.4"},
      # mysql
      {:myxql, "~> 0.9", only: [:dev, :test]},
      # postgres
      {:postgrex, "~> 0.22", only: [:dev, :test]},
      # mongo
      {:mongodb_driver, "~> 1.6", only: [:dev, :test]},
      # redis
      {:redix, "~> 1.5", only: [:dev, :test]},
      # ceph and minio
      {:ex_aws, "~> 2.7", only: [:dev, :test]},
      {:ex_aws_s3, "~> 2.5", only: [:dev, :test]},
      {:sweet_xml, "~> 0.7", only: [:dev, :test]},
      # cassandra
      {:xandra, "~> 0.19", only: [:dev, :test]},
      # kafka
      {:kafka_ex, "~> 1.0", only: [:dev, :test]},
      # RabbitMQ
      {:amqp, "~> 4.1", only: [:dev, :test]},
      # Zookeeper
      {:erlzk, "~> 0.6", only: [:dev, :test]},
      # EMQX
      {:tortoise311, "~> 0.12", only: [:dev, :test]},
      # Toxiproxy (for fault injection tests)
      {:toxiproxy_ex, "~> 2.0", only: [:dev, :test]},
      # For watching directories for file changes in mix task
      {:fs, "~> 11.4"},
      {:decimal, "~> 3.0", only: [:dev, :test], override: true},

      # Code quality
      {:dialyxir, "~> 1.3", only: [:dev], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      citest: ["test --exclude flaky --cover"],
      # Testing & Coverage
      coveralls: ["test --cover", "coveralls.html"],
      # Code Quality
      quality: ["format --check-formatted", "credo --strict", "dialyzer"]
    ]
  end
end
