local M = {}
local configured = false
function M.setup(opts)
  assert(not configured, "editor_core.setup() can only run once")
  opts = vim.deepcopy(opts or {})
  for key in pairs(opts) do
    assert(({
      options = true, theme = true, formatting = true, behaviors = true,
      input_method = true, log_level = true, keymaps = true, url = true,
    })[key], "Unknown editor_core option: " .. tostring(key))
  end
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
  if opts.input_method ~= nil then
    assert(type(opts.input_method) == "table", "editor_core.input_method must be a table")
    for key in pairs(opts.input_method) do
      assert(({ source = true, wait_time_ms = true })[key], "editor_core.input_method." .. tostring(key) .. " is not a supported setting")
    end
    if opts.input_method.source ~= nil then
      assert(type(opts.input_method.source) == "string" and vim.trim(opts.input_method.source) ~= "",
        "editor_core.input_method.source must be a non-empty string")
    end
    if opts.input_method.wait_time_ms ~= nil then
      local wait = opts.input_method.wait_time_ms
      assert(type(wait) == "number" and wait >= 0 and wait % 1 == 0,
        "editor_core.input_method.wait_time_ms must be a non-negative integer")
    end
  end
  local logger = require("editor_core.logger")
  if opts.log_level ~= nil then
    assert(type(opts.log_level) == "string" and logger.LEVELS[opts.log_level] ~= nil,
      "editor_core.log_level must be DEBUG, INFO, WARN or ERROR")
    logger.set_level(opts.log_level)
  end
  require("editor_core.input_method").configure(opts.input_method)
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
