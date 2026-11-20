-- CodeCompanion's HTTP adapters resolve configured api_key sources ($VAR, literal,
-- function), never the variables the agent CLIs bill against: exporting
-- ANTHROPIC_API_KEY or OPENAI_API_KEY for a CLI never leaks into CodeCompanion.
local t = dofile("tests/helper.lua")

local function resolve(env)
  local probe = [[
    local ai = require("agent_workbench.state")
    local list = vim.deepcopy(ai.providers)
    list[#list + 1] = { name = "env_prof", label = "Env OpenAI",
      api = { name = "openai", adapter = "openai", api_key = "$SPEC_ENV_OPENAI_KEY" } }
    list[#list + 1] = { name = "lit_prof", label = "Literal Work",
      api = { name = "spec_literal", adapter = "anthropic", api_key = "literal-secret-key" } }
    list[#list + 1] = { name = "fn_prof", label = "Fn Work",
      api = { name = "spec_fn", adapter = "anthropic", api_key = function() return vim.env.SPEC_FN_BACKING end } }
    ai._set_providers(list)
    require("lazy").load({ plugins = { "codecompanion.nvim" } })
    local adapters = require("codecompanion.adapters")
    local utils = require("codecompanion.adapters.utils")
    local out = {}
    for _, name in ipairs({ "anthropic", "openai", "spec_literal", "spec_fn" }) do
      local ok, adapter = pcall(adapters.resolve, name)
      local key
      if ok and adapter then key = utils.get_env_vars(adapter).env_replaced.api_key end
      out[name] = { name = ok and adapter and adapter.name or vim.NIL, type = ok and adapter and adapter.type or vim.NIL,
        key = key or vim.NIL }
    end
    local ok, codex = pcall(adapters.resolve, "codex")
    out.codex_auth = ok and codex and codex.defaults and codex.defaults.auth_method or vim.NIL
    out.codecompanion_adapter = vim.g.codecompanion_adapter or vim.NIL
    io.stdout:write(vim.json.encode(out))
    vim.cmd("qa!")
  ]]
  local result = vim.system({ vim.v.progpath, "--headless", "-u", "init.lua", "-i", "NONE", "-c", "lua " .. probe:gsub("\n", " ") },
    { env = env, text = true }):wait(30000)
  local ok, decoded = pcall(vim.json.decode, (result.stdout or ""):match("{.*}") or "")
  return ok and decoded or { error = (result.stdout or "") .. (result.stderr or "") }
end

local configured = resolve({
  ANTHROPIC_API_KEY = "cli-anthropic",
  OPENAI_API_KEY = "cli-openai",
  SPEC_ENV_OPENAI_KEY = "from-dollar-var",
  SPEC_FN_BACKING = "from-lua-function",
})

t.eq(configured.anthropic, { name = "anthropic", type = "http", key = "" },
  "unconfigured built-in anthropic adapter ignores ANTHROPIC_API_KEY")
t.eq(configured.openai, { name = "openai", type = "http", key = "from-dollar-var" },
  "$VAR api_key reads its named environment variable")
t.eq(configured.spec_literal, { name = "spec_literal", type = "http", key = "literal-secret-key" },
  "literal api_key string resolves directly without touching environment variables")
t.eq(configured.spec_fn, { name = "spec_fn", type = "http", key = "from-lua-function" },
  "function api_key resolves dynamically when CodeCompanion requests credentials")
t.eq(configured.codex_auth, "chat-gpt",
  "the Codex ACP adapter uses the ChatGPT login, not OPENAI_API_KEY")
t.eq(configured.codecompanion_adapter, vim.NIL, "vim.g.codecompanion_adapter stays unset")

local unset_env = resolve({
  ANTHROPIC_API_KEY = "cli-anthropic",
  OPENAI_API_KEY = "cli-openai",
  SPEC_ENV_OPENAI_KEY = "",
  SPEC_FN_BACKING = "",
})
t.eq(unset_env.openai.key, "", "unset $VAR resolves to empty rather than falling back to OPENAI_API_KEY")
t.eq(unset_env.spec_fn.key, "", "empty function result resolves to empty rather than CLI keys")

t.done()
