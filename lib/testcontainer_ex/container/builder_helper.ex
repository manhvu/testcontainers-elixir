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

    if config.reuse &&
         ("true" == Map.get(state.properties, "testcontainer_ex.reuse.enable", "false") ||
            config.force_reuse) do
      hash = Hash.struct_to_hash(config)

      config
      |> Config.with_label(container_reuse(), "true")
      |> Config.with_label(container_reuse_hash_label(), hash)
      |> Config.with_label(container_session_id_label(), state.session_id)
      |> Config.with_label(container_version_label(), library_version())
      |> Kernel.then(&{:reuse, &1, hash})
    else
      config
      |> Config.with_label(container_reuse(), "false")
      |> Config.with_label(container_session_id_label(), state.session_id)
      |> Config.with_label(container_version_label(), library_version())
      |> Kernel.then(&{:noreuse, &1, nil})
    end
  end
end
