-- MOD 15 -- no diagnostic decoration where the diagnostics are noise rather than news.
--
-- All three display channels go off together in these buffers: the inline virtual text, the undercurl under the offending text, and the sign in the gutter. Turning off only the virtual text still left a yellow undercurl on most lines of a markdown file, which is the same noise in a quieter font.
--
-- The diagnostics themselves still exist. <leader>cd, <leader>xx, ]d, and Trouble all still list them, and the conform hook that runs `markdownlint-cli2 --fix` on save still sees the diagnostics it keys off. What changes is only what gets painted into the buffer.
--
-- markdown: markdownlint-cli2, which the markdown extra wires into nvim-lint, fires MD013 (line length) on nearly every paragraph, because prose here is written one logical line per paragraph instead of wrapped at a column. That leaves a warning hanging off the end of most lines and makes a README unreadable.
--
-- yaml: the yaml extra runs yamlls with `validate = true` against the whole SchemaStore catalogue. Any GitHub Actions file using a key newer than the schema, any manifest with a CRD, anything Helm-templated, gets "Property X is not allowed" on lines that are perfectly correct.
--
-- BUILD, BUILD.pants: MOD 11 maps these to filetype python so they highlight, which also attaches basedpyright to them. `python_sources()` and its siblings are pants builtins that no import declares, so basedpyright reports every line of every BUILD file as an undefined name. Matched by filename rather than filetype, since the filetype really is python.
--
-- json is deliberately NOT here: jsonls diagnostics in a .json file are almost always a real missing or trailing comma, and that is exactly when the inline text is worth having.
--
-- LazyVim passes `opts.diagnostics` straight to vim.diagnostic.config(). Each display option there may be a fun(namespace, bufnr) that neovim resolves per buffer, so opting buffers out needs no autocmd and no second namespace. The values returned otherwise are LazyVim's own defaults, copied from lazyvim/plugins/lsp/init.lua, so nothing outside these buffers changes.
--
-- To keep one channel in the quiet buffers, drop its wrapper: `underline = true` alone puts the undercurl back everywhere while the text and signs stay off.

local quiet_filetypes = {
  markdown = true,
  ["markdown.mdx"] = true,
  yaml = true,
}

local quiet_filenames = {
  BUILD = true,
  ["BUILD.pants"] = true,
}

local function is_quiet(bufnr)
  return quiet_filetypes[vim.bo[bufnr].filetype] == true
    or quiet_filenames[vim.fs.basename(vim.api.nvim_buf_get_name(bufnr))] == true
end

return {
  {
    "neovim/nvim-lspconfig",
    -- Wrapping the values LazyVim already computed, rather than restating them, so this
    -- keeps working if LazyVim changes a default or an extra adds to one. The `opts`
    -- function form receives the merged table, and each wrapper runs per buffer at
    -- render time.
    opts = function(_, opts)
      for _, channel in ipairs({ "virtual_text", "underline", "signs" }) do
        local configured = opts.diagnostics[channel]
        opts.diagnostics[channel] = function(namespace, bufnr)
          if is_quiet(bufnr) then
            return false
          end
          -- Unlikely, but LazyVim could hand us a per-buffer function of its own.
          if type(configured) == "function" then
            return configured(namespace, bufnr)
          end
          return configured
        end
      end
    end,
  },
}
