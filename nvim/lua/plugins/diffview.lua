return {
  -- MOD 12 -- side-by-side changeset review, the one thing lazygit does not do well.
  --
  -- lazygit shows diffs in a single pane. This gives a file panel plus two-pane diffs
  -- for a whole branch at once, which is the shape of a PR review.
  --
  -- Layout follows the Zed settings this replaced: "diff_view_style": "split" becomes
  -- diff2_horizontal, and the git panel's tree_view becomes listing_style = "tree".
  {
    "sindrets/diffview.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    cmd = {
      "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory",
      "DiffviewToggleFiles", "DiffviewFocusFiles", "DiffviewRefresh",
    },
    keys = {
      { "<leader>gv", "<cmd>DiffviewOpen<cr>", desc = "Diffview: working changes" },
      { "<leader>gV", "<cmd>DiffviewFileHistory %<cr>", desc = "Diffview: this file's history" },
      {
        "<leader>gr",
        function()
          -- Resolve the repo's actual default branch rather than assuming main.
          local ref = vim.fn.system({ "git", "symbolic-ref", "refs/remotes/origin/HEAD" })
          local base = vim.v.shell_error == 0
              and vim.trim(ref):gsub("^refs/remotes/", "")
            or "origin/main"
          vim.cmd("DiffviewOpen " .. base .. "...HEAD")
        end,
        desc = "Diffview: review branch vs base",
      },
    },
    opts = {
      enhanced_diff_hl = true, -- clearer add/change/delete colours than plain diff
      view = {
        default = { layout = "diff2_horizontal" }, -- side by side
        merge_tool = { layout = "diff3_horizontal" },
        file_history = { layout = "diff2_horizontal" },
      },
      file_panel = {
        listing_style = "tree",
        win_config = { position = "left", width = 35 },
      },
    },
  },
}
