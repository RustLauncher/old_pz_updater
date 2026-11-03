CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

ISCDSettingsView = ISPanel:derive("ISCDSettingsView")

local SPAD = 24
local SGAP = 16
local SBTN_H = 38
local KROW_H = 46
local STEP_W = 38
local STEP_H = 26
local CATMUTE_W = 92
local FONT = UIFont.Medium

local CAT_LABEL = { bark = "IGUI_PD_SoundCatBark", fx = "IGUI_PD_SoundCatFx", ambient = "IGUI_PD_SoundCatAmbient" }

local LBL = { r = 0.78, g = 0.80, b = 0.78 }
local DIV = { r = 1.0, g = 1.0, b = 1.0, a = 0.14 }

local function fh(font) return getTextManager():getFontHeight(font) end
local function strW(font, s) return getTextManager():MeasureStringX(font, s) end

function ISCDSettingsView:new(x, y, w, h)
    local o = ISPanel.new(self, x, y, w, h)
    o.background = false
    o.capturingId = nil
    return o
end

function ISCDSettingsView:instantiate() CD.UI.viewInstantiate(self) end
function ISCDSettingsView:onMouseWheel(del) return CD.UI.viewMouseWheel(self, del) end

function ISCDSettingsView:mkBtn(w, h, text, onclick)
    local b = ISButton:new(0, 0, w, h, text, self, onclick)
    b:initialise()
    b:instantiate()
    b:setDisplayBackground(true)
    self:addChild(b)
    return b
end

function ISCDSettingsView:doLayout()
    local L = {}
    local sm = fh(FONT)
    local y = SPAD

    L.displayLabelY = y
    y = y + sm + 6
    L.textsBtnY = y
    y = y + SBTN_H + SGAP
    L.moodlesBtnY = y
    y = y + SBTN_H + SGAP
    L.namesBtnY = y
    y = y + SBTN_H + SGAP
    L.div0 = y
    y = y + 1 + SGAP

    L.soundLabelY = y
    y = y + sm + 6
    L.volRowY = y
    y = y + sm + 4
    L.trackY = y
    L.trackH = 18
    y = y + L.trackH + SGAP
    L.muteY = y
    y = y + SBTN_H + SGAP

    L.catHeadY = {}
    L.catTrackY = {}
    for _, c in ipairs(CD.SOUND_CATEGORIES) do
        L.catHeadY[c] = y
        y = y + STEP_H + 4
        L.catTrackY[c] = y
        y = y + L.trackH + SGAP
    end

    L.div1 = y
    y = y + 1 + SGAP

    L.feedLabelY = y
    y = y + sm + 6
    L.feedRowY = y
    y = y + sm + 4
    L.feedTrackY = y
    y = y + L.trackH + SGAP

    L.loiterLabelY = y
    y = y + sm + 6
    L.loiterRowY = y
    y = y + sm + 4
    L.loiterTrackY = y
    y = y + L.trackH + SGAP

    L.div2 = y
    y = y + 1 + SGAP

    L.keysLabelY = y
    y = y + sm + 6
    L.joypadNoteY = y
    y = y + sm + 6
    L.rowsY = y
    y = y + KROW_H * #CD.Settings.ACTIONS + 4

    L.noticeY = y
    y = y + sm

    y = y + SPAD
    L.contentH = y
    self.L = L
    return L
end

function ISCDSettingsView:layout()
    local cw = CD.UI.viewContentW(self)
    local L = self:doLayout()

    local trackX = SPAD + STEP_W + 4
    local trackW = cw - SPAD * 2 - (STEP_W + 4) * 2
    if trackW < 20 then
        trackW = 20
    end
    self.trackX = trackX
    self.trackW = trackW

    self.textsBtn:setX(SPAD)
    self.textsBtn:setY(L.textsBtnY)
    self.textsBtn:setWidth(cw - SPAD * 2)
    self.moodlesBtn:setX(SPAD)
    self.moodlesBtn:setY(L.moodlesBtnY)
    self.moodlesBtn:setWidth(cw - SPAD * 2)
    self.namesBtn:setX(SPAD)
    self.namesBtn:setY(L.namesBtnY)
    self.namesBtn:setWidth(cw - SPAD * 2)

    self.volMinusBtn:setX(SPAD)
    self.volMinusBtn:setY(L.trackY - 4)
    self.volPlusBtn:setX(cw - SPAD - STEP_W)
    self.volPlusBtn:setY(L.trackY - 4)
    self.volTrackBtn:setX(trackX)
    self.volTrackBtn:setY(L.trackY)
    self.volTrackBtn:setWidth(trackW)

    self.muteBtn:setX(SPAD)
    self.muteBtn:setY(L.muteY)
    self.muteBtn:setWidth(cw - SPAD * 2)

    for _, c in ipairs(CD.SOUND_CATEGORIES) do
        local cb = self.catBtns[c]
        local hy = L.catHeadY[c]
        local ty2 = L.catTrackY[c]
        cb.mute:setX(cw - SPAD - CATMUTE_W)
        cb.mute:setY(hy)
        cb.minus:setX(SPAD)
        cb.minus:setY(ty2 - 4)
        cb.plus:setX(cw - SPAD - STEP_W)
        cb.plus:setY(ty2 - 4)
        cb.track:setX(trackX)
        cb.track:setY(ty2)
        cb.track:setWidth(trackW)
    end

    self.feedMinusBtn:setX(SPAD)
    self.feedMinusBtn:setY(L.feedTrackY - 4)
    self.feedPlusBtn:setX(cw - SPAD - STEP_W)
    self.feedPlusBtn:setY(L.feedTrackY - 4)
    self.feedTrackBtn:setX(trackX)
    self.feedTrackBtn:setY(L.feedTrackY)
    self.feedTrackBtn:setWidth(trackW)

    self.loiterMinusBtn:setX(SPAD)
    self.loiterMinusBtn:setY(L.loiterTrackY - 4)
    self.loiterPlusBtn:setX(cw - SPAD - STEP_W)
    self.loiterPlusBtn:setY(L.loiterTrackY - 4)
    self.loiterTrackBtn:setX(trackX)
    self.loiterTrackBtn:setY(L.loiterTrackY)
    self.loiterTrackBtn:setWidth(trackW)

    local clearW, rebindW = 76, 96
    local clearX = cw - SPAD - clearW
    local rebindX = clearX - 6 - rebindW
    self.rebindX = rebindX
    for i = 1, #CD.Settings.ACTIONS do
        local ry = L.rowsY + (i - 1) * KROW_H
        local by = ry + math.floor((KROW_H - SBTN_H) / 2)
        local row = self.rowBtns[i]
        row.rebind:setX(rebindX)
        row.rebind:setY(by)
        row.clear:setX(clearX)
        row.clear:setY(by)
    end

    self:setScrollHeight(L.contentH)
end

function ISCDSettingsView:createChildren()
    self:doLayout()

    self.textsBtn = self:mkBtn(10, SBTN_H, "", ISCDSettingsView.onToggleTexts)
    self.moodlesBtn = self:mkBtn(10, SBTN_H, "", ISCDSettingsView.onToggleMoodles)
    self.namesBtn = self:mkBtn(10, SBTN_H, "", ISCDSettingsView.onToggleNames)

    self.volMinusBtn = self:mkBtn(STEP_W, STEP_H, "-", ISCDSettingsView.onVolMinus)
    self.volPlusBtn  = self:mkBtn(STEP_W, STEP_H, "+", ISCDSettingsView.onVolPlus)
    self.volTrackBtn = self:mkBtn(10, 18, "", ISCDSettingsView.onVolTrack)
    self.volTrackBtn:setDisplayBackground(false)

    self.muteBtn = self:mkBtn(10, SBTN_H, "", ISCDSettingsView.onMute)

    self.catBtns = {}
    for _, c in ipairs(CD.SOUND_CATEGORIES) do
        local minus = self:mkBtn(STEP_W, STEP_H, "-", ISCDSettingsView.onCatMinus)
        local plus  = self:mkBtn(STEP_W, STEP_H, "+", ISCDSettingsView.onCatPlus)
        local track = self:mkBtn(10, 18, "", ISCDSettingsView.onCatTrack)
        track:setDisplayBackground(false)
        local mute  = self:mkBtn(CATMUTE_W, STEP_H, "", ISCDSettingsView.onCatMute)
        minus.cdCat = c
        plus.cdCat = c
        track.cdCat = c
        mute.cdCat = c
        self.catBtns[c] = { minus = minus, plus = plus, track = track, mute = mute }
    end

    self.feedMinusBtn = self:mkBtn(STEP_W, STEP_H, "-", ISCDSettingsView.onFeedMinus)
    self.feedPlusBtn  = self:mkBtn(STEP_W, STEP_H, "+", ISCDSettingsView.onFeedPlus)
    self.feedTrackBtn = self:mkBtn(10, 18, "", ISCDSettingsView.onFeedTrack)
    self.feedTrackBtn:setDisplayBackground(false)

    self.loiterMinusBtn = self:mkBtn(STEP_W, STEP_H, "-", ISCDSettingsView.onLoiterMinus)
    self.loiterPlusBtn  = self:mkBtn(STEP_W, STEP_H, "+", ISCDSettingsView.onLoiterPlus)
    self.loiterTrackBtn = self:mkBtn(10, 18, "", ISCDSettingsView.onLoiterTrack)
    self.loiterTrackBtn:setDisplayBackground(false)

    self.rowBtns = {}
    for i, spec in ipairs(CD.Settings.ACTIONS) do
        local rb = self:mkBtn(96, SBTN_H, getText("IGUI_PD_KeyRebind"), ISCDSettingsView.onRebind)
        rb.cdActionId = spec.id
        local cb = self:mkBtn(76, SBTN_H, getText("IGUI_PD_KeyClear"), ISCDSettingsView.onClear)
        cb.cdActionId = spec.id
        self.rowBtns[i] = { rebind = rb, clear = cb }
    end

    self:layout()
end

function ISCDSettingsView:prerender()
    if self.textsBtn then
        self.textsBtn.title = getText(CD.Settings.getShowTexts() and "IGUI_PD_ShowTextsOn" or "IGUI_PD_ShowTextsOff")
    end
    if self.moodlesBtn then
        self.moodlesBtn.title = getText(CD.Settings.getShowMoodles() and "IGUI_PD_ShowMoodlesOn" or "IGUI_PD_ShowMoodlesOff")
    end
    if self.namesBtn then
        self.namesBtn.title = getText(CD.Settings.getShowNames() and "IGUI_PD_ShowNamesOn" or "IGUI_PD_ShowNamesOff")
    end
    if self.muteBtn then
        self.muteBtn.title = getText(CD.Settings.isMuted() and "IGUI_PD_MuteOn" or "IGUI_PD_MuteOff")
    end
    if self.catBtns then
        for _, c in ipairs(CD.SOUND_CATEGORIES) do
            local b = self.catBtns[c].mute
            if b then
                b.title = getText(CD.Settings.isCatMuted(c) and "IGUI_PD_MuteOn" or "IGUI_PD_MuteOff")
            end
        end
    end
    CD.UI.viewBeginRender(self)
end

function ISCDSettingsView:render()
    self:drawContent()
    CD.UI.viewEndRender(self)
end

function ISCDSettingsView:drawContent()
    local L = self.L
    if not L then return end
    local cw = CD.UI.viewContentW(self)
    local sm = FONT
    local smH = fh(FONT)

    self:drawText(getText("IGUI_PD_DisplayLabel"), SPAD, L.displayLabelY, LBL.r, LBL.g, LBL.b, 1, sm)
    self:drawRect(SPAD, L.div0, cw - SPAD * 2, 1, DIV.a, DIV.r, DIV.g, DIV.b)

    self:drawText(getText("IGUI_PD_SoundLabel"), SPAD, L.soundLabelY, LBL.r, LBL.g, LBL.b, 1, sm)
    local vol = CD.Settings.data.volume or 1.0
    self:drawText(getText("IGUI_PD_VolumeLabel"), SPAD, L.volRowY, 1, 1, 1, 1, sm)
    local pct = tostring(math.floor(vol * 100 + 0.5)) .. "%"
    self:drawText(pct, cw - SPAD - strW(sm, pct), L.volRowY, 1, 1, 1, 1, sm)

    local tx, tw, ty, th = self.trackX, self.trackW, L.trackY, L.trackH
    self:drawRect(tx, ty, tw, th, 0.85, 0.10, 0.10, 0.10)
    if not CD.Settings.isMuted() then
        self:drawRect(tx, ty, tw * vol, th, 0.9, 0.45, 0.66, 0.40)
    end
    self:drawRectBorder(tx, ty, tw, th, 0.6, 0.5, 0.5, 0.5)

    for _, c in ipairs(CD.SOUND_CATEGORIES) do
        local hy = L.catHeadY[c]
        local hty = hy + math.floor((STEP_H - smH) / 2)
        self:drawText(getText(CAT_LABEL[c]), SPAD, hty, 1, 1, 1, 1, sm)
        local cvol = CD.Settings.getCatVolume(c)
        local cpct = tostring(math.floor(cvol * 100 + 0.5)) .. "%"
        self:drawText(cpct, cw - SPAD - CATMUTE_W - 8 - strW(sm, cpct), hty, 0.80, 0.85, 0.70, 1, sm)

        local cty = L.catTrackY[c]
        self:drawRect(tx, cty, tw, th, 0.85, 0.10, 0.10, 0.10)
        if not (CD.Settings.isCatMuted(c) or CD.Settings.isMuted()) then
            self:drawRect(tx, cty, tw * cvol, th, 0.9, 0.45, 0.66, 0.40)
        end
        self:drawRectBorder(tx, cty, tw, th, 0.6, 0.5, 0.5, 0.5)
    end

    self:drawRect(SPAD, L.div1, cw - SPAD * 2, 1, DIV.a, DIV.r, DIV.g, DIV.b)

    self:drawText(getText("IGUI_PD_AutoFeedLabel"), SPAD, L.feedLabelY, LBL.r, LBL.g, LBL.b, 1, sm)
    local trig = CD.Settings.getFeedTrigger(self.owner)
    self:drawText(getText("IGUI_PD_AutoFeedTrigger"), SPAD, L.feedRowY, 1, 1, 1, 1, sm)
    local fpct = tostring(math.floor(trig * 100 + 0.5)) .. "%"
    self:drawText(fpct, cw - SPAD - strW(sm, fpct), L.feedRowY, 1, 1, 1, 1, sm)
    local fx, fw, fy, fth = self.trackX, self.trackW, L.feedTrackY, L.trackH
    self:drawRect(fx, fy, fw, fth, 0.85, 0.10, 0.10, 0.10)
    local fratio = (trig - 0.1) / 0.9
    if fratio < 0 then fratio = 0 elseif fratio > 1 then fratio = 1 end
    self:drawRect(fx, fy, fw * fratio, fth, 0.9, 0.45, 0.66, 0.40)
    self:drawRectBorder(fx, fy, fw, fth, 0.6, 0.5, 0.5, 0.5)

    self:drawText(getText("IGUI_PD_LoiterLabel"), SPAD, L.loiterLabelY, LBL.r, LBL.g, LBL.b, 1, sm)
    local lrad = CD.Settings.getLoiterRadius(self.owner)
    self:drawText(getText("IGUI_PD_LoiterRadius"), SPAD, L.loiterRowY, 1, 1, 1, 1, sm)
    local ltxt = tostring(lrad)
    self:drawText(ltxt, cw - SPAD - strW(sm, ltxt), L.loiterRowY, 1, 1, 1, 1, sm)
    local lx, lw, ly, lth = self.trackX, self.trackW, L.loiterTrackY, L.trackH
    self:drawRect(lx, ly, lw, lth, 0.85, 0.10, 0.10, 0.10)
    local lspan = CD.LOITER_RADIUS_MAX - CD.LOITER_RADIUS_MIN
    local lratio = lspan > 0 and (lrad - CD.LOITER_RADIUS_MIN) / lspan or 0
    if lratio < 0 then lratio = 0 elseif lratio > 1 then lratio = 1 end
    self:drawRect(lx, ly, lw * lratio, lth, 0.9, 0.45, 0.66, 0.40)
    self:drawRectBorder(lx, ly, lw, lth, 0.6, 0.5, 0.5, 0.5)

    self:drawRect(SPAD, L.div2, cw - SPAD * 2, 1, DIV.a, DIV.r, DIV.g, DIV.b)

    self:drawText(getText("IGUI_PD_KeybindsLabel"), SPAD, L.keysLabelY, LBL.r, LBL.g, LBL.b, 1, sm)
    self:drawText(getText("IGUI_PD_KeyJoypadNote"), SPAD, L.joypadNoteY, 0.62, 0.62, 0.62, 1, sm)
    for i, spec in ipairs(CD.Settings.ACTIONS) do
        local ry = L.rowsY + (i - 1) * KROW_H
        local ty2 = ry + math.floor((KROW_H - smH) / 2)
        self:drawText(getText(spec.label), SPAD, ty2, 1, 1, 1, 1, sm)
        local txt
        if self.capturingId == spec.id then
            txt = getText("IGUI_PD_KeyPressPrompt")
        else
            txt = CD.Settings.keyName(CD.Settings.getKey(spec.id))
        end
        local kx = (self.rebindX or (cw - 190)) - 12 - strW(sm, txt)
        self:drawText(txt, kx, ty2, 0.80, 0.85, 0.70, 1, sm)
    end

    if self.notice then
        self:drawText(self.notice, SPAD, L.noticeY, 0.90, 0.52, 0.42, 1, sm)
    end
end

function ISCDSettingsView.onVolMinus() CD.Settings.setVolume((CD.Settings.data.volume or 1.0) - 0.05) end
function ISCDSettingsView.onVolPlus() CD.Settings.setVolume((CD.Settings.data.volume or 1.0) + 0.05) end

function ISCDSettingsView.onVolTrack(_, button)
    local w = button:getWidth()
    if w > 0 then
        CD.Settings.setVolume(button:getMouseX() / w)
    end
end

function ISCDSettingsView.onMute()
    CD.Settings.setMute(not CD.Settings.isMuted())
end

function ISCDSettingsView.onCatMinus(_, button)
    local c = button.cdCat
    CD.Settings.setCatVolume(c, CD.Settings.getCatVolume(c) - 0.05)
end

function ISCDSettingsView.onCatPlus(_, button)
    local c = button.cdCat
    CD.Settings.setCatVolume(c, CD.Settings.getCatVolume(c) + 0.05)
end

function ISCDSettingsView.onCatTrack(_, button)
    local w = button:getWidth()
    if w > 0 then
        CD.Settings.setCatVolume(button.cdCat, button:getMouseX() / w)
    end
end

function ISCDSettingsView.onCatMute(_, button)
    local c = button.cdCat
    CD.Settings.setCatMute(c, not CD.Settings.isCatMuted(c))
end

function ISCDSettingsView.onToggleTexts()
    CD.Settings.setShowTexts(not CD.Settings.getShowTexts())
end

function ISCDSettingsView.onToggleMoodles()
    CD.Settings.setShowMoodles(not CD.Settings.getShowMoodles())
end

function ISCDSettingsView.onToggleNames()
    CD.Settings.setShowNames(not CD.Settings.getShowNames())
end

function ISCDSettingsView.onFeedMinus(view) CD.Settings.setFeedTrigger(CD.Settings.getFeedTrigger(view.owner) - 0.05, view.owner) end
function ISCDSettingsView.onFeedPlus(view)  CD.Settings.setFeedTrigger(CD.Settings.getFeedTrigger(view.owner) + 0.05, view.owner) end

function ISCDSettingsView.onFeedTrack(view, button)
    local w = button:getWidth()
    if w > 0 then
        CD.Settings.setFeedTrigger(0.1 + (button:getMouseX() / w) * 0.9, view.owner)
    end
end

function ISCDSettingsView.onLoiterMinus(view) CD.Settings.setLoiterRadius(CD.Settings.getLoiterRadius(view.owner) - 1, view.owner) end
function ISCDSettingsView.onLoiterPlus(view)  CD.Settings.setLoiterRadius(CD.Settings.getLoiterRadius(view.owner) + 1, view.owner) end

function ISCDSettingsView.onLoiterTrack(view, button)
    local w = button:getWidth()
    if w > 0 then
        local span = CD.LOITER_RADIUS_MAX - CD.LOITER_RADIUS_MIN
        CD.Settings.setLoiterRadius(CD.LOITER_RADIUS_MIN + (button:getMouseX() / w) * span, view.owner)
    end
end

function ISCDSettingsView.onRebind(view, button)
    local id = button.cdActionId
    view.capturingId = id
    view.notice = nil
    CD.Keybinds.beginCapture(function(code)
        if view.capturingId ~= id then return end
        view.capturingId = nil
        if code and code ~= 0 then
            local conflicts = CD.Keybinds.findConflicts(code, id)
            CD.Settings.setKey(id, code)
            if #conflicts > 0 then
                view.notice = getText("IGUI_PD_KeyConflict", CD.Settings.keyName(code), table.concat(conflicts, ", "))
            end
        end
    end)
end

function ISCDSettingsView.onClear(view, button)
    CD.Settings.setKey(button.cdActionId, 0)
    if view.capturingId == button.cdActionId then
        view.capturingId = nil
        CD.Keybinds.captureCb = nil
    end
end

ISCDSettingsWindow = {}

function ISCDSettingsWindow.Open()
    CD.openDogWindowTab(getPlayer(), "settings")
end
