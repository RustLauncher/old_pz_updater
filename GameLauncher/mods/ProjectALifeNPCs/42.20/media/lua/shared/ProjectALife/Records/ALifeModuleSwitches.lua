ProjectALife = ProjectALife or {}

local Switches = {}
ProjectALife.ModuleSwitches = Switches

Switches.values = {

    leader = true,
    gunner = true,
    medic = true,
    radioman = true,
    careful = true,

    talk = true,
    robbery = true,
    fortify = true,
    nightHold = true,
    sniper = true,
    stealth = true,
    ambusher = true,

    orders = true,
    stance = true,
    activity = true,
    home = true,
    plan = true,

    panic = true,
    fear = true,
    gunFear = true,
    withdraw = true,
    warning = true,

    flee = true,

    strafe = true,
    weave = true,
    cover = true,
    doorstack = true,
    cqbsweep = true,
    flanking = true,

    meleeFootwork = true,
    meleeFlank = true,
    meleeBreach = true,
    meleeIntimidate = true,
    meleeCaution = true,
    zombieAvoid = true,
    weaponSwitchMelee = true,

    healing = true,
    scavenge = true,
    search = true,
    investigate = true,
    idleLife = true,
    patrolRest = true,
    visitorLife = true,
    regroup = true,
    groupMarch = true,
    spread = true,
}

function Switches.get(id)
    local value = Switches.values[id]
    if value == true then return true end
    if value == false then return false end
    return nil
end

function Switches.set(id, enabled)
    if type(id) ~= "string" then return false end
    if enabled == nil then
        Switches.values[id] = nil
    else
        Switches.values[id] = enabled == true
    end
    local registry = ProjectALife.ModuleRegistry
    if registry ~= nil and type(registry.invalidate) == "function" then
        registry.invalidate()
    end
    return true
end

return Switches
