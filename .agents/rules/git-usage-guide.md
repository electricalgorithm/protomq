---
trigger: always_on
---

# Git Usage Guide

As an agent working on this repository, you must adhere to the following Git workflow and commit message conventions.

## Commit Message Format

We strictly follow the [Conventional Commits](https://www.conventionalcommits.org/) specification for our commit messages.

1.  **Header:** The commit header must use the conventional commit format: `<type>(<scope>): <description>`.
    *   Examples of types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`.
2.  **Body:** Explain the changes made and *why* they are needed. Do not just describe *what* changed, as the diff already shows that. Focus on the reasoning and context.
3.  **Footer:** Every commit must have a sign-off in the footer.

## Pre-Commit Requirements

Before committing your changes, you must guarantee code quality by running the appropriate checks based on the file types modified:

*   **Python:** The code must be tested against `ruff` rules. Include linting and formatting checks.
*   **Bash:** The code must be checked with `shellcheck` to resolve any warnings or errors.
*   **Zig:** Any Zig code must be successfully built and tested.

## Integration Testing

Before considering a goal "done" or creating a pull request, you **must run all integration tests**. 

Execute the following script from the root directory to run the full test suite:
```bash
./tests/run_all.sh
```
Ensure all tests pass successfully.

## Performance Benchmarks

If your changes are related to performance (e.g., optimizations, memory management, algorithmic improvements, etc.), you **shall run the relevant benchmarks** to verify the impact of your changes. Include the benchmark results in your final report or pull request.
