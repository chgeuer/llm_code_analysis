defmodule CodeAnalysis.API.ReferenceGenerator do
  @moduledoc """
  Generates API reference documentation for Elixir applications.

  Uses `CodeAnalysis.API.Introspection` to extract module and function information,
  then formats it as markdown documentation.
  """

  alias CodeAnalysis.API.Introspection

  @options_schema NimbleOptions.new!(
                    app_name: [
                      type: :atom,
                      required: true,
                      doc: "Application name"
                    ],
                    category_mappings: [
                      type: {:list, :any},
                      required: true,
                      doc: "List of {pattern, category} tuples for categorizing modules"
                    ],
                    output_file: [
                      type: :string,
                      required: true,
                      doc: "Path to write the markdown file"
                    ],
                    include_modulename_in_functions: [
                      type: :boolean,
                      default: false,
                      doc: "Include full module name in function signatures"
                    ],
                    include_hidden_functions: [
                      type: :boolean,
                      default: false,
                      doc: "Include functions without @doc"
                    ]
                  )

  @doc """
  Generates API reference documentation.

  ## Options

  #{NimbleOptions.docs(@options_schema)}

  ## Examples

      CodeAnalysis.API.ReferenceGenerator.generate(
        app_name: :my_app,
        category_mappings: [
          {~r/ServiceBus/, "Service Bus"},
          {~r/EventHubs/, "Event Hubs"},
          {true, "Other"}
        ],
        output_file: "docs/api-reference.md"
      )

  """
  @spec generate(keyword()) :: :ok
  def generate(opts) do
    opts =
      opts
      |> NimbleOptions.validate!(@options_schema)

    app_name = opts[:app_name]
    category_mappings = opts[:category_mappings]
    output_file = opts[:output_file]
    include_modulename = opts[:include_modulename_in_functions]
    include_hidden = opts[:include_hidden_functions]

    IO.puts("Generating API reference...")

    # Use CodeAnalysis.API.Introspection to get the API overview
    api_overview =
      Introspection.generate_api_overview(
        app_name: app_name,
        category_mappings: category_mappings,
        include_hidden: include_hidden
      )

    # Generate markdown documentation from the overview
    content =
      generate_documentation(
        api_overview,
        category_mappings,
        app_name,
        include_modulename,
        output_file
      )

    File.write!(output_file, content)

    total_modules =
      api_overview
      |> Enum.map(fn {_category, modules} -> map_size(modules) end)
      |> Enum.sum()

    IO.puts(
      "API reference generated (#{map_size(api_overview)} categories, #{total_modules} modules).\nWritten to: #{output_file}"
    )

    :ok
  end

  defp generate_documentation(
         api_overview,
         category_mappings,
         app_name,
         include_modulename,
         output_file
       ) do
    # Header
    header = """
    # #{humanize_app_name(app_name)} - API Reference

    Concise reference of all public modules and functions.

    ---

    """

    # Extract category order from mappings (order matters)
    categories =
      category_mappings
      |> Enum.map(fn
        {true, category} -> category
        {_pattern, category} -> category
      end)
      |> Enum.uniq()

    # Generate content for each category in the specified order
    category_docs =
      categories
      |> Enum.filter(fn cat -> Map.has_key?(api_overview, cat) end)
      |> Enum.map(fn category ->
        modules = Map.get(api_overview, category, %{})
        generate_category(category, modules, include_modulename, output_file)
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n\n")

    # Methodology footer
    footer = """

    ---

    ## How This Was Generated

    This document was generated using CodeAnalysis.API.ReferenceGenerator:

    1. Extract API structure using CodeAnalysis.API.Introspection
    2. `:application.get_key/2` - List all application modules
    3. `Module.__info__(:functions)` - Get exported functions for each module
    4. `Code.fetch_docs/1` - Extract @doc documentation and function signatures with parameter names
    5. Pattern matching on module names for categorization

    """

    header <> category_docs <> footer
  end

  defp generate_category(_category, modules, _include_modulename, _output_file)
       when map_size(modules) == 0 do
    nil
  end

  defp generate_category(category, modules, include_modulename, output_file) do
    module_docs =
      modules
      |> Enum.sort()
      |> Enum.map(fn {module_name, details} ->
        document_module(module_name, details, include_modulename, output_file)
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n\n")

    if module_docs == "" do
      nil
    else
      "## #{category}\n\n#{module_docs}"
    end
  end

  defp document_module(module_name, details, include_modulename, output_file) do
    %{
      module_description: module_doc,
      file_path: source_path,
      functions: functions
    } = details

    if map_size(functions) == 0 do
      nil
    else
      # Create header with link to source file
      header =
        if source_path do
          # Make the path relative to the output file location
          relative_path = make_relative_to_output(source_path, output_file)

          if module_doc do
            """
            ### [`#{module_name}`](#{relative_path})

            #{module_doc}
            """
          else
            """
            ### [`#{module_name}`](#{relative_path})
            """
          end
        else
          if module_doc do
            """
            ### `#{module_name}`

            #{module_doc}
            """
          else
            """
            ### `#{module_name}`
            """
          end
        end

      # Format functions
      function_docs =
        functions
        |> Enum.sort()
        |> Enum.map_join("\n", fn {signature, doc} ->
          format_function(module_name, signature, doc, include_modulename)
        end)

      """
      #{header}

      #{function_docs}
      """
    end
  end

  defp format_function(module_name, signature, nil, include_modulename) do
    function_sig =
      if include_modulename do
        "#{module_name}.#{signature}"
      else
        signature
      end

    "- `#{function_sig}`"
  end

  defp format_function(module_name, signature, doc, include_modulename) do
    function_sig =
      if include_modulename do
        "#{module_name}.#{signature}"
      else
        signature
      end

    "- `#{function_sig}` - #{doc}"
  end

  defp humanize_app_name(app_name) when is_atom(app_name) do
    app_name
    |> to_string()
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  # Make a source file path relative to the output markdown file
  # E.g., if output is "docs/llm-api-reference.md" and source is "lib/azure/amqp.ex"
  # then result should be "../lib/azure/amqp.ex"
  defp make_relative_to_output(source_path, output_file) do
    output_dir = Path.dirname(output_file)
    Path.relative_to(source_path, output_dir)
  end
end
