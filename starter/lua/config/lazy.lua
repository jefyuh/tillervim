local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  local result = vim.system({ "git", "clone", "--filter=blob:none", "--branch=stable", "https://github.com/folke/lazy.nvim.git", lazypath }, { text = true }):wait()
  assert(result.code == 0, result.stderr)
end
local personal = vim.g.tillervim_config_root
local standard = vim.fn.stdpath("config")
local alternate = vim.uv.fs_realpath(personal) ~= vim.uv.fs_realpath(standard)
if alternate then
  -- lazy's default reset puts stdpath(config) before the -u host. Its
  -- unrelated lua/plugins would then silently override the selected profile.
  vim.opt.rtp:remove(standard)
  vim.opt.rtp:remove(standard .. "/after")
  vim.opt.rtp:prepend(personal)
  vim.opt.rtp:append(personal .. "/after")
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
  install = { colorscheme = { "default" } },
  checker = { enabled = true, notify = false, frequency = 86400 },
  performance = { rtp = { reset = not alternate, disabled_plugins = { "gzip", "tarPlugin", "tohtml", "zipPlugin" } } },
})
