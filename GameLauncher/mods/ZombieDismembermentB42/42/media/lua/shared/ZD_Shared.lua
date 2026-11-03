require "NPCs/BodyLocations"
local group = BodyLocations.getGroup("Human")
group:getOrCreateLocation(ItemBodyLocation.get(ResourceLocation.of("ZombieDismemberment:HeadCarrier")))

ZombieDismemberment = ZombieDismemberment or {}
local ZD = ZombieDismemberment

ZD.MODKEY = "ZombieDismembermentB42"
ZD.GLOBAL_KEY = "ZombieDismembermentB42_State_v1"

ZD.VISUALS = {
    ForeArm = {
        L = "ZombieDismemberment.ZD_ForeArm_L",
        R = "ZombieDismemberment.ZD_ForeArm_R",
    },
    UpperArm = {
        L = "ZombieDismemberment.ZD_UpperArm_L",
        R = "ZombieDismemberment.ZD_UpperArm_R",
    },
    WholeLeg = {
        L = "ZombieDismemberment.ZD_Leg_L",
        R = "ZombieDismemberment.ZD_Leg_R",
    },
}

ZD.VISUALS.Head = { L = "ZombieDismemberment.ZD_Head" }

ZD.ALL_VISUALS = {
    "ZombieDismemberment.ZD_Head",
    "ZombieDismemberment.ZD_ForeArm_L",
    "ZombieDismemberment.ZD_ForeArm_R",
    "ZombieDismemberment.ZD_UpperArm_L",
    "ZombieDismemberment.ZD_UpperArm_R",
    "ZombieDismemberment.ZD_Leg_L",
    "ZombieDismemberment.ZD_Leg_R",
}

function ZD.isNPC(character, md)
    md = md or character:getModData()
    if md.notAloneBody == true or md.brain or md.brainId ~= nil or md.isDeadBandit == true
        or md.ProjectALifeOwned == true or md.ProjectALifeActor == true then return true end
    if not instanceof(character, "IsoZombie") then return false end
    if character:getVariableBoolean("SurvivorNPC") or character:getVariableBoolean("NotAloneBody")
        or character:getVariableBoolean("Bandit") or character:getVariableBoolean("ALifeActor") then return true end
    -- Bandits registers server brains before the client sets the actor variable.
    if BanditUtils and BanditUtils.GetZombieID and GetBanditClusterData then
        local id = BanditUtils.GetZombieID(character)
        local cluster = GetBanditClusterData(id)
        return cluster ~= nil and cluster[id] ~= nil
    end
    return false
end

function ZD.getData()
    local d = ModData.getOrCreate(ZD.GLOBAL_KEY)
    d.zombies = d.zombies or {}
    d.revision = tonumber(d.revision) or 0
    return d
end

function ZD.trueZombieID(zombie)
    if not zombie then return nil end
    local ok, result = pcall(function()
        local pID = zombie:getPersistentOutfitID()
        if not pID or pID == 0 then return nil end
        local bits = string.split(string.reverse(Long.toUnsignedString(pID, 2)), "")
        while #bits < 16 do bits[#bits + 1] = 0 end
        bits[16] = 0
        return tostring(Long.parseUnsignedLong(string.reverse(table.concat(bits, "")), 2))
    end)
    if ok then return result end
    return nil
end

function ZD.validSide(side)
    return side == "L" or side == "R"
end

function ZD.validCut(cut)
    return cut == "ForeArm" or cut == "UpperArm"
end

function ZD.validLeg(cut)
    return cut == "WholeLeg"
end

function ZD.validHead(cut)
    return cut == "Decapitated"
end

function ZD.copyState(state)
    if type(state) ~= "table" then return {} end
    local out = {}
    if ZD.validCut(state.L) then out.L = state.L end
    if ZD.validCut(state.R) then out.R = state.R end
    if ZD.validLeg(state.LegL) then out.LegL = state.LegL end
    if ZD.validLeg(state.LegR) then out.LegR = state.LegR end
    if ZD.validHead(state.Head) then out.Head = state.Head end
    return out
end

function ZD.copyLimbState(state)
    local out = ZD.copyState(state)
    out.Head = nil
    return out
end

local function strongerArmCut(a, b)
    if a == "UpperArm" or b == "UpperArm" then return "UpperArm" end
    if a == "ForeArm" or b == "ForeArm" then return "ForeArm" end
    return nil
end

function ZD.mergeStates(a, b)
    a = type(a) == "table" and a or {}
    b = type(b) == "table" and b or {}
    local out = {}
    out.L = strongerArmCut(a.L, b.L)
    out.R = strongerArmCut(a.R, b.R)
    if ZD.validLeg(a.LegL) or ZD.validLeg(b.LegL) then out.LegL = "WholeLeg" end
    if ZD.validLeg(a.LegR) or ZD.validLeg(b.LegR) then out.LegR = "WholeLeg" end
    if ZD.validHead(a.Head) or ZD.validHead(b.Head) then out.Head = "Decapitated" end
    return out
end

function ZD.stateSignature(state)
    if type(state) ~= "table" then return "-|-|-|-|-" end
    return table.concat({
        tostring(state.L or "-"),
        tostring(state.R or "-"),
        tostring(state.LegL or "-"),
        tostring(state.LegR or "-"),
        tostring(state.Head or "-"),
    }, "|")
end

return ZD