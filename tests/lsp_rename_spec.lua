local t = dofile("tests/helper.lua")
local lsp = require("editor_core.lsp")

vim.cmd("enew")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local value = 1", "print(value)" })
vim.api.nvim_win_set_cursor(0, { 1, 6 })

local real = {
  get_clients = vim.lsp.get_clients,
  notify = vim.notify,
  feedkeys = vim.api.nvim_feedkeys,
  defer_fn = vim.defer_fn,
}
local requests, notifications, keys, timers, cancelled
local methods, clients
local client = { name = "rename-test", offset_encoding = "utf-16" }
function client:supports_method(method) return methods[method] ~= false end
function client:request(method, params, callback, buf)
  requests[#requests + 1] = { method = method, params = params, callback = callback, buf = buf }
  return true, #requests
end
function client:cancel_request(id) cancelled = id end
vim.lsp.get_clients = function() return clients end
vim.notify = function(msg, level) notifications[#notifications + 1] = { msg = msg, level = level } end
vim.api.nvim_feedkeys = function(value) keys[#keys + 1] = value end
vim.defer_fn = function(callback) timers[#timers + 1] = callback end

local function reset()
  requests, notifications, keys, timers, methods, cancelled = {}, {}, {}, {}, {}, nil
  clients = { client }
  vim.api.nvim_win_set_cursor(0, { 1, 6 })
end
local function reply(result, err)
  requests[#requests].callback(err, result)
end
local function refused(pattern)
  t.eq(#notifications, 1, "a refusal produces one notification")
  t.eq(notifications[1] and notifications[1].level, vim.log.levels.ERROR, "rename refusal is an error")
  t.ok(notifications[1] and notifications[1].msg:find(pattern, 1, true), "the error explains " .. pattern)
  t.eq(keys, {}, "a refused rename never opens the command line")
end

reset()
clients = {}
lsp.rename()
refused("no language server supports rename")

reset()
lsp.rename()
t.eq(requests[1].method, "textDocument/prepareRename", "rename checks the position before opening its UI")
reply(nil)
refused("symbol at cursor cannot be renamed")
t.eq(package.loaded.inc_rename, nil, "unsupported positions do not load IncRename")

reset()
lsp.rename()
reply(nil, { message = "read-only symbol" })
refused("rename-test: read-only symbol")

reset()
methods["textDocument/prepareRename"] = false
lsp.rename()
t.eq(requests[1].method, "textDocument/references", "servers without prepareRename use references")
t.eq(requests[1].params.context.includeDeclaration, true, "a declaration alone counts for rename preview")
reply({})
refused("no references found at cursor")

reset()
methods["textDocument/references"] = false
lsp.rename()
reply({ defaultBehavior = true })
refused("does not support references")

reset()
lsp.rename()
reply({ defaultBehavior = true })
reply(nil, { message = "workspace unavailable" })
refused("workspace unavailable")

reset()
lsp.rename()
timers[1]()
refused("did not respond within 5 seconds")
t.eq(cancelled, 1, "a timed-out request is cancelled")
reply({ defaultBehavior = true })
t.eq(#requests, 1, "a response after timeout cannot reopen rename")

reset()
lsp.rename()
vim.api.nvim_win_set_cursor(0, { 2, 6 })
reply({ defaultBehavior = true })
t.eq({ notifications, keys, #requests }, { {}, {}, 1 }, "moving the cursor cancels a pending rename")

reset()
lsp.rename()
vim.api.nvim_buf_set_lines(0, 1, 2, false, { "print(value + 1)" })
reply({ defaultBehavior = true })
t.eq({ notifications, keys, #requests }, { {}, {}, 1 }, "editing the file cancels a pending rename")

reset()
lsp.rename()
local old_reply = requests[1].callback
lsp.rename()
old_reply(nil, { message = "outdated refusal" })
t.eq(notifications, {}, "a newer rename supersedes an older request")
reply({ defaultBehavior = true })
t.eq(requests[#requests].method, "textDocument/references", "supported positions also check preview references")
reply({ { uri = vim.uri_from_bufnr(0), range = {
  start = { line = 0, character = 6 }, ["end"] = { line = 0, character = 11 },
} } })
t.eq(keys, { ":IncRename value" }, "supported symbols keep the editable IncRename preview command")
t.eq(notifications, {}, "a supported rename opens without an error")
t.ok(package.loaded.inc_rename ~= nil, "IncRename loads only for a supported rename")
timers[#timers]()
t.eq(notifications, {}, "a completed check never reports a timeout")

vim.lsp.get_clients, vim.notify = real.get_clients, real.notify
vim.api.nvim_feedkeys, vim.defer_fn = real.feedkeys, real.defer_fn
t.done()
