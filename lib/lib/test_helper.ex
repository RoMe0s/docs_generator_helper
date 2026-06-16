defmodule DocsGeneratorHelper.TestHelpers do
  @moduledoc """
  Call this in the test_helper.exs file for you API app.
  It should replace default `ExUnit.srart()`


    ```
    {:ok, _} = Application.ensure_all_started(:ex_machina)

    DocsGeneratorHelper.TestHelpers.start()

    # Commented old ex unit start, we will uncomment it later.
    # ExUnit.start()

    Ecto.Adapters.SQL.Sandbox.mode(Core.Repo, :manual)

    ```

  """

  def start(opts \\ []) do
    default_path = Keyword.get(opts, :default_path, "doc/temp_open_api.json")
    default_path |> Path.dirname() |> File.mkdir_p!()

    Bureaucrat.start(
      env_var: "BUREUCRAT_DOC",
      writer: Keyword.get(opts, :writer, DocsGeneratorHelper.JsonOpenApiWriter),
      default_path: default_path,
      json_library: Keyword.get(opts, :json_library, Jason)
    )

    ExUnit.start(formatters: [ExUnit.CLIFormatter, Bureaucrat.Formatter])
  end
end
