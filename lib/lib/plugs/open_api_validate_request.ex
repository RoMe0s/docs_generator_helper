defmodule DocsGeneratorHelper.Plugs.OpenApiValidateRequest do
  @moduledoc false

  @behaviour Plug

  alias OpenApiSpex.Plug.PutApiSpec
  alias Plug.Conn

  @impl Plug
  def init(_opts),
    do: OpenApiSpex.Plug.CastAndValidate.init(json_render_error_v2: true, replace_params: false)

  @impl Plug
  def call(
        %{
          private: %{
            phoenix_controller: controller,
            open_api_validate_request: true
          }
        } = conn,
        opts
      ) do
    if function_exported?(controller, :open_api_operation, 1) do
      OpenApiSpex.Plug.CastAndValidate.call(conn, opts)
    else
      conn
    end
  end

  def call(
        conn = %{
          private: %{
            phoenix_controller: controller,
            phoenix_action: action,
            open_api_spex: _
          }
        },
        _opts
      ) do
    if function_exported?(controller, :open_api_operation, 1) do
      {_spec, operation_lookup} = PutApiSpec.get_spec_and_operation_lookup(conn)

      operation =
        case operation_lookup[{controller, action}] do
          nil ->
            operation = controller.open_api_operation(action)

            PutApiSpec.get_and_cache_controller_action(
              conn,
              operation.operationId,
              {controller, action}
            )

          operation ->
            operation
        end

      put_operation_id(conn, operation)
    else
      conn
    end
  end

  defp put_operation_id(conn, operation) do
    private_data =
      conn
      |> Map.get(:private)
      |> Map.get(:open_api_spex, %{})
      |> Map.put(:operation_id, operation.operationId)

    Conn.put_private(conn, :open_api_spex, private_data)
  end
end
