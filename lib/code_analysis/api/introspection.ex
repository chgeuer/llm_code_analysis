defmodule CodeAnalysis.API.Introspection do
  @moduledoc """
  Introspects an Elixir application's API to generate a structured representation
  of all modules, functions, and their documentation.

  This module provides generic API introspection capabilities that can be used
  for generating documentation, validating API usage, or analyzing codebases.
  """

  @doc """
  Generates a complete API overview as a data structure.

  Returns a map organized by category, then by module, with function details:

  ```elixir
  %{
    "Category Name" => %{
      "Module.Name" => %{
        module_description: "Description from @moduledoc",
        file_path: "relative/path/to/file.ex",
        functions: %{
          "function_name/arity" => "Function description from @doc",
          "other_function/2" => nil  # Has @doc false or no @doc
        }
      }
    }
  }
  ```

  ## Options

  - `:app_name` - (required) Application name to introspect
  - `:category_mappings` - (required) List of `{pattern, category}` tuples to organize modules
  - `:include_hidden` - Include functions with `@doc false` (default: `false`)

  ## Examples

      iex> overview = CodeAnalysis.API.Introspection.generate_api_overview(
      ...>   app_name: :my_app,
      ...>   category_mappings: [
      ...>     {~r/^Mix\.Tasks/, "Mix Tasks"},
      ...>     {~r/Core/, "Core"},
      ...>     {true, "Other"}
      ...>   ]
      ...> )
      iex> Map.keys(overview)
      ["Mix Tasks", "Core", "Other"]
  """
  def generate_api_overview(opts) do
    app_name = Keyword.fetch!(opts, :app_name)
    category_mappings = Keyword.fetch!(opts, :category_mappings)
    include_hidden = Keyword.get(opts, :include_hidden, false)

    # Get all modules from the application
    {:ok, modules} = :application.get_key(app_name, :modules)

    # Group modules by category
    modules
    |> Enum.sort()
    |> Enum.group_by(&categorize_module(&1, category_mappings))
    |> Enum.map(fn {category, category_modules} ->
      module_data =
        category_modules
        |> Enum.sort()
        |> Enum.map(&introspect_module(&1, include_hidden))
        |> Map.new()

      {category, module_data}
    end)
    |> Map.new()
  end

  @doc """
  Introspects a single module and returns its details.

  Returns a tuple of `{module_name, details}` where details is a map:

  ```elixir
  {
    "MyApp.Connection",
    %{
      module_description: "Connection management",
      file_path: "lib/my_app/connection.ex",
      functions: %{
        "start_link/1" => "Starts a connection",
        "close/1" => nil
      }
    }
  }
  ```
  """
  def introspect_module(module, include_hidden \\ false) do
    module_name = inspect(module)

    details = %{
      module_description: get_module_description(module),
      file_path: get_module_file_path(module),
      functions: get_module_functions(module, include_hidden)
    }

    {module_name, details}
  end

  @doc """
  Gets all function signatures and descriptions for a module.

  Returns a map of `"function_name/arity" => "description"`.
  Functions with `@doc false` or no `@doc` have `nil` as description.
  """
  def get_module_functions(module, include_hidden \\ false) do
    # Get all exported functions
    functions = module.__info__(:functions)

    # Get documentation for the module
    {:docs_v1, _, _, _, _, _, docs} = Code.fetch_docs(module)

    # Build map of function signatures to descriptions
    functions
    |> Enum.map(fn {name, arity} ->
      signature = "#{name}/#{arity}"

      # Find matching doc entry
      doc_entry =
        Enum.find(docs, fn
          {{:function, ^name, ^arity}, _, _, _, _} -> true
          _ -> false
        end)

      description =
        case doc_entry do
          {{:function, _, _}, _, _, :hidden, _} when not include_hidden ->
            :skip

          {{:function, _, _}, _, _, :none, _} ->
            nil

          {{:function, _, _}, _, _, doc_content, _} when is_map(doc_content) ->
            extract_first_sentence(doc_content)

          {{:function, _, _}, _, _, doc_content, _} when is_binary(doc_content) ->
            extract_first_sentence(doc_content)

          _ ->
            nil
        end

      {signature, description}
    end)
    |> Enum.reject(fn {_, desc} -> desc == :skip end)
    |> Map.new()
  end

  @doc """
  Gets the module description from @moduledoc.
  Returns the first sentence or paragraph, or nil if no @moduledoc.
  """
  def get_module_description(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, %{"en" => moduledoc}, _, _} when is_binary(moduledoc) ->
        extract_first_sentence(moduledoc)

      {:docs_v1, _, _, _, :hidden, _, _} ->
        nil

      {:docs_v1, _, _, _, :none, _, _} ->
        nil

      _ ->
        nil
    end
  end

  @doc """
  Gets the relative file path for a module from the project root.
  """
  def get_module_file_path(module) do
    case module.module_info(:compile)[:source] do
      source when is_list(source) ->
        source_path = to_string(source)

        # Try to make it relative to project root
        case find_project_root() do
          nil ->
            source_path

          root ->
            Path.relative_to(source_path, root)
        end

      _ ->
        nil
    end
  end

  # Private helpers

  defp categorize_module(module, category_mappings) do
    module_name = inspect(module)

    # Find first matching category
    Enum.find_value(category_mappings, fn
      {true, category} ->
        category

      {pattern, category} when is_struct(pattern, Regex) ->
        if Regex.match?(pattern, module_name), do: category
    end)
  end

  defp extract_first_sentence(doc) when is_map(doc) do
    # For ExDoc format
    case Map.get(doc, "en") do
      nil -> nil
      text -> extract_first_sentence(text)
    end
  end

  defp extract_first_sentence(doc) when is_binary(doc) do
    doc
    |> String.trim()
    |> String.split("\n\n")
    |> List.first()
    |> String.split(". ")
    |> List.first()
    |> case do
      nil -> nil
      "" -> nil
      text -> String.trim(text)
    end
  end

  defp extract_first_sentence(_), do: nil

  defp find_project_root do
    # Try to find mix.exs in current or parent directories
    case File.cwd() do
      {:ok, cwd} -> find_mix_project(cwd)
      _ -> nil
    end
  end

  defp find_mix_project(dir) do
    mix_file = Path.join(dir, "mix.exs")

    cond do
      File.exists?(mix_file) ->
        dir

      dir == "/" or dir == "." ->
        nil

      true ->
        find_mix_project(Path.dirname(dir))
    end
  end
end
