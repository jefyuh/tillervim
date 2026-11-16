-- LSP rename with a live preview: every occurrence updates in the buffer while
-- the new name is still being typed on the cmdline, and <Esc> leaves the code
-- untouched. Same interaction model as `inccommand = "split"` in
-- local-plugin/editor-core.nvim/lua/editor_core/options.lua, applied to rename instead of :substitute.
--
-- Reached through `,r` on an LSP buffer (lua/tillervim/plugins/coding/lsp.lua).
-- editor_core.lsp.rename checks prepareRename and references before leaving
-- `:IncRename <cword>` on the cmdline, so unsupported positions report why
-- they cannot be renamed instead of opening and immediately cancelling.
--
-- Nvim's own `grn` (plain `vim.lsp.buf.rename()`) is not remapped, but the
-- nowait `gr` (References) shadows it in an LSP buffer, so `,r` is the rename
-- key there.
return {
  "smjonas/inc-rename.nvim",
  cmd = "IncRename",
  opts = {},
}
