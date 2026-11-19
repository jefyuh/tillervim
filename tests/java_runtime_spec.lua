-- Exercise FileType with JDK 17 alone, then discover a side-by-side SDK.
local t = dofile("tests/helper.lua")
local root = vim.fn.tempname()
local sdkman = root .. "/sdkman/java"
local function fixture(home, major)
  vim.fn.mkdir(home .. "/bin", "p")
  vim.fn.writefile({ "JAVA_VERSION=\"" .. major .. ".0.1\"" }, home .. "/release")
  vim.fn.writefile({ "#!/bin/sh", "exit 1" }, home .. "/bin/java")
  assert(vim.fn.setfperm(home .. "/bin/java", "rwx------") == 1)
end
local project = root .. "/jdk17"
fixture(project, 17)
local expand, exepath, java_home = vim.fn.expand, vim.fn.exepath, vim.env.JAVA_HOME
vim.env.JAVA_HOME = project
vim.fn.expand = function(path, ...)
  if path == "~/.sdkman/candidates/java" then return sdkman end
  return expand(path, ...)
end
vim.fn.exepath = function(name)
  if name == "java" then return project .. "/bin/java" end
  return exepath(name)
end

local notify, notices = vim.notify, {}
vim.notify = function(msg, level, ...)
  if type(msg) == "string" and msg:find("jdtls and Java debugging", 1, true) then
    table.insert(notices, level)
  end
  return notify(msg, level, ...)
end

local jdk = require("tillervim.util.jdk")
local bin, reason = jdk.for_jdtls()
t.eq(bin, nil, "JDK 17 cannot host this language server")
t.ok(reason:find("found JDK 17", 1, true), "diagnostic names the detected version")
for _, name in ipairs({ "First", "Second" }) do
  local file = root .. "/" .. name .. ".java"
  vim.fn.writefile({ "class " .. name .. " {}" }, file)
  vim.cmd.edit(vim.fn.fnameescape(file))
  t.eq(vim.bo.filetype, "java", "opens " .. name .. " normally")
  t.ok(not vim.b.java_jdtls_started, "buffer remains eligible for a later attach")
end
t.eq(notices, { vim.log.levels.WARN }, "only one runtime warning for multiple files")
t.eq(#vim.lsp.get_clients({ name = "jdtls" }), 0, "no jdtls started on 17")

fixture(sdkman .. "/side-by-side", 25)
t.eq(jdk.for_jdtls(), sdkman .. "/side-by-side/bin/java", "side-by-side JDK enables jdtls")
t.eq(vim.env.JAVA_HOME, project, "project JDK stays selected")
vim.notify, vim.fn.expand, vim.fn.exepath = notify, expand, exepath
vim.env.JAVA_HOME = java_home
vim.fn.delete(root, "rf")
t.done()
