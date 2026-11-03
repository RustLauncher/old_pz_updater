require "ISUI/ISUIElement"

CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

local HEAD_OFFSET = 55
local TAG_W = 260
local LINE_H = 16
local TAG_RADIUS = 14

local ALERT_BANDS = {
    group = { key = "IGUI_PD_AlertGroupTag", r = 1.00, g = 0.30, b = 0.25 },
    close = { key = "IGUI_PD_AlertCloseTag", r = 0.98, g = 0.45, b = 0.20 },
    near  = { key = "IGUI_PD_AlertNearTag",  r = 0.96, g = 0.86, b = 0.32 },
    far   = { key = "IGUI_PD_AlertFarTag",   r = 0.62, g = 0.72, b = 0.82 },
}

local ISCDNameTag = ISUIElement:derive("ISCDNameTag")

-- Hit-rect em zero: o caminho de botao direito da engine e so por bounds e ignora
-- setConsumeMouseEvents(false). Com width 0 o isOverElement nunca casa e some a deadzone.
function ISCDNameTag:new(playerNum)
    local o = ISUIElement:new(0, 0, 0, 0)
    setmetatable(o, self)
    self.__index = self
    o.playerNum = playerNum
    o.draw = false
    return o
end

-- Setar no :instantiate e nao no :new: instantiate cria um javaObject novo e a flag se perde.
function ISCDNameTag:instantiate()
    ISUIElement.instantiate(self)
    self:setRenderThisPlayerOnly(self.playerNum)
    self:setFollowGameWorld(true)
    self.javaObject:setConsumeMouseEvents(false)
end

function ISCDNameTag:prerender()
    self.draw = false
    self.lines = nil
    if not CD.showNameTags() then return end
    local player = getSpecificPlayer(self.playerNum)
    if not player or player:isDead() then return end
    local dog = self.dog
    if not dog then return end
    -- Quem seta isInvisible e o fallback BLINK do salto de cerca em MP.
    local hidden = dog:isInvisible()
    if hidden then return end
    if math.floor(dog:getZ()) ~= math.floor(player:getZ()) then return end

    local lines = {}
    local showName = CD.Settings.getShowNames()
    if CD.isOwnedBy(dog, player) then
        if CD.showNotifications() then
            local band = ALERT_BANDS[CD.data(dog).alertTier]
            if band then
                lines[#lines + 1] = { text = getText(band.key), r = band.r, g = band.g, b = band.b }
            end
            local bd = CD.statusBadge(dog)
            if bd then
                lines[#lines + 1] = { text = getText(bd.key), r = bd.r, g = bd.g, b = bd.b }
            end
            local dist = CD.data(dog).distractingUntilMin
            if dist and CD.worldMinutes() < dist then
                lines[#lines + 1] = { text = getText("IGUI_PD_TrickDistractTag"), r = 0.95, g = 0.35, b = 0.30 }
            end
            local untilMin = CD.data(dog).fetchResultUntilMin
            if untilMin and CD.worldMinutes() < untilMin then
                local r = CD.data(dog).fetchResult
                if r and r.ok then
                    lines[#lines + 1] = { text = getText("IGUI_PD_TrickFetchDoneTag", r.item or "?"),
                                          r = 0.55, g = 0.90, b = 0.55 }
                else
                    lines[#lines + 1] = { text = getText("IGUI_PD_TrickFetchNoneTag"),
                                          r = 0.95, g = 0.45, b = 0.40 }
                end
            end
            local fetchMem = CD.fetchedScent(dog)
            if fetchMem then
                lines[#lines + 1] = { text = getText("IGUI_PD_TrickFetchTag", fetchMem.name or "?"),
                                      r = 0.70, g = 0.80, b = 0.95 }
            end
            local sniffing = CD.data(dog).sniffingUntilMin
            if sniffing and CD.worldMinutes() < sniffing then
                local spot = CD.data(dog).sniffSpot
                local mem = CD.sniffedScent(dog)
                local scentName = (spot and spot.name) or (mem and mem.name) or "?"
                lines[#lines + 1] = { text = getText("IGUI_PD_TrickSniffTag", scentName), r = 0.62, g = 0.86, b = 0.52 }
            end
            local feeding = CD.data(dog).autoFeeding
            local drink = CD.data(dog).autoFeedKind == "water"
            if feeding == "going" then
                lines[#lines + 1] = { text = getText(drink and "IGUI_PD_AutoFeedGoingDrink" or "IGUI_PD_AutoFeedGoing"), r = 0.55, g = 0.85, b = 0.45 }
            elseif feeding == "eating" then
                lines[#lines + 1] = { text = getText(drink and "IGUI_PD_AutoFeedDrinking" or "IGUI_PD_AutoFeedEating"), r = 0.55, g = 0.85, b = 0.45 }
            end
            local hunting = CD.data(dog).hunting
            if hunting == "tracking" then
                lines[#lines + 1] = { text = getText("IGUI_PD_HuntTracking"), r = 0.82, g = 0.72, b = 0.42 }
            elseif hunting == "sniffing" then
                lines[#lines + 1] = { text = getText("IGUI_PD_HuntSniffing"), r = 0.62, g = 0.86, b = 0.52 }
            elseif hunting == "chasing" then
                lines[#lines + 1] = { text = getText("IGUI_PD_HuntChasing"), r = 0.88, g = 0.66, b = 0.34 }
            elseif hunting == "holding" then
                lines[#lines + 1] = { text = getText("IGUI_PD_HuntHolding"), r = 0.90, g = 0.45, b = 0.40 }
            elseif hunting == "retrieving" then
                lines[#lines + 1] = { text = getText("IGUI_PD_HuntRetrieving"), r = 0.70, g = 0.80, b = 0.50 }
            elseif hunting == "foraging" then
                lines[#lines + 1] = { text = getText("IGUI_PD_HuntForaging"), r = 0.62, g = 0.80, b = 0.55 }
            elseif CD.data(dog).huntCooling then
                lines[#lines + 1] = { text = getText("IGUI_PD_HuntCooldown"), r = 0.60, g = 0.60, b = 0.62 }
            end
            if CD.data(dog).careMode then
                lines[#lines + 1] = { text = getText("IGUI_PD_CareTag"), r = 0.55, g = 0.82, b = 0.70 }
            end
        end
        if CD.isPregnant(dog) then
            lines[#lines + 1] = { text = CD.pregnancyLabel(dog), r = 0.96, g = 0.55, b = 0.80 }
        end
        if showName then
            lines[#lines + 1] = { text = CD.data(dog).name or CD.breedNoun(dog), r = 1, g = 1, b = 1 }
        end
    else
        local owner = CD.data(dog).ownerName
        if showName and owner and owner ~= "" then
            lines[#lines + 1] = { text = getText("IGUI_PD_OwnerTag", owner), r = 0.70, g = 0.78, b = 0.92 }
        end
        if CD.isPregnant(dog) then
            lines[#lines + 1] = { text = CD.pregnancyLabel(dog), r = 0.96, g = 0.55, b = 0.80 }
        end
        if showName then
            lines[#lines + 1] = { text = CD.data(dog).name or CD.breedNoun(dog), r = 1, g = 1, b = 1 }
        end
    end
    if #lines == 0 then return end
    self.lines = lines

    local off = HEAD_OFFSET / getCore():getZoom(self.playerNum)
    local sx = isoToScreenX(self.playerNum, dog:getX(), dog:getY(), dog:getZ()) - getPlayerScreenLeft(self.playerNum)
    local sy = isoToScreenY(self.playerNum, dog:getX(), dog:getY(), dog:getZ()) - getPlayerScreenTop(self.playerNum) - off
    self:setX(sx - TAG_W / 2)
    self:setY(sy - #lines * LINE_H)
    self.draw = true
end

function ISCDNameTag:render()
    if not self.draw or not self.lines then return end
    local cx = TAG_W / 2
    for i = 1, #self.lines do
        local ln = self.lines[i]
        local y = (i - 1) * LINE_H
        self:drawTextCentre(ln.text, cx + 1, y + 1, 0, 0, 0, 0.7, UIFont.Small)
        self:drawTextCentre(ln.text, cx, y, ln.r, ln.g, ln.b, 1, UIFont.Small)
    end
end

local pools = {}

local function ensurePool(playerNum)
    if not pools[playerNum] then
        pools[playerNum] = {}
    end
    return pools[playerNum]
end

local function tagSlot(playerNum, index)
    local pool = ensurePool(playerNum)
    local o = pool[index]
    if not o then
        o = ISCDNameTag:new(playerNum)
        o:initialise()
        o:instantiate()
        o:addToUIManager()
        pool[index] = o
    end
    return o
end

local function gatherCompanions(player, radius)
    local out = {}
    local comps = CD.regCompanions()
    local pz = math.floor(player:getZ())
    for i = 1, #comps do
        local a = comps[i]
        if a:isExistInTheWorld() and not a:isDead()
           and math.floor(a:getZ()) == pz and CD.dist2D(a, player) <= radius then
            out[#out + 1] = a
        end
    end
    return out
end

local function refreshTags(playerNum)
    local pool = ensurePool(playerNum)
    local player = getSpecificPlayer(playerNum)
    local n = 0
    if player and not player:isDead() and CD.showNameTags() then
        local dogs = gatherCompanions(player, TAG_RADIUS)
        for _, dog in ipairs(dogs) do
            n = n + 1
            tagSlot(playerNum, n).dog = dog
        end
    end
    for j = n + 1, #pool do pool[j].dog = nil end
end

ISCDNameTag.prerender = CD.pzWrap("cli.nametag_draw", ISCDNameTag.prerender)
ISCDNameTag.render = CD.pzWrap("cli.nametag_draw", ISCDNameTag.render)

if isClient() or not isServer() then
    Events.OnCreatePlayer.Add(function(playerNum)
        ensurePool(playerNum)
    end)

    -- O prerender ja cuida do quadro a quadro; a varredura so decide QUAIS caes tem etiqueta.
    local SCAN_TICKS = 10
    local scanTick = 0
    CD.evAdd(Events.OnTick, function()
        scanTick = scanTick + 1
        if scanTick < SCAN_TICKS then return end
        scanTick = 0
        for playerNum = 0, getNumActivePlayers() - 1 do
            refreshTags(playerNum)
        end
    end, "cli.nametags")
end
