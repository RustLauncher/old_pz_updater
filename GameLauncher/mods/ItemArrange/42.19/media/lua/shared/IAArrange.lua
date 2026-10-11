IA = IA or {}

local CURSOR_ORDER_N = 1
local CURSOR_ORDER_W = 2
local CURSOR_ORDER_S = 3
local CURSOR_ORDER_E = 4

function IA.getSurfaceInfo(square)
    local cursorOrder = CURSOR_ORDER_N

    local ground = {
        zmin = 0,
        zmax = 1,
        xmin = 0,
        xmax = 1,
        ymin = 0,
        ymax = 1,
    }

    local squareN = square:getCell():getGridSquare(square:getX(), square:getY() - 1, square:getZ())
    local squareS = square:getCell():getGridSquare(square:getX(), square:getY() + 1, square:getZ())
    local squareW = square:getCell():getGridSquare(square:getX() - 1, square:getY(), square:getZ())
    local squareE = square:getCell():getGridSquare(square:getX() + 1, square:getY(), square:getZ())

    local wall = square:getWall()
    if wall then
        if wall:isWallN() then
            ground.ymin = 0.1
            cursorOrder = CURSOR_ORDER_N
        elseif wall:isWallW() then
            ground.xmin = 0.1
            cursorOrder = CURSOR_ORDER_W
        else
            ground.ymin = 0.1
            ground.xmin = 0.1
        end
    end
    
    if squareS then
        local wallS = squareS:getWall()
        if wallS then
            if wallS:isWallN() then
                ground.ymax = 0.9
                cursorOrder = CURSOR_ORDER_S
            end
        end

        if not squareS:isFree(false) then
            ground.ymax = 0.9
        end
    end
    
    if squareE then
        local wallE = squareE:getWall()
        if wallE then
            if wallE:isWallW() then
                ground.xmax = 0.9
                cursorOrder = CURSOR_ORDER_E
            end
        end

        if not squareE:isFree(false) then
            ground.xmax = 0.9
        end
    end

    if squareW then
        if not squareW:isFree(false) then
            ground.xmin = 0.1
        end
    end

    if squareN then
        if not squareN:isFree(false) then
            ground.ymin = 0.1
        end
    end

    local tileObjects = square:getLuaTileObjectList()
    local squareSurfaceOffset = 0
    local surfaces = {}
    for k, object in pairs(tileObjects) do
        local sprite = object:getSprite()
        if sprite then
            local surfaceOffsetNoTable = object:getSurfaceOffsetNoTable()
            if surfaceOffsetNoTable > squareSurfaceOffset then
                squareSurfaceOffset = surfaceOffsetNoTable
            end

            local surfaceOffset = object:getSurfaceOffset()
            if surfaceOffset > squareSurfaceOffset then
                squareSurfaceOffset = surfaceOffset
            end

            squareSurfaceOffset = squareSurfaceOffset / 96

            local spriteName = sprite:getName()
            if IA.surfaces[spriteName] then
                surfaces = IA.surfaces[spriteName]
                for _, surface in ipairs(surfaces) do
                    if not surface.zmin then
                        surface.zmin = squareSurfaceOffset
                    end
                end
                object:setOverlaySprite("")
                break
            else
                ground.zmin = squareSurfaceOffset
            end
        end
    end
    
    if #surfaces == 0 then
        table.insert(surfaces, ground)
    end

    -- recognized objects with known surfaces
    local sourceSurfaces = surfaces

    -- Build per-square surfaces and compute vertical clearance against the next
    -- overlapping higher surface so items only fit if their dz fits the gap.
    local normalized = {}
    for i, src in ipairs(sourceSurfaces) do
        normalized[i] = {
            xmin = src.xmin or ground.xmin,
            xmax = src.xmax or ground.xmax,
            ymin = src.ymin or ground.ymin,
            ymax = src.ymax or ground.ymax,
            zmin = src.zmin or ground.zmin,
            zmax = src.zmax or ground.zmax,
        }
    end

    local clearancePad = 0.001
    for i, surface in ipairs(normalized) do
        local nearestAbove
        for j, other in ipairs(normalized) do
            if i ~= j and other.zmin > surface.zmin then
                local overlapX = (surface.xmin < other.xmax) and (other.xmin < surface.xmax)
                local overlapY = (surface.ymin < other.ymax) and (other.ymin < surface.ymax)
                if overlapX and overlapY then
                    if not nearestAbove or other.zmin < nearestAbove then
                        nearestAbove = other.zmin
                    end
                end
            end
        end

        if nearestAbove then
            local capped = nearestAbove - clearancePad
            if capped < surface.zmax then
                surface.zmax = capped
            end
        end

        if surface.zmax > 1 then
            surface.zmax = 1
        end
        if surface.zmax < surface.zmin then
            surface.zmax = surface.zmin
        end
    end

    surfaces = normalized
    return cursorOrder, surfaces

end

local function buildGroundList(square, extraItem)
    local arrangables = IA.arrangables
    local groundList = {}
    local wobs = square:getWorldObjects()
    for i = 0, wobs:size() - 1 do
        local witem = wobs:get(i)
        local item = witem:getItem()
        local fType = item:getFullType()
        if arrangables[fType] then
            if not groundList[fType] then
                groundList[fType] = {}
            end
            table.insert(groundList[fType], { item = item, witem = witem })
        end
    end

    if extraItem then
        local fType = extraItem:getFullType()
        if arrangables[fType] then
            if not groundList[fType] then
                groundList[fType] = {}
            end
            table.insert(groundList[fType], { item = extraItem })
        end
    end

    return groundList
end

local function arrangeGroundList(square, groundList, applyOffsets)
    local arrangables = IA.arrangables

    local cursorOrder, surfaces = IA.getSurfaceInfo(square)

    -- Prefer the smallest fitting vertical band first; this keeps shallow shelves
    -- for shallow items and leaves tall bands for bulky items.
    local orderedSurfaceIndexes = {}
    for i = 1, #surfaces do
        orderedSurfaceIndexes[i] = i
    end
    table.sort(orderedSurfaceIndexes, function(a, b)
        local sa = surfaces[a] or {}
        local sb = surfaces[b] or {}
        local da = (sa.zmax or 1) - (sa.zmin or 0)
        local db = (sb.zmax or 1) - (sb.zmin or 0)
        if da ~= db then
            return da < db
        end

        -- Tie-break by profile order to keep author-defined shelf preference.
        return a < b
    end)

    -- surface cursor
    local cs = 1
    local exhaustedSurfaces = {}
    local surfaceCursorState = {}

    local surfaceInfo
    local xmin, xmax, ymin, ymax, zmin, zmax
    local cx, cy

    -- max stack dimensions per surface
    local dxmax = 0
    local dymax = 0

    local function saveCurrentSurfaceState()
        if not cs then
            return
        end

        if cx == nil or cy == nil then
            return
        end

        surfaceCursorState[cs] = {
            cx = cx,
            cy = cy,
            dxmax = dxmax,
            dymax = dymax,
        }
    end

    local function setSurface(index)
        local surfaceIndex = orderedSurfaceIndexes[index]
        local s = surfaceIndex and surfaces[surfaceIndex] or nil
        if not s then
            return false
        end

        saveCurrentSurfaceState()

        cs = index
        surfaceInfo = s

        xmin = surfaceInfo.xmin
        xmax = surfaceInfo.xmax
        ymin = surfaceInfo.ymin
        ymax = surfaceInfo.ymax
        zmin = surfaceInfo.zmin or 0
        zmax = surfaceInfo.zmax or 1
        if zmax > 1 then zmax = 1 end

        local state = surfaceCursorState[index]
        if state and state.cx ~= nil and state.cy ~= nil then
            cx = state.cx
            cy = state.cy
            dxmax = state.dxmax or 0
            dymax = state.dymax or 0
        else
            -- E and S use decrementing cursor, W and N use incrementing cursor
            cx = (cursorOrder == CURSOR_ORDER_E) and xmax or xmin
            cy = (cursorOrder == CURSOR_ORDER_S) and ymax or ymin
            dxmax = 0
            dymax = 0
        end

        return true
    end

    local function canSurfaceFitItem(index, dx, dy, dz, mz)
        local surfaceIndex = orderedSurfaceIndexes[index]
        local s = surfaceIndex and surfaces[surfaceIndex] or nil
        if not s then
            return false
        end

        local sxmin = s.xmin
        local sxmax = s.xmax
        local symin = s.ymin
        local symax = s.ymax
        local szmin = s.zmin or 0
        local szmax = s.zmax or 1
        if szmax > 1 then
            szmax = 1
        end

        local hasFootprintRoom = (sxmin + dx) <= sxmax and (symin + dy) <= symax
        if not hasFootprintRoom then
            return false
        end

        return (szmin + (mz or 0) + dz) <= szmax
    end

    local function selectLowestFittingSurface(dx, dy, dz, mz, skipIndex)
        for index = 1, #orderedSurfaceIndexes do
            if index ~= skipIndex and not exhaustedSurfaces[index] and canSurfaceFitItem(index, dx, dy, dz, mz) then
                return index
            end
        end
        return nil
    end

    local function switchSurfaceByFit(dx, dy, dz, mz, exhaustCurrent)
        local shouldExhaust = (exhaustCurrent ~= false)
        local previous = cs

        if shouldExhaust and previous then
            exhaustedSurfaces[cs] = true
        end

        local nextSurface = selectLowestFittingSurface(dx, dy, dz, mz, previous)
        if not nextSurface and not shouldExhaust then
            -- Fallback: if this was a temporary guard switch, allow staying put.
            nextSurface = selectLowestFittingSurface(dx, dy, dz, mz)
        end

        if not nextSurface then
            return false
        end

        return setSurface(nextSurface)
    end

    local function switchSurfaceByGuard(dx, dy, dz, mz, guardState)
        -- Guard switches should not permanently exhaust a surface on first miss,
        -- but must still terminate if we keep bouncing across candidates.
        if not guardState then
            return switchSurfaceByFit(dx, dy, dz, mz, false)
        end

        guardState.attempts = (guardState.attempts or 0) + 1

        if guardState.attempts <= #orderedSurfaceIndexes then
            return switchSurfaceByFit(dx, dy, dz, mz, false)
        end

        guardState.attempts = 0
        return switchSurfaceByFit(dx, dy, dz, mz, true)
    end

    local function isOutOfBounds(xpos, ypos, dx, dy)
        return (cursorOrder == CURSOR_ORDER_N and ypos + dy > ymax)
            or (cursorOrder == CURSOR_ORDER_W and xpos + dx > xmax)
            or (cursorOrder == CURSOR_ORDER_S and ypos < ymin)
            or (cursorOrder == CURSOR_ORDER_E and xpos < xmin)
    end

    local placedBoundsBySurface = {}

    local function getAnchorBounds(xpos, ypos, zpos, dx, dy, dz)
        local x1, x2, y1, y2
        if cursorOrder == CURSOR_ORDER_S then
            x1 = xpos
            x2 = xpos + dx
            y1 = ypos - dy
            y2 = ypos
        elseif cursorOrder == CURSOR_ORDER_E then
            x1 = xpos - dx
            x2 = xpos
            y1 = ypos
            y2 = ypos + dy
        else
            x1 = xpos
            x2 = xpos + dx
            y1 = ypos
            y2 = ypos + dy
        end

        return {
            x1 = x1,
            x2 = x2,
            y1 = y1,
            y2 = y2,
            z1 = zpos,
            z2 = zpos + dz,
        }
    end

    local function boundsOverlap(a, b)
        -- Use a tiny epsilon so numerically-adjacent bounds (touching faces)
        -- are not treated as collisions due to floating-point noise.
        local eps = 0.0005
        local overlapX = ((a.x1 + eps) < b.x2) and ((b.x1 + eps) < a.x2)
        local overlapY = ((a.y1 + eps) < b.y2) and ((b.y1 + eps) < a.y2)
        local overlapZ = ((a.z1 + eps) < b.z2) and ((b.z1 + eps) < a.z2)
        return overlapX and overlapY and overlapZ
    end

    local function isPositionOccupied(surfaceIndex, xpos, ypos, zpos, dx, dy, dz)
        local bounds = getAnchorBounds(xpos, ypos, zpos, dx, dy, dz)
        local placed = placedBoundsBySurface[surfaceIndex]
        if not placed then
            return false
        end

        for _, existing in ipairs(placed) do
            if boundsOverlap(bounds, existing) then
                return true
            end
        end

        return false
    end

    local function registerPlacedBounds(surfaceIndex, xpos, ypos, zpos, dx, dy, dz)
        if not placedBoundsBySurface[surfaceIndex] then
            placedBoundsBySurface[surfaceIndex] = {}
        end
        table.insert(placedBoundsBySurface[surfaceIndex], getAnchorBounds(xpos, ypos, zpos, dx, dy, dz))
    end

    local totalTypes = 0
    for _ in pairs(groundList) do
        totalTypes = totalTypes + 1
    end

    local processedTypes = 0
    for fType, witems in pairs(groundList) do
        local arr = arrangables[fType]

        -- item dimensions
        local dx = arr.dx
        local dy = arr.dy
        local dz = arr.dz

        -- item minimal z offset (used if had to be rotated)
        local mz = arr.mz or 0

        -- max item number on a single stack
        local qz = arr.qz or 3

        -- Surface exhaustion is item-size specific. Reset per type, then pick the
        -- smallest fitting band for this type instead of inheriting prior type.
        exhaustedSurfaces = {}
        local firstSurface = selectLowestFittingSurface(dx, dy, dz, mz)
        if not firstSurface or not setSurface(firstSurface) then
            print ("ItemArranger: no fitting surface found for item type " .. tostring(fType))
            return false
        end

        if cursorOrder == CURSOR_ORDER_W or cursorOrder == CURSOR_ORDER_E then
            if dx > dymax then
                dymax = dx
            end
        else
            if dy > dxmax then
                dxmax = dy
            end
        end

        local z = 0
        for i, entry in ipairs(witems) do
            local zpos = zmin + mz + (z * dz)
            local xpos = cx
            local ypos = cy
            while (zpos + dz) > zmax or z >= qz do
                z = 0

                -- If the first item in a stack cannot fit this z band, skip to next surface.
                local cannotFitSurface = (zmin + mz + dz) > zmax
                if cannotFitSurface then
                    if not switchSurfaceByFit(dx, dy, dz, mz) then
                        print ("ItemArranger: ran out of space to arrange items on surface (" .. cs .. "), cursorOrder:" .. cursorOrder .. ", xpos: " .. xpos .. ", ypos: " .. ypos .. ", zpos: " .. zpos .. ", dx: " .. dx .. ", dy: " .. dy .. " xmax: " .. xmax .. ", ymax: " .. ymax)
                        return false
                    end

                    zpos = zmin + mz + (z * dz)
                    xpos = cx
                    ypos = cy
                else
                    if cursorOrder == CURSOR_ORDER_W or cursorOrder == CURSOR_ORDER_E then
                        cy = cy + dy
                    else
                        cx = cx + dx
                    end
                    zpos = zmin + mz + (z * dz)
                    if cursorOrder == CURSOR_ORDER_W then
                        if cy + dy > ymax then
                            cy = ymin
                            cx = cx + dymax
                            dymax = dx
                        end
                    elseif cursorOrder == CURSOR_ORDER_E then
                        if cy + dy > ymax then
                            cy = ymin
                            cx = cx - dymax
                            dymax = dx
                        end
                    else
                        if cx + dx > xmax then
                            cx = xmin
                            if cursorOrder == CURSOR_ORDER_S then
                                cy = cy - dxmax
                            else
                                cy = cy + dxmax
                            end
                            dxmax = dy
                        end
                    end

                    xpos = cx
                    ypos = cy
                    if isOutOfBounds(xpos, ypos, dx, dy) then
                        if not switchSurfaceByFit(dx, dy, dz, mz) then
                            print ("ItemArranger: ran out of space to arrange items on this surface (1), cursorOrder:" .. cursorOrder .. ", xpos: " .. xpos .. ", ypos: " .. ypos .. ", zpos: " .. zpos .. ", dx: " .. dx .. ", dy: " .. dy .. " xmax: " .. xmax .. ", ymax: " .. ymax)
                            return false
                        end

                        zpos = zmin + mz + (z * dz)
                        xpos = cx
                        ypos = cy
                    end
                end
            end

            -- Restored cursor state can be stale for the current item dimensions.
            -- Re-validate XY bounds before placing this item.
            local xyGuardState = { attempts = 0 }
            while isOutOfBounds(xpos, ypos, dx, dy) do
                z = 0
                if not switchSurfaceByGuard(dx, dy, dz, mz, xyGuardState) then
                    print ("ItemArranger: ran out of space to arrange items on this surface (xy-guard), cursorOrder:" .. cursorOrder .. ", xpos: " .. xpos .. ", ypos: " .. ypos .. ", zpos: " .. zpos .. ", dx: " .. dx .. ", dy: " .. dy .. " xmax: " .. xmax .. ", ymax: " .. ymax)
                    return false
                end

                zpos = zmin + mz + (z * dz)
                xpos = cx
                ypos = cy
            end

            while isPositionOccupied(cs, xpos, ypos, zpos, dx, dy, dz) do
                z = 0
                if cursorOrder == CURSOR_ORDER_W or cursorOrder == CURSOR_ORDER_E then
                    cy = cy + dy
                else
                    cx = cx + dx
                end

                zpos = zmin + mz + (z * dz)
                if cursorOrder == CURSOR_ORDER_W then
                    if cy + dy > ymax then
                        cy = ymin
                        cx = cx + dymax
                        dymax = dx
                    end
                elseif cursorOrder == CURSOR_ORDER_E then
                    if cy + dy > ymax then
                        cy = ymin
                        cx = cx - dymax
                        dymax = dx
                    end
                else
                    if cx + dx > xmax then
                        cx = xmin
                        if cursorOrder == CURSOR_ORDER_S then
                            cy = cy - dxmax
                        else
                            cy = cy + dxmax
                        end
                        dxmax = dy
                    end
                end

                zpos = zmin + mz + (z * dz)
                xpos = cx
                ypos = cy

                if isOutOfBounds(xpos, ypos, dx, dy) then
                    if not switchSurfaceByFit(dx, dy, dz, mz) then
                        print ("ItemArranger: ran out of space to arrange items on this surface (collision-guard), cursorOrder:" .. cursorOrder .. ", xpos: " .. xpos .. ", ypos: " .. ypos .. ", zpos: " .. zpos .. ", dx: " .. dx .. ", dy: " .. dy .. " xmax: " .. xmax .. ", ymax: " .. ymax)
                        return false
                    end

                    zpos = zmin + mz + (z * dz)
                    xpos = cx
                    ypos = cy
                end

                local xyAfterCollisionGuardState = { attempts = 0 }
                while isOutOfBounds(xpos, ypos, dx, dy) do
                    z = 0
                    if not switchSurfaceByGuard(dx, dy, dz, mz, xyAfterCollisionGuardState) then
                        print ("ItemArranger: ran out of space to arrange items on this surface (xy-after-collision), cursorOrder:" .. cursorOrder .. ", xpos: " .. xpos .. ", ypos: " .. ypos .. ", zpos: " .. zpos .. ", dx: " .. dx .. ", dy: " .. dy .. " xmax: " .. xmax .. ", ymax: " .. ymax)
                        return false
                    end

                    zpos = zmin + mz + (z * dz)
                    xpos = cx
                    ypos = cy
                end
            end

            local anchorX = xpos
            local anchorY = ypos

            if cursorOrder == CURSOR_ORDER_N then
                xpos = xpos + (dx / 2)
                ypos = ypos + (dy / 2)
            elseif cursorOrder == CURSOR_ORDER_S then
                xpos = xpos + (dx / 2)
                ypos = ypos - (dy / 2)
            elseif cursorOrder == CURSOR_ORDER_E then
                xpos = xpos - (dx / 2)
                ypos = ypos + (dy / 2)
            elseif cursorOrder == CURSOR_ORDER_W then
                xpos = xpos + (dx / 2)
                ypos = ypos + (dy / 2)
            end

            if applyOffsets and entry.witem then
                entry.witem:setOffset(xpos, ypos, zpos)

                local item = entry.item
                local fx = arr.fx or 0
                item:setWorldXRotation(fx)

                local fy = arr.fy or 0
                item:setWorldYRotation(fy)

                local fz = arr.fz or 0
                item:setWorldZRotation(fz)

                item:setDoingExtendedPlacement(false)
                entry.witem:syncExtendedPlacement()
            end

            registerPlacedBounds(cs, anchorX, anchorY, zpos, dx, dy, dz)
            z = z + 1
        end

        processedTypes = processedTypes + 1

        -- Move to the next stack slot only if another item type is pending.
        if processedTypes < totalTypes then
            if cursorOrder == CURSOR_ORDER_W then
                cy = cy + dy
                if cy + dy > ymax then
                    cy = ymin
                    cx = cx + dymax
                    dymax = 0
                    if cx + dx > xmax then
                        if not switchSurfaceByFit(dx, dy, dz, mz) then
                            print ("ItemArranger: ran out of space to arrange items on this surface (2)")
                            return false
                        end
                    end
                end
            elseif cursorOrder == CURSOR_ORDER_E then
                cy = cy + dy
                if cy + dy > ymax then
                    cy = ymin
                    cx = cx - dymax
                    dymax = 0
                    if cx < xmin then
                        if not switchSurfaceByFit(dx, dy, dz, mz) then
                            print ("ItemArranger: ran out of space to arrange items on this surface (3)")
                            return false
                        end
                    end
                end
            else
                cx = cx + dx
                if cx + dx > xmax then
                    cx = xmin
                    if cursorOrder == CURSOR_ORDER_S then
                        cy = cy - dxmax
                    else
                        cy = cy + dxmax
                    end
                    dxmax = 0

                    if (cursorOrder == CURSOR_ORDER_N and cy + dy > ymax) or (cursorOrder == CURSOR_ORDER_S and cy < ymin) then
                        if not switchSurfaceByFit(dx, dy, dz, mz) then
                            print ("ItemArranger: ran out of space to arrange items on this surface (4)")
                            return false
                        end
                    end
                end
            end
        end
    end

    return true
end


function IA.CheckSpace(square, item)
    if not square or not item then
        return false
    end

    local fType = item:getFullType()
    local arr = IA.arrangables[fType]
    if not arr then
        return true
    end

    local groundList = buildGroundList(square)
    local sameTypeItems = groundList[fType]
    if sameTypeItems and #sameTypeItems > 0 then
        local qz = arr.qz or 3
        local currentStackSize = #sameTypeItems % qz
        if currentStackSize ~= 0 then
            local _, surfaces = IA.getSurfaceInfo(square)
            local mz = arr.mz or 0
            for _, surfaceInfo in ipairs(surfaces) do
                local zmin = surfaceInfo.zmin or 0
                local zmax = surfaceInfo.zmax or 1
                if zmax > 1 then zmax = 1 end

                local nextZ = zmin + mz + (currentStackSize * arr.dz)
                if (nextZ + arr.dz) <= zmax then
                    return true
                end
            end
        end
    end

    return arrangeGroundList(square, buildGroundList(square, item), false)
end

function IA.ArrangeItems(square, simulate)
    return arrangeGroundList(square, buildGroundList(square), not simulate)
end
