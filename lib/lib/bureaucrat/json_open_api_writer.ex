defmodule DocsGeneratorHelper.JsonOpenApiWriter do
  @moduledoc """
  Custom Bureaucrat writer that produces an OpenAPI 3.0 JSON file enriched with
  real request/response examples from tests.

  ## How it works

  The base spec (all paths, parameters, schemas, and operation definitions) comes
  from `TilWeb.ApiSpec.spec()`, which reflects the `operation/2` declarations in
  controllers. Bureaucrat adds recorded test interactions on top as response
  examples under `paths.<path>.<method>.responses.<status>.content.application/json.examples`.

  ## Usage

  Tests are recorded automatically via `Bureaucrat.Macros` — every `get/post/put/
  patch/delete` call that returns JSON is captured without any manual `doc()` calls.
  To exclude a request from documentation, use the `_undocumented` variants
  (e.g. `get_undocumented`).

  Generate the output file:

      BUREUCRAT_DOC=true mix test
  """

  def write(records, path) do
    spec = %{}
    # TilWeb.ApiSpec.spec()
    # |> Jason.encode!()
    # |> Jason.decode!()

    updated = Enum.reduce(records, spec, &add_example(&2, &1))

    File.write!(path, Jason.encode!(updated, pretty: true))
  end

  defp add_example(spec, conn) do
    method = String.downcase(conn.method)
    status = to_string(conn.status)
    path_template = find_path_template(spec["paths"] || %{}, conn.request_path)

    case path_template do
      nil ->
        spec

      template ->
        desc = conn.assigns.bureaucrat_desc || "Example"
        body = decode_body(conn.resp_body)
        base = ["paths", template, method, "responses", status, "content", "application/json"]
        existing_schema = get_in(spec, base ++ ["schema"])

        spec
        |> deep_put(base ++ ["examples", desc], %{"summary" => desc, "value" => body})
        |> maybe_infer_schema(base ++ ["schema"], body, existing_schema)
    end
  end

  defp maybe_infer_schema(spec, _path, _body, %{"$ref" => _}), do: spec
  defp maybe_infer_schema(spec, _path, _body, %{"properties" => _}), do: spec
  defp maybe_infer_schema(spec, path, body, _), do: deep_put(spec, path, infer_schema(body))

  defp infer_schema(nil), do: %{"nullable" => true}
  defp infer_schema(v) when is_boolean(v), do: %{"type" => "boolean"}
  defp infer_schema(v) when is_integer(v), do: %{"type" => "integer"}
  defp infer_schema(v) when is_float(v), do: %{"type" => "number"}
  defp infer_schema(v) when is_binary(v), do: %{"type" => "string"}

  defp infer_schema(v) when is_list(v) do
    items = if Enum.empty?(v), do: %{}, else: infer_schema(List.first(v))
    %{"type" => "array", "items" => items}
  end

  defp infer_schema(v) when is_map(v) do
    %{
      "type" => "object",
      "properties" => Map.new(v, fn {k, val} -> {to_string(k), infer_schema(val)} end)
    }
  end

  defp find_path_template(paths, request_path) do
    Enum.find(Map.keys(paths), fn template ->
      pattern = String.replace(template, ~r/\{[^}]+\}/, "[^/]+")
      Regex.match?(~r"^#{pattern}$", request_path)
    end)
  end

  defp decode_body(""), do: nil

  defp decode_body(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> decoded
      _ -> body
    end
  end

  defp deep_put(map, [key], value),
    do: Map.put(map || %{}, key, value)

  defp deep_put(map, [key | rest], value),
    do: Map.put(map || %{}, key, deep_put(Map.get(map || %{}, key, %{}), rest, value))
end
