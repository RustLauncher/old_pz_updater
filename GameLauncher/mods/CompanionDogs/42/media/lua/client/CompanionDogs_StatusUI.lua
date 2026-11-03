require "ISUI/ISCollapsableWindow"
require "ISUI/ISCollapsableWindowJoypad"
require "ISUI/ISButton"
require "ISUI/ISEquippedItem"
require "ISUI/ISTextBox"
require "ISUI/ISModalDialog"
require "ISUI/ISContextMenu"
require "ISUI/ISTabPanel"

CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

local function makeStashProxy(owner)
    local md = {}
    local function rec() return CD.playerData(owner).stash end
    return {
        getModData = function()
            local r = rec()
            md.CompanionDogs = (r and r.data) or {}
            return md
        end,
        getHunger = function()
            local r = rec()
            return (r and r.hunger) or 0
        end,
        getThirst = function()
            local r = rec()
            return (r and r.thirst) or 0
        end,
        getHealth = function()
            local r = rec()
            return (r and r.hp) or 1
        end,
        isExistInTheWorld = function() return true end,
    }
end

local function cdEachCarriedItem(container, fn)
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        fn(item)
        if instanceof(item, "InventoryContainer") then
            local inner = item:getInventory()
            if inner then
                cdEachCarriedItem(inner, fn)
            end
        end
    end
end

local function cdListFoods(playerObj, breedKey)
    local groups, order = {}, {}
    cdEachCarriedItem(playerObj:getInventory(), function(item)
        if instanceof(item, "Food") and not item:isRotten() and item:getHungerChange() < 0 then
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

local function cdFirstWaterIn(container)
    local list = container:getAllWaterFluidSources(true)
    if list and list:size() > 0 then return list:get(0) end
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if instanceof(item, "InventoryContainer") then
            local inner = item:getInventory()
            local found = inner and cdFirstWaterIn(inner)
            if found then return found end
        end
    end
    return nil
end

local function cdFirstWater(playerObj)
    return cdFirstWaterIn(playerObj:getInventory())
end

ISCDStatusWindow = ISCollapsableWindowJoypad:derive("ISCDStatusWindow")
ISCDTabView = ISPanel:derive("ISCDTabView")
ISCDStatusView = ISCDTabView:derive("ISCDStatusView")
ISCDHealthView = ISCDTabView:derive("ISCDHealthView")
ISCDCommandsView = ISCDTabView:derive("ISCDCommandsView")
ISCDLockedView = ISCDTabView:derive("ISCDLockedView")

local HEART_FULL = "media/ui/Sidebar/48/Heart_On_48.png"
local HEART_EMPTY = "media/ui/Sidebar/48/Heart_Off_48.png"
local HEART_COUNT = 5
local HEART_SIZE = 22
local HEART_GAP = 5

local WIN_W = 480
local MIN_W = 340
local MIN_H = 240
local PAD = 16
local SECT_GAP = 14
local ROW_GAP = 7
local DIVIDER_GAP = 12
local BTN_H = 28
local BTN_GAP = 8
local STEP_W = 30
local TRACK_H = 16

local HDR_H = 124
local HDR_PAD = 10
local HDR_AV = 112

local TAB_FONT = UIFont.NewSmall
local TAB_ZOOM = 0.90
local TAB_H_PAD = 8

local NEED_BAR_H = 14
local NEED_LABEL_W = 86
local NEED_VALUE_W = 42

local SKILL_BAR_H = 15
local SKILL_LABEL_W = 96
local SKILL_CELLS = 10
local SKILL_CELL_GAP = 3
local SKILL_TIP_W = 224

local TRAIT_BAR_H = 11
local TRAIT_LABEL_W = 116
local TRAIT_WORD_W = 60

local LBL = { r = 0.78, g = 0.80, b = 0.78 }
local DIV = { r = 1.0, g = 1.0, b = 1.0, a = 0.14 }
local BAR_BG = { r = 0.10, g = 0.10, b = 0.10, a = 0.85 }
local SKILL_FILL = { r = 0.45, g = 0.66, b = 0.40 }
local SKILL_PROG = { r = 0.62, g = 0.78, b = 0.55 }
local CELL_BG = { r = 0.09, g = 0.09, b = 0.09 }
local TRAIT_FILL = { r = 0.55, g = 0.62, b = 0.40 }

local function fh(font) return getTextManager():getFontHeight(font) end
local function strW(font, s) return getTextManager():MeasureStringX(font, s) end
local function lerp(a, b, t) return a + (b - a) * t end

local function cdLoadPaw(w)
    return getTexture("media/textures/CDDogPaw_" .. w .. ".png")
        or getTexture("CDDogPaw_" .. w)
end

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

local function renderTip(win, lines, mx, my)
    local font = UIFont.Small
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

function ISCDTabView:new(x, y, w, h)
    local o = ISPanel.new(self, x, y, w, h)
    o.background = false
    o.heartOn = getTexture(HEART_FULL)
    o.heartOff = getTexture(HEART_EMPTY)
    return o
end

function ISCDTabView:instantiate() CD.UI.viewInstantiate(self) end
function ISCDTabView:onMouseWheel(del) return CD.UI.viewMouseWheel(self, del) end

function ISCDTabView:dogName()
    local name
    if self.animal then
        name = CD.data(self.animal).name
    end
    return name or CD.breedNoun(self.animal)
end

function ISCDTabView:layout()
    local L = self:doLayout()
    self:setScrollHeight(L.contentH)
end

function ISCDTabView:prerender()
    CD.UI.viewBeginRender(self)
end

function ISCDTabView:render()
    self:drawContent()
    CD.UI.viewEndRender(self)
end

function ISCDTabView:makeBtn(w, text, onclick, internal)
    local b = ISButton:new(0, 0, w, BTN_H, text, self, onclick)
    b.internal = internal
    b:initialise()
    b:instantiate()
    b:setDisplayBackground(true)
    self:addChild(b)
    return b
end

function ISCDTabView:markActive(btn, active)
    if not btn then return end
    if active then
        btn:setBackgroundRGBA(0.24, 0.52, 0.30, 0.85)
        btn:setBorderRGBA(0.50, 0.85, 0.55, 1.0)
        btn.backgroundColorMouseOver = { r = 0.30, g = 0.62, b = 0.36, a = 0.95 }
    else
        btn:setBackgroundRGBA(0.10, 0.10, 0.10, 0.70)
        btn:setBorderRGBA(0.45, 0.45, 0.45, 0.70)
        btn.backgroundColorMouseOver = { r = 0.25, g = 0.25, b = 0.25, a = 0.85 }
    end
end

-- ISButton:setEnable reescreve background e border com um instantaneo tirado na PRIMEIRA chamada,
-- entao chamar por quadro depois do markActive congela o botao na cor daquele instante. Ordem
-- invertida e so na virada: quem desenha por ultimo e o markActive.
function ISCDTabView:markActiveEnabled(btn, enabled, active)
    if not btn then return end
    if btn.enable ~= enabled then
        btn:setEnable(enabled)
    end
    if enabled then
        self:markActive(btn, active)
    end
end

function ISCDTabView:drawDivider(y)
    local cw = CD.UI.viewContentW(self)
    self:drawRect(PAD, y, cw - PAD * 2, 1, DIV.a, DIV.r, DIV.g, DIV.b)
end

function ISCDTabView:drawNeedBar(label, y, fill, severity)
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

function ISCDTabView:drawSkillBar(label, y, level, into, need)
    local cw = CD.UI.viewContentW(self)
    local right = cw - PAD
    local sm = fh(UIFont.Small)
    local labelY = y + math.floor((SKILL_BAR_H - sm) / 2)
    self:drawText(label, PAD, labelY, 0.92, 0.92, 0.92, 1, UIFont.Small)

    local barX = PAD + SKILL_LABEL_W
    local barW = right - barX
    if barW < SKILL_CELLS then
        barW = SKILL_CELLS
    end
    local cellW = (barW - SKILL_CELL_GAP * (SKILL_CELLS - 1)) / SKILL_CELLS
    local frac = (need > 0) and (into / need) or 1
    if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end

    for i = 1, SKILL_CELLS do
        local cx = math.floor(barX + (i - 1) * (cellW + SKILL_CELL_GAP))
        local cw2 = math.floor(cellW + 0.5)
        self:drawRect(cx, y, cw2, SKILL_BAR_H, 0.85, CELL_BG.r, CELL_BG.g, CELL_BG.b)
        if i <= level then
            self:drawRect(cx, y, cw2, SKILL_BAR_H, 0.95, SKILL_FILL.r, SKILL_FILL.g, SKILL_FILL.b)
        elseif i == level + 1 and frac > 0 then
            self:drawRect(cx, y, math.max(1, math.floor(cw2 * frac)), SKILL_BAR_H, 0.95, SKILL_PROG.r, SKILL_PROG.g, SKILL_PROG.b)
        end
        self:drawRectBorder(cx, y, cw2, SKILL_BAR_H, 0.5, 0.55, 0.55, 0.55)
    end
end

function ISCDTabView:drawSkillTip(tip, mx, my)
    local font = UIFont.Small
    local title = getText("IGUI_PD_Skill_" .. tip.skill) .. "  " .. getText("IGUI_PD_SkillLevelFmt", tostring(tip.level))
    local xpLine
    if tip.level >= CD.SKILL_MAX_LEVEL then
        xpLine = "XP: MAX"
    else
        xpLine = string.format("XP: %d / %d", math.floor(tip.into), math.floor(tip.need))
    end

    local lines = { { t = title, c = { 1, 1, 1 } }, { t = xpLine, c = { 0.72, 0.82, 0.92 } } }
    if tip.mult and tip.mult ~= 1 then
        lines[#lines + 1] = { t = string.format("XP x%.1f", tip.mult), c = { 0.72, 0.82, 0.92 } }
    end
    lines[#lines + 1] = { t = "", c = { 1, 1, 1 } }
    local breedNoun = CD.breedNoun(self.animal)
    for _, l in ipairs(wrapText(font, getText("IGUI_PD_SkillDesc_" .. tip.skill, breedNoun), SKILL_TIP_W)) do
        lines[#lines + 1] = { t = l, c = { 0.84, 0.84, 0.84 } }
    end

    renderTip(self, lines, mx, my)
end

function ISCDTabView:drawInfoTip(title, body, mx, my)
    local font = UIFont.Small
    local lines = { { t = title, c = { 1, 1, 1 } }, { t = "", c = { 1, 1, 1 } } }
    for _, l in ipairs(wrapText(font, body, SKILL_TIP_W)) do
        lines[#lines + 1] = { t = l, c = { 0.84, 0.84, 0.84 } }
    end
    renderTip(self, lines, mx, my)
end

function ISCDTabView:drawTraitBar(label, y, ratio)
    local cw = CD.UI.viewContentW(self)
    local right = cw - PAD
    local sm = fh(UIFont.Small)
    local labelY = y + math.floor((TRAIT_BAR_H - sm) / 2)
    self:drawText(label, PAD, labelY, 0.92, 0.92, 0.92, 1, UIFont.Small)

    local wordKey = "IGUI_PD_TraitAvg"
    if ratio < 0.34 then wordKey = "IGUI_PD_TraitLow"
    elseif ratio > 0.66 then wordKey = "IGUI_PD_TraitHigh" end
    local word = getText(wordKey)
    self:drawText(word, right - strW(UIFont.Small, word), labelY, 0.78, 0.78, 0.78, 1, UIFont.Small)

    local barX = PAD + TRAIT_LABEL_W
    local barW = (right - TRAIT_WORD_W - 6) - barX
    if barW < 12 then
        barW = 12
    end
    self:drawRect(barX, y, barW, TRAIT_BAR_H, BAR_BG.a, BAR_BG.r, BAR_BG.g, BAR_BG.b)
    self:drawRectBorder(barX, y, barW, TRAIT_BAR_H, 0.5, 0, 0, 0)
    if ratio > 0 then
        self:drawRect(barX + 1, y + 1, math.floor((barW - 2) * ratio), TRAIT_BAR_H - 2, 0.95, TRAIT_FILL.r, TRAIT_FILL.g, TRAIT_FILL.b)
    end
end


local HEALTH_PART_TEXTURE = {
    head = "head", upperTorso = "upper_torso", lowerTorso = "lower_torso",
    rightFrontLeg = "right_front_leg", rightFrontPaw = "right_front_paw",
    leftFrontLeg = "left_front_leg", leftFrontPaw = "left_front_paw",
    rightBackLeg = "right_back_leg", rightBackPaw = "right_back_paw",
    leftBackLeg = "left_back_leg", leftBackPaw = "left_back_paw", tail = "tail",
    stomach = "lower_torso", lungs = "upper_torso", heart = "upper_torso",
}

local HEALTH_PART_ANCHOR = {
    head = { 0.176, 0.448 }, upperTorso = { 0.377, 0.501 }, lowerTorso = { 0.606, 0.390 },
    rightFrontLeg = { 0.296, 0.743 }, rightFrontPaw = { 0.257, 0.883 },
    leftFrontLeg = { 0.378, 0.741 }, leftFrontPaw = { 0.322, 0.961 },
    rightBackLeg = { 0.599, 0.638 }, rightBackPaw = { 0.557, 0.733 },
    leftBackLeg = { 0.724, 0.563 }, leftBackPaw = { 0.714, 0.749 }, tail = { 0.858, 0.164 },
    stomach = { 0.600, 0.400 }, lungs = { 0.420, 0.470 }, heart = { 0.330, 0.520 },
}
local HEALTH_COLOR = {
    [0] = { 0.20, 0.80, 0.28, 0.72 },
    [1] = { 0.95, 0.86, 0.18, 0.74 },
    [2] = { 0.72, 0.58, 0.10, 0.78 },
    [3] = { 0.88, 0.18, 0.14, 0.82 },
}
local HEALTH_PART_SCORE = { [0] = 100, [1] = 75, [2] = 50, [3] = 25 }
local HEALTH_CARD_PAD = 10
local HEALTH_COND_PAD = 5
local HEALTH_COL_GAP = 12
local HEALTH_STACK_W = 400
local HEALTH_DOT = 10
local HEALTH_BAR_H = 16
local HEALTH_GLOW_SCALE = 1.06
local HEALTH_NAME_COLOR = {
    [0] = { 0.55, 0.85, 0.55 },
    [1] = { 1.00, 0.88, 0.30 },
    [2] = { 0.98, 0.72, 0.18 },
    [3] = { 0.95, 0.22, 0.18 },
}
local HEALTH_PAW_PART = { front = "rightFrontPaw", back = "rightBackPaw" }
local HEALTH_LEG_PART = { front = "rightFrontLeg", back = "rightBackLeg" }

-- Doenca com remedio correndo e doenca com protecao carimbada aparecem na lista pelo mesmo molde:
-- uma linha por curso e uma por janela, e o nome vem da propria doenca. `own` e o relogio da doenca
-- que passa sozinha: acabando antes do curso, a cura vem por ele.
local VET_COURSES = {
    { field = "vetCourseFlu", nameKey = "IGUI_PD_HealthCondition_canineFlu", own = "vetFluMin" },
    { field = "vetCourseHw", nameKey = "IGUI_PD_HealthCondition_heartwormDisease", own = "vetHwMin" },
    { field = "vetCourseAlg", nameKey = "IGUI_PD_HealthCondition_skinAllergy", own = "vetAlgMin" },
    { field = "vetCourseFlea", nameKey = "IGUI_PD_VetRow_infest" },
    { field = "vetCourseWorms", nameKey = "IGUI_PD_HealthCondition_intestinalParasite" },
}
local VET_PREVENTS = {
    { field = "vetDewormPrevUntilMin", nameKey = "IGUI_PD_HealthCondition_intestinalParasite" },
    { field = "vetHwPrevUntilMin", nameKey = "IGUI_PD_HealthCondition_heartwormDisease" },
    { field = "vetAlgPrevUntilMin", nameKey = "IGUI_PD_HealthCondition_skinAllergy" },
    { field = "vetFleaPrevUntilMin", nameKey = "IGUI_PD_VetRow_infest" },
}
-- Alergia de bicho nao tem carne por tras: a linha sai sem o nome do alimento.
local ALLERGY_NO_PROTEIN = { fleas = true, ticks = true, debug = true }

local function allergyPartList(d)
    local ids = {}
    for id in string.gmatch(d.vetAlgParts or "", "[^,]+") do
        ids[#ids + 1] = id
    end
    return ids
end

local function vetHours(min)
    return tostring(math.max(1, math.ceil(min / 60)))
end

-- Tudo que muda o desenho ou a lista, quantizado: os relogios entram de 15 em 15 minutos, o passo da
-- passada do vet, senao o retrato seria refeito a cada minuto de jogo.
local function healthSig(animal)
    local d = CD.data(animal)
    local pct = 0
    if d.vetKind ~= nil then
        local done = d.vetCureMin or 0
        if (d.vetStage or 0) >= 1 then
            done = d.vetInfectMin or 0
        end
        pct = math.floor((done / CD.vetHealGoal(d)) * 100)
    end
    local courses, prevents, aids = {}, {}, {}
    for i = 1, #VET_COURSES do
        courses[i] = tostring(d[VET_COURSES[i].field] ~= nil)
    end
    for i = 1, #VET_PREVENTS do
        prevents[i] = tostring(d[VET_PREVENTS[i].field] ~= nil)
    end
    for i = 1, #CD.VET_AID_ROWS do
        aids[i] = tostring(d[CD.VET_AID_ROWS[i].field] ~= nil)
    end
    aids[#aids + 1] = tostring(d.vetPickedMin ~= nil) .. tostring(d.vetGarlicMin ~= nil)
    aids[#aids + 1] = tostring(d.vetGastroEased ~= nil) .. tostring(d.vetToxicEased ~= nil)
    aids[#aids + 1] = tostring(CD.vetProtected(d, "vetBoostUntilMin", CD.worldMinutes()))
    aids[#aids + 1] = tostring(math.floor(CD.worldMinutes() / CD.VET_TICK_INTERVAL_MIN))
    return table.concat({
        tostring(CD.vetCareEnabled()), tostring(d.vetKind), tostring(d.vetPaw), tostring(d.vetStage or 0),
        tostring(d.vetBroken ~= nil), tostring(d.vetDress or 0), tostring(d.vetDressDirty ~= nil),
        tostring(d.vetCrit ~= nil), tostring(CD.vetBleeding(animal)), tostring(d.vetAbxMin ~= nil),
        tostring(d.vetGastroMin ~= nil), tostring(d.vetWorms ~= nil), tostring(d.vetDewormMin ~= nil),
        tostring(CD.isSick(animal)), tostring(CD.vetImmune(animal)), tostring(pct),
        tostring(d.vetFluMin ~= nil), tostring(d.vetFluQuiet ~= nil), tostring(d.vetHwMin ~= nil),
        tostring(d.vetAlgParts), tostring(d.vetAlgSrc), tostring(d.vetAllergenKnown ~= nil),
        tostring(d.vetFleas ~= nil), tostring(d.vetTicks ~= nil),
        table.concat(courses, ","), table.concat(prevents, ","), table.concat(aids, ","),
    }, "|")
end

local function healthSnapshot(animal, owner)
    local d = CD.data(animal)
    local parts = {}
    for _, id in ipairs(CD.HEALTH_BODY_PARTS) do parts[id] = 0 end
    local conditions = {}
    local function mark(ids, severity)
        for _, id in ipairs(ids) do
            parts[id] = math.max(parts[id] or 0, severity)
        end
    end
    local function add(name, description, severity)
        conditions[#conditions + 1] = { name = name, description = description, severity = severity }
    end
    local info = CD.vetInfo(animal, owner)
    if info and info.title then
        local paw = HEALTH_PAW_PART[d.vetPaw]
        local leg = HEALTH_LEG_PART[d.vetPaw]
        if paw == nil then
            paw = "lowerTorso"
        end
        mark({ paw }, 3)
        if d.vetBroken ~= nil and leg then
            mark({ leg }, 3)
        end
        if d.vetCrit ~= nil then
            mark({ "heart" }, 3)
        end
        local desc = info.symptom
        if info.dress then
            desc = desc .. " " .. info.dress
        end
        if info.progress then
            desc = desc .. " " .. info.progress
        end
        add(info.title, desc, 3)
    end
    if CD.vetFeverFrom(d) then
        -- Febre e do corpo todo: pulmao e estomago ficam de fora para a gripe e o estomago virado
        -- acenderem a propria parte por cima.
        local body = {}
        for _, id in ipairs(CD.HEALTH_BODY_PARTS) do
            if id ~= "lungs" and id ~= "stomach" then
                body[#body + 1] = id
            end
        end
        mark(body, 2)
    end
    if d.vetFluMin ~= nil then
        mark({ "lungs" }, 3)
    end
    if d.vetHwMin ~= nil then
        mark({ "heart" }, 3)
    end
    if d.vetAlgMin ~= nil then
        mark(allergyPartList(d), 2)
    end
    if d.vetTicks ~= nil then
        mark(CD.HEALTH_EXTERNAL_PARTS, 2)
    elseif d.vetFleas ~= nil then
        mark(CD.HEALTH_EXTERNAL_PARTS, 1)
    end
    if d.vetGastroMin ~= nil or d.vetWorms ~= nil or CD.isSick(animal) then
        mark({ "stomach" }, 2)
    end
    if info then
        for _, row in ipairs(info.extras) do
            local severity = row.sev or 2
            if row.good then
                severity = 0
            end
            add(row.text, row.tip, severity)
        end
    end
    if #conditions == 0 then
        add(getText("IGUI_PD_HealthNoConditions"), nil, 0)
    end
    local visual = {}
    local total, count = 0, 0
    for id, severity in pairs(parts) do
        local texture = HEALTH_PART_TEXTURE[id]
        if texture then
            visual[texture] = math.max(visual[texture] or 0, severity)
        end
        total = total + (HEALTH_PART_SCORE[severity] or 100)
        count = count + 1
    end
    local percent = 100
    if count > 0 then
        percent = math.floor(total / count + 0.5)
    end
    return {
        sig = healthSig(animal),
        parts = parts,
        visual = visual,
        conditions = conditions,
        conditionPercent = percent,
    }
end

function ISCDHealthView:new(x, y, w, h)
    local o = ISCDTabView.new(self, x, y, w, h)
    o.healthBase = getTexture("media/ui/CDHealth/base.png")
    o.healthLayers = {}
    for _, texture in pairs(HEALTH_PART_TEXTURE) do
        if o.healthLayers[texture] == nil then
            o.healthLayers[texture] = getTexture("media/ui/CDHealth/" .. texture .. ".png")
        end
    end
    return o
end

-- Moldura comum do painel: fundo fosco e borda discreta.
local function drawCard(view, x, y, w, h)
    view:drawRect(x, y, w, h, 0.55, 0.07, 0.07, 0.07)
    view:drawRectBorder(x, y, w, h, 0.75, 0.36, 0.36, 0.36)
end

-- Geometria inteira da aba num passo so: desenho e lista lado a lado enquanto couber, empilhados
-- em janela estreita. Quem desenha nao recalcula nada, so le.
local function healthLayout(view, snapshot)
    local cw = CD.UI.viewContentW(view)
    local smallH = fh(UIFont.Small)
    local medH = fh(UIFont.Medium)
    local rowH = smallH + 6
    local headerH = medH + 6
    local L = { cw = cw, smallH = smallH, rowH = rowH, rows = {}, conditions = {} }

    local labelW = 0
    for _, id in ipairs(CD.HEALTH_BODY_PARTS) do
        labelW = math.max(labelW, strW(UIFont.Small, getText("IGUI_PD_HealthPart_" .. id)))
    end
    local partsW = labelW + HEALTH_DOT + 20 + strW(UIFont.Small, ">") + HEALTH_CARD_PAD * 2
    partsW = math.min(math.max(partsW, 150), math.floor(cw * 0.42))
    local colW = cw - PAD * 2 - partsW - HEALTH_COL_GAP
    L.stacked = cw < HEALTH_STACK_W or colW < 190
    if L.stacked then
        colW = cw - PAD * 2
        partsW = colW
    end
    L.colW = colW

    local dogSize = math.min(colW - HEALTH_CARD_PAD * 2, 240)
    L.diagram = { x = PAD, y = PAD, w = colW, h = HEALTH_CARD_PAD * 2 + headerH + dogSize }
    L.dog = {
        x = PAD + math.floor((colW - dogSize) / 2),
        y = PAD + HEALTH_CARD_PAD + headerH,
        size = dogSize,
    }

    local partsH = HEALTH_CARD_PAD * 2 + headerH + #CD.HEALTH_BODY_PARTS * rowH + 9
    local flowY
    if L.stacked then
        L.parts = { x = PAD, y = L.diagram.y + L.diagram.h + HEALTH_COL_GAP, w = partsW, h = partsH }
        flowY = L.parts.y + partsH + SECT_GAP
    else
        L.parts = { x = PAD + colW + HEALTH_COL_GAP, y = PAD, w = partsW, h = partsH }
        flowY = L.diagram.y + L.diagram.h + SECT_GAP
    end

    local ry = L.parts.y + HEALTH_CARD_PAD + headerH
    for i, id in ipairs(CD.HEALTH_BODY_PARTS) do
        if i == #CD.HEALTH_EXTERNAL_PARTS + 1 then
            L.dividerY = ry + 4
            ry = ry + 9
        end
        L.rows[i] = { id = id, y = ry }
        ry = ry + rowH
    end

    L.overallLabelY = flowY
    L.barY = flowY + headerH
    local y = L.barY + HEALTH_BAR_H + 12

    -- O cartao mostra so o nome; a explicacao fica no tooltip, senao tres condicoes juntas viram
    -- uma parede de texto no meio da aba.
    local textW = colW - HEALTH_CARD_PAD * 2
    for _, condition in ipairs(snapshot.conditions) do
        local entry = {
            y = y,
            color = HEALTH_NAME_COLOR[condition.severity] or HEALTH_NAME_COLOR[2],
            name = condition.name,
            nameLines = wrapText(UIFont.Small, condition.name, textW),
        }
        if condition.description and condition.description ~= "" then
            entry.tip = condition.description
        end
        entry.h = HEALTH_COND_PAD * 2 + #entry.nameLines * (smallH + 2)
        L.conditions[#L.conditions + 1] = entry
        y = y + entry.h + 6
    end

    if not CD.deathEnabled() then
        L.deathLines = wrapText(UIFont.Small, getText("IGUI_PD_HealthDeathDisabled"), colW)
        L.deathY = y + 4
        y = L.deathY + #L.deathLines * (smallH + 2)
    end

    L.contentH = math.max(y, L.parts.y + L.parts.h) + PAD
    return L
end

-- Parte em foco: a linha sob o mouse, a camada mais proxima do cursor no desenho ou, sem mouse, a
-- mais grave. E ela que acende e recebe o balão.
local function healthActivePart(L, snapshot, over, mx, my)
    if over then
        if mx >= L.parts.x and mx < L.parts.x + L.parts.w then
            for _, row in ipairs(L.rows) do
                if my >= row.y and my < row.y + L.rowH then
                    return row.id
                end
            end
        end
        local d = L.dog
        if mx >= d.x and mx < d.x + d.size and my >= d.y and my < d.y + d.size then
            local best, bestDist
            local limit = d.size * 0.13
            for id, anchor in pairs(HEALTH_PART_ANCHOR) do
                local dx = (d.x + anchor[1] * d.size) - mx
                local dy = (d.y + anchor[2] * d.size) - my
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist < limit and (bestDist == nil or dist < bestDist) then
                    best, bestDist = id, dist
                end
            end
            if best then
                return best
            end
        end
    end
    local worst, worstSeverity = nil, 0
    for _, id in ipairs(CD.HEALTH_BODY_PARTS) do
        local severity = snapshot.parts[id] or 0
        if severity > worstSeverity then
            worst, worstSeverity = id, severity
        end
    end
    return worst
end

local function drawHealthCallout(view, L, id, color)
    local d = L.dog
    local anchor = HEALTH_PART_ANCHOR[id]
    local ax = math.floor(d.x + anchor[1] * d.size)
    local ay = math.floor(d.y + anchor[2] * d.size)
    local label = getText("IGUI_PD_HealthPart_" .. id)
    local bw = strW(UIFont.Small, label) + 14
    local bh = L.smallH + 8
    local card = L.diagram
    local bx = (anchor[1] < 0.5) and (ax + 28) or (ax - 28 - bw)
    bx = math.floor(CD.UI.clamp(bx, card.x + 6, card.x + card.w - bw - 6))
    local by = math.floor(CD.UI.clamp(ay - bh / 2, card.y + 6, card.y + card.h - bh - 6))
    local lx = ax
    if ax > bx + bw then
        lx = bx + bw
    elseif ax < bx then
        lx = bx
    end
    view:drawLine2(lx, by + math.floor(bh / 2), ax, ay, 0.85, color[1], color[2], color[3])
    view:drawRect(bx, by, bw, bh, 0.90, 0.05, 0.05, 0.05)
    view:drawRectBorder(bx, by, bw, bh, 0.90, color[1], color[2], color[3])
    view:drawText(label, bx + 7, by + 4, color[1], color[2], color[3], 1, UIFont.Small)
    view:drawRect(ax - 2, ay - 2, 5, 5, 0.95, color[1], color[2], color[3])
end

function ISCDHealthView:doLayout()
    self.snapshot = healthSnapshot(self.animal, self.owner)
    self.L = healthLayout(self, self.snapshot)
    return self.L
end

function ISCDHealthView:drawContent()
    local animal = self.animal
    if not animal then return end
    if self.snapshot == nil or self.snapshot.sig ~= healthSig(animal) then
        self.snapshot = healthSnapshot(animal, self.owner)
        self.L = nil
    end
    local snap = self.snapshot
    local L = self.L
    if L == nil or L.cw ~= CD.UI.viewContentW(self) then
        L = healthLayout(self, snap)
        self.L = L
        self:setScrollHeight(L.contentH)
    end
    local over = self:isMouseOver() or self:isMouseOverChild()
    local mx, my = self:getMouseX(), self:getMouseY()
    local active = healthActivePart(L, snap, over, mx, my)
    local activeSeverity = (active and snap.parts[active]) or 0

    drawCard(self, L.diagram.x, L.diagram.y, L.diagram.w, L.diagram.h)
    self:drawText(getText("IGUI_PD_HealthDiagram"), L.diagram.x + HEALTH_CARD_PAD,
        L.diagram.y + HEALTH_CARD_PAD, LBL.r, LBL.g, LBL.b, 1, UIFont.Medium)
    local d = L.dog
    if self.healthBase then
        self:drawTextureScaled(self.healthBase, d.x, d.y, d.size, d.size, 1, 1, 1, 1)
    end
    for texture, severity in pairs(snap.visual) do
        local layer = self.healthLayers[texture]
        local color = HEALTH_COLOR[severity] or HEALTH_COLOR[0]
        if layer then
            self:drawTextureScaled(layer, d.x, d.y, d.size, d.size, color[4], color[1], color[2], color[3])
        end
    end
    if active then
        -- A camada da parte em foco volta um pouco maior, ancorada no proprio centro de massa, com
        -- o alpha respirando: e o brilho que liga o balao ao desenho.
        local layer = self.healthLayers[HEALTH_PART_TEXTURE[active]]
        local anchor = HEALTH_PART_ANCHOR[active]
        if layer then
            local color = HEALTH_COLOR[activeSeverity] or HEALTH_COLOR[0]
            local glow = 0.16 + 0.14 * math.abs(math.sin(getTimestampMs() / 420))
            local grow = d.size * (1 - HEALTH_GLOW_SCALE)
            self:drawTextureScaled(layer, d.x + anchor[1] * grow, d.y + anchor[2] * grow,
                d.size * HEALTH_GLOW_SCALE, d.size * HEALTH_GLOW_SCALE, glow, color[1], color[2], color[3])
        end
        if not L.stacked then
            drawHealthCallout(self, L, active, HEALTH_NAME_COLOR[activeSeverity] or HEALTH_NAME_COLOR[0])
        end
    end

    drawCard(self, L.parts.x, L.parts.y, L.parts.w, L.parts.h)
    self:drawText(getText("IGUI_PD_HealthBodyParts"), L.parts.x + HEALTH_CARD_PAD,
        L.parts.y + HEALTH_CARD_PAD, LBL.r, LBL.g, LBL.b, 1, UIFont.Medium)
    if L.dividerY then
        self:drawRect(L.parts.x + HEALTH_CARD_PAD, L.dividerY, L.parts.w - HEALTH_CARD_PAD * 2, 1,
            DIV.a, DIV.r, DIV.g, DIV.b)
    end
    local dotX = L.parts.x + HEALTH_CARD_PAD
    for _, row in ipairs(L.rows) do
        local severity = snap.parts[row.id] or 0
        local color = HEALTH_COLOR[severity] or HEALTH_COLOR[0]
        if row.id == active then
            local hi = HEALTH_NAME_COLOR[severity] or HEALTH_NAME_COLOR[0]
            self:drawRect(L.parts.x + 2, row.y, L.parts.w - 4, L.rowH, 0.22, hi[1], hi[2], hi[3])
            self:drawRectBorder(L.parts.x + 2, row.y, L.parts.w - 4, L.rowH, 0.75, hi[1], hi[2], hi[3])
            local chevron = ">"
            self:drawText(chevron, L.parts.x + L.parts.w - HEALTH_CARD_PAD - strW(UIFont.Small, chevron),
                row.y + math.floor((L.rowH - L.smallH) / 2), hi[1], hi[2], hi[3], 1, UIFont.Small)
        end
        local dotY = row.y + math.floor((L.rowH - HEALTH_DOT) / 2)
        self:drawRect(dotX, dotY, HEALTH_DOT, HEALTH_DOT, color[4], color[1], color[2], color[3])
        self:drawRectBorder(dotX, dotY, HEALTH_DOT, HEALTH_DOT, 0.8, 0.45, 0.45, 0.45)
        self:drawText(getText("IGUI_PD_HealthPart_" .. row.id), dotX + HEALTH_DOT + 8,
            row.y + math.floor((L.rowH - L.smallH) / 2), 0.92, 0.92, 0.92, 1, UIFont.Small)
    end

    self:drawText(getText("IGUI_PD_HealthOverall"), PAD, L.overallLabelY, 1, 1, 1, 1, UIFont.Medium)
    local hp = animal:getHealth()
    local maxHealth = CD.data(animal).maxHealth or 1
    local hpPercent = 0
    if maxHealth > 0 then
        hpPercent = math.floor(math.max(0, math.min(1, hp / maxHealth)) * 100 + 0.5)
    end
    local pct = math.min(hpPercent, snap.conditionPercent)
    local pctText = tostring(pct) .. "%"
    local pctW = strW(UIFont.Small, pctText)
    local barW = L.colW - pctW - 10
    local pr, pg, pb = severityColor(1 - pct / 100)
    self:drawRect(PAD, L.barY, barW, HEALTH_BAR_H, BAR_BG.a, BAR_BG.r, BAR_BG.g, BAR_BG.b)
    self:drawRectBorder(PAD, L.barY, barW, HEALTH_BAR_H, 0.5, 0, 0, 0)
    if pct > 0 then
        self:drawRect(PAD + 1, L.barY + 1, math.floor((barW - 2) * pct / 100), HEALTH_BAR_H - 2, 0.95, pr, pg, pb)
    end
    self:drawText(pctText, PAD + L.colW - pctW, L.barY + math.floor((HEALTH_BAR_H - L.smallH) / 2),
        pr, pg, pb, 1, UIFont.Small)

    local tip = nil
    for _, entry in ipairs(L.conditions) do
        drawCard(self, PAD, entry.y, L.colW, entry.h)
        if entry.tip and over and mx >= PAD and mx < PAD + L.colW
            and my >= entry.y and my < entry.y + entry.h then
            self:drawRect(PAD, entry.y, L.colW, entry.h, 0.10, 1, 1, 1)
            tip = entry
        end
        local tx = PAD + HEALTH_CARD_PAD
        local ty = entry.y + HEALTH_COND_PAD
        for _, line in ipairs(entry.nameLines) do
            self:drawText(line, tx, ty, entry.color[1], entry.color[2], entry.color[3], 1, UIFont.Small)
            ty = ty + L.smallH + 2
        end
    end
    if L.deathLines then
        local deathY = L.deathY
        for _, line in ipairs(L.deathLines) do
            self:drawText(line, PAD, deathY, 0.58, 0.78, 0.58, 1, UIFont.Small)
            deathY = deathY + L.smallH + 2
        end
    end
    if tip then
        self:drawInfoTip(tip.name, tip.tip, mx, my)
    end
end

local function openTreatMenu(owner, animal)
    local menu = ISContextMenu.get(owner:getPlayerNum(), getMouseX(), getMouseY())
    CD.buildTreatMenu(menu, owner, animal)
    if menu.numOptions <= 1 then
        local opt = menu:addOption(getText("IGUI_PD_VetNothingToDo"), nil, nil)
        opt.notAvailable = true
    end
end

function ISCDHealthView:onRightMouseUp(x, y)
    if self.animal and self.owner and not self.stashed then
        openTreatMenu(self.owner, self.animal)
        return true
    end
    return ISPanel.onRightMouseUp(self, x, y)
end

local function woundKeys(kind, stage, broken, infected, crit)
    if crit then return "critical", "critical" end
    if stage >= 2 then return "fever", "fever" end
    if kind == "sprain" then return "sprain", "sprain" end
    if broken then return "fracture", infected and "infected" or "fracture" end
    if infected then return "infected", "infected" end
    return "cut", "cut"
end

---@param animal IsoAnimal|table the dog, or the stash proxy
---@param player IsoPlayer|nil whose Husbandry decides whether the diagnosis lines show
---@return table|nil info wound fields (title, dress, symptom, todo, progress) plus `extras`, one row per other condition
function CD.vetInfo(animal, player)
    if not CD.vetCareEnabled() then return nil end
    local d = CD.data(animal)
    local now = CD.worldMinutes()
    local diag = player ~= nil and player:getPerkLevel(Perks.Husbandry) >= CD.VET_DIAG_HUSBANDRY
    local info = { extras = {} }
    local kind, stage = CD.vetCondition(animal)
    if kind then
        stage = stage or 0
        local infected = stage >= 1
        local broken = d.vetBroken ~= nil
        local dress = d.vetDress or 0
        local cond = "cut"
        local suffix = ""
        if kind == "sprain" then
            cond = "sprain"
        elseif broken then
            cond = "fracture"
            if infected then
                suffix = "_infected"
            end
        elseif infected then
            suffix = "_infected"
        elseif dress >= 1 then
            suffix = "_dressed"
        elseif kind == "cut" and not CD.vetBleeding(animal) then
            suffix = "_open"
        end
        local title = getText("IGUI_PD_VetCond_" .. cond .. suffix)
        local crit = infected and d.vetCrit ~= nil
        if crit then
            title = title .. " " .. getText("IGUI_PD_VetStage_3")
        elseif stage >= 2 then
            title = title .. " " .. getText("IGUI_PD_VetStage_2")
        end
        if d.vetPaw == "front" or d.vetPaw == "back" then
            title = title .. " (" .. getText("IGUI_PD_VetPaw_" .. d.vetPaw) .. ")"
        end
        local symptom, todo = woundKeys(kind, stage, broken, infected, crit)
        if symptom == "cut" and not CD.vetBleeding(animal) then
            symptom = "cut_open"
        end
        info.title = title
        info.infected = infected
        info.broken = broken
        info.symptom = getText("IGUI_PD_VetSymptom_" .. symptom)
        info.todo = getText("IGUI_PD_VetTodo_" .. todo)
        if kind == "cut" then
            local dk = tostring(dress)
            if d.vetDressDirty ~= nil then
                dk = "dirty"
            end
            info.dress = getText("IGUI_PD_VetDress_" .. dk)
        end
        if diag then
            local done = d.vetCureMin or 0
            if stage >= 1 then
                done = d.vetInfectMin or 0
            end
            local pct = math.floor((done / CD.vetHealGoal(d)) * 100 + 0.5)
            if pct > 99 then
                pct = 99
            end
            info.progress = getText("IGUI_PD_VetProgress", tostring(pct))
        end
    end
    -- Uma linha por doenca tratada, com a hora da cura: vale o que acabar primeiro, o remedio ou a
    -- propria doenca. Antibiotico nao cura gripe, so corta o que sobrar dela quando a dose acaba.
    local rate = CD.vetRecoveryRate(d)
    local cures, order = {}, {}
    local function cure(nameKey, left)
        if cures[nameKey] == nil then
            order[#order + 1] = nameKey
        elseif cures[nameKey] <= left then
            return
        end
        cures[nameKey] = left
    end
    local abxShown = false
    if kind and stage >= 1 and (d.vetAbxMin ~= nil or d.vetGarlicMin ~= nil) then
        local left = (CD.VET_INFECT_HEAL_MIN - (d.vetInfectMin or 0)) / rate
        cure("IGUI_PD_HealthCondition_woundInfection", math.min(left, d.vetAbxMin or left, d.vetGarlicMin or left))
        abxShown = d.vetAbxMin ~= nil
    end
    for i = 1, #VET_COURSES do
        local row = VET_COURSES[i]
        local left = d[row.field]
        if left ~= nil then
            local own = row.own and d[row.own]
            if own ~= nil then
                left = math.min(left, own / rate)
            end
            cure(row.nameKey, left)
        end
    end
    if d.vetAbxMin ~= nil and d.vetFluMin ~= nil then
        local left = d.vetFluMin / rate
        if left > d.vetAbxMin then
            left = d.vetAbxMin + (left - d.vetAbxMin) * CD.VET_FLU_ABX_CUT
        end
        cure("IGUI_PD_HealthCondition_canineFlu", left)
        abxShown = true
    end
    if d.vetWorms ~= nil and d.vetDewormMin ~= nil then
        cure("IGUI_PD_HealthCondition_intestinalParasite", d.vetDewormMin - (CD.VET_DEWORM_MIN - CD.VET_DEWORM_ACT_MIN))
    end
    -- Camomila e detox agem na hora e nao abrem curso: a marca mostra o tratamento enquanto a doenca dura.
    if d.vetGastroEased ~= nil and d.vetGastroMin ~= nil then
        cure("IGUI_PD_HealthCondition_gastroenteritis", d.vetGastroMin / rate)
    end
    if d.vetToxicEased ~= nil and CD.isSick(animal) then
        cure("IGUI_PD_HealthCondition_toxic", (d.sickUntilMin - now) / rate)
    end
    if d.vetGastroMin ~= nil then
        local text = getText("IGUI_PD_VetRow_gastro")
        if diag and cures.IGUI_PD_HealthCondition_gastroenteritis == nil then
            text = text .. " (" .. getText("IGUI_PD_VetHoursLeft", vetHours(d.vetGastroMin / rate)) .. ")"
        end
        info.extras[#info.extras + 1] = { text = text,
            tip = getText("IGUI_PD_VetSymptom_gastro") .. " " .. getText("IGUI_PD_VetTodo_gastro") }
    end
    if d.vetWorms ~= nil then
        info.extras[#info.extras + 1] = { text = getText("IGUI_PD_VetRow_worms"),
            tip = getText("IGUI_PD_VetSymptom_worms") .. " " .. getText("IGUI_PD_VetTodo_worms") }
    end
    -- Com o verme ainda no cao a linha e a do tratamento; depois, o resto da dose e so protecao.
    if d.vetDewormMin ~= nil and d.vetWorms == nil then
        info.extras[#info.extras + 1] = {
            text = getText("IGUI_PD_VetRow_deworm") .. " (" .. getText("IGUI_PD_VetHoursLeft", vetHours(d.vetDewormMin)) .. ")",
            tip = getText("IGUI_PD_VetRowTip_deworm"), good = true,
        }
    end
    if d.vetFluMin ~= nil then
        local text = getText("IGUI_PD_HealthCondition_canineFlu")
        if diag and cures.IGUI_PD_HealthCondition_canineFlu == nil then
            text = text .. " (" .. getText("IGUI_PD_VetHoursLeft", vetHours(d.vetFluMin / rate)) .. ")"
        end
        info.extras[#info.extras + 1] = { text = text, sev = 3,
            tip = getText("IGUI_PD_VetSymptom_flu") .. " " .. getText("IGUI_PD_VetTodo_flu") }
    end
    if d.vetHwMin ~= nil then
        local text = getText("IGUI_PD_HealthCondition_heartwormDisease")
        if diag and cures.IGUI_PD_HealthCondition_heartwormDisease == nil then
            text = text .. " (" .. getText("IGUI_PD_VetHoursLeft", vetHours(d.vetHwMin / rate)) .. ")"
        end
        info.extras[#info.extras + 1] = { text = text, sev = 3,
            tip = getText("IGUI_PD_VetSymptom_heartworm") .. " " .. getText("IGUI_PD_VetTodo_heartworm") }
    end
    if d.vetAlgMin ~= nil then
        local text = getText("IGUI_PD_HealthCondition_skinAllergy")
        local src = d.vetAlgSrc
        if src ~= nil and not ALLERGY_NO_PROTEIN[src] then
            text = text .. " (" .. getText("IGUI_PD_VetProtein_" .. src) .. ")"
        end
        info.extras[#info.extras + 1] = { text = text,
            tip = getText("IGUI_PD_VetSymptom_allergy") .. " " .. getText("IGUI_PD_VetTodo_allergy") }
    end
    -- A carne sorteada so aparece depois da primeira reacao; a crise em curso ja conta, para cao de
    -- save de antes da marca.
    local allergen = d.vetAllergen
    if allergen ~= nil and (d.vetAllergenKnown ~= nil or d.vetAlgSrc == allergen) then
        local food = getText("IGUI_PD_VetProtein_" .. allergen)
        info.extras[#info.extras + 1] = { text = getText("IGUI_PD_VetAllergicTo", food),
            tip = getText("IGUI_PD_VetAllergicToTip", food) }
    end
    if d.vetTicks ~= nil then
        info.extras[#info.extras + 1] = { text = getText("IGUI_PD_HealthCondition_ticks"),
            tip = getText("IGUI_PD_VetSymptom_ticks") .. " " .. getText("IGUI_PD_VetTodo_infest") }
    end
    if d.vetFleas ~= nil then
        info.extras[#info.extras + 1] = { text = getText("IGUI_PD_HealthCondition_fleas"), sev = 1,
            tip = getText("IGUI_PD_VetSymptom_fleas") .. " " .. getText("IGUI_PD_VetTodo_infest") }
    end
    for i = 1, #order do
        info.extras[#info.extras + 1] = {
            text = getText("IGUI_PD_VetRow_courseCure", getText(order[i]), vetHours(cures[order[i]])),
            tip = getText("IGUI_PD_VetRowTip_course"), good = true,
        }
    end
    if d.vetAbxMin ~= nil and not abxShown then
        info.extras[#info.extras + 1] = {
            text = getText("IGUI_PD_VetRow_abx") .. " (" .. getText("IGUI_PD_VetHoursLeft", vetHours(d.vetAbxMin)) .. ")",
            tip = getText("IGUI_PD_VetRowTip_abx"), good = true,
        }
    end
    for i = 1, #VET_PREVENTS do
        local row = VET_PREVENTS[i]
        if CD.vetProtected(d, row.field, now) then
            local days = math.ceil((d[row.field] - now) / 1440)
            info.extras[#info.extras + 1] = {
                text = getText("IGUI_PD_VetRow_prev", getText(row.nameKey), tostring(days)),
                tip = getText("IGUI_PD_VetRowTip_prev"), good = true,
            }
        end
    end
    if CD.vetImmuneFrom(d, now) then
        local days = math.ceil((d.vetImmuneUntilMin - now) / 1440)
        info.extras[#info.extras + 1] = { text = getText("IGUI_PD_VetRow_immune", tostring(days)),
            tip = getText("IGUI_PD_VetRowTip_immune"), good = true }
    end
    for i = 1, #CD.VET_AID_ROWS do
        local row = CD.VET_AID_ROWS[i]
        local left = d[row.field]
        if left ~= nil then
            local text = getText("IGUI_PD_VetRow_aid", getItemNameFromFullType(row.item))
            if row.timed then
                text = text .. " (" .. getText("IGUI_PD_VetHoursLeft", vetHours(left)) .. ")"
            end
            info.extras[#info.extras + 1] = { text = text, tip = getText("IGUI_PD_VetRowTip_aid"), good = true }
        end
    end
    if d.vetPickedMin ~= nil then
        info.extras[#info.extras + 1] = {
            text = getText("IGUI_PD_VetRow_picked", vetHours(d.vetPickedMin)),
            tip = getText("IGUI_PD_VetRowTip_picked"),
        }
    end
    if CD.vetProtected(d, "vetBoostUntilMin", now) then
        local hours = math.ceil((d.vetBoostUntilMin - now) / 60)
        info.extras[#info.extras + 1] = { text = getText("IGUI_PD_VetRow_boost", tostring(hours)),
            tip = getText("IGUI_PD_VetRowTip_boost"), good = true }
    end
    if info.title == nil and #info.extras == 0 then return nil end
    return info
end

local function vetRows(view)
    local a = view.animal
    if not a then return {} end
    local info = CD.vetInfo(a, view.owner)
    if not info then return {} end
    local rows = {}
    local tips = {}
    if info.title then
        rows[#rows + 1] = { text = info.title, r = 0.95, g = 0.45, b = 0.40 }
        if info.dress then
            rows[#rows + 1] = { text = info.dress, r = 0.88, g = 0.88, b = 0.88 }
        end
        if view.stashed then
            rows[#rows + 1] = { text = getText("IGUI_PD_VetPaused"), r = 0.75, g = 0.75, b = 0.75 }
        elseif info.progress then
            rows[#rows + 1] = { text = info.progress, r = 0.88, g = 0.88, b = 0.88 }
        end
        tips[#tips + 1] = info.symptom .. " " .. info.todo
    end
    for _, e in ipairs(info.extras) do
        if e.good then
            rows[#rows + 1] = { text = e.text, r = 0.55, g = 0.85, b = 0.55 }
        else
            rows[#rows + 1] = { text = e.text, r = 0.95, g = 0.70, b = 0.40 }
        end
        tips[#tips + 1] = e.tip
    end
    local body = table.concat(tips, " ")
    if not view.stashed then
        body = body .. " " .. getText("IGUI_PD_VetClickHint")
    end
    rows.tip = { title = info.title or info.extras[1].text, body = body }
    return rows
end

-- A secao Saude abre as acoes no botao direito, como o painel de saude do jogo.
function ISCDStatusView:onRightMouseUp(x, y)
    local L = self.L
    if L and L.vetRows and #L.vetRows > 0 and self.animal and self.owner and not self.stashed then
        local sm = fh(UIFont.Small)
        local top = L.vetLabelY
        local bottom = L.vetY + sm * #L.vetRows
        if y >= top and y < bottom then
            openTreatMenu(self.owner, self.animal)
            return true
        end
    end
    return ISPanel.onRightMouseUp(self, x, y)
end

function ISCDStatusView:doLayout()
    local L = {}
    local sm = fh(UIFont.Small)
    local y = PAD

    L.loyaltyLabelY = y
    y = y + sm + ROW_GAP
    L.heartsY = y
    y = y + HEART_SIZE + SECT_GAP

    L.div1 = y
    y = y + 1 + DIVIDER_GAP

    L.needsLabelY = y
    y = y + sm + ROW_GAP
    L.needsY = y
    L.needRowH = math.max(sm, NEED_BAR_H) + ROW_GAP
    y = y + L.needRowH * 4 - ROW_GAP + SECT_GAP

    L.vetRows = vetRows(self)
    if #L.vetRows > 0 then
        L.vetLabelY = y
        y = y + sm + ROW_GAP
        L.vetY = y
        y = y + sm * #L.vetRows + SECT_GAP
    end

    L.div2 = y
    y = y + 1 + DIVIDER_GAP

    L.skillsLabelY = y
    y = y + sm + ROW_GAP
    L.skillsY = y
    L.skills = CD.skillsFor(self.animal)
    L.skillRowH = math.max(sm, SKILL_BAR_H) + ROW_GAP
    if #L.skills > 0 then
        y = y + L.skillRowH * #L.skills - ROW_GAP + SECT_GAP
    else
        y = y + SECT_GAP
    end

    L.div3 = y
    y = y + 1 + DIVIDER_GAP

    L.genomeLabelY = y
    y = y + sm + ROW_GAP
    L.speciesRowY = y
    y = y + sm + ROW_GAP
    L.breedRowY = y
    y = y + sm + ROW_GAP
    L.genomeY = y
    L.traitRowH = math.max(sm, TRAIT_BAR_H) + ROW_GAP
    y = y + L.traitRowH * 3 - ROW_GAP

    y = y + PAD
    L.contentH = y
    self.L = L
    return L
end

function ISCDStatusView:drawContent()
    local L = self.L
    if not L then return end
    local a = self.animal
    local breedNoun = CD.breedNoun(a)
    local cw = CD.UI.viewContentW(self)
    local x = PAD

    local over = self:isMouseOver() or self:isMouseOverChild()
    local mx, my = self:getMouseX(), self:getMouseY()
    local infoTip = nil
    local tip = nil
    local function hoverRow(y, h)
        return over and my >= y and my < y + h and mx >= PAD and mx <= cw - PAD
    end
    local function hoverRect(bx, y, w, h)
        return over and mx >= bx and mx < bx + w and my >= y and my < y + h
    end

    self:drawText(getText("IGUI_PD_LoyaltyLabel"), x, L.loyaltyLabelY, LBL.r, LBL.g, LBL.b, 1, UIFont.Small)
    local loyalty = 0
    if a then
        loyalty = CD.loyalty(a)
    end
    local maxL = CD.TRUST_MAX
    local filled = math.floor((loyalty / maxL) * HEART_COUNT + 0.5)
    if filled < 0 then filled = 0 elseif filled > HEART_COUNT then filled = HEART_COUNT end
    local hy = L.heartsY
    local hx = x
    for i = 1, HEART_COUNT do
        local tex = (i <= filled) and self.heartOn or self.heartOff
        self:drawTextureScaled(tex, hx, hy, HEART_SIZE, HEART_SIZE, 1, 1, 1, 1)
        hx = hx + HEART_SIZE + HEART_GAP
    end
    local numY = hy + (HEART_SIZE - fh(UIFont.Small)) / 2
    self:drawText(math.floor(loyalty) .. "/" .. maxL, hx + 8, numY, 1, 1, 1, 1, UIFont.Small)
    if hoverRow(L.loyaltyLabelY, (L.heartsY - L.loyaltyLabelY) + HEART_SIZE) then
        infoTip = { title = getText("IGUI_PD_LoyaltyLabel"), body = getText("IGUI_PD_LoyaltyDesc", breedNoun) }
    end

    self:drawDivider(L.div1)

    self:drawText(getText("IGUI_PD_NeedsLabel"), x, L.needsLabelY, LBL.r, LBL.g, LBL.b, 1, UIFont.Small)
    local hunger, thirst, health, stress = 0, 0, 1, 0
    if a then
        hunger = CD.getHunger(a)
        thirst = a:getThirst()
        health = a:getHealth()
        stress = CD.getStress(a)
    end
    local ny = L.needsY
    self:drawNeedBar(getText("IGUI_PD_Need_hunger"), ny, hunger, hunger)
    if hoverRow(ny, L.needRowH) then
        infoTip = { title = getText("IGUI_PD_Need_hunger"), body = getText("IGUI_PD_NeedDesc_hunger", breedNoun) }
    end
    ny = ny + L.needRowH
    self:drawNeedBar(getText("IGUI_PD_Need_thirst"), ny, thirst, thirst)
    if hoverRow(ny, L.needRowH) then
        infoTip = { title = getText("IGUI_PD_Need_thirst"), body = getText("IGUI_PD_NeedDesc_thirst", breedNoun) }
    end
    ny = ny + L.needRowH
    self:drawNeedBar(getText("IGUI_PD_Need_health"), ny, health, 1 - health)
    if hoverRow(ny, L.needRowH) then
        infoTip = { title = getText("IGUI_PD_Need_health"), body = getText("IGUI_PD_NeedDesc_health", breedNoun) }
    end
    ny = ny + L.needRowH
    self:drawNeedBar(getText("IGUI_PD_Need_stress"), ny, stress, stress)
    if hoverRow(ny, L.needRowH) then
        infoTip = { title = getText("IGUI_PD_Need_stress"), body = getText("IGUI_PD_NeedDesc_stress", breedNoun) }
    end

    local vet = vetRows(self)
    if #vet ~= #L.vetRows then
        self:layout()
        return
    end
    if #vet > 0 then
        local sm = fh(UIFont.Small)
        self:drawText(getText("IGUI_PD_VetSection"), x, L.vetLabelY, LBL.r, LBL.g, LBL.b, 1, UIFont.Small)
        local vy = L.vetY
        for _, row in ipairs(vet) do
            self:drawText(row.text, x, vy, row.r, row.g, row.b, 1, UIFont.Small)
            vy = vy + sm
        end
        if hoverRow(L.vetLabelY, vy - L.vetLabelY) then
            infoTip = vet.tip
        end
    end

    self:drawDivider(L.div2)

    self:drawText(getText("IGUI_PD_SkillsLabel"), x, L.skillsLabelY, LBL.r, LBL.g, LBL.b, 1, UIFont.Small)
    local sy = L.skillsY
    for _, skill in ipairs(L.skills) do
        local level, into, need = 0, 0, 1
        if a then
            level, into, need = CD.skillProgress(a, skill)
        end
        self:drawSkillBar(getText("IGUI_PD_Skill_" .. skill), sy, level, into, need)
        if over and my >= sy and my < sy + L.skillRowH and mx >= PAD and mx <= cw - PAD then
            local mult = 1
            if a then
                mult = CD.getBreedDef(a).xpMult[skill] or 1
            end
            tip = { skill = skill, level = level, into = into, need = need, mult = mult }
        end
        sy = sy + L.skillRowH
    end

    self:drawDivider(L.div3)

    self:drawText(getText("IGUI_PD_GenomeLabel"), x, L.genomeLabelY, LBL.r, LBL.g, LBL.b, 1, UIFont.Small)
    if hoverRow(L.genomeLabelY, fh(UIFont.Small) + ROW_GAP) then
        infoTip = { title = getText("IGUI_PD_GenomeLabel"), body = getText("IGUI_PD_GenomeDesc", breedNoun) }
    end
    -- Especie em linha propria, acima da raca: "Calico Cat" e o nome da RACA, nao da especie.
    local speciesKey = CD.DEFAULT_BREED
    if a then
        speciesKey = CD.getBreed(a)
    end
    self:drawText(getText("IGUI_PD_SpeciesLabel") .. ": " .. CD.speciesLabelFromKey(speciesKey),
                  x, L.speciesRowY, 0.72, 0.82, 0.92, 1, UIFont.Small)

    local breedName = breedNoun
    local mongrel = false
    if a then
        mongrel = CD.isMongrel(a)
    end
    if mongrel then
        breedName = breedName .. " (" .. getText("IGUI_PD_Mestico") .. ")"
    end
    local ageTxt = breedNoun
    if a then
        ageTxt = CD.ageNoun(a)
    end
    local breedText = getText("IGUI_PD_BreedLabel") .. ": " .. breedName .. ", " .. ageTxt
    self:drawText(breedText, x, L.breedRowY, 0.72, 0.82, 0.92, 1, UIFont.Small)
    if hoverRect(PAD, L.breedRowY, strW(UIFont.Small, breedText), fh(UIFont.Small)) then
        local bkey = CD.DEFAULT_BREED
        if a then
            bkey = CD.getBreed(a)
        end
        local body = getText(CD.breedDescKey(bkey))
        if mongrel then
            local ll = ""
            if a then
                ll = CD.lineageLabel(a)
            end
            if ll ~= "" then
                body = ll .. " \n " .. body
            end
        end
        infoTip = { title = breedName, body = body }
    end
    local ty = L.genomeY
    for _, gene in ipairs({ "strength", "aggressiveness", "resistance" }) do
        local ratio = 0.5
        if a then
            ratio = CD.geneRatio(a, gene)
        end
        self:drawTraitBar(getText("IGUI_PD_Gene_" .. gene), ty, ratio)
        if hoverRow(ty, L.traitRowH) then
            infoTip = { title = getText("IGUI_PD_Gene_" .. gene), body = getText("IGUI_PD_GeneDesc_" .. gene, breedNoun) }
        end
        ty = ty + L.traitRowH
    end

    if tip then
        self:drawSkillTip(tip, mx, my)
    elseif infoTip then
        self:drawInfoTip(infoTip.title, infoTip.body, mx, my)
    end
end

local function trickGrid(tricks)
    local slots, col, row = {}, 0, 0
    for i = 1, #tricks do
        local wide = tricks[i].wide == true
        if wide and col > 0 then
            col, row = 0, row + 1
        end
        slots[i] = { col = col, row = row, wide = wide }
        if wide then
            col, row = 0, row + 1
        else
            col = col + 1
            if col >= 3 then
                col, row = 0, row + 1
            end
        end
    end
    if col > 0 then
        row = row + 1
    end
    return slots, row
end

function ISCDCommandsView:doLayout()
    local L = {}
    local sm = fh(UIFont.Small)
    local y = PAD

    L.modeLabelY = y
    y = y + sm + ROW_GAP
    L.modeBtnY = y
    y = y + BTN_H + SECT_GAP

    L.keepLabelY = y
    y = y + sm + ROW_GAP
    L.keepRowY = y
    L.keepTrackY = y + math.floor((BTN_H - TRACK_H) / 2)
    y = y + BTN_H + SECT_GAP

    L.alertLabelY = y
    y = y + sm + ROW_GAP
    L.alertBtnY = y
    y = y + BTN_H + SECT_GAP

    if self.showCombat then
        L.protectLabelY = y
        y = y + sm + ROW_GAP
        L.protectBtnY = y
        y = y + BTN_H + SECT_GAP
    end

    if self.showHunt then
        L.huntLabelY = y
        y = y + sm + ROW_GAP
        L.huntBtnY = y
        y = y + BTN_H + SECT_GAP
    end

    if self.showTricks then
        L.trickLabelY = y
        y = y + sm + ROW_GAP
        L.trickBtnY = y
        L.trickSlots, L.trickRows = trickGrid(self.tricks)
        y = y + BTN_H * L.trickRows + BTN_GAP * (L.trickRows - 1) + SECT_GAP
    end

    if self.showCare then
        L.careLabelY = y
        y = y + sm + ROW_GAP
        L.careBtnY = y
        y = y + BTN_H + SECT_GAP
    end

    if self.showBag then
        L.bagBtnY = y
        y = y + BTN_H + SECT_GAP
    end

    L.actionsLabelY = y
    y = y + sm + ROW_GAP
    L.actionBtnY = y
    y = y + BTN_H

    y = y + PAD
    L.contentH = y
    self.L = L
    return L
end

function ISCDCommandsView:createChildren()
    self.showBag = self.animal ~= nil and not self.stashed and CD.hasBag(self.animal)
    self.showCombat = self.animal == nil or CD.breedCanFight(self.animal)
    self.showCare = (not self.stashed) and CD.careEnabled()
        and (self.animal == nil or CD.breedCanTendLivestock(self.animal))
    self.showHunt = self.animal == nil or CD.breedCanHunt(self.animal)
    self.tricks = CD.tricksFor(self.animal)
    self.showTricks = (not self.stashed) and CD.tricksEnabled() and #self.tricks > 0
    self:doLayout()

    self.followBtn = self:makeBtn(10, getText("IGUI_PD_CmdFollow"), ISCDCommandsView.onModeFollow, "CDFOLLOW")
    self.stayBtn   = self:makeBtn(10, getText("IGUI_PD_CmdStay"), ISCDCommandsView.onModeStay, "CDSTAY")
    if self.showCombat then
        self.guardBtn = self:makeBtn(10, getText("IGUI_PD_CmdGuard"), ISCDCommandsView.onModeGuard, "CDGUARD")
    end

    self.keepMinusBtn = self:makeBtn(STEP_W, "-", ISCDCommandsView.onKeepMinus, "CDKEEPMINUS")
    self.keepPlusBtn  = self:makeBtn(STEP_W, "+", ISCDCommandsView.onKeepPlus, "CDKEEPPLUS")
    self.keepTrackBtn = self:makeBtn(10, "", ISCDCommandsView.onKeepTrack, "CDKEEPTRACK")
    self.keepTrackBtn:setDisplayBackground(false)
    self.keepTrackBtn:setHeight(TRACK_H)

    self.alertBtn  = self:makeBtn(10, getText("IGUI_PD_AlertOn"), ISCDCommandsView.onAlertFull, "CDALERTON")
    self.quietBtn  = self:makeBtn(10, getText("IGUI_PD_AlertQuiet"), ISCDCommandsView.onAlertQuiet, "CDALERTQUIET")
    self.silentBtn = self:makeBtn(10, getText("IGUI_PD_AlertSilent"), ISCDCommandsView.onAlertSilent, "CDALERTSILENT")

    if self.showCombat then
        self.protectBtn = self:makeBtn(10, getText("IGUI_PD_AutoProtect"), ISCDCommandsView.onToggleProtect, "CDPROTECT")
    end
    if self.showHunt then
        self.huntBtn = self:makeBtn(10, getText("IGUI_PD_HuntMode"), ISCDCommandsView.onToggleHunt, "CDHUNT")
    end

    if self.showCare then
        self.careBtn = self:makeBtn(10, getText("IGUI_PD_CareStart"), ISCDCommandsView.onToggleCare, "CDCARE")
    end

    self.trickBtns = {}
    if self.showTricks then
        for i, def in ipairs(self.tricks) do
            local b = self:makeBtn(10, getText(def.labelKey), ISCDCommandsView.onTrick, "CDTRICK_" .. def.id)
            b.cdTrick = def
            self.trickBtns[i] = b
        end
    end

    if self.showBag then
        self.bagBtn = self:makeBtn(10, getText("IGUI_PD_OpenBag"), ISCDCommandsView.onOpenBag, "CDBAG")
    end

    self.fetchBtn   = self:makeBtn(10, getText("IGUI_PD_CmdFetch"), ISCDCommandsView.onFetch, "CDFETCH")
    self.renameBtn  = self:makeBtn(10, getText("IGUI_PD_BtnRename"), ISCDCommandsView.onRenameBtn, "CDRENAME")
    self.releaseBtn = self:makeBtn(10, getText("IGUI_PD_BtnRelease"), ISCDCommandsView.onReleaseBtn, "CDRELEASE")
    local bn = CD.breedNoun(self.animal)
    self.fetchBtn:setTooltip(getText("IGUI_PD_CmdFetchDesc", bn))
    self.renameBtn:setTooltip(getText("IGUI_PD_BtnRenameDesc", bn))
    self.releaseBtn:setTooltip(getText("IGUI_PD_BtnReleaseDesc", bn))
    self:markActive(self.fetchBtn, false)
    self:markActive(self.renameBtn, false)
    self:markActive(self.releaseBtn, false)

    if self.stashed then
        self:applyStashedMode()
    end

    self:layout()
end

function ISCDCommandsView:layout()
    local L = self:doLayout()
    local cw = CD.UI.viewContentW(self)
    local w3 = math.floor((cw - PAD * 2 - BTN_GAP * 2) / 3)
    if w3 < 10 then
        w3 = 10
    end
    local function col(i) return PAD + (w3 + BTN_GAP) * i end
    local fullW = cw - PAD * 2

    if self.guardBtn then
        self.followBtn:setX(col(0))
        self.followBtn:setY(L.modeBtnY)
        self.followBtn:setWidth(w3)
        self.stayBtn:setX(col(1))
        self.stayBtn:setY(L.modeBtnY)
        self.stayBtn:setWidth(w3)
        self.guardBtn:setX(col(2))
        self.guardBtn:setY(L.modeBtnY)
        self.guardBtn:setWidth(w3)
    else
        local w2 = math.floor((cw - PAD * 2 - BTN_GAP) / 2)
        if w2 < 10 then
            w2 = 10
        end
        self.followBtn:setX(PAD)
        self.followBtn:setY(L.modeBtnY)
        self.followBtn:setWidth(w2)
        self.stayBtn:setX(PAD + w2 + BTN_GAP)
        self.stayBtn:setY(L.modeBtnY)
        self.stayBtn:setWidth(w2)
    end

    local keepTrackX = PAD + STEP_W + BTN_GAP
    local keepTrackW = fullW - (STEP_W + BTN_GAP) * 2
    if keepTrackW < 20 then
        keepTrackW = 20
    end
    self.keepTrackX, self.keepTrackW = keepTrackX, keepTrackW
    self.keepMinusBtn:setX(PAD)
    self.keepMinusBtn:setY(L.keepRowY)
    self.keepPlusBtn:setX(PAD + fullW - STEP_W)
    self.keepPlusBtn:setY(L.keepRowY)
    self.keepTrackBtn:setX(keepTrackX)
    self.keepTrackBtn:setY(L.keepTrackY)
    self.keepTrackBtn:setWidth(keepTrackW)

    self.alertBtn:setX(col(0))
    self.alertBtn:setY(L.alertBtnY)
    self.alertBtn:setWidth(w3)
    self.quietBtn:setX(col(1))
    self.quietBtn:setY(L.alertBtnY)
    self.quietBtn:setWidth(w3)
    self.silentBtn:setX(col(2))
    self.silentBtn:setY(L.alertBtnY)
    self.silentBtn:setWidth(w3)

    if self.protectBtn and L.protectBtnY then
        self.protectBtn:setX(PAD)
        self.protectBtn:setY(L.protectBtnY)
        self.protectBtn:setWidth(fullW)
    end
    if self.huntBtn and L.huntBtnY then
        self.huntBtn:setX(PAD)
        self.huntBtn:setY(L.huntBtnY)
        self.huntBtn:setWidth(fullW)
    end

    if self.careBtn and L.careBtnY then
        self.careBtn:setX(PAD)
        self.careBtn:setY(L.careBtnY)
        self.careBtn:setWidth(fullW)
    end

    if self.bagBtn and L.bagBtnY then
        self.bagBtn:setX(PAD)
        self.bagBtn:setY(L.bagBtnY)
        self.bagBtn:setWidth(fullW)
    end

    if L.trickBtnY then
        for i, b in ipairs(self.trickBtns or {}) do
            local s = L.trickSlots[i]
            b:setX(s.wide and PAD or col(s.col))
            b:setY(L.trickBtnY + s.row * (BTN_H + BTN_GAP))
            b:setWidth(s.wide and fullW or w3)
        end
    end

    self.fetchBtn:setX(col(0))
    self.fetchBtn:setY(L.actionBtnY)
    self.fetchBtn:setWidth(w3)
    self.renameBtn:setX(col(1))
    self.renameBtn:setY(L.actionBtnY)
    self.renameBtn:setWidth(w3)
    self.releaseBtn:setX(col(2))
    self.releaseBtn:setY(L.actionBtnY)
    self.releaseBtn:setWidth(w3)

    self:setScrollHeight(L.contentH)
end

function ISCDCommandsView:applyStashedMode()
    local tip = getText("IGUI_PD_DrivingDisabledTip")
    for _, key in ipairs({ "followBtn", "stayBtn", "guardBtn", "keepMinusBtn", "keepPlusBtn", "keepTrackBtn",
                           "alertBtn", "quietBtn", "silentBtn", "protectBtn", "huntBtn" }) do
        local b = self[key]
        if b then
            b:setEnable(false)
            b:setTooltip(tip)
        end
    end
    self.fetchBtn.title = getText("IGUI_PD_FeedCompanion")
    self.fetchBtn.onclick = ISCDCommandsView.onFeedStashed
    self.fetchBtn:setTooltip(nil)
    self.releaseBtn.title = getText("IGUI_PD_Water")
    self.releaseBtn.onclick = ISCDCommandsView.onWaterStashed
    self.releaseBtn:setTooltip(nil)
end

function ISCDCommandsView:prerender()
    if not self.stashed then
        local state = CD.STATE_FOLLOW
        if self.animal then
            state = CD.getState(self.animal)
        end
        self:markActive(self.followBtn, state == CD.STATE_FOLLOW)
        self:markActive(self.stayBtn, state == CD.STATE_STAY)
        self:markActive(self.guardBtn, state == CD.STATE_GUARD)

        local keep = self.animal and CD.followKeep(self.animal) or CD.FOLLOW_START_DIST
        self.keepMinusBtn:setEnable(keep > CD.FOLLOW_KEEP_MIN)
        self.keepPlusBtn:setEnable(keep < CD.FOLLOW_KEEP_MAX)

        local mode = "full"
        if self.animal then
            mode = CD.getAlertMode(self.animal)
        end
        self:markActive(self.alertBtn, mode == "full")
        local unlocked = not (self.animal and CD.alertModeLocked(self.animal))
        self:markActiveEnabled(self.quietBtn, unlocked, mode == "quiet")
        self:markActiveEnabled(self.silentBtn, unlocked, mode == "silent")

        local protect = false
        if self.animal then
            protect = CD.getAutoProtect(self.animal)
        end
        self:markActive(self.protectBtn, protect)
        if self.protectBtn then
            self.protectBtn.title = getText(protect and "IGUI_PD_AutoProtectOn" or "IGUI_PD_AutoProtectOff")
        end

        local hunt = false
        if self.animal then
            hunt = CD.getHuntMode(self.animal)
        end
        self:markActiveEnabled(self.huntBtn, CD.huntEnabled(), hunt)
        if self.huntBtn then
            self.huntBtn.title = getText(hunt and "IGUI_PD_HuntModeOn" or "IGUI_PD_HuntModeOff")
        end

        if self.careBtn then
            local caring = false
            if self.animal then
                caring = CD.getCareMode(self.animal)
            end
            self:markActive(self.careBtn, caring)
            self.careBtn.title = getText(caring and "IGUI_PD_CareStop" or "IGUI_PD_CareStart")
        end

        for _, b in ipairs(self.trickBtns or {}) do
            local why = CD.trickBlockReason(self.animal, b.cdTrick, self.owner or getPlayer())
            b:setEnable(why == nil)
            local t = CD.trickLabel(self.animal, b.cdTrick)
            if t and t ~= b.title then
                b:setTitle(t)
            end
        end
    end
    CD.UI.viewBeginRender(self)
end

function ISCDCommandsView:drawContent()
    local L = self.L
    if not L then return end
    local breedNoun = CD.breedNoun(self.animal)
    local cw = CD.UI.viewContentW(self)
    local x = PAD

    local over = self:isMouseOver() or self:isMouseOverChild()
    local mx, my = self:getMouseX(), self:getMouseY()
    local infoTip = nil
    local function hoverRect(bx, y, w, h)
        return over and mx >= bx and mx < bx + w and my >= y and my < y + h
    end

    self:drawText(getText("IGUI_PD_ModeLabel"), x, L.modeLabelY, LBL.r, LBL.g, LBL.b, 1, UIFont.Small)
    self:drawText(getText("IGUI_PD_KeepLabel"), x, L.keepLabelY, LBL.r, LBL.g, LBL.b, 1, UIFont.Small)
    do
        local keep = self.animal and CD.followKeep(self.animal) or CD.FOLLOW_START_DIST
        local lo, hi = CD.FOLLOW_KEEP_MIN, CD.FOLLOW_KEEP_MAX
        local n = (keep % 1 == 0) and tostring(math.floor(keep)) or tostring(keep)
        local label = getText("IGUI_PD_KeepTiles", n)
        self:drawText(label, cw - PAD - strW(UIFont.Small, label), L.keepLabelY, 1, 1, 1, 1, UIFont.Small)
        local tx, tw, ty = self.keepTrackX or PAD, self.keepTrackW or 20, L.keepTrackY
        self:drawRect(tx, ty, tw, TRACK_H, 0.85, 0.10, 0.10, 0.10)
        self:drawRect(tx, ty, tw * ((keep - lo) / (hi - lo)), TRACK_H, 0.9, 0.45, 0.66, 0.40)
        self:drawRectBorder(tx, ty, tw, TRACK_H, 0.6, 0.5, 0.5, 0.5)
    end
    self:drawText(getText("IGUI_PD_SentinelLabel"), x, L.alertLabelY, LBL.r, LBL.g, LBL.b, 1, UIFont.Small)
    if L.protectLabelY then
        self:drawText(getText("IGUI_PD_AutoProtectLabel"), x, L.protectLabelY, LBL.r, LBL.g, LBL.b, 1, UIFont.Small)
    end
    if L.huntLabelY then
        self:drawText(getText("IGUI_PD_HuntLabel"), x, L.huntLabelY, LBL.r, LBL.g, LBL.b, 1, UIFont.Small)
    end
    if L.careLabelY then
        self:drawText(getText("IGUI_PD_CareLabel"), x, L.careLabelY, LBL.r, LBL.g, LBL.b, 1, UIFont.Small)
    end
    if L.trickLabelY then
        self:drawText(getText("IGUI_PD_TrickRoot"), x, L.trickLabelY, LBL.r, LBL.g, LBL.b, 1, UIFont.Small)
    end
    self:drawText(getText("IGUI_PD_ActionsLabel"), x, L.actionsLabelY, LBL.r, LBL.g, LBL.b, 1, UIFont.Small)

    local w3 = math.floor((cw - PAD * 2 - BTN_GAP * 2) / 3)
    local function btnX(c) return PAD + (w3 + BTN_GAP) * c end
    local modeCells = {
        { key = "IGUI_PD_CmdFollow", desc = "IGUI_PD_CmdFollowDesc" },
        { key = "IGUI_PD_CmdStay",   desc = "IGUI_PD_CmdStayDesc" },
        { key = "IGUI_PD_CmdGuard",  desc = "IGUI_PD_CmdGuardDesc" },
    }
    local alertCells = {
        { key = "IGUI_PD_AlertOn",     desc = "IGUI_PD_AlertFullDesc" },
        { key = "IGUI_PD_AlertQuiet",  desc = "IGUI_PD_AlertQuietDesc" },
        { key = "IGUI_PD_AlertSilent", desc = "IGUI_PD_AlertSilentDesc" },
    }
    if self.guardBtn then
        for c, cell in ipairs(modeCells) do
            if hoverRect(btnX(c - 1), L.modeBtnY, w3, BTN_H) then
                infoTip = { title = getText(cell.key), body = getText(cell.desc, breedNoun) }
            end
        end
    else
        local w2 = math.floor((cw - PAD * 2 - BTN_GAP) / 2)
        for c = 1, 2 do
            if hoverRect(PAD + (w2 + BTN_GAP) * (c - 1), L.modeBtnY, w2, BTN_H) then
                infoTip = { title = getText(modeCells[c].key), body = getText(modeCells[c].desc, breedNoun) }
            end
        end
    end
    if hoverRect(PAD, L.keepRowY, cw - PAD * 2, BTN_H) then
        infoTip = { title = getText("IGUI_PD_KeepLabel"), body = getText("IGUI_PD_KeepDesc", breedNoun) }
    end
    local lockedAlert = self.animal and CD.alertModeLocked(self.animal)
    for c, cell in ipairs(alertCells) do
        if hoverRect(btnX(c - 1), L.alertBtnY, w3, BTN_H) then
            local body = (lockedAlert and c > 1) and CD.speciesText(self.animal, "IGUI_PD_AlertLockedTip", breedNoun)
                or CD.speciesText(self.animal, cell.desc, breedNoun)
            infoTip = { title = getText(cell.key), body = body }
        end
    end
    if L.protectBtnY and hoverRect(PAD, L.protectBtnY, cw - PAD * 2, BTN_H) then
        infoTip = { title = getText("IGUI_PD_AutoProtect"), body = getText("IGUI_PD_AutoProtectDesc", breedNoun) }
    end
    if L.huntBtnY and hoverRect(PAD, L.huntBtnY, cw - PAD * 2, BTN_H) then
        local body = CD.huntEnabled() and CD.speciesText(self.animal, "IGUI_PD_HuntModeDesc", breedNoun)
            or getText("IGUI_PD_HuntDisabledTip")
        infoTip = { title = getText("IGUI_PD_HuntMode"), body = body }
    end
    if L.careBtnY and hoverRect(PAD, L.careBtnY, cw - PAD * 2, BTN_H) then
        local caring = false
        if self.animal then
            caring = CD.getCareMode(self.animal)
        end
        infoTip = {
            title = caring and getText("IGUI_PD_CareStop") or getText("IGUI_PD_CareStart"),
            body = getText("IGUI_PD_CareModeDesc", breedNoun) .. " " .. getText("IGUI_PD_CareDeselectWarn"),
        }
    end

    if L.trickBtnY then
        for i, b in ipairs(self.trickBtns or {}) do
            local slot = L.trickSlots[i]
            local bx = slot.wide and PAD or btnX(slot.col)
            local bw = slot.wide and (cw - PAD * 2) or w3
            if hoverRect(bx, L.trickBtnY + slot.row * (BTN_H + BTN_GAP), bw, BTN_H) then
                local def = b.cdTrick
                local why, a1, a2 = CD.trickBlockReason(self.animal, def, self.owner or getPlayer())
                infoTip = {
                    title = CD.trickLabel(self.animal, def),
                    body = why and CD.speciesText(self.animal, why, a1, a2) or CD.trickDescription(self.animal, def),
                }
            end
        end
    end

    if infoTip then
        self:drawInfoTip(infoTip.title, infoTip.body, mx, my)
    end
end

function ISCDCommandsView:setMode(state)
    if self.stashed or not self.animal then return end
    CD.request("setstate", self.animal, { state = state }, self.owner or getPlayer())
end

function ISCDCommandsView:setAlertMode(mode)
    if self.stashed or not self.animal then return end
    CD.request("setalertmode", self.animal, { mode = mode }, self.owner or getPlayer())
end

function ISCDCommandsView:setFollowKeep(keep)
    if self.stashed or not self.animal then return end
    keep = CD.snapFollowKeep(keep)
    if not keep or keep == CD.followKeep(self.animal) then return end
    CD.setFollowKeep(self.animal, keep)
    CD.request("setfollowkeep", self.animal, { keep = keep }, self.owner or getPlayer())
end

function ISCDCommandsView.onModeFollow(view) view:setMode(CD.STATE_FOLLOW) end
function ISCDCommandsView.onModeStay(view)   view:setMode(CD.STATE_STAY) end
function ISCDCommandsView.onModeGuard(view)  view:setMode(CD.STATE_GUARD) end
function ISCDCommandsView.onAlertFull(view)   view:setAlertMode("full") end
function ISCDCommandsView.onAlertQuiet(view)  view:setAlertMode("quiet") end
function ISCDCommandsView.onAlertSilent(view) view:setAlertMode("silent") end
function ISCDCommandsView.onKeepMinus(view)
    if not view.animal then return end
    view:setFollowKeep(CD.followKeep(view.animal) - CD.FOLLOW_KEEP_STEP)
end

function ISCDCommandsView.onKeepPlus(view)
    if not view.animal then return end
    view:setFollowKeep(CD.followKeep(view.animal) + CD.FOLLOW_KEEP_STEP)
end

function ISCDCommandsView.onKeepTrack(view, button)
    local w = button:getWidth()
    if w <= 0 then return end
    local lo, hi = CD.FOLLOW_KEEP_MIN, CD.FOLLOW_KEEP_MAX
    view:setFollowKeep(lo + (hi - lo) * (button:getMouseX() / w))
end

function ISCDCommandsView.onTrick(view, btn)
    if view.stashed or not view.animal then return end
    local def = btn and btn.cdTrick
    if not def then return end
    local player = view.owner or getPlayer()
    if def.id == "goto" and view.window then
        view.window:close()
    end
    CD.startTrick(player, view.animal, def.id)
end

function ISCDCommandsView.onToggleProtect(view)
    if view.stashed or not view.animal then return end
    local on = false
    if view.animal then
        on = CD.getAutoProtect(view.animal)
    end
    CD.request("setautoprotect", view.animal, { on = not on }, view.owner or getPlayer())
end

function ISCDCommandsView.onToggleHunt(view)
    if view.stashed or not view.animal then return end
    local on = false
    if view.animal then
        on = CD.getHuntMode(view.animal)
    end
    CD.request("sethuntmode", view.animal, { on = not on }, view.owner or getPlayer())
end

local function onCareConfirm(target, button)
    local internal = (type(button) == "table") and button.internal or button
    if internal == "YES" and target and target.animal then
        CD.request("setcaremode", target.animal, { on = true }, target.owner or getPlayer())
        if target.window then
            target.window:close()
        end
    end
end

function ISCDCommandsView.onToggleCare(view)
    if view.stashed or not view.animal then return end
    local caring = false
    if view.animal then
        caring = CD.getCareMode(view.animal)
    end
    if caring then
        CD.request("setcaremode", view.animal, { on = false }, view.owner or getPlayer())
        return
    end
    local p = view.owner or getPlayer()
    local modal = ISModalDialog:new(0, 0, 380, 160,
        getText("IGUI_PD_CareDeselectConfirm", view:dogName()), true, view, onCareConfirm,
        p and p:getPlayerNum() or 0)
    modal:initialise()
    modal:addToUIManager()
end

function ISCDCommandsView.onFetch(view)
    if not view.animal then return end
    local p = view.owner or getPlayer()
    if p then
        p:playEmote("comehere")
        p:Callout(false)
    end
    CD.request("teleport", view.animal, nil, p)
end

function ISCDCommandsView.onOpenBag(view)
    if view and view.animal and CD.openBagWindow then
        CD.openBagWindow(view.animal, view.owner or getPlayer())
    end
end

local function onRenameApply(_, button, view)
    if button.internal == "OK" then
        local text = button.parent.entry:getText()
        local owner = view.owner or getPlayer()
        if view.stashed then
            CD.requestStashed("renamestashed", { text = text }, owner)
        else
            CD.request("rename", view.animal, { text = text }, owner)
        end
    end
end

function ISCDCommandsView.onRenameBtn(view)
    local animal = view.animal
    if not animal then return end
    local cur = CD.data(animal).name or ""
    local player = view.owner or getPlayer()
    local modal = ISTextBox:new(0, 0, 290, 180, getText("IGUI_PD_RenameTitle", CD.breedNoun(animal)), cur, nil,
        onRenameApply, player and player:getPlayerNum() or 0, view)
    modal:initialise()
    modal:addToUIManager()
end

function ISCDCommandsView.doFeedStashed(view, player, food)
    player = player or view.owner or getPlayer()
    if not (player and food) then return end
    local inv = player:getInventory()
    if not inv:contains(food) then return end

    local need
    if view.animal then
        need = view.animal:getHunger()
    end
    local bite = CD.computeBite(food, need)
    CD.requestStashed("feedstashed", { hunger = bite.hunger, thirst = bite.thirst, partialFrac = bite.partialFrac, foodId = food:getID() }, player)
end

function ISCDCommandsView.onFeedStashed(view)
    local player = view.owner or getPlayer()
    if not player then return end
    local foods = cdListFoods(player, view.animal and CD.getBreed(view.animal))
    if #foods == 0 then
        HaloTextHelper.addText(player, getText("IGUI_PD_NeedFood"))
        return
    end
    if #foods == 1 then
        ISCDCommandsView.doFeedStashed(view, player, foods[1].item)
        return
    end
    local menu = ISContextMenu.get(player:getPlayerNum(), getMouseX(), getMouseY())
    for _, g in ipairs(foods) do
        local label = g.count > 1 and (g.name .. " (" .. g.count .. ")") or g.name
        local opt = menu:addOption(label, view, ISCDCommandsView.doFeedStashed, player, g.item)
        opt.iconTexture = g.item:getTexture()
        if g.bad then
            opt.color = { r = 1, g = 0.35, b = 0.35 }
            menu.cdBadLabels = menu.cdBadLabels or {}
            menu.cdBadLabels[opt.name] = true
            local tooltip = ISWorldObjectContextMenu.addToolTip()
            tooltip:setName(g.name)
            tooltip.description = "<RGB:1,0.35,0.35>" .. CD.speciesText(view.animal, "IGUI_PD_BadFood")
            opt.toolTip = tooltip
        end
    end
end

function ISCDCommandsView.onWaterStashed(view)
    local player = view.owner or getPlayer()
    if not player then return end
    local item = cdFirstWater(player)
    if not item then
        HaloTextHelper.addText(player, getText("IGUI_PD_NeedWater"))
        return
    end
    CD.requestStashed("waterstashed", { waterId = item:getID() }, player)
end

local function onReleaseConfirm(target, button)
    local internal = (type(button) == "table") and button.internal or button
    if internal == "YES" and target and target.animal then
        CD.request("release", target.animal, nil, target.owner or getPlayer())
        if target.window then
            target.window:close()
        end
    end
end

function ISCDCommandsView.onReleaseBtn(view)
    if not view.animal then return end
    local p = view.owner or getPlayer()
    local pnum = p and p:getPlayerNum() or 0
    local text = getText("IGUI_PD_ReleaseConfirm", view:dogName()) .. "\n" .. getText("IGUI_PD_ReleaseWarn")
    local w, h = ISModalDialog.CalcSize(380, 160, text)
    local x = getPlayerScreenLeft(pnum) + (getPlayerScreenWidth(pnum) - w) / 2
    local y = getPlayerScreenTop(pnum) + (getPlayerScreenHeight(pnum) - h) / 2
    local modal = ISModalDialog:new(math.max(1, x), math.max(1, y), w, h, text,
        true, view, onReleaseConfirm, pnum)
    modal:initialise()
    modal:addToUIManager()
end

function ISCDLockedView:doLayout()
    self.L = { contentH = self.height or 1 }
    return self.L
end

function ISCDLockedView:drawContent()
    local msg = getText("IGUI_PD_TabLockedTip")
    local cw = CD.UI.viewContentW(self)
    local mw = strW(UIFont.Small, msg)
    self:drawText(msg, math.max(PAD, (cw - mw) / 2), 24, 0.62, 0.62, 0.62, 1, UIFont.Small)
end

function ISCDStatusWindow:new(x, y, width, height, animal)
    local o = ISCollapsableWindowJoypad.new(self, x, y, width, height)
    o.animal = animal
    o.resizable = true
    o.avatarBg = getTexture("media/ui/avatarBackgroundWhite.png")
    o:setTitle(o:dogName())
    return o
end

function ISCDStatusWindow:dogName()
    if not self.animal then return getText("IGUI_PD_KennelTitle") end
    local name = CD.data(self.animal).name
    if name then return name end
    local bn = CD.breedNoun(self.animal)
    return bn or getText("IGUI_PD_DogDefaultName")
end

function ISCDStatusWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    local top = self:titleBarHeight()
    local rh = self:resizeWidgetHeight()
    self.hdrH = HDR_H

    local pw = self.width
    local ph = math.max(1, self.height - top - self.hdrH - rh)
    self.panel = ISTabPanel:new(0, top + self.hdrH, pw, ph)
    self.panel:initialise()
    self.panel.equalTabWidth = false
    self.panel.centerTabs = false
    self.panel.tabPadX = 16
    self.panel.target = self
    self.panel.onActivateView = ISCDStatusWindow.onTabActivated
    self.panel.tabHeight = math.ceil(getTextManager():getFontHeight(TAB_FONT) * TAB_ZOOM) + TAB_H_PAD
    self.panel.cdLocked = {}
    self.panel.drawTextCentre = function(pnl, str, x, y, r, g, b, a, font)
        local tm = getTextManager()
        local tw = tm:MeasureStringX(TAB_FONT, str) * TAB_ZOOM
        local th = tm:getFontHeight(TAB_FONT) * TAB_ZOOM
        if pnl.cdLocked[str] then
            r, g, b = 0.45, 0.45, 0.45
        end
        pnl:drawTextZoomed(str, x - tw / 2, math.floor((pnl.tabHeight - th) / 2), TAB_ZOOM, r, g, b, a, TAB_FONT)
    end
    local baseOnMouseDown = self.panel.onMouseDown
    self.panel.onMouseDown = function(pnl, x, y)
        if pnl:getMouseY() >= 0 and pnl:getMouseY() < pnl.tabHeight then
            local idx = pnl:getTabIndexAtX(pnl:getMouseX())
            local vo = pnl.viewList and pnl.viewList[idx]
            if vo and pnl.cdLocked[vo.name] then return end
        end
        return baseOnMouseDown(pnl, x, y)
    end
    self:addChild(self.panel)

    self.views = {}
    local vh = math.max(1, ph - self.panel.tabHeight)
    local function addTab(id, label, view)
        view.cdTabId = id
        view.window = self
        view.animal = self.animal
        view.stashed = self.stashed
        view.owner = self.owner
        self.panel:addView(label, view)
        self.views[#self.views + 1] = view
    end

    local statusLabel = getText("IGUI_PD_TabSkillsStatus")
    local healthLabel = getText("IGUI_PD_TabHealth")
    local commandsLabel = getText("IGUI_PD_TabCommands")
    if self.animal then
        addTab("status",   statusLabel,   ISCDStatusView:new(0, 0, pw, vh))
        addTab("health",   healthLabel,   ISCDHealthView:new(0, 0, pw, vh))
        addTab("commands", commandsLabel, ISCDCommandsView:new(0, 0, pw, vh))
    else
        addTab("status",   statusLabel,   ISCDLockedView:new(0, 0, pw, vh))
        addTab("health",   healthLabel,   ISCDLockedView:new(0, 0, pw, vh))
        addTab("commands", commandsLabel, ISCDLockedView:new(0, 0, pw, vh))
        self.panel.cdLocked[statusLabel] = true
        self.panel.cdLocked[healthLabel] = true
        self.panel.cdLocked[commandsLabel] = true
    end
    local kennel = ISCDKennelView:new(0, 0, pw, vh)
    kennel.playerNum = self.playerNum or 0
    addTab("kennel", getText("IGUI_PD_KennelTitle"), kennel)
    self.kennelView = kennel
    local settings = ISCDSettingsView:new(0, 0, pw, vh)
    addTab("settings", getText("IGUI_PD_ConfigsBtn"), settings)
    self.settingsView = settings
    self:fitTabs()

    if self.animal and not self.stashed then
        local av = ISCDDogAvatar:new(HDR_PAD, top + math.floor((HDR_H - HDR_AV) / 2), HDR_AV, HDR_AV)
        av:initialise()
        self:addChild(av)
        av:bindAnimal(self.animal)
        self.headerAvatar = av
    end

    CD.UI.initResizable(self, "dogwin", MIN_W, MIN_H)
end

function ISCDStatusWindow:fitTabs()
    local p = self.panel
    if not p or not p.viewList then return end
    local n = #p.viewList
    if n == 0 then return end
    local tm = getTextManager()
    local nat, sumNat = {}, 0
    for i, vo in ipairs(p.viewList) do
        nat[i] = math.ceil(tm:MeasureStringX(TAB_FONT, vo.name) * TAB_ZOOM) + p.tabPadX
        sumNat = sumNat + nat[i]
    end
    local avail = p.width - 2 - (n - 1)
    if sumNat <= 0 or avail <= sumNat then
        for i, vo in ipairs(p.viewList) do vo.tabWidth = nat[i] end
        return
    end
    local acc = 0
    for i, vo in ipairs(p.viewList) do
        local w = (i < n) and math.floor(nat[i] * avail / sumNat) or (avail - acc)
        acc = acc + w
        vo.tabWidth = w
    end
end

function ISCDStatusWindow:reflow()
    if not self.panel then return end
    local top = self:titleBarHeight()
    local rh = self:resizeWidgetHeight()
    self.panel:setX(0)
    self.panel:setY(top + (self.hdrH or 0))
    self.panel:setWidth(self.width)
    self.panel:setHeight(math.max(1, self.height - top - (self.hdrH or 0) - rh))
    self:fitTabs()
    local vh = math.max(1, self.panel.height - self.panel.tabHeight)
    for _, v in ipairs(self.views or {}) do
        v:setY(self.panel.tabHeight)
        v:setWidth(self.panel.width)
        v:setHeight(vh)
        v:layout()
    end
end

function ISCDStatusWindow.onTabActivated(win, panel)
    local v = panel:getActiveView()
    if not v then return end
    if v.cdTabId then
        CD.Settings.setLastTab(v.cdTabId, win.playerNum)
    end
    if win.settingsView and v ~= win.settingsView then
        win.settingsView.capturingId = nil
        CD.Keybinds.captureCb = nil
    end
    win:syncJoypadRows(true)
end

function ISCDStatusWindow:activateTabId(id)
    if not (id and self.panel) then return false end
    for _, vo in ipairs(self.panel.viewList) do
        if vo.view.cdTabId == id then
            if self.panel.cdLocked[vo.name] then return false end
            self.panel:activateView(vo.name)
            return true
        end
    end
    return false
end

function ISCDStatusWindow:checkShouldClose()
    if not self.animal then return false end
    if self.stashed then
        local owner = self.owner
        local hasStash = owner ~= nil and CD.isMounted(owner) and CD.playerData(owner).stash ~= nil
        if not hasStash then
            self:close()
            return true
        end
    else
        if not self.animal:isExistInTheWorld() then
            self:close()
            return true
        end
    end
    return false
end

function ISCDStatusWindow:drawHeader()
    if self.isCollapsed then return end
    local top = self:titleBarHeight()
    local ax = HDR_PAD
    local ay = top + math.floor((HDR_H - HDR_AV) / 2)
    self:drawRectBorder(ax - 1, ay - 1, HDR_AV + 2, HDR_AV + 2, 1, 0.3, 0.3, 0.3)
    if self.avatarBg then
        self:drawTextureScaled(self.avatarBg, ax, ay, HDR_AV, HDR_AV, 1, 0.4, 0.4, 0.4)
    end

    if not self.animal then
        local paw = getTexture("media/textures/CDDogPawGrey_48.png") or cdLoadPaw(48)
        if paw then
            self:drawTextureScaled(paw, ax + 8, ay + 8, HDR_AV - 16, HDR_AV - 16, 0.5, 1, 1, 1)
        end
        local tx = ax + HDR_AV + 12
        local msg = getText("IGUI_PD_KennelEmpty")
        local ty = ay + math.floor((HDR_AV - fh(UIFont.Medium)) / 2)
        self:drawText(msg, tx, ty, 0.72, 0.72, 0.72, 1, UIFont.Medium)
        return
    end
    local av = self.headerAvatar
    if av and av.boundAnimal then
        av:applyFrame()
    else
        local paw = cdLoadPaw(48)
        if paw then
            self:drawTextureScaled(paw, ax + 8, ay + 8, HDR_AV - 16, HDR_AV - 16, 1, 1, 1, 1)
        end
    end

    local a = self.animal
    local tx = ax + HDR_AV + 12
    local mdH = fh(UIFont.Medium)
    local smH = fh(UIFont.Small)
    local blockH = mdH + 6 + smH + 4 + smH
    local nameY = ay + math.max(2, math.floor((HDR_AV - blockH) / 2))
    self:drawText(self:dogName(), tx, nameY, 1, 1, 1, 1, UIFont.Medium)

    local breedName = CD.breedNoun(a)
    if a and CD.isMongrel(a) then
        breedName = breedName .. " (" .. getText("IGUI_PD_Mestico") .. ")"
    end
    local line = getText("IGUI_PD_BreedLabel") .. ": " .. breedName
    if a then
        line = line .. ", " .. CD.ageNoun(a)
    end
    local lineY = nameY + mdH + 6
    self:drawText(line, tx, lineY, 0.72, 0.82, 0.92, 1, UIFont.Small)

    local d = CD.data(a)
    local zk = d.zombieKills or 0
    local pk = d.preyKills or 0
    local killsY = lineY + smH + 4
    self:drawText(getText("IGUI_PD_KillsLabel") .. ": " .. getText("IGUI_PD_KillsFmt", tostring(zk), tostring(pk)),
        tx, killsY, 0.72, 0.82, 0.92, 1, UIFont.Small)

    local badge
    if a then
        badge = CD.statusBadge(a)
    end
    if badge then
        local wtxt = getText(badge.key)
        self:drawText(wtxt, self.width - 12 - strW(UIFont.Small, wtxt), nameY + 2, badge.r, badge.g, badge.b, 1, UIFont.Small)
    end
    if self.stashed then
        local btxt = getText("IGUI_PD_InVehicleBanner")
        self:drawText(btxt, self.width - 12 - strW(UIFont.Small, btxt), lineY, 0.70, 0.80, 0.95, 1, UIFont.Small)
    end
end

function ISCDStatusWindow:prerender()
    if self:checkShouldClose() then return end
    self:setTitle(self:dogName())
    ISCollapsableWindow.prerender(self)
    self:drawHeader()
end

function ISCDStatusWindow:drawLockedTabTip()
    local p = self.panel
    if self.isCollapsed or not (p and p.cdLocked) then return end
    local pmy = p:getMouseY()
    if not (p:isMouseOver() and pmy >= 0 and pmy < p.tabHeight) then return end
    local idx = p:getTabIndexAtX(p:getMouseX())
    local vo = p.viewList and p.viewList[idx]
    if not (vo and p.cdLocked[vo.name]) then return end

    local font = UIFont.Small
    local txt = getText("IGUI_PD_TabLockedTip")
    local pad = 8
    local w = strW(font, txt) + pad * 2
    local h = fh(font) + pad * 2
    local mx, my = self:getMouseX(), self:getMouseY()
    local tx = mx + 14
    local ty = my + 16
    if tx + w > self.width then
        tx = self.width - w - 2
    end
    if tx < 2 then
        tx = 2
    end
    if ty + h > self.height then
        ty = my - h - 6
    end
    self:drawRect(tx, ty, w, h, 0.93, 0.06, 0.06, 0.06)
    self:drawRectBorder(tx, ty, w, h, 0.85, 0.5, 0.5, 0.5)
    self:drawText(txt, tx + pad, ty + pad, 0.86, 0.86, 0.86, 1, font)
end

function ISCDStatusWindow:render()
    ISCollapsableWindow.render(self)
    self:drawLockedTabTip()
end

function ISCDStatusWindow:close()
    CD.UI.persist(self)
    if self.settingsView then
        self.settingsView.capturingId = nil
    end
    CD.Keybinds.captureCb = nil
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    local pn = self.playerNum or 0
    if isJoypadFocusOnElementOrDescendant(pn, self) then
        setJoypadFocus(pn, nil)
    end
    if ISCDStatusWindow.instances[pn] == self then
        ISCDStatusWindow.instances[pn] = nil
    end
end

-- Controle: as linhas navegaveis sao os botoes visiveis da aba ativa, agrupados por Y.
-- Reconstruidas a cada entrada porque as abas criam e escondem botao conforme o estado do cao.
local function collectButtons(el, out)
    for _, child in ipairs(el:getChildrenInOrder()) do
        if child.isButton and child:isVisible() and child.enable ~= false then
            out[#out + 1] = child
        end
        collectButtons(child, out)
    end
    return out
end

function ISCDStatusWindow:syncJoypadRows(resetFocus)
    local view = self.panel and self.panel:getActiveView()
    local joypadData = self.joyfocus
    local focused = nil
    if not resetFocus then
        local children = self:getVisibleChildren(self.joypadIndexY or 0)
        focused = children and children[self.joypadIndex or 0]
    end
    if joypadData then
        self:clearJoypadFocus(joypadData)
    end
    self:clearJoypadButtonsList()
    if not view then return end
    local buttons = collectButtons(view, {})
    table.sort(buttons, function(a, b)
        local ay, by = a:getAbsoluteY(), b:getAbsoluteY()
        if ay ~= by then return ay < by end
        return a:getAbsoluteX() < b:getAbsoluteX()
    end)
    local rows, lastY = {}, nil
    for _, b in ipairs(buttons) do
        local y = b:getAbsoluteY()
        if lastY == nil or math.abs(y - lastY) > 4 then
            rows[#rows + 1] = {}
            lastY = y
        end
        table.insert(rows[#rows], b)
    end
    self:addJoypadButtonRows(rows)
    if not joypadData then return end
    if not (focused and self:setJoypadFocus(focused, joypadData)) then
        self:setJoypadFocusTopLeft(joypadData)
    end
end

function ISCDStatusWindow:onGainJoypadFocus(joypadData)
    ISCollapsableWindowJoypad.onGainJoypadFocus(self, joypadData)
    self:syncJoypadRows(false)
end

function ISCDStatusWindow:onLoseJoypadFocus(joypadData)
    self:clearJoypadFocus(joypadData)
    ISCollapsableWindowJoypad.onLoseJoypadFocus(self, joypadData)
end

function ISCDStatusWindow:cycleTab(dir)
    local p = self.panel
    if not (p and p.viewList and #p.viewList > 0) then return end
    local n = #p.viewList
    local idx = p:getActiveViewIndex()
    for _ = 1, n - 1 do
        idx = ((idx - 1 + dir) % n) + 1
        local vo = p.viewList[idx]
        if vo and not p.cdLocked[vo.name] then
            p:activateView(vo.name)
            return
        end
    end
end

function ISCDStatusWindow:ensureVisible()
    if not self.joyfocus then return end
    local view = self.panel and self.panel:getActiveView()
    local children = self:getVisibleChildren(self.joypadIndexY or 0)
    local child = children and children[self.joypadIndex or 0]
    if not (view and child and child.parent == view) then return end
    local scroll = view:getYScroll()
    local y, h = child:getY(), child:getHeight()
    local vh = view:getHeight()
    if y + scroll < 0 then
        view:setYScroll(-y + 8)
    elseif y + h + scroll > vh then
        view:setYScroll(-(y + h - vh + 8))
    end
end

function ISCDStatusWindow:onJoypadDown(button, joypadData)
    self:syncJoypadRows(false)
    if button == Joypad.BButton and not self:isFocusOnControl() then
        self:close()
        return
    end
    if button == Joypad.LBumper then
        self:cycleTab(-1)
        return
    end
    if button == Joypad.RBumper then
        self:cycleTab(1)
        return
    end
    ISCollapsableWindowJoypad.onJoypadDown(self, button, joypadData)
end

function ISCDStatusWindow:onJoypadDirUp(joypadData)
    self:syncJoypadRows(false)
    ISCollapsableWindowJoypad.onJoypadDirUp(self, joypadData)
end

function ISCDStatusWindow:onJoypadDirDown(joypadData)
    self:syncJoypadRows(false)
    ISCollapsableWindowJoypad.onJoypadDirDown(self, joypadData)
end

function ISCDStatusWindow:onJoypadDirLeft(joypadData)
    self:syncJoypadRows(false)
    ISCollapsableWindowJoypad.onJoypadDirLeft(self, joypadData)
end

function ISCDStatusWindow:onJoypadDirRight(joypadData)
    self:syncJoypadRows(false)
    ISCollapsableWindowJoypad.onJoypadDirRight(self, joypadData)
end

ISCDStatusWindow.instances = ISCDStatusWindow.instances or {}

function ISCDStatusWindow.instanceFor(playerObj)
    local pn = 0
    if playerObj then
        pn = playerObj:getPlayerNum()
    end
    return ISCDStatusWindow.instances[pn], pn
end

local function openDogWindow(animal, stashed, owner, tabId, actor)
    local who = actor or owner or (animal and CD.getOwnerPlayer(animal)) or getPlayer()
    local pn = 0
    if who then
        pn = who:getPlayerNum()
    end
    if ISCDStatusWindow.instances[pn] then
        ISCDStatusWindow.instances[pn]:close()
    end
    local win = ISCDStatusWindow:new(0, 0, WIN_W, 480, animal)
    win.stashed = stashed
    win.owner = owner or who
    win.playerNum = pn
    win:initialise()
    win:instantiate()
    win:setRenderThisPlayerOnly(pn)
    local top = win:titleBarHeight()
    local rh = win:resizeWidgetHeight()
    local maxC = 320
    for _, v in ipairs(win.views or {}) do
        if v.L and v.L.contentH and v.L.contentH > maxC then
            maxC = v.L.contentH
        end
    end
    local naturalH = top + (win.hdrH or 0) + ((win.panel and win.panel.tabHeight) or 0) + maxC + rh
    CD.UI.applyOpenGeometry(win, "dogwin", WIN_W, naturalH)
    win:addToUIManager()
    ISCDStatusWindow.instances[pn] = win
    local wantTab = tabId or (CD.Settings.getLastTab and CD.Settings.getLastTab(pn))
    if not win:activateTabId(wantTab) and win.panel then
        for _, vo in ipairs(win.panel.viewList) do
            if not win.panel.cdLocked[vo.name] then
                win.panel:activateView(vo.name)
                break
            end
        end
    end
    if JoypadState.players[pn + 1] then
        setJoypadFocus(pn, win)
    end
    return win
end

function ISCDStatusWindow.OpenFor(animal, tabId, actor)
    if not animal then return end
    openDogWindow(animal, nil, nil, tabId, actor)
end

function ISCDStatusWindow.OpenStashed(playerObj, tabId)
    if not playerObj then return end
    openDogWindow(makeStashProxy(playerObj), true, playerObj, tabId, playerObj)
end

function ISCDStatusWindow.OpenKennelOnly(playerObj, tabId)
    openDogWindow(nil, nil, playerObj, tabId or "kennel", playerObj)
end

---Opens the dog window on tabId: the companion, the stashed dog while mounted, or the kennel alone.
---@param playerObj IsoPlayer|nil getPlayer() when nil
---@param tabId string|nil nil means the last tab used, or the kennel without a dog
function CD.openDogWindowTab(playerObj, tabId)
    local p = playerObj or getPlayer()
    if not p then return end
    local dog = CD.getCompanionAnimal(p)
    if dog then
        ISCDStatusWindow.OpenFor(dog, tabId, p)
    elseif CD.isMounted(p) and CD.playerData(p).stash then
        ISCDStatusWindow.OpenStashed(p, tabId)
    else
        ISCDStatusWindow.OpenKennelOnly(p, tabId or "kennel")
    end
end

---Toggles the dog window of this player; it opens on the same sheet openDogWindowTab picks.
---@param playerObj IsoPlayer|nil
function CD.openDogStatus(playerObj)
    local open = ISCDStatusWindow.instanceFor(playerObj)
    if open then
        open:close()
        return
    end
    local dog = CD.getCompanionAnimal(playerObj)
    if dog then
        ISCDStatusWindow.OpenFor(dog, nil, playerObj)
    elseif playerObj and CD.isMounted(playerObj) and CD.playerData(playerObj).stash then
        ISCDStatusWindow.OpenStashed(playerObj)
    elseif playerObj then
        ISCDStatusWindow.OpenKennelOnly(playerObj)
    end
end

local function onDogStatusButton(panel)
    CD.openDogStatus(panel and panel.chr)
end

-- Roda do botao Back do controle: e a unica porta de entrada da janela sem mouse.
local Wheel_addCommands = ISBackButtonWheel.addCommands
function ISBackButtonWheel:addCommands()
    Wheel_addCommands(self)
    local playerObj = getSpecificPlayer(self.playerNum)
    if not playerObj then return end
    self:addSlice(getText("IGUI_PD_HUDTooltip"), getTexture("media/textures/CDDogPaw_64.png"),
        CD.openDogStatus, playerObj)
end

local ISEquippedItem_createChildren = ISEquippedItem.createChildren
function ISEquippedItem:createChildren()
    ISEquippedItem_createChildren(self)
    local ref = self.mainHand or self.offHand or self.invBtn or self.healthBtn
    if not ref then return end
    local w = ref:getWidth()
    local h = math.floor(w * 0.75)
    local btn = ISButton:new(0, self:getHeight() + 5, w, h, "", self, onDogStatusButton)
    btn.internal = "CDDOGSTATUS"
    btn:initialise()
    btn:instantiate()
    btn:setDisplayBackground(false)
    btn.cdTexOn = cdLoadPaw(w)
    btn.cdTexOff = getTexture("media/textures/CDDogPawGrey_" .. w .. ".png") or btn.cdTexOn
    local tex = btn.cdTexOff or btn.cdTexOn
    if tex then
        btn:setImage(tex)
    end
    btn:setTooltip(getText("IGUI_PD_HUDTooltip"))
    self:addChild(btn)
    self.cdDogStatusBtn = btn
end

local ISEquippedItem_prerender = ISEquippedItem.prerender
function ISEquippedItem:prerender()
    ISEquippedItem_prerender(self)
    local btn = self.cdDogStatusBtn
    if not btn then return end
    local wantTex = (ISCDStatusWindow.instanceFor(self.chr) ~= nil) and btn.cdTexOn or btn.cdTexOff
    if wantTex and btn.image ~= wantTex then
        btn:setImage(wantTex)
    end
    local w = btn:getWidth()
    local maxBottom = 0
    local globalMaxBottom = 0
    local kids = self.children
    if kids then
        for _, c in pairs(kids) do
            if c ~= btn and c:getIsVisible() then
                local b = c:getY() + c:getHeight()
                if b > globalMaxBottom then
                    globalMaxBottom = b
                end
                if math.abs(c:getWidth() - w) <= 4 and b > maxBottom then
                    maxBottom = b
                end
            end
        end
    end
    local ty = maxBottom + (UI_BORDER_SPACING or 10) + 5
    if math.abs(btn:getY() - ty) > 0.5 then
        btn:setY(ty)
    end
    self:setHeight(math.max(globalMaxBottom, ty + btn:getHeight()))
end
