-- Installs the language servers and linters this config expects, then exits.
--
-- Run headlessly from the install scripts:
--   nvim --headless -c "luafile ~/.config/nvim/bootstrap-mason.lua"
--
-- Note: -c luafile, not -l. `nvim -l` does not load the user config, so lazy.nvim
-- would not exist and the Lazy! command would fail.
--
-- Why this exists: mason-lspconfig installs a server the first time you open a
-- matching filetype. That works, but it means the first real session on a new
-- machine has no LSP while things download in the background. Doing it during
-- install instead means the editor is complete the first time you open it.
--
-- The list is explicit rather than derived. Deriving it from the enabled extras
-- means a silent no-op the moment LazyVim renames something, and a silent no-op
-- here looks exactly like a working install until you press `gd` and nothing
-- happens.

local packages = {
  -- language servers
  "basedpyright", -- python
  "ruff", -- python lint/format
  "yaml-language-server", -- 1131 yaml files in wbl-eval
  "json-lsp",
  "marksman", -- markdown
  "taplo", -- toml
  "dockerfile-language-server",
  "bash-language-server",
  "lua-language-server", -- for editing this config
  -- linters
  "shellcheck",
  "hadolint",
  "markdownlint-cli2",
  "markdown-toc",
}

vim.cmd("Lazy! load mason.nvim")

local ok, registry = pcall(require, "mason-registry")
if not ok then
  io.write("mason-registry unavailable; skipping server install\n")
  vim.cmd("qa!")
  return
end

local pending, failed, installed = 0, {}, {}
local refreshed = false

registry.refresh(function()
  for _, name in ipairs(packages) do
    local found, pkg = pcall(registry.get_package, name)
    if not found then
      table.insert(failed, name .. " (not in registry)")
    elseif pkg:is_installed() then
      table.insert(installed, name)
    else
      pending = pending + 1
      pkg:once("install:success", function()
        pending = pending - 1
        table.insert(installed, name)
      end)
      pkg:once("install:failed", function()
        pending = pending - 1
        table.insert(failed, name)
      end)
      pkg:install()
    end
  end
  refreshed = true
end)

-- Poll rather than exit immediately: installs are async, and quitting early is
-- what leaves a machine half-provisioned. 10 minutes is generous for a slow link.
--
-- `refreshed` guards a race: registry.refresh is itself async, so without it
-- `pending` is still 0 on the first tick, vim.wait returns straight away, and the
-- script quits before a single package has started. That failure is invisible --
-- the script prints "0 installed" and exits 0, and you only find out when `gd`
-- does nothing on a machine you thought was provisioned.
local deadline = vim.uv.now() + 10 * 60 * 1000
vim.wait(10 * 60 * 1000, function()
  return (refreshed and pending == 0) or vim.uv.now() > deadline
end, 500)

if not refreshed then
  io.write("mason: registry refresh never completed; nothing installed\n")
  vim.cmd("qa!")
  return
end

io.write(("mason: %d installed"):format(#installed))
if #failed > 0 then
  io.write((", %d FAILED: %s"):format(#failed, table.concat(failed, ", ")))
end
if pending > 0 then
  io.write((", %d still running at timeout"):format(pending))
end
io.write("\n")

vim.cmd("qa!")
