require "ISUI/ISCollapsableWindow"
require "RadioCom/ISUIRadio/ISSliderPanel"

CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

ISCDDogEditor = ISCollapsableWindow:derive("ISCDDogEditor")
ISCDDogEditor.instances = ISCDDogEditor.instances or {}

local PAD = 10
local ROW_H = 28
local HDR_H = 24
local LABEL_W = 130
local VAL_W = 52
local SLIDER_H = 20
local DEF_W = 520
local MIN_W = 360
local HOLD_MS = 1500

local C_HDR = { r = 0.95, g = 0.88, b = 0.55 }
local C_TXT = { r = 0.84, g = 0.84, b = 0.84 }
local C_VAL = { r = 0.55, g = 0.85, b = 0.45 }

local NEEDS = {
    { key = "hunger",  label = "Hunger" },
    { key = "thirst",  label = "Thirst" },
    { key = "stress",  label = "Stress" },
    { key = "loyalty", label = "Loyalty" },
    { key = "health",  label = "Health" },
}
local GENES = { "strength", "aggressiveness", "resistance" }
local SKILL_LABELS = { scent = "Scent", combat = "Combat", obedience = "Obedience", hunt = "Hunt", herding = "Herding" }

local function capitalize(s)
    return s:sub(1, 1):upper() .. s:sub(2)
end

function ISCDDogEditor:readValue(row)
    local a = self.animal
    if row.kind == "skill" then return CD.getSkillLevel(a, row.key) end
    if row.kind == "gene" then return CD.geneRatio(a, row.key) * 100 end
    local k = row.key
    if k == "hunger" then return a:getHunger() * 100 end
    if k == "thirst" then return a:getThirst() * 100 end
    if k == "stress" then return CD.getStress(a) * 100 end
    if k == "loyalty" then return CD.loyalty(a) / CD.TRUST_MAX * 100 end
    return a:getHealth() / (CD.data(a).maxHealth or 1) * 100
end

function ISCDDogEditor:sendValue(row, v)
    if row.kind == "skill" then
        CD.request("debugskill", self.animal, { skill = row.key, set = v }, self.player)
        return
    end
    local field = row.key
    if row.kind == "gene" then
        field = "gene:" .. row.key
    end
    CD.request("debugset", self.animal, { field = field, value = v / 100 }, self.player)
end

local function onSliderChange(self, v, slider)
    slider.cdRow.pending = v
end

local function sliderRelease(slider, x, y)
    ISSliderPanel.onMouseUp(slider, x, y)
    local row = slider.cdRow
    if row.pending == nil then return end
    slider.cdWin:sendValue(row, row.pending)
    row.pending = nil
    row.holdUntil = getTimestampMs() + HOLD_MS
end

local function sliderReleaseOutside(slider, x, y)
    ISSliderPanel.onMouseUpOutside(slider, x, y)
    sliderRelease(slider, x, y)
end

function ISCDDogEditor:new(animal, player, key)
    local o = ISCollapsableWindow.new(self, 0, 0, DEF_W, 200)
    o.animal = animal
    o.player = player
    o.playerNum = player:getPlayerNum()
    o.cdKey = key
    o.sections = {}
    o.rows = {}
    o:setTitle("Status editor: " .. tostring(CD.data(animal).name or CD.breedNoun(animal)))
    return o
end

function ISCDDogEditor:buildSections()
    local needs = {}
    for _, n in ipairs(NEEDS) do
        needs[#needs + 1] = { kind = "need", key = n.key, label = n.label, max = 100 }
    end
    local genes = {}
    for _, g in ipairs(GENES) do
        genes[#genes + 1] = { kind = "gene", key = g, label = capitalize(g), max = 100 }
    end
    local skills = {}
    for _, s in ipairs(CD.skillsFor(self.animal)) do
        skills[#skills + 1] = { kind = "skill", key = s, label = SKILL_LABELS[s] or capitalize(s), max = CD.SKILL_MAX_LEVEL }
    end
    self.sections = {
        { title = "Needs", rows = needs },
        { title = "Genes", rows = genes },
        { title = "Skills (0-" .. tostring(CD.SKILL_MAX_LEVEL) .. ")", rows = skills },
    }
end

function ISCDDogEditor:naturalHeight()
    local h = self:titleBarHeight() + PAD
    for _, sec in ipairs(self.sections) do
        h = h + HDR_H + #sec.rows * ROW_H
    end
    return h + PAD + self:resizeWidgetHeight()
end

function ISCDDogEditor:createChildren()
    ISCollapsableWindow.createChildren(self)
    self:buildSections()
    for _, sec in ipairs(self.sections) do
        for _, row in ipairs(sec.rows) do
            local s = ISSliderPanel:new(0, 0, 100, SLIDER_H, self, onSliderChange)
            s:initialise()
            s:instantiate()
            if row.kind == "skill" then
                s:setValues(0, row.max, 1, 1, true)
            else
                s:setValues(0, row.max, 1, 10, true)
            end
            s:setCurrentValue(self:readValue(row), true)
            s.cdRow = row
            s.cdWin = self
            s.onMouseUp = sliderRelease
            s.onMouseUpOutside = sliderReleaseOutside
            self:addChild(s)
            row.slider = s
            self.rows[#self.rows + 1] = row
        end
    end
    CD.UI.initResizable(self, "dogedit", MIN_W, self:naturalHeight())
    self:reflow()
end

function ISCDDogEditor:reflow()
    if not self.rows then return end
    local y = self:titleBarHeight() + PAD
    local sliderX = PAD + LABEL_W
    local sliderW = math.max(60, self.width - sliderX - VAL_W - PAD)
    for _, sec in ipairs(self.sections) do
        sec.y = y
        y = y + HDR_H
        for _, row in ipairs(sec.rows) do
            row.y = y
            local s = row.slider
            s:setX(sliderX)
            s:setY(y + (ROW_H - SLIDER_H) / 2)
            s:setWidth(sliderW)
            y = y + ROW_H
        end
    end
end

function ISCDDogEditor:prerender()
    ISCollapsableWindow.prerender(self)
    if self.animal:isDead() then
        self:close()
        return
    end
    local now = getTimestampMs()
    for _, row in ipairs(self.rows) do
        local s = row.slider
        if not s.dragInside and row.pending == nil and now > (row.holdUntil or 0) then
            s:setCurrentValue(self:readValue(row), true)
        end
    end
end

function ISCDDogEditor:render()
    ISCollapsableWindow.render(self)
    if self.isCollapsed then return end
    local font = UIFont.Small
    local fh = getTextManager():getFontHeight(font)
    local valX = self.width - PAD - VAL_W
    for _, sec in ipairs(self.sections) do
        self:drawText(sec.title, PAD, sec.y + (HDR_H - fh) / 2, C_HDR.r, C_HDR.g, C_HDR.b, 1, font)
        self:drawRect(PAD, sec.y + HDR_H - 3, self.width - PAD * 2, 1, 0.3, 1, 1, 1)
    end
    for _, row in ipairs(self.rows) do
        local ty = row.y + (ROW_H - fh) / 2
        self:drawText(row.label, PAD + 6, ty, C_TXT.r, C_TXT.g, C_TXT.b, 1, font)
        local v = row.pending or row.slider:getCurrentValue()
        local s = tostring(math.floor(v + 0.5))
        if row.kind ~= "skill" then
            s = s .. "%"
        end
        self:drawTextRight(s, valX + VAL_W, ty, C_VAL.r, C_VAL.g, C_VAL.b, 1, font)
    end
end

function ISCDDogEditor:close()
    CD.UI.persist(self)
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    if ISCDDogEditor.instances[self.cdKey] == self then
        ISCDDogEditor.instances[self.cdKey] = nil
    end
end

function ISCDDogEditor.open(animal, player)
    if not animal or not CD.debugAllowed() then return end
    player = player or getPlayer()
    local pn = player:getPlayerNum()
    local key = tostring(CD.animKey(animal)) .. ":" .. tostring(pn)
    local win = ISCDDogEditor.instances[key]
    if win then
        win.animal = animal
        win:setVisible(true)
        win:bringToTop()
        return
    end
    win = ISCDDogEditor:new(animal, player, key)
    win:initialise()
    win:instantiate()
    CD.UI.applyOpenGeometry(win, "dogedit", DEF_W, win:naturalHeight())
    win:setRenderThisPlayerOnly(pn)
    win:addToUIManager()
    ISCDDogEditor.instances[key] = win
end


-- Janela de debug dos males: aplica e limpa cada condicao do vetcare no cao apontado, pelo servidor.
ISCDHealthDebugWindow = ISCollapsableWindow:derive("ISCDHealthDebugWindow")
ISCDHealthDebugWindow.instances = ISCDHealthDebugWindow.instances or {}

local HEALTH_DEBUG_W = 600
local HEALTH_DEBUG_H = 150
local HEALTH_DEBUG_PAD = 12
local HEALTH_DEBUG_GAP = 10
local HEALTH_DEBUG_CONTROL_H = 30

local function healthDebugSelected(combo)
    local option = combo.options[combo.selected]
    if option == nil then return nil end
    return option.data
end

local function healthDebugTitle(animal)
    return "Health status: " .. tostring(CD.data(animal).name or CD.breedNoun(animal))
end

function ISCDHealthDebugWindow:new(animal, player, key)
    local o = ISCollapsableWindow.new(self, 0, 0, HEALTH_DEBUG_W, HEALTH_DEBUG_H)
    o.animal = animal
    o.player = player
    o.playerNum = player:getPlayerNum()
    o.cdKey = key
    o.resizable = false
    o:setTitle(healthDebugTitle(animal))
    return o
end

function ISCDHealthDebugWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    local y = self:titleBarHeight() + HEALTH_DEBUG_PAD
    local innerW = self.width - HEALTH_DEBUG_PAD * 2
    self.ailmentCombo = ISComboBox:new(HEALTH_DEBUG_PAD, y, innerW, HEALTH_DEBUG_CONTROL_H)
    self.ailmentCombo:initialise()
    self:addChild(self.ailmentCombo)
    for _, entry in ipairs(CD.HEALTH_DEBUG_AILMENTS) do
        self.ailmentCombo:addOptionWithData(getText(entry.labelKey), entry.id)
    end

    y = y + HEALTH_DEBUG_CONTROL_H + HEALTH_DEBUG_GAP
    local buttonW = math.floor((innerW - HEALTH_DEBUG_GAP * 2) / 3)
    self.applyButton = ISButton:new(HEALTH_DEBUG_PAD, y, buttonW, HEALTH_DEBUG_CONTROL_H,
        "Apply", self, ISCDHealthDebugWindow.onApply)
    self.applyButton:initialise()
    self.applyButton:instantiate()
    self:addChild(self.applyButton)

    self.clearButton = ISButton:new(HEALTH_DEBUG_PAD + buttonW + HEALTH_DEBUG_GAP, y,
        buttonW, HEALTH_DEBUG_CONTROL_H, "Clear this one", self, ISCDHealthDebugWindow.onClear)
    self.clearButton:initialise()
    self.clearButton:instantiate()
    self:addChild(self.clearButton)

    local clearAllX = HEALTH_DEBUG_PAD + (buttonW + HEALTH_DEBUG_GAP) * 2
    self.clearAllButton = ISButton:new(clearAllX, y, innerW - (clearAllX - HEALTH_DEBUG_PAD),
        HEALTH_DEBUG_CONTROL_H, "Cure everything", self, ISCDHealthDebugWindow.onClearAll)
    self.clearAllButton:initialise()
    self.clearAllButton:instantiate()
    self:addChild(self.clearAllButton)
end

function ISCDHealthDebugWindow:onApply()
    local ailment = healthDebugSelected(self.ailmentCombo)
    if ailment then
        CD.request("debughealth", self.animal, { action = "apply", ailment = ailment }, self.player)
    end
end

function ISCDHealthDebugWindow:onClear()
    local ailment = healthDebugSelected(self.ailmentCombo)
    if ailment then
        CD.request("debughealth", self.animal, { action = "clear", ailment = ailment }, self.player)
    end
end

function ISCDHealthDebugWindow:onClearAll()
    CD.request("debughealth", self.animal, { action = "clearAll" }, self.player)
end

function ISCDHealthDebugWindow:prerender()
    ISCollapsableWindow.prerender(self)
    if not self.animal or self.animal:isDead() then
        self:close()
    end
end

function ISCDHealthDebugWindow:close()
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    if ISCDHealthDebugWindow.instances[self.cdKey] == self then
        ISCDHealthDebugWindow.instances[self.cdKey] = nil
    end
end

function ISCDHealthDebugWindow.open(animal, player)
    if not animal or not CD.debugAllowed() then return end
    player = player or getPlayer()
    if not player then return end
    local pn = player:getPlayerNum()
    local key = tostring(CD.animKey(animal)) .. ":" .. tostring(pn)
    local win = ISCDHealthDebugWindow.instances[key]
    if win then
        win.animal = animal
        win.player = player
        win:setTitle(healthDebugTitle(animal))
        win:setVisible(true)
        win:bringToTop()
        return
    end
    win = ISCDHealthDebugWindow:new(animal, player, key)
    win:initialise()
    win:instantiate()
    local left, top, sw, sh = CD.UI.playerViewport(win)
    win:setX(left + math.max(0, math.floor((sw - win.width) / 2)))
    win:setY(top + math.max(0, math.floor((sh - win.height) / 2)))
    win:setRenderThisPlayerOnly(pn)
    win:addToUIManager()
    ISCDHealthDebugWindow.instances[key] = win
end
