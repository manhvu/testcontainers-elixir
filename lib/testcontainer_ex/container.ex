defmodule TestcontainerEx.Container do
  @moduledoc """
  Convenience module for container configuration.

  Delegates to `TestcontainerEx.Container.Config` for all operations.
  """

  alias TestcontainerEx.Container.Config

  # Delegate all public functions from Config
  defdelegate new(image), to: Config
  defdelegate with_waiting_strategy(config, wait_fn), to: Config
  defdelegate with_waiting_strategies(config, wait_fns), to: Config
  defdelegate with_environment(config, key, value), to: Config
  defdelegate with_exposed_port(config, port), to: Config
  defdelegate with_exposed_ports(config, ports), to: Config
  defdelegate with_fixed_port(config, port, host_port \\ nil), to: Config
  defdelegate with_bind_mount(config, host_src, container_dest, options \\ "ro"), to: Config
  defdelegate with_bind_volume(config, volume, container_dest, read_only \\ false), to: Config
  defdelegate with_label(config, key, value), to: Config
  defdelegate with_cmd(config, cmd), to: Config
  defdelegate with_auto_remove(config, auto_remove), to: Config
  defdelegate with_privileged(config, privileged), to: Config
  defdelegate with_reuse(config, reuse), to: Config
  defdelegate with_force_reuse(config, force_reuse), to: Config
  defdelegate with_auth(config, username, password), to: Config
  defdelegate with_check_image(config, check_image), to: Config
  defdelegate with_network_mode(config, mode), to: Config
  defdelegate with_network(config, network_name), to: Config
  defdelegate with_hostname(config, hostname), to: Config
  defdelegate with_name(config, name), to: Config
  defdelegate with_copy_to(config, target, source), to: Config
  defdelegate with_pull_policy(config, policy), to: Config
  defdelegate with_log_consumer(config, level), to: Config
  defdelegate with_request_id(config, request_id), to: Config
  defdelegate mapped_port(container, port), to: Config
  defdelegate valid_image(config), to: Config
  defdelegate valid_image!(config), to: Config
end
