ProjectALife = ProjectALife or {}

local TargetPolicy = { adapters = {} }
ProjectALife.TargetPolicy = TargetPolicy

function TargetPolicy.configure(adapters)
    TargetPolicy.adapters = adapters or {}
end

local function indexable(target)
    local kind = type(target)
    return kind == "table" or kind == "userdata"
end

local function trueMethod(target, method)
    if not indexable(target) then return false end
    local callable = target[method]
    if type(callable) ~= "function" then return false end
    local callOk, value = pcall(callable, target)
    return callOk and value == true
end

function TargetPolicy.dataOf(target)
    if not indexable(target) or target.getModData == nil then return nil end
    if target.hasModData ~= nil and target:hasModData() ~= true then return nil end
    return target:getModData()
end

function TargetPolicy.grappledCorpse(target, data, dataChecked)
    if trueMethod(target, "isReanimatedForGrappleOnly") then return true end
    if dataChecked == true then
        return type(data) == "table" and data.ProjectALifeCorpseOf ~= nil
    end
    if not indexable(target) or type(target.getModData) ~= "function" then return false end
    if type(target.hasModData) == "function" then
        local hasOk, hasData = pcall(target.hasModData, target)
        if not hasOk or hasData ~= true then return false end
    end
    local ok, data = pcall(target.getModData, target)
    return ok and type(data) == "table" and data.ProjectALifeCorpseOf ~= nil
end

local function ownedActor(target)
    local data = TargetPolicy.dataOf(target)
    return type(data) == "table"
        and (data.ProjectALifeOwned == true or data.ProjectALifeActor == true)
end

function TargetPolicy.identityOf(target)
    if not indexable(target) then return nil, nil, nil end
    local uid, generation, onlineId
    local data = TargetPolicy.dataOf(target)
    if type(data) == "table" then
        uid, generation = data.ProjectALifeUID, data.ProjectALifeGeneration
    end
    if target.getOnlineID ~= nil then onlineId = target:getOnlineID() end
    return uid, generation, onlineId
end

function TargetPolicy.identity(target)
    local stamp = {}
    stamp.uid, stamp.generation, stamp.onlineId = TargetPolicy.identityOf(target)
    return stamp
end

function TargetPolicy.sameIdentity(target, stamp)
    if stamp == nil then return true end
    local uid, generation, onlineId = TargetPolicy.identityOf(target)
    return uid == stamp.uid and generation == stamp.generation
        and onlineId == stamp.onlineId
end

function TargetPolicy.canAttack(target, stamp, actor)
    if target == nil then return false, "target_missing" end
    if not TargetPolicy.sameIdentity(target, stamp) then return false, "target_recycled" end
    if TargetPolicy.grappledCorpse(target) then return false, "target_grappled_corpse" end
    if type(TargetPolicy.adapters.canAttack) == "function" then
        local ok, allowed, reason = pcall(TargetPolicy.adapters.canAttack, target)
        return ok and allowed == true, ok and reason or "target_policy_failed"
    end
    if trueMethod(target, "isDead") then return false, "target_dead" end
    local healthOk = indexable(target) and target.getHealth ~= nil
    local health = healthOk and target:getHealth() or nil
    if healthOk and tonumber(health) ~= nil and health <= 0 then
        return false, "target_dead"
    end

    if trueMethod(target, "isOnKillDone")
            and not (ownedActor(target) and healthOk and (tonumber(health) or 0) > 0) then
        return false, "target_dying"
    end

    local squareOk = indexable(target) and target.getCurrentSquare ~= nil
    local square = squareOk and target:getCurrentSquare() or nil
    if squareOk and square == nil then return false, "target_unloaded" end

    if trueMethod(target, "isZombie") and not ownedActor(target) then return true end
    local protected = TargetPolicy.protection(target, square, actor)
    if protected ~= nil then return false, protected end

    return true
end

function TargetPolicy.nonPvpShield()
    local settings = ProjectALife.Settings
    local current = settings ~= nil and settings.current or nil
    if type(current) == "table" and current.nonPvpShield ~= nil then return current.nonPvpShield == true end
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    return type(vars) == "table" and vars.Combat_NonPvpZoneShield == true
end

function TargetPolicy.retaliates(actor, target)
    if actor == nil or target == nil then return false end
    local uid = actor
    if type(actor) == "table" then uid = actor.uid end
    local perception = ProjectALife.Perception
    if type(uid) ~= "string" or perception == nil or type(perception.attackers) ~= "table" then return false end
    local entry = perception.attackers[uid]
    if type(entry) ~= "table" or entry.attacker ~= target then return false end
    local now = type(getTimestampMs) == "function" and getTimestampMs() or 0
    return now < (tonumber(entry.untilMs) or 0)
end

function TargetPolicy.protection(target, square, actor)

    if trueMethod(target, "isInvisible") then return "target_invisible" end
    if trueMethod(target, "isGhostMode") then return "target_ghost" end
    if square == nil and indexable(target) and target.getCurrentSquare ~= nil then
        square = target:getCurrentSquare()
    end
    if square ~= nil and SafeHouse ~= nil then

        local ok, safehouse = pcall(function() return SafeHouse.getSafeHouse(square) end)
        if ok and safehouse ~= nil then return "target_safehouse" end
    end
    if not TargetPolicy.nonPvpShield() then return nil end
    local positionOk = indexable(target) and target.getX ~= nil and target.getY ~= nil
    local x, y
    if positionOk then x, y = target:getX(), target:getY() end
    if positionOk and NonPvpZone ~= nil then
        local ok, zone = pcall(function()
            return NonPvpZone.getNonPvpZone(math.floor(x), math.floor(y))
        end)
        if ok and zone ~= nil and not TargetPolicy.retaliates(actor, target) then return "target_non_pvp_zone" end
    end
    return nil
end

return TargetPolicy
