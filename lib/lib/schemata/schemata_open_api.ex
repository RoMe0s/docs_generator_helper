defmodule DocsGeneratorHelper.Schemata.OpenAPI do
  alias OpenApiSpex.{Reference, Schema}
  alias Schemata.Definitions, as: Def
  alias Schemata.Validators, as: Val

  @doc """
  Returns all OpenAPI component schemas derived from a `%Schemata.Schema{}`.

  The root schema is keyed by `root_name`. All `definitions` entries are promoted
  to top-level keys. References are rewritten from `#/definitions/<name>` to
  `#/components/schemas/<name>`.

  Callback validators that have no native OpenAPI equivalent are preserved as
  `"x-schemata-callbacks"` extensions for documentation generators.
  """
  @spec components_from(Schemata.Schema.t(), String.t()) ::
          %{String.t() => Schema.t() | Reference.t()}
  def components_from(%Schemata.Schema{} = schema, root_name) do
    defs =
      Map.new(schema.definitions, fn {key, value} ->
        {to_string(key), to_openapi(value)}
      end)

    Map.put(defs, root_name, to_openapi_root(schema))
  end

  @doc """
  Converts a Schemata definition to an `%OpenApiSpex.Schema{}` or `%OpenApiSpex.Reference{}`.

  Callback validators are preserved in the `extensions` field under
  `"x-schemata-callbacks"`.
  """
  @spec to_openapi(term()) :: Schema.t() | Reference.t()
  def to_openapi(%Def.String{opts: opts}) do
    %Schema{type: :string}
    |> put_opt(:minLength, opts[:minLength])
    |> put_opt(:maxLength, opts[:maxLength])
    |> put_nullable(opts)
    |> put_callbacks(opts)
  end

  def to_openapi(%Def.Integer{opts: opts}) do
    %Schema{type: :integer}
    |> put_opt(:minimum, opts[:minimum])
    |> put_opt(:maximum, opts[:maximum])
    |> put_opt(:exclusiveMinimum, opts[:exclusiveMinimum])
    |> put_opt(:exclusiveMaximum, opts[:exclusiveMaximum])
    |> put_nullable(opts)
    |> put_callbacks(opts)
  end

  def to_openapi(%Def.Number{opts: opts}) do
    %Schema{type: :number}
    |> put_opt(:minimum, opts[:minimum])
    |> put_opt(:maximum, opts[:maximum])
    |> put_opt(:exclusiveMinimum, opts[:exclusiveMinimum])
    |> put_opt(:exclusiveMaximum, opts[:exclusiveMaximum])
    |> put_opt(:multipleOf, opts[:multipleOf])
    |> put_nullable(opts)
    |> put_callbacks(opts)
  end

  def to_openapi(%Def.Boolean{opts: opts}),
    do: %Schema{type: :boolean} |> put_nullable(opts) |> put_callbacks(opts)

  def to_openapi(%Def.Date{opts: opts}),
    do: %Schema{type: :string, format: :date} |> put_nullable(opts) |> put_callbacks(opts)

  def to_openapi(%Def.Datetime{opts: opts}),
    do:
      %Schema{type: :string, format: :"date-time"}
      |> put_nullable(opts)
      |> put_callbacks(opts)

  def to_openapi(%Def.Time{opts: opts}),
    do:
      %Schema{type: :string, pattern: "^([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]$"}
      |> put_nullable(opts)
      |> put_callbacks(opts)

  def to_openapi(%Def.Email{opts: opts}),
    do: %Schema{type: :string, format: :email} |> put_nullable(opts) |> put_callbacks(opts)

  def to_openapi(%Def.Hostname{opts: opts}),
    do: %Schema{type: :string, format: :hostname} |> put_nullable(opts) |> put_callbacks(opts)

  def to_openapi(%Def.UUID{opts: opts}),
    do: %Schema{type: :string, format: :uuid} |> put_nullable(opts) |> put_callbacks(opts)

  def to_openapi(%Def.Regex{pattern: pattern, opts: opts}) do
    %Schema{type: :string, pattern: to_pattern_string(pattern)}
    |> put_opt(:minLength, opts[:minLength])
    |> put_opt(:maxLength, opts[:maxLength])
    |> put_nullable(opts)
    |> put_callbacks(opts)
  end

  def to_openapi(%Def.Enum{enum: values, type: type, opts: opts}) do
    nullable = is_list(type) or Keyword.get(opts, :null, false)
    clean_values = Enum.reject(values, &is_nil/1)

    %Schema{type: :string, enum: clean_values}
    |> then(fn s -> if nullable, do: %{s | nullable: true}, else: s end)
    |> put_callbacks(opts)
  end

  def to_openapi(%Def.Object{properties: properties, opts: opts}) do
    required = Keyword.get(opts, :required, [])

    %Schema{
      type: :object,
      properties: map_properties(properties),
      required: nonempty(required),
      additionalProperties: Keyword.get(opts, :additionalProperties, false)
    }
    |> put_nullable(opts)
    |> put_callbacks(opts)
  end

  def to_openapi(%Def.Array{items: items, opts: opts}) when is_list(items) do
    %Schema{
      type: :array,
      items: %Schema{oneOf: Enum.map(items, &to_openapi/1)}
    }
    |> put_array_opts(opts)
    |> put_nullable(opts)
    |> put_callbacks(opts)
  end

  def to_openapi(%Def.Array{items: item, opts: opts}) do
    %Schema{
      type: :array,
      items: to_openapi(item)
    }
    |> put_array_opts(opts)
    |> put_nullable(opts)
    |> put_callbacks(opts)
  end

  def to_openapi(%Def.OneOf{one_of: schemas, opts: opts}),
    do:
      %Schema{oneOf: Enum.map(schemas, &to_openapi/1)}
      |> put_nullable(opts)
      |> put_callbacks(opts)

  def to_openapi(%Def.Ref{ref: ref}),
    do: %Reference{"$ref": "#/components/schemas/#{ref}"}

  # --- Callback serialization ---

  defp serialize_callback(%Val.RequiredIf{
         field: field,
         required_if_field: required_if_field,
         required_if_value: value
       }) do
    %{
      "type" => "required_if",
      "field" => field,
      "required_if_field" => required_if_field,
      "required_if_value" => serialize_value(value)
    }
  end

  defp serialize_callback(%Val.RequiredOneOf{properties: properties}) do
    %{"type" => "required_one_of", "properties" => properties}
  end

  defp serialize_callback(%Val.RequiredWith{
         field: field,
         required_with_field: required_with_field
       }) do
    %{"type" => "required_with", "field" => field, "required_with_field" => required_with_field}
  end

  defp serialize_callback(%Val.ValidateIf{
         filters_map: filters_map,
         base_field: base_field,
         filter_field: filter_field,
         rule: rule
       }) do
    %{
      "type" => "validate_if",
      "base_field" => base_field,
      "filter_field" => filter_field,
      "rule" => to_string(rule),
      "filters" => Map.new(filters_map, fn {k, v} -> {k, serialize_value(v)} end)
    }
  end

  defp serialize_callback(%Val.Equals{value: value}) do
    %{"type" => "equals", "value" => serialize_value(value)}
  end

  defp serialize_callback(%Val.DateFrom{value: value, equal: equal}) do
    base = %{"type" => "date_from", "value" => to_string(value)}
    if equal, do: Map.put(base, "equal", true), else: base
  end

  defp serialize_callback(%Val.DateTo{value: value, equal: equal}) do
    base = %{"type" => "date_to", "value" => to_string(value)}
    if equal, do: Map.put(base, "equal", true), else: base
  end

  defp serialize_callback(%Val.Regexs{regexs: regexs}) do
    %{
      "type" => "regexs",
      "patterns" =>
        Enum.map(regexs, fn
          {:not, %Regex{source: src}} -> %{"not" => src}
          %Regex{source: src} -> %{"match" => src}
        end)
    }
  end

  defp serialize_callback(%Val.ObjectUniqBy{value: value}) when is_binary(value),
    do: %{"type" => "object_uniq_by", "field" => value}

  defp serialize_callback(%Val.ObjectUniqBy{}),
    do: %{"type" => "object_uniq_by"}

  defp serialize_callback(%Val.RequiredItems{value_path: path, required_values: values}) do
    %{"type" => "required_items", "value_path" => path, "required_values" => values}
  end

  defp serialize_callback(%Val.Any{validations: validations}) do
    %{
      "type" => "any",
      "validations" =>
        Enum.map(validations, fn
          {v, msg} when is_binary(msg) -> v |> serialize_callback() |> Map.put("message", msg)
          {v, _} -> serialize_callback(v)
          v -> serialize_callback(v)
        end)
    }
  end

  defp serialize_value(f) when is_function(f), do: "<function>"
  defp serialize_value(%Regex{source: src}), do: src
  defp serialize_value(%Date{} = d), do: Date.to_iso8601(d)

  defp serialize_value({op, val}) when is_atom(op),
    do: %{"op" => Atom.to_string(op), "value" => val}

  defp serialize_value(a) when is_atom(a) and not is_boolean(a) and not is_nil(a),
    do: Atom.to_string(a)

  defp serialize_value(v), do: v

  # --- Helpers ---

  defp to_openapi_root(%Schemata.Schema{} = schema) do
    required = schema.required

    %Schema{
      type: :object,
      properties: map_properties(schema.properties),
      required: nonempty(required),
      additionalProperties: schema.additionalProperties
    }
    |> put_callbacks_list(schema.callbacks)
  end

  defp map_properties(props) when is_map(props),
    do: Map.new(props, fn {k, v} -> {k, to_openapi(v)} end)

  defp put_callbacks(schema, opts),
    do: put_callbacks_list(schema, Keyword.get(opts, :callbacks, []))

  defp put_callbacks_list(schema, []), do: schema

  defp put_callbacks_list(schema, callbacks) do
    %{
      schema
      | extensions: %{"x-schemata-callbacks" => Enum.map(callbacks, &serialize_callback/1)}
    }
  end

  defp put_nullable(schema, opts) do
    if Keyword.get(opts, :null), do: %{schema | nullable: true}, else: schema
  end

  defp put_opt(schema, _key, nil), do: schema
  defp put_opt(schema, key, value), do: Map.put(schema, key, value)

  defp put_array_opts(schema, opts) do
    schema
    |> put_opt(:minItems, opts[:minItems])
    |> put_opt(:maxItems, opts[:maxItems])
    |> put_opt(:uniqueItems, opts[:uniqueItems])
  end

  defp nonempty([]), do: nil
  defp nonempty(list), do: list

  defp to_pattern_string(%Regex{source: source}), do: source
  defp to_pattern_string(pattern) when is_binary(pattern), do: pattern
end
