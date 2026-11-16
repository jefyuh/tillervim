# TillerVim

**An agentic Neovim configuration. You steer. Agents work.**

[中文](README_CN.md) · [Manual](docs/MANUAL.md) · [Diagnostics](docs/DIAGNOSTICS.md)

TillerVim brings editing, native coding agents, chat and Git review into one
Neovim workspace. The distribution supplies working defaults; your own Neovim
configuration is a separate repository containing ordinary Lua and lazy.nvim specs.

## What is included

- **Native Codex** in an embedded terminal, with session resume, model selection,
  file/selection delivery, a real prompt editor and optional tmux rendering.
- **Optional chat transports:** CodeCompanion with Codex ACP and OpenAI HTTP.
  The new-chat picker chooses the transport explicitly. One AI panel is shown
  per tab, while hidden sessions remain alive.
- **Review rounds:** immutable Git snapshots, changes-since-baseline views in
  CodeDiff, and feedback drafts delivered back to the owning conversation.
- **Editing:** Oil, Snacks pickers, Treesitter, LSP, completion, formatting,
  debugging and language-specific runners.
- **Optional local ghost text:** Minuet and the bundled llama-service package.
  Its model starts only with an attached UI and an eligible file, never headless.

Only Codex has a native backend in this release. Chat/HTTP integrations and
local completion are independent of the native terminal. Setup starts no agent,
chat, review baseline or model.

## Requirements

Neovim **0.12.5+**, Git, ripgrep and a terminal with a Nerd Font are the basics.
Language features need their corresponding toolchains; Treesitter parser builds
need a C compiler and tree-sitter-cli **0.26.1+**.

For the native terminal install and authenticate the `codex` CLI. `tmux` enables
its preferred frame wrapper. ACP chat additionally needs `codex-acp`; HTTP chat
reads `NVIM_OPENAI_API_KEY`, independently of CLI credentials. Run
`:checkhealth tillervim` for the complete dependency report.

## Install

Start with a new or backed-up Neovim configuration directory. Copy the bundled
starter, **not the distribution source**, into your configuration:

```sh
tillervim_source="$(mktemp -d)"
git clone --depth 1 https://github.com/jefyuh/tillervim.git "$tillervim_source"
mkdir -p ~/.config/nvim
cp -R "$tillervim_source/starter/." ~/.config/nvim/
nvim
```

lazy.nvim installs TillerVim and its dependencies on first launch. Commit your
own configuration and `lazy-lock.json` to your own repository. Use `:Lazy` to
review updates. Updating TillerVim does not rewrite your personal files.

The starter loads the distribution first, then your plugin specs:

```lua
require("lazy").setup({
  spec = {
    { "jefyuh/tillervim", import = "tillervim.plugins" },
    { import = "plugins" },
  },
  defaults = { lazy = true, version = false },
  rocks = { enabled = false },
})
```

The complete bootstrap is in [starter/](starter/). Leaders are set in its
`init.lua` before plugin keys are resolved; the default leader is Space and the
local leader is comma.

## Personal configuration

```text
~/.config/nvim/
├── init.lua
├── bootstrap.lua      # Early loader/cwd validation
├── lua/config/
│   ├── lazy.lua       # Plugin manager and imports
│   ├── options.lua    # vim.opt and vim.g, after editor defaults
│   ├── keymaps.lua    # vim.keymap.set/del, after default mappings
│   └── autocmds.lua   # Your autocommands
├── lua/plugins/       # Native lazy.nvim specs: additions and overrides
└── lazy-lock.json     # Versions of your installed distribution and plugins
```

TillerVim loads these optional user files once. Options load after editor-core
settings and before other startup plugins; autocommands and mappings load at
`User LazyDone`. The starter records its own source directory, so configuration
navigation follows the active config even when launched with `nvim -u /path/init.lua`.

Use the plugin's documented options. For example, `lua/plugins/oil.lua`:

```lua
return {
  "stevearc/oil.nvim",
  opts = { view_options = { show_hidden = false } },
}
```

Plugin specs merge using lazy.nvim's own rules. Tables in `opts` merge; use an
`opts` function to edit inherited lists or settings, and `keys` to customize
lazy mappings. A different key is a different mapping: disable the old key in
the same mode when adding a replacement. You can also edit the inherited list.
For example, move Dial's increment key in both Normal and Visual modes while
preserving its callbacks, expression flags and read-only guard:

```lua
-- lua/plugins/dial.lua
return {
  "monaqa/dial.nvim",
  keys = function(_, keys)
    for _, key in ipairs(keys) do
      if key[1] == "<C-a>" then key[1] = "<M-a>" end
    end
    return keys
  end,
}
```

Ordinary global mappings use Neovim directly:

```lua
-- lua/config/keymaps.lua
vim.keymap.del("n", "<leader>qq")
vim.keymap.set("n", "<leader>qq", "<cmd>confirm qa<cr>", { desc = "Quit all" })
```

There is no action-name keymap registry or shared key configuration language.
Oil, Snacks and Aerial each use their own native mapping options. Which-key
shows metadata; `<leader>?` reads the mappings actually installed.

Our own packages expose their own options and callable APIs. For example:

```lua
-- lua/plugins/agent.lua
return {
  "agent-workbench.nvim",
  opts = { terminal = { provider = "native" }, panel = { width = 100 } },
}
```

See the package documentation for [Agent Workbench](local-plugin/agent-workbench.nvim/README.md),
[editor-core](local-plugin/editor-core.nvim/README.md),
[git-review](local-plugin/git-review.nvim/README.md) and
[llama-service](local-plugin/llama-service.nvim/README.md).
Do not edit the installed distribution's private `tillervim.config.*` modules.

## Everyday keys

| Prefix/key | Purpose |
| --- | --- |
| `;` | Find a file, symbol or position |
| `,` | Act on the current file or view |
| `s` | Arrange windows |
| `<leader>` | Global domains: AI, Git, debug, UI and sessions |
| `<leader>an` / `al` | New / switch AI chat |
| `<leader>ac` / `af` | Toggle / focus AI chat |
| `<leader>ar` / `aR` / `am` | Resume / continue / select native model |
| `<leader>ab` / `as` / `ai` | Add file / selection / compose prompt |
| `<leader>aV` / `av` | Start review round / review changes since baseline |
| `,C` in Git views | Write review feedback |
| `<leader>ax` / `ae` | Select HTTP key profile / inline edit |
| `<leader>?` | Show live keybinding guide |

Native Codex uses `--no-alt-screen --yolo` by default; customize
`opts.native.codex.args` on `agent-workbench.nvim` to change its launch policy.
HTTP adapters use `NVIM_*` key variables. Codex ACP uses ChatGPT authentication.
Nothing writes billing credentials into the environment.

The [manual](docs/MANUAL.md) explains full editing, debugging and review workflows.

## Development

The root `init.lua` is a development/test host for this checkout. Installed users
start from `starter/init.lua`. Distribution modules live under `lua/tillervim/`;
local packages resolve their scripts relative to their own source.

```sh
make verify                 # Whitespace, startup and the complete spec suite
make test S="dial user_config"
make health
```

Tests run sequentially, use offline agent stand-ins and never start a real AI
turn. The user-config integration test starts a separate host and verifies
native plugin overrides, mapping removal, load order and profile relabelling.
