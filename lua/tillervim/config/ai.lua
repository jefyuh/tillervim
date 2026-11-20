-- AI settings. Edit this table, then restart Nvim to apply changes.
-- local-plugin/agent-workbench.nvim/lua/agent_workbench/state.lua validates it and owns the live state; plugin specs wire it
-- into the native terminals and CodeCompanion. Requiring this file only returns data.
return {
  plugin_dirs = {}, -- Local native plugin paths for Codex.
  -- Native is built in. Snacks and custom providers use the same lifecycle.
  terminal = { provider = "snacks" },
  native = {
    codex = { args = { "--no-alt-screen", "--yolo" }, wrap_tmux = true },
    antigravity = { args = { "--settings", '{"altScreenMode":"always"}' } },
  },
  -- HTTP profile for inline edits and command prompts, not for new chats.
  -- "auto": the first provider API whose key is configured, else the first API.
  -- Pin one with its api.name (default: api.adapter), e.g. "openai".
  -- :AI key <name> switches it for this Nvim only; nothing is saved here.
  key_profile = "auto",

  -- Width in columns, shared by native terminals and CodeCompanion chats.
  panel = { width = 90 },

  -- One provider groups related entry points; offer any of tui, acp and api.
  -- Omit a part to hide it. There is no default backend: <leader>an asks.
  -- Entries appear as terminals, then ACP, then API, in provider order.
  -- CodeCompanion's own chats use the first ACP adapter, else the first API.
  --
  -- tui.kind: codex, antigravity, kimi or opencode. The personal profile selects transports.
  -- acp.adapter: an existing CodeCompanion ACP adapter; command checks PATH.
  --   A new adapter must also be registered in lua/tillervim/plugins/ai/codecompanion.lua.
  -- api.adapter: a CodeCompanion HTTP adapter; declare HTTP providers explicitly
  --   in personal agent-workbench.nvim opts. `api_key` accepts "$VAR", a literal
  --   key string, or `function() -> string|nil`. Optional: label, model, and
  --   name (a unique key profile/adapter name).
  providers = {
    {
      name = "codex",
      label = "Codex",
      cli_api_key = "OPENAI_API_KEY",
      tui = { kind = "codex" },
      -- The ChatGPT login: codex-acp's own default (`api-key`) would bill
      -- OPENAI_API_KEY instead.
      acp = { adapter = "codex", command = "codex-acp", auth_method = "chat-gpt" },
    },
  },
}
