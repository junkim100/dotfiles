return {
  -- MOD 18 -- basedpyright, turned down from "tell me everything" to "tell me what is wrong".
  --
  -- basedpyright defaults to `typeCheckingMode = "recommended"`, which is considerably stricter than the pyright default LazyVim was written against, and LazyVim ships no settings for it. Six lines of ordinary python produce eight diagnostics: reportAny on every value that came from an untyped library, reportUnknownParameterType and reportMissingParameterType on every un-annotated argument, reportUnknownVariableType on every inferred local. None of them mean the code is wrong; they mean the code is not fully annotated, which for a research monorepo is every file.
  --
  -- "standard" is pyright's own default and takes that same file to one diagnostic. Real type errors still surface: an `x: int = "not an int"` is still an error under it.
  --
  -- The two import rules are off because in solar-system they cannot be right. pants runs with `enable_resolves = false` and resolves each target's requirements into its own sandbox, so there is no single interpreter that has the dependency set installed. The .venv at the repo root holds only the pre-commit and pytest tooling, and nothing is on PATH but the system python 3.9. basedpyright therefore cannot resolve a third-party import in that tree no matter how it is pointed, so the rule fires on correct code every time.
  --
  -- The cost is that a genuinely misspelled import name goes unflagged. If a project ever does get a venv with its real dependencies, delete the two overrides and point basedpyright at it with `python = { pythonPath = "<venv>/bin/python" }` instead, which fixes the diagnostics properly rather than hiding them.
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        basedpyright = {
          settings = {
            basedpyright = {
              analysis = {
                typeCheckingMode = "standard",
                diagnosticSeverityOverrides = {
                  reportMissingImports = "none",
                  reportMissingModuleSource = "none",
                },
              },
            },
          },
        },
      },
    },
  },
}
