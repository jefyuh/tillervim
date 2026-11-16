return {
  "folke/snacks.nvim",
  optional = true,
  keys = {
    { "<leader>gg", function() require("tillervim.util.lazygit").open() end, desc = "Lazygit", mode = { "n" } },
    { "<leader>gf", function() require("tillervim.util.lazygit").open(vim.api.nvim_buf_get_name(0)) end, desc = "File history (Lazygit)", mode = { "n" } },
  },
}
