-- All native actions resolve through the same controller for their provider.
local controllers = {}
return function(kind)
  if kind == "codex" then return require("agent_workbench.backend.codex") end
  if not controllers[kind] then
    controllers[kind] = require("agent_workbench.backend.cli").new(kind)
  end
  return controllers[kind]
end
