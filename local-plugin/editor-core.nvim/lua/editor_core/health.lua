-- Core-owned diagnostics for :checkhealth editor_core: input source and logs.
-- The host's health aggregator owns its dependency and version requirements.
local M = {}
local health = vim.health

function M.check()
  health.start("config: input method")
  if vim.fn.has("macunix") ~= 1 then
    health.info("automatic input-source switching is only enabled on macOS")
  else
    local source, origin = require("editor_core.input_method").default_source()
    if source then
      health.ok(("Normal-mode source is %s (%s)"):format(source, origin))
    else
      health.warn("Normal-mode input source could not be detected",
        { "Set NVIM_ENGLISH_INPUT_SOURCE to a macOS input-source ID" })
    end
  end

  health.start("config: logs")
  local log_path = vim.lsp.log.get_filename()
  local stat = vim.uv.fs_stat(log_path)
  if stat and stat.size > 10 * 1024 * 1024 then
    health.warn(("LSP log is %.1f MiB: %s"):format(stat.size / 1024 / 1024, log_path))
  else
    health.ok("LSP log size is below 10 MiB")
  end
end

return M
