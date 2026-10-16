require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISUI3DModel"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISTextEntryBox"

CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

ISCDKennelView = ISPanel:derive("ISCDKennelView")
ISCDKennelScroll = ISPanel:derive("ISCDKennelScroll")
ISCDKennelRow = ISPanel:derive("ISCDKennelRow")
ISCDDogAvatar = ISUI3DModel:derive("ISCDDogAvatar")

local PAD = 8
local ROW_H = 120
local AV_PAD = 4
local BTN_H = 22
local REFRESH_TICKS = 20

local C_NEAR = { r = 0.55, g = 0.85, b = 0.45 }
local C_WITH = { r = 1.00, g = 0.65, b = 0.10 }
local C_LOST = { r = 0.92, g = 0.28, b = 0.22 }
local C_FAR  = { r = 0.70, g = 0.70, b = 0.70 }

local function cdLevelFromXp(xp)
    xp = tonumber(xp) or 0
    local level, need = 0, 0
    while level < CD.SKILL_MAX_LEVEL do
        need = need + CD.SKILL_XP_BASE * (level + 1)
        if xp < need then break end
        level = level + 1
    end
    return level
end

local function cdSkillsSummary(animal, snapSkills, breedKey)
    local parts = {}
    for _, s in ipairs(CD.skillsFor(animal, breedKey)) do
        local lv = 0
        if animal then
            lv = CD.getSkillLevel(animal, s)
        elseif type(snapSkills) == "table" then
            lv = cdLevelFromXp(snapSkills[s])
        end
        if lv > 0 then
            parts[#parts + 1] = getText("IGUI_PD_Skill_" .. s) .. " " .. tostring(lv)
        end
    end
    return table.concat(parts, "  ")
end

local function cdSexLabel(sex, isPup, breedKey)
    if isPup then return CD.youngNounFromKey(breedKey) end
    if sex == "female" then return getText("IGUI_PD_Sex_Female") end
    if sex == "male" then
        if CD.breedSterileMale(breedKey) then
            return getText("IGUI_PD_Sex_Male") .. " (" .. getText("IGUI_PD_Sterile") .. ")"
        end
        return getText("IGUI_PD_Sex_Male")
    end
    return nil
end

local function cdRecallWait(snap)
    if not (snap and snap.recallAtMin) then return nil end
    local rem = CD.KENNEL_RECALL_COOLDOWN_MIN - (CD.worldMinutes() - snap.recallAtMin)
    if rem > 0 then return rem end
    return nil
end

local function cdCooldownLabel(mins)
    if mins >= 60 then
        return getText("IGUI_PD_KennelRecallIn", tostring(math.ceil(mins / 60)) .. "h")
    end
    return getText("IGUI_PD_KennelRecallIn", tostring(math.max(1, math.ceil(mins))) .. "min")
end

local function cdLastSeen(savedAtMin)
    if not savedAtMin then return nil end
    local mins = math.max(0, CD.worldMinutes() - savedAtMin)
    local hours = math.floor(mins / 60)
    if hours >= 48 then
        return getText("IGUI_PD_KennelLastSeenDays", tostring(math.floor(hours / 24)))
    end
    if hours < 1 then
        hours = 1
    end
    return getText("IGUI_PD_KennelLastSeen", tostring(hours))
end

local function cdFitText(font, txt, maxW)
    if getTextManager():MeasureStringX(font, txt) <= maxW then return txt end
    local s = txt
    while #s > 1 and getTextManager():MeasureStringX(font, s .. "...") > maxW do
        s = string.sub(s, 1, #s - 1)
    end
    return s .. "..."
end

local portraitCache = {}
local function cdPortrait(breedKey)
    breedKey = breedKey or "default"
    local tex = portraitCache[breedKey]
    if tex == nil then
        tex = getTexture("media/textures/CDPortrait_" .. breedKey .. ".png")
            or getTexture("media/textures/CDDogPaw_48.png")
            or false
        portraitCache[breedKey] = tex
    end
    return tex or nil
end

function ISCDDogAvatar:instantiate()
    ISUI3DModel.instantiate(self)
    self:setIsometric(false)
end

function ISCDDogAvatar:onMouseDown() return false end
function ISCDDogAvatar:onMouseMove() return false end
function ISCDDogAvatar:onMouseMoveOutside() return false end
function ISCDDogAvatar:onMouseUp() return false end
function ISCDDogAvatar:onMouseUpOutside() return false end

function ISCDDogAvatar:bindAnimal(animal)
    if self.boundAnimal == animal then return end
    self.boundAnimal = animal
    if animal then
        self:setAnimSetName(animal:GetAnimSetName())
        self:setCharacter(animal)
        self:setState("idle")
        self:setVisible(true)
    else
        self:setVisible(false)
    end
end

-- Teto do zoom: o render faz sizeV = 25 - zoom e monta o ortho em -sizeV..sizeV, entao negativo
-- espelha os dois eixos. O zoom cresce com o tamanho vivo, entao inverte so depois que o cao cresce.
local AVATAR_ZOOM_MAX = 22

function ISCDDogAvatar:applyFrame()
    local animal = self.boundAnimal
    if not animal then return end
    local def = AnimalAvatarDefinition[animal:getAnimalType()]
    if not def then return end
    local size = animal:getData():getSize()
    local zoom = (def.trailerZoom + (self.zoomAdd or 0)) * size
    if zoom > AVATAR_ZOOM_MAX then
        zoom = AVATAR_ZOOM_MAX
    end
    self:setZoom(zoom)
    self:setXOffset(def.trailerXoffset * size)
    self:setYOffset(def.trailerYoffset * size)
    self:setDirection(def.trailerDir)
    self:setVariable("TrailerAnimation", "idle1")
end

function ISCDKennelRow:new(x, y, w, h)
    local o = ISPanel.new(self, x, y, w, h)
    o.background = false
    return o
end

function ISCDKennelRow:createChildren()
    local s = self.height - AV_PAD * 2
    self.avatar = ISCDDogAvatar:new(AV_PAD, AV_PAD, s, s)
    self.avatar:initialise()
    self:addChild(self.avatar)
    self.avatar:setVisible(false)
end

function ISCDKennelRow:onMouseDown(x, y)
    if self.kennelView and self.rowData then
        self.kennelView.selectedToken = self.rowData.token
    end
    return true
end

function ISCDKennelRow:prerender()
    local r = self.rowData
    if not r then return end
    local w, h = self.width, self.height
    local kv = self.kennelView

    if self.altRow then
        self:drawRect(0, 0, w, h, 0.06, 1, 1, 1)
    end
    if kv and kv.selectedToken == r.token then
        self:drawRect(0, 0, w, h - 1, 0.30, 0.20, 0.40, 0.60)
        self:drawRectBorder(0, 0, w, h - 1, 0.6, 0.35, 0.55, 0.80)
    elseif self:isMouseOver() then
        self:drawRect(0, 0, w, h - 1, 0.08, 1, 1, 1)
    end

    local s = h - AV_PAD * 2
    self:drawRectBorder(AV_PAD - 1, AV_PAD - 1, s + 2, s + 2, 1, 0.3, 0.3, 0.3)
    if kv and kv.avatarBg then
        self:drawTextureScaled(kv.avatarBg, AV_PAD, AV_PAD, s, s, 1, 0.4, 0.4, 0.4)
    end
    if self.avatar and self.avatar.boundAnimal then
        self.avatar:applyFrame()
    else
        local tex = cdPortrait(r.breedKey)
        if tex then
            self:drawTextureScaled(tex, AV_PAD + 4, AV_PAD + 4, s - 8, s - 8, 1, 1, 1, 1)
        end
    end

    local font = UIFont.Small
    local fhh = getTextManager():getFontHeight(font)
    local tx = AV_PAD * 2 + s + 6
    local y1 = math.floor(h / 2) - fhh - 4
    local y2 = math.floor(h / 2) + 4

    local sw = getTextManager():MeasureStringX(font, r.statusText or "")
    self:drawText(r.statusText or "", w - sw - 6, y1, r.statusColor.r, r.statusColor.g, r.statusColor.b, 1, font)
    if r.active then
        local at = getTextManager():MeasureStringX(font, r.activeText)
        self:drawText(r.activeText, w - at - 6, y2, 0.55, 0.85, 0.45, 1, font)
    end

    local maxW = math.max(10, w - tx - sw - 12)
    self:drawText(cdFitText(font, r.title, maxW), tx, y1, 0.92, 0.92, 0.92, 1, font)
    if r.subText and r.subText ~= "" then
        self:drawText(cdFitText(font, r.subText, maxW), tx, y2, 0.62, 0.62, 0.62, 1, font)
    end

    self:drawRect(0, h - 1, w, 1, 0.25, 0.4, 0.4, 0.4)
end

function ISCDKennelScroll:new(x, y, w, h)
    local o = ISPanel.new(self, x, y, w, h)
    o.background = false
    return o
end

function ISCDKennelScroll:instantiate() CD.UI.viewInstantiate(self) end
function ISCDKennelScroll:onMouseWheel(del) return CD.UI.viewMouseWheel(self, del) end
function ISCDKennelScroll:prerender() CD.UI.viewBeginRender(self) end

function ISCDKennelScroll:render()
    local kv = self.kennelView
    if kv and #(kv.rowsData or {}) == 0 then
        local msg = getText("IGUI_PD_KennelEmpty")
        local mw = getTextManager():MeasureStringX(UIFont.Small, msg)
        self:drawText(msg, math.max(0, (self.width - mw) / 2), 20, 0.65, 0.65, 0.65, 1, UIFont.Small)
    end
    CD.UI.viewEndRender(self)
end

function ISCDKennelView:new(x, y, w, h)
    local o = ISPanel.new(self, x, y, w, h)
    o.background = false
    o.refreshTick = REFRESH_TICKS
    o.avatarBg = getTexture("media/ui/avatarBackgroundWhite.png")
    o.rowsData = {}
    o.rowPanels = {}
    return o
end

function ISCDKennelView:player()
    return getSpecificPlayer(self.playerNum or 0) or getPlayer()
end

function ISCDKennelView:createChildren()
    self.scroll = ISCDKennelScroll:new(PAD, PAD, math.max(20, self.width - PAD * 2), math.max(20, self.height - PAD * 3 - BTN_H))
    self.scroll.kennelView = self
    self:addChild(self.scroll)

    self.fetchBtn = ISButton:new(0, 0, 10, BTN_H, getText("IGUI_PD_CmdFetch"), self, ISCDKennelView.onFetch)
    self.fetchBtn:initialise()
    self:addChild(self.fetchBtn)
    self.statusBtn = ISButton:new(0, 0, 10, BTN_H, getText("IGUI_PD_Inspect"), self, ISCDKennelView.onStatus)
    self.statusBtn:initialise()
    self:addChild(self.statusBtn)
    self.selectBtn = ISButton:new(0, 0, 10, BTN_H, getText("IGUI_PD_KennelBtnSelect"), self, ISCDKennelView.onSelect)
    self.selectBtn:initialise()
    self:addChild(self.selectBtn)

    self:layout()
    self:refreshRows()
end

function ISCDKennelView:layout()
    if not self.scroll then return end
    local listH = self.height - PAD * 3 - BTN_H
    if listH < 60 then
        listH = 60
    end
    local listW = self.width - PAD * 2
    if listW < 120 then
        listW = 120
    end
    self.scroll:setX(PAD)
    self.scroll:setY(PAD)
    self.scroll:setWidth(listW)
    self.scroll:setHeight(listH)

    local btnY = PAD + listH + PAD
    local bw = math.floor((listW - PAD * 2) / 3)
    self.fetchBtn:setX(PAD)
    self.fetchBtn:setY(btnY)
    self.fetchBtn:setWidth(bw)
    self.statusBtn:setX(PAD * 2 + bw)
    self.statusBtn:setY(btnY)
    self.statusBtn:setWidth(bw)
    self.selectBtn:setX(PAD * 3 + bw * 2)
    self.selectBtn:setY(btnY)
    self.selectBtn:setWidth(bw)

    local cw = CD.UI.viewContentW(self.scroll)
    for _, rp in ipairs(self.rowPanels) do rp:setWidth(cw) end
    self.scroll:setScrollHeight(#self.rowsData * ROW_H)
end

function ISCDKennelView:refreshRows()
    if not self.scroll then return end
    local player = self:player()
    if not player then return end
    local pd = CD.playerData(player)

    local tokens = {}
    if type(pd.companions) == "table" then
        for t in pairs(pd.companions) do tokens[t] = true end
    end
    if type(pd.kennel) == "table" then
        for t in pairs(pd.kennel) do tokens[t] = true end
    end
    if pd.token ~= nil then
        tokens[pd.token] = true
    end

    local liveByToken = {}
    local comps = CD.regCompanions()
    for i = 1, #comps do
        local a = comps[i]
        if a:isExistInTheWorld() and not a:isDead() and CD.isOwnedBy(a, player) then
            local t = CD.data(a).companionToken
            if t ~= nil then
                liveByToken[t] = a
            end
        end
    end
    local ctok = pd.carried and pd.carried.data and pd.carried.data.companionToken
    local stok = pd.stash and pd.stash.data and pd.stash.data.companionToken

    local rows = {}
    for t in pairs(tokens) do
        local snap = type(pd.kennel) == "table" and pd.kennel[t] or nil
        local animal = liveByToken[t]
        local d = animal and CD.data(animal) or nil
        local pos = type(pd.dogPositions) == "table" and pd.dogPositions[t] or nil
        local name = (d and d.name) or (snap and snap.name) or (pos and pos.name)
        local breedKey = (d and d.breed) or (snap and snap.breed)
        local sex = (d and (d.sex or CD.animalSex(animal))) or (snap and snap.sex)
        local isPup = (d and d.isPup) or (snap and snap.isPup)

        local breedNoun = CD.breedNounFromKey(breedKey)
        local title = breedNoun
        local sexLabel = cdSexLabel(sex, isPup, breedKey)
        if sexLabel then
            title = title .. " (" .. sexLabel .. ")"
        end
        if name and name ~= "" then
            title = name .. "  -  " .. title
        end

        local statusText, statusColor, lastSeen
        if animal then
            statusText, statusColor = getText("IGUI_PD_KennelStatusNear"), C_NEAR
            local badge = CD.statusBadge(animal)
            if badge then
                statusText = statusText .. " · " .. getText(badge.key)
            end
        elseif t == ctok then
            statusText, statusColor = getText("IGUI_PD_KennelStatusCarried"), C_WITH
        elseif t == stok then
            statusText, statusColor = getText("IGUI_PD_InVehicleBanner"), C_WITH
        elseif snap and snap.lost then
            statusText, statusColor = getText("IGUI_PD_KennelStatusLost"), C_LOST
            lastSeen = cdLastSeen(snap.savedAtMin)
        elseif snap then
            statusText, statusColor = getText("IGUI_PD_KennelStatusFar"), C_FAR
            lastSeen = cdLastSeen(snap.savedAtMin)
        else
            statusText, statusColor = CD.speciesTextFromKey(breedKey, "IGUI_PD_KennelStatusNoData"), C_FAR
        end

        local sub = cdSkillsSummary(animal, snap and snap.skills, breedKey)
        if lastSeen then
            sub = (sub ~= "" and (sub .. "  ·  ") or "") .. lastSeen
        end
        local recallWait = cdRecallWait(snap)
        if recallWait then
            sub = (sub ~= "" and (sub .. "  ·  ") or "") .. cdCooldownLabel(recallWait)
        end

        rows[#rows + 1] = {
            token = t, animal = animal, snap = snap, breedKey = breedKey,
            recallWait = recallWait,
            withYou = (t == ctok or t == stok),
            title = title, subText = sub,
            statusText = statusText, statusColor = statusColor,
            active = (t == pd.token), activeText = getText("IGUI_PD_KennelActive"),
            sortName = name or breedNoun,
        }
    end

    table.sort(rows, function(a, b)
        if a.active ~= b.active then return a.active end
        if (a.animal ~= nil) ~= (b.animal ~= nil) then return a.animal ~= nil end
        if a.sortName ~= b.sortName then return a.sortName < b.sortName end
        return a.token < b.token
    end)

    self.rowsData = rows
    if self.selectedToken ~= nil then
        local found = false
        for _, r in ipairs(rows) do
            if r.token == self.selectedToken then
                found = true
                break
            end
        end
        if not found then
            self.selectedToken = nil
        end
    end

    local cw = CD.UI.viewContentW(self.scroll)
    for i, r in ipairs(rows) do
        local rp = self.rowPanels[i]
        if not rp then
            rp = ISCDKennelRow:new(0, (i - 1) * ROW_H, cw, ROW_H)
            rp.kennelView = self
            rp:initialise()
            self.scroll:addChild(rp)
            self.rowPanels[i] = rp
        end
        rp.rowData = r
        rp.altRow = (i % 2 == 0)
        rp:setY((i - 1) * ROW_H)
        rp:setWidth(cw)
        rp:setVisible(true)
        rp.avatar:bindAnimal(r.animal)
    end
    for i = #rows + 1, #self.rowPanels do
        local rp = self.rowPanels[i]
        rp.rowData = nil
        rp:setVisible(false)
        rp.avatar:bindAnimal(nil)
    end
    self.scroll:setScrollHeight(#rows * ROW_H)
end

function ISCDKennelView:selectedRow()
    if self.selectedToken == nil then return nil end
    for _, r in ipairs(self.rowsData or {}) do
        if r.token == self.selectedToken then return r end
    end
    return nil
end

function ISCDKennelView:prerender()
    self.refreshTick = (self.refreshTick or 0) + 1
    if self.refreshTick >= REFRESH_TICKS then
        self.refreshTick = 0
        self:refreshRows()
    end
    local row = self:selectedRow()
    self.fetchBtn:setEnable(row ~= nil and row.recallWait == nil
        and (row.animal ~= nil or (row.snap ~= nil and not row.withYou)))
    self.statusBtn:setEnable(row ~= nil and row.animal ~= nil)
    local onActive = row ~= nil and row.animal ~= nil and row.active
    self.selectBtn:setTitle(onActive and getText("IGUI_PD_KennelBtnDismiss") or getText("IGUI_PD_KennelBtnSelect"))
    self.selectBtn:setEnable(row ~= nil and row.animal ~= nil)
end

function ISCDKennelView:render()
    if self.scroll then
        self:drawRectBorder(self.scroll.x, self.scroll.y, self.scroll.width, self.scroll.height, 0.5, 0.4, 0.4, 0.4)
    end
end

local function cdCallout(player)
    if not player then return end
    player:playEmote("comehere")
    player:Callout(false)
end

function ISCDKennelView:onRecallConfirm(button)
    if button.internal ~= "YES" then return end
    local tok = self.pendingRecallToken
    self.pendingRecallToken = nil
    if tok == nil then return end
    cdCallout(self:player())
    CD.requestStashed("recall", { token = tok }, self:player())
end

function ISCDKennelView:onFetch()
    local row = self:selectedRow()
    if not row or row.recallWait then return end
    if row.animal then
        cdCallout(self:player())
        CD.request("teleport", row.animal, nil, self:player())
        return
    end
    if not row.snap or row.withYou then return end
    self.pendingRecallToken = row.token
    local modal = ISModalDialog:new(0, 0, 340, 140,
        getText("IGUI_PD_KennelRecallConfirm", row.sortName), true, self, ISCDKennelView.onRecallConfirm, self.playerNum or 0)
    modal:initialise()
    modal:addToUIManager()
end

function ISCDKennelView:onStatus()
    local row = self:selectedRow()
    if row and row.animal then
        ISCDStatusWindow.OpenFor(row.animal, "status", self:player())
    end
end

function ISCDKennelView:onSelect()
    local row = self:selectedRow()
    if row and row.animal then
        CD.request(row.active and "dismiss" or "select", row.animal, nil, self:player())
    end
end

ISCDAdminKennelWindow = ISCollapsableWindow:derive("ISCDAdminKennelWindow")
ISCDAdminKennelScroll = ISPanel:derive("ISCDAdminKennelScroll")

local ADM_ROW_H = 18
local ADM_MIN_W, ADM_MIN_H = 360, 220
local ADM_DEF_W, ADM_DEF_H = 480, 380

local function cdAdminStatus(dog, now)
    if dog.lost then return getText("IGUI_PD_KennelStatusLost"), true end
    local s = ""
    if dog.savedAtMin and now then
        local hrs = math.max(0, math.floor((now - dog.savedAtMin) / 60 + 0.5))
        s = getText("IGUI_PD_KennelLastSeen", tostring(hrs))
    end
    if dog.x then
        local coord = "(" .. tostring(dog.x) .. "," .. tostring(dog.y) .. "," .. tostring(dog.z or 0) .. ")"
        s = (s ~= "" and (s .. "  ") or "") .. coord
    end
    return s, false
end

function ISCDAdminKennelScroll:instantiate() CD.UI.viewInstantiate(self) end
function ISCDAdminKennelScroll:onMouseWheel(del) return CD.UI.viewMouseWheel(self, del) end
function ISCDAdminKennelScroll:prerender() CD.UI.viewBeginRender(self) end

function ISCDAdminKennelScroll:render()
    local win = self.adminWin
    local lines = (win and win.lines) or {}
    if #lines == 0 then
        local msg = getText((win and win.waiting) and "IGUI_PD_AdminKennelWait" or "IGUI_PD_AdminKennelEmpty")
        local mw = getTextManager():MeasureStringX(UIFont.Small, msg)
        self:drawText(msg, math.max(0, (self.width - mw) / 2), 20, 0.65, 0.65, 0.65, 1, UIFont.Small)
    else
        local y = 4
        for _, ln in ipairs(lines) do
            self:drawText(ln.text, 6 + (ln.lvl or 0) * 16, y, ln.r, ln.g, ln.b, 1, UIFont.Small)
            y = y + ADM_ROW_H
        end
    end
    CD.UI.viewEndRender(self)
end

function ISCDAdminKennelWindow:new(x, y, w, h)
    local o = ISCollapsableWindow.new(self, x, y, w, h)
    o.title = getText("IGUI_PD_AdminKennelTitle")
    o.lines = {}
    o.data = nil
    o.lastFilter = ""
    o.waiting = true
    return o
end

function ISCDAdminKennelWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    self.searchLbl = getText("IGUI_PD_AdminSearch")
    self.searchLblW = getTextManager():MeasureStringX(UIFont.Small, self.searchLbl)
    self.searchEntry = ISTextEntryBox:new("", 0, 0, 10, BTN_H)
    self.searchEntry:initialise()
    self.searchEntry:instantiate()
    self:addChild(self.searchEntry)
    self.scroll = ISCDAdminKennelScroll:new(PAD, self:titleBarHeight() + PAD, 20, 20)
    self.scroll.adminWin = self
    self:addChild(self.scroll)
    self.refreshBtn = ISButton:new(0, 0, 10, BTN_H, getText("IGUI_PD_AdminRefresh"), self, ISCDAdminKennelWindow.onRefresh)
    self.refreshBtn:initialise()
    self:addChild(self.refreshBtn)
    CD.UI.initResizable(self, "dogadmin", ADM_MIN_W, ADM_MIN_H)
    self:reflow()
end

function ISCDAdminKennelWindow:reflow()
    if not self.scroll then return end
    local top = self:titleBarHeight()
    local rh = self:resizeWidgetHeight()
    local rowY = top + PAD
    local lblW = self.searchLblW or 60
    if self.searchEntry then
        self.searchEntry:setX(PAD + lblW + 6)
        self.searchEntry:setY(rowY)
        self.searchEntry:setWidth(math.max(80, self.width - PAD * 2 - lblW - 6))
        self.searchEntry:setHeight(BTN_H)
    end
    local listY = rowY + BTN_H + PAD
    local listW = math.max(120, self.width - PAD * 2)
    local listH = math.max(60, self.height - listY - PAD * 2 - BTN_H - rh)
    self.scroll:setX(PAD)
    self.scroll:setY(listY)
    self.scroll:setWidth(listW)
    self.scroll:setHeight(listH)
    self.scroll:setScrollHeight(#self.lines * ADM_ROW_H + 8)
    local btnY = listY + listH + PAD
    self.refreshBtn:setX(PAD)
    self.refreshBtn:setY(btnY)
    self.refreshBtn:setWidth(listW)
end

function ISCDAdminKennelWindow:render()
    ISCollapsableWindow.render(self)
    if self.searchEntry and not self.isCollapsed then
        self:drawText(self.searchLbl or "", PAD, self.searchEntry:getY() + 4, 0.75, 0.75, 0.75, 1, UIFont.Small)
    end
end

function ISCDAdminKennelWindow:prerender()
    ISCollapsableWindow.prerender(self)
    local f = ""
    if self.searchEntry then
        f = self.searchEntry:getText() or ""
    end
    if f ~= self.lastFilter then
        self.lastFilter = f
        self:rebuildLines()
    end
end

function ISCDAdminKennelWindow:rebuildLines()
    local lines = {}
    local data = self.data
    if data then
        local filter = tostring(self.lastFilter or ""):lower()
        for _, o in ipairs(data.owners) do
            local oname = tostring(o.name or o.key or "?")
            if filter == "" or oname:lower():find(filter, 1, true) or tostring(o.key or ""):lower():find(filter, 1, true) then
                local dogs = type(o.dogs) == "table" and o.dogs or {}
                local label = oname
                if o.name and o.key and o.name ~= o.key then
                    label = label .. " (" .. tostring(o.key) .. ")"
                end
                label = label .. "  [" .. getText(o.online and "IGUI_PD_AdminOnline" or "IGUI_PD_AdminOffline") .. "]"
                    .. "  -  " .. getText("IGUI_PD_AdminDogCount", tostring(#dogs))
                lines[#lines + 1] = { text = label, r = 0.95, g = 0.88, b = 0.55, lvl = 0 }
                for _, dog in ipairs(dogs) do
                    local noun = CD.breedNounFromKey(dog.breed)
                    local title = noun
                    local sexLabel = cdSexLabel(dog.sex, dog.isPup, dog.breed)
                    if sexLabel then
                        title = title .. " (" .. sexLabel .. ")"
                    end
                    if dog.name and dog.name ~= "" then
                        title = tostring(dog.name) .. "  -  " .. title
                    end
                    local st, isLost = cdAdminStatus(dog, data.now)
                    if st ~= "" then
                        title = title .. "   " .. st
                    end
                    if isLost then
                        lines[#lines + 1] = { text = title, r = C_LOST.r, g = C_LOST.g, b = C_LOST.b, lvl = 1 }
                    else
                        lines[#lines + 1] = { text = title, r = 0.82, g = 0.82, b = 0.82, lvl = 1 }
                    end
                    local sk = cdSkillsSummary(nil, dog.skills, dog.breed)
                    if sk ~= "" then
                        lines[#lines + 1] = { text = sk, r = 0.58, g = 0.68, b = 0.80, lvl = 2 }
                    end
                end
            end
        end
    end
    self.lines = lines
    self:reflow()
end

function ISCDAdminKennelWindow:onRefresh()
    self.waiting = true
    self.lines = {}
    self:reflow()
    CD.request("kenneladmin", nil, {}, self.owner)
end

function ISCDAdminKennelWindow:close()
    CD.UI.persist(self)
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    if ISCDAdminKennelWindow.instance == self then
        ISCDAdminKennelWindow.instance = nil
    end
end

---Fills the open admin kennel window with the owners the server listed; ignored when it is closed.
---@param payload table|nil { owners, now }; nil shows an empty list
function CD.onKennelAdminList(payload)
    local win = ISCDAdminKennelWindow.instance
    if not win then return end
    win.waiting = false
    local owners = (type(payload) == "table" and type(payload.owners) == "table") and payload.owners or {}
    table.sort(owners, function(a, b)
        return tostring(a.name or a.key or ""):lower() < tostring(b.name or b.key or ""):lower()
    end)
    for _, o in ipairs(owners) do
        if type(o.dogs) == "table" then
            table.sort(o.dogs, function(a, b) return tostring(a.name or ""):lower() < tostring(b.name or ""):lower() end)
        end
    end
    win.data = { owners = owners, now = (type(payload) == "table") and payload.now or nil }
    win:rebuildLines()
end

---Opens the admin kennel window, replacing an open one, and asks the server for the list.
---@param playerObj IsoPlayer
function CD.openAdminKennel(playerObj)
    if ISCDAdminKennelWindow.instance then
        ISCDAdminKennelWindow.instance:close()
    end
    local win = ISCDAdminKennelWindow:new(0, 0, ADM_DEF_W, ADM_DEF_H)
    win.owner = playerObj
    win:initialise()
    win:instantiate()
    CD.UI.applyOpenGeometry(win, "dogadmin", ADM_DEF_W, ADM_DEF_H)
    win:addToUIManager()
    ISCDAdminKennelWindow.instance = win
    CD.request("kenneladmin", nil, {}, playerObj)
end

ISCDTuningWindow = ISCollapsableWindow:derive("ISCDTuningWindow")
ISCDTuningScroll = ISPanel:derive("ISCDTuningScroll")

local TUN_MIN_W, TUN_MIN_H = 470, 434
local TUN_DEF_W, TUN_DEF_H = 640, 580
local TUN_ENTRY_W, TUN_ENTRY_H = 78, 22
local TUN_ROW_GAP = 18
local TUN_REFRESH_MS = 3000

local C_HDR  = { r = 0.95, g = 0.88, b = 0.55 }
local C_TXT  = { r = 0.84, g = 0.84, b = 0.84 }
local C_DIM  = { r = 0.55, g = 0.55, b = 0.55 }
local C_NOTE = { r = 0.60, g = 0.66, b = 0.74 }
local C_WARN = { r = 0.93, g = 0.58, b = 0.25 }
local C_MOD  = { r = 0.55, g = 0.85, b = 0.45 }

local function tunFH(font) return getTextManager():getFontHeight(font) end
local function tunW(font, s) return getTextManager():MeasureStringX(font, s) end

local function tunWrap(font, s, maxW)
    local out = {}
    if not s or s == "" or maxW < 40 then return out end
    local line = ""
    for word in string.gmatch(s, "%S+") do
        local try = (line == "") and word or (line .. " " .. word)
        if tunW(font, try) <= maxW then
            line = try
        else
            if line ~= "" then
                out[#out + 1] = line
            end
            line = word
        end
    end
    if line ~= "" then
        out[#out + 1] = line
    end
    return out
end

function ISCDTuningScroll:instantiate() CD.UI.viewInstantiate(self) end
function ISCDTuningScroll:onMouseWheel(del) return CD.UI.viewMouseWheel(self, del) end
function ISCDTuningScroll:prerender() CD.UI.viewBeginRender(self) end

-- Nunca chamar entry:unfocus() daqui: o onLostFocus roda de dentro do UnfocusActiveTextEntryBox,
-- que desreferencia o Core.currentTextEntryBox logo depois. NPE por frame.
local function tunEntryCommit(entry)
    local scroll = entry.cdScroll
    local win = scroll and scroll.tuneWin
    local spec = CD.tunableSpec(entry.cdKey)
    if not spec then return end
    local txt = entry:getInternalText() or ""
    local v = tonumber(txt)
    if v == nil then return end
    local cur = tonumber(win and win.values and win.values[spec.key])
    if cur ~= nil and v == cur then return end
    entry.cdCommitted = true
    CD.request("tuningset", nil, { key = spec.key, value = v })
end

function ISCDTuningScroll:buildRows()
    self.rows = {}
    for i = 1, #(CD.TUNABLES or {}) do
        local spec = CD.TUNABLES[i]
        local e = ISTextEntryBox:new("", 0, 0, TUN_ENTRY_W, TUN_ENTRY_H)
        e:initialise()
        e:instantiate()
        self:addChild(e)
        e:setOnlyNumbers(true)
        e.cdKey = spec.key
        e.cdScroll = self
        e.onCommandEntered = tunEntryCommit
        e.onLostFocus = tunEntryCommit
        self.rows[i] = { spec = spec, entry = e }
    end
end

function ISCDTuningScroll:syncEntries(values)
    for i = 1, #(self.rows or {}) do
        local row = self.rows[i]
        local v = values and values[row.spec.key]
        if v ~= nil and row.entry then
            local focused = row.entry:isFocused()
            if (not focused) or row.entry.cdCommitted then
                local cur = row.entry:getInternalText() or ""
                if cur ~= tostring(v) then
                    row.entry:setText(tostring(v))
                end
                row.entry.cdCommitted = false
            end
        end
    end
end

function ISCDTuningScroll:layout()
    local cw = CD.UI.viewContentW(self)
    local win = self.tuneWin
    local sh = tunFH(UIFont.Small)
    local y = 6

    local L = { perf = {}, rows = {} }
    L.perfY = y
    local perf = (win and win.perf) or nil
    local hasPerf = perf ~= nil and perf.ticks ~= nil
    if win and win.waiting then
        L.perf[#L.perf + 1] = { t = "waiting for the server...", c = C_DIM }
    elseif not (win and win.perfOn) then
        L.perf[#L.perf + 1] = { t = hasPerf and "Measurement is off: the numbers below are the last window recorded."
                                          or "Measurement is off. Turn it on below, wait one window, then read here.", c = C_DIM }
    elseif not hasPerf then
        L.perf[#L.perf + 1] = { t = "Measurement on: first window closes in up to " .. tostring((win and win.secs) or 20) .. "s.", c = C_DIM }
    end
    if hasPerf then
        L.perf[#L.perf + 1] = { t = string.format("companionTick: %.2f ms/s load   %.3f ms/tick   %.1f ticks/s   (%d ticks in %.0fs)",
            perf.msPerSec or 0, perf.msPerTick or 0, perf.ticksPerSec or 0, perf.ticks or 0, perf.secs or 0), c = C_TXT }
        L.perf[#L.perf + 1] = { t = string.format("loaded dogs: %d (%d companions)   cell:getAnimals() sweeps: %.1f/s",
            perf.dogs or 0, perf.comps or 0, perf.scans or 0), c = C_TXT }
    end
    local fg = CD._perfLast.fallGuard
    if fg then
        L.perf[#L.perf + 1] = { t = string.format("fall guard (this client): %.2f+-%.2f ms/s   %.1f sweeps/s x %.0f dogs   %.2f misses/s   %d flag writes in %.0fs",
            fg.msPerSec, fg.band, fg.sweeps, fg.dogs, fg.misses, fg.writes, fg.secs), c = C_TXT }
    end
    if win and win.clockMs then
        local coarse = win.clockMs > 2
        L.perf[#L.perf + 1] = {
            t = string.format("clock granularity %.1f ms   probe %.2f us   spike threshold %s ms   depth %d%s",
                win.clockMs, win.probeUs or 0, tostring(win.spikeMs or "?"), win.level or 0,
                win.csvOn and "   CSV: RECORDING" or ""),
            c = coarse and C_WARN or C_DIM }
        if coarse then
            L.perf[#L.perf + 1] = { t = "COARSE CLOCK: read the counters below as the primary evidence; ms per zone only in aggregate.",
                                    c = C_WARN }
        end
    end
    if win and win.csvOn and win.csvName then
        L.perf[#L.perf + 1] = { t = "writing " .. tostring(win.csvName) .. " in the Zomboid folder", c = C_NOTE }
    end
    y = y + #L.perf * (sh + 2) + 4
    L.barsY = y
    L.bars = {}
    if hasPerf and perf.blocks and #perf.blocks > 0 then
        local maxV = 0
        for i = 1, #perf.blocks do
            if (perf.blocks[i].msPerSec or 0) > maxV then
                maxV = perf.blocks[i].msPerSec
            end
        end
        for i = 1, #perf.blocks do
            L.bars[i] = { key = perf.blocks[i].key, v = perf.blocks[i].msPerSec or 0,
                          frac = (maxV > 0) and ((perf.blocks[i].msPerSec or 0) / maxV) or 0 }
        end
        y = y + #L.bars * (sh + 3) + 2
        L.nestY = y
        y = y + sh + 4
    end
    L.cntY = y
    L.cnt = nil
    if hasPerf and perf.counters and #perf.counters > 0 then
        local parts = {}
        for i = 1, #perf.counters do
            parts[#parts + 1] = string.format("%s %.0f/s", tostring(perf.counters[i].key), perf.counters[i].perSec or 0)
        end
        L.cnt = "counters: " .. table.concat(parts, "   ")
        y = y + sh + 4
    end
    L.gauY = y
    L.gau = nil
    if hasPerf and perf.gauges and #perf.gauges > 0 then
        local parts = {}
        for i = 1, #perf.gauges do
            parts[#parts + 1] = string.format("%s avg %.1f max %.0f", tostring(perf.gauges[i].key),
                perf.gauges[i].avg or 0, perf.gauges[i].max or 0)
        end
        L.gau = "gauges (window average, not a rate): " .. table.concat(parts, "   ")
        y = y + sh + 4
    end

    y = y + 6
    L.knobHdrY = y
    y = y + tunFH(UIFont.Medium) + 6

    local entryX = cw - 12 - TUN_ENTRY_W
    local noteW = math.max(80, entryX - 24)
    for i = 1, #(self.rows or {}) do
        local row = self.rows[i]
        row.y = y
        row.entry:setX(entryX)
        row.entry:setY(y - 3)
        y = y + math.max(TUN_ENTRY_H, sh) + 4
        row.noteLines = tunWrap(UIFont.Small, row.spec.note, noteW)
        y = y + #row.noteLines * (sh + 2)
        row.sepY = y + math.floor(TUN_ROW_GAP / 2)
        y = y + TUN_ROW_GAP
    end

    L.contentH = y + 4
    self.L = L
    self:setScrollHeight(L.contentH)
end

function ISCDTuningScroll:render()
    local win = self.tuneWin
    local L = self.L
    if not L then
        CD.UI.viewEndRender(self)
        return
    end
    local cw = CD.UI.viewContentW(self)
    local sh = tunFH(UIFont.Small)

    local y = L.perfY
    for i = 1, #L.perf do
        self:drawText(L.perf[i].t, 8, y, L.perf[i].c.r, L.perf[i].c.g, L.perf[i].c.b, 1, UIFont.Small)
        y = y + sh + 2
    end
    if L.bars and #L.bars > 0 then
        y = L.barsY
        local labelW = 96
        local barX = 8 + labelW
        local barW = math.max(40, cw - barX - 90)
        for i = 1, #L.bars do
            local b = L.bars[i]
            self:drawText(tostring(b.key), 8, y, 0.78, 0.80, 0.84, 1, UIFont.Small)
            self:drawRect(barX, y + 3, barW, sh - 4, 0.85, 0.10, 0.10, 0.10)
            self:drawRect(barX, y + 3, math.max(1, barW * b.frac), sh - 4, 0.9, 0.45, 0.66, 0.40)
            self:drawText(string.format("%.2f ms/s", b.v), barX + barW + 8, y, 0.78, 0.80, 0.84, 1, UIFont.Small)
            y = y + sh + 3
        end
        self:drawText("Self time: each ms counts in one row only, so the rows add up.",
            8, L.nestY, C_DIM.r, C_DIM.g, C_DIM.b, 1, UIFont.Small)
    end
    if L.cnt then
        self:drawText(L.cnt, 8, L.cntY, C_NOTE.r, C_NOTE.g, C_NOTE.b, 1, UIFont.Small)
    end
    if L.gau then
        self:drawText(L.gau, 8, L.gauY, C_NOTE.r, C_NOTE.g, C_NOTE.b, 1, UIFont.Small)
    end

    self:drawText("SERVER TUNING", 8, L.knobHdrY, C_HDR.r, C_HDR.g, C_HDR.b, 1, UIFont.Medium)

    local entryX = cw - 12 - TUN_ENTRY_W
    for i = 1, #(self.rows or {}) do
        local row = self.rows[i]
        local spec = row.spec
        local cur = (win and win.values and win.values[spec.key])
        local c = ((cur ~= nil) and (cur ~= spec.def)) and C_MOD or C_TXT
        self:drawText(spec.label, 8, row.y, c.r, c.g, c.b, 1, UIFont.Small)
        local defTxt = "default " .. tostring(spec.def) .. "   (" .. tostring(spec.min) .. ".." .. tostring(spec.max) .. ")"
        local dX = entryX - 12 - tunW(UIFont.Small, defTxt)
        if dX > 8 + tunW(UIFont.Small, spec.label) + 12 then
            self:drawText(defTxt, dX, row.y, C_DIM.r, C_DIM.g, C_DIM.b, 1, UIFont.Small)
        end
        local ny = row.y + math.max(TUN_ENTRY_H, sh) + 4
        local warn = string.sub(spec.note or "", 1, 7) == "WARNING"
        local nc = warn and C_WARN or C_NOTE
        for j = 1, #(row.noteLines or {}) do
            self:drawText(row.noteLines[j], 16, ny, nc.r, nc.g, nc.b, 1, UIFont.Small)
            ny = ny + sh + 2
        end
        if row.sepY then
            self:drawRect(8, row.sepY, math.max(10, cw - 16), 1, 0.14, 1, 1, 1)
        end
    end
    CD.UI.viewEndRender(self)
end

function ISCDTuningWindow:new(x, y, w, h)
    local o = ISCollapsableWindow.new(self, x, y, w, h)
    o.title = "Companion Dogs - server tuning"
    o.values = nil
    o.perf = nil
    o.perfOn = false
    o.level = 0
    o.csvOn = false
    o.dmgOn = false
    o.netAuthOn = true
    o.loiterOn = true
    o.huntOn = true
    o.traceLeft = 0
    o.secs = 20
    o.waiting = true
    o.lastReqMs = 0
    return o
end

function ISCDTuningWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    local top = self:titleBarHeight()
    local listW = math.max(120, self.width - PAD * 2)
    local listH = math.max(60, self.height - (top + PAD) - PAD * 5 - BTN_H * 4 - self:resizeWidgetHeight())
    local halfW = math.floor((listW - PAD) / 2)
    local btnY = top + PAD + listH + PAD
    self.scroll = ISCDTuningScroll:new(PAD, top + PAD, listW, listH)
    self.scroll.background = false
    self.scroll.tuneWin = self
    self:addChild(self.scroll)
    self.scroll:buildRows()
    local thirdW = math.floor((listW - PAD * 2) / 3)
    self.levelBtn = ISButton:new(PAD, btnY, thirdW, BTN_H, "Depth: ?", self, ISCDTuningWindow.onLevelToggle)
    self.levelBtn:initialise()
    self:addChild(self.levelBtn)
    self.csvBtn = ISButton:new(PAD + thirdW + PAD, btnY, thirdW, BTN_H, "CSV log: ?", self, ISCDTuningWindow.onCsvToggle)
    self.csvBtn:initialise()
    self:addChild(self.csvBtn)
    self.traceBtn = ISButton:new(PAD + (thirdW + PAD) * 2, btnY, thirdW, BTN_H, "Trace 600 ticks", self, ISCDTuningWindow.onTrace)
    self.traceBtn:initialise()
    self:addChild(self.traceBtn)
    local btnY2 = btnY + BTN_H + PAD
    self.perfBtn = ISButton:new(PAD, btnY2, halfW, BTN_H, "Measurement: ?", self, ISCDTuningWindow.onPerfToggle)
    self.perfBtn:initialise()
    self:addChild(self.perfBtn)
    self.resetBtn = ISButton:new(PAD + halfW + PAD, btnY2, halfW, BTN_H, "Restore defaults", self, ISCDTuningWindow.onReset)
    self.resetBtn:initialise()
    self:addChild(self.resetBtn)
    local btnY3 = btnY2 + BTN_H + PAD
    self.dmgBtn = ISButton:new(PAD, btnY3, halfW, BTN_H, "Damage diagnostics: ?", self, ISCDTuningWindow.onDmgToggle)
    self.dmgBtn:initialise()
    self:addChild(self.dmgBtn)
    self.netAuthBtn = ISButton:new(PAD + halfW + PAD, btnY3, halfW, BTN_H, "Client authority: ?", self, ISCDTuningWindow.onNetAuthToggle)
    self.netAuthBtn:initialise()
    -- Quebra de linha na mao: o ISButton desliga o wrap automatico assim que o texto tem \n.
    self.netAuthBtn:setTooltip(
        "ON: the owner's game moves the dog, the server only checks it.\n" ..
        "Smooth movement, more network packets.\n" ..
        " \n" ..
        "OFF: the server moves every dog.\n" ..
        "Fewer packets, choppy movement, more server load.")
    self:addChild(self.netAuthBtn)
    local btnY4 = btnY3 + BTN_H + PAD
    self.loiterBtn = ISButton:new(PAD, btnY4, halfW, BTN_H, "Idle dogs wander: ?", self, ISCDTuningWindow.onLoiterToggle)
    self.loiterBtn:initialise()
    self.loiterBtn:setTooltip("Idle dogs walk around and interact. Cosmetic only, costs a little performance.")
    self:addChild(self.loiterBtn)
    self.huntBtn = ISButton:new(PAD + halfW + PAD, btnY4, halfW, BTN_H, "Hunting: ?", self, ISCDTuningWindow.onHuntToggle)
    self.huntBtn:initialise()
    self.huntBtn:setTooltip(
        "ON: dogs can hunt.\n" ..
        " \n" ..
        "OFF: hunting is off for everyone on the server.\n" ..
        "Dogs ignore prey even with Hunt mode on, and the\n" ..
        "foraging bonus and the foraging scout stop working.")
    self:addChild(self.huntBtn)
    CD.UI.initResizable(self, "dogtune", TUN_MIN_W, TUN_MIN_H)
    self:reflow()
end

function ISCDTuningWindow:reflow()
    if not (self.scroll and self.perfBtn) then return end
    local top = self:titleBarHeight()
    local rh = self:resizeWidgetHeight()
    local listY = top + PAD
    local listW = math.max(120, self.width - PAD * 2)
    local listH = math.max(60, self.height - listY - PAD * 5 - BTN_H * 4 - rh)
    self.scroll:setX(PAD)
    self.scroll:setY(listY)
    self.scroll:setWidth(listW)
    self.scroll:setHeight(listH)
    self.scroll:layout()
    local btnY = listY + listH + PAD
    local btnY2 = btnY + BTN_H + PAD
    local halfW = math.floor((listW - PAD) / 2)
    local thirdW = math.floor((listW - PAD * 2) / 3)
    if self.levelBtn then
        self.levelBtn:setX(PAD)
        self.levelBtn:setY(btnY)
        self.levelBtn:setWidth(thirdW)
    end
    if self.csvBtn then
        self.csvBtn:setX(PAD + thirdW + PAD)
        self.csvBtn:setY(btnY)
        self.csvBtn:setWidth(thirdW)
    end
    if self.traceBtn then
        self.traceBtn:setX(PAD + (thirdW + PAD) * 2)
        self.traceBtn:setY(btnY)
        self.traceBtn:setWidth(thirdW)
    end
    self.perfBtn:setX(PAD)
    self.perfBtn:setY(btnY2)
    self.perfBtn:setWidth(halfW)
    self.resetBtn:setX(PAD + halfW + PAD)
    self.resetBtn:setY(btnY2)
    self.resetBtn:setWidth(halfW)
    if self.dmgBtn then
        self.dmgBtn:setX(PAD)
        self.dmgBtn:setY(btnY2 + BTN_H + PAD)
        self.dmgBtn:setWidth(halfW)
    end
    if self.netAuthBtn then
        self.netAuthBtn:setX(PAD + halfW + PAD)
        self.netAuthBtn:setY(btnY2 + BTN_H + PAD)
        self.netAuthBtn:setWidth(halfW)
    end
    if self.loiterBtn then
        self.loiterBtn:setX(PAD)
        self.loiterBtn:setY(btnY2 + (BTN_H + PAD) * 2)
        self.loiterBtn:setWidth(halfW)
    end
    if self.huntBtn then
        self.huntBtn:setX(PAD + halfW + PAD)
        self.huntBtn:setY(btnY2 + (BTN_H + PAD) * 2)
        self.huntBtn:setWidth(halfW)
    end
end

function ISCDTuningWindow:prerender()
    ISCollapsableWindow.prerender(self)
    local now = getTimestampMs()
    if now - (self.lastReqMs or 0) > TUN_REFRESH_MS then
        self.lastReqMs = now
        CD.request("tuningget", nil, {})
    end
    if self.perfBtn then
        self.perfBtn:setTitle(self.perfOn and "Measurement: ON" or "Measurement: off")
    end
    if self.levelBtn then
        self.levelBtn:setTitle((self.level or 0) >= 2 and "Depth: 2 (deep)" or "Depth: 1 (blocks)")
        self.levelBtn:setEnable(self.perfOn == true)
    end
    if self.csvBtn then
        self.csvBtn:setTitle(self.csvOn and "CSV log: RECORDING" or "CSV log: off")
    end
    if self.traceBtn then
        local left = self.traceLeft or 0
        self.traceBtn:setTitle(left > 0 and ("Tracing: " .. tostring(left)) or "Trace 600 ticks")
        self.traceBtn:setEnable(self.perfOn == true and left == 0)
    end
    if self.dmgBtn then
        self.dmgBtn:setTitle(self.dmgOn and "Damage diagnostics: ON" or "Damage diagnostics: off")
    end
    if self.netAuthBtn then
        self.netAuthBtn:setTitle(self.netAuthOn and "Client authority: ON" or "Client authority: off")
    end
    if self.loiterBtn then
        self.loiterBtn:setTitle(self.loiterOn and "Idle dogs wander: ON" or "Idle dogs wander: off")
    end
    if self.huntBtn then
        self.huntBtn:setTitle(self.huntOn and "Hunting: ON" or "Hunting: off")
    end
end

function ISCDTuningWindow:onLoiterToggle()
    CD.request("passiveidle", nil, { on = not self.loiterOn })
end

function ISCDTuningWindow:onHuntToggle()
    CD.request("hunttoggle", nil, { on = not self.huntOn })
end

function ISCDTuningWindow:onDmgToggle()
    CD.request("dmgdebug", nil, { on = not self.dmgOn })
end

function ISCDTuningWindow:onNetAuthToggle()
    CD.request("netauthority", nil, { on = not self.netAuthOn })
end

local function setClientPerf(on)
    CD.PERF_DEBUG = on
    CD.perfApplyLevel()
    CD.perfReset()
    if on then
        CD.perfCalibrate()
    end
end

function ISCDTuningWindow:onPerfToggle()
    local want = not self.perfOn
    if isClient() then
        setClientPerf(want)
    end
    CD.request("perfdebug", nil, { on = want })
end

function ISCDTuningWindow:onLevelToggle()
    local want = ((self.level or 1) >= 2) and 1 or 2
    if isClient() then
        CD.PERF_LEVEL = want
        CD.perfApplyLevel()
    end
    CD.request("perflevel", nil, { level = want })
end

function ISCDTuningWindow:onCsvToggle()
    local want = not self.csvOn
    if isClient() then
        if want and not CD.PERF_DEBUG then
            CD.PERF_DEBUG = true
            CD.perfApplyLevel()
        end
        CD.perfCsvArm(want)
    end
    CD.request("perfcsv", nil, { on = want })
end

function ISCDTuningWindow:onTrace()
    if isClient() and CD.perfTraceArm then
        CD.perfTraceArm(600)
    end
    CD.request("perftrace", nil, { ticks = 600 })
end

function ISCDTuningWindow:onReset()
    CD.request("tuningreset", nil, {})
end

function ISCDTuningWindow:close()
    CD.UI.persist(self)
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    if ISCDTuningWindow.instance == self then
        ISCDTuningWindow.instance = nil
    end
end

---Fills the open tuning window with the server values; the first list also aligns this client's meter with the server.
---@param payload table server tuning payload
function CD.onTuningList(payload)
    local win = ISCDTuningWindow.instance
    if not win or type(payload) ~= "table" then return end
    local firstList = win.waiting
    win.waiting = false
    win.values = type(payload.values) == "table" and payload.values or {}
    win.perf   = type(payload.perf) == "table" and payload.perf or nil
    win.perfOn = payload.perfOn == true
    -- Medicao ligada numa sessao anterior deixaria este client sem medidor. So no primeiro pacote:
    -- depois dele quem manda e o botao, e um pacote antigo ainda em transito desfaria o clique.
    if firstList and isClient() and win.perfOn ~= (CD.PERF_DEBUG == true) then
        setClientPerf(win.perfOn)
    end
    win.secs   = payload.secs or 20
    win.level     = payload.level or 0
    win.csvOn     = payload.csvOn == true
    win.csvName   = payload.csvName
    win.clockMs   = payload.clockMs
    win.probeUs   = payload.probeUs
    win.spikeMs   = payload.spikeMs
    win.traceLeft = payload.trace or 0
    win.dmgOn     = payload.dmgOn == true
    win.netAuthOn = payload.netAuthOn ~= false
    win.loiterOn = payload.loiterOn ~= false
    win.huntOn = payload.huntOn ~= false
    if win.scroll then
        win.scroll:syncEntries(win.values)
        win.scroll:layout()
    end
end

---Opens the server tuning and performance window, replacing an open one, and asks the server for the values.
function CD.openTuningPanel()
    if ISCDTuningWindow.instance then
        ISCDTuningWindow.instance:close()
    end
    local win = ISCDTuningWindow:new(0, 0, TUN_DEF_W, TUN_DEF_H)
    win:initialise()
    win:instantiate()
    CD.UI.applyOpenGeometry(win, "dogtune", TUN_DEF_W, TUN_DEF_H)
    win:addToUIManager()
    ISCDTuningWindow.instance = win
    CD.request("tuningget", nil, {})
end
