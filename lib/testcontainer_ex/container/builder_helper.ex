defmodule TestcontainerEx.Container.BuilderHelper do
  @moduledoc """
  Applies common labels and reuse logic to container configurations.

  This is the bridge between raw container configs and the orchestration
  layer — it adds session labels, reuse hashes, and language metadata.
  """

  import TestcontainerEx.Util.Constants

  alias TestcontainerEx.Container
  alias TestcontainerEx.Container.Config
  alias TestcontainerEx.Util.Hash

  require Logger

  @doc """
  Builds a container config and applies orchestration labels.

  Returns `{:reuse, config, hash}` or `{:noreuse, config, nil}`.
  """
  @spec build(struct(), map()) :: {:reuse, Config.t(), String.t()} | {:noreuse, Config.t(), nil}
  def build(builder, state) when is_map(state) and is_struct(builder) do
    config =
      Container.Builder.build(builder)
      |> Config.with_label(container_lang_label(), container_lang_value())
      |> Config.with_label(container_label(), "#{true}")

    reuse_enabled =
      config.reuse &&
        ("true" == Map.get(state.properties, "testcontainer_ex.reuse.enable", "false") ||
           config.force_reuse)

    if reuse_enabled and config.auto_remove do
      Logger.warning(
        "Reuse requested for a container set to auto-remove; ignoring reuse to avoid data loss. " <>
          "Call with_auto_remove(false) to enable reuse."
      )

      config
      |> Config.with_label(container_reuse(), "false")
      |> apply_common_labels(state)
      |> Kernel.then(&{:noreuse, &1, nil})
    else
      if reuse_enabled do
        hash = Hash.struct_to_hash(config)

        config
        |> Config.with_label(container_reuse(), "true")
        |> Config.with_label(container_reuse_hash_label(), hash)
        |> apply_common_labels(state)
        |> Kernel.then(&{:reuse, &1, hash})
      else
        config
        |> Config.with_label(container_reuse(), "false")
        |> apply_common_labels(state)
        |> Kernel.then(&{:noreuse, &1, nil})
      end
    end
  end

  defp apply_common_labels(config, state) do
    config
    |> Config.with_label(container_session_id_label(), state.session_id)
    |> Config.with_label(container_version_label(), library_version())
  end
end
