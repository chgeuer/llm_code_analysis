defmodule Mix.Tasks.Api.Validate do
  use Mix.Task

  @moduledoc """
  Validates that code files only call existing APIs.

  ## Usage

      mix api.validate

  This task validates all `.exs` and `.livemd` files in the project,
  checking that all module function calls resolve to actual exported functions.

  ## Configuration

  The allowed modules can be configured in `mix.exs`:

      def project do
        [
          api_validation_allowed_modules: [
            "MyApp",
            "SomeTestHelper"
          ]
        ]
      end

  ## How It Works

  1. Finds all `.exs` and `.livemd` files (excluding `_build/` and `deps/`)
  2. For `.livemd` files, extracts only executable code blocks
  3. Parses code into AST and extracts all module function calls
  4. Resolves aliases to full module names
  5. Checks if each function exists using runtime reflection
  6. Reports any calls to non-existent functions

  ## Output

  Shows summary of:
  - Total files validated
  - Valid vs invalid file counts
  - Details of invalid API calls with file locations

  """

  alias CodeAnalysis.API.Validator
  @shortdoc "Validates API calls in code files"

  @default_stdlib_modules ~w[
      Enum String Map List Kernel IO File System Process Logger Stream
      Agent Task GenServer Supervisor Application Code Module Regex URI Path
      DateTime NaiveDateTime Date Time Integer Float Keyword Exception Range Mix
      :crypto :base64 :timer :telemetry
      Kino Jason Req Broadway Flow ExUnit SweetXml X509 Bandit Avrora
    ]

  @impl Mix.Task
  def run(_args) do
    # Ensure the application is compiled
    Mix.Task.run("compile")

    IO.puts("# Validating API calls (checking actual function existence)...")

    # Get configuration from mix.exs
    config = Mix.Project.config()
    custom_allowed = config[:api_validation_allowed_modules] || []
    allowed_modules = @default_stdlib_modules ++ custom_allowed

    Validator.validate(
      file_patterns: ["**/*.{exs,livemd}"],
      exclude_patterns: ["_build/", "deps/"],
      allowed_modules: allowed_modules
    )
    |> Validator.print_summary()
  end
end
