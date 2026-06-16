defmodule Mix.Tasks.Schemata.Gen.Spec do
  use Mix.Task

  @shortdoc "Print OpenApiSpex schema modules from a Schemata schema module"

  @moduledoc """
  Generates OpenApiSpex schema modules from a Schemata schema module and prints
  the result to stdout. Paste the output wherever it is needed.

  The module must implement `create/0` returning a `%Schemata.Schema{}`.

  ## Usage

      mix schemata.gen.spec \\
        --module MyApp.Schemas.EmployeeRequest \\
        --name MyApp.OpenAPI

      mix schemata.gen.spec \\
        --module MyApp.Schemas.SearchParams \\
        --name MyApp.OpenAPI \\
        --params

  ## Options

  * `--module` - Module implementing `create/0 :: %Schemata.Schema{}` (required)
  * `--name`   - Prefix applied to all generated module names (required)
  * `--params` - Generate a `parameters_schema/0` module instead of a `schema/0` module
  """

  @switches [module: :string, name: :string, params: :boolean]

  @impl true
  def run(argv) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(argv, strict: @switches)

    module = opts |> Keyword.fetch!(:module) |> then(&Module.concat([&1]))
    prefix = Keyword.fetch!(opts, :name)
    schema_name = module |> Module.split() |> List.last()
    schema = apply(module, :create, [])

    output =
      if Keyword.get(opts, :params) do
        module_name = "#{prefix}.#{Macro.camelize(schema_name)}"
        generate_params_output(schema, module_name)
      else
        components = DocsGeneratorHelper.Schemata.OpenAPI.components_from(schema, schema_name)
        generate_output(components, prefix)
      end

    Mix.shell().info(output)
  end

  # --- Output generator ---

  defp generate_output(components, prefix) do
    modules =
      Enum.map_join(components, "\n\n", fn {name, schema} ->
        generate_module("#{prefix}.#{Macro.camelize(name)}", schema, prefix)
      end)

    format(modules)
  end

  defp generate_params_output(
         %Schemata.Schema{properties: properties, required: required},
         module_name
       ) do
    required_fields = required || []

    entries =
      Enum.map_join(properties, ",\n", fn {name, definition} ->
        schema = definition |> DocsGeneratorHelper.Schemata.OpenAPI.to_openapi() |> render_schema("")
        req = name in required_fields
        ~s|Operation.parameter(:#{name}, :query, #{schema}, "#{name}", required: #{req})|
      end)

    source = """
    defmodule #{module_name} do
      alias OpenApiSpex.{Operation, Schema}

      def parameters_schema do
        [
          #{entries}
        ]
      end
    end
    """

    format(source)
  end

  defp generate_module(module_name, %OpenApiSpex.Reference{} = ref, prefix) do
    generate_schema_module(module_name, %OpenApiSpex.Schema{title: module_name, allOf: [ref]}, prefix)
  end

  defp generate_module(module_name, %OpenApiSpex.Schema{} = schema, prefix) do
    generate_schema_module(module_name, %{schema | title: module_name}, prefix)
  end

  defp generate_schema_module(module_name, schema, prefix) do
    """
    defmodule #{module_name} do
      alias OpenApiSpex.Schema

      @behaviour OpenApiSpex.Schema

      @impl OpenApiSpex.Schema
      def schema do
        #{render_schema(schema, prefix)}
      end
    end
    """
  end

  defp format(source) do
    source |> Code.format_string!() |> IO.iodata_to_binary()
  rescue
    _ -> source
  end

  # --- Schema rendering ---

  defp render_schema(%OpenApiSpex.Reference{"$ref": "#/components/schemas/" <> name}, prefix),
    do: "#{prefix}.#{Macro.camelize(name)}"

  defp render_schema(%OpenApiSpex.Reference{"$ref": ref}, _prefix),
    do: ~s|%Reference{"$ref": #{inspect(ref)}}|

  defp render_schema(%OpenApiSpex.Schema{} = schema, prefix) do
    fields =
      schema
      |> Map.from_struct()
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == [] end)
      |> Enum.sort_by(fn {k, _} -> field_priority(k) end)
      |> Enum.map_join(", ", fn
        {:required, v} -> "required: #{render_required(v)}"
        {:pattern, v} when is_binary(v) -> "pattern: #{render_pattern(v)}"
        {k, v} -> "#{render_key(k)}: #{render_value(v, prefix)}"
      end)

    "%Schema{#{fields}}"
  end

  defp render_value(%OpenApiSpex.Schema{} = s, prefix), do: render_schema(s, prefix)
  defp render_value(%OpenApiSpex.Reference{} = r, prefix), do: render_schema(r, prefix)

  defp render_value(map, prefix) when is_map(map),
    do: "%{#{Enum.map_join(map, ", ", fn {k, v} -> render_map_entry(k, v, prefix) end)}}"

  defp render_value(list, prefix) when is_list(list),
    do: "[#{Enum.map_join(list, ", ", &render_value(&1, prefix))}]"

  defp render_value(value, _prefix), do: inspect(value)

  defp field_priority(:type), do: 0
  defp field_priority(:title), do: 1
  defp field_priority(:required), do: 3
  defp field_priority(:additionalProperties), do: 4
  defp field_priority(_), do: 2

  defp render_required(list) when is_list(list),
    do: "[#{Enum.map_join(list, ", ", fn s -> ":#{s}" end)}]"

  defp render_pattern(pattern) when is_binary(pattern) do
    escaped = String.replace(pattern, "/", "\\/")
    "~r/#{escaped}/u"
  end

  defp render_key(key) when is_atom(key) do
    str = Atom.to_string(key)
    if str =~ ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/, do: str, else: ~s|"#{str}"|
  end

  defp render_map_entry(key, value, prefix) when is_atom(key),
    do: "#{render_key(key)}: #{render_value(value, prefix)}"

  defp render_map_entry(key, value, prefix),
    do: "#{inspect(key)} => #{render_value(value, prefix)}"
end
