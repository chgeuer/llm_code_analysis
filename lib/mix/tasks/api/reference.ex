defmodule Mix.Tasks.Api.Reference do
  use Mix.Task

  @moduledoc """
  Generates API reference documentation for the application.

  ## Usage

      mix api.reference

  This task generates a markdown file with all public modules and functions,
  organized by category.

  ## Configuration

  Configure in your `mix.exs` project settings:

      def project do
        [
          # ... other settings ...
          api_category_mappings: [
            {~r/MyApp.Web/, "Web"},
            {~r/MyApp.Core/, "Core"},
            {true, "Other"}
          ],
          api_reference_output_file: "docs/api-reference.md"
        ]
      end

  ### Configuration Options

  - `:api_category_mappings` - List of `{pattern, category}` tuples for organizing modules.
    Each tuple is either `{regex, "Category Name"}` or `{true, "Default Category"}`.
    The order matters - first match wins.

  - `:api_reference_output_file` - Path where to write the markdown file.

  If not configured, sensible defaults are used based on the application name.
  """

  @shortdoc "Generates API reference documentation"

  alias CodeAnalysis.API.ReferenceGenerator

  @impl Mix.Task
  def run(_args) do
    # Ensure the application is compiled
    Mix.Task.run("compile")

    # Get configuration from mix.exs
    config = Mix.Project.config()

    ReferenceGenerator.generate(
      app_name: config[:app],
      category_mappings: config[:api_category_mappings],
      output_file: config[:api_reference_output_file],
      include_modulename_in_functions:
        Keyword.get(config, :include_modulename_in_functions, true),
      include_hidden_functions: Keyword.get(config, :include_hidden_functions, false)
    )
  end
end
