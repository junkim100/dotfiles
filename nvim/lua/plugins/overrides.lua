return {
  -- MOD 3 -- stop mason from auto-downloading tool binaries.
  --
  -- Stock LazyVim installs stylua and shfmt on first launch, unprompted. Neither is
  -- useful here (Claude Code does the editing), and on a shared GPU box you do not
  -- want nvim pulling binaries into ~/.local/share/nvim/mason on its own.
  --
  -- Note the function form: LazyVim marks this key `opts_extend`, so the usual
  -- `opts = { ensure_installed = {} }` would MERGE with the defaults and still
  -- install both. Mutating opts in a function is what actually replaces the list.
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      -- Filter, do not replace. An earlier version of this set ensure_installed to a
      -- fixed list, which silently wiped every server the lang.* extras add: enabling
      -- lang.yaml and friends installed nothing at all. Removing only the entries we
      -- do not want keeps this working as extras come and go.
      --
      -- stylua and shfmt are formatters for code Claude Code writes, so neither earns
      -- a download. Everything else, including every language server, passes through.
      local skip = { stylua = true, shfmt = true }
      local keep = {}
      for _, tool in ipairs(opts.ensure_installed or {}) do
        if not skip[tool] then
          keep[#keep + 1] = tool
        end
      end
      opts.ensure_installed = keep
      return opts
    end,
  },

  -- MOD 5 -- trim the treesitter parser set.
  --
  -- Every parser is compiled from C on first run, so the stock list is a long build
  -- on any new machine and needs a working compiler. This keeps what you actually
  -- read (Python, shell, config, markdown) plus the handful LazyVim needs internally,
  -- and drops the web stack. Same function-form reason as above: opts_extend.
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      -- Filter, same reasoning as the mason block above. Replacing this list with a
      -- fixed one silently dropped parsers the lang.* extras add, which is how
      -- Dockerfiles ended up with no highlighting after lang.docker was enabled.
      --
      -- Every parser compiles from C on first run, so the web stack is dropped: none
      -- of it appears in this monorepo, and each one is build time on a fresh machine.
      local skip = {
        html = true, javascript = true, jsdoc = true, tsx = true,
        typescript = true, css = true, scss = true, vue = true, svelte = true,
      }
      local keep = {}
      for _, lang in ipairs(opts.ensure_installed or {}) do
        if not skip[lang] then
          keep[#keep + 1] = lang
        end
      end
      opts.ensure_installed = keep
      return opts
    end,
  },

  -- MOD 6 -- show dotfiles by default in the explorer, file finder, and grep.
  --
  -- snacks defaults `hidden = false`, which hides anything starting with a dot.
  -- That makes the explorer close to useless in a dotfiles repo, and it also hides
  -- .github/, .claude/, .env, and friends in normal projects.
  --
  -- `ignored` stays false on purpose: that one controls GITIGNORED files, and
  -- flipping it floods the picker with .venv/, __pycache__/, and node_modules/.
  -- Press H inside any picker to toggle hidden at runtime.
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        sources = {
          explorer = { hidden = true, ignored = false },
          files = { hidden = true, ignored = false },
          grep = { hidden = true, ignored = false },
        },
      },
    },
  },
}
