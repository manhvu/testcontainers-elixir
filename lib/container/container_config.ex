# SPDX-License-Identifier: MIT
defmodule TestcontainerEx.ContainerConfig do
  @moduledoc """
  Shared helpers for container configuration structs.

  Provides a macro `using_container_config/1` that injects the standard
  `with_check_image/2` and `with_reuse/1` setter functions into a container
  module. Every container struct is expected to have a `check_image` and a
  `reuse` field.

  ## Example

      defmodule MyContainer do
        use TestcontainerEx.ContainerConfig

        defstruct [:name, check_image: nil, reuse: false, ...]
      end

  After the `use` call the module will have `with_check_image/2` and
  `with_reuse/1` defined, matching the behaviour that was previously
  copy-pasted into every container file.
  """

  @doc """
  Injects `with_check_image/2` and `with_reuse/1` into the calling module.

  The macro expects the calling module to define a struct that includes the
  `:check_image` and `:reuse` keys.
  """
  defmacro __using__(_opts) do
    quote do
      import TestcontainerEx.Container.Config, only: [is_valid_image: 1]

      @doc """
      Sets the check image regex (or string) used to validate the container
      image name before starting.
      """
      @spec with_check_image(t(), String.t() | Regex.t()) :: t()
      def with_check_image(config, check_image) when is_valid_image(check_image) do
        struct!(config, check_image: check_image)
      end

      @doc """
      Enables or disables container reuse.
      """
      @spec with_reuse(t(), boolean()) :: t()
      def with_reuse(config, reuse) when is_boolean(reuse) do
        struct!(config, reuse: reuse)
      end
    end
  end
end
