local t = dofile("tests/helper.lua")
local tmp = vim.fn.tempname() .. " managed install"
vim.fn.mkdir(tmp, "p")
tmp = assert(vim.uv.fs_realpath(tmp))
local managed, user = tmp .. "/plugins", tmp .. "/personal"
local distro = managed .. "/tillervim"
vim.fn.mkdir(managed, "p")
assert(vim.system({ "cp", "-R", t.root, distro }, { text = true }):wait().code == 0)
-- Simulate a real lazy.nvim clone on a branch even when the outer checkout is a
-- detached PR head (GitHub Actions) or a linked worktree (.git file).
vim.fn.delete(distro .. "/.git", "rf")
assert(vim.system({ "git", "-C", distro, "init", "-q" }, { text = true }):wait().code == 0)
assert(vim.system({ "git", "-C", distro, "symbolic-ref", "HEAD", "refs/heads/main" }, { text = true }):wait().code == 0)
assert(vim.system({
  "git", "-C", distro, "-c", "user.name=Spec", "-c", "user.email=spec@example.invalid",
  "commit", "-q", "--allow-empty", "-m", "fixture",
}, { text = true }):wait().code == 0)
assert(vim.system({ "cp", "-R", t.root .. "/starter", user }, { text = true }):wait().code == 0)

-- Reuse external dependencies offline, while putting the distribution and its
-- bundled directories under lazy.nvim's actual managed root. This is the path
-- arrangement a checkout-local host cannot exercise.
local bundled = { ["tillervim"] = true }
local names = { "editor-core.nvim", "agent-workbench.nvim", "git-review.nvim", "llama-service.nvim" }
for _, name in ipairs(names) do bundled[name] = true end
local external = {}
for name, plugin in pairs(require("lazy.core.config").plugins) do
  if not bundled[name] then external[#external + 1] = { name, dir = plugin.dir } end
end
vim.fn.writefile(vim.split("return " .. vim.inspect(external), "\n", { plain = true }), user .. "/lua/plugins/init.lua")
local lazy_file = user .. "/lua/config/lazy.lua"
local source = table.concat(vim.fn.readfile(lazy_file), "\n")
source = source:gsub('require%("lazy"%).setup%({', 'require("lazy").setup({\n  root = ' .. vim.inspect(managed) .. ',')
source = source:gsub('import = "tillervim.plugins"', 'dir = ' .. vim.inspect(distro) .. ', import = "tillervim.plugins"')
source = source:gsub('install = { colorscheme', 'install = { missing = false, colorscheme')
source = source:gsub('checker = { enabled = true', 'checker = { enabled = false')
vim.fn.writefile(vim.split(source, "\n", { plain = true }), lazy_file)
local probe = tmp .. "/probe.lua"
vim.fn.writefile({
  'assert(vim.v.errmsg == "", vim.v.errmsg)',
  'local distro = ' .. vim.inspect(distro),
  'assert(require("tillervim").root() == distro)',
  'vim.cmd("Lazy! install")',
  'assert(vim.v.errmsg == "", vim.v.errmsg)',
  'local names = ' .. vim.inspect(names),
  'for _, name in ipairs(names) do',
  '  local plugin = require("lazy.core.config").plugins[name]',
  '  assert(plugin.virtual == true, name .. " must be owned by its distribution")',
  '  assert(plugin.dir == distro .. "/local-plugin/" .. name)',
  '  assert(vim.fn.filereadable(plugin.dir .. "/README.md") == 1, name .. " was removed by install")',
  '  assert(vim.fn.filereadable(plugin.dir .. ".cloning") == 0, name .. " was cloned separately")',
  'end',
  'assert(vim.fn.exists(":AI") == 2)',
  'assert(#require("agent_workbench").sessions() == 0)',
  'assert(package.loaded["llama_service"] == nil)',
  'io.stdout:write("MANAGED_INSTALL_OK\\n")',
  'vim.cmd("cquit 0")',
}, probe)
local result = vim.system({ vim.v.progpath, "--headless", "-u", user .. "/init.lua", "-i", "NONE", "-n",
  "-c", "luafile " .. vim.fn.fnameescape(probe), "-c", "cquit 1" }, { cwd = tmp, text = true }):wait(20000)
t.eq(result.code, 0, "install keeps bundled packages inside a managed distribution\n" .. (result.stderr or ""))
t.ok((result.stdout or ""):find("MANAGED_INSTALL_OK", 1, true), "all bundled runtimes survive the real installer")
vim.fn.delete(tmp, "rf")
t.done()
