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

-- MOD 14 -- keep the project root where you launched nvim, not at the monorepo top.
--
-- LazyVim's default is { "lsp", { ".git", "lua" }, "cwd" }. Opening a Python file
-- under eval/wbl-eval is already correct, because basedpyright roots itself there
-- and the lsp detector runs first. Launching nvim with no file is not: nothing has
-- attached yet, so it falls to the .git marker and jumps to the solar-system root,
-- putting 40-odd sibling projects in the explorer and grepping the whole monorepo.
--
-- "cwd" alone, so the root is always where you launched, full stop.
--
-- Leaving "lsp" ahead of it looks smarter and mostly works, but it narrows without
-- warning inside vendored code: open src/wbl_eval/evals/agents/mini-swe-agent/... and
-- basedpyright roots itself at that vendored tree, so <leader>/ silently greps the
-- dependency instead of the project. During a PR review that is exactly wrong.
--
-- pyproject.toml is deliberately NOT a marker either: wbl-eval contains 74 of them
-- in vendored trees, so it would root you inside whatever dependency you opened.
--
-- To get the LSP-aware behaviour back, use { "lsp", "cwd" }. The cwd variants of
-- each picker stay available regardless: <leader>E explorer, <leader>fF files,
-- <leader>sG grep.
vim.g.root_spec = { "cwd" }

-- MOD 17 -- absolute line numbers, not relative.
--
-- LazyVim sets both `number` and `relativenumber`, which gives the hybrid gutter: the cursor line shows its real number and every other line shows its distance from the cursor. That makes counted motions easy to type (`8k` for the line labelled 8), at the cost of the whole gutter renumbering on every cursor move.
--
-- `number` stays on, which is already LazyVim's default, so the gutter now shows plain file line numbers. `<leader>uL` toggles relative back on for a session.
vim.opt.relativenumber = false

-- MOD 19 -- a clipboard that reaches the machine you are actually sitting at.
--
-- LazyVim sets `clipboard = vim.env.SSH_CONNECTION and "" or "unnamedplus"`. Inside this tmux SSH_CONNECTION is always set, so the clipboard was empty and `y` never left nvim. Turning it back on alone is not enough either: neovim's provider search finds pbcopy first and pbcopy sets the clipboard of the host nvim runs on, which over SSH is the wrong machine.
--
-- OSC 52 is the escape-sequence protocol that carries a copy out through the terminal instead, so the clipboard that ends up filled is the one in front of you. tmux forwards it already (`set-clipboard external`); no passthrough needed, since tmux handles OSC 52 itself.
--
-- Only when remote. Locally, neovim's own pbcopy path is faster and has no size ceiling, whereas OSC 52 is capped by what tmux and the terminal will accept in one sequence, so a yank of a very large file can be truncated or dropped.
--
-- Paste is deliberately NOT OSC 52. Reading the clipboard that way requires the terminal to answer a query, which tmux does not pass back, so it would hang or return nothing. `p` returns nvim's own last yank instead, and pasting from the outside machine is done with the terminal's paste (Cmd-V), which types the text in and is handled correctly by bracketed paste.
vim.opt.clipboard = "unnamedplus"

if vim.env.SSH_CONNECTION or vim.env.SSH_TTY then
  local osc52 = require("vim.ui.clipboard.osc52")
  local function from_unnamed()
    return { vim.fn.getreg('"', 1, true), vim.fn.getregtype('"') }
  end
  vim.g.clipboard = {
    name = "OSC 52",
    copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
    paste = { ["+"] = from_unnamed, ["*"] = from_unnamed },
  }
end
