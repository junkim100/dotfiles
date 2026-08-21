-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- MOD 21 -- copy the current file's path.
--
-- The explorer already yanks a path with `y`, but only for the entry under the cursor there. Nothing in LazyVim copies the path of the buffer you are actually editing, which is what you want when handing a location to Claude Code or to someone else.
--
-- Both registers are set, not just `+`. Over SSH the `+` paste handler in MOD 19 returns the unnamed register rather than reading the clipboard back, so setting `+` alone would send the path to the laptop but leave `p` inside nvim pasting whatever you yanked before.
--
-- `:.` is relative to nvim's cwd, which MOD 14 pins as the project root, so the relative form is the repo-relative path you can paste into a review comment.
local function copy_path(modifier, label)
  return function()
    local path = vim.fn.expand("%" .. modifier)
    if path == "" then
      vim.notify("Buffer has no file", vim.log.levels.WARN, { title = "Copy path" })
      return
    end
    vim.fn.setreg("+", path)
    vim.fn.setreg('"', path)
    vim.notify(path, vim.log.levels.INFO, { title = "Copied " .. label })
  end
end

vim.keymap.set("n", "<leader>fy", copy_path(":.", "relative path"), { desc = "Copy relative path" })
vim.keymap.set("n", "<leader>fY", copy_path(":p", "full path"), { desc = "Copy full path" })
