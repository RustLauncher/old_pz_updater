--[[
    Fletcher: bows, crossbows and their ammunition as data, and how they combine with Archery.

    Two ammo families: arrows (bows) and bolts (crossbows). A launcher only takes its family; the
    player's preferred type is kept per family (player md fl_preferredArrow / fl_preferredBolt).
    Crossbows lean less on skill (their own per-level steps: steady aim from the start, cocking
    speed gains most) and the Lever Crossbow needs a Cocking Lever to be cocked (def.cocker,
    enforced in shared/Fletcher/Reload.lua).

    A shot's stats = the bow's base + Archery scaling (F.SKILL per-level steps) + the nocked arrow's
    modifiers. client/Fletcher/Bow.lua applies them to the bow in hand (F.applyBowSkill) and picks
    the arrow an empty bow nocks next (F.arrowFor): the player's preferred type if they carry one,
    else the best they carry. Each arrow is its own AmmoType (media/registries.lua), so pointing the
    bow item at it (setAmmoType) is all vanilla reload / unload need.
]]

require "Fletcher/Core"
require "Fletcher/Skill"
require "Fletcher/Fletching"
local F = Fletcher

-- Bases at Archery 0. kind: bow / crossbow; family: the ammo it takes. Bows: rest / drawVisual =
-- the worn, skinned pieces (client/Fletcher/Bow.lua). steps: per-level changes (default F.SKILL's).
F.CROSSBOW_STEPS = { hitChance = 2, critChance = 1, aimingTime = -1, reloadTime = -3 }
F.BOW_DEFS = {
    ["Fletcher.SimpleBow"] = {
        hit = 35, crit = 10, draw = 50, nock = 35, damage = { 0.9, 1.6 }, range = 18,
        rest = "Fletcher.BowVisualRest", drawVisual = "Fletcher.BowVisualDraw",
    },
    -- long, heavy draw: hits hardest of the wooden bows, slow on target
    ["Fletcher.Longbow"] = {
        hit = 35, crit = 12, draw = 60, nock = 40, damage = { 1.3, 2.3 }, range = 24, drawEndurance = 0.009,
        rest = "Fletcher.LongbowVisualRest", drawVisual = "Fletcher.LongbowVisualDraw",
    },
    -- short and quick, nearly the longbow's punch
    ["Fletcher.RecurveBow"] = {
        hit = 40, crit = 15, draw = 40, nock = 30, damage = { 1.2, 2.1 }, range = 22,
        rest = "Fletcher.RecurveVisualRest", drawVisual = "Fletcher.RecurveVisualDraw",
    },
    -- found only: let-off and sights make it the most accurate and the strongest
    ["Fletcher.CompoundBow"] = {
        hit = 50, crit = 18, draw = 35, nock = 30, damage = { 1.3, 2.1 }, range = 26, drawEndurance = 0.003,
        rest = "Fletcher.CompoundVisualRest", drawVisual = "Fletcher.CompoundVisualDraw",
    },
    -- urban (docs/urban_crafting.md): plumbing pipe, ends flattened: a light draw (least damage and range),
    -- quick on target, tough, but brittle below freezing (F.BRITTLE)
    ["Fletcher.PVCBow"] = {
        hit = 35, crit = 8, draw = 40, nock = 35, damage = { 0.75, 1.35 }, range = 16, coldBrittle = true,
        rest = "Fletcher.PVCBowVisualRest", drawVisual = "Fletcher.PVCBowVisualDraw",
    },
    -- urban: sawn from a plank: the Simple Bow's punch, slower to draw, and a cracked board is done
    ["Fletcher.BoardBow"] = {
        hit = 35, crit = 10, draw = 55, nock = 35, damage = { 1.0, 1.7 }, range = 18,
        rest = "Fletcher.BoardBowVisualRest", drawVisual = "Fletcher.BoardBowVisualDraw",
    },
    -- urban: two hockey sticks lapped and taped: more punch than the Simple Bow without sinew, heavy, less accurate
    ["Fletcher.HockeyBow"] = {
        hit = 33, crit = 12, draw = 45, nock = 35, damage = { 1.15, 2.0 }, range = 20,
        rest = "Fletcher.HockeyBowVisualRest", drawVisual = "Fletcher.HockeyBowVisualDraw",
    },
    -- urban: a recurve backed with tape instead of sinew: recurve class, a little slower, wears faster
    ["Fletcher.TapedRecurveBow"] = {
        hit = 38, crit = 14, draw = 44, nock = 30, damage = { 1.15, 2.0 }, range = 21,
        rest = "Fletcher.TapedRecurveBowVisualRest", drawVisual = "Fletcher.TapedRecurveBowVisualDraw",
    },
    -- crossbows: held like rifles (real held models, vanilla rifle animations)
    ["Fletcher.HandCrossbow"] = {
        kind = "crossbow", family = "bolt", steps = F.CROSSBOW_STEPS, cock = "Hand",
        hit = 45, crit = 12, draw = 30, nock = 60, damage = { 1.2, 2.0 }, range = 20,
    },
    ["Fletcher.LeverCrossbow"] = {
        kind = "crossbow", family = "bolt", steps = F.CROSSBOW_STEPS, cock = "Lever", cocker = "Fletcher.CockingLever",
        hit = 50, crit = 15, draw = 30, nock = 75, damage = { 1.6, 2.6 }, range = 24,
    },
    -- found only: a crank cocker is slow, the draw weight hits hardest of everything
    ["Fletcher.CrankCrossbow"] = {
        kind = "crossbow", family = "bolt", steps = F.CROSSBOW_STEPS, cock = "Crank",
        hit = 55, crit = 18, draw = 30, nock = 110, damage = { 1.6, 2.5 }, range = 28,
    },
}
for _, def in pairs(F.BOW_DEFS) do
    def.kind = def.kind or "bow"
    def.family = def.family or "arrow"
end

-- rank: "best available" order. damage multiplies the bow's; hit / crit add; breakage multiplies.
-- (arrows and bolts: "arrow" in names below means either)
F.ARROW_DEFS = {
    ["Fletcher.WoodenArrow"] = { ammo = "fletcher:arrow_wood", rank = 1, damage = 0.8, hit = 0, crit = 0, breakage = 0.6 },
    ["Fletcher.StoneArrow"] = { ammo = "fletcher:arrow_stone", rank = 2, damage = 1.0, hit = 0, crit = 0, breakage = 1.0 },
    -- carved bone (hunting materials): a little sharper and tougher than stone, short of a nail
    ["Fletcher.BoneArrow"] = { ammo = "fletcher:arrow_bone", rank = 2.5, damage = 1.0, hit = 0, crit = 4, breakage = 0.9 },
    ["Fletcher.NailArrow"] = { ammo = "fletcher:arrow_nail", rank = 3, damage = 1.0, hit = 0, crit = 8, breakage = 0.8 },
    -- special arrows (def.special): never nocked as "the best carried", only when chosen
    -- a lure: hardly hurts, rattles where it lands (F.arrowNoise)
    ["Fletcher.NoiseArrow"] = { ammo = "fletcher:arrow_noise", rank = 0, damage = 0.3, hit = 0, crit = -20, breakage = 0.9, special = true,
                                noise = { radius = 18, volume = 18, pulses = 5, every = 1.2 } },   -- (vanilla noise maker: 17)
    -- lit on release when a lighter / matches are carried (F.lightFire): sets alight what it hits, or the ground
    ["Fletcher.FireArrow"] = { ammo = "fletcher:arrow_fire", rank = 0, damage = 0.8, hit = 0, crit = 0, breakage = 1.0, special = true,
                               fire = { energy = 60 }, streak = "Fletcher.FlightStreakFire" },
    -- bowfishing (0.7, Bowfishing.lua): on a line; a weak barbed point against anything on land
    ["Fletcher.FishingArrow"] = { ammo = "fletcher:arrow_fishing", rank = 0, damage = 0.6, hit = 0, crit = -10, breakage = 0.5, special = true,
                                  fishing = true },
    ["Fletcher.CarbonArrow"] = { ammo = "fletcher:arrow_carbon", rank = 4, damage = 1.1, hit = 8, crit = 0, breakage = 0.4 },
    ["Fletcher.BroadheadArrow"] = { ammo = "fletcher:arrow_broadhead", rank = 5, damage = 1.35, hit = 0, crit = 4, breakage = 1.4 },
    ["Fletcher.WoodenBolt"] = { family = "bolt", ammo = "fletcher:bolt_wood", rank = 1, damage = 0.85, hit = 0, crit = 0, breakage = 0.6 },
    ["Fletcher.IronBolt"] = { family = "bolt", ammo = "fletcher:bolt_iron", rank = 2, damage = 1.0, hit = 0, crit = 6, breakage = 0.8 },
    ["Fletcher.AluminumBolt"] = { family = "bolt", ammo = "fletcher:bolt_aluminum", rank = 3, damage = 1.1, hit = 8, crit = 0, breakage = 0.4 },
    ["Fletcher.BroadheadBolt"] = { family = "bolt", ammo = "fletcher:bolt_broadhead", rank = 4, damage = 1.35, hit = 0, crit = 4, breakage = 1.4 },
}
-- Matched arrows and bolts (the fletching bench; items GENERATED by animation/scripts/matched_arrows.py):
-- one of a matched set strays less and breaks less than its base type; it looks like the base (def.base:
-- nocked look, loaded-bolt model) and wears into the base's damaged form.
F.MATCHED = { spread = 0.85, breakage = 0.75 }
F.MATCHABLE = { "WoodenArrow", "StoneArrow", "BoneArrow", "NailArrow", "BroadheadArrow", "WoodenBolt", "IronBolt", "BroadheadBolt" }
for _, name in ipairs(F.MATCHABLE) do
    local base = F.ARROW_DEFS["Fletcher." .. name]
    if base then
        local m = {}
        for k, v in pairs(base) do m[k] = v end
        m.ammo = base.ammo .. "_matched"
        m.rank = base.rank + 0.05            -- (just above its base: "the best carried" takes it first)
        m.breakage = base.breakage * F.MATCHED.breakage
        m.spread = F.MATCHED.spread
        m.base = "Fletcher." .. name
        m.matched = true
        F.ARROW_DEFS["Fletcher.Matched" .. name] = m
    end
end

for t, def in pairs(F.ARROW_DEFS) do
    def.family = def.family or "arrow"
    -- each arrow's own nocked look (client/Fletcher/Bow.lua also registers them as visuals); set here so
    -- reloading this file keeps it
    local v = "Fletcher.ArrowVisual_" .. (def.base or t):match("%.(.+)$")
    if def.family == "arrow" and getScriptManager and getScriptManager():getItem(v) then def.visual = v end
end
F.DEFAULT_AMMO = { arrow = "Fletcher.WoodenArrow", bolt = "Fletcher.WoodenBolt" }
F.DEFAULT_ARROW = F.DEFAULT_AMMO.arrow
F.PREF_KEY = { arrow = "fl_preferredArrow", bolt = "fl_preferredBolt" }

--- Ammo types of a family ("arrow" by default), best first
function F.arrowsByRank(family)
    family = family or "arrow"
    local out = {}
    for fullType, def in pairs(F.ARROW_DEFS) do
        if def.family == family then out[#out + 1] = fullType end
    end
    table.sort(out, function(a, b) return F.ARROW_DEFS[a].rank > F.ARROW_DEFS[b].rank end)
    return out
end

--- Is this item one of our launchers (bow or crossbow)?
function F.isBow(item)
    return item ~= nil and item.getFullType ~= nil and F.BOW_DEFS[item:getFullType()] ~= nil
end

--- A bow proper (drawn by hand: the worn bow rig and our draw animations), not a crossbow
function F.isHandBow(item)
    local def = F.isBow(item) and F.BOW_DEFS[item:getFullType()]
    return def and def.kind == "bow" or false
end

--- The ammo family a launcher takes
function F.familyOf(bow)
    local def = F.bowDef(bow)
    return def and def.family or "arrow"
end

function F.bowDef(bow)
    return bow and F.BOW_DEFS[bow:getFullType()] or nil
end

--- Every stat of a shot: bow (def) + Archery level + arrow (fullType; nil = no modifiers) + its
--- fletching (fl, Fletching.lua; nil = feathers).
function F.shotStats(bowDef, level, arrowType, bow, fl)
    local L = math.max(0, math.min(10, level or 0))
    local a = F.ARROW_DEFS[arrowType or ""] or { damage = 1, hit = 0, crit = 0, breakage = 1 }
    local fd = F.fletchDef and F.fletchDef(fl) or { spread = 1, breakage = 1 }
    local steps = bowDef.steps
    local step = function(name) return (steps and steps[name] or F.SKILL[name][2]) * L end
    local out = {
        spreadMul = (a.spread or 1) * fd.spread,   -- (a matched arrow strays less, tape more: F.shotSpread)
        hitChance = bowDef.hit + step("hitChance") + a.hit,
        critChance = bowDef.crit + step("critChance") + a.crit,
        aimingTime = math.max(10, bowDef.draw + step("aimingTime")),
        reloadTime = math.max(8, bowDef.nock + step("reloadTime")),
        minDamage = bowDef.damage[1] * a.damage,
        maxDamage = bowDef.damage[2] * a.damage,
        range = bowDef.range,
        breakChance = math.max(F.BREAK_FLOOR or 0, F.stat("breakChance", L) * a.breakage * fd.breakage),
    }
    -- seasoned wood (Seasoning.lua): a harder-hitting, farther-reaching bow
    if bow and F.bowSeasoned and F.bowSeasoned(bow) then
        out.minDamage, out.maxDamage = out.minDamage * F.SEASONED.damage, out.maxDamage * F.SEASONED.damage
        out.range = out.range + F.SEASONED.range
        out.seasoned = true
    end
    return out
end

--- The arrow type a bow's AmmoType names right now (nil if not one of ours)
function F.bowArrow(bow)
    local ok, key = pcall(function() return bow:getAmmoType():getItemKey() end)
    return ok and F.ARROW_DEFS[key] and key or nil
end

--- Point the bow at an arrow type (what vanilla reload takes next). True if it changed.
function F.setBowArrow(bow, arrowType)
    local def = F.ARROW_DEFS[arrowType or ""]
    if not def or F.bowArrow(bow) == arrowType then return false end
    bow:setAmmoType(AmmoType.get(ResourceLocation.of(def.ammo)))
    return true
end

--- How many of an arrow type the character carries (bags included)
function F.arrowCount(character, arrowType)
    return character:getInventory():getCountTypeRecurse(arrowType)
end

--- The player's chosen type in a family (player mod data; nil = best available)
function F.preferredArrow(character, family)
    family = family or "arrow"
    local p = character:getModData()[F.PREF_KEY[family]]
    local def = F.ARROW_DEFS[p or ""]
    return def and def.family == family and p or nil
end

--- Choose a type (its family is its own), or clear a family's choice (arrowType nil + family)
function F.setPreferredArrow(character, arrowType, family)
    local def = F.ARROW_DEFS[arrowType or ""]
    family = def and def.family or family or "arrow"
    character:getModData()[F.PREF_KEY[family]] = def and arrowType or nil
end

--- What an empty launcher should take next: the preferred type of its family if carried, else
--- the best of its family carried, else the preferred type (or whatever it names now) so the
--- reload prompt asks for it.
function F.arrowFor(character, bow)
    local family = F.familyOf(bow)
    local pref = F.preferredArrow(character, family)
    if pref and F.arrowCount(character, pref) > 0 then return pref end
    for _, t in ipairs(F.arrowsByRank(family)) do
        -- (a lure like the noisemaker is only nocked when chosen: never as "the best carried")
        if not F.ARROW_DEFS[t].special and F.arrowCount(character, t) > 0 then return t end
    end
    local now = F.bowArrow(bow)
    if now and F.ARROW_DEFS[now].family ~= family then now = nil end
    return pref or now or F.DEFAULT_AMMO[family]
end

-- Arrow wear: a shot arrow that doesn't break may come back damaged ("Fletcher.Damaged<Type>",
-- GENERATED by animation/scripts/damaged_arrows.py with its re-fletch recipe). Percent: base + per
-- Archery level, x the arrow's def.wear (default 1); special arrows (fire, noise) don't wear.
F.WEAR = { base = 25, perLevel = -1 }
F.WEAR_FACTOR = { ["Fletcher.CarbonArrow"] = 0.5, ["Fletcher.AluminumBolt"] = 0.5,
                  ["Fletcher.NailArrow"] = 0.8, ["Fletcher.IronBolt"] = 0.8 }

--- The damaged form of an arrow / bolt type, or nil (none, or it doesn't wear)
function F.damagedOf(arrowType)
    local def = F.ARROW_DEFS[arrowType or ""]
    if not def or def.special then return nil end
    local d = "Fletcher.Damaged" .. (def.base or arrowType):match("%.(.+)$")     -- (a matched one: its base's)
    return getScriptManager():getItem(d) and d or nil
end

--- Percent chance a surviving arrow comes back damaged (F.WEAR_OVERRIDE in tests); fl: its fletching
function F.wearChance(shooter, arrowType, fl)
    if F.WEAR_OVERRIDE then return F.WEAR_OVERRIDE end
    if F.BREAK_CHANCE_OVERRIDE == 0 then return 0 end      -- (tests that switch breakage off: no wear either)
    local L = F.level and shooter and F.level(shooter) or 0
    local fw = F.fletchDef and F.fletchDef(fl).wear or 1
    return math.max(0, F.WEAR.base + F.WEAR.perLevel * L) * (F.WEAR_FACTOR[arrowType or ""] or 1) * fw
end

-- Leg shots cripple (Projectile.lua F.finishProjectile): percent chance a hit in the legs band of a
-- standing zombie that survives turns it into a crawler; x2 on a critical, x F.CRIPPLE_FACTOR
-- (broadheads cut, a blunt noisemaker can't). F.CRIPPLE_OVERRIDE in tests.
F.CRIPPLE = { base = 20, perLevel = 2 }
F.CRIPPLE_FACTOR = { ["Fletcher.BroadheadArrow"] = 1.5, ["Fletcher.BroadheadBolt"] = 1.5, ["Fletcher.NoiseArrow"] = 0 }

--- Percent chance a leg hit cripples
function F.crippleChance(shooter, arrowType, crit)
    if F.CRIPPLE_OVERRIDE then return F.CRIPPLE_OVERRIDE end
    local L = F.level and shooter and F.level(shooter) or 0
    local c = (F.CRIPPLE.base + F.CRIPPLE.perLevel * L) * (F.CRIPPLE_FACTOR[arrowType or ""] or 1)
    return math.min(100, crit and c * 2 or c)
end

-- Reload clips (animation/scripts/bow_clips.py, crossbow_clips.py): seconds at speed 1, and for the
-- cocking clips the share of the clip where the string latches and where the bolt is on the rail
-- (client/Fletcher/Bow.lua swaps the crossbow's model there). def.cock picks the clip.
F.NOCK_SECONDS = 1.77               -- Fletcher_Bow_Nock: 53 frames (video mocap, mocap_clips.py)
F.COCK = {
    Hand = { seconds = 2.4, cocked = 0.5, bolt = 0.812 },
    Lever = { seconds = 2.8, cocked = 0.571, bolt = 0.839 },
    Crank = { seconds = 4.0, cocked = 0.7, bolt = 0.887 },
}
F.QUIVER_SPEED = 1.15                   -- nocking / cocking from the worn hip quiver holding that ammo
F.BACK_QUIVER_SPEED = 1.07              -- ... from the back quiver (reaching over the shoulder)

--- Seconds a load's clip lasts at speed 1
function F.loadSeconds(gun)
    local def = F.bowDef(gun)
    local cock = def and def.cock and F.COCK[def.cock]
    return cock and cock.seconds or F.NOCK_SECONDS
end

--- How much faster than its clip this character loads this launcher: Archery (the def's reload
--- time at level 0 over the scaled one) and a worn quiver with that ammo in it
function F.reloadFactor(character, gun)
    local def = F.bowDef(gun)
    if not (def and character) then return 1.0 end
    local f = def.nock / F.shotStats(def, F.level(character), nil).reloadTime
    local q = F.quiverFor and F.quiverFor(character, def.family)
    if q == "hip" then f = f * F.QUIVER_SPEED elseif q == "back" then f = f * F.BACK_QUIVER_SPEED end
    return f
end

--- The Lever Crossbow can't be cocked without its lever: the missing tool's type, or nil
function F.missingCocker(character, bow)
    local def = F.bowDef(bow)
    if not (def and def.cocker) then return nil end
    if character and character:getInventory():containsTypeRecurse(def.cocker) then return nil end
    return def.cocker
end

-- Cold-brittle bows (def.coldBrittle: the PVC Bow): below freezing (the air at the holder: indoors
-- counts as warmer) the bow wears twice as fast (half the one-in-N condition loss chance)
F.BRITTLE = { belowC = 0.0, wear = 0.5, checkMs = 5000 }
F.coldCache = F.coldCache or {}

--- Is this cold-brittle bow cold in this character's hands now? (cached per character for F.BRITTLE.checkMs)
function F.bowCold(character, def)
    if not (def and def.coldBrittle and character) then return false end
    local now = getTimestampMs()
    local c = F.coldCache[character]
    if c and now - c.t < F.BRITTLE.checkMs and F.BRITTLE_OVERRIDE == nil then return c.cold end
    local cold = F.BRITTLE_OVERRIDE
    if cold == nil then
        local ok, t = pcall(function() return getClimateManager():getAirTemperatureForCharacter(character, false) end)
        cold = ok and t ~= nil and t < F.BRITTLE.belowC or false
    end
    F.coldCache[character] = { t = now, cold = cold }
    return cold
end

--- Set the bow's stats from its def, its holder's Archery level and the arrow it has (or will)
--- nock. Cached on the item; returns true when something changed.
function F.applyBowSkill(character, bow, arrowType)
    local def = F.bowDef(bow)
    if not (character and def) then return false end
    arrowType = arrowType or F.bowArrow(bow)
    local level = F.level(character)
    local md = bow:getModData()
    -- true projectiles (shared/Fletcher/Projectile.lua): vanilla's own hit is switched off by a tiny
    -- range (vanilla picks its target while aiming: nothing later in the shot can stop it)
    local proj = F.projectileMode and F.projectileMode() or false
    local seasoned = F.bowSeasoned and F.bowSeasoned(bow) or false
    local cold = F.bowCold(character, def)
    local key = level .. "|" .. tostring(arrowType) .. "|" .. tostring(character:getOnlineID()) .. "|" .. tostring(proj) .. "|" .. tostring(seasoned) .. "|" .. tostring(cold)
    if md.fl_skillKey == key then return false end
    local s = F.shotStats(def, level, arrowType, bow)
    -- seasoned wood wears slower (condition loss is one chance in N per use: a larger N)
    local base = bow:getScriptItem():getConditionLowerChance()
    local lower = seasoned and math.floor(base * F.SEASONED.wear + 0.5) or base
    if cold then lower = math.max(1, math.floor(lower * F.BRITTLE.wear + 0.5)) end    -- (brittle in the cold)
    bow:setConditionLowerChance(lower)
    md.fl_cold = cold or nil
    if seasoned and md.fl_crafted ~= true and F.nameSeasoned then F.nameSeasoned(bow) end   -- (a found bow: well made)
    bow:setHitChance(s.hitChance)
    bow:setCriticalChance(s.critChance)
    bow:setAimingTime(s.aimingTime)
    bow:setReloadTime(s.reloadTime)
    bow:setMinDamage(s.minDamage)
    bow:setMaxDamage(s.maxDamage)
    bow:setMaxRange(proj and F.PROJ.suppressRange or s.range)
    md.fl_skillKey = key
    md.fl_skillLevel = level
    return true
end

return F
