return {
  "folke/snacks.nvim",
  optional = true,
  opts = function(_, opts)
    opts.dashboard = require("editor_core.dashboard").build(require("tillervim.config.dashboard"), function()
      return require("tillervim.util.github").dashboard_sections()
    end)
  end,
}
