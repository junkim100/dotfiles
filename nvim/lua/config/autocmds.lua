-- Loaded automatically. LazyVim's own autocmds are already applied.

-- MOD 2 (part 2) -- reload files that changed on disk while sitting still.
--
-- LazyVim already runs :checktime on FocusGained/TermClose/TermLeave, which covers
-- "switch to the Claude Code pane, come back". Switching buffers is covered natively
-- by 'autoread'. What neither covers: staying inside nvim, on the same buffer, while
-- Claude Code rewrites the file. Without this the screen shows stale code with no hint.
vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
  group = vim.api.nvim_create_augroup("checktime_idle", { clear = true }),
  callback = function()
    -- Only real file buffers, and never while a command line is open.
    if vim.bo.buftype == "" and vim.fn.mode() ~= "c" then
      vim.cmd("checktime")
    end
  end,
})

-- Say so when it happens, otherwise the buffer changes under you with no explanation.
vim.api.nvim_create_autocmd("FileChangedShellPost", {
  group = vim.api.nvim_create_augroup("checktime_notify", { clear = true }),
  callback = function()
    vim.notify("Reloaded from disk", vim.log.levels.INFO, { title = "File changed" })
  end,
})

-- MOD 8 -- carry the terminal's transparency into floating windows and pickers.
--
-- everforest-nvim clears its core highlights, but Snacks pickers, explorer windows, and hover windows use plugin-specific groups that can retain opaque backgrounds.
--
-- Attributes are read and merged rather than replaced: passing `{ bg = "none" }` to `nvim_set_hl` overwrites the whole definition and would drop foreground colors.
local function clear_bg(group)
  local hl = vim.api.nvim_get_hl(0, { name = group, link = false })
  if vim.tbl_isempty(hl) then
    return
  end
  hl.bg, hl.ctermbg = nil, nil
  pcall(vim.api.nvim_set_hl, 0, group, hl)
end

local transparent_groups = {
  "NormalFloat",
  "FloatBorder",
  "FloatTitle",
  "FloatFooter",
  "SnacksNormal",
  "SnacksNormalNC",
  "SnacksWinBar",
  "SnacksWinBarNC",
  "SnacksPicker",
  "SnacksPickerList",
  "SnacksPickerInput",
  "SnacksPickerBox",
  "SnacksPickerPreview",
  "SnacksPickerBorder",
  "SnacksPickerListBorder",
  "SnacksPickerInputBorder",
  "SnacksPickerPreviewBorder",
  "SnacksPickerTitle",
  "SnacksDashboardNormal",
  "SnacksNotifierHistory",
  "TelescopeNormal",
  "TelescopeBorder",
  "WhichKeyNormal",
  "TroubleNormal",
}

local function apply_transparency()
  for _, g in ipairs(transparent_groups) do
    clear_bg(g)
  end
end

vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("transparent_floats", { clear = true }),
  callback = apply_transparency,
})

-- The colorscheme has usually already loaded by the time this file runs, so the
-- autocmd alone would not fire on startup.
apply_transparency()

-- MOD 16 -- no spell checking, in any filetype.
--
-- LazyVim turns `spell` on for text, plaintex, typst, gitcommit, and markdown (its own autocmds.lua, group `lazyvim_wrap_spell`). Nothing in the neovim runtime does, so that one autocmd is the whole story, and re-creating its group with `clear = true` from here replaces it: LazyVim loads its autocmds before this file, so the group is already in place to take over.
--
-- The `wrap = true` half of that autocmd is worth keeping. Prose in this repo is one logical line per paragraph, so without soft wrap a paragraph runs off the right edge as a single line.
--
-- `<leader>us` still toggles spell per window if you ever want it back for one buffer.
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("lazyvim_wrap_spell", { clear = true }),
  pattern = { "text", "plaintex", "typst", "gitcommit", "markdown" },
  callback = function()
    vim.opt_local.wrap = true
  end,
})
