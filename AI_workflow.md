## Workflow

## OFFTOP
Do not ask to run formatters etc. all this stuff will be done later by developer

## Step 1. Collecting basic info

Ask developer to provide router module name, remember it as #{router_module}
Remember web module name as #{web_module}

## Step 2. Choose the controller

Run
  ```
  MIX_ENV=test mix open_api_coverage #{router_module}
  ```
Choose first entry from the result list
Remember the method (e.g. GET, POST) as #{route_method}
Remember the route path as #{route_path}

## Step 3. Generate request schema if possible

Ask developer to provide request json_schema module name
Remember it as a #{request_schema_module_name}

Run for `GET` request:
  ```
  mix schemata.gen.spec --module #{request_schema_module_name} --name #{web_module}.#{schema in plural}.Schemas.#{action}Request --params
  ```

Run for `POST/PATCH/PUT` request:
  ```
  mix schemata.gen.spec --module #{request_schema_module_name} --name #{web_module}.#{schema in plural}.Schemas.#{action}Request
  ```

## Step 4. Update controller

Definitions:
#{action} - action name/function name in controller
#{description} - AI generated short summary, e.g. "Create new User" or smth. like that
#{Schema in plural} - Camel cased schema name in plural, e.g. Users, Persons etc.
#{schema} - Camel cased schema name, e.g. User, Person etc.
#{response description} - AI generated short summary of response, e.g. "Create new User response" or smth. like that
#{schema in human readable} - If module schema name is UserSomeRelation than it should be User Some Relation.

Add stub info to controller(if not exists):
  ```Elixir
  use OpenApiSpex.ControllerSpecs
  ```
After
  ```Elixir
  use #{web_module}, :controller
  ```

Right before the action add next stub code:

For `GET` requests:
  ```Elixir
  # TODO: review AI-generated
  operation(#{action},
    summary: #{description},
    parameters: #{web_module}.#{schema in plural}.Schemas.#{action}Request.parameters_schema(),
    responses: %{
      200 => {"#{response description}", "application/json", #{web_module}.#{Schema in plural}.Schemas.#{action}Response}
    }
  )
  ```

For `POST/PATCH/PUT` requests:
  ```Elixir
  # TODO: review AI-generated
  operation(#{action},
    summary: #{description},
    request_body: {"Request params", "application/json", #{web_module}.#{schema in plural}.Schemas.#{action}Request},
    responses: %{
      200 => {"#{response description}", "application/json", #{web_module}.#{Schema in plural}.Schemas.#{action}Response}
    }
  )
  ```

## Step 5. Generate stub response spec module:

module_path - apps/missed_part/#{web_module}/schemas/#{Schema in plural}/#{action}_response.ex (of course, everything in lower case etc.)

  ```Elixir
  defmodule #{web_module}.#{Schema in plural}.Schemas.#{action}Response do
    @moduledoc false

    alias OpenApiSpex.Schema

    @behaviour OpenApiSpex.Schema

    # TODO: review AI-generated

    @impl OpenApiSpex.Schema
    def schema do
      %Schema{
        type: :object,
        title: #{response description},
        properties: %{
          data: %Schema{
            type: :object,
            title: #{schema in human readable}
          }
        },
        required: [:data],
        additionalProperties: false
      }
    end
  end
  ```

## Step 6. Try to find test file for the controller

Usually it has same file name as controller with `_test.exs` suffix. e.g. `users_controller_test.exs`
Do it using one and only one try, stop the process if related test does not exist and ask developer to provide the path
Remember it as a #{test_path}

## Step 7. Try to find test case for happy path

Use next pattern: `json_response(200)`
Do it using one and only one try, stop the process if related test does not exist and ask developer to provide the line
Remember it as a #{test_line}

## Step 8. Refresh examples:

This example can not work for everyone, required flags are `MIX_ENV=test` and `BUREUCRAT_DOC=true`
DB_HOST and DB_PORT can be different and can be skipped, discuss it with the dev

  ```
  DB_HOST=localhost DB_PORT=42529 MIX_ENV=test BUREUCRAT_DOC=true mix test #{test_path}:#{test_line}
  ```

## Step 9. Find response example:

If test didn't fail than read `doc/temp_open_api.json` file and find success response example using `#{route_path}`

Use #{route_path}, "responses", "200" or "201", "examples", "value" anchors:

  ```
  "/pfu/mvtn_review_request": { <- #{route path}
    "post": {
      ...
      "responses": {
        "200": {
          "content": {
            "application/json": {
              "examples": {
                "...": {
                  "value": {
                    "data": {
                      "id": "06bb13ed-e71e-4712-8f5c-528d1225d087",
                      "request_id": "47d4f3ad-1497-4768-831d-7aa83ce7c542",
                      "result": 200
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
  ```

If you cannot find the example, ask the developer about future steps or providing the example

## Step 10. Generate response

Using example from file or from developer generate schema and place it into `#{web_module}.#{Schema in plural}.Schemas.#{action}Response` by adding to data.properties.
Also, add additionalProperties: false for `data` object.
