-- Guards the agent panel's input rules (local-plugin/agent-workbench.nvim/lua/agent_workbench/terminal.lua).
--
-- Both were silent losses rather than errors, which is why they survived so
-- long: a click inside the panel left Terminal-mode, so returning to the window
-- manager and clicking back put the panel in Normal mode; and a quick double
-- Esc -- the agents' own "go back a message" -- was eaten by Snacks'
-- `term_normal` double-tap unless disabled and guarded buffer-locally.
local t = dofile("tests/helper.lua")

local config = require("agent_workbench.state")
local ai_term = require("agent_workbench.terminal")

-- A stand-in for the real CLI: identity is decided by the command's basename,
-- so a script named after the provider is indistinguishable from the agent as
-- far as ai.state.is_native_command is concerned -- and it will not try to
-- reach the network or a real session.
local bin = vim.fn.tempname() .. "/" .. config.agents[config.agent_names()[1]].command
vim.fn.mkdir(vim.fn.fnamemodify(bin, ":h"), "p")
vim.fn.writefile({ "#!/bin/sh", "exec cat" }, bin)
vim.fn.setfperm(bin, "rwx------")

---@param cmd string[]
---@return integer buf
local function open_panel(cmd)
  local term = require("snacks").terminal.open(cmd, {
    auto_insert = true,
    start_insert = true,
    win = { position = "right", width = 0.4, keys = { term_normal = false },
      on_buf = function(win)
        vim.b[win.buf].agent_workbench = { id = "native:codex", kind = "codex", cmd = cmd, cwd = vim.fn.getcwd() }
      end,
    },
  })
  vim.wait(2000, function() return vim.bo[term.buf].buftype == "terminal" end)
  return term.buf
end

---tmux leaves its socket file behind when a server exits, so a spec that
---started one removes the file too, or every run adds one to /tmp/tmux-*/.
---@param socket string
local function remove_socket(socket)
  local dir = (vim.env.TMUX_TMPDIR and vim.env.TMUX_TMPDIR ~= "") and vim.env.TMUX_TMPDIR or "/tmp"
  for _, path in ipairs(vim.fn.glob(dir .. "/tmux-*/" .. socket, false, true)) do
    vim.fn.delete(path)
  end
end

---Is `lhs` mapped in Terminal-mode, and is that mapping buffer-local?
local function buffer_local(lhs)
  local m = vim.fn.maparg(lhs, "t", false, true)
  return next(m) ~= nil and m.buffer == 1
end

---The same question for Normal mode, where the scrollback forwarding lives.
local function buffer_local_n(lhs)
  local m = vim.fn.maparg(lhs, "n", false, true)
  return next(m) ~= nil and m.buffer == 1
end

-- Unwrapped panel: Nvim itself sees the click, so it needs the guard.
local plain = open_panel({ bin })
t.ok(ai_term.is_agent_buf(plain), "the fake agent reads as an agent buffer")
t.eq(vim.fn.maparg("<Esc>", "t", false, true).buffer, 1,
  "Esc is buffer-local on the panel, so it reaches the agent without waiting on prefixes")
t.ok(buffer_local("<LeftMouse>"),
  "an unwrapped panel guards the mouse, so a click inside it keeps Terminal-mode")
t.ok(buffer_local("<ScrollWheelDown>"),
  "an unwrapped inline panel swallows Terminal-mode wheel-down at the live bottom")
t.ok(not buffer_local_n("<PageUp>"),
  "an unwrapped panel leaves scrolling to Nvim, which owns the scrollback there")

-- Builtin <C-\><C-n> leaves Terminal-mode; distribution defaults install no
-- extra Terminal-mode exit aliases (<Esc><Esc>, jk, <C-]>, <C-\>).
for _, lhs in ipairs({ "<Esc><Esc>", "jk", "<C-]>", "<C-\\>" }) do
  t.eq(vim.fn.maparg(lhs, "t", false, true), {}, lhs .. " is unmapped in Terminal-mode by default")
end

-- Wrapped panel: tmux turns mouse reporting on, Nvim forwards the click and
-- never leaves Terminal-mode on its own. Mapping there would take the click
-- away from tmux's copy-mode instead of fixing anything.
if vim.fn.executable("tmux") == 1 then
  local wrapped = open_panel({
    "tmux", "-f", "/dev/null", "-L", "nvim-spec-" .. vim.fn.getpid(),
    "set-option", "-g", "mouse", "on", ";",
    "new-session", "-A", "-s", "main", bin,
  })
  t.eq(vim.fn.maparg("<Esc>", "t", false, true).buffer, 1,
    "a wrapped panel still passes Esc through to the agent")
  t.ok(not buffer_local("<LeftMouse>"), "a wrapped panel leaves the mouse to tmux")
  -- Nvim's scrollback is one composed screenful when tmux owns the history, so
  -- a scroll from terminal-Normal mode has to go into the pane instead.
  for _, lhs in ipairs({ "<PageUp>", "<PageDown>", "<ScrollWheelUp>", "<C-u>", "<C-d>" }) do
    t.ok(buffer_local_n(lhs), "a wrapped panel forwards " .. lhs .. " into tmux history")
  end

  local socket = "nvim-spec-" .. vim.fn.getpid()
  local tmux = function(...)
    local command = { "tmux", "-L", socket }
    vim.list_extend(command, { ... })
    return vim.system(command, { text = true }):wait()
  end
  local pane_in_mode = function()
    return vim.trim(tmux("display-message", "-p", "-t", "main:", "#{pane_in_mode}").stdout or "")
  end

  -- The session answers before its pane does: on tmux 3.4 (CI) copy-mode
  -- failed and #{pane_in_mode} was empty for ~25 ms after #{session_name}
  -- was there. Wait for the pane, and the client, the next steps use.
  t.ok(vim.wait(2000, function()
    return pane_in_mode() == "0" and vim.trim(tmux("list-clients", "-t", "main").stdout or "") ~= ""
  end, 10), "the wrapped tmux server is ready")
  t.eq(tmux("copy-mode", "-u", "-t", "main:").code, 0,
    "the wrapped panel can enter tmux copy-mode")
  t.eq(pane_in_mode(), "1", "tmux reports that scrollback is active")
  vim.b[wrapped].ai_preserve_scrollback_once = true
  vim.api.nvim_exec_autocmds("TermEnter", { buffer = wrapped, modeline = false })
  t.eq(pane_in_mode(), "1", "the scroll-forwarding TermEnter preserves copy-mode once")
  vim.api.nvim_exec_autocmds("TermEnter", { buffer = wrapped, modeline = false })
  t.ok(vim.wait(1000, function() return pane_in_mode() == "0" end, 10),
    "manually resuming terminal input returns tmux to the live bottom")
  vim.fn.jobstop(vim.bo[wrapped].channel)
  -- jobstop only detaches the client; the server and its cat pane would
  -- outlive the run otherwise (39 of them had piled up under /tmp/tmux-*/).
  tmux("kill-server")
  remove_socket(socket)
end

-- The native Codex wrapper preserves modified Enter through tmux's CSI u
-- forwarding, independently of the host's editable provider declarations.
if vim.fn.executable("tmux") == 1 then
  local joined = table.concat(require("agent_workbench.backend.codex")._terminal_command({ "codex" }), " ")
  t.ok(joined:find("extended-keys always", 1, true), "Codex preserves modified Enter")
  t.ok(joined:find("extended-keys-format csi-u", 1, true), "tmux emits CSI u for Codex")
end

-- A failing agent must not take its own error message down with it. The tmux
-- wrapper's teardown reports success to nvim whatever the pane's command did,
-- so without the launcher a startup failure is indistinguishable from a clean
-- exit and Snacks just closes the panel.
local runner = require("agent_workbench.backend.launch").runner()
t.eq(vim.fn.executable(runner), 1, "local-plugin/agent-workbench.nvim/scripts/agent-run is present and executable")

-- The script itself: a clean exit passes straight through, a failure reports
-- the status and says why the panel is still there.
t.eq(vim.fn.system({ runner, "sh", "-c", "exit 0" }) == "" and vim.v.shell_error, 0,
  "a clean exit passes through untouched")
local failed = vim.fn.system({ runner, "sh", "-c", "echo boom; exit 7" })
t.eq(vim.v.shell_error, 7, "a failure keeps the agent's own exit status")
t.ok(failed:find("boom", 1, true) ~= nil, "and keeps the agent's own output")
t.ok(failed:find("exited with status 7", 1, true) ~= nil, "and names the status")

-- Both wrappers have to route the pane through it.
if vim.fn.executable("tmux") == 1 then
  local cmd = require("agent_workbench.backend.codex")._terminal_command({ "codex" })
  local at = vim.fn.index(cmd, runner)
  t.ok(at >= 0, "the Codex wrapper runs the pane through agent-run")
  t.eq(cmd[at + 2], "codex", "with the agent command right after it")
end
-- Teardown. Quitting Nvim used to leave behind whatever the agent had spawned
-- into its own process group -- tmux only signals the pane's own process, and
-- the kernel's hangup only its session leader -- so a Codex exec_command dev
-- server outlived its Nvim by three days with ppid 1. The wrapper's
-- client-detached hook now runs local-plugin/agent-workbench.nvim/scripts/agent-teardown, which records the
-- pane's process tree before the server goes and sweeps the survivors after.
-- destroy-unattached has to be off for that hook to run at all: with it on, the
-- server was gone before the hook fired (measured).
local teardown = require("agent_workbench.backend.launch").teardown()
t.eq(vim.fn.executable(teardown), 1, "local-plugin/agent-workbench.nvim/scripts/agent-teardown is present and executable")

if vim.fn.executable("tmux") == 1 then
  local cmd = require("agent_workbench.backend.codex")._terminal_command({ "codex" })
  local joined = table.concat(cmd, " ")
  t.ok(joined:find("destroy-unattached off", 1, true) ~= nil,
    "the Codex wrapper keeps the session until its client-detached hook has run")
  t.eq(cmd[#cmd - 1], "client-detached", "the Codex wrapper ends with the client-detached hook")
  t.ok(teardown ~= "" and cmd[#cmd]:find(teardown, 1, true) ~= nil
    and cmd[#cmd]:find("kill-server", 1, true) ~= nil,
    "and that hook runs agent-teardown, falling back to kill-server")
end
-- The script itself, against a throwaway server shaped like a real pane: the
-- real launcher (agent-run) -> an agent stand-in -> the agent's children, two
-- of them in process groups of their own. One child is the leak shape (UC-1);
-- the other names an ignore-listed daemon and must be left alone (UC-R3). The
-- agent's argv -- and so the launcher's -- carries ignore-listed words too, as
-- a plugin path can, and that must not exempt the tree: the ignore list only
-- starts at the agent's children. The stand-in keeps its `&` list so no shell
-- exec-optimises a level away; agent-run never does, it checks the status.
if teardown ~= "" and vim.fn.executable("tmux") == 1 and vim.fn.executable("perl") == 1 then
  local sock = "nvim-spec-teardown-" .. vim.fn.getpid()
  local orphan = "nvim-spec-orphan-" .. vim.fn.getpid()
  local keep = "nvim-spec-crashpad_handler-" .. vim.fn.getpid()
  local children = table.concat({
    "perl -e 'setpgrp(0,0); sleep 300' " .. orphan .. " &",
    "perl -e 'setpgrp(0,0); sleep 300' " .. keep .. " &",
    "sleep 300",
  }, " ")
  local function alive(tag) return vim.fn.system({ "pgrep", "-f", tag }) ~= "" end
  vim.fn.system({ "tmux", "-f", "/dev/null", "-L", sock, "new-session", "-d", "-s", "main",
    runner, "sh", "-c", children, "--plugin-dir", "/x/gradle/emulator/" })
  vim.wait(2000, function() return alive(orphan) and alive(keep) end, 100)
  t.ok(alive(orphan) and alive(keep), "the stand-in tree is up before teardown")

  -- The default form returns at once and does the work detached (a hook's job
  -- dies with the server); --wait is the watchdog's synchronous form.
  vim.fn.system({ teardown, "--wait", sock })
  t.eq(vim.v.shell_error, 0, "agent-teardown --wait exits 0")
  vim.fn.system({ "tmux", "-L", sock, "list-sessions" })
  t.ok(vim.v.shell_error ~= 0, "the tmux server is gone")
  t.ok(not alive(orphan), "the own-process-group child went with it (UC-1)")
  t.ok(alive(keep), "an ignore-listed process under the pane was left alone (UC-R3)")
  vim.fn.system({ "pkill", "-f", keep })

  -- A server that is already gone is a no-op, not an error (UC-3).
  vim.fn.system({ teardown, sock })
  t.eq(vim.v.shell_error, 0, "agent-teardown on a dead server is a quiet no-op")
  remove_socket(sock)
end

-- Metadata from the provider, rather than Snacks' command guesses, owns identity.
vim.b[plain].snacks_terminal = nil
t.eq(ai_term.agent_of(plain), "codex", "agent identity survives removing Snacks metadata")
t.eq(require("agent_workbench").session_of_buffer(plain).kind, "codex", "host UI uses the same public identity")

-- Alternate-screen TUIs (Antigravity's default altScreenMode, OpenCode) enable
-- mouse reporting themselves, so clicks must pass through instead of being
-- swallowed by keep_terminal_mode_on_click; inline Antigravity (args = {})
-- still gets the click guard.
do
  local defaults = require("agent_workbench").options().native.antigravity
  t.eq(defaults.args, { "--settings", '{"altScreenMode":"always","pickerGrouping":"grouped"}' },
    "Antigravity defaults to session-only altScreenMode and workspace-grouped /resume")
  t.eq(defaults.wrap_tmux, true,
    "Antigravity defaults to wrap_tmux so DEC 2026 frames compose offscreen without libvterm PTY-chunk tearing")

  if vim.fn.executable("tmux") == 1 then
    local cli = require("agent_workbench.backend.cli")
    local agy_cmd = cli._terminal_command("antigravity", { "agy", "--settings", '{"altScreenMode":"always"}' })
    local agy_joined = table.concat(agy_cmd, " ")
    local at = vim.fn.index(agy_cmd, runner)
    t.ok(at >= 0 and agy_cmd[at + 2] == "agy", "Antigravity tmux wrapper runs agy through agent-run")
    t.ok(agy_joined:find("antigravity-nvim-" .. vim.fn.getpid(), 1, true) ~= nil,
      "Antigravity uses its own per-Nvim tmux socket")
    t.ok(agy_joined:find("escape-time 0", 1, true) ~= nil
      and agy_joined:find("extended-keys always", 1, true) ~= nil
      and agy_joined:find("extended-keys-format csi-u", 1, true) ~= nil,
      "Antigravity tmux wrapper preserves zero-delay Esc and CSI u modified Enter")
    t.ok(agy_joined:find("bind-key -T root WheelUpPane copy-mode", 1, true) == nil,
      "Antigravity altScreenMode leaves WheelUpPane unbound so mouse wheel reaches agy's own viewport")
    t.ok(agy_joined:find("destroy-unattached off", 1, true) ~= nil and agy_cmd[#agy_cmd - 1] == "client-detached",
      "Antigravity tmux wrapper installs the client-detached teardown hook")

    local inline_cmd = table.concat(cli._terminal_command("antigravity", { "agy" }), " ")
    t.ok(inline_cmd:find("bind-key -T root WheelUpPane copy-mode -e", 1, true) ~= nil,
      "inline Antigravity (without altScreenMode) binds WheelUpPane to tmux copy-mode")

    local restore = require("agent_workbench.options")._patch({ native = { antigravity = { wrap_tmux = false } } })
    local unwrapped = cli._terminal_command("antigravity", { "agy", "--settings", '{"altScreenMode":"always"}' })
    restore()
    t.eq(unwrapped, { "agy", "--settings", '{"altScreenMode":"always"}' },
      "native.antigravity.wrap_tmux = false bypasses the tmux wrapper")
  end

  local prev = config.agents.antigravity
  config._set_providers({
    { name = "codex", label = "Codex", tui = { kind = "codex" } },
    { name = "antigravity", label = "Antigravity", tui = { kind = "antigravity" } },
    { name = "opencode", label = "OpenCode", tui = { kind = "opencode" } },
  })
  local function open_kind(kind, cmd)
    local term = require("snacks").terminal.open({ bin }, {
      auto_insert = true,
      start_insert = true,
      win = { position = "right", width = 0.4, keys = { term_normal = false },
        on_buf = function(win)
          vim.b[win.buf].agent_workbench = { id = "native:" .. kind, kind = kind, cmd = cmd, cwd = vim.fn.getcwd() }
        end,
      },
    })
    vim.wait(2000, function() return vim.bo[term.buf].buftype == "terminal" end)
    return term.buf
  end

  local agy_alt = open_kind("antigravity", { "agy", "--settings", '{"altScreenMode":"always"}' })
  t.eq(vim.fn.maparg("<Esc>", "t", false, true).buffer, 1, "Antigravity altscreen still passes Esc through")
  t.ok(not buffer_local("<LeftMouse>"), "Antigravity altscreen leaves mouse clicks to the TUI")
  t.ok(not buffer_local("<ScrollWheelDown>"), "Antigravity altscreen leaves wheel-down to the TUI")

  local agy_wrapped = open_kind("antigravity", {
    "tmux", "-L", "agy-spec-unused", "new-session", "agy", "--settings", '{"altScreenMode":"always"}',
  })
  t.ok(not buffer_local("<LeftMouse>"), "tmux-wrapped Antigravity altscreen leaves mouse clicks to tmux/TUI")
  t.ok(buffer_local_n("<PageUp>"), "tmux-wrapped Antigravity forwards terminal-Normal PageUp into the pane")

  local agy_inline = open_kind("antigravity", { "agy" })
  t.ok(buffer_local("<LeftMouse>"), "inline Antigravity (args = {}) keeps the click guard")
  t.ok(buffer_local("<ScrollWheelDown>"), "inline Antigravity keeps the wheel-down bottom guard")

  local oc = open_kind("opencode", { "opencode" })
  t.ok(not buffer_local("<LeftMouse>"), "OpenCode leaves mouse clicks to its alternate-screen TUI")

  for _, b in ipairs({ agy_alt, agy_wrapped, agy_inline, oc }) do
    pcall(vim.fn.jobstop, vim.bo[b].channel)
    pcall(vim.api.nvim_buf_delete, b, { force = true })
  end

  -- Antigravity <leader>ar: workspace-isolated session discovery and async picker resume.
  do
    local agy_history = require("agent_workbench.backend.antigravity")
    local fixture_root = vim.fn.tempname()
    local repo_a = fixture_root .. "/space repo/project-a"
    local repo_b = fixture_root .. "/space repo/project-b"
    local repo_empty = fixture_root .. "/space repo/empty"
    local agy_data = fixture_root .. "/agy-data"
    local agy_stub_dir = fixture_root .. "/bin"
    local argv_out = fixture_root .. "/agy-argv.txt"
    for _, d in ipairs({ repo_a .. "/.git", repo_b .. "/.git", repo_empty .. "/.git", agy_data .. "/cache", agy_stub_dir }) do
      vim.fn.mkdir(d, "p")
    end
    local real_a = vim.uv.fs_realpath(repo_a) or repo_a
    local real_b = vim.uv.fs_realpath(repo_b) or repo_b
    local encoded_a = "file://" .. real_a:gsub(" ", "%%20")
    local agy_stub = agy_stub_dir .. "/agy"
    vim.fn.writefile({
      "#!/bin/sh",
      'printf "%s\\n" "$PWD" > ' .. vim.fn.shellescape(argv_out),
      'for arg in "$@"; do printf "%s\\n" "$arg" >> ' .. vim.fn.shellescape(argv_out) .. '; done',
      "exec cat",
    }, agy_stub)
    vim.fn.setfperm(agy_stub, "rwx------")

    vim.fn.writefile({ vim.json.encode({
      conversations = {
        ["11111111-aaaa-bbbb-cccc-000000000001"] = {
          is_internal = false,
          last_modified_time = "2026-11-24T10:00:00+08:00",
          summary = {
            ID = "11111111-aaaa-bbbb-cccc-000000000001",
            Title = "Older Project A Thread",
            Preview = "older prompt",
            NumSteps = 12,
            AppDataDir = "antigravity-cli",
            WorkspaceURIs = { encoded_a },
          },
        },
        ["22222222-aaaa-bbbb-cccc-000000000002"] = {
          is_internal = false,
          last_modified_time = "2026-11-24T16:30:00+08:00",
          summary = {
            ID = "22222222-aaaa-bbbb-cccc-000000000002",
            Title = "",
            Preview = "Newest\n  fallback preview",
            NumSteps = 45,
            AppDataDir = "antigravity-cli",
            WorkspaceURIs = { encoded_a, "file:///tmp/staged-plugin-workspace" },
          },
        },
        ["33333333-aaaa-bbbb-cccc-000000000003"] = {
          is_internal = false,
          last_modified_time = "2026-11-24T17:00:00+08:00",
          summary = {
            ID = "33333333-aaaa-bbbb-cccc-000000000003",
            Title = "Other Repo Thread",
            NumSteps = 99,
            AppDataDir = "antigravity-cli",
            WorkspaceURIs = { "file://" .. real_b },
          },
        },
        ["44444444-aaaa-bbbb-cccc-000000000004"] = {
          is_internal = true,
          last_modified_time = "2026-11-24T17:05:00+08:00",
          summary = {
            ID = "44444444-aaaa-bbbb-cccc-000000000004",
            Title = "Internal Subagent",
            NumSteps = 30,
            AppDataDir = "antigravity-cli",
            WorkspaceURIs = { encoded_a },
          },
        },
        ["55555555-aaaa-bbbb-cccc-000000000005"] = {
          is_internal = false,
          last_modified_time = "2026-11-24T17:10:00+08:00",
          summary = {
            ID = "55555555-aaaa-bbbb-cccc-000000000005",
            Title = "Zero Step Empty",
            NumSteps = 0,
            AppDataDir = "antigravity-cli",
            WorkspaceURIs = { encoded_a },
          },
        },
        ["66666666-aaaa-bbbb-cccc-000000000006"] = {
          is_internal = false,
          last_modified_time = "2026-11-24T17:15:00+08:00",
          summary = {
            ID = "66666666-aaaa-bbbb-cccc-000000000006",
            Title = "Desktop App Thread",
            NumSteps = 8,
            AppDataDir = "antigravity",
            WorkspaceURIs = { encoded_a },
          },
        },
      },
    }) }, agy_data .. "/cache/conversation_metadata.json")

    agy_history._data_dir = agy_data
    local listed = agy_history.sessions(repo_a)
    t.eq(#listed, 2, "Antigravity history isolates sessions belonging to the requested workspace")
    t.eq(listed[1].id, "22222222-aaaa-bbbb-cccc-000000000002", "newest workspace session sorts first")
    t.eq(listed[1].title, "Newest fallback preview", "empty title falls back to single-line preview")
    t.eq(listed[2].id, "11111111-aaaa-bbbb-cccc-000000000001", "older session in same workspace sorts second")
    t.eq(#agy_history.sessions(repo_empty), 0, "workspace with no matching sessions returns empty")

    local restore_agy = require("agent_workbench.options")._patch({
      native = { antigravity = { command = agy_stub, args = { "--settings", '{"altScreenMode":"always","pickerGrouping":"grouped"}' }, wrap_tmux = false } },
      plugin_dirs = {},
    })
    config._set_providers({
      { name = "antigravity", label = "Antigravity", tui = { kind = "antigravity" } },
    })

    local real_select, real_notify = vim.ui.select, vim.notify
    local notes, pending_select = {}, nil
    vim.notify = function(msg, level) notes[#notes + 1] = { msg = tostring(msg), level = level } end
    vim.ui.select = function(items, opts, on_choice)
      pending_select = { items = items, opts = opts, on_choice = on_choice }
    end

    local ai = require("agent_workbench")
    vim.cmd("tabnew")
    local empty_file = repo_empty .. "/main.lua"
    vim.fn.writefile({ "return 1" }, empty_file)
    vim.cmd.edit(vim.fn.fnameescape(empty_file))
    ai.resume()
    t.eq(pending_select, nil, "empty workspace opens no session picker")
    t.eq(ai.session("antigravity"), nil, "empty workspace starts no blank Antigravity terminal")
    t.ok(notes[#notes] and notes[#notes].msg:find("No Antigravity sessions found", 1, true) ~= nil,
      "empty workspace explains there are no sessions for this directory")

    local file_a = repo_a .. "/init.lua"
    vim.fn.writefile({ "return true" }, file_a)
    vim.cmd.edit(vim.fn.fnameescape(file_a))
    notes = {}
    ai.resume()
    t.ok(pending_select ~= nil and pending_select.opts.kind == "ai_antigravity_resume",
      "<leader>ar opens the Antigravity session picker")
    t.eq(#pending_select.items, 2, "picker offers only the current project's sessions")
    t.eq(ai.session("antigravity"), nil, "Antigravity stays unstarted while the picker is open")

    -- Cancel starts nothing.
    local cancel_cb = pending_select.on_choice
    pending_select = nil
    cancel_cb(nil)
    t.eq(ai.session("antigravity"), nil, "cancelling the resume picker starts no session")

    -- Async selection (as Snacks.picker runs it) spawns agy --conversation <id> in repo_a.
    notes = {}
    ai.resume()
    local chosen = pending_select.items[1]
    local confirm_cb = pending_select.on_choice
    pending_select = nil
    vim.schedule(function() confirm_cb(chosen) end)
    t.ok(vim.wait(2000, function()
      local s = ai.session("antigravity")
      return s ~= nil and s.alive
    end, 20), "confirming a session starts Antigravity")
    t.ok(vim.wait(2000, function() return vim.fn.filereadable(argv_out) == 1 end, 20),
      "stand-in agy recorded its invocation")
    local recorded = vim.fn.readfile(argv_out)
    t.eq(vim.uv.fs_realpath(recorded[1]) or recorded[1], real_a, "resumed Antigravity runs in the project root")
    t.eq({ recorded[#recorded - 1], recorded[#recorded] }, { "--conversation", chosen.id },
      "resumed Antigravity receives --conversation <selected-id>")
    local started_notes = vim.tbl_filter(function(n)
      return n.msg:find("Started Antigravity · terminal · subscription to resume a session", 1, true) ~= nil
    end, notes)
    t.eq(#started_notes, 1, "async picker resume announces startup once")

    -- Pressing <leader>ar while already active focuses the session without opening a picker.
    notes = {}
    vim.cmd("stopinsert")
    vim.cmd("wincmd h")
    ai.resume()
    t.eq(pending_select, nil, "<leader>ar on a running Antigravity session opens no picker")
    t.ok(notes[#notes] and notes[#notes].msg:find("An Antigravity session is already active", 1, true) ~= nil,
      "<leader>ar on a running Antigravity session explains why")

    vim.cmd("stopinsert")
    assert(ai.stop("antigravity"))
    vim.cmd("tabclose!")
    vim.ui.select, vim.notify = real_select, real_notify
    agy_history._data_dir = nil
    restore_agy()
    vim.fn.delete(fixture_root, "rf")
  end

  if not prev then
    config._set_providers(require("agent_workbench").options().providers)
  end
end

t.eq(require("lazy.core.config").plugins["claudecode.nvim"], nil, "no Claude integration is installed by this config")
t.eq(vim.fn.exists(":ClaudeCode"), 0, "no Claude launch command remains")
local file = vim.api.nvim_create_buf(false, true)
vim.b[file].agent_workbench = { id = "native:codex", kind = "codex" }
t.eq(ai_term.agent_of(file), nil, "a file cannot become an agent terminal from metadata alone")
pcall(vim.fn.jobstop, vim.bo[plain].channel)
pcall(vim.api.nvim_buf_delete, plain, { force = true })
vim.fn.delete(vim.fs.dirname(bin), "rf")
t.done()
