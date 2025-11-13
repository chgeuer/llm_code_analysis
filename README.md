# LLM Code Analysis

**Tools for AI coding agents to validate and analyze Elixir code in LiveBooks and scripts.**

This library provides Mix tasks and utilities designed specifically for LLM coding agents (like GitHub Copilot, Claude Code, Cursor) to validate, analyze, and document Elixir code. It helps AI agents ensure code quality, verify API usage, and generate comprehensive documentation.

## 🎯 Purpose

When working with Large Language Model coding agents, you often need to:

1. **Validate LiveBook code** - Ensure that LiveBook notebooks contain valid, executable code
2. **Verify API calls** - Check that all module function calls actually exist at runtime
3. **Extract code from notebooks** - Get clean, executable Elixir code from LiveBook markdown
4. **Generate API documentation** - Create comprehensive API references for AI agents to understand your codebase

This library provides automated tools to accomplish all of these tasks.

## 🚀 Mix Tasks for AI Agents

### 1. `mix livebook.extract` - Extract Code from LiveBooks

Extracts executable Elixir code from LiveBook (`.livemd`) files, filtering out markdown examples.

**Use Case:** AI agents can extract code from LiveBooks for testing, validation, or execution.

```bash
# Extract code (outputs clean Elixir code)
mix livebook.extract path/to/notebook.livemd > extracted.exs

# Extract with analysis (includes module calls, aliases, etc.)
mix livebook.extract --include-analysis notebook.livemd > analysis.md
```

**What it does:**
- Parses LiveBook markdown files
- Extracts only executable code cells (filters out `force_markdown` examples)
- Optionally analyzes AST for aliases and function calls
- Outputs clean code or detailed markdown analysis

**Perfect for:**
- Testing LiveBook code in CI/CD pipelines
- Validating notebook syntax before committing
- Analyzing dependencies and API usage in notebooks

### 2. `mix api.validate` - Validate API Calls

Validates that all module function calls in your code actually exist at runtime.

**Use Case:** AI agents can verify code correctness by checking that all API calls are valid.

```bash
mix api.validate
```

**What it does:**
- Scans all `.exs` and `.livemd` files in your project
- For LiveBooks, extracts executable code first
- Parses code into AST and extracts all module function calls
- Resolves aliases to full module names
- Uses runtime reflection to verify each function exists
- Reports invalid calls with file locations

**Output example:**
```
VALIDATION SUMMARY
================================================================================
Total files:   15
Valid files:   13 (86.7%)
Invalid files: 2 (13.3%)

INVALID API CALLS FOUND
================================================================================
📄 scripts/example.exs
   ❌ Invalid calls:
      - NonExistent.Module.function
      - Another.Bad.call
```

A more complex (real-world) example would be

```text
Compiling 16 files (.ex)
Generated azure_amqp app
# Validating API calls (checking actual function existence)...
================================================================================
VALIDATION SUMMARY
================================================================================

Total files:   122
Valid files:   78 (63.9%)
Invalid files: 44 (36.1%)

================================================================================
INVALID API CALLS FOUND
================================================================================

📄 content/05_advanced_patterns.livemd
   ❌ Invalid calls:
      - MyEventProcessor.start_link
      - ResilientSend.send_with_retry

📄 content/azure_certificates.livemd
   ❌ Invalid calls:
      - MicrosoftCerts.CompileHelpers.download_certs_for_pinning

...

📄 test/integration/service_bus/sync_api_test.exs
   ❌ Invalid calls:
      - IntegrationConfig.fetch_jwt_token (→ Azure.Amqp.Test.IntegrationConfig.fetch_jwt_token)
      - IntegrationConfig.jwt_config! (→ Azure.Amqp.Test.IntegrationConfig.jwt_config!)

📄 test/integration/service_bus/topics_test.exs
   ❌ Invalid calls:
      - IntegrationConfig.sas_config! (→ Azure.Amqp.Test.IntegrationConfig.sas_config!)

📄 test/integration/stream_receiver_integration_test.exs
   ❌ Invalid calls:
      - Azure.Amqp.Test.IntegrationConfig.eventhub_config!
      - Azure.Amqp.Test.IntegrationConfig.fetch_eventhub_jwt_token
      - ConnectionHolder.get_connection (→ Azure.Amqp.Test.ConnectionHolder.get_connection)
      - IntegrationConfig.sas_config! (→ Azure.Amqp.Test.IntegrationConfig.sas_config!)
      - QueueFlusher.flush_queue (→ Azure.Amqp.Test.QueueFlusher.flush_queue)
      - TelemetryHelper.attach_minimal_handler (→ Azure.Amqp.Test.TelemetryHelper.attach_minimal_handler)
      - TelemetryHelper.detach_all (→ Azure.Amqp.Test.TelemetryHelper.detach_all)
```

**Perfect for:**
- Pre-commit hooks to catch API errors
- CI/CD validation of code quality
- Ensuring LiveBook notebooks use valid APIs
- Detecting typos in module or function names

### 3. `mix api.reference` - Generate API Documentation

Generates comprehensive API reference documentation in markdown format.

**Use Case:** AI agents can generate up-to-date API documentation for understanding codebases.

```bash
mix api.reference
```

**What it does:**
- Introspects all public modules and functions in your application
- Organizes modules by category (configurable)
- Generates markdown documentation with:
  - Module descriptions
  - Function signatures
  - Documentation from `@doc` attributes
  - Return types from `@spec`
- Outputs to configurable file (default: `docs/api-reference.md`)

**Configuration in `mix.exs`:**
```elixir
def project do
  [
    # ... other settings ...
    api_category_mappings: [
      {~r/MyApp.Web/, "Web"},
      {~r/MyApp.Core/, "Core"},
      {~r/MyApp.Data/, "Data Access"},
      {true, "Other"}  # default category
    ],
    api_reference_output_file: "docs/api-reference.md"
  ]
end
```

**Perfect for:**
- Generating documentation for AI agents to learn your API
- Keeping API docs synchronized with code
- Creating reference material for development teams
- Automated documentation in CI/CD

### 4. `mix docs.show_groups` - Show Module Organization

Shows how modules are categorized for documentation.

**Use Case:** Verify module organization before generating documentation.

```bash
mix docs.show_groups
```

**What it does:**
- Displays computed module groups based on `category_mappings`
- Shows which modules fall into which categories
- Helps verify documentation organization

**Perfect for:**
- Debugging category mappings
- Verifying module organization
- Understanding documentation structure

## 🤖 AI Agent Workflows

### Workflow 1: Validate LiveBook Before Committing

```bash
# Extract and test LiveBook code
mix livebook.extract notebook.livemd > /tmp/test.exs
elixir /tmp/test.exs

# Validate API calls
mix api.validate

# If both pass, commit!
git add notebook.livemd
git commit -m "Add working notebook"
```

### Workflow 2: Generate Documentation for AI Learning

```bash
# Generate comprehensive API reference
mix api.reference

# The AI agent can now read docs/api-reference.md to understand your API
cat docs/api-reference.md
```

### Workflow 3: CI/CD Pipeline Validation

```yaml
# .github/workflows/validate.yml
- name: Validate LiveBook API calls
  run: |
    mix deps.get
    mix compile
    mix api.validate
```

### Workflow 4: Extract and Analyze LiveBook Dependencies

```bash
# Extract code with analysis
mix livebook.extract --include-analysis notebook.livemd > analysis.md

# Review module calls and dependencies
cat analysis.md
```

## 📦 Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:llm_code_analysis, github: "chgeuer/llm_code_analysis"}
  ]
end
```

Then run:

```bash
mix deps.get
mix compile
```

## 🔧 Configuration

### API Validation

Configure allowed modules in `mix.exs`:

```elixir
def project do
  [
    api_validation_allowed_modules: [
      "MyApp",           # Allow all MyApp.* modules
      "TestHelper",      # Allow TestHelper module
      "CustomUtil"       # Allow CustomUtil module
    ]
  ]
end
```

By default, all standard library modules are allowed (Enum, String, Map, etc.).

### API Reference Generation

Configure categories and output:

```elixir
def project do
  [
    api_category_mappings: [
      {~r/Azure.ServiceBus/, "Service Bus"},
      {~r/Azure.EventHubs/, "Event Hubs"},
      {~r/Azure.Storage/, "Storage"},
      {true, "Core"}  # catch-all
    ],
    api_reference_output_file: "docs/AZURE_API.md"
  ]
end
```

## 🎓 Use Cases for AI Agents

### 1. **Code Quality Assurance**
- AI agents can automatically validate code before suggesting changes
- Ensure LiveBook examples actually work
- Catch API errors early

### 2. **Documentation Generation**
- AI agents can generate and maintain API documentation
- Keep docs synchronized with code changes
- Provide context for code understanding

### 3. **LiveBook Testing**
- Extract and test notebook code in isolation
- Validate notebooks in CI/CD pipelines
- Ensure examples remain executable

### 4. **API Learning**
- AI agents can read generated API references to understand codebases
- Learn available modules and functions
- Make better code suggestions based on actual APIs

### 5. **Dependency Analysis**
- Understand what modules a LiveBook uses
- Identify external dependencies
- Plan code refactoring

## 🧪 Components

This library includes:

- **`CodeAnalysis.Livebook.Extractor`** - Extract code from LiveBook files
  - Uses `NimbleLivebookMarkdownExtractor` for robust parsing
  - AST-based alias and function call extraction
  - Alias resolution

- **`CodeAnalysis.API.Validator`** - Validate API calls
  - Runtime reflection to check function existence
  - Support for `.exs` and `.livemd` files
  - Detailed error reporting

- **`CodeAnalysis.API.ReferenceGenerator`** - Generate API docs
  - Module introspection
  - Markdown formatting
  - Category-based organization

- **`CodeAnalysis.API.Introspection`** - API analysis utilities
  - Extract module and function information
  - Parse documentation and specs
  - Module categorization

## 📝 Example Output

### API Validation Output

```
VALIDATION SUMMARY
================================================================================
Total files:   24
Valid files:   24 (100.0%)
Invalid files: 0 (0.0%)

✅ All files use valid public APIs!
```

### LiveBook Extraction with Analysis

```markdown
# Extracted Code Analysis

**Source:** `notebook.livemd`

## Extracted Executable Code

```elixir
Mix.install([
  {:req, "~> 0.5"}
])

data = Req.get!("https://api.example.com")
IO.inspect(data)
```

## Analysis

✅ **Code is syntactically valid Elixir**

### Module Function Calls (2)

- `Mix.install`
- `Req.get!`
```

**Built for AI coding agents to validate, analyze, and document Elixir code efficiently.**