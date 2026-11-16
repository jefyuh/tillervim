local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  local result = vim.system({ "git", "clone", "--filter=blob:none", "--branch=stable", "https://github.com/folke/lazy.nvim.git", lazypath }, { text = true }):wait()
  assert(result.code == 0, result.stderr)
end
vim.opt.rtp:prepend(lazypath)
require("lazy").setup({
  spec = {
    { "jefyuh/tillervim", import = "tillervim.plugins" },
    { import = "plugins" },
  },
  defaults = { lazy = true, version = false },
  lockfile = vim.g.tillervim_config_root .. "/lazy-lock.json",
  rocks = { enabled = false },
  install = { colorscheme = { "solarized-osaka" } },
  checker = { enabled = true, notify = false, frequency = 86400 },
  performance = { rtp = { paths = { vim.g.tillervim_config_root }, disabled_plugins = { "gzip", "tarPlugin", "tohtml", "zipPlugin" } } },
})
