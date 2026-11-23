# agent-workbench.nvim

A native Codex, Antigravity, Kimi Code and OpenCode CLI workbench for Neovim 0.12.5+. It owns the terminal
session, context delivery, prompt editor and per-tab chat routing. Claude is a
future extension; declaring `tui.kind = "claude"` is rejected in this release.
Historical Claude transcripts remain readable for existing review baselines.

```lua
-- A normal lazy.nvim local spec. Requiring the module itself is inert.
{
  dir = "/absolute/path/to/agent-workbench.nvim",
  main = "agent_workbench",
  cmd = { "AI", "AIInfo" },
  opts = {
    terminal = { provider = "native" }, -- no Snacks dependency
    native = { codex = { command = "codex", wrap_tmux = true } },
  },
  keys = {
    { "<leader>ac", function() require("agent_workbench").toggle() end, desc = "Toggle AI chat" },
    { "<leader>as", function() require("agent_workbench").send_selection() end, mode = "x", desc = "Add selection to AI chat" },
  },
}
```

Use `terminal.provider = "snacks"` and declare `folke/snacks.nvim` in the host
when choosing Snacks. Missing selected providers fail; there is no automatic
fallback. The terminal provider and tmux renderer are independent choices.
External terminals without a Neovim PTY/buffer are not supported in this release.

The additional native kinds use independent per-kind sessions and their CLI defaults. Set `native.<kind>.command` and `native.<kind>.args` to override the launch command. Codex and Antigravity compose DEC 2026 TUI frames through dedicated `tmux` wrappers (`wrap_tmux = true`) when `tmux` is installed; Codex also owns its external editor and native review hooks. When a UI is attached, `<C-v>` in native agent panels and the prompt editor renders non-focusable `[Image #N]` thumbnail cards (via optional `Snacks.image` when present, or a compact badge fallback; `<M-p>` / Normal `<localleader>p` folds, `<M-n>` cycles, `<M-x>` / Normal `<localleader>d` dismisses). See the [transport matrix](../../docs/SETUP.md#terminal-and-chat-providers).

## Options and lifecycle

`setup(opts)` runs once. It copies declarations; dictionaries accept partial
overrides and ordered lists replace, including empty `native.codex.args = {}`.
`false` disables an optional integration. Invalid declarations fail at
setup/startup with the setting/provider name; invalid live `vim.g.ai_review`
leaves warn once and retain valid siblings. Edit setup values and restart to
reconfigure. Session state and the selected HTTP profile are separate live state.

| Option | Type / default | Meaning |
| --- | --- | --- |
| `providers` | ordered table list; one Codex native entry | Unique `name`, `label`, optional `cli_api_key`, and `tui`, `acp`, `api` parts. Supported native kinds are `codex`, `antigravity`, `kimi` and `opencode`. |
| `native.codex.command` | string; `"codex"` | Executable or absolute executable path. |
| `native.codex.args` | string list; `{ "--no-alt-screen", "--yolo" }` | Base argv, preserved for new/resume/continue. The host's existing execution policy is retained. |
| `native.codex.wrap_tmux` | boolean; `true` | Frame composition/scrollback wrapper when tmux is installed. |
| `native.codex.teardown_ignore` | string; shared daemon ERE | `awk` ERE of child daemon processes spared during tmux teardown. |
| `native.antigravity.args` | string list; `{ "--settings", '{"altScreenMode":"always"}' }` | Session-only alternate-screen mode in `agy` for bounded viewport scrolling. |
| `native.antigravity.wrap_tmux` | boolean; `true` | Offscreen DEC 2026 frame composition wrapper when `tmux` is installed (leaves mouse wheel passthrough intact in `altScreenMode`). |
| `terminal.provider` | `"native"`, `"snacks"`, provider table; `"native"` | PTY/view owner. |
| `panel.width` | positive integer; `90` | Native/chat panel width in columns. |
| `plugin_dirs` | ordered string list; `{}` | Local plugins for native Codex and Antigravity terminals, staged at launch. Codex shares its plugin cache. Antigravity uses a temporary plugin workspace. |
| `integrations.companion` | boolean; `false` | Enable the optional CodeCompanion chat/inline integration. The host installs/configures CodeCompanion. |
| `integrations.review` | boolean; `false` | Enable prompt hooks and review events. The host supplies git-review.nvim and CodeDiff. |
| `key_profile` | string; `"auto"` | Startup HTTP profile (`"auto"` or a configured `api` profile name). |
| `review` | table | Partial review policy; live `vim.g.ai_review` overrides it. See the host manual for every field. |
| `callbacks` | optional function table | `project_root(path)`, `editor_win()`, `origin_tab(tab)`, `notify_error(error)`, `toggle_zoom(win)`; native defaults require no private host module. |

A provider's `acp = { adapter, command, auth_method? }` identifies a CLI bridge.
`api = { adapter, api_key, name?, label?, model? }` identifies an HTTP profile;
`api_key` accepts `"$VAR"` (environment variable), a literal key string, or `function() -> string|nil` (never a CLI billing variable). The host's built-in
OpenAI/Anthropic adapter safeguards and Codex `chat-gpt` ACP authentication stay
in place. Switching HTTP profiles does not restart or move a terminal/chat.

Global mappings belong to the host's lazy.nvim `keys` specs. The package
installs no global mappings. Bind public methods such as `new_chat`, `toggle`,
`compose`, `review` and `inline` directly. HTTP profile changes emit
`User AIStateChanged`; hosts may update display metadata without remapping keys.

Setup installs the cheap command/input/slot facade. It starts no CLI, listener,
model, baseline or plugin installer. Native providers load at first use;
CodeCompanion and review/storage load only for their enabled workflow.

## Public operations

```lua
local agent = require("agent_workbench")
local session, err = agent.open("codex", { mode = "new" })
-- modes: new, resume, continue, model; a running session is reused
agent.send_context("native:codex", { text = "draft text" }) -- never submits
agent.send_context("codex", { path = "/absolute/file.lua", modified = false })
agent.hide("codex") -- hide only this tab's owned window, keep process/buffer
agent.show("codex")
agent.stop("codex") -- explicit teardown, idempotent
```

`open/show` return a copied session or `nil, { code, message }` on failure.
`hide/stop/send_context` return success or `false, { code, message }` for a
refusal. `open`, `show`, `hide`, `stop`, `send_context` target native backends;
ACP/API chats use the host facade/pickers. A copy visible in the current tab is
focused there; no second terminal is opened beside it. Other-tab and last-normal-
window hides are refused. Floats do not count as another normal window. A provider's
hide refusal is reported and prevents switching; if a new view had to open first,
it is hidden again. Invalid context fields are refused before opening a session.
File mentions resolve from the running session's root; captured saved selections
use absolute paths because the recipient may belong to another project.

`session(id)`, `sessions()`, `session_of_buffer(buf)`, `backends()` and `options()`
return copied observations. A session contains `id`, `kind`, `generation`,
`root`, `buf`, owned `win`, `alive`, and optional `exit_code`. Buffer identity is
plugin-owned metadata, independent of Snacks. `AgentWorkbenchSessionChanged`
announces registry changes. `key.use(name)` / `key.info()` manage HTTP state.

The host facade also supplies `new_chat`, `switch_chat`, `toggle`, `focus`, `zoom`,
`add_buffer`, `send_selection`, `compose`, `resume`, `continue`, `select_model`,
`transcript`, `transcript_pick`, `review`, and `new_round`. `:AI` opens the chat
switcher; `:AI new`, `:AI info`, `:AI key [name]` and `:AIInfo` are its command
entrypoints. `:AI provider` explains its removal. Internal state, backend test
hooks (`_...`), CodeCompanion internals and tmux handles are not a stable API.

## Embedded terminal provider

A custom table implements the following functions (ordinary functions, not
colon methods):

```lua
open(request)              --> opaque_handle | nil, {code, message}
show(handle, request)      --> owned_window | nil, error
hide(handle, tab)          --> true | false, error
send(handle, exact_bytes)  --> true | false, error
alive(handle)             --> boolean
stop(handle)              --> true | false, error
```

`request` supplies `argv`, absolute `cwd`, `env`, `width`, plus callbacks:
`on_buffer(buf)` **before TermOpen**, `on_view(win)` for each owned view, and
`on_exit(code)` when the PTY ends. The embedded buffer must be a Neovim terminal
with its channel available through `vim.bo[buf].channel`. Other handle contents
remain private. The coordinator tracks identity/generation/owned views; it never
looks up a Snacks terminal or copies a provider's private fields.

`send` preserves exact bytes and never appends Enter. `hide` preserves the PTY
and buffer; the coordinator refuses another tab, the last normal window and an
unowned copy. `stop` releases owned PTY/view resources. Providers clean partial
opens; the coordinator also releases any reported buffer on failure. Exit
callbacks are generation-scoped, so an old process cannot remove a replacement.
A nonzero exit keeps diagnostics visible; a successful exit closes its panel.
Native launch owns the tmux watchdog and descendant teardown, rather than each
provider implementing another process-tree policy.

The host's `tests/plugin_contract_spec.lua` runs real offline PTYs with native,
Snacks and custom providers in minimal hosts that reject private host imports.
It verifies exact CJK/space argv and context, process reuse, hide/show/stop,
copies, last-window/floats, stale callbacks, partial-open cleanup, surfaced send
refusals and retryable stop refusals. No AI turn
or network request runs in these fixtures.
