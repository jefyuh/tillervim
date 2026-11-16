-- Host bootstrap, run before lazy.nvim imports plugin specs.
-- Editor options, mappings and behaviors are applied later by editor-core.nvim.

-- Cache the Lua modules loaded from here on, before lazy.nvim enables it too.
vim.loader.enable()

dofile(require("tillervim").root() .. "/starter/bootstrap.lua")

local cwd = require("tillervim.util.cwd")

-- Capture an absolute argument before plugins can change the buffer or cwd.
-- Apply only once, after startup has resolved every relative file argument.
local first = vim.fn.argc() > 0 and vim.fn.argv(0) or nil
if type(first) == "string" and first ~= "-" and not first:match("^%a[%w+.-]*://") then
  local path = vim.fn.fnamemodify(first, ":p")
  local initial_cwd = vim.fn.getcwd()
  vim.api.nvim_create_autocmd("VimEnter", {
    group = vim.api.nvim_create_augroup("startup_cwd", { clear = true }),
    once = true,
    desc = "Set startup cwd from the first file or directory",
    callback = function()
      -- Respect an explicit :cd/:lcd/:tcd or a restored session's directory.
      if vim.fn.getcwd() ~= initial_cwd or vim.fn.haslocaldir() ~= 0 then return end
      local target = cwd.startup_dir(path)
      if target then vim.cmd.cd(vim.fn.fnameescape(target)) end
    end,
  })
end

-- Lazy expands <leader> in plugin keys, so both leaders must already be set.
vim.g.mapleader = vim.g.mapleader or " "
vim.g.maplocalleader = vim.g.maplocalleader or ","

-- Expose debug printing during plugin setup; load its tools only on first use.
_G.dd = function(...) return require("tillervim.util.debug").dump(...) end
vim.print = _G.dd
