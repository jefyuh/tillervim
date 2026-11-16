local M = {}
local configured = false
function M.setup(opts)
  assert(not configured, "editor_core.setup() can only run once")
  opts = vim.deepcopy(opts or {})
  for group, allowed in pairs({
    behaviors = { input_method = true, restore_cursor = true, highlight_yank = true, autoread = true },
    formatting = { autoformat = true },
  }) do
    assert(opts[group] == nil or type(opts[group]) == "table", "editor_core." .. group .. " must be a table")
    for key, value in pairs(opts[group] or {}) do
      assert(allowed[key], "editor_core." .. group .. "." .. tostring(key) .. " is not a supported setting")
      assert(type(value) == "boolean", "editor_core." .. group .. "." .. key .. " must be boolean")
    end
  end
  configured = true
  require("editor_core.url").setup(opts.url)
  require("editor_core.options").setup(opts.options or {}, opts.theme or {}, opts.formatting or {})
  if opts.keymaps ~= false then
    assert(opts.keymaps == nil or opts.keymaps == true, "editor_core.keymaps must be boolean")
    require("editor_core.keymaps").setup()
    require("editor_core.keyguide").setup()
  end
  require("editor_core.autocmds").setup(opts.behaviors or {})
end
return M
