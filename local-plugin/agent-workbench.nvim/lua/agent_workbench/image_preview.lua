---@module "agent_workbench.image_preview"
---Floating thumbnail cards and `[Image #N]` badges for native TUI panels and
---the prompt editor.
---
---Embedded `:terminal` buffers (`libvterm` + Codex's inner `tmux`) strip raw
---Kitty Graphics sequences from child CLIs, while `agy` renders only a dim
---attachment summary without an inline `[Image #1]` token. Rendering staged
---clipboard snapshots in a non-focusable host float uses Neovim's own window
---grid (via `Snacks.image` Unicode placeholders when available, or a compact
---badge fallback), so splits clip cleanly, panels hide without ghost pixels,
---and headless runs stay completely inert.

local M = {}

local api = vim.api

-- Delay before checking whether `<CR>` submitted the prompt or merely accepted
-- an inline completion item in the TUI.
M.SUBMIT_SETTLE_MS = 180

-- Specs may flip `_force_ui` and supply `_renderer` without attaching a real UI
-- or spawning `magick` / terminal escape probes.
M._force_ui = false
M._renderer = nil

local CARD_ZINDEX_PANEL = 45
local CARD_ZINDEX_PROMPT = 50

local terms = {} ---@type table<integer, table>
local prompts = {} ---@type table<integer, table>
local seq = 0
local key_ns = nil
local augroup = nil
local highlight_ready = false

---@return boolean
function M._ui_active()
  return M._force_ui == true or #api.nvim_list_uis() > 0
end

local function ensure_highlights()
  if highlight_ready then return end
  highlight_ready = true
  api.nvim_set_hl(0, "AgentWorkbenchImageBadge", { link = "DiagnosticInfo", default = true })
  api.nvim_set_hl(0, "AgentWorkbenchImageHint", { link = "Comment", default = true })
end

---@param bytes integer?
---@return string
function M.format_bytes(bytes)
  if type(bytes) ~= "number" or bytes <= 0 then return "" end
  if bytes < 1024 then return ("%d B"):format(bytes) end
  if bytes < 1024 * 1024 then return ("%d KB"):format(math.max(1, math.floor(bytes / 1024 + 0.5))) end
  return ("%.1f MB"):format(bytes / (1024 * 1024))
end

---@return table|nil
local function resolve_renderer()
  if not M._ui_active() then return nil end
  if M._renderer ~= nil then return M._renderer or nil end
  local snacks = rawget(_G, "Snacks") or package.loaded["snacks"]
  if type(snacks) ~= "table" or not snacks.image then return nil end
  if snacks.image.config and snacks.image.config.enabled == false then return nil end
  return {
    detect = function(cb)
      snacks.image.terminal.detect(function()
        local supported = snacks.image.terminal.env().supported == true
        cb(supported)
      end)
    end,
    supports_file = function(path)
      return snacks.image.supports_file(path) == true
    end,
    attach = function(buf, path)
      return snacks.image.buf._attach(buf, { src = path })
    end,
    clean = function(buf)
      pcall(snacks.image.placement.clean, buf)
    end,
  }
end

---@param entry table
local function clean_graphics(entry)
  if entry.placement and type(entry.placement.close) == "function" then
    pcall(entry.placement.close, entry.placement)
  end
  entry.placement = nil
  if entry.card_buf and api.nvim_buf_is_valid(entry.card_buf) then
    local renderer = resolve_renderer()
    if renderer and renderer.clean then pcall(renderer.clean, entry.card_buf) end
  end
end

---@param entry table
local function close_card_win(entry)
  entry.render_token = (entry.render_token or 0) + 1
  entry._last_cfg = nil
  entry._last_render = nil
  clean_graphics(entry)
  if entry.card_win and api.nvim_win_is_valid(entry.card_win) then
    pcall(api.nvim_win_close, entry.card_win, true)
  end
  entry.card_win = nil
end

---@param entry table
---@param delete_files boolean?
local function destroy_entry(entry, delete_files)
  if not entry then return end
  close_card_win(entry)
  if entry.card_buf and api.nvim_buf_is_valid(entry.card_buf) then
    pcall(api.nvim_buf_delete, entry.card_buf, { force = true })
  end
  entry.card_buf = nil
  if delete_files and entry.owned_files then
    for _, item in ipairs(entry.items or {}) do
      if item.path then pcall(vim.fn.delete, item.path) end
    end
  end
  entry.items = {}
end

---@param entry table
---@return integer
local function ensure_card_buf(entry)
  if entry.card_buf and api.nvim_buf_is_valid(entry.card_buf) then
    return entry.card_buf
  end
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].modifiable = false
  vim.b[buf].agent_image_preview = true
  entry.card_buf = buf
  return buf
end

---@param entry table
---@param lines string[]
local function set_card_lines(entry, lines)
  local buf = ensure_card_buf(entry)
  vim.bo[buf].modifiable = true
  vim.bo[buf].filetype = "agent_image_badge"
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
end

---@param entry table
---@return string
local function title_text(entry)
  local count = #entry.items
  local idx = math.max(1, math.min(entry.index or count, count))
  entry.index = idx
  local item = entry.items[idx]
  local sz = M.format_bytes(item and item.bytes)
  local suffix = sz ~= "" and (" · " .. sz) or ""
  if count == 1 then
    return (" 󰋩 [Image #1]%s "):format(suffix)
  end
  return (" 󰋩 [Image #%d] (%d/%d)%s "):format(idx, idx, count, suffix)
end

---@param entry table
---@param can_expand boolean
---@param is_prompt boolean
---@return string
local function footer_text(entry, can_expand, is_prompt)
  local parts = {}
  if #entry.items > 1 then
    parts[#parts + 1] = "<M-n> next"
  end
  if can_expand then
    parts[#parts + 1] = entry.folded and "<M-p> show" or "<M-p> fold"
  end
  if not is_prompt then
    parts[#parts + 1] = "<M-x> clear"
  end
  if #parts == 0 then return " attached " end
  return " " .. table.concat(parts, " · ") .. " "
end

---@param entry table
---@return string
local function badge_line(entry)
  local total = 0
  for _, item in ipairs(entry.items) do
    total = total + (item.bytes or 0)
  end
  local sz = M.format_bytes(total)
  local suffix = sz ~= "" and (" · " .. sz) or ""
  if #entry.items == 1 then
    return ("  [Image #1]%s ready"):format(suffix)
  end
  return ("  [Image #1..#%d]%s ready"):format(#entry.items, suffix)
end

---@param entry table
---@param layout fun(expanded: boolean, min_w: integer): table|nil
---@param is_prompt boolean
local function open_or_update(entry, layout, is_prompt)
  if not M._ui_active() or #entry.items == 0 then
    close_card_win(entry)
    return
  end
  ensure_highlights()
  local title = title_text(entry)
  local line = badge_line(entry)
  local renderer = resolve_renderer()
  local item = entry.items[entry.index]
  local file_ok = renderer ~= nil and item ~= nil
    and (not renderer.supports_file or renderer.supports_file(item.path))

  local function apply(gfx_supported)
    local can_expand = gfx_supported == true and file_ok
    local expanded = can_expand and not entry.folded
    local footer = footer_text(entry, can_expand, is_prompt)
    local min_w = math.max(
      vim.fn.strdisplaywidth(title) + 2,
      vim.fn.strdisplaywidth(footer) + 2,
      expanded and 22 or (vim.fn.strdisplaywidth(line) + 2)
    )
    local geo = layout(expanded, min_w)
    if not geo then
      close_card_win(entry)
      return
    end

    local buf = ensure_card_buf(entry)
    local win_cfg = {
      relative = geo.relative,
      win = geo.win,
      row = geo.row,
      col = geo.col,
      width = geo.width,
      height = geo.height,
      border = "rounded",
      title = { { title, "AgentWorkbenchImageBadge" } },
      title_pos = "center",
      footer = { { footer, "AgentWorkbenchImageHint" } },
      footer_pos = "center",
      zindex = geo.zindex,
    }

    local cfg_sig = {
      relative = geo.relative,
      win = geo.win,
      row = geo.row,
      col = geo.col,
      width = geo.width,
      height = geo.height,
      title = title,
      footer = footer,
      zindex = geo.zindex,
    }

    if entry.card_win and api.nvim_win_is_valid(entry.card_win) then
      if not vim.deep_equal(entry._last_cfg, cfg_sig) then
        local ok = pcall(api.nvim_win_set_config, entry.card_win, win_cfg)
        if not ok then
          close_card_win(entry)
        else
          entry._last_cfg = cfg_sig
        end
      end
    end
    if not (entry.card_win and api.nvim_win_is_valid(entry.card_win)) then
      local open_cfg = vim.tbl_extend("force", win_cfg, {
        focusable = false,
        style = "minimal",
        noautocmd = true,
      })
      local ok, win = pcall(api.nvim_open_win, buf, false, open_cfg)
      if not ok or not win then return end
      entry.card_win = win
      entry._last_cfg = cfg_sig
      entry._last_render = nil
      vim.wo[win].winblend = 0
      vim.wo[win].wrap = false
      vim.wo[win].number = false
      vim.wo[win].relativenumber = false
      vim.wo[win].signcolumn = "no"
      vim.wo[win].foldcolumn = "0"
      vim.wo[win].cursorline = false
    end

    local render_sig = {
      win = entry.card_win,
      expanded = expanded,
      path = expanded and item and item.path or nil,
      line = not expanded and line or nil,
      width = geo.width,
      height = geo.height,
    }
    if not vim.deep_equal(entry._last_render, render_sig) then
      clean_graphics(entry)
      if expanded and renderer and renderer.attach then
        set_card_lines(entry, { "" })
        entry.placement = renderer.attach(buf, item.path)
      else
        set_card_lines(entry, { line })
      end
      entry._last_render = render_sig
    end
  end

  entry.render_token = (entry.render_token or 0) + 1
  local token = entry.render_token

  if not file_ok then
    apply(false)
    return
  end

  if renderer.detect then
    renderer.detect(function(supported)
      if entry.render_token ~= token then return end
      if #entry.items == 0 then return end
      apply(supported == true)
    end)
  else
    apply(true)
  end
end

---@param buf integer
---@return integer|nil
local function find_panel_win(buf)
  if not api.nvim_buf_is_valid(buf) then return nil end
  local tab = api.nvim_get_current_tabpage()
  for _, win in ipairs(api.nvim_tabpage_list_wins(tab)) do
    if api.nvim_win_is_valid(win)
      and api.nvim_win_get_config(win).relative == ""
      and api.nvim_win_get_buf(win) == buf
    then
      return win
    end
  end
  return nil
end

---@param buf integer
local function render_terminal(buf)
  local entry = terms[buf]
  if not entry or #entry.items == 0 then return end
  open_or_update(entry, function(expanded, min_w)
    local panel_win = find_panel_win(buf)
    if not panel_win then return nil end
    local win_w = api.nvim_win_get_width(panel_win)
    local win_h = api.nvim_win_get_height(panel_win)
    if win_w < 16 or win_h < 4 then return nil end
    local max_w = math.max(14, win_w - 4)
    local width = expanded
      and math.min(max_w, math.max(min_w, math.min(30, math.floor(win_w * 0.44))))
      or math.min(max_w, min_w)
    local height = expanded
      and math.max(4, math.min(9, math.min(win_h - 4, math.floor(win_h * 0.24))))
      or 1
    return {
      relative = "win",
      win = panel_win,
      row = 0,
      col = math.max(0, win_w - width - 2),
      width = width,
      height = height,
      zindex = CARD_ZINDEX_PANEL,
    }
  end, false)
end

---@param buf integer
local function render_prompt(buf)
  local entry = prompts[buf]
  if not entry or #entry.items == 0 then return end
  open_or_update(entry, function(expanded, min_w)
    local pwin = entry.prompt_win
    if not (pwin and api.nvim_win_is_valid(pwin)) then return nil end
    if api.nvim_win_get_tabpage(pwin) ~= api.nvim_get_current_tabpage() then return nil end
    local cfg = api.nvim_win_get_config(pwin)
    local p_row = type(cfg.row) == "table" and cfg.row[false] or tonumber(cfg.row) or 0
    local p_col = type(cfg.col) == "table" and cfg.col[false] or tonumber(cfg.col) or 0
    local p_w = cfg.width or api.nvim_win_get_width(pwin)
    local p_h = cfg.height or api.nvim_win_get_height(pwin)
    local zindex = cfg.zindex or CARD_ZINDEX_PROMPT

    local cols, lines = vim.o.columns, vim.o.lines
    local want_w = expanded and math.max(min_w, 28) or min_w
    local want_h = expanded and 8 or 1

    -- Prefer right beside the prompt float; fall back to below it, then inside
    -- its top-right corner on cramped screens.
    local right_col = p_col + p_w + 3
    local right_avail = cols - right_col - 2
    if right_avail >= math.min(want_w, 22) then
      local width = math.min(want_w, right_avail)
      local height = math.min(want_h, math.max(1, lines - p_row - 4))
      return {
        relative = "editor",
        row = math.max(0, p_row),
        col = right_col,
        width = width,
        height = height,
        zindex = zindex,
      }
    end

    local below_row = p_row + p_h + 2
    local below_avail = lines - below_row - 3
    if below_avail >= (expanded and 5 or 1) then
      local width = math.min(want_w, math.max(16, cols - 4))
      local height = math.min(want_h, below_avail)
      local col = math.max(0, math.min(cols - width - 2, p_col + p_w - width))
      return {
        relative = "editor",
        row = below_row,
        col = col,
        width = width,
        height = height,
        zindex = zindex,
      }
    end

    local width = math.min(want_w, math.max(16, p_w - 4))
    local height = math.min(want_h, math.max(1, p_h - 3))
    return {
      relative = "editor",
      row = math.max(0, p_row + 1),
      col = math.max(0, p_col + p_w - width - 1),
      width = width,
      height = height,
      zindex = zindex + 1,
    }
  end, true)
end

---@param buf integer
---@return boolean
local function agy_still_has_attachment(buf)
  if not api.nvim_buf_is_valid(buf) then return false end
  local all = api.nvim_buf_get_lines(buf, 0, -1, false)
  local last = #all
  while last > 0 and all[last]:match("^%s*$") do
    last = last - 1
  end
  for i = last, math.max(1, last - 16), -1 do
    if all[i]:find("%d+%s+media attached") then return true end
  end
  return false
end

local function on_key(_, typed)
  if next(terms) == nil or not typed or typed == "" then return end
  if api.nvim_get_mode().mode ~= "t" then return end
  local buf = api.nvim_get_current_buf()
  local entry = terms[buf]
  if not entry or #entry.items == 0 then return end
  local key = vim.fn.keytrans(typed)
  if key == "<C-c>" or key == "<C-C>" then
    vim.schedule(function() M.clear_terminal(buf) end)
  elseif key == "<CR>" or key == "<Enter>" or key == "<kEnter>" then
    local info = vim.b[buf].agent_workbench
    local kind = type(info) == "table" and info.kind or nil
    local generation = entry.submit_gen or 0
    entry.submit_gen = generation + 1
    local expected = entry.submit_gen
    vim.defer_fn(function()
      local live = terms[buf]
      if not live or live.submit_gen ~= expected or #live.items == 0 then return end
      if kind == "antigravity" and agy_still_has_attachment(buf) then return end
      M.clear_terminal(buf)
    end, M.SUBMIT_SETTLE_MS)
  end
end
M._on_key = on_key

local function ensure_watchers()
  if not key_ns then
    key_ns = api.nvim_create_namespace("agent_workbench.image_preview.keys")
    vim.on_key(function(k, typed) pcall(on_key, k, typed) end, key_ns)
  end
  if not augroup then
    augroup = api.nvim_create_augroup("agent_workbench_image_preview", { clear = true })
    api.nvim_create_autocmd({ "BufWinEnter", "WinEnter", "TabEnter", "VimResized" }, {
      group = augroup,
      callback = function()
        vim.schedule(function() M.refresh_all() end)
      end,
    })
    api.nvim_create_autocmd("WinResized", {
      group = augroup,
      callback = function()
        local wins = vim.v.event and vim.v.event.windows or {}
        local own = {}
        for _, e in pairs(terms) do if e.card_win then own[e.card_win] = true end end
        for _, e in pairs(prompts) do if e.card_win then own[e.card_win] = true end end
        local external = false
        for _, w in ipairs(wins) do
          if not own[w] then external = true; break end
        end
        if external then
          vim.schedule(function() M.refresh_all() end)
        end
      end,
    })
    api.nvim_create_autocmd("WinClosed", {
      group = augroup,
      callback = function(ev)
        local closed = tonumber(ev.match)
        if not closed then return end
        for buf, entry in pairs(terms) do
          if entry.card_win == closed then
            entry.card_win = nil
          else
            vim.schedule(function()
              if terms[buf] then render_terminal(buf) end
            end)
          end
        end
        for buf, entry in pairs(prompts) do
          if entry.prompt_win == closed then
            M.clear_prompt(buf)
          end
        end
      end,
    })
    api.nvim_create_autocmd("VimLeavePre", {
      group = augroup,
      callback = function()
        for buf in pairs(terms) do M.clear_terminal(buf) end
        for buf in pairs(prompts) do M.clear_prompt(buf) end
      end,
    })
  end
end

---@param buf integer
---@return table
local function ensure_terminal_entry(buf)
  local entry = terms[buf]
  if entry then return entry end
  ensure_watchers()
  entry = {
    buf = buf,
    items = {},
    index = 1,
    folded = false,
    owned_files = true,
  }
  terms[buf] = entry
  api.nvim_create_autocmd({ "TermClose", "BufWipeout" }, {
    group = augroup,
    buffer = buf,
    once = true,
    callback = function()
      M.clear_terminal(buf)
    end,
  })
  return entry
end

---Refresh every active preview card against current window geometry/visibility.
function M.refresh_all()
  for buf, entry in pairs(terms) do
    if not api.nvim_buf_is_valid(buf) or #entry.items == 0 then
      M.clear_terminal(buf)
    elseif find_panel_win(buf) then
      render_terminal(buf)
    else
      close_card_win(entry)
    end
  end
  for buf, entry in pairs(prompts) do
    if not api.nvim_buf_is_valid(buf) or not (entry.prompt_win and api.nvim_win_is_valid(entry.prompt_win)) then
      M.clear_prompt(buf)
    elseif #entry.items > 0 then
      render_prompt(buf)
    end
  end
end

---Handle `<C-v>` in an agent `:terminal` buffer: snapshot clipboard PNG when
---available, show the preview card, and always forward `0x16` to the child PTY.
---@param buf integer
function M.paste_terminal(buf)
  if not api.nvim_buf_is_valid(buf) then return end
  local channel = vim.bo[buf].channel
  if not channel or channel <= 0 then return end

  if M._ui_active() then
    local clipboard = require("agent_workbench.clipboard")
    if clipboard.has_image() then
      seq = seq + 1
      local png = ("%s/term-%d-%d.png"):format(clipboard.staging_dir(), buf, seq)
      local ok = clipboard.save_image(png)
      if ok then
        local stat = vim.uv.fs_stat(png)
        local entry = ensure_terminal_entry(buf)
        entry.items[#entry.items + 1] = { path = png, bytes = stat and stat.size or 0 }
        entry.index = #entry.items
        entry.folded = false
        entry.submit_gen = (entry.submit_gen or 0) + 1
        render_terminal(buf)
      end
    end
  end

  api.nvim_chan_send(channel, "\22")
end

---Transfer staged prompt-editor PNGs to `buf`'s terminal preview card once
---`clipboard.attach` has replayed them into the TUI's unsent input box.
---@param buf integer
---@param paths string[]
---@return boolean adopted true when `image_preview` now owns deleting `paths`
function M.adopt_terminal(buf, paths)
  if not M._ui_active() or not api.nvim_buf_is_valid(buf) or type(paths) ~= "table" or #paths == 0 then
    return false
  end
  local added = 0
  local entry = ensure_terminal_entry(buf)
  for _, path in ipairs(paths) do
    local stat = type(path) == "string" and vim.uv.fs_stat(path) or nil
    if stat and stat.size > 0 then
      entry.items[#entry.items + 1] = { path = path, bytes = stat.size }
      added = added + 1
    elseif type(path) == "string" then
      pcall(vim.fn.delete, path)
    end
  end
  if added == 0 then return true end
  entry.index = #entry.items
  entry.folded = false
  entry.submit_gen = (entry.submit_gen or 0) + 1
  render_terminal(buf)
  return true
end

---Clear a terminal's pending image preview and delete its temporary PNGs.
---@param buf integer?
function M.clear_terminal(buf)
  buf = buf or api.nvim_get_current_buf()
  local entry = terms[buf]
  if not entry then return end
  terms[buf] = nil
  destroy_entry(entry, true)
end

---Update the companion preview card for a prompt editor buffer (`<leader>ai`).
---`editor.lua` retains file ownership because cancelling deletes them there and
---returning hands them to `attach_images`.
---@param prompt_win integer
---@param buf integer
---@param paths string[]
function M.set_prompt(prompt_win, buf, paths)
  if not M._ui_active() or not api.nvim_buf_is_valid(buf) or not api.nvim_win_is_valid(prompt_win) then
    return
  end
  if type(paths) ~= "table" or #paths == 0 then
    M.clear_prompt(buf)
    return
  end
  ensure_watchers()
  local entry = prompts[buf]
  if not entry then
    entry = {
      buf = buf,
      prompt_win = prompt_win,
      items = {},
      index = 1,
      folded = false,
      owned_files = false,
    }
    prompts[buf] = entry
  else
    entry.prompt_win = prompt_win
  end
  entry.items = {}
  for _, path in ipairs(paths) do
    local stat = vim.uv.fs_stat(path)
    entry.items[#entry.items + 1] = { path = path, bytes = stat and stat.size or 0 }
  end
  entry.index = #entry.items
  entry.folded = false
  render_prompt(buf)
end

---Close and forget a prompt editor buffer's companion preview card.
---@param buf integer?
function M.clear_prompt(buf)
  buf = buf or api.nvim_get_current_buf()
  local entry = prompts[buf]
  if not entry then return end
  prompts[buf] = nil
  destroy_entry(entry, false)
end

---@param buf integer?
---@return table|nil, boolean
local function entry_of(buf)
  buf = buf or api.nvim_get_current_buf()
  if prompts[buf] then return prompts[buf], true end
  if terms[buf] then return terms[buf], false end
  return nil, false
end

---Fold or expand the preview card for `buf`.
---@param buf integer?
---@return boolean toggled
function M.toggle(buf)
  buf = buf or api.nvim_get_current_buf()
  local entry, is_prompt = entry_of(buf)
  if not entry or #entry.items == 0 then return false end
  entry.folded = not entry.folded
  if is_prompt then render_prompt(buf) else render_terminal(buf) end
  return true
end

---Cycle through attached images when multiple screenshots are staged.
---@param buf integer?
---@param step integer?
---@return boolean cycled
function M.cycle(buf, step)
  buf = buf or api.nvim_get_current_buf()
  local entry, is_prompt = entry_of(buf)
  if not entry or #entry.items <= 1 then return false end
  local count = #entry.items
  entry.index = ((entry.index - 1 + (step or 1)) % count) + 1
  if is_prompt then render_prompt(buf) else render_terminal(buf) end
  return true
end

---Attach buffer-local preview controls to an agent `:terminal` buffer.
---@param buf integer
function M.attach_terminal_keys(buf)
  if not api.nvim_buf_is_valid(buf) then return end
  vim.keymap.set("t", "<C-v>", function() M.paste_terminal(buf) end, {
    buffer = buf,
    nowait = true,
    noremap = true,
    silent = true,
    desc = "Paste clipboard image into agent",
  })
  vim.keymap.set({ "t", "n" }, "<M-p>", function() M.toggle(buf) end, {
    buffer = buf,
    nowait = true,
    noremap = true,
    silent = true,
    desc = "Toggle attached image preview",
  })
  vim.keymap.set({ "t", "n" }, "<M-n>", function() M.cycle(buf, 1) end, {
    buffer = buf,
    nowait = true,
    noremap = true,
    silent = true,
    desc = "Next attached image",
  })
  vim.keymap.set({ "t", "n" }, "<M-x>", function() M.clear_terminal(buf) end, {
    buffer = buf,
    nowait = true,
    noremap = true,
    silent = true,
    desc = "Dismiss attached image preview",
  })
  vim.keymap.set("n", ",p", function() M.toggle(buf) end, {
    buffer = buf,
    silent = true,
    desc = "Toggle attached image preview",
  })
  vim.keymap.set("n", ",P", function() M.clear_terminal(buf) end, {
    buffer = buf,
    silent = true,
    desc = "Dismiss attached image preview",
  })
  vim.keymap.set("n", "]i", function() M.cycle(buf, 1) end, {
    buffer = buf,
    silent = true,
    desc = "Next attached image",
  })
  vim.keymap.set("n", "[i", function() M.cycle(buf, -1) end, {
    buffer = buf,
    silent = true,
    desc = "Previous attached image",
  })
end

---Observation helper for specs.
---@param buf integer
---@return { count: integer, index: integer, folded: boolean, win: integer|nil, paths: string[] }|nil
function M._inspect(buf)
  local entry = prompts[buf] or terms[buf]
  if not entry then return nil end
  local paths = {}
  for i, item in ipairs(entry.items) do paths[i] = item.path end
  return {
    count = #entry.items,
    index = entry.index,
    folded = entry.folded,
    win = entry.card_win and api.nvim_win_is_valid(entry.card_win) and entry.card_win or nil,
    paths = paths,
  }
end

return M
