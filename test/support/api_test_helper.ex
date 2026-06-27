defmodule TestcontainerEx.ApiTestHelper do
  @moduledoc """
  Helper for stubbing Docker API responses in tests.
  """

  def conn(stubs) do
    adapter = fn request ->
      url =
        request.url
        |> to_string()
        |> URI.parse()
        |> then(fn uri ->
          if uri.query, do: "#{uri.path}?#{uri.query}", else: uri.path
        end)

      method = request.method

      case Map.get(stubs, {method, url}) do
        {status, body} when is_binary(body) ->
          response =
            Req.Response.new(
              status: status,
              body: body,
              headers: [{"content-type", "text/plain"}]
            )

          {request, response}

        {status, body} when is_map(body) or is_list(body) ->
          response =
            Req.Response.new(
              status: status,
              body: Jason.encode!(body),
              headers: [{"content-type", "application/json"}]
            )

          {request, response}

        nil ->
          response =
            Req.Response.new(
              status: 404,
              body: "not found",
              headers: [{"content-type", "text/plain"}]
            )

          {request, response}
      end
    end

    Req.new(adapter: adapter)
  end
end
