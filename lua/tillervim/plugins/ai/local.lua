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
    { "<leader>ao", "<cmd>CodeCompanionHistory<cr>", desc = "Browse saved Companion chats" },
    { "<leader>ae", inline, mode = { "n", "x" }, expr = true, silent = false, desc = "Inline edit…" },
  },
  opts = function()
    local opts = vim.deepcopy(require("tillervim.config.ai"))
    local git = require("tillervim.util.settings").git()
    opts.review = vim.tbl_deep_extend("force", vim.deepcopy(require("tillervim.config.review")), {
      max_file_size = git.max_file_size, history_limit = git.history_limit, retention = { saved = git.retention.saved },
    })
    opts.integrations = { companion = true, review = true }
    opts.callbacks = {
      project_root = require("tillervim.util.cwd").project_root,
      editor_win = function() return require("editor_core.window").editor_win() end,
      origin_tab = function(tab) return require("editor_core.window").origin_tab(tab) end,
      notify_error = function(err) return require("editor_core.vim_error").notify(err) end,
    }
    return opts
  end,
  config = function(_, opts)
    require("agent_workbench").setup(opts)
    require("editor_core.terminal").set_agent_test(require("agent_workbench.terminal").is_agent_buf)
    vim.api.nvim_create_autocmd("User", {
      group = vim.api.nvim_create_augroup("tillervim_inline_label", { clear = true }),
      pattern = "AIStateChanged", callback = relabel_inline,
    })
    relabel_inline()
  end,
}
