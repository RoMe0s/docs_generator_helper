# DocsGeneratorHelper

Helps to generate open_api docs using existing schemata schemas and existing tests for generating examples etc.
Needs AI/human to orchestrate the process
Needs human to check the output :(

## Installation

```elixir
def deps do
  [
    {:docs_generator_helper, github: "RoMe0s/docs_generator_helper"}
  ]
end
```

## Idea

There are several libs used in the process:

1. open_api_spex - used for describing open_api schema, generating doc, testing request and responses against schema

2. bureaucrat - used for collecting examples from tests, WILL BE REMOVED after the first iteration

3. schemata - schemata lib, we have some extensions for the lib here to make writing open_api spex easier. Later it will be moved to schema lib maybe

So, eventually we want to have only one new dependency - open_api_spex.
Requests and responses will be validated agains that schema in TEST env only.
So, CI will fails if something is changed.
Of course it will not give the 1:1 code to doc, because removing some optional fields will not lead to errors, but we will try to keep it up to date.

Schemata converter can be saved or even moved to schemata lib (it will force us to add open_api_spex as dependency to schemata) or we can keep this lib with huge refactoring after stage 1 and deleting bureaucrat.

## Usage

You have to add stub api spec file(it's default file, more details at open_api_spex lib doc page).
Replace Til in module name and path with your module name, path for this - apps/til/lib/til_web/api_spec.ex.

      ```elixir
      defmodule TilWeb.ApiSpec do
        @moduledoc false

        alias OpenApiSpex.{Info, OpenApi, Paths, Server}

        @behaviour OpenApi

        @impl OpenApi
        def spec do
          %OpenApi{
            servers: [
              %Server{
                url: "https://yourapi.example.com"
              }
            ],
            info: %Info{
              title: "My App",
              version: "1.0"
            },
            paths: Paths.from_router(TilWeb.Router)
          }
          |> OpenApiSpex.resolve_schema_modules()
        end
      end
      ```

In your existing conn_case.ex you have to remove next lines:

      ```elixir
      import Phoenix.ConnTest
      ```

Add new lines:


      ```elixir
      import Phoenix.ConnTest, only: :functions
      import Bureaucrat.Helpers
      import Bureaucrat.Macros, except: [get: 2, get: 3, post: 2, post: 3, put: 2, put: 3, patch: 2, patch: 3, delete: 2, delete: 3]
      import DocsGeneratorHelper.TestMacros
      ```

Also you have to build your basic conn in different way:

      ```elixir
      conn =
        Phoenix.ConnTest.build_conn()
        |> Plug.Conn.put_req_header("accept", "application/json")
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> OpenApiSpex.Plug.PutApiSpec.call(OpenApiSpex.Plug.PutApiSpec.init(module: TilWeb.ApiSpec)) # replace with your spec
        |> Plug.Conn.put_private(:open_api_validate_request, true)
      ```

And add helper function for skipping open_api_spex request validation for cases when you want to test invalid input:
      ```elixir
      def skip_open_api_validate_request(conn),
        do: Plug.Conn.put_private(conn, :open_api_validate_request, false)
      ```

Now we have to enable additional plug for test env only:
In apps/til/lib/til_web.ex find function `controller` and change it.

From:
      ```elixir
      def controller do
        quote do
          use Phoenix.Controller, formats: [:json]

          import Plug.Conn

          unquote(verified_routes())
        end
      end
      ```

To:
      ```elixir
      def controller do
        test_env_plugs =
          if Mix.env() == :test do
            quote do: plug(TilWeb.Plugs.OpenApiValidate)
          end

        quote do
          use Phoenix.Controller, formats: [:json]

          import Plug.Conn

          unquote(verified_routes())
          unquote(test_env_plugs)
        end
      end
      ```
