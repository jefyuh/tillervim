-- Exercise real VimEnter startup: -c qa would quit before the cwd hook runs.
local t = dofile("tests/helper.lua")
local config = vim.fn.fnamemodify("init.lua", ":p")
local base = vim.fn.tempname()
vim.fn.mkdir(base, "p")
base = vim.uv.fs_realpath(base)
local repo, loose, worktree = base .. "/project with spaces", base .. "/loose", base .. "/worktree"
for _, dir in ipairs({ repo .. "/.git", repo .. "/src", loose, worktree .. "/src" }) do
  vim.fn.mkdir(dir, "p")
end
local file, other = repo .. "/src/one.txt", worktree .. "/src/two.txt"
vim.fn.writefile({ "one" }, file)
vim.fn.writefile({ "two" }, other)
-- Worktrees and submodules use a .git file rather than a directory.
vim.fn.writefile({ "gitdir: ../common/.git/worktrees/example" }, worktree .. "/.git")
vim.fn.writefile({ "loose" }, loose .. "/plain.txt")

local probe = base .. "/probe.lua"
vim.fn.writefile(vim.split([[
local result = {
  cwd = vim.fn.getcwd(), file = vim.api.nvim_buf_get_name(0),
  agent_root = require("tillervim.util.cwd").project_root(),
  oil_dir = package.loaded.oil and package.loaded.oil.get_current_dir(),
}
if vim.env.CWD_SAVE == "1" then
  result.parent_existed = vim.fn.isdirectory(vim.fs.dirname(result.file)) == 1
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "new file" })
  vim.cmd.write()
  result.saved = vim.fn.readfile(result.file)
end
if vim.env.CWD_DELETE == "1" then
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "unsaved text" })
  assert(vim.uv.fs_rmdir(vim.uv.cwd()))
  assert(vim.uv.cwd() == nil)
  vim.wait(50)
  result.kept_text = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  result.kept_modified = vim.bo.modified
  vim.cmd.cd(vim.fn.fnameescape(vim.env.CWD_REPAIR))
end
if vim.env.CWD_NEXT == "1" then
  vim.cmd("next")
  result.next_file = vim.api.nvim_buf_get_name(0)
end
if vim.env.CWD_EDIT ~= "" then
  vim.cmd.edit(vim.fn.fnameescape(vim.env.CWD_EDIT))
end
result.later_cwd = vim.fn.getcwd()
io.stdout:write(vim.json.encode(result) .. "\n")
vim.cmd("cquit 0")
]], "\n", { plain = true }), probe)

local function child(args, opts)
  opts = opts or {}
  local command = { vim.v.progpath, "--headless", "-u", config, "-i", "NONE" }
  vim.list_extend(command, args)
  vim.list_extend(command, { "-c", [[lua vim.api.nvim_create_autocmd("VimEnter", {
    once = true, callback = function()
      vim.schedule(function()
        local ok, err = pcall(dofile, vim.env.CWD_PROBE)
        if not ok then io.stderr:write(tostring(err)); vim.cmd("cquit 1") end
      end)
    end,
  })]] })
  local result = vim.system(command, {
    cwd = opts.cwd or base, text = true, stdin = opts.stdin,
    env = {
      CWD_PROBE = probe, CWD_EDIT = opts.edit or "", CWD_NEXT = opts.next and "1" or "",
      CWD_SAVE = opts.save and "1" or "", CWD_DELETE = opts.delete and "1" or "", CWD_REPAIR = base,
    },
  }):wait(20000)
  local ok, decoded = pcall(vim.json.decode, result.stdout or "")
  t.ok(result.code == 0 and ok, "startup probe exits cleanly"
    .. (result.code == 0 and ok and "" or ": " .. (result.stderr or "")))
  return ok and decoded or {}
end

local started = child({ file }, { edit = other })
t.eq(started.cwd, repo, "a file starts in its Git root")
t.eq(started.agent_root, repo, "the agents use the same project")
t.eq(started.later_cwd, repo, "editing another repository leaves cwd alone")

t.eq(child({ "project with spaces/src/one.txt" }).cwd, repo, "relative paths resolve before cwd changes")
local directory = child({ "project with spaces/src" })
t.eq(directory.cwd, repo .. "/src", "a relative directory argument sets cwd correctly")
t.eq(directory.oil_dir, repo .. "/src/", "Oil opens the original directory after cwd changes")
t.eq(child({}).cwd, base, "startup without arguments keeps the shell directory")
t.eq(child({ "-" }, { stdin = "text\n" }).cwd, base, "stdin keeps the shell directory")

for _, dir in ipairs({ repo, loose }) do
  local argument = vim.fs.basename(dir) .. "/created on save/to/file"
  local new = child({ argument }, { save = true })
  t.eq(new.file, base .. "/" .. argument, "a new file keeps its absolute path after startup")
  t.eq(new.parent_existed, false, "missing target parents are allowed at startup")
  t.eq(new.cwd, dir, "a new file uses its Git root or nearest existing parent")
  t.eq(new.saved, { "new file" }, "saving creates missing target directories and writes the file")
  t.eq(new.later_cwd, dir, "saving leaves cwd unchanged")
end

-- Startup validation must not become a runtime watcher that discards edits.
local removed = base .. "/removed while editing"
vim.fn.mkdir(removed, "p")
local editing = child({}, { cwd = removed, delete = true })
t.eq(editing.kept_text, { "unsaved text" }, "deleting cwd during editing keeps the buffer")
t.eq(editing.kept_modified, true, "the surviving buffer remains modified")
t.eq(editing.later_cwd, base, "an explicit :cd repairs a deleted cwd during editing")

-- An absolute argument reaches util.cwd.startup_dir with nothing but ':p'
-- applied (lua/tillervim/bootstrap/setup.lua), so the path cases call it in this process
-- rather than each starting a child Nvim.
local cwd = require("tillervim.util.cwd")
do
  local previous = vim.fn.getcwd()
  vim.fn.chdir(repo .. "/src")
  t.eq(cwd.project_root(file), repo, "a file uses its Git root")
  t.eq(cwd.project_root(other), worktree, "project lookup recognizes a worktree's .git file")
  t.eq(cwd.project_root(), repo, "project lookup without a file starts at the working directory")
  t.eq(cwd.project_root(""), repo, "an empty project path also starts at the working directory")
  t.eq(cwd.project_root(loose .. "/plain.txt"), vim.uv.cwd(),
    "a non-Git file falls back to the working directory, unlike startup resolution")
  vim.fn.chdir(previous)
end
t.eq(cwd.startup_dir(repo .. "/src/new/deeper/file.txt"), repo, "a new file with missing parents finds its repository")
t.eq(cwd.startup_dir(other), worktree, "a .git file identifies a worktree or submodule root")
t.eq(cwd.startup_dir(loose .. "/plain.txt"), loose, "a non-Git file uses its parent directory")
t.eq(cwd.startup_dir(loose .. "/missing/new.txt"), loose, "a missing non-Git parent uses its nearest existing ancestor")
t.eq(cwd.startup_dir(repo .. "/src"), repo .. "/src", "a directory argument stays at that exact directory")

local nested = repo .. "/vendor/inner"
vim.fn.mkdir(nested .. "/.git", "p")
vim.fn.writefile({ "nested" }, nested .. "/nested.txt")
t.eq(cwd.startup_dir(nested .. "/nested.txt"), nested, "the nearest nested repository wins")
assert(vim.uv.fs_symlink(file, base .. "/link.txt"))
t.eq(cwd.startup_dir(base .. "/link.txt"), repo, "a symlinked file uses the target repository")

for _, scope in ipairs({ "cd", "lcd", "tcd" }) do
  t.eq(child({ file, "-c", scope .. " " .. vim.fn.fnameescape(loose) }).cwd, loose,
    "an explicit startup :" .. scope .. " takes precedence")
end

local multiple = child({ "project with spaces/src/one.txt", "worktree/src/two.txt" }, { next = true })
t.eq(multiple.cwd, repo, "the first file determines cwd with multiple arguments")
t.eq(multiple.next_file, other, "changing cwd preserves subsequent relative arguments")
t.eq(multiple.later_cwd, repo, ":next does not change cwd again")

-- Remove each child's process cwd just before init.lua runs. A valid absolute
-- target does not permit guessing a replacement cwd, and $PWD is diagnostic only.
for _, known_pwd in ipairs({ true, false }) do
  local lost = base .. "/deleted before startup"
  vim.fn.mkdir(lost, "p")
  local before_init = [[lua
    package.preload["lazy"] = function() error("unexpected lazy load") end
    assert(vim.uv.fs_rmdir(vim.uv.cwd()))
  ]] .. (known_pwd and "" or "vim.env.PWD = nil")
  local failed = vim.system({
    vim.v.progpath, "--headless", "-u", config, "-i", "NONE", "-n",
    "--cmd", before_init, file, "-c", "cquit 0",
  }, { cwd = lost, env = { PWD = lost }, text = true }):wait(20000)
  t.eq(failed.code, 1, "an unavailable startup cwd exits with status 1")
  local diagnostic = failed.stderr or ""
  t.ok(diagnostic:find("Cannot start Nvim: current working directory is unavailable.", 1, true) ~= nil,
    "startup reports the unavailable cwd directly")
  t.ok(diagnostic:find("Original directory ($PWD): " .. (known_pwd and lost or "(unknown)"), 1, true) ~= nil,
    "the error names the original directory when known")
  t.ok(diagnostic:find("Change to an existing directory and start Nvim again.", 1, true) ~= nil,
    "the error explains how to retry")
  t.ok(not diagnostic:find("unexpected lazy load", 1, true) and not diagnostic:find("stack traceback", 1, true),
    "startup stops before loading plugins, without a Lua traceback")
end
vim.fn.delete(base, "rf")
t.done()
