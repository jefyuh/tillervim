-- Leaders are set before lazy.nvim expands plugin keys.
vim.g.mapleader = " "
vim.g.maplocalleader = ","
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
dofile(root .. "/bootstrap.lua")
vim.g.tillervim_config_root = root
vim.opt.rtp:prepend(root)
require("config.lazy")
