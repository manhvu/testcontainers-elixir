defmodule TestcontainerEx.Connection.Strategies.Minikube do
  @moduledoc """
  Resolves the container engine host by evaluating `minikube docker-env`.

  This strategy activates when:
  - `MINIKUBE_ACTIVE_DOCKERD` or `MINIKUBE_PROFILE` is set, OR
  - The `minikube` binary is available on PATH

  It runs `minikube docker-env --shell none` to extract the container engine host.
  """

  @behaviour TestcontainerEx.Connection.Strategies.Behaviour

  alias TestcontainerEx.Connection.Url

  @minikube_bin "minikube"

  require Logger

  @impl true
  def resolve do
    cond do
      System.get_env("MINIKUBE_ACTIVE_DOCKERD") && System.get_env("CONTAINER_ENGINE_HOST") ->
        probe(System.get_env("CONTAINER_ENGINE_HOST"))

      System.get_env("MINIKUBE_ACTIVE_DOCKERD") && System.get_env("DOCKER_HOST") ->
        probe(System.get_env("DOCKER_HOST"))

      minikube_available?() ->
        eval_docker_env()

      true ->
        {:error, :minikube_not_available}
    end
  end

  defp minikube_available? do
    case System.cmd("which", [@minikube_bin], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  rescue
    ErlangError -> false
  end

  defp eval_docker_env do
    case System.cmd(@minikube_bin, ["docker-env", "--shell", "none"], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.find_value({:error, :no_docker_host_in_output}, fn
          "CONTAINER_ENGINE_HOST=" <> rest ->
            url = String.trim(rest) |> String.trim("\"")
            if url != "", do: {:ok, url}, else: nil

          _ ->
            nil
        end)
        |> case do
          {:ok, url} ->
            Logger.info("Connected to container engine via minikube: #{url}")
            probe(url)

          error ->
            error
        end

      {_output, _exit_code} ->
        {:error, :minikube_docker_env_failed}
    end
  end

  defp probe(url) do
    case Req.get("#{Url.construct(url)}/_ping") do
      {:ok, %{status: 200}} -> {:ok, url}
      {:error, reason} -> {:error, {:ping_failed, url, reason}}
    end
  end
end
