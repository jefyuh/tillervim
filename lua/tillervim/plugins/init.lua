require("tillervim").prepare()
return {
  { "jefyuh/tillervim", lazy = false, priority = 11000, config = function() require("tillervim").setup() end },
  -- Import order is merge order; language specs extend their feature owners.
  { import = "tillervim.plugins.editor" },
  { import = "tillervim.plugins.coding" },
  { import = "tillervim.plugins.ai" },
  { import = "tillervim.plugins.ui" },
  { import = "tillervim.plugins.git" },
  { import = "tillervim.plugins.lang" },
}
