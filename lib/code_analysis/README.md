# Code Analysis Modules

This directory contains reusable code analysis tools that can be extracted into a separate library.

## Architecture: Function Aliases

The code analysis tools use **function aliases** in `mix.exs` for explicit configuration flow:

```elixir
# In mix.exs
defp aliases do
  [
    llm_api_reference: fn _args ->
      CodeAnalysis.API.ReferenceGenerator.generate(
        app_name: :azure_amqp,
        category_mappings: api_category_mappings(),  # Helper function
        output_file: "docs/llm-api-reference.md"
      )
    end
  ]
end
```

**Why function aliases?**
- ✅ Configuration at point of use (visible in alias)
- ✅ No pollution of `project/0` with library-specific config
- ✅ Explicit data flow (no hidden global config)
- ✅ Can call library directly (Mix task optional)
- ✅ Easy to create variations with different configs

## Structure

### `CodeAnalysis.Livebook.Extractor`

Utilities for working with Livebook (`.livemd`) files:
- Extract executable code (filtering out `force_markdown` blocks)
- Parse AST to extract aliases
- Extract module function calls
- Resolve aliases to full module names

**Location:** `lib/code_analysis/livebook/extractor.ex`

### `CodeAnalysis.API.ReferenceGenerator`

Generate API reference documentation from compiled Elixir applications:
- Uses `ApiIntrospection` module to extract module and function information
- Organizes modules by category using regex patterns
- Generates markdown documentation
- **Uses NimbleOptions for validation**
- Customizable via configuration

**Location:** `lib/code_analysis/api/reference_generator.ex`

### `CodeAnalysis.API.Validator`

Validate that code files only call existing APIs:
- Parse Elixir and Livebook files
- Extract all module function calls using AST
- Resolve aliases to full module names
- Check function existence using runtime reflection
- **Uses NimbleOptions for validation**
- Generate detailed validation reports

**Location:** `lib/code_analysis/api/validator.ex`

## Mix Aliases (Recommended Usage)

The recommended way to use these tools is via **function aliases** in `mix.exs`:

```bash
mix llm_api_reference    # Generate API reference
mix validate_api_calls   # Validate API usage
mix extract_livebook_code notebook.livemd > output.exs
```

### Configuration in mix.exs

```elixir
defp aliases do
  [
    # Function alias - explicit configuration
    llm_api_reference: fn _args ->
      Mix.Task.run("compile")

      CodeAnalysis.API.ReferenceGenerator.generate(
        app_name: :azure_amqp,
        category_mappings: api_category_mappings(),
        output_file: "docs/llm-api-reference.md",
        include_modulename_in_functions: true,
        include_hidden_functions: true
      )
    end,

    validate_api_calls: fn _args ->
      Mix.Task.run("compile")

      CodeAnalysis.API.Validator.validate(
        file_patterns: ["**/*.{exs,livemd}"],
        exclude_patterns: ["_build/", "deps/"],
        allowed_modules: api_validation_allowed_modules()
      )
      |> CodeAnalysis.API.Validator.print_summary()
    end
  ]
end

# Helper functions called by aliases
defp api_category_mappings do
  [
    {~r/ServiceBus/, "Service Bus"},
    {~r/EventHubs/, "Event Hubs"},
    {true, "Other"}
  ]
end

defp api_validation_allowed_modules do
  ~w[MyApp.TestHelper MyApp.Support]
end
```

## Mix Tasks (Alternative Usage)

### `mix livebook.extract`

Extract executable code from Livebook files.

```bash
# Extract code (quiet mode)
mix livebook.extract notebook.livemd > output.exs

# Generate markdown analysis
mix livebook.extract --include-analysis notebook.livemd > analysis.md
```

**Implementation:** `lib/mix/tasks/livebook.extract.ex`

### `mix api.reference`

Generate API reference documentation.

```bash
mix api.reference
```

**Configuration in `mix.exs`:**

```elixir
def project do
  [
    # Define how modules are categorized
    api_category_mappings: [
      {~r/ServiceBus/, "Service Bus"},
      {~r/EventHubs/, "Event Hubs"},
      {true, "Other"}
    ],

    # Define output file location
    api_reference_output_file: "docs/llm-api-reference.md"
  ]
end
```

**Options:**
- `:api_category_mappings` - List of `{pattern, category}` tuples (required)
- `:api_reference_output_file` - Output file path (default: `"docs/llm-api-reference.md"`)

**Implementation:** `lib/mix/tasks/api.reference.ex`

### `mix api.validate`

Validate API calls in all code files.

```bash
mix api.validate
```

Validates all `.exs` and `.livemd` files, checking that module function calls
resolve to actual exported functions.

**Configuration in `mix.exs`:**

```elixir
def project do
  [
    # Define module prefixes to allow without validation
    api_validation_allowed_modules: [
      "MyApp.TestHelper",
      "MyApp.Support"
    ]
  ]
end
```

**Options:**
- `:api_validation_allowed_modules` - List of module name prefixes to skip validation

**Implementation:** `lib/mix/tasks/api.validate.ex`

## Migration Plan

These modules are designed to be extracted into a separate `code_analysis` library:

1. **Current State**: Modules live in `azure_amqp` under `lib/code_analysis/`
2. **Future State**: Move to separate `code_analysis` hex package
3. **Usage**: `azure_amqp` would then depend on `{:code_analysis, "~> 0.1"}`

### What Needs to Move

From `azure_amqp` to `code_analysis` library:
- `lib/code_analysis/**/*` → All code analysis modules
- `lib/mix/tasks/livebook.extract.ex` → Livebook extraction task
- `lib/mix/tasks/api.reference.ex` → API reference task
- `lib/mix/tasks/api.validate.ex` → API validation task
- `lib/azure/amqp/api_introspection.ex` → Generic API introspection module (rename)

### What Stays in `azure_amqp`

- `api_category_mappings/0` function in `mix.exs` (called by alias)
- `api_validation_allowed_modules/0` function in `mix.exs` (called by alias)
- Function aliases in `aliases/0` (application-specific wiring)
- Legacy scripts in `scripts/` (for backward compatibility)

## Benefits of Extraction

1. **Reusability**: Other Elixir projects can use the same tools
2. **Maintainability**: Separate concerns and versioning
3. **Testing**: Easier to test in isolation
4. **Distribution**: Available as hex package
5. **Documentation**: Dedicated docs for code analysis tools

## Dependencies

The code analysis modules have minimal dependencies:
- **NimbleOptions** - For parameter validation
- Standard library only (no other external deps)
- Works with any compiled Elixir application
- Mix tasks integrate seamlessly with any project

## Parameter Validation

All library functions use **NimbleOptions** for parameter validation:

```elixir
# Invalid call - missing required parameter
CodeAnalysis.API.ReferenceGenerator.generate(
  app_name: :my_app
  # Error: required :category_mappings option not found
)

# Invalid call - wrong type
CodeAnalysis.API.Validator.validate(
  file_patterns: "not a list"
  # Error: expected list, got: "not a list"
)
```

This ensures:
- ✅ Required parameters are provided
- ✅ Types are correct
- ✅ Clear error messages
- ✅ Self-documenting code

## Example Usage in Other Projects

```elixir
# In another project's mix.exs
defp deps do
  [
    {:code_analysis, "~> 0.1"}
  ]
end

defp aliases do
  [
    # Function aliases for explicit configuration
    api_ref: fn _args ->
      Mix.Task.run("compile")

      CodeAnalysis.API.ReferenceGenerator.generate(
        app_name: :my_app,
        category_mappings: [
          {~r/MyApp.Web/, "Web"},
          {~r/MyApp.Core/, "Core"},
          {true, "Other"}
        ],
        output_file: "docs/api-reference.md"
      )
    end,

    validate: fn _args ->
      Mix.Task.run("compile")

      CodeAnalysis.API.Validator.validate(
        allowed_modules: ["MyApp.TestHelper"]
      )
      |> CodeAnalysis.API.Validator.print_summary()
    end,

    extract: fn args ->
      Mix.Task.run("livebook.extract", args)
    end
  ]
end
```

## How Configuration Works

### Function Aliases Approach (Recommended)

Configuration is **explicit and visible** in the alias definition:

```elixir
llm_api_reference: fn _args ->
  CodeAnalysis.API.ReferenceGenerator.generate(
    app_name: :azure_amqp,                    # Direct parameter
    category_mappings: api_category_mappings(), # Helper function
    output_file: "docs/llm-api-reference.md"  # Direct parameter
  )
end
```

**Data flow:**
1. User runs `mix llm_api_reference`
2. Mix executes the function alias
3. Function calls helper (e.g., `api_category_mappings()`)
4. Function calls library with explicit parameters
5. Library validates parameters with NimbleOptions

**Benefits:**
- No global configuration pollution
- Clear what's being passed
- Easy to create variations
- Can skip Mix tasks entirely

## Testing

```bash
# Test livebook extraction
mix livebook.extract test/fixtures/sample.livemd > /tmp/extracted.exs

# Test API reference generation
mix api.reference

# Test API validation
mix api.validate

# Run with analysis
mix livebook.extract --include-analysis test/fixtures/sample.livemd > /tmp/analysis.md
```
