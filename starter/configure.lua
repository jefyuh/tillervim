-- Runs under nvim -l, before starting lazy.nvim or reading personal Lua.
local action, root = arg[1], arg[2]
local starter = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))
local catalog = dofile(starter .. "/profile.lua")
local profile, original = catalog.read(root)
local function has(exe) return vim.fn.executable(exe) == 1 end
local function say(line) io.stdout:write(line .. "\n") end
local function prompt(question)
  io.stdout:write(question .. " "); io.stdout:flush()
  return assert(io.read("*l"), "Input closed. Use --defaults or explicit flags for unattended setup.")
end
assert(vim.fn.has("nvim-0.12.5") == 1, "Neovim 0.12.5+ required")
local function parse(key, val)
  if key == "ai" or key == "languages" then
    if val == "none" then return {} end
    return vim.split(val, ",", { plain = true })
  end
  return val
end
local install, login = false, false
local fields = { "theme", "explorer", "completion", "languages", "ai" }
local function summary()
  for _, key in ipairs(fields) do
    local value = profile[key]
    say(key .. " = " .. (type(value) == "table" and table.concat(value, ",") or value))
  end
end
if action == "setup" then
  local i = 3
  while arg[i] do
    local flag = arg[i]
    if flag == "--install-core" then install = true
    elseif flag == "--login" then login = true
    elseif flag == "--defaults" then -- Accept existing choices or the distribution defaults.
    else
      local key = flag:match("^%-%-([a-z]+)$")
      assert(key and catalog.defaults[key] ~= nil, "Unknown option " .. flag)
      i = i + 1
      profile[key] = parse(key, assert(arg[i], "Missing value for " .. flag))
    end
    i = i + 1
  end
  if not arg[3] then
    local themes = vim.tbl_keys(catalog.themes)
    table.sort(themes)
    for _, field in ipairs({ { "theme", themes }, { "explorer", { "oil", "tree" } },
        { "completion", { "local", "off" } }, { "languages", catalog.languages }, { "ai", catalog.ai } }) do
      local key = field[1]
      local value = profile[key]
      local current = type(value) == "table" and table.concat(value, ",") or value
      say(key .. " choices: " .. table.concat(field[2], ", "))
      local answer = prompt(key .. " [" .. (current == "" and "none" or current) .. "] (Enter keeps it):")
      if answer ~= "" then profile[key] = parse(key, answer) end
    end
  end
  profile = catalog.validate(profile)
  local path = root .. "/tillervim.json"
  local lock = path .. ".lock"
  assert(vim.uv.fs_mkdir(lock, 448), "Another setup is writing " .. path .. " (lock: " .. lock .. ")")
  local tmp = lock .. "/profile"
  local ok, err = pcall(function()
    local _, current = catalog.read(root)
    assert(current == original, "Preferences changed during setup. Run setup again.")
    local lines = { "{" }
    for i, key in ipairs(fields) do
      lines[#lines + 1] = ('  "%s": %s%s'):format(key, vim.json.encode(profile[key]), i < #fields and "," or "")
    end
    lines[#lines + 1] = "}"
    assert(vim.fn.writefile(lines, tmp) == 0)
    assert(vim.uv.fs_rename(tmp, path))
  end)
  vim.uv.fs_unlink(tmp)
  vim.uv.fs_rmdir(lock)
  assert(ok, err)
  say("Saved " .. path)
else
  assert(not arg[3], "Unexpected option " .. tostring(arg[3]))
end
summary()
local function version(exe)
  if has(exe) then
    local out = vim.system({ exe, "--version" }, { text = true }):wait(5000)
    return vim.version.parse(out.stdout or "")
  end
end
local function core()
  local needed = {}
  if not has("rg") then table.insert(needed, "ripgrep") end
  local ts = version("tree-sitter")
  if not ts or not vim.version.ge(ts, "0.26.1") then table.insert(needed, "tree-sitter-cli") end
  return needed
end
local needed = core()
if #needed > 0 then
  say("Core search/parser packages needed: " .. table.concat(needed, ", "))
  if action == "setup" and vim.fn.has("macunix") == 1 and has("brew") then
    if install or (not arg[3] and prompt("Install these with Homebrew? [y/N]"):lower() == "y") then
      local result = vim.system(vim.list_extend({ "brew", "install" }, needed), { text = true }):wait()
      assert(result.code == 0, result.stderr)
      needed = core()
      assert(#needed == 0, "Check PATH or upgrade: " .. table.concat(needed, ", "))
    end
  end
end
local required = has("git") and has("cc") and #needed == 0
for _, exe in ipairs({ "git", "rg", "tree-sitter", "cc", "fd" }) do
  say(exe .. " = " .. (has(exe) and vim.fn.exepath(exe) or "missing"))
end
local sdks = { bash = "bash", c = "cc", go = "go", python = "python3", rust = "cargo", dart = "dart",
  tex = "latexmk", frontend = "node", typescript = "node", yaml = "node", json = "node" }
for _, lang in ipairs(profile.languages) do
  local exe = sdks[lang]
  if exe and not has(exe) then say(lang .. ": provide " .. exe .. " via your project or SDK manager") end
  if lang == "java" then
    local resolver = starter .. "/../lua/tillervim/util/jdk.lua"
    if not vim.uv.fs_stat(resolver) then resolver = vim.fn.stdpath("data") .. "/lazy/tillervim/lua/tillervim/util/jdk.lua" end
    if vim.uv.fs_stat(resolver) then
      local java, reason = dofile(resolver).for_jdtls()
      say(java and ("jdtls runtime = " .. java) or reason)
    else say("Java: provide JDK 25+ for jdtls. JDK 17 projects can edit with syntax highlighting.") end
  end
end
local products = { codex = "codex", ["codex-acp"] = "codex-acp" }
for _, id in ipairs(profile.ai) do
  local bridge = catalog.bridges[(id:gsub("%-acp$", ""))]
  local exe = products[id] or (bridge and bridge.command)
  if exe then say(id .. ": " .. (has(exe) and vim.fn.exepath(exe) or "CLI missing, skipped")) end
end
if (vim.tbl_contains(profile.ai, "codex") or vim.tbl_contains(profile.ai, "codex-acp")) and has("codex") then
  local status = vim.system({ "codex", "login", "status" }):wait(5000)
  say(status.code == 0 and "Codex: signed in" or "Codex: login not confirmed")
  if action == "setup" and status.code ~= 0 and (login or (not arg[3] and prompt("Open codex login? [y/N]"):lower() == "y")) then
    assert(os.execute("codex login") == 0, "Codex login did not finish. Retry with setup --login.")
    assert(vim.system({ "codex", "login", "status" }):wait(5000).code == 0, "Codex login is still pending")
    say("Codex: signed in")
  end
end
if action == "sync" or action == "doctor" then
  assert(required, "Prepare missing core dependencies and rerun " .. action)
end
