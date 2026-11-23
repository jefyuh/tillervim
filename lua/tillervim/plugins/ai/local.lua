local root = require("tillervim").root()
local function inline() return require("agent_workbench").inline() end
local function relabel_inline()
  local label = require("agent_workbench").key.info().profile.label
  for _, mode in ipairs({ "n", "x" }) do
    for _, mapping in ipairs(vim.api.nvim_get_keymap(mode)) do
      if mapping.callback == inline then
        -- mapset keeps the user's exact callback, mode and mapping flags.
        mapping.desc = ("Inline edit · %s (HTTP)…"):format(label)
        vim.fn.mapset(mapping)
      end
    end
  end
end
return {
  virtual = true, dir = root .. "/local-plugin/agent-workbench.nvim", name = "agent-workbench.nvim", main = "agent_workbench",
  lazy = false, priority = 9000,
  keys = {
    { "<leader>an", function() require("agent_workbench").new_chat() end, mode = { "n", "x" }, desc = "New AI chat…" },
    { "<leader>al", function() require("agent_workbench").switch_chat() end, mode = { "n", "x" }, desc = "Switch AI chat…" },
    { "<leader>ac", function() require("agent_workbench").toggle() end, mode = "n", desc = "Toggle AI chat" },
    { "<leader>af", function() require("agent_workbench").focus() end, mode = "n", desc = "Focus AI chat" },
    { "<leader>az", function() require("agent_workbench").zoom() end, mode = "n", desc = "Toggle AI chat zoom" },
    { "<C-.>", function() require("agent_workbench").zoom() end, mode = { "n", "i", "t" }, desc = "Toggle AI chat zoom" },
    { "<leader>ar", function() require("agent_workbench").resume() end, mode = "n", desc = "Resume native agent…" },
    { "<leader>aR", function() require("agent_workbench").continue() end, mode = "n", desc = "Continue native agent" },
    { "<leader>am", function() require("agent_workbench").select_model() end, mode = "n", desc = "Select native agent model…" },
    { "<leader>ab", function() require("agent_workbench").add_buffer() end, mode = "n", desc = "Add file to AI chat" },
    { "<leader>as", function() require("agent_workbench").send_selection() end, mode = "x", desc = "Add selection to AI chat" },
    { "<leader>ai", function() require("agent_workbench").compose() end, mode = { "n", "x" }, desc = "Compose prompt for AI chat" },
    { "<leader>at", function() require("agent_workbench").transcript() end, mode = "n", desc = "Read native agent transcript" },
    { "<leader>aT", function() require("agent_workbench").transcript_pick() end, mode = "n", desc = "Browse native agent transcripts" },
    { "<leader>av", function() require("agent_workbench").review() end, mode = "n", desc = "Review changes since round baseline" },
    { "<leader>aV", function() require("agent_workbench").new_round() end, mode = "n", desc = "Start review round" },
    { "<leader>ax", "<cmd>AI key<cr>", desc = "Switch API key profile…" },
    { "<leader>ao", require("tillervim.profile").companion and "<cmd>CodeCompanionHistory<cr>" or false, desc = "Browse saved Companion chats" },
    { "<leader>ae", inline, mode = { "n", "x" }, expr = true, silent = false, desc = "Inline edit…" },
  },
  opts = function()
    local opts = vim.deepcopy(require("tillervim.config.ai"))
    local codex = opts.providers[1]
    local parts = { codex = "tui", ["codex-acp"] = "acp" }
    local profile = require("tillervim.profile")
    opts.providers = {}
    local groups = {}
    for _, id in ipairs(profile.selected.ai) do
      local name = parts[id] and "codex" or id:gsub("%-acp$", "")
      local bridge = profile.bridges[name]
      if not groups[name] then
        groups[name] = { name = name, label = bridge and bridge.label or codex.label }
        table.insert(opts.providers, groups[name])
      end
      local group = groups[name]
      if parts[id] then
        group[parts[id]] = codex[parts[id]]
        group.cli_api_key = codex.cli_api_key
      elseif id == name then
        group.tui = { kind = name }
      else
        group.acp = { adapter = bridge.adapter, command = bridge.command }
      end
    end
    local git = require("tillervim.util.settings").git()
    opts.review = vim.tbl_deep_extend("force", vim.deepcopy(require("tillervim.config.review")), {
      max_file_size = git.max_file_size, history_limit = git.history_limit, retention = { saved = git.retention.saved },
    })
    opts.integrations = { review = true }
    opts.callbacks = {
      project_root = require("tillervim.util.cwd").project_root,
      editor_win = function() return require("editor_core.window").editor_win() end,
      origin_tab = function(tab) return require("editor_core.window").origin_tab(tab) end,
      notify_error = function(err) return require("editor_core.vim_error").notify(err) end,
      toggle_zoom = function(win) return require("editor_core.window").toggle_zoom(win) end,
    }
    return opts
  end,
  config = function(_, opts)
    opts.integrations = opts.integrations or {}
    if opts.integrations.companion == nil then
      opts.integrations.companion = require("tillervim.profile").companion
        or vim.iter(opts.providers or {}):any(function(entry) return entry.acp ~= nil or entry.api ~= nil end)
    end
    if opts.integrations.companion and not require("tillervim.profile").companion and vim.fn.maparg("<leader>ao", "n") == "" then
      vim.keymap.set("n", "<leader>ao", "<cmd>CodeCompanionHistory<cr>", { desc = "Browse saved Companion chats" })
    end
    require("agent_workbench").setup(opts)
    require("editor_core.terminal").set_agent_test(require("agent_workbench.terminal").is_agent_buf)
    vim.api.nvim_create_autocmd("User", {
      group = vim.api.nvim_create_augroup("tillervim_inline_label", { clear = true }),
      pattern = "AIStateChanged", callback = relabel_inline,
    })
    relabel_inline()
  end,
}
