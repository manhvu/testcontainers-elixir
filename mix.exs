defmodule TestcontainerEx.MixProject do
  use Mix.Project

  @app :testcontainer_ex
  @version "0.3.1"
  @source_url "https://github.com/manhvu/testcontainers-elixir"

  def project do
    [
      app: @app,
      name: "#{@app}",
      version: @version,
      description:
        "TestcontainerEx supports ExUnit tests, providing lightweight, throwaway instances of common databases or anything else that can run in a Docker/Podman container. TestcontainerEx is reworked from Testcontainers lib.",
      elixir: "~> 1.18",
      source_url: @source_url,
      homepage_url: @source_url,
      aliases: aliases(),
      deps: deps(),
      dialyzer: [plt_add_apps: [:mix]],
      package: [
        files: ~w(lib .formatter.exs mix.exs README* LICENSE*),
        links: %{"GitHub" => @source_url},
        licenses: ["MIT"]
      ],
      test_coverage: [
        summary: [threshold: 50],
        ignore_modules: [
          TestHelper,
          Inspect.TestcontainerEx.TestUser
        ]
      ],
      elixirc_paths: elixirc_paths(Mix.env())
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

  defp deps do
    [
      {:uniq, "~> 0.6"},
      {:telemetry, "~> 1.4"},
      {:recon, "~> 2.5", only: [:dev, :test]},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.3", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:tesla, "~> 1.7"},
      {:jason, "~> 1.4"},
      {:hackney, "~> 4.2"},
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
      {:decimal, "~> 3.0", only: [:dev, :test], override: true}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      citest: ["test --exclude flaky --cover"]
    ]
  end
end
