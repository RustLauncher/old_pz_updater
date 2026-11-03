ProjectALife = ProjectALife or {}
require "ProjectALife/Audio/ALifeReactionLibrary"

local Catalog = {
    aliases = {
        COUNTER_CONTACT = "CONTACT_HOSTILE",
        WOUNDED_STATE = "RETREAT",
        MEET_STOP = "WARNING_STOP",
        MEET_LOWER_WEAPON = "WARNING_LOWER_WEAPON",
        DEAD_FRIEND = "ALLY_DOWN",
        WEAPON_EMPTY = "OUT_OF_AMMO",
    },
    events = {
        CONTACT_PLAYER = { priority = 80, chance = 100, cooldownMs = 14000,
            groupCooldownMs = 3000, actorLockMs = 1900 },
        CONTACT_INFECTED = { priority = 75, chance = 100, cooldownMs = 12000,
            groupCooldownMs = 2600, actorLockMs = 1700 },
        CONTACT_HOSTILE = { priority = 80, chance = 100, cooldownMs = 14000,
            groupCooldownMs = 3000, actorLockMs = 1900 },
        HURT = { priority = 100, chance = 68, cooldownMs = 3200,
            groupCooldownMs = 0, actorLockMs = 900, interrupt = true },
        ALLY_DOWN = { priority = 95, chance = 72, cooldownMs = 10000,
            groupCooldownMs = 2600, actorLockMs = 1600, interrupt = true },
        RETREAT = { priority = 90, chance = 85, cooldownMs = 12000,
            groupCooldownMs = 2200, actorLockMs = 1600, interrupt = true },
        SURRENDER = { priority = 100, chance = 100, cooldownMs = 15000,
            groupCooldownMs = 2000, actorLockMs = 2200, interrupt = true },
        RELOAD = { priority = 50, chance = 28, cooldownMs = 18000,
            groupCooldownMs = 1800, actorLockMs = 1100 },
        OUT_OF_AMMO = { priority = 88, chance = 80, cooldownMs = 12000,
            groupCooldownMs = 2200, actorLockMs = 1500, interrupt = true },
        WEAPON_JAM = { priority = 92, chance = 82, cooldownMs = 9000,
            groupCooldownMs = 1800, actorLockMs = 1400, interrupt = true },
        BREACH = { priority = 60, chance = 46, cooldownMs = 14000,
            groupCooldownMs = 2400, actorLockMs = 1500 },
        KILL_CONFIRMED = { priority = 55, chance = 34, cooldownMs = 15000,
            groupCooldownMs = 2200, actorLockMs = 1300 },
        LOST_TARGET = { priority = 45, chance = 42, cooldownMs = 16000,
            groupCooldownMs = 2200, actorLockMs = 1300 },
        SEARCH_START = { priority = 40, chance = 36, cooldownMs = 18000,
            groupCooldownMs = 2200, actorLockMs = 1300 },
        ORDER_ACK = { priority = 65, chance = 100, cooldownMs = 2500,
            groupCooldownMs = 800, actorLockMs = 1000 },
        WARNING_STOP = { priority = 85, chance = 100, cooldownMs = 12000,
            groupCooldownMs = 2400, actorLockMs = 1900 },
        WARNING_LOWER_WEAPON = { priority = 85, chance = 100, cooldownMs = 12000,
            groupCooldownMs = 2400, actorLockMs = 1900 },
        IDLE = { priority = 10, chance = 8, cooldownMs = 60000,
            groupCooldownMs = 9000, actorLockMs = 1600 },

        PANIC = { priority = 95, chance = 60, cooldownMs = 20000,
            groupCooldownMs = 2000, actorLockMs = 1400, interrupt = true },
        STEADY = { priority = 90, chance = 100, cooldownMs = 30000,
            groupCooldownMs = 3000, actorLockMs = 1600 },
    },
    profiles = {
        calm_male = { label = "Calm Male", tone = "calm", female = false,
            shipEnabled = true, ambientEligible = true, captionOnly = true, lines = {} },
        calm_female = { label = "Calm Female", tone = "calm", female = true,
            shipEnabled = true, ambientEligible = true, captionOnly = true, lines = {} },
        aggressive_male = {
            label = "Aggressive Male", tone = "aggressive", female = false,
            shipEnabled = true, ambientEligible = true, captionOnly = true, lines = {},
        },
        aggressive_female = {
            label = "Aggressive Female", tone = "aggressive", female = true,
            shipEnabled = true, ambientEligible = true, captionOnly = true, lines = {},
        },
    },
    styles = {
        calm = {
            CONTACT_PLAYER = { "Person ahead.", "I've got someone in sight." },
            CONTACT_INFECTED = { "Infected, close.", "Dead ahead. Stay sharp." },
            CONTACT_HOSTILE = { "Hostile contact.", "Movement. Armed contact." },
            HURT = { "I'm hit!", "Taking fire!", "That got me!" },
            ALLY_DOWN = { "One of ours is down!", "We lost someone!" },
            RETREAT = { "Pulling back!", "I need distance!" },
            SURRENDER = { "I give up!", "Stop! I'm done!" },
            RELOAD = { "Reloading.", "Cover me, reloading." },
            OUT_OF_AMMO = { "I'm dry!", "No rounds left!" },
            WEAPON_JAM = { "Weapon jam!", "Stoppage!" },
            BREACH = { "Opening it up.", "Breaching now." },
            KILL_CONFIRMED = { "Target down.", "Threat is down." },
            LOST_TARGET = { "Lost sight of them.", "Contact disappeared." },
            SEARCH_START = { "Check the area.", "Spread out and look." },
            ORDER_ACK = { "Understood.", "On it.", "Copy that." },
            WARNING_STOP = { "Stop right there!", "Don't come any closer!" },
            WARNING_LOWER_WEAPON = { "Lower the weapon!", "Put the weapon down!" },
            IDLE = { "Keep watching.", "Quiet so far." },
            PANIC = { "Contact! Get down!", "Cover, now!", "They're on us -- move!" },
            STEADY = { "Steady. Hold the line.", "Easy. On me.", "Eyes up, hold it together." },
        },
        aggressive = {
            CONTACT_PLAYER = { "There! I see someone!", "Got a live one!" },
            CONTACT_INFECTED = { "Deadheads incoming!", "Infected! Drop them!" },
            CONTACT_HOSTILE = { "Hostiles! Take them!", "Enemy spotted!" },
            HURT = { "I'm hit!", "You bastard!", "They got me!" },
            ALLY_DOWN = { "They dropped one of us!", "Ours is down!" },
            RETREAT = { "Fall back!", "Move! Get back!" },
            SURRENDER = { "Enough! I surrender!", "Don't shoot! I'm done!" },
            RELOAD = { "Hold them off, reloading!", "Cover me while I load!" },
            OUT_OF_AMMO = { "I'm empty!", "Out of ammo!" },
            WEAPON_JAM = { "Damn it, jammed!", "Gun's jammed!" },
            BREACH = { "Break it open!", "Coming through!" },
            KILL_CONFIRMED = { "Dropped them.", "That's one down." },
            LOST_TARGET = { "Where'd they go?", "Find them!" },
            SEARCH_START = { "Hunt them down.", "Check every corner." },
            ORDER_ACK = { "Yeah, moving.", "Got it.", "Doing it." },
            WARNING_STOP = { "Stop or get shot!", "One more step and you're done!" },
            WARNING_LOWER_WEAPON = { "Drop the weapon!", "Weapon down, now!" },
            IDLE = { "Stay ready.", "Something's out there." },
            PANIC = { "Contact! Contact!", "Get down, get DOWN!", "Ambush! Scatter!" },
            STEADY = { "HOLD THE LINE!", "Steady! Nobody runs!", "On me! Form up!" },
        },
    },
}

local Library = ProjectALife.ReactionLibrary
for category, ids in pairs(Library.groups or {}) do
    local defaults = Library.defaults[category] or {}
    for _, id in ipairs(ids) do
        if Catalog.events[id] == nil then
            Catalog.events[id] = {
                category = category,
                priority = defaults.priority,
                chance = defaults.chance,
                cooldownMs = defaults.cooldownMs,
                groupCooldownMs = defaults.groupCooldownMs,
                actorLockMs = defaults.actorLockMs,
            }
        end
    end
end
for tone, lines in pairs(Library.styles or {}) do
    Catalog.styles[tone] = Catalog.styles[tone] or {}
    for event, entries in pairs(lines) do
        Catalog.styles[tone][event] = entries
    end
end
Catalog.ambientPools = Library.ambientPools
Catalog.actionContracts = Library.actionContracts
require "ProjectALife/Audio/ALifeVoiceExtraEvents"
if type(ProjectALife.VoiceExtraEventsRegister) == "function" then
    ProjectALife.VoiceExtraEventsRegister(Catalog)
end

local function eventId(value)
    if type(value) ~= "string" then return nil end
    local id = string.upper(value)
    return Catalog.aliases[id] or id
end

function Catalog.resolveEvent(value)
    local id = eventId(value)
    if id == nil or Catalog.events[id] == nil then return nil end
    return id
end

function Catalog.event(value)
    local id = Catalog.resolveEvent(value)
    return id and Catalog.events[id] or nil
end

function Catalog.eventIds(category)
    local result = {}
    for id, specification in pairs(Catalog.events) do
        if category == nil or specification.category == category then
            result[#result + 1] = id
        end
    end
    table.sort(result)
    return result
end

function Catalog.contract(action)
    return Catalog.actionContracts
        and Catalog.actionContracts[string.lower(tostring(action or ""))] or nil
end

function Catalog.shipProfileIds(female, ambientOnly)
    local result = {}
    for id, profile in pairs(Catalog.profiles) do
        local gender = tostring(profile.gender or (profile.female and "female" or "male"))
        local genderMatches = female == nil or gender == "mixed"
            or (female == true and profile.female == true)
            or (female == false and profile.female ~= true)
        if profile.shipEnabled ~= false and genderMatches
                and (ambientOnly ~= true or profile.ambientEligible == true) then
            result[#result + 1] = id
        end
    end
    table.sort(result)
    return result
end

local function randomProfile(female)
    local ids = Catalog.shipProfileIds(female, false)
    local automatic = {}
    for _,id in ipairs(ids) do
        if Catalog.profiles[id].manualOnly ~= true then automatic[#automatic+1]=id end
    end
    ids = automatic
    if #ids == 0 then return nil end
    local index = type(ZombRand) == "function" and ZombRand(#ids) + 1
        or math.random(#ids)
    return ids[index]
end

function Catalog.resolveProfile(value, female)
    local id = type(value) == "string" and string.lower(value) or ""
    if id == "*" or id == "random" then
        return randomProfile(female) or (female == true and "calm_female" or "calm_male")
    end
    local profile = Catalog.profiles[id]
    if profile ~= nil and profile.shipEnabled ~= false then return id end
    return female == true and "calm_female" or "calm_male"
end

local function append(result, entries)
    if type(entries) ~= "table" then return end
    for _, entry in ipairs(entries) do
        if type(entry) == "string" then
            result[#result + 1] = { text = entry, weight = 1 }
        elseif type(entry) == "table" then
            result[#result + 1] = entry
        end
    end
end

Catalog.rejectedClips = {
    PALV_404_MEET_HELLO_01 = true, PALV_404_SUPPORT_04 = true, PALV_404_MEET_STOP_01 = true,
    PALV_405_MEET_HELLO_01 = true, PALV_405_SUPPORT_04 = true, PALV_405_MEET_STOP_01 = true,
    PALV_406_MEET_HELLO_01 = true, PALV_406_SUPPORT_04 = true, PALV_406_MEET_STOP_01 = true,
    PALV_407_MEET_HELLO_01 = true, PALV_407_MEET_HELLO_02 = true, PALV_407_SUPPORT_04 = true,
    PALV_408_MEET_HELLO_01 = true, PALV_408_SUPPORT_04 = true,
    PALV_409_MEET_HELLO_01 = true, PALV_409_MEET_HELLO_02 = true, PALV_409_SUPPORT_04 = true,
    PALV_413_SUPPORT_04 = true, PALV_414_SUPPORT_04 = true, PALV_415_SUPPORT_04 = true,
    PALV_419_SUPPORT_03 = true, PALV_420_SUPPORT_03 = true, PALV_421_SUPPORT_03 = true,
    PALV_422_PANIC_ZOMBIE_02 = true, PALV_422_LOOT_START_02 = true,
    PALV_423_BANTER_JOKE_01 = true, PALV_423_BANTER_JOKE_03 = true,
    PALV_424_PANIC_ZOMBIE_01 = true, PALV_424_BANTER_JOKE_01 = true,
    PALV_424_BANTER_JOKE_02 = true, PALV_424_BANTER_JOKE_03 = true,
    PALV_425_ALLY_DOWN_03 = true, PALV_425_BANTER_INTRO_02 = true,
    PALV_426_ALLY_DOWN_03 = true, PALV_426_PANIC_ZOMBIE_02 = true,
    PALV_427_PANIC_ZOMBIE_02 = true, PALV_427_BANTER_JOKE_03 = true,
    PALV_428_PANIC_ZOMBIE_01 = true, PALV_428_PANIC_ZOMBIE_02 = true,
    PALV_428_BANTER_JOKE_01 = true, PALV_428_BANTER_JOKE_02 = true,
    PALV_429_ALLY_DOWN_02 = true, PALV_429_PANIC_ZOMBIE_01 = true,
    PALV_429_PANIC_ZOMBIE_02 = true, PALV_429_BANTER_JOKE_01 = true, PALV_429_BANTER_JOKE_02 = true,
    PALV_427_FRIENDLY_FIRE_01 = true, PALV_428_POST_COMBAT_HOLD_02 = true,
    PALV_428_ENEMY_DOWN_02 = true, PALV_428_ORDER_FIRE_01 = true,
}

function Catalog.clipAllowed(sound)
    if type(sound) == "string" and string.sub(sound, 1, 6) == "PALUI_" then
        sound = string.sub(sound, 7)
    end
    return Catalog.rejectedClips[sound or ""] ~= true
end

function Catalog.previewClips(sounds)
    local result = {}
    if type(sounds) ~= "table" then return result end
    for _, sound in ipairs(sounds) do
        if Catalog.clipAllowed(sound) then result[#result + 1] = sound end
    end
    for event, value in pairs(sounds) do
        if type(event) == "string" then
            if type(value) == "table" then
                local clips = Catalog.previewClips(value)
                if #clips > 0 then result[event] = clips end
            elseif type(value) == "string" and Catalog.clipAllowed(value) then
                result[event] = value
            end
        end
    end
    return result
end

function Catalog.entries(profileId, value)
    local requested = type(profileId) == "string" and string.lower(profileId) or ""
    local id = Catalog.profiles[requested] and requested
        or Catalog.resolveProfile(profileId, false)
    local event = Catalog.resolveEvent(value)
    local profile = Catalog.profiles[id]
    if event == nil or profile == nil then return {} end
    local result = {}
    local authored = profile.lines and profile.lines[event]
    if type(authored) == "table" and #authored > 0 then
        append(result, authored)
    else
        append(result, Catalog.styles[profile.tone] and Catalog.styles[profile.tone][event])
    end
    local allowed = {}
    for _, entry in ipairs(result) do
        if Catalog.clipAllowed(entry.sound) then allowed[#allowed + 1] = entry end
    end
    return allowed
end

function Catalog.profileIds()
    local result = {}
    for id in pairs(Catalog.profiles) do result[#result + 1] = id end
    table.sort(result)
    return result
end

function Catalog.registerProfile(id, specification)
    if type(id) ~= "string" or id == "" or type(specification) ~= "table" then
        return false, "voice_profile_invalid"
    end
    id = string.lower(id)
    Catalog.profiles[id] = {
        label = tostring(specification.label or id),
        tone = Catalog.styles[specification.tone] and specification.tone or "calm",
        female = specification.female == true,
        gender = tostring(specification.gender
            or (specification.female == true and "female" or "male")),
        sourcePack = type(specification.sourcePack) == "string"
            and specification.sourcePack or nil,
        sourceTone = type(specification.sourceTone) == "string"
            and specification.sourceTone or nil,
        readyClips = tonumber(specification.readyClips) or 0,
        coveredEvents = tonumber(specification.coveredEvents) or 0,
        shipEnabled = specification.shipEnabled ~= false,
        ambientEligible = specification.ambientEligible == true,
        qualityOverride = specification.qualityOverride == true,
        captionOnly = specification.captionOnly == true,
        manualOnly = specification.manualOnly == true,
        shipReason = type(specification.shipReason) == "string"
            and specification.shipReason or nil,
        usableContact = tonumber(specification.usableContact) or 0,
        usableCombat = tonumber(specification.usableCombat) or 0,
        usableAmbient = tonumber(specification.usableAmbient) or 0,
        usableTotal = tonumber(specification.usableTotal) or 0,
        usableCounts = type(specification.usableCounts) == "table"
            and specification.usableCounts or {},
        qualityRejected = type(specification.qualityRejected) == "table"
            and specification.qualityRejected or {},
        sampleSound = type(specification.sampleSound) == "string" and Catalog.clipAllowed(specification.sampleSound)
            and specification.sampleSound or nil,
        sampleSounds = Catalog.previewClips(specification.sampleSounds),
        previewSounds = Catalog.previewClips(specification.previewSounds),
        lines = type(specification.lines) == "table" and specification.lines or {},
    }
    return true, id
end

function Catalog.registerEntry(profileId, value, entry)
    local event = Catalog.resolveEvent(value)
    local profile = Catalog.profiles[string.lower(tostring(profileId or ""))]
    if event == nil or profile == nil
            or (type(entry) ~= "string" and type(entry) ~= "table") then
        return false, "voice_entry_invalid"
    end
    profile.lines[event] = profile.lines[event] or {}
    profile.lines[event][#profile.lines[event] + 1] = entry
    return true
end

ProjectALife.VoiceCatalog = Catalog
require "ProjectALife/Audio/ALifeVoiceWorkbenchProfiles"
if type(ProjectALife.VoiceWorkbenchRegister) == "function" then
    ProjectALife.VoiceWorkbenchRegister(Catalog)
end
require "ProjectALife/Audio/ALifeVoiceProjectProfiles"
if type(ProjectALife.VoiceProjectRegister) == "function" then
    ProjectALife.VoiceProjectRegister(Catalog)
end
require "ProjectALife/Audio/ALifeVoiceLegacyProfiles"
ProjectALife.VoiceLegacyRegister(Catalog)
require "ProjectALife/Audio/ALifeVoiceDialogue"
ProjectALife.VoiceDialogueRegister(Catalog)
require "ProjectALife/Audio/ALifeGossip"
return Catalog
