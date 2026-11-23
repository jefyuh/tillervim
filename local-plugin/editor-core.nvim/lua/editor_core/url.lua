local M = {}
local buffer_dir = function()
  local name = vim.api.nvim_buf_get_name(0)
  return name ~= "" and vim.bo.buftype == "" and vim.fs.dirname(name) or vim.fn.getcwd()
end
function M.setup(opts) if opts and opts.buffer_dir then buffer_dir = opts.buffer_dir end end

-- Include UTF-8 bytes so removing the <cfile> shortcut does not truncate URLs
-- with Unicode hostnames, paths, or query values.
local url_chars = "[%w%-%._~:/?#%[%]@!$&'()*+,;%%=\128-\255]+"
-- CJK and fullwidth punctuation (，。、（）「」“”…) never appear unencoded in a
-- URL, and CJK prose runs straight into a link without a space, so the first
-- such character ends the URL text.
local cjk_punctuation =
  [=[[\u2018\u2019\u201c\u201d\u2026\u3000-\u303f\uff01-\uff0f\uff1a-\uff20\uff3b-\uff40\uff5b-\uff65]]=]
-- Box-drawing / block-element glyphs (borders, quote bars, scrollbars) never
-- belong to unquoted URLs or file paths.
local frame_glyph = [=[[\u2500-\u259f]]=]
local literal_separators = {
  "\t", "|", "│", "┃", "║", "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█", "▐", "▕", "░", "▒", "▓",
}
local cjk_pairs = {
  ["（"] = "）",
  ["「"] = "」",
  ["『"] = "』",
  ["“"] = "”",
  ["‘"] = "’",
  ["【"] = "】",
  ["《"] = "》",
}
local max_lines = 16
-- Rows a run the terminal wrapped may add on top of max_lines: a signed URL
-- of a few thousand bytes in a narrow panel, not a whole scrollback.
local max_wrapped = 256

-- Terminal table columns, TUI borders and scrollbars are separated by padding
-- or vertical rules/blocks. Keep byte positions for the cursor and display
-- columns for alignment across CJK.
local function cells(line)
  -- Quoted filenames may contain padding or vertical rules literally. Mask
  -- closed quotes for separator lookup, preserving byte offsets into the text.
  local layout = line:gsub("(([\"'`]).-%2)", function(quoted) return string.rep("x", #quoted) end)
  local result, from = {}, 1
  while from <= #line do
    local first, last = #line + 1, #line
    local ps, pe = layout:find("%s%s+", from)
    if ps and ps < first then first, last = ps, pe end
    for _, separator in ipairs(literal_separators) do
      local s, e = layout:find(separator, from, true)
      if s and s < first then first, last = s, e end
    end
    local spaces, text = line:sub(from, first - 1):match("^(%s*)(.-)%s*$")
    if text ~= "" then
      local col = from + #spaces
      result[#result + 1] = {
        text = text,
        col = col,
        display_col = vim.fn.strdisplaywidth(line:sub(1, col - 1)),
      }
    end
    from = last + 1
  end
  return result
end

local function url_piece(text)
  local piece = text:match("^" .. url_chars)
  if not piece then return nil end
  local stop = vim.fn.match(piece, cjk_punctuation)
  if stop >= 0 then piece = piece:sub(1, stop) end
  local frame = vim.fn.match(piece, frame_glyph)
  if frame >= 0 then piece = piece:sub(1, frame) end
  return piece ~= "" and piece or nil
end

local function trim_url(url)
  -- Sentence punctuation and Markdown wrappers are not part of the URL;
  -- balanced parentheses inside a path (e.g. a Wikipedia URL) are.
  repeat
    local prev = url
    url = url:gsub("[.,;:!]+$", "")
    for _, pair in ipairs({ { "(", ")" }, { "[", "]" } }) do
      local _, opens = url:gsub("%" .. pair[1], "")
      local _, closes = url:gsub("%" .. pair[2], "")
      while closes > opens and url:sub(-1) == pair[2] do
        url, closes = url:sub(1, -2), closes - 1
      end
    end
  until url == prev
  return url
end

-- Whether the terminal wrapped row `i` into the next, once per row: every
-- candidate walking a long wrapped run asks for the same rows.
local function wraps_at(ctx, i)
  local wraps = ctx.wraps[i]
  if wraps == nil then
    wraps = ctx.lines[i] ~= nil
      and require("editor_core.terminal_text").soft_wraps(ctx.lines[i], ctx.lines[i + 1], ctx.width)
    ctx.wraps[i] = wraps
  end
  return wraps
end

local function delimiter_before(text, start)
  if start <= 1 then return nil, nil end
  local ch = text:sub(start - 1, start - 1)
  if ch == "(" then return "(", ")" end
  if ch == "<" then return "<", ">" end
  if ch == '"' or ch == "'" or ch == "`" then return ch, ch end
  if start >= 4 then
    local wide = text:sub(start - 3, start - 1)
    if cjk_pairs[wide] then return wide, cjk_pairs[wide] end
  end
  return nil, nil
end

local bullet_pattern = [[^\%([•·◦▪▸▹‣⁃⎿└├\-*+]\|#\+\|\d\+[.)]\)\s\+]]
local rule_pattern = [[^[-_=─━═┄┅┈┉]\+$]]

-- Media, document and archive deliverables that belong in the OS player/viewer
-- (`vim.ui.open`) rather than a Neovim buffer (`:edit` on `.mp4` only extracts
-- a static frame-0 image without video playback or audio).
local EXTERNAL_FILE_EXTS = {
  mp4 = true, mov = true, m4v = true, mkv = true, webm = true, avi = true,
  flv = true, wmv = true, mpg = true, mpeg = true, ["3gp"] = true,
  mp3 = true, m4a = true, wav = true, flac = true, ogg = true, opus = true,
  aac = true, aiff = true,
  pdf = true, epub = true,
  doc = true, docx = true, xls = true, xlsx = true, ppt = true, pptx = true,
  pages = true, numbers = true, key = true, odt = true, ods = true, odp = true,
  dmg = true, pkg = true, zip = true, rar = true, ["7z"] = true,
}

local function opens_externally(path)
  local ext = vim.fn.fnamemodify(path, ":e"):lower()
  return ext ~= "" and EXTERNAL_FILE_EXTS[ext] == true
end

local function list_body_col(cell)
  local marker = vim.fn.matchstr(cell.text, bullet_pattern)
  return marker ~= "" and (cell.display_col + vim.fn.strdisplaywidth(marker)) or nil
end

local function starts_new_item(text)
  return text:find("^https?://") ~= nil
    or text:find("^file://") ~= nil
    or vim.fn.match(text, rule_pattern) >= 0
    or vim.fn.match(text, bullet_pattern) >= 0
end

-- Find an aligned cell on `target_row` continuing `start_cell` (from `origin_row`)
-- across table columns, framed TUI boxes, bullet lists or indented TUI paragraphs.
local function next_aligned_cell(ctx, origin_row, start_cell, prev_row, delimited)
  local next_cells = ctx.rows[prev_row + 1]
  if not next_cells or #next_cells == 0 then return nil end

  local origin_cells = ctx.rows[origin_row] or {}
  local column = start_cell.display_col
  local body_col = list_body_col(start_cell)

  for _, nc in ipairs(next_cells) do
    if nc.display_col == column or (body_col and nc.display_col == body_col) then
      if not nc.text:find("^https?://") and not nc.text:find("^file://")
        and vim.fn.match(nc.text, rule_pattern) < 0
      then
        if nc.display_col == body_col and starts_new_item(nc.text) then return nil end
        if not delimited and starts_new_item(nc.text) then return nil end
        -- Plain unindented shell output at raw col 0 (e.g. `ls -F` printing
        -- `dir/` above `file`) is only joined when the row filled a lagged PTY.
        if not delimited and column == 0 and nc.display_col == 0 and start_cell.col == 1 and nc.col == 1 then
          if not ctx.width or vim.fn.strdisplaywidth(ctx.lines[prev_row] or "") < math.max(20, ctx.width - 10) then
            return nil
          end
        end
        return nc
      end
    end
  end

  -- Single-cell indented TUI paragraph / list wrap (`±2` columns, or wrapping
  -- back to the row's leading indent after a `Label:  path` cell split).
  if #next_cells == 1 then
    local nc = next_cells[1]
    if nc.display_col > 0 and not starts_new_item(nc.text) then
      if #origin_cells == 1 then
        if (column > 0 and math.abs(nc.display_col - column) <= 2)
          or (body_col and math.abs(nc.display_col - body_col) <= 2)
        then
          return nc
        end
      elseif start_cell == origin_cells[#origin_cells] then
        local first_cell = origin_cells[1]
        local line_col = first_cell.display_col
        local line_body = list_body_col(first_cell)
        if (line_col > 0 and math.abs(nc.display_col - line_col) <= 2)
          or (line_body and math.abs(nc.display_col - line_body) <= 2)
        then
          return nc
        end
      end
    elseif delimited and nc.display_col == 0 and not starts_new_item(nc.text)
      and start_cell == origin_cells[#origin_cells]
      and origin_cells[1] and origin_cells[1].display_col == 0
    then
      return nc
    end
  end
  return nil
end

-- `ctx` holds, by row number, the scanned rows' cells (`rows`) and raw text
-- (`lines`), whether they are `terminal` output, the grid's `width`, and the
-- `wraps` that wraps_at has answered.
local function candidate(ctx, row, start_cell, start, file, scheme_prefix)
  local opening, closer = delimiter_before(start_cell.text, start)
  local ascii_quote = opening == '"' or opening == "'" or opening == "`"
  local quoted = file and ascii_quote
  local delimited = closer ~= nil
  local function get_piece(text)
    if quoted then return text:match("^[^" .. opening .. "]+") end
    local p = url_piece(text)
    if p and ascii_quote then
      local q = p:find(opening, 1, true)
      if q then p = p:sub(1, q - 1) end
    end
    return p ~= "" and p or nil
  end
  local cell = start_cell
  local tail = cell.text:sub(start)
  local piece = get_piece(tail)
  if not piece or piece == "" then return nil end
  local fallback = {
    url = trim_url(piece),
    spans = { { row = row, first = cell.col + start - 1, last = cell.col + start + #piece - 2 } },
  }

  local url, spans, partials = "", {}, {}
  -- `wrapped`: the terminal wrapped the row just read, so the text resumes in
  -- column 0 of the next one. `tui_cont`: an aligned TUI cell continues the
  -- target on the next row. `soft_wrapped`: any terminal edge-wrap happened
  -- (after which column continuation is disallowed). `tui_joined`: an unclosed
  -- file or cut-scheme continuation across aligned TUI cells happened.
  local wrapped, tui_cont, soft_wrapped, tui_joined = false, nil, false, false
  -- Rows down a table column count against max_lines, rows the terminal
  -- wrapped against max_wrapped: a long link stays whole.
  local column_rows, wrapped_rows = 0, 0
  local next_row = row - 1
  while true do
    next_row = next_row + 1
    if wrapped then
      wrapped_rows = wrapped_rows + 1
      -- Its end is out of reach: no target beats a truncated one.
      if wrapped_rows > max_wrapped then return nil end
    else
      column_rows = column_rows + 1
      if column_rows > max_lines then break end
    end
    if next_row > row then
      local continuation = wrapped
        -- The whole row, not its first cell: a wrap splits text anywhere, so
        -- the padding and rules that separate cells mean nothing here.
        and { text = ctx.lines[next_row], col = 1, display_col = 0 }
        or tui_cont
      if not continuation then break end
      cell, start, tail = continuation, 1, continuation.text
      piece = get_piece(tail)
      if not piece or piece == "" then break end
      -- Use a Unicode-aware pattern: table rules are now valid token bytes too.
      -- Not after a wrap: soft_wraps already refuses a row led by a rule, and
      -- a wrapped tail can be all "=" (base64 padding).
      if not wrapped and vim.fn.match(piece, rule_pattern) >= 0 then break end
      -- A link starting in column 0 is the next link, not this one's tail.
      if (wrapped or tui_cont) and piece:find("^https?://") then break end
    end
    url = url .. piece
    local first = cell.col + start - 1
    local last = first + #piece - 1
    spans[#spans + 1] = { row = next_row, first = first, last = last }
    if file then
      partials[#partials + 1] = { url = trim_url(url), spans = vim.deepcopy(spans) }
    end
    local enclosed = opening == "(" and piece:find(")", 1, true) and ("(" .. url):match("^%b()")
    if enclosed then
      local inner = enclosed:sub(2, -2)
      if file then partials[#partials + 1] = { url = inner, spans = vim.deepcopy(spans) } end
      return { url = inner, spans = spans, partials = partials, fallback = fallback }
    end
    if closer and opening ~= "(" and tail:sub(#piece + 1, #piece + #closer) == closer then
      local clean = file and url or trim_url(url)
      if file then partials[#partials + 1] = { url = clean, spans = vim.deepcopy(spans) } end
      return { url = clean, spans = spans, partials = partials, fallback = fallback }
    end
    -- Only join terminal rendering. Source newlines stay real.
    if not ctx.terminal then break end
    -- A target that runs into the right edge of a row the terminal wrapped
    -- goes on in column 0, bare or enclosed, whatever column it started in.
    wrapped = last == #ctx.lines[next_row] and wraps_at(ctx, next_row)
    tui_cont = nil
    if not wrapped and #piece == #tail and not soft_wrapped then
      if delimited or file or (scheme_prefix and next_row == row) then
        tui_cont = next_aligned_cell(ctx, row, start_cell, next_row, delimited)
      end
    end
    soft_wrapped = soft_wrapped or wrapped
    tui_joined = tui_joined or (file and tui_cont ~= nil)
      or (scheme_prefix and not delimited and next_row == row and tui_cont ~= nil)
    -- Otherwise only an enclosed target continues, only down its aligned column
    -- and only once its closing delimiter is found.
    if not wrapped and not tui_cont then break end
  end
  -- Wrapped text is one line to the program that printed it, so what it
  -- joined stands without a closing delimiter. A file path keeps its prefixes
  -- as fallbacks, for a newline written right after a valid path.
  -- Unwrapped, a bare target is its first row's piece, which fallback is.
  if soft_wrapped or tui_joined then
    return { url = trim_url(url), spans = spans, partials = partials, fallback = fallback }
  end
  if file then fallback.partials = partials end
  return fallback
end

local function url_decode(s)
  return (s:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

local function existing_file(path)
  if not path or path == "" then return nil end
  if path:sub(1, 2) == "~/" then path = vim.uv.os_homedir() .. path:sub(2) end
  if path:sub(1, 1) ~= "/" then
    local info = vim.bo.buftype == "terminal" and (vim.b.agent_workbench or vim.b.snacks_terminal)
    local base = info and info.cwd or buffer_dir()
    path = vim.fs.joinpath(base, path)
  end
  local stat = vim.uv.fs_stat(path)
  return stat and stat.type == "file" and path or nil
end

local function local_file(raw)
  if not raw or raw == "" then return nil end
  if raw:find("^file://") then
    raw = url_decode(raw:gsub("^file://localhost/", "/"):gsub("^file://", ""))
  elseif raw:find("://", 1, true) then
    return nil
  end

  -- Check the exact string first so literal '#' or ':' in a filename wins.
  local literal = existing_file(raw)
  if literal then return { path = literal } end

  -- Strip Markdown / GitHub line anchors (#L10, #L10-L20, #L10-20, #L10C5).
  local base, lnum, col = raw:match("^(.-)#L(%d+)C(%d+)$")
  if not base then base, lnum = raw:match("^(.-)#L(%d+)%-L?%d+$") end
  if not base then base, lnum = raw:match("^(.-)#L(%d+)$") end
  if base and base ~= "" then
    local resolved = existing_file(base)
    if resolved then return { path = resolved, lnum = tonumber(lnum), col = tonumber(col) } end
  end

  -- Strip compiler / grep / yank_path / TUI :line[:col][-end][:] suffixes.
  local trimmed = raw:gsub(":$", "")
  base, lnum, col = trimmed:match("^(.+):(%d+):(%d+)%-%d+$")
  if not base then base, lnum, col = trimmed:match("^(.+):(%d+):(%d+)$") end
  if not base then base, lnum = trimmed:match("^(.+):(%d+)%-L?%d+$") end
  if not base then base, lnum = trimmed:match("^(.+):(%d+)$") end
  if base and base ~= "" then
    local resolved = existing_file(base)
    if resolved then return { path = resolved, lnum = tonumber(lnum), col = tonumber(col) } end
  end
  if trimmed ~= raw then
    local resolved = existing_file(trimmed)
    if resolved then return { path = resolved } end
  end
  return nil
end

local function resolve_file_part(part)
  local resolved = local_file(part.url)
  if resolved then return part, resolved end
  -- CJK prose glued straight onto the end of a path or :line:col (e.g.
  -- `ai.lua:22:5并更新了配置` or `/tmp/中文目录/ai.lua:10的说明`).
  local cut = vim.fn.match(part.url, [=[\v[!-~]\zs[\u3040-\u30ff\u3400-\u9fff\uf900-\ufaff][^/]*$]=])
  if cut > 0 then
    local shorter = trim_url(part.url:sub(1, cut))
    resolved = local_file(shorter)
    if resolved then
      local trimmed_spans = vim.deepcopy(part.spans)
      local tail_span = trimmed_spans[#trimmed_spans]
      if tail_span then
        tail_span.last = math.max(tail_span.first, tail_span.last - (#part.url - #shorter))
      end
      return { url = shorter, spans = trimmed_spans }, resolved
    end
  end
  return part, nil
end

local function each_file_start(text, cb)
  local seen = {}
  local function emit(pos, tok)
    if tok == "" or seen[pos] then return end
    seen[pos] = true
    cb(pos, tok)
    if tok:byte(1) >= 128 then
      local ascii = tok:find("[~%.%w_%-/]")
      if ascii and ascii > 1 and not seen[pos + ascii - 1] then
        seen[pos + ascii - 1] = true
        cb(pos + ascii - 1, tok:sub(ascii))
      end
    end
  end
  for base, raw in text:gmatch("()([^%s<>\"'`%(%)%[%]]+)") do
    local opener = text:sub(base - 1, base - 1)
    if opener == '"' or opener == "'" or opener == "`" then
      emit(base, raw)
    else
      local offset = 1
      while offset <= #raw do
        local m = vim.fn.matchstrpos(raw, cjk_punctuation, offset - 1)
        local stop = m[2] >= 0 and m[2] or #raw
        if stop >= offset then
          emit(base + offset - 1, raw:sub(offset, stop))
        end
        if m[2] < 0 then break end
        offset = m[3] + 1
      end
    end
  end
end

local function open_local_file(resolved)
  if opens_externally(resolved.path) then
    vim.ui.open(resolved.path)
    return
  end
  -- From a panel (an agent terminal, a chat) the file goes to the editor
  -- in this tab, leaving the panel and its process intact.
  vim.api.nvim_set_current_win(require("editor_core.buffer").editor_target())
  vim.cmd.edit({ args = { resolved.path }, magic = { file = false, bar = false } })
  if resolved.lnum then
    local total = vim.api.nvim_buf_line_count(0)
    local lnum = math.max(1, math.min(resolved.lnum, total))
    local c = math.max(0, (resolved.col or 1) - 1)
    pcall(vim.api.nvim_win_set_cursor, 0, { lnum, c })
  end
end

---Open the nearest HTTP(S) URL or existing local file on this row (or Visual selection).
---In terminals, targets continue across rows the terminal wrapped, across `url`
---highlight extmarks, and across aligned table / TUI cells.
function M.open()
  local mode = vim.fn.mode()
  if mode:find("^[vV\22]") then
    local region = vim.fn.getregion(vim.fn.getpos("."), vim.fn.getpos("v"), { type = mode })
    vim.cmd.normal({ args = { vim.keycode("<Esc>") }, bang = true })
    local parts = {}
    for idx, l in ipairs(region) do
      parts[idx] = #region > 1
        and vim.fn.substitute(l, [=[^\s*[│┃║▏▎▍▌|]\?\s*\|\s*[│┃║▏▎▍▌█▐▕░▒▓|]\?\s*$]=], "", "g")
        or vim.trim(l)
    end
    local selected = trim_url(table.concat(parts, ""):gsub("^([\"'`])(.-)%1$", "%2"))
    if selected ~= "" then
      local _, resolved = resolve_file_part({ url = selected, spans = {} })
      if resolved then
        open_local_file(resolved)
      else
        vim.ui.open(selected)
      end
    end
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor[1], cursor[2] + 1
  local terminal = vim.bo.buftype == "terminal"
  local count = vim.api.nvim_buf_line_count(0)
  local first = terminal and math.max(1, row - max_lines + 1) or row
  local last = terminal and math.min(count, row + max_lines - 1) or row
  local ctx = {
    rows = {},
    lines = {},
    wraps = {},
    terminal = terminal,
    width = terminal and require("editor_core.terminal_text").grid_width(vim.api.nvim_get_current_buf()) or nil,
  }
  if terminal then
    -- A link the terminal wrapped is one line to the program however many
    -- rows it takes. Only the wrapped run through the cursor row can put a
    -- target on it -- nothing goes down a column after a wrap -- so the
    -- window grows over that run alone: to its first row, less max_lines for
    -- a column that led into it, and to its last. Growing over any run in
    -- reach cost seconds next to a long minified or base64 line.
    local soft_wraps = require("editor_core.terminal_text").soft_wraps
    local function line(i) return vim.api.nvim_buf_get_lines(0, i - 1, i, false)[1] end
    local top, bottom = row, row
    while top > 1 and row - top < max_wrapped and soft_wraps(line(top - 1), line(top), ctx.width) do
      top = top - 1
    end
    while bottom < count and bottom - row < max_wrapped and soft_wraps(line(bottom), line(bottom + 1), ctx.width) do
      bottom = bottom + 1
    end
    first = math.max(1, math.min(first, top - max_lines + 1))
    last = math.max(last, bottom)
  end
  -- One row past the window, so the last row's wrap can still be judged.
  for i, line in ipairs(vim.api.nvim_buf_get_lines(0, first - 1, terminal and last + 1 or last, false)) do
    ctx.lines[first + i - 1] = line
    if first + i - 1 <= last then ctx.rows[first + i - 1] = cells(line) end
  end
  local rows = ctx.rows

  local best, best_distance = nil, math.huge
  local function consider(link, resolved)
    if not link then return end
    for _, span in ipairs(link.spans) do
      if span.row == row then
        local distance = math.max(span.first - col, col - span.last, 0)
        if distance < best_distance then
          best, best_distance = {
            target = resolved and resolved.path or link.url,
            file = resolved ~= nil,
            resolved = resolved,
          }, distance
        end
      end
    end
  end

  -- OSC 8 terminal hyperlinks attach `details.url` to highlight extmarks across
  -- every wrapped row of the link, even when the visible label omits the path.
  local row_len = #(ctx.lines[row] or "")
  local extmarks = vim.api.nvim_buf_get_extmarks(0, -1, { row - 1, 0 }, { row - 1, -1 }, {
    details = true,
    type = "highlight",
    overlap = true,
  })
  for _, mark in ipairs(extmarks) do
    local details = mark[4]
    if details and type(details.url) == "string" and details.url ~= "" then
      local span_first = mark[2] < row - 1 and 1 or (mark[3] + 1)
      local end_row = details.end_row or mark[2]
      local span_last = end_row > row - 1 and math.max(1, row_len)
        or math.max(span_first, details.end_col or (mark[3] + 1))
      local resolved = local_file(details.url)
      consider({ url = details.url, spans = { { row = row, first = span_first, last = span_last } } }, resolved)
    end
  end

  for i = first, row do
    for _, cell in ipairs(rows[i]) do
      for start in cell.text:gmatch("()https?://") do
        consider(candidate(ctx, i, cell, start))
      end
      -- A wrap can cut the scheme itself ("htt" | "ps://"), leaving no row
      -- that holds "https://": start from a prefix of it at the cell's edge.
      if terminal then
        for k = 7, 1, -1 do
          local start = #cell.text - k + 1
          if start >= 1 then
            local prefix = cell.text:sub(start)
            if (("https://"):sub(1, k) == prefix or ("http://"):sub(1, k) == prefix)
              and not prefix:find("^https?://$")
            then
              -- Not inside a word or a link: a base64 row ending in "h" is no
              -- scheme, and walking its run from every such row is quadratic.
              if not cell.text:sub(start - 1, start - 1):find("[%w%-%._~%%/=?&#+@!$*,;]") then
                local link = candidate(ctx, i, cell, start, false, true)
                if link and link.url:find("^https?://") then consider(link) end
              end
              break
            end
          end
        end
      end
      each_file_start(cell.text, function(start, token)
        -- A token at the start of a row that the row above wraps into, right
        -- after an ASCII path/token byte at the edge, is that token's tail: its
        -- candidate walks on through this row. Starting again here made a long
        -- wrapped run cost the square of its rows.
        local tail_of_above = i > first and cell.col == 1 and start == 1
          and ctx.lines[i - 1]:find("[%w%-%._~:/?#%%@!$&*+,;=]$") ~= nil and wraps_at(ctx, i - 1)
        -- Existence distinguishes files (including extensionless names) from
        -- prose; directories such as a wrapped /tmp/ are never opened as files.
        if (not token:find("://", 1, true) or token:find("^file://")) and not tail_of_above then
          local link = candidate(ctx, i, cell, start, true)
          if link then
            local list = link.partials or { link }
            for idx = #list, 1, -1 do
              local part = list[idx]
              local covers_row = false
              for _, sp in ipairs(part.spans) do
                if sp.row == row then covers_row = true; break end
              end
              if covers_row then
                local matched_part, resolved = resolve_file_part(part)
                if resolved then
                  consider(matched_part, resolved)
                  break
                end
              end
            end
          end
        end
      end)
    end
  end
  if best and best.file then
    open_local_file(best.resolved)
    return
  end
  local target = best and best.target or (vim.bo.buftype == "" and vim.fn.expand("%:p") or "")
  if target ~= "" then vim.ui.open(target) end
end

return M
