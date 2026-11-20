local launch = require("agent_workbench.backend.launch")
local terminals = require("agent_workbench.terminal_provider")
local M = {}

local function terminal_env()
  local env = launch.editor_env()
  -- Bubble Tea v2 gates DEC 2026 synchronized output queries on TERM_PROGRAM
  -- when :terminal sets TERM=xterm-256color. Guarantee a non-empty value so
  -- embedded TUIs always batch frames without cursor flicker.
  if (vim.env.TERM_PROGRAM or "") == "" then env.TERM_PROGRAM = "nvim" end
  return env
end

function M.new(kind)
  local backend, session = {}, nil
  local config = require("agent_workbench.options").get()
  local native = assert(config.native[kind])
  function backend.running() return terminals.alive(session) end
  function backend.buf() return backend.running() and session.buf or nil end
  function backend.window() return terminals.window(session) end
  function backend.visible()
    local win = backend.window()
    return win ~= nil and vim.api.nvim_win_get_tabpage(win) == vim.api.nvim_get_current_tabpage()
  end
  function backend.hide() return terminals.hide(session) end
  function backend.stop()
    if not session then return true end
    local ok, err = terminals.stop(session)
    if ok then session = nil end
    return ok, err
  end
  local function open(extra)
    if not backend.running() then
      local argv = vim.list_extend({ native.command }, native.args)
      vim.list_extend(argv, extra or {})
      local root = require("agent_workbench.context").project_root(vim.api.nvim_buf_get_name(0))
      session = terminals.open(kind, { argv = argv, cwd = root, env = terminal_env(), width = config.panel.width })
    end
    local win = backend.window()
    for _, candidate in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.api.nvim_win_get_buf(candidate) == session.buf and vim.api.nvim_win_get_config(candidate).relative == "" then
        win = candidate
        break
      end
    end
    if not win then
      local shown, err = terminals.show(session)
      assert(shown, err and err.message)
      win = shown
    end
    vim.api.nvim_set_current_win(win)
    vim.cmd.startinsert()
  end
  backend.reveal = open
  backend.focus = open
  function backend.continue()
    open({ "--continue" })
  end
  function backend.resume()
    if kind == "kimi" then return open({ "--session" }) end
    open()
    vim.notify("Use the CLI's session picker in this terminal")
  end
  function backend.select_model()
    open()
    vim.notify("Choose the model in this CLI's interface")
  end
  function backend.send_text(text)
    open()
    local payload = text:gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("\27", "")
    local ok, err = terminals.send(session, "\27[200~" .. payload .. "\27[201~")
    assert(ok, err and err.message)
  end
  function backend.add_path(path, modified)
    open()
    if modified then vim.notify("File references use the saved file", vim.log.levels.WARN) end
    backend.send_text("@" .. (vim.fs.relpath(session.root, path) or path) .. " ")
  end
  function backend.attach_images(paths)
    local function discard()
      for _, png in ipairs(paths or {}) do vim.fn.delete(png) end
    end
    if not backend.running() then
      vim.notify("Agent terminal is gone; images were not attached", vim.log.levels.WARN)
      discard()
      return
    end
    local channel = session.buf and vim.api.nvim_buf_is_valid(session.buf) and vim.bo[session.buf].channel
    if not channel or channel <= 0 then
      vim.notify("Agent terminal is not ready; images were not attached", vim.log.levels.WARN)
      discard()
      return
    end
    require("agent_workbench.clipboard").attach(channel, paths, function()
      if session and session.buf and vim.api.nvim_buf_is_valid(session.buf)
        and require("agent_workbench.image_preview").adopt_terminal(session.buf, paths) then
        return
      end
      discard()
    end)
  end
  function backend.edit_prompt(opts)
    if opts and (opts.on_consumed or opts.on_expired) then
      if opts.on_expired then opts.on_expired() end
      return vim.notify("Review draft kept. Use an ACP chat for integrated review.", vim.log.levels.WARN)
    end
    if opts and opts.seed then backend.send_text(opts.seed) else open() end
  end
  return backend
end
return M
