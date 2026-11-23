-- Native-agent launch support. Requiring this module starts nothing: each
-- backend calls ensure_watchdog only when its own terminal is first used.
local M = {}
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h:h")
function M.script(name) return root .. "/scripts/" .. name end

local function teardown_ignore()
  return require("agent_workbench.options").get().native.codex.teardown_ignore
end

---Path to the $EDITOR wrapper the agent terminals are launched with.
---@return string
function M.wrapper()
  return M.script("agent-editor")
end

---Launcher that keeps a failed agent's error on screen instead of letting the
---panel vanish. Used as the pane command inside both tmux wrappers -- see
---local-plugin/agent-workbench.nvim/scripts/agent-run for why the exit status cannot be recovered on this side.
---@return string
function M.runner()
  return M.script("agent-run")
end

---Absolute path to local-plugin/agent-workbench.nvim/scripts/agent-teardown. Both wrappers run it from their
---`client-detached` hook and their watchdog: it records the pane's process tree
---before the tmux server goes and sweeps whatever of it survives, so quitting
---Nvim no longer leaves the agent's background jobs running with ppid 1.
---@return string
function M.teardown()
  return M.script("agent-teardown")
end

---Command argv to invoke agent-teardown with the configured ignore pattern.
---@param socket string
---@param wait? boolean
---@return string[]
function M.teardown_argv(socket, wait)
  local argv = { M.teardown(), "--ignore", teardown_ignore() }
  if wait then argv[#argv + 1] = "--wait" end
  argv[#argv + 1] = socket
  return argv
end

---The tmux command installed as the wrapper's `client-detached` hook: run
---agent-teardown for `socket` detached, or -- should the script be missing --
---fall back to a bare kill-server, so the server never outlives its client.
---@param socket string the wrapper server's `-L` name
---@return string
function M.teardown_hook(socket)
  local sh = table.concat(vim.tbl_map(vim.fn.shellescape, M.teardown_argv(socket, false)), " ")
    .. " || tmux -L " .. socket .. " kill-server"
  return 'run-shell -b "' .. sh:gsub('[\\"$`]', "\\%0") .. '"'
end

---Environment for the TUI's ctrl+g handoff, including without tmux. A tmux
---pane also needs these values explicitly forwarded through new-session -e.
---@return table<string, string>
function M.editor_env()
  local wrapper = M.wrapper()
  return { EDITOR = wrapper, VISUAL = wrapper, NVIM = vim.v.servername }
end

-- A detached watchdog covers exits where client-detached cannot run (Nvim
-- killed outright or the host terminal torn down), and sweeps stale wrapper
-- servers from earlier crashes. Teardown runs synchronously so a socket only
-- goes once the server and the agent's leftover process tree are gone.
local watchdog_started = {}

---@param agent "claude"|"codex"|"antigravity"
function M.ensure_watchdog(agent)
  if watchdog_started[agent] then return end
  watchdog_started[agent] = true

  local pid = vim.fn.getpid()
  local prefix = agent .. "-nvim-"
  local socket = prefix .. pid
  local teardown = table.concat(vim.tbl_map(vim.fn.shellescape, {
    M.teardown(), "--ignore", teardown_ignore(), "--wait",
  }), " ")
  local script = string.format([[
    for s in /private/tmp/tmux-*/%s* /tmp/tmux-*/%s*; do
      [ -e "$s" ] || continue
      case $s in *.lock) continue ;; esac   # tmux's lock file beside the socket
      owner=${s##*%s}
      if ! kill -0 "$owner" 2>/dev/null; then
        %s "$s" || tmux -S "$s" kill-server 2>/dev/null
        rm -f "$s"
      fi
    done
    while kill -0 %d 2>/dev/null; do sleep 2; done
    %s %s || tmux -L %s kill-server 2>/dev/null
    rm -f /private/tmp/tmux-*/%s /tmp/tmux-*/%s
  ]], prefix, prefix, prefix, teardown, pid, teardown, socket, socket, socket, socket)
  -- detach calls setsid, surviving the SIGHUP cascade through Nvim's group.
  vim.fn.jobstart({ "sh", "-c", script }, { detach = true })
end

---Compose a dedicated per-agent tmux wrapper argv around `args`.
---
---Neovim's libvterm only suppresses buffer-line copy during DEC Mode 2026
---synchronized updates while mutating cell attributes, cursor state and OSC 2
---titles per 1024-byte PTY chunk, tearing multi-kilobyte TUI frames (Codex,
---Antigravity). tmux buffers the full ?2026h...?2026l frame offscreen and emits
---only the net diff to :terminal.
---@param agent "claude"|"codex"|"antigravity"
---@param args string[]
---@param opts? { copy_mode_scroll?: boolean, env?: table<string, string> }
---@return string[]
function M.tmux_command(agent, args, opts)
  M.ensure_watchdog(agent)
  local raw_term = vim.env.TERM
  local term = (raw_term and raw_term ~= "" and raw_term ~= "dumb") and raw_term or "xterm-256color"
  local socket = agent .. "-nvim-" .. vim.fn.getpid()
  local env = M.editor_env()
  local command = {
    "env", "TERM=" .. term,
    "tmux", "-f", "/dev/null", "-L", socket,
    "set-option", "-s", "escape-time", "0",
    ";", "set-option", "-g", "default-terminal", term,
    ";", "set-option", "-g", "history-limit", "50000",
    ";", "set-option", "-g", "mouse", "on",
    -- Keep mouse scrolling, but suppress tmux's pane menu on right-click.
    ";", "unbind-key", "-T", "root", "MouseDown3Pane",
    ";", "unbind-key", "-T", "root", "M-MouseDown3Pane",
    -- <S-CR> reaches this pane as CSI u (ESC[13;2u) from editor_core/keymaps.lua.
    -- `always` + `csi-u` preserves modified Enter for both crossterm (Codex) and
    -- Bubble Tea (Antigravity) instead of collapsing it to a bare submit CR.
    ";", "set-option", "-g", "extended-keys", "always",
    ";", "set-option", "-g", "extended-keys-format", "csi-u",
  }
  -- Inline TUIs (--no-alt-screen) rely on tmux copy-mode for scrollback, whereas
  -- alternate-screen TUIs that own mouse tracking (Antigravity altScreenMode)
  -- scroll their own viewport when WheelUpPane/PPage are left unbound here.
  if not opts or opts.copy_mode_scroll ~= false then
    vim.list_extend(command, {
      ";", "bind-key", "-T", "root", "WheelUpPane", "copy-mode", "-e",
      ";", "bind-key", "-T", "root", "PPage", "copy-mode", "-eu",
    })
  end
  vim.list_extend(command, {
    ";", "bind-key", "-T", "copy-mode", "WheelUpPane", "send-keys", "-X", "-N", "2", "scroll-up",
    ";", "bind-key", "-T", "copy-mode", "WheelDownPane", "send-keys", "-X", "-N", "2", "scroll-down",
    ";", "bind-key", "-T", "copy-mode-vi", "WheelUpPane", "send-keys", "-X", "-N", "2", "scroll-up",
    ";", "bind-key", "-T", "copy-mode-vi", "WheelDownPane", "send-keys", "-X", "-N", "2", "scroll-down",
    ";", "new-session", "-A", "-s", "main",
    -- tmux only puts into the pane what is whitelisted here; $NVIM must be
    -- spelled out from v:servername because jobstart runs without a shell.
    "-e", "EDITOR=" .. env.EDITOR,
    "-e", "VISUAL=" .. env.VISUAL,
    "-e", "NVIM=" .. vim.v.servername,
  })
  if opts and opts.env and opts.env.TERM_PROGRAM and opts.env.TERM_PROGRAM ~= "" then
    vim.list_extend(command, { "-e", "TERM_PROGRAM=" .. opts.env.TERM_PROGRAM })
  end
  command[#command + 1] = M.runner()
  vim.list_extend(command, args)
  vim.list_extend(command, {
    -- Off, deliberately: the client-detached hook below records the pane's
    -- process tree before killing the server; exit-empty ends the server on a
    -- clean agent exit.
    ";", "set-option", "-g", "destroy-unattached", "off",
    ";", "set-option", "-g", "exit-empty", "on",
    ";", "set-option", "-g", "status", "off",
    ";", "set-hook", "-g", "client-detached", M.teardown_hook(socket),
  })
  return command
end

---Synchronously tear down `buf`'s owned tmux wrapper server and socket, if any.
---@param buf integer|nil
---@param agent "claude"|"codex"|"antigravity"
function M.stop_tmux(buf, agent)
  local info = buf and vim.api.nvim_buf_is_valid(buf) and vim.b[buf].agent_workbench
  local argv = info and info.cmd or {}
  local socket = agent .. "-nvim-" .. vim.fn.getpid()
  for i, arg in ipairs(argv) do
    if arg == "-L" and argv[i + 1] == socket then
      vim.system(M.teardown_argv(socket, true), { timeout = 5000 }):wait()
      local tmp = (vim.env.TMUX_TMPDIR and vim.env.TMUX_TMPDIR ~= "") and vim.env.TMUX_TMPDIR or nil
      local globs = tmp and { tmp .. "/tmux-*/" .. socket }
        or { "/private/tmp/tmux-*/" .. socket, "/tmp/tmux-*/" .. socket }
      for _, pat in ipairs(globs) do
        for _, path in ipairs(vim.fn.glob(pat, false, true)) do vim.fn.delete(path) end
      end
      break
    end
  end
end

return M
