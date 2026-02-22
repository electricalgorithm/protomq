---
trigger: always_on
---

# Code Style Guide

## Python
We strictly adhere to the [Google Python Style Guide](https://google.github.io/styleguide/pyguide.html).
- **Indentation:** Use 4 spaces per indentation level.
- **Line Length:** Maximum 80 characters.
- **Tools:** Use `ruff` for linting and formatting to enforce these standards automatically. Use 'mypy' for type-strict coding.
- **Documentation:** Use Google-style docstrings for documenting modules, classes, and functions. Each module, function or class must have a docstring.

## Bash
For shell scripting, the main goal is readability, maintainability, and safety.
- **Linting:** Always run scripts through [`shellcheck`](https://www.shellcheck.net/) and resolve any warnings.
- **Formatting:** Use [`shfmt`](https://github.com/mvdan/sh) for consistent formatting (suggested: 2 spaces for indentation).
- **Safety:** Always start scripts with `set -euo pipefail` to catch errors, uninitialized variables, and hidden pipe failures early.
- **Best Practices:**
  - ALWAYS quote your variables (e.g., `"$var"`) to prevent word splitting and globbing issues.
  - Use `$(command)` for command substitution instead of backticks (`` `command` ``).
  - Use function declarations like `my_func() { ... }` instead of `function my_func { ... }`.
  - Prefer descriptive variable names over terse ones.

## Zig
Zig's standard library and compiler set a strong precedent for style. Prioritize explicitness, code readability, and leveraging the built-in toolchain.
- **Formatting:** Always run `zig fmt` on your codebase before submitting changes. The formatter is the absolute source of truth for indentation, line breaks, and bracket placement.
- **Naming Conventions:**
  - Use `PascalCase` for types (structs, enums, unions, errors).
  - Use `camelCase` for functions, variables, and struct members.
  - Use `snake_case` for file names and directory names.
- **Best Practices:**
  - Avoid `catch unreachable` unless you can mathematically prove the error will never happen. If you use it, document *why* it is safe.
  - Value explicit error handling and propagation (`try`).
  - Keep functions focused and small.
  - Add doc comments (`///`) for all public APIs, structs, and complex internal logic.
