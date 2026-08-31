return {
  -- MOD 13 -- explicit formatters for the file types this monorepo is made of.
  --
  -- Stock LazyVim only wires conform for lua, sh, markdown, and fish. Everything
  -- else was left to conform's LSP fallback, which turns out not to be dependable:
  -- taplo attaches to a .toml buffer advertising textDocument/formatting, and the
  -- fallback still does nothing. Naming the formatter per filetype makes it
  -- deterministic instead of a race against the language server attaching.
  --
  -- Function form on purpose: formatters_by_ft is a plain table that LazyVim has
  -- already populated, so assigning a fresh table would drop lua and sh.
  {
    "stevearc/conform.nvim",
    opts = function(_, opts)
      opts.formatters_by_ft = opts.formatters_by_ft or {}
      opts.formatters_by_ft.toml = { "taplo" }
      opts.formatters_by_ft.json = { "prettier" }
      opts.formatters_by_ft.jsonc = { "prettier" }
      opts.formatters_by_ft.yaml = { "prettier" }
      return opts
    end,
  },
}
