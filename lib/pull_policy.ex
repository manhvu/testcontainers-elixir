defmodule TestcontainerEx.PullPolicy do
  @moduledoc """
  Pull policies that control whether an image is fetched from a remote registry
  before starting a container.
  """

  alias TestcontainerEx.PullPolicy

  @type t :: %__MODULE__{
          always_pull: boolean() | nil,
          pull_if_missing: boolean() | nil,
          pull_condition: (struct(), Req.Response.t() -> boolean()) | nil
        }

  defstruct [:always_pull, :pull_if_missing, :pull_condition]

  @spec always_pull() :: PullPolicy.t()
  @doc """
  Returns a pull policy that always pulls the image.

      iex> TestcontainerEx.PullPolicy.always_pull()
      %TestcontainerEx.PullPolicy{always_pull: true, pull_if_missing: nil, pull_condition: nil}
  """
  def always_pull do
    %__MODULE__{always_pull: true}
  end

  @spec never_pull() :: PullPolicy.t()
  @doc """
  Returns a pull policy that never pulls the image.

      iex> TestcontainerEx.PullPolicy.never_pull()
      %TestcontainerEx.PullPolicy{always_pull: nil, pull_if_missing: nil, pull_condition: nil}
  """
  def never_pull do
    %__MODULE__{}
  end

  @spec pull_if_missing() :: PullPolicy.t()
  @doc """
  Returns a pull policy that pulls only when the image is not present locally.

      iex> TestcontainerEx.PullPolicy.pull_if_missing()
      %TestcontainerEx.PullPolicy{always_pull: nil, pull_if_missing: true, pull_condition: nil}
  """
  def pull_if_missing do
    %__MODULE__{pull_if_missing: true}
  end

  @spec pull_condition(
          expr ::
            (config :: struct(), conn :: Req.Response.t() -> true | false)
        ) ::
          PullPolicy.t()
  def pull_condition(expr) do
    %__MODULE__{pull_condition: expr}
  end
end
