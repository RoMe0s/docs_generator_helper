defmodule DocsGeneratorHelper.MixProject do
  use Mix.Project

  def project do
    [
      app: :docs_generator_helper,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:open_api_spex, "~> 3.21"},

      # deps for test helpers, should be without test only env to be compiled when used as a dependency
      {:phoenix, "~> 1.7"},
      {:bureaucrat, "~> 0.2.10"},
      {:schemata, github: "edenlabllc/schemata"},
      {:jason, "~> 1.4"}
    ]
  end
end
