return {
  "folke/snacks.nvim",
  optional = true,
  opts = function(_, opts)
    local dashboard = vim.deepcopy(require("tillervim.config.dashboard"))
    if require("tillervim.profile").selected.explorer == "tree" then
      for _, key in ipairs(dashboard.keys) do
        if key.action == ":Oil" then key.action = function() Snacks.explorer() end end
      end
    end
    opts.dashboard = require("editor_core.dashboard").build(dashboard, function()
      return require("tillervim.util.github").dashboard_sections()
    end)
  end,
}
