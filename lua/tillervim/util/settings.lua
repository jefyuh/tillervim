-- Host migration policy only. Independent plugins receive resolved values/callbacks.
local M = {}
function M.git_overrides()
  local value = {}
  local legacy = vim.g.ai_review
  if type(legacy) ~= "table" then return value end
  local limit = legacy.history_limit
  if limit == false or type(limit) == "number" and limit >= 1 and limit % 1 == 0 then value.history_limit = limit end
  local size = legacy.max_file_size
  if type(size) == "number" and size >= 1 and size % 1 == 0 then value.max_file_size = size end
  local saved = type(legacy.retention) == "table" and legacy.retention.saved
  if type(saved) == "number" and saved >= 1 and saved % 1 == 0 then value.retention = { saved = saved } end
  return value
end
function M.git()
  return vim.tbl_deep_extend("force", vim.deepcopy(require("tillervim.config.git")), M.git_overrides())
end
return M
