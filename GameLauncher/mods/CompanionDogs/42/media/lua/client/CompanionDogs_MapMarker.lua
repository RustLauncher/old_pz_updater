require "ISUI/Maps/ISWorldMap"
require "ISUI/Maps/ISMiniMap"

CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

local MARKER_TEX = "media/textures/CDDogPaw_64.png"
local MARKER_TEX_GREY = "media/textures/CDDogPawGrey_64.png"
local TRACK_THROTTLE = 10
local MM_ICON = 14
local WM_ICON = 20
local LBL_ACTIVE_R, LBL_ACTIVE_G, LBL_ACTIVE_B = 0.31, 0.23, 0.16
local LBL_PASSIVE_R, LBL_PASSIVE_G, LBL_PASSIVE_B = 0.42, 0.42, 0.42

local markers = {}
local markerTex = nil
local markerTexGrey = nil

local function texture(active)
    if markerTex == nil then
        markerTex = getTexture(MARKER_TEX)
    end
    if markerTexGrey == nil then
        markerTexGrey = getTexture(MARKER_TEX_GREY)
    end
    if active then return markerTex end
    return markerTexGrey or markerTex
end

local trackTick = 0
local sendEvery = 60
local sendCount = 0
local lastSentBy = {}

local function trackPlayer(player, doSend)
    local pn = player:getPlayerNum()
    local lastSent = lastSentBy[pn]
    if not lastSent then
        lastSent = {}
        lastSentBy[pn] = lastSent
    end
    local pd = CD.playerData(player)
    pd.dogPositions = pd.dogPositions or {}

    local liveTokens = {}
    local comps = CD.regCompanions()
    for i = 1, #comps do
        local a = comps[i]
        if a:isExistInTheWorld() and not a:isDead() and CD.isOwnedBy(a, player) then
            local t = CD.data(a).companionToken
            if t ~= nil then
                pd.dogPositions[t] = { x = a:getX(), y = a:getY(), z = a:getZ(),
                                       name = CD.data(a).name or CD.breedNoun(a) }
                liveTokens[t] = true
            end
        end
    end

    if (pd.stash ~= nil or pd.carried ~= nil) and pd.token ~= nil then
        local prev = pd.dogPositions[pd.token]
        pd.dogPositions[pd.token] = { x = player:getX(), y = player:getY(), z = player:getZ(),
                                      name = (prev and prev.name) or pd.name or CD.breedNoun(nil) }
    end

    if pd.token ~= nil and pd.lastPos and pd.dogPositions[pd.token] == nil then
        pd.dogPositions[pd.token] = { x = pd.lastPos.x, y = pd.lastPos.y, z = pd.lastPos.z, name = pd.name }
    end

    if type(pd.kennel) == "table" then
        for t, snap in pairs(pd.kennel) do
            if pd.dogPositions[t] == nil and type(snap) == "table" and snap.x then
                pd.dogPositions[t] = { x = snap.x, y = snap.y, z = snap.z or 0, name = snap.name }
            end
        end
    end

    local myTokens = {}
    if type(pd.companions) == "table" then
        for t in pairs(pd.companions) do myTokens[t] = true end
    end
    for t in pairs(liveTokens) do myTokens[t] = true end
    if pd.token ~= nil then
        myTokens[pd.token] = true
    end

    for t in pairs(pd.dogPositions) do
        if not myTokens[t] then
            pd.dogPositions[t] = nil
            lastSent[t] = nil
        end
    end

    local out = {}
    for t in pairs(myTokens) do
        local p = pd.dogPositions[t]
        if p and p.x then
            out[#out + 1] = { x = p.x, y = p.y, z = p.z, name = p.name, active = (t == pd.token) }
        end
    end
    markers[pn] = out

    if doSend then
        local list = {}
        for t, p in pairs(pd.dogPositions) do
            local fx, fy, fz = math.floor(p.x), math.floor(p.y), math.floor(p.z or 0)
            local ls = lastSent[t]
            if not ls or ls.x ~= fx or ls.y ~= fy or ls.z ~= fz or ls.name ~= p.name then
                list[#list + 1] = { t = t, x = fx, y = fy, z = fz, name = p.name }
                lastSent[t] = { x = fx, y = fy, z = fz, name = p.name }
            end
        end
        if #list > 0 then
            CD.request("dogpos", nil, { list = list }, player)
        end
    end
end

local function updateTracked()
    trackTick = trackTick + 1
    if trackTick < TRACK_THROTTLE then return end
    trackTick = 0
    if not CD.showMapMarker() then
        markers = {}
        return
    end
    sendCount = sendCount + 1
    local doSend = sendCount >= sendEvery
    if doSend then
        sendCount = 0
    end
    CD.eachLocalPlayer(function(p) trackPlayer(p, doSend) end)
end

local function drawMarker(mapUI, iconSize, clampToEdge)
    if not CD.showMapMarker() then return end
    local mine = markers[mapUI.playerNum or 0]
    if not mine or #mine == 0 then return end
    local api = mapUI.mapAPI
    if not api then return end
    local half = iconSize / 2
    local w, h = mapUI:getWidth(), mapUI:getHeight()
    for _, m in ipairs(mine) do
        local tex = texture(m.active)
        local sx, sy = api:worldToUIX(m.x, m.y), api:worldToUIY(m.x, m.y)
        if sx ~= nil and tex then
            if clampToEdge then
                if sx < half then sx = half elseif sx > w - half then sx = w - half end
                if sy < half then sy = half elseif sy > h - half then sy = h - half end
            end
            mapUI:drawTextureScaledAspect(tex, sx - half, sy - half, iconSize, iconSize, 1.0, 1.0, 1.0, 1.0)
            if not clampToEdge and m.name and m.name ~= "" then
                local r, g, b
                if m.active then r, g, b = LBL_ACTIVE_R, LBL_ACTIVE_G, LBL_ACTIVE_B
                else r, g, b = LBL_PASSIVE_R, LBL_PASSIVE_G, LBL_PASSIVE_B end
                mapUI:drawText(m.name, sx + half + 2, sy - 7, r, g, b, 1.0, UIFont.Small)
            end
        end
    end
end

local origWorldPrerender = ISWorldMap.prerender
function ISWorldMap:prerender()
    origWorldPrerender(self)
    CD.pz("cli.mapdraw", drawMarker, self, WM_ICON, false)
end

local origMiniPrerender = ISMiniMapInner.prerender
function ISMiniMapInner:prerender()
    origMiniPrerender(self)
    CD.pz("cli.mapdraw", drawMarker, self, MM_ICON, true)
end

if isClient() or not isServer() then
    CD.evAdd(Events.OnTick, updateTracked, "cli.mapmarker")
end
