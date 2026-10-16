--[[
    Fletcher 0.7: zombies with bows and crossbows on their back.

    Vanilla gives a zombie an attached weapon this way (AttachedWeaponDefinitions, read by
    IsoZombie.addRandomAttachedWeapon): if its outfit has an attachedWeaponCustomOutfit entry and a
    roll passes that entry's chance, it picks from that entry's list; otherwise the global
    "Chance of attached weapon" (6 percent) picks from every definition naming the outfit.

    - Hunter (no vanilla entry): an entry of our own, chance = sandbox Fletcher.HunterZombieBows
      (10), a bow or crossbow on the back. The other hunters go on exactly as in vanilla.
    - Ranger (no vanilla entry): the same with primitive bows, at a third of that chance.
    - Survivalists (vanilla entries): a primitive bow joins their lists (one pick among several).
    If another mod already has an entry for the outfit, ours is added to its list instead.

    The bow goes on at vanilla's "Rifle On Back" (with a bag: "... with Bag"), and the client shows it
    with its back model (client/Fletcher/Bow.lua F.syncZombieBows). Killed, the zombie drops it with
    the rest of its gear. Arrows, bolts and the Hip Quiver are in the hunters' own loot
    (server/Fletcher/Distributions.lua F.ZOMBIE_LOOT).
]]

require "Definitions/AttachedWeaponDefinitions"
require "Fletcher/Core"
local F = Fletcher

AttachedWeaponDefinitions.fletcherHunterBow = {
    id = "fletcherHunterBow",
    chance = 20,
    outfit = { "Hunter" },
    weaponLocation = { "Rifle On Back" },
    bloodLocations = nil,
    addHoles = false,
    daySurvived = 0,
    weapons = {                     -- (picked at random: repeats weigh the common ones)
        "Fletcher.SimpleBow", "Fletcher.SimpleBow", "Fletcher.RecurveBow", "Fletcher.RecurveBow",
        "Fletcher.Longbow", "Fletcher.CompoundBow", "Fletcher.CompoundBow",
        "Fletcher.HandCrossbow", "Fletcher.LeverCrossbow", "Fletcher.CrankCrossbow",
    },
}

AttachedWeaponDefinitions.fletcherWoodsBow = {
    id = "fletcherWoodsBow",
    chance = 20,
    outfit = { "Ranger", "Survivalist", "Survivalist02", "Survivalist03", "Survivalist04", "Survivalist05",
               "Survivalist_Mid", "Survivalist_Late" },
    weaponLocation = { "Rifle On Back" },
    bloodLocations = nil,
    addHoles = false,
    daySurvived = 0,
    weapons = { "Fletcher.SimpleBow", "Fletcher.SimpleBow", "Fletcher.Longbow", "Fletcher.RecurveBow" },
}

F.ZOMBIE_BOW_OUTFITS = {
    -- outfit = { definition, share of the sandbox percent for an entry of our own }
    Hunter = { "fletcherHunterBow", 1 },
    Ranger = { "fletcherWoodsBow", 1 / 3 },
}
F.ZOMBIE_BOW_JOINS = { "Survivalist", "Survivalist_Mid", "Survivalist_Late" }   -- vanilla lists we join

function F.zombieBowPercent()
    local sv = SandboxVars and SandboxVars.Fletcher
    local v = sv and tonumber(sv.HunterZombieBows)
    return math.max(0, math.min(100, v or 10))
end

-- (by id: a rerun of this file makes new definition tables; the old copy in a list is swapped out)
local function place(list, def)
    for i = #list, 1, -1 do
        if type(list[i]) == "table" and list[i].id == def.id then table.remove(list, i) end
    end
    table.insert(list, def)
end

local function drop(list, def)
    for i = #list, 1, -1 do
        if type(list[i]) == "table" and list[i].id == def.id then table.remove(list, i) end
    end
end

--- Put our definitions into the per-outfit lists, with the sandbox's chance. Safe to call again.
function F.registerZombieBows()
    local custom = AttachedWeaponDefinitions.attachedWeaponCustomOutfit
    if not custom then return 0 end
    local pct = F.zombieBowPercent()
    local n = 0
    for outfit, spec in pairs(F.ZOMBIE_BOW_OUTFITS) do
        local def = AttachedWeaponDefinitions[spec[1]]
        local entry = custom[outfit]
        if not entry or entry.fletcherOwn then
            -- our own entry: its chance is the sandbox percent (0: never)
            custom[outfit] = { chance = math.floor(pct * spec[2] + 0.5), maxitem = 1, weapons = { def }, fletcherOwn = true }
        else
            place(entry.weapons, def)                   -- another mod's entry: one more pick in it
        end
        n = n + 1
    end
    for _, outfit in ipairs(F.ZOMBIE_BOW_JOINS) do
        local entry = custom[outfit]
        local def = AttachedWeaponDefinitions.fletcherWoodsBow
        if entry and entry.weapons then
            if pct > 0 then place(entry.weapons, def); n = n + 1 else drop(entry.weapons, def) end
        end
    end
    -- (each definition's own chance is its weight when a list is picked from, so it stays above 0;
    -- it also puts them in the global 6 percent pool for these outfits, a small extra)
    return n
end

-- The game copies these lists into Java (AttachedWeaponDefinitions.init) the first time it dresses a
-- zombie after any Lua file has run (LuaManager.RunLuaInternal marks the copy dirty), and keeps that
-- copy. OnInitGlobalModData comes after every Lua file has loaded (the sandbox is in by then: on a
-- client, the server's) and before the world dresses its first zombie, so the copy has the sandbox
-- percent. A change later in a session only takes effect after some Lua file runs again
-- (tests/_lib.lua T.zombieListsChanged); tests/mp_zombie_gear.lua checks a server whose sandbox is set.
F.registerZombieBows()
Events.OnInitGlobalModData.Add(function() F.registerZombieBows() end)

return F
