require "ProjectALife/Behaviours/ALifeModuleRegistry"

ProjectALife = ProjectALife or {}

local Registry = ProjectALife.ModuleRegistry
local Strafe = { id = "strafe" }
ProjectALife.ModuleStrafe = Strafe

function Strafe.active(data)
    if not Registry.isEnabled("strafe") then return false end
    local uid = type(data) == "table" and data.ProjectALifeUID or nil
    local actors = ProjectALife.ActorRegistry
    if uid == nil or actors == nil or type(actors.peek) ~= "function" then return true end
    local actor = actors.peek(uid)
    if type(actor) ~= "table" then return true end
    return Registry.allows(actor, "strafe") == true
end

Registry.register({
    id = "strafe",
    kind = "craft",
    label = "Aimed movement",
    summary = "Shooters keep the gun on the target, or where it was last seen, while they walk.",
    defaultEnabled = true,
    evaluate = function() return nil end,
})

return Strafe
