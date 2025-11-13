# AI Agent Quick Reference - LLM Code Analysis

## Quick Commands

```bash
# Validate all code files
mix api.validate

# Extract LiveBook code
mix livebook.extract notebook.livemd > code.exs

# Extract with analysis
mix livebook.extract --include-analysis notebook.livemd > analysis.md

# Generate API reference
mix api.reference

# Show module groups
mix docs.show_groups
```

## Common AI Agent Workflows

### 1. Test LiveBook Before Commit

```bash
# Extract and validate
mix livebook.extract notebook.livemd > /tmp/test.exs
elixir /tmp/test.exs && echo "✅ Valid" || echo "❌ Failed"

# Check API calls
mix api.validate
```

### 2. Validate Changed Files

```bash
# Get changed LiveBook files
git diff --name-only | grep '.livemd$' | while read file; do
  echo "Validating $file..."
  mix livebook.extract "$file" > /tmp/extracted.exs
  elixir /tmp/extracted.exs
done
```

### 3. Generate Fresh API Docs

```bash
# Ensure compiled
mix compile

# Generate docs
mix api.reference

# Docs are now in docs/api-reference.md
```

### 4. Pre-Commit Hook

```bash
#!/bin/bash
# .git/hooks/pre-commit

# Validate all API calls
mix api.validate || {
  echo "❌ API validation failed"
  exit 1
}

# Validate LiveBook files
for file in $(git diff --cached --name-only | grep '.livemd$'); do
  mix livebook.extract "$file" > /tmp/test.exs || {
    echo "❌ Failed to extract $file"
    exit 1
  }
  
  elixir /tmp/test.exs || {
    echo "❌ Extracted code from $file has errors"
    exit 1
  }
done

echo "✅ All validations passed"
```

## Understanding Output

### API Validation Success

```
VALIDATION SUMMARY
Total files:   15
Valid files:   15 (100.0%)
Invalid files: 0 (0.0%)

✅ All files use valid public APIs!
```

### API Validation Failure

```
VALIDATION SUMMARY
Total files:   15
Valid files:   13 (86.7%)
Invalid files: 2 (13.3%)

INVALID API CALLS FOUND
📄 scripts/example.exs
   ❌ Invalid calls:
      - NonExistent.Module.function
```

**Action:** Fix the invalid function calls in the listed files.

### LiveBook Extraction

```elixir
# Output is clean, executable Elixir code
Mix.install([
  {:req, "~> 0.5"}
])

data = Req.get!("https://api.example.com")
```

**Use:** Save to `.exs` file and execute with `elixir`.

### LiveBook Analysis

```markdown
## Analysis

✅ **Code is syntactically valid Elixir**

### Module Function Calls (2)
- `Mix.install`
- `Req.get!`
```

**Use:** Understand dependencies and API usage.

## Configuration Tips

### Allow Custom Modules (mix.exs)

```elixir
def project do
  [
    api_validation_allowed_modules: [
      "MyApp",
      "MyTestHelper"
    ]
  ]
end
```

### Configure API Reference Categories

```elixir
def project do
  [
    api_category_mappings: [
      {~r/MyApp.Web/, "Web Interface"},
      {~r/MyApp.Core/, "Core Logic"},
      {true, "Utilities"}
    ],
    api_reference_output_file: "docs/API.md"
  ]
end
```

## Error Handling

### "Module not loaded"

**Cause:** Module isn't compiled or available.

**Fix:** Run `mix compile` first.

### "No executable code found"

**Cause:** LiveBook only has markdown or all code is marked `force_markdown`.

**Fix:** Ensure LiveBook has executable code cells.

### "Syntax error in extracted code"

**Cause:** LiveBook cells might be incomplete or have syntax errors.

**Fix:** Check individual code cells in the LiveBook.

## Integration with CI/CD

### GitHub Actions

```yaml
name: Validate Code

on: [push, pull_request]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      
      - name: Setup Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.19'
          otp-version: '27'
      
      - name: Install dependencies
        run: mix deps.get
      
      - name: Compile
        run: mix compile
      
      - name: Validate API calls
        run: mix api.validate
      
      - name: Test LiveBooks
        run: |
          for file in $(find . -name "*.livemd" -not -path "./deps/*"); do
            echo "Testing $file..."
            mix livebook.extract "$file" > /tmp/test.exs
            elixir /tmp/test.exs
          done
```

## Best Practices for AI Agents

1. **Always run `mix compile` before validation tasks**
2. **Use `api.validate` before committing code changes**
3. **Generate fresh API docs after adding new modules**
4. **Test extracted LiveBook code in isolation**
5. **Use `--include-analysis` to understand dependencies**
6. **Configure allowed modules for your project in mix.exs**
7. **Integrate validation into your CI/CD pipeline**

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Task not found | Run `mix deps.get && mix compile` |
| Module not loaded | Ensure application is compiled |
| Invalid API calls found | Check if modules are actually available |
| Empty extraction | LiveBook has no executable code |
| Parsing error | Check LiveBook syntax |

---

**Quick tip:** Run `mix help <task>` for detailed task documentation.
Example: `mix help livebook.extract`
