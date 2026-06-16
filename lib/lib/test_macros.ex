defmodule DocsGeneratorHelper.TestMacros do
  @moduledoc """
  Extends Bureaucrat.Macros with automatic OpenAPI response validation.

  ## Usage

  On `ConnCase` file, change this

      import Phoenix.ConnTest

  To

      import Phoenix.ConnTest, only: :functions
      import Bureaucrat.Helpers
      import Bureaucrat.Macros, except: [get: 2, get: 3, post: 2, post: 3, put: 2, put: 3, patch: 2, patch: 3, delete: 2, delete: 3]
      import DocsGeneratorHelper.TestMacros
  """

  @doc_http_methods [:get, :post, :put, :patch, :delete]

  @undocumented_method_names %{
    get: :get_undocumented,
    post: :post_undocumented,
    put: :put_undocumented,
    patch: :patch_undocumented,
    delete: :delete_undocumented
  }

  for method <- @doc_http_methods do
    @doc """
    Dispatches test request with documentation.
    Documents: get, post, put, patch and delete requests.
    """
    defmacro unquote(method)(conn, path_or_action, params_or_body \\ nil) do
      method = unquote(method)

      quote do
        conn =
          Phoenix.ConnTest.dispatch(
            unquote(conn),
            @endpoint,
            unquote(method),
            unquote(path_or_action),
            unquote(params_or_body)
          )

        if conn.halted do
          conn
        else
          conn =
            if "BUREUCRAT_DOC" |> System.get_env("") |> String.downcase() == "true" do
              accept_header = conn |> Plug.Conn.get_req_header("accept") |> List.first() || ""
              content_header = conn |> Plug.Conn.get_req_header("content-type") |> List.first() || ""
              is_json = Enum.any?([accept_header, content_header], &String.contains?(&1, "json"))

              if is_json do
                try do
                  doc(conn)
                rescue
                  # Bureaucrat fails to get controller/action when request is halted from a plug.
                  # In this case, we skip documentation. Here is the reason:
                  # https://github.com/api-hogs/bureaucrat/blob/8ac7efd04dafdedfe986ba0032e7cb1cbac1df5d/lib/bureaucrat/helpers.ex#L147
                  e in MatchError ->
                    conn
                end
              else
                conn
              end
            else
              conn
            end

          if Map.has_key?(conn.private, :open_api_spex) && Map.has_key?(conn.private.open_api_spex, :operation_id) do
            OpenApiSpex.TestAssertions.assert_operation_response(conn)
          else
            conn
          end
        end
      end
    end
  end

  for method <- @doc_http_methods do
    @doc """
    Dispatches test request without documentation.
    Implements: get_undocumented, post_undocumented, put_undocumented, ..., macros to skip doc.
    """
    method_name = @undocumented_method_names[method]

    defmacro unquote(method_name)(conn, path_or_action, params_or_body \\ nil) do
      method = unquote(method)

      quote do
        Phoenix.ConnTest.dispatch(
          unquote(conn),
          @endpoint,
          unquote(method),
          unquote(path_or_action),
          unquote(params_or_body)
        )
      end
    end
  end
end
