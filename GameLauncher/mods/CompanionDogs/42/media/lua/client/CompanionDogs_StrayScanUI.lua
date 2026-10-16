require "ISUI/ISPanel"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISUI3DModel"

CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

ISCDScanView = ISPanel:derive("ISCDScanView")
ISCDScanWindow = ISCollapsableWindow:derive("ISCDScanWindow")

local WIN_W = 460
local MIN_W = 340
local MIN_H = 240
local PAD = 16
local SECT_GAP = 14
local ROW_GAP = 7
local DIVIDER_GAP = 12

local HDR_H = 124
local HDR_PAD = 10
local HDR_AV = 112

local NEED_BAR_H = 14
local NEED_LABEL_W = 86
local NEED_VALUE_W = 42

local TRAIT_BAR_H = 11
local TRAIT_LABEL_W = 116
local TRAIT_WORD_W = 60

local TIP_W = 224
local MAX_DIST = 5

local LBL = { r = 0.78, g = 0.80, b = 0.78 }
local DIV = { r = 1.0, g = 1.0, b = 1.0, a = 0.14 }
local BAR_BG = { r = 0.10, g = 0.10, b = 0.10, a = 0.85 }
local TRAIT_FILL = { r = 0.55, g = 0.62, b = 0.40 }
local WARN = { r = 0.92, g = 0.45, b = 0.35 }

local TRAITS = { "strength", "aggressiveness", "resistance" }

local function fh(font) return getTextManager():getFontHeight(font) end
local function strW(font, s) return getTextManager():MeasureStringX(font, s) end
local function lerp(a, b, t) return a + (b - a) * t end

local function severityColor(sev)
    if sev < 0 then sev = 0 elseif sev > 1 then sev = 1 end
    if sev < 0.5 then
        local t = sev / 0.5
        return lerp(0.40, 0.85, t), lerp(0.70, 0.72, t), lerp(0.34, 0.28, t)
    end
    local t = (sev - 0.5) / 0.5
    return lerp(0.85, 0.80, t), lerp(0.72, 0.27, t), lerp(0.28, 0.24, t)
end

local function wrapText(font, text, maxW)
    local lines = {}
    local line = ""
    for word in string.gmatch(text or "", "%S+") do
        local test = (line == "") and word or (line .. " " .. word)
        if line ~= "" and strW(font, test) > maxW then
            lines[#lines + 1] = line
            line = word
        else
            line = test
        end
    end
    if line ~= "" then
        lines[#lines + 1] = line
    end
    return lines
end

local function renderTip(win, title, body, mx, my)
    local font = UIFont.Small
    local lines = { { t = title, c = { 1, 1, 1 } }, { t = "", c = { 1, 1, 1 } } }
    for _, l in ipairs(wrapText(font, body, TIP_W)) do
        lines[#lines + 1] = { t = l, c = { 0.84, 0.84, 0.84 } }
    end

    local fhs = fh(font)
    local pad = 8
    local w = 0
    for _, l in ipairs(lines) do w = math.max(w, strW(font, l.t)) end
    w = w + pad * 2
    local h = #lines * fhs + pad * 2

    local visTop = -win:getYScroll()
    local visBot = visTop + win:getHeight()
    local tx = mx + 16
    local ty = my + 10
    if tx + w > win.width then
        tx = win.width - w - 2
    end
    if tx < 2 then
        tx = 2
    end
    if ty + h > visBot then
        ty = visBot - h - 2
    end
    if ty < visTop then
        ty = visTop
    end

    win:drawRect(tx, ty, w, h, 0.93, 0.06, 0.06, 0.06)
    win:drawRectBorder(tx, ty, w, h, 0.85, 0.5, 0.5, 0.5)
    local ly = ty + pad
    for _, l in ipairs(lines) do
        if l.t ~= "" then
            win:drawText(l.t, tx + pad, ly, l.c[1], l.c[2], l.c[3], 1, font)
        end
        ly = ly + fhs
    end
end

local function specialtyLine(animal)
    local def = CD.getBreedDef(animal)
    local mult = def and def.xpMult
    if not mult then return nil end
    local parts = {}
    for _, s in ipairs(CD.skillsFor(animal)) do
        local m = mult[s]
        if m and m > 1.0 then
            parts[#parts + 1] = getText("IGUI_PD_Skill_" .. s) .. string.format(" x%.1f", m)
        end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, ", ")
end

function ISCDScanView:new(x, y, w, h)
    local o = ISPanel.new(self, x, y, w, h)
    o.background = false
    return o
end

function ISCDScanView:instantiate() CD.UI.viewInstantiate(self) end
function ISCDScanView:onMouseWheel(del) return CD.UI.viewMouseWheel(self, del) end

function ISCDScanView:layout()
    local L = self:doLayout()
    self:setScrollHeight(L.contentH)
end

function ISCDScanView:doLayout()
    local L = {}
    local sm = fh(UIFont.Small)
    local y = PAD

    L.traitsLabelY = y
    y = y + sm + ROW_GAP
    L.traitsY = y
    L.traitRowH = math.max(sm, TRAIT_BAR_H) + ROW_GAP
    y = y + L.traitRowH * #TRAITS - ROW_GAP + SECT_GAP

    L.div1 = y
    y = y + 1 + DIVIDER_GAP

    L.condLabelY = y
    y = y + sm + ROW_GAP
    L.condY = y
    L.needRowH = math.max(sm, NEED_BAR_H) + ROW_GAP
    y = y + L.needRowH - ROW_GAP + SECT_GAP

    L.div2 = y
    y = y + 1 + DIVIDER_GAP

    L.adoptLabelY = y
    y = y + sm + ROW_GAP
    L.trustY = y
    y = y + L.needRowH
    L.trustFmtY = y
    y = y + sm + ROW_GAP
    L.limitY = y
    y = y + sm

    y = y + PAD
    L.contentH = y
    self.L = L
    return L
end

function ISCDScanView:drawDivider(y)
    local cw = CD.UI.viewContentW(self)
    self:drawRect(PAD, y, cw - PAD * 2, 1, DIV.a, DIV.r, DIV.g, DIV.b)
end

function ISCDScanView:drawNeedBar(label, y, fill, severity)
    local cw = CD.UI.viewContentW(self)
    local right = cw - PAD
    local sm = fh(UIFont.Small)
    local labelY = y + math.floor((NEED_BAR_H - sm) / 2)
    self:drawText(label, PAD, labelY, 0.92, 0.92, 0.92, 1, UIFont.Small)

    local valText = string.format("%d%%", math.floor(fill * 100 + 0.5))
    self:drawText(valText, right - strW(UIFont.Small, valText), labelY, 0.82, 0.82, 0.82, 1, UIFont.Small)

    local barX = PAD + NEED_LABEL_W
    local barW = (right - NEED_VALUE_W - 6) - barX
    if barW < 12 then
        barW = 12
    end
    self:drawRect(barX, y, barW, NEED_BAR_H, BAR_BG.a, BAR_BG.r, BAR_BG.g, BAR_BG.b)
    self:drawRectBorder(barX, y, barW, NEED_BAR_H, 0.5, 0, 0, 0)
    local f = fill
    if f < 0 then f = 0 elseif f > 1 then f = 1 end
    if f > 0 then
        local r, g, b = severityColor(severity)
        self:drawRect(barX + 1, y + 1, math.floor((barW - 2) * f), NEED_BAR_H - 2, 0.95, r, g, b)
    end
end

function ISCDScanView:drawTraitBar(label, y, ratio)
    local cw = CD.UI.viewContentW(self)
    local right = cw - PAD
    local sm = fh(UIFont.Small)
    local labelY = y + math.floor((TRAIT_BAR_H - sm) / 2)
    self:drawText(label, PAD, labelY, 0.92, 0.92, 0.92, 1, UIFont.Small)

    local word
    if ratio == nil then
        word = getText("IGUI_PD_ScanUnknown")
    elseif ratio < 0.34 then
        word = getText("IGUI_PD_TraitLow")
    elseif ratio > 0.66 then
        word = getText("IGUI_PD_TraitHigh")
    else
        word = getText("IGUI_PD_TraitAvg")
    end
    self:drawText(word, right - strW(UIFont.Small, word), labelY, 0.78, 0.78, 0.78, 1, UIFont.Small)

    local barX = PAD + TRAIT_LABEL_W
    local barW = (right - TRAIT_WORD_W - 6) - barX
    if barW < 12 then
        barW = 12
    end
    self:drawRect(barX, y, barW, TRAIT_BAR_H, BAR_BG.a, BAR_BG.r, BAR_BG.g, BAR_BG.b)
    self:drawRectBorder(barX, y, barW, TRAIT_BAR_H, 0.5, 0, 0, 0)
    if ratio and ratio > 0 then
        self:drawRect(barX + 1, y + 1, math.floor((barW - 2) * ratio), TRAIT_BAR_H - 2, 0.95,
            TRAIT_FILL.r, TRAIT_FILL.g, TRAIT_FILL.b)
    end
end

function ISCDScanView:prerender()
    CD.UI.viewBeginRender(self)
end

function ISCDScanView:render()
    self:drawContent()
    CD.UI.viewEndRender(self)
end

function ISCDScanView:drawContent()
    local L = self.L
    if not L then return end
    local a = self.animal
    if not a then return end
    local breedNoun = CD.breedNoun(a)
    local cw = CD.UI.viewContentW(self)
    local x = PAD

    local over = self:isMouseOver() or self:isMouseOverChild()
    local mx, my = self:getMouseX(), self:getMouseY()
    local tip = nil
    local function hoverRow(y, h)
        return over and my >= y and my < y + h and mx >= PAD and mx <= cw - PAD
    end

    self:drawText(getText("IGUI_PD_GenomeLabel"), x, L.traitsLabelY, LBL.r, LBL.g, LBL.b, 1, UIFont.Small)
    if hoverRow(L.traitsLabelY, fh(UIFont.Small) + ROW_GAP) then
        tip = { title = getText("IGUI_PD_GenomeLabel"), body = getText("IGUI_PD_GenomeDesc", breedNoun) }
    end
    local known = CD.data(a).genes ~= nil
    local ty = L.traitsY
    for _, gene in ipairs(TRAITS) do
        self:drawTraitBar(getText("IGUI_PD_Gene_" .. gene), ty, known and CD.geneRatio(a, gene) or nil)
        if hoverRow(ty, L.traitRowH) then
            tip = { title = getText("IGUI_PD_Gene_" .. gene), body = getText("IGUI_PD_GeneDesc_" .. gene, breedNoun) }
        end
        ty = ty + L.traitRowH
    end

    self:drawDivider(L.div1)

    self:drawText(getText("IGUI_PD_ScanCondition"), x, L.condLabelY, LBL.r, LBL.g, LBL.b, 1, UIFont.Small)
    local health = a:getHealth()
    self:drawNeedBar(getText("IGUI_PD_Need_health"), L.condY, health, 1 - health)

    self:drawDivider(L.div2)

    self:drawText(getText("IGUI_PD_ScanAdoption"), x, L.adoptLabelY, LBL.r, LBL.g, LBL.b, 1, UIFont.Small)
    local trust = CD.getTrust(a)
    local need = CD.tameThreshold()
    if need <= 0 then
        need = 1
    end
    local ratio = trust / need
    if ratio > 1 then
        ratio = 1
    end
    self:drawNeedBar(getText("IGUI_PD_ScanTrust"), L.trustY, ratio, 1 - ratio)
    if hoverRow(L.trustY, L.needRowH) then
        tip = { title = getText("IGUI_PD_ScanTrust"), body = getText("IGUI_PD_ScanTrustDesc", breedNoun) }
    end
    self:drawText(getText("IGUI_PD_ScanTrustFmt", tostring(math.floor(trust)), tostring(math.floor(need))),
        x, L.trustFmtY, 0.72, 0.82, 0.92, 1, UIFont.Small)

    if self.actor and CD.atCompanionLimit(self.actor) then
        self:drawText(getText("IGUI_PD_FeedLimit", tostring(CD.maxCompanions())),
            x, L.limitY, WARN.r, WARN.g, WARN.b, 1, UIFont.Small)
    end

    if tip then
        renderTip(self, tip.title, tip.body, mx, my)
    end
end

function ISCDScanWindow:new(x, y, width, height, animal)
    local o = ISCollapsableWindow.new(self, x, y, width, height)
    o.animal = animal
    o.resizable = true
    o.avatarBg = getTexture("media/ui/avatarBackgroundWhite.png")
    o:setTitle(CD.speciesText(animal, "IGUI_PD_ScanTitle"))
    return o
end

function ISCDScanWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    local top = self:titleBarHeight()
    local rh = self:resizeWidgetHeight()
    self.hdrH = HDR_H

    local vw = self.width
    local vh = math.max(1, self.height - top - self.hdrH - rh)
    self.view = ISCDScanView:new(0, top + self.hdrH, vw, vh)
    self.view.animal = self.animal
    self.view.actor = self.actor
    self.view:initialise()
    self:addChild(self.view)
    self.view:layout()

    local av = ISCDDogAvatar:new(HDR_PAD, top + math.floor((HDR_H - HDR_AV) / 2), HDR_AV, HDR_AV)
    av:initialise()
    self:addChild(av)
    av:bindAnimal(self.animal)
    self.headerAvatar = av

    CD.UI.initResizable(self, "scanwin", MIN_W, MIN_H)
end

function ISCDScanWindow:reflow()
    if not self.view then return end
    local top = self:titleBarHeight()
    local rh = self:resizeWidgetHeight()
    self.view:setX(0)
    self.view:setY(top + (self.hdrH or 0))
    self.view:setWidth(self.width)
    self.view:setHeight(math.max(1, self.height - top - (self.hdrH or 0) - rh))
    self.view:layout()
end

function ISCDScanWindow:checkShouldClose()
    local a = self.animal
    if not a or not a:isExistInTheWorld() or a:getHealth() <= 0 then
        self:close()
        return true
    end
    if CD.isCompanion(a) then
        self:close()
        return true
    end
    local chr = self.actor
    local sq = a:getCurrentSquare()
    if chr and sq and sq:DistToProper(chr) > MAX_DIST then
        self:close()
        return true
    end
    return false
end

function ISCDScanWindow:drawHeader()
    if self.isCollapsed then return end
    local a = self.animal
    local top = self:titleBarHeight()
    local ax = HDR_PAD
    local ay = top + math.floor((HDR_H - HDR_AV) / 2)
    self:drawRectBorder(ax - 1, ay - 1, HDR_AV + 2, HDR_AV + 2, 1, 0.3, 0.3, 0.3)
    if self.avatarBg then
        self:drawTextureScaled(self.avatarBg, ax, ay, HDR_AV, HDR_AV, 1, 0.4, 0.4, 0.4)
    end
    local av = self.headerAvatar
    if av and av.boundAnimal then
        av:applyFrame()
    end

    local breedName = CD.breedNoun(a)
    if CD.isMongrel(a) then
        breedName = breedName .. " (" .. getText("IGUI_PD_Mestico") .. ")"
    end

    local bits = {}
    local sx = CD.sexNoun(a)
    if sx then
        bits[#bits + 1] = sx
    end
    bits[#bits + 1] = CD.ageNoun(a)
    if CD.isPregnant(a) then
        bits[#bits + 1] = CD.pregnancyLabel(a)
    end

    local spec = specialtyLine(a)
    local tx = ax + HDR_AV + 12
    local mdH = fh(UIFont.Medium)
    local smH = fh(UIFont.Small)
    local blockH = mdH + 6 + smH + (spec and (4 + smH) or 0)
    local nameY = ay + math.max(2, math.floor((HDR_AV - blockH) / 2))

    self:drawText(breedName, tx, nameY, 1, 1, 1, 1, UIFont.Medium)
    local lineY = nameY + mdH + 6
    self:drawText(table.concat(bits, ", "), tx, lineY, 0.72, 0.82, 0.92, 1, UIFont.Small)
    if spec then
        self:drawText(getText("IGUI_PD_ScanSpecialty") .. ": " .. spec, tx, lineY + smH + 4,
            0.72, 0.82, 0.92, 1, UIFont.Small)
    end
end

function ISCDScanWindow:prerender()
    if self:checkShouldClose() then return end
    ISCollapsableWindow.prerender(self)
    self:drawHeader()
end

function ISCDScanWindow:close()
    CD.UI.persist(self)
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    local pn = self.playerNum or 0
    if ISCDScanWindow.instances[pn] == self then
        ISCDScanWindow.instances[pn] = nil
    end
end

ISCDScanWindow.instances = ISCDScanWindow.instances or {}

---Opens the scan sheet of a dog, replacing this player's open one, and asks the server for the details.
---@param animal IsoAnimal
---@param playerObj IsoPlayer|nil getPlayer() when nil
---@return ISCDScanWindow|nil win nil when the animal is not a dog
function CD.openStrayScan(animal, playerObj)
    if not (animal and CD.isDog(animal)) then return end
    local who = playerObj or getPlayer()
    local pn = 0
    if who then
        pn = who:getPlayerNum()
    end
    if ISCDScanWindow.instances[pn] then
        ISCDScanWindow.instances[pn]:close()
    end

    CD.request("scanstray", animal, nil, who)

    local win = ISCDScanWindow:new(0, 0, WIN_W, 420, animal)
    win.actor = who
    win.playerNum = pn
    win:initialise()
    win:instantiate()
    win:setRenderThisPlayerOnly(pn)
    local top = win:titleBarHeight()
    local rh = win:resizeWidgetHeight()
    local contentH = (win.view and win.view.L and win.view.L.contentH) or 260
    CD.UI.applyOpenGeometry(win, "scanwin", WIN_W, top + HDR_H + contentH + rh)
    win:addToUIManager()
    ISCDScanWindow.instances[pn] = win
    return win
end
