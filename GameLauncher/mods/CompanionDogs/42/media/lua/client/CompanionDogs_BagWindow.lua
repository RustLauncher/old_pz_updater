require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"

CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

ISCDBagWindow = ISCollapsableWindow:derive("ISCDBagWindow")
CD.BagWindow = CD.BagWindow or {}

local PAD = 8
local HEADER_H = 18
local ROW_H = 24

local function cdItemWeight(it)
    local w = it:getUnequippedWeight()
    if w <= 0 then
        w = it:getWeight()
    end
    return w
end

local function cdDrawRow(self, y, item, alt)
    if not item.height then
        item.height = self.itemheight
    end
    local h = item.height
    if (y + self:getYScroll() + h < 0) or (y + self:getYScroll() >= self.height) then
        return y + h
    end
    local w = self:getWidth()
    if alt then
        self:drawRect(0, y, w, h, 0.06, 1, 1, 1)
    end
    if self.selected == item.index then
        self:drawSelection(0, y, w, h - 1)
    elseif self.mouseoverselected == item.index and self:isMouseOver() and not self:isMouseOverScrollBar() then
        self:drawMouseOverHighlight(0, y, w, h - 1)
    end
    local d = item.item
    local sz = h - 6
    if d and d.tex then
        self:drawTextureScaledAspect(d.tex, 3, y + 3, sz, sz, 1, 1, 1, 1)
    end
    local ty = y + (h - self.fontHgt) / 2
    if d and d.weight then
        local ws = string.format("%.2f", d.weight)
        local wx = w - getTextManager():MeasureStringX(self.font, ws) - 6
        self:drawText(ws, wx, ty, 0.62, 0.62, 0.62, 1, self.font)
    end
    self:drawText(item.text, h + 2, ty, 0.9, 0.9, 0.9, 1, self.font)
    self:drawRect(0, y + h - 1, w, 1, 0.25, 0.4, 0.4, 0.4)
    return y + h
end

local function eligibleForDeposit(item)
    if not item then return false end
    if CD.isSaddlebagType(item:getFullType()) then return false end
    if instanceof(item, "InventoryContainer") then return false end
    if instanceof(item, "AnimalInventoryItem") then return false end
    local eq = item:isEquipped()
    if eq then return false end
    return true
end

local function collectDepositable(inv, out, depth)
    if not inv or depth > 6 then return end
    local items = inv:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if instanceof(it, "InventoryContainer") then
            collectDepositable(it:getInventory(), out, depth + 1)
        elseif eligibleForDeposit(it) then
            out[#out + 1] = it
        end
    end
end

function ISCDBagWindow:new(x, y, w, h)
    local o = ISCollapsableWindow.new(self, x, y, w, h)
    o.records = {}
    o.cap = 0
    o.playerNum = 0
    o.resizable = true
    o:setTitle(getText("IGUI_PD_BagWindowTitle"))
    return o
end

function ISCDBagWindow:listGeom()
    local top = self:titleBarHeight() + PAD
    local listTop = top + HEADER_H
    local rh = self:resizeWidgetHeight()
    local colW = math.floor((self.width - PAD * 3) / 2)
    if colW < 40 then
        colW = 40
    end
    local listH = self.height - listTop - PAD - rh
    if listH < 40 then
        listH = 40
    end
    self.headerY = top
    self.invX = PAD
    self.bagX = PAD * 2 + colW
    self.colW = colW
    return listTop, colW, listH
end

function ISCDBagWindow:createChildren()
    ISCollapsableWindow.createChildren(self)

    local rowFont = UIFont.Small
    local rowFontHgt = getTextManager():getFontHeight(rowFont)
    -- Listas criadas ja no tamanho final: construir pequeno e redimensionar prende a scrollbar no canto.
    local listTop, colW, listH = self:listGeom()

    self.invList = ISScrollingListBox:new(self.invX, listTop, colW, listH)
    self.invList:initialise()
    self.invList.itemheight = ROW_H
    self.invList.font = rowFont
    self.invList.fontHgt = rowFontHgt
    self.invList.drawBorder = true
    self.invList.doDrawItem = cdDrawRow
    self.invList:setOnMouseDownFunction(self, self.onDeposit)
    self:addChild(self.invList)

    self.bagList = ISScrollingListBox:new(self.bagX, listTop, colW, listH)
    self.bagList:initialise()
    self.bagList.itemheight = ROW_H
    self.bagList.font = rowFont
    self.bagList.fontHgt = rowFontHgt
    self.bagList.drawBorder = true
    self.bagList.doDrawItem = cdDrawRow
    self.bagList:setOnMouseDownFunction(self, self.onWithdraw)
    self:addChild(self.bagList)

    CD.UI.initResizable(self, "bag", 420, 260)
    self:refresh()
end

function ISCDBagWindow:layoutLists()
    if not (self.invList and self.bagList) then return end
    local listTop, colW, listH = self:listGeom()
    self.invList:setX(self.invX)
    self.invList:setY(listTop)
    self.invList:setWidth(colW)
    self.invList:setHeight(listH)
    self.bagList:setX(self.bagX)
    self.bagList:setY(listTop)
    self.bagList:setWidth(colW)
    self.bagList:setHeight(listH)
end

function ISCDBagWindow:reflow()
    self:layoutLists()
end

function ISCDBagWindow:prerender()
    ISCollapsableWindow.prerender(self)
    if not self.headerY then return end
    local fy = self.headerY + (HEADER_H - getTextManager():getFontHeight(UIFont.Small)) / 2
    self:drawRect(self.invX, self.headerY, self.colW, HEADER_H, 0.4, 0.12, 0.12, 0.12)
    self:drawRect(self.bagX, self.headerY, self.colW, HEADER_H, 0.4, 0.12, 0.12, 0.12)
    self:drawText(getText("IGUI_PD_BagYours"), self.invX + 4, fy, 0.8, 0.8, 0.8, 1, UIFont.Small)
    local used = CD.bagWeight(self.records)
    local bagHdr = getText("IGUI_PD_BagCapacity", string.format("%.1f", used), tostring(self.cap or 0))
    self:drawText(bagHdr, self.bagX + 4, fy, 0.8, 0.8, 0.8, 1, UIFont.Small)
end

function ISCDBagWindow:sendBag(command, extra)
    if not self.animalId then return end
    extra = extra or {}
    extra.id = self.animalId
    if isClient() then
        CD.sendAs(getSpecificPlayer(self.playerNum or 0) or getPlayer(), command, extra)
    elseif CD.Server and CD.Server[command] then
        extra.__animal = self.animal or getAnimal(self.animalId)
        CD.Server[command](getSpecificPlayer(self.playerNum or 0) or getPlayer(), extra)
    end
end

function ISCDBagWindow:cdHalo(key, name)
    if not (CD.showNotifications == nil or CD.showNotifications()) then return end
    local pl = getSpecificPlayer(self.playerNum) or getPlayer()
    if pl then
        HaloTextHelper.addText(pl, getText(key, name or ""))
    end
end

function ISCDBagWindow:onDeposit(data)
    if data and data.item then
        self:sendBag("bagput", { itemId = data.item:getID() })
        self:cdHalo("IGUI_PD_BagStored", data.item:getName())
        local isMap = data.item:IsMap()
        if isMap then
            self:cdHalo("IGUI_PD_BagMapNoAnnot")
        end
    end
end

function ISCDBagWindow:onWithdraw(data)
    if data and data.index then
        self:sendBag("bagtake", { index = data.index })
        local r = self.records and self.records[data.index]
        if r then
            local disp = CD.bagDisplayItem(r)
            if disp then
                self:cdHalo("IGUI_PD_BagTaken", disp:getName())
            end
        end
    end
end

function ISCDBagWindow:refresh()
    if not self.bagList or not self.invList then return end

    self.bagList:clear()
    local dispCache = {}
    local function dispFor(r)
        local sig = r.t .. "\0" .. (r.name or "") .. "\0" .. (r.age and string.format("%.3f", r.age) or "")
            .. "\0" .. (r.aged and string.format("%.2f", r.aged) or "") .. (r.cooked and "c" or "") .. (r.burnt and "b" or "")
        local d = dispCache[sig]
        if d == nil then
            d = CD.bagDisplayItem(r) or false
            dispCache[sig] = d
        end
        return d or nil
    end

    local bGroups, bOrder = {}, {}
    for i, r in ipairs(self.records or {}) do
        local disp = dispFor(r)
        local key = r.t .. "\0" .. (r.name or "") .. "\0" .. CD.itemStateKey(disp)
        local g = bGroups[key]
        if not g then
            g = { t = r.t, name = r.name, disp = disp, w = 0, indices = {} }
            bGroups[key] = g
            bOrder[#bOrder + 1] = key
        end
        g.indices[#g.indices + 1] = i
        g.w = g.w + (r.w or (g.disp and cdItemWeight(g.disp)) or 0)
    end
    for _, key in ipairs(bOrder) do
        local g = bGroups[key]
        local n = #g.indices
        local name, tex = (g.name or g.t), nil
        if g.disp then
            name = g.disp:getName()
            tex = g.disp:getTexture()
        end
        local label = (n > 1) and (name .. " (x" .. n .. ")") or name
        self.bagList:addItem(label, { index = g.indices[1], count = n, tex = tex, weight = g.w })
    end

    self.invList:clear()
    local player = getSpecificPlayer(self.playerNum) or getPlayer()
    local inv = player and player:getInventory()
    if inv then
        local depositable = {}
        collectDepositable(inv, depositable, 0)
        local iGroups, iOrder = {}, {}
        for _, it in ipairs(depositable) do
            local key = it:getFullType() .. "\0" .. CD.itemStateKey(it)
            local g = iGroups[key]
            if not g then
                local tex = it:getTexture()
                g = { items = {}, name = it:getName(), tex = tex, w = 0 }
                iGroups[key] = g
                iOrder[#iOrder + 1] = key
            end
            g.items[#g.items + 1] = it
            g.w = g.w + cdItemWeight(it)
        end
        for _, key in ipairs(iOrder) do
            local g = iGroups[key]
            local n = #g.items
            local label = (n > 1) and (g.name .. " (x" .. n .. ")") or g.name
            self.invList:addItem(label, { item = g.items[1], count = n, tex = g.tex, weight = g.w })
        end
    end
end

function ISCDBagWindow:setData(cap, records)
    self.cap = cap or self.cap or 0
    self.records = records or {}
    self:refresh()
end

function ISCDBagWindow:close()
    CD.UI.persist(self)
    CD.BagWindow.instances[self.playerNum or 0] = nil
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
end

CD.BagWindow.instances = CD.BagWindow.instances or {}
CD.BagWindow.liveAnimals = CD.BagWindow.liveAnimals or {}

---Asks the server for the bag contents; the window opens when the reply reaches CD.BagWindow.onData.
---@param animal IsoAnimal
---@param player IsoPlayer|nil getPlayer() when nil
function CD.openBagWindow(animal, player)
    if not animal then return end
    CD.BagWindow = CD.BagWindow or {}
    player = player or getPlayer()
    local pn = 0
    if player then
        pn = player:getPlayerNum()
    end
    CD.BagWindow.pendingNum = pn
    CD.BagWindow.liveAnimals[pn] = animal
    CD.request("bagopen", animal, nil, player)
end

---Opens or refreshes the bag window of the local player who asked last.
---@param args table server payload { id, cap, items }
function CD.BagWindow.onData(args)
    if not args or not args.id then return end
    local pn = CD.BagWindow.pendingNum or 0
    local animal = getAnimal(args.id) or CD.BagWindow.liveAnimals[pn]
    local w = CD.BagWindow.instances[pn]
    if not w then
        w = ISCDBagWindow:new(0, 0, 800, 580)
        w.playerNum = pn
        w:initialise()
        w:instantiate()
        w:setRenderThisPlayerOnly(pn)
        CD.UI.applyOpenGeometry(w, "bag", 800, 580)
        w:addToUIManager()
        CD.BagWindow.instances[pn] = w
    end
    w.animal = animal
    w.animalId = args.id
    w:setData(args.cap, args.items)
    w:setVisible(true)
    w:bringToTop()
end
