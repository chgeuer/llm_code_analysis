defmodule CodeAnalysis.Livebook.Extractor do
  @moduledoc """
  Utilities for extracting executable code from Livebook (.livemd) files.

  Filters out non-executable code blocks marked with `force_markdown`.
  Provides AST-based analysis of aliases and function calls.
  """

  @doc """
  Extracts only executable Elixir code from a Livebook markdown string.

  Filters out:
  - Markdown text and formatting
  - Code blocks marked with `<!-- livebook:{"force_markdown":true} -->`

  Returns a string containing only executable Elixir code.

  ## Examples

      iex> content = ~s(
      ...> # My Notebook
      ...>
      ...> ```elixir
      ...> IO.puts("real code")
      ...> ```
      ...>
      ...> <!-- livebook:{"force_markdown":true} -->
      ...>
      ...> ```elixir
      ...> FakeModule.bad()
      ...> ```
      ...> )
      iex> CodeAnalysis.Livebook.Extractor.extract_executable_code(content)
      "IO.puts(\\"real code\\")"

  """
  @spec extract_executable_code(String.t()) :: String.t()
  def extract_executable_code(content) do
    lines = String.split(content, "\n")

    {executable_blocks, _state} =
      Enum.reduce(lines, {[], :outside_block}, fn line, {blocks, state} ->
        case state do
          :outside_block ->
            cond do
              String.contains?(line, ~s(<!-- livebook:{"force_markdown":true})) ->
                {blocks, :in_force_markdown}

              String.match?(line, ~r/^```elixir\s*$/) ->
                {blocks, :in_executable_block}

              true ->
                {blocks, :outside_block}
            end

          :in_force_markdown ->
            if String.match?(line, ~r/^```elixir\s*$/) do
              {blocks, :in_non_executable_block}
            else
              {blocks, :in_force_markdown}
            end

          :in_non_executable_block ->
            if String.match?(line, ~r/^```\s*$/) do
              {blocks, :outside_block}
            else
              {blocks, :in_non_executable_block}
            end

          :in_executable_block ->
            if String.match?(line, ~r/^```\s*$/) do
              # Add a blank line between code blocks for separation
              {["" | blocks], :outside_block}
            else
              {[line | blocks], :in_executable_block}
            end
        end
      end)

    executable_blocks
    |> Enum.reverse()
    |> Enum.join("\n")
    |> String.trim()
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

  Returns a MapSet of `{module, function}` tuples.

  ## Examples

      iex> {:ok, ast} = Code.string_to_quoted("Azure.EventHubs.send_event(conn, hub, event)")
      iex> CodeAnalysis.Livebook.Extractor.extract_calls(ast)
      MapSet.new([{"Azure.EventHubs", "send_event"}])

  """
  @spec extract_calls(Macro.t()) :: MapSet.t({String.t(), String.t()})
  def extract_calls(ast) do
    calls = MapSet.new()

    {_, calls} =
      Macro.prewalk(ast, calls, fn
        # Skip alias statements - they shouldn't be counted as function calls
        {:alias, _, _}, acc ->
          {nil, acc}

        # Match Module.function(...) or Module.function
        {{:., _, [{:__aliases__, _, module_parts}, function]}, _, _args}, acc
        when is_atom(function) ->
          module = Enum.join(module_parts, ".")
          {nil, MapSet.put(acc, {module, to_string(function)})}

        # Match Module.function in other contexts (not a call)
        {:., _, [{:__aliases__, _, module_parts}, function]}, acc when is_atom(function) ->
          module = Enum.join(module_parts, ".")
          {nil, MapSet.put(acc, {module, to_string(function)})}

        node, acc ->
          {node, acc}
      end)

    calls
  end

  @doc """
  Resolves a module name through aliases.

  Given a module name like "EventData" and a map of aliases,
  returns the full module name like "Azure.EventHubs.EventData".

  ## Examples

      iex> aliases = %{"EventData" => "Azure.EventHubs.EventData"}
      iex> CodeAnalysis.Livebook.Extractor.resolve_alias("EventData", aliases)
      "Azure.EventHubs.EventData"

      iex> CodeAnalysis.Livebook.Extractor.resolve_alias("UnknownModule", %{})
      "UnknownModule"

  """
  @spec resolve_alias(String.t(), %{String.t() => String.t()}) :: String.t()
  def resolve_alias(module, aliases) do
    parts = String.split(module, ".")
    first_part = List.first(parts)

    case Map.get(aliases, first_part) do
      nil ->
        module

      aliased_module ->
        remaining = Enum.drop(parts, 1)

        if Enum.empty?(remaining) do
          aliased_module
        else
          "#{aliased_module}.#{Enum.join(remaining, ".")}"
        end
    end
  end
end
