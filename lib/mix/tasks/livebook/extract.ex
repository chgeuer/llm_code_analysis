defmodule Mix.Tasks.Livebook.Extract do
  use Mix.Task

  @moduledoc """
  Extracts executable Elixir code from Livebook (.livemd) files.

  ## Usage

      # Extract code (quiet mode - outputs only code)
      mix livebook.extract path/to/notebook.livemd > output.exs

      # Generate markdown analysis
      mix livebook.extract --include-analysis path/to/notebook.livemd > analysis.md

  ## Options

    * `--include-analysis` - Generate markdown-formatted analysis with AST details

  By default, outputs only the extracted executable code (suitable for piping to .exs files).
  With --include-analysis, outputs markdown with code and detailed analysis.

  ## Examples

      # Extract code for execution
      mix livebook.extract content/00_interactive.livemd > /tmp/extracted.exs

      # Generate analysis document
      mix livebook.extract --include-analysis content/02_event_hubs_basics.livemd > /tmp/analysis.md

  """
  alias CodeAnalysis.Livebook.Extractor
  @shortdoc "Extracts executable code from Livebook files"

  @impl Mix.Task
  def run(args) do
    {opts, remaining_args} = parse_args(args)

    case remaining_args do
      [input_file] ->
        code = extract_code(input_file)

        if opts[:include_analysis] do
          print_markdown_analysis(input_file, code)
        else
          IO.puts(code)
        end

      _ ->
        print_usage()
        exit({:shutdown, 1})
    end
  end

  defp parse_args(args) do
    {opts, remaining} =
      Enum.split_with(args, fn arg ->
        String.starts_with?(arg, "--")
      end)

    parsed_opts =
      opts
      |> Enum.map(fn
        "--include-analysis" -> {:include_analysis, true}
        other -> {:unknown, other}
      end)
      |> Enum.into(%{})

    {parsed_opts, remaining}
  end

  defp extract_code(input_file) do
    unless File.exists?(input_file) do
      Mix.shell().error("❌ File not found: #{input_file}")
      exit({:shutdown, 1})
    end

    unless String.ends_with?(input_file, ".livemd") do
      Mix.shell().error("⚠️  Warning: File doesn't have .livemd extension")
    end

    content = File.read!(input_file)
    Extractor.extract_executable_code(content)
  end

  defp print_markdown_analysis(input_file, code) do
    """
    # Extracted Code Analysis

    **Source:** `#{input_file}`

    ## Extracted Executable Code

    ```elixir
    #{code}
    ```
    """
    |> IO.puts()

    case Code.string_to_quoted(code) do
      {:ok, ast} ->
        IO.puts("## Analysis")
        IO.puts("")
        IO.puts("✅ **Code is syntactically valid Elixir**")
        IO.puts("")

        # Extract module calls
        aliases = Extractor.extract_aliases(ast)
        calls = Extractor.extract_calls(ast)

        # Aliases section
        if map_size(aliases) > 0 do
          IO.puts("### Aliases (#{map_size(aliases)})")
          IO.puts("")

          aliases
          |> Enum.sort()
          |> Enum.each(fn {short, full} ->
            IO.puts("- `#{short}` → `#{full}`")
          end)

          IO.puts("")
        end

        # Module function calls section
        if MapSet.size(calls) > 0 do
          IO.puts("### Module Function Calls (#{MapSet.size(calls)})")
          IO.puts("")

          calls
          |> Enum.sort()
          |> Enum.each(fn {mod, fun} ->
            resolved = Extractor.resolve_alias(mod, aliases)

            if mod == resolved do
              IO.puts("- `#{mod}.#{fun}`")
            else
              IO.puts("- `#{mod}.#{fun}` → `#{resolved}.#{fun}`")
            end
          end)
        end

      {:error, {line, error, token}} ->
        """
        ## Analysis

        ❌ **Code has syntax errors:**

        - **Line #{line}:** #{error}#{token}

        > This might be because livebook cells are independent and some may have incomplete expressions.
        """
        |> IO.puts()
    end
  end

  defp print_usage do
    """
    Usage: mix livebook.extract [--include-analysis] <input.livemd>

    Options:
      --include-analysis    Generate markdown-formatted analysis

    By default, only outputs extracted code (suitable for piping to .exs files).
    With --include-analysis, outputs markdown (suitable for .md files).

    Examples:
      mix livebook.extract notebook.livemd > output.exs
      mix livebook.extract --include-analysis notebook.livemd > analysis.md
    """
    |> Mix.shell().info()
  end
end
