local root = require("tillervim").root()
return {
  {
    virtual = true, dir = root .. "/local-plugin/editor-core.nvim", name = "editor-core.nvim", main = "editor_core",
    lazy = false, priority = 10000,
    opts = function()
      return {
        options = require("tillervim.config.options"), theme = require("tillervim.config.theme"), formatting = require("tillervim.config.formatting"),
        behaviors = require("tillervim.config.behaviors"),
        url = { buffer_dir = require("tillervim.util.cwd").buffer_dir },
      }
    end,
    config = function(_, opts)
      require("editor_core").setup(opts)
      require("tillervim").load_user("options")
    end,
  },
}
