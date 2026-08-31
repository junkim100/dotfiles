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
          -- Resolve the repo's real default branch rather than assuming main.
          --
          -- origin/HEAD is the right answer when it exists, but only `git clone`
          -- sets it; a remote added by hand has no such ref. So fall through a
          -- chain and verify each candidate actually resolves before using it,
          -- rather than handing DiffviewOpen a ref that does not exist.
          local function resolves(ref)
            vim.fn.system({ "git", "rev-parse", "--verify", "--quiet", ref })
            return vim.v.shell_error == 0
          end

          local base
          local head = vim.fn.system({ "git", "symbolic-ref", "refs/remotes/origin/HEAD" })
          if vim.v.shell_error == 0 then
            base = (vim.trim(head):gsub("^refs/remotes/", ""))
          else
            for _, candidate in ipairs({ "origin/main", "origin/master", "main", "master" }) do
              if resolves(candidate) then
                base = candidate
                break
              end
            end
          end

          if not base then
            vim.notify(
              "No default branch found (tried origin/HEAD, origin/main, origin/master, main, master).\n"
                .. "Use :DiffviewOpen <base>...HEAD directly.",
              vim.log.levels.WARN
            )
            return
          end
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
