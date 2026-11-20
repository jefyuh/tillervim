-- Startup options resolve through personal Lua specs without starting a CLI or loading optional integrations.
local t = dofile("tests/helper.lua")
local tmp = vim.fn.tempname() .. " startup knobs"
vim.fn.mkdir(tmp, "p")
local output = tmp .. "/report.json"
local probe = tmp .. "/probe.lua"
vim.fn.writefile({
  "vim.wait(120, function() return false end)",
  "local s = require('agent_workbench.state')",
  "local report = { key = s.key_setting(), auto = s.key.auto, calls = _G.key_calls or 0, agents = s.agent_names(), notes = _G.notes, sessions = require('agent_workbench').sessions(), companion = package.loaded.codecompanion ~= nil, claude = package.loaded.claudecode ~= nil }",
  "vim.fn.writefile({vim.json.encode(report)}, " .. string.format("%q", output) .. ")",
  "vim.cmd('cquit 0')",
}, probe)

for _, case in ipairs({
  { name = "default configuration has no implicit HTTP profile", spec = "return {}", expected = nil, setting = "auto" },
  { name = "opts.key_profile pins an explicit profile", spec = [[
    return { { "agent-workbench.nvim", opts = function(_, opts)
      opts.key_profile = "work"
      table.insert(opts.providers, { name = "openai", label = "OpenAI", api = { adapter = "openai", api_key = "sk-literal" } })
      table.insert(opts.providers, { name = "work", label = "Work", api = { name = "work", adapter = "openai", api_key = function() _G.key_calls = (_G.key_calls or 0) + 1; return "sk-work" end } })
    end } }
  ]], expected = "work", setting = "work" },
  { name = "function api_key is not invoked during auto startup", spec = [[
    return { { "agent-workbench.nvim", opts = function(_, opts)
      table.insert(opts.providers, { name = "fn_key", label = "Keychain", api = { adapter = "openai", api_key = function() _G.key_calls = (_G.key_calls or 0) + 1; return "sk-lazy" end } })
    end } }
  ]], expected = "openai", setting = "auto" },
  { name = "invalid opts.key_profile falls back to auto with warning", spec = [[
    return { { "agent-workbench.nvim", opts = function(_, opts)
      opts.key_profile = "unknown-profile"
      table.insert(opts.providers, { name = "openai", label = "OpenAI", api = { adapter = "openai", api_key = "sk-literal" } })
    end } }
  ]], expected = "openai", setting = "auto", warning = true },
}) do
  vim.fn.delete(output)
  local host = tmp .. "/host"
  vim.fn.delete(host, "rf")
  vim.fn.mkdir(host .. "/lua/plugins", "p")
  assert(vim.system({ "cp", "-R", t.root .. "/starter/.", host }):wait().code == 0)
  local lazy = table.concat(vim.fn.readfile(host .. "/lua/config/lazy.lua"), "\n")
  lazy = lazy:gsub('"jefyuh/tillervim", import', 'dir = vim.env.TILLERVIM_TEST_ROOT, name = "tillervim", import')
  lazy = lazy:gsub('install = { colorscheme', 'install = { missing = false, colorscheme')
  vim.fn.writefile(vim.split(lazy, "\n", { plain = true }), host .. "/lua/config/lazy.lua")
  vim.fn.writefile(vim.split(case.spec, "\n", { plain = true }), host .. "/lua/plugins/init.lua")
  local pre = "_G.notes = {}; vim.notify = function(message) table.insert(_G.notes, tostring(message)) end"
  local env = vim.fn.environ()
  env.TILLERVIM_TEST_ROOT, env.NVIM = t.root, nil
  local result = vim.system({ vim.v.progpath, "--headless", "-u", host .. "/init.lua", "-i", "NONE",
    "--cmd", "lua " .. pre, "-c", "luafile " .. vim.fn.fnameescape(probe),
  }, { text = true, env = env, clear_env = true, cwd = t.root }):wait(15000)
  t.eq(result.code, 0, case.name .. ": startup succeeds " .. (result.stderr or ""))
  if vim.fn.filereadable(output) == 1 then
    local report = vim.json.decode(table.concat(vim.fn.readfile(output), "\n"))
    t.eq(report.key, case.setting, case.name .. ": profile setting")
    t.eq(report.calls, 0, case.name .. ": startup never executes api_key functions")
    t.eq(report.agents, { "codex" }, case.name .. ": native backend stays Codex only")
    t.ok(#report.sessions == 0 and not report.companion and not report.claude, case.name .. ": nothing starts")
    if case.warning then t.ok(#report.notes >= 1, case.name .. ": one actionable warning is available") end
  end
end
vim.fn.delete(tmp, "rf")
t.done()
