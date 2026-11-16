local t = dofile("tests/helper.lua")
local tmp = vim.fn.tempname() .. " user config"
vim.fn.mkdir(tmp, "p")
local result = vim.system({ vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-c", "luafile tests/fixtures/user_config.lua", "-c", "cquit 1" },
  { env = { KEY_TEST_TMP = tmp, TILLERVIM_TEST_ROOT = t.root }, text = true }):wait(20000)
t.eq(result.code, 0, "independent user config overrides real plugins without a key DSL\n" .. (result.stderr or ""))
local complete = vim.fn.filereadable(tmp .. "/result") == 1 and vim.fn.readfile(tmp .. "/result")[1]
t.eq(complete, "user-config-complete", "user options, maps, specs and billing labels all checked")
vim.fn.delete(tmp, "rf")
t.done()
