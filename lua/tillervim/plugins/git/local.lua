local root = require("tillervim").root()
return {
  virtual = true, dir = root .. "/local-plugin/git-review.nvim", name = "git-review.nvim", main = "git_review",
  opts = function()
    local opts = require("tillervim.util.settings").git()
    opts.resolve = require("tillervim.util.settings").git_overrides
    opts.labels = function(method, value, callback)
      return require("agent_workbench.review.labels")[method](value, callback)
    end
    opts.review_vars = function(entry) return require("agent_workbench.review.rounds").review_vars(entry) end
    opts.close_aux = function(tab) return require("editor_core.diffsplit").close(tab) end
    return opts
  end,
}
