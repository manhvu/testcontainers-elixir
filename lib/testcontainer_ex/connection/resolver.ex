defmodule TestcontainerEx.Connection.Resolver do
  @moduledoc """
  Orchestrates host resolution strategies in priority order.

  Tries each strategy in sequence until one succeeds.
  Returns `{:ok, url}` or `{:error, reasons}`.
  """

  alias TestcontainerEx.Connection.Strategies

  @strategies [
    Strategies.Properties,
    Strategies.Env,
    Strategies.Dotenv,
    Strategies.ContainerEnv,
    Strategies.Minikube,
    Strategies.Socket
  ]

  @doc """
  Resolves the container engine host URL by trying each strategy in order.
  """
  @spec resolve() :: {:ok, String.t()} | {:error, [term()]}
  def resolve do
    do_resolve(@strategies, [])
  end

  defp do_resolve([], errors), do: {:error, Enum.reverse(errors)}

  defp do_resolve([strategy | rest], errors) do
    case strategy.resolve() do
      {:ok, url} -> {:ok, url}
      {:error, reason} -> do_resolve(rest, [reason | errors])
    end
  end
end
