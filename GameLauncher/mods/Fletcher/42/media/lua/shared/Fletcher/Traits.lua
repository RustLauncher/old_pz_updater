--[[
    Fletcher 0.7: Archery from character creation.

    - The Archer trait (fletcher:archer: media/registries.lua + scripts/Fletcher/Fletcher_Traits.txt):
      +2 Archery, +1 Carving. Its boosts come from the script, read by the game itself.
    - Vanilla's Hunter trait (F.TRAIT_BOOSTS) and Park Ranger profession (F.PROFESSION_BOOSTS) also
      start with Archery: added to their definitions when this file loads, so creation shows
      "+1 Archery" and applies it like any vanilla boost (starting level + faster XP).

    The definitions' boost maps are HashMap<Perk, Integer> and the game casts every value to Integer
    (SurvivorDesc, XP.AddXP, IsoGameCharacter.modifyTraitXPBoost). A Lua number put in with map:put
    is a Double and crashes character creation (FieldRations 1.0.0 on the Steam Deck), so boosts go
    in through def:addXPBoost(perk, n), which takes a Java int. tests/traits.lua checks the types.

    New characters only. OnNewGame raises a new character's Archery to what its trait / profession
    should give if creation didn't (never lowers).
]]

require "Fletcher/Core"
local F = Fletcher

F.ARCHER_TRAIT = "fletcher:archer"
F.TRAIT_BOOSTS = { hunter = 1 }              -- vanilla trait short name -> Archery levels
F.PROFESSION_BOOSTS = { parkranger = 1 }     -- vanilla profession short name -> Archery levels

--- "base:hunter" -> "hunter"
local function shortName(t)
    local s = tostring(t or "")
    return string.match(s, ":(.+)$") or s
end

local function archery()
    return Perks and Perks.Archery          -- (never Aiming: these boosts are Archery's alone)
end

--- vanilla writes "+N Skill" lines into the creation descriptions once at boot (OnGameBoot);
--- boosts added after that need their line added here (once)
local function addLine(def, perk, level)
    local line = "+" .. level .. " " .. PerkFactory.getPerkName(perk)
    local desc = def:getDescription() or ""
    if not string.find(desc, line, 1, true) then
        def:setDescription(desc == "" and line or (desc .. "\n" .. line))
    end
end

local function boost(def, table_, perk)
    local level = table_[shortName(def:getType())]
    if not level then return false end
    local had = def:getXpBoosts():get(perk)
    if not (had and had:intValue() >= level) then def:addXPBoost(perk, level) end
    if F.creationTextDone then addLine(def, perk, level) end
    return true
end

--- Add the Archery boosts to vanilla's trait and profession definitions. Safe to call again.
--- Returns how many definitions carry one.
function F.registerArcheryBoosts()
    local perk = archery()
    if not perk then return 0 end
    local n = 0
    if CharacterTraitDefinition then
        local list = CharacterTraitDefinition.getTraits()
        for i = 0, list:size() - 1 do
            if boost(list:get(i), F.TRAIT_BOOSTS, perk) then n = n + 1 end
        end
    end
    if CharacterProfessionDefinition then
        local list = CharacterProfessionDefinition.getProfessions()
        for i = 0, list:size() - 1 do
            if boost(list:get(i), F.PROFESSION_BOOSTS, perk) then n = n + 1 end
        end
    end
    return n
end

--- The Archer trait's definition (nil if it didn't load)
function F.archerTrait()
    local ok, t = pcall(function() return CharacterTrait.get(ResourceLocation.of(F.ARCHER_TRAIT)) end)
    return ok and t or nil
end

--- The Archery a character's traits and profession should give at creation (vanilla adds them up).
function F.creationArchery(character)
    local perk = archery()
    if not (perk and character) then return 0 end
    local total = 0
    local traits = CharacterTraitDefinition and CharacterTraitDefinition.getTraits()
    for i = 0, (traits and traits:size() or 0) - 1 do
        local def = traits:get(i)
        if character:hasTrait(def:getType()) then
            local b = def:getXpBoosts():get(perk)
            if b then total = total + b:intValue() end
        end
    end
    local prof = character:getDescriptor() and character:getDescriptor():getCharacterProfession()
    local pdef = prof and CharacterProfessionDefinition.getCharacterProfessionDefinition(prof)
    local b = pdef and pdef:getXpBoosts():get(perk)
    if b then total = total + b:intValue() end
    return math.min(10, total)
end

--- Give a new character the Archery its creation should have if it didn't (never lowers).
function F.applyCreationArchery(character)
    local perk = archery()
    local want = F.creationArchery(character)
    if not perk or want <= 0 then return false end
    local xp = character:getXp()
    local changed = false
    local rate = math.min(3, want)
    if xp:getPerkBoost(perk) < rate then
        xp:setPerkBoost(perk, rate)
        changed = true
    end
    if character:getPerkLevel(perk) < want then
        character:setPerkLevelDebug(perk, want)
        xp:setXPToLevel(perk, want)
        changed = true
    end
    return changed
end

F.registerArcheryBoosts()
Events.OnGameBoot.Add(function()
    -- (after vanilla's DoTraits / DoProfessions: those wrote the lines for boosts already in place)
    F.creationTextDone = true
    F.registerArcheryBoosts()
end)
Events.OnNewGame.Add(function(player)
    if player then F.applyCreationArchery(player) end
end)

return F
