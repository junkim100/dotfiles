return {
  -- MOD 4 -- nord, matching your ghostty and tmux themes.
  -- gbprod's port rather than shaunsingh's: it ships integrations for the plugins
  -- LazyVim actually uses (snacks, telescope, gitsigns, lualine, which-key), so the
  -- whole UI is themed instead of just the buffer text.
  {
    "gbprod/nord.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      -- Ghostty runs background-opacity 0.7 + background-blur 30, and the theme
      -- there is the same nord. Painting a solid #2E3440 here would cancel both,
      -- so let the terminal's own background show through instead.
      transparent = true,
      diff = { mode = "bg" },
      search = { theme = "vim" },
    },
  },
  { "LazyVim/LazyVim", opts = { colorscheme = "nord" } },
}
