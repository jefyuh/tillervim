-- Exercise the pre-install command and a real personal host together.
local t = dofile("tests/helper.lua")
local root = vim.fn.tempname() .. " personal"
vim.fn.mkdir(root, "p")
local function run(argv, opts) return vim.system(argv, vim.tbl_extend("force", { text = true }, opts or {})):wait(45000) end
local function setup(...)
  local argv = { t.root .. "/starter/bin/tillervim", "--config", root, "setup" }
  return run(vim.list_extend(argv, { ... }))
end
local function write(file, data) vim.fn.writefile(vim.split(data, "\n", { plain = true }), root .. "/" .. file) end
assert(run({ "cp", "-R", t.root .. "/starter/.", root }).code == 0)
local lazy_file = root .. "/lua/config/lazy.lua"
local lazy = table.concat(vim.fn.readfile(lazy_file), "\n")
lazy = lazy:gsub('"jefyuh/tillervim", import', 'dir = vim.env.TILLERVIM_TEST_ROOT, name = "tillervim", import')
lazy = lazy:gsub('install = { colorscheme', 'install = { missing = false, colorscheme')
write("lua/config/lazy.lua", lazy)
write("lua/plugins/init.lua", [[return {
  { "agent-workbench.nvim", opts = { terminal = { provider = vim.env.TILLERVIM_TEST_TERMINAL } } },
}]])
local foreign = root .. "/other/nvim/lua/plugins"
vim.fn.mkdir(foreign, "p")
vim.fn.writefile({ 'error("loaded the unrelated default profile")' }, foreign .. "/init.lua")
local r = setup("--theme", "default", "--explorer", "tree", "--languages", "yaml", "--ai",
  "antigravity,kimi,opencode,antigravity-acp,kimi-acp,opencode-acp,copilot-acp,vibe-acp")
t.eq(r.code, 0, "setup before any personal plugins load: " .. r.stderr)
local path = root .. "/tillervim.json"
local before = vim.fn.readfile(path)
t.ok(setup("--ai", "unknown").code ~= 0, "invalid provider rejected")
t.eq(vim.fn.readfile(path), before, "invalid setup preserves prior choices")
for _, exe in ipairs({ "agy", "kimi", "opencode" }) do
  write(exe, "#!/bin/sh\nexec cat")
  vim.fn.setfperm(root .. "/" .. exe, "rwx------")
end
write("probe.lua", [[
local a = require("agent_workbench")
local plugins = require("lazy.core.config").plugins
assert(not plugins["nvim-jdtls"] and not plugins["oil.nvim"] and not plugins["solarized-osaka.nvim"])
assert(not plugins["nvim-dap-python"])
local values = require("lazy.core.plugin").values
local lsp = values(plugins["nvim-lspconfig"], "opts", false)
assert(lsp.servers.yamlls and not lsp.servers.vtsls and lsp.tools.prettier)
assert(Snacks.config.explorer.enabled)
assert(vim.fn.maparg("-", "n", false, true).desc == "Parent directory (tree)")
require("lazy").load({ plugins = { "codecompanion.nvim", "bufferline.nvim", "incline.nvim" } })
for adapter, argv in pairs({ antigravity = { "agy", "acp" }, kimi_cli = { "kimi", "acp" }, opencode = { "opencode", "acp" },
    copilot_acp = { "copilot", "--acp", "--stdio" }, mistral_vibe = { "vibe-acp" } }) do
  local resolved = require("codecompanion.adapters.acp").resolve(adapter)
  assert(vim.deep_equal(resolved.commands.default, argv), adapter .. ": " .. vim.inspect(resolved))
end
assert(#a.backends() == 8 and #a.sessions() == 0)
for _, kind in ipairs({ "antigravity", "kimi", "opencode" }) do
  local session, err = a.open(kind)
  assert(session and session.alive, vim.inspect(err))
  local cmd = vim.b[session.buf].agent_workbench.cmd
  if kind == "antigravity" and vim.fn.executable("tmux") == 1 then
    assert(vim.tbl_contains(cmd, "tmux") and vim.tbl_contains(cmd, "agy"), vim.inspect(cmd))
  else
    assert(cmd[1] == (kind == "antigravity" and "agy" or kind), vim.inspect(cmd))
  end
  assert(a.send_context(kind, { text = "draft" }))
  assert(a.hide(kind))
  assert(a.show(kind).buf == session.buf)
end
assert(#a.sessions() == 3)
for _, kind in ipairs({ "antigravity", "kimi", "opencode" }) do assert(a.stop(kind)) end
assert(#a.sessions() == 0)
assert(vim.v.errmsg == "", vim.v.errmsg)
]])
for _, provider in ipairs({ "native", "snacks" }) do
  local result = run({ vim.v.progpath, "--headless", "-i", "NONE", "-u", root .. "/init.lua", "-c",
    "lua local ok, err = pcall(dofile, vim.g.tillervim_config_root .. '/probe.lua'); if not ok then print(err); vim.cmd('cquit 1') end", "+qa!" },
    { env = { TILLERVIM_TEST_ROOT = t.root, XDG_CONFIG_HOME = root .. "/other", TILLERVIM_TEST_TERMINAL = provider, PATH = root .. ":" .. vim.env.PATH } })
  t.eq(result.code, 0, provider .. " selected modules, ACP commands and independent PTYs: " .. result.stderr)
end
t.eq(setup("--languages", "none", "--ai", "none", "--completion", "off").code, 0, "empty profile saved")
local minimal = run({ vim.v.progpath, "--headless", "-i", "NONE", "-u", root .. "/init.lua", "-c",
  [[lua local p = require("lazy.core.config").plugins; if p["minuet-ai.nvim"] or p["codecompanion.nvim"] or p["nvim-jdtls"] or #require("agent_workbench").backends() > 0 or vim.v.errmsg ~= "" then vim.cmd("cquit 1") end]], "+qa!" },
  { env = { TILLERVIM_TEST_ROOT = t.root, XDG_CONFIG_HOME = root .. "/other", TILLERVIM_TEST_TERMINAL = "native" } })
t.eq(minimal.code, 0, "empty selections remain empty in an alternate personal host: " .. minimal.stderr)
-- The official login flow is represented by an offline executable. No provider
-- ever receives a prompt or an HTTP request during this spec.
write("codex", [=[#!/bin/sh
base=$(dirname "$0")
echo "$*" >> "$base/login-calls"
case "$*" in
  "login status") test -f "$base/signed-in" ;;
  "login") touch "$base/signed-in" ;;
  *) exit 3 ;;
esac]=])
vim.fn.setfperm(root .. "/codex", "rwx------")
local login = run({ t.root .. "/starter/bin/tillervim", "--config", root, "setup", "--ai", "codex", "--login" },
  { env = { PATH = root .. ":" .. vim.env.PATH } })
t.eq(login.code, 0, "opt-in CLI login completes")
t.eq(vim.fn.readfile(root .. "/login-calls"), { "login status", "login", "login status" }, "check, login and verify")
t.ok(setup("--ai", "openai").code ~= 0, "HTTP providers are configured in personal Lua opts, not profile presets")
vim.fn.delete(root, "rf")
t.done()
