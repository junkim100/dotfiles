return {
  -- MOD 20 -- delete a saved session.
  --
  -- persistence.nvim can list, load, and pick sessions, but has no way to remove one. They are plain .vim files in stdpath("state").."/sessions", named after the directory with every / replaced by %, so deleting one is deleting its file. Without this, clearing out a session for a directory you have since deleted or renamed means finding that file by hand.
  --
  -- The decoding mirrors persistence's own select(), with one deliberate difference: select() dedupes by directory, which hides the per-branch sessions it writes for a git repo. Deleting is exactly when you want to see those, so this dedupes by file instead and shows the branch alongside the path.
  {
    "folke/persistence.nvim",
    -- stylua: ignore
    keys = {
      {
        "<leader>qx",
        function()
          local config = require("persistence.config")
          local items = {}
          for _, session in ipairs(require("persistence").list()) do
            local file = session:sub(#config.options.dir + 1, -5)
            local dir, branch = unpack(vim.split(file, "%%", { plain = true }))
            items[#items + 1] = {
              session = session,
              dir = (dir:gsub("%%", "/")),
              branch = branch and (branch:gsub("%%", "/")) or nil,
            }
          end
          if #items == 0 then
            vim.notify("No saved sessions", vim.log.levels.INFO, { title = "Persistence" })
            return
          end
          vim.ui.select(items, {
            prompt = "Delete a session: ",
            format_item = function(item)
              local name = vim.fn.fnamemodify(item.dir, ":p:~")
              return item.branch and (name .. "  [" .. item.branch .. "]") or name
            end,
          }, function(item)
            if not item then
              return
            end
            if vim.fn.delete(item.session) == 0 then
              vim.notify("Deleted session for " .. item.dir, vim.log.levels.INFO, { title = "Persistence" })
            else
              vim.notify("Could not delete " .. item.session, vim.log.levels.ERROR, { title = "Persistence" })
            end
          end)
        end,
        desc = "Delete Session",
      },
    },
  },
}
