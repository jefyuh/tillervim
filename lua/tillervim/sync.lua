-- Install missing targets of the active personal host, without updating or cleaning.
local M = {}
local function options(name)
  local plugin = require("lazy.core.config").plugins[name]
  return plugin and require("lazy.core.plugin").values(plugin, "opts", false) or {}
end

function M.run()
  local lazy = require("lazy.core.config")
  for _, notice in ipairs(lazy.spec.notifs) do
    if notice.level == vim.log.levels.ERROR then error(notice.msg) end
  end
  local missing_plugins = vim.tbl_filter(function(plugin)
    return not plugin.virtual and not vim.uv.fs_stat(plugin.dir)
  end, vim.tbl_values(lazy.plugins))
  if #missing_plugins > 0 then require("lazy").install({ wait = true, show = false }) end
  for name, plugin in pairs(lazy.plugins) do
    assert(plugin.virtual or vim.uv.fs_stat(plugin.dir), "Missing plugin: " .. name)
    for _, task in ipairs(plugin._.tasks or {}) do assert(not task:has_errors(), "Plugin install failed: " .. name) end
  end
  if lazy.plugins["mason.nvim"] then
    local registry = require("mason-registry")
    local ready = false
    registry.refresh(function() ready = true end)
    assert(vim.wait(120000, function() return ready end), "Mason registry timed out")
    local targets = {}
    for key, config in pairs(options("nvim-lspconfig").tools or {}) do
      if type(key) == "number" then targets[config] = {} else targets[key] = config end
    end
    local function add_mapped_tools(identifiers, mapping)
      for _, identifier in ipairs(identifiers) do
        local name, version = require("mason-core.package").Parse(identifier)
        local pkg = assert(mapping[name], "No Mason package for " .. identifier)
        targets[pkg] = targets[pkg] or {}
        if version then targets[pkg] = { version = version } end
      end
    end
    if lazy.plugins["mason-lspconfig.nvim"] then
      local names = require("mason-lspconfig.mappings").get_mason_map().lspconfig_to_package
      add_mapped_tools(options("mason-lspconfig.nvim").ensure_installed or {}, names)
    end
    if lazy.plugins["mason-nvim-dap.nvim"] then
      local mapping = require("mason-nvim-dap.mappings.source").nvim_dap_to_package
      local opts = vim.tbl_deep_extend("force", {
        ensure_installed = vim.tbl_keys(options("nvim-dap").handlers or {}),
      }, options("mason-nvim-dap.nvim"))
      add_mapped_tools(opts.ensure_installed, mapping)
    end
    local packages = {}
    for name, config in pairs(targets) do
      local pkg = registry.get_package(name)
      packages[name] = pkg
      if not pkg:is_installed() and not pkg:is_installing() then
        if type(config) == "function" then config = config() end
        pkg:install(config)
      end
    end
    assert(vim.wait(900000, function()
      for _, pkg in pairs(packages) do if pkg:is_installing() then return false end end
      return true
    end, 200), "Mason install timed out")
    local missing = {}
    for name, pkg in pairs(packages) do if not pkg:is_installed() then table.insert(missing, name) end end
    assert(#missing == 0, "Mason install failed: " .. table.concat(missing, ", ") .. " (see :MasonLog)")
  end
  if lazy.plugins["nvim-treesitter"] then
    for _, parser in ipairs(options("nvim-treesitter").ensure_installed or {}) do
      assert(vim.treesitter.language.add(parser), "Cannot load parser: " .. parser .. ". Run :TSInstall! " .. parser)
    end
  end
  if lazy.plugins["codediff.nvim"] then
    local diff = require("codediff.core.diff")
    assert(diff.get_version(), "CodeDiff native library is unavailable")
  end
  assert(vim.v.errmsg == "", vim.v.errmsg)
  print("TillerVim sync complete")
end
return M
