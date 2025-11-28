defmodule CodeAnalysis.Livebook.Extractor do
  @moduledoc """
  Utilities for extracting executable code from Livebook (.livemd) files.

  Filters out non-executable code blocks marked with `force_markdown`.
  Provides AST-based analysis of aliases and function calls.

  Note: The `extract_executable_code/1` function now delegates to the
  `NimbleLivebookMarkdownExtractor` library for robust parsing.
  """

  @doc """
  Extracts only executable Elixir code from a Livebook markdown string.

  Filters out:
  - Markdown text and formatting
  - Code blocks marked with `<!-- livebook:{"force_markdown":true} -->`

  Returns a string containing only executable Elixir code.

  This function now uses the NimbleParsec-based `NimbleLivebookMarkdownExtractor`
  library for more robust and reliable parsing.

  ## Examples

      iex> content = \"\"\"
      ...> # My Notebook
      ...>
      ...> \\`\\`\\`elixir
      ...> a = 1
      ...> \\`\\`\\`
      ...>
      ...> <!-- livebook:{"force_markdown":true} -->
      ...>
      ...> \\`\\`\\`elixir
      ...> b = 2
      ...> \\`\\`\\`
      ...>
      ...> \\`\\`\\`elixir
      ...> c = 3
      ...> \\`\\`\\`
      ...> \"\"\"
      iex> CodeAnalysis.Livebook.Extractor.extract_executable_code(content)
      "a = 1\\n\\nc = 3"

  """
  @spec extract_executable_code(String.t()) :: String.t()
  def extract_executable_code(content) do
    NimbleLivebookMarkdownExtractor.extract_executable_code(content)
  end

  @doc """
  Extracts aliases from an Elixir AST.

  Handles:
  - `alias Module`
  - `alias Module, as: Alias`
  - `alias Module.{A, B, C}`

  Returns a map of short names to full module names.

  ## Examples

      iex> {:ok, ast} = Code.string_to_quoted("alias Azure.EventHubs.EventData")
      iex> CodeAnalysis.Livebook.Extractor.extract_aliases(ast)
      %{"EventData" => "Azure.EventHubs.EventData"}

  """
  @spec extract_aliases(Macro.t()) :: %{String.t() => String.t()}
  def extract_aliases(ast) do
    aliases = %{}

    Macro.prewalk(ast, aliases, fn
      # alias Module
      {:alias, _, [{:__aliases__, _, module_parts}]}, acc ->
        full_module = Enum.join(module_parts, ".")
        short_name = List.last(module_parts) |> to_string()
        {nil, Map.put(acc, short_name, full_module)}

      # alias Module, as: Alias
      {:alias, _, [{:__aliases__, _, module_parts}, [as: {:__aliases__, _, [alias_name]}]]}, acc ->
        full_module = Enum.join(module_parts, ".")
        {nil, Map.put(acc, to_string(alias_name), full_module)}

      # alias Module.{A, B, C}
      {:alias, _, [{{:., _, [{:__aliases__, _, base_parts}, :{}]}, _, submodules}]}, acc ->
        base = Enum.join(base_parts, ".")

        new_aliases =
          Enum.reduce(submodules, acc, fn
            {:__aliases__, _, [submodule]}, inner_acc ->
              full_module = "#{base}.#{submodule}"
              Map.put(inner_acc, to_string(submodule), full_module)

            _, inner_acc ->
              inner_acc
          end)

        {nil, new_aliases}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
  end

  @doc """
  Extracts module function calls from an Elixir AST.

  Returns a MapSet of `{module, function, arity}` tuples.

  ## Examples

      iex> {:ok, ast} = Code.string_to_quoted("Azure.EventHubs.send_event(conn, hub, event)")
      iex> CodeAnalysis.Livebook.Extractor.extract_calls(ast)
      MapSet.new([{"Azure.EventHubs", "send_event", 3}])

  """
  @spec extract_calls(Macro.t()) :: MapSet.t({String.t(), String.t(), non_neg_integer()})
  def extract_calls(ast) do
    calls = MapSet.new()

    {_, calls} =
      Macro.prewalk(ast, calls, fn
        # Skip alias statements - they shouldn't be counted as function calls
        {:alias, _, _}, acc ->
          {nil, acc}

        # Match Module.function(...) or Module.function with args
        {{:., _, [{:__aliases__, _, module_parts}, function]}, _, args}, acc
        when is_atom(function) and is_list(args) ->
          module = Enum.join(module_parts, ".")
          arity = length(args)
          {nil, MapSet.put(acc, {module, to_string(function), arity})}

        # Match Module.function in other contexts (not a call) - no arity
        {:., _, [{:__aliases__, _, module_parts}, function]}, acc when is_atom(function) ->
          module = Enum.join(module_parts, ".")
          # No arity available for non-call contexts
          {nil, MapSet.put(acc, {module, to_string(function), nil})}

        node, acc ->
          {node, acc}
      end)

    calls
  end

  @doc """
  Resolves a module name through aliases.

  Given a module name like "EventData" and a map of aliases,
  returns the full module name like "Azure.EventHubs.EventData".

  If the aliases map contains a "__namespace__" key, it will be used
  to resolve unqualified single-part module names by prefixing them
  with the namespace (implementing Elixir's implicit aliasing).

  However, standard Elixir modules (Enum, String, Map, etc.) are never
  prefixed with the namespace.

  ## Examples

      iex> aliases = %{"EventData" => "Azure.EventHubs.EventData"}
      iex> CodeAnalysis.Livebook.Extractor.resolve_alias("EventData", aliases)
      "Azure.EventHubs.EventData"

      iex> CodeAnalysis.Livebook.Extractor.resolve_alias("UnknownModule", %{})
      "UnknownModule"

      iex> aliases = %{"__namespace__" => "Azure.EventHubs.Processor"}
      iex> CodeAnalysis.Livebook.Extractor.resolve_alias("PartitionManager", aliases)
      "Azure.EventHubs.Processor.PartitionManager"

      iex> aliases = %{"__namespace__" => "Azure.EventHubs.Processor"}
      iex> CodeAnalysis.Livebook.Extractor.resolve_alias("Enum", aliases)
      "Enum"

  """
  @spec resolve_alias(String.t(), %{String.t() => String.t()}) :: String.t()
  def resolve_alias(module, aliases) do
    parts = String.split(module, ".")
    first_part = List.first(parts)

    case Map.get(aliases, first_part) do
      nil ->
        # No explicit alias found, check for implicit namespace aliasing
        # If it's a single-part name and we have a namespace, try prefixing
        # BUT: don't prefix standard library modules or modules that start with certain known prefixes
        if length(parts) == 1 && should_apply_namespace?(module) do
          case Map.get(aliases, "__namespace__") do
            nil -> module
            namespace -> "#{namespace}.#{module}"
          end
        else
          module
        end

      aliased_module ->
        remaining = Enum.drop(parts, 1)

        if Enum.empty?(remaining) do
          aliased_module
        else
          "#{aliased_module}.#{Enum.join(remaining, ".")}"
        end
    end
  end

  # Determines if a module name should have namespace prefix applied
  # Standard library and common modules should not be prefixed
  defp should_apply_namespace?(module) do
    # List of modules that should never be prefixed with namespace
    stdlib_modules = ~w[
      Enum Enumerable String Map List Kernel IO File System Process Logger Stream
      Agent Task GenServer Supervisor Application Code Module Regex URI
      Path DateTime NaiveDateTime Date Time Integer Float Keyword Exception
      Range Mix MapSet Tuple Access Base Calendar Inspect Port Node
      Protocol Record Set Version Collectable
      Jason Req Kino ExUnit Broadway Flow SweetXml X509 Bandit Avrora
      WebSockex NimbleOptions NimbleParsec Finch Mint
    ]

    # Don't apply namespace to standard library modules
    module not in stdlib_modules
  end
end
