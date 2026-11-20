-- Shared by the pre-install wizard and the distribution's spec resolver.
local M = {}
M.themes = {
  ["solarized-osaka"] = "craftzdog/solarized-osaka.nvim",
  tokyonight = "folke/tokyonight.nvim",
  catppuccin = "catppuccin/nvim",
  gruvbox = "ellisonleao/gruvbox.nvim",
  kanagawa = "rebelot/kanagawa.nvim",
  ["rose-pine"] = "rose-pine/neovim",
  nightfox = "EdenEast/nightfox.nvim",
  everforest = "sainnhe/everforest",
  onedark = "navarasu/onedark.nvim",
  nord = "shaunsingh/nord.nvim",
  dracula = "Mofiqul/dracula.nvim",
  material = "marko-cerovac/material.nvim",
  default = false, -- Built into Neovim.
}
M.languages = { "bash", "c", "dart", "frontend", "go", "java", "json", "python", "rust", "tex", "typescript", "yaml" }
M.bridges = {
  antigravity = { label = "Antigravity", adapter = "antigravity", command = "agy" },
  kimi = { label = "Kimi Code", adapter = "kimi_cli", command = "kimi" },
  opencode = { label = "OpenCode", adapter = "opencode", command = "opencode" },
  copilot = { label = "GitHub Copilot", adapter = "copilot_acp", command = "copilot" },
  vibe = { label = "Mistral Vibe", adapter = "mistral_vibe", command = "vibe-acp" },
}
M.ai = { "codex", "codex-acp", "antigravity", "antigravity-acp", "kimi", "kimi-acp", "opencode", "opencode-acp", "copilot-acp", "vibe-acp" }
M.defaults = {
  theme = "solarized-osaka", explorer = "oil", completion = "local", languages = M.languages,
  ai = { "codex", "codex-acp" },
}
function M.validate(profile)
  assert(type(profile) == "table" and not vim.islist(profile), "tillervim.json must contain an object")
  for key, value in pairs(profile) do
    assert(M.defaults[key] ~= nil, "Unknown preference: " .. key)
    if key == "theme" then
      assert(M.themes[value] ~= nil, "Unknown theme: " .. tostring(value))
    elseif key == "completion" then
      assert(value == "local" or value == "off", "completion must be local or off")
    elseif key == "explorer" then
      assert(value == "oil" or value == "tree", "explorer must be oil or tree")
    else
      assert(type(value) == "table" and vim.islist(value), key .. " must be an array")
      local seen = {}
      for _, item in ipairs(value) do
        assert(vim.tbl_contains(M[key], item), "Unknown " .. key .. " choice: " .. tostring(item))
        assert(not seen[item], "Duplicate " .. key .. " choice: " .. item)
        seen[item] = true
      end
    end
  end
  return vim.tbl_extend("force", vim.deepcopy(M.defaults), profile)
end

function M.read(root)
  local path = root .. "/tillervim.json"
  local stat, err, code = vim.uv.fs_stat(path)
  if not stat and code == "ENOENT" then return vim.deepcopy(M.defaults) end
  assert(stat, err)
  local raw = table.concat(vim.fn.readfile(path, "b"), "\n")
  local ok, value = pcall(function() return M.validate(vim.json.decode(raw)) end)
  assert(ok, path .. ": " .. tostring(value))
  return value, raw
end
return M
