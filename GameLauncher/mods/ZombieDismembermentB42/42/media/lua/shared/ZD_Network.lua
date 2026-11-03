require "ZD_Shared"

ZD_Network = ZD_Network or {}
local N = ZD_Network
local ZD = ZombieDismemberment

N.PROTOCOL = 1
N.KEY = "ZombieDismembermentB42_MP_v1"
N.MAX_BATCH = 32
N.CARRIERS = {
    ["ZombieDismemberment.ZD_Corpse_ForeArm_L"] = {"L", "ForeArm"},
    ["ZombieDismemberment.ZD_Corpse_ForeArm_R"] = {"R", "ForeArm"},
    ["ZombieDismemberment.ZD_Corpse_UpperArm_L"] = {"L", "UpperArm"},
    ["ZombieDismemberment.ZD_Corpse_UpperArm_R"] = {"R", "UpperArm"},
    ["ZombieDismemberment.ZD_Corpse_Leg_L"] = {"LegL", "WholeLeg"},
    ["ZombieDismemberment.ZD_Corpse_Leg_R"] = {"LegR", "WholeLeg"},
    ["ZombieDismemberment.ZD_Corpse_Head"] = {"Head", "Decapitated"},
}

function N.enabled()
    return isServer() or isClient()
end

function N.number(value, minimum, maximum)
    return type(value) == "number" and value == value and value >= minimum and value <= maximum
end

function N.onlineID(zombie)
    local id = zombie:getOnlineID()
    if id ~= -1 then
        return id
    end
end

function N.validUID(uid)
    return type(uid) == "string" and #uid <= 40 and uid:match("^mp:%d+$") ~= nil
end

function N.hasState(state)
    return type(state) == "table" and (ZD.validCut(state.L) or ZD.validCut(state.R)
        or ZD.validLeg(state.LegL) or ZD.validLeg(state.LegR) or ZD.validHead(state.Head))
end

function N.hasLiveState(character)
    local md = character:getModData()
    return ZD.validCut(md.ZD_L) or ZD.validCut(md.ZD_R) or ZD.validLeg(md.ZD_LegL)
        or ZD.validLeg(md.ZD_LegR) or ZD.validHead(md.ZD_Head)
end

function N.read(character)
    local md = character:getModData()
    return ZD.copyState({L = md.ZD_L, R = md.ZD_R, LegL = md.ZD_LegL, LegR = md.ZD_LegR, Head = md.ZD_Head})
end

function N.write(character, state, uid, revision)
    local md = character:getModData()
    local clean = ZD.copyState(state)
    md.ZD_L = clean.L
    md.ZD_R = clean.R
    md.ZD_LegL = clean.LegL
    md.ZD_LegR = clean.LegR
    md.ZD_Head = clean.Head
    if N.validUID(uid) then
        md.ZD_MPUID = uid
        md.ZD_trueID = uid
    end
    if N.number(revision, 0, 9007199254740991) then
        md.ZD_MPRevision = revision
    end
    return clean
end

function N.identity(zombie)
    if isServer() and N.serverIdentity then return N.serverIdentity(zombie) end
    local md = zombie:getModData()
    if N.validUID(md.ZD_MPUID) then return md.ZD_MPUID end
    local id = N.onlineID(zombie)
    if id then return "online:" .. tostring(id) end
end

function N.state(zombie)
    if isServer() and N.serverState then return N.serverState(zombie) end
    return N.read(zombie)
end

function N.packet(zombie, state, uid, revision, nonce)
    return {
        v = N.PROTOCOL, id = N.onlineID(zombie), uid = uid, revision = revision,
        outfit = ZD.trueZombieID(zombie), x = zombie:getX(), y = zombie:getY(), z = zombie:getZ(),
        state = ZD.copyState(state), nonce = nonce,
    }
end

function N.validPacket(packet)
    return type(packet) == "table" and packet.v == N.PROTOCOL and N.validUID(packet.uid)
        and N.number(packet.id, -32768, 32767) and packet.id ~= -1 and packet.id == math.floor(packet.id)
        and N.number(packet.revision, 0, 9007199254740991) and packet.revision == math.floor(packet.revision)
        and N.number(packet.x, -1000000, 1000000) and N.number(packet.y, -1000000, 1000000)
        and N.number(packet.z, -32, 32) and type(packet.state) == "table"
end

function N.stampCarrier(character, item)
    local md = character:getModData()
    if not N.validUID(md.ZD_MPUID) then return end
    local data = item:getModData()
    data.ZD_MPUID = md.ZD_MPUID
    data.ZD_MPRevision = md.ZD_MPRevision or 0
end

function N.recoverCarriers(character)
    local worn = character:getWornItems()
    local state = {}
    local uid
    local revision = 0
    for i = 0, worn:size() - 1 do
        local item = worn:get(i):getItem()
        local spec = N.CARRIERS[item:getFullType()]
        if spec then
            state = ZD.mergeStates(state, {[spec[1]] = spec[2]})
            local data = item:getModData()
            if N.validUID(data.ZD_MPUID) then
                if uid and uid ~= data.ZD_MPUID then return end
                uid = data.ZD_MPUID
                revision = math.max(revision, tonumber(data.ZD_MPRevision) or 0)
            end
        end
    end
    if N.hasState(state) then
        N.write(character, ZD.mergeStates(N.read(character), state), uid, revision)
    end
end

function N.isGrapple(zombie)
    return zombie:isReanimatedForGrappleOnly()
end

function N.impact(old, state)
    if old.Head ~= state.Head and ZD.validHead(state.Head) then
        return {limb = "Head", cut = "Decapitated"}
    end
    for _, side in ipairs({"L", "R"}) do
        if old[side] ~= state[side] and ZD.validCut(state[side]) then
            return {limb = "Arm", side = side, cut = state[side]}
        end
        local key = "Leg" .. side
        if old[key] ~= state[key] and ZD.validLeg(state[key]) then
            return {limb = "Leg", side = side, cut = "WholeLeg"}
        end
    end
end

return N
