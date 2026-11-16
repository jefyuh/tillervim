-- Actual editor actions, independent from which-key's renderer.
local M = {}
local views = {}
function M.setup()

  local bindings = {
    { key = "<leader>ml", action = "<cmd>Lazy<cr>", desc = "Lazy", mode = "n" },
    { key = "<leader>?", action = function() M.show() end, desc = "Keybinding guide", mode = "n" },
    { key = ";a", action = "<C-^>", desc = "Last used buffer (alternate)", mode = "n" },
    { key = "<leader>qq", action = function() require("editor_core.quit").all() end, desc = "Quit all", mode = "n" },
    { key = "<leader>qQ", action = function() require("editor_core.quit").all(true) end, desc = "Force quit all", mode = "n" },
    { key = "ss", action = "<cmd>split<cr>", desc = "Split below", mode = "n" },
    { key = "sv", action = "<cmd>vsplit<cr>", desc = "Split right", mode = "n" },
    { key = "sw", action = "<C-w>p", desc = "Previous window", mode = "n" },
    { key = "se", action = "<cmd>WindowFocusEditor<cr>", desc = "Editor window (toggle back)", mode = "n" },
    { key = "sd", action = "<cmd>WindowCloseCurrent<cr>", desc = "Close window", mode = "n" },
    { key = "so", action = "<cmd>WindowCloseOthers<cr>", desc = "Close other windows", mode = "n" },
    { key = "s=", action = function() require("editor_core.window").equalize_respecting_fixed() end, desc = "Equalize windows", mode = "n" },
    { key = "sm", action = function() require("editor_core.window").toggle_zoom() end, desc = "Toggle zoom", mode = "n" },
    { key = "<leader><tab>n", action = "<cmd>tabnew<cr>", desc = "New tab" },
    { key = "<leader><tab><tab>", action = "<cmd>tabnew<cr>", desc = "New tab" },
    { key = "<leader><tab>d", action = "<cmd>tabclose<cr>", desc = "Close tab" },
    { key = "<leader><tab>]", action = "<cmd>tabnext<cr>", desc = "Next tab" },
    { key = "<leader><tab>[", action = "<cmd>tabprev<cr>", desc = "Prev tab" },
    { key = "<leader><tab>l", action = "<cmd>tablast<cr>", desc = "Last tab" },
    { key = "<leader><tab>f", action = "<cmd>tabfirst<cr>", desc = "First tab" },
    { key = "<leader><tab>a", action = "g<Tab>", desc = "Last used tab (alternate)" },
    { key = "<leader><tab>o", action = "<cmd>tabonly<cr>", desc = "Close other tabs" },
    { key = "<leader><tab>s", action = "<cmd>tabs<cr>", desc = "List all tabs" },
    { key = "<leader>uf", action = function()
      local enabled = vim.b.autoformat ~= false
      vim.b.autoformat = not enabled
      vim.notify("File autoformat " .. (vim.b.autoformat and "enabled" or "disabled"))
    end, desc = "Toggle autoformat (file)" },
    { key = "<leader>uF", action = function()
      vim.g.autoformat = not vim.g.autoformat
      vim.notify("Autoformat " .. (vim.g.autoformat and "enabled" or "disabled"))
    end, desc = "Toggle autoformat (global)" },
    { key = "<leader>us", action = function() vim.opt_local.spell = not vim.opt_local.spell:get() end, desc = "Toggle spelling" },
    { key = "<leader>uw", action = function() vim.opt_local.wrap = not vim.opt_local.wrap:get() end, desc = "Toggle word wrap" },
    { key = "<leader>ul", action = function() vim.opt_local.number = not vim.opt_local.number:get() end, desc = "Toggle line numbers" },
    { key = "<leader>uL", action = function() vim.opt_local.relativenumber = not vim.opt_local.relativenumber:get() end, desc = "Toggle relative numbers" },
    { key = "<leader>ud", action = function() vim.diagnostic.enable(not vim.diagnostic.is_enabled()) end, desc = "Toggle diagnostics" },
    { key = "<leader>uh", action = function() vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled()) end, desc = "Toggle inlay hints" },
    { key = "<leader>uT", action = function()
      if vim.b.ts_highlight then
        vim.treesitter.stop()
      else
        vim.treesitter.start()
      end
    end, desc = "Toggle Treesitter highlight" },
    { key = "<leader>uc", action = function()
      local level = vim.o.conceallevel == 0 and 2 or 0
      vim.opt_local.conceallevel = level
      vim.notify("Conceallevel: " .. level)
    end, desc = "Toggle conceal level" },
    { key = "<leader>ub", action = function()
      vim.o.background = vim.o.background == "dark" and "light" or "dark"
    end, desc = "Toggle dark/light background" },
  }
  for _, entry in ipairs(bindings) do
    vim.keymap.set(entry.mode or "n", entry.key, entry.action, { desc = entry.desc, silent = true })
  end
end

-- Render the bindings their owners actually installed, including live descs.
-- Shared open actions are also shown outside picker/file-manager buffers.
function M.show()
  local api = vim.api
  local tab = api.nvim_get_current_tabpage()
  if views[tab] and api.nvim_win_is_valid(views[tab]) then api.nvim_set_current_win(views[tab]); return end
  local lines = { "TillerVim Key Reference", "", ";  Go to a file/symbol", ",  Act on this file/view", "s  Arrange windows", "<leader>  Global domains" }
  for _, mode in ipairs({ "n", "x", "i", "t" }) do
    local maps = {}
    for _, scope in ipairs({ api.nvim_get_keymap(mode), api.nvim_buf_get_keymap(0, mode) }) do
      for _, mapping in ipairs(scope) do if mapping.desc and mapping.desc ~= "" then maps[mapping.lhs] = mapping.desc end end
    end
    lines[#lines + 1], lines[#lines + 2] = "", "Mode: " .. mode
    local keys = vim.tbl_keys(maps)
    table.sort(keys)
    for _, key in ipairs(keys) do lines[#lines + 1] = string.format("  %-28s %s", key, maps[key]) end
  end
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].buftype, vim.bo[buf].bufhidden, vim.bo[buf].modifiable = "nofile", "wipe", false
  local width = math.max(1, math.min(110, vim.o.columns - 4))
  local height = math.max(1, math.min(#lines, vim.o.lines - 6))
  local win = api.nvim_open_win(buf, true, { relative = "editor", style = "minimal", border = "rounded",
  width = width, height = height, row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
  col = math.max(0, math.floor((vim.o.columns - width) / 2)), title = " Key Reference " })
  views[tab] = win
  local function close() if api.nvim_win_is_valid(win) then api.nvim_win_close(win, true) end end
  vim.keymap.set("n", "q", close, { buffer = buf, desc = "Close keybinding guide" })
  vim.keymap.set("n", "<Esc>", close, { buffer = buf, desc = "Close keybinding guide" })
end
return M
