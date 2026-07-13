defmodule TestcontainerEx.Container.Info do
  @moduledoc """
  Convenience functions for extracting runtime information from a started container.

  While `Config` holds the full configuration, `Info` provides focused accessors
  for the most commonly needed runtime details — host, port, connection strings.

  ## Usage

      {:ok, container} = TestcontainerEx.start_container(PostgresContainer.new())

      # Get connection parameters for Postgrex
      opts = TestcontainerEx.Container.Info.pg_connect_opts(container)

      # Get a generic connection URL
      url = TestcontainerEx.Container.Info.url(container, 5432, "postgres")
  """

  alias TestcontainerEx.Container.Config

  @doc """
  Returns the host address for the container.
  """
  @spec host(Config.t()) :: String.t()
  def host(%Config{} = container), do: TestcontainerEx.get_host(container)

  @doc """
  Returns the mapped host port for the given container port.
  """
  @spec port(Config.t(), integer()) :: integer() | nil
  def port(%Config{} = container, container_port),
    do: TestcontainerEx.get_port(container, container_port)

  @doc """
  Returns a generic connection URL for the container.

  ## Parameters

    * `container` — a started container config
    * `container_port` — the internal container port
    * `scheme` — protocol scheme (e.g. "postgres", "redis", "http")

  ## Examples

      iex> Info.url(container, 5432, "postgres")
      "postgres://localhost:55123"

      iex> Info.url(container, 6379, "redis")
      "redis://localhost:55124"
  """
  @spec url(Config.t(), integer(), String.t()) :: String.t()
  def url(%Config{} = container, container_port, scheme) do
    h = host(container)
    p = port(container, container_port)
    "#{scheme}://#{h}:#{p}"
  end

  @doc """
  Returns connection options suitable for `Postgrex.start_link/1`.

  Requires the container to have `:POSTGRES_USER`, `:POSTGRES_PASSWORD`,
  and `:POSTGRES_DB` environment variables set.
  """
  @spec pg_connect_opts(Config.t(), keyword()) :: keyword()
  def pg_connect_opts(%Config{} = container, overrides \\ []) do
    base = [
      hostname: host(container),
      port: port(container, 5432),
      username: container.environment[:POSTGRES_USER],
      password: container.environment[:POSTGRES_PASSWORD],
      database: container.environment[:POSTGRES_DB]
    ]

    Keyword.merge(base, overrides)
  end

  @doc """
  Returns connection options suitable for `MyXQL.start_link/1`.

  Requires the container to have `:MYSQL_USER`, `:MYSQL_PASSWORD`,
  and `:MYSQL_DATABASE` environment variables set.
  """
  @spec mysql_connect_opts(Config.t(), keyword()) :: keyword()
  def mysql_connect_opts(%Config{} = container, overrides \\ []) do
    base = [
      hostname: host(container),
      port: port(container, 3306),
      username: container.environment[:MYSQL_USER],
      password: container.environment[:MYSQL_PASSWORD],
      database: container.environment[:MYSQL_DATABASE]
    ]

    Keyword.merge(base, overrides)
  end

  @doc """
  Returns a Redis connection URL.

  If `:REDIS_PASSWORD` is set in the container environment, it is included
  in the URL.
  """
  @spec redis_url(Config.t()) :: String.t()
  def redis_url(%Config{} = container) do
    password = container.environment[:REDIS_PASSWORD]
    auth_part = if password, do: ":#{password}@", else: ""
    "redis://#{auth_part}#{host(container)}:#{port(container, 6379)}/"
  end

  @doc """
  Returns a MongoDB connection URL.

  Uses `:MONGO_INITDB_ROOT_USERNAME`, `:MONGO_INITDB_ROOT_PASSWORD`,
  and `:MONGO_INITDB_DATABASE` from the container environment.
  """
  @spec mongo_url(Config.t()) :: String.t()
  def mongo_url(%Config{} = container) do
    username = container.environment[:MONGO_INITDB_ROOT_USERNAME]
    password = container.environment[:MONGO_INITDB_ROOT_PASSWORD]
    database = container.environment[:MONGO_INITDB_DATABASE]
    "mongodb://#{username}:#{password}@#{host(container)}:#{port(container, 27_017)}/#{database}"
  end

  @doc """
  Returns a ClickHouse connection URL.

  Uses `:CLICKHOUSE_USER`, `:CLICKHOUSE_PASSWORD`, and `:CLICKHOUSE_DB` from the
  container environment. The HTTP interface (port 8123) is used by default.
  """
  @spec clickhouse_url(Config.t()) :: String.t()
  def clickhouse_url(%Config{} = container) do
    user = container.environment[:CLICKHOUSE_USER]
    pass = container.environment[:CLICKHOUSE_PASSWORD]
    database = container.environment[:CLICKHOUSE_DB]
    auth_part = if user, do: "#{user}:#{pass}@", else: ""
    "http://#{auth_part}#{host(container)}:#{port(container, 8123)}/?database=#{database}"
  end

  @doc """
  Returns an AMQP connection URL for RabbitMQ.

  Uses `:RABBITMQ_DEFAULT_USER`, `:RABBITMQ_DEFAULT_PASS`,
  and `:RABBITMQ_DEFAULT_VHOST` from the container environment.
  """
  @spec amqp_url(Config.t()) :: String.t()
  def amqp_url(%Config{} = container) do
    user = container.environment[:RABBITMQ_DEFAULT_USER]
    pass = container.environment[:RABBITMQ_DEFAULT_PASS]
    vhost = container.environment[:RABBITMQ_DEFAULT_VHOST] || "/"
    vhost_segment = if vhost == "/", do: "", else: "/#{vhost}"
    "amqp://#{user}:#{pass}@#{host(container)}:#{port(container, 5672)}#{vhost_segment}"
  end
end
