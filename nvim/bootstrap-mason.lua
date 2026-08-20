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
--
-- Which of them can actually install here depends on the machine: mason pulls
-- from several ecosystems and each needs its own toolchain. That is read from
-- each package's registry entry rather than hardcoded, so it stays correct if a
-- package changes how it ships. At time of writing:
--   github -> standalone binary, no runtime (ruff, marksman, taplo,
--             lua-language-server, shellcheck, hadolint)
--   pypi   -> needs python3                 (basedpyright)
--   npm    -> needs node                    (yaml, json, docker, bash, markdown)
--
-- Per-package matters. An earlier version gated the whole run behind `node`,
-- which on a box without node installed zero servers where seven would have been
-- fine. basedpyright especially: it is pypi, and python3 is a safe bet on a GPU
-- box in a way node is not.

local packages = {
  -- language servers
  "basedpyright", -- python
  "ruff", -- python lint/format
  "yaml-language-server", -- 1131 yaml files in wbl-eval
  "json-lsp",
  "marksman", -- markdown
  "taplo", -- toml
  "dockerfile-language-server",
  "docker-compose-language-service", -- wbl-eval has a docker-compose.yml
  "bash-language-server",
  "lua-language-server", -- for editing this config
  -- linters
  "shellcheck",
  "hadolint",
  "markdownlint-cli2",
  "markdown-toc",
}

local runtimes = {
  npm = "node",
  pypi = "python3",
  cargo = "cargo",
  golang = "go",
  gem = "gem",
  composer = "php",
  luarocks = "luarocks",
}

-- Returns the name of the missing toolchain, or nil when the package can install.
local function blocked_by(pkg)
  local id = pkg.spec and pkg.spec.source and pkg.spec.source.id or ""
  local ecosystem = id:match("^pkg:([^/]+)")
  local needs = ecosystem and runtimes[ecosystem]
  if needs and vim.fn.executable(needs) ~= 1 then
    return needs
  end
  return nil
end

vim.cmd("Lazy! load mason.nvim")

local ok, registry = pcall(require, "mason-registry")
if not ok then
  io.write("mason-registry unavailable; skipping server install\n")
  vim.cmd("qa!")
  return
end

local pending, failed, installed, skipped = 0, {}, {}, {}
local refreshed = false

registry.refresh(function()
  for _, name in ipairs(packages) do
    local found, pkg = pcall(registry.get_package, name)
    if not found then
      table.insert(failed, name .. " (not in registry)")
    elseif pkg:is_installed() then
      table.insert(installed, name)
    else
      local missing_runtime = blocked_by(pkg)
      if missing_runtime then
        -- Not a failure: this machine simply cannot build it. Say which toolchain
        -- would fix it instead of letting mason error out mid-install.
        table.insert(skipped, name .. " (needs " .. missing_runtime .. ")")
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
if #skipped > 0 then
  io.write(("\n  skipped (missing toolchain): %s"):format(table.concat(skipped, ", ")))
end
if #failed > 0 then
  io.write(("\n  FAILED: %s"):format(table.concat(failed, ", ")))
end
if pending > 0 then
  io.write((", %d still running at timeout"):format(pending))
end
io.write("\n")

vim.cmd("qa!")
