local host = require("tillervim")
local catalog = dofile(host.root() .. "/starter/profile.lua")
local profile = catalog.read(host.config_root())
local companion = vim.iter(profile.ai):any(function(id) return id == "openai" or id:match("%-acp$") end)
return { selected = profile, themes = catalog.themes, bridges = catalog.bridges, companion = companion }
