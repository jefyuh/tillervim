require("tillervim").prepare()
local specs = {
  { "jefyuh/tillervim", lazy = false, priority = 11000, config = function() require("tillervim").setup() end },
  -- Import order is merge order; language specs extend their feature owners.
  { import = "tillervim.plugins.editor" },
  { import = "tillervim.plugins.coding" },
  { import = "tillervim.plugins.ai" },
  { import = "tillervim.plugins.ui" },
  { import = "tillervim.plugins.git" },
}
local languages = vim.deepcopy(require("tillervim.profile").selected.languages)
table.sort(languages)
for _, lang in ipairs(languages) do
  specs[#specs + 1] = { import = "tillervim.plugins.lang." .. lang }
end
return specs
