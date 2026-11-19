-- Resolve the JVM for jdtls independently of the project's build toolchain.
local M = {}
local minimum = 25 -- jdtls 1.63+ bundles require JavaSE 25.

local function java_major(home)
  local file = io.open(home .. "/release")
  if not file then return end
  local version = file:read("*a"):match('JAVA_VERSION="(%d+)')
  file:close()
  return tonumber(version)
end

-- Prefer JAVA_HOME, SDKMAN current, the newest SDKMAN candidate, then PATH.
function M.for_jdtls()
  local sdkman = vim.fn.expand("~/.sdkman/candidates/java")
  local homes = { vim.env.JAVA_HOME or "", sdkman .. "/current" }
  local others = vim.fn.glob(sdkman .. "/*", false, true)
  table.sort(others, function(a, b) return (java_major(a) or 0) > (java_major(b) or 0) end)
  vim.list_extend(homes, others)
  local on_path = vim.fn.exepath("java")
  if on_path ~= "" then
    table.insert(homes, vim.fs.dirname(vim.fs.dirname(vim.uv.fs_realpath(on_path) or on_path)))
  end
  local newest
  for _, home in ipairs(homes) do
    if home ~= "" and vim.fn.executable(home .. "/bin/java") == 1 then
      local major = java_major(home)
      if major and major >= minimum then return home .. "/bin/java" end
      if major then newest = math.max(newest or 0, major) end
    end
  end
  local found = newest and ("found JDK " .. newest) or "no compatible JDK found"
  return nil, ("Java editing available; jdtls and Java debugging need JDK %d+ (%s). "
    .. "Install a compatible JDK alongside the project JDK, then save and run :edit in the Java buffer."):format(minimum, found)
end

return M
