-- Working-directory resolution. Requiring this module changes nothing.
-- lua/tillervim/bootstrap/setup.lua checks the process cwd before plugins load and picks
-- the startup directory at VimEnter, after relative arguments are resolved.
local M = {}

---The active user configuration, including an init loaded by -u.
---Independent of the current file, cwd and stdpath("config").
---@return string
function M.config_root()
  return require("tillervim").config_root()
end

local function is_dir(path)
  local st = vim.uv.fs_stat(path)
  return st ~= nil and st.type == "directory"
end

--- `path` itself if it still exists, else its nearest surviving ancestor.
---@param path string
---@return string?
local function nearest_existing(path)
  if is_dir(path) then return path end
  for dir in vim.fs.parents(path) do
    if is_dir(dir) then return dir end
  end
end

--- Local directory for file browsing/searching from the current buffer.
--- Oil supplies its directory; files supply their parent. Terminals, unnamed
--- buffers and other virtual buffers use the window/tab cwd, never their URI.
---@return string
function M.buffer_dir()
  local dir
  if vim.bo.filetype == "oil" and package.loaded.oil then
    dir = package.loaded.oil.get_current_dir()
  elseif vim.bo.buftype == "" then
    local name = vim.api.nvim_buf_get_name(0)
    if name ~= "" and not name:match("^%a[%w+.-]*://") then
      dir = is_dir(name) and name or vim.fs.dirname(name)
    end
  end
  return (dir and nearest_existing(dir))
      or nearest_existing(vim.fn.getcwd())
      or vim.uv.os_homedir()
      or "/"
end

---The Git root for a file, or the working directory when no root is found.
---Shared by agent launch, selection paths and recorded-session lookup.
---@param path string? a file path; "" or nil means "use the working directory"
---@return string
function M.project_root(path)
  local start = (path and path ~= "") and vim.fs.dirname(path)
    or (vim.uv.cwd() or vim.fn.getcwd())
  return vim.fs.root(start, ".git") or vim.uv.cwd() or vim.fn.getcwd()
end

--- The directory Nvim starts in for a file or directory argument.
---
--- A directory is used exactly. A file uses its nearest `.git` ancestor (a
--- `.git` file counts, so worktrees and submodules keep their own root), else
--- its parent. Symlinks resolve to their target first, and a parent that does
--- not exist yet falls back to its nearest existing ancestor.
---@param path string an absolute path
---@return string?
function M.startup_dir(path)
  local target = vim.uv.fs_realpath(path) or path
  if is_dir(target) then return target end
  local dir = nearest_existing(vim.fs.dirname(target))
  return dir and (vim.fs.root(dir, ".git") or dir)
end

return M
