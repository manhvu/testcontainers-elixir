import Config

config :logger, level: :debug

# Format logger output to include metadata for TestcontainerEx debugging
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:testcontainer_ex, :container_id, :image, :session_id, :engine, :request_id]
