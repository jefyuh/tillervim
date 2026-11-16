---@module "editor_core.lsp"
---LSP actions and rename with error handling.

local logger = require("editor_core.logger")

local M = {}
local rename_generation = 0

---Check rename support before opening IncRename's command-line preview.
---IncRename cancels silently when references are empty; prepareRename alone
---also cannot protect servers that do not implement that optional method.
function M.rename()
  rename_generation = rename_generation + 1
  local generation = rename_generation
  local win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
  local cursor, tick = vim.api.nvim_win_get_cursor(win), vim.api.nvim_buf_get_changedtick(buf)
  -- IncRename sends the eventual rename to the first capable client too.
  local client = vim.lsp.get_clients({ bufnr = buf, method = "textDocument/rename" })[1]
  if not client then
    vim.notify("Cannot rename: no language server supports rename", vim.log.levels.ERROR, { title = "LSP rename" })
    return
  end

  local finished, request_id = false, nil
  local function current()
    return generation == rename_generation
      and vim.api.nvim_get_current_win() == win
      and vim.api.nvim_get_current_buf() == buf
      and vim.api.nvim_buf_get_changedtick(buf) == tick
      and vim.deep_equal(vim.api.nvim_win_get_cursor(win), cursor)
      and vim.api.nvim_get_mode().mode == "n"
  end
  local function finish(reason)
    if finished then return end
    finished = true
    if reason and current() then
      vim.notify("Cannot rename: " .. reason, vim.log.levels.ERROR, { title = "LSP rename" })
    end
  end
  local function request(method, params, callback)
    local sent
    sent, request_id = client:request(method, params, function(err, result)
      if finished then return end
      if not current() then finish(); return end
      if err then finish(client.name .. ": " .. err.message); return end
      callback(result)
    end, buf)
    if not sent then finish("could not contact " .. client.name) end
  end

  vim.defer_fn(function()
    if finished then return end
    finish(client.name .. " did not respond within 5 seconds")
    if request_id then client:cancel_request(request_id) end
  end, 5000)

  local params = vim.lsp.util.make_position_params(win, client.offset_encoding)
  local function references()
    if not client:supports_method("textDocument/references", buf) then
      finish(client.name .. " does not support references required for rename preview")
      return
    end
    request("textDocument/references", vim.tbl_extend("force", params, {
      context = { includeDeclaration = true },
    }), function(result)
      if not result or vim.tbl_isempty(result) then
        finish("no references found at cursor (" .. client.name .. ")")
        return
      end
      local ok, err = pcall(require, "inc_rename")
      if not ok then finish("IncRename unavailable: " .. tostring(err)); return end
      finish()
      vim.api.nvim_feedkeys(":IncRename " .. vim.fn.expand("<cword>"), "n", false)
    end)
  end
  if client:supports_method("textDocument/prepareRename", buf) then
    request("textDocument/prepareRename", params, function(result)
      if not result then
        finish("symbol at cursor cannot be renamed (" .. client.name .. ")")
        return
      end
      references()
    end)
  else
    references()
  end
end

---Safe LSP code action execution with error handling
---Uses a metatable to dynamically create functions for each action
---@example
---local lsp = require("editor_core.lsp")
---lsp.action["source.organizeImports"]()  -- Organize imports
---lsp.action["quickfix"]()                -- Apply quickfix
M.action = setmetatable({}, {
  __index = function(_, action)
    return function()
      if type(action) ~= "string" then
        logger.error("LSP action must be a string, got %s", type(action))
        return
      end

      logger.debug("Executing LSP action: %s", action)

      local success, result = logger.safe_call(function()
        -- Check if LSP is available
        local clients = vim.lsp.get_clients({ bufnr = 0 })
        if #clients == 0 then
          logger.warn("No active LSP clients for current buffer")
          return false
        end

        vim.lsp.buf.code_action({
          apply = true,
          context = {
            only = { action },
            diagnostics = {},
          }
        })

        return true
      end, string.format("LSP action: %s", action))

      if not success then
        logger.error("LSP action failed: %s", result)
      elseif result == false then
        logger.debug("LSP action skipped: %s", action)
      else
        logger.debug("LSP action completed: %s", action)
      end

      return success and result ~= false
    end
  end
})

return M
