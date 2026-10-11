--[[
    Fletcher: the bow while it's equipped.

    The bow item's hand model is invisible (WeaponSprite = FletcherEmpty); what you see is a worn
    piece skinned to the prop bones every clip animates (see "Bow rig" in CLAUDE.md):
      BowVisualRest  the whole bow on Bip01_Prop2, string straight: for every clip that isn't ours
                     (vanilla clips put Bip01_Prop1 in the right hand)
      BowVisualDraw  the string's nock on Bip01_Prop1: while aiming (our draw / hold / release clips)
    Each bow has its own pair (F.BOW_DEFS rest / drawVisual, shared/Fletcher/Gear.lua).
    Each tick, for the local player: set the FletcherBow animation variable (our AnimSets nodes
    require it), make sure the right visual is worn (or none when no bow is in hand), and keep the
    bow's arrow straight (F.syncArrow):
      empty bow  -> its AmmoType names the arrow to nock next (F.arrowFor), so R nocks that one
      nocked     -> md.fl_nocked remembers the arrow (the item's AmmoType may not survive a save)
    The visual items are created and removed here; they never stay in the inventory without a bow.

    The nocked arrow is worn too (fletcher:arrow, on Bip01_Prop1), one look per arrow type
    (ArrowVisual_<arrow>). A crossbow is its own held model (WeaponSprite), swapped here between
    uncocked, cocked and loaded-with-that-bolt (F.crossbowSprite), following the cocking clip.
    Animation variables set here: FletcherBow (our bow nodes), FletcherBowEmpty (a hand bow with no arrow
    on the string: aiming shows the release's follow-through instead of a draw), FletcherXbow (the cocking clip:
    def.cock, else "none") and FletcherReloadSpeed (the load clips' speed: vanilla's ReloadSpeed x
    F.reloadFactor, i.e. Archery and a worn quiver).
]]

require "Fletcher/Core"
require "Fletcher/Skill"
require "Fletcher/Gear"
require "Fletcher/Reload"
require "Fletcher/Quiver"
require "Fletcher/FireLight"
local F = Fletcher

F.BOWS, F.VISUALS = {}, {}
for fullType, def in pairs(F.BOW_DEFS) do
    F.BOWS[fullType] = true                 -- every launcher (crossbows too: arrow sync, stats, shots)
    if def.rest then
        F.VISUALS[def.rest] = true
        F.VISUALS[def.drawVisual] = true
    end
end

local location
local function bowLocation()
    location = location or ItemBodyLocation.get(ResourceLocation.of("fletcher:bow"))
    return location
end

function F.equippedBow(player)
    local item = player:getPrimaryHandItem()
    if item and F.BOWS[item:getFullType()] then return item end
    return nil
end

--- The visual a player should wear now: draw while aiming a bow, rest while holding one, else none.
function F.wantedVisual(player)
    local bow = F.equippedBow(player)
    local taking = F.equipping[player]
    if (not bow or not F.isHandBow(bow)) and taking and F.BOW_DEFS[taking] then
        return F.BOW_DEFS[taking].rest                       -- being taken off the shoulder
    end
    if not bow or not F.isHandBow(bow) then return nil end      -- crossbows are their own held model
    local def = F.bowDef(bow)
    -- nocking (also while aiming): the Rest model. The Draw model's string and bending limbs follow
    -- Bip01_Prop1, which the nock clip carries to the quiver and turns with the arrow
    if player:getVariableBoolean("isLoading") then return def.rest end
    return player:isAiming() and def.drawVisual or def.rest
end

F.ARROW_VISUAL = "Fletcher.ArrowVisual"           -- fallback look (an arrow type without its own)
F.ARROW_VISUALS = { [F.ARROW_VISUAL] = true }     -- every arrow visual (fletcher:arrow)
for _, v in ipairs(F.FIRE_LIT_VISUALS or {}) do F.ARROW_VISUALS[v] = true; F.VISUALS[v] = true end
F.VISUALS[F.ARROW_VISUAL] = true
for t, def in pairs(F.ARROW_DEFS) do
    if def.family == "arrow" then
        local v = "Fletcher.ArrowVisual_" .. (def.base or t):match("%.(.+)$")
        if getScriptManager():getItem(v) then
            def.visual = v
            F.ARROW_VISUALS[v] = true
            F.VISUALS[v] = true
        end
    end
end
F.equipping = F.equipping or {}          -- character -> bow type being equipped / unequipped
F.loadingSince = F.loadingSince or {}

local arrowLocation
local function arrowSlot()
    arrowLocation = arrowLocation or ItemBodyLocation.get(ResourceLocation.of("fletcher:arrow"))
    return arrowLocation
end

--- The speed our load clips play at for this character and launcher (FletcherReloadSpeed)
function F.reloadSpeed(player, bow)
    return math.max(0.05, player:getVariableFloat("ReloadSpeed", 1.0)) * (bow and F.reloadFactor(player, bow) or 1.0)
end

--- How far through its load clip the character is (0..1+), or nil when not loading. Call once a
--- tick (F.syncBow does): it remembers when the load started.
function F.loadProgress(player, bow, now)
    local key = player:getPlayerNum()
    if not (bow and player:getVariableBoolean("isLoading")) then
        F.loadingSince[key] = nil
        return nil
    end
    F.loadingSince[key] = F.loadingSince[key] or now
    return (now - F.loadingSince[key]) / (F.loadSeconds(bow) * 1000 / F.reloadSpeed(player, bow))
end

--- Should the character show an arrow (the nocked / in-hand arrow piece on Bip01_Prop1)? While a bow
--- holds one, and while nocking once the hand has drawn it from the quiver (the nock clip takes it
--- out at F.NOCK_GRAB of its F.NOCK_SECONDS). progress: F.loadProgress.
F.NOCK_GRAB = 0.47                  -- the hand is at the quiver at frame 14 of the nock clip
function F.wantsArrow(player, bow, progress)
    if not (bow and F.isHandBow(bow)) then return false end
    if bow:isRoundChambered() then return true end
    return progress ~= nil and progress * F.NOCK_SECONDS >= F.NOCK_GRAB
end

-- Bows and crossbows slung on the back (0.6.1: AttachmentType = Rifle, vanilla's Back slot; attached
-- weapons weigh 30 percent less). The game draws an attached weapon with its WeaponSprite, placed like a
-- rifle: each launcher gets a model built for that (bows.py / crossbows.py <prefix>_Back: a bow upright
-- with its string toward the body, a crossbow rolled so the prod lies across the back). Back in the
-- hands: a bow its invisible held model again (the worn visual is the bow you see), a crossbow its own
-- (F.syncCrossbowSprite). Every client does this for every player it sees (a WeaponSprite is the item's
-- own field: other clients' copies keep the script's).
F.BACK_SPRITES = { ["Fletcher.SimpleBow"] = "Fletcher.FletcherBow_Back", ["Fletcher.Longbow"] = "Fletcher.FletcherLongbow_Back",
                   ["Fletcher.RecurveBow"] = "Fletcher.FletcherRecurve_Back", ["Fletcher.PVCBow"] = "Fletcher.FletcherPVCBow_Back", ["Fletcher.BoardBow"] = "Fletcher.FletcherBoardBow_Back", ["Fletcher.HockeyBow"] = "Fletcher.FletcherHockeyBow_Back", ["Fletcher.TapedRecurveBow"] = "Fletcher.FletcherTapedRecurve_Back", ["Fletcher.CompoundBow"] = "Fletcher.FletcherCompound_Back",
                   ["Fletcher.HandCrossbow"] = "Fletcher.FletcherHandCrossbow_Back", ["Fletcher.LeverCrossbow"] = "Fletcher.FletcherLeverCrossbow_Back",
                   ["Fletcher.CrankCrossbow"] = "Fletcher.FletcherCrankCrossbow_Back" }
-- over a worn bag (vanilla's "Rifle On Back with Bag" turns a rifle across the pack): bows have a copy
-- turned back upright and set out onto the pack (bows.py BACK_BAG_BOW); crossbows look right as they are
F.BACK_BAG_SPRITES = { ["Fletcher.SimpleBow"] = "Fletcher.FletcherBow_BackBag", ["Fletcher.Longbow"] = "Fletcher.FletcherLongbow_BackBag",
                       ["Fletcher.RecurveBow"] = "Fletcher.FletcherRecurve_BackBag", ["Fletcher.PVCBow"] = "Fletcher.FletcherPVCBow_BackBag", ["Fletcher.BoardBow"] = "Fletcher.FletcherBoardBow_BackBag", ["Fletcher.HockeyBow"] = "Fletcher.FletcherHockeyBow_BackBag", ["Fletcher.TapedRecurveBow"] = "Fletcher.FletcherTapedRecurve_BackBag", ["Fletcher.CompoundBow"] = "Fletcher.FletcherCompound_BackBag" }
F.HELD_SPRITE = "Fletcher.FletcherEmpty"

--- Bring a character's launchers' WeaponSprites in line: on the back, the back model; a bow in the
--- hands, the invisible held one (a crossbow in the hands: F.syncCrossbowSprite). True if one changed.
--- A character's (player's or zombie's) attached launchers -> their back models (over a bag: a bow's
--- _BackBag copy). The held item is skipped. True if one changed.
function F.syncAttachedSprites(character, held)
    local changed = false
    local list = character:getAttachedItems()
    for i = 0, (list and list:size() or 0) - 1 do
        local att = list:get(i)
        local it = att:getItem()
        local back = it and F.BACK_SPRITES[it:getFullType()]
        if back and it ~= held then
            local loc = att:getLocation()
            if loc and loc:find("with Bag", 1, true) then back = F.BACK_BAG_SPRITES[it:getFullType()] or back end
            if it:getWeaponSprite() ~= back then it:setWeaponSprite(back); changed = true end
        end
    end
    return changed
end

-- The Back Quiver's worn look (0.7). The quiver item has no model of its own: a hidden look item is
-- worn with it at fletcher:backquiverlook, on the back or set out onto a worn backpack (the same line
-- further out: gear_visuals.py BACK_QUIVER_BAG), like the bow's worn visual. (An item's ItemVisual
-- can't be re-pointed: InventoryItem.getVisual() resets its clothing item from the script each call.)
-- Local players only; other clients see it as the synced clothing it is.
F.BACK_QUIVER_LOOK = { back = "Fletcher.BackQuiverLook", bag = "Fletcher.BackQuiverLookBag" }
F.BACK_QUIVER_LOOKS = { ["Fletcher.BackQuiverLook"] = true, ["Fletcher.BackQuiverLookBag"] = true }
local packLocation, lookLocation
function F.wantedBackQuiverLook(player)
    if not (F.wornBackQuiver and F.wornBackQuiver(player)) then return nil end
    packLocation = packLocation or ItemBodyLocation.get(ResourceLocation.of("base:back"))
    return player:getWornItem(packLocation) and F.BACK_QUIVER_LOOK.bag or F.BACK_QUIVER_LOOK.back
end

--- Wear the right look item (or none). True if it changed.
function F.syncBackQuiverLook(player)
    lookLocation = lookLocation or ItemBodyLocation.get(ResourceLocation.of("fletcher:backquiverlook"))
    local want = F.wantedBackQuiverLook(player)
    local cur = player:getWornItem(lookLocation)
    if (cur and cur:getFullType()) == want then return false end
    local inv = player:getInventory()
    local items = inv:getItems()
    for i = items:size() - 1, 0, -1 do                    -- the old look, and any stray copy
        local it = items:get(i)
        if F.BACK_QUIVER_LOOKS[it:getFullType()] then
            if player:isEquippedClothing(it) then player:removeWornItem(it) end
            inv:Remove(it)
        end
    end
    if cur and cur:getContainer() then cur:getContainer():Remove(cur) end
    if want then
        local it = inv:AddItem(want)
        player:setWornItem(lookLocation, it)
    end
    player:resetModelNextFrame()
    return true
end

function F.syncBowSprites(player)
    local changed = false
    local function want(item, sprite)
        if item:getWeaponSprite() ~= sprite then item:setWeaponSprite(sprite); changed = true end
    end
    local held = player:getPrimaryHandItem()
    if F.syncAttachedSprites(player, held) then changed = true end
    if held and F.BACK_SPRITES[held:getFullType()] then
        if F.isHandBow(held) then
            want(held, F.HELD_SPRITE)
        elseif held:getWeaponSprite() == F.BACK_SPRITES[held:getFullType()] then
            want(held, F.crossbowSprite(held) or held:getScriptItem():getWeaponSprite())   -- (off the back: its own again)
        end
    end
    if changed then player:resetModelNextFrame() end
    return changed
end

--- A warm light round an archer whose fire arrow burns (a lamppost light source moved with them)
F.fireLights = F.fireLights or {}           -- player -> { light, x, y, z }
function F.syncFireLight(player, bow)
    local want = F.showsLit(player, bow)
    local cur = F.fireLights[player]
    local x, y, z = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
    if cur and (not want or cur.x ~= x or cur.y ~= y or cur.z ~= z) then
        pcall(function() getCell():removeLamppost(cur.light) end)
        F.fireLights[player] = nil
        cur = nil
    end
    if want and not cur then
        local L = F.LIGHT.light
        local ok, light = pcall(function()
            local l = IsoLightSource.new(x, y, z, L.r, L.g, L.b, L.radius)
            getCell():addLamppost(l)
            return l
        end)
        if ok and light then F.fireLights[player] = { light = light, x = x, y = y, z = z } end
    end
end

--- Is the rag of the fire arrow on this bow burning (lit, or the light action past its catch)?
function F.showsLit(player, bow)
    if not (bow and F.fireNocked and F.fireNocked(bow)) then return false end
    if F.isLit(bow) then return true end
    local l = player and F.lighting and F.lighting[player]
    return l ~= nil and l.bow == bow and getTimestampMs() - l.at >= F.LIGHT.catchAt * F.LIGHT.seconds * 1000
end

--- The arrow visual for a bow: its nocked arrow's look (a burning fire arrow: one flame frame of
--- F.FIRE_LIT_VISUALS, cycled), or the one it's nocking
function F.arrowVisualFor(bow, player)
    if player and F.showsLit(player, bow) then
        -- (Kahlua's % is wrong on numbers this big: the remainder by floor division)
        local n = #F.FIRE_LIT_VISUALS
        local t = math.floor(getTimestampMs() / F.LIGHT.flickerMs)
        return F.FIRE_LIT_VISUALS[t - math.floor(t / n) * n + 1]
    end
    local arrow = bow:isRoundChambered() and bow:getModData().fl_nocked or F.bowArrow(bow)
    local def = F.ARROW_DEFS[arrow or ""]
    return def and def.visual or F.ARROW_VISUAL
end

--- Wear this arrow visual (fullType; true = the fallback look), or none (nil / false)
function F.syncArrowVisual(player, want)
    if want == true then want = F.ARROW_VISUAL end
    local current = player:getWornItem(arrowSlot())
    if (current and current:getFullType() or nil) == (want or nil) then return false end
    local inv = player:getInventory()
    if current then
        player:removeWornItem(current)
        inv:Remove(current)
    end
    if want then
        local it = inv:AddItem(want)
        player:setWornItem(it:getBodyLocation(), it)
    end
    player:resetModelNextFrame()
    return true
end

--- The held model a crossbow should show: uncocked, cocked (the string on the nut, no bolt yet), or
--- loaded with its bolt (<base>_<BoltItem>: animation/scripts/crossbows.py). progress: F.loadProgress.
F.XBOW_BASE = F.XBOW_BASE or {}
function F.crossbowSprite(bow, progress)
    local def = F.bowDef(bow)
    local cock = def and def.cock and F.COCK[def.cock]
    if not cock then return nil end
    local t = bow:getFullType()
    if not F.XBOW_BASE[t] then
        local script = getScriptManager():getItem(t)
        F.XBOW_BASE[t] = script and script:getWeaponSprite() or nil
    end
    local base = F.XBOW_BASE[t]
    if not base then return nil end
    local loaded = bow:isRoundChambered() or bow:getCurrentAmmoCount() > 0
    local bolt
    if loaded then
        bolt = bow:getModData().fl_nocked or F.bowArrow(bow)
    elseif progress and progress >= cock.bolt then
        bolt = F.bowArrow(bow)
    elseif progress and progress >= cock.cocked then
        return base .. "_Cocked"
    end
    if bolt then
        local bd = F.ARROW_DEFS[bolt]
        return base .. "_" .. ((bd and bd.base) or bolt):match("%.(.+)$")      -- (matched: its base's model)
    end
    return base
end

function F.syncCrossbowSprite(player, bow, progress)
    local want = bow and F.crossbowSprite(bow, progress)
    if not want or bow:getWeaponSprite() == want then return false end
    bow:setWeaponSprite(want)
    player:resetEquippedHandsModels()
    return true
end

-- Equip / unequip of a bow: FletcherEquip for our action nodes (the bow isn't in hand yet when
-- equipping), and the bow's rest visual while it's being taken out
function F.onEquipStart(action)
    local item = action and action.item
    if item and F.isHandBow(item) then
        F.equipping[action.character] = item:getFullType()
        action.character:setVariable("FletcherEquip", "true")
    end
end

function F.onEquipEnd(action)
    if action and action.character and F.equipping[action.character] then
        F.equipping[action.character] = nil
        action.character:setVariable("FletcherEquip", "false")
    end
end

for _, cls in ipairs({ ISEquipWeaponAction, ISUnequipAction }) do
    if cls and not cls.fl_equipWrapped then
        cls.fl_equipWrapped = true
        local start, stop, perform = cls.start, cls.stop, cls.perform
        cls.start = function(self, ...) F.onEquipStart(self); return start(self, ...) end
        cls.stop = function(self, ...) F.onEquipEnd(self); return stop(self, ...) end
        cls.perform = function(self, ...) F.onEquipEnd(self); return perform(self, ...) end
    end
end

-- Holding a draw this long switches the hold to the tired clip (aim_fletcherbow_tired.xml)
F.TIRED_SECONDS = 4.0
F.aimingSince = F.aimingSince or {}

--- FletcherBowTired for a character: true once it has held a drawn bow for F.TIRED_SECONDS.
--- Animation variables are local, so every client works it out for every character it shows.
function F.syncTired(character, now)
    local key = character:getOnlineID() .. "/" .. tostring(character:getPlayerNum())
    local held = character:getPrimaryHandItem()
    if F.isHandBow(held) and character:isAiming() and held:isRoundChambered() then   -- only a drawn arrow tires
        F.aimingSince[key] = F.aimingSince[key] or now
    else
        F.aimingSince[key] = nil
    end
    local since = F.aimingSince[key]
    local tired = since and (now - since) >= F.TIRED_SECONDS * 1000
    character:setVariable("FletcherBowTired", tired and "true" or "false")
    -- holding a draw costs stamina (the local player's own; doubled once the arm starts to shake)
    if since and character:isLocalPlayer() then
        local last = F.drainAt[key] or now
        local dt = math.max(0, math.min(0.2, (now - last) / 1000))
        local def = F.bowDef(held)
        local rate = (def and def.drawEndurance or F.DRAW_ENDURANCE) * (tired and 2 or 1)
        if dt > 0 then pcall(function() character:getStats():remove(CharacterStat.ENDURANCE, rate * dt) end) end
        F.drainAt[key] = now
    else
        F.drainAt[key] = nil
    end
end
F.DRAW_ENDURANCE = 0.006      -- endurance (0..1) per second held drawn; per bow: def.drawEndurance
F.drainAt = F.drainAt or {}

--- The arrow the bow holds or will nock, kept in line with what's carried / nocked.
function F.syncArrow(player, bow)
    local md = bow:getModData()
    local arrow
    -- holding one: nocked (chambered), or just loaded and not yet chambered (vanilla puts the round in
    -- the 1-round magazine, then a rack chambers it): treating the second as empty re-pointed the bow at
    -- the best arrow left, so nocking the LAST of a chosen type recorded (and later shot) another type
    if bow:isRoundChambered() or bow:getCurrentAmmoCount() > 0 then
        md.fl_nocked = md.fl_nocked or F.bowArrow(bow) or F.DEFAULT_AMMO[F.familyOf(bow)]
        arrow = md.fl_nocked
    else
        md.fl_nocked, md.fl_nockedFletch = nil, nil
        arrow = F.arrowFor(player, bow)
    end
    F.setBowArrow(bow, arrow)
    return arrow
end

local function removeStrays(player, keep)
    local inv = player:getInventory()
    local items = inv:getItems()
    for i = items:size() - 1, 0, -1 do
        local it = items:get(i)
        if F.VISUALS[it:getFullType()] and it ~= keep and not F.ARROW_VISUALS[it:getFullType()] then
            if player:isEquippedClothing(it) then player:removeWornItem(it) end
            inv:Remove(it)
        end
    end
end

--- Bring the player's bow state in line. Returns true when the visual changed.
function F.syncBow(player)
    local bow = F.equippedBow(player)
    local now = getTimestampMs()
    local def = F.bowDef(bow)
    player:setVariable("FletcherBow", F.isHandBow(bow) and "true" or "false")   -- our bow AnimSets
    -- an empty bow (just shot): aiming shows the follow-through, not a draw (aim_fletcherbow_empty etc.)
    player:setVariable("FletcherBowEmpty", F.isHandBow(bow) and not bow:isRoundChambered() and "true" or "false")
    player:setVariable("FletcherXbow", def and def.cock or "none")               -- our cocking clips
    player:setVariable("FletcherReloadSpeed", F.reloadSpeed(player, bow))
    F.syncTired(player, now)
    local progress = F.loadProgress(player, bow, now)
    F.syncArrowVisual(player, F.wantsArrow(player, bow, progress) and F.arrowVisualFor(bow, player) or nil)
    if F.syncFireLight then F.syncFireLight(player, bow) end
    F.syncBowSprites(player)
    F.syncBackQuiverLook(player)
    F.syncCrossbowSprite(player, bow, progress)
    if bow then F.applyBowSkill(player, bow, F.syncArrow(player, bow)) end
    local want = F.wantedVisual(player)
    local current = player:getWornItem(bowLocation())
    local currentType = current and current:getFullType() or nil
    if currentType == want then
        return false
    end
    if current then                          -- the worn piece itself, wherever it sits now
        player:removeWornItem(current)
        if current:getContainer() then current:getContainer():Remove(current) end
    end
    removeStrays(player, nil)
    if want then
        local it = player:getInventory():AddItem(want)
        player:setWornItem(it:getBodyLocation(), it)
    end
    player:resetModelNextFrame()
    return true
end

function F.onBowPlayerUpdate(player)
    if not player:isLocalPlayer() then return end
    local ok, err = pcall(F.syncBow, player)
    if not ok and not F.syncErrorShown then
        F.syncErrorShown = true
        F.log("bow sync error: " .. tostring(err))
    end
end

--- The player's arrow choice: kept here, and in multiplayer on the server too (its reload reads it)
function F.choosePreferredArrow(player, arrowType, family)
    F.setPreferredArrow(player, arrowType, family)
    if isClient() then sendClientCommand(player, "Fletcher", "prefer", { arrow = arrowType, family = family }) end
end

-- Other players' bows (multiplayer): our AnimSets nodes need FletcherBow on every character this
-- client animates, and animation variables are local, so set it for remote players here too
-- (their visuals arrive as synced clothing).
function F.syncRemoteBows()
    local list = getOnlinePlayers()
    for i = 0, (list and list:size() or 0) - 1 do
        local p = list:get(i)
        if p and not p:isLocalPlayer() then
            local item = p:getPrimaryHandItem()
            local def = F.BOWS[item and item:getFullType() or ""] and F.bowDef(item)
            p:setVariable("FletcherBow", F.isHandBow(item) and "true" or "false")
            p:setVariable("FletcherBowEmpty", F.isHandBow(item) and not item:isRoundChambered() and "true" or "false")
            p:setVariable("FletcherXbow", def and def.cock or "none")
            p:setVariable("FletcherReloadSpeed", F.reloadSpeed(p, def and item or nil))
            F.syncTired(p, getTimestampMs())
            F.syncBowSprites(p)
        end
    end
end

-- Right-click a bow: which arrow to nock (player mod data; "best available" = none chosen)
function F.onBowContextMenu(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    local bow
    for _, entry in ipairs(items) do
        local item = type(entry) == "table" and entry.items and entry.items[1] or entry
        if item and item.getFullType and F.BOWS[item:getFullType()] then bow = item; break end
    end
    if not (player and bow) then return end
    local family = F.familyOf(bow)
    local parent = context:addOption(getText(family == "bolt" and "IGUI_Fletcher_BoltsToLoad" or "IGUI_Fletcher_ArrowsToNock"), nil, nil)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(parent, sub)
    local pref = F.preferredArrow(player, family)
    local best = sub:addOption(getText("IGUI_Fletcher_BestArrow"), player, F.choosePreferredArrow, nil, family)
    if not pref then best.iconTexture = getTexture("media/ui/Tick_Mark-10.png") end
    for _, t in ipairs(F.arrowsByRank(family)) do
        local name = getItemNameFromFullType(t) .. " (" .. F.arrowCount(player, t) .. ")"
        local opt = sub:addOption(name, player, F.choosePreferredArrow, t, family)
        if pref == t then opt.iconTexture = getTexture("media/ui/Tick_Mark-10.png") end
    end
    if bow:isRoundChambered() then
        local nocked = bow:getModData().fl_nocked or F.bowArrow(bow)
        local info = sub:addOption(getText("IGUI_Fletcher_Nocked", getItemNameFromFullType(nocked)), nil, nil)
        info.notAvailable = true
    end
end

Events.OnFillInventoryObjectContextMenu.Add(function(...) F.onBowContextMenu(...) end)

local nextRemote = 0
function F.onBowTick()
    if not isClient() then return end
    local now = getTimestampMs()
    if now < nextRemote then return end
    nextRemote = now + 500
    pcall(F.syncRemoteBows)
end

Events.OnTick.Add(function() F.onBowTick() end)

-- Zombies with a bow or crossbow on the back (shared/Fletcher/ZombieGear.lua): the game draws it
-- with the script's WeaponSprite (a bow's is invisible), and every client has its own copy of the
-- item, so each side swaps in the back models itself, about once a second.
F.ZOMBIE_SPRITE_MS = 1000
local nextZombies = 0
function F.syncZombieBows()
    local zl = getCell() and getCell():getZombieList()
    local n = 0
    for i = 0, (zl and zl:size() or 0) - 1 do
        local z = zl:get(i)
        local list = z:getAttachedItems()
        if list and list:size() > 0 and F.syncAttachedSprites(z, nil) then
            z:resetModelNextFrame()
            n = n + 1
        end
    end
    return n
end

function F.onZombieBowsTick()
    local now = getTimestampMs()
    if now < nextZombies then return end
    nextZombies = now + F.ZOMBIE_SPRITE_MS
    pcall(F.syncZombieBows)
end

Events.OnTick.Add(function() F.onZombieBowsTick() end)

-- Every tick for the local player(s). Not OnPlayerUpdate: a multiplayer client never fires it for
-- its own player (counted on 42.21), so nothing here would run in multiplayer.
function F.onLocalBowsTick()
    for i = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(i)
        if p and p:isLocalPlayer() then F.onBowPlayerUpdate(p) end
    end
end

Events.OnTick.Add(function() F.onLocalBowsTick() end)    -- by name: reloads apply

return F
