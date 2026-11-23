-- Lazygit uses its own terminal input rules and floating window. Requiring
-- this module does not start a terminal or install mappings.
local M = {}

---@param file? string show this file's history instead of the repository
function M.open(file)
  local cmd = file and { "lazygit", "log", "--filter", file } or "lazygit"
  return Snacks.terminal(cmd, {
    cwd = Snacks.git.get_root(),
    interactive = true,
    win = {
      style = "float", width = 0.9, height = 0.9,
    },
  })
end

return M
