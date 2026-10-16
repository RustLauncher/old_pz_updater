require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISCDFeedDog"
require "TimedActions/ISCDPetDog"
require "TimedActions/ISCDTreatDog"
require "TimedActions/ISCDMedicateDog"
require "TimedActions/ISCDWaterDog"
require "TimedActions/ISCDFillDish"
require "ISUI/Animal/ISAnimalContextMenu"
require "TimedActions/ISContextualActions"

CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

local function cdForEachCarriedItem(container, fn)
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        fn(item)
        if instanceof(item, "InventoryContainer") then
            local inner = item:getInventory()
            if inner then
                cdForEachCarriedItem(inner, fn)
            end
        end
    end
end

local function groupCarriedFoods(playerObj, accept, breedKey)
    local groups, order = {}, {}
    cdForEachCarriedItem(playerObj:getInventory(), function(item)
        if accept(item) then
            local key = item:getFullType()
            local g = groups[key]
            if g then
                g.count = g.count + 1
            else
                g = { item = item, count = 1, name = item:getName(), bad = CD.isBadDogFood(item, breedKey) }
                groups[key] = g
                order[#order + 1] = g
            end
        end
    end)
    table.sort(order, function(a, b) return a.name < b.name end)
    return order
end

local function isHandFood(item)
    return instanceof(item, "Food") and not item:isRotten() and item:getHungerChange() < 0
end

local function listFoods(playerObj, breedKey)
    return groupCarriedFoods(playerObj, isHandFood, breedKey)
end

local function cdFindWaterIn(container)
    local list = container:getAllWaterFluidSources(true)
    if list and list:size() > 0 then return list:get(0) end
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if instanceof(item, "InventoryContainer") then
            local inner = item:getInventory()
            local found = inner and cdFindWaterIn(inner)
            if found then return found end
        end
    end
    return nil
end

local function findWater(playerObj)
    return cdFindWaterIn(playerObj:getInventory())
end

local function onFeedDog(playerObj, animal, food)
    if not food then return end
    animal:stopAllMovementNow()
    if luautils.walkAdj(playerObj, animal:getSquare()) then
        ISTimedActionQueue.addGetUpAndThen(playerObj, ISCDFeedDog:new(playerObj, animal, food))
    end
end

local function cdApplyBadFoodCue(menu, opt, g, animal)
    if not (opt and g and g.bad) then return end
    opt.color = { r = 1, g = 0.35, b = 0.35 }
    if menu then
        menu.cdBadLabels = menu.cdBadLabels or {}
        menu.cdBadLabels[opt.name] = true
    end
    local tooltip = ISWorldObjectContextMenu.addToolTip()
    tooltip:setName(g.name)
    tooltip.description = "<RGB:1,0.35,0.35>" .. CD.speciesText(animal, "IGUI_PD_BadFood")
    opt.toolTip = tooltip
end

local function addFeedEntry(parent, playerObj, animal, labelText)
    local foods = listFoods(playerObj, animal and CD.getBreed(animal))
    if #foods == 0 then
        local opt = parent:addOption(labelText, nil, nil)
        opt.notAvailable = true
        local tooltip = ISWorldObjectContextMenu.addToolTip()
        tooltip:setName(getText("IGUI_PD_NeedFood"))
        opt.toolTip = tooltip
        return
    end
    if #foods == 1 then
        local opt = parent:addOption(labelText, playerObj, onFeedDog, animal, foods[1].item)
        opt.iconTexture = foods[1].item:getTexture()
        cdApplyBadFoodCue(parent, opt, foods[1], animal)
        return
    end
    local header = parent:addOption(labelText, nil, nil)
    local sub = ISContextMenu:getNew(parent)
    parent:addSubMenu(header, sub)
    for _, g in ipairs(foods) do
        local label = g.count > 1 and (g.name .. " (" .. g.count .. ")") or g.name
        local opt = sub:addOption(label, playerObj, onFeedDog, animal, g.item)
        opt.iconTexture = g.item:getTexture()
        cdApplyBadFoodCue(sub, opt, g, animal)
    end
end

---Stops the dog, walks next to it and queues the petting action.
---@param playerObj IsoPlayer
---@param animal IsoAnimal
function CD.startPet(playerObj, animal)
    if not playerObj or not animal then return end
    animal:stopAllMovementNow()
    if luautils.walkAdj(playerObj, animal:getSquare()) then
        -- addGetUpAndThen: interagir sentado no chao trava o ataque e deixa a endurance na taxa de sentado.
        ISTimedActionQueue.addGetUpAndThen(playerObj, ISCDPetDog:new(playerObj, animal))
    end
end

local onPetDog = CD.startPet

local function onWaterDog(playerObj, animal, item)
    if not item then return end
    animal:stopAllMovementNow()
    if luautils.walkAdj(playerObj, animal:getSquare()) then
        ISTimedActionQueue.addGetUpAndThen(playerObj, ISCDWaterDog:new(playerObj, animal, item))
    end
end

local function onSetState(animal, playerObj, state)
    CD.request("setstate", animal, { state = state }, playerObj)
end

local function onCome(animal, playerObj)
    CD.request("come", animal, nil, playerObj)
end

local function onSelectDog(animal, playerObj)
    CD.request("select", animal, nil, playerObj)
end

local function onDismissDog(animal, playerObj)
    CD.request("dismiss", animal, nil, playerObj)
end

local function onAttack(animal, playerObj)
    CD.request("attack", animal, nil, playerObj)
end

local CDGotoCursor

local function getGotoCursorClass()
    if CDGotoCursor then return CDGotoCursor end
    local cursor = ISBuildingObject:derive("CDGotoCursor")

    function cursor:isValid(square)
        if not square or not self.character then return false end
        if not CD.squareHasFloor(square) then return false end
        local dx = (square:getX() + 0.5) - self.character:getX()
        local dy = (square:getY() + 0.5) - self.character:getY()
        local maxd = CD.TRICK_GOTO_MAX_DIST
        return (dx * dx + dy * dy) <= (maxd * maxd)
    end

    function cursor:render(x, y, z, square)
        local hc = self:isValid(square) and getCore():getGoodHighlitedColor() or getCore():getBadHighlitedColor()
        self:getFloorCursorSprite():RenderGhostTileColor(x, y, z, hc:getR(), hc:getG(), hc:getB(), 0.8)
    end

    function cursor:tryBuild(x, y, z)
        local square = getCell():getGridSquare(x, y, z)
        if not self:isValid(square) then return nil end
        self:create(x, y, z, self.north, nil)
        return nil
    end

    function cursor:create(x, y, z)
        local dog = self.dog
        if dog then
            CD.request("trickgoto", dog, { x = x, y = y, z = z }, self.character)
        end
        getCell():setDrag(nil, self.player)
    end

    function cursor:new(character, dog)
        local o = {}
        setmetatable(o, self)
        self.__index = self
        o:init()
        o.character = character
        o.player = character:getPlayerNum()
        o.dog = dog
        o.noNeedHammer = true
        o.skipBuildAction = true
        return o
    end

    CDGotoCursor = cursor
    return cursor
end

---Runs the trick or shows why it is blocked; goto first picks the target tile with a cursor.
---@param playerObj IsoPlayer
---@param animal IsoAnimal
---@param trickId string
function CD.startTrick(playerObj, animal, trickId)
    local def = CD.trickDef(trickId)
    if not playerObj or not animal or not def then return end
    local why, a1 = CD.trickBlockReason(animal, def, playerObj)
    if why then
        local msg
        if why == "IGUI_PD_TrickLocked" then
            msg = getText("IGUI_PD_TrickLockedHalo", CD.data(animal).name or CD.breedNoun(animal), a1)
        else
            msg = CD.speciesText(animal, why)
        end
        HaloTextHelper.addBadText(playerObj, msg)
        return
    end
    if trickId == "goto" then
        local cls = getGotoCursorClass()
        getCell():setDrag(cls:new(playerObj, animal), playerObj:getPlayerNum())
        HaloTextHelper.addText(playerObj, CD.speciesText(animal, "IGUI_PD_TrickGotoPick"))
        return
    end
    CD.request(CD.trickCommandFor(animal, def), animal, nil, playerObj)
end

local function onTrick(animal, playerObj, trickId)
    CD.startTrick(playerObj, animal, trickId)
end

local function addTrickOption(menu, playerObj, animal, def, extra)
    local label = CD.trickLabel(animal, def)
    local why, a1, a2 = CD.trickBlockReason(animal, def, playerObj)
    if not why then
        local opt = menu:addOption(label, animal, onTrick, playerObj, def.id, extra)
        local tip = ISWorldObjectContextMenu.addToolTip()
        tip:setName(label)
        tip.description = CD.trickDescription(animal, def)
        opt.toolTip = tip
        return opt
    end
    local opt = menu:addOption(label, nil, nil)
    opt.notAvailable = true
    menu.cdBadLabels = menu.cdBadLabels or {}
    menu.cdBadLabels[label] = true
    local tip = ISWorldObjectContextMenu.addToolTip()
    tip:setName(label)
    tip.description = CD.speciesText(animal, why, a1, a2)
    opt.toolTip = tip
    return opt
end

local function addTricksMenu(context, menu, playerObj, animal)
    if not CD.tricksEnabled() then return end
    local tricks = CD.tricksFor(animal)
    if #tricks == 0 then return end
    local header = menu:addOption(getText("IGUI_PD_TrickRoot"), nil, nil)
    local sub = ISContextMenu:getNew(menu)
    context:addSubMenu(header, sub)
    for _, def in ipairs(tricks) do
        addTrickOption(sub, playerObj, animal, def, nil)
    end
end

local function onCareConfirm(target, button)
    local internal = (type(button) == "table") and button.internal or button
    if internal == "YES" and target and target.animal then
        CD.request("setcaremode", target.animal, { on = true }, target.player)
    end
end

local function onToggleCare(animal, playerObj)
    local on = false
    if animal then
        on = CD.getCareMode(animal)
    end
    if on then
        CD.request("setcaremode", animal, { on = false }, playerObj)
        return
    end
    local nm = ""
    if animal then
        nm = CD.data(animal).name or CD.breedNoun(animal)
    end
    local modal = ISModalDialog:new(0, 0, 380, 160,
        getText("IGUI_PD_CareDeselectConfirm", nm), true, { animal = animal, player = playerObj }, onCareConfirm,
        playerObj and playerObj:getPlayerNum() or 0)
    modal:initialise()
    modal:addToUIManager()
end

local function onInspect(animal, playerObj)
    ISCDStatusWindow.OpenFor(animal, nil, playerObj)
end

local CD_SCAN_DIST = 5

local function onScanStray(animal, playerObj)
    CD.openStrayScan(animal, playerObj)
end

local function onReleaseConfirm(target, button)
    local internal = (type(button) == "table") and button.internal or button
    if internal == "YES" and target and target.animal then
        CD.request("release", target.animal, nil, target.player)
    end
end

local function onRelease(animal, playerObj)
    local nm = ""
    if animal then
        nm = CD.data(animal).name or CD.breedNoun(animal)
    end
    local pnum = playerObj and playerObj:getPlayerNum() or 0
    local text = getText("IGUI_PD_ReleaseConfirm", nm) .. "\n" .. getText("IGUI_PD_ReleaseWarn")
    -- x/y zero faz o ISModalDialog abrir em cima do mouse, que no clique de contexto pode ser a beirada.
    local w, h = ISModalDialog.CalcSize(380, 160, text)
    local x = getPlayerScreenLeft(pnum) + (getPlayerScreenWidth(pnum) - w) / 2
    local y = getPlayerScreenTop(pnum) + (getPlayerScreenHeight(pnum) - h) / 2
    local modal = ISModalDialog:new(math.max(1, x), math.max(1, y), w, h, text,
        true, { animal = animal, player = playerObj }, onReleaseConfirm, pnum)
    modal:initialise()
    modal:addToUIManager()
end

local function onCarry(animal, playerObj)
    AnimalContextMenu.onPickupAnimal(animal, playerObj)
end

local function onRenameApply(_, button, animal, playerObj)
    if button.internal == "OK" then
        CD.request("rename", animal, { text = button.parent.entry:getText() }, playerObj)
    end
end

local function onRename(animal, playerObj)
    local modal = ISTextBox:new(0, 0, 290, 180, getText("IGUI_PD_RenameTitle", CD.breedNoun(animal)),
        CD.data(animal).name or "", nil, onRenameApply, playerObj:getPlayerNum(), animal, playerObj)
    modal:initialise()
    modal:addToUIManager()
end

local function onForceBreed(animal, playerObj) CD.request("forcebreed", animal, nil, playerObj) end
local function onForceWhelp(animal, playerObj) CD.request("forcewhelp", animal, nil, playerObj) end
local function onMaturePup(animal, playerObj) CD.request("maturepup", animal, nil, playerObj) end

local function onToggleBreeding(animal, playerObj)
    CD.request("setbreedmode", animal, { off = not (CD.data(animal).breedingOff == true) }, playerObj)
end

local function onToggleGrowth(animal, playerObj)
    CD.request("setgrowthmode", animal, { paused = not (CD.data(animal).growthPaused == true) }, playerObj)
end

local function onDebugTokens(animal, playerObj)
    local pd = CD.playerData(playerObj)
    local n = 0
    if type(pd.companions) == "table" then
        for _ in pairs(pd.companions) do n = n + 1 end
    end
    local act = (CD.data(animal).companionToken ~= nil and CD.data(animal).companionToken == pd.token)
    HaloTextHelper.addText(playerObj, "dog=" .. tostring(CD.data(animal).companionToken)
        .. " active=" .. tostring(pd.token) .. " isActive=" .. tostring(act) .. " count=" .. tostring(n))
end

local HUNT_DIAG_TINY = { "mouse", "rat", "squirrel" }
local HUNT_DIAG_SMALL = { "rab", "raccoon" }
local HUNT_DIAG_LARGE = { fawn = true, doe = true, buck = true, deer = true }
local function huntDiagClass(t)
    if not t then return "?", nil end
    if HUNT_DIAG_LARGE[t] then return "LARGE(L6)", "large" end
    for _, p in ipairs(HUNT_DIAG_TINY) do
        if string.sub(t, 1, string.len(p)) == p then return "tiny(L3)", "tiny" end
    end
    for _, p in ipairs(HUNT_DIAG_SMALL) do
        if string.sub(t, 1, string.len(p)) == p then return "small(L3)", "small" end
    end
    return "UNHUNTABLE", nil
end

local function onHuntDiag(animal, playerObj)
    local lvl = CD.getSkillLevel(animal, "hunt")
    local cell = getCell()
    local ax, ay = math.floor(animal:getX()), math.floor(animal:getY())
    local az = math.floor(animal:getZ())
    local found = {}
    if cell then
        for dx = -20, 20 do
            for dy = -20, 20 do
                local sq = cell:getGridSquare(ax + dx, ay + dy, az)
                local list = sq and sq:getAnimals()
                if list then
                    for i = 0, list:size() - 1 do
                        local o = list:get(i)
                        local wild = o:isWild()
                        local t = o:getAnimalType()
                        if t then
                            local lbl, cls = huntDiagClass(t)
                            local capped = cls ~= nil and not CD.breedCanHuntClass(animal, cls)
                            local k = t .. (wild and "" or "[tame]") .. " " .. lbl .. (capped and "[teto]" or "")
                            found[k] = (found[k] or 0) + 1
                        end
                    end
                end
            end
        end
    end
    local s = "Caca lvl=" .. tostring(lvl)
    local any = false
    for k, c in pairs(found) do
        s = s .. " | " .. k .. " x" .. c
        any = true
    end
    if not any then
        s = s .. " | nenhum animal num raio de 20"
    end
    HaloTextHelper.addText(playerObj, s)
end

local function onGrowthDiag(animal, playerObj)
    local d = CD.data(animal)
    local t = animal:getAnimalType() or "?"
    local days = "?"
    local dt = animal:getData()
    if dt then
        days = dt:getDaysSurvived()
    end
    local hrs = string.format("%.0f", animal:getHoursSurvived())
    local s = "type=" .. tostring(t) .. " pup=" .. tostring(d.isPup == true) .. " sex=" .. tostring(d.sex)
        .. " days=" .. tostring(days) .. " hrs=" .. tostring(hrs) .. " engGrow@90"
    if d.isPup then
        local mins = CD.maturityMinutes()
        local remain = ((d.bornMin or 0) + mins - CD.worldMinutes()) / 1440
        s = s .. string.format(" matura_em=%.2fd", remain)
        if d.growthPaused then
            s = s .. " [PAUSADO]"
        end
    end
    HaloTextHelper.addText(playerObj, s)
end

local function onDeleteDog(animal, playerObj)
    CD.request("deletedog", animal, nil, playerObj)
end

local function onDeleteAllConfirm(target, button)
    local internal = (type(button) == "table") and button.internal or button
    if internal == "YES" and target then
        CD.request("deletealldogs", nil, {}, target.player)
    end
end

local function onWipeApopConfirm(target, button)
    local internal = (type(button) == "table") and button.internal or button
    if internal == "YES" and target then
        CD.request("wipedogsapop", nil, { skipload = true }, target.player)
    end
end

local function onWipeApop(_, playerObj)
    local modal = ISModalDialog:new(0, 0, 440, 200,
        "Sweep EVERY animal cell on disk and delete every dog found, anywhere in the save, including dogs far from " ..
        "any player? This runs in the background and can take a while. Save the game afterwards. This cannot be undone.",
        true, { player = playerObj }, onWipeApopConfirm,
        playerObj and playerObj:getPlayerNum() or 0)
    modal:initialise()
    modal:addToUIManager()
end

local function onDeleteAllDogs(_, playerObj)
    local modal = ISModalDialog:new(0, 0, 440, 200,
        "Delete EVERY dog in the whole save: all owners, strays included, loaded or not, plus kennel and " ..
        "vehicle records? The far-away part runs in the background; save the game when it reports done. " ..
        "Use this before removing the mod from a save. This cannot be undone.",
        true, { player = playerObj }, onDeleteAllConfirm,
        playerObj and playerObj:getPlayerNum() or 0)
    modal:initialise()
    modal:addToUIManager()
end

local function cdDebugRoot(context)
    local opt = context:getOptionFromName(getText("IGUI_PD_DebugRoot"))
    if opt and opt.subOption then
        local existing = context:getSubMenu(opt.subOption)
        if existing then return existing end
    end
    local header = context:addOption(getText("IGUI_PD_DebugRoot"), nil, nil)
    local menu = ISContextMenu:getNew(context)
    context:addSubMenu(header, menu)
    return menu
end

local function cdDebugSection(context, label)
    local root = cdDebugRoot(context)
    local opt = root:getOptionFromName(label)
    if opt and opt.subOption then
        local existing = root:getSubMenu(opt.subOption)
        if existing then return existing end
    end
    local header = root:addOption(label, nil, nil)
    local sub = ISContextMenu:getNew(root)
    root:addSubMenu(header, sub)
    return sub
end

local function cdDebugTouchSections(context, dbg, adm)
    if dbg then
        cdDebugSection(context, "Spawn")
    end
    if dbg or adm then
        cdDebugSection(context, "Tools")
    end
end

local function addDebugEntry(parent, playerObj, animal, multi)
    if not CD.debugAllowed() then return end
    cdDebugTouchSections(parent, true, CD.adminAllowed())
    local tools = cdDebugSection(parent, "Tools")
    local label = "Dog"
    if multi then
        local nm = ""
        if animal then
            nm = CD.data(animal).name or CD.breedNoun(animal)
        end
        label = "Dog: " .. tostring(nm)
    end
    tools:addOption("Delete " .. (multi and label or "this dog"), animal, onDeleteDog, playerObj)
    local sub = cdDebugSection(parent, label)
    sub:addOption("Status editor", animal, ISCDDogEditor.open, playerObj)
    sub:addOption("Health status", animal, ISCDHealthDebugWindow.open, playerObj)
    sub:addOption("Tokens", animal, onDebugTokens, playerObj)
    sub:addOption("Hunt diag", animal, onHuntDiag, playerObj)
    sub:addOption("Growth diag", animal, onGrowthDiag, playerObj)

    local brHeader = sub:addOption("Breeding", nil, nil)
    local brSub = ISContextMenu:getNew(sub)
    sub:addSubMenu(brHeader, brSub)
    brSub:addOption("Force pregnancy (nearest dog)", animal, onForceBreed, playerObj)
    brSub:addOption("Whelp now", animal, onForceWhelp, playerObj)
    brSub:addOption("Mature pup", animal, onMaturePup, playerObj)
end

local function onSpawnDog(_, playerObj, square, atype, kind)
    if not square then return end
    CD.request("spawn", nil, { type = atype, kind = kind, x = square:getX(), y = square:getY(), z = square:getZ() }, playerObj)
end

local function onSpawnRandomApply(_, button, playerObj, square)
    if button.internal ~= "OK" then return end
    local n = tonumber(button.parent.entry:getText())
    if not n then return end
    CD.request("spawnrandom", nil, { n = n, x = square:getX(), y = square:getY(), z = square:getZ() }, playerObj)
end

local function onSpawnRandom(_, playerObj, square)
    if not square then return end
    local modal = ISTextBox:new(0, 0, 290, 180,
        "How many dogs? 1 to " .. tostring(CD.SPAWN_RANDOM_MAX) .. ", random breed and sex.",
        "5", nil, onSpawnRandomApply, playerObj:getPlayerNum(), playerObj, square)
    modal:initialise()
    modal.entry:setOnlyNumbers(true)
    modal:addToUIManager()
end

local function onResetSpawns(_, playerObj)
    CD.request("resetspawns", nil, {}, playerObj)
end

local function onEquipBag(animal, playerObj, bagItem)
    if not animal or not bagItem then return end
    CD.request("equipsaddlebag", animal, { itemId = bagItem:getID() }, playerObj)
end

local function onUnequipBag(animal, playerObj)
    if not animal then return end
    CD.request("unequipsaddlebag", animal, {}, playerObj)
end

local function onOpenBag(animal, playerObj)
    if not animal then return end
    CD.openBagWindow(animal, playerObj)
end

local function findDisinfectant(playerObj)
    local found = nil
    cdForEachCarriedItem(playerObj:getInventory(), function(item)
        if not found and CD.isDisinfectant(item) then
            found = item
        end
    end)
    return found
end

local function listBandages(playerObj)
    local seen, order = {}, {}
    cdForEachCarriedItem(playerObj:getInventory(), function(item)
        if CD.isDogBandage(item) and not seen[item:getFullType()] then
            seen[item:getFullType()] = true
            order[#order + 1] = item
        end
    end)
    table.sort(order, function(a, b)
        if a:isAlcoholic() ~= b:isAlcoholic() then return a:isAlcoholic() end
        return a:getBandagePower() > b:getBandagePower()
    end)
    return order
end

local function onTreatDog(animal, playerObj, bandage)
    if not (animal and bandage) then return end
    animal:stopAllMovementNow()
    if not luautils.walkAdj(playerObj, animal:getSquare()) then return end
    ISTimedActionQueue.addGetUpAndThen(playerObj, ISCDTreatDog:new(playerObj, animal, bandage, findDisinfectant(playerObj)))
end

local function listMedicines(playerObj, animal)
    local seen, order = {}, {}
    cdForEachCarriedItem(playerObj:getInventory(), function(item)
        local ft = item:getFullType()
        if not seen[ft] and CD.vetMedicineApplies(animal, ft) then
            seen[ft] = true
            order[#order + 1] = item
        end
    end)
    return order
end

local function onMedicateDog(animal, playerObj, item)
    if not (animal and item) then return end
    animal:stopAllMovementNow()
    if not luautils.walkAdj(playerObj, animal:getSquare()) then return end
    ISTimedActionQueue.addGetUpAndThen(playerObj, ISCDMedicateDog:new(playerObj, animal, item))
end

local function listBaths(playerObj, animal)
    local seen, order = {}, {}
    cdForEachCarriedItem(playerObj:getInventory(), function(item)
        local ft = item:getFullType()
        if not seen[ft] and CD.vetBathApplies(animal, ft) and item:getCurrentUsesFloat() > 0 then
            seen[ft] = true
            order[#order + 1] = item
        end
    end)
    return order
end

local function onBathDog(animal, playerObj, item)
    if not (animal and item) then return end
    animal:stopAllMovementNow()
    if not luautils.walkAdj(playerObj, animal:getSquare()) then return end
    ISTimedActionQueue.addGetUpAndThen(playerObj, ISCDBathDog:new(playerObj, animal, item))
end

local function onUndressDog(animal, playerObj)
    if not animal then return end
    animal:stopAllMovementNow()
    if not luautils.walkAdj(playerObj, animal:getSquare()) then return end
    CompanionDogs.request("vetundress", animal, {}, playerObj)
end

-- As acoes de saude moram na secao Saude da ficha, aberta pelo clique, como o painel de saude do jogo.
---@param menu ISContextMenu
---@param playerObj IsoPlayer
---@param animal IsoAnimal
function CD.buildTreatMenu(menu, playerObj, animal)
    if not CD.vetCareEnabled() then return end
    local wounded = CD.vetCondition(animal) == "cut"
    if wounded and (CD.data(animal).vetDress or 0) >= 1 then
        menu:addOption(getText("IGUI_PD_RemoveDressing"), animal, onUndressDog, playerObj)
    end
    if wounded then
        local bandages = listBandages(playerObj)
        local disinfect = findDisinfectant(playerObj)
        if #bandages == 0 then
            local opt = menu:addOption(getText("IGUI_PD_TreatWound"), animal, nil)
            opt.notAvailable = true
            local tip = ISWorldObjectContextMenu.addToolTip()
            tip:setName(getText("IGUI_PD_NeedBandage"))
            opt.toolTip = tip
        end
        for _, item in ipairs(bandages) do
            local name = getText("IGUI_PD_TreatWound") .. ": " .. item:getName()
            if disinfect and not item:isAlcoholic() and item:getBandagePower() >= 1 then
                name = name .. " + " .. disinfect:getName()
            end
            local opt = menu:addOption(name, animal, onTreatDog, playerObj, item)
            opt.iconTexture = item:getTexture()
        end
    end
    for _, item in ipairs(listMedicines(playerObj, animal)) do
        local def = CD.vetMedicineDef(item:getFullType())
        local label = item:getName()
        if def.menuKey then
            label = getText(def.menuKey)
        end
        local opt = menu:addOption(label, animal, onMedicateDog, playerObj, item)
        opt.iconTexture = item:getTexture()
    end
    local baths = listBaths(playerObj, animal)
    if #baths == 0 then return end
    local water, cloth = CD.vetBathKit(playerObj:getInventory())
    for _, item in ipairs(baths) do
        local opt = menu:addOption(getText("IGUI_PD_VetBath") .. ": " .. item:getName(), animal, onBathDog, playerObj, item)
        opt.iconTexture = item:getTexture()
        if not (water and cloth) then
            opt.notAvailable = true
            local tip = ISWorldObjectContextMenu.addToolTip()
            tip:setName(getText("IGUI_PD_VetBathNeed"))
            opt.toolTip = tip
        end
    end
end

local function addTreatEntry(parent, playerObj, animal)
    if not CD.vetCareEnabled() then return end
    if CD.vetCondition(animal) ~= "cut" and #listMedicines(playerObj, animal) == 0
        and #listBaths(playerObj, animal) == 0 then return end
    local header = parent:addOption(getText("IGUI_PD_TreatWound"), nil, nil)
    local sub = ISContextMenu:getNew(parent)
    parent:addSubMenu(header, sub)
    CD.buildTreatMenu(sub, playerObj, animal)
end

local function addCareEntry(menu, playerObj, animal)
    if not CD.careEnabled() or not CD.breedCanTendLivestock(animal) then return end
    local caring = CD.getCareMode(animal)
    local clbl = caring and getText("IGUI_PD_CareStop") or getText("IGUI_PD_CareStart")
    local cOpt = menu:addOption(clbl, animal, onToggleCare, playerObj)
    local cTip = ISWorldObjectContextMenu.addToolTip()
    cTip:setName(clbl)
    cTip.description = getText("IGUI_PD_CareModeDesc", CD.breedNoun(animal))
    if not caring then
        cTip.description = cTip.description .. " " .. getText("IGUI_PD_CareDeselectWarn")
    end
    cOpt.toolTip = cTip
end

local function identityBits(animal)
    local breedTxt = CD.breedNoun(animal)
    if CD.isMongrel(animal) then
        breedTxt = breedTxt .. " (" .. getText("IGUI_PD_Mestico") .. ")"
    end
    local bits = { breedTxt }
    local sx = CD.sexNoun(animal)
    if sx then
        bits[#bits + 1] = sx
    end
    return bits
end

local function onAnimalMenu(player, context, animals)
    local playerObj = getSpecificPlayer(player)
    if not playerObj then return end
    local dogCount = 0
    for _, animal in ipairs(animals) do
        if CD.isDog(animal) then
            dogCount = dogCount + 1
        end
    end
    for _, animal in ipairs(animals) do
        if CD.isDog(animal) then
            addDebugEntry(context, playerObj, animal, dogCount > 1)
            if CD.isCompanion(animal) and CD.isOwnedBy(animal, playerObj) then
                local name = CD.data(animal).name or CD.breedNoun(animal)
                if CD.isPregnant(animal) then
                    name = name .. " (" .. CD.pregnancyLabel(animal) .. ")"
                end
                local header = context:addOption(name, nil, nil)
                local menu = ISContextMenu:getNew(context)
                context:addSubMenu(header, menu)
                do
                    local bits = identityBits(animal)
                    if CD.isPuppy(animal) then
                        bits[#bits + 1] = CD.youngNoun(animal)
                    end
                    if CD.isPregnant(animal) then
                        bits[#bits + 1] = CD.pregnancyLabel(animal)
                    end
                    local infoOpt = menu:addOption(table.concat(bits, ", "), nil, nil)
                    infoOpt.notAvailable = true
                end
                if CD.animalSex(animal) ~= "pup" and CD.breedCanBreed(animal) then
                    local off = CD.data(animal).breedingOff == true
                    local lbl = off and getText("IGUI_PD_BreedingEnable") or getText("IGUI_PD_BreedingDisable")
                    menu:addOption(lbl, animal, onToggleBreeding, playerObj)
                end
                if CD.isPuppy(animal) then
                    local paused = CD.data(animal).growthPaused == true
                    local glbl = paused and getText("IGUI_PD_ResumeGrowth") or getText("IGUI_PD_PauseGrowth")
                    local gOpt = menu:addOption(glbl, animal, onToggleGrowth, playerObj)
                    local gTip = ISWorldObjectContextMenu.addToolTip()
                    gTip.description = CD.speciesText(animal, "IGUI_PD_PauseGrowthTip")
                    gOpt.toolTip = gTip
                end
                local tok = CD.data(animal).companionToken
                local active = tok ~= nil and tok == CD.playerData(playerObj).token
                if not active then
                    menu:addOption(getText("IGUI_PD_Select", name), animal, onSelectDog, playerObj)
                    if CD.bondingEnabled() then
                        menu:addOption(getText("IGUI_PD_Pet"), playerObj, onPetDog, animal)
                    end
                    addCareEntry(menu, playerObj, animal)
                    menu:addOption(getText("IGUI_PD_Inspect"), animal, onInspect, playerObj)
                    menu:addOption(getText("IGUI_PD_Rename"), animal, onRename, playerObj)
                    menu:addOption(getText("IGUI_PD_Carry"), animal, onCarry, playerObj)
                    menu:addOption(getText("IGUI_PD_Release"), animal, onRelease, playerObj)
                else
                    addFeedEntry(menu, playerObj, animal, getText("IGUI_PD_FeedCompanion"))
                    local water = findWater(playerObj)
                    local waterOpt = menu:addOption(getText("IGUI_PD_Water"), playerObj, onWaterDog, animal, water)
                    if not water then
                        waterOpt.notAvailable = true
                        local tooltip = ISWorldObjectContextMenu.addToolTip()
                        tooltip:setName(getText("IGUI_PD_NeedWater"))
                        waterOpt.toolTip = tooltip
                    end
                    if CD.bondingEnabled() then
                        menu:addOption(getText("IGUI_PD_Pet"), playerObj, onPetDog, animal)
                    end
                    addTreatEntry(menu, playerObj, animal)
                    if CD.getState(animal) == CD.STATE_FOLLOW then
                        menu:addOption(getText("IGUI_PD_Stay"), animal, onSetState, playerObj, CD.STATE_STAY)
                    else
                        menu:addOption(getText("IGUI_PD_Follow"), animal, onSetState, playerObj, CD.STATE_FOLLOW)
                    end
                    menu:addOption(getText("IGUI_PD_CmdCome"), animal, onCome, playerObj)
                    if CD.combatEnabled() and CD.breedCanFight(animal) then
                        menu:addOption(getText("IGUI_PD_CmdAttack"), animal, onAttack, playerObj)
                    end
                    addTricksMenu(context, menu, playerObj, animal)
                    addCareEntry(menu, playerObj, animal)
                    if CD.hasBag(animal) then
                        menu:addOption(getText("IGUI_PD_OpenBag"), animal, onOpenBag, playerObj)
                        menu:addOption(getText("IGUI_PD_UnequipBag"), animal, onUnequipBag, playerObj)
                    else
                        local bag = CD.findBagItem(playerObj)
                        if bag then
                            menu:addOption(getText("IGUI_PD_EquipBag"), animal, onEquipBag, playerObj, bag)
                        end
                    end
                    menu:addOption(getText("IGUI_PD_Inspect"), animal, onInspect, playerObj)
                    menu:addOption(getText("IGUI_PD_Rename"), animal, onRename, playerObj)
                    local dOpt = menu:addOption(getText("IGUI_PD_Dismiss", name), animal, onDismissDog, playerObj)
                    local dTip = ISWorldObjectContextMenu.addToolTip()
                    dTip:setName(getText("IGUI_PD_Dismiss", name))
                    dTip.description = getText("IGUI_PD_DismissTip", CD.breedNoun(animal))
                    dOpt.toolTip = dTip
                    menu:addOption(getText("IGUI_PD_Carry"), animal, onCarry, playerObj)
                    menu:addOption(getText("IGUI_PD_Release"), animal, onRelease, playerObj)
                end
            elseif not CD.isCompanion(animal) then
                do
                    local bits = identityBits(animal)
                    bits[#bits + 1] = CD.ageNoun(animal)
                    local idOpt = context:addOption(table.concat(bits, ", "), nil, nil)
                    idOpt.notAvailable = true
                end
                local scanOpt = context:addOption(CD.speciesText(animal, "IGUI_PD_ScanStray"), animal, onScanStray, playerObj)
                local sq = animal:getCurrentSquare()
                if not sq or sq:DistToProper(playerObj) > CD_SCAN_DIST then
                    scanOpt.notAvailable = true
                    local tooltip = ISWorldObjectContextMenu.addToolTip()
                    tooltip:setName(getText("IGUI_PD_ScanTooFar"))
                    scanOpt.toolTip = tooltip
                end
                if CD.atCompanionLimit(playerObj) then
                    local label = getText("IGUI_PD_Feed")
                    local opt = context:addOption(label, nil, nil)
                    opt.notAvailable = true
                    context.cdBadLabels = context.cdBadLabels or {}
                    context.cdBadLabels[label] = true
                    local tooltip = ISWorldObjectContextMenu.addToolTip()
                    tooltip:setName(getText("IGUI_PD_FeedLimit", tostring(CD.maxCompanions())))
                    opt.toolTip = tooltip
                else
                    addFeedEntry(context, playerObj, animal, getText("IGUI_PD_Feed"))
                end
            end
        end
    end
end

local function onWorldMenu(player, context, worldobjects)
    local dbg = CD.debugAllowed()
    local adm = CD.adminAllowed()
    if not (dbg or adm) then return end
    local playerObj = getSpecificPlayer(player)
    if not playerObj then return end

    local square
    for _, o in ipairs(worldobjects) do
        if o:getSquare() then
            square = o:getSquare()
            break
        end
    end
    square = square or playerObj:getCurrentSquare()
    if not square then return end

    cdDebugTouchSections(context, dbg, adm)
    if dbg then
        local spawn = cdDebugSection(context, "Spawn")
        for _, breedKey in ipairs(CD.BREED_ORDER) do
            local noun = CD.breedNounFromKey(breedKey)
            spawn:addOption(getText("IGUI_PD_SpawnBreedMale", noun), worldobjects, onSpawnDog, playerObj, square, CD.breedAnimalType(breedKey, "male"), breedKey)
            spawn:addOption(getText("IGUI_PD_SpawnBreedFemale", noun), worldobjects, onSpawnDog, playerObj, square, CD.breedAnimalType(breedKey, "female"), breedKey)
        end
        local tools = cdDebugSection(context, "Tools")
        local resetOpt = tools:addOption(getText("IGUI_PD_ResetSpawns"), worldobjects, onResetSpawns, playerObj)
        local resetTip = ISWorldObjectContextMenu.addToolTip()
        resetTip.description = getText("IGUI_PD_ResetSpawnsTip")
        resetOpt.toolTip = resetTip
        tools:addOption(getText("IGUI_PD_AdminKennel"), playerObj, function(p) CD.openAdminKennel(p) end)
        local delOpt = tools:addOption("Delete ALL dogs (whole save)", worldobjects, onDeleteAllDogs, playerObj)
        local delTip = ISWorldObjectContextMenu.addToolTip()
        delTip.description = "Deletes every dog in the save: the loaded ones right away, then sweeps the animal cells on disk for the ones far from any player. Save the game when it reports done."
        delOpt.toolTip = delTip
        local apopOpt = tools:addOption("Sweep disk only (skip loaded dogs)", worldobjects, onWipeApop, playerObj)
        local apopTip = ISWorldObjectContextMenu.addToolTip()
        apopTip.description = "Only the disk part of the command above. For re-running the sweep without touching the dogs currently in the world."
        apopOpt.toolTip = apopTip
    end
    if adm then
        local tools = cdDebugSection(context, "Tools")
        local randOpt = tools:addOption("Spawn random dogs (max " .. tostring(CD.SPAWN_RANDOM_MAX) .. ")...",
            worldobjects, onSpawnRandom, playerObj, square)
        local randTip = ISWorldObjectContextMenu.addToolTip()
        randTip.description = "Spawns up to " .. tostring(CD.SPAWN_RANDOM_MAX) ..
            " dogs at a time around this spot, each one a random breed and sex drawn from every breed installed on the server. " ..
            "A higher number is capped at " .. tostring(CD.SPAWN_RANDOM_MAX) .. "; run it again for more."
        randOpt.toolTip = randTip
        local tuneOpt = tools:addOption("Server tuning / performance", playerObj, CD.openTuningPanel)
        local tuneTip = ISWorldObjectContextMenu.addToolTip()
        tuneTip.description = "Live perf readout and the tick/region/sniff budgets, applied server-side."
        tuneOpt.toolTip = tuneTip
    end
end

if not ISContextMenu.cdRedRenderWrapped then
    local vanillaRender = ISContextMenu.render
    function ISContextMenu:render()
        local bad = self.cdBadLabels
        if not bad then return vanillaRender(self) end
        local origDrawText = self.drawText
        self.drawText = function(s, text, x, y, r, g, b, a, font)
            if text ~= nil and bad[text] then
                r, g, b = 1, 0.35, 0.35
            end
            return origDrawText(s, text, x, y, r, g, b, a, font)
        end
        vanillaRender(self)
        self.drawText = origDrawText
    end
    ISContextMenu.cdRedRenderWrapped = true
end

if not AnimalContextMenu.cd_doMenuWrapped then
    local vanillaDoMenu = AnimalContextMenu.doMenu
    AnimalContextMenu.doMenu = function(player, context, animal, test)
        if CD.isDog(animal) then
            return
        end
        return vanillaDoMenu(player, context, animal, test)
    end
    AnimalContextMenu.cd_doMenuWrapped = true
end

local function cdContextAxes(playerObj)
    local dir = playerObj:getForwardIsoDirection()
    local x, y = playerObj:getX(), playerObj:getY()
    local lx, ly = x - math.floor(x), y - math.floor(y)
    if dir == IsoDirections.NW then
        if ly < lx then return IsoDirections.N, IsoDirections.W end
        return IsoDirections.W, IsoDirections.N
    elseif dir == IsoDirections.NE then
        if ly < (1 - lx) then return IsoDirections.N, IsoDirections.E end
        return IsoDirections.E, IsoDirections.N
    elseif dir == IsoDirections.SE then
        if (1 - ly) < (1 - lx) then return IsoDirections.S, IsoDirections.E end
        return IsoDirections.E, IsoDirections.S
    elseif dir == IsoDirections.SW then
        if (1 - ly) < lx then return IsoDirections.S, IsoDirections.W end
        return IsoDirections.W, IsoDirections.S
    end
    return dir, nil
end

local function cdContextFallback(playerObj, dir)
    local square = playerObj:getCurrentSquare()
    local adjacent = square and square:getAdjacentSquare(dir)
    if not adjacent then return false end

    local bed = adjacent:getBed() or square:getBed()
    if bed then
        ContextualActionHandlers.SleepInBed(nil, playerObj, bed)
        return true
    end

    if playerObj:isIgnoreAutoVault() then return false end
    if not (playerObj:isInteractButtonDown() or playerObj:isSafeToClimbOver(dir)) then return false end

    local hopSquare, north
    if dir == IsoDirections.N then hopSquare, north = square, true
    elseif dir == IsoDirections.W then hopSquare, north = square, false
    elseif dir == IsoDirections.S then hopSquare, north = adjacent, true
    elseif dir == IsoDirections.E then hopSquare, north = adjacent, false end
    if hopSquare and hopSquare:has(north and IsoFlagType.HoppableN or IsoFlagType.HoppableW) then
        local fence = hopSquare:getHoppable(north)
        if fence then
            ISWorldObjectContextMenu.onClimbOverFence(nil, fence, dir, playerObj:getIndex())
            return true
        end
    end

    if playerObj:canClimbOverWall(dir) then
        playerObj:climbOverWall(dir)
        return true
    end
    return false
end

if not ContextualActionHandlers.cd_animalWrapped then
    local vanillaAnimalInteraction = ContextualActionHandlers.AnimalsInteraction
    ContextualActionHandlers.AnimalsInteraction = function(action, playerObj, animal, arg2, arg3, arg4)
        if animal and CD.isDog(animal) then
            if playerObj then
                local first, second = cdContextAxes(playerObj)
                if not cdContextFallback(playerObj, first) and second then
                    cdContextFallback(playerObj, second)
                end
            end
            return
        end
        return vanillaAnimalInteraction(action, playerObj, animal, arg2, arg3, arg4)
    end
    ContextualActionHandlers.cd_animalWrapped = true
end

if not AnimalContextMenu.cd_pickupWrapped then
    local vanillaPickup = AnimalContextMenu.onPickupAnimal
    AnimalContextMenu.onPickupAnimal = function(animal, chr)
        if chr and CD.isDog(animal) and CD.isCompanion(animal) and not CD.isOwnedBy(animal, chr) then
            HaloTextHelper.addBadText(chr, getText("IGUI_PD_NoCarryOther", CD.speciesNoun(animal)))
            return
        end
        return vanillaPickup(animal, chr)
    end
    AnimalContextMenu.cd_pickupWrapped = true
end

if not AnimalContextMenu.cd_invMenuWrapped then
    local vanillaInvMenu = AnimalContextMenu.doInventoryMenu
    AnimalContextMenu.doInventoryMenu = function(player, context, animalInv, test)
        local animal = nil
        if animalInv then
            animal = animalInv:getAnimal()
        end
        local playerObj = getSpecificPlayer(player)
        if animal and playerObj and CD.isDog(animal) and CD.isCompanion(animal) and CD.isOwnedBy(animal, playerObj) then
            local info = context:addOption(getText("ContextMenu_AnimalInfo"), animal, AnimalContextMenu.onAnimalInfo, playerObj)
            info.iconTexture = getTexture("media/ui/inventoryPanes/Button_Info.png")
            if not CD.isMounted(playerObj) then
                local drop = context:addOption(getText("ContextMenu_Drop"), { animalInv }, ISInventoryPaneContextMenu.onDropItems, player)
                drop.iconTexture = getTexture("media/ui/AnimalActions_Grab.png")
            end
            AnimalContextMenu.doFeedFromHandMenu(playerObj, animal, context)
            AnimalContextMenu.doWaterAnimalMenu(context, animal, playerObj)
            return
        end
        return vanillaInvMenu(player, context, animalInv, test)
    end
    AnimalContextMenu.cd_invMenuWrapped = true
end

ISCDPlaceDish = ISBaseTimedAction:derive("ISCDPlaceDish")

function ISCDPlaceDish:isValid()
    return self.item and self.character:getInventory():containsRecursive(self.item)
end

function ISCDPlaceDish:start()
    self.item:setJobType(getText("IGUI_JobType_Dropping"))
    self.item:setJobDelta(0.0)
    self.sound = self.character:playSound("PutItemInBag")
end

-- O efeito sai por contagem de ticks: num client de MP o complete() so e repassado ao Lua no server.
function ISCDPlaceDish:update()
    self.item:setJobDelta(self:getJobDelta())
    self.cdTicks = (self.cdTicks or 0) + 1
    if self.cdTicks >= self.cdMaxTicks and not self.cdDone then
        self:doPlace()
        self:forceComplete()
    end
end

function ISCDPlaceDish:stopSound()
    if self.sound and self.character:getEmitter():isPlaying(self.sound) then
        self.character:getEmitter():stopOrTriggerSound(self.sound)
    end
end

function ISCDPlaceDish:doPlace()
    if self.cdDone then return end
    self.cdDone = true
    if not self.character:getInventory():containsRecursive(self.item) then return end
    CD.request("placedish", nil, {
        x = self.x, y = self.y, z = self.z,
        itemId = self.item:getID(),
        xo = self.xoffset, yo = self.yoffset, rot = self.rotation,
    }, self.character)
end

function ISCDPlaceDish:stop()
    self:stopSound()
    self.item:setJobDelta(0.0)
    ISBaseTimedAction.stop(self)
end

function ISCDPlaceDish:perform()
    self:doPlace()
    self:stopSound()
    self.item:setJobDelta(0.0)
    ISInventoryPage.renderDirty = true
    ISBaseTimedAction.perform(self)
end

-- Sem complete(): defini-lo opta pelo net-action sync, e o dedicado nao carrega media/lua/client
-- (so o checksum), entao o aceite nunca vem e a barra trava pra sempre.

function ISCDPlaceDish:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return 30
end

function ISCDPlaceDish:new(character, item, sq, xoffset, yoffset, rotation)
    local o = ISBaseTimedAction.new(self, character)
    o.item = item
    o.x, o.y, o.z = sq:getX(), sq:getY(), sq:getZ()
    o.xoffset = xoffset
    o.yoffset = yoffset
    o.rotation = rotation
    o.maxTime = o:getDuration()
    o.cdMaxTicks = 15
    o.stopOnWalk = false
    o.stopOnRun = false
    return o
end

local CDPlaceDishCursor

local function getPlaceDishCursorClass()
    if CDPlaceDishCursor then return CDPlaceDishCursor end
    local cursor = ISPlace3DItemCursor:derive("CDPlaceDishCursor")

    function cursor:getSurface()
        self.surfacesPossible = {}
        return 0
    end

    function cursor:create()
        local item = self.items[1]
        local sq = self.selectedSqDrop
        if not (item and sq) then return end
        if not luautils.walkAdjAltTest(self.chr, sq, self.itemSq, true) then return end
        if self.chr:isEquipped(item) then
            ISTimedActionQueue.add(ISUnequipAction:new(self.chr, item, 1, "place"))
        end
        ISTimedActionQueue.addGetUpAndThen(self.chr,
            ISCDPlaceDish:new(self.chr, item, sq, self.render3DItemXOffset, self.render3DItemYOffset, self:clamp(self.render3DItemRot)))
        self.keepOnSquare = false
    end

    function cursor:new(character, item)
        local o = ISPlace3DItemCursor.new(self, character, { item })
        o.placeAll = false
        return o
    end

    CDPlaceDishCursor = cursor
    return cursor
end

local function onPlaceDishClick(playerObj, item)
    if not playerObj or not item then return end
    local cursorClass = getPlaceDishCursorClass()
    local playerNum = playerObj:getPlayerNum()
    for _, ui in ipairs({ getPlayerInventory(playerNum), getPlayerLoot(playerNum) }) do
        if ui and ui:isVisible() and not ui.isCollapsed and not ui.pin then
            ui.isCollapsed = true
            ui:setMaxDrawHeight(ui:titleBarHeight())
        end
    end
    getCell():setDrag(cursorClass:new(playerObj, item), playerNum)
end

local function onInventoryDishMenu(playerNum, context, items)
    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj then return end
    local dish
    for _, v in ipairs(items) do
        local it = v
        if not instanceof(v, "InventoryItem") then
            it = v.items and v.items[1]
        end
        if it and CD.isDishType(it:getFullType()) then
            dish = it
            break
        end
    end
    if not dish then return end
    context:addOption(getText("IGUI_PD_PlaceDish"), playerObj, onPlaceDishClick, dish)
    -- O remove de inventario do "Place item on ground" vanilla nao e recursivo e duplica a tigela.
    context:removeOptionByName(getText("ContextMenu_PlaceItemOnGround"))
end

local function listDishFoods(playerObj)
    return groupCarriedFoods(playerObj, CD.isBowlFood)
end

local function onAddDishFood(playerObj, x, y, z, item, dishId)
    if not (playerObj and item) then return end
    local sq = getCell():getGridSquare(x, y, z)
    if sq then
        luautils.walkAdj(playerObj, sq)
    end
    ISTimedActionQueue.addGetUpAndThen(playerObj, ISCDFillDish:new(playerObj, x, y, z, item, "dishaddfood", "foodId", dishId))
end

local function onAddDishWater(playerObj, x, y, z, water, dishId)
    if not (playerObj and water) then return end
    local sq = getCell():getGridSquare(x, y, z)
    if sq then
        luautils.walkAdj(playerObj, sq)
    end
    ISTimedActionQueue.addGetUpAndThen(playerObj, ISCDFillDish:new(playerObj, x, y, z, water, "dishaddwater", "waterId", dishId))
end

local function onEmptyDish(playerObj, x, y, z, dishId)
    if not playerObj then return end
    local sq = getCell():getGridSquare(x, y, z)
    if sq then
        luautils.walkAdj(playerObj, sq)
    end
    ISTimedActionQueue.addGetUpAndThen(playerObj, ISCDFillDish:new(playerObj, x, y, z, nil, "dishempty", nil, dishId))
end

local function cdDishStock(dish, x, y, z)
    local md = dish and dish:getModData() or {}
    local foodPts = md.cdFoodMeals or 0
    local waterPts = md.cdWater or 0
    local id = dish and dish:getID()
    local cached = CD.dishStock[CD.dishStockKey(x, y, z, id)] or CD.dishStock[CD.dishStockKey(x, y, z)]
    if cached then
        foodPts = cached.food or 0
        waterPts = cached.water or 0
    end
    return foodPts, waterPts
end

local function cdDishStatusText(foodPts, waterPts)
    if foodPts > 0 then
        return getText("IGUI_PD_BowlStatusFood", tostring(math.floor(foodPts)), tostring(CD.DISH_MAX_MEALS))
    elseif waterPts > 0 then
        return getText("IGUI_PD_BowlStatusWater", tostring(math.floor(waterPts)), tostring(CD.DISH_MAX_WATER))
    end
    return getText("IGUI_PD_BowlStatusEmpty")
end

local function cdBuildDishOptions(playerObj, menu, dish, x, y, z, foodPts, waterPts, withStatus)
    local hasFood = foodPts > 0
    local hasWater = waterPts > 0
    local dishId = dish and dish:getID()

    if withStatus then
        menu:addOption(cdDishStatusText(foodPts, waterPts), nil, nil)
    end

    if hasWater then
        local opt = menu:addOption(getText("IGUI_PD_AddBowlFood"), nil, nil)
        opt.notAvailable = true
        local tip = ISWorldObjectContextMenu.addToolTip()
        tip:setName(getText("IGUI_PD_BowlHasWater"))
        opt.toolTip = tip
    else
        local foods = listDishFoods(playerObj)
        if #foods > 0 then
            local header = menu:addOption(getText("IGUI_PD_AddBowlFood"), nil, nil)
            local sub = ISContextMenu:getNew(menu)
            menu:addSubMenu(header, sub)
            for _, g in ipairs(foods) do
                local label = (g.count > 1) and (g.name .. " (" .. g.count .. ")") or g.name
                local opt = sub:addOption(label, playerObj, onAddDishFood, x, y, z, g.item, dishId)
                if g.item then
                    opt.iconTexture = g.item:getTexture()
                end
                if g.bad then
                    opt.notAvailable = true
                    cdApplyBadFoodCue(sub, opt, g)
                end
            end
        else
            local opt = menu:addOption(getText("IGUI_PD_AddBowlFood"), nil, nil)
            opt.notAvailable = true
            local tip = ISWorldObjectContextMenu.addToolTip()
            tip:setName(getText("IGUI_PD_BowlNeedFood"))
            opt.toolTip = tip
        end
    end

    if hasFood then
        local opt = menu:addOption(getText("IGUI_PD_AddBowlWater"), nil, nil)
        opt.notAvailable = true
        local tip = ISWorldObjectContextMenu.addToolTip()
        tip:setName(getText("IGUI_PD_BowlHasFood"))
        opt.toolTip = tip
    else
        local water = findWater(playerObj)
        local wopt = menu:addOption(getText("IGUI_PD_AddBowlWater"), playerObj, onAddDishWater, x, y, z, water, dishId)
        if not water then
            wopt.notAvailable = true
            local tip = ISWorldObjectContextMenu.addToolTip()
            tip:setName(getText("IGUI_PD_NeedWater"))
            wopt.toolTip = tip
        end
    end

    if hasFood or hasWater then
        menu:addOption(getText("IGUI_PD_EmptyBowl"), playerObj, onEmptyDish, x, y, z, dishId)
    end
end

local function onDishWorldMenu(playerNum, context, worldobjects, test)
    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj then return end
    local dishes, seen = {}, {}
    for _, o in ipairs(worldobjects) do
        local sq = o:getSquare()
        local wobs = sq and sq:getWorldObjects()
        if wobs then
            for i = 0, wobs:size() - 1 do
                local wo = wobs:get(i)
                local item = wo:getItem()
                if item and CD.isDishType(item:getFullType()) then
                    local id = item:getID()
                    if not (id and seen[id]) then
                        if id then
                            seen[id] = true
                        end
                        dishes[#dishes + 1] = { wo = wo, item = item, x = sq:getX(), y = sq:getY(), z = sq:getZ() }
                    end
                end
            end
        end
    end
    if #dishes == 0 then return end
    if test then return ISWorldObjectContextMenu.setTest() end

    if #dishes == 1 then
        local d = dishes[1]
        local foodPts, waterPts = cdDishStock(d.item, d.x, d.y, d.z)
        cdBuildDishOptions(playerObj, context, d.item, d.x, d.y, d.z, foodPts, waterPts, true)
        return
    end

    for _, d in ipairs(dishes) do
        local foodPts, waterPts = cdDishStock(d.item, d.x, d.y, d.z)
        local parent = context:addOption(d.item:getName() .. " (" .. cdDishStatusText(foodPts, waterPts) .. ")", nil, nil)
        local sub = ISContextMenu:getNew(context)
        context:addSubMenu(parent, sub)
        parent.onHighlight = ISWorldObjectContextMenu.handleGrabWorldItem_onHighlight
        parent.onHighlightParams = { d.wo }
        cdBuildDishOptions(playerObj, sub, d.item, d.x, d.y, d.z, foodPts, waterPts, false)
    end
end

if isClient() or not isServer() then
    Events.OnClickedAnimalForContext.Add(onAnimalMenu)
    Events.OnFillWorldObjectContextMenu.Add(onWorldMenu)
    Events.OnFillInventoryObjectContextMenu.Add(onInventoryDishMenu)
    Events.OnFillWorldObjectContextMenu.Add(onDishWorldMenu)
end
