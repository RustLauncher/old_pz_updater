require "ProjectALife/Shells/ALifeProfileHydrator"
require "ProjectALife/Shells/ALifeShellState"
require "ProjectALife/Shells/ALifeAIFence"
require "ProjectALife/Shells/ALifeShellSimulation"

require "ProjectALife/Shells/ALifeDeathInventory"
require "ProjectALife/Compat/ALifeEquipEventShield"

ProjectALife = ProjectALife or {}

local ShellAdapter = { adapters = {}, cleanupProgress = setmetatable({}, { __mode = "k" }) }
ProjectALife.ShellAdapter = ShellAdapter
local Hydrator = ProjectALife.ProfileHydrator
local ShellState = ProjectALife.ShellState
local AIFence = ProjectALife.AIFence

function ShellAdapter.carriesLight(actor)
    local memory = type(actor) == "table" and actor.memory or nil
    if type(memory) ~= "table" then return false end
    if memory.flashlight ~= nil then return memory.flashlight == true end
    if memory.nightvision == true then return false end
    local settings = ProjectALife.Settings
    if settings ~= nil and type(settings.current) == "table" and settings.current.nightvision == true then
        return false
    end
    local text = tostring(memory.groupId or actor.uid or "")
    if text == "" then return false end
    local hash = 0
    for index = 1, #text do hash = (hash * 31 + string.byte(text, index)) % 2147483647 end
    return hash % 100 < 50
end

local function setVariable(shell, name, value)
    local ok = pcall(function() shell:SetVariable(name, tostring(value)) end)
    if not ok then shell:setVariable(name, tostring(value)) end
end

local function getVariable(shell, name)
    if shell.GetVariable == nil then return nil end
    return shell:GetVariable(name)
end

function ShellAdapter.dropFlashlight(shell)
    pcall(function()
        local data = shell:getModData()
        if type(data) == "table" and data.ProjectALifeFlashlight ~= nil then data.ProjectALifeFlashlight = nil end
    end)
end

function ShellAdapter.squareBlocked(square)
    if square == nil then return false end
    if square.isSolid ~= nil and square:isSolid() == true then return true end
    if square.isSolidTrans ~= nil and square:isSolidTrans() == true then return true end
    if square.getObjects == nil or type(instanceof) ~= "function" then return false end
    local objects = square:getObjects()
    if objects == nil or objects.size == nil then return false end
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        if object ~= nil and instanceof(object, "IsoThumpable") and object:isBlockAllTheSquare() == true then
            return true
        end
    end
    return false
end

function ShellAdapter.openSquareNear(cell, x, y, z)
    for radius = 1, 3 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = cell:getGridSquare(x + dx, y + dy, z)
                    if square ~= nil and not ShellAdapter.squareBlocked(square) then return x + dx, y + dy end
                end
            end
        end
    end
    return nil
end

local function createZombieShell(actor)
    local factory = ShellAdapter.adapters.createZombie or createZombie
    if type(factory) ~= "function" then return nil, "create_zombie_unavailable" end
    local position = actor.worldPosition
    if ShellAdapter.adapters.createZombie == nil and type(getCell) == "function" then
        local cellOk, cell = pcall(getCell)
        local squareOk, square = pcall(function()
            return cell and cell:getGridSquare(
                math.floor(position.x), math.floor(position.y), math.floor(position.z))
        end)
        if not cellOk or not squareOk or square == nil then
            return nil, "spawn_square_unavailable"
        end
        local blockedOk, blocked = pcall(ShellAdapter.squareBlocked, square)
        if blockedOk and blocked then
            local moveOk, nx, ny = pcall(ShellAdapter.openSquareNear, cell,
                math.floor(position.x), math.floor(position.y), math.floor(position.z))
            if not moveOk or nx == nil then return nil, "spawn_square_blocked" end
            position = { x = nx + 0.5, y = ny + 0.5, z = position.z }
        end
    end
    local direction = IsoDirections ~= nil and IsoDirections.S or nil
    local ok, shell = pcall(
        factory, position.x, position.y, position.z, nil, 0, direction)
    if not ok or shell == nil then return nil, ok and "shell_not_created" or tostring(shell) end
    if ShellAdapter.adapters.createZombie == nil then
        local squareOk, square = pcall(function() return shell:getCurrentSquare() end)
        local coordinateOk, x, y, z = pcall(function()
            return square:getX(), square:getY(), square:getZ()
        end)
        if not squareOk or square == nil or not coordinateOk
                or x ~= math.floor(position.x) or y ~= math.floor(position.y)
                or z ~= math.floor(position.z) then
            pcall(function() shell:removeFromWorld() end)
            pcall(function() shell:removeFromSquare() end)
            return nil, "shell_square_mismatch"
        end
    end
    return shell
end

function ShellAdapter.configure(adapters)
    ShellAdapter.adapters = adapters or {}
    Hydrator.configure(ShellAdapter.adapters.profile)
end

function ShellAdapter.createShell(actor)
    local gate = ProjectALife.CleanupLock
    if gate ~= nil and gate.refuse("npc_body") then return nil, "cleanup_locked" end
    local shell, createError = createZombieShell(actor)
    if shell == nil then return nil, createError end

    local scrubbed, scrubReason = pcall(ShellAdapter.scrubShell, shell)
    if not scrubbed or scrubReason ~= true then
        pcall(function() shell:removeFromWorld() end)
        pcall(function() shell:removeFromSquare() end)
        return nil, "shell_cleanup_failed:" .. tostring(scrubReason)
    end
    AIFence.untrack(shell)
    local ok, reason = pcall(function()

        shell:setUseless(true)
        shell:setCanWalk(true)
        shell:setCrawler(false)
        shell:setBecomeCrawler(false)
        shell:setFakeDead(false)
        shell:setForceFakeDead(false)
        shell:setReanimate(false)
        shell:setReanimatedPlayer(false)
        pcall(function() shell:setTarget(nil) end)
        setVariable(shell, "ALifeActor", true)
        setVariable(shell, "ALifeUID", actor.uid)
        setVariable(shell, "ALifeGeneration", actor.generation)
        local data = shell:getModData()
        data.ProjectALifeOwned = true
        data.ProjectALifeUID = actor.uid
        data.ProjectALifeGeneration = actor.generation

        data.ProjectALifeSpawnedAtMs = (type(getTimestampMs) == "function")
            and getTimestampMs() or 0

        data.ProjectALifeConduct = actor.memory and actor.memory.conduct or nil

        data.ProjectALifeFlashlight = ShellAdapter.carriesLight(actor) or nil
    end)
    if not ok then
        pcall(ShellAdapter.lowerFailed, shell)
        pcall(function() shell:removeFromWorld() end)
        pcall(function() shell:removeFromSquare() end)
        return nil, "shell_initialization_failed:" .. tostring(reason)
    end
    local protected, protectError = AIFence.track(shell)
    if not protected then

        local entered = type(AIFence.fenced) == "table" and AIFence.fenced[shell] ~= nil
        AIFence.untrack(shell)
        if not entered then pcall(ShellAdapter.lowerFailed, shell) end
        pcall(function() shell:removeFromWorld() end)
        pcall(function() shell:removeFromSquare() end)
        return nil, "ai_fence_failed:" .. tostring(protectError)
    end
    return shell
end

function ShellAdapter.lowerFailed(shell)
    if shell == nil or type(AIFence.fenced) ~= "table" or type(AIFence.lower) ~= "function" then return false end
    AIFence.fenced[shell] = true
    return AIFence.lower(shell, "create_failed")
end

function ShellAdapter.hydrateShell(shell, actor)
    local ok = pcall(function()
        setVariable(shell, "ALifeProfileId", actor.profileId)
        setVariable(shell, "ALifeFactionId", actor.factionId)
        setVariable(shell, "ALifeActivity", actor.activity)
        setVariable(shell, "ALifeIntent", actor.intent)
        local data = shell:getModData()
        data.ProjectALifeProfileId = actor.profileId
        data.ProjectALifeFactionId = actor.factionId
        data.ProjectALifeActivity = actor.activity
        data.ProjectALifeIntent = actor.intent
        local admin = type(actor.memory) == "table"
            and type(actor.memory.admin) == "table" and actor.memory.admin or nil
        data.ProjectALifeAdminManaged = admin ~= nil and true or nil
        data.ProjectALifeAdminPersistent = admin and admin.persistent == true or nil
        data.ProjectALifeInvulnerable = admin and admin.invulnerable == true or nil
        data.ProjectALifeAdminStationary = admin and admin.stationary == true or nil
        data.ProjectALifeLeashX = admin and admin.leash and admin.leash.x or nil
        data.ProjectALifeLeashY = admin and admin.leash and admin.leash.y or nil
        data.ProjectALifeLeashZ = admin and admin.leash and admin.leash.z or nil
        data.ProjectALifeLeashRadius = admin and admin.leash and admin.leash.radius or nil
    end)
    if not ok then return false end
    local hydrated
    if type(ShellAdapter.adapters.hydrateProfile) == "function" then
        local profileOk, result = pcall(ShellAdapter.adapters.hydrateProfile, shell, actor)
        hydrated = profileOk and result == true
    else
        hydrated = Hydrator.hydrate(shell, actor) == true
    end
    return hydrated
end

function ShellAdapter.scrubShell(shell)
    if shell == nil then return false end
    return ProjectALife.EquipEventShield.withCleanup(shell, function()
    pcall(function()
        local traversal = ProjectALife.ObstacleTraversal
        if traversal then
            traversal.cancel(shell, "scrub")

            if type(traversal.forget) == "function" then traversal.forget(shell, "scrub") end
        end
    end)
    pcall(function()
        if ProjectALife.Animations then ProjectALife.Animations.clear(shell) end
    end)
    pcall(function()
        if ProjectALife.Animations then ProjectALife.Animations.forget(shell) end
    end)
    if ProjectALife.Combat then
        ProjectALife.Combat.pathRequests[shell] = nil
        ProjectALife.Combat.aimState[shell] = nil
    end

    pcall(function()
        local dedicated = type(isServer) == "function" and isServer()
        if dedicated then

            local inventory = shell:getInventory()
            if inventory ~= nil then inventory:clear() end
        else
            shell:setPrimaryHandItem(nil)
            shell:setSecondaryHandItem(nil)
            local inventory = shell:getInventory()
            if inventory ~= nil then inventory:clear() end
        end
    end)
    pcall(function() shell:clearAttachedItems() end)

    if type(shell.clearWornItems) == "function" then pcall(shell.clearWornItems, shell) end
    pcall(function()
        local visuals = shell:getItemVisuals()
        if visuals ~= nil then visuals:clear() end
    end)
    pcall(function() ProjectALife.DeathInventory.clear(shell) end)

    pcall(function()
        local data = shell:getModData()
        if type(data) ~= "table" then return end
        local keys, count = {}, 0
        for key in pairs(data) do
            if type(key) == "string" and string.sub(key, 1, 12) == "ProjectALife" then
                count = count + 1
                keys[count] = key
            end
        end
        for index = 1, count do data[keys[index]] = nil end
    end)

    pcall(function()
        for _, name in ipairs({ "ALife", "ALifeActor", "ALifeUID", "ALifeGeneration",
                "ALifeWalkSpeed", "ALifeRunSpeed",
                "ALifeSprintSpeed", "ALifeAimWalk", "ALifeWeaponHeld",
                "ALifeArms", "ALifeGrip", "ALifeStrafe",
                "ALifeStrafeX", "ALifeStrafeY", "ALifePace", "ALifeSneak", "ALifeLimp" }) do
            shell:SetVariable(name, "")
        end
    end)

    return true
    end)
end

function ShellAdapter.cleanupShell(shell)
    if shell == nil then return true end
    local uid, generation = ShellAdapter.shellIdentity(shell)
    local progress = ShellAdapter.cleanupProgress[shell]
    if progress ~= nil and (progress.uid ~= uid or progress.generation ~= generation) then
        if not (progress.worldRemoved == true and (uid == nil or uid == "") and generation == nil
                and ShellAdapter.zombieListed(shell) == false) then
            progress = nil
            ShellAdapter.cleanupProgress[shell] = nil
        end
    end
    if progress == nil and type(uid) == "string" and #uid > 0 and type(generation) == "number" then
        progress = { uid = uid, generation = generation, worldRemoved = false }
        ShellAdapter.cleanupProgress[shell] = progress
    end
    if progress == nil or progress.worldRemoved ~= true then
        if not ProjectALife.ShellSimulation.retire(shell) then return false end
        if type(shell.removeFromWorld) ~= "function" then return false end
        local worldOk = pcall(shell.removeFromWorld, shell)
        if not worldOk then return false end
        if progress ~= nil then progress.worldRemoved = true end
    end
    if type(shell.getCurrentSquare) ~= "function" or shell:getCurrentSquare() ~= nil then
        if type(shell.removeFromSquare) ~= "function" then return false end
        local squareOk = pcall(shell.removeFromSquare, shell)
        if not squareOk then return false end
    end
    ShellAdapter.scrubShell(shell)
    AIFence.untrack(shell)
    ShellAdapter.cleanupProgress[shell] = nil
    return true
end

function ShellAdapter.saveCleanupComplete(shell, uid, generation)
    local progress = ShellAdapter.cleanupProgress[shell]
    return type(progress) == "table" and progress.uid == uid and progress.generation == generation
        and progress.worldRemoved == true
end

function ShellAdapter.isObject(value)
    local kind = type(value)
    return kind == "userdata" or kind == "table"
end

function ShellAdapter.shellAlive(shell)
    if not ShellAdapter.isObject(shell) or shell.isDead == nil
            or shell:isDead() == true or shell.getCurrentSquare == nil then
        return false
    end
    if type(isServer) == "function" and isServer() then

        local square = shell:getCurrentSquare()
        local moving = square ~= nil and square.getMovingObjects ~= nil
            and square:getMovingObjects() or nil
        if moving ~= nil and moving.contains ~= nil and moving:contains(shell) == true then return true end

        return square ~= nil and ShellAdapter.zombieListedFast(shell)
    end
    if shell.isExistInTheWorld == nil then return false end
    if shell:isExistInTheWorld() ~= true then

        return ShellAdapter.newborn(shell) and shell:getCurrentSquare() ~= nil
            and ShellAdapter.zombieListedFast(shell)
    end
    return shell:getCurrentSquare() ~= nil
end

ShellAdapter.bornGraceMs = 2000

function ShellAdapter.newborn(shell)
    if shell.hasModData == nil or shell:hasModData() ~= true
            or type(getTimestampMs) ~= "function" then return false end
    local born = tonumber(shell:getModData().ProjectALifeSpawnedAtMs)
    if born == nil then return false end
    local age = getTimestampMs() - born
    return age >= 0 and age < ShellAdapter.bornGraceMs
end

function ShellAdapter.shellIdentity(shell)
    if not ShellAdapter.isObject(shell) then return nil, nil end
    local data = shell.getModData ~= nil and shell:getModData() or nil
    if type(data) == "table" then
        local uid, generation = data.ProjectALifeUID,
            tonumber(data.ProjectALifeGeneration)
        if type(uid) == "string" and generation ~= nil then return uid, generation end
    end
    return getVariable(shell, "ALifeUID"),
        tonumber(getVariable(shell, "ALifeGeneration"))
end

function ShellAdapter.shellPosition(shell)
    if not ShellAdapter.isObject(shell) or shell.getX == nil
            or shell.getY == nil or shell.getZ == nil then return nil end
    return { x = shell:getX(), y = shell:getY(), z = shell:getZ() }
end

function ShellAdapter.shellDead(shell)
    return ShellAdapter.isObject(shell) and shell.isDead ~= nil and shell:isDead() == true
end

function ShellAdapter.zombieListedFast(shell)
    if type(getCell) ~= "function" then return false end
    local cell = getCell()
    if not ShellAdapter.isObject(cell) or cell.getZombieList == nil then return false end
    local zombies = cell:getZombieList()
    return ShellAdapter.isObject(zombies) and zombies.contains ~= nil and zombies:contains(shell) == true
end

function ShellAdapter.zombieListed(shell)
    if not ShellAdapter.isObject(shell) or type(getCell) ~= "function" then return nil end
    local cellOk, cell = pcall(getCell)
    if not cellOk or not ShellAdapter.isObject(cell) or cell.getZombieList == nil then return nil end
    local zombies = cell:getZombieList()
    if not ShellAdapter.isObject(zombies) or zombies.contains == nil then return nil end
    return zombies:contains(shell) == true
end

function ShellAdapter.releaseOldShell(shell)
    if ShellAdapter.shellAlive(shell) or ShellAdapter.zombieListed(shell) == true then
        return ShellAdapter.cleanupShell(shell)
    end
    ShellAdapter.scrubShell(shell)
    AIFence.untrack(shell)
    return true
end

function ShellAdapter.probeShell(shell, position)
    local probe = {}
    local isObject = ShellAdapter.isObject(shell)
    if isObject and shell.getCurrentSquare ~= nil then
        probe.squareNil = shell:getCurrentSquare() == nil
    end
    if isObject and shell.getOnlineID ~= nil then probe.onlineId = shell:getOnlineID() end
    local here = ShellAdapter.shellPosition(shell)
    if here ~= nil and tonumber(here.x) ~= nil and tonumber(here.y) ~= nil then
        probe.bodyAt = math.floor(here.x) .. "," .. math.floor(here.y) .. ","
            .. math.floor(tonumber(here.z) or 0)
    end
    probe.inList = ShellAdapter.zombieListed(shell)
    local x = type(position) == "table" and tonumber(position.x) or nil
    local y = type(position) == "table" and tonumber(position.y) or nil
    if x == nil or y == nil then return probe end
    local z = math.floor(tonumber(position.z) or 0)
    probe.at = math.floor(x) .. "," .. math.floor(y) .. "," .. z
    local cellOk, cell = false, nil
    if type(getCell) == "function" then cellOk, cell = pcall(getCell) end
    if cellOk and ShellAdapter.isObject(cell) and cell.getGridSquare ~= nil then
        probe.loaded = cell:getGridSquare(math.floor(x), math.floor(y), z) ~= nil
    end
    local locator = ProjectALife.PlayerLocator
    if locator ~= nil and type(locator.list) == "function" and type(locator.position) == "function" then
        local nearest
        for _, player in ipairs(locator.list() or {}) do
            local at = locator.position(player)
            if type(at) == "table" and tonumber(at.x) ~= nil and tonumber(at.y) ~= nil then
                local squared = (tonumber(at.x) - x) ^ 2 + (tonumber(at.y) - y) ^ 2
                if nearest == nil or squared < nearest then nearest = squared end
            end
        end
        if nearest ~= nil then probe.nearest = math.floor(math.sqrt(nearest) * 10 + 0.5) / 10 end
    end
    return probe
end

function ShellAdapter.countZombies(center, radius, except, wholeChunk)
    local found = { mates = 0, stale = 0, anim = 0, plain = 0 }
    local x = type(center) == "table" and tonumber(center.x) or nil
    local y = type(center) == "table" and tonumber(center.y) or nil
    if x == nil or y == nil or type(getCell) ~= "function" or type(instanceof) ~= "function" then return found end
    local cell = getCell()
    if not ShellAdapter.isObject(cell) or cell.getGridSquare == nil then return found end
    local z = math.floor(tonumber(center.z) or 0)
    local x0, y0 = math.floor(x) - radius, math.floor(y) - radius
    local x1, y1 = math.floor(x) + radius, math.floor(y) + radius
    if wholeChunk then
        x0, y0 = math.floor(x / 8) * 8, math.floor(y / 8) * 8
        x1, y1 = x0 + 7, y0 + 7
    end
    local watchdog = ProjectALife.Watchdog
    local bindings = watchdog ~= nil and watchdog.bindings or {}
    local nearest
    for sx = x0, x1 do
        for sy = y0, y1 do
            local square = cell:getGridSquare(sx, sy, z)
            local moving = ShellAdapter.isObject(square) and square.getMovingObjects ~= nil
                and square:getMovingObjects() or nil
            local count = ShellAdapter.isObject(moving) and moving.size ~= nil and moving.get ~= nil
                and tonumber(moving:size()) or 0
            for index = 0, count - 1 do
                local zombie = moving:get(index)
                if zombie ~= except and ShellAdapter.isObject(zombie) and zombie.isDead ~= nil
                        and instanceof(zombie, "IsoZombie") and zombie:isDead() ~= true then
                    local data = zombie.hasModData ~= nil and zombie.getModData ~= nil
                        and zombie:hasModData() and zombie:getModData() or nil
                    local uid = type(data) == "table" and data.ProjectALifeUID or nil
                    local mark = zombie.GetVariable ~= nil and zombie:GetVariable("ALifeActor") or nil
                    if uid ~= nil then
                        local held = bindings[uid]
                        if held ~= nil and held.shell == zombie then found.mates = found.mates + 1
                        else found.stale = found.stale + 1 end
                    elseif tostring(mark) == "true" then
                        found.anim = found.anim + 1
                    else
                        found.plain = found.plain + 1
                        if zombie.getX ~= nil and zombie.getY ~= nil then
                            local distance = math.sqrt(((tonumber(zombie:getX()) or x) - x) ^ 2
                                + ((tonumber(zombie:getY()) or y) - y) ^ 2)
                            if nearest == nil or distance < nearest then nearest = distance end
                        end
                    end
                end
            end
        end
    end
    if nearest ~= nil then found.nearestPlain = math.floor(nearest * 10 + 0.5) / 10 end
    return found
end

ShellAdapter.watchTiles = 30

function ShellAdapter.zombieWatched(zombie)
    if type(isServer) == "function" and isServer() == true then
        local locator = ProjectALife.PlayerLocator
        if locator == nil or type(locator.list) ~= "function" or type(locator.position) ~= "function" then return true end
        local x, y = tonumber(zombie:getX()), tonumber(zombie:getY())
        for _, player in ipairs(locator.list() or {}) do
            local at = locator.position(player)
            if type(at) ~= "table" or x == nil or y == nil
                    or ((tonumber(at.x) or 0) - x) ^ 2 + ((tonumber(at.y) or 0) - y) ^ 2 <= ShellAdapter.watchTiles ^ 2 then
                return true
            end
        end
        return false
    end
    if type(getSpecificPlayer) ~= "function" or type(zombie.getSquare) ~= "function" then return true end
    local square = zombie:getSquare()
    if square == nil or type(square.isCanSee) ~= "function" then return true end
    for index = 0, 3 do
        if getSpecificPlayer(index) ~= nil and square:isCanSee(index) == true then return true end
    end
    return false
end

function ShellAdapter.clearZone(center, radius, except)
    local result = { removed = 0, watched = 0 }
    local x = type(center) == "table" and tonumber(center.x) or nil
    local y = type(center) == "table" and tonumber(center.y) or nil
    if x == nil or y == nil or type(getCell) ~= "function" or type(instanceof) ~= "function" then return result end
    local cell = getCell()
    if not ShellAdapter.isObject(cell) or cell.getGridSquare == nil then return result end
    local z = math.floor(tonumber(center.z) or 0)
    local reach = math.ceil(radius)
    local doomed = {}
    for sx = math.floor(x) - reach, math.floor(x) + reach do
        for sy = math.floor(y) - reach, math.floor(y) + reach do
            local square = cell:getGridSquare(sx, sy, z)
            local moving = ShellAdapter.isObject(square) and square.getMovingObjects ~= nil
                and square:getMovingObjects() or nil
            local count = ShellAdapter.isObject(moving) and moving.size ~= nil and moving.get ~= nil
                and tonumber(moving:size()) or 0
            for index = 0, count - 1 do
                local zombie = moving:get(index)
                if zombie ~= except and ShellAdapter.isObject(zombie) and zombie.isDead ~= nil
                        and instanceof(zombie, "IsoZombie") and zombie:isDead() ~= true
                        and zombie.getX ~= nil and zombie.getY ~= nil
                        and (zombie:getX() - x) ^ 2 + (zombie:getY() - y) ^ 2 <= radius * radius then
                    local data = zombie.hasModData ~= nil and zombie.getModData ~= nil
                        and zombie:hasModData() and zombie:getModData() or nil
                    local mark = zombie.GetVariable ~= nil and zombie:GetVariable("ALifeActor") or nil
                    local simulation = ProjectALife.ShellSimulation
                    local grappled = simulation ~= nil and type(simulation.grappledCorpse) == "function"
                        and simulation.grappledCorpse(zombie) == true
                    if not (type(data) == "table" and data.ProjectALifeUID ~= nil) and tostring(mark) ~= "true"
                            and not grappled then
                        if ShellAdapter.zombieWatched(zombie) then
                            result.watched = result.watched + 1
                        else
                            doomed[#doomed + 1] = zombie
                        end
                    end
                end
            end
        end
    end
    for _, zombie in ipairs(doomed) do
        if pcall(function()
            zombie:removeFromWorld()
            zombie:removeFromSquare()
        end) then result.removed = result.removed + 1 end
    end
    return result
end

function ShellAdapter.placeFacts(position)
    local server = type(isServer) == "function" and isServer() == true
    local facts = { side = server and "server" or "sp" }
    local x = type(position) == "table" and tonumber(position.x) or nil
    local y = type(position) == "table" and tonumber(position.y) or nil
    if x == nil or y == nil or type(getCell) ~= "function" then return facts end
    local cell = getCell()
    if not ShellAdapter.isObject(cell) or cell.getGridSquare == nil then return facts end
    local fx, fy, fz = math.floor(x), math.floor(y), math.floor(tonumber(position.z) or 0)
    local ring = 0
    for dx = -8, 8, 8 do
        for dy = -8, 8, 8 do
            if (dx ~= 0 or dy ~= 0) and cell:getGridSquare(fx + dx, fy + dy, fz) ~= nil then ring = ring + 1 end
        end
    end
    facts.ring = ring
    if not server and cell.getChunkMap ~= nil then
        local map = cell:getChunkMap(0)
        if ShellAdapter.isObject(map) and map.getWorldXMinTiles ~= nil and map.getWorldXMaxTiles ~= nil
                and map.getWorldYMinTiles ~= nil and map.getWorldYMaxTiles ~= nil and map.getWidthInTiles ~= nil then
            facts.edge = math.min(fx - map:getWorldXMinTiles(), map:getWorldXMaxTiles() - 1 - fx,
                fy - map:getWorldYMinTiles(), map:getWorldYMaxTiles() - 1 - fy)
            facts.win = map:getWidthInTiles()
        end
    end
    local zombies = cell.getZombieList ~= nil and cell:getZombieList() or nil
    if ShellAdapter.isObject(zombies) and zombies.size ~= nil then facts.cellZeds = zombies:size() end
    local config = server and type(SandboxVars) == "table" and SandboxVars.ZombieConfig or nil
    if type(config) == "table" then facts.cullAt = tonumber(config.ZombiesCountBeforeDelete) end
    return facts
end

function ShellAdapter.fate(shell)
    if not ShellAdapter.isObject(shell) then return "none" end
    local listed = ShellAdapter.zombieListed(shell) == true
    if listed or ShellAdapter.shellAlive(shell) then return "left" end
    return "removed"
end

function ShellAdapter.recoverShell(actor, binding)
    if binding and binding.shell then
        local uid, generation = ShellAdapter.shellIdentity(binding.shell)

        if uid == binding.uid and generation == binding.generation
                and not ShellAdapter.shellDead(binding.shell)
                and not ShellAdapter.releaseOldShell(binding.shell) then
            return false, "old_shell_cleanup_failed"
        end
    end

    local spawnActor = actor
    if binding and binding.lastPosition then
        spawnActor = {}
        for key, value in pairs(actor) do spawnActor[key] = value end
        spawnActor.worldPosition = binding.lastPosition
    end
    local shell, createError = ShellAdapter.createShell(spawnActor)
    if shell == nil then return false, createError end
    if not ShellAdapter.hydrateShell(shell, actor) then
        ShellAdapter.cleanupShell(shell)
        return false, "shell_hydration_failed"
    end
    return shell
end

function ShellAdapter.detachShell(_, binding)
    if not binding then return true end
    local uid, generation = ShellAdapter.shellIdentity(binding.shell)

    if binding.saveCleanupFailed == true and (uid == nil or uid == "") and generation == nil
            and ShellAdapter.saveCleanupComplete(binding.shell, binding.uid, binding.generation)
            and ShellAdapter.zombieListed(binding.shell) == false then
        return ShellAdapter.cleanupShell(binding.shell)
    end

    if uid ~= binding.uid or generation ~= binding.generation
            or ShellAdapter.shellDead(binding.shell) then return true end
    return ShellAdapter.releaseOldShell(binding.shell)
end

function ShellAdapter.spawnAdapters(extra)
    extra = extra or {}
    return {
        nowMs = extra.nowMs,
        newUid = extra.newUid,
        persist = extra.persist,
        emit = extra.emit,
        createShell = ShellAdapter.createShell,
        hydrateShell = ShellAdapter.hydrateShell,
        cleanupShell = ShellAdapter.cleanupShell,
        shellAlive = ShellAdapter.shellAlive,
        shellIdentity = ShellAdapter.shellIdentity,
        shellPosition = ShellAdapter.shellPosition,
        captureShellState = ShellState.capture,
        saveCleanupComplete = ShellAdapter.saveCleanupComplete,
        recoverShell = ShellAdapter.recoverShell,
        detachShell = ShellAdapter.detachShell,
    }
end

return ShellAdapter
