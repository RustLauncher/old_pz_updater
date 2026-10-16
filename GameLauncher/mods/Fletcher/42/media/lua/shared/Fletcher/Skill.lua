--[[
    Fletcher: the Archery skill (media/perks.txt, parent Firearm).

    For bows Archery replaces Aiming: the bows' AimingPerk* modifiers are 0 in their scripts, and
    the bow in hand gets its stats from its own base + the holder's Archery level + the nocked
    arrow (F.shotStats / F.applyBowSkill in Gear.lua; F.SKILL below gives the Simple Bow's base and
    the per-level steps every bow shares). XP: F.XP per shot / hit / kill (client/Fletcher/Arrows.lua). Crafting XP comes
    from the recipes' xpAward.
]]

require "Fletcher/Core"
local F = Fletcher

-- level 0 -> 10
F.SKILL = {
    hitChance = { 35, 4 },        -- base, per level (percent)
    critChance = { 10, 2 },
    aimingTime = { 50, -3 },      -- draw time (vanilla: lower is quicker on target)
    reloadTime = { 35, -1.5 },    -- nocking time
    breakChance = { 30, -1.5 },   -- percent of shot arrows that break (x the arrow type; F.BREAK_FLOOR)
}
F.XP = { shot = 1, hit = 2, kill = 4 }   -- (a shot's XP only counts when it hits: F.shotXp)
F.BREAK_FLOOR = 8                        -- percent: arrows always wear out eventually

--- The Archery perk (falls back to Aiming if perks.txt didn't load, so nothing errors).
function F.perk()
    return Perks.Archery or Perks.Aiming
end

function F.level(character)
    return character and character:getPerkLevel(F.perk()) or 0
end

function F.stat(name, level)
    local s = F.SKILL[name]
    return s[1] + s[2] * math.max(0, math.min(10, level or 0))
end

--- Every skill-driven stat of the Simple Bow (no arrow modifiers) at a level.
function F.bowStats(level)
    local out = {}
    for name in pairs(F.SKILL) do out[name] = F.stat(name, level) end
    return out
end

--- Award Archery XP through the game (its XP multipliers apply). With per-skill multipliers the game
--- reads the sandbox option MultiplierConfig.Archery (sandbox-options.txt); if AddXP throws anyway
--- (the option missing), the XP still goes in, by our own multiplier, instead of the error.
function F.awardXp(character, amount)
    if not (character and amount and amount > 0) then return end
    local ok = pcall(function()
        if addXp then addXp(character, F.perk(), amount) else character:getXp():AddXP(F.perk(), amount) end
    end)
    if not ok then
        local mc = SandboxVars and SandboxVars.MultiplierConfig or {}
        local m = mc.GlobalToggle ~= false and (mc.Global or 1) or (mc.Archery or 1)
        character:getXp():AddXPNoMultiplier(F.perk(), amount * m)
    end
end

return F
