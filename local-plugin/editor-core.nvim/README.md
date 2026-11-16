# editor-core.nvim

Editor preferences, foundational mappings/autocommands, window/buffer operations
and the keybinding guide. Requiring the module is inert. A high-priority
`lazy = false` local spec calls `require("editor_core").setup(opts)` once.

Options: `options` (public Vim option overrides), `theme` (UI options/glyphs),
`formatting` (autoformat), `behaviors` (optional input-method/cursor/yank/autoread
behavior), `keymaps` (boolean, defaults to true), and
`url.buffer_dir` (optional host directory callback). `keymaps = false` installs
no mappings. Configure individual mappings with ordinary `vim.keymap.set/del`
after setup. Callable feature APIs remain available without the default keys.

Distribution defaults live under `lua/tillervim/config/`; personal overrides use
the native lazy.nvim spec. The runtime owns private compatibility
settings and behavior. `editor_core.options`, `keymaps`, `autocmds` apply them;
which-key renders metadata and is not required for actions or the generated
`editor_core.keyguide.show()` guide. Oil, Snacks and Aerial specs translate the
shared open declarations explicitly into their supported upstream actions.

The host passes dashboard data to `editor_core.dashboard.build(data, extra_sections)`
from the Snacks spec. The optional callback supplies content when the dashboard
renders; it is not called during setup. Layout and viewport behavior belong here;
quotes/keys and optional GitHub integration belong to the host.
`:checkhealth editor_core` checks input-source switching and editor logs. The
host's aggregator owns its external-tool, Mason and plugin/version requirements.
Reusable window, buffer, terminal-text, URL, DAP and LSP operations are documented
in the host's `docs/UTILITIES.md`. They import no private host config/util modules.
