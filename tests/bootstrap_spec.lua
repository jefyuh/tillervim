local t = dofile("tests/helper.lua")
local root = t.root

-- The loader starts before host helpers and plugin specs, rather than waiting
-- for lazy.nvim to enable it after the initial bootstrap modules have loaded.
t.eq(vim.loader.enabled, true, "vim.loader is enabled")
local first_statement
for line in io.lines(root .. "/lua/tillervim/bootstrap/setup.lua") do
  if not line:match("^%s*%-%-") and line:match("%S") then first_statement = line break end
end
t.eq(first_statement, "vim.loader.enable()", "setup enables the loader before other initialization")

-- Data files may construct tables, but cannot import runtime modules, change
-- globals or call editor APIs. Returned data contains no deferred callbacks.
local environment = setmetatable({
  ipairs = ipairs,
  type = type,
  vim = { tbl_extend = vim.tbl_extend, list_extend = vim.list_extend },
}, {
  __index = function(_, key) error("config read unexpected global: " .. tostring(key)) end,
  __newindex = function(_, key) error("config wrote global: " .. tostring(key)) end,
})
local function is_data(value)
  if type(value) == "table" then
    for key, item in pairs(value) do
      if not is_data(key) or not is_data(item) then return false end
    end
    return true
  end
  return type(value) == "string" or type(value) == "number" or type(value) == "boolean"
end
for _, path in ipairs(vim.fn.glob(root .. "/lua/tillervim/config/*.lua", false, true)) do
  local chunk = assert(loadfile(path))
  local ok, data = pcall(setfenv(chunk, environment))
  local name = vim.fs.basename(path)
  t.ok(ok, name .. " evaluates without runtime access" .. (ok and "" or ": " .. tostring(data)))
  t.ok(ok and type(data) == "table" and is_data(data), name .. " returns only data")
end
t.eq(package.loaded["tillervim.health"], nil, "health aggregation stays unloaded at startup")
t.eq(package.loaded["tillervim.util.debug"], nil, "debug tools stay unloaded until first use")
t.eq(package.loaded["tillervim.util.github"], nil, "GitHub dashboard content stays unloaded until render")
t.ok(vim.tbl_contains(vim.fn.getcompletion("checkhealth tillervim", "cmdline"), "tillervim"),
  "native checkhealth discovers the bootstrap provider")

-- -u must find this checkout from another cwd, without relying on the user's
-- stdpath(config). Keep the shared data path so the probe never installs tools.
local temp = vim.fn.tempname() .. " bootstrap spec"
vim.fn.mkdir(temp .. "/config", "p")
local probe = temp .. "/probe.lua"
vim.fn.writefile({
  'assert(package.loaded["tillervim.bootstrap.setup"] and package.loaded["lazy"])',
  'assert(require("lazy.core.config").options.lockfile == ' .. vim.inspect(root .. "/lazy-lock.json") .. ')',
  'assert(package.loaded["tillervim.health"] == nil)',
  'assert(package.loaded["tillervim.util.debug"] == nil)',
  'local expected = ' .. vim.inspect(root),
  'assert(vim.fn.stdpath("config") ~= expected)',
  'assert(require("tillervim.util.cwd").config_root() == expected)',
  'local picker_root, dashboard_root',
  'Snacks.picker.files = function(opts) picker_root = opts.cwd end',
  'vim.fn.maparg("<leader>mf", "n", false, true).callback()',
  'assert(picker_root == expected, "config picker used another checkout")',
  'Snacks.dashboard.pick = function(_, opts) dashboard_root = opts.cwd end',
  'for _, item in ipairs(require("tillervim.config.dashboard").keys) do',
  '  if item.key == "c" then vim.cmd(item.action); break end',
  'end',
  'assert(dashboard_root == expected, "dashboard used another checkout")',
  'io.stdout:write("config navigation: ok\\n")',
  'assert(vim.v.errmsg == "", vim.v.errmsg)',
  'io.stdout:write("isolated bootstrap: ok\\n")',
  'vim.cmd("cquit 0")',
}, probe)
local child = vim.system({
  vim.v.progpath, "--headless", "-u", root .. "/init.lua", "-i", "NONE", "-n",
  "-c", "luafile " .. vim.fn.fnameescape(probe),
  "-c", "cquit 1",
}, { cwd = temp, env = { XDG_CONFIG_HOME = temp .. "/config" }, text = true }):wait(20000)
t.eq(child.code, 0, "an isolated checkout starts cleanly: " .. (child.stderr or ""))
t.ok((child.stdout or ""):find("isolated bootstrap: ok", 1, true) ~= nil,
  "the isolated checkout uses its own bootstrap and lockfile")
t.ok((child.stdout or ""):find("config navigation: ok", 1, true) ~= nil,
  "both configuration pickers use the active checkout, independent of cwd/stdpath")
vim.fn.delete(temp, "rf")
t.done()
