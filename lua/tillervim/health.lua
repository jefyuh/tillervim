-- Host environment requirements and package health aggregation.
-- Loaded only by :checkhealth tillervim, never during startup.
local M = {}
local health = vim.health

-- External CLI tools the config relies on (not managed by Mason).
-- { executable, what needs it, required }
local executables = {
  { "git",     "version control, gitsigns, snacks pickers",            true },
  { "rg",      "ripgrep — snacks grep/search",                         true },
  { "fd",      "snacks file finding, venv-selector",                   false },
  { "node",    "AI ACP bridges, npm-based Mason servers, ,x runner and debugging for JS/TS", false },
  { "tmux",    "native AI TUI frame wrapper",                          false },
  { "go",      "go toolchain, ,x runner for Go",                       false },
  { "java",    "JDK 25+ runs jdtls; Java debugging",                   false },
  { "cargo",   "Rust binary and test debugging",                        false },
  { "dart",    "Dart debugging (or use a project FVM SDK)",             false },
  { "flutter", "Flutter debugging (or use a project FVM SDK)",          false },
  { "python3", "debugpy venv, ,x runner for Python",                    false },
  { "cc",      "Treesitter parser builds, ,x compile & run for C",      false },
  { "lazygit", "<leader>gg git UI",                                    false },
  { "curl",    "AI ghost-text requests and llama-server checks",       false },
  { "gh",      "<leader>G GitHub pickers and status",                  false },
}

-- Platform-gated tools, appended so `:checkhealth tillervim` elsewhere does not
-- warn about something that platform could never use.
if vim.fn.has("macunix") == 1 then
  table.insert(executables,
    { "macism", "macOS input-source switching between Normal and input", false })
end

-- nvim-treesitter's main branch builds every parser with `tree-sitter build`,
-- so without this CLI no parser installs or updates, and every
-- `build = ":TSUpdate"` asks for a rebuild. The floor is nvim-treesitter's own
-- (README requirements, TREE_SITTER_MIN_VER in its health.lua); compare the two
-- when an update lands, as lua/tillervim/plugins/ui/treesitter.lua notes for the Nvim floor.
local TREE_SITTER_MIN = "0.26.1"

local function check_tree_sitter()
  local fix = { "brew install tree-sitter-cli (a package manager's build, not npm's)" }
  if vim.fn.executable("tree-sitter") ~= 1 then
    health.error("tree-sitter not found — nvim-treesitter cannot build parsers", fix)
    return
  end
  local out = vim.system({ "tree-sitter", "--version" }, { text = true }):wait(5000)
  local version = vim.version.parse(out.stdout or "")
  if version and vim.version.ge(version, TREE_SITTER_MIN) then
    health.ok(("tree-sitter %s found — nvim-treesitter builds parsers with it"):format(tostring(version)))
  else
    health.error(("tree-sitter %s found — nvim-treesitter needs %s or later")
      :format(version and tostring(version) or "(unknown version)", TREE_SITTER_MIN), fix)
  end
end

-- Mason packages worth surfacing (Mason installs lazily, so absence is info).
local mason_packages = { "lua-language-server", "vtsls", "gopls", "prettier",
  "jdtls", "java-debug-adapter", "java-test", "codelldb", "delve", "js-debug-adapter" }

local function installed_mason_names()
  local ok, mr = pcall(require, "mason-registry")
  if not ok then
    return nil
  end
  return mr.get_installed_package_names()
end

function M.check()
  health.start("config: Neovim version")
  if vim.fn.has("nvim-0.12.5") == 1 then
    health.ok("Neovim " .. tostring(vim.version()))
  else
    health.error("Neovim >= 0.12.5 required (refactoring.nvim's minimum; nvim-treesitter main needs 0.12)")
  end

  health.start("config: external tools")
  for _, t in ipairs(executables) do
    local exe, why, required = t[1], t[2], t[3]
    if vim.fn.executable(exe) == 1 then
      health.ok(("%s found — %s"):format(exe, why))
    elseif required then
      health.error(("%s not found — needed for %s"):format(exe, why))
    else
      health.warn(("%s not found — %s unavailable"):format(exe, why))
    end
  end
  check_tree_sitter()

  require("editor_core.health").check()

  health.start("config: mason packages")
  local names = installed_mason_names()
  if not names then
    health.warn("mason.nvim is not installed (run :Lazy install)")
  else
    local set = {}
    for _, n in ipairs(names) do
      set[n] = true
    end
    for _, pkg in ipairs(mason_packages) do
      if set[pkg] then
        health.ok(pkg .. " installed")
      else
        health.info(pkg .. " not installed yet (Mason installs on demand)")
      end
    end
  end

  require("agent_workbench.health").check()
  require("git_review.health").check({ retention = require("agent_workbench.review.settings").get().retention })
  require("llama_service.health").check()
end

return M
