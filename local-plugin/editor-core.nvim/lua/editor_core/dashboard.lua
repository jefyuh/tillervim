-- Snacks dashboard content and viewport locking. Loaded by the UI spec
-- when Snacks resolves its options, before its first dashboard can open.
-- Lock the dashboard buffer against scrolling: the layout is centered on open
-- and any viewport shift breaks the panes. We can't use FileType because
-- snacks sets `eventignore = "all"` while assigning the dashboard filetype,
-- so we hook the `SnacksDashboardOpened` user event it fires afterwards.
local installed = false
local function setup_viewport()
  if installed then return end
  installed = true
  vim.api.nvim_create_autocmd("User", {
    pattern = "SnacksDashboardOpened",
    callback = function()
      local buf = vim.api.nvim_get_current_buf()
      if vim.bo[buf].filetype ~= "snacks_dashboard" then return end
      vim.b[buf].snacks_scroll = false
      local map_opts = { buffer = buf, silent = true, nowait = true }
      -- Only disable keys that genuinely scroll the viewport. j/k/arrows/gg/G are
      -- left alone so snacks' built-in cursor navigation between menu items still
      -- works (it snaps the cursor to the nearest actionable key).
      for _, key in ipairs({
        "<C-d>", "<C-u>", "<C-f>", "<C-b>", "<C-e>", "<C-y>",
        "<ScrollWheelUp>", "<ScrollWheelDown>",
        "<PageUp>", "<PageDown>",
      }) do
        vim.keymap.set("n", key, "<Nop>", map_opts)
      end
      -- Any other scroll source restores the initial topline as well.
      local view
      vim.schedule(function()
        local win = vim.fn.bufwinid(buf)
        if win ~= -1 then view = vim.api.nvim_win_call(win, vim.fn.winsaveview) end
      end)
      local restoring = false
      vim.api.nvim_create_autocmd("WinScrolled", {
        buffer = buf,
        callback = function()
          if restoring or not view then return end
          restoring = true
          vim.schedule(function()
            local win = vim.fn.bufwinid(buf)
            if win ~= -1 then
              vim.api.nvim_win_call(win, function() vim.fn.winrestview(view) end)
            end
            restoring = false
          end)
        end,
      })
    end,
  })
end

-- The lolcat pipe needs a shell, so the quote is escaped instead of passed as
-- argv. `-W 36` caps the bubble at 38 columns, which keeps it inside the
-- 64-column pane once the section centers the roughly 39-column output.
-- LuaJIT's math.random is deterministic until seeded, so hrtime seeds it —
-- otherwise every session would greet you with the same quote.
local function cowsay_quote(quotes)
  math.randomseed(vim.uv.hrtime())
  local quote = quotes[math.random(#quotes)]
  return ("cowsay -W 36 %s | lolcat -f"):format(vim.fn.shellescape(quote))
end

-- The `square` colorscript from shell-color-scripts, inlined so the dashboard
-- banner needs no external binary. Each group is a 7-cell block drawn with the
-- normal ANSI foreground on its left half and the bright/bold one on its right.
-- Returned as list-form argv so no shell parses the raw escape bytes.
local function color_squares()
  local rows = { { "▀ █", "█ ▀" }, { "██ ", " ██" }, { "▄ █", "█ ▄" } }
  local lines = {}
  for _, row in ipairs(rows) do
    local groups = {}
    for color = 1, 6 do -- red, green, yellow, blue, magenta, cyan
      groups[#groups + 1] = ("\27[3%dm%s \27[1;9%dm%s\27[0m"):format(color, row[1], color, row[2])
    end
    lines[#lines + 1] = " " .. table.concat(groups, "   ")
  end
  return { "printf", "%s\n", table.concat(lines, "\n") }
end

local M = {}

---Build dashboard layout. Extra content is supplied by the host and resolved
---only when Snacks renders that section, not while plugin options are built.
---@param opts table
---@param extra_sections? fun(): table[]
function M.build(opts, extra_sections)
  setup_viewport()
  opts = vim.deepcopy(opts or {})
  return {
    enabled = opts.enabled ~= false,
    -- Snacks shares one pane width; both columns use the same geometry.
    width = opts.width or 64,
    preset = { keys = opts.keys },
    sections = {
      {
        section = "terminal",
        cmd = cowsay_quote(opts.quotes or { "Welcome to Nvim" }),
        padding = 1,
        -- The cow is narrower than the pane, so center it independently.
        indent = 12,
        enabled = vim.fn.executable("cowsay") == 1 and vim.fn.executable("lolcat") == 1,
      },
      { section = "keys", gap = 1, padding = 1, indent = 3 },
      {
        pane = 2,
        section = "terminal",
        cmd = color_squares(),
        height = 3,
        padding = 2,
        indent = 3,
      },
      function()
        return vim.tbl_map(function(section)
          return vim.tbl_extend("force", {
            pane = 2,
            section = "terminal",
            padding = 1,
            ttl = 5 * 60,
            indent = 3,
          }, section)
        end, extra_sections and extra_sections() or {})
      end,
      { section = "startup" },
    },
  }
end

return M
