defmodule CodeAnalysis.API.Validator do
  @moduledoc """
  Validates Elixir scripts and Livebook files against the actual API.

  Uses AST parsing and runtime reflection to check if module function calls
  truly exist. Handles aliases correctly and provides detailed reporting.
  """

  alias CodeAnalysis.Livebook.Extractor

  @options_schema NimbleOptions.new!(
                    file_patterns: [
                      type: {:list, :string},
                      default: ["**/*.{exs,livemd}"],
                      doc: "List of glob patterns to match files"
                    ],
                    exclude_patterns: [
                      type: {:list, :string},
                      default: ["_build/", "deps/"],
                      doc: "Patterns to exclude from validation"
                    ],
                    allowed_modules: [
                      type: {:list, :string},
                      default: [],
                      doc: "List of module prefixes to allow without validation"
                    ]
                  )

  @doc """
  Validates files against the API.

  ## Options

  #{NimbleOptions.docs(@options_schema)}

  ## Returns

  A list of validation results, each containing:
  - `:file` - File path
  - `:calls` - All function calls found
  - `:invalid` - Invalid calls
  - `:valid?` - Boolean indicating if file is valid

  ## Examples

      results = CodeAnalysis.API.Validator.validate(
        file_patterns: ["lib/**/*.ex", "test/**/*.exs"],
        exclude_patterns: ["_build/", "deps/"],
        allowed_modules: ["MyApp.TestHelper"]
      )

      Enum.each(results, fn result ->
        unless result.valid? do
          IO.puts("Invalid calls in \#{result.file}:")
          Enum.each(result.invalid, &IO.puts("  - \#{&1}"))
        end
      end)

  """
  @spec validate(keyword()) :: [map()]
  def validate(opts \\ []) do
    opts = NimbleOptions.validate!(opts, @options_schema)

    file_patterns = opts[:file_patterns]
    exclude_patterns = opts[:exclude_patterns]
    allowed_modules = opts[:allowed_modules] ++ default_allowed_modules()

    find_files(file_patterns, exclude_patterns)
    |> Enum.map(&validate_file(&1, allowed_modules))
  end

  @doc """
  Prints a summary of validation results.

  Takes the results from `validate/1` and prints a formatted summary
  showing total files, valid/invalid counts, and details of invalid calls.
  """
  @spec print_summary([map()]) :: :ok
  def print_summary(results) do
    total = length(results)
    valid = Enum.count(results, & &1.valid?)
    invalid = total - valid

    IO.puts(String.duplicate("=", 80))
    IO.puts("VALIDATION SUMMARY")
    IO.puts(String.duplicate("=", 80))
    IO.puts("")
    IO.puts("Total files:   #{total}")
    IO.puts("Valid files:   #{valid} (#{percentage(valid, total)}%)")
    IO.puts("Invalid files: #{invalid} (#{percentage(invalid, total)}%)")
    IO.puts("")

    if invalid > 0 do
      IO.puts(String.duplicate("=", 80))
      IO.puts("INVALID API CALLS FOUND")
      IO.puts(String.duplicate("=", 80))
      IO.puts("")

      results
      |> Enum.reject(& &1.valid?)
      |> Enum.each(fn result ->
        IO.puts("📄 #{result.file}")
        IO.puts("   ❌ Invalid calls:")

        result.invalid
        |> Enum.each(fn call ->
          IO.puts("      - #{call}")
        end)

        IO.puts("")
      end)
    else
      IO.puts("✅ All files use valid public APIs!")
    end

    :ok
  end

  # Private functions

  defp extract_module_namespace(ast) do
    {_, namespace} =
      Macro.prewalk(ast, nil, fn
        {:defmodule, _, [{:__aliases__, _, module_parts}, _]}, _acc ->
          # Extract the namespace from defmodule, excluding the last part
          case module_parts do
            [_single] ->
              # No namespace for top-level modules
              {nil, nil}

            parts when is_list(parts) ->
              # For nested modules like Azure.EventHubs.Processor.PartitionManagerTest
              # The namespace is Azure.EventHubs.Processor
              namespace_parts = Enum.drop(parts, -1)
              namespace = Enum.join(namespace_parts, ".")
              {nil, namespace}
          end

        node, acc ->
          {node, acc}
      end)

    namespace
  end

  defp merge_implicit_aliases(explicit_aliases, nil), do: explicit_aliases

  defp merge_implicit_aliases(explicit_aliases, namespace) do
    # For a module in namespace "Azure.EventHubs.Processor",
    # Elixir's implicit aliasing means that unqualified single-part names
    # like "PartitionManager" resolve to "Azure.EventHubs.Processor.PartitionManager"
    # 
    # We store the namespace in the aliases map with a special key so that
    # resolve_alias can apply it when needed.

    Map.put(explicit_aliases, "__namespace__", namespace)
  end

  defp find_files(patterns, exclude_patterns) do
    patterns
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.uniq()
    |> Enum.reject(fn path ->
      Enum.any?(exclude_patterns, &String.starts_with?(path, &1))
    end)
  end

  defp validate_file(file_path, allowed_modules) do
    content = File.read!(file_path)

    # For .livemd files, extract only executable code blocks
    code_to_validate =
      if String.ends_with?(file_path, ".livemd") do
        Extractor.extract_executable_code(content)
      else
        content
      end

    # Try to parse the code into AST
    case Code.string_to_quoted(code_to_validate) do
      {:ok, ast} ->
        validate_ast(file_path, ast, allowed_modules)

      {:error, _} ->
        # If AST parsing fails, fall back to regex-based detection
        validate_with_regex(file_path, code_to_validate, allowed_modules)
    end
  end

  defp validate_ast(file_path, ast, allowed_modules) do
    # Extract module namespace from defmodule
    module_namespace = extract_module_namespace(ast)

    # Extract aliases from AST
    explicit_aliases = Extractor.extract_aliases(ast)

    # Combine explicit aliases with implicit aliases from module namespace
    aliases = merge_implicit_aliases(explicit_aliases, module_namespace)

    # Extract all module function calls from AST
    calls = Extractor.extract_calls(ast)

    # Resolve calls through aliases and check if they exist
    invalid_calls =
      calls
      |> MapSet.to_list()
      |> Enum.reject(fn
        {module, function, _arity} ->
          # Check if function exists with ANY arity (not strict arity check)
          # because pipe operators and default parameters make arity complex
          resolved_module = Extractor.resolve_alias(module, aliases)
          valid_call?(resolved_module, function, allowed_modules)
      end)
      |> Enum.map(fn
        {module, function, arity} when is_integer(arity) ->
          resolved = Extractor.resolve_alias(module, aliases)
          "#{resolved}.#{function}/#{arity}"

        {module, function, nil} ->
          resolved = Extractor.resolve_alias(module, aliases)
          "#{resolved}.#{function}"
      end)
      |> Enum.sort()

    all_calls =
      calls
      |> MapSet.to_list()
      |> Enum.map(fn
        {mod, fun, arity} when is_integer(arity) ->
          resolved = Extractor.resolve_alias(mod, aliases)
          "#{resolved}.#{fun}/#{arity}"

        {mod, fun, nil} ->
          resolved = Extractor.resolve_alias(mod, aliases)
          "#{resolved}.#{fun}"
      end)
      |> Enum.sort()

    %{
      file: file_path,
      calls: all_calls,
      invalid: invalid_calls,
      valid?: Enum.empty?(invalid_calls)
    }
  end

  defp validate_with_regex(file_path, code_to_validate, allowed_modules) do
    # Fallback to regex-based validation for unparseable code
    aliases = parse_aliases(code_to_validate)

    calls =
      Regex.scan(~r/([A-Z][A-Za-z0-9._]*\.[a-z_][a-z0-9_!?]*)\s*[(\[]/, code_to_validate)
      |> Enum.map(fn [_, call] -> call end)
      |> Enum.uniq()
      |> Enum.sort()

    invalid_calls =
      calls
      |> Enum.reject(fn call ->
        resolved = resolve_alias(call, aliases)
        valid_call_string?(resolved, allowed_modules)
      end)
      |> Enum.map(fn call ->
        resolved = resolve_alias(call, aliases)

        if call == resolved do
          call
        else
          "#{call} (→ #{resolved})"
        end
      end)

    %{
      file: file_path,
      calls: calls,
      invalid: invalid_calls,
      valid?: Enum.empty?(invalid_calls)
    }
  end

  defp parse_aliases(content) do
    aliases = %{}

    # Pattern 1 & 2: alias Module or alias Module, as: Alias
    aliases =
      Regex.scan(~r/alias\s+([A-Z][A-Za-z0-9.]*)\s*(?:,\s*as:\s*([A-Z][A-Za-z0-9.]*))?/, content)
      |> Enum.reduce(aliases, fn match, acc ->
        case match do
          [_, full_module] ->
            short_name = full_module |> String.split(".") |> List.last()
            Map.put(acc, short_name, full_module)

          [_, full_module, alias_name] when alias_name != "" ->
            Map.put(acc, alias_name, full_module)

          _ ->
            acc
        end
      end)

    # Pattern 3: alias Module.{A, B, C}
    Regex.scan(~r/alias\s+([A-Z][A-Za-z0-9.]*)\.\{([^}]+)\}/, content)
    |> Enum.reduce(aliases, fn [_, base_module, submodules], acc ->
      submodules
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reduce(acc, fn submodule, inner_acc ->
        full_module = "#{base_module}.#{submodule}"
        Map.put(inner_acc, submodule, full_module)
      end)
    end)
  end

  defp resolve_alias(call, aliases) do
    parts = String.split(call, ".")
    {module_parts, [_function]} = Enum.split(parts, -1)
    first_part = List.first(module_parts)

    case Map.get(aliases, first_part) do
      nil ->
        call

      aliased_module ->
        call |> String.replace_prefix(first_part, aliased_module)
    end
  end

  defp valid_call?(module_name, function_name, allowed_modules) do
    if allowed_module?(module_name, allowed_modules) do
      true
    else
      check_function_exists?(module_name, function_name)
    end
  end

  defp valid_call_string?(call, allowed_modules) do
    parts = String.split(call, ".")
    {module_parts, [function]} = Enum.split(parts, -1)
    module_name = Enum.join(module_parts, ".")

    valid_call?(module_name, function, allowed_modules)
  end

  defp check_function_exists?(module_name, function_name) do
    module = String.to_existing_atom("Elixir.#{module_name}")

    case Code.ensure_loaded(module) do
      {:module, ^module} ->
        exports = module.__info__(:functions)

        Enum.any?(exports, fn {name, _arity} ->
          Atom.to_string(name) == function_name
        end)

      {:error, _} ->
        false
    end
  rescue
    ArgumentError ->
      false
  end

  defp allowed_module?(module, allowed_modules) do
    Enum.any?(allowed_modules, fn prefix ->
      String.starts_with?(module, prefix)
    end)
  end

  defp default_allowed_modules do
    ~w[
      Enum String Map List Kernel IO File System Process Logger Stream
      Agent Task GenServer Supervisor Application Code Module Regex URI
      Path DateTime NaiveDateTime Date Time Integer Float Keyword Exception
      Range Mix
      :crypto :base64 :timer :telemetry
      Kino Jason Req Broadway Flow ExUnit SweetXml X509 Bandit Avrora
    ]
  end

  defp percentage(count, total) when total > 0 do
    Float.round(count * 100 / total, 1)
  end

  defp percentage(_, _), do: 0
end
