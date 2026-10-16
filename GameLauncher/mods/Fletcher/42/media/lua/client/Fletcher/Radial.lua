--[[
    Fletcher: the reload radial menu (hold R; hold RB on a controller) in a bow's words.
    Vanilla builds it for guns: nocking is "Load Rounds", taking the arrow off is "Rack" (a nocked
    arrow is a chambered round). For our launchers each slice is relabelled after vanilla fills the
    menu: Nock Arrow / Unnock Arrow (bows), Load Bolt / Remove Bolt (crossbows), with a second line
    saying what's nocked or how many of the next arrow are carried. With one already nocked / loaded
    the load slice is left out (F.bowFull, shared/Fletcher/Reload.lua). The slices still run vanilla's
    commands (and so our Reload.lua wrappers).
    Then one slice per arrow / bolt type carried (its icon, how many, how many in the quiver, chosen /
    nocked) and "Best Available": picking one chooses it and nocks it (F.radialChooseArrow,
    client/Fletcher/Nock.lua). More than F.RADIAL_DIRECT types: one "Choose Arrow..." slice opens a
    ring of them (with Back). Mouse: click a slice; controller: point the stick, release RB.
    Wrapped once (ISFirearmRadialMenu.fl_wrapped); the wrapper calls F.relabelRadial by name.
]]

require "ISUI/ISFirearmRadialMenu"
require "Fletcher/Core"
require "Fletcher/Gear"
require "Fletcher/Reload"
require "Fletcher/FireLight"
local F = Fletcher

F.LIGHT_ICON = "media/ui/Fletcher/Radial_LightArrow.png"
F.RADIAL_DIRECT = 8          -- up to this many types carried: their slices go straight in the menu

local iconCache = {}
local function icon(arrowType)
    if iconCache[arrowType] == nil then
        local it = instanceItem(arrowType)
        iconCache[arrowType] = it and it:getTex() or false
    end
    return iconCache[arrowType] or nil
end

--- The arrow / bolt types of this launcher's family the character carries, best first
function F.carriedArrowTypes(character, bow)
    local out = {}
    for _, t in ipairs(F.arrowsByRank(F.familyOf(bow))) do
        if F.arrowCount(character, t) > 0 then out[#out + 1] = t end
    end
    return out
end

local function inQuiver(character, arrowType)
    local n = 0
    for _, q in ipairs(F.wornQuivers and F.wornQuivers(character) or {}) do n = n + q:getInventory():getCountType(arrowType) end
    return n
end

--- Slice text for an arrow type: its name, then how many (in the quiver), chosen / nocked
function F.arrowSliceText(character, bow, arrowType)
    local family = F.familyOf(bow)
    local line2 = getText("IGUI_Fletcher_Radial_Count", F.arrowCount(character, arrowType))
    local q = inQuiver(character, arrowType)
    if q > 0 then line2 = line2 .. "  " .. getText("IGUI_Fletcher_Radial_InQuiver", q) end
    local nocked = bow:isRoundChambered() and (bow:getModData().fl_nocked or F.bowArrow(bow)) or nil
    if nocked == arrowType then
        line2 = line2 .. "  " .. getText("IGUI_Fletcher_Radial_NockedTag")
    elseif F.preferredArrow(character, family) == arrowType then
        line2 = line2 .. "  " .. getText("IGUI_Fletcher_Radial_ChosenTag")
    end
    return getItemNameFromFullType(arrowType) .. "\n" .. line2
end

local function addTypeSlices(menu, character, bow, types)
    local family = F.familyOf(bow)
    local best = getText("IGUI_Fletcher_BestArrow")
    if not F.preferredArrow(character, family) then best = best .. "\n" .. getText("IGUI_Fletcher_Radial_ChosenTag") end
    menu:addSlice(best, icon(types[1]), F.radialChooseArrow, character, bow, nil)
    for _, t in ipairs(types) do
        menu:addSlice(F.arrowSliceText(character, bow, t), icon(t), F.radialChooseArrow, character, bow, t)
    end
end

--- "Choose Arrow...": the ring of every type carried, and Back (the reload menu again)
function F.openArrowRing(frm)
    local weapon = frm:getWeapon()
    if not (weapon and F.BOW_DEFS[weapon:getFullType()]) then return end
    local menu = getPlayerRadialMenu(frm.playerNum)
    menu:clear()
    addTypeSlices(menu, frm.character, weapon, F.carriedArrowTypes(frm.character, weapon))
    menu:addSlice(getText("IGUI_Fletcher_Radial_Back"), getTexture("media/ui/FirearmRadial_Rack.png"),
        function() frm:fillMenu(); frm:display() end)
    frm:display()
end

function F.addArrowSlices(frm, menu, weapon)
    local types = F.carriedArrowTypes(frm.character, weapon)
    if #types == 0 then return end
    if #types <= F.RADIAL_DIRECT then
        addTypeSlices(menu, frm.character, weapon, types)
    else
        local bolt = F.familyOf(weapon) == "bolt"
        menu:addSlice(getText(bolt and "IGUI_Fletcher_Radial_ChooseBolt" or "IGUI_Fletcher_Radial_ChooseArrow")
            .. "\n" .. getText("IGUI_Fletcher_Radial_TypesCarried", #types), icon(types[1]), F.openArrowRing, frm)
    end
end

local function firstLine(text)
    return text and (text:match("^([^\n]*)") or text) or nil
end

function F.radialInfo(character, bow)
    if bow:isRoundChambered() then
        return getText("IGUI_Fletcher_Nocked", getItemNameFromFullType(bow:getModData().fl_nocked or F.bowArrow(bow) or ""))
    end
    local t = F.bowArrow(bow)
    if not t then return "" end
    return getText("IGUI_Fletcher_Radial_Carried", F.arrowCount(character, t), getItemNameFromFullType(t))
end

function F.relabelRadial(frm)
    local weapon = frm.getWeapon and frm:getWeapon()
    if not (weapon and F.BOW_DEFS[weapon:getFullType()]) then return end
    local bolt = F.familyOf(weapon) == "bolt"
    local load = getText(bolt and "IGUI_Fletcher_Radial_LoadBolt" or "IGUI_Fletcher_Radial_Nock")
    local unload = getText(bolt and "IGUI_Fletcher_Radial_RemoveBolt" or "IGUI_Fletcher_Radial_Unnock")
    local labels = {
        [getText("IGUI_FirearmRadial_LoadRounds")] = load,
        [getText("IGUI_FirearmRadial_ChamberRound")] = load,
        [getText("IGUI_FirearmRadial_UnloadRounds")] = unload,
        [getText("IGUI_FirearmRadial_UnloadRound")] = unload,
        [getText("IGUI_FirearmRadial_Rack")] = unload,
    }
    local menu = getPlayerRadialMenu(frm.playerNum)
    local info = F.radialInfo(frm.character, weapon)
    -- full (one arrow / bolt at a time): no load slice. Rebuild the menu without it.
    local loads = { [getText("IGUI_FirearmRadial_LoadRounds")] = true, [getText("IGUI_FirearmRadial_ChamberRound")] = true }
    if F.bowFull(weapon) then
        local keep = {}
        for _, slice in ipairs(menu.slices) do
            if not loads[firstLine(slice.text) or ""] then keep[#keep + 1] = slice end
        end
        if #keep ~= #menu.slices then
            menu:clear()
            for _, sl in ipairs(keep) do
                local c = sl.command or {}
                menu:addSlice(sl.text, sl.texture, c[1], c[2], c[3], c[4], c[5], c[6], c[7])
            end
        end
    end
    -- relabel; two vanilla slices can map to the same action (Unload Rounds / Rack): keep the first
    local seen, keep, dup = {}, {}, false
    for _, slice in ipairs(menu.slices) do
        local label = labels[firstLine(slice.text) or ""]
        if label and seen[label] then
            dup = true
        elseif slice.text then          -- (vanilla's empty placeholder slices: dropped, the ring is ours)
            if label then
                seen[label] = true; slice.text = label .. "\n" .. info
                -- the load slice shows the arrow it will nock
                local loadSlice = label == load
                local t = loadSlice and F.arrowFor(frm.character, weapon)
                if t and icon(t) then slice.texture = icon(t) end
            end
            keep[#keep + 1] = slice
        end
    end
    menu:clear()
    -- an unlit fire arrow on the string: Light Arrow, first in the ring, with its own icon (FireLight.lua)
    if F.canLightArrow and F.canLightArrow(frm.character, weapon) then
        menu:addSlice(getText("IGUI_Fletcher_Radial_LightArrow") .. "\n" .. getText("IGUI_Fletcher_Radial_LightArrowInfo"),
            getTexture(F.LIGHT_ICON), F.queueLightArrow, frm.character, weapon)
    end
    for _, sl in ipairs(keep) do
        local c = sl.command or {}
        menu:addSlice(sl.text, sl.texture, c[1], c[2], c[3], c[4], c[5], c[6], c[7])
    end
    F.addArrowSlices(frm, menu, weapon)
end

if not ISFirearmRadialMenu.fl_wrapped then
    ISFirearmRadialMenu.fl_wrapped = true
    local fill = ISFirearmRadialMenu.fillMenu
    ISFirearmRadialMenu.fillMenu = function(self, ...)
        local r = fill(self, ...)
        local ok, err = pcall(F.relabelRadial, self)
        if not ok then print("[Fletcher] radial relabel: " .. tostring(err)) end
        return r
    end
end

return F
