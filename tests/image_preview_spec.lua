-- Floating thumbnail cards and `[Image #N]` badges for native TUI panels and
-- the prompt editor (local-plugin/agent-workbench.nvim/lua/agent_workbench/image_preview.lua).
local t = dofile("tests/helper.lua")

local preview = require("agent_workbench.image_preview")
local clipboard = require("agent_workbench.clipboard")
local editor = require("agent_workbench.editor")
local config = require("agent_workbench.state")

---------------------------------------------------------------------------
-- 1. Headless default: completely inert unless a UI is attached
---------------------------------------------------------------------------
t.eq(preview._ui_active(), false, "headless runs report no UI attached by default")
t.eq(preview.format_bytes(0), "", "zero-byte size renders empty")
t.eq(preview.format_bytes(512), "512 B", "sub-KB size renders in bytes")
t.eq(preview.format_bytes(39812), "39 KB", "kilobyte size rounds cleanly")

-- Stub clipboard and terminal PTY stand-in so the real system clipboard is untouched.
local fixture_png = vim.fn.fnamemodify("tests/fixtures/pixel.png", ":p")
local png_bytes = table.concat(vim.fn.readfile(fixture_png, "b"), "\n")
local has_image = true
local saved_files = {}

local real_has_image = clipboard.has_image
local real_save_image = clipboard.save_image
local real_restore_image = clipboard.restore_image

clipboard.has_image = function() return has_image end
clipboard.save_image = function(target)
  local src = assert(io.open(fixture_png, "rb"))
  local raw = src:read("*a")
  src:close()
  local dst = assert(io.open(target, "wb"))
  dst:write(raw)
  dst:close()
  saved_files[#saved_files + 1] = target
  return true
end
clipboard.restore_image = function(path)
  return vim.uv.fs_stat(path) ~= nil
end

local _ = png_bytes -- keep reference clear

-- Stand-in CLI: offline `cat`, matching ai_terminal_spec and editor_spec.
local tmpdir = vim.fn.tempname()
vim.fn.mkdir(tmpdir, "p")
local bin = tmpdir .. "/fake-agent"
vim.fn.writefile({ "#!/bin/sh", "exec cat" }, bin)
vim.fn.setfperm(bin, "rwx------")

local prev_providers = vim.deepcopy(config.providers)
config._set_providers({
  { name = "codex", label = "Codex", tui = { kind = "codex" } },
  { name = "antigravity", label = "Antigravity", tui = { kind = "antigravity" } },
})

local sent_bytes = {}
local real_chan_send = vim.api.nvim_chan_send
vim.api.nvim_chan_send = function(channel, data)
  sent_bytes[channel] = (sent_bytes[channel] or "") .. tostring(data)
  return real_chan_send(channel, data)
end

local function open_agent_panel(kind)
  vim.cmd("rightbelow 60vsplit")
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(win, buf)
  vim.b[buf].agent_workbench = {
    id = "native:" .. kind,
    kind = kind,
    cmd = { bin },
    cwd = tmpdir,
  }
  local chan
  vim.api.nvim_buf_call(buf, function()
    chan = vim.fn.jobstart({ bin }, { term = true })
  end)
  sent_bytes[chan] = ""
  t.ok(chan and chan > 0, kind .. " stand-in PTY started")
  return buf, win, chan
end

local function title_of(win)
  if not (win and vim.api.nvim_win_is_valid(win)) then return nil end
  local cfg = vim.api.nvim_win_get_config(win)
  local title = cfg.title
  if type(title) == "table" then return (title[1] or {})[1] end
  return title
end

local function footer_of(win)
  if not (win and vim.api.nvim_win_is_valid(win)) then return nil end
  local cfg = vim.api.nvim_win_get_config(win)
  local footer = cfg.footer
  if type(footer) == "table" then return (footer[1] or {})[1] end
  return footer
end

---------------------------------------------------------------------------
-- 2. Headless safety on `<C-v>` when `_force_ui` is false
---------------------------------------------------------------------------
do
  local buf, _, chan = open_agent_panel("codex")
  t.ok(vim.fn.maparg("<C-v>", "t", false, true).buffer == 1, "<C-v> is buffer-local on agent terminal")
  t.ok(vim.fn.maparg("<M-p>", "t", false, true).buffer == 1, "<M-p> is buffer-local in Terminal-mode")
  t.ok(vim.fn.maparg(",p", "n", false, true).buffer == 1, ",p is buffer-local in Normal mode")
  t.ok(vim.fn.maparg(",d", "n", false, true).buffer == 1, ",d is buffer-local in Normal mode")
  t.ok(vim.fn.maparg(",P", "n", false, true).buffer ~= 1, ",P is not mapped on agent terminal (no CodeDiff collision)")
  t.ok(vim.fn.maparg("[i", "n", false, true).buffer ~= 1, "[i stays global indent-change motion")

  saved_files = {}
  preview.paste_terminal(buf)
  t.eq(saved_files, {}, "headless <C-v> snapshots nothing when UI is inactive")
  t.eq(preview._inspect(buf), nil, "headless <C-v> opens no preview entry")
  t.eq(sent_bytes[chan], "\22", "headless <C-v> still forwards raw 0x16 to the child PTY")

  pcall(vim.fn.jobstop, chan)
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
  vim.cmd("silent! only")
end

---------------------------------------------------------------------------
-- 3. UI active + graphics renderer: TUI `<C-v>` thumbnail card, fold, cycle,
--    hide/show, and `<CR>` auto-dismiss
---------------------------------------------------------------------------
local attached_renders = {}
local cleaned_bufs = 0
local gfx_supported = true

preview._force_ui = true
preview.SUBMIT_SETTLE_MS = 40
preview._renderer = {
  detect = function(cb) cb(gfx_supported) end,
  supports_file = function() return true end,
  attach = function(buf, path)
    attached_renders[#attached_renders + 1] = { buf = buf, path = path }
    return {
      close = function() cleaned_bufs = cleaned_bufs + 1 end,
    }
  end,
  clean = function() cleaned_bufs = cleaned_bufs + 1 end,
}

do
  local buf, panel_win, chan = open_agent_panel("codex")

  -- Empty clipboard forwards 0x16 without opening a card.
  has_image = false
  saved_files = {}
  preview.paste_terminal(buf)
  t.eq(preview._inspect(buf), nil, "non-image clipboard opens no preview card")
  t.eq(saved_files, {}, "non-image clipboard writes no snapshot file")

  -- Image #1 on clipboard: snapshots PNG, forwards 0x16, opens expanded thumbnail card.
  has_image = true
  preview.paste_terminal(buf)
  local s1 = preview._inspect(buf)
  t.ok(s1 ~= nil and s1.count == 1 and s1.index == 1 and not s1.folded, "first <C-v> tracks Image #1 expanded")
  t.ok(s1.win ~= nil and vim.api.nvim_win_is_valid(s1.win), "thumbnail float is open")
  local cfg1 = vim.api.nvim_win_get_config(s1.win)
  t.eq(cfg1.relative, "win", "terminal card is anchored to the panel window")
  t.eq(cfg1.win, panel_win, "terminal card points at the agent panel window")
  t.eq(cfg1.focusable, false, "terminal card never steals focus")
  t.ok(cfg1.height >= 4, "graphics-capable terminal opens expanded multi-row thumbnail card")
  t.ok((title_of(s1.win) or ""):find("[Image #1]", 1, true) ~= nil, "card title highlights [Image #1]")
  t.eq(#attached_renders, 1, "renderer attached PNG #1")
  t.eq(attached_renders[1].path, s1.paths[1], "renderer received staged PNG #1 path")

  -- Image #2 on clipboard: updates badge to [Image #2] (2/2) and cycles cleanly.
  preview.paste_terminal(buf)
  local s2 = preview._inspect(buf)
  t.eq({ s2.count, s2.index }, { 2, 2 }, "second <C-v> advances to Image #2 of 2")
  t.ok((title_of(s2.win) or ""):find("[Image #2] (2/2)", 1, true) ~= nil, "card title shows [Image #2] (2/2)")
  t.ok((footer_of(s2.win) or ""):find("<M-n>", 1, true) ~= nil, "multi-image footer advertises <M-n> cycling")

  t.eq(preview.cycle(buf, 1), true, "<M-n> cycles back to Image #1")
  t.ok((title_of(preview._inspect(buf).win) or ""):find("[Image #1] (1/2)", 1, true) ~= nil,
    "cycling wraps to [Image #1] (1/2)")

  -- Which-key classifies `,p` and `,d` under `Agent · image preview` in agent terminals.
  require("lazy").load({ plugins = { "which-key.nvim" } })
  vim.api.nvim_exec_autocmds("VimEnter", { modeline = false })
  vim.wait(500, function() return require("which-key.config").loaded end)
  do
    vim.api.nvim_set_current_win(panel_win)
    local wk_mode = require("which-key.buf").get({ mode = "n", update = true })
    local comma = wk_mode.tree:find(",")
    local View = require("which-key.view")
    local rows, cur, under = {}, nil, {}
    for _, child in ipairs(comma:children()) do rows[#rows + 1] = View.item(child, { parent = comma }) end
    View.sort(rows)
    for _, r in ipairs(rows) do
      if r.key == "" then cur = r.desc:gsub("^── ", "") else under[r.keys] = cur end
    end
    t.eq({ under[",p"], under[",d"] }, { "Agent · image preview", "Agent · image preview" },
      ",p and ,d sit under Agent · image preview in agent terminals")
    t.ok(under[",P"] == nil, "no ,P CodeDiff collision in agent terminals")
  end

  -- `<M-p>` / `,p` folds to a 1-row pill without dropping pending attachments, then expands back.
  t.eq(preview.toggle(buf), true, "<M-p> folds the card")
  local folded = preview._inspect(buf)
  t.eq({ folded.folded, vim.api.nvim_win_get_config(folded.win).height }, { true, 1 },
    "folded card shrinks to a 1-row pill")
  local pill_line = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(folded.win), 0, 1, false)[1] or ""
  t.ok(pill_line:find("[Image #1..#2]", 1, true) ~= nil, "folded pill keeps [Image #1..#2] summary visible")

  t.eq(preview.toggle(buf), true, "second <M-p> expands the thumbnail card back")
  t.ok(vim.api.nvim_win_get_config(preview._inspect(buf).win).height >= 4, "expanded card restores thumbnail height")

  -- Hiding the panel window closes the float so nothing lingers over code splits;
  -- re-showing the buffer in a split re-attaches the float cleanly.
  vim.api.nvim_win_close(panel_win, true)
  vim.wait(80, function() return preview._inspect(buf).win == nil end, 10)
  t.eq(preview._inspect(buf).win, nil, "hiding the agent panel closes the overlay float")
  t.eq(preview._inspect(buf).count, 2, "unsent attachments survive panel hide")

  vim.cmd("rightbelow 60vsplit")
  local reopened_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(reopened_win, buf)
  preview.refresh_all()
  local restored = preview._inspect(buf)
  t.ok(restored.win ~= nil and vim.api.nvim_win_get_config(restored.win).win == reopened_win,
    "re-showing the panel re-anchors the preview float")

  -- Submitting (`<CR>` in Terminal-mode) clears the card and deletes snapshot PNGs.
  local paths_before = vim.deepcopy(restored.paths)
  local real_mode = vim.api.nvim_get_mode
  vim.api.nvim_get_mode = function() return { mode = "t", blocking = false } end
  preview._on_key("\r", "\r")
  vim.api.nvim_get_mode = real_mode
  t.ok(vim.wait(400, function() return preview._inspect(buf) == nil end, 10),
    "Terminal-mode <CR> dismisses Codex's pending preview card")
  for _, p in ipairs(paths_before) do
    t.eq(vim.fn.filereadable(p), 0, "snapshot PNG deleted after submit: " .. p)
  end

  pcall(vim.fn.jobstop, chan)
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
  vim.cmd("silent! only")
end

---------------------------------------------------------------------------
-- 4. Antigravity (`agy`): `<CR>` on @file completion keeps preview while
--    `N media attached` remains on screen, and clears once submitted;
--    non-graphics terminal falls back to 1-row `[Image #1]` badge.
---------------------------------------------------------------------------
do
  gfx_supported = false
  local agy_buf = vim.api.nvim_create_buf(false, true)
  -- Test against a realistic non-terminal scratch first? No, `paste_terminal`
  -- needs a channel, while `adopt_terminal` works on any valid panel buffer!
  -- Let's use a real panel split + modifiable copy check via `agy` PTY output.
  vim.cmd("rightbelow 60vsplit")
  local agy_win = vim.api.nvim_get_current_win()
  local echo_bin = tmpdir .. "/agy-sim"
  vim.fn.writefile({
    "#!/bin/sh",
    "printf '📎 1 media attached (clipboard, 39 KB, image/png)  (ctrl+o to expand)\\n> @readme\\n'",
    "cat >/dev/null",
  }, echo_bin)
  vim.fn.setfperm(echo_bin, "rwx------")
  vim.api.nvim_win_set_buf(agy_win, agy_buf)
  vim.b[agy_buf].agent_workbench = { id = "native:antigravity", kind = "antigravity", cmd = { echo_bin }, cwd = tmpdir }
  local chan
  vim.api.nvim_buf_call(agy_buf, function()
    chan = vim.fn.jobstart({ echo_bin }, { term = true })
  end)
  t.ok(vim.wait(1000, function()
    local lines = table.concat(vim.api.nvim_buf_get_lines(agy_buf, 0, -1, false), "\n")
    return lines:find("1 media attached", 1, true) ~= nil
  end, 20), "simulated agy rendered its attachment header")

  preview.paste_terminal(agy_buf)
  local st = preview._inspect(agy_buf)
  t.ok(st ~= nil and st.win ~= nil, "agy <C-v> opens the badge float even without Kitty graphics")
  t.eq(vim.api.nvim_win_get_config(st.win).height, 1, "non-graphics fallback uses compact 1-row badge")
  t.ok((title_of(st.win) or ""):find("[Image #1]", 1, true) ~= nil, "agy fallback badge clearly displays [Image #1]")

  -- While `1 media attached` is still on screen (e.g. `<CR>` accepted @file completion),
  -- `<CR>` must NOT prematurely kill the badge!
  local real_mode = vim.api.nvim_get_mode
  vim.api.nvim_get_mode = function() return { mode = "t", blocking = false } end
  preview._on_key("\r", "\r")
  vim.wait(120, function() return false end)
  t.ok(preview._inspect(agy_buf) ~= nil, "agy preview survives <CR> while `1 media attached` is still unsent")

  -- `<C-c>` clears immediately.
  preview._on_key("\3", vim.keycode("<C-c>"))
  vim.api.nvim_get_mode = real_mode
  t.ok(vim.wait(200, function() return preview._inspect(agy_buf) == nil end, 10),
    "Terminal-mode <C-c> clears agy preview")

  pcall(vim.fn.jobstop, chan)
  pcall(vim.api.nvim_buf_delete, agy_buf, { force = true })
  vim.cmd("silent! only")
  gfx_supported = true
end

---------------------------------------------------------------------------
-- 5. Prompt editor (`<leader>ai` / `editor.open`): companion thumbnail float
--    beside prompt float, modal guard harmony, and handoff to TUI panel
---------------------------------------------------------------------------
do
  local released = {}
  local real_release = editor._release
  editor._release = function(s) released[#released + 1] = s end

  local prompt_dir = tmpdir .. "/editor"
  vim.fn.mkdir(prompt_dir, "p")

  -- Cancel (`<C-c>`) closes both the prompt float and the companion preview float,
  -- and deletes staged PNGs.
  local p1 = prompt_dir .. "/one.md"
  vim.fn.writefile({ "explain this screenshot" }, p1)
  t.eq(editor.open(p1, p1 .. ".done"), "opened", "prompt editor opens")
  vim.wait(150, function() return false end)
  local pwin = vim.api.nvim_get_current_win()
  local pbuf = vim.api.nvim_win_get_buf(pwin)
  t.ok(editor.is_prompt_win(pwin), "focused window is the prompt float")

  vim.cmd.stopinsert()
  t.ok(vim.fn.maparg("<M-p>", "n", false, true).buffer == 1, "<M-p> is buffer-local on prompt float")
  t.ok(vim.fn.maparg("<M-n>", "i", false, true).buffer == 1, "<M-n> is buffer-local in Insert mode on prompt float")
  t.ok(vim.fn.maparg("[i", "n", false, true).buffer ~= 1, "prompt float preserves Markdown [i indent motion")
  vim.fn.maparg("<C-v>", "n", false, true).callback()
  local ps = preview._inspect(pbuf)
  t.ok(ps ~= nil and ps.win ~= nil and vim.api.nvim_win_is_valid(ps.win),
    "<C-v> in prompt editor opens companion thumbnail float")
  t.eq(vim.api.nvim_get_current_win(), pwin, "companion float never steals focus from the modal prompt")
  t.ok((vim.wo[pwin].winbar or ""):find("<M-p> preview", 1, true) ~= nil,
    "prompt winbar reveals <M-p> preview hint once an image is staged")
  local staged_path = ps.paths[1]

  -- Second <C-v> adds <M-n> next hint in winbar; external close of companion float cleans graphics.
  vim.fn.maparg("<C-v>", "n", false, true).callback()
  t.ok((vim.wo[pwin].winbar or ""):find("<M-n> next", 1, true) ~= nil,
    "prompt winbar reveals <M-n> next hint when multiple images are staged")
  local staged_paths = vim.deepcopy(preview._inspect(pbuf).paths)
  local before_clean = cleaned_bufs
  vim.api.nvim_win_close(preview._inspect(pbuf).win, true)
  vim.wait(80, function() return preview._inspect(pbuf).win == nil end, 10)
  t.ok(cleaned_bufs > before_clean, "external close of preview float cleans graphics placement")

  vim.api.nvim_feedkeys(vim.keycode("<C-c>"), "x", false)
  vim.wait(200, function() return preview._inspect(pbuf) == nil end, 10)
  t.eq(preview._inspect(pbuf), nil, "cancelling prompt closes companion preview float")
  for _, sp in ipairs(staged_paths) do
    t.eq(vim.fn.filereadable(sp), 0, "cancelling prompt deletes staged PNG: " .. sp)
  end

  -- Return (`<C-d>`) hands staged PNGs to `attach_images`, which transfers them
  -- into the live Codex TUI panel's preview card until submitted!
  local session, cleanup_codex = t.start_codex(tmpdir)
  local p2 = prompt_dir .. "/two.md"
  vim.fn.writefile({ "ship it" }, p2)
  editor.open(p2, p2 .. ".done")
  vim.wait(150, function() return false end)
  local pwin2 = vim.api.nvim_get_current_win()
  local pbuf2 = vim.api.nvim_win_get_buf(pwin2)
  vim.cmd.stopinsert()
  vim.fn.maparg("<C-v>", "n", false, true).callback()
  local handed_png = preview._inspect(pbuf2).paths[1]

  vim.api.nvim_feedkeys(vim.keycode("<C-d>"), "x", false)
  t.ok(vim.wait(2500, function()
    local ts = preview._inspect(session.buf)
    return ts ~= nil and ts.count == 1
  end, 25), "returning prompt transfers staged image preview onto the live Codex panel")
  local ts = preview._inspect(session.buf)
  t.eq(ts.paths[1], handed_png, "Codex panel adopts the exact staged PNG until the user submits")
  t.eq(vim.fn.filereadable(handed_png), 1, "adopted PNG remains readable for panel preview")

  preview.clear_terminal(session.buf)
  t.eq(vim.fn.filereadable(handed_png), 0, "clearing panel preview deletes the adopted PNG")

  cleanup_codex()
  editor._release = real_release
end

---------------------------------------------------------------------------
-- 6. Real `Snacks.image` boundary: pcall-guarded fallback when placement raises
---------------------------------------------------------------------------
do
  preview._renderer = {
    detect = function(cb) cb(true) end,
    supports_file = function() return true end,
    attach = function() return nil end,
    clean = function() end,
  }
  local buf, _, chan = open_agent_panel("codex")
  has_image = true
  preview.paste_terminal(buf)
  local st = preview._inspect(buf)
  t.ok(st ~= nil and st.win ~= nil, "failed renderer.attach still opens the preview float")
  local fallback_line = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(st.win), 0, 1, false)[1] or ""
  t.ok(fallback_line:find("[Image #1]", 1, true) ~= nil,
    "failed renderer.attach degrades cleanly to the [Image #1] badge text")
  preview.clear_terminal(buf)
  pcall(vim.fn.jobstop, chan)
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
  vim.cmd("silent! only")
end

-- Restore global test seams.
vim.api.nvim_chan_send = real_chan_send
preview._force_ui = false
preview._renderer = nil
clipboard.has_image = real_has_image
clipboard.save_image = real_save_image
clipboard.restore_image = real_restore_image
config._set_providers(prev_providers)
vim.fn.delete(tmpdir, "rf")

t.done()
