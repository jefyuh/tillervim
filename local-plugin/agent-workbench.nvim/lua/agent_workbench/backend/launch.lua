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

---@param agent "claude"|"codex"
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

return M
