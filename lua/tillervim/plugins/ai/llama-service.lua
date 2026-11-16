local root = require("tillervim").root()
return {
  opts = function() return require("tillervim.config.completion").server end,
  virtual = true, dir = root .. "/local-plugin/llama-service.nvim", name = "llama-service.nvim", main = "llama_service",
}
