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

local function alt_screen_always(argv)
  return table.concat(argv, " "):find('"altScreenMode"%s*:%s*"always"') ~= nil
end

local function terminal_command(kind, argv, env)
  local native = require("agent_workbench.options").get().native[kind]
  if kind ~= "antigravity" or not native or native.wrap_tmux == false or vim.fn.executable("tmux") ~= 1 then
    return argv
  end
  -- In session-only altScreenMode, agy enables mouse tracking (?1002h/?1006h)
  -- and scrolls its own viewport, so tmux leaves WheelUpPane/PPage unbound to
  -- pass wheel and page keys straight to agy while still composing DEC 2026
  -- frames offscreen. Inline agy (args = {}) uses tmux copy-mode like Codex.
  return launch.tmux_command("antigravity", argv, {
    copy_mode_scroll = not alt_screen_always(argv),
    env = env or terminal_env(),
  })
end
M._terminal_command = terminal_command

local function agy_prompt_ready(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return false end
  for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if line:match("^>%s*$") then return true end
  end
  return false
end

function M.new(kind)
  local backend, session = {}, nil
  assert(require("agent_workbench.options").get().native[kind])
  local function agent_label()
    local agent = require("agent_workbench.state").agents[kind]
    return agent and agent.label or kind
  end
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
    launch.stop_tmux(session.buf, kind)
    local ok, err = terminals.stop(session)
    if ok then session = nil end
    return ok, err
  end
  local function open(extra)
    if not backend.running() then
      local config = require("agent_workbench.options").get()
      local native = assert(config.native[kind])
      local argv = vim.list_extend({ native.command }, native.args)
      if kind == "antigravity" then
        vim.list_extend(argv, require("agent_workbench.plugins").antigravity_args(native.command))
      end
      vim.list_extend(argv, extra or {})
      local env = terminal_env()
      local root = require("agent_workbench.context").project_root(vim.api.nvim_buf_get_name(0))
      session = terminals.open(kind, {
        argv = terminal_command(kind, argv, env),
        cwd = root,
        env = env,
        width = config.panel.width,
      })
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
  local function send_agy_slash(target, slash)
    local timer = assert(vim.uv.new_timer())
    local stable, elapsed = 0, 0
    local function close_timer()
      if not timer:is_closing() then
        timer:stop()
        timer:close()
      end
    end
    timer:start(100, 100, vim.schedule_wrap(function()
      elapsed = elapsed + 100
      if session ~= target or not backend.running() then
        close_timer()
        return
      end
      if agy_prompt_ready(target.buf) then
        stable = stable + 1
      else
        stable = 0
      end
      if stable >= 2 then
        close_timer()
        local sent = terminals.send(target, slash)
        if not sent then return end
        -- Bubble Tea updates the slash-command state on the text tick before
        -- Enter dispatches `/resume`; a 0ms gap arrives in one read and drops Enter.
        vim.defer_fn(function()
          if session == target and backend.running() then
            terminals.send(target, "\r")
          end
        end, 120)
      elseif elapsed >= 15000 then
        close_timer()
      end
    end))
  end
  backend.reveal = function() open() end
  backend.focus = function() open() end
  function backend.continue()
    if backend.running() then
      open()
      vim.notify(("%s is already running: this is its session"):format(agent_label()),
        vim.log.levels.INFO, { title = "AI" })
      return
    end
    open({ "--continue" })
  end
  function backend.resume()
    if backend.running() then
      open()
      local label = agent_label()
      local article = label:match("^[AEIOUaeiou]") and "An" or "A"
      local hint = kind == "antigravity" and "use /resume in it" or "exit it before resuming another"
      vim.notify(("%s %s session is already active: %s"):format(article, label, hint),
        vim.log.levels.INFO, { title = "AI" })
      return
    end
    if kind == "kimi" then return open({ "--session" }) end
    if kind == "antigravity" then
      open()
      if session and backend.running() then send_agy_slash(session, "/resume") end
      return
    end
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
