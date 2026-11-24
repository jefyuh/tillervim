-- Antigravity CLI (agy) local session history discovery, scoped per workspace.
--
-- Upstream `agy` has no `agy resume` CLI subcommand, and its in-TUI `/resume`
-- command lists sessions from every repository (`default-cli-project`). Reading
-- `cache/conversation_metadata.json` lets `<leader>ar` present a project-scoped
-- picker in Neovim and launch `agy --conversation <id>` directly.
local M = {}

-- Test seam: override `~/.gemini/antigravity-cli` without touching $HOME.
M._data_dir = nil

local function data_dir()
  if M._data_dir then return M._data_dir end
  local home = vim.env.HOME or vim.fn.expand("~")
  return home .. "/.gemini/antigravity-cli"
end

local function norm_path(path)
  if type(path) ~= "string" or path == "" then return nil end
  local trimmed = path ~= "/" and path:gsub("/+$", "") or "/"
  return vim.uv.fs_realpath(trimmed) or vim.fs.normalize(trimmed)
end

local function uri_to_path(uri)
  if type(uri) ~= "string" then return nil end
  local raw = uri:match("^file://localhost(/.*)$") or uri:match("^file://(/.*)$")
  if not raw then return nil end
  local decoded = raw:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end)
  return norm_path(decoded)
end

local function clean_title(summary, id)
  local title = vim.trim(tostring(summary.Title or ""):gsub("%s+", " "))
  if title ~= "" then return title end
  local preview = vim.trim(tostring(summary.Preview or ""):gsub("%s+", " "))
  if preview ~= "" then
    if vim.fn.strchars(preview) > 60 then
      return vim.fn.strcharpart(preview, 0, 60) .. "…"
    end
    return preview
  end
  return tostring(id):sub(1, 8)
end

---@class ai.antigravity.Session
---@field id string
---@field title string
---@field steps integer
---@field mtime integer
---@field sort_key number

---Return recorded Antigravity CLI sessions whose workspaces include `root`,
---sorted newest first. Excludes internal subagent/workflow runs, zero-step
---abandoned sessions, and non-CLI desktop conversations.
---@param root string
---@return ai.antigravity.Session[]
function M.sessions(root)
  local target = norm_path(root)
  if not target then return {} end
  local file = data_dir() .. "/cache/conversation_metadata.json"
  if vim.fn.filereadable(file) ~= 1 then return {} end
  local ok_read, lines = pcall(vim.fn.readfile, file)
  if not ok_read or type(lines) ~= "table" then return {} end
  local ok_json, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not ok_json or type(decoded) ~= "table" or type(decoded.conversations) ~= "table" then
    return {}
  end

  local time_util = require("agent_workbench.transcript.time")
  local out = {}
  for key, entry in pairs(decoded.conversations) do
    if type(entry) == "table" and entry.is_internal ~= true then
      local s = entry.summary
      local app = type(s) == "table" and s.AppDataDir or nil
      local steps = type(s) == "table" and tonumber(s.NumSteps) or 0
      if type(s) == "table"
        and s.Internal ~= true
        and (app == nil or app == "" or app == "antigravity-cli")
        and steps > 0
        and type(s.WorkspaceURIs) == "table"
      then
        local matched = false
        for _, uri in ipairs(s.WorkspaceURIs) do
          if uri_to_path(uri) == target then
            matched = true
            break
          end
        end
        if matched then
          local id = type(s.ID) == "string" and s.ID ~= "" and s.ID or tostring(key)
          local epoch = time_util.epoch(entry.last_modified_time)
            or time_util.epoch(s.UpdatedAt)
            or 0
          out[#out + 1] = {
            id = id,
            title = clean_title(s, id),
            steps = steps,
            mtime = epoch > 0 and math.floor(epoch) or 0,
            sort_key = epoch,
          }
        end
      end
    end
  end

  table.sort(out, function(a, b)
    if a.sort_key ~= b.sort_key then return a.sort_key > b.sort_key end
    return a.id < b.id
  end)
  return out
end

---@param s ai.antigravity.Session
---@return string
function M.format_session(s)
  local when = (s.mtime or 0) > 0 and os.date("%Y-%m-%d %H:%M", s.mtime) or "unknown"
  return ("%s · %s · %d %s"):format(when, s.title, s.steps, s.steps == 1 and "step" or "steps")
end

return M
