# Global Claude Rules

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

## 5. Python Environment Management
- Always use `uv` instead of `conda` for Python project and dependency management.
- For new Python projects:
  - Use `uv init` to initialize the project.
  - Use `uv add <package>` to add runtime dependencies.
  - Use `uv add --dev <package>` to add development dependencies (ruff, pytest, etc.).
- Use `uv run <cmd>` to run Python commands within the project environment (for example `uv run python -m pytest`).
- Prefer the `uv` project workflow (`uv init`, `uv add`, `uv run`) over `pip`, `uv pip`, or manual virtualenv commands.
- Run `uv run ruff check --fix` and `uv run ruff format` on all Python code after completing a task.
- Run `uv run ruff check --fix` and `uv run ruff format` before making any git commits.
- Use `fire` for handling command-line arguments in Python scripts.
