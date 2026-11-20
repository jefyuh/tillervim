-- Validated AI backends and the live HTTP key profile.
-- Options come from agent_workbench.setup; this module resolves live state.
-- Consumers share this table, so :AI key updates state in place.
local settings = require("agent_workbench.options").get()

-- The native terminal agents this config implements: local-plugin/agent-workbench.nvim/lua/agent_workbench/backend/<kind>.lua,
-- the tmux wrappers, the prompt hooks and the transcript readers. A provider's
-- `tui.kind` names one of these; a new kind needs that code, not just an entry.
local TUI_KINDS = {
  codex = {
    command = settings.native.codex.command,
    prompt_pattern = "/editor/[^/]*%.md$", -- $CODEX_HOME/editor/*.md
    capabilities = { tree_add = false },
  },
}

for _, kind in ipairs({ "antigravity", "kimi", "opencode" }) do
  TUI_KINDS[kind] = { command = settings.native[kind].command, capabilities = {} }
end

-- CodeCompanion's built-in HTTP adapters, neutralized by default in
-- lua/tillervim/plugins/ai/codecompanion.lua unless explicitly configured in
-- providers: a chat restored from history, or any upstream path naming the
-- plain adapter, must never silently read a CLI's own billing variable.
local BUILTIN_HTTP_ADAPTERS = { "anthropic", "openai" }

-- CodeCompanion's built-in ACP adapters that must never fall back to API-key
-- auth, whichever providers are listed: codex-acp's own default (`api-key`)
-- bills OPENAI_API_KEY instead of the ChatGPT login, and a chat restored from
-- history, or a typed :CodeCompanionChat naming it, uses the adapter even
-- when no provider offers it. A provider's `acp.auth_method` overrides this.
local BUILTIN_ACP_AUTH = {
  codex = "chat-gpt",
}

-- Variables a CLI reads in place of its subscription login.
local CLI_KEYS = { ANTHROPIC_API_KEY = true, OPENAI_API_KEY = true, CLAUDE_CODE_OAUTH_TOKEN = true }

local M = {
  codecompanion = {},
  key = { auto = true },
  panel = vim.deepcopy(settings.panel),
  builtin_http_adapters = BUILTIN_HTTP_ADAPTERS,
  builtin_acp_auth = BUILTIN_ACP_AUTH,
}

---@class ai.KeySpec
---@field source "env"|"value"|"function"
---@field var? string
---@field display string redacted label safe for UI/health/notifications
---@field configured fun(): boolean cheap check without executing user functions
---@field resolve fun(): string|nil, string|nil

---Parse and validate an HTTP profile's `api_key`: `"$VAR"` (or `"${VAR}"`), a
---literal secret string, or `function() -> string|nil`. Refuses CLI billing
---variables at load time so startup stops before any request can run.
---@param name string
---@param raw any
---@return ai.KeySpec
function M.parse_api_key(name, raw)
  if type(raw) == "function" then
    return {
      source = "function",
      display = "function",
      configured = function() return true end,
      resolve = function()
        local ok, value = pcall(raw)
        if not ok then return nil, ("api_key function for %s failed: %s"):format(name, tostring(value)) end
        if type(value) ~= "string" or value == "" then
          return nil, ("api_key function for %s returned no key"):format(name)
        end
        return value
      end,
    }
  end
  if type(raw) ~= "string" or vim.trim(raw) == "" then
    error(("AI key profile %q: api_key must be $VAR, a non-empty string, or a function"):format(name), 0)
  end
  if raw:sub(1, 1) == "$" then
    local var = raw:match("^%$%{([%a_][%w_]*)%}$") or raw:match("^%$([%a_][%w_]*)$")
    if not var then
      error(("AI key profile %q: invalid environment variable %q (expected $VAR or ${VAR})"):format(name, raw), 0)
    end
    if CLI_KEYS[var] then
      error(("AI key profile %q cannot read CLI billing variable $%s"):format(name, var), 0)
    end
    local display = "$" .. var
    return {
      source = "env",
      var = var,
      display = display,
      configured = function() return (vim.env[var] or "") ~= "" end,
      resolve = function()
        local value = vim.env[var]
        if value == nil or value == "" then return nil, display .. " is not set" end
        return value
      end,
    }
  end
  if CLI_KEYS[raw] then
    error(("AI key profile %q cannot read CLI billing variable %s"):format(name, raw), 0)
  end
  return {
    source = "value",
    display = "literal",
    configured = function() return true end,
    resolve = function() return raw end,
  }
end

---A native terminal agent as the rest of the config reads it.
---@class ai.Agent
---@field name string the TUI kind: "codex"
---@field provider string the provider that offers it
---@field label string
---@field command string
---@field prompt_pattern string
---@field capabilities table<string, boolean>
---@field cli_api_key? string

---An HTTP key profile.
---@class ai.KeyProfile
---@field name string the profile and its CodeCompanion adapter name
---@field provider string
---@field adapter string the built-in HTTP adapter it extends
---@field label string
---@field api_key string an NVIM_* variable
---@field model? string

---Check `list` and derive what the rest of the config reads from it. Pure:
---nothing is assigned, so a spec can feed it any list. Raises (level 0, the
---provider named) on anything that would otherwise surface as a broken key.
---@param list table[]
---@return { providers: table[], agents: table<string, ai.Agent>, agent_names: string[], key_profiles: table<string, ai.KeyProfile>, key_names: string[], acp: table[] }
function M.build(list)
  local function fail(fmt, ...) error(("AI providers: " .. fmt):format(...), 0) end
  local function fields(value, allowed, path)
    for key in pairs(value) do
      if not allowed[key] then fail("%s.%s is not a supported setting", path, tostring(key)) end
    end
  end
  local function optional_string(value, path)
    if value ~= nil and (type(value) ~= "string" or value == "") then fail("%s must be a non-empty string", path) end
  end
  if type(list) ~= "table" or not vim.islist(list) then fail("expected a list") end
  local out = { providers = list, agents = {}, agent_names = {}, key_profiles = {}, key_names = {}, acp = {} }
  local names, adapters = {}, {}
  for i, p in ipairs(list) do
    if type(p) ~= "table" or type(p.name) ~= "string" or p.name == "" then fail("entry %d has no name", i) end
    local who = ("%q"):format(p.name)
    fields(p, { name = true, label = true, cli_api_key = true, tui = true, acp = true, api = true }, who)
    if names[p.name] then fail("%s is listed twice", who) end
    names[p.name] = true
    if type(p.label) ~= "string" then fail("%s has no label", who) end
    if not (p.tui or p.acp or p.api) then fail("%s offers none of tui, acp, api", who) end
    if p.cli_api_key ~= nil and type(p.cli_api_key) ~= "string" then fail("%s: cli_api_key must be a string", who) end

    if p.tui then
      local kind = type(p.tui) == "table" and p.tui.kind
      local impl = TUI_KINDS[kind]
      if not impl then
        fail("%s: tui.kind must be one of %s, not %s", who, table.concat(vim.tbl_keys(TUI_KINDS), ", "), vim.inspect(kind))
      end
      fields(p.tui, { kind = true }, who .. ".tui")
      -- One session per agent per Nvim (#7): two providers on one kind would
      -- be two entries for the same terminal.
      if out.agents[kind] then fail("%s: tui kind %q is already offered by %q", who, kind, out.agents[kind].provider) end
      out.agents[kind] = {
        name = kind, provider = p.name, label = p.label, command = impl.command,
        prompt_pattern = impl.prompt_pattern, capabilities = impl.capabilities, cli_api_key = p.cli_api_key,
      }
      out.agent_names[#out.agent_names + 1] = kind
    end

    if p.acp then
      local a = p.acp
      if type(a) ~= "table" or type(a.adapter) ~= "string" or type(a.command) ~= "string" then
        fail("%s: acp needs an adapter and a command", who)
      end
      fields(a, { adapter = true, command = true, auth_method = true }, who .. ".acp")
      optional_string(a.adapter, who .. ".acp.adapter")
      optional_string(a.command, who .. ".acp.command")
      optional_string(a.auth_method, who .. ".acp.auth_method")
      if adapters[a.adapter] then fail("%s: adapter %q is used twice", who, a.adapter) end
      adapters[a.adapter] = true
      out.acp[#out.acp + 1] = {
        provider = p.name, label = p.label, adapter = a.adapter, command = a.command,
        auth_method = a.auth_method, cli_api_key = p.cli_api_key,
      }
    end

    if p.api then
      local a = p.api
      if type(a) ~= "table" or type(a.adapter) ~= "string" then fail("%s: api needs an adapter", who) end
      fields(a, { adapter = true, api_key = true, name = true, label = true, model = true }, who .. ".api")
      for _, key in ipairs({ "adapter", "name", "label", "model" }) do optional_string(a[key], who .. ".api." .. key) end
      local id = a.name or a.adapter
      if adapters[id] then fail("%s: api name %q is used twice; give api.name", who, id) end
      adapters[id] = true
      local key_spec = M.parse_api_key(id, a.api_key)
      local profile = {
        name = id, provider = p.name, adapter = a.adapter, label = a.label or p.label,
        api_key = key_spec.display, key_spec = key_spec, model = a.model,
      }
      out.key_profiles[id] = profile
      out.key_names[#out.key_names + 1] = id
    end
  end
  return out
end

local built
---Make `list` the providers: every derived table is replaced in place on M.
---@param list table[]
local function apply(list)
  built = M.build(list)
  ---@type table[] the providers, in order
  M.providers = built.providers
  ---@type table<string, ai.Agent> the native terminal agents offered, by kind
  M.agents = built.agents
  ---@type table<string, ai.KeyProfile>
  M.key_profiles = built.key_profiles
  ---@type table[] the ACP chats offered, in order
  M.acp = built.acp
  -- The first `acp` in provider order, nil when no provider offers one.
  M.codecompanion.acp_adapter = built.acp[1] and built.acp[1].adapter or nil
  -- The chat adapter for CodeCompanion's own paths that name none (a typed
  -- :CodeCompanionChat, the action palette): the first `acp`, else the first
  -- `api`, else CodeCompanion's own default. Every chat <leader>an starts
  -- names its adapter itself.
  M.codecompanion.chat_adapter = M.codecompanion.acp_adapter or built.key_names[1]
end
apply(vim.deepcopy(settings.providers))

---@return string[] the native agents offered, in provider order
function M.agent_names() return vim.deepcopy(built.agent_names) end
---@return string[] every key profile, in provider order
function M.key_names() return vim.deepcopy(built.key_names) end

local function is_set(var) return (vim.env[var] or "") ~= "" end

---The profile `auto` stands for now: the first whose key is configured, else
---the first; nil when no provider offers `api`.
---@return string|nil
function M.auto_key()
  for _, name in ipairs(built.key_names) do
    if M.key_profiles[name].key_spec.configured() then return name end
  end
  return built.key_names[1]
end

---Select the HTTP key profile. `auto` resolves now (M.auto_key); any other
---name pins it. Validates before it mutates anything.
---@param name string
function M.use_key(name)
  name = (name or ""):lower()
  local auto = name == "auto"
  local id = auto and M.auto_key() or name
  local profile = id and M.key_profiles[id]
  if not profile then
    if auto then
      -- No provider offers `api`: inline edits and command prompts refuse
      -- (ai.companion), and nothing else reads the key.
      M.key.name, M.key.label, M.key.auto = nil, "none", true
      M.codecompanion.http_adapter, M.codecompanion.api_key, M.codecompanion.key_spec, M.codecompanion.model = nil, nil, nil, nil
      return
    end
    local names = M.key_names()
    table.insert(names, 1, "auto")
    error(("Unknown AI key profile %q; expected %s"):format(name, table.concat(names, ", ")), 0)
  end
  M.key.name, M.key.label, M.key.auto = id, profile.label, auto
  -- The adapter *name*: a profile's name is its CodeCompanion adapter.
  M.codecompanion.http_adapter = id
  M.codecompanion.api_key = profile.api_key
  M.codecompanion.key_spec = profile.key_spec
  M.codecompanion.model = profile.model
end

---The inline/cmd adapter as CodeCompanion takes it: a bare name, or name plus
---model when the profile pins one.
---@return string|{ name: string, model: string }|nil
function M.http_adapter_spec()
  local c = M.codecompanion
  return c.model and { name = c.http_adapter, model = c.model } or c.http_adapter
end

---The key profile setting as a user spells it: "auto" or a profile name.
---@return string
function M.key_setting()
  return M.key.auto and "auto" or M.key.name
end

---A way to start a chat, as the new-chat picker (local-plugin/agent-workbench.nvim/lua/agent_workbench/slot.lua) offers it.
---@class ai.Backend
---@field id string "codex", "acp:<adapter>" or "api:<profile>"
---@field kind "native"|"acp"|"http"
---@field provider string the provider it belongs to
---@field agent? string native: the TUI kind
---@field adapter? string acp, http: the CodeCompanion adapter
---@field command? string native, acp: the executable it needs
---@field profile? string http: the key profile
---@field api_key? string http: the profile's NVIM_* variable
---@field model? string http: the profile's pinned model
---@field label string what it is, where it runs and who bills it
---@field available boolean whether it can start here
---@field why? string why it cannot
---@field warn? string a CLI billing variable that is set, so "subscription" may not hold

---Every way to start a chat, available or not: the terminals, then the ACP
---chats, then the API chats, each in provider order. Answering reads PATH and
---the environment only; it loads no plugin.
---@return ai.Backend[]
function M.backends()
  local function warn_of(var) return var and is_set(var) and (var .. " is set — it may bill the API") or nil end
  local all = {}
  for _, kind in ipairs(built.agent_names) do
    local a = M.agents[kind]
    local ok = vim.fn.executable(a.command) == 1
    all[#all + 1] = {
      id = kind, kind = "native", provider = a.provider, agent = kind, command = a.command,
      label = a.label .. (kind == "codex" and " · terminal · subscription" or " · terminal · CLI account"),
      available = ok, why = not ok and (a.command .. " not found") or nil, warn = warn_of(a.cli_api_key),
    }
  end
  for _, a in ipairs(M.acp) do
    local ok = vim.fn.executable(a.command) == 1
    all[#all + 1] = {
      id = "acp:" .. a.adapter, kind = "acp", provider = a.provider, adapter = a.adapter, command = a.command,
      label = a.label .. (a.adapter == "codex" and " · CodeCompanion ACP · subscription" or " · CodeCompanion ACP · CLI account"),
      available = ok, why = not ok and (a.command .. " not found") or nil, warn = warn_of(a.cli_api_key),
    }
  end
  for _, name in ipairs(built.key_names) do
    local kp = M.key_profiles[name]
    local ok = kp.key_spec.configured()
    all[#all + 1] = {
      id = "api:" .. name, kind = "http", provider = kp.provider, adapter = name, profile = name,
      api_key = kp.api_key, key_spec = kp.key_spec, model = kp.model,
      label = kp.label .. " · CodeCompanion API · API credits",
      available = ok, why = not ok and (kp.api_key .. " is not set") or nil,
    }
  end
  return all
end

---Specs only: resolve another provider list in-process, as if setup supplied
---it. `auto` is resolved again, and a pinned key that
---the new list lacks falls back to it. What a plugin read at its load (the
---CodeCompanion adapters) keeps what it read.
---@param list table[]
function M._set_providers(list)
  apply(list)
  if M.key.auto or not M.key_profiles[M.key.name or ""] then M.use_key("auto") end
end

M.use_key("auto")
local key_default = settings.key_profile
-- A typo in this optional knob falls back to auto instead of aborting startup.
if key_default and key_default ~= "" and not pcall(M.use_key, key_default) then
  vim.schedule(function()
    vim.notify(("AI key profile %q is invalid; using auto (see :checkhealth agent_workbench)"):format(key_default), vim.log.levels.WARN)
  end)
end

---Which native agent a terminal command runs, if any: every one offered,
---since several can run at once and each panel keeps its own input rules,
---edgy slot and statusline label.
---@param cmd string|string[]|nil
---@return string|nil agent the TUI kind
function M.agent_of_command(cmd)
  if type(cmd) == "table" then
    for _, part in ipairs(cmd) do
      local agent = M.agent_of_command(tostring(part))
      if agent then return agent end
    end
    return nil
  end
  if type(cmd) ~= "string" then return nil end
  for token in cmd:gmatch("[^%s]+") do
    local base = vim.fs.basename((token:gsub("^[\"']+", ""):gsub("[\"';]+$", "")))
    for _, kind in ipairs(built.agent_names) do
      if base == vim.fs.basename(M.agents[kind].command) then return kind end
    end
  end
  return nil
end

function M.is_native_command(cmd)
  return M.agent_of_command(cmd) ~= nil
end

---Which agent handed over a prompt file, from the temp path its CLI chose;
---nil for a path no offered CLI uses (an agent's pane running `git commit`,
---say). Such a prompt has no owner: it takes no seed and attaches no image,
---since either would go to an agent guessed at.
---@param path string
---@return string|nil agent the TUI kind
function M.agent_of_prompt(path)
  for _, kind in ipairs(built.agent_names) do
    if type(path) == "string" and M.agents[kind].prompt_pattern and path:find(M.agents[kind].prompt_pattern) then return kind end
  end
  return nil
end

return M
