# Global Claude Rules

## Python Environment Management
- Always use `uv` instead of `conda` for Python project and dependency management.
- For new Python projects:
  - Use `uv init` to initialize the project.
  - Use `uv add <package>` to add runtime dependencies.
  - Use `uv add --dev <package>` to add development dependencies (ruff, pytest, etc.).
- Use `uv run <cmd>` to run Python commands within the project environment (for example `uv run python -m pytest`).
- Prefer the `uv` project workflow (`uv init`, `uv add`, `uv run`) over `pip`, `uv pip`, or manual virtualenv commands. 

## Python CLI Arguments
- Use `fire` for handling command-line arguments in Python scripts.
- Prefer fire over argparse, click, or typer unless a requirement explicitly demands otherwise.

## Code Quality
- Run `uv run ruff check --fix` and `uv run ruff format` on all Python code after completing a task.
- Run `uv run ruff check --fix` and `uv run ruff format` before making any git commits.
- Fix any linting errors before considering a task complete.

