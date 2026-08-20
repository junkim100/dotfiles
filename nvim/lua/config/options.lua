-- Loaded automatically before lazy.nvim starts.
-- LazyVim's own defaults: https://www.lazyvim.org/configuration/general

-- MOD 1 -- disable unused providers.
-- Opening any .py file makes neovim shell out to probe for a python3 provider.
-- Measured on this machine: 104ms startup with these on, 46ms with them off.
-- Nothing here uses node/perl/ruby/python remote plugins, so all four are dead weight.
vim.g.loaded_node_provider = 0
vim.g.loaded_python3_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0

-- MOD 2 (part 1) -- support for reloading files Claude Code edits underneath you.
--
-- swapfile stays at its default (on). An earlier version of this turned it off
-- claiming it reduced prompts from Claude Code's edits, which is wrong: swap
-- conflicts come from a crashed session or two nvim instances on one file, not
-- from a file changing on disk. Turning it off only gave up crash recovery.
vim.opt.undofile = true
vim.opt.autoread = true
vim.opt.updatetime = 200 -- how long the cursor must rest before CursorHold fires

-- MOD 7 -- match the Python LSP you already used in Zed.
-- LazyVim defaults to pyright; your Zed settings used basedpyright + ruff.
vim.g.lazyvim_python_lsp = "basedpyright"
vim.g.lazyvim_python_ruff = "ruff"

-- MOD 10 -- mouse.
-- 3 lines per wheel tick is jumpy; 2 tracks the content better.
vim.opt.mousescroll = "ver:2,hor:4"

-- Hover events, which is what lets the mouse trigger things rather than only clicks.
-- Every mouse movement sends an event, so this stays off over SSH where that traffic
-- shows up as lag on the GPU boxes. Local sessions get it, remote ones do not.
vim.opt.mousemoveevent = vim.env.SSH_TTY == nil and vim.env.SSH_CONNECTION == nil

-- MOD 11 -- teach nvim about this monorepo's own file conventions.
-- pants BUILD files are Python (`python_sources()` and friends) but carry no
-- extension, so without this the 240 of them in wbl-eval render as plain text.
vim.filetype.add({
  filename = {
    BUILD = "python",
    ["BUILD.pants"] = "python",
  },
  extension = {
    -- Jinja templates. There is no dedicated parser, but htmldjango gets most of
    -- the delimiters right, which beats treating them as plain text.
    j2 = "htmldjango",
    jinja = "htmldjango",
  },
})
