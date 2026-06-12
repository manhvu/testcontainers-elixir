defmodule TestcontainerEx.Connection.Strategies.Properties do
  @moduledoc """
  Resolves the container engine host from `.testcontainer_ex.properties`.

  Checks `tc.host` first, then `docker.host`.
  """

  @behaviour TestcontainerEx.Connection.Strategies.Behaviour

  alias TestcontainerEx.Connection.Url
  alias TestcontainerEx.Util.PropertiesParser

  @properties ["tc.host", "docker.host"]
  @default_file "~/.testcontainer_ex.properties"

  @impl true
  def resolve do
    with {:ok, properties} <- PropertiesParser.read_property_file(@default_file),
         {:ok, url} <- find_url(properties),
         :ok <- probe(url) do
      {:ok, url}
    end
  end

  defp find_url(properties) do
    Enum.find_value(@properties, {:error, :not_found}, fn key ->
      case Map.fetch(properties, key) do
        {:ok, url} when is_binary(url) and url != "" -> {:ok, url}
        _ -> nil
      end
    end)
  end

  defp probe(url) do
    case Req.get("#{Url.construct(url)}/_ping") do
      {:ok, %{status: 200}} -> :ok
      {:error, reason} -> {:error, {:ping_failed, reason}}
    end
  end
end
