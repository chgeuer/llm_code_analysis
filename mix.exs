defmodule LlmCodeAnalysis.MixProject do
  use Mix.Project

  def project do
    [
      app: :llm_code_analysis,
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
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.39.1", only: [:dev], runtime: false},
      {:nimble_options, "~> 1.0"},
      {:nimble_livebook_markdown_extractor, github: "chgeuer/nimble_livebook_markdown_extractor"}
    ]
  end
end
