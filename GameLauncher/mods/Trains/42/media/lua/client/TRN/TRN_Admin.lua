if isServer() then return end

--[[ Trains -- an admin's tools: laying a line of the host's own (SERVERS.md).

    Single player and any client. **Everything here asks**: the server
    decides who is an admin from its own copy of the player (TRN_Util.admin)
    and what a line may be (TRN_Server, `lineAdd`), and says in a line what
    it did or why not. What is kept on this machine is only a draft: the
    points an admin has walked so far, which nobody else sees and nothing is
    built from until it is sent whole.

    A line is laid by standing where it goes:

        Start a new line where I stand
        Add a point where I stand            a corner, or just somewhere it passes
        Add a stop where I stand...          and its name
        Take back the last point
        Finish it as a loop...               its name; three points or more
        Finish it as a line, out and back... its name
        Throw the draft away

    and near a line of the host's: Take up the line <name>.

    **And every train somebody owns** (TRN_Claims): End <player>'s claim
    on the <train>, from anywhere. The server checks who asks.

    The draft is drawn for the admin laying it: a green square on the
    ground at each point (TRN_Body, the same mark as a platform's).
]]

require "TRN/TRN_Config"
require "TRN/TRN_Util"
require "TRN/TRN_Net"
require "TRN/TRN_Time"
require "TRN/TRN_Clock"
require "TRN/TRN_Claims"

TRN = TRN or {}
local C, U, Net, T, K = TRN.Config, TRN.Util, TRN.Net, TRN.Time, TRN.Clock

local A = {}
TRN.Admin = A

A.draft = nil           -- { z =, pts = { { x =, y =, stop = name or nil }, ... } }
A.stats = { sent = 0 }

local function here(player)
    return math.floor(player:getX()) + 0.5, math.floor(player:getY()) + 0.5, math.floor(player:getZ())
end

--- How long the draft is so far, in squares, and how many stops it has.
function A.measure()
    local d = A.draft
    if not d then return 0, 0, 0 end
    local len, stops = 0, 0
    for i, p in ipairs(d.pts) do
        if p.stop then stops = stops + 1 end
        local q = d.pts[i + 1]
        if q then len = len + math.sqrt((q.x - p.x) * (q.x - p.x) + (q.y - p.y) * (q.y - p.y)) end
    end
    return #d.pts, stops, math.floor(len)
end

local function note(player, key, a, b, c)
    U.note(player, getText(key, a ~= nil and tostring(a) or nil, b ~= nil and tostring(b) or nil,
                           c ~= nil and tostring(c) or nil), 150, 220, 150)
end

--- A point where she stands, a stop if it is given a name. Refused, with
--- words, nearer the last point than a car is long.
function A.point(player, stop)
    local x, y, z = here(player)
    if not A.draft then A.draft = { z = z, pts = {} } end
    local d = A.draft
    local last = d.pts[#d.pts]
    if last and math.sqrt((x - last.x) * (x - last.x) + (y - last.y) * (y - last.y)) < C.Lines.apart then
        U.note(player, getText("IGUI_TRN_RefuseLineShort", tostring(C.Lines.apart)), 255, 120, 90)
        return false
    end
    if #d.pts >= C.Lines.points then
        U.note(player, getText("IGUI_TRN_RefuseLineLong", tostring(C.Lines.points)), 255, 120, 90)
        return false
    end
    if type(stop) == "string" then
        stop = string.sub(stop:gsub("^%s+", ""):gsub("%s+$", ""), 1, C.Lines.nameMost)
        if stop == "" then stop = nil end
    else
        stop = nil
    end
    d.pts[#d.pts + 1] = { x = x, y = y, stop = stop }
    local n, _, len = A.measure()
    if stop then note(player, "IGUI_TRN_AdminStopAdded", n, stop, len) else note(player, "IGUI_TRN_AdminPointAdded", n, len) end
    return true
end

function A.back(player)
    local d = A.draft
    if not d then return end
    table.remove(d.pts)
    if #d.pts == 0 then A.draft = nil end
    note(player, "IGUI_TRN_AdminBackDone", A.measure())
end

function A.drop(player)
    A.draft = nil
    note(player, "IGUI_TRN_AdminDropped")
end

--- Sends the draft whole. It is kept until the server has spoken: a line
--- that is refused can be mended and sent again.
function A.finish(player, closed, name)
    local d = A.draft
    if not d then return false end
    A.stats.sent = A.stats.sent + 1
    A.sentRev = K.state and K.state.rev or nil
    return Net.send(player, "lineAdd", { closed = closed == true, name = name, pts = d.pts })
end

--- The state changed: if a line was sent and there is one more line now,
--- it was taken, and the draft has done its work.
function A.changed()
    if A.draft and A.sentRev and K.state and K.state.rev ~= A.sentRev then
        A.draft, A.sentRev = nil, nil
    end
end

function A.take(player, id)
    return Net.send(player, "lineDrop", { id = id })
end

--- The line of the host's nearest this player, within reach, or nil.
function A.near(player)
    local x, y = player:getX(), player:getY()
    local best, bestFar = nil, nil
    for _, route in ipairs(K.routes()) do
        if route.own then
            local d, far = T.nearest(route, x, y)
            if d and far <= C.Lines.reach and (not bestFar or far < bestFar) then best, bestFar = route, far end
        end
    end
    return best
end

---------------------------------------------------------------------------
-- Asking for a name
---------------------------------------------------------------------------
--- Asks the admin for a line of text and hands it to `fn`. Where the
--- game's own box is not there to ask with, `fallback` is the answer.
function A.ask(player, title, fallback, fn)
    if not ISTextBox then return fn(fallback) end
    U.try("admin.ask", function()
        local box = ISTextBox:new(0, 0, 300, 180, title, fallback, nil, function(_, button)
            if button.internal == "OK" then fn(button.parent.entry:getText()) end
        end, player:getPlayerNum())
        box:initialise()
        box:addToUIManager()
    end)
end

function A.onStop(_, player)
    local _, stops = A.measure()
    A.ask(player, getText("IGUI_TRN_AdminStopName"), getText("IGUI_TRN_AdminStopDefault", tostring(stops + 1)),
          function(name) A.point(player, name) end)
end

function A.onPoint(_, player) A.point(player, nil) end
function A.onBack(_, player) A.back(player) end
function A.onDrop(_, player) A.drop(player) end
function A.onTake(_, player, id) A.take(player, id) end

--- Every claim there is (TRN_Claims), by train: { { id, name, who }, ... }.
function A.claims()
    local out = {}
    local claims = K.state and K.state.claims
    if type(claims) ~= "table" then return out end
    for id in pairs(claims) do
        local claim = TRN.Claims.of(id)
        if claim then
            local _, train = T.find(K.routes(), id)
            out[#out + 1] = { id = id, name = train and U.trainName(train) or id, who = claim.who }
        end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

function A.onUnclaim(_, player, id)
    return Net.send(player, "unclaim", { train = id })
end

function A.onFinish(_, player, closed)
    local n = (K.state and K.state.lines and #K.state.lines or 0) + 1
    A.ask(player, getText("IGUI_TRN_AdminLineName"), getText("IGUI_TRN_AdminLineDefault", tostring(n)),
          function(name) A.finish(player, closed, name) end)
end

---------------------------------------------------------------------------
-- The menu
---------------------------------------------------------------------------
--- Adds *Trains (admin)* to a right-click. **Who it is for is the menu's
--- to say** (TRN_Menu.fill asks TRN_Util.admin, once): asked here as well,
--- each test covered for the other and a mutation of either was missed.
function A.fill(context, worldobjects, player)
    local top = context:addOption(getText("IGUI_TRN_AdminMenu"), worldobjects, nil)
    local menu = ISContextMenu:getNew(context)
    context:addSubMenu(top, menu)
    if not A.draft then
        menu:addOption(getText("IGUI_TRN_AdminStart"), worldobjects, A.onPoint, player)
    else
        local n, stops, len = A.measure()
        menu:addOption(getText("IGUI_TRN_AdminDraft", tostring(n), tostring(stops), tostring(len)), worldobjects, nil)
            .notAvailable = true
        menu:addOption(getText("IGUI_TRN_AdminPoint"), worldobjects, A.onPoint, player)
        menu:addOption(getText("IGUI_TRN_AdminStop"), worldobjects, A.onStop, player)
        menu:addOption(getText("IGUI_TRN_AdminBack"), worldobjects, A.onBack, player)
        local loop = menu:addOption(getText("IGUI_TRN_AdminLoop"), worldobjects, A.onFinish, player, true)
        local line = menu:addOption(getText("IGUI_TRN_AdminLine"), worldobjects, A.onFinish, player, false)
        if stops < 2 then loop.notAvailable, line.notAvailable = true, true end
        if n < 3 then loop.notAvailable = true end
        menu:addOption(getText("IGUI_TRN_AdminDrop"), worldobjects, A.onDrop, player)
    end
    if not A.draft then
        -- (A stop is a point with a name: the first point of a line may be one.)
        menu:addOption(getText("IGUI_TRN_AdminStartStop"), worldobjects, A.onStop, player)
    end
    local near = A.near(player)
    if near then
        menu:addOption(getText("IGUI_TRN_AdminTake", tostring(near.label or near.id)), worldobjects, A.onTake, player, near.id)
    end
    -- Every train somebody owns, and whose: an admin ends any claim, from anywhere.
    for _, held in ipairs(A.claims()) do
        menu:addOption(getText("IGUI_TRN_AdminClaimEnd", held.name, held.who), worldobjects, A.onUnclaim, player, held.id)
    end
    return true
end

--- The draft, drawn for whoever is laying it.
function A.draw(player, home)
    local d = A.draft
    if not d or not TRN.Body or not TRN.Body.spot then return end
    for _, p in ipairs(d.pts) do
        TRN.Body.spot(p.x, p.y, d.z, home)
    end
end

function A.status()
    local n, stops, len = A.measure()
    U.log("status: admin: %s; a draft of %d point(s), %d stop(s), %d squares; %d line(s) sent",
          tostring(U.try("admin.status", function() return U.admin(getSpecificPlayer(0)) end)), n, stops, len, A.stats.sent)
end

return A
