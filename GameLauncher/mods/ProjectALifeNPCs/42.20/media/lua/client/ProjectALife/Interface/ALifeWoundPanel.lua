require "ISUI/ISPanel"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISUI3DModel"
require "ProjectALife/Core/ALifeText"
require "ProjectALife/Shells/ALifeWounds"
require "ProjectALife/Interface/ALifeWoundPanelData"
require "ProjectALife/Interface/ALifeMenuPrefs"

ProjectALife = ProjectALife or {}

local Data = ProjectALife.WoundPanelData
local Text = ProjectALife.Text

local Panel = {
    instance = nil, pollMs = 600, tickMs = 100, staleMs = 2500, closeTiles = 10, reach = 3, treatTiles = 3.2,
    messageMs = 5000, lostLimit = 4, faultLimit = 3, textures = {}, faults = 0,
}
ProjectALife.WoundPanel = Panel

local Window = ISCollapsableWindow:derive("ALifeWoundWindow")
local Body = ISPanel:derive("ALifeWoundBody")
local List = ISScrollingListBox:derive("ALifeWoundList")
Panel.Window, Panel.Body, Panel.List = Window, Body, List

function Panel.wanted()
    if Panel.broken == true then return false end
    local prefs = ProjectALife.MenuPrefs
    if prefs ~= nil and type(prefs.woundPanelOn) == "function" then return prefs.woundPanelOn() == true end
    return true
end

function Panel.fault(window, err)
    if Panel.strict == true then error(err, 0) end
    Panel.faults = Panel.faults + 1
    Panel.lastFault = tostring(err)
    if Panel.faults <= 3 then print("[A-Life] wound panel fault: " .. Panel.lastFault) end
    if window == nil then return end
    window.faults = (window.faults or 0) + 1
    if window.faults < Panel.faultLimit or window.broken == true then return end
    window.broken = true
    Panel.broken = true
    local uid, menu = window.uid, ProjectALife.WoundsMenu
    local player = getSpecificPlayer(window.playerNum)
    window:close()
    if menu ~= nil and type(menu.send) == "function" and player ~= nil then menu.send(player, uid, false) end
end

function Panel.nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return 0
end

function Panel.measure(text)
    return getTextManager():MeasureStringX(UIFont.Small, text)
end

function Panel.texture(name)
    local hit = Panel.textures[name]
    if hit ~= nil then
        if hit == false then return nil end
        return hit
    end
    local found = nil
    if type(getTexture) == "function" then
        found = getTexture(name)
        if found == nil then found = getTexture(name .. ".png") end
    end
    if found == nil then
        Panel.textures[name] = false
        return nil
    end
    Panel.textures[name] = found
    return found
end

function Panel.dispatch(player, args)
    if type(isClient) == "function" and isClient() then
        if type(sendClientCommand) ~= "function" then return false end
        sendClientCommand(player, "ProjectALife", "npcWounds", args)
        return true
    end
    local health = ProjectALife.Health
    if health == nil or type(health.onClientCommand) ~= "function" then return false end
    health.onClientCommand("ProjectALife", "npcWounds", player, args)
    return true
end

function Panel.isFemale(body)
    if body == nil or type(body.isFemale) ~= "function" then return false end
    return body:isFemale() == true
end

function Panel.sex(window)
    if window.female == true then return "female" end
    return "male"
end

function Panel.join(first, second)
    local a = type(first) == "string" and first or ""
    local b = type(second) == "string" and second or ""
    if a ~= "" and b ~= "" then return a .. "  /  " .. b end
    if a ~= "" then return a end
    return b
end

function Panel.revealOn(player)
    local prefs = ProjectALife.MenuPrefs
    if prefs ~= nil and type(prefs.allowed) == "function" then return prefs.allowed(player) == true end
    return false
end

function Panel.identity(uid, player)
    local out = {}
    local menu = ProjectALife.TalkMenu
    if menu == nil or type(menu.recordFor) ~= "function" or type(menu.describe) ~= "function" then return out end
    local found, record = pcall(menu.recordFor, uid)
    if not found or type(record) ~= "table" then return out end
    local key = nil
    local speech = ProjectALife.Speech
    if speech ~= nil and type(speech.playerKey) == "function" then
        local okKey, value = pcall(speech.playerKey, player)
        if okKey then key = value end
    end
    local done, _, name, faction, role, known = pcall(menu.describe, record, key, 1)
    if not done then return out end
    local masked = known ~= true
    if not masked and type(menu.mystery) == "function" then masked = menu.mystery() == true end
    if masked then
        if known == true then out.name = name end
        return out
    end
    out.name, out.faction, out.role = name, faction, role
    local catalog = ProjectALife.Catalog
    if catalog ~= nil and type(catalog.npc) == "function" then
        local okProfile, profile = pcall(catalog.npc, record.profileId)
        if okProfile and type(profile) == "table" and type(profile.general) == "table" then out.rank = profile.general.rank end
    end
    return out
end

function Panel.bodyState(body)
    if body == nil then return nil end
    local square = nil
    if type(body.getCurrentSquare) == "function" then square = body:getCurrentSquare() end
    if square == nil and type(body.getSquare) == "function" then square = body:getSquare() end
    if square == nil then return nil end
    local dead = false
    if type(body.isDead) == "function" then dead = body:isDead() == true end
    return { x = body:getX(), y = body:getY(), z = body:getZ(), dead = dead }
end

function Panel.snapshotFrom(payload)
    local state = nil
    if type(payload.state) == "string" then state = payload.state end
    return { injuries = ProjectALife.Wounds.copy(payload.injuries), hours = tonumber(payload.hours), hp = tonumber(payload.hp),
        downed = payload.downed == true, state = state, dead = false, known = true }
end

function Panel.blank()
    return { injuries = {}, hours = nil, hp = nil, downed = false, state = nil, dead = false, known = true }
end

function Panel.modData(body)
    if type(body.hasModData) == "function" and body:hasModData() ~= true then return nil end
    if type(body.getModData) ~= "function" then return nil end
    return body:getModData()
end

function Panel.corpseUid(body)
    if body == nil then return nil end
    local ok, data = pcall(Panel.modData, body)
    if not ok or type(data) ~= "table" then return nil end
    local uid = data.ProjectALifeCorpseOf
    if type(uid) ~= "string" or uid == "" then return nil end
    return uid
end

function Panel.corpseSnapshot(body)
    local snapshot = { injuries = {}, hours = Data.worldHours(), hp = 0, downed = false, state = nil, dead = true, known = false }
    local ok, data = pcall(Panel.modData, body)
    if ok and type(data) == "table" and type(data.ProjectALifeInjuries) == "table" then
        snapshot.injuries = ProjectALife.Wounds.copy(data.ProjectALifeInjuries)
        snapshot.known = true
    end
    return snapshot
end

function Panel.corpseNear(square)
    if square == nil or type(getCell) ~= "function" then return nil end
    local cell = getCell()
    local best, bestUid, bestDistance = nil, nil, 2.5
    local x, y, z = square:getX(), square:getY(), square:getZ()
    for dx = -1, 1 do
        for dy = -1, 1 do
            local around = cell:getGridSquare(x + dx, y + dy, z)
            local bodies = nil
            if around ~= nil and type(around.getDeadBodys) == "function" then bodies = around:getDeadBodys() end
            local count = 0
            if bodies ~= nil then count = bodies:size() end
            for index = 0, count - 1 do
                local body = bodies:get(index)
                local uid = Panel.corpseUid(body)
                if uid ~= nil then
                    local distance = math.sqrt((body:getX() - x - 0.5) ^ 2 + (body:getY() - y - 0.5) ^ 2)
                    if distance < bestDistance then best, bestUid, bestDistance = body, uid, distance end
                end
            end
        end
    end
    return best, bestUid
end

function Panel.checkCorpse(playerNum, uid, body)
    Panel.open(playerNum, uid, body, { corpse = true, snapshot = Panel.corpseSnapshot(body) })
end

function Panel.fillCorpse(playerNum, context, square, player)
    if Panel.wanted() ~= true or square == nil or player == nil then return false end
    local body, uid = Panel.corpseNear(square)
    if body == nil then return false end
    if math.abs(body:getZ() - player:getZ()) > 0.5
            or (body:getX() - player:getX()) ^ 2 + (body:getY() - player:getY()) ^ 2 > Panel.reach ^ 2 then
        return false
    end
    context:addOption(Text.ui("Check wounds"), playerNum, Panel.checkCorpse, uid, body)
    return true
end

function Panel.near(window, player)
    if window.lastX == nil then return false end
    local dx, dy = window.lastX - player:getX(), window.lastY - player:getY()
    return dx * dx + dy * dy <= Panel.treatTiles * Panel.treatTiles and math.abs(window.lastZ - player:getZ()) < 0.6
end

function Panel.facts(window, player)
    local snapshot = window.snapshot
    local inventory = player:getInventory()
    local kits, splint = {}, false
    if inventory ~= nil then
        for _, itemType in ipairs(Data.dressings) do
            local item = inventory:getFirstTypeRecurse(itemType)
            if item ~= nil then
                local name = itemType
                if type(item.getName) == "function" then name = item:getName() end
                kits[#kits + 1] = { item = itemType, name = name, object = item }
            end
        end
        splint = inventory:getFirstTypeRecurse(Data.splintItem) ~= nil
    end
    local aid = ProjectALife.InjuryMenu
    local medical, medicalKit = false, false
    if aid ~= nil and type(aid.available) == "function" and aid.available() == true then
        medical = true
        medicalKit = type(aid.hasKit) == "function" and aid.hasKit(player) == true
    end
    return { injuries = snapshot.injuries, downed = snapshot.downed, state = snapshot.state, dead = window.dead == true,
        kits = kits, splint = splint, medical = medical, medicalKit = medicalKit, near = Panel.near(window, player) }
end

function Panel.reasonTip(option, reason)
    local text = Data.reasonText(reason)
    local pool = ISInventoryPaneContextMenu
    if pool == nil or type(pool.addToolTip) ~= "function" then return end
    local tip = pool.addToolTip()
    if tip == nil then return end
    tip.description = text
    option.toolTip = tip
end

function Panel.addEntry(window, context, entry)
    if entry.id == "bandage" and entry.enabled then
        local option = context:addOption(entry.label, nil)
        local sub = context:getNew(context)
        context:addSubMenu(option, sub)
        for _, kit in ipairs(entry.kits) do
            local row = sub:addOption(kit.name, window, Window.dress, kit.item)
            if kit.object ~= nil then row.itemForTexture = kit.object end
        end
        return
    end
    local option = nil
    if entry.id == "splint" then
        option = context:addOption(entry.label, window, Window.splint)
    elseif entry.id == "medical" then
        option = context:addOption(entry.label, window, Window.medical)
    else
        option = context:addOption(entry.label, window, Window.nothing)
    end
    if not entry.enabled then
        option.notAvailable = true
        Panel.reasonTip(option, entry.reason)
    end
end

function Panel.makePortrait(window)
    local lay = window.lay
    local portrait = ISUI3DModel:new(lay.pad, lay.headTop, lay.portraitWidth, lay.portraitHeight)
    portrait:initialise()
    window:addChild(portrait)
    window.portrait = portrait
    portrait:setCharacter(window.shell)
    portrait:setIsometric(false)
    portrait:setDirection(IsoDirections.S)
    portrait:setDoRandomExtAnimations(false)
    portrait:setState("idle")
    portrait:setZoom(10)
    portrait:setYOffset(-0.75)
    portrait.prerender = Panel.portraitPrerender
end

function Panel.portraitPrerender(model)
    model.javaObject:setAnimate(false)
end

function Panel.build(playerNum, uid, body, options)
    if type(ISCollapsableWindow) ~= "table" or type(uid) ~= "string" or uid == "" or body == nil then return nil end
    local player = getSpecificPlayer(playerNum)
    if player == nil then return nil end
    options = type(options) == "table" and options or {}
    if Panel.instance ~= nil then Panel.instance:close() end
    local core = getCore()
    local manager = getTextManager()
    local fh = manager:getFontHeight(UIFont.Small)
    local mh = manager:getFontHeight(UIFont.Medium)
    local lay = Data.layout(ISCollapsableWindow.TitleBarHeight(), fh, mh)
    local window = Window:new((core:getScreenWidth() - lay.width) / 2, (core:getScreenHeight() - lay.height) / 2,
        lay.width, lay.height)
    window.lay, window.fh, window.mh = lay, fh, mh
    window.uid, window.playerNum, window.shell = uid, playerNum, body
    window.corpse = options.corpse == true
    window.dead = window.corpse
    window.female = Panel.isFemale(body)
    window.identity = Panel.identity(uid, player)
    window.snapshot = options.snapshot or Panel.blank()
    window.loaded = window.corpse
    window.nextPollAt = 0
    local state = Panel.bodyState(body)
    if state ~= nil then window.lastX, window.lastY, window.lastZ = state.x, state.y, state.z end
    window:initialise()
    window:addToUIManager()
    window:bringToTop()
    Panel.instance = window
    if not window.corpse then window:poll(Panel.nowMs()) end
    return window
end

function Panel.open(playerNum, uid, body, options)
    if Panel.wanted() ~= true then return false end
    local ok, window = pcall(Panel.build, playerNum, uid, body, options)
    if ok and window ~= nil then return true end
    if not ok then
        if Panel.instance ~= nil then pcall(Panel.instance.close, Panel.instance) end
        Panel.fault(nil, window)
    end
    return false
end

function Panel.take(payload)
    local window = Panel.instance
    if window == nil or type(payload) ~= "table" then return false end
    if tostring(payload.uid or "") ~= window.uid then return false end
    local ok, err = pcall(window.onReply, window, payload)
    if not ok then Panel.fault(window, err) end
    return true
end

function Window:shownName()
    local identity = self.identity
    if type(identity) == "table" and type(identity.name) == "string" and identity.name ~= "" then return identity.name end
    return Text.ui("Stranger")
end

function Window:createChildren()
    ISCollapsableWindow.createChildren(self)
    self:setResizable(false)
    self.backgroundColor = Data.color("windowBg")
    self.borderColor = Data.color("windowBorder")
    local lay = self.lay
    if self.corpse ~= true then
        local ok = pcall(Panel.makePortrait, self)
        if not ok and self.portrait ~= nil then
            self:removeChild(self.portrait)
            self.portrait = nil
        end
    end
    self.body = Body:new(self, lay.bodyX, lay.bodyY)
    self.body:initialise()
    self:addChild(self.body)
    local list = List:new(self, lay.listX, lay.listY, lay.listWidth, lay.listHeight)
    list:initialise()
    list:instantiate()
    list.backgroundColor = Data.color("listBg")
    list.borderColor = Data.color("listBorder")
    list.selectionColor = Data.color("select")
    list.mouseOverHighlightColor = Data.color("hover")
    list.drawBorder = true
    list.selected = 0
    list:setOnMouseDownFunction(self, Window.onRowPicked)
    self:addChild(list)
    self.list = list
    self:setTitle(Text.ui("Wound check - {name}", { name = self:shownName() }))
    self:rebuild()
end

function Window:activePart()
    if self.hoverPart ~= nil then return self.hoverPart end
    return self.selectedPart
end

function Window:setHover(part, from)
    if part == nil then
        if self.hoverFrom == from then
            self.hoverPart, self.hoverFrom = nil, nil
        end
        return
    end
    self.hoverPart, self.hoverFrom = part, from
end

function Window:select(part)
    if part == self.selectedPart then part = nil end
    self.selectedPart = part
    self:syncList()
end

function Window:syncList()
    local list = self.list
    if list == nil then return end
    list.selected = 0
    if self.selectedPart == nil then return end
    for index, item in ipairs(list.items) do
        if item.item.part == self.selectedPart then
            list.selected = index
            list:ensureVisible(index)
            return
        end
    end
end

function Window:onRowPicked(row)
    if type(row) == "table" then self:select(row.part) end
end

function Window:flash(text, tone)
    self.message = { text = text, tone = tone or "plain", untilMs = Panel.nowMs() + Panel.messageMs }
end

function Window:fillList()
    local list = self.list
    if list == nil then return end
    list:clear()
    local fh = self.fh
    local width = self.lay.listWidth - 34
    for _, row in ipairs(self.rows) do
        local lines = {}
        for _, line in ipairs(row.lines) do
            lines[#lines + 1] = { text = Data.fit(line.text, width, Panel.measure), tone = line.tone }
        end
        local item = list:addItem(row.title, { part = row.part, title = row.title, lines = lines, rank = row.rank })
        item.height = (#lines + 1) * fh + 8
    end
    self:syncList()
end

function Window:rebuild()
    local snapshot = self.snapshot
    local hours = snapshot.hours or Data.worldHours()
    self.hours = hours
    self.rows = Data.rows(snapshot.injuries, hours, snapshot.dead)
    self.placed = Data.place(snapshot.injuries, self.female)
    self.ranks = Data.ranks(snapshot.injuries, hours, snapshot.dead)
    self.statusWord = Data.statusWord(snapshot.hp, snapshot.dead)
    self.bleeding = snapshot.dead ~= true and (snapshot.downed == true or Data.bleedingNow(snapshot.injuries, hours))
    self.stateText, self.stateTone = Data.stateLine(snapshot)
    self:fillList()
end

function Window:apply(snapshot)
    if self.dead == true then snapshot.dead = true end
    local signature = Data.signature(snapshot, snapshot.hours or Data.worldHours())
    self.snapshot = snapshot
    if signature == self.signature then return end
    self.signature = signature
    self:rebuild()
end

function Window:markDead()
    if self.dead == true then return end
    self.dead = true
    self.snapshot.dead = true
    self.snapshot.hp = 0
    self.signature = nil
    self:apply(self.snapshot)
    self:flash(Text.ui("They died."), "bad")
end

function Window:lostReason()
    local player = getSpecificPlayer(self.playerNum)
    if player == nil or player:isDead() then return "player" end
    local ok, state = pcall(Panel.bodyState, self.shell)
    if ok and state ~= nil then
        if state.dead and self.dead ~= true then self:markDead() end
        self.lastX, self.lastY, self.lastZ = state.x, state.y, state.z
    elseif self.dead ~= true then
        return "gone"
    end
    if self.lastX == nil then return "gone" end
    local dx, dy = self.lastX - player:getX(), self.lastY - player:getY()
    if dx * dx + dy * dy > Panel.closeTiles * Panel.closeTiles or math.abs(self.lastZ - player:getZ()) > 1.5 then
        return "far"
    end
    return nil
end

function Window:finish(reason)
    local text = nil
    if reason == "far" then
        text = Text.ui("They are too far away. Wound check closed.")
    elseif reason == "gone" then
        text = Text.ui("They are no longer here. Wound check closed.")
    end
    local menu = ProjectALife.WoundsMenu
    if text ~= nil and menu ~= nil and type(menu.say) == "function" then
        menu.say(getSpecificPlayer(self.playerNum), text, false)
    end
    self:close()
end

function Window:poll(now)
    self.nextPollAt = now + Panel.pollMs
    if self.awaitingAt ~= nil and now - self.awaitingAt < Panel.staleMs then return end
    local player = getSpecificPlayer(self.playerNum)
    if player == nil then return end
    self.awaitingAt = now
    if not Panel.dispatch(player, { uid = self.uid, view = true }) then self.awaitingAt = nil end
end

function Window:update()
    ISCollapsableWindow.update(self)
    if not self:isVisible() or self.broken == true then return end
    local ok, err = pcall(self.tick, self)
    if not ok then Panel.fault(self, err) end
end

function Window:tick()
    local now = Panel.nowMs()
    if now < (self.nextTickAt or 0) then return end
    self.nextTickAt = now + Panel.tickMs
    local why = self:lostReason()
    if why ~= nil then
        self:finish(why)
        return
    end
    if self.dead == true or self.isCollapsed == true then return end
    if self.busyAt ~= nil and now - self.busyAt > Panel.staleMs then
        self.busyAt = nil
        self:flash(Text.ui("Give them a moment."), "warn")
    end
    if now >= (self.nextPollAt or 0) then self:poll(now) end
end

function Window:onReply(payload)
    local now = Panel.nowMs()
    local isView = payload.view == true
    self.awaitingAt = nil
    if payload.reason ~= nil then
        if isView then
            if payload.reason == "unavailable" then
                self.lost = (self.lost or 0) + 1
                if self.lost >= Panel.lostLimit and self.dead ~= true then self:finish("gone") end
            end
        else
            self.busyAt = nil
            self.nextPollAt = 0
            self:flash(Data.reasonText(payload.reason), "bad")
        end
        return
    end
    self.lost = 0
    self.loaded = true
    self:apply(Panel.snapshotFrom(payload))
    if not isView then
        self.busyAt = nil
        self.nextPollAt = 0
        if payload.treated == true then
            if self.pendingAction == "splint" then
                self:flash(Text.ui("Splinted."), "good")
            else
                self:flash(Text.ui("Dressed."), "good")
            end
        end
    end
    self.replyAt = now
end

function Window:act(kind, args)
    local player = getSpecificPlayer(self.playerNum)
    if player == nil or self.dead == true then return end
    self.pendingAction, self.busyAt = kind, Panel.nowMs()
    if not Panel.dispatch(player, args) then self.busyAt = nil end
end

function Window:dress(itemType)
    self:act("dress", { uid = self.uid, treat = true, kit = itemType })
end

function Window:splint()
    self:act("splint", { uid = self.uid, splint = true })
end

function Window:medical()
    local aid = ProjectALife.InjuryMenu
    if aid == nil or type(aid.aid) ~= "function" then return end
    aid.aid(self.playerNum, self.uid)
    self.nextPollAt = Panel.nowMs() + 400
end

function Window:nothing()
end

function Window:openMenu(part, x, y)
    if type(getMouseX) == "function" and type(getMouseY) == "function" then x, y = getMouseX(), getMouseY() end
    if part ~= nil and self.selectedPart ~= part then
        self.selectedPart = part
        self:syncList()
    end
    local player = getSpecificPlayer(self.playerNum)
    if player == nil or type(ISContextMenu) ~= "table" or type(ISContextMenu.get) ~= "function" then return false end
    if self.dead == true then
        self:flash(Data.reasonText("dead"), "bad")
        return false
    end
    local entries = Data.treatments(Panel.facts(self, player))
    local context = ISContextMenu.get(self.playerNum, x, y)
    for _, entry in ipairs(entries) do Panel.addEntry(self, context, entry) end
    return true
end

function Window:close()
    if Panel.instance == self then Panel.instance = nil end
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
end

function Window:drawVitals()
    local lay, bar, frame = self.lay, Data.bar, Data.frame
    local x, y = lay.barX, lay.bodyY
    self:drawRect(x, y, bar.width, bar.height, 1, 0.15, 0.15, 0.15)
    local hp = self.snapshot.hp
    if self.dead == true then hp = 0 end
    if hp == nil then hp = 100 end
    local length = math.max(0, math.min(bar.fillHeight, math.floor((100 - hp) * 2.56)))
    local back = Panel.texture("media/ui/BodyDamage/DamageBar_Vert")
    local fill = Panel.texture("media/ui/BodyDamage/DamageBar_Vert_Fill")
    if back ~= nil then self:drawTextureScaled(back, x + 1, y + 1, bar.fillWidth, bar.fillHeight, 1, 1, 1, 1) end
    if fill ~= nil and length < bar.fillHeight then
        self:drawTextureScaled(fill, x + 1, y + 1 + length, bar.fillWidth, bar.fillHeight - length, 1, 1, 1, 1)
    end
    local name = "media/ui/Heart_On"
    if self.dead == true then name = "media/ui/Heart_Off" end
    local heart = Panel.texture(name)
    if heart ~= nil then self:drawTexture(heart, x - 1, y + frame.height - heart:getHeight() - 2, 1, 1, 1, 1) end
end

function Window:drawHeader()
    local lay, fh, mh = self.lay, self.fh, self.mh
    local identity = self.identity or {}
    if self.portrait == nil then
        self:drawRect(lay.pad, lay.headTop, lay.portraitWidth, lay.portraitHeight, 1, 0.015, 0.02, 0.017)
        local icon = Panel.texture("media/ui/Moodle_Icon_Dead")
        if icon ~= nil then
            self:drawTexture(icon, lay.pad + (lay.portraitWidth - 32) / 2, lay.headTop + (lay.portraitHeight - 32) / 2, 1, 1, 1, 1)
        end
    end
    self:drawRectBorder(lay.pad, lay.headTop, lay.portraitWidth, lay.portraitHeight, 1, 0.2, 0.25, 0.2)
    local x = lay.pad + lay.portraitWidth + 12
    local y = lay.headTop + 2
    self:drawText(self:shownName(), x, y, 0.92, 0.94, 0.82, 1, UIFont.Medium)
    y = y + mh + 2
    local sub = Panel.join(identity.rank, identity.role)
    if sub ~= "" then
        self:drawText(sub, x, y, 0.58, 0.64, 0.56, 1, UIFont.Small)
        y = y + fh + 2
    end
    if type(identity.faction) == "string" and identity.faction ~= "" then
        self:drawText(identity.faction, x, y, 0.58, 0.64, 0.56, 1, UIFont.Small)
    end
end

function Window:drawOverall()
    local lay, fh = self.lay, self.fh
    local x, y = lay.textX, lay.bodyY
    self:drawText(Data.word("IGUI_health_Overall_Body_Status", "Overall Body Status"), x, y, 1, 1, 1, 1, UIFont.Small)
    y = y + fh
    local tint = Data.statusTint(self.snapshot.hp)
    if self.dead == true then tint = 1 end
    self:drawText(self.statusWord or "", x, y, 1, 1 - tint, 1 - tint, 1, UIFont.Small)
    y = y + fh
    local r, g, b = Data.tone(self.stateTone or "dim")
    local tx = x
    if self.bleeding == true then
        local drop = Panel.texture("media/ui/Moodle_Icon_Bleeding")
        if drop ~= nil then
            local width = math.floor(fh * 0.64 + 0.5)
            self:drawTextureScaled(drop, x, y, width, fh, 1, 1, 1, 1)
            tx = x + width + 4
        end
    end
    self:drawText(self.stateText or "", tx, y, r, g, b, 1, UIFont.Small)
end

function Window:prerender()
    ISCollapsableWindow.prerender(self)
    if self.isCollapsed == true or self.broken == true then return end
    local ok, err = pcall(self.paintBack, self)
    if not ok then Panel.fault(self, err) end
end

function Window:paintBack()
    self:drawHeader()
    self:drawVitals()
    self:drawOverall()
    self:drawText(Data.word("IGUI_health_RightClickTreatement", "Right click to show Treatment menu"), self.lay.pad,
        self.lay.bottomY, 1, 1, 1, 1, UIFont.Small)
end

function Window:render()
    ISCollapsableWindow.render(self)
    if self.isCollapsed == true or self.broken == true then return end
    local ok, err = pcall(self.paintFront, self)
    if not ok then Panel.fault(self, err) end
end

function Window:paintFront()
    local lay = self.lay
    local now = Panel.nowMs()
    local message = self.message
    if message ~= nil and now > message.untilMs then
        self.message = nil
        message = nil
    end
    if message ~= nil then
        local r, g, b = Data.tone(message.tone)
        self:drawText(message.text, lay.pad, lay.messageY, r, g, b, 1, UIFont.Small)
    elseif self.dead ~= true and self.lastX ~= nil then
        local player = getSpecificPlayer(self.playerNum)
        if player ~= nil and not Panel.near(self, player) then
            local r, g, b = Data.tone("warn")
            self:drawText(Text.ui("Move closer to treat them."), lay.pad, lay.messageY, r, g, b, 1, UIFont.Small)
        end
    end
    if self.list ~= nil and #self.rows == 0 then
        local note = nil
        if self.loaded ~= true then
            note = Text.ui("Checking their wounds...")
        elseif self.snapshot.known == false then
            note = Text.ui("Nothing was recorded about their wounds.")
        else
            note = Text.ui("No wounds you can see.")
        end
        local r, g, b = Data.tone("dim")
        self:drawText(note, lay.listX + 10, lay.listY + 10, r, g, b, 1, UIFont.Small)
    end
end

function Body:new(window, x, y)
    local o = ISPanel:new(x, y, Data.frame.width, Data.frame.height)
    setmetatable(o, self)
    self.__index = self
    o.window = window
    o.background = false
    return o
end

function Body:prerender()
end

function Body:buildBoxes()
    local boxes = {}
    local sex = Panel.sex(self.window)
    local frame = Data.frame
    for index = 0, 16 do
        local segment = Data.segments[index]
        local tex = Panel.texture("media/ui/BodyParts/bps_" .. sex .. "_" .. segment.bps)
        if tex ~= nil and type(tex.getOffsetX) == "function" then
            boxes[#boxes + 1] = { index = index, x = tex:getOffsetX() + frame.x, y = tex:getOffsetY() + frame.y,
                w = tex:getWidth(), h = tex:getHeight(), z = segment.z }
        end
    end
    return boxes
end

function Body:segmentAt(x, y)
    if self.boxes == nil then self.boxes = self:buildBoxes() end
    return Data.hit(self.boxes, x, y)
end

function Body:partAt(x, y)
    local index = self:segmentAt(x, y)
    if index == nil then return nil end
    return Data.partOf[index]
end

function Body:onMouseMove(dx, dy)
    self.window:setHover(self:partAt(self:getMouseX(), self:getMouseY()), "body")
end

function Body:onMouseMoveOutside(dx, dy)
    self.window:setHover(nil, "body")
end

function Body:onMouseDown(x, y)
    local part = self:partAt(x, y)
    if part ~= nil then self.window:select(part) end
    return true
end

function Body:onMouseUp(x, y)
    return true
end

function Body:onRightMouseUp(x, y)
    self.window:openMenu(self:partAt(x, y), self:getAbsoluteX() + x, self:getAbsoluteY() + y)
    return true
end

function Body:drawTints(sex, active)
    local frame, window = Data.frame, self.window
    for _, part in ipairs(Data.order) do
        local rank = window.ranks[part]
        local alpha = 0
        if rank ~= nil then alpha = 0.3 end
        if part == active then
            if rank ~= nil then alpha = 0.6 else alpha = 0.22 end
        end
        if alpha > 0 then
            local r, g, b = Data.levelColor(rank or 1)
            for _, index in ipairs(Data.groups[part]) do
                local tex = Panel.texture("media/ui/BodyParts/bps_" .. sex .. "_" .. Data.segments[index].bps)
                if tex ~= nil then self:drawTexture(tex, frame.x, frame.y, alpha, r, g, b) end
            end
        end
    end
end

function Body:drawOverlays(sex)
    local frame = Data.frame
    for _, place in ipairs(self.window.placed) do
        if place.overlay ~= nil then
            local tex = Panel.texture(Data.textureName(sex == "female", place.overlay, Data.segments[place.segment].tex))
            if tex ~= nil then self:drawTexture(tex, frame.x, frame.y, 1, 1, 1, 1) end
        end
    end
end

function Body:boxOf(segment)
    if self.boxes == nil then self.boxes = self:buildBoxes() end
    for _, box in ipairs(self.boxes) do
        if box.index == segment then return box end
    end
    return nil
end

function Body:drawFocus(sex, active)
    local frame, window = Data.frame, self.window
    local outline = Panel.texture("media/ui/BodyParts/bps_" .. sex .. "_outlines")
    if outline ~= nil then self:drawTexture(outline, frame.x, frame.y, 0.5, 1, 1, 1) end
    local outer = Panel.texture("media/ui/BodyParts/bps_node_diamond_outline")
    local inner = Panel.texture("media/ui/BodyParts/bps_node_diamond")
    if outer == nil or inner == nil then return end
    for _, place in ipairs(window.placed) do
        local box = place.part == active and self:boxOf(place.segment) or nil
        if box ~= nil then
            local r, g, b = Data.levelColor(Data.rank(place.injury, window.hours, window.snapshot.dead))
            local cx, cy = box.x + box.w / 2, box.y + box.h / 2
            self:drawTexture(inner, cx - inner:getWidthOrig() / 2, cy - inner:getHeightOrig() / 2, 1, r, g, b)
            self:drawTexture(outer, cx - outer:getWidthOrig() / 2, cy - outer:getHeightOrig() / 2, 1, 1, 1, 1)
        end
    end
end

function Body:render()
    if self.window.broken == true then return end
    local ok, err = pcall(self.paint, self)
    if not ok then Panel.fault(self.window, err) end
end

function Body:paint()
    local window = self.window
    local sex = Panel.sex(window)
    local frame = Data.frame
    local base = Panel.texture("media/ui/BodyDamage/" .. sex .. "_base")
    if base ~= nil then self:drawTexture(base, frame.x, frame.y, 1, 1, 1, 1) end
    local active = window:activePart()
    self:drawTints(sex, active)
    self:drawOverlays(sex)
    if active ~= nil then self:drawFocus(sex, active) end
end

function List:new(window, x, y, width, height)
    local o = ISScrollingListBox.new(self, x, y, width, height)
    o.window = window
    return o
end

function List:rowPart(row)
    local item = self.items[row]
    if item == nil or type(item.item) ~= "table" then return nil end
    return item.item.part
end

function List:onMouseMove(dx, dy)
    ISScrollingListBox.onMouseMove(self, dx, dy)
    self.window:setHover(self:rowPart(self.mouseoverselected), "list")
end

function List:onMouseMoveOutside(x, y)
    ISScrollingListBox.onMouseMoveOutside(self, x, y)
    self.window:setHover(nil, "list")
end

function List:onRightMouseUp(x, y)
    local part = self:rowPart(self:rowAt(x, y))
    self.window:openMenu(part, self:getAbsoluteX() + x, self:getAbsoluteY() + y)
    return true
end

function List:doDrawItem(y, item, alt)
    if self.window.broken ~= true then
        local ok, err = pcall(self.paintRow, self, y, item)
        if not ok then Panel.fault(self.window, err) end
    end
    return y + item.height
end

function List:paintRow(y, item)
    local window, row, height = self.window, item.item, item.height
    if y + self:getYScroll() + height < 0 or y + self:getYScroll() >= self.height then return end
    if self.selected == item.index then
        self:drawRect(0, y, self:getWidth(), height - 1, 0.2, 1, 1, 1)
    elseif self.mouseoverselected == item.index and self:isMouseOver() and not self:isMouseOverScrollBar() then
        self:drawRect(0, y, self:getWidth(), height - 1, 0.07, 1, 1, 1)
    end
    if window.hoverFrom == "body" and window.hoverPart == row.part then
        self:drawRectBorder(0, y, self:getWidth() - 1, height - 1, 1, 1, 1, 1)
    end
    local r, g, b = Data.levelColor(row.rank)
    self:drawRect(0, y + 2, 3, height - 5, 1, r, g, b)
    local fh = window.fh
    self:drawText(row.title, 10, y + 3, 1, 1, 1, 1, UIFont.Small)
    local ty = y + 3 + fh
    for _, line in ipairs(row.lines) do
        local lr, lg, lb = Data.tone(line.tone)
        self:drawText(line.text, 16, ty, lr, lg, lb, 1, UIFont.Small)
        ty = ty + fh
    end
end

return Panel
