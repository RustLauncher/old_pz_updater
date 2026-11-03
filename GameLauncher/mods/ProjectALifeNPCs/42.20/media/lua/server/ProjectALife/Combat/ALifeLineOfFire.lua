ProjectALife = ProjectALife or {}

local LineOfFire = {
    settings = { maximumSquares = 64,

        maximumStoreys = 3 },

    impactSound = "BulletImpact",
}
ProjectALife.LineOfFire = LineOfFire

local function edgeHasWindow(square, nextSquare)

    return square:isWindowTo(nextSquare) == true
        or nextSquare:isWindowTo(square) == true
end

local function edgeWindowBlocksShot(square, nextSquare)
    local window = square.getWindowTo ~= nil and square:getWindowTo(nextSquare) or nil
    if window == nil and nextSquare.getWindowTo ~= nil then window = nextSquare:getWindowTo(square) end
    if window == nil and square.getWindowThumpableTo ~= nil then window = square:getWindowThumpableTo(nextSquare) end
    if window == nil and nextSquare.getWindowThumpableTo ~= nil then window = nextSquare:getWindowThumpableTo(square) end
    if window == nil or window.isBarricaded == nil or window:isBarricaded() ~= true then return false end
    local same = window.getBarricadeOnSameSquare ~= nil and window:getBarricadeOnSameSquare() or nil
    local opposite = window.getBarricadeOnOppositeSquare ~= nil and window:getBarricadeOnOppositeSquare() or nil
    if same == nil and opposite == nil then return LineOfFire.engineRayOpaque(square, nextSquare) ~= false end
    return (same ~= nil and same:isBlockVision() == true)
        or (opposite ~= nil and opposite:isBlockVision() == true)
end

function LineOfFire.hoppableEdge(square, nextSquare)
    if square:getHoppableTo(nextSquare) ~= nil
            or nextSquare:getHoppableTo(square) ~= nil then return true end
    local over = LineOfFire.shootsOver
    if type(square.getWallHoppableTo) == "function"
            and over(square:getWallHoppableTo(nextSquare)) then return true end
    if type(nextSquare.getWallHoppableTo) == "function"
            and over(nextSquare:getWallHoppableTo(square)) then return true end
    if type(square.getHoppableThumpableTo) == "function"
            and over(square:getHoppableThumpableTo(nextSquare)) then return true end
    if type(nextSquare.getHoppableThumpableTo) == "function"
            and over(nextSquare:getHoppableThumpableTo(square)) then return true end
    return false
end

function LineOfFire.shootsOver(object)
    if object == nil then return false end
    return type(object.isTallHoppable) ~= "function" or object:isTallHoppable() ~= true
end

function LineOfFire.transparentEdge(square, north)
    if IsoFlagType == nil or type(square.getObjects) ~= "function" then return nil end
    local objects = square:getObjects()
    if objects == nil then return nil end
    local blocks = north and IsoFlagType.collideN or IsoFlagType.collideW
    local seeOver = north and IsoFlagType.transparentN or IsoFlagType.transparentW
    if blocks == nil or seeOver == nil then return nil end
    local found
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        local properties
        if object ~= nil and type(object.getProperties) == "function" then
            properties = object:getProperties()
        end
        if properties ~= nil and type(properties.has) == "function"
                and properties:has(blocks) == true then

            if properties:has(seeOver) ~= true then return false end
            found = true
        end
    end
    return found
end

function LineOfFire.seeOverEdge(square, nextSquare)
    if type(square.getX) ~= "function" or type(nextSquare.getX) ~= "function" then
        return false
    end
    local dx = nextSquare:getX() - square:getX()
    local dy = nextSquare:getY() - square:getY()
    local over = false
    if dx ~= 0 then
        local side = LineOfFire.transparentEdge(dx > 0 and nextSquare or square, false)
        if side == false then return false end
        over = over or side == true
    end
    if dy ~= 0 then
        local side = LineOfFire.transparentEdge(dy > 0 and nextSquare or square, true)
        if side == false then return false end
        over = over or side == true
    end
    return over
end

function LineOfFire.rayBlocked(result)
    local results = LosUtil ~= nil and LosUtil.TestResults or nil
    local blocked = results ~= nil and results.Blocked or nil
    if blocked ~= nil then return result == blocked end
    return tostring(result) == "Blocked"
end

function LineOfFire.engineEdgeResult(cell, fromX, fromY, fromZ, toX, toY, toZ)
    if cell == nil or LosUtil == nil or type(LosUtil.lineClear) ~= "function" then return nil end
    local ok, result = pcall(LosUtil.lineClear, cell, fromX, fromY, fromZ, toX, toY, toZ, false)
    if not ok then return nil end
    return result
end

function LineOfFire.engineRayOpaque(square, nextSquare)
    if LosUtil == nil or type(LosUtil.lineClear) ~= "function"
            or type(getCell) ~= "function" then return nil end
    if type(square.getX) ~= "function" or type(nextSquare.getX) ~= "function" then
        return nil
    end
    local result = LineOfFire.engineEdgeResult(getCell(),
        square:getX(), square:getY(), square:getZ(),
        nextSquare:getX(), nextSquare:getY(), nextSquare:getZ())
    if result == nil then return nil end
    return LineOfFire.rayBlocked(result)
end

local function edgeBlocksShot(square, nextSquare, forSight)
    if square == nil or nextSquare == nil then return true end
    if edgeHasWindow(square, nextSquare) then

        if forSight then
            return LineOfFire.engineRayOpaque(square, nextSquare) ~= false
        end
        return edgeWindowBlocksShot(square, nextSquare)
    end

    if LineOfFire.hoppableEdge(square, nextSquare) then return false end
    local solid = square:isSomethingTo(nextSquare) == true
        or nextSquare:isSomethingTo(square) == true
        or square:isBlockedTo(nextSquare) == true
    if not solid then return false end

    if LineOfFire.seeOverEdge(square, nextSquare) then return false end

    return LineOfFire.engineRayOpaque(square, nextSquare) ~= false
end

function LineOfFire.storeyRule(z, targetZ, shooterOutside, targetOutside, maximumStoreys)
    if z == targetZ then return true end
    if shooterOutside ~= true or targetOutside ~= true then return false end
    return math.abs((tonumber(z) or 0) - (tonumber(targetZ) or 0)) <= (tonumber(maximumStoreys) or 3)
end

function LineOfFire.openAir(cell, x, y, z)
    local outside = false
    pcall(function()
        local square = cell:getGridSquare(x, y, z)
        if square ~= nil and square:isOutside() == true then outside = true end
    end)
    return outside
end

function LineOfFire.storeyAt(step, steps, fromZ, toZ)
    fromZ, toZ = math.floor(tonumber(fromZ) or 0), math.floor(tonumber(toZ) or 0)
    steps = tonumber(steps) or 0
    if fromZ == toZ or steps <= 0 then return toZ end
    local fraction = math.max(0, math.min(1, (tonumber(step) or 0) / steps))
    return math.floor(fromZ + (toZ - fromZ) * fraction + 0.5)
end

function LineOfFire.tileRayClear(a, b)
    if a == nil or b == nil or LosUtil == nil or type(getCell) ~= "function" then return nil end
    local ok, result = pcall(LineOfFire.characterRay, a, b)
    if not ok or result == nil then return nil end
    return not LineOfFire.rayBlocked(result)
end

function LineOfFire.characterRay(a, b)
    return LosUtil.lineClear(getCell(),
        math.floor(a:getX()), math.floor(a:getY()), math.floor(a:getZ()),
        math.floor(b:getX()), math.floor(b:getY()), math.floor(b:getZ()), false)
end

function LineOfFire.stepCount(spanX, spanY)
    spanX = math.abs(math.floor(tonumber(spanX) or 0))
    spanY = math.abs(math.floor(tonumber(spanY) or 0))
    if spanX == 0 or spanY == 0 then return spanX + spanY end
    local a, b = spanX, spanY
    while b ~= 0 do a, b = b, a % b end
    local corners = 0
    if math.floor(spanX / a) % 2 == 1 and math.floor(spanY / a) % 2 == 1 then corners = a end
    return spanX + spanY - corners
end

function LineOfFire.cells(fromX, fromY, toX, toY, limit, visit)
    local x, y = math.floor(fromX), math.floor(fromY)
    local endX, endY = math.floor(toX), math.floor(toY)
    local spanX, spanY = math.abs(endX - x), math.abs(endY - y)
    local stepX = endX >= x and 1 or -1
    local stepY = endY >= y and 1 or -1
    local total = LineOfFire.stepCount(spanX, spanY)
    local reach = math.floor(tonumber(limit) or LineOfFire.settings.maximumSquares)
    local longX = spanX >= spanY
    local crossedX, crossedY = 0, 0
    for index = 1, total do
        if (longX and crossedX or crossedY) >= reach then return "exhausted" end

        local lineX = (2 * crossedX + 1) * spanY
        local lineY = (2 * crossedY + 1) * spanX
        local moveX = crossedX < spanX and (crossedY >= spanY or lineX <= lineY)
        local moveY = crossedY < spanY and (crossedX >= spanX or lineY <= lineX)
        local nextX, nextY = x, y
        if moveX then nextX = x + stepX; crossedX = crossedX + 1 end
        if moveY then nextY = y + stepY; crossedY = crossedY + 1 end
        local stop = visit(x, y, nextX, nextY, index, total)
        if stop ~= nil then return "stopped", stop end
        x, y = nextX, nextY
    end
    if x == endX and y == endY then return "arrived" end
    return "exhausted"
end

function LineOfFire.airBoundaryClear(cell, fromX, fromY, toX, toY, storey)
    if storey <= 0 or type(cell.getGridSquare) ~= "function"
            or type(cell.getChunkForGridSquare) ~= "function"
            or LosUtil == nil or type(LosUtil.lineClear) ~= "function"
            or IsoFlagType == nil or IsoFlagType.collideW == nil or IsoFlagType.collideN == nil
            or IsoFlagType.transparentW == nil or IsoFlagType.transparentN == nil then return false end
    local fromGround = cell:getGridSquare(fromX, fromY, 0)
    local toGround = cell:getGridSquare(toX, toY, 0)
    if fromGround == nil or toGround == nil
            or type(fromGround.isOutside) ~= "function" or type(toGround.isOutside) ~= "function"
            or type(fromGround.getChunk) ~= "function" or type(toGround.getChunk) ~= "function"
            or fromGround:isOutside() ~= true or toGround:isOutside() ~= true then return false end
    local fromChunk = cell:getChunkForGridSquare(fromX, fromY, storey)
    local toChunk = cell:getChunkForGridSquare(toX, toY, storey)
    if fromChunk == nil or toChunk == nil or fromGround:getChunk() ~= fromChunk
            or toGround:getChunk() ~= toChunk then return false end
    if fromX ~= toX then
        local west = cell:getGridSquare(fromX > toX and fromX or toX,
            fromX > toX and fromY or toY, storey)
        if west ~= nil and LineOfFire.transparentEdge(west, false) == false then return false end
    end
    if fromY ~= toY then
        local north = cell:getGridSquare(fromY > toY and fromX or toX,
            fromY > toY and fromY or toY, storey)
        if north ~= nil and LineOfFire.transparentEdge(north, true) == false then return false end
    end
    local result = LineOfFire.engineEdgeResult(cell, fromX, fromY, storey,
        toX, toY, storey)
    if result == nil then return false end
    local results = LosUtil.TestResults
    if results ~= nil and type(result) ~= "string" then
        return result == results.Clear or result == results.ClearThroughOpenDoor
    end
    return result == "Clear" or result == "ClearThroughOpenDoor"
end

function LineOfFire.meleeEdgeClosed(square, nextSquare)
    if square == nil or nextSquare == nil
            or type(square.isBlockedTo) ~= "function" or type(nextSquare.isBlockedTo) ~= "function"
            or type(square.isHoppableTo) ~= "function" or type(nextSquare.isHoppableTo) ~= "function" then return true end
    return square:isBlockedTo(nextSquare) ~= false or nextSquare:isBlockedTo(square) ~= false
        or square:isHoppableTo(nextSquare) ~= false or nextSquare:isHoppableTo(square) ~= false
end

function LineOfFire.boundaryClosed(cell, fromX, fromY, toX, toY, storey, forSight)
    local square = cell:getGridSquare(fromX, fromY, storey)
    local nextSquare = cell:getGridSquare(toX, toY, storey)
    if forSight == "melee" then
        if fromX ~= toX and fromY ~= toY then
            local sideX = cell:getGridSquare(toX, fromY, storey)
            local sideY = cell:getGridSquare(fromX, toY, storey)
            return LineOfFire.meleeEdgeClosed(square, sideX)
                or LineOfFire.meleeEdgeClosed(sideX, nextSquare)
                or LineOfFire.meleeEdgeClosed(square, sideY)
                or LineOfFire.meleeEdgeClosed(sideY, nextSquare)
        end
        return LineOfFire.meleeEdgeClosed(square, nextSquare)
    end
    if fromX ~= toX and fromY ~= toY then
        return LineOfFire.boundaryClosed(cell, fromX, fromY, toX, fromY, storey, forSight)
            or LineOfFire.boundaryClosed(cell, toX, fromY, toX, toY, storey, forSight)
            or LineOfFire.boundaryClosed(cell, fromX, fromY, fromX, toY, storey, forSight)
            or LineOfFire.boundaryClosed(cell, fromX, toY, toX, toY, storey, forSight)
    end
    if square == nil or nextSquare == nil then
        if forSight then return true end
        return not LineOfFire.airBoundaryClear(cell, fromX, fromY, toX, toY, storey)
    end
    return edgeBlocksShot(square, nextSquare, forSight)
end

function LineOfFire.hasClearBoundary(shell, target, forSight)
    if shell == nil or target == nil then return false end
    local ok, clear = pcall(LineOfFire.boundaryWalk, shell, target, forSight)

    return ok and clear == true
end

function LineOfFire.boundaryWalk(shell, target, forSight)
    if type(getCell) ~= "function" then return false end
    local cell = getCell()
    if cell == nil or type(cell.getGridSquare) ~= "function" then return false end
    if forSight == "melee" and (type(shell.getX) ~= "function" or type(shell.getY) ~= "function"
            or type(shell.getZ) ~= "function" or type(target.getX) ~= "function"
            or type(target.getY) ~= "function" or type(target.getZ) ~= "function") then return false end
    local x0, y0 = math.floor(shell:getX()), math.floor(shell:getY())
    local x1, y1 = math.floor(target:getX()), math.floor(target:getY())

    local z = math.floor(shell:getZ())
    local targetZ = math.floor(target:getZ())
    if forSight == "melee" and (z ~= targetZ or cell:getGridSquare(x0, y0, z) == nil
            or cell:getGridSquare(x1, y1, targetZ) == nil) then return false end
    if z ~= targetZ then

        if not LineOfFire.storeyRule(z, targetZ, LineOfFire.openAir(cell, x0, y0, z),
                LineOfFire.openAir(cell, x1, y1, targetZ), LineOfFire.settings.maximumStoreys) then
            return false
        end
    end
    local outcome = LineOfFire.cells(x0, y0, x1, y1, LineOfFire.settings.maximumSquares,
        function(fromX, fromY, toX, toY, index, total)
            local here = LineOfFire.storeyAt(index - 1, total, z, targetZ)
            local there = LineOfFire.storeyAt(index, total, z, targetZ)
            if LineOfFire.boundaryClosed(cell, fromX, fromY, toX, toY, here, forSight) then return false end

            if there ~= here
                    and LineOfFire.boundaryClosed(cell, fromX, fromY, toX, toY, there, forSight) then
                return false
            end
            return nil
        end)
    return outcome == "arrived"
end

function LineOfFire.liveBystander(body, shell, target)
    if body == nil or body == shell or body == target then return false end
    if not instanceof(body, "IsoZombie") then return false end
    return body.isDead ~= nil and body:isDead() ~= true
end

function LineOfFire.bystanderOn(square, shell, target)
    local moving = square:getMovingObjects()
    if moving == nil then return nil end
    for index = 0, moving:size() - 1 do
        local body = moving:get(index)
        if LineOfFire.liveBystander(body, shell, target) then return body end
    end
    return nil
end

function LineOfFire.firstBodyOnLine(shell, target)
    if shell == nil or target == nil then return nil end
    local found
    pcall(function()
        local cell = getCell()
        if cell == nil then return end
        local fromZ, targetZ = math.floor(shell:getZ()), math.floor(target:getZ())
        LineOfFire.cells(shell:getX(), shell:getY(), target:getX(), target:getY(),
            LineOfFire.settings.maximumSquares, function(fromX, fromY, cx, cy, index, total)
                if index >= total then return true end

                local rayZ = LineOfFire.storeyAt(index, total, fromZ, targetZ)
                local square = cell:getGridSquare(cx, cy, rayZ)
                if square == nil then return nil end
                found = LineOfFire.bystanderOn(square, shell, target)
                if found ~= nil then return true end
                return nil
            end)
    end)
    return found
end

function LineOfFire.bodyBeyond(shell, target, squares)
    if shell == nil or target == nil then return nil end
    local found
    pcall(function()
        local cell = getCell()
        if cell == nil then return end
        local x0, y0 = shell:getX(), shell:getY()
        local x1, y1 = target:getX(), target:getY()
        local z = math.floor(target:getZ())
        local dx, dy = x1 - x0, y1 - y0
        local length = math.sqrt(dx * dx + dy * dy)
        if length < 0.001 then return end
        dx, dy = dx / length, dy / length
        local limit = math.max(1, math.floor(tonumber(squares) or 3))
        local visited = {}
        for step = 1, limit * 2 do
            local px, py = x1 + dx * step * 0.5, y1 + dy * step * 0.5
            local sx, sy = math.floor(px), math.floor(py)
            local key = sx .. ":" .. sy
            if visited[key] == nil then
                visited[key] = true
                local square = cell:getGridSquare(sx, sy, z)
                local moving = square ~= nil and square:getMovingObjects() or nil
                for index = 0, (moving ~= nil and moving:size() or 0) - 1 do
                    local body = moving:get(index)
                    if body ~= nil and body ~= shell and body ~= target and instanceof(body, "IsoZombie")
                            and body:isDead() ~= true then
                        local data = body:getModData()
                        local person = type(data) == "table"
                            and (data.ProjectALifeOwned == true or data.ProjectALifeActor == true)
                        if not person then

                            local bx, by = body:getX() - x1, body:getY() - y1
                            local along = bx * dx + by * dy
                            local off = math.abs(bx * dy - by * dx)
                            if along > 0 and along <= limit and off <= 0.75 then found = body; return end
                        end
                    end
                end
            end
        end
    end)
    return found
end

function LineOfFire.pelletsOf(weapon)
    local count = 1
    if weapon ~= nil and weapon.getProjectileCount ~= nil then
        local projectiles = weapon:getProjectileCount()
        count = tonumber(projectiles) or 1
    end
    return math.max(1, math.floor(count))
end

function LineOfFire.pierces(weapon)
    return weapon ~= nil and weapon.isPiercingBullets ~= nil
        and weapon:isPiercingBullets() == true
end

function LineOfFire.impact(square)
    if square == nil then return end
    pcall(function() square:playSound(LineOfFire.impactSound) end)
end

function LineOfFire.breakPane(window)
    if window == nil or not instanceof(window, "IsoWindow") then return false end
    if window:isSmashed() == true or window:IsOpen() == true then return false end

    if window.isInvincible ~= nil and window:isInvincible() == true then return false end
    window:smashWindow()
    return true
end

function LineOfFire.breakPanesOn(square)
    local objects = square:getObjects()
    if objects == nil then return end
    local panes
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        if object ~= nil and instanceof(object, "IsoWindow") then
            panes = panes or {}
            panes[#panes + 1] = object
        end
    end
    if panes == nil then return end
    for _, pane in ipairs(panes) do LineOfFire.breakPane(pane) end
end

function LineOfFire.breakEdgeGlass(square, nextSquare)
    pcall(function()
        if square.getWindowTo ~= nil then
            local window = square:getWindowTo(nextSquare) or nextSquare:getWindowTo(square)
            if window ~= nil then
                LineOfFire.breakPane(window)
                return
            end
        end
        LineOfFire.breakPanesOn(square)
        LineOfFire.breakPanesOn(nextSquare)
    end)
end

function LineOfFire.roundCrosses(square, nextSquare)
    if square == nil or nextSquare == nil then return false end
    if edgeBlocksShot(square, nextSquare, false) then
        LineOfFire.impact(square)
        return false
    end
    if edgeHasWindow(square, nextSquare) then
        LineOfFire.breakEdgeGlass(square, nextSquare)
    end
    return true
end

function LineOfFire.roundEdge(cell, fromX, fromY, toX, toY, storey)
    local square = cell:getGridSquare(fromX, fromY, storey)
    local nextSquare = cell:getGridSquare(toX, toY, storey)
    if fromX ~= toX and fromY ~= toY
            and LineOfFire.boundaryClosed(cell, fromX, fromY, toX, toY, storey, false) then
        LineOfFire.impact(square or nextSquare)
        return false
    end
    if square == nil or nextSquare == nil then
        return LineOfFire.airBoundaryClear(cell, fromX, fromY, toX, toY, storey)
    end
    return LineOfFire.roundCrosses(square, nextSquare)
end

function LineOfFire.mayTake(policy, body)
    if type(policy) ~= "function" then return true end
    local ok, answer = pcall(policy, body)
    return ok and answer ~= false
end

function LineOfFire.roundMeetsBodies(square, round)
    local moving = square:getMovingObjects()
    if moving == nil then return true end
    for index = 0, moving:size() - 1 do
        local body = moving:get(index)
        if LineOfFire.liveBystander(body, round.shell, round.target)
                and LineOfFire.mayTake(round.mayHitCharacter, body) then
            round.applyCharacterHit(body)
            round.pellets = round.pellets - 1
            if round.pellets <= 0 and not round.piercing then
                LineOfFire.impact(square)
                return false
            end
        end
    end
    return true
end

function LineOfFire.resolve(shell, target, weapon, applyCharacterHit, mayHitCharacter)
    if shell == nil or target == nil or type(getCell) ~= "function" then return false end
    local ok, primaryClear = pcall(function()
        local cell = getCell()
        if cell == nil or type(cell.getGridSquare) ~= "function" then return false end
        local x0, y0 = math.floor(shell:getX()), math.floor(shell:getY())
        local x1, y1 = math.floor(target:getX()), math.floor(target:getY())

        local z = math.floor(shell:getZ())
        local targetZ = math.floor(target:getZ())
        if z ~= targetZ then

            if not LineOfFire.storeyRule(z, targetZ, LineOfFire.openAir(cell, x0, y0, z),
                    LineOfFire.openAir(cell, x1, y1, targetZ), LineOfFire.settings.maximumStoreys) then
                return false
            end
        end
        local round = {
            shell = shell, target = target,
            pellets = LineOfFire.pelletsOf(weapon), piercing = LineOfFire.pierces(weapon),
            applyCharacterHit = applyCharacterHit, mayHitCharacter = mayHitCharacter,
        }
        local outcome = LineOfFire.cells(x0, y0, x1, y1, LineOfFire.settings.maximumSquares,
            function(fromX, fromY, toX, toY, index, total)

                local here = LineOfFire.storeyAt(index - 1, total, z, targetZ)
                local there = LineOfFire.storeyAt(index, total, z, targetZ)
                if not LineOfFire.roundEdge(cell, fromX, fromY, toX, toY, here) then return false end
                if there ~= here and not LineOfFire.roundEdge(cell, fromX, fromY, toX, toY, there) then return false end

                if index < total then
                    local square = cell:getGridSquare(toX, toY, there)
                    if square ~= nil and not LineOfFire.roundMeetsBodies(square, round) then
                        return false
                    end
                end
                return nil
            end)

        return outcome ~= "stopped"
    end)

    if not ok then return false end
    return primaryClear ~= false
end

return LineOfFire
