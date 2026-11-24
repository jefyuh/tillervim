return {
  "MeanderingProgrammer/render-markdown.nvim",
  ft = { "markdown", "markdown.gh", "codecompanion" },
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    "nvim-tree/nvim-web-devicons",
  },
  keys = {
    -- ,m stays local to rendered buffers and preserves ,r for LSP rename.
    { "<localleader>m", "<cmd>RenderMarkdown toggle<cr>", desc = "Toggle Markdown render", mode = "n",
      ft = { "markdown", "markdown.gh", "codecompanion" } },
  },
  opts = {
    -- Keep <!-- ... --> notes visible in rendered documents and templates;
    -- users may re-enable concealing in their own render-markdown.nvim opts.
    html = { comment = { conceal = false } },
    -- FileType attaches before Snacks requests its first render. Keep its GitHub view settings.
    overrides = { filetype = { ["markdown.gh"] = { render_modes = true, bullet = { enabled = false } } } },
  },
}
