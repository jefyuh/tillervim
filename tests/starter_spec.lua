local t = dofile("tests/helper.lua")
local tmp = vim.fn.tempname() .. " starter host"
local config = tmp .. "/personal config"
vim.fn.mkdir(config, "p")
tmp = assert(vim.uv.fs_realpath(tmp))
config = tmp .. "/personal config"
local copied = vim.system({ "cp", "-R", t.root .. "/starter/.", config }, { text = true }):wait()
assert(copied.code == 0, copied.stderr)

-- Exercise the actual installation template with this checkout as its local
-- dependency. Shared installed dependencies keep this consumer fully offline.
local lazy_file = config .. "/lua/config/lazy.lua"
local source = table.concat(vim.fn.readfile(lazy_file), "\n")
source = source:gsub('{ "jefyuh/tillervim", import = "tillervim.plugins" }',
  '{ "jefyuh/tillervim", dir = ' .. vim.inspect(t.root) .. ', import = "tillervim.plugins" }')
source = source:gsub('install = { colorscheme', 'install = { missing = false, colorscheme')
source = source:gsub('checker = { enabled = true', 'checker = { enabled = false')
vim.fn.writefile(vim.split(source, "\n", { plain = true }), lazy_file)
vim.fn.writefile({ 'vim.opt.tabstop = 3' }, config .. "/lua/config/options.lua")
vim.fn.writefile({
  'vim.keymap.del("n", "<leader>qq")',
  'vim.keymap.set("n", "<leader>qz", "<cmd>qa<cr>", { desc = "Quit all" })',
}, config .. "/lua/config/keymaps.lua")
local probe = tmp .. "/probe.lua"
vim.fn.writefile({
  'assert(vim.v.errmsg == "", vim.v.errmsg)',
  'local expected = ' .. vim.inspect(config),
  'assert(vim.fn.stdpath("config") ~= expected)',
  'assert(require("tillervim.util.cwd").config_root() == expected, "config root: " .. require("tillervim.util.cwd").config_root() .. " expected: " .. expected)',
  'assert(require("lazy.core.config").options.lockfile == expected .. "/lazy-lock.json")',
  'assert(vim.o.tabstop == 3)',
  'assert(vim.fn.maparg("<leader>qq", "n") == "")',
  'assert(vim.fn.maparg("<leader>qz", "n") ~= "")',
  'assert(vim.fn.exists(":AI") == 2)',
  'assert(#require("agent_workbench").sessions() == 0)',
  'assert(package.loaded["tillervim.health"] == nil)',
  'assert(package.loaded["agent_workbench.backend.codex"] == nil)',
  'io.stdout:write("STARTER_HOST_OK\\n")',
  'vim.cmd("cquit 0")',
}, probe)
local result = vim.system({ vim.v.progpath, "--headless", "-u", config .. "/init.lua", "-i", "NONE", "-n",
  "-c", "luafile " .. vim.fn.fnameescape(probe), "-c", "cquit 1" }, {
  cwd = tmp, env = { XDG_CONFIG_HOME = tmp .. "/unrelated" }, text = true,
}):wait(20000)
t.eq(result.code, 0, "shipped starter loads a separate personal repo offline\n" .. (result.stderr or ""))
t.ok((result.stdout or ""):find("STARTER_HOST_OK", 1, true), "starter preserves user paths, options and keys without starting an Agent")
vim.fn.delete(tmp, "rf")
t.done()
