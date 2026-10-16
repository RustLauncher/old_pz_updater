ProjectALife = ProjectALife or {}

ProjectALife.VoiceLootEventsRegister = function(Catalog)
    if type(Catalog) ~= "table" or Catalog.lootEventsLoaded then return end
    Catalog.lootEventsLoaded = true
    local Library = ProjectALife.ReactionLibrary
    local defaults = Library and Library.defaults and Library.defaults.scavenge or {}
    for _, id in ipairs({ "FOUND_TOOL", "FOUND_GEAR" }) do
        if Catalog.events[id] == nil then
            Catalog.events[id] = {
                category = "scavenge",
                priority = defaults.priority or 36,
                chance = defaults.chance or 38,
                cooldownMs = defaults.cooldownMs or 24000,
                groupCooldownMs = defaults.groupCooldownMs or 3200,
                actorLockMs = defaults.actorLockMs or 1200,
            }
        end
    end
    Catalog.styles.calm = Catalog.styles.calm or {}
    Catalog.styles.aggressive = Catalog.styles.aggressive or {}
    Catalog.styles.calm.FOUND_TOOL = {
        { text = "Got a {found} here.", when = { named = "yes" } },
        { text = "{found}. That's worth the weight.", when = { named = "yes" } },
        { text = "Found a tool." },
        { text = "There's a tool in this one." },
    }
    Catalog.styles.aggressive.FOUND_TOOL = {
        { text = "{found}! I'm keeping this.", when = { named = "yes" } },
        { text = "Look at this -- {found}.", when = { named = "yes" } },
        { text = "Found a tool. That'll do." },
        { text = "A tool. Better than my hands." },
    }
    Catalog.styles.calm.FOUND_GEAR = {
        { text = "Picked up a {found}.", when = { named = "yes" } },
        { text = "{found}. Taking it.", when = { named = "yes" } },
        { text = "Got something. Supplies." },
        { text = "Taking this. It'll keep." },
    }
    Catalog.styles.aggressive.FOUND_GEAR = {
        { text = "{found}. Mine now.", when = { named = "yes" } },
        { text = "Grabbing this {found}.", when = { named = "yes" } },
        { text = "Supplies. I'll take it." },
        { text = "Something useful. Finally." },
    }
end
