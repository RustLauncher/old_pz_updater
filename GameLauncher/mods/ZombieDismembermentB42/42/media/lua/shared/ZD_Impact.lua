ZD_Impact = ZD_Impact or {}
local I = ZD_Impact
local function norm(value)
    local s = string.lower(tostring(value or ""))
    s = s:match("([^.:/]+)$") or s
    return (s:gsub("[^%w]", ""))
end
function I.isFootwear(itemType, location)
    if string.find(tostring(itemType or ""), "ZombieDismemberment.", 1, true) == 1 then return false end
    local loc = norm(location)
    if loc == "shoes" or loc == "boots" or loc == "footwear" then return true end
    local t = norm(itemType)
    return t:find("^shoes") ~= nil or t:find("^shoe") ~= nil
        or t:find("^boots") ~= nil or t:find("^boot") ~= nil
end
local HEAD_LOCS = {
    hat=true, fullhat=true, mask=true, maskeyes=true, maskfull=true,
    eyes=true, ears=true, nose=true, lefteyebrow=true, righteyebrow=true,
    lip=true, tongue=true, neck=true, necktexture=true, necklace=true,
    necklacelong=true, jackethat=true, jackethatbulky=true, sweaterhat=true,
    makeupfullface=true, makeupeyes=true, makeupeyesshadow=true, makeuplips=true,
}

local function isHeadDamage(t)
    if not t:find("^zeddmg") then return false end
    local damage = t:sub(7)
    return damage:find("^head") ~= nil or damage:find("^skull") ~= nil
        or damage:find("^faceskull") ~= nil or damage:find("^shotgunface") ~= nil
        or damage:find("^bulletforehead") ~= nil or damage:find("^bulletface") ~= nil
        or damage == "bulletlefttemple" or damage == "bulletrighttemple"
        or damage:find("^mouth") ~= nil or damage:find("^neck") ~= nil
        or damage == "nochin" or damage == "nonose" or damage:find("^noear") ~= nil
end
function I.isHeadAccessory(itemType, location)
    if string.find(tostring(itemType or ""), "ZombieDismemberment.", 1, true) == 1 then return false end
    if HEAD_LOCS[norm(location)] then return true end
    local t = norm(itemType)
    return isHeadDamage(t) or t:find("^nosestud") ~= nil
        or t:find("^hat") ~= nil or t:find("^helmet") ~= nil
        or t:find("^glasses") ~= nil or t:find("^earring") ~= nil
        or t:find("^mask") ~= nil or t:find("^bandagehead") ~= nil
        or t:find("^bandageneck") ~= nil or t:find("^woundhead") ~= nil
        or t:find("^woundneck") ~= nil
end
local function objectMatches(object, predicate)
    local visual = instanceof(object, "ItemVisual")
    local itemType
    if visual then itemType = object:getItemType()
    else itemType = object:getFullType() end
    if not itemType then return false end
    local si = object:getScriptItem()
    local loc
    if visual then loc = si and si:getBodyLocation()
    else loc = object:getBodyLocation() or (si and si:getBodyLocation()) end
    loc = loc and loc:getTranslationName() or nil
    return predicate(itemType, loc)
end

function I.cleanup(character, predicate)
    local removed = 0
    local corpse = instanceof(character, "IsoDeadBody")
    local inv
    local visuals
    if corpse then inv = character:getContainer()
    else inv = character:getInventory(); visuals = character:getItemVisuals() end
    local hv = character:getHumanVisual()
    local lists = {visuals, hv and hv:getBodyVisuals()}
    for k = 1, 2 do
        local list = lists[k]
        if list then
            for i = list:size() - 1, 0, -1 do
                local obj = list:get(i)
                if objectMatches(obj, predicate) then list:remove(obj); removed = removed + 1 end
            end
        end
    end
    local worn = character:getWornItems()
    if worn then
        for i = worn:size() - 1, 0, -1 do
            local wi = worn:get(i)
            local item = wi and wi:getItem() or nil
            local loc = wi and wi:getLocation() or nil
            loc = loc and loc:getTranslationName() or nil
            if item and (predicate(item:getFullType(), loc) or objectMatches(item, predicate)) then
                worn:remove(item)
                if inv then inv:Remove(item) end
                removed = removed + 1
            end
        end
    end
    if inv then
        local items = inv:getItems()
        for i = items:size() - 1, 0, -1 do
            local item = items:get(i)
            if objectMatches(item, predicate) then inv:Remove(item); removed = removed + 1 end
        end
    end
    if predicate == I.isHeadAccessory then
        local attached = character:getAttachedItems()
        if attached then
            for i = attached:size() - 1, 0, -1 do
                local ai = attached:get(i)
                local loc = string.lower(tostring(ai:getLocation() or ""))
                if loc:find("head", 1, true) or loc:find("jaw", 1, true) or loc:find("mouth", 1, true) then
                    local item = ai:getItem(); attached:remove(item)
                    if inv and item then inv:Remove(item) end
                    removed = removed + 1
                end
            end
        end
        if not corpse then character:setJawStabAttach(false) end
    end
    if removed > 0 and not corpse then
        character:onWornItemsChanged()
        character:resetModelNextFrame()
    end
    return removed
end
function I.weaponKind(weapon)
    if not weapon or not instanceof(weapon, "HandWeapon") then return nil end
    local kind
    if weapon:isRanged() then
        local ammo = weapon:getAmmoType()
        if ammo and norm(ammo:getTranslationName()) == "shotgunshells" then kind = "Shotgun" end
    else
        local si = weapon:getScriptItem()
        if si and si:containsWeaponCategory(WeaponCategory.LONG_BLADE) then kind = "LongBlade"
        elseif si and si:containsWeaponCategory(WeaponCategory.AXE) then kind = "Axe" end
    end
    return kind
end
function I.decapitationChance(attacker, kind, baseChance, useStrength)
    local chance = math.max(0, math.min(100, tonumber(baseChance) or 5))
    if chance == 0 or chance == 100 then return chance end
    if useStrength and kind ~= "Shotgun" then
        local strength = attacker and tonumber(attacker:getPerkLevel(Perks.Strength)) or 5
        strength = math.max(0, math.min(10, strength))
        chance = chance * (0.5 + 0.1 * strength)
    end
    return math.max(0, math.min(100, chance))
end
return I
