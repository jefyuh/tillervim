-- Public distribution entry point. Requiring it starts no plugins or processes.
local M = {}
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
local prepared, configured = false, false
local loaded = {}
function M.root() return root end
function M.config_root()
  return vim.g.tillervim_config_root or vim.fn.stdpath("config")
end

function M.load_user(name)
  if loaded[name] then return end
  loaded[name] = true
  local path = M.config_root() .. "/lua/config/" .. name .. ".lua"
  if vim.fn.filereadable(path) == 0 then return end
  local chunk = assert(loadfile(path))
  local ok, value = xpcall(chunk, debug.traceback)
  if not ok then error("TillerVim: " .. path .. "\n" .. tostring(value)) end
  package.loaded["config." .. name] = value == nil and true or value
end

-- Called during spec import, before lazy.nvim resolves mapping leaders.
function M.prepare()
  if prepared then return end
  prepared = true
  require("tillervim.bootstrap.setup")
  -- These packages ship inside this repository. Register their runtime paths
  -- explicitly; virtual lazy specs configure them without cloning/cleaning
  -- nested directories inside lazy.nvim's managed root.
  for _, name in ipairs({ "editor-core", "agent-workbench", "git-review", "llama-service" }) do
    vim.opt.rtp:append(root .. "/local-plugin/" .. name .. ".nvim")
  end
  -- Virtual lazy packages already sit on rtp, which would otherwise satisfy
  -- require() before lazy.nvim's autoloader can run their setup(opts).
  local lazy_packages = { git_review = "git-review.nvim", llama_service = "llama-service.nvim" }
  local loading = {}
  table.insert(package.loaders, 2, function(mod)
    local head = mod:match("^([%w_]+)")
    local plugin = head and lazy_packages[head]
    if not plugin or loading[plugin] then return nil end
    local cfg = package.loaded["lazy.core.config"]
    local spec = cfg and cfg.plugins and cfg.plugins[plugin]
    if not spec or spec._.loaded then return nil end
    loading[plugin] = true
    package.loaded[mod] = nil
    local ok, err = pcall(function() require("lazy").load({ plugins = { plugin } }) end)
    loading[plugin] = false
    assert(ok, err)
    local loaded_mod = package.loaded[mod]
    if type(loaded_mod) == "table" then
      return function() return loaded_mod end
    end
    return nil
  end)
end

function M.setup()
  if configured then return end
  configured = true
  -- All startup mappings and lazy key handlers exist before user overrides.
  vim.api.nvim_create_autocmd("User", {
    group = vim.api.nvim_create_augroup("tillervim_user_config", { clear = true }),
    pattern = "LazyDone", once = true,
    callback = function()
      M.load_user("autocmds")
      M.load_user("keymaps")
    end,
  })
end
return M
