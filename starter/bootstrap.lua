-- Run before lazy.nvim can normalize a missing working directory.
vim.loader.enable()

-- A shell can outlive its deleted directory (for example, a removed worktree).
-- Stop before plugins load instead of guessing a different working directory.
-- Missing target files or parent directories are allowed; only the process cwd
-- must exist. This runs once at startup, so it never quits an editing session.
if not vim.uv.cwd() then
  io.stderr:write(("Cannot start Nvim: current working directory is unavailable.\n"
    .. "Original directory ($PWD): %s\n"
    .. "Change to an existing directory and start Nvim again.\n"):format(vim.env.PWD or "(unknown)"))
  -- Exit before plugin setup or file editing. A fatal exit keeps stderr visible
  -- in the terminal; :cquit would restore the screen over the diagnostic.
  os.exit(1)
end
