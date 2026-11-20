# Initial setup and personal profiles

Copy the starter into your personal Neovim configuration directory. Run the wizard before the first Neovim launch, so lazy.nvim sees your language, theme and provider choices before resolving plugins.

```sh
~/.config/nvim/bin/tillervim setup
~/.config/nvim/bin/tillervim sync
~/.config/nvim/bin/tillervim doctor
```

The command targets the starter containing the script. Pass `--config /path/to/personal` before the subcommand to select another host. For an existing installation, update the distribution first, then copy `bin/tillervim`, `configure.lua` and `profile.lua` from the matching starter. For multiple personal configurations launched with `-u`, merge the runtimepath handling in the [starter loader](../starter/lua/config/lazy.lua) so overrides come from the requested host.

**setup** writes `tillervim.json` atomically in that directory. Press Enter to keep an answer, enter comma-separated IDs to select several, or enter `none` for an empty list. With flags, omitted settings keep their values. Use `--defaults` to accept existing or distribution defaults without prompts.

```sh
~/.config/nvim/bin/tillervim setup --theme tokyonight --explorer tree \
  --languages go,python --completion off \
  --ai codex,antigravity,kimi,opencode,antigravity-acp,kimi-acp,opencode-acp
```

**sync** uses the personal init, installs missing lazy.nvim plugins and Mason tools, and checks that selected parsers and CodeDiff's native library load. Missing prerequisites or failed targets produce a nonzero exit. Fix the reported issue and rerun. Disabled modules stop requesting their packages. Use lazy.nvim for upgrades and lockfile management.

**doctor** checks the host, selected SDKs, CLIs and Codex login before loading any plugins. Missing core dependencies produce a nonzero exit. Optional tools, credentials and Java degradation are reported individually. Inside Neovim, `:checkhealth tillervim` reports effective plugin and tool health. `:AI info` lists configured transports and sessions.

## Profile fields

| Field | Choices |
| --- | --- |
| `theme` | `solarized-osaka`, `tokyonight`, `catppuccin`, `gruvbox`, `kanagawa`, `rose-pine`, `nightfox`, `everforest`, `onedark`, `nord`, `dracula`, `material`, or Neovim's built-in `default`. Only the selected theme enters the plugin spec. |
| `explorer` | `oil` for editable directory listings or `tree` for Snacks Explorer. Directory arguments, editing a directory, dashboard Browse files, `-` and `;o` use your selection. Oil opens `;o` in a float. Tree opens a sidebar. |
| `languages` | Any of `bash,c,dart,frontend,go,java,json,python,rust,tex,typescript,yaml`. Each module contributes its tools, plugins, LSP and runners. Lua is part of the editor core. Browsing an unselected filetype can still install its syntax parser on demand. |
| `completion` | `local` enables Minuet ghost text with a separately provisioned llama-server and model. `off` skips Minuet. Ordinary completion works independently. |
| `ai` | An array of the individual transport IDs below. An empty array disables the preset chats. |

Existing configurations without a profile retain Solarized Osaka, Oil, all language modules, local ghost text and the Codex terminal/ACP transports. Omitted JSON fields inherit those defaults. Put ordinary keymaps in personal `lua/config/keymaps.lua`, and plugin keys, theme variants and advanced overrides in `lua/plugins/*.lua`. Restart after changing choices and sync new dependencies. See [personal configuration](../README.md#personal-configuration).

With Tokyo Night selected, a personal plugin spec can return `{ { "folke/tokyonight.nvim", opts = { style = "moon" } } }`. Everforest and Nord read upstream `vim.g` settings in the spec’s `init`.

For example, a personal profile can enable Python, the tree and both Kimi transports.

```json
{
  "theme": "kanagawa",
  "explorer": "tree",
  "languages": ["python"],
  "ai": ["kimi", "kimi-acp"],
  "completion": "off"
}
```

## Terminal and chat providers

| Product | Native terminal ID and executable | CodeCompanion ACP ID and command |
| --- | --- | --- |
| Codex | `codex` → `codex` | `codex-acp` → separate `codex-acp` bridge with ChatGPT authentication |
| Antigravity | `antigravity` → `agy` | `antigravity-acp` → `agy acp`, requires an ACP-capable CLI version |
| Kimi Code | `kimi` → `kimi` | `kimi-acp` → `kimi acp` |
| OpenCode | `opencode` → `opencode` | `opencode-acp` → `opencode acp` |
| [GitHub Copilot CLI](https://docs.github.com/en/copilot/reference/copilot-cli-reference/acp-server) | — | `copilot-acp` → `copilot --acp --stdio` |
| [Mistral Vibe](https://docs.mistral.ai/vibe/code/use-vibe-in-other-ides) | — | `vibe-acp` → `vibe-acp` |

Declare optional HTTP chat and inline-editing providers explicitly in personal `agent-workbench.nvim` `opts.providers`, setting `api_key` to `"$VAR"`, a literal secret, or `function() -> string|nil`. Diagnostics report availability without exposing secret values.

Use `<Space>an` to start a session, `<Space>al` to switch, and `<Space>ac` to hide or show it. Each native agent keeps its own embedded PTY. Pasted file references and selections remain drafts. The additional CLIs use their own permissions, model selection and session history; Antigravity launches with session-only `altScreenMode` enabled for flicker-free rendering and bounded viewport scrolling. Kimi supports a cold-start session picker, and all three additional native agents can continue their latest session. Codex also integrates the tmux renderer, external prompt editor, transcript reader and native round hooks. Choose the ACP transport for integrated chat review with the other agents. [Antigravity ACP](https://antigravity.google/docs/cli/acp) · [Kimi ACP](https://moonshotai.github.io/kimi-code/en/reference/kimi-acp.html) · [OpenCode ACP](https://opencode.ai/docs/cli/acp/)

## Machine dependencies

Provide Neovim 0.12.5+, Git and a C compiler. Full-text search uses ripgrep, and parser builds require tree-sitter CLI 0.26.1+. On macOS, setup can install those two missing packages with an existing Homebrew installation. Pass `--install-core` for unattended installation. fd, a Nerd Font and tmux enhance particular features.

The distribution installs editor-owned plugins, parsers and Mason packages for the selected modules. Provide project SDKs through your normal toolchain manager. A Java 17 project can keep using Java 17 for builds. The pinned jdtls needs JDK 25+ for its own JVM. With only 17 present, editing and highlighting remain available. Install a compatible JDK alongside 17, save and run `:edit` to attach the server. Resolution checks JAVA_HOME, SDKMAN and PATH.

The wizard detects existing agent executables. With Codex selected and installed, `setup --login` can launch the official login flow. Use `kimi login`, `opencode auth login`, or sign in inside `agy` for the other CLIs. GitHub features use an existing `gh auth login`. Use `:MasonLog` for package failures and the [diagnostics guide](DIAGNOSTICS.md) for dependency, environment and runtime details.

## Changing choices and recovering from errors

- **Keep existing entries.** Each of `--ai` and `--languages` replaces its entire list. To add ACP to a Kimi-only profile, pass `--ai kimi,kimi-acp`. To change only the theme, pass only `--theme kanagawa`. Restart Neovim to load the new plugin selection.
- **Repair a profile.** For invalid JSON, unknown names or duplicate entries, correct the `tillervim.json` at the path in the error and rerun setup. If the file changed while the wizard was open, rerun setup to read the latest choices.
- **Resume after an interruption.** Run doctor to check core tools, then retry sync. Inspect `:MasonLog` for a failed Mason install. For a parser that fails to load, follow the reported `:TSInstall! parser-name` command. If you cancelled Codex authorization after saving a profile, rerun `setup --login`.
