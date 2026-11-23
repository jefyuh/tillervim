-- Supported consumer options. Requiring this module registers nothing.
local M = {}
local DEFAULT_TEARDOWN_IGNORE = "gradle|kotlin.*[Dd]aemon|crashpad_handler|qemu-system|/emulator/|adb .*fork-server|OrbStack|com[.]docker|ibtoold|CoreSimulator|SkyComputerUseClient"
local defaults = {
  providers = { { name = "codex", label = "Codex", cli_api_key = "OPENAI_API_KEY", tui = { kind = "codex" } } },
  key_profile = "auto",
  panel = { width = 90 },
  terminal = { provider = "native" },
  native = { codex = { command = "codex", args = { "--no-alt-screen", "--yolo" }, wrap_tmux = true, teardown_ignore = DEFAULT_TEARDOWN_IGNORE },
    antigravity = { command = "agy", args = { "--settings", '{"altScreenMode":"always"}' }, wrap_tmux = true }, kimi = { command = "kimi", args = {} },
    opencode = { command = "opencode", args = {} } },
  integrations = { companion = false, review = false },
  plugin_dirs = {},
  callbacks = {},
}
local effective

---@class AgentWorkbenchOptions
---@field providers? table[] Ordered list; replaces defaults, never index-merges.
---@field key_profile? string HTTP profile for inline/cmd only.
---@field panel? {width?: integer}
---@field terminal? {provider?: "native"|"snacks"|table}
---@field native? table Native launch preferences.
---@field integrations? {companion?: boolean, review?: boolean}
---@field review? table Review policy, overridden live by vim.g.ai_review.
---@field callbacks? table Optional host editor/root/error callbacks.

---@param opts? AgentWorkbenchOptions
function M.setup(opts)
  assert(effective == nil, "agent_workbench.setup() can only run once")
  opts = vim.deepcopy(opts or {})
  for key in pairs(opts) do assert(defaults[key] ~= nil or key == "review", "Unknown agent_workbench option: " .. key) end
  local value = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)
  if opts.providers then value.providers = vim.deepcopy(opts.providers) end
  if opts.plugin_dirs then value.plugin_dirs = vim.deepcopy(opts.plugin_dirs) end
  local function fields(table_value, allowed, path)
    assert(type(table_value) == "table", path .. " must be a table")
    for key in pairs(table_value) do assert(allowed[key], path .. "." .. tostring(key) .. " is not a supported setting") end
  end
  fields(value.panel, { width = true }, "agent_workbench.panel")
  fields(value.terminal, { provider = true }, "agent_workbench.terminal")
  fields(value.integrations, { companion = true, review = true }, "agent_workbench.integrations")
  fields(value.native, defaults.native, "agent_workbench.native")
  for kind, native in pairs(value.native) do
    local path = "agent_workbench.native." .. kind
    fields(native, defaults.native[kind], path)
    local args = vim.tbl_get(opts, "native", kind, "args")
    if args ~= nil then native.args = vim.deepcopy(args) end
    assert(type(native.command) == "string" and native.command ~= "", path .. ".command must name an executable")
    assert(vim.islist(native.args), path .. ".args must be an argv list")
    for _, arg in ipairs(native.args) do assert(type(arg) == "string", path .. ".args must contain strings") end
  end
  for key, enabled in pairs(value.integrations) do
    assert(type(enabled) == "boolean", "agent_workbench.integrations." .. key .. " must be boolean")
  end
  assert(type(value.key_profile) == "string" and value.key_profile ~= "", "agent_workbench.key_profile must be a profile name")
  assert(type(value.native.codex.wrap_tmux) == "boolean", "agent_workbench.native.codex.wrap_tmux must be boolean")
  assert(type(value.native.codex.teardown_ignore) == "string", "agent_workbench.native.codex.teardown_ignore must be a string")
  assert(type(value.native.antigravity.wrap_tmux) == "boolean", "agent_workbench.native.antigravity.wrap_tmux must be boolean")
  assert(vim.islist(value.plugin_dirs), "agent_workbench.plugin_dirs must be an ordered list")
  for i, dir in ipairs(value.plugin_dirs) do assert(type(dir) == "string" and dir ~= "", "agent_workbench.plugin_dirs[" .. i .. "] must be a directory path") end
  assert(type(value.panel.width) == "number" and value.panel.width >= 1 and value.panel.width % 1 == 0,
  "agent_workbench.panel.width must be a positive integer")
  assert(type(value.terminal.provider) == "table" or value.terminal.provider == "native" or value.terminal.provider == "snacks",
  "agent_workbench.terminal.provider must be native, snacks or a provider table")
  if type(value.terminal.provider) == "table" then
    assert(value.terminal.provider.embedded ~= false, "External terminal providers are not supported in this release")
    for _, method in ipairs({ "open", "show", "hide", "send", "alive", "stop" }) do
      assert(type(value.terminal.provider[method]) == "function", "agent_workbench.terminal.provider missing " .. method)
    end
  end
  fields(value.callbacks, { project_root = true, editor_win = true, origin_tab = true, notify_error = true }, "agent_workbench.callbacks")
  for key, fn in pairs(value.callbacks) do assert(type(fn) == "function", "agent_workbench.callbacks." .. key .. " must be a function") end
  value.review = vim.tbl_deep_extend("force", vim.deepcopy(require("agent_workbench.review.defaults")), value.review or {})
  require("agent_workbench.review.settings").validate(value.review)
  effective = value
end

function M.get() return vim.deepcopy(effective or defaults) end
function M.callback(name) return (effective or defaults).callbacks[name] end

---Specs only: temporarily mutate effective options in-process and return a restore closure.
function M._patch(patch)
  local prev = vim.deepcopy(effective or defaults)
  local next_val = vim.tbl_deep_extend("force", vim.deepcopy(prev), patch or {})
  if patch and patch.plugin_dirs ~= nil then next_val.plugin_dirs = vim.deepcopy(patch.plugin_dirs) end
  effective = next_val
  return function() effective = prev end
end

return M
