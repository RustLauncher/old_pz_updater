require "ProjectALife/Compat/ALifeFeatureGate"

ProjectALife = ProjectALife or {}

local Gate = ProjectALife.FeatureGate

local Blame = {
    id = "blame",
    metrics = { thievesBlamed = 0, manhuntsHeld = 0 },
}
ProjectALife.Blame = Blame

function Blame.active()
    return Gate.on(Blame.id, "Blame_Fair", true)
end

function Blame.shared()
    return #Gate.players() > 1
end

function Blame.multiplayer()
    return Gate.dedicated() or (type(isClient) == "function" and isClient() == true)
end

function Blame.keys(players)
    if not Blame.active() or not Blame.shared() or type(players) ~= "table" then return nil end
    local fair = ProjectALife.Fairness
    if fair == nil or type(fair.keyOf) ~= "function" then return nil end
    local keys, seen = {}, {}
    for _, player in ipairs(players) do
        local key = fair.keyOf(player)
        if key ~= nil and not seen[key] then
            seen[key] = true
            keys[#keys + 1] = key
        end
    end
    if #keys == 0 then return nil end
    return keys
end

function Blame.keepsTarget(memory)
    if type(memory) ~= "table" or not Blame.active() or not Blame.multiplayer() then return false end
    local wanted = memory.targetUsername
    if type(wanted) ~= "string" or wanted == "" then return false end
    Blame.metrics.manhuntsHeld = Blame.metrics.manhuntsHeld + 1
    return true
end

return Blame
