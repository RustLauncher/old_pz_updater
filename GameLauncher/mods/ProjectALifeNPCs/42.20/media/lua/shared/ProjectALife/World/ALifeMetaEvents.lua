ProjectALife = ProjectALife or {}

local MetaEvents = {
    settings = {
        enabled = true,
        earlyDays = 14,
        earlyPerDayMax = 2,
        gunfireWeight = 50,
        heliWeight = 25,
        crashWeight = 25,

        ambienceWeight = 45,

        customFireShare = 0.4,
        militaryStartDay = 30,
        militaryPerWeek = 1.3,

        laterPerDayMax = 1.3,

        militaryShare = 0.5,
        minGapMinutes = 120,
        offsetMinimum = 180,
        offsetMaximum = 420,
    },
    sounds = {
        gunfire = {
            "MetaPistol1", "MetaPistol2", "MetaPistol3",
            "MetaShotgun1", "MetaAssaultRifle1",
        },
        distantFire = { "PALWorldShootout", "PALWorldShootout2", "PALWorldHunterRifle" },
        heli = "Helicopter",
        flavor = { "MetaDogBark", "MetaScream" },

        heliPass = { "PALWorldHeliPass1", "PALWorldHeliPass2",
            "PALWorldHeliPass3", "PALWorldHeliPass4" },
        crash = { "PALWorldCarCrash1", "PALWorldCarCrash2", "PALWorldCarCrash3" },

        crashAftermath = "PALWorldCarAlarm",

        untilDay = {
            PALWorldSirensServices = 1,
            PALWorldPoliceSiren = 1,
            PALWorldArtillery1 = 12,
            PALWorldArtillery2 = 12,
            PALWorldArtillery3 = 12,
            PALWorldWarExplosions = 12,
            PALWorldJetOverhead = 12,
        },
        sessionAlarm = "PALWorldSessionAlarm",
        radioBackup = "PALWorldRadioBackup",
        radioOff = "PALWorldRadioOff",
        roundWhizz = "PALWorldRoundWhizz",

        ambience = {
            "PALWorldPoliceSiren", "PALWorldShootout", "PALWorldScream",
            "PALWorldDistress1", "PALWorldDistress2",
            "PALWorldEerie1", "PALWorldEerie2", "PALWorldEerie3", "PALWorldEerie4",

            "PALWorldEerie5", "PALWorldEerie6", "PALWorldShootout2",
            "PALWorldHunterRifle", "PALWorldTortured",
            "PALWorldSirensServices", "PALWorldArtillery1", "PALWorldArtillery2",
            "PALWorldArtillery3", "PALWorldWarExplosions", "PALWorldJetOverhead",
            "PALWorldCarAlarm", "PALWorldCarAlarm2", "PALWorldCarPullup2",
        },
    },
    whitelist = {
        MetaPistol1 = true,
        MetaPistol2 = true,
        MetaPistol3 = true,
        MetaShotgun1 = true,
        MetaAssaultRifle1 = true,
        Helicopter = true,
        MetaDogBark = true,
        MetaScream = true,
        PALWorldSessionAlarm = true,
        PALWorldCarCrash1 = true,
        PALWorldCarCrash2 = true,
        PALWorldCarCrash3 = true,
        PALWorldCarAlarm = true,
        PALWorldHeliPass1 = true,
        PALWorldHeliPass2 = true,
        PALWorldPoliceSiren = true,
        PALWorldShootout = true,
        PALWorldDistress1 = true,
        PALWorldDistress2 = true,
        PALWorldEerie1 = true,
        PALWorldEerie2 = true,
        PALWorldEerie3 = true,
        PALWorldEerie4 = true,
        PALWorldScream = true,
        PALWorldBroadcast = true,
        PALWorldRadioBackup = true,
        PALWorldRadioOff = true,
        PALWorldRoundWhizz = true,

        PALWorldAirRaidSiren = true,
        PALWorldArtillery1 = true,
        PALWorldArtillery2 = true,
        PALWorldArtillery3 = true,
        PALWorldWarExplosions = true,
        PALWorldJetOverhead = true,
        PALWorldSirensServices = true,
        PALWorldHeliPass3 = true,
        PALWorldHeliPass4 = true,
        PALWorldCarPullup2 = true,
        PALWorldCarAlarm2 = true,
        PALWorldShootout2 = true,
        PALWorldHunterRifle = true,
        PALWorldTortured = true,
        PALWorldEerie5 = true,
        PALWorldEerie6 = true,
    },
}

ProjectALife.MetaEvents = MetaEvents

function MetaEvents.soundAllowed(name)
    return MetaEvents.whitelist[tostring(name or "")] == true
end

MetaEvents.raidSounds = { PALWorldAirRaidSiren = true, PALWorldSessionAlarm = true, PALWorldJetOverhead = true }

function MetaEvents.sirenAircraftAllowed()
    local settings = ProjectALife.Settings
    local current = settings ~= nil and settings.current or nil
    if type(current) == "table" and current.raidSirenAircraft ~= nil then return current.raidSirenAircraft == true end
    local options = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    return type(options) == "table" and options.Raid_SirenAircraftSounds ~= false
end

function MetaEvents.raidSoundAllowed(name)
    if MetaEvents.raidSounds[tostring(name or "")] ~= true then return true end
    return MetaEvents.sirenAircraftAllowed()
end

function MetaEvents.soundAllowedOnDay(name, day)
    local limit = MetaEvents.sounds.untilDay and MetaEvents.sounds.untilDay[tostring(name or "")]
    if limit == nil then return true end
    return (tonumber(day) or 0) <= limit
end

function MetaEvents.kindForRoll(value)
    local settings = MetaEvents.settings
    local gunfire = math.max(0, tonumber(settings.gunfireWeight) or 0)
    local heli = math.max(0, tonumber(settings.heliWeight) or 0)
    local crash = math.max(0, tonumber(settings.crashWeight) or 0)
    local ambience = math.max(0, tonumber(settings.ambienceWeight) or 0)
    local total = gunfire + heli + crash + ambience
    if total <= 0 then return nil end
    local picked = math.max(0, math.min(total - 0.000001,
        (tonumber(value) or 0) * total))
    if picked < gunfire then return "gunfire" end
    if picked < gunfire + heli then return "heli" end
    if picked < gunfire + heli + crash then return "crash" end
    return "ambience"
end

MetaEvents.crashWeights = {
    PALWorldCarCrash1 = 25,
    PALWorldCarCrash2 = 25,
    PALWorldCarCrash3 = 50,
}

function MetaEvents.crashForRoll(roll)
    local bank = MetaEvents.sounds.crash
    if type(bank) ~= "table" or #bank == 0 then return nil end
    local total = 0
    for _, name in ipairs(bank) do
        total = total + (tonumber(MetaEvents.crashWeights[name]) or 1)
    end
    local picked = math.max(0, math.min(0.999999, tonumber(roll) or 0)) * total
    local seen = 0
    for _, name in ipairs(bank) do
        seen = seen + (tonumber(MetaEvents.crashWeights[name]) or 1)
        if picked < seen then return name end
    end
    return bank[#bank]
end

MetaEvents.ambienceWeights = {
    PALWorldPoliceSiren = 24,
    PALWorldSirensServices = 8,
    PALWorldScream = 19,
    PALWorldDistress1 = 8,
    PALWorldDistress2 = 8,
    PALWorldTortured = 3,
    PALWorldShootout = 10,
    PALWorldShootout2 = 8,
    PALWorldHunterRifle = 6,
    PALWorldArtillery1 = 6,
    PALWorldArtillery2 = 6,
    PALWorldArtillery3 = 6,
    PALWorldWarExplosions = 5,
    PALWorldJetOverhead = 4,
    PALWorldEerie1 = 3,
    PALWorldEerie2 = 3,
    PALWorldEerie3 = 3,
    PALWorldEerie4 = 3,
    PALWorldEerie5 = 3,
    PALWorldEerie6 = 3,
    PALWorldCarAlarm = 4,
    PALWorldCarAlarm2 = 3,
    PALWorldCarPullup2 = 6,
}

MetaEvents.sirenLastDay = 3

function MetaEvents.ambienceWeightFor(name, day)
    local weight = tonumber(MetaEvents.ambienceWeights[name]) or 1
    if not MetaEvents.raidSoundAllowed(name) then return 0 end
    if name == "PALWorldPoliceSiren" and day ~= nil
            and day > (tonumber(MetaEvents.sirenLastDay) or 3) then
        return 0
    end

    if day ~= nil and not MetaEvents.soundAllowedOnDay(name, day) then return 0 end
    return weight
end

function MetaEvents.ambienceForRoll(value, day)
    local bank = MetaEvents.sounds.ambience
    if type(bank) ~= "table" or #bank == 0 then return nil end
    local total = 0
    for _, name in ipairs(bank) do
        total = total + MetaEvents.ambienceWeightFor(name, day)
    end
    if total <= 0 then return nil end
    local picked = math.max(0, math.min(total - 0.000001,
        (tonumber(value) or 0) * total))
    local seen = 0
    local last
    for _, name in ipairs(bank) do
        local weight = MetaEvents.ambienceWeightFor(name, day)
        if weight > 0 then
            last = name
            seen = seen + weight
            if picked < seen then return name end
        end
    end
    return last
end

MetaEvents.opening = {
    enabled = true,
    artillery = { "PALWorldArtillery1", "PALWorldArtillery2",
        "PALWorldArtillery3", "PALWorldWarExplosions" },
    jet = "PALWorldJetOverhead",
    artilleryAtMinutes = 1,
    artilleryRepeatMinutes = 3,
    artilleryVolleys = 3,
    jetAtMinutes = 10,
    heliAtMinutes = 15,

    untilHours = 168,
    minGapMinutes = 1,

    graceMinutes = 3,

    artilleryDistanceMinimum = 90,
    artilleryDistanceMaximum = 180,
    flybyDistanceMinimum = 25,
    flybyDistanceMaximum = 70,
    volume = 1,
}

function MetaEvents.openingCues()
    local opening = MetaEvents.opening
    local cues = {}
    local bank = opening.artillery
    if type(bank) == "table" and #bank > 0 then
        local first = tonumber(opening.artilleryAtMinutes) or 0
        local gap = tonumber(opening.artilleryRepeatMinutes) or 0
        for step = 1, math.floor(tonumber(opening.artilleryVolleys) or 0) do
            cues[#cues + 1] = {
                slot = "artillery" .. tostring(step),
                minutes = first + (step - 1) * gap,
                name = bank[1 + (step - 1) % #bank],
                near = tonumber(opening.artilleryDistanceMinimum) or 90,
                far = tonumber(opening.artilleryDistanceMaximum) or 180,
            }
        end
    end
    local near = tonumber(opening.flybyDistanceMinimum) or 25
    local far = tonumber(opening.flybyDistanceMaximum) or 70
    if type(opening.jet) == "string" then
        cues[#cues + 1] = { slot = "jet", name = opening.jet,
            minutes = tonumber(opening.jetAtMinutes) or 10, near = near, far = far }
    end

    local passes = MetaEvents.sounds.heliPass
    if type(passes) == "table" and passes[1] ~= nil then
        cues[#cues + 1] = { slot = "heli", name = passes[1], heli = true,
            minutes = tonumber(opening.heliAtMinutes) or 15, near = near, far = far }
    end
    return cues
end

return MetaEvents
