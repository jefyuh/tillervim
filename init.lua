-- Development/test host. Installations use starter/init.lua in their own config.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
dofile(root .. "/starter/bootstrap.lua")
vim.opt.rtp:prepend(root)
vim.g.tillervim_config_root = root
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  local result = vim.system({ "git", "clone", "--filter=blob:none", "--branch=stable", "https://github.com/folke/lazy.nvim.git", lazypath }, { text = true }):wait()
  assert(result.code == 0, result.stderr)
end
vim.opt.rtp:prepend(lazypath)
require("lazy").setup({
  spec = { { dir = root, name = "tillervim", import = "tillervim.plugins" } },
  defaults = { lazy = true, version = false },
  lockfile = root .. "/lazy-lock.json",
  rocks = { enabled = false },
  install = { colorscheme = { "solarized-osaka" } },
  checker = { enabled = false },
  performance = { rtp = { reset = false, paths = { root }, disabled_plugins = { "gzip", "tarPlugin", "tohtml", "zipPlugin" } } },
})
