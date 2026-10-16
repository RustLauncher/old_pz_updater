require "ProjectALife/Shells/ALifeAnimations"
require "ProjectALife/Audio/ALifeVoice"
require "ProjectALife/Movement/ALifeDoorPolicy"

ProjectALife = ProjectALife or {}

local Animations = ProjectALife.Animations
local Voice = ProjectALife.Voice

local Traversal = {

    edgeBans = {},

    breachClaims = {},
    settings = {

        breachImpactMs = 480,

        breachRecoverMs = 1400,

        breachSwingsPerWindow = 3,
        breachSwingsPerPlank = 4,

        breachStrengthPercent = 100,

        breachPlankDamage = 22,
        breachObjectDamage = 8,

        breachUnreadFloor = 500,

        breachDeadlineMs = 48000,
        metalBreachRefused = true,
        breachRetryMs = 60000,
        breachReach = 2,

        nativeStartGraceMs = 1200,
        nativeLandedGraceMs = 1800,
        nativeFenceTimeoutMs = 4200,
        nativeWindowTimeoutMs = 4800,

        queueHoldMs = 2000,
        occupiedHoldMs = 1000,

        refusalRepeatMs = 500,

        occupiedStreak = 3,
        occupiedBanMs = 10000,

        dropBanMs = 60000,

        readoptWindowMs = 1000,

        landingCheckMs = 400,

        detourRadius = 8,
        detourNodes = 300,
        detourRouteMs = 2000,
        detourSearchWindowMs = 50,
        detourSearchesPerWindow = 2,

        openingFailMs = 90000,
        openingFailCapMs = 300000,
        staticBanMs = 180000,

        windowDwellMs = 6000,

        replanFreshMs = 3000,

        climbArmMs = 600,

        edgeStrikeMs = 60000,

        shutAfterMs = 600,
        shutDeadlineMs = 20000,
        shutLimit = 64,

        closeDoors = true,
        closeDeadlineMs = 30000,
        closeThreatTiles = 10,
        closeGroupTiles = 6,
        closePlayerTiles = 3,

        lockSearchMs = 4000,
        lockForgetMs = 20000,

        keptOutMs = 90000,

        lockWayMs = 1000,
    },
    adapters = {},
    active = setmetatable({}, { __mode = "k" }),
    results = setmetatable({}, { __mode = "k" }),
    breachBans = setmetatable({}, { __mode = "k" }),
    metrics = { nativeRefused = 0, nativeLockedOut = 0, edgeQueued = 0, nativeBanned = 0,
        nativeBudget = 0, nativeOccupied = 0, occupiedBans = 0, readopted = 0,
        interrupted = 0, clipsAborted = 0, detours = 0, detourMisses = 0, dismantled = 0,
        openingMarks = 0, staticBans = 0, armed = 0, armForced = 0, dwells = 0,
        courteousRefusals = 0, courteousDoors = 0, doorsShut = 0, doorsLeftOpen = 0,
        courteousEntries = 0, doorsUnlocked = 0, glassCleared = 0,
        nativeTimeouts = 0, crossedWedges = 0, climbHeld = 0, pathWhy = "none",
        routeSearches = 0, routeHits = 0, routeDeferred = 0, exitRounds = 0 },

    refusals = {},

    cuts = {},

    shellBans = {},

    edgeBanBy = {},

    detours = {},
    detourCount = 0,

    routes = {},
    routeCount = 0,
    routeSearch = { atMs = 0, used = 0 },
    revision = 0,

    openingFails = {},

    windowTouch = {},

    replanPending = {},

    edgeStrikes = {},

    shutQueue = {},
    shutCount = 0,

    lockSearch = {},

    lockWays = {},

    keptOut = {},
}
ProjectALife.ObstacleTraversal = Traversal

function Traversal.count(name)
    Traversal.metrics = Traversal.metrics or {}
    Traversal.metrics[name] = (Traversal.metrics[name] or 0) + 1
end

function Traversal.objectLoaded(object)
    if object == nil then return false end
    if object.getObjectIndex ~= nil and object:getObjectIndex() < 0 then return false end
    if object.getSquare == nil then return false end
    local square = object:getSquare()
    if square == nil then return false end
    if square.getChunk ~= nil and square:getChunk() == nil then return false end
    if type(getCell) == "function" and square.getX ~= nil then
        local cell = getCell()
        if cell == nil or cell:getGridSquare(square:getX(), square:getY(), square:getZ()) ~= square then
            return false
        end
    end
    return true
end

local function collisionDirection(shell)
    if IsoDirections == nil or shell == nil or shell.isCollidedN == nil or shell.isCollidedE == nil
            or shell.isCollidedS == nil or shell.isCollidedW == nil then
        return nil
    end
    local north, east, south, west = shell:isCollidedN(), shell:isCollidedE(),
        shell:isCollidedS(), shell:isCollidedW()
    local count = (north and 1 or 0) + (east and 1 or 0)
        + (south and 1 or 0) + (west and 1 or 0)
    if count ~= 1 then return nil end
    if north then return IsoDirections.N end
    if east then return IsoDirections.E end
    if south then return IsoDirections.S end
    if west then return IsoDirections.W end
    return nil
end

local function intendedDirection(shell, target)
    if IsoDirections == nil or type(target) ~= "table" then return nil end
    if shell == nil or shell.getX == nil or shell.getY == nil then return nil end
    local x, y = shell:getX(), shell:getY()
    local dx, dy = (target.x or x) - x, (target.y or y) - y
    if math.abs(dx) < 0.05 and math.abs(dy) < 0.05 then return nil end
    if math.abs(dx) >= math.abs(dy) then
        return dx >= 0 and IsoDirections.E or IsoDirections.W
    end
    return dy >= 0 and IsoDirections.S or IsoDirections.N
end

local function windowFlag(window, method)
    if window == nil or window[method] == nil then return false end
    return window[method](window) == true
end

local function barricadeOf(object)
    local found
    pcall(function() found = object:getBarricadeOnSameSquare() end)
    if found == nil then
        pcall(function() found = object:getBarricadeOnOppositeSquare() end)
    end
    return found
end

local function prepareWindow(window, shell)
    if not Traversal.objectLoaded(window) then return false, "obstacle_unloaded" end
    if Traversal.ownSiteObject(shell, window) then return false, "own_outpost_reroute" end

    if Traversal.windowInvincible(window) then return false, "window_invincible_reroute" end

    local readable, isOpen = pcall(function() return window:IsOpen() end)
    if not readable then return true end
    if isOpen == true or windowFlag(window, "isSmashed") then

        if windowFlag(window, "isBarricaded") then
            local barricade = barricadeOf(window)
            if barricade ~= nil then return false, "breach", barricade end
            return false, "window_barricaded_reroute"
        end
        Traversal.knockOutGlass(window, shell)
        return true
    end
    local locked = windowFlag(window, "isLocked") or windowFlag(window, "isPermaLocked")
    if locked and not Traversal.lockedWindowAllowed(shell, window) then
        Traversal.pathWhy(shell, "window_locked")
        return false, "window_locked"
    end
    if windowFlag(window, "isBarricaded") then
        local barricade = barricadeOf(window)
        if barricade ~= nil then return false, "breach", barricade end
        return false, "window_barricaded_reroute"
    end

    if locked then
        Traversal.pathWhy(shell, "window_locked")
        return false, "breach_window", window
    end
    Traversal.pathWhy(shell, "window_closed")
    pcall(function() shell:faceThisObject(window) end)
    pcall(function() shell:openWindow(window) end)

    if not windowFlag(window, "IsOpen") then
        pcall(function() window:ToggleWindow(shell) end)
    end
    if windowFlag(window, "IsOpen") then
        Traversal.noteWindowOpened(shell, window)
        return true
    end

    return false, "breach_window", window
end

local function enterWindowClimb(shell, window)
    local ok, entered = pcall(function()
        if window.canClimbThrough ~= nil
                and window:canClimbThrough(shell) == false then return false end
        if type(isServer) == "function" and isServer() then return false end
        if shell.climbThroughWindow == nil then return false end
        if type(isClient) == "function" and isClient()
                and not ProjectALife.TraversalHands.prepare(shell, true) then return false end
        shell:climbThroughWindow(window)
        return true
    end)
    return ok and entered == true
end

local function enterWindowFrameClimb(shell, frame)
    local ok, entered = pcall(function()

        if frame.canClimbThrough ~= nil
                and frame:canClimbThrough(shell) == false then return false end
        if type(isServer) == "function" and isServer() then return false end
        if shell.climbThroughWindowFrame == nil then return false end
        if type(isClient) == "function" and isClient()
                and not ProjectALife.TraversalHands.prepare(shell, true) then return false end
        shell:climbThroughWindowFrame(frame)
        return true
    end)
    return ok and entered == true
end
Traversal.enterWindowClimb = enterWindowClimb
Traversal.enterWindowFrameClimb = enterWindowFrameClimb

local function isDoorObject(object)
    if object == nil or type(instanceof) ~= "function" then return false end
    if instanceof(object, "IsoDoor") then return true end
    return instanceof(object, "IsoThumpable") == true and object.isDoor ~= nil
        and object:isDoor() == true
end

local function directDoorBetween(square, nextSquare)

    if square == nil or square.getDoorTo == nil then return nil end
    local direct = square:getDoorTo(nextSquare)
    if isDoorObject(direct) and direct.IsOpen ~= nil and direct:IsOpen() ~= true then
        return direct
    end
    return nil
end

local function closedDoorBetween(square, nextSquare)
    return directDoorBetween(square, nextSquare)
end

local function collidedDoor(shell)
    if shell == nil or shell.getCollidedObject == nil then return nil end
    local object = shell:getCollidedObject()
    if not isDoorObject(object) or object.IsOpen == nil then return nil end
    return object:IsOpen() ~= true and object or nil
end

function Traversal.doorObstructed(door)
    local obstructed = false
    pcall(function() obstructed = door:isObstructed() == true end)
    if obstructed then return true end
    local policy = ProjectALife.DoorPolicy
    return policy ~= nil and type(policy.groupObstructed) == "function" and policy.groupObstructed(door) == true
end

Traversal.doorBlockFlags = { "isObstructed", "isBarricaded", "isLocked", "isLockedByKey" }

function Traversal.doorBlockKind(object, from)
    if object == nil then return nil end
    local policy = ProjectALife.DoorPolicy
    if policy ~= nil and type(policy.blockKind) == "function" then
        return policy.blockKind(object, from)
    end

    for index = 1, #Traversal.doorBlockFlags do
        local name = Traversal.doorBlockFlags[index]
        local query = object[name]
        if query ~= nil then
            local ok, value = pcall(query, object)
            if ok and value == true then return name end
        end
    end
    return nil
end

local function doorIsPassable(object, from)
    if object == nil then return true end
    return Traversal.doorBlockKind(object, from) == nil
end

function Traversal.boundaryEntry(shell, object, actor)
    local standoff = ProjectALife.Standoff
    if standoff == nil or type(standoff.allowBoundaryEntry) ~= "function" then return true end
    return standoff.allowBoundaryEntry(shell, object, actor) ~= false
end

function Traversal.boundaryHolds(shell, object)
    local policy = ProjectALife.DoorPolicy
    if shell == nil or object == nil or policy == nil or type(policy.boundaryOwners) ~= "function" then return false end
    local actor = policy.actorOf(shell)
    if actor == nil or policy.boundaryOwners(object) == nil then return false end
    if policy.boundaryKeepsOut(actor, object) then return true end
    return Traversal.boundaryEntry(shell, object, actor) == false
end

function Traversal.courtesyHolds(shell, object, square)
    local policy = ProjectALife.DoorPolicy
    if shell == nil or policy == nil or type(policy.keyWaived) ~= "function" then return false end
    if Traversal.ownSiteObject(shell, object) then return false end
    if Traversal.boundaryHolds(shell, object) then return true end
    if not policy.keyWaived(object, square) then return false end
    return not Traversal.breachAllowed(shell, object)
end

function Traversal.unlockFromInside(shell, object, square)
    local policy = ProjectALife.DoorPolicy
    if shell == nil or policy == nil or type(policy.unlockableFrom) ~= "function"
            or not policy.unlockableFrom(object, square) then
        return false
    end
    if Traversal.ownSiteObject(shell, object) then return false end
    if Traversal.invitedThrough(shell, object) then return false end
    local x, y = policy.pointOf(object)
    if x == nil or policy.inPlayerBase(x, y) or not policy.unlock(object) then return false end
    Traversal.count("doorsUnlocked")
    local blackBox = ProjectALife.BlackBox
    if blackBox ~= nil and blackBox.enabled and type(blackBox.note) == "function" then
        pcall(blackBox.note, shell, "door-unlocked", "from=inside at=" .. tostring(x) .. "," .. tostring(y))
    end
    return true
end

function Traversal.entryCourtesyHolds(shell, object, square, nextSquare)
    if Traversal.enteringKeptOut(shell, square, nextSquare) then return true end
    local policy = ProjectALife.DoorPolicy
    if shell == nil or object == nil or policy == nil or type(policy.entering) ~= "function"
            or not policy.entering(square, nextSquare, object) then
        return false
    end
    if Traversal.ownSiteObject(shell, object) then return false end
    return not Traversal.breachAllowed(shell, object)
end

function Traversal.refuseEntry(shell)
    Traversal.count("courteousEntries")
    Traversal.refuseCourteously(shell)
    return false, "courteous_reroute"
end

function Traversal.sameRoom(a, b)
    if a == nil or b == nil or type(a.getRoom) ~= "function" or type(b.getRoom) ~= "function" then
        return false
    end
    local room = a:getRoom()
    if room ~= nil then return room == b:getRoom() end
    if b:getRoom() ~= nil or IsoFlagType == nil or IsoFlagType.exterior == nil
            or type(a.has) ~= "function" or type(b.has) ~= "function" then
        return false
    end
    return a:has(IsoFlagType.exterior) == true and b:has(IsoFlagType.exterior) == true
end

function Traversal.siblingPassage(door, from)
    local policy = ProjectALife.DoorPolicy
    if door == nil or policy == nil or type(policy.grouped) ~= "function" or type(getCell) ~= "function"
            or type(door.getSquare) ~= "function" or type(door.getOppositeSquare) ~= "function"
            or type(door.getNorth) ~= "function" or policy.grouped(door) then
        return nil
    end
    local square, opposite, cell = door:getSquare(), door:getOppositeSquare(), getCell()
    if square == nil or opposite == nil or cell == nil then return nil end
    local north = door:getNorth() == true
    for step = -1, 1, 2 do
        local x, y = square:getX(), square:getY()
        if north then x = x + step else y = y + step end
        local beside = cell:getGridSquare(x, y, square:getZ())
        local objects = nil
        if beside ~= nil then objects = beside:getObjects() end
        for index = 0, (objects ~= nil and objects:size() or 0) - 1 do
            local other = objects:get(index)
            if other ~= door and isDoorObject(other) and type(other.getNorth) == "function"
                    and other:getNorth() == north and type(other.getOppositeSquare) == "function"
                    and not policy.grouped(other)
                    and Traversal.sameRoom(square, other:getSquare())
                    and Traversal.sameRoom(opposite, other:getOppositeSquare())
                    and (other:IsOpen() == true or Traversal.doorBlockKind(other, from) == nil) then
                return other
            end
        end
    end
    return nil
end

function Traversal.siblingReroute(shell, door, square, nextSquare, now, doorsOnly)
    if Traversal.siblingPassage(door, square) == nil then return false end
    local key = Traversal.edgeKey(square, nextSquare)
    if key == nil or Traversal.detourRoute(shell, key, doorsOnly == true) == nil then return false end
    Traversal.markOpening(shell, key, "door_sibling", now)
    return true
end

function Traversal.edgeNote(square, nextSquare, object)
    if square == nil or nextSquare == nil or type(square.getX) ~= "function"
            or type(nextSquare.getX) ~= "function" then
        return " at=-"
    end
    local x, y = math.floor(square:getX()), math.floor(square:getY())
    local nx, ny = math.floor(nextSquare:getX()), math.floor(nextSquare:getY())
    local direction = "?"
    if ny < y then direction = "N" elseif ny > y then direction = "S"
    elseif nx > x then direction = "E" elseif nx < x then direction = "W" end
    local onEdge = "-"
    if object ~= nil and type(square.getDoorTo) == "function" then
        onEdge = tostring(square:getDoorTo(nextSquare) == object)
    end
    return " at=" .. x .. "," .. y .. " next=" .. nx .. "," .. ny .. " dir=" .. direction .. " edge=" .. onEdge
end

local function playSoundFrom(source, sound)
    if source == nil or type(sound) ~= "string" or sound == "" then return end
    local dedicated = type(isServer) == "function" and isServer()
    if dedicated and type(sendPlaySound) == "function" then
        pcall(sendPlaySound, sound, false, source)
    else
        pcall(function() source:playSound(sound) end)
    end
end

function Traversal.toggleGroup(object)
    if IsoDoor == nil then return false end
    local double, garage = -1, -1
    pcall(function() double = tonumber(IsoDoor.getDoubleDoorIndex(object)) or -1 end)
    pcall(function() garage = tonumber(IsoDoor.getGarageDoorIndex(object)) or -1 end)
    if double > -1 then
        return pcall(function() IsoDoor.toggleDoubleDoor(object, true) end) == true
    end
    if garage > -1 then
        return pcall(function() IsoDoor.toggleGarageDoor(object, true) end) == true
    end
    return false
end

function Traversal.settleLeaf(object, square)
    local home = square
    pcall(function() home = object:getSquare() or square end)
    if home ~= nil then pcall(function() home:RecalcAllWithNeighbours(true) end) end
    local open = false
    pcall(function() open = object:IsOpen() == true end)
    pcall(function() object:syncIsoObject(false, open and 1 or 0, nil, nil) end)
    if type(object.PlayAnimation) == "function" then pcall(object.PlayAnimation, object) end
    pcall(function()
        if FBORenderChunk ~= nil then
            object:invalidateRenderChunkLevel(FBORenderChunk.DIRTY_OBJECT_MODIFY)
        end
    end)
    return home
end

function Traversal.doorSound(object, square)
    pcall(function()
        if object.getSoundPrefix == nil then return end
        local prefix = object:getSoundPrefix()
        if type(prefix) ~= "string" or prefix == "" then return end
        local isOpen = true
        pcall(function() isOpen = object:IsOpen() == true end)
        playSoundFrom(square or object, prefix .. (isOpen and "Open" or "Close"))
    end)
end

local function openDoor(object, square, shell)
    if not Traversal.objectLoaded(object) then return false end

    local alreadyOpen = false
    pcall(function() alreadyOpen = object:IsOpen() == true end)
    if alreadyOpen then return true end

    if Traversal.doorBlockKind(object, square) ~= nil then return false end
    if Traversal.courtesyHolds(shell, object, square) then return false end
    if Traversal.doorKeptOut(shell, object, square) then return false end

    local policy = ProjectALife.DoorPolicy
    if policy ~= nil and type(policy.groupLocked) == "function"
            and policy.groupLocked(object, square) == true then
        return false
    end

    local keyed, locked, leaf = false, false, object
    if policy ~= nil and type(policy.ask) == "function" then

        keyed = policy.ask(object, "isLockedByKey") == true
        locked = keyed or policy.ask(object, "isLocked") == true
        if type(policy.steadyLeaf) == "function" then leaf = policy.steadyLeaf(object) end
    end

    local grouped = Traversal.toggleGroup(object)
    local home = square
    if grouped then
        pcall(function() home = object:getSquare() or square end)
    else
        if type(object.ToggleDoorSilent) ~= "function" or not pcall(object.ToggleDoorSilent, object) then return false end
        home = Traversal.settleLeaf(object, square)
    end
    Traversal.doorSound(object, home)
    local readable, open = pcall(function() return object:IsOpen() end)

    local opened = grouped or not readable or open == true
    if opened then
        Traversal.noteOpened(shell, leaf, home, keyed, locked, square)
        Traversal.noteEntry(shell, object, "door", nil)
        local plus = ProjectALife.BlackBoxPlus
        if plus ~= nil then pcall(plus.doorOpened, shell, object, square, keyed, locked, grouped, readable, open) end
        local intrusion = ProjectALife.IntrusionCue
        if intrusion ~= nil then pcall(intrusion.doorOpened, shell, object, square) end
    end
    return opened
end
Traversal.openDoor = openDoor

local function crossingAhead(square, direction)
    if square == nil or direction == nil then return false end
    if square.getAdjacentSquare == nil or square.getWindowTo == nil then return false end
    local nextSquare = square:getAdjacentSquare(direction)
    if nextSquare == nil then return false end
    if square:getWindowTo(nextSquare) ~= nil then return true end
    if square.getWindowFrameTo == nil then return false end
    return square:getWindowFrameTo(nextSquare) ~= nil
        or directDoorBetween(square, nextSquare) ~= nil
end

local function sideDirection(shell, target, direction)
    if IsoDirections == nil or type(target) ~= "table" then return nil end
    if shell == nil or shell.getX == nil or shell.getY == nil then return nil end
    local x, y = shell:getX(), shell:getY()
    local dx, dy = (target.x or x) - x, (target.y or y) - y
    if direction == IsoDirections.E or direction == IsoDirections.W then
        if math.abs(dy) < 0.05 then return nil end
        return dy >= 0 and IsoDirections.S or IsoDirections.N
    end
    if direction == IsoDirections.N or direction == IsoDirections.S then
        if math.abs(dx) < 0.05 then return nil end
        return dx >= 0 and IsoDirections.E or IsoDirections.W
    end
    return nil
end

function Traversal.sideCrossingTaken(shell, square, side)
    local door = directDoorBetween(square, square:getAdjacentSquare(side))
    if door == nil then return true end
    if collidedDoor(shell) == door or Traversal.collidedToward(shell, side) then return true end
    return Traversal.facingDirection(shell) == side
end

function Traversal.collidedToward(shell, direction)
    if shell == nil or IsoDirections == nil or direction == nil then return false end
    local name = nil
    if direction == IsoDirections.N then name = "isCollidedN"
    elseif direction == IsoDirections.E then name = "isCollidedE"
    elseif direction == IsoDirections.S then name = "isCollidedS"
    elseif direction == IsoDirections.W then name = "isCollidedW" end
    if name == nil or type(shell[name]) ~= "function" then return false end
    return shell[name](shell) == true
end

function Traversal.crossingDirection(shell, target)
    local direction = collisionDirection(shell) or intendedDirection(shell, target)
    if direction == nil then return nil end
    local square = shell.getSquare ~= nil and shell:getSquare() or nil
    if square == nil or crossingAhead(square, direction) then return direction end
    local side = sideDirection(shell, target, direction)
    if side ~= nil and crossingAhead(square, side) and Traversal.sideCrossingTaken(shell, square, side) then
        return side
    end
    return direction
end

function Traversal.openWindowAhead(shell, target)
    if shell == nil or type(target) ~= "table" or Traversal.isBusy(shell) then
        return false
    end
    local ok, opened, reason = pcall(function()
        local direction = Traversal.crossingDirection(shell, target)
        if direction == nil then return false end
        local square = shell:getSquare()
        if square == nil then return false end
        local nextSquare = square:getAdjacentSquare(direction)
        if nextSquare == nil then return false end
        local window = square:getWindowTo(nextSquare)
        if window == nil then return false end
        if not Traversal.objectLoaded(window) or Traversal.ownSiteObject(shell, window) then return false end

        if Traversal.probeRefused(shell, window, square, nextSquare, direction) then return false end
        if Traversal.entryCourtesyHolds(shell, window, square, nextSquare) then return false end

        if windowFlag(window, "isSmashed") then
            if not windowFlag(window, "isBarricaded") then Traversal.knockOutGlass(window, shell) end
            return false
        end
        if window:IsOpen() then return false end
        if windowFlag(window, "isBarricaded") then return false end
        if windowFlag(window, "isLocked") or windowFlag(window, "isPermaLocked") then
            Traversal.pathWhy(shell, "window_locked")
            return false, "window_locked"
        end
        Traversal.pathWhy(shell, "window_closed")
        shell:faceThisObject(window)
        pcall(function() shell:openWindow(window) end)

        if not windowFlag(window, "IsOpen") then pcall(function() window:ToggleWindow(shell) end) end
        return windowFlag(window, "IsOpen"), "window_closed"
    end)
    if not ok then return false, "window_probe_failed" end
    return opened == true, reason
end

function Traversal.openDoorAhead(shell, target)
    if shell == nil or type(target) ~= "table" or Traversal.isBusy(shell) then
        return false
    end
    if type(Traversal.adapters.tryDoor) == "function" then
        local ok, opened, reason = pcall(Traversal.adapters.tryDoor, shell, target)
        return ok and opened == true, ok and reason or nil
    end
    local ok, opened, reason = pcall(function()
        local direction = Traversal.crossingDirection(shell, target)
        if direction == nil then return false end
        local square = shell:getSquare()
        if square == nil then return false end
        local nextSquare = square:getAdjacentSquare(direction)
        if nextSquare == nil then return false end

        local door = collidedDoor(shell) or directDoorBetween(square, nextSquare)
        if door == nil then return false end

        local alreadyOpen = door.IsOpen ~= nil and door:IsOpen() == true
        if alreadyOpen then return false end
        Traversal.unlockFromInside(shell, door, square)
        if not doorIsPassable(door, square) then return false, "door_blocked" end
        if Traversal.courtesyHolds(shell, door, square) then return false, "door_blocked" end
        if not openDoor(door, square, shell) then return false, "door_open_failed" end
        return true
    end)
    if not ok then return false, "door_probe_failed" end
    return opened == true, reason
end

local function nowMs()
    if type(Traversal.adapters.nowMs) == "function" then return Traversal.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function Traversal.nowMs() return nowMs() end

function Traversal.closesDoors()
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    if type(vars) == "table" and vars.Behavior_CloseDoors == false then return false end
    return Traversal.settings.closeDoors ~= false
end

function Traversal.doorSide(object, x, y)
    local squares = ProjectALife.DoorPolicy.doorwaySquares(object)
    if squares == nil or x == nil or y == nil then return nil end
    local a, b = squares[1], squares[2]
    local ax, ay, bx, by = a:getX(), a:getY(), b:getX(), b:getY()
    if ax == bx then return math.floor(y) >= math.max(ay, by) end
    return math.floor(x) >= math.max(ax, bx)
end

function Traversal.calmRecord(shell, object, from)
    if not Traversal.closesDoors() or from == nil or type(from.getX) ~= "function" then return nil end
    local side = Traversal.doorSide(object, from:getX(), from:getY())
    if side == nil then return nil end
    local actor = ProjectALife.DoorPolicy.actorOf(shell)
    local memory = actor ~= nil and type(actor.memory) == "table" and actor.memory or {}
    return { calm = true, side = side, actor = actor, group = memory.groupId or memory.outpostId }
end

function Traversal.noteOpened(shell, object, square, keyed, locked, from)
    local policy = ProjectALife.DoorPolicy
    if shell == nil or object == nil or policy == nil or type(policy.playersDoor) ~= "function" then
        return false
    end

    local calm = nil
    if not policy.playersDoor(object, keyed) and not Traversal.ownSiteObject(shell, object) then
        calm = Traversal.calmRecord(shell, object, from)
        if calm == nil then return false end
    end
    local queue = Traversal.shutQueue
    if queue[object] == nil then
        if Traversal.shutCount >= Traversal.settings.shutLimit then
            Traversal.count("doorsLeftOpen")
            return false
        end
        Traversal.shutCount = Traversal.shutCount + 1
    end
    local now = nowMs()
    local record = { shell = shell, square = square, keyed = keyed == true,
        afterMs = now + Traversal.settings.shutAfterMs, deadlineAtMs = now + Traversal.settings.shutDeadlineMs }
    if calm ~= nil then
        calm.shell, calm.square, calm.afterMs = shell, square, record.afterMs
        calm.deadlineAtMs = now + Traversal.settings.closeDeadlineMs
        record = calm
    end
    queue[object] = record
    return true
end

Traversal.busyKinds = { combat = true, retreat = true, reaction = true, recovering = true }
Traversal.busyWords = { "attack", "engage", "hunt", "chase", "pursu", "flee", "retreat", "withdraw",
    "panic", "kite", "escape", "rescue", "fight" }

function Traversal.shellBusy(shell)
    if shell == nil or type(shell.getModData) ~= "function" then return true end
    if type(shell.isDead) == "function" and shell:isDead() == true then return true end
    if type(shell.isDraggingCorpse) == "function" and shell:isDraggingCorpse() == true then return true end
    if type(shell.isPerformingGrappleAnimation) == "function" and shell:isPerformingGrappleAnimation() == true then
        return true
    end
    local data = shell:getModData()
    if type(data) ~= "table" then return true end
    if Traversal.busyKinds[tostring(data.ProjectALifeBehaviorState)] == true then return true end
    local intent = string.lower(tostring(data.ProjectALifeBehaviorIntent or ""))
    for index = 1, #Traversal.busyWords do
        if string.find(intent, Traversal.busyWords[index], 1, true) ~= nil then return true end
    end
    return false
end

function Traversal.calmHolds(object, record)
    local now = nowMs()
    if record.calmUntilMs ~= nil and now >= record.calmCheckedMs and now < record.calmUntilMs then
        return record.calmVerdict == true
    end
    local held = Traversal.calmScan(object, record)
    record.calmVerdict, record.calmCheckedMs, record.calmUntilMs = held, now, now + 500
    return held
end

function Traversal.calmScan(object, record)
    if Traversal.shellBusy(record.shell) then return true end
    local policy = ProjectALife.DoorPolicy
    local squares = policy.doorwaySquares(object)
    if squares == nil then return true end
    local cx = (squares[1]:getX() + squares[2]:getX()) / 2 + 0.5
    local cy = (squares[1]:getY() + squares[2]:getY()) / 2 + 0.5
    local s = Traversal.settings
    local near = s.closePlayerTiles * s.closePlayerTiles
    local players = policy.players()
    for index = 1, #players do
        local px, py = tonumber(policy.ask(players[index], "getX")), tonumber(policy.ask(players[index], "getY"))
        if px ~= nil and py ~= nil and policy.ask(players[index], "isDead") ~= true
                and (px - cx) * (px - cx) + (py - cy) * (py - cy) <= near then
            return true
        end
    end
    local cell = type(getCell) == "function" and getCell() or nil
    if cell == nil or type(cell.getZombieList) ~= "function" then return true end
    local bodies = cell:getZombieList()
    if bodies == nil or type(bodies.size) ~= "function" then return true end
    local threat, group = s.closeThreatTiles * s.closeThreatTiles, s.closeGroupTiles * s.closeGroupTiles
    local relations = ProjectALife.Relations
    for index = 0, bodies:size() - 1 do
        local body = bodies:get(index)
        if body ~= nil and body ~= record.shell and not (type(body.isDead) == "function" and body:isDead() == true) then
            local bx, by = body:getX(), body:getY()
            local d = (bx - cx) * (bx - cx) + (by - cy) * (by - cy)
            if d <= threat then
                local data = type(body.hasModData) == "function" and body:hasModData() and body:getModData() or nil
                if type(data) ~= "table" or (data.ProjectALifeOwned ~= true and data.ProjectALifeActor ~= true) then
                    return true
                end
                local other = policy.actorOf(body)
                local memory = other ~= nil and type(other.memory) == "table" and other.memory or {}
                if record.group ~= nil and (memory.groupId or memory.outpostId) == record.group then
                    if d <= group and Traversal.doorSide(object, bx, by) == record.side then return true end
                elseif other ~= nil and record.actor ~= nil and relations ~= nil and type(relations.hostile) == "function"
                        and relations.hostile(record.actor, other) == true then
                    return true
                end
            end
        end
    end
    return false
end

function Traversal.squareHoldsBody(square)
    if square == nil or square.getMovingObjects == nil then return false end
    local movers = square:getMovingObjects()
    return movers ~= nil and movers.size ~= nil and movers:size() > 0
end

function Traversal.doorwayClear(object, shell)
    local squares = ProjectALife.DoorPolicy.doorwaySquares(object)
    if squares == nil then return false end
    local x, y = nil, nil
    if shell ~= nil and type(shell.getX) == "function" and type(shell.getY) == "function" then
        x, y = math.floor(shell:getX()), math.floor(shell:getY())
    end
    for index = 1, #squares do
        local square = squares[index]
        if Traversal.squareHoldsBody(square) then return false end
        if x ~= nil and x == square:getX() and y == square:getY() then return false end
    end
    return true
end

function Traversal.shutDoor(object, square)
    local grouped = Traversal.toggleGroup(object)
    local home = square
    if not grouped then
        if type(object.ToggleDoorSilent) ~= "function" or not pcall(object.ToggleDoorSilent, object) then
            return false
        end
        home = Traversal.settleLeaf(object, square)
    end
    Traversal.doorSound(object, home)
    return ProjectALife.DoorPolicy.ask(object, "IsOpen") ~= true
end

function Traversal.shutBehind(now)
    local policy = ProjectALife.DoorPolicy
    if policy == nil then return 0 end
    local shut = 0
    for object, record in pairs(Traversal.shutQueue) do
        local done = true
        if not Traversal.objectLoaded(object) then
            Traversal.count("doorsLeftOpen")
        elseif policy.ask(object, "IsOpen") == true and policy.ask(object, "isBarricaded") ~= true then
            if now >= record.deadlineAtMs then
                Traversal.count("doorsLeftOpen")
            elseif now < record.afterMs or not Traversal.doorwayClear(object, record.shell)
                    or (record.calm == true and Traversal.calmHolds(object, record)) then
                done = false
            elseif Traversal.shutDoor(object, record.square) then
                Traversal.count("doorsShut")
                shut = shut + 1
            else
                Traversal.count("doorsLeftOpen")
            end
        end
        if done then
            Traversal.shutQueue[object] = nil
            Traversal.shutCount = math.max(0, Traversal.shutCount - 1)
        end
    end
    return shut
end

local function setVariable(shell, name, value)
    local ok = pcall(function() shell:SetVariable(name, tostring(value)) end)
    if not ok then pcall(function() shell:setVariable(name, tostring(value)) end) end
end

function Traversal.damage(base)
    return (tonumber(base) or 0) * (tonumber(Traversal.settings.breachStrengthPercent) or 100) / 100
end
function Traversal.swingsNeeded(base)
    local percent = math.max(25, tonumber(Traversal.settings.breachStrengthPercent) or 100)
    return math.max(1, math.floor((tonumber(base) or 1) * 100 / percent + 0.5))
end

local function windowBreachImpact(shell, entry)

    entry.windowSwings = (entry.windowSwings or 0) + 1
    if entry.windowSwings < Traversal.swingsNeeded(Traversal.settings.breachSwingsPerWindow) then
        return false
    end

    local struck = pcall(function() entry.target:smashWindow(false, false) end)
    if not struck then
        struck = pcall(function() entry.target:smashWindow() end)
    end
    if not struck then return false end
    local readable, smashed = pcall(function() return entry.target:isSmashed() end)
    playSoundFrom(shell, "SmashWindow")
    return not readable or smashed == true
end

local function breachAnimation(shell, entry)
    if entry.kind == "window" then return "breach_window" end
    local carry = ""
    pcall(function()
        carry = string.lower(tostring(shell:getModData().ProjectALifeWeaponClass or ""))
    end)
    if carry == "handgun" then return "shove_handgun" end
    if carry == "rifle" then return "shove_rifle" end
    if carry == "spear" then return "combat_spear_a" end
    if carry == "melee2h" then return "combat_2h_c" end
    if carry == "melee" or carry == "knife" then return "combat_melee" end
    return "combat_unarmed"
end

function Traversal.faceBreach(shell, entry, now)
    if entry.faceAtMs ~= nil and now >= entry.faceAtMs and now - entry.faceAtMs < 100 then return end
    entry.faceAtMs = now
    local square = entry.target:getSquare()
    if square == nil then return end
    local x, y = square:getX() + 0.5, square:getY() + 0.5
    if entry.target.getNorth ~= nil then
        if entry.target:getNorth() then y = y - 0.5 else x = x - 0.5 end
    end
    local fence = ProjectALife.AIFence
    if fence ~= nil and type(fence.faceAimPoint) == "function" then
        fence.faceAimPoint(shell, x, y, now)
    else
        shell:faceLocationF(x, y)
    end
end

local function beginBreachSwing(shell, entry, now)

    pcall(function()
        local animations = ProjectALife.Animations
        if animations ~= nil then animations.apply(shell, breachAnimation(shell, entry)) end
    end)

    local beat = Traversal.settings.breachImpactMs
    entry.impactAtMs = now + (entry.kind == "window" and beat or beat + 60)
    entry.nextSwingAtMs = entry.impactAtMs
end

function Traversal.metalBarricade(object)
    local metal = false
    pcall(function()
        metal = (object.isMetal ~= nil and object:isMetal() == true)
            or (object.isMetalBar ~= nil and object:isMetalBar() == true)
    end)
    return metal
end

function Traversal.integrityOf(entry, metal)
    if entry.kind == "barricade" and not metal then
        return Traversal.swingsNeeded(Traversal.settings.breachSwingsPerPlank), 1
    end
    local health, source = 0, nil
    local policy = ProjectALife.DoorPolicy
    if entry.kind ~= "barricade" and policy ~= nil and type(policy.strength) == "function" then
        health, source = policy.strength(entry.target, Traversal.settings.breachUnreadFloor)
    else
        pcall(function() health = tonumber(entry.target:getHealth()) or 0 end)
    end
    if entry.kind == "barricade" then
        return health, Traversal.damage(Traversal.settings.breachPlankDamage)
    end
    return health, Traversal.damage(Traversal.settings.breachObjectDamage), source
end

function Traversal.blowSound(shell)
    local sound
    pcall(function()
        local weapons = ProjectALife.Weapons
        local weapon = weapons ~= nil and weapons.current(shell) or nil
        if weapon ~= nil and weapon.getDoorHitSound ~= nil then sound = weapon:getDoorHitSound() end
    end)
    if type(sound) ~= "string" or sound == "" then sound = "ZombieThumpGeneric" end
    return sound
end

function Traversal.breakSound(entry, metal)
    if entry.kind == "barricade" then
        return metal and "BreakBarricadeMetal" or "BreakBarricadePlank"
    end
    local prefix
    pcall(function()
        if entry.target.getSoundPrefix ~= nil then prefix = entry.target:getSoundPrefix() end
    end)
    if type(prefix) == "string" and prefix ~= "" then return prefix .. "Break" end
    return "BreakDoor"
end

function Traversal.giveWay(entry, metal)
    local target = entry.target
    if entry.kind == "barricade" then
        local cleared = false
        pcall(function()
            if metal then
                if target.isMetal ~= nil and target:isMetal() == true then
                    target:removeMetal(nil)
                else
                    target:removeMetalBar(nil)
                end
                cleared = true
            else
                target:removePlank(nil)
                cleared = (tonumber(target:getNumPlanks()) or 0) <= 0
            end
        end)
        return cleared
    end
    local grouped = false
    if IsoDoor ~= nil then
        pcall(function()
            grouped = IsoDoor.destroyDoubleDoor ~= nil and IsoDoor.destroyDoubleDoor(target) == true
        end)
        if not grouped then
            pcall(function()
                grouped = IsoDoor.destroyGarageDoor ~= nil and IsoDoor.destroyGarageDoor(target) == true
            end)
        end
    end
    if grouped then return true end
    return pcall(function() target:destroy() end) == true
end

function Traversal.noteIntegrity(shell, entry)
    local blackBox = ProjectALife.BlackBox
    if blackBox == nil or not blackBox.enabled or type(blackBox.note) ~= "function" then return false end
    pcall(blackBox.note, shell, "trav-integrity", tostring(entry.kind) .. " " .. tostring(entry.integrity)
        .. " from=" .. tostring(entry.integritySource or "-") .. " cost=" .. tostring(entry.integrityCost))
    return true
end

local function breachImpact(shell, entry)
    if not Traversal.objectLoaded(entry.target) then return true end
    if Traversal.ownSiteObject(shell, entry.target) then return true end
    if entry.kind == "window" then
        return windowBreachImpact(shell, entry)
    end
    local target = entry.target
    local metal = entry.kind == "barricade" and Traversal.metalBarricade(target)
    if entry.integrity == nil then
        entry.integrity, entry.integrityCost, entry.integritySource = Traversal.integrityOf(entry, metal)
        pcall(function()
            local left = tonumber(target:getModData().ProjectALifeBreachLeft)
            if left ~= nil and left < entry.integrity then entry.integrity = left end
        end)
        Traversal.noteIntegrity(shell, entry)
    end
    local crew = ProjectALife.MeleeCrew
    local scale = crew ~= nil and type(crew.breachScale) == "function" and crew.breachScale(shell) or 1
    entry.integrity = entry.integrity - entry.integrityCost * scale
    if entry.integrity > 0 then
        playSoundFrom(shell, Traversal.blowSound(shell))
        pcall(function() target:getModData().ProjectALifeBreachLeft = entry.integrity end)
        return false
    end
    entry.integrity = nil
    pcall(function() target:getModData().ProjectALifeBreachLeft = nil end)
    playSoundFrom(shell, Traversal.breakSound(entry, metal))
    return Traversal.giveWay(entry, metal)
end

local function breachCleared(entry)

    if not Traversal.objectLoaded(entry.target) then return true end
    if entry.kind == "door" and windowFlag(entry.target, "IsOpen") then return true end
    if entry.kind == "window" and (windowFlag(entry.target, "IsOpen")
            or windowFlag(entry.target, "isSmashed")) then return true end
    if entry.target.getObjectIndex ~= nil and entry.target:getObjectIndex() < 0 then return true end
    return false
end

local function breachSwing(shell, entry, now)
    if breachCleared(entry) then return true end
    if entry.impactAtMs == nil then
        beginBreachSwing(shell, entry, now)
        return false
    end
    if now < entry.impactAtMs then return false end
    entry.impactAtMs = nil

    entry.nextSwingAtMs = now + Traversal.settings.breachRecoverMs
    return breachImpact(shell, entry)
end

local releaseForClimb

function Traversal.forceRefusal(shell, object)
    local breaching = ProjectALife.Breaching
    if breaching == nil or type(breaching.refusal) ~= "function" then return nil end
    local ok, reason = pcall(breaching.refusal, shell, object)
    if ok and type(reason) == "string" then return reason end
    return nil
end

function Traversal.breachAllowed(shell, object)
    local policy = ProjectALife.DoorPolicy
    if policy == nil or type(policy.breachAllowed) ~= "function" then return true end
    return policy.breachAllowed(shell, object) ~= false
end

function Traversal.lockedWindowAllowed(shell, window)
    local policy, breaching, relations = ProjectALife.DoorPolicy, ProjectALife.Breaching, ProjectALife.Relations
    if policy == nil or type(policy.actorOf) ~= "function" then return false end
    local actor = policy.actorOf(shell)
    if type(actor) ~= "table" then return false end
    local raid = breaching ~= nil and type(breaching.motive) == "function"
        and breaching.motive(actor, nowMs()) == "raid"
    local hostile = relations ~= nil and type(relations.hostileToPlayer) == "function"
        and relations.hostileToPlayer(actor, nil) == true
    if not raid and not hostile then return false end
    local registry = ProjectALife.ModuleRegistry
    if registry == nil or type(registry.allows) ~= "function" or not registry.allows(actor, "doorstack") then
        return false
    end
    return type(policy.mayBreach) == "function" and policy.mayBreach(shell, window, "key") == true
end

function Traversal.refuseCourteously(shell, edge)
    Traversal.count("courteousRefusals")
    local square, nextSquare
    if type(edge) == "table" then
        square, nextSquare = edge.square, edge.nextSquare
    else
        square, nextSquare = Traversal.trySquare, Traversal.tryNext
    end
    if shell == nil or square == nil or nextSquare == nil then return nil end
    local now = nowMs()
    Traversal.keepOut(shell, square, nextSquare, now)
    return Traversal.markOpening(shell, Traversal.edgeKey(square, nextSquare), "courteous", now)
end

function Traversal.buildingOf(square)
    if square == nil or type(square.getBuilding) ~= "function" then return nil end
    return square:getBuilding()
end

function Traversal.keepOut(shell, square, nextSquare, now)
    local building = Traversal.buildingOf(nextSquare)
    if shell == nil or building == nil or building == Traversal.buildingOf(square) then return end
    if Traversal.invitedAt(shell, nextSquare) then return end
    Traversal.keptOut[shell] = { building = building, untilMs = (tonumber(now) or nowMs()) + Traversal.settings.keptOutMs }
end

function Traversal.keptOutOf(shell, building, now)
    local record = shell ~= nil and building ~= nil and Traversal.keptOut[shell] or nil
    return record ~= nil and record.building == building and (tonumber(now) or nowMs()) < record.untilMs
end

function Traversal.uninvitedVisit(shell, square)
    local policy = ProjectALife.DoorPolicy
    local actor = policy ~= nil and type(policy.actorOf) == "function" and policy.actorOf(shell) or nil
    if actor == nil or type(actor.memory) ~= "table" or type(actor.memory.visit) ~= "table" then return false end
    return not Traversal.invitedAt(shell, square, actor)
end

function Traversal.invitedAt(shell, square, actor)
    local policy = ProjectALife.DoorPolicy
    if shell == nil or square == nil or policy == nil or type(policy.invitedAt) ~= "function"
            or type(square.getX) ~= "function" or type(square.getY) ~= "function" then return false end
    if actor == nil and type(policy.actorOf) == "function" then actor = policy.actorOf(shell) end
    if actor == nil then return false end
    return policy.invitedAt(actor, square:getX(), square:getY()) == true
end

function Traversal.invitedThrough(shell, object)
    if object == nil or type(object.getSquare) ~= "function" then return false end
    return Traversal.invitedAt(shell, object:getSquare())
end

function Traversal.forgiveCourtesy(shell)
    if shell == nil then return false end
    Traversal.keptOut[shell] = nil
    local fails = Traversal.openingFails[shell]
    if type(fails) == "table" then
        for key, mark in pairs(fails) do
            if type(mark) == "table" and mark.why == "courteous" then fails[key] = nil end
        end
    end
    return true
end

function Traversal.baseEntryKeptOut(shell, square, nextSquare)
    local policy = ProjectALife.DoorPolicy
    if shell == nil or policy == nil or type(policy.baseEntryRefused) ~= "function" then return false end
    return policy.baseEntryRefused(shell, square, nextSquare) == true
end

function Traversal.enteringKeptOut(shell, square, nextSquare, now)
    if shell == nil then return false end
    local building = Traversal.buildingOf(nextSquare)
    if building == nil or building == Traversal.buildingOf(square) then return false end
    if Traversal.uninvitedVisit(shell, nextSquare) then return true end
    if Traversal.baseEntryKeptOut(shell, square, nextSquare) then return true end
    if Traversal.keptOut[shell] == nil then return false end
    return Traversal.keptOutOf(shell, building, now)
end

function Traversal.doorKeptOut(shell, object, square)
    if shell == nil or object == nil then return false end
    local far = nil
    if type(object.getSquare) == "function" and type(object.getOppositeSquare) == "function" then
        far = object:getSquare()
        if far == square then far = object:getOppositeSquare() end
    end
    if Traversal.uninvitedVisit(shell, far) then return true end
    if far ~= nil and Traversal.baseEntryKeptOut(shell, square, far) then return true end
    if Traversal.keptOut[shell] == nil or far == nil then return false end
    return Traversal.enteringKeptOut(shell, square, far)
end

function Traversal.breachInRange(shell, object)
    if shell == nil or object == nil or object.getSquare == nil then return false end
    local square = object:getSquare()
    if square == nil then return false end
    local dx, dy = shell:getX() - (square:getX() + 0.5), shell:getY() - (square:getY() + 0.5)
    return math.abs(shell:getZ() - square:getZ()) < 0.5
        and dx * dx + dy * dy <= Traversal.settings.breachReach ^ 2
end

local function beginBreach(shell, object, kind)
    if not Traversal.objectLoaded(object) then return false, "obstacle_unloaded" end
    if not Traversal.breachInRange(shell, object) then return false, "breach_out_of_range" end
    local retryAt = Traversal.breachBans[object]
    if retryAt ~= nil and nowMs() < retryAt then return false, "breach_retry_cooldown" end
    if Traversal.ownSiteObject(shell, object) then return false, "own_outpost_reroute" end

    if object.IsOpen ~= nil and object:IsOpen() == true then return false, "already_open" end

    if kind == "barricade" and Traversal.tryWindow == true and Traversal.breachOutOfReach(object) then
        return false, "barricade_metal_reroute"
    end

    if not Traversal.breachAllowed(shell, object) then
        Traversal.refuseCourteously(shell)
        return false, "courteous_reroute"
    end

    local forced = Traversal.forceRefusal(shell, object)
    if forced ~= nil then return false, forced end

    local claimKey

    if object.getSquare ~= nil then
        local square = object:getSquare()
        if square ~= nil then
            claimKey = tostring(kind) .. ":" .. tostring(square:getX()) .. ":"
                .. tostring(square:getY()) .. ":" .. tostring(square:getZ())
        end
    end
    if claimKey ~= nil then
        local held = Traversal.breachClaims[claimKey]
        if held ~= nil and held.shell ~= shell and Traversal.active[held.shell] ~= nil
                and nowMs() - (tonumber(held.atMs) or 0) < Traversal.settings.breachDeadlineMs then
            return false, "breach_claimed"
        end
        Traversal.breachClaims[claimKey] = { shell = shell, atMs = nowMs() }
    end

    if ProjectALife.BlackBox ~= nil and ProjectALife.BlackBox.enabled then
        pcall(function()
            local blackBox = ProjectALife.BlackBox
            blackBox.note(shell, "trav-breach", tostring(kind) .. " " .. blackBox.describeObject(object)
                .. Traversal.edgeNote(Traversal.trySquare, Traversal.tryNext, object))
        end)
    end
    if releaseForClimb ~= nil then releaseForClimb(shell) end
    Traversal.active[shell] = {
        mode = "breach", target = object, kind = kind, claimKey = claimKey,
        square = Traversal.trySquare, nextSquare = Traversal.tryNext,
        deadlineAtMs = nowMs() + Traversal.settings.breachDeadlineMs, nextSwingAtMs = 0,
        impactAtMs = nil,
    }
    setVariable(shell, "ALifeTraversal", "breach")
    local plus = ProjectALife.BlackBoxPlus
    if plus ~= nil then pcall(plus.breach, shell, "start", kind, object, nil, nil) end
    Voice.play(shell, "BREACH", { context = { obstacle = kind } })
    return true
end
Traversal.beginBreach = beginBreach

local function getVariable(shell, name)
    if shell == nil or shell.GetVariable == nil then return nil end
    return shell:GetVariable(name)
end

local function clearVariable(shell, name)
    local ok = pcall(function() shell:ClearVariable(name) end)
    if not ok then pcall(function() shell:clearVariable(name) end) end
end

releaseForClimb = function(shell)

    pcall(function()
        local guard = ProjectALife.AIFence
        if guard ~= nil and type(guard.silenceTraversalAudio) == "function" then
            guard.silenceTraversalAudio(shell, true)
        end
    end)
    pcall(function()
        local behavior = shell:getPathFindBehavior2()
        if behavior ~= nil then
            behavior:cancel()
            pcall(function() behavior:reset() end)
        end
        pcall(function() shell:setPath2(nil) end)
        if ZombieIdleState ~= nil and PathFindState ~= nil
                and shell:getCurrentState() == PathFindState.instance() then
            shell:changeState(ZombieIdleState.instance())
        end
        shell:setMoving(false)
        pcall(function() shell:setVariable("bMoving", false) end)
        pcall(function() shell:setVariable("bPathfind", false) end)
    end)
    pcall(function()
        local movement = ProjectALife.Movement
        if movement ~= nil and type(movement.setPathActive) == "function" then
            movement.setPathActive(shell, false)
        else
            shell:getModData().ProjectALifePathActive = nil
        end
    end)

    pcall(function() Animations.cancelForLocomotion(shell) end)
end

local function neutralizeRunningVault(shell)

    pcall(function() shell:setRunning(false) end)
    pcall(function() shell:setSprinting(false) end)
    pcall(function() shell:ClearVariable("VaultOverRun") end)
    pcall(function() shell:ClearVariable("VaultOverSprint") end)
end

local function releaseReservation(shell, key)
    if shell == nil or key == nil then return end
    local lease = Traversal.reservations[key]
    if lease ~= nil and lease.owner == shell then
        Traversal.reservations[key] = nil
    end
end

function Traversal.releaseClimbAction(shell, fence, window)
    if shell == nil or type(shell.setVariable) ~= "function" then return false end
    pcall(function()
        if fence == true then shell:setVariable("ClimbFenceFinished", true) end
        if window == true then shell:setVariable("ClimbWindowFinished", true) end
    end)
    return true
end

local function leaveNativeState(shell)
    local stateOk, current = pcall(function() return shell:getCurrentState() end)
    local climbFence = stateOk and ClimbOverFenceState ~= nil
        and current == ClimbOverFenceState.instance()
    local climbWindow = stateOk and ClimbThroughWindowState ~= nil
        and current == ClimbThroughWindowState.instance()

    pcall(function()

        if shell.getActionStateName == nil then return end
        local name = string.lower(tostring(shell:getActionStateName() or ""))
        if name == "climbfence" then climbFence = true end
        if name == "climbwindow" then climbWindow = true end
    end)
    for _, name in ipairs({
        "ClimbingFence", "ClimbFenceStarted", "ClimbFenceFinished",
        "ClimbFenceOutcome", "ClimbFenceFlopped", "ClimbWindowStarted",
        "ClimbWindowEnd", "ClimbWindowFinished", "ClimbWindowOutcome",
        "ClimbWindowFlopped", "VaultOverRun", "VaultOverSprint", "BlockWindow",
    }) do clearVariable(shell, name) end
    if climbFence or climbWindow then

        pcall(function()
            shell:setVariable("ClimbFenceStarted", true)
            shell:setVariable("ClimbFenceFinished", true)
            shell:setVariable("ClimbWindowStarted", true)
            shell:setVariable("ClimbWindowFinished", true)
            shell:setVariable("ClimbingFence", false)
        end)
        if ZombieIdleState ~= nil then

            pcall(function() shell:changeState(ZombieIdleState.instance()) end)
        end
        Traversal.releaseClimbAction(shell, climbFence, climbWindow)

        pcall(function()
            local data = shell:getModData()
            if type(data) == "table" then data.ProjectALifeClimbSinceMs = nil end
        end)
    end
    pcall(function() shell:setIgnoreMovement(false) end)
    pcall(function() shell:setHideWeaponModel(false) end)

    setVariable(shell, "bPathfind", false)
    setVariable(shell, "bMoving", false)

    pcall(function() shell:resetModelNextFrame() end)
end

local function finish(shell, success, reason)

    local bannedKey
    if (reason == "native_timeout" or reason == "native_no_crossing")
            and Traversal.interrupted(shell, Traversal.active[shell]) then

        reason = "native_interrupted"
        Traversal.count("interrupted")
    end
    if reason == "native_timeout" or reason == "native_no_crossing" then
        pcall(function()
            local entry = Traversal.active[shell]
            local recent = Traversal.lastCrossing[shell]

            if entry ~= nil and entry.nativeKind == "fence"
                    and recent ~= nil and recent.banKey ~= nil
                    and nowMs() - (tonumber(recent.atMs) or 0) < 10000 then
                Traversal.edgeBans[recent.banKey] = nowMs() + 60000
                Traversal.noteBanOrigin(recent.banKey, shell, reason)
                bannedKey = recent.banKey
            end

            if entry ~= nil and entry.edgeKey ~= nil and entry.nativeKind == "window" then
                bannedKey = Traversal.windowStrike(shell, entry.edgeKey, reason, nowMs())
            elseif entry ~= nil and entry.edgeKey ~= nil then
                Traversal.edgeBans[entry.edgeKey] = nowMs() + 60000
                Traversal.noteBanOrigin(entry.edgeKey, shell, reason)
                bannedKey = entry.edgeKey
            end
        end)
    end
    local entry = Traversal.active[shell]
    if entry ~= nil and entry.mode == "breach" then
        if reason == "breach_timeout" then
            Traversal.breachBans[entry.target] = nowMs() + Traversal.settings.breachRetryMs
        end
        local plus = ProjectALife.BlackBoxPlus
        if plus ~= nil then pcall(plus.breach, shell, "finish", entry.kind, entry.target, reason, success) end
    end
    if success == true then
        Traversal.windowTouch[shell] = nil
    elseif entry ~= nil then
        Traversal.noteFinishFailure(shell, entry, reason)
    end
    if ProjectALife.BlackBox ~= nil and ProjectALife.BlackBox.enabled then
        pcall(function()
            ProjectALife.BlackBox.note(shell, "trav-end", tostring(success) .. " "
                .. tostring(reason) .. " mode="
                .. tostring(entry and entry.mode)
                .. " edge=" .. tostring(entry and entry.edgeKey)
                .. (bannedKey ~= nil and (" ban=60000 banned=" .. tostring(bannedKey)) or ""))
        end)
    end

    if entry ~= nil and entry.adopted == true and success ~= true then
        releaseForClimb(shell)
    end

    leaveNativeState(shell)
    Animations.clear(shell)
    setVariable(shell, "ALifeTraversal", "")
    if entry ~= nil then releaseReservation(shell, entry.crossingKey) end
    if entry ~= nil and entry.claimKey ~= nil then Traversal.breachClaims[entry.claimKey] = nil end
    Traversal.active[shell] = nil
    Traversal.results[shell] = { success = success == true, reason = reason }

    Traversal.lockoutUntilMs[shell] = nowMs() + 1500

    Traversal.forgetEdge(shell)

    pcall(function() shell:resetModelNextFrame() end)
    pcall(function()
        local data = shell:getModData()
        data.ProjectALifeLastTraversalResult = success == true and "success" or "failed"
        data.ProjectALifeLastTraversalReason = tostring(reason or "unknown")
        data.ProjectALifeLastTraversalAtMs = nowMs()
    end)
end

local function tallBoundary(square, nextSquare, direction)
    local ok, object = pcall(function()
        if direction == IsoDirections.N then return square:getHoppableWall(true) end
        if direction == IsoDirections.S then return nextSquare:getHoppableWall(true) end
        if direction == IsoDirections.W then return square:getHoppableWall(false) end
        if direction == IsoDirections.E then return nextSquare:getHoppableWall(false) end
        return nil
    end)
    if not ok or object == nil then return nil end
    local tallOk, tall = pcall(function() return object:isTallHoppable() end)
    return tallOk and tall == true and object or nil
end

local function reachedSquare(shell, entry)
    if shell == nil or entry == nil then return false end
    local current = shell.getCurrentSquare ~= nil and shell:getCurrentSquare() or nil
    if current == nil then
        if shell.getSquare == nil then return false end
        current = shell:getSquare()
    end
    if current == nil then return false end
    if current == entry.destination then return true end
    if entry.destX == nil or current.getX == nil or current.getY == nil then return false end
    local okX, x = pcall(current.getX, current)
    local okY, y = pcall(current.getY, current)
    return okX and okY and x == entry.destX and y == entry.destY
end

local function nativeClimbActive(shell)
    if shell == nil then return false end
    if shell.getActionStateName ~= nil then
        local name = string.lower(tostring(shell:getActionStateName() or ""))
        if name == "climbfence" then return true, "fence" end
        if name == "climbwindow" then return true, "window" end
    end
    if shell.getCurrentState == nil then return false end
    local state = shell:getCurrentState()
    if ClimbOverFenceState ~= nil and state == ClimbOverFenceState.instance() then
        return true, "fence"
    end
    if ClimbThroughWindowState ~= nil and state == ClimbThroughWindowState.instance() then
        return true, "window"
    end
    return false, nil
end

function Traversal.holdsClimb(shell)
    local entry = shell ~= nil and Traversal.active[shell] or nil
    if entry == nil or entry.mode ~= "native" then return false end
    if type(shell.isDead) == "function" and shell:isDead() == true then return false end
    if nowMs() >= (tonumber(entry.deadlineAtMs) or 0) then return false end
    return nativeClimbActive(shell) == true
end

Traversal.climbRefusedAtMs = setmetatable({}, { __mode = "k" })
function Traversal.refuseNative(shell)
    if shell == nil then return false end
    local active, kind = nativeClimbActive(shell)
    if not active then return false end

    local edgeKey = Traversal.nativeEdgeKey(shell)
    if kind ~= "window" and not Traversal.fenceAt(shell, edgeKey) then edgeKey = nil end
    leaveNativeState(shell)
    Traversal.active[shell] = nil
    Traversal.climbRefusedAtMs[shell] = nowMs()
    local fresh = Traversal.noteRefusal(shell, "posted", edgeKey, Traversal.climbRefusedAtMs[shell], true)

    if kind == "window" and edgeKey ~= nil then
        Traversal.noteWindowFailure(shell, "scavenge_window_excluded", edgeKey, nowMs())
    end
    Traversal.metrics = Traversal.metrics or {}
    if fresh then
        Traversal.metrics.nativeRefused = (Traversal.metrics.nativeRefused or 0) + 1
        local blackBox = ProjectALife.BlackBox
        if blackBox ~= nil and blackBox.enabled then
            pcall(blackBox.note, shell, "trav-refuse", "native climb cut: posted")
        end
    end
    return true, edgeKey
end

function Traversal.fenceAt(shell, edgeKey)
    local x1, y1, x2, y2, z = Traversal.edgeEnds(edgeKey)
    if x1 == nil or shell == nil or shell.getX == nil or shell.getY == nil or type(getCell) ~= "function" then
        return false
    end
    local x, y = math.floor(shell:getX()), math.floor(shell:getY())
    if not ((x == x1 and y == y1) or (x == x2 and y == y2)) then return false end
    local cell = getCell()
    local a = cell ~= nil and cell:getGridSquare(x1, y1, z) or nil
    local b = cell ~= nil and cell:getGridSquare(x2, y2, z) or nil
    if a == nil or b == nil or type(a.isHoppableTo) ~= "function" or type(b.isHoppableTo) ~= "function" then
        return false
    end
    return a:isHoppableTo(b) == true or b:isHoppableTo(a) == true
end

function Traversal.pathWhy(shell, why)
    if shell == nil then return nil end
    local record = Traversal.refusals[shell]
    if record == nil then
        record = { streak = 0 }
        Traversal.refusals[shell] = record
    end
    record.pathWhy, record.pathWhyAtMs = why, nowMs()
    Traversal.metrics.pathWhy = why
    local movement = ProjectALife.Movement
    if movement ~= nil and type(movement.pathWhy) == "function" then
        movement.pathWhy(shell, why)
    elseif type(shell.getModData) == "function" then
        local data = shell:getModData()
        if type(data) == "table" then data.ProjectALifePathWhy = why end
    end
    local entry = Traversal.active[shell]
    if entry ~= nil then entry.pathWhy = why end
    return why
end

function Traversal.noteRefusal(shell, kind, edgeKey, now, stamped)
    if shell == nil then return false end
    now = tonumber(now) or nowMs()
    local record = Traversal.refusals[shell]
    if record == nil then
        record = { streak = 0 }
        Traversal.refusals[shell] = record
    end
    local fresh = record.kind ~= kind or record.edgeKey ~= edgeKey
        or record.lastAtMs == nil or now - record.lastAtMs > Traversal.settings.refusalRepeatMs
    if kind ~= "impassable" or record.edgeKey ~= edgeKey or record.kind ~= kind then
        record.impassableSinceMs, record.impassableX, record.impassableY = nil, nil, nil
    end
    if kind == "impassable" and record.impassableSinceMs == nil then
        record.impassableSinceMs = now
        record.impassableX, record.impassableY = shell:getX(), shell:getY()
    end
    if fresh then
        if record.kind == kind and record.edgeKey == edgeKey and record.atMs ~= nil
                and now - record.atMs < 10000 then
            record.streak = (record.streak or 0) + 1
        else
            record.streak = 1
        end
        record.atMs = now
    end
    record.kind, record.edgeKey, record.lastAtMs = kind, edgeKey, now
    if stamped then
        if fresh or record.stampKind ~= kind then record.stampHandled = nil end
        record.stampKind, record.stampEdgeKey = kind, edgeKey
        record.stampAtMs = Traversal.climbRefusedAtMs[shell]
    end
    return fresh, record
end

function Traversal.lastRefusal(shell)
    local record = shell ~= nil and Traversal.refusals[shell] or nil
    if record == nil or record.kind == nil then return nil end
    return record.kind, record.lastAtMs, record.edgeKey
end

function Traversal.stampedRefusal(shell)
    local record = shell ~= nil and Traversal.refusals[shell] or nil
    local at = shell ~= nil and Traversal.climbRefusedAtMs[shell] or nil
    if record == nil or at == nil or record.stampAtMs ~= at then return nil end
    return record
end

function Traversal.leaseHeld(shell, edgeKey, now)
    local lease = edgeKey ~= nil and Traversal.reservations[edgeKey] or nil
    return type(lease) == "table" and lease.owner ~= shell
        and (tonumber(now) or 0) < (tonumber(lease.untilMs) or 0)
end

function Traversal.climbRefusedRecently(shell, now, holdMs)
    local at = shell ~= nil and Traversal.climbRefusedAtMs[shell] or nil
    if at == nil then return false end
    now = tonumber(now) or 0
    local hold = tonumber(holdMs) or 0
    local record = Traversal.stampedRefusal(shell)
    if record ~= nil and record.stampKind == "queue" then
        if not Traversal.leaseHeld(shell, record.stampEdgeKey, now) then return false end
        hold = math.min(hold, Traversal.settings.queueHoldMs)
    elseif record ~= nil and record.stampKind == "occupied" then
        hold = math.min(hold, Traversal.settings.occupiedHoldMs)
    end
    return now - at < hold
end

function Traversal.queueHoldMs(shell, now, capMs)
    local record = Traversal.stampedRefusal(shell)
    if record == nil or record.stampKind ~= "queue" then return nil end
    if not Traversal.leaseHeld(shell, record.stampEdgeKey, now) then return 0 end
    return tonumber(capMs) or Traversal.settings.queueHoldMs
end

function Traversal.refusalWait(shell, now, readOnly)
    local record = Traversal.stampedRefusal(shell)
    if record == nil or record.stampHandled == true then return nil end
    now = tonumber(now) or 0
    local kind = record.stampKind
    if kind == "ban" then
        local ban = Traversal.shellBans[shell]
        if ban == nil or ban.why ~= "landing_occupied" or ban.key ~= record.stampEdgeKey then return nil end
        if now < (tonumber(ban.untilMs) or 0) then return "wait" end
    elseif kind == "queue" or kind == "occupied" then
        if Traversal.echoLive(shell, now)
                or Traversal.climbRefusedRecently(shell, now, Traversal.settings.queueHoldMs) then
            return "wait"
        end
    else
        return nil
    end
    if readOnly ~= true then record.stampHandled = true end
    return "resume"
end

function Traversal.settleRefusal(shell)
    local record = Traversal.stampedRefusal(shell)
    if record ~= nil then record.stampHandled = true end
end

function Traversal.echoLive(shell, now)
    local record = shell ~= nil and Traversal.refusals[shell] or nil
    local at = record ~= nil and record.nativeAtMs or nil
    return at ~= nil and (tonumber(now) or 0) - at <= Traversal.settings.readoptWindowMs
        and nativeClimbActive(shell) == true
end

function Traversal.shellBanned(shell, edgeKey, now)
    local ban = shell ~= nil and Traversal.shellBans[shell] or nil
    return ban ~= nil and edgeKey ~= nil and ban.key == edgeKey
        and (tonumber(now) or 0) < (tonumber(ban.untilMs) or 0)
end

function Traversal.uidOf(shell)
    if shell == nil or type(shell.getModData) ~= "function" then return nil end
    local ok, data = pcall(shell.getModData, shell)
    if not ok or type(data) ~= "table" then return nil end
    return data.ProjectALifeUID
end

function Traversal.noteBanOrigin(key, shell, why)
    Traversal.revision = (Traversal.revision or 0) + 1
    local blackBox = ProjectALife.BlackBox
    if key == nil or blackBox == nil or not blackBox.enabled then return end
    Traversal.edgeBanBy[key] = tostring(Traversal.uidOf(shell) or "?") .. " " .. tostring(why or "?")
end

Traversal.lastEdgeKey = setmetatable({}, { __mode = "k" })

local function facingDirection(shell)
    if IsoDirections == nil or shell == nil or type(shell.getDir) ~= "function" then return nil end
    local ok, direction = pcall(shell.getDir, shell)
    if not ok then return nil end
    if direction == IsoDirections.N or direction == IsoDirections.E
            or direction == IsoDirections.S or direction == IsoDirections.W then
        return direction
    end
    return nil
end
Traversal.facingDirection = facingDirection

local function nativeEdgeKey(shell)
    local key
    pcall(function()
        local square = shell:getSquare()
        if square == nil then return end
        local direction = facingDirection(shell) or collisionDirection(shell)
        local nextSquare = direction ~= nil and square:getAdjacentSquare(direction) or nil
        if nextSquare == nil then return end

        key = Traversal.edgeKey(square, nextSquare)
    end)
    if key ~= nil then
        Traversal.lastEdgeKey[shell] = key
        return key
    end
    return Traversal.lastEdgeKey[shell]
end
Traversal.nativeEdgeKey = nativeEdgeKey

function Traversal.nativeLanding(shell)
    if shell == nil or type(shell.getSquare) ~= "function" then return nil end
    local square = shell:getSquare()
    if square == nil or type(square.getAdjacentSquare) ~= "function" then return nil end
    local direction = facingDirection(shell) or collisionDirection(shell)
    if direction == nil then return nil end
    return square:getAdjacentSquare(direction), square, true, direction
end

function Traversal.edgeKeyToward(square, direction)
    if square == nil or direction == nil or IsoDirections == nil then return nil end
    local dx, dy = 0, 0
    if direction == IsoDirections.N then dy = -1
    elseif direction == IsoDirections.S then dy = 1
    elseif direction == IsoDirections.E then dx = 1
    elseif direction == IsoDirections.W then dx = -1
    else return nil end
    local okX, x = pcall(square.getX, square)
    local okY, y = pcall(square.getY, square)
    local okZ, z = pcall(square.getZ, square)
    if not (okX and okY and okZ) or tonumber(x) == nil or tonumber(y) == nil then return nil end
    local a = tostring(x) .. ":" .. tostring(y)
    local b = tostring(x + dx) .. ":" .. tostring(y + dy)
    if b < a then a, b = b, a end
    return a .. "|" .. b .. "@" .. tostring(z)
end

function Traversal.adoptedLandingRefusal(shell)

    local data = type(shell.getModData) == "function" and shell:getModData() or nil
    local since = type(data) == "table" and tonumber(data.ProjectALifeClimbSinceMs) or nil
    if since ~= nil and nowMs() - since > Traversal.settings.landingCheckMs then return nil end
    local landing, square, known, direction = Traversal.nativeLanding(shell)
    if not known then return nil end
    if landing == nil then
        local z = square ~= nil and type(square.getZ) == "function" and tonumber(square:getZ()) or 0
        if (z or 0) >= 1 then return "drop", Traversal.edgeKeyToward(square, direction) end
        return nil
    end

    if Traversal.dropLanding(landing) then return "drop", Traversal.edgeKey(square, landing) end
    local reason = Traversal.landingRefusal(landing)
    if reason == "climb_landing_occupied" then return "occupied" end

    if reason == "climb_landing_blocked_reroute" and Traversal.landingStatic(landing) then
        return "blocked", Traversal.edgeKey(square, landing)
    end
    return nil
end

function Traversal.adoptedEntryRefusal(shell)
    local data = type(shell.getModData) == "function" and shell:getModData() or nil
    local since = type(data) == "table" and tonumber(data.ProjectALifeClimbSinceMs) or nil
    if since ~= nil and nowMs() - since > Traversal.settings.landingCheckMs then return nil end
    local landing, square = Traversal.nativeLanding(shell)
    if landing == nil or square == nil then return nil end
    local opening = nil
    if type(square.getWindowTo) == "function" then opening = square:getWindowTo(landing) end
    if opening == nil and type(square.getWindowFrameTo) == "function" then opening = square:getWindowFrameTo(landing) end
    if opening == nil and type(square.getWindowThumpableTo) == "function" then
        opening = square:getWindowThumpableTo(landing)
    end
    if opening == nil or not Traversal.entryCourtesyHolds(shell, opening, square, landing) then return nil end
    local key = Traversal.edgeKey(square, landing)
    Traversal.count("courteousEntries")
    Traversal.markOpening(shell, key, "courteous", nowMs())
    return key
end

function Traversal.rememberCut(shell, entry, caller)
    if shell == nil or entry == nil then return end
    local cut = Traversal.cuts[shell]
    if cut == nil then
        cut = {}
        Traversal.cuts[shell] = cut
    end
    cut.edgeKey, cut.nativeKind = entry.edgeKey, entry.nativeKind
    cut.startedAtMs, cut.deadlineAtMs = entry.startedAtMs, entry.deadlineAtMs
    cut.startX, cut.startY, cut.startZ = entry.startX, entry.startY, entry.startZ
    cut.atMs, cut.caller, cut.live = nowMs(), caller, true
end

function Traversal.cutFor(shell, edgeKey, now)
    local cut = shell ~= nil and Traversal.cuts[shell] or nil
    if cut == nil or cut.live ~= true then return nil end
    if (tonumber(now) or 0) - (tonumber(cut.atMs) or 0) > Traversal.settings.readoptWindowMs then
        cut.live = false
        return nil
    end
    if edgeKey ~= nil and cut.edgeKey ~= nil and edgeKey ~= cut.edgeKey then return nil end
    return cut
end

function Traversal.inheritCut(entry, cut)
    entry.startedAtMs = cut.startedAtMs or entry.startedAtMs
    entry.deadlineAtMs = cut.deadlineAtMs or entry.deadlineAtMs
    entry.startX = cut.startX or entry.startX
    entry.startY = cut.startY or entry.startY
    entry.startZ = cut.startZ or entry.startZ
    entry.interrupted = true
    cut.live = false
    Traversal.count("readopted")
end

function Traversal.interrupted(shell, entry)
    if entry == nil then return false end
    if entry.interrupted == true then return true end
    local started = tonumber(entry.startedAtMs)
    if started == nil or shell == nil or type(shell.getModData) ~= "function" then return false end
    local data = shell:getModData()
    local hit = type(data) == "table" and tonumber(data.ProjectALifeLastHitAtMs) or nil
    return hit ~= nil and hit >= started
end

Traversal.climbLog = setmetatable({}, { __mode = "k" })
Traversal.climbBudget = 3
Traversal.climbWindowMs = 15000
Traversal.climbPenaltyMs = 20000
function Traversal.noteClimb(shell, now)
    if shell == nil then return 0 end
    now = tonumber(now) or nowMs()
    local log = Traversal.climbLog[shell]
    if log == nil or now - log.sinceMs > Traversal.climbWindowMs then
        log = { sinceMs = now, count = 0 }
        Traversal.climbLog[shell] = log
    end

    log.count = log.count + 1
    return log.count
end
function Traversal.climbOverBudget(shell, now)
    local log = shell ~= nil and Traversal.climbLog[shell] or nil
    if log == nil then return false end
    now = tonumber(now) or nowMs()
    if now - log.sinceMs > Traversal.climbWindowMs + Traversal.climbPenaltyMs then return false end
    return log.count > Traversal.climbBudget
end

local function reserveEdge(shell, key)
    if key == nil then return true end
    local now = nowMs()
    local lease = Traversal.reservations[key]
    local mine = shell
    if lease ~= nil and lease.owner ~= mine and now < lease.untilMs then return false end
    Traversal.reservations[key] = { owner = mine, untilMs = now + 9000 }
    return true
end

function Traversal.refusedEcho(shell, edgeKey, now)
    local record = Traversal.refusals[shell]
    local at = record ~= nil and record.nativeAtMs or nil
    if at == nil then return false end
    if now - at > Traversal.settings.readoptWindowMs
            or (edgeKey ~= nil and record.nativeEdgeKey ~= nil and edgeKey ~= record.nativeEdgeKey) then
        record.nativeAtMs = nil
        return false
    end
    if record.nativeRelease == true then releaseForClimb(shell) end
    leaveNativeState(shell)
    record.lastAtMs = now
    return true
end

function Traversal.adoptNative(shell)
    if shell == nil or Traversal.active[shell] ~= nil then return false end
    local active, kind = nativeClimbActive(shell)
    if not active then

        local record = Traversal.refusals[shell]
        if record ~= nil then record.nativeAtMs = nil end
        return false
    end

    local edgeKey = nativeEdgeKey(shell)
    if Traversal.refusedEcho(shell, edgeKey, nowMs()) then return false end

    local lockout = Traversal.lockoutUntilMs[shell]
    local lockedOut = lockout ~= nil and nowMs() < lockout

    local cut = Traversal.cutFor(shell, edgeKey, nowMs())
    local banned = edgeKey ~= nil and ((Traversal.edgeBans[edgeKey] or 0) > nowMs()
        or Traversal.shellBanned(shell, edgeKey, nowMs())
        or Traversal.openingFailed(shell, edgeKey, nowMs()))

    local overBudget = cut == nil and Traversal.climbOverBudget(shell, nowMs())

    local occupied = false
    if cut == nil and not (lockedOut or banned or overBudget) then
        local landing, landingKey = Traversal.adoptedLandingRefusal(shell)
        occupied = landing == "occupied"
        if landing == "drop" then

            if landingKey ~= nil then
                edgeKey = landingKey
                Traversal.banShell(shell, edgeKey, Traversal.settings.dropBanMs, "landing_drop")
            end
            banned = true
        elseif landing == "blocked" then
            edgeKey = landingKey or edgeKey
            Traversal.noteWindowFailure(shell, kind == "fence" and "fence_obstacle" or "window_obstacle",
                edgeKey, nowMs())
            banned = true
        elseif kind == "window" then
            local entryKey = Traversal.adoptedEntryRefusal(shell)
            if entryKey ~= nil then
                edgeKey = entryKey
                banned = true
            end
        end
    end

    local taken = false
    if not (lockedOut or banned or overBudget or occupied) then
        taken = not reserveEdge(shell, edgeKey)
    end
    if lockedOut or banned or overBudget or occupied or taken then

        if not lockedOut then
            releaseForClimb(shell)
            Traversal.climbRefusedAtMs[shell] = nowMs()
        end
        leaveNativeState(shell)
        local refusal = "queue"
        if lockedOut then refusal = "locked"
        elseif banned then refusal = "ban"
        elseif overBudget then refusal = "budget"
        elseif occupied then refusal = "occupied" end

        local fresh, record = Traversal.noteRefusal(shell, refusal, edgeKey, nowMs(), not lockedOut)

        record.nativeAtMs, record.nativeEdgeKey, record.nativeRelease = nowMs(), edgeKey, not lockedOut
        if not fresh then return false end

        if banned then Traversal.askReplan(shell, edgeKey, nowMs()) end
        Traversal.metrics = Traversal.metrics or {}
        if lockedOut then
            Traversal.metrics.nativeLockedOut = (Traversal.metrics.nativeLockedOut or 0) + 1
        elseif taken then

            Traversal.metrics.edgeQueued = (Traversal.metrics.edgeQueued or 0) + 1
        elseif occupied then
            Traversal.metrics.nativeOccupied = (Traversal.metrics.nativeOccupied or 0) + 1
            Traversal.occupiedStreak(shell, edgeKey, record)
        elseif banned then
            Traversal.metrics.nativeBanned = (Traversal.metrics.nativeBanned or 0) + 1
        else
            Traversal.metrics.nativeBudget = (Traversal.metrics.nativeBudget or 0) + 1
        end

        if lockedOut then return false end
        Traversal.noteRefusalOnce(shell, refusal, edgeKey)
        return false
    end
    if cut == nil then Traversal.noteClimb(shell, nowMs()) end
    Traversal.settleRefusal(shell)

    pcall(Animations.cancelForLocomotion, shell)
    neutralizeRunningVault(shell)
    local timeout = kind == "window" and Traversal.settings.nativeWindowTimeoutMs
        or Traversal.settings.nativeFenceTimeoutMs
    local startX, startY, startZ
    pcall(function()
        startX, startY, startZ = shell:getX(), shell:getY(), shell:getZ()
    end)
    Traversal.active[shell] = {
        mode = "native", nativeKind = kind, adopted = true,
        startX = startX, startY = startY, startZ = startZ,

        edgeKey = edgeKey, crossingKey = edgeKey,

        startedAtMs = nowMs(),
        deadlineAtMs = nowMs() + timeout,
    }
    if cut ~= nil then Traversal.inheritCut(Traversal.active[shell], cut) end
    if kind == "window" then Traversal.touchWindow(shell, edgeKey, nowMs()) end
    setVariable(shell, "ALifeTraversal", kind)
    local blackBox = ProjectALife.BlackBox
    if blackBox ~= nil and blackBox.enabled then
        pcall(Traversal.noteAdopt, shell, kind, edgeKey, cut ~= nil)
    end
    return true
end

function Traversal.noteRefusalOnce(shell, refusal, edgeKey)
    local blackBox = ProjectALife.BlackBox
    if blackBox == nil or not blackBox.enabled then return false end
    local noteKey = refusal .. ":" .. tostring(edgeKey) .. "#" .. tostring(Traversal.uidOf(shell))
    Traversal.refusalNotedAtMs = Traversal.refusalNotedAtMs or {}
    local noted = Traversal.refusalNotedAtMs
    if (noted[noteKey] or 0) + 10000 <= nowMs() then
        if (Traversal.refusalNotedCount or 0) >= 256 then
            Traversal.refusalNotedAtMs, Traversal.refusalNotedCount = {}, 0
            noted = Traversal.refusalNotedAtMs
        end
        if noted[noteKey] == nil then Traversal.refusalNotedCount = (Traversal.refusalNotedCount or 0) + 1 end
        noted[noteKey] = nowMs()
        pcall(Traversal.noteRefusalLine, shell, refusal, edgeKey)
        return true
    end
    return false
end

function Traversal.noteAdopt(shell, kind, edgeKey, readopted)
    local blackBox = ProjectALife.BlackBox
    if blackBox == nil or not blackBox.enabled then return end
    blackBox.note(shell, "trav-adopt", tostring(kind) .. " edge=" .. tostring(edgeKey)
        .. (readopted and " readopted" or "") .. " " .. Traversal.describeEdgeKey(edgeKey))
end

function Traversal.occupiedStreak(shell, edgeKey, record)
    if edgeKey == nil or record == nil
            or (record.streak or 0) < Traversal.settings.occupiedStreak then
        return false
    end
    Traversal.banShell(shell, edgeKey, Traversal.settings.occupiedBanMs, "landing_occupied")
    record.streak = 0
    record.kind, record.stampKind = "ban", "ban"
    Traversal.count("occupiedBans")
    return true
end

function Traversal.banShell(shell, edgeKey, ms, why)
    if shell == nil or edgeKey == nil then return end
    local ban = Traversal.shellBans[shell]
    if ban == nil then
        ban = {}
        Traversal.shellBans[shell] = ban
    end
    ban.key, ban.untilMs, ban.why = edgeKey, nowMs() + (tonumber(ms) or 0), why
end

function Traversal.edgeEnds(key)
    if type(key) ~= "string" then return nil end
    local x1, y1, x2, y2, z = string.match(key, "^(%-?%d+):(%-?%d+)|(%-?%d+):(%-?%d+)@?(%-?%d*)$")
    if x1 == nil then return nil end
    return tonumber(x1), tonumber(y1), tonumber(x2), tonumber(y2), tonumber(z) or 0
end

Traversal.hopAccessors = { "getHoppableTo", "getHoppableThumpableTo", "getWallHoppableTo" }
function Traversal.describeEdgeKey(edgeKey)
    local blackBox = ProjectALife.BlackBox
    if blackBox == nil or not blackBox.enabled then return "" end
    local ok, text = pcall(Traversal.describeEdgeRaw, edgeKey)
    return ok and tostring(text) or "landing=?"
end

function Traversal.describeEdgeRaw(edgeKey)
    local blackBox = ProjectALife.BlackBox
    local x1, y1, x2, y2, z = Traversal.edgeEnds(edgeKey)
    if x1 == nil or type(getCell) ~= "function" then return "" end
    local cell = getCell()
    if cell == nil then return "" end
    local a, b = cell:getGridSquare(x1, y1, z), cell:getGridSquare(x2, y2, z)
    if a == nil or b == nil then return "landing=unloaded" end
    local parts = {}
    for index = 1, #Traversal.hopAccessors do
        local name = Traversal.hopAccessors[index]
        for side = 1, 2 do
            local from, to = a, b
            if side == 2 then from, to = b, a end
            local method = from[name]
            if type(method) == "function" then
                local ok, object = pcall(method, from, to)
                if ok and object ~= nil then
                    parts[#parts + 1] = name .. "=" .. tostring(blackBox.describeObject(object))
                end
            end
        end
    end
    parts[#parts + 1] = x1 .. ":" .. y1 .. "=[" .. Traversal.objectsOn(a) .. "]"
    parts[#parts + 1] = x2 .. ":" .. y2 .. "=[" .. Traversal.objectsOn(b) .. "]"
    return table.concat(parts, " ")
end

function Traversal.objectsOn(square)
    if square == nil or type(square.getObjects) ~= "function" then return "?" end
    local objects = square:getObjects()
    if objects == nil or type(objects.size) ~= "function" then return "" end
    local names = {}
    for index = 0, math.min(objects:size(), 8) - 1 do
        local object = objects:get(index)
        local name = "?"
        if object ~= nil and type(object.getSprite) == "function" then
            local sprite = object:getSprite()
            if sprite ~= nil and type(sprite.getName) == "function" then name = tostring(sprite:getName()) end
        end
        if object ~= nil and type(object.getProperties) == "function" then
            local properties = object:getProperties()
            if properties ~= nil and type(properties.get) == "function" then
                local ok, movement = pcall(properties.get, properties, "Movement")
                if ok and movement ~= nil and movement ~= "" then name = name .. "(" .. tostring(movement) .. ")" end
            end
        end
        names[#names + 1] = name
    end
    return table.concat(names, ",")
end

function Traversal.noteRefusalLine(shell, kind, edgeKey)
    local blackBox = ProjectALife.BlackBox
    if blackBox == nil or not blackBox.enabled then return end
    local now = nowMs()
    local key = tostring(edgeKey)
    local detail
    if kind == "queue" then
        local lease = edgeKey ~= nil and Traversal.reservations[edgeKey] or nil
        local left = lease ~= nil and math.max(0, (tonumber(lease.untilMs) or now) - now) or 0
        detail = "edge held by another: " .. key .. " holder="
            .. tostring(lease ~= nil and Traversal.uidOf(lease.owner) or "?") .. " lease=" .. left .. "ms"
    elseif kind == "ban" then
        local personal = Traversal.shellBanned(shell, edgeKey, now)
        local ban = Traversal.shellBans[shell]
        local untilMs = personal and ban.untilMs or (tonumber(Traversal.edgeBans[edgeKey]) or now)
        local by = personal and ("self " .. tostring(ban.why)) or tostring(Traversal.edgeBanBy[edgeKey] or "?")
        detail = "edge banned: " .. key .. " by=" .. by
            .. " left=" .. math.floor(math.max(0, untilMs - now) / 1000) .. "s"
    elseif kind == "budget" then
        local log = Traversal.climbLog[shell]
        detail = "climb budget spent: " .. tostring(log ~= nil and log.count or "?") .. "/"
            .. tostring(Traversal.climbBudget) .. " edge=" .. key
    elseif kind == "occupied" then
        detail = "landing occupied: " .. key
    else
        detail = tostring(kind) .. " " .. key
    end
    blackBox.note(shell, "trav-" .. tostring(kind), detail .. " " .. Traversal.describeEdgeKey(edgeKey))
end

local function unstableLanding(shell)
    local unstable = false
    pcall(function()
        unstable = shell:isOnFloor() == true or shell:isKnockedDown() == true
            or shell:isProne() == true or shell:isCrawling() == true
    end)
    return unstable
end

function Traversal.configure(adapters)
    Traversal.adapters = adapters or {}
end

function Traversal.reset()
    Traversal.active = setmetatable({}, { __mode = "k" })
    Traversal.results = setmetatable({}, { __mode = "k" })
    Traversal.breachBans = setmetatable({}, { __mode = "k" })
    Traversal.lockoutUntilMs = setmetatable({}, { __mode = "k" })
    Traversal.lastCrossing = setmetatable({}, { __mode = "k" })

    Traversal.climbLog = setmetatable({}, { __mode = "k" })
    Traversal.climbRefusedAtMs = setmetatable({}, { __mode = "k" })
    Traversal.lastEdgeKey = setmetatable({}, { __mode = "k" })
    Traversal.reservations = {}

    Traversal.edgeBans = {}
    Traversal.breachClaims = {}
    Traversal.refusalNotedAtMs, Traversal.refusalNotedCount = {}, 0
    Traversal.sweptAtMs = nil
    Traversal.refusals, Traversal.cuts, Traversal.shellBans = {}, {}, {}
    Traversal.edgeBanBy = {}
    Traversal.detours, Traversal.detourCount = {}, 0
    Traversal.routes, Traversal.routeCount = {}, 0
    Traversal.routeSearch, Traversal.revision = { atMs = 0, used = 0 }, 0
    Traversal.openingFails, Traversal.windowTouch = {}, {}
    Traversal.replanPending, Traversal.edgeStrikes = {}, {}
    Traversal.shutQueue, Traversal.shutCount = {}, 0
    Traversal.lockSearch, Traversal.lockWays, Traversal.keptOut = {}, {}, {}
    Traversal.windowOpening = setmetatable({}, { __mode = "k" })
    Traversal.metrics.pathWhy = "none"
end

Traversal.lockoutUntilMs = setmetatable({}, { __mode = "k" })
Traversal.lastCrossing = setmetatable({}, { __mode = "k" })

Traversal.reservations = {}

function Traversal.edgeKey(square, nextSquare)
    local key
    pcall(function()
        local a = tostring(square:getX()) .. ":" .. tostring(square:getY())
        local b = tostring(nextSquare:getX()) .. ":" .. tostring(nextSquare:getY())
        if b < a then a, b = b, a end
        key = a .. "|" .. b
    end)
    if key == nil then return nil end
    local floor = ""
    pcall(function() floor = "@" .. tostring(square:getZ()) end)
    return key .. floor
end

local function reserveCrossing(shell, square, nextSquare)
    local key = Traversal.edgeKey(square, nextSquare)
    if key == nil then return true, nil end
    local now = nowMs()
    local lease = Traversal.reservations[key]
    local mine = shell
    if lease ~= nil and lease.owner ~= mine and now < lease.untilMs then
        return false, key
    end
    Traversal.reservations[key] = { owner = mine, untilMs = now + 9000 }
    return true, key
end

function Traversal.dropLanding(square)
    if square == nil or type(square.getZ) ~= "function" then return false end
    if (tonumber(square:getZ()) or 0) < 1 then return false end
    if type(square.TreatAsSolidFloor) ~= "function" then return false end
    local ok, solid = pcall(square.TreatAsSolidFloor, square)
    return ok and solid == false
end

function Traversal.landingWater(square)
    if square == nil or IsoFlagType == nil or type(square.getProperties) ~= "function" then return false end
    local properties = square:getProperties()
    return properties ~= nil and type(properties.has) == "function"
        and properties:has(IsoFlagType.water) == true
end

function Traversal.landingVehicle(square)
    return square ~= nil and type(square.getVehicleContainer) == "function"
        and square:getVehicleContainer() ~= nil
end

local function landingRefusal(square)
    if square == nil then return "climb_landing_blocked_reroute" end
    local blocked = false
    pcall(function()
        blocked = square:isSolid() == true
            or square:isSolidTrans() == true
            or square:HasStairs() == true
    end)
    if blocked or Traversal.landingWater(square) then return "climb_landing_blocked_reroute" end

    if Traversal.dropLanding(square) then return "climb_landing_drop_reroute" end
    if Traversal.landingVehicle(square) then return "climb_landing_vehicle_reroute" end
    local occupied = false
    pcall(function()
        occupied = square:isFree(false) == true
            and square:isFree(true) ~= true
    end)
    if occupied then return "climb_landing_occupied" end
    pcall(function() blocked = square:isFree(true) ~= true end)
    if blocked then return "climb_landing_blocked_reroute" end
    return nil
end
Traversal.landingRefusal = landingRefusal

function Traversal.openingRefusal(shell, square, nextSquare, now)
    local reason = landingRefusal(nextSquare)
    if reason ~= nil then return reason end
    local key = Traversal.edgeKey(square, nextSquare)
    if key ~= nil and (Traversal.edgeBans[key] or 0) > now then
        return "edge_banned_reroute"
    end
    if Traversal.openingFailed(shell, key, now) then return "opening_failed_reroute" end
    if Traversal.climbOverBudget(shell, now) then return "climb_budget_reroute" end
    return nil
end

function Traversal.beginNative(shell, kind, square, nextSquare, reservationKey)
    local now = nowMs()
    local entry = {
        mode = "native_pending", destination = nextSquare, nativeKind = kind,
        startDeadlineAtMs = now + Traversal.settings.nativeStartGraceMs,
        startedAtMs = now,
        crossingKey = reservationKey,
        edgeKey = Traversal.edgeKey(square, nextSquare),
        deadlineAtMs = now + (kind == "fence"
            and Traversal.settings.nativeFenceTimeoutMs
            or Traversal.settings.nativeWindowTimeoutMs),
    }
    pcall(function() entry.destX, entry.destY = nextSquare:getX(), nextSquare:getY() end)
    pcall(function()
        entry.startX, entry.startY, entry.startZ = shell:getX(), shell:getY(), shell:getZ()
    end)
    Traversal.active[shell] = entry

    Traversal.noteClimb(shell, now)
    Traversal.settleRefusal(shell)
    return entry
end

function Traversal.ownSiteObject(shell, object)
    local owned = false
    pcall(function()
        local data = shell:getModData()
        local uid = type(data) == "table" and data.ProjectALifeUID or nil
        local actors = ProjectALife.ActorRegistry
        local actor = uid ~= nil and actors ~= nil and type(actors.read) == "function" and actors.read(uid) or nil
        local memory = actor ~= nil and type(actor.memory) == "table" and actor.memory or nil
        if memory == nil or memory.outpostSquadId ~= nil or type(memory.outpostId) ~= "string" then return end
        local sites = ProjectALife.OutpostRegistry
        local site = sites ~= nil and type(sites.read) == "function" and sites.read(memory.outpostId) or nil

        local bounds = site ~= nil and site.bounds or memory.garrisonBounds
        if type(bounds) ~= "table" then return end
        local square = object:getSquare()
        if square == nil then return end
        local x, y = square:getX(), square:getY()
        owned = x >= bounds.x1 - 1 and x <= bounds.x2 + 1 and y >= bounds.y1 - 1 and y <= bounds.y2 + 1
    end)
    return owned
end

function Traversal.dismantle(barricade, object)
    local removed = 0
    pcall(function()
        for _ = 1, 12 do
            local planks = tonumber(barricade:getNumPlanks()) or 0
            if planks > 0 then
                barricade:removePlank(nil)
                removed = removed + 1
            elseif barricade.isMetal ~= nil and barricade:isMetal() then
                barricade:removeMetal(nil)
                removed = removed + 1
                break
            elseif barricade.isMetalBar ~= nil and barricade:isMetalBar() then
                barricade:removeMetalBar(nil)
                removed = removed + 1
                break
            else
                break
            end
        end
    end)
    pcall(function()
        if object ~= nil then object:getModData().ProjectALifeOwnWay = true end
    end)
    Traversal.metrics = Traversal.metrics or {}
    Traversal.metrics.dismantled = (Traversal.metrics.dismantled or 0) + 1
    return removed
end

function Traversal.try(shell, target, doorsOnly, replans)

    local lockout = shell ~= nil and Traversal.lockoutUntilMs[shell] or nil
    if lockout ~= nil and nowMs() < lockout then
        return false, "traversal_lockout"
    end

    if shell ~= nil then
        local contact
        pcall(function()
            local perception = ProjectALife.Perception
            if perception ~= nil and type(perception.contactThreat) == "function" then
                contact = perception.contactThreat(shell)
            end
        end)
        if contact ~= nil then return false, "traversal_contact_blocked" end
    end
    if type(Traversal.adapters.try) == "function" then
        local ok, result = pcall(Traversal.adapters.try, shell, target, doorsOnly)
        return ok and result == true
    end
    if shell == nil or type(target) ~= "table" then return false end

    local pendingReservationKey
    local function abandonReservation(key)
        releaseReservation(shell, key)
        if pendingReservationKey == key then pendingReservationKey = nil end
    end

    Traversal.trySquare, Traversal.tryNext, Traversal.tryWindow = nil, nil, nil
    local ok, crossed, reason = pcall(function()
        local direction = Traversal.crossingDirection(shell, target)
        if direction == nil then return false end
        local square = shell:getSquare()
        if square == nil then return false end
        local nextSquare = square:getAdjacentSquare(direction)
        if nextSquare == nil then return false end

        Traversal.trySquare, Traversal.tryNext = square, nextSquare
        if Traversal.baseEntryKeptOut(shell, square, nextSquare) then return Traversal.refuseEntry(shell) end

        local door = collidedDoor(shell) or closedDoorBetween(square, nextSquare)
        if door ~= nil then

            local doorOpen = false
            pcall(function() doorOpen = door:IsOpen() == true end)
            if ProjectALife.BlackBox ~= nil and ProjectALife.BlackBox.enabled then
                pcall(function()
                    local blackBox = ProjectALife.BlackBox
                    blackBox.note(shell, "trav-door", blackBox.describeObject(door)
                        .. Traversal.edgeNote(square, nextSquare, door))
                end)
            end
            if doorOpen then return false, nil end
            if Traversal.doorObstructed(door) then
                return false, "door_obstructed_reroute"
            end
            Traversal.unlockFromInside(shell, door, square)
            if not doorIsPassable(door, square) then

                local barricade = barricadeOf(door)
                if barricade ~= nil then

                    if Traversal.ownSiteObject(shell, door) then
                        return false, "own_outpost_reroute"
                    end
                    return beginBreach(shell, barricade, "barricade")
                end

                local locked = false
                pcall(function() locked = door:isLocked() == true
                    or door:isLockedByKey() == true end)

                local stealthSystem = ProjectALife.Stealth
                if locked and stealthSystem ~= nil
                        and stealthSystem.canPick(shell)
                        and Traversal.breachAllowed(shell, door)
                        and Traversal.forceRefusal(shell, door) == nil then
                    pcall(function() shell:faceThisObject(door) end)

                    pcall(function()
                        local animations = ProjectALife.Animations
                        if animations ~= nil then
                            animations.apply(shell, "heal_bandage")
                        end
                    end)
                    Traversal.active[shell] = {
                        mode = "picking", target = door,
                        deadlineAtMs = nowMs()
                            + stealthSystem.settings.pickMs,
                    }
                    return true, "lock_picking"
                end

                local policy = ProjectALife.DoorPolicy
                if policy ~= nil then
                    local at = nowMs()
                    if replans == true
                            and Traversal.siblingReroute(shell, door, square, nextSquare, at, doorsOnly) then
                        return false, "door_sibling_reroute"
                    end
                    return Traversal.lockedDoor(shell, door, square, nextSquare, target, doorsOnly, at, replans)
                end
                return beginBreach(shell, door, "door")
            end
            if Traversal.courtesyHolds(shell, door, square) then
                Traversal.count("courteousDoors")
                Traversal.refuseCourteously(shell)
                return false, "courteous_reroute"
            end
            if Traversal.enteringKeptOut(shell, square, nextSquare) then return Traversal.refuseEntry(shell) end
            if not openDoor(door, square, shell) then
                return false, "door_open_failed"
            end

            return false, nil
        end

        local window = square:getWindowTo(nextSquare)
        if window ~= nil then
            Traversal.tryWindow = true
            if doorsOnly == true then return false, "scavenge_window_excluded" end
            if ProjectALife.BlackBox ~= nil and ProjectALife.BlackBox.enabled then
                pcall(function()
                    local blackBox = ProjectALife.BlackBox
                    blackBox.note(shell, "trav-window", blackBox.describeObject(window))
                end)
            end
            if Traversal.entryCourtesyHolds(shell, window, square, nextSquare) then
                return Traversal.refuseEntry(shell)
            end
            local reserved, reservationKey = reserveCrossing(shell, square, nextSquare)
            if not reserved then
                return false, "traversal_reserved_reroute"
            end
            pendingReservationKey = reservationKey
            local landingReason = Traversal.openingRefusal(shell, square, nextSquare, nowMs())
            if landingReason ~= nil then
                abandonReservation(reservationKey)
                return false, landingReason
            end
            local passable, windowReason, breachTarget = prepareWindow(window, shell)
            if not passable and windowReason == "breach" then
                abandonReservation(reservationKey)
                return beginBreach(shell, breachTarget, "barricade")
            end
            if not passable and windowReason == "breach_window" then
                abandonReservation(reservationKey)
                return beginBreach(shell, breachTarget, "window")
            end
            if not passable then
                abandonReservation(reservationKey)
                return false, windowReason
            end
            releaseForClimb(shell)
            neutralizeRunningVault(shell)
            if not Traversal.armClimb(shell, "window", window, square, nextSquare, reservationKey) then
                abandonReservation(reservationKey)
                return false, "window_climb_unavailable"
            end
            pendingReservationKey = nil
            return true
        end
        local frame = square:getWindowFrameTo(nextSquare)
        if frame ~= nil then
            Traversal.tryWindow = true
            if doorsOnly == true then return false, "scavenge_window_excluded" end
            if Traversal.entryCourtesyHolds(shell, frame, square, nextSquare) then
                return Traversal.refuseEntry(shell)
            end
            local reserved, reservationKey = reserveCrossing(shell, square, nextSquare)
            if not reserved then
                return false, "traversal_reserved_reroute"
            end
            pendingReservationKey = reservationKey
            local landingReason = Traversal.openingRefusal(shell, square, nextSquare, nowMs())
            if landingReason ~= nil then
                abandonReservation(reservationKey)
                return false, landingReason
            end

            if windowFlag(frame, "isBarricaded") then
                abandonReservation(reservationKey)
                local barricade = barricadeOf(frame)
                if barricade ~= nil then
                    return beginBreach(shell, barricade, "barricade")
                end
                return false, "window_barricaded_reroute"
            end
            releaseForClimb(shell)
            neutralizeRunningVault(shell)
            if not Traversal.armClimb(shell, "frame", frame, square, nextSquare, reservationKey) then
                abandonReservation(reservationKey)
                return false, "window_frame_climb_unavailable"
            end
            pendingReservationKey = nil
            return true
        end

        local thumpableWindow
        pcall(function()
            thumpableWindow = square:getWindowThumpableTo(nextSquare)
        end)
        if thumpableWindow ~= nil then
            Traversal.tryWindow = true
            if doorsOnly == true then return false, "scavenge_window_excluded" end
            if Traversal.entryCourtesyHolds(shell, thumpableWindow, square, nextSquare) then
                return Traversal.refuseEntry(shell)
            end
            local reserved, reservationKey = reserveCrossing(shell, square, nextSquare)
            if not reserved then
                return false, "traversal_reserved_reroute"
            end
            pendingReservationKey = reservationKey
            local landingReason = Traversal.openingRefusal(shell, square, nextSquare, nowMs())
            if landingReason ~= nil then
                abandonReservation(reservationKey)
                return false, landingReason
            end

            if windowFlag(thumpableWindow, "isBarricaded") then
                abandonReservation(reservationKey)
                local barricade = barricadeOf(thumpableWindow)
                if barricade ~= nil then
                    return beginBreach(shell, barricade, "barricade")
                end
                return false, "window_barricaded_reroute"
            end
            releaseForClimb(shell)
            neutralizeRunningVault(shell)
            if not Traversal.armClimb(shell, "window", thumpableWindow, square, nextSquare, reservationKey) then
                abandonReservation(reservationKey)
                return false, "window_climb_unavailable"
            end
            pendingReservationKey = nil
            return true
        end
        if tallBoundary(square, nextSquare, direction) ~= nil then
            return false, "tall_fence_unsupported_reroute"
        end
        local hoppable = square:getHoppableTo(nextSquare)
        if hoppable ~= nil then

            if doorsOnly == true then return false, "posted_no_climb" end
            local reserved, reservationKey = reserveCrossing(shell, square, nextSquare)
            if not reserved then
                return false, "traversal_reserved_reroute"
            end
            pendingReservationKey = reservationKey

            local landingReason = landingRefusal(nextSquare)
            if landingReason ~= nil then
                abandonReservation(reservationKey)

                Traversal.noteWindowFailure(shell, landingReason, Traversal.edgeKey(square, nextSquare),
                    nowMs(), nextSquare)
                return false, landingReason
            end

            local onStairs = false
            pcall(function()
                onStairs = square:HasStairs() == true
                    or nextSquare:HasStairs() == true
            end)
            if onStairs then
                abandonReservation(reservationKey)
                return false, "fence_on_stairs"
            end

            local crossKey
            pcall(function()
                crossKey = tostring(nextSquare:getX()) .. ":"
                    .. tostring(nextSquare:getY()) .. ">"
                    .. tostring(square:getX()) .. ":" .. tostring(square:getY())
            end)
            local recent = Traversal.lastCrossing[shell]
            if recent ~= nil and recent.key == crossKey
                    and nowMs() - recent.atMs < 6000 then
                abandonReservation(reservationKey)
                return false, "vault_pingpong_reroute"
            end

            local railing = false
            pcall(function()
                local hop = square:getHoppableTo(nextSquare)
                    or nextSquare:getHoppableTo(square)
                local sprite = hop and hop:getSprite()
                    and hop:getSprite():getName() or ""
                railing = string.find(tostring(sprite),
                    "fixtures_railings", 1, true) ~= nil
            end)
            if railing then
                abandonReservation(reservationKey)
                return false, "railing_reroute"
            end

            local banKey = Traversal.edgeKey(square, nextSquare)
            if banKey ~= nil and (Traversal.edgeBans[banKey] or 0) > nowMs() then
                abandonReservation(reservationKey)
                return false, "edge_banned_reroute"
            end

            if Traversal.climbOverBudget(shell, nowMs()) then
                abandonReservation(reservationKey)
                return false, "climb_budget_reroute"
            end
            releaseForClimb(shell)
            neutralizeRunningVault(shell)
            if ProjectALife.BlackBox ~= nil and ProjectALife.BlackBox.enabled then
                pcall(function()
                    local blackBox = ProjectALife.BlackBox
                    blackBox.note(shell, "trav-fence",
                        blackBox.describeObject(square:getHoppableTo(nextSquare)
                            or nextSquare:getHoppableTo(square)))
                end)
            end
            local climbOk, climbStarted = pcall(function()
                return shell:climbOverFence(direction)
            end)
            if not climbOk or climbStarted == false then
                abandonReservation(reservationKey)
                return false, "fence_climb_unavailable"
            end
            pcall(function()
                Traversal.lastCrossing[shell] = {
                    key = tostring(square:getX()) .. ":"
                        .. tostring(square:getY()) .. ">"
                        .. tostring(nextSquare:getX()) .. ":"
                        .. tostring(nextSquare:getY()),
                    banKey = banKey,
                    atMs = nowMs(),
                }
            end)
            Traversal.beginNative(shell, "fence", square, nextSquare, reservationKey)
            pendingReservationKey = nil
            return true
        end
        return false
    end)
    if not ok then
        Traversal.trySquare, Traversal.tryNext, Traversal.tryWindow = nil, nil, nil
        abandonReservation(pendingReservationKey)
        pcall(function()
            local data = shell:getModData()
            data.ProjectALifeLastTraversalResult = "failed"
            data.ProjectALifeLastTraversalReason = "traversal_exception"
            data.ProjectALifeLastTraversalError = tostring(crossed)
            data.ProjectALifeLastTraversalAtMs = nowMs()
        end)
        return false, "traversal_exception"
    end
    if crossed ~= true and reason ~= nil then Traversal.noteRouterRefusal(shell, reason) end
    if Traversal.tryWindow == true then Traversal.afterWindowTry(shell, crossed == true, reason) end
    Traversal.trySquare, Traversal.tryNext, Traversal.tryWindow = nil, nil, nil
    return crossed == true, crossed ~= true and reason or nil
end

Traversal.routerRefusalKinds = {
    traversal_reserved_reroute = "queue",
    climb_landing_occupied = "occupied",
    edge_banned_reroute = "ban",
    door_locked_reroute = "ban",
    climb_budget_reroute = "budget",
}
function Traversal.noteRouterRefusal(shell, reason)
    local kind = Traversal.routerRefusalKinds[reason]
    if shell == nil then return false end
    local edgeKey
    if Traversal.trySquare ~= nil and Traversal.tryNext ~= nil then
        edgeKey = Traversal.edgeKey(Traversal.trySquare, Traversal.tryNext)
    end
    if kind == nil then

        if Traversal.tryWindow == true and Traversal.windowFailReasons[reason] ~= nil then
            Traversal.noteRefusalOnce(shell, reason, edgeKey)
        end
        return false
    end
    local fresh = Traversal.noteRefusal(shell, kind, edgeKey, nowMs(), false)
    if fresh then Traversal.noteRefusalOnce(shell, kind, edgeKey) end
    return fresh
end

function Traversal.isBusy(shell)

    if shell ~= nil and Traversal.active[shell] == nil then
        Traversal.adoptNative(shell)
    end
    return shell ~= nil and Traversal.active[shell] ~= nil
end

function Traversal.forgetEdge(shell)
    if shell == nil then return end
    Traversal.lastEdgeKey[shell] = nil
end

function Traversal.consumeResult(shell)
    local result = shell and Traversal.results[shell] or nil
    if shell ~= nil then Traversal.results[shell] = nil end
    return result
end

function Traversal.noteTracked(shell, kind, detail)
    local blackBox = ProjectALife.BlackBox
    if blackBox == nil or not blackBox.enabled or type(blackBox.tracked) ~= "table"
            or blackBox.tracked[shell] == nil then
        return
    end
    pcall(blackBox.note, shell, kind, detail)
end

function Traversal.forget(shell, caller)
    if shell == nil then return false end
    local wasActive = Traversal.active[shell] ~= nil
    for key, lease in pairs(Traversal.reservations) do
        if lease.owner == shell then Traversal.reservations[key] = nil end
    end
    for key, claim in pairs(Traversal.breachClaims) do
        if claim.shell == shell then Traversal.breachClaims[key] = nil end
    end
    if wasActive then
        Traversal.noteTracked(shell, "trav-forget", tostring(caller or "?")
            .. " mode=" .. tostring(Traversal.active[shell].mode))
    end
    Traversal.active[shell] = nil
    Traversal.results[shell] = nil
    Traversal.lockoutUntilMs[shell] = nil
    Traversal.lastCrossing[shell] = nil
    Traversal.climbLog[shell] = nil
    Traversal.climbRefusedAtMs[shell] = nil
    Traversal.lastEdgeKey[shell] = nil
    Traversal.refusals[shell] = nil
    Traversal.cuts[shell] = nil
    Traversal.shellBans[shell] = nil
    Traversal.openingFails[shell] = nil
    Traversal.windowTouch[shell] = nil
    Traversal.replanPending[shell] = nil
    Traversal.lockSearch[shell] = nil
    Traversal.lockWays[shell] = nil
    Traversal.keptOut[shell] = nil
    Traversal.forgetBanOrigins(shell)
    return wasActive
end

function Traversal.forgetBanOrigins(shell)
    local origins = Traversal.edgeBanBy
    if type(origins) ~= "table" then return end
    local uid
    for key, origin in pairs(origins) do
        uid = uid or tostring(Traversal.uidOf(shell) or "?") .. " "
        if string.sub(tostring(origin), 1, #uid) == uid then origins[key] = nil end
    end
end

function Traversal.cancel(shell, caller)
    if shell == nil then return false end
    local wasActive = Traversal.active[shell] ~= nil
    local wasNative = nativeClimbActive(shell) == true
    local entry = Traversal.active[shell]
    if entry ~= nil then releaseReservation(shell, entry.crossingKey) end
    if entry ~= nil and entry.claimKey ~= nil then Traversal.breachClaims[entry.claimKey] = nil end

    if entry ~= nil and (entry.mode == "native" or entry.mode == "native_pending") then
        Traversal.rememberCut(shell, entry, caller)
    end
    Traversal.active[shell] = nil
    Traversal.results[shell] = nil
    if wasActive or wasNative then
        if wasNative then releaseForClimb(shell) end
        leaveNativeState(shell)
        Animations.clear(shell)
        setVariable(shell, "ALifeTraversal", "")
        Traversal.noteTracked(shell, "trav-cancel", tostring(caller or "?")
            .. " mode=" .. tostring(entry ~= nil and entry.mode or "native"))
    end
    return wasActive or wasNative
end

function Traversal.inClip(shell)
    if shell == nil then return false end
    local entry = Traversal.active[shell]
    if entry ~= nil then return entry.mode == "native" or entry.mode == "native_pending" end
    return nativeClimbActive(shell) == true
end

function Traversal.abortClip(shell, reason)
    if not Traversal.inClip(shell) then return false end
    Traversal.cancel(shell, reason or "abort_clip")
    if type(shell.resetModelNextFrame) == "function" then pcall(shell.resetModelNextFrame, shell) end
    Traversal.count("clipsAborted")
    return true
end

local function tickNative(shell, entry, now)
    local windowOutcome = string.lower(tostring(
        getVariable(shell, "ClimbWindowOutcome") or ""))
    local fenceOutcome = string.lower(tostring(
        getVariable(shell, "ClimbFenceOutcome") or ""))

    local failedOutcome =
        windowOutcome == "obstacle" or windowOutcome == "fall"
        or fenceOutcome == "obstacle" or fenceOutcome == "falling"
        or fenceOutcome == "fall"

    local active = nativeClimbActive(shell)

    local crossed = false
    if tonumber(entry.startX) ~= nil and tonumber(entry.startY) ~= nil
            and tonumber(entry.startZ) ~= nil and shell.getX ~= nil and shell.getY ~= nil
            and shell.getZ ~= nil then
        crossed = math.floor(shell:getX()) ~= math.floor(entry.startX)
            or math.floor(shell:getY()) ~= math.floor(entry.startY)
            or math.floor(shell:getZ()) ~= math.floor(entry.startZ)
    end
    local landed = (crossed or reachedSquare(shell, entry)) and not active
    if crossed and active then
        entry.crossedAtMs = entry.crossedAtMs or now
    elseif not crossed then
        entry.crossedAtMs = nil
    end
    if failedOutcome then
        finish(shell, false, fenceOutcome ~= "" and "fence_" .. fenceOutcome
            or "window_" .. windowOutcome)
    elseif landed then
        finish(shell, true, "native_complete")
    elseif not active then

        local cut
        pcall(function()
            local data = shell:getModData()
            if type(data) == "table" then
                cut = tonumber(data.ProjectALifeClimbCutAtMs)
            end
        end)
        local startedAt = tonumber(entry.startedAtMs)

        if cut ~= nil and startedAt ~= nil and cut >= startedAt then
            finish(shell, false, "native_cut")
        else
            finish(shell, false, "native_no_crossing")
        end
    elseif entry.crossedAtMs ~= nil
            and now - entry.crossedAtMs >= Traversal.settings.nativeLandedGraceMs then
        Traversal.count("crossedWedges")
        finish(shell, true, "native_complete")
    elseif now >= entry.deadlineAtMs then
        Traversal.count("nativeTimeouts")
        finish(shell, false, "native_timeout")
    end
end

function Traversal.heldBy(executor, shell)
    local uid = type(executor.byShell) == "table" and executor.byShell[shell] or nil
    return uid ~= nil and type(executor.executed) == "table" and type(executor.entryMatches) == "function"
        and executor.entryMatches(shell, uid, executor.executed[uid]) == true
end

function Traversal.tickShell(shell, now)
    local entry = Traversal.active[shell]
    if entry == nil then return 0 end
    local executor = ProjectALife.Executor
    if executor ~= nil and executor.clientAuthority()
            and executor.authorityFor(shell) ~= true then

        if not Traversal.heldBy(executor, shell) then Traversal.forget(shell) end
        return 0
    end
    now = now or nowMs()
    if entry.mode == "picking" then
        if not Traversal.objectLoaded(entry.target) then
            finish(shell, false, "lock_pick_unloaded")
        elseif shell.isDead ~= nil and shell:isDead() then
            finish(shell, false, "lock_pick_dead")
        elseif not Traversal.breachInRange(shell, entry.target) then
            finish(shell, false, "lock_pick_out_of_range")
        elseif now >= entry.deadlineAtMs then
            local stealthSystem = ProjectALife.Stealth
            local picked = stealthSystem ~= nil
                and stealthSystem.finishPick(shell, entry.target)
            finish(shell, picked == true,
                picked and "lock_picked" or "lock_pick_failed")
        end
    elseif entry.mode == "breach" then
        if breachCleared(entry) then
            finish(shell, true, "breach_complete")
        elseif not Traversal.breachAllowed(shell, entry.target) then
            Traversal.refuseCourteously(shell, entry)
            finish(shell, false, "courteous_reroute")
        elseif not Traversal.breachInRange(shell, entry.target) then
            finish(shell, false, "breach_out_of_range")
        elseif now >= entry.deadlineAtMs then
            finish(shell, false, "breach_timeout")
        else
            pcall(Traversal.faceBreach, shell, entry, now)
            if now >= (entry.nextSwingAtMs or 0) and breachSwing(shell, entry, now) then
                finish(shell, true, "breach_complete")
            end
        end
    elseif entry.mode == "native_pending" then
        if reachedSquare(shell, entry)
                and not nativeClimbActive(shell) then
            finish(shell, true, "native_complete")
        elseif nativeClimbActive(shell) then
            entry.mode = "native"
            entry.deadlineAtMs = now + (entry.nativeKind == "window"
                and Traversal.settings.nativeWindowTimeoutMs or Traversal.settings.nativeFenceTimeoutMs)
            tickNative(shell, entry, now)
        elseif now >= (entry.startDeadlineAtMs or now) then
            finish(shell, false, tostring(entry.nativeKind or "native")
                .. "_start_rejected")
        end
    elseif entry.mode == "native" then
        tickNative(shell, entry, now)
    elseif entry.mode == "native_arming" then
        Traversal.tickArming(shell, entry, now)
    elseif now >= entry.deadlineAtMs then
        finish(shell, false, "traversal_timeout")
    end
    return 1
end

function Traversal.tick(budget)

    local processed, now = 0, nowMs()
    for shell in pairs(Traversal.refusals) do Traversal.banImpassableHold(shell, now) end

    Traversal.sweptAtMs = Traversal.sweptAtMs or now
    if now - Traversal.sweptAtMs >= 60000 then
        Traversal.sweptAtMs = now
        for key, untilMs in pairs(Traversal.edgeBans) do
            if (tonumber(untilMs) or 0) <= now then Traversal.edgeBans[key] = nil end
        end
        for key in pairs(Traversal.edgeBanBy) do
            if Traversal.edgeBans[key] == nil then Traversal.edgeBanBy[key] = nil end
        end
        for shell, ban in pairs(Traversal.shellBans) do
            if now >= (tonumber(ban.untilMs) or 0) then Traversal.shellBans[shell] = nil end
        end
        for key, detour in pairs(Traversal.detours) do
            if now >= (tonumber(detour.untilMs) or 0) then Traversal.detours[key] = nil end
        end
        for key, lease in pairs(Traversal.reservations) do
            if type(lease) ~= "table" or now >= (tonumber(lease.untilMs) or 0) then
                Traversal.reservations[key] = nil
            end
        end
        for key, claim in pairs(Traversal.breachClaims) do
            if type(claim) ~= "table" or now - (tonumber(claim.atMs) or 0)
                    > Traversal.settings.breachDeadlineMs then
                Traversal.breachClaims[key] = nil
            end
        end
        Traversal.sweepWindows(now)
    end
    for shell in pairs(Traversal.active) do
        processed = processed + Traversal.tickShell(shell, now)
    end
    Traversal.shutBehind(now)
    return processed
end

function Traversal.detourFor(shell, edgeKey, doorsOnly)
    if shell == nil then return nil end
    if edgeKey == nil then
        local record = Traversal.refusals[shell]
        edgeKey = record ~= nil and record.edgeKey or nil
    end
    local x1, y1, x2, y2, z = Traversal.edgeEnds(edgeKey)
    if x1 == nil or type(shell.getX) ~= "function" or type(shell.getY) ~= "function" then return nil end
    local sx, sy = shell:getX(), shell:getY()
    local nx, ny, fx, fy = x1, y1, x2, y2
    if (sx - x2 - 0.5) ^ 2 + (sy - y2 - 0.5) ^ 2 < (sx - x1 - 0.5) ^ 2 + (sy - y1 - 0.5) ^ 2 then
        nx, ny, fx, fy = x2, y2, x1, y1
    end
    local now = nowMs()
    local climbs = doorsOnly ~= true and not Traversal.climbOverBudget(shell, now)
    local cacheKey = edgeKey .. ">" .. fx .. ":" .. fy .. (climbs and "" or "!")
    local cached = Traversal.detours[cacheKey]
    if cached ~= nil and now < (tonumber(cached.untilMs) or 0) then
        if cached.none then return nil end
        return cached.x, cached.y, cached.z
    end
    local wx, wy = Traversal.searchDetour(shell, edgeKey, nx, ny, fx, fy, z, climbs, now)
    local untilMs = tonumber(Traversal.edgeBans[edgeKey]) or 0
    if Traversal.shellBanned(shell, edgeKey, now) then
        untilMs = math.max(untilMs, tonumber(Traversal.shellBans[shell].untilMs) or 0)
    end
    if untilMs <= now then untilMs = now + Traversal.settings.occupiedBanMs end
    if (Traversal.detourCount or 0) >= 256 then Traversal.detours, Traversal.detourCount = {}, 0 end
    Traversal.detourCount = (Traversal.detourCount or 0) + 1
    if wx == nil then
        Traversal.detours[cacheKey] = { none = true, untilMs = untilMs }
        Traversal.count("detourMisses")
        return nil
    end
    Traversal.detours[cacheKey] = { x = wx + 0.5, y = wy + 0.5, z = z, untilMs = untilMs }
    Traversal.count("detours")
    return wx + 0.5, wy + 0.5, z
end

Traversal.detourSteps = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

function Traversal.detourStep(a, b, refusedKey, climbs, shell, now)
    if Traversal.keptOut[shell] ~= nil and Traversal.enteringKeptOut(shell, a, b, now) then return nil end
    local opening = type(a.getWindowTo) == "function" and a:getWindowTo(b) or nil
    if opening == nil and type(a.getWindowFrameTo) == "function" then opening = a:getWindowFrameTo(b) end
    if opening ~= nil then
        local key = climbs == true and Traversal.edgeKey(a, b) or nil
        if key == nil or key == refusedKey or (Traversal.edgeBans[key] or 0) > now
                or Traversal.openingFailed(shell, key, now)
                or Traversal.landingStatic(b) or Traversal.dropLanding(b)
                or Traversal.entryCourtesyHolds(shell, opening, a, b) then
            return nil
        end

        if Traversal.barricadeOn(opening) ~= nil or Traversal.windowInvincible(opening) then return nil end
        return 2
    end
    if type(a.isHoppableTo) == "function" and a:isHoppableTo(b) == true then
        if not climbs then return nil end
        local key = Traversal.edgeKey(a, b)
        if key == nil or key == refusedKey or (Traversal.edgeBans[key] or 0) > now
                or Traversal.shellBanned(shell, key, now)
                or Traversal.landingStatic(b) or Traversal.dropLanding(b) then
            return nil
        end
        return 2
    end
    if type(a.isBlockedTo) == "function" and a:isBlockedTo(b) == true then
        if type(a.getDoorTo) ~= "function" then return nil end
        local door = a:getDoorTo(b)
        if door ~= nil and Traversal.courtesyHolds(shell, door, a) then return nil end
        if door ~= nil and Traversal.doorBlockKind(door, a) == nil then return 1 end
        return nil
    end
    return 0
end

function Traversal.searchDetour(shell, refusedKey, nx, ny, fx, fy, z, climbs, now)
    local qx, qy, qk, path = Traversal.detourSearch(shell, refusedKey, nx, ny, fx, fy, z, climbs, now)
    if path == nil then return nil end
    local firstCross, firstPast
    for index = 2, #path do
        local node = path[index]
        if firstCross == nil and qk[node] ~= 0 then firstCross = index end
        if firstPast == nil then
            local near
            if nx ~= fx then
                near = (fx > nx and qx[node] <= nx) or (fx < nx and qx[node] >= nx)
            else
                near = (fy > ny and qy[node] <= ny) or (fy < ny and qy[node] >= ny)
            end
            if not near then firstPast = index end
        end
    end
    local pick = firstPast
    if firstCross ~= nil and (firstPast == nil or firstCross <= firstPast) then pick = firstCross end
    if pick == nil then return nil end

    if pick - 1 > 1 then pick = pick - 1 end
    local node = path[pick]
    return qx[node], qy[node]
end

function Traversal.detourSearch(shell, refusedKey, nx, ny, fx, fy, z, climbs, now)
    if type(getCell) ~= "function" then return nil end
    local cell = getCell()
    if cell == nil then return nil end
    local start = cell:getGridSquare(nx, ny, z)
    if start == nil then return nil end
    local radius = Traversal.settings.detourRadius
    local width = radius * 2 + 1
    local ox, oy = nx - radius, ny - radius
    local qx, qy, qp, qk, squares = { nx }, { ny }, { 0 }, { 0 }, { start }
    local seen = { [(nx - ox) * width + (ny - oy)] = true }
    local steps = Traversal.detourSteps
    local head, found = 1, nil
    while head <= #qx and head <= Traversal.settings.detourNodes do
        local hx, hy = qx[head], qy[head]
        for index = 1, 4 do
            local tx, ty = hx + steps[index][1], hy + steps[index][2]
            local slot = (tx - ox) * width + (ty - oy)
            local refused = hx == nx and hy == ny and tx == fx and ty == fy
            if not refused and not seen[slot] and tx >= ox and tx < ox + width
                    and ty >= oy and ty < oy + width then
                local there = cell:getGridSquare(tx, ty, z)
                local step
                if there ~= nil then
                    step = Traversal.detourStep(squares[head], there, refusedKey, climbs, shell, now)
                end

                if step ~= nil and step ~= 2 and not (tx == fx and ty == fy)
                        and not Traversal.detourWalkable(there) then
                    step = nil
                end
                if step ~= nil then
                    seen[slot] = true
                    local n = #qx + 1
                    qx[n], qy[n], qp[n], qk[n], squares[n] = tx, ty, head, step, there
                    if tx == fx and ty == fy then
                        found = n
                        break
                    end
                end
            end
        end
        if found ~= nil then break end
        head = head + 1
    end
    if found == nil then return nil end
    local reversed, at = {}, found
    while at ~= nil and at > 0 do
        reversed[#reversed + 1] = at
        at = qp[at]
    end
    local path = {}
    for index = #reversed, 1, -1 do path[#path + 1] = reversed[index] end
    return qx, qy, qk, path
end

function Traversal.copyRoute(route)
    local copy = {}
    for index = 1, #route do
        local point = route[index]
        copy[index] = { x = point.x, y = point.y, z = point.z }
    end
    return copy
end

function Traversal.routeAround(shell, edgeKey, nx, ny, fx, fy, z, climbs, now)
    local qx, qy, _, path = Traversal.detourSearch(shell, edgeKey, nx, ny, fx, fy, z, climbs, now)
    if path == nil or #path < 2 then return nil end
    local last = #path
    local cell = getCell()
    local far = cell ~= nil and cell:getGridSquare(fx, fy, z) or nil
    if far ~= nil and far.isFree ~= nil and far:isFree(false) ~= true then last = last - 1 end
    local route = {}
    for index = 2, last do
        local node = path[index]
        route[#route + 1] = { x = qx[node] + 0.5, y = qy[node] + 0.5, z = z }
    end
    if #route == 0 then return nil end
    Traversal.count("detours")
    return route
end

function Traversal.detourRoute(shell, edgeKey, doorsOnly, budgeted)
    local x1, y1, x2, y2, z = Traversal.edgeEnds(edgeKey)
    if x1 == nil or shell == nil or shell.getX == nil or shell.getY == nil then return nil end
    local sx, sy = shell:getX(), shell:getY()
    local nx, ny, fx, fy = x1, y1, x2, y2
    if (sx - x2 - 0.5) ^ 2 + (sy - y2 - 0.5) ^ 2 < (sx - x1 - 0.5) ^ 2 + (sy - y1 - 0.5) ^ 2 then
        nx, ny, fx, fy = x2, y2, x1, y1
    end
    local now = nowMs()
    local climbs = doorsOnly ~= true and not Traversal.climbOverBudget(shell, now)
    local settings = Traversal.settings
    local cacheKey = nx .. ":" .. ny .. ">" .. fx .. ":" .. fy .. ":" .. tostring(z)
    if not climbs then
        local cached = Traversal.routes[cacheKey]
        if cached ~= nil and cached.revision == Traversal.revision and now >= cached.atMs
                and now - cached.atMs < settings.detourRouteMs then
            Traversal.count("routeHits")
            if cached.route == nil then return nil end
            return Traversal.copyRoute(cached.route)
        end
    end
    if budgeted == true then
        local window = Traversal.routeSearch
        if now < window.atMs or now - window.atMs >= settings.detourSearchWindowMs then
            window.atMs, window.used = now, 0
        end
        if window.used >= settings.detourSearchesPerWindow then
            Traversal.count("routeDeferred")
            return nil, "deferred"
        end
        window.used = window.used + 1
    end
    Traversal.count("routeSearches")
    local route = Traversal.routeAround(shell, edgeKey, nx, ny, fx, fy, z, climbs, now)
    if climbs then return route end
    if (Traversal.routeCount or 0) >= 64 then Traversal.routes, Traversal.routeCount = {}, 0 end
    Traversal.routeCount = (Traversal.routeCount or 0) + 1
    Traversal.routes[cacheKey] = { route = route, atMs = now, revision = Traversal.revision }
    if route == nil then return nil end
    return Traversal.copyRoute(route)
end

function Traversal.lockedDoor(shell, door, square, nextSquare, target, doorsOnly, now, replans)
    local policy = ProjectALife.DoorPolicy
    local settings = Traversal.settings
    local kind = Traversal.doorBlockKind(door, square)
    local key = Traversal.edgeKey(square, nextSquare)
    local mayBreach = policy.mayBreach(shell, door, kind)
    if replans ~= true then
        if mayBreach and (policy.edgeBanned(square, nextSquare, now) or not policy.playerLock(kind)) then
            return Traversal.beginBreach(shell, door, "door")
        end
        policy.refuse(square, nextSquare, now, shell)
        return false, "door_locked_reroute"
    end
    if not Traversal.breachAllowed(shell, door) then
        if not mayBreach then policy.refuse(square, nextSquare, now, shell) end
        Traversal.refuseCourteously(shell)
        return false, "courteous_reroute"
    end
    local search = Traversal.lockSearch[shell]
    if search == nil or search.key ~= key or now < search.lastMs
            or now - search.lastMs > settings.lockForgetMs then
        search = { key = key, atMs = now, lastMs = now }
        Traversal.lockSearch[shell] = search
    end
    search.lastMs = now
    local fails = Traversal.openingFails[shell]
    local mark = fails ~= nil and key ~= nil and fails[key] or nil
    local back = mark ~= nil and mark.why == "door_locked" and now < (tonumber(mark.untilMs) or 0)
        and now - (tonumber(mark.atMs) or now) >= settings.lockSearchMs
    local way
    if not back then way = Traversal.lockedWay(shell, key, target, doorsOnly, now) end
    if mayBreach and (back or (way == nil and now - search.atMs >= settings.lockSearchMs)) then
        return Traversal.beginBreach(shell, door, "door")
    end
    policy.refuse(square, nextSquare, now, shell)
    if way ~= nil or not mayBreach then
        Traversal.markOpening(shell, key, "door_locked", now)
        return false, "door_locked_reroute"
    end
    Traversal.count("lockSearches")
    return false, "door_locked_search"
end

function Traversal.lockedWay(shell, edgeKey, goal, doorsOnly, now)
    if shell == nil or edgeKey == nil then return nil end
    now = tonumber(now) or nowMs()

    local gx, gy
    if type(goal) == "table" and tonumber(goal.x) ~= nil and tonumber(goal.y) ~= nil then
        gx, gy = math.floor(goal.x), math.floor(goal.y)
    end
    local cached = Traversal.lockWays[shell]
    if cached ~= nil and cached.key == edgeKey and cached.gx == gx and cached.gy == gy
            and now >= cached.atMs and now - cached.atMs < Traversal.settings.lockWayMs then
        return cached.route
    end
    local route, asked
    local entrances = ProjectALife.Entrances
    if entrances ~= nil and type(entrances.wayRound) == "function" then
        local ok, found, detoured = pcall(entrances.wayRound, shell, edgeKey, goal, doorsOnly == true, now)
        if ok and type(found) == "table" and found[1] ~= nil then route = found end
        asked = ok and detoured == true
    end
    if route == nil and not asked then route = Traversal.detourRoute(shell, edgeKey, doorsOnly == true) end
    if cached == nil then
        cached = {}
        Traversal.lockWays[shell] = cached
    end
    cached.key, cached.gx, cached.gy, cached.route, cached.atMs = edgeKey, gx, gy, route, now
    return route
end

function Traversal.wayRound(shell, edgeKey, goal, doorsOnly, budgeted)
    local fails = shell ~= nil and edgeKey ~= nil and Traversal.openingFails[shell] or nil
    local mark = fails ~= nil and fails[edgeKey] or nil
    if mark ~= nil and (mark.why == "door_locked" or mark.why == "courteous") then
        return Traversal.lockedWay(shell, edgeKey, goal, doorsOnly, nowMs())
    end
    local route, deferred = Traversal.detourRoute(shell, edgeKey, doorsOnly == true, budgeted)
    if route ~= nil or deferred ~= nil then return route, deferred end
    local fine, found = pcall(Traversal.exitRoute, shell, edgeKey, goal, doorsOnly, nowMs())
    if fine then return found end
    return nil
end

function Traversal.exitRoute(shell, edgeKey, goal, doorsOnly, now)
    local entrances = ProjectALife.Entrances
    if shell == nil or edgeKey == nil or type(goal) ~= "table" or type(getCell) ~= "function"
            or entrances == nil or type(entrances.mapSite) ~= "function"
            or type(entrances.bestEntry) ~= "function" or type(entrances.ringRoute) ~= "function" then return nil end
    local gx, gy = tonumber(goal.x), tonumber(goal.y)
    local x1, y1, x2, y2, z = Traversal.edgeEnds(edgeKey)
    local cell = getCell()
    if gx == nil or gy == nil or x1 == nil or cell == nil or math.abs(z) >= 0.4 then return nil end
    local near, far = cell:getGridSquare(x1, y1, z), cell:getGridSquare(x2, y2, z)
    if near == nil or far == nil or near.getBuilding == nil or far.getBuilding == nil then return nil end
    local sx, sy = shell:getX(), shell:getY()
    if (sx - x2 - 0.5) ^ 2 + (sy - y2 - 0.5) ^ 2 < (sx - x1 - 0.5) ^ 2 + (sy - y1 - 0.5) ^ 2 then
        near, far = far, near
    end
    local building = near:getBuilding()
    if building == nil or far:getBuilding() ~= nil then return nil end
    local there = cell:getGridSquare(math.floor(gx), math.floor(gy), z)
    if there ~= nil and there.getBuilding ~= nil and there:getBuilding() == building then return nil end
    local site = entrances.mapSite(building, z, now, nil, sx, sy)
    local entry = site ~= nil and entrances.bestEntry(site, shell, edgeKey, doorsOnly, true, sx, sy, now) or nil
    if entry == nil then return nil end
    local outside = { x = entry.sx + 0.5, y = entry.sy + 0.5, z = z }
    local route = { { x = entry.ix + 0.5, y = entry.iy + 0.5, z = z }, outside }
    local ring = entrances.ringRoute(site, outside.x, outside.y, gx, gy)
    for index = 1, #ring do route[#route + 1] = ring[index] end
    Traversal.count("exitRounds")
    return route
end

Traversal.windowFailReasons = {
    window_locked = "mark",
    climb_landing_blocked_reroute = "landing",
    climb_landing_drop_reroute = "static",
    window_invincible_reroute = "static",
    barricade_metal_reroute = "static",
    window_obstacle = "static",
    window_fall = "static",

    fence_obstacle = "static",
    climb_landing_vehicle_reroute = "mark",
    window_climb_unavailable = "mark",
    window_frame_climb_unavailable = "mark",
    window_barricaded_reroute = "mark",
    scavenge_window_excluded = "mark",
    window_arm_rejected = "mark",
    native_no_crossing = "mark",
    native_timeout = "mark",
    breach_timeout = "mark",
    dwell = "mark",
    edge_banned_reroute = "replan",
    opening_failed_reroute = "replan",
    breach_retry_cooldown = "replan",
}

function Traversal.windowInvincible(window)
    return window ~= nil and window.isInvincible ~= nil and window:isInvincible() == true
end

function Traversal.windowGlassy(window)
    if window == nil or window.isGlassRemoved == nil then return false end
    return windowFlag(window, "isSmashed") and not windowFlag(window, "isGlassRemoved")
end

function Traversal.knockOutGlass(window, shell)
    if not Traversal.windowGlassy(window) then return false end
    if shell ~= nil then pcall(function() shell:faceThisObject(window) end) end
    if not pcall(function() window:removeBrokenGlass() end) then return false end
    if type(isServer) == "function" and isServer() then
        pcall(function() window:sync() end)
    elseif Traversal.windowGlassy(window) and window.setGlassRemoved ~= nil then
        pcall(function() window:setGlassRemoved(true) end)
    end
    playSoundFrom(shell or window, "RemoveBrokenGlass")
    Traversal.count("glassCleared")
    return true
end

function Traversal.landingStatic(square)
    if square == nil then return false end
    if square.isSolid ~= nil and square:isSolid() == true then return true end
    if square.isSolidTrans ~= nil and square:isSolidTrans() == true then return true end
    if Traversal.landingWater(square) then return true end
    return square.HasStairs ~= nil and square:HasStairs() == true
end

function Traversal.detourWalkable(square)
    if square.isSolid ~= nil and square:isSolid() == true then return false end
    if square.isSolidTrans ~= nil and square:isSolidTrans() == true then return false end
    return not Traversal.landingWater(square)
end

function Traversal.barricadeOn(object)
    if object == nil then return nil end
    local found
    if object.getBarricadeOnSameSquare ~= nil then found = object:getBarricadeOnSameSquare() end
    if found == nil and object.getBarricadeOnOppositeSquare ~= nil then
        found = object:getBarricadeOnOppositeSquare()
    end
    return found
end

function Traversal.breachOutOfReach(barricade)
    local settings = Traversal.settings
    if settings.metalBreachRefused ~= true or barricade == nil
            or not Traversal.metalBarricade(barricade) then
        return false
    end
    local health = barricade.getHealth ~= nil and tonumber(barricade:getHealth()) or 0
    if barricade.hasModData ~= nil and barricade:hasModData() == true then
        local left = tonumber(barricade:getModData().ProjectALifeBreachLeft)
        if left ~= nil and left < health then health = left end
    end
    local cost = Traversal.damage(settings.breachPlankDamage)
    local swings = math.floor(settings.breachDeadlineMs / (settings.breachImpactMs + settings.breachRecoverMs))
    return cost <= 0 or (health or 0) > swings * cost
end

function Traversal.staticBan(edgeKey, shell, why, now)
    if edgeKey == nil then return end
    local untilMs = (tonumber(now) or nowMs()) + Traversal.settings.staticBanMs
    if (tonumber(Traversal.edgeBans[edgeKey]) or 0) < untilMs then
        if (tonumber(Traversal.edgeBans[edgeKey]) or 0) <= (tonumber(now) or 0) then Traversal.count("staticBans") end
        Traversal.edgeBans[edgeKey] = untilMs
        Traversal.noteBanOrigin(edgeKey, shell, why)
    end
end

function Traversal.openingFailed(shell, edgeKey, now)
    local fails = shell ~= nil and edgeKey ~= nil and Traversal.openingFails[shell] or nil
    local mark = fails ~= nil and fails[edgeKey] or nil
    return mark ~= nil and (tonumber(now) or 0) < (tonumber(mark.untilMs) or 0)
end

function Traversal.askReplan(shell, edgeKey, now)
    if shell == nil or edgeKey == nil then return end
    local pending = Traversal.replanPending[shell]
    if pending == nil then
        pending = {}
        Traversal.replanPending[shell] = pending
    end
    pending.key, pending.atMs = edgeKey, tonumber(now) or nowMs()
end

function Traversal.requestReplan(shell, edgeKey, now)
    if shell == nil or edgeKey == nil then return end
    now = tonumber(now) or nowMs()
    Traversal.climbRefusedAtMs[shell] = now
    Traversal.noteRefusal(shell, "impassable", edgeKey, now, true)
    Traversal.askReplan(shell, edgeKey, now)
end

function Traversal.banImpassableHold(shell, now)
    local record = Traversal.refusals[shell]
    if record == nil or record.kind ~= "impassable" or record.edgeKey == nil
            or record.impassableSinceMs == nil or now - record.impassableSinceMs < 2000 then return false end
    local dx, dy = shell:getX() - record.impassableX, shell:getY() - record.impassableY
    if Traversal.active[shell] ~= nil or dx * dx + dy * dy > 0.16 then
        record.impassableSinceMs = nil
        return false
    end
    local x1, y1, x2, y2, z = Traversal.edgeEnds(record.edgeKey)
    if x1 == nil or math.abs(shell:getZ() - z) >= 0.4
            or (shell:getX() - (x1 + x2 + 1) / 2) ^ 2
                + (shell:getY() - (y1 + y2 + 1) / 2) ^ 2 > 2.25 then return false end
    if (tonumber(Traversal.edgeBans[record.edgeKey]) or 0) <= now then
        Traversal.edgeBans[record.edgeKey] = now + 15000
        Traversal.noteBanOrigin(record.edgeKey, shell, "impassable_hold_2s")
        Traversal.askReplan(shell, record.edgeKey, now)
        Traversal.count("impassableHoldBans")
    end
    record.impassableSinceMs = nil
    return true
end

function Traversal.markOpening(shell, edgeKey, why, now)
    if shell == nil or edgeKey == nil then return nil end
    now = tonumber(now) or nowMs()
    local fails = Traversal.openingFails[shell]
    if fails == nil then
        fails = {}
        Traversal.openingFails[shell] = fails
    end
    local mark = fails[edgeKey]
    if mark == nil then
        mark = { count = 0 }
        fails[edgeKey] = mark
    end
    local settings = Traversal.settings
    mark.count = mark.count + 1
    mark.untilMs = now + math.min(settings.openingFailCapMs, settings.openingFailMs * 2 ^ (mark.count - 1))
    mark.why, mark.atMs = why, now
    Traversal.count("openingMarks")
    Traversal.requestReplan(shell, edgeKey, now)
    Traversal.noteRefusalOnce(shell, "mark:" .. tostring(why), edgeKey)
    return mark
end

function Traversal.noteWindowFailure(shell, reason, edgeKey, now, landing)
    local kind = Traversal.windowFailReasons[reason]
    if kind == nil or shell == nil or edgeKey == nil then return false end
    now = tonumber(now) or nowMs()
    if kind == "landing" then
        if not Traversal.landingStatic(landing) then return false end
        kind = "static"
    end
    if kind == "static" then Traversal.staticBan(edgeKey, shell, reason, now) end
    if kind == "replan" or Traversal.openingFailed(shell, edgeKey, now) then
        Traversal.requestReplan(shell, edgeKey, now)
    else
        Traversal.markOpening(shell, edgeKey, reason, now)
    end
    return true
end

function Traversal.noteFinishFailure(shell, entry, reason)
    if entry == nil or entry.edgeKey == nil then return false end
    if entry.nativeKind ~= "window" and entry.windowEdge ~= true
            and reason ~= "fence_obstacle" then return false end

    if reason == "native_timeout" or reason == "native_no_crossing" then return false end
    return Traversal.noteWindowFailure(shell, reason, entry.edgeKey, nowMs())
end

function Traversal.windowStrike(shell, edgeKey, reason, now)
    if shell == nil or edgeKey == nil then return nil end
    now = tonumber(now) or nowMs()
    Traversal.noteWindowFailure(shell, reason, edgeKey, now)
    local by = tostring(Traversal.uidOf(shell) or shell)
    local strike = Traversal.edgeStrikes[edgeKey]
    if strike ~= nil and strike.by ~= by
            and now - (tonumber(strike.atMs) or 0) < Traversal.settings.edgeStrikeMs then
        Traversal.edgeBans[edgeKey] = now + 60000
        Traversal.noteBanOrigin(edgeKey, shell, reason)
        Traversal.edgeStrikes[edgeKey] = nil
        return edgeKey
    end
    Traversal.edgeStrikes[edgeKey] = { by = by, atMs = now }
    return nil
end

function Traversal.touchWindow(shell, edgeKey, now)
    if shell == nil or edgeKey == nil then return end
    now = tonumber(now) or nowMs()
    local touch = Traversal.windowTouch[shell]
    if touch == nil then
        touch = {}
        Traversal.windowTouch[shell] = touch
    end
    if touch.key ~= edgeKey or touch.lastMs == nil or now - touch.lastMs > Traversal.settings.windowDwellMs then
        touch.key, touch.sinceMs = edgeKey, now
    end
    touch.lastMs = now
end

function Traversal.takeReplan(shell, now)
    local pending = shell ~= nil and Traversal.replanPending[shell] or nil
    if pending == nil or pending.key == nil then return nil end
    local key = pending.key
    pending.key = nil
    if (tonumber(now) or nowMs()) - (tonumber(pending.atMs) or 0) > Traversal.settings.replanFreshMs then return nil end
    return key
end

function Traversal.windowDwelled(shell, now)
    local touch = shell ~= nil and Traversal.windowTouch[shell] or nil
    if touch == nil or touch.key == nil or shell.getX == nil or shell.getY == nil then return nil end
    now = tonumber(now) or nowMs()
    local x1, y1, x2, y2 = Traversal.edgeEnds(touch.key)
    if x1 == nil then return nil end
    local dx = shell:getX() - ((x1 + x2) / 2 + 0.5)
    local dy = shell:getY() - ((y1 + y2) / 2 + 0.5)
    if dx * dx + dy * dy > 2.25 then
        Traversal.windowTouch[shell] = nil
        return nil
    end
    if now - (tonumber(touch.sinceMs) or now) <= Traversal.settings.windowDwellMs then return nil end
    Traversal.windowTouch[shell] = nil
    Traversal.count("dwells")
    Traversal.noteWindowFailure(shell, "dwell", touch.key, now)
    return Traversal.takeReplan(shell, now)
end

function Traversal.probeRefused(shell, window, square, nextSquare, direction)
    local now = nowMs()
    local key = Traversal.edgeKey(square, nextSquare)
    local pressed = key ~= nil and collisionDirection(shell) == direction
    if pressed then Traversal.touchWindow(shell, key, now) end
    local reason = Traversal.openingRefusal(shell, square, nextSquare, now)
    if reason == nil and Traversal.windowInvincible(window) then reason = "window_invincible_reroute" end
    if reason == nil and window.isBarricaded ~= nil and window:isBarricaded() == true
            and Traversal.breachOutOfReach(Traversal.barricadeOn(window)) then
        reason = "barricade_metal_reroute"
    end
    if reason == nil then return false end
    if pressed then Traversal.noteWindowFailure(shell, reason, key, now, nextSquare) end
    return true
end

function Traversal.afterWindowTry(shell, crossed, reason)
    local square, nextSquare = Traversal.trySquare, Traversal.tryNext
    local key = square ~= nil and nextSquare ~= nil and Traversal.edgeKey(square, nextSquare) or nil
    if key == nil then return end
    local now = nowMs()
    Traversal.touchWindow(shell, key, now)
    if crossed then
        local entry = Traversal.active[shell]
        if entry ~= nil and entry.edgeKey == nil then entry.edgeKey, entry.windowEdge = key, true end
        return
    end
    if reason ~= nil then Traversal.noteWindowFailure(shell, reason, key, now, nextSquare) end
end

function Traversal.actionState(shell)
    if shell == nil or shell.getActionStateName == nil then return "" end
    return string.lower(tostring(shell:getActionStateName() or ""))
end

function Traversal.climbOpen(shell, object, frame)
    if type(isServer) == "function" and isServer() then return false end
    if frame and shell.climbThroughWindowFrame == nil then return false end
    if not frame and shell.climbThroughWindow == nil then return false end
    return object == nil or object.canClimbThrough == nil or object:canClimbThrough(shell) ~= false
end

Traversal.windowOpening = setmetatable({}, { __mode = "k" })
function Traversal.noteWindowOpened(shell, window)
    playSoundFrom(shell or window, "OpenWindow")
    if shell == nil then return nil end
    local fair = ProjectALife.Fairness
    local holdMs = fair ~= nil and type(fair.windowOpenMs) == "function" and tonumber(fair.windowOpenMs(nil, shell)) or 0
    if holdMs == nil or holdMs <= 0 then return nil end
    local untilMs = nowMs() + holdMs
    Traversal.windowOpening[shell] = { window = window, untilMs = untilMs }
    return untilMs
end

function Traversal.openHoldUntil(shell, object, now)
    local opening = shell ~= nil and Traversal.windowOpening[shell] or nil
    if opening == nil then return nil end
    if opening.window ~= object or now >= opening.untilMs then
        Traversal.windowOpening[shell] = nil
        return nil
    end
    return opening.untilMs
end

function Traversal.noteEntry(shell, object, kind, nextSquare)
    local fair = ProjectALife.Fairness
    if shell == nil or fair == nil or type(fair.onEntry) ~= "function" then return 0 end
    return fair.onEntry(shell, object, kind, nextSquare, nowMs())
end

function Traversal.noteWindowEntry(shell, object, nextSquare)
    playSoundFrom(shell, "ClimbThroughWindow")
    return Traversal.noteEntry(shell, object, "window", nextSquare)
end

function Traversal.armClimb(shell, kind, object, square, nextSquare, key)
    local frame = kind == "frame"
    local now = nowMs()
    local hold = Traversal.openHoldUntil(shell, object, now)
    local state = Traversal.actionState(shell)
    if hold == nil and (state == "" or state == "idle") then
        local enter = frame and Traversal.enterWindowFrameClimb or Traversal.enterWindowClimb
        if not enter(shell, object) then return false end
        Traversal.beginNative(shell, "window", square, nextSquare, key)
        Traversal.noteWindowEntry(shell, object, nextSquare)
        return true
    end
    if not Traversal.climbOpen(shell, object, frame) then return false end
    local armUntil = math.max(now + Traversal.settings.climbArmMs, hold or 0)
    Traversal.active[shell] = {
        mode = "native_arming", nativeKind = "window", object = object, frame = frame,
        square = square, nextSquare = nextSquare, crossingKey = key,
        edgeKey = Traversal.edgeKey(square, nextSquare),
        notBeforeAtMs = hold,
        armDeadlineAtMs = armUntil,
        deadlineAtMs = armUntil + Traversal.settings.nativeStartGraceMs,
    }
    Traversal.count("armed")
    return true
end

function Traversal.tickArming(shell, entry, now)
    if now < (tonumber(entry.notBeforeAtMs) or 0) then
        if entry.object ~= nil and type(shell.faceThisObject) == "function" then shell:faceThisObject(entry.object) end
        return
    end
    local state = Traversal.actionState(shell)
    if state ~= "idle" and state ~= "" then
        if now < (tonumber(entry.armDeadlineAtMs) or 0) then return end
        Traversal.count("armForced")
    end
    local enter = entry.frame and Traversal.enterWindowFrameClimb or Traversal.enterWindowClimb
    if not enter(shell, entry.object) then
        finish(shell, false, "window_arm_rejected")
        return
    end
    Traversal.beginNative(shell, "window", entry.square, entry.nextSquare, entry.crossingKey)
    Traversal.noteWindowEntry(shell, entry.object, entry.nextSquare)
end

function Traversal.sweepWindows(now)
    local cap = Traversal.settings.openingFailCapMs
    for shell, fails in pairs(Traversal.openingFails) do
        local live = false
        for key, mark in pairs(fails) do
            if now - (tonumber(mark.untilMs) or 0) >= cap then fails[key] = nil else live = true end
        end
        if not live then Traversal.openingFails[shell] = nil end
    end
    for key, strike in pairs(Traversal.edgeStrikes) do
        if now - (tonumber(strike.atMs) or 0) >= Traversal.settings.edgeStrikeMs then
            Traversal.edgeStrikes[key] = nil
        end
    end
end

return Traversal
