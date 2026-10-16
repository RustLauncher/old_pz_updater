ProjectALife = ProjectALife or {}

require "ProjectALife/Records/ALifeBehaviorSettings"
require "ProjectALife/Records/ALifeRecordCodec"
require "ProjectALife/Records/ALifeRecordMigration"

local Custom = {
    fileName = "alife_custom_profiles.ini",
    deletedFileName = "alife_deleted_profiles.ini",
    profiles = {},
    deleted = {},
    revision = 0,
    serverManaged = false,
    loadFailed = false,
}
ProjectALife.CustomProfiles = Custom

Custom.newcomer = { strength = 4, endurance = 7, awareness = 7, aiming = 3 }

function Custom.startingHP()
    local combat = ProjectALife.BehaviorSettings and ProjectALife.BehaviorSettings.combat
    return tonumber(combat and combat.standardHealth) or 50
end

function Custom.rating(general, key)
    local value = type(general) == "table" and tonumber(general[key]) or nil
    if value ~= nil then return value end
    if key == "healthHP" then return Custom.startingHP() end
    return Custom.newcomer[key]
end

local FIELD_ORDER = {
    "faction", "name", "female", "skin", "hairStyle", "hairColor",
    "beardStyle", "beardColor",
    "healthHP", "strength", "endurance", "awareness", "aiming",
    "aimPlayerPercent", "aimZombiePercent", "voiceProfile", "profession",
    "role", "rank", "defaultActivity", "spawnWeight", "tags", "notes",
    "behaviorProfile", "primaryBehavior", "combatReady", "ammoMode",
    "primaryMagazines", "secondaryMagazines",
    "infiniteAmmo", "supportCaller", "supportPolicy", "supportType", "supportHeli", "dropAmmo",
    "magazineDropMax", "magazineDropChance", "dropWeapon",
    "dropWeaponChance", "dropWeaponPreset", "dropWeaponCondition", "dropArmorChance",
    "armorCondition", "damageReduction", "damageOutput", "nameMode", "fixedName", "npcClass",
    "lookFixed", "lookVary", "toneFixed",
}

local DEFAULT_GENERAL = {

    faction = "alife_riverside", name = "Custom NPC", female = false, skin = 0,
    hairStyle = "", hairColor = "0.18,0.12,0.08",
    beardStyle = "", beardColor = "0.18,0.12,0.08",
    strength = Custom.newcomer.strength, endurance = Custom.newcomer.endurance,
    awareness = Custom.newcomer.awareness, aiming = Custom.newcomer.aiming, voiceProfile = "",
    profession = "none", role = "Scout", rank = "Regular",
    defaultActivity = "patrol", spawnWeight = 1.0, tags = "", notes = "",
    behaviorProfile = "seek_destroy", primaryBehavior = "none",
    combatReady = "default", ammoMode = "magazines",
    primaryMagazines = 3, secondaryMagazines = 0,
    infiniteAmmo = false, supportCaller = false,
    dropAmmo = true, magazineDropMax = 1, magazineDropChance = 35,
    dropWeapon = true, dropWeaponChance = 100, dropWeaponCondition = 1,
    dropArmorChance = 20, armorCondition = 5,
}

local CLOTHING_SLOTS = {
    "Hat", "Eyes", "Mask", "Ears", "Faces", "Neck", "Scarf",
    "Top", "Jacket", "Vest", "AmmoStrap", "Hands", "Wrist",
    "Fingers", "Underwear", "Pants", "Socks", "Shoes", "Back",
    "LeftArm", "RightArm", "LeftForearm", "RightForearm", "LeftHand", "RightHand",
    "LeftWrist", "RightWrist", "LeftShin", "RightShin", "LeftGaiter", "RightGaiter",
    "Belt", "Holster", "ShoulderHolster", "AnkleHolster", "FannyPackFront", "FannyPackBack",
    "Necklace", "LongNecklace", "Nose", "BellyButton", "LeftRing", "RightRing",
    "LeftMiddleRing", "RightMiddleRing", "UnderwearTop", "UnderwearBottom",
    "LongJohnsTop", "LongJohnsBottom", "TankTop", "Tshirt", "Sweater", "ShoulderPads",
    "Gorget", "Cuirass", "Codpiece", "Apron", "Tail", "FullSuit", "FullRobe",
    "LeftGreave", "RightGreave", "LeftKnee", "RightKnee", "LeftThigh", "RightThigh",
    "LeftShoulder", "RightShoulder", "LeftElbow", "RightElbow", "Webbing", "BreathingGear",

    "MakeUpFullFace", "MakeUpEyes", "MakeUpEyesShadow", "MakeUpLips",

    "ModdedA", "ModdedB", "ModdedC",
}
local MODULE_SLOTS = {
    "decisions", "perception", "movement", "combat", "scavenging", "voice",
}
local OUTFIT_IDS = { "A", "B", "C", "D", "E", "F" }

Custom.seasons = { spring = true, summer = true, autumn = true, winter = true }

Custom.outfitSections, Custom.tintSections = {}, {}
for _, outfitId in ipairs(OUTFIT_IDS) do
    Custom.outfitSections["outfit" .. outfitId] = outfitId
    Custom.tintSections["tint" .. outfitId] = outfitId
end

local function copy(source)
    local result = {}
    for key, value in pairs(source or {}) do result[key] = value end
    return result
end

local preparations = {}
local preparationEpoch = 0

Custom.memo = {}
Custom.stepMs = 4

function Custom.copyPreparedRecord(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    local previous = seen[value]
    if previous == false then error("cyclic prepared record") end
    if previous ~= nil then return previous end
    local result = {}
    seen[value] = false
    for key, item in pairs(value) do
        if type(item) == "table" then result[key] = Custom.copyPreparedRecord(item, seen)
        else result[key] = item end
    end
    seen[value] = result
    return result
end

function Custom.sameRecord(left, right)
    if left == right then return true end
    if type(left) ~= "table" or type(right) ~= "table" then return false end
    local count = 0
    for key, value in pairs(left) do
        local other = right[key]
        if other == nil then return false end
        if value ~= other and not (type(value) == "table" and Custom.sameRecord(value, other)) then return false end
        count = count + 1
    end
    for _ in pairs(right) do count = count - 1 end
    return count == 0
end

function Custom.memoFor(record)
    local entry = Custom.memo[record.id]
    if entry == nil then return nil end
    if entry.compact ~= Custom.compactOn() then return nil end
    local ok, same = pcall(Custom.sameRecord, entry.snapshot, record)
    if ok and same then return entry end
    return nil
end

function Custom.memoize(record, text, valid)
    local ok, snapshot = pcall(Custom.copyPreparedRecord, record)
    if not ok then return nil end
    local entry = { snapshot = snapshot, text = text, valid = valid == true, compact = Custom.compactOn() }
    Custom.memo[record.id] = entry
    return entry
end

function Custom.warmStep()
    local list = Custom.profiles
    if Custom.warmList ~= list then Custom.warmList, Custom.warmCursor = list, 1 end
    local cursor = Custom.warmCursor
    while cursor <= #list do
        local record = list[cursor]
        cursor = cursor + 1
        if type(record) == "table" and type(record.id) == "string" and not Custom.deleted[record.id]
                and Custom.memo[record.id] == nil then
            local ok, text = pcall(Custom.serializeProfile, record)
            if ok and type(text) == "string" then Custom.memoize(record, text, false) end
            Custom.warmCursor = cursor
            return true
        end
    end
    Custom.warmCursor = cursor
    return false
end

function Custom.prepareSave(profile)
    if Custom.batchLocked() then return nil end
    if (Custom.loadFailed and not Custom.serverManaged) or type(profile) ~= "table" or type(profile.id) ~= "string" then return nil end
    local copied, sources, deleted, ids, replacement = pcall(function()
        local sources, deleted, seen, ids = {}, copy(Custom.deleted), {}, {}
        local replacement, found = Custom.copyPreparedRecord(profile), false
        deleted[profile.id] = nil
        for index, record in ipairs(Custom.profiles) do
            if type(record) ~= "table" or type(record.id) ~= "string" then return nil end
            if record.id == profile.id then sources[index], found = replacement, true
            else sources[index] = record end
            seen[record.id] = true
        end
        if not found then sources[#sources + 1] = replacement; seen[profile.id] = true end
        for id, removed in pairs(deleted) do
            if type(id) ~= "string" then return nil end
            if removed and not seen[id] then ids[#ids + 1] = id end
        end
        table.sort(ids)
        return sources, deleted, ids, replacement
    end)
    if not copied or sources == nil then return nil end
    local handle = {}
    preparations[handle] = { previous = Custom.profiles, previousDeleted = Custom.deleted,
        managed = Custom.serverManaged, epoch = preparationEpoch, sources = sources, records = {}, deleted = deleted, ids = ids,
        index = 1, editId = profile.id, replacement = replacement,
        proof = ProjectALife.RecordMigration.beginPrepared("member") }
    return handle
end

function Custom.cancelPrepared(handle)
    local state = preparations[handle]
    if state ~= nil and state.editIds ~= nil and state.commitStarted and not state.published and not state.writeFailed then
        return false, "commit_in_progress"
    end
    if state ~= nil then ProjectALife.RecordMigration.cancelPrepared(state.proof) end
    if Custom.batchHandle == handle then Custom.batchHandle = nil end
    preparations[handle] = nil
    if state ~= nil and state.published then return true, "committed" end
    return true, "cancelled"
end

function Custom.batchLocked(handle)
    return Custom.batchHandle ~= nil and Custom.batchHandle ~= handle
end

function Custom.prepareManySave(profiles)
    if Custom.batchLocked() then return nil end
    if (Custom.loadFailed and not Custom.serverManaged) or type(profiles) ~= "table" or #profiles == 0 then return nil end
    local copied, sources, deleted, ids, edits, count = pcall(function()
        local sources, deleted, seen, ids, edits, count = {}, copy(Custom.deleted), {}, {}, {}, 0
        for _, profile in ipairs(profiles) do
            if type(profile) ~= "table" or type(profile.id) ~= "string" or edits[profile.id] ~= nil then return nil end
            edits[profile.id] = Custom.copyPreparedRecord(profile)
            deleted[profile.id] = profile.general and profile.general.deleted == true or nil
            count = count + 1
        end
        for index, record in ipairs(Custom.profiles) do
            if type(record) ~= "table" or type(record.id) ~= "string" then return nil end
            sources[index] = edits[record.id] or record
            seen[record.id] = true
        end
        for _, profile in ipairs(profiles) do
            if not seen[profile.id] then sources[#sources + 1] = edits[profile.id]; seen[profile.id] = true end
        end
        for id, removed in pairs(deleted) do
            if type(id) ~= "string" then return nil end
            if removed and not seen[id] then ids[#ids + 1] = id end
        end
        table.sort(ids)
        return sources, deleted, ids, edits, count
    end)
    if not copied or sources == nil then return nil end
    local handle = {}
    preparations[handle] = { previous = Custom.profiles, previousDeleted = Custom.deleted,
        managed = Custom.serverManaged, epoch = preparationEpoch, sources = sources, records = {}, deleted = deleted, ids = ids,
        index = 1, editIds = edits, editCount = count, editTexts = {},
        inputProfiles = profiles,
        proof = ProjectALife.RecordMigration.beginPrepared("member") }
    return handle
end

function Custom.batchInputsCurrent(state)
    local profiles, seen = state.inputProfiles, {}
    if type(profiles) ~= "table" or #profiles ~= state.editCount then return false end
    for _, profile in ipairs(profiles) do
        if type(profile) ~= "table" or seen[profile.id] or not Custom.sameRecord(profile, state.editIds[profile.id]) then return false end
        seen[profile.id] = true
    end
    return true
end

function Custom.publishManyPrepared(state, handle)
    Custom.profiles, Custom.deleted = state.records, state.deleted
    Custom.loadMemo, state.published = nil, true
    ProjectALife.RecordMigration.cancelPrepared(state.proof)
    if Custom.batchHandle == handle then Custom.batchHandle = nil end
end

function Custom.preparedEdit(state, id)
    if state.editIds ~= nil then return state.editIds[id] ~= nil end
    return id == state.editId
end

function Custom.preparationCurrent(handle)
    local state = preparations[handle]
    return state ~= nil and state.previous == Custom.profiles and state.previousDeleted == Custom.deleted
        and state.epoch == preparationEpoch
        and state.managed == Custom.serverManaged and (not Custom.loadFailed or Custom.serverManaged)
end

function Custom.prepareUnit(state)
    local Migration = ProjectALife.RecordMigration
    if state.pendingText ~= nil then
        local trusted = not Custom.preparedEdit(state, state.pendingId) or (state.pendingEntry ~= nil and state.pendingEntry.valid == true)
        if not Migration.addPrepared(state.proof, state.pendingText, trusted and state.pendingId or nil) then return false end
        if state.pendingEntry ~= nil then
            if Custom.preparedEdit(state, state.pendingId) then state.pendingEntry.valid = true end
            Custom.memo[state.pendingId] = state.pendingEntry
        end
        if state.pendingId == state.editId then state.editText = state.pendingText end
        if state.editIds ~= nil and state.editIds[state.pendingId] ~= nil then state.editTexts[state.pendingId] = state.pendingText end
        state.pendingText, state.pendingId, state.pendingEntry, state.index = nil, nil, nil, state.index + 1
        return true
    end
    local index, count = state.index, #state.sources
    if index <= count + #state.ids then
        local record, text, entry, id
        if index <= count then
            local source = state.sources[index]
            if source == state.replacement then record = source
            else record = Custom.copyPreparedRecord(source) end
            state.records[index] = record
            id = record.id
            if state.deleted[id] then
                text = Custom.serializeProfile(Custom.deletionRecord(id))
            else
                entry = Custom.memoFor(record)
                if entry ~= nil then text = entry.text end
                if text == nil then
                    text = Custom.serializeProfile(record)
                    if type(text) == "string" then entry = Custom.memoize(record, text, false) end
                end
            end
        else
            id = state.ids[index - count]
            text = Custom.serializeProfile(Custom.deletionRecord(id))
        end
        if type(text) ~= "string" then return false end
        state.pendingText, state.pendingId, state.pendingEntry = text, id, entry
        if id ~= state.editId or (entry ~= nil and entry.valid == true) then return Custom.prepareUnit(state) end
        return true
    end
    state.text = Migration.finishPrepared(state.proof)
    if state.text == nil then return false end
    local seen, stale = {}, {}
    for _, record in ipairs(state.records) do seen[record.id] = true end
    for id in pairs(Custom.memo) do
        if not seen[id] then stale[#stale + 1] = id end
    end
    for _, id in ipairs(stale) do Custom.memo[id] = nil end
    return true
end

function Custom.stepPrepared(handle)
    local state = preparations[handle]
    if state ~= nil and state.editIds ~= nil then
        if state.published then return true, true end
        if state.writeFailed then return false, false end
        if not state.commitStarted then
            if not Custom.preparationCurrent(handle) or Custom.batchLocked(handle)
                    or state.text ~= nil and not Custom.batchInputsCurrent(state) then return false, false end
        end
    elseif not Custom.preparationCurrent(handle) or Custom.batchLocked(handle) then return false, false end
    if state.text ~= nil then
        if not state.commitStarted then
            local name = state.managed and "alife_server_profiles.ini" or Custom.fileName
            if not ProjectALife.RecordMigration.beginPreparedWrite(state.proof, name, state.text, "member") then return false, false end
            state.commitStarted = true
            if state.editIds ~= nil then Custom.batchHandle = handle end
            return true, false
        end
        local ok, ready = ProjectALife.RecordMigration.stepPreparedWrite(state.proof)
        state.committed = ok and ready
        if state.editIds ~= nil then
            if not ok then
                state.writeFailed = true
                ProjectALife.RecordMigration.cancelPrepared(state.proof)
                if Custom.batchHandle == handle then Custom.batchHandle = nil end
            elseif ready then Custom.publishManyPrepared(state, handle) end
        end
        return ok, ready
    end
    local clock = ProjectALife.RecordMigration.transactionClock
    local startedAt = clock()
    local ok, result = pcall(function()
        for _ = 1, 4096 do
            if not Custom.prepareUnit(state) or state.text ~= nil then return state.text ~= nil or false end
            local now = startedAt ~= nil and clock() or nil
            if now == nil or now < startedAt or now - startedAt >= Custom.stepMs then return true end
        end
        return true
    end)
    return ok and result == true, false
end

function Custom.savePrepared(profile, handle)
    if Custom.batchLocked(handle) then return false end
    local state = preparations[handle]
    if not Custom.preparationCurrent(handle) or state.text == nil or not state.committed then return false end
    local ok, same = pcall(function()
        local entry = Custom.memoFor(profile)
        if entry ~= nil then return entry.text == state.editText end
        return Custom.serializeProfile(profile) == state.editText
    end)
    if not ok or not same then return false end
    Custom.profiles, Custom.deleted = state.records, state.deleted
    Custom.loadMemo = nil
    Custom.cancelPrepared(handle)
    return true
end

function Custom.saveManyPrepared(profiles, handle)
    local state = preparations[handle]
    if state == nil or state.editIds == nil or not state.published then return false end
    Custom.cancelPrepared(handle)
    return true
end

function Custom.blank(id)
    local general = {}
    for key, value in pairs(DEFAULT_GENERAL) do general[key] = value end
    general.healthHP = Custom.startingHP()
    local clothing = { Hat = "none", Eyes = "none", Mask = "none",
        Ears = "none", Faces = "none", Neck = "none", Scarf = "none",
        Top = "Base.Shirt_Workman", Jacket = "none", Vest = "none",
        AmmoStrap = "none", Hands = "none", Wrist = "none",
        Fingers = "none", Underwear = "none",
        Pants = "Base.Trousers_Denim", Socks = "none",
        Shoes = "Base.Shoes_Random", Back = "none",

        MakeUpFullFace = "none", MakeUpEyes = "none",
        MakeUpEyesShadow = "none", MakeUpLips = "none",
        ModdedA = "none", ModdedB = "none", ModdedC = "none" }
    local outfitSets = { A = copy(clothing) }
    local profile = {
        id = id or ("custom_" .. tostring(os.time and os.time() or 0)),
        general = general,
        clothing = clothing,

        outfits = outfitSets,
        outfitSets = outfitSets,
        outfitTints = { A = {} },
        outfitEnabled = { A = true, B = false, C = false,
            D = false, E = false, F = false },

        outfitSeason = {},
        weapons = { primary = "Base.Pistol", secondary = "none",
            melee = "Base.BaseballBat" },
        weaponAttachments = {},
        ammo = { primary = 30, secondary = 0 },
        modules = { decisions = "", perception = "", movement = "", combat = "",
            scavenging = "", voice = "" },
        moduleOverrides = {},
    }
    profile.syntheticOutfitA = copy(outfitSets.A)
    return profile
end

function Custom.syntheticOutfit(profile, id)
    if id ~= "A" or type(profile.syntheticOutfitA) ~= "table" then return false end
    if type(profile.outfitSeason) == "table" and profile.outfitSeason.A ~= nil then return false end
    local tints = type(profile.outfitTints) == "table" and profile.outfitTints.A or profile.tintA
    for _, tint in pairs(type(tints) == "table" and tints or {}) do
        if tostring(tint or "") ~= "" then return false end
    end
    local sets = profile.outfits or profile.outfitSets
    local outfit = type(sets) == "table" and sets.A or profile.outfitA
    return Custom.sameRecord(outfit, profile.syntheticOutfitA)
end

local function fieldText(value)
    if type(value) == "boolean" then return value and "true" or "false" end
    return tostring(value)
end

local function choiceText(value, maximum)
    if type(value) ~= "string" then return tostring(value or "none") end
    if value ~= "" and string.find(value, "[|%s]") == nil then return value end
    local choices = {}
    for choice in string.gmatch(value .. "|", "(.-)|") do
        choice = string.match(choice, "^%s*(.-)%s*$")
        if choice ~= "" and #choices < maximum then
            choices[#choices + 1] = choice
        end
    end
    return #choices > 0 and table.concat(choices, "|") or "none"
end

function Custom.readGeneral(text)
    if text == "true" then return true end
    if text == "false" then return false end
    local number = tonumber(text)
    if number ~= nil then return number end
    return text
end

function Custom.compactOn()
    if Custom.compactForced ~= nil then return Custom.compactForced == true end
    local prefs = ProjectALife.MenuPrefs
    if prefs ~= nil and type(prefs.creatorCompactSaveOn) == "function" then
        local ok, on = pcall(prefs.creatorCompactSaveOn)
        if ok then return on == true end
    end
    return true
end

function Custom.baseline()
    local known = Custom.baselineCache
    if known == nil then
        known = Custom.blank("baseline")
        Custom.baselineCache = known
    end
    return known
end

function Custom.fillSlots(set)
    for _, slot in ipairs(CLOTHING_SLOTS) do
        if set[slot] == nil then set[slot] = "none" end
    end
end

local function serializeProfile(profile)
    local Codec = ProjectALife.RecordCodec
    local block = Codec.begin("member", profile.id)
    if profile.general.deleted == true then
        Codec.put(block, "general", "deleted", true)
        return Codec.finish(block)
    end
    local compact = Custom.compactOn()
    local base = compact and Custom.baseline() or nil
    local skippedAwareness = false
    for _, key in ipairs(FIELD_ORDER) do
        local value = profile.general[key]
        if value == nil then value = DEFAULT_GENERAL[key] end
        if value ~= nil then
            local text = fieldText(value)
            local fallback = DEFAULT_GENERAL[key]
            local omit = compact and fallback ~= nil and Custom.readGeneral(text) == fallback
            if omit and key == "aiming" and not skippedAwareness then omit = false end
            if omit and key == "awareness" then skippedAwareness = true end
            if not omit then Codec.put(block, "general", key, text) end
        end
    end
    for _, slot in ipairs(CLOTHING_SLOTS) do
        local text = tostring(profile.clothing[slot] or "none")
        if not compact or text ~= tostring(base.clothing[slot] or "none") then
            Codec.put(block, "clothing", slot, text)
        end
    end
    for _, outfitId in ipairs(OUTFIT_IDS) do
        local enabled = profile.outfitEnabled and profile.outfitEnabled[outfitId]
        if enabled == nil then enabled = outfitId == "A" end
        if not compact or (enabled == true) ~= (base.outfitEnabled[outfitId] == true) then
            Codec.put(block, "outfitEnabled", outfitId, enabled and "true" or "false")
        end
        local season = profile.outfitSeason and profile.outfitSeason[outfitId] or nil
        if season ~= nil and Custom.seasons[season] then
            Codec.put(block, "outfitSeason", outfitId, season)
        end
        local sets = profile.outfits or profile.outfitSets
        local outfit = sets and sets[outfitId] or nil
        if type(outfit) == "table" and not Custom.syntheticOutfit(profile, outfitId) then
            local wrote = false
            local defaults = outfitId == "A" and base ~= nil and base.outfits.A or nil
            for _, slot in ipairs(CLOTHING_SLOTS) do
                local text = choiceText(outfit[slot] or "none", 4)
                local fallback = defaults ~= nil and defaults[slot] or nil
                if not compact or text ~= tostring(fallback or "none") then
                    Codec.put(block, "outfit" .. outfitId, slot, text)
                    wrote = true
                end
            end
            if compact and not wrote then
                Codec.put(block, "outfit" .. outfitId, CLOTHING_SLOTS[1], choiceText(outfit[CLOTHING_SLOTS[1]] or "none", 4))
            end
        end
        local tints = profile.outfitTints and profile.outfitTints[outfitId] or nil
        if type(tints) == "table" then
            for _, slot in ipairs(CLOTHING_SLOTS) do
                if type(tints[slot]) == "string" and tints[slot] ~= "" then
                    Codec.put(block, "tint" .. outfitId, slot, tostring(tints[slot]))
                end
            end
        end
    end
    for _, slot in ipairs({ "primary", "secondary", "melee" }) do
        local text = tostring(profile.weapons[slot] or "none")
        if not compact or text ~= base.weapons[slot] then Codec.put(block, "weapons", slot, text) end
    end
    local attachmentWeapons = {}
    for weaponType, parts in pairs(profile.weaponAttachments or {}) do

        if type(weaponType) == "string" and type(parts) == "string"
                and string.match(weaponType, "^%S+$") and string.find(parts, "%S") ~= nil then
            attachmentWeapons[#attachmentWeapons + 1] = weaponType
        end
    end
    table.sort(attachmentWeapons)
    for _, weaponType in ipairs(attachmentWeapons) do
        Codec.put(block, "weaponAttachments", weaponType, profile.weaponAttachments[weaponType])
    end
    for _, slot in ipairs({ "primary", "secondary" }) do
        local text = tostring(profile.ammo[slot] or 0)
        if not compact or (tonumber(text) or 0) ~= base.ammo[slot] then Codec.put(block, "ammo", slot, text) end
    end
    for _, slot in ipairs(MODULE_SLOTS) do
        local text = tostring(profile.modules and profile.modules[slot] or "")
        if not compact or text ~= tostring(base.modules[slot] or "") then Codec.put(block, "modules", slot, text) end
    end
    local overrideKeys = {}
    for key in pairs(profile.moduleOverrides or {}) do

        if type(key) == "string" and string.match(key, "^[%w_%-%.]+$") then overrideKeys[#overrideKeys + 1] = key end
    end
    table.sort(overrideKeys)
    for _, key in ipairs(overrideKeys) do
        Codec.put(block, "moduleOverrides", key, tostring(profile.moduleOverrides[key] or "inherit"))
    end
    return Codec.finish(block)
end

Custom.serializeProfile = serializeProfile

function Custom.serializeProfiles(profiles)
    local sections = {}
    for _, profile in ipairs(type(profiles) == "table" and profiles or {}) do
        sections[#sections + 1] = serializeProfile(profile)
    end
    return table.concat(sections, "\n\n")
end

function Custom.serializeAll()
    local records, seen, ids = {}, {}, {}
    for _, profile in ipairs(Custom.profiles) do
        records[#records + 1] = Custom.deleted[profile.id] and Custom.deletionRecord(profile.id) or profile
        seen[profile.id] = true
    end
    for id, deleted in pairs(Custom.deleted) do
        if deleted and not seen[id] then ids[#ids + 1] = id end
    end
    table.sort(ids)
    for _, id in ipairs(ids) do records[#records + 1] = Custom.deletionRecord(id) end
    return Custom.serializeProfiles(records)
end

function Custom.deletionRecord(id)
    local profile = Custom.blank(id)
    profile.general.deleted = true
    return profile
end

function Custom.chunkText(text)
    text = type(text) == "string" and text or ""
    local chunks = {}
    for first = 1, #text, 8000 do chunks[#chunks + 1] = string.sub(text, first, first + 7999) end
    return chunks
end

function Custom.joinChunks(chunks)
    if type(chunks) ~= "table" then return nil end
    local parts = {}
    for index = 1, #chunks do
        if type(chunks[index]) ~= "string" then return nil end
        parts[index] = chunks[index]
    end
    return table.concat(parts)
end

function Custom.applyField(profile, section, key, value)
    if section == "general" then
        if value == "true" then value = true
        elseif value == "false" then value = false
        elseif tonumber(value) ~= nil then value = tonumber(value) end
        profile.general[key] = value
    elseif section == "clothing" then
        profile.clothing[key] = value
    elseif section == "weapons" then
        profile.weapons[key] = value
    elseif section == "weaponAttachments" then
        if key ~= "" and value ~= "" then
            profile.weaponAttachments[key] = value
        else return false end
    elseif section == "ammo" then
        profile.ammo[key] = tonumber(value) or 0
    elseif section == "modules" then
        profile.modules[key] = value
    elseif Custom.outfitSections[section] ~= nil then
        local outfitId = Custom.outfitSections[section]
        profile.outfits[outfitId] = profile.outfits[outfitId] or {}
        profile.outfits[outfitId][key] = value
    elseif Custom.tintSections[section] ~= nil then
        local outfitId = Custom.tintSections[section]
        profile.outfitTints[outfitId] = profile.outfitTints[outfitId] or {}
        profile.outfitTints[outfitId][key] = value
    elseif section == "moduleOverrides" then
        profile.moduleOverrides[key] = value
    elseif section == "outfitEnabled" then
        profile.outfitEnabled[key] = value == "true"
    elseif section == "outfitSeason" then
        if string.match(key, "^[A-F]$") == nil then return false end
        profile.outfitSeason = profile.outfitSeason or {}
        if value == "random" then
            profile.outfitSeason[key] = nil
        elseif Custom.seasons[value] then
            profile.outfitSeason[key] = value
        else
            return false
        end
    else
        return false
    end
    return true
end

Custom.renamedSlots = { brain = "decisions" }

function Custom.renameSlots(slots)
    if type(slots) ~= "table" then return slots end
    for old, current in pairs(Custom.renamedSlots) do
        if slots[old] ~= nil then
            if slots[current] == nil then slots[current] = slots[old] end
            slots[old] = nil
        end
    end
    return slots
end

function Custom.fromRecord(record, strict)
    if strict and string.match(record.id, "^[%w_%-]+$") == nil then
        return nil, "profile_header_required"
    end
    Custom.renameSlots(record.modules)
    local profile = Custom.blank(record.id)
    for section, values in pairs(record) do
        if type(values) == "table" then
            for key, value in pairs(values) do
                if not Custom.applyField(profile, section, key, value) and strict then
                    return nil, "invalid_profile_line"
                end
            end
        end
    end

    local authored = type(record.general) == "table" and record.general or {}
    if authored.aiming == nil and tonumber(authored.awareness) ~= nil then
        profile.general.aiming = tonumber(authored.awareness)
    end
    if profile.general.deleted ~= true then
        Custom.fillSlots(profile.clothing)
        for _, outfitId in ipairs(OUTFIT_IDS) do
            local set = profile.outfits[outfitId]
            if set ~= nil then Custom.fillSlots(set) end
        end
    end
    if record.outfitA ~= nil then profile.syntheticOutfitA = nil
    else profile.syntheticOutfitA = copy(profile.outfits.A) end
    return profile
end

function Custom.fromRecords(records, strict)
    local profiles = {}
    for _, record in ipairs(records or {}) do
        local profile, reason = Custom.fromRecord(record, strict)
        if profile == nil then return nil, reason end
        profiles[#profiles + 1] = profile
    end
    return profiles
end

function Custom.parse(text)
    local parsed = ProjectALife.RecordCodec.decode(tostring(text or ""),
        { source = Custom.fileName, kind = "member", text = true, lenient = true })
    return Custom.fromRecords(parsed and parsed.records, false)
end

Custom.decodeReasons = {
    outside_record = "profile_header_required",
    wrong_kind = "profile_header_required",
    duplicate_record = "duplicate_profile_id",
}

function Custom.validate(text, expectedId, allowEmpty)
    if type(text) ~= "string" then return nil, "profile_text_required" end
    expectedId = type(expectedId) == "string" and expectedId or nil
    if expectedId ~= nil and string.match(expectedId, "^[%w_%-]+$") == nil then
        return nil, "invalid_profile_id"
    end
    local parsed, _, code = ProjectALife.RecordCodec.decode(text,
        { source = "profile", kind = "member", text = true })
    if parsed == nil then return nil, Custom.decodeReasons[code] or "invalid_profile_line" end
    local profiles, reason = Custom.fromRecords(parsed.records, true)
    if profiles == nil then return nil, reason end
    if #profiles == 0 and allowEmpty ~= true then
        return nil, "profile_required"
    end
    if expectedId ~= nil and (#profiles ~= 1 or profiles[1].id ~= expectedId) then
        return nil, "profile_id_mismatch"
    end
    return Custom.checkAmmo(profiles)
end

function Custom.checkAmmo(profiles)
    for _, profile in ipairs(profiles) do
        local general = profile.general or {}
        local mode = string.lower(tostring(general.ammoMode or "magazines"))
        if mode ~= "magazines" and mode ~= "rounds" then
            return nil, "invalid_ammo_mode:" .. tostring(profile.id)
        end
        for _, key in ipairs({ "primaryMagazines", "secondaryMagazines" }) do
            local value = tonumber(general[key])
            if value == nil or value < 0 or value ~= math.floor(value) then
                return nil, "invalid_" .. key .. ":" .. tostring(profile.id)
            end
        end
    end
    return profiles
end

function Custom.applySync(text, revision, persistCache)
    if Custom.batchLocked() then return false, "profile_write_busy" end
    local profiles, reason = Custom.validate(text, nil, true)
    if profiles == nil then return false, reason end
    Custom.profiles = profiles
    Custom.deleted = {}
    for _, profile in ipairs(profiles) do
        if profile.general.deleted == true then Custom.deleted[profile.id] = true end
    end
    Custom.revision = math.max(0, math.floor(tonumber(revision) or 0))
    Custom.loadMemo = nil
    Custom.serverManaged = true
    if persistCache == true then
        if not Custom.persist() or not Custom.persistDeleted() then
            print("[A-Life] NPC cache could not be saved; server data is active")
            return true, "profile_cache_write_failed"
        end
    end
    return true
end

Custom.loadMs = 5

function Custom.loadBegin()
    local Migration = ProjectALife.RecordMigration
    local state = { phase = "done", total = 0 }
    if Custom.batchLocked() then return state end
    if Custom.serverManaged then return state end
    if Migration.writeBusy[Custom.fileName] ~= nil then return state end
    state.previousDeleted = Custom.deleted
    Custom.loadDeleted()
    if type(getFileReader) ~= "function" then return state end
    local memo = Custom.loadMemo
    state.keep = { source = Custom.fileName, knownRaw = memo and memo.raw or nil,
        knownParsed = memo and memo.parsed or nil }
    state.reader = Migration.readSavedBegin(Custom.fileName, "member", state.keep)
    state.profiles, state.deleted, state.epoch = Custom.profiles, Custom.deleted, preparationEpoch
    state.phase = "read"
    return state
end

function Custom.loadFinish(state, ok, loaded)
    Custom.loadFailed = not (ok and loaded)
    if Custom.loadFailed then
        Custom.deleted = state.previousDeleted
        print("[A-Life] NPC template file unreadable; saving blocked to preserve it")
    end
    for _, profile in ipairs(Custom.profiles) do
        if profile.general.deleted == true then Custom.deleted[profile.id] = true end
    end
    state.reader, state.keep, state.records, state.built = nil, nil, nil, nil
    state.phase = "done"
    return true
end

function Custom.loadCurrent(state)
    return not Custom.serverManaged and state.profiles == Custom.profiles
        and state.deleted == Custom.deleted and state.epoch == preparationEpoch
        and ProjectALife.RecordMigration.writeBusy[Custom.fileName] == nil
end

function Custom.loadDiscard(state)
    local reader = state.reader
    if reader ~= nil and reader.backup ~= nil then reader = reader.backup end
    reader = reader ~= nil and reader.reader or nil
    if reader ~= nil and reader.reader ~= nil then pcall(function() reader.reader:close() end) end
    state.reader, state.keep, state.records, state.built = nil, nil, nil, nil
    state.phase = "done"
    return true
end

function Custom.loadApply(state)
    if not Custom.loadCurrent(state) then return Custom.loadDiscard(state) end
    Custom.profiles = state.built
    for _, profile in ipairs(Custom.profiles) do
        Custom.deleted[profile.id] = profile.general.deleted == true or nil
    end
    Custom.loadFailed = false
    if state.origin == "backup" then print("[A-Life] Recovered NPC templates from backup") end
    if state.origin == "primary" and state.keep.parsed ~= nil then
        Custom.loadMemo = { raw = state.raw, parsed = state.keep.parsed }
    else
        Custom.loadMemo = nil
    end
    return Custom.loadFinish(state, true, true)
end

function Custom.loadAdvance(state, budgetMs)
    local Migration = ProjectALife.RecordMigration
    if state.phase == "read" then
        local done, body, origin, raw = Migration.readSavedStep(state.reader, budgetMs)
        if not done then return false end
        state.total = state.reader.total or state.total
        if origin == "retired" then
            if not Migration.setAside(Custom.fileName, raw) then return Custom.loadFinish(state, true, false) end
            body = ""
        end
        if body == nil then
            return Custom.loadFinish(state, true, ProjectALife.RecordSalvage.restoreLocal(Custom, "member"))
        end
        state.origin, state.raw = origin, raw
        local parsed = state.keep.parsed
        if parsed == nil then
            state.built = Custom.parse(body)
            return Custom.loadApply(state)
        end
        state.records, state.built, state.index = parsed.records, {}, 1
        state.total = #state.records
        state.phase = "convert"
        if budgetMs ~= nil then return false end
    end
    local records, built = state.records, state.built
    local startedAt = budgetMs ~= nil and Migration.transactionClock() or nil
    while state.index <= #records do
        built[#built + 1] = Custom.fromRecord(records[state.index], false)
        state.index = state.index + 1
        if startedAt ~= nil then
            local now = Migration.transactionClock()
            if now == nil or now < startedAt or now - startedAt >= budgetMs then return false end
        end
    end
    return Custom.loadApply(state)
end

function Custom.loadStep(state, budgetMs)
    if state.phase == "done" then return true end
    if not Custom.loadCurrent(state) then return Custom.loadDiscard(state) end
    local ok, finished = pcall(Custom.loadAdvance, state, budgetMs)
    if not ok then return Custom.loadFinish(state, false, false) end
    return finished == true
end

function Custom.loadProgress(state)
    local reader = state.reader
    local total = tonumber(reader ~= nil and reader.total or state.total) or 0
    if state.phase == "done" then return total, total end
    if state.phase == "convert" then return math.min(total, math.floor((total + (state.index or 1) - 1) / 2)), total end
    local started = 0
    if reader ~= nil then
        started = reader.decoded or (reader.decoder ~= nil and #reader.decoder.records) or 0
    end
    return math.min(total, math.floor(started / 2)), total
end

function Custom.load()
    if Custom.primed == true then return Custom.profiles end
    local state = Custom.loadBegin()
    while not Custom.loadStep(state, nil) do end
    return Custom.profiles
end

function Custom.loadDeleted()
    if Custom.batchLocked() then return Custom.deleted end
    if type(getFileReader) ~= "function" then return Custom.deleted end
    local deleted = {}
    pcall(function()
        local reader = getFileReader(Custom.deletedFileName, true)
        if reader == nil then return end
        while true do
            local id = reader:readLine()
            if id == nil then break end
            id = string.match(tostring(id), "^%s*(.-)%s*$")

            if string.match(id, "^[%w_%-]+$") then deleted[id] = true end
        end
        reader:close()
    end)
    Custom.deleted = deleted
    return Custom.deleted
end

function Custom.persistDeleted()
    if Custom.batchLocked() then return false end
    if type(getFileWriter) ~= "function" then return false end
    local ids = {}
    for id in pairs(Custom.deleted) do ids[#ids + 1] = id end
    table.sort(ids)
    local ok, written = pcall(function()
        local name = Custom.serverManaged and "alife_server_deleted_profiles.ini" or Custom.deletedFileName
        local writer = getFileWriter(name, true, false)
        if writer == nil then return false end
        for _, id in ipairs(ids) do writer:write(id .. "\n") end
        writer:close()
        return true
    end)
    return ok and written == true
end

function Custom.isDeleted(id)
    return type(id) == "string" and Custom.deleted[id] == true
end

function Custom.restore(id)
    if Custom.batchLocked() then return false end
    if not Custom.isDeleted(id) then return true end
    Custom.deleted[id] = nil
    if Custom.persistDeleted() then preparationEpoch = preparationEpoch + 1; return true end
    Custom.deleted[id] = true
    return false
end

function Custom.persist()
    if Custom.batchLocked() then return false end
    if Custom.loadFailed and not Custom.serverManaged then return false end
    local name = Custom.serverManaged and "alife_server_profiles.ini" or Custom.fileName
    Custom.loadMemo = nil
    local ok, written = pcall(function()
        return ProjectALife.RecordMigration.persistSaved(name, Custom.serializeAll(), "member")
    end)
    return ok and written == true
end

function Custom.get(id)
    for _, profile in ipairs(Custom.profiles) do
        if profile.id == id and profile.general.deleted ~= true then return profile end
    end
    return nil
end

local function upsertLocal(profile)
    for index, existing in ipairs(Custom.profiles) do
        if existing.id == profile.id then
            Custom.profiles[index] = profile
            return true
        end
    end
    Custom.profiles[#Custom.profiles + 1] = profile
    return true
end

local function multiplayerClient()
    local ok, value = pcall(function()
        return type(isClient) == "function" and isClient()
    end)
    return ok and value == true
end

function Custom.save(profile)
    if Custom.batchLocked() then return false end
    if type(profile) ~= "table" or type(profile.id) ~= "string" then return false end
    if multiplayerClient() then
        local client = ProjectALife.CustomProfileClient
        if client == nil or type(client.upsert) ~= "function"
                or not client.upsert(profile) then return false end
        return upsertLocal(profile)
    end
    return Custom.saveMany({ profile })
end

function Custom.saveMany(profiles)
    if Custom.batchLocked() then return false, 0 end
    if type(profiles) ~= "table" then return false end
    for _, profile in ipairs(profiles) do
        if type(profile) ~= "table" or type(profile.id) ~= "string" then return false end
    end
    local remote = multiplayerClient()
    local previous, deleted = Custom.profiles, Custom.deleted
    Custom.profiles, Custom.deleted = copy(previous), copy(deleted)
    for index, profile in ipairs(profiles) do
        if remote then
            local client = ProjectALife.CustomProfileClient
            if client == nil or type(client.upsert) ~= "function"
                    or not client.upsert(profile) then
                Custom.profiles, Custom.deleted = previous, deleted
                if client and type(client.hello) == "function" then
                    client.awaitingEdit = true
                    client.hello(-1)
                end
                return false, index - 1
            end
        end
        Custom.deleted[profile.id] = nil
        upsertLocal(profile)
    end
    if remote or Custom.persist() then return true end
    Custom.profiles, Custom.deleted = previous, deleted
    return false, 0
end

function Custom.delete(id)
    if Custom.batchLocked() then return false end
    for index, existing in ipairs(Custom.profiles) do
        if existing.id == id then
            if multiplayerClient() then
                local client = ProjectALife.CustomProfileClient
                if client == nil or type(client.delete) ~= "function"
                        or not client.delete(id) then return false end
                table.remove(Custom.profiles, index)
                return true
            end
            table.remove(Custom.profiles, index)
            if Custom.persist() then preparationEpoch = preparationEpoch + 1; return true end
            table.insert(Custom.profiles, index, existing)
            return false
        end
    end
    return false
end

function Custom.remove(id)
    if Custom.batchLocked() then return false end
    if type(id) ~= "string" or id == "" then return false end
    if multiplayerClient() then
        local client = ProjectALife.CustomProfileClient
        if client == nil or type(client.delete) ~= "function" or not client.delete(id) then return false end
        upsertLocal(Custom.deletionRecord(id))
        Custom.deleted[id] = true
        return true
    end
    local previous, deleted = Custom.profiles, Custom.deleted
    Custom.profiles, Custom.deleted = {}, copy(deleted)
    for _, profile in ipairs(previous) do
        if profile.id ~= id then Custom.profiles[#Custom.profiles + 1] = profile end
    end
    Custom.deleted[id] = true
    if Custom.persist() then return true end
    Custom.profiles, Custom.deleted = previous, deleted
    return false
end

function Custom.catalogText()
    if not Custom.serverManaged then Custom.load() end
    return Custom.serializeAll()
end

return Custom
