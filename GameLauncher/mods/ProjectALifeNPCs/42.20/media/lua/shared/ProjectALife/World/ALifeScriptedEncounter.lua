ProjectALife = ProjectALife or {}

local Scripted = {

    allowed = {
        id = "string",

        warnRadius = "number",
        closeRadius = "number",
        contactRadius = "number",
        contactHoldMs = "number",

        holdPost = "boolean",
        noClimb = "boolean",

        fireHoldMs = "number",
        volley = "boolean",

        damageScale = "number",
    },
    metrics = { stamped = 0, refusedKeys = 0 },
}
ProjectALife.ScriptedEncounter = Scripted

function Scripted.clean(block)
    if type(block) ~= "table" then return nil end
    local result, kept = {}, 0
    for key, value in pairs(block) do
        local wanted = Scripted.allowed[key]
        if wanted ~= nil and type(value) == wanted then
            result[key] = value
            kept = kept + 1
        else
            Scripted.metrics.refusedKeys = Scripted.metrics.refusedKeys + 1
        end
    end
    if kept == 0 then return nil end
    return result
end

function Scripted.stamp(memory, block)
    if type(memory) ~= "table" then return nil end
    local cleaned = Scripted.clean(block)
    if cleaned == nil then return nil end
    memory.scripted = cleaned
    Scripted.metrics.stamped = Scripted.metrics.stamped + 1
    return cleaned
end

function Scripted.of(actor)
    if type(actor) ~= "table" then return nil end
    local memory = type(actor.memory) == "table" and actor.memory or actor
    local block = memory.scripted
    return type(block) == "table" and block or nil
end

function Scripted.value(actor, key, fallback)
    local block = Scripted.of(actor)
    if block == nil then return fallback end
    local value = block[key]
    if value == nil then return fallback end
    return value
end

function Scripted.is(actor, id)
    local block = Scripted.of(actor)
    if block == nil then return false end
    if id == nil then return true end
    return tostring(block.id or "") == tostring(id)
end

function Scripted.reset()
    Scripted.metrics = { stamped = 0, refusedKeys = 0 }
    return true
end

return Scripted
