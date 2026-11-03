ProjectALife = ProjectALife or {}
require "ProjectALife/Audio/ALifeFactionVoiceStyles"
require "ProjectALife/Audio/ALifeVoiceLootEvents"

ProjectALife.VoiceExtraEventsRegister = function(Catalog)
    if type(Catalog) ~= "table" or Catalog.extraEventsLoaded then return end
    Catalog.extraEventsLoaded = true
    local Library = ProjectALife.ReactionLibrary
    local defaults = Library and Library.defaults and Library.defaults.tactics or {}
    for _, id in ipairs({ "SUPPRESS_FIRE", "SUPPORT_CALL", "ALLY_HIT", "HIT_CONFIRMED",
            "BANTER_INTRO", "BANTER_REACTION" }) do
        if Catalog.events[id] == nil then
            Catalog.events[id] = {
                category = "tactics",
                priority = defaults.priority or 63,
                chance = defaults.chance or 55,
                cooldownMs = defaults.cooldownMs or 18000,
                groupCooldownMs = defaults.groupCooldownMs or 2600,
                actorLockMs = defaults.actorLockMs or 1400,
            }
        end
    end
    Catalog.styles.calm = Catalog.styles.calm or {}
    Catalog.styles.aggressive = Catalog.styles.aggressive or {}
    Catalog.styles.calm.SUPPRESS_FIRE = { "Suppressing. Keep your heads down.", "I'll keep them pinned." }
    Catalog.styles.aggressive.SUPPRESS_FIRE = { "Stay down! Eat this!", "Pinning them -- move up!" }
    Catalog.styles.calm.SUPPORT_CALL = { "Calling it in. Hold on.", "Radio's up. Help is coming." }
    Catalog.styles.aggressive.SUPPORT_CALL = { "Get me backup, now!", "Calling the cavalry!" }
    Catalog.styles.calm.ALLY_HIT = { "You're hit! Get behind cover!", "Keep pressure on that wound!" }
    Catalog.styles.aggressive.ALLY_HIT = Catalog.styles.calm.ALLY_HIT
    Catalog.styles.calm.HIT_CONFIRMED = { "Hit! They're still moving.", "They're wounded!" }
    Catalog.styles.aggressive.HIT_CONFIRMED = Catalog.styles.calm.HIT_CONFIRMED
    Catalog.styles.calm.BANTER_INTRO = { "Anyone still awake over there?" }
    Catalog.styles.aggressive.BANTER_INTRO = Catalog.styles.calm.BANTER_INTRO
    Catalog.styles.calm.BANTER_REACTION = { "Yeah. I'm listening." }
    Catalog.styles.aggressive.BANTER_REACTION = Catalog.styles.calm.BANTER_REACTION

    Catalog.events.GUN_FEAR = {
        category = "tactics", priority = 88, chance = 100,
        cooldownMs = 9000, groupCooldownMs = 1200,
        actorLockMs = defaults.actorLockMs or 1400, interrupt = true,
    }
    Catalog.styles.calm.GUN_FEAR = { "Easy -- easy! I'm backing off.", "Not worth it. I'm gone." }
    Catalog.styles.aggressive.GUN_FEAR = { "He's got a gun -- move!", "Back off! He's got the drop!" }
    local ambient = Library and Library.defaults and Library.defaults.ambient or {}
    for _, id in ipairs({ "BANTER_INTRO", "BANTER_REACTION" }) do
        local event = Catalog.events[id]
        event.category = "ambient"
        event.priority = ambient.priority or 12
        event.cooldownMs = ambient.cooldownMs or 45000
        event.groupCooldownMs = ambient.groupCooldownMs or 8500
    end
    Catalog.events.CAMP_CHATTER = {
        category = "ambient", priority = ambient.priority or 12,
        chance = ambient.chance or 26, cooldownMs = ambient.cooldownMs or 45000,
        groupCooldownMs = ambient.groupCooldownMs or 8500,
        actorLockMs = ambient.actorLockMs or 1500,
    }
    Catalog.styles.calm.CAMP_CHATTER = { "Keep the fire low. Light travels farther than courage." }
    Catalog.styles.aggressive.CAMP_CHATTER = Catalog.styles.calm.CAMP_CHATTER
    for _, state in ipairs({ "idle", "indoors" }) do
        local pool = Catalog.ambientPools and Catalog.ambientPools[state]
        if type(pool) == "table" then pool[#pool + 1] = "CAMP_CHATTER" end
    end

    function Catalog.captionFor(profileId, event, entry)
        local text = entry and entry.text
        if type(text) == "string" and text ~= "" then return text end
        if entry and entry.sound then

            return "[" .. tostring(event or "voice"):gsub("_", " "):lower() .. "]"
        end
        local profile = Catalog.profiles and Catalog.profiles[profileId]
        local tone = profile and profile.tone or "calm"
        local choices = Catalog.styles[tone] and Catalog.styles[tone][event]
            or Catalog.styles.calm and Catalog.styles.calm[event]
        local fallback = type(choices) == "table" and choices[1]
        if type(fallback) == "table" then fallback = fallback.text end
        return fallback or ("[" .. tostring(event or "voice"):gsub("_", " "):lower() .. "]")
    end

    if type(ProjectALife.VoiceLootEventsRegister) == "function" then
        ProjectALife.VoiceLootEventsRegister(Catalog)
    end
    if type(ProjectALife.FactionVoiceRegister) == "function" then
        ProjectALife.FactionVoiceRegister(Catalog)
    end
end
