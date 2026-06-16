defmodule Mix.Tasks.OpenApiCoverage do
  @moduledoc """
  Prints controllers and actions that do not have an OpenAPI operation defined.

  Usage:
      mix open_api_coverage TilWeb.Router
  """

  use Mix.Task

  @shortdoc "List controllers and actions without open_api_operation defined"

  @impl Mix.Task
  def run([router_module]) do
    router = Module.concat([router_module])

    missing =
      Phoenix.Router.routes(router)
      |> Enum.filter(&controller_route?/1)
      |> Enum.reject(&open_api_covered?/1)
      |> Enum.uniq_by(fn %{plug: controller, plug_opts: action, path: path} -> {controller, action, path} end)

    if missing == [] do
      Mix.shell().info("All routes have OpenAPI specs defined.")
    else
      Mix.shell().info("Routes missing OpenAPI specs:\n")

      missing
      |> Enum.group_by(& &1.plug)
      |> Enum.each(fn {controller, routes} ->
        Mix.shell().info(inspect(controller))

        Enum.each(routes, fn %{verb: verb, path: path, plug_opts: action} ->
          Mix.shell().info("  [#{String.upcase(to_string(verb))}]    #{path}    #{action}")
        end)

        Mix.shell().info("")
      end)
    end
  end

  def run(_), do: Mix.shell().error("Usage: mix open_api_coverage <RouterModule>")

  defp controller_route?(%{plug_opts: action}), do: is_atom(action)

  defp open_api_covered?(%{plug: controller, plug_opts: action}) do
    Code.ensure_loaded(controller)

    function_exported?(controller, :open_api_operation, 1) and
      not is_nil(controller.open_api_operation(action))
  end
end
