# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Changed
- **Function signatures now show parameter names instead of arity** - The API reference generator now extracts parameter names from function documentation and displays them in the generated markdown. For example, instead of `terminate/2` and `terminate/3`, it now shows `terminate(reason, state)` and `terminate(reason, state, timeout)`. This makes the API reference more informative and easier to understand for LLM coding agents and developers.

### Enhanced
- Improved handling of functions with default parameters - When a function has default parameters creating multiple arities (like `from_connection_string/1` and `from_connection_string/2`), the generator now correctly extracts and displays the appropriate parameter names for each arity.
- Better handling of `__struct__` functions - Struct literal signatures like `%Module{}` are now properly converted to `__struct__()` format.

### Technical Details
- Updated `CodeAnalysis.API.Introspection.get_module_functions/2` to extract function signatures with parameter names from `Code.fetch_docs/1`
- Added `extract_signature/3`, `find_doc_entry/3`, `extract_function_call/1`, and `extract_function_call_with_params/2` helper functions
- Function signatures are extracted from the docs metadata and cleaned up to remove default value expressions while preserving parameter names

## [0.1.0] - Initial Release

### Added
- Mix task `mix api.validate` for validating API calls in code
- Mix task `mix api.reference` for generating API reference documentation
- Mix task `mix livebook.extract` for extracting code from LiveBook files
- Mix task `mix docs.show_groups` for showing module organization
- `CodeAnalysis.API.Introspection` module for API introspection
- `CodeAnalysis.API.ReferenceGenerator` module for generating API documentation
- `CodeAnalysis.API.Validator` module for validating API calls
- `CodeAnalysis.Livebook.Extractor` module for extracting LiveBook code
