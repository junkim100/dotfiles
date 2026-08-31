return {
  -- MOD 21 -- put back the two things LazyVim switches off in render-markdown.
  --
  -- The markdown extra already ships render-markdown.nvim and it is already rendering: bullets, tables, code blocks, blockquotes, and concealed emphasis markers all work out of the box. What LazyVim turns off is `heading.icons` and `checkbox`, which are the two most visible parts, so the buffer reads as "markdown is not being rendered" when nearly all of it is.
  --
  -- Nothing else is touched. `code.width = "block"` and `sign = false` stay as LazyVim set them.
  {
    "MeanderingProgrammer/render-markdown.nvim",
    opts = {
      heading = {
        icons = { "󰲡 ", "󰲣 ", "󰲥 ", "󰲧 ", "󰲩 ", "󰲫 " },
      },
      checkbox = {
        enabled = true,
      },
    },
  },
}
