import Config

config :logger, level: :warning

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:testcontainer_ex, :container_id, :image, :session_id, :request_id]
