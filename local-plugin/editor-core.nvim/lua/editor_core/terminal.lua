local M = {}

local pending_drift_fixes = {}

-- Which terminals run a coding agent is the AI layer's to say: ai.terminal
-- registers its test at startup (local-plugin/agent-workbench.nvim/lua/agent_workbench/terminal.lua). Only those panels get
-- the drift repair below -- applying it to plain shell terminals would make
-- every Normal -> Terminal-mode transition flicker -- and the numbered
-- terminals never hide one. Until a test is registered, no terminal is one.
local is_agent = function(_) return false end

---@param fn fun(buf: integer): boolean
function M.set_agent_test(fn)
  is_agent = fn
end

-- Identifies a native AI agent's :terminal window in the current tabpage, if
-- visible.
local function find_agent_win()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if is_agent(buf) then return win end
  end
end

local RESTORE_DELAY_MS = 25

local function max_topline(win, buf)
  return math.max(1, vim.api.nvim_buf_line_count(buf) - vim.api.nvim_win_get_height(win) + 1)
end

-- Keep a terminal window from scrolling past its last terminal row into empty
-- EndOfBuffer space. Builtin Normal-mode downward scrolling (<ScrollWheelDown>,
-- <C-e>, <C-d>, <PageDown>) allows topline to advance all the way to line('$'),
-- pushing the live bottom row up toward the top of the window.
function M.clamp_scroll(win)
  if not win or not vim.api.nvim_win_is_valid(win) then return end
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].buftype ~= "terminal" or vim.wo[win].wrap then return end
  local max_top = max_topline(win, buf)
  vim.api.nvim_win_call(win, function()
    local view = vim.fn.winsaveview()
    if view.topline > max_top then
      view.topline = max_top
      vim.fn.winrestview(view)
    end
  end)
end

function M.scroll_wheel_down(win, count)
  if not win or not vim.api.nvim_win_is_valid(win) then return end
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].buftype ~= "terminal" or vim.wo[win].wrap then return end
  local step = (tonumber((vim.o.mousescroll or ""):match("ver:(%d+)")) or 3) * (count or 1)
  if step <= 0 then return end
  local max_top = max_topline(win, buf)
  vim.api.nvim_win_call(win, function()
    local view = vim.fn.winsaveview()
    local new_top = math.min(max_top, view.topline + step)
    if new_top > view.topline then
      view.topline = new_top
      if view.lnum < new_top then view.lnum = new_top end
      vim.fn.winrestview(view)
    end
  end)
end

function M.attach_scroll_clamp(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  vim.b[buf].snacks_scroll = false

  vim.keymap.set("n", "<ScrollWheelDown>", function()
    local pos = vim.fn.getmousepos()
    local target = (pos.winid and pos.winid ~= 0) and pos.winid or vim.api.nvim_get_current_win()
    if not vim.api.nvim_win_is_valid(target) then return end
    local tbuf = vim.api.nvim_win_get_buf(target)
    if vim.bo[tbuf].buftype ~= "terminal" or vim.wo[target].wrap then
      local step = (tonumber((vim.o.mousescroll or ""):match("ver:(%d+)")) or 3) * vim.v.count1
      if step > 0 then
        vim.api.nvim_win_call(target, function()
          vim.cmd.normal({ args = { step .. "\5" }, bang = true })
        end)
      end
      return
    end
    M.scroll_wheel_down(target, vim.v.count1)
  end, { buffer = buf, silent = true, desc = "Scroll terminal down" })

  local function step_down(kind, fallback)
    return function()
      local win = vim.api.nvim_get_current_win()
      local wbuf = vim.api.nvim_win_get_buf(win)
      if vim.bo[wbuf].buftype ~= "terminal" or vim.wo[win].wrap then
        vim.cmd.normal({ args = { (vim.v.count > 0 and tostring(vim.v.count) or "") .. fallback }, bang = true })
        return
      end
      local cnt = vim.api.nvim_buf_line_count(wbuf)
      local h = vim.api.nvim_win_get_height(win)
      local max_top = math.max(1, cnt - h + 1)
      local view = vim.fn.winsaveview()
      if kind == "line" then
        local new_top = math.min(max_top, view.topline + vim.v.count1)
        if new_top > view.topline then
          view.topline = new_top
          if view.lnum < new_top then view.lnum = new_top end
          vim.fn.winrestview(view)
        end
        return
      end
      local step
      if kind == "half" then
        if vim.v.count > 0 then vim.wo[win].scroll = math.min(h, vim.v.count) end
        step = vim.v.count > 0 and vim.v.count or vim.wo[win].scroll
      else
        step = math.max(1, h - 2) * vim.v.count1
      end
      local new_top = math.min(max_top, math.max(view.topline, view.topline + step))
      local new_lnum = math.min(cnt, view.lnum + step)
      if new_top ~= view.topline or new_lnum ~= view.lnum then
        view.topline = new_top
        if new_lnum < new_top then new_lnum = new_top end
        view.lnum = new_lnum
        vim.fn.winrestview(view)
      end
    end
  end

  vim.keymap.set("n", "<C-e>", step_down("line", "\5"), { buffer = buf, silent = true, desc = "Scroll terminal line down" })
  vim.keymap.set("n", "<C-d>", step_down("half", "\4"), { buffer = buf, silent = true, desc = "Scroll terminal half-page down" })
  vim.keymap.set("n", "<C-f>", step_down("page", "\6"), { buffer = buf, silent = true, desc = "Scroll terminal page down" })
  vim.keymap.set("n", "<PageDown>", step_down("page", "\6"), { buffer = buf, silent = true, desc = "Scroll terminal page down" })
end

-- Drift fix for a native-agent :terminal window.
-- libvterm's grid only invalidates on shrink, not on grow. Shrinking forces
-- row truncation, which clears the residue cells; growing back restores the
-- original window size after the child TUI has re-rendered to the shrunken size.
--
-- The grow needs real wall-clock delay, not just a hop to the next event-loop
-- tick. Nvim pushes a terminal window's new size down to the pty asynchronously
-- on its internal terminal refresh timer (~10ms). That path is not the redraw
-- path, so forcing `:redraw` does not trigger it either. With `defer_fn(..., 0)`
-- the grow lands before the timer ever fires, so nvim's terminal layer only
-- observes the original size: no pty resize, no SIGWINCH, no TUI repaint. The
-- shrink must survive at least one refresh tick to be seen at all.
--
-- Measured against a child that logs every SIGWINCH: 0ms never propagates,
-- >=10ms always does. 25ms keeps margin over timer jitter while staying short
-- enough that the one-row dip is barely visible.
--
-- Opening the bottom terminal spans several ticks of Snacks reflow and edgy
-- layout, but a manual repair has no such padding. Keeping the shrink alive for
-- 25ms makes both call paths reliably reach the pty.
--
-- See issue #2 for the full mechanism.
function M.fix_drift(win)
  win = win or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(win) then return false end
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].buftype ~= "terminal" then
    vim.notify("fix_drift: target window is not a :terminal", vim.log.levels.WARN)
    return false
  end
  if pending_drift_fixes[win] then return true end

  local height = vim.api.nvim_win_get_height(win)
  if height <= 1 then return false end
  local orig_fh = vim.wo[win].winfixheight
  vim.wo[win].winfixheight = false

  -- Use the window API instead of `:resize`. The Ex command can enter a buffer
  -- modification path while a non-modifiable terminal buffer is current and
  -- fail with E21. nvim_win_set_height only changes the window geometry while
  -- still sending the same SIGWINCH that makes the TUI redraw.
  local ok, err = pcall(vim.api.nvim_win_set_height, win, height - 1)
  if not ok then
    vim.wo[win].winfixheight = orig_fh
    vim.notify("Could not fix terminal TUI drift: " .. tostring(err), vim.log.levels.WARN)
    return false
  end

  pending_drift_fixes[win] = true
  vim.defer_fn(function()
    pending_drift_fixes[win] = nil
    if vim.api.nvim_win_is_valid(win) then
      -- Restore relatively, matching `:resize +1` if some other layout change
      -- happened between the two event-loop ticks.
      local current_height = vim.api.nvim_win_get_height(win)
      pcall(vim.api.nvim_win_set_height, win, current_height + 1)
      vim.wo[win].winfixheight = orig_fh
    end
  end, RESTORE_DELAY_MS)
  return true
end

local function count_term_wins()
  local n = 0
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].buftype == "terminal" then n = n + 1 end
  end
  return n
end

local SHAPES = {
  bottom = { position = "bottom", height = 25 },
  float = {
    position = "float",
    width = 0.85,
    height = 0.8,
    border = "rounded",
    title_pos = "center",
  },
}

---Do terminals float in this configuration?
---
---One shape, chosen once -- not switchable at runtime. Snacks decides a window's
---shape when it opens one; edgy must agree across each hide, show and relayout.
---Override in init.lua with `vim.g.terminal_position = "bottom"`.
---
---edgy asks this: it claims every non-agent `snacks_terminal` for its bottom
---edge, which would drag a float into the layout the moment it opens.
---@return boolean
function M.floats()
  return vim.g.terminal_position ~= "bottom"
end

---Which terminal was last acted on, so <C-/> after closing terminal 3 comes
---back to terminal 3 rather than starting over at 1.
local last_id = nil

-- Floats stack, so showing a second terminal leaves the first sitting behind it.
-- Closing the top one then reveals the other, which reads as jumping between
-- terminals rather than dismissing the one in front of you. Docked terminals do
-- not need this: edgy already gives them one shared slot.
---@param keep integer the terminal that is about to be shown
local function hide_other_floats(keep)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    local info = vim.bo[buf].buftype == "terminal" and vim.b[buf].snacks_terminal
    if
      info
      and info.id
      and info.id ~= keep
      and vim.api.nvim_win_get_config(win).relative ~= ""
      and not is_agent(buf)
    then
      local other = Snacks.terminal.get(nil, { count = info.id, create = false })
      if other and other:win_valid() then other:hide() end
    end
  end
end

---@param count integer
---@return table win options for this terminal in the configured shape
local function win_opts_for(count)
  local floating = M.floats()
  local opts = vim.deepcopy(SHAPES[floating and "float" or "bottom"])
  if floating then
    -- Snacks leaves float titles empty; no tabline or statusline names the
    -- terminal there, so its number belongs in the border.
    opts.title = (" Terminal %d "):format(count)
  end
  return opts
end

-- Repair the agent pane after a docked terminal reshuffles the layout (issue
-- #2). Only on open -- close reshuffles too, but the flash isn't worth it. The
-- `defer_fn(..., 0)` lets Snacks' reflow and edgy's autocmd cascade finish
-- first; non-zero delays just add visible flicker. Floats never reflow the
-- window tree, so they need no repair.
---@param before integer terminal-window count before the operation
local function repair_agent_after_dock(before)
  if M.floats() then return end
  vim.defer_fn(function()
    if count_term_wins() > before then
      local agent_win = find_agent_win()
      if agent_win then M.fix_drift(agent_win) end
    end
  end, 0)
end

---Show terminal `count` and put the cursor in it. Never closes anything.
---
---This is what terminal-local `,1`..`,9` do in Normal mode. They choose
---which terminal you are looking at, so pressing its own number has to
---leave it open -- closing is <C-/>'s single job.
---@param count integer
function M.focus(count)
  last_id = count

  local before = count_term_wins()
  hide_other_floats(count)

  local term = Snacks.terminal.get(nil, { count = count, win = win_opts_for(count) })
  if term then
    if not term:win_valid() then term:show() end
    if term:win_valid() then vim.api.nvim_set_current_win(term.win) end
  end

  repair_agent_after_dock(before)
end

---Open or close a terminal -- the only thing that closes one.
---Terminals are identified by `count`: Snacks derives identity from
---cmd/cwd/env/count and never reads `opts.id`.
---@param count integer? which terminal; nil resolves to the current one, an
---explicit v:count, or the one you were last in
function M.toggle(count)
  if not count then
    local buf = vim.api.nvim_get_current_buf()
    local info = vim.bo[buf].buftype == "terminal" and vim.b[buf].snacks_terminal

    if info and info.id then
      -- Sitting in a terminal: this is the one you mean. Without it, an
      -- unnumbered toggle always meant terminal 1, so pressing it inside
      -- terminal 3 dismissed a different terminal entirely.
      count = info.id
    elseif vim.v.count > 0 then
      -- `3<C-/>`. v:count is 0 when nothing was typed, which is the only way to
      -- tell a deliberate "1" from no count at all.
      count = vim.v.count
    else
      count = last_id
    end
  end

  count = count or vim.v.count1

  -- Showing but not focused: go to it rather than close it. Dismissing a window
  -- you are not looking at is a surprise, and pressing again -- now from inside
  -- it -- closes it, so nothing is lost.
  local existing = Snacks.terminal.get(nil, { count = count, create = false })
  if
    existing
    and existing:win_valid()
    and vim.api.nvim_get_current_win() ~= existing.win
  then
    M.focus(count)
    return
  end

  last_id = count

  local before = count_term_wins()
  hide_other_floats(count)

  Snacks.terminal(nil, { count = count, win = win_opts_for(count) })

  repair_agent_after_dock(before)
end

return M
