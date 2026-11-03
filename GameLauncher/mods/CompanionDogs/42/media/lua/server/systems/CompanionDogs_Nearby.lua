CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

local function maybeUpdate(animal, player)
    local d = CD.data(animal)
    local pd = CD.playerData(player)
    if pd.token == nil then
        if d.companionToken ~= nil then return end
        pd.seq = (pd.seq or 0) + 1
        CD.setActiveDog(pd, pd.seq, d.name)
        d.companionToken = pd.seq
        CD.transmit(animal)
    elseif d.companionToken ~= pd.token then
        return
    end
    CD.updateCompanion(animal, player)
end

---Scans the squares around the last known spot of each of the player's tokens the registry pass missed, within R of the player.
---@param cell IsoCell
---@param player IsoPlayer
---@param pd table the player's CompanionDogs mod data
---@param px integer player tile
---@param py integer
---@param pz integer
---@param R number tiles from the player on each axis
---@param foundTok table|nil set of the tokens already found
---@return IsoAnimal[]|nil dogs nil when none
---@nodiscard
CD.ghostScan = function(cell, player, pd, px, py, pz, R, foundTok)
    local toks = nil
    if type(pd.companions) == "table" then
        for t in pairs(pd.companions) do
            if not (foundTok and foundTok[t]) then
                toks = toks or {}
                toks[#toks + 1] = t
            end
        end
    end
    if pd.token ~= nil and not (foundTok and foundTok[pd.token]) then
        local dup = false
        if toks then
            for i = 1, #toks do
                if toks[i] == pd.token then
                    dup = true
                    break
                end
            end
        end
        if not dup then
            toks = toks or {}
            toks[#toks + 1] = pd.token
        end
    end
    if not toks or type(pd.tokenAnchor) ~= "table" then return nil end
    local GR = CD.GHOST_SCAN_RADIUS
    local out = nil
    for i = 1, #toks do
        local t = toks[i]
        local anc = pd.tokenAnchor[t]
        if anc and anc.z == pz and math.abs(anc.x - px) <= R and math.abs(anc.y - py) <= R then
            for dx = -GR, GR do
                for dy = -GR, GR do
                    local sq = cell:getGridSquare(anc.x + dx, anc.y + dy, anc.z)
                    local list = sq and sq:getAnimals()
                    if list then
                        for j = 0, list:size() - 1 do
                            local a = list:get(j)
                            if CD.isDog(a) and CD.isCompanion(a) and CD.isOwnedBy(a, player)
                               and CD.data(a).companionToken == t then
                                out = out or {}
                                out[#out + 1] = a
                            end
                        end
                    end
                end
            end
        end
    end
    return out
end

local function driveNearbyDogs(pd, player, present)
    if present then
        local grew = false
        pd.uidGen = pd.uidGen or {}
        local keeperByUid = {}
        for _, a in ipairs(present) do
            local u = CD.data(a).uid
            if u ~= nil then
                local g = CD.data(a).gen or 0
                local k = keeperByUid[u]
                local kg = k and (CD.data(k).gen or 0) or -1
                if g > kg
                   or (g == kg and CD.data(a).companionToken == pd.token and CD.data(k).companionToken ~= pd.token) then
                    keeperByUid[u] = a
                end
            end
        end
        local survivors = {}
        for _, a in ipairs(present) do
            local u = CD.data(a).uid
            local stale = u ~= nil and (keeperByUid[u] ~= a or (CD.data(a).gen or 0) < (pd.uidGen[u] or 0))
            if stale then
                local vt = CD.data(a).companionToken
                local k = keeperByUid[u]
                local ktok = (k ~= nil and k ~= a) and CD.data(k).companionToken or nil
                if CD.cloneSlotShouldClear(pd, vt, ktok) and pd.companions ~= nil then
                    pd.companions[vt] = nil
                end
                CD.reapDogState(a:getOnlineID())
                CD.despawn(a)
                grew = true
            else
                survivors[#survivors + 1] = a
            end
        end
        present = survivors
        do
            local byTok = {}
            for _, a in ipairs(present) do
                local t = CD.data(a).companionToken
                if t ~= nil then
                    byTok[t] = byTok[t] or {}
                    table.insert(byTok[t], a)
                end
            end
            CD._twinLogAt = CD._twinLogAt or {}
            for t, list in pairs(byTok) do
                if #list == 1 then
                    if CD.data(list[1]).uid == nil then
                        CD.ensureUid(list[1])
                        CD.transmit(list[1])
                    end
                elseif (getTimestampMs() - (CD._twinLogAt[t] or -math.huge)) > 60000 then
                    CD._twinLogAt[t] = getTimestampMs()
                    CD.log("[CD-TWIN] token=" .. tostring(t) .. " instancias=" .. tostring(#list) ..
                          " nome=" .. tostring(CD.data(list[1]).name) .. " ativo(pd.token)=" .. tostring(pd.token))
                    for i = 1, #list do
                        local a = list[i]
                        local ax = tostring(a:getX())
                        local ay = tostring(a:getY())
                        local az = tostring(a:getZ())
                        local aid = tostring(a:getAnimalID())
                        CD.log("[CD-TWIN]   #" .. tostring(i) ..
                              " uid=" .. tostring(CD.data(a).uid) ..
                              " gen=" .. tostring(CD.data(a).gen) ..
                              " animalID=" .. aid ..
                              " onlineID=" .. tostring(a:getOnlineID()) ..
                              " em " .. ax .. "," .. ay .. "," .. az)
                    end
                end
            end
        end
        local seenToken = {}
        for _, a in ipairs(present) do
            local da = CD.data(a)
            local t = da.companionToken
            if t ~= nil and seenToken[t] then
                local m = pd.seq or 0
                if type(pd.companions) == "table" then
                    for k in pairs(pd.companions) do if k > m then m = k end end
                end
                m = m + 1
                pd.seq = m
                da.companionToken = m
                t = m
                CD.transmit(a)
                grew = true
            end
            if t ~= nil then
                seenToken[t] = true
                if type(pd.companions) ~= "table" then
                    pd.companions = {}
                end
                if not pd.companions[t] then
                    pd.companions[t] = true
                    grew = true
                end
                pd.tokenAnchor = pd.tokenAnchor or {}
                pd.tokenAnchor[t] = { x = math.floor(a:getX()), y = math.floor(a:getY()), z = math.floor(a:getZ()) }
            end
            if CD.hasBag(a) and CD.ensureAttachSlots(a) then
                if a:getAttachedItem("saddlebags_l") == nil then
                    CD.applyBagVisual(a)
                end
            end
            if da.ownerKey == nil or da.ownerKey == "" then
                local ok = CD.ownerKey(player)
                if ok ~= nil and ok ~= "" then
                    da.ownerKey = ok
                    CD.transmit(a)
                end
            end
            CD.kennelMirror(player, a)
            maybeUpdate(a, player)
        end
        if grew and player then
            player:transmitModData()
        end
    end
end

local function processNearbyDogs(player)
    local px = math.floor(player:getX())
    local py = math.floor(player:getY())
    local pz = math.floor(player:getZ())
    local cell = getCell()
    if not cell then return end
    local R = CD.TELEPORT_DIST + 4
    local pd = CD.playerData(player)
    local present, matchesToken, deadDogs = nil, false, nil
    local cand, foundTok = nil, nil
    local ownKeyed, ownNamed = CD.regCompanionsOf(player)
    local checked = 0
    for pass = 1, 2 do
        local lst = (pass == 1) and ownKeyed or ownNamed
        if lst then
            checked = checked + #lst
            for i = 1, #lst do
                local a = lst[i]
                if a:isExistInTheWorld() and CD.isOwnedBy(a, player)
                   and math.abs(math.floor(a:getX()) - px) <= R
                   and math.abs(math.floor(a:getY()) - py) <= R
                   and math.floor(a:getZ()) == pz then
                    cand = cand or {}
                    cand[#cand + 1] = a
                    local t = CD.data(a).companionToken
                    if t ~= nil then
                        foundTok = foundTok or {}
                        foundTok[t] = true
                    end
                end
            end
        end
    end
    CD.perfCount("iter.ownercheck", checked)
    local ghosts = CD.ghostScan(cell, player, pd, px, py, pz, R, foundTok)
    if ghosts then
        cand = cand or {}
        for i = 1, #ghosts do cand[#cand + 1] = ghosts[i] end
    end
    if cand then
        for i = 1, #cand do
            local a = cand[i]
            local deadDog = a ~= nil and (a:isDead() or a:getHealth() <= 0)
            if deadDog then
                deadDogs = deadDogs or {}
                deadDogs[#deadDogs + 1] = a
            else
                present = present or {}
                present[#present + 1] = a
                if CD.data(a).companionToken == pd.token then
                    matchesToken = true
                end
                if cell then
                    local ol = cell:getObjectList()
                    if not ol:contains(a) then
                        ol:add(a)
                    end
                end
            end
        end
    end
    if deadDogs then
        pd.uidGen = pd.uidGen or {}
        for _, a in ipairs(deadDogs) do
            local da = CD.data(a)
            local u = da.uid
            if u ~= nil and (da.gen or 0) < (pd.uidGen[u] or 0) then
                CD.reapDogState(a:getOnlineID())
                CD.despawn(a)
            elseif not da.diedNotified then
                da.diedNotified = true
                CD.clearCompanionSlot(player, da.companionToken, da.name, CD.getBreed(a), a)
                CD.reapDogState(a:getOnlineID())
                CD.logCompanionDeath(a, "varredura")
            end
        end
    end

    local offGridDog = nil
    if pd.token ~= nil and not matchesToken then
        offGridDog = CD.getCompanionAnimal(player)
    end

    if not present and not offGridDog then
        return
    end
    driveNearbyDogs(pd, player, present)
    if offGridDog then
        maybeUpdate(offGridDog, player)
    end
end
CD.processNearbyDogs = processNearbyDogs
