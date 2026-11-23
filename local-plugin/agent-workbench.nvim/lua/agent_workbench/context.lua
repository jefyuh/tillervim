-- Optional host policy has native defaults; no private host modules are loaded.
local M = {}
local function callback(name, fallback, ...)
  return (require("agent_workbench.options").callback(name) or fallback)(...)
end
function M.project_root(path)
  return callback("project_root", function(file)
    local start = file and file ~= "" and vim.fs.dirname(file) or vim.fn.getcwd()
    return vim.fs.root(start, ".git") or vim.fn.getcwd()
  end, path)
end
function M.editor_win()
  return callback("editor_win", function()
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.api.nvim_win_get_config(win).relative == "" and vim.bo[buf].buftype == "" then return win end
    end
  end)
end
function M.origin_tab(tab)
  return callback("origin_tab", function() return nil end, tab)
end
function M.notify_error(err)
  return callback("notify_error", function(value) vim.notify(tostring(value), vim.log.levels.WARN) end, err)
end
function M.toggle_zoom(win)
  return callback("toggle_zoom", function(target)
    target = target or vim.api.nvim_get_current_win()
    if not vim.api.nvim_win_is_valid(target) then return false end
    if vim.w[target].agent_zoomed then
      local saved = vim.t.agent_zoom_state
      vim.w[target].agent_zoomed, vim.t.agent_zoom_state = false, nil
      for _, wf in ipairs(saved and saved.winfix or {}) do
        if type(wf) == "table" and wf.win and vim.api.nvim_win_is_valid(wf.win) then
          vim.wo[wf.win].winfixwidth, vim.wo[wf.win].winfixheight = wf.width, wf.height
        end
      end
      vim.cmd("wincmd =")
      if saved and saved.target_width and vim.wo[target].winfixwidth then
        vim.api.nvim_win_set_width(target, saved.target_width)
      end
      return false
    end
    local winfix = {}
    local target_width = vim.api.nvim_win_get_width(target)
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if w ~= target and vim.api.nvim_win_is_valid(w) and vim.api.nvim_win_get_config(w).relative == "" then
        winfix[#winfix + 1] = { win = w, width = vim.wo[w].winfixwidth, height = vim.wo[w].winfixheight }
        vim.wo[w].winfixwidth, vim.wo[w].winfixheight = false, false
      end
    end
    vim.api.nvim_win_call(target, function()
      vim.cmd.wincmd("_")
      vim.cmd.wincmd("|")
    end)
    vim.w[target].agent_zoomed = true
    vim.t.agent_zoom_state = { winfix = winfix, target_width = target_width }
    return true
  end, win)
end
return M
