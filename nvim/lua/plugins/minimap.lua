return {
  -- MOD 9 -- minimap, replacing Zed's `"minimap": { "show": "always" }`.
  --
  -- Terminal minimaps draw at character-cell resolution, so this is coarser than
  -- Zed's pixel-rendered one. neominimap uses treesitter for the colouring, which
  -- makes it the closest of the options. It needs `wrap = false`, which LazyVim
  -- already sets.
  --
  -- Toggle with <leader>mm if it turns out to cost more width than it earns.
  {
    "Isrothy/neominimap.nvim",
    version = "v3.*.*",
    lazy = false,
    keys = {
      { "<leader>mm", "<cmd>Neominimap toggle<cr>", desc = "Minimap: toggle" },
      { "<leader>mf", "<cmd>Neominimap focus<cr>", desc = "Minimap: focus" },
    },
    init = function()
      vim.opt.sidescrolloff = 36 -- so the minimap does not shove text off-screen
      vim.g.neominimap = {
        auto_enable = true,
        layout = "float",
        float = { window_border = "none" },
        -- Skip buffers where a minimap is meaningless or actively in the way.
        exclude_filetypes = {
          "help", "bigfile", "snacks_picker_list", "snacks_layout_box",
          "snacks_picker_input", "trouble", "lazy", "mason", "neo-tree",
          -- Diffview panes are already a side-by-side comparison; a minimap on top
          -- of them is noise, and it eats width the diff needs.
          "DiffviewFiles", "DiffviewFileHistory", "diff",
        },
        exclude_buftypes = { "nofile", "nowrite", "quickfix", "terminal", "prompt" },
        git = { enabled = true },       -- git signs in the minimap gutter
        diagnostic = { enabled = true },
        search = { enabled = true },    -- show matches from / in the minimap
        treesitter = { enabled = true },
      }
    end,
  },
}
