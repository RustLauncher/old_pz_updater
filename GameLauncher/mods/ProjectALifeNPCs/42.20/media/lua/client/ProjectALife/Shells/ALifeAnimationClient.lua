require "ProjectALife/Shells/ALifeAnimations"
require "ProjectALife/Shells/ALifeAIFence"
require "ProjectALife/Audio/ALifeVoiceCatalog"
require "ProjectALife/Compat/ALifeInterop"

ProjectALife = ProjectALife or {}

local Animations = ProjectALife.Animations
local AIFence = ProjectALife.AIFence
local Interop = ProjectALife.Interop
local Client = {
    pending = {}, order = {}, maximumPending = 128, dropped = 0,
    presented = setmetatable({}, { __mode = "k" }),
    weaponPresented = setmetatable({}, { __mode = "k" }),
    onlineIdentity = {},
    onlineShell = setmetatable({}, { __mode = "v" }),
    identityShell = setmetatable({}, { __mode = "v" }),

    observed = setmetatable({}, { __mode = "v" }),
    observedCount = 0,

    observedAtMs = {},
    pendingByOnline = {},

    announced = {}, announcedAtMs = {}, announcedOnline = {},
    announceLeaseMs = 4000, announceSweepMs = 5000, nextAnnounceSweepAtMs = 0,
    ticks = 0, applied = 0, immediate = 0,
    lastIndexAtMs = -math.huge,
    indexIntervalMs = 1000,
    indexScans = 0,
}
ProjectALife.AnimationClient = Client

local function nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

local function identity(shell)
    local ok, uid, generation = pcall(function()
        local data = shell:getModData()
        return data.ProjectALifeUID, tonumber(data.ProjectALifeGeneration)
    end)
    if ok and type(uid) == "string" and uid ~= "" then return uid, generation end
    ok, uid, generation = pcall(function()
        return shell:GetVariable("ALifeUID"),
            tonumber(shell:GetVariable("ALifeGeneration"))
    end)
    if ok and type(uid) == "string" and uid ~= "" then return uid, generation end
    return nil, nil
end

local function setVariable(shell, name, value)
    local ok = pcall(function() shell:SetVariable(name, tostring(value)) end)
    if not ok then pcall(function() shell:setVariable(name, tostring(value)) end) end
end

local function humanSkinIndex(value)
    return math.max(0, math.min(4, math.floor(tonumber(value) or 0)))
end

local function humanSkinTexture(presentation)
    local expected = ((presentation or {}).female == true
            and "FemaleBody0" or "MaleBody0")
        .. tostring(humanSkinIndex((presentation or {}).skin) + 1)
    return presentation and presentation.skinTexture == expected
        and presentation.skinTexture or expected
end

local function applyColor(visual, encoded, beard)
    local r, g, b = string.match(tostring(encoded or ""),
        "^%s*([%d%.]+)%s*,%s*([%d%.]+)%s*,%s*([%d%.]+)%s*$")
    if not r or ImmutableColor == nil then return end
    local color = ImmutableColor.new(
        math.max(0, math.min(1, tonumber(r) or 0)),
        math.max(0, math.min(1, tonumber(g) or 0)),
        math.max(0, math.min(1, tonumber(b) or 0)), 1)
    if beard then
        visual:setBeardColor(color)
        visual:setNaturalBeardColor(color)
    else
        visual:setHairColor(color)
        visual:setNaturalHairColor(color)
    end
end

local function realOnlineId(value)
    local onlineId = tonumber(value)
    if onlineId == nil or onlineId == -1 then return nil end
    return onlineId
end

local function messageKey(message)
    if type(message.uid) == "string" then
        return "uid:" .. message.uid .. ":" .. tostring(message.generation)
    end
    local onlineId = realOnlineId(message.onlineId)
    if onlineId then return "online:" .. tostring(onlineId) end
    return nil
end

local function record(shell)
    local ok, onlineId = pcall(function() return shell:getOnlineID() end)
    onlineId = ok and realOnlineId(onlineId) or nil
    if onlineId == nil then return nil end
    if Client.observed[onlineId] ~= shell then
        Client.observed[onlineId] = shell
        Client.observedCount = Client.observedCount + 1

        Client.observedAtMs[onlineId] = nowMs()
    end
    return onlineId
end

function Client.replicaAgeMs(shell, now)
    if shell == nil or shell.getOnlineID == nil then return nil end
    local onlineId = realOnlineId(shell:getOnlineID())
    if onlineId == nil or Client.observed[onlineId] ~= shell then return nil end
    local seenAt = Client.observedAtMs[onlineId]
    if seenAt == nil then return nil end
    return (tonumber(now) or nowMs()) - seenAt
end

function Client.identityPending(shell)
    if shell == nil or shell.getOnlineID == nil then return false end
    local onlineId = realOnlineId(shell:getOnlineID())
    return onlineId ~= nil and Client.pendingByOnline[onlineId] ~= nil
end

function Client.announce(onlineId, key, now)
    if onlineId == nil or type(key) ~= "string" then return end
    local previous = Client.announcedOnline[key]
    if previous ~= nil and previous ~= onlineId and Client.announced[previous] == key then
        Client.announced[previous], Client.announcedAtMs[previous] = nil, nil
    end
    Client.announced[onlineId], Client.announcedAtMs[onlineId] = key, now
    Client.announcedOnline[key] = onlineId
end

function Client.announcedIdentity(onlineId, now)
    onlineId = realOnlineId(onlineId)
    local key = onlineId ~= nil and Client.announced[onlineId] or nil
    if key == nil then return nil end
    local at = Client.announcedAtMs[onlineId]
    now = tonumber(now) or nowMs()
    if at == nil or now < at or now - at >= Client.announceLeaseMs then return nil end
    local uid, generation = string.match(key, "^uid:(.+):([^:]*)$")
    return uid, tonumber(generation)
end

function Client.sweepAnnounced(now)
    if now < Client.nextAnnounceSweepAtMs and now >= Client.nextAnnounceSweepAtMs - Client.announceSweepMs then
        return 0
    end
    Client.nextAnnounceSweepAtMs = now + Client.announceSweepMs
    local stale
    for onlineId, at in pairs(Client.announcedAtMs) do
        if now < at or now - at >= Client.announceLeaseMs then
            stale = stale or {}
            stale[#stale + 1] = onlineId
        end
    end
    for _, onlineId in ipairs(stale or {}) do
        local key = Client.announced[onlineId]
        if key ~= nil and Client.announcedOnline[key] == onlineId then Client.announcedOnline[key] = nil end
        Client.announced[onlineId], Client.announcedAtMs[onlineId] = nil, nil
    end
    return stale and #stale or 0
end

function Client.forget(shell)
    if shell == nil then return false end
    Client.presented[shell], Client.weaponPresented[shell] = nil, nil
    return true
end

local function shellAvailable(shell)
    if shell == nil then return false end

    local currentOk, square = pcall(function() return shell:getCurrentSquare() end)
    if currentOk then return square ~= nil end
    local ok, exists = pcall(function() return shell:isExistInTheWorld() end)
    if ok then return exists == true end
    return true
end

local function buildIndex()
    local lookup = { online = {}, identity = {}, seenOnline = {} }
    if type(getCell) ~= "function" then return nil end
    local cell = getCell()
    local zombies = cell and cell:getZombieList() or nil
    if zombies == nil then zombies = { size = function() return 0 end, get = function() return nil end } end
    local function index(shell)
        local onlineOk, onlineId = pcall(function() return shell:getOnlineID() end)
        onlineId = onlineOk and realOnlineId(onlineId) or nil
        if onlineId ~= nil then
            lookup.online[onlineId] = shell
            lookup.seenOnline[onlineId] = shell
        end
        local uid, generation = identity(shell)
        if type(uid) == "string" then
            local key = "uid:" .. uid .. ":" .. tostring(generation)
            lookup.identity[key] = shell
            Client.identityShell[key] = shell
        end
    end
    for itemIndex = 0, zombies:size() - 1 do
        index(zombies:get(itemIndex))
    end
    for _, shell in pairs(Client.observed) do index(shell) end
    for onlineId, boundShell in pairs(Client.onlineShell) do
        if lookup.seenOnline[onlineId] ~= boundShell then
            Client.onlineShell[onlineId] = nil
            Client.onlineIdentity[onlineId] = nil
        end
    end
    Client.indexScans = Client.indexScans + 1
    return lookup
end

local function quickIndex()
    return { identity = {}, online = Client.observed, seenOnline = {} }
end

local function resolve(message, index)
    local identityKey = type(message.uid) == "string" and messageKey(message) or nil
    if identityKey ~= nil then
        local shell = Client.identityShell[identityKey]
        if shellAvailable(shell) then
            local uid, generation = identity(shell)
            if uid == message.uid and generation == tonumber(message.generation) then return shell end
        end
        Client.identityShell[identityKey] = nil
        if index == nil then index = quickIndex() end
        shell = index.identity[identityKey]
        if shellAvailable(shell) then
            local uid, generation = identity(shell)
            if uid == message.uid and generation == tonumber(message.generation) then return shell end
        end
        local onlineId = realOnlineId(message.onlineId)
        shell = onlineId and index.online[onlineId] or nil
        if not shellAvailable(shell) then return nil end

        local idOk, currentId = pcall(function() return shell:getOnlineID() end)
        if not idOk or realOnlineId(currentId) ~= onlineId then return nil end
        local uid, generation = identity(shell)
        if type(uid) == "string" then
            return uid == message.uid and generation == tonumber(message.generation)
                and shell or nil
        end
        local previousIdentity = Client.onlineIdentity[onlineId]
        local previousShell = Client.onlineShell[onlineId]
        if previousIdentity ~= nil and previousIdentity ~= identityKey
                and previousShell == shell then return nil end
        local stamped = pcall(function()
            local data = shell:getModData()
            data.ProjectALifeOwned = true
            data.ProjectALifeActor = true
            data.ProjectALifeUID = message.uid
            data.ProjectALifeGeneration = tonumber(message.generation)
            setVariable(shell, "ALifeActor", true)
        end)
        if not stamped then return nil end
        Client.onlineIdentity[onlineId] = identityKey
        Client.onlineShell[onlineId] = shell
        Client.identityShell[identityKey] = shell
        return shell
    end
    local onlineId = realOnlineId(message.onlineId)
    local shell = onlineId and Client.onlineShell[onlineId] or nil
    if shellAvailable(shell) then return shell end
    if index == nil then index = quickIndex() end
    return onlineId and index.online[onlineId] or nil
end

function Client.bodyLocation(item)
    local hydrator = ProjectALife.ProfileHydrator
    if hydrator ~= nil and type(hydrator.bodyLocationOf) == "function" then
        return hydrator.bodyLocationOf(item)
    end
    local where
    if item.getBodyLocation ~= nil then where = item:getBodyLocation() end
    if (where == nil or where == "") and item.canBeEquipped ~= nil then where = item:canBeEquipped() end
    local kind = type(where)
    if (kind == "string" and where ~= "") or kind == "userdata" or kind == "table" then return where end
    return nil
end

local function presentationSignature(message)
    local value = message.presentation or {}
    local clothing = type(value.clothing) == "table" and value.clothing or {}
    return table.concat({
        tostring(message.uid), tostring(message.generation), tostring(message.onlineId),
        tostring(value.female), tostring(value.skin), tostring(value.hair),
        tostring(value.voiceProfile),
        humanSkinTexture(value), tostring(value.beard), tostring(value.hairColor),
        tostring(value.beardColor), table.concat(clothing, "|"),
        tostring(value.appearanceSeed),
        table.concat(type(value.clothingTints) == "table" and value.clothingTints or {}, "|"),
    }, ":")
end

local function applyPresentation(shell, message)
    local presentation = message.presentation
    if type(presentation) ~= "table" then return end

    local dyingOk, dying = pcall(function() return shell:isDead() end)
    if dyingOk and dying == true then

        pcall(function()
            local worn = shell:getWornItems()
            if worn == nil or (worn.size ~= nil and worn:size() > 0) then return end
            local hydrator = ProjectALife.ProfileHydrator
            if hydrator == nil or type(hydrator.wear) ~= "function" then return end
            local dressed = 0
            for index, itemType in ipairs(type(presentation.clothing) == "table"
                    and presentation.clothing or {}) do
                local item = type(instanceItem) == "function" and instanceItem(itemType) or nil
                if item ~= nil then
                    if type(hydrator.prepareClothing) == "function" then
                        hydrator.prepareClothing(item, { itemType = itemType,
                            tint = presentation.clothingTints and presentation.clothingTints[index] },
                            presentation.appearanceSeed or message.uid)
                    end
                    if hydrator.wear(shell, item) then dressed = dressed + 1 end
                end
            end
            if dressed > 0 then
                Client.metrics = Client.metrics or {}
                Client.metrics.corpsesDressed = (Client.metrics.corpsesDressed or 0) + 1
            end
        end)
        return
    end
    local signature = presentationSignature(message)
    if Client.presented[shell] == signature then return end
    local hydrator = ProjectALife.ProfileHydrator
    if hydrator ~= nil and type(hydrator.showBandages) == "function" then hydrator.showBandages(shell, {}) end
    Client.showBandages(shell, {})
    local complete = true
    local ok = pcall(function()
        local data = shell:getModData()
        data.ProjectALifeOwned = true
        data.ProjectALifeActor = true
        data.ProjectALifeUID = message.uid
        data.ProjectALifeGeneration = tonumber(message.generation)
        data.ProjectALifeSkinTexture = humanSkinTexture(presentation)
        AIFence.track(shell)
        setVariable(shell, "ALifeActor", true)
        setVariable(shell, "ALifeUID", message.uid)
        setVariable(shell, "ALifeGeneration", message.generation)
        if presentation.voiceProfile ~= nil then
            data.ProjectALifeVoiceProfile = presentation.voiceProfile
            setVariable(shell, "ALifeVoiceProfile", presentation.voiceProfile)
        end
        if presentation.female ~= nil then
            data.ProjectALifeFemale = presentation.female
            setVariable(shell, "ALifeFemale", presentation.female)
            shell:setFemaleEtc(presentation.female)
        end
        pcall(function() shell:setDressInRandomOutfit(false) end)
        pcall(function() shell:setPersistentOutfitID(0, true) end)
        local visual = shell:getHumanVisual()
        if visual ~= nil then
            visual:clear()
            if tonumber(presentation.skin) then
                visual:setSkinTextureIndex(humanSkinIndex(presentation.skin))
            end
            visual:setSkinTextureName(humanSkinTexture(presentation))
            visual:removeBlood()
            visual:removeDirt()
            visual:setHairModel(tostring(presentation.hair or ""))
            visual:setBeardModel(tostring(presentation.beard or ""))
            applyColor(visual, presentation.hairColor, false)
            applyColor(visual, presentation.beardColor, true)
        end
        local itemVisuals = shell:getItemVisuals()
        local createdVisuals, createdItems = {}, {}
        for index, itemType in ipairs(type(presentation.clothing) == "table"
                and presentation.clothing or {}) do
            local item = type(instanceItem) == "function" and instanceItem(itemType) or nil
            local hydrator = ProjectALife.ProfileHydrator
            if item ~= nil and hydrator ~= nil and type(hydrator.prepareClothing) == "function" then
                hydrator.prepareClothing(item, { itemType = itemType,
                    tint = presentation.clothingTints and presentation.clothingTints[index] },
                    presentation.appearanceSeed or message.uid)
            end
            local itemVisual = item and item:getVisual() or nil
            if itemVisual ~= nil then
                createdVisuals[#createdVisuals + 1] = itemVisual
                createdItems[#createdItems + 1] = item
            end
        end
        complete = #createdVisuals == #(type(presentation.clothing) == "table" and presentation.clothing or {})
        if not complete then return end

        if itemVisuals ~= nil and #createdVisuals > 0 then
            itemVisuals:clear()

            if type(shell.clearWornItems) == "function" then shell:clearWornItems() end
            for _, itemVisual in ipairs(createdVisuals) do itemVisuals:add(itemVisual) end

            local hydrator = ProjectALife.ProfileHydrator
            for _, item in ipairs(createdItems) do
                if hydrator ~= nil and type(hydrator.wear) == "function" then
                    hydrator.wear(shell, item)
                else

                    pcall(function()
                        local where = Client.bodyLocation(item)

                        if where ~= nil then
                            local list = shell:getWornItems()
                            if list ~= nil then list:setItem(where, item) end
                        end
                    end)
                end
            end
        end
        shell:onWornItemsChanged()
        shell:resetModelNextFrame()
    end)
    if ok and complete then
        Client.presented[shell] = signature
        local hydrator = ProjectALife.ProfileHydrator
        if hydrator ~= nil and type(hydrator.bandageShown) == "table" then hydrator.bandageShown[shell] = nil end
        Client.bandageShown[shell] = nil
        Client.woundShown[shell] = nil
    end
end

Client.bandageShown = setmetatable({}, { __mode = "k" })
Client.woundShown = setmetatable({}, { __mode = "k" })

function Client.showBandages(shell, types)
    types = type(types) == "table" and types or {}
    local key = table.concat(types, "|")
    local state = Client.bandageShown[shell]
    if (state == nil and key == "") or (state ~= nil and state.key == key) then return false end
    if type(instanceItem) ~= "function" or shell == nil then return false end
    return pcall(function()
        local list, visuals = shell:getWornItems(), shell:getItemVisuals()
        if state ~= nil then
            for _, old in ipairs(state.items) do
                if list ~= nil and type(list.remove) == "function" then list:remove(old) end
                local oldVisual = old:getVisual()
                if visuals ~= nil and oldVisual ~= nil then visuals:remove(oldVisual) end
            end
        end
        local items = {}
        for _, itemType in ipairs(types) do
            local item = type(itemType) == "string" and instanceItem(itemType) or nil
            local visual = item ~= nil and item:getVisual() or nil
            local where = visual ~= nil and Client.bodyLocation(item) or nil
            if where ~= nil and list ~= nil then
                if visuals ~= nil then visuals:add(visual) end
                list:setItem(where, item)
                items[#items + 1] = item
            end
        end
        shell:onWornItemsChanged()
        Client.bandageShown[shell] = { key = key, items = items }
        shell:resetModelNextFrame()
    end)
end

function Client.applyBandages(shell, message)
    local hydrator = ProjectALife.ProfileHydrator
    local types
    if message.bandages ~= nil then
        types = Animations.poseBandages(message.bandages)
    else
        local presentation = message.presentation
        if type(presentation) ~= "table" or Client.presented[shell] == nil then return end
        types = presentation.bandages
    end
    if hydrator ~= nil and type(hydrator.showBandages) == "function" then
        hydrator.showBandages(shell, types)
        return
    end
    Client.showBandages(shell, types)
end

function Client.applyWounds(shell, message)
    if message.wounds == nil then return end
    local data = shell:getModData()
    data.ProjectALifeWounds = message.wounds
    data.ProjectALifeInjured = message.injured ~= "" and message.injured or nil
    local previous = Client.woundShown[shell] or 0
    if message.wounds > previous then
        local health = ProjectALife.Health
        for _ = 1, math.min(3, message.wounds - previous) do
            if health ~= nil and type(health.stain) == "function" then
                health.stain(shell, message.woundZone)
            elseif type(shell.addBlood) == "function" then
                shell:addBlood(nil, false, true, false)
            end
        end
    end
    Client.woundShown[shell] = message.wounds
end

local function applyWeaponPresentation(shell, message)
    local deadOk, dead = pcall(function() return shell:isDead() end)
    if deadOk and dead == true then return end
    local signature = table.concat({ tostring(message.uid), tostring(message.generation),
        tostring(message.weaponType), tostring(message.weaponClass),
        tostring(message.weaponLocation), tostring(message.weaponHeld),
        tostring(message.combatHold), tostring(message.readyCarry) }, ":")

    local previous = Animations.weaponVisuals and Animations.weaponVisuals[shell]
    local weapon = previous and previous.itemType == message.weaponType and previous.item or nil
    if weapon == nil and type(message.weaponType) == "string" and type(instanceItem) == "function" then
        weapon = instanceItem(message.weaponType)
    end
    if type(message.weaponType) == "string" and message.weaponType ~= "" and weapon == nil then return end
    if Animations.presentWeapon(shell, weapon, message.weaponType,
            message.weaponClass, message.weaponHeld == true or message.combatHold == true
                or message.readyCarry == true) == true then
        Client.weaponPresented[shell] = signature
    end
end

local function apply(message, index)
    local shell = resolve(message, index)
    if shell == nil then return false end

    local sim = ProjectALife.ShellSimulation
    if sim ~= nil and type(sim.grappledCorpse) == "function" and sim.grappledCorpse(shell) then
        Client.metrics = Client.metrics or {}
        Client.metrics.corpsesRefused = (Client.metrics.corpsesRefused or 0) + 1
        return true
    end

    local executor = ProjectALife.Executor
    if executor ~= nil and executor.executes(shell) then
        Client.presented[shell], Client.weaponPresented[shell] = nil, nil
        return true
    end
    local data = nil
    pcall(function()
        data = shell:getModData()
        data.ProjectALifePace = message.pace == "sprint" and "sprint" or (message.pace == "run" and "run" or "walk")
        data.ProjectALifeCombatPhase = tostring(message.combatPhase or "idle")
        data.ProjectALifeAimWalk = message.aimWalk == true
        data.ProjectALifeDangerPosture = tostring(message.dangerPosture or "relaxed")

        data.ProjectALifeWeaponHeld = message.weaponHeld == true or message.combatHold == true
            or message.readyCarry == true
        data.ProjectALifeHandsBusyUntilMs = tonumber(message.handsBusyUntilMs)
        if type(message.weaponClass) == "string" and message.weaponClass ~= "" then
            data.ProjectALifeWeaponClass = message.weaponClass
        end
        data.ProjectALifeSneakActive = message.sneak == true or nil
        data.ProjectALifeWoundLeg = message.limp == true or nil
    end)
    setVariable(shell, "ALifeSneak", message.sneak == true)
    setVariable(shell, "ALifeLimp", message.limp == true)
    setVariable(shell, "ALifePace", data ~= nil and data.ProjectALifePace or "walk")
    setVariable(shell, "ALifeCombatPhase", tostring(message.combatPhase or "idle"))
    setVariable(shell, "ALifeAimWalk", message.aimWalk == true)

    if message.combatHold == true then
        Animations.combatHold[shell] = true
    else
        Animations.combatHold[shell] = nil
    end
    if message.readyCarry == true then
        Animations.readyCarry[shell] = true
    else
        Animations.readyCarry[shell] = nil
    end
    applyPresentation(shell, message)
    Client.applyBandages(shell, message)
    Client.applyWounds(shell, message)
    applyWeaponPresentation(shell, message)
    Animations.applyRemote(shell, message.animation, message.animationSerial)
    if ProjectALife.ShellSimulation and message.simulation then
        ProjectALife.ShellSimulation.receive(shell, message.simulation)
    end
    Interop.spawned(shell, message.uid, message.generation)
    return true
end

local function dequeue(key)
    local message = Client.pending[key]
    Client.pending[key] = nil
    for index = #Client.order, 1, -1 do
        if Client.order[index] == key then table.remove(Client.order, index) end
    end
    if message ~= nil then
        local onlineId = realOnlineId(message.onlineId)
        if onlineId ~= nil and Client.pendingByOnline[onlineId] == key then
            Client.pendingByOnline[onlineId] = nil
        end
    end
end

function Client.releaseOnline(onlineId, key, keep)
    if onlineId ~= nil and onlineId ~= keep and Client.pendingByOnline[onlineId] == key then
        Client.pendingByOnline[onlineId] = nil
    end
end

function Client.dropOldest()
    local dropped = table.remove(Client.order, 1)
    if dropped == nil then return nil end
    local message = Client.pending[dropped]
    Client.pending[dropped] = nil
    if message ~= nil then Client.releaseOnline(realOnlineId(message.onlineId), dropped, nil) end
    Client.dropped = Client.dropped + 1
    return dropped
end

function Client.observe(shell)
    if shell == nil then return end
    local onlineId = record(shell)
    if onlineId == nil or #Client.order == 0 then return end
    local key = Client.pendingByOnline[onlineId]
    local message = key and Client.pending[key] or nil
    if message ~= nil and apply(message, quickIndex()) then
        Client.applied = Client.applied + 1
        Client.immediate = Client.immediate + 1
        dequeue(key)
    end
end

local function finite(value)
    return type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

function Client.validMessage(message)
    if type(message) ~= "table" then return false end
    if not Animations.validWoundPose(message) then return false end
    if message.simulation ~= nil and (not ProjectALife.ShellSimulation
            or not ProjectALife.ShellSimulation.valid(message.simulation)) then return false end
    for _, key in ipairs({"onlineId", "generation", "animationSerial", "handsBusyUntilMs"}) do
        if message[key] ~= nil and not finite(message[key]) then return false end
    end
    if message.uid ~= nil and (type(message.uid) ~= "string" or #message.uid < 1
            or #message.uid > 64 or not finite(message.generation)) then return false end
    local presentation = message.presentation
    if presentation ~= nil then
        if type(presentation) ~= "table" then return false end
        if presentation.female ~= nil and type(presentation.female) ~= "boolean" then return false end
        if presentation.skin ~= nil and not finite(presentation.skin) then return false end
        if presentation.voiceProfile ~= nil then
            local catalog = ProjectALife.VoiceCatalog
            local profile = type(presentation.voiceProfile) == "string"
                and catalog and catalog.profiles[presentation.voiceProfile]
            if type(profile) ~= "table" or profile.shipEnabled == false then return false end
        end
    end
    return true
end

function Client.visualsQALine()
    local seen, wounded, idle = {}, 0, 0
    local function count(shell)
        if shell == nil or seen[shell] then return end
        seen[shell] = true
        local ok, data = pcall(function() if shell:isDead() then return nil end; return shell:getModData() end)
        if not ok or type(data) ~= "table" or type(data.ProjectALifeUID) ~= "string" then return end
        if data.ProjectALifeWoundLeg == true or data.ProjectALifeInjured ~= nil
                or (tonumber(data.ProjectALifeWounds) or 0) > 0 then wounded = wounded + 1 end
        local preset = Animations.presetOf(Animations.current[shell])
        if preset ~= nil and preset.idle == true then idle = idle + 1 end
    end
    for _, shell in pairs(Client.observed) do count(shell) end
    local executor = ProjectALife.Executor
    for _, entry in pairs(executor ~= nil and executor.executed or {}) do count(entry.shell) end
    return "[ALIFE-QA] client Visuals: wounded=" .. tostring(wounded) .. " idle=" .. tostring(idle)
end

local function onServerCommand(module, command, arguments)
    if module ~= "ProjectALife" or command ~= "animationSync"
            or not Client.validMessage(arguments) then return end
    if not Animations.supports(arguments.animation) then return end
    local key = messageKey(arguments)
    if key == nil then return end
    local now = nowMs()
    arguments.deadlineAtMs = now + 3000
    local onlineId = realOnlineId(arguments.onlineId)
    local waiting = Client.pending[key]
    if waiting == nil then
        if #Client.order >= Client.maximumPending then
            Client.dropOldest()
        end
        Client.order[#Client.order + 1] = key
    else

        Client.releaseOnline(realOnlineId(waiting.onlineId), key, onlineId)
    end
    Client.pending[key] = arguments
    if onlineId ~= nil then Client.pendingByOnline[onlineId] = key end
    if type(arguments.uid) == "string" then Client.announce(onlineId, key, now) end
    Client.sweepAnnounced(now)

    if apply(arguments, quickIndex()) then
        Client.applied = Client.applied + 1
        Client.immediate = Client.immediate + 1
        dequeue(key)
    end
end

local function onTick()
    Client.ticks = Client.ticks + 1
    Animations.tick(8)
    if #Client.order == 0 then return end
    local now = nowMs()
    local unresolved = false
    for index = #Client.order, 1, -1 do
        local key = Client.order[index]
        local message = Client.pending[key]
        local done = message == nil or apply(message, nil)
        if done and message ~= nil then Client.applied = Client.applied + 1 end
        if done or now >= message.deadlineAtMs then
            dequeue(key)
        else
            unresolved = true
        end
    end
    if unresolved and now - Client.lastIndexAtMs >= Client.indexIntervalMs then
        Client.lastIndexAtMs = now
        local shellIndex = buildIndex()
        for index = #Client.order, 1, -1 do
            local key = Client.order[index]
            local message = Client.pending[key]
            local done = message == nil or apply(message, shellIndex)
            if done and message ~= nil then Client.applied = Client.applied + 1 end
            if done or now >= message.deadlineAtMs then dequeue(key) end
        end
    end
end

function Client.diagnostics()
    local listSize = -1
    pcall(function()
        local zombies = getCell():getZombieList()
        listSize = zombies and zombies:size() or -1
    end)
    local observed = 0
    for _ in pairs(Client.observed) do observed = observed + 1 end
    local text = "appearanceFix=20260915 list=" .. tostring(listSize) .. " observed=" .. tostring(observed)
        .. " scans=" .. tostring(Client.indexScans) .. " ticks=" .. tostring(Client.ticks)
        .. " applied=" .. tostring(Client.applied) .. " immediate=" .. tostring(Client.immediate)
        .. " dropped=" .. tostring(Client.dropped)
    local key = Client.order[1]
    local message = key and Client.pending[key] or nil
    if message ~= nil then
        local onlineId = realOnlineId(message.onlineId)
        local inObserved = onlineId ~= nil and Client.observed[onlineId] ~= nil
        local inList = false
        pcall(function()
            local zombies = getCell():getZombieList()
            for itemIndex = 0, zombies:size() - 1 do
                local shell = zombies:get(itemIndex)
                if realOnlineId(shell:getOnlineID()) == onlineId then inList = true end
            end
        end)
        text = text .. " first=" .. tostring(key) .. " onlineId=" .. tostring(message.onlineId)
            .. " inObserved=" .. tostring(inObserved) .. " inList=" .. tostring(inList)
        local replica = onlineId ~= nil and Client.observed[onlineId] or nil
        if replica ~= nil then
            local uid, generation = identity(replica)
            local rawOk, raw = pcall(function() return replica:GetVariable("ALifeUID") end)
            local existsOk, exists = pcall(function() return replica:isExistInTheWorld() end)
            local remoteOk, remote = pcall(function() return replica:isRemoteZombie() end)
            text = text .. " replicaUid=" .. tostring(uid) .. ":" .. tostring(generation)
                .. " rawVar=" .. (rawOk and ("[" .. tostring(raw) .. "]") or "err")
                .. " exists=" .. (existsOk and tostring(exists) or "err")
                .. " remote=" .. (remoteOk and tostring(remote) or "err")
        end
    end
    return text
end

Client.receive, Client.tick = onServerCommand, onTick

if type(Events) == "table" then
    if Events.OnServerCommand ~= nil then Events.OnServerCommand.Add(onServerCommand) end
    if Events.OnTick ~= nil then Events.OnTick.Add(onTick) end
end

return Client
