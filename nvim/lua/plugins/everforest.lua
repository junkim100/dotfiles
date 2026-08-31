return {
  {
    "neanias/everforest-nvim",
    version = false,
    lazy = false,
    priority = 1000,
    opts = {
      background = "medium",
      transparent_background_level = 2,
    },
    config = function(_, opts)
      require("everforest").setup(opts)
    end,
  },
  { "LazyVim/LazyVim", opts = { colorscheme = "everforest" } },
}
