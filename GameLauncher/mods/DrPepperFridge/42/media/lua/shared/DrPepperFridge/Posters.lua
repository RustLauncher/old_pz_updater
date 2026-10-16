-- Unique collectible moveables. The sprite pairs use vanilla wall-poster pivots.
DrPepperPosters = DrPepperPosters or {}
local P = DrPepperPosters
P.designs = { 'BeAPepper', 'Original', 'Refreshment', 'GoodTimes', 'PeppersDelight' }
P.prefix = 'drpepper_posters_01_'
P.placementRevision = 2
P.defaults = { PostersEnabled = true, PosterChance = 10, PosterNearDrinksOnly = true, PosterRadius = 3 }

function P.option(name)
    local options = SandboxVars and SandboxVars.DrPepperFridge
    if options and options[name] ~= nil then return options[name] end
    return P.defaults[name]
end

function P.numberOption(name, minimum, maximum)
    local value = tonumber(P.option(name)) or P.defaults[name]
    return math.max(minimum, math.min(maximum, value))
end

function P.spriteName(design, facing)
    return P.prefix .. tostring((design - 1) * 2 + (facing == 'S' and 1 or 0))
end

function P.itemType(design)
    return 'DrPepper.Poster' .. P.designs[design]
end

function P.spriteInfo(name)
    if not name or string.sub(name, 1, #P.prefix) ~= P.prefix then return end
    local index = tonumber(string.sub(name, #P.prefix + 1))
    if not index or index < 0 or index > 9 or index ~= math.floor(index) then return end
    return math.floor(index / 2) + 1, index % 2 == 0 and 'E' or 'S'
end

-- A real wall overlay need not be a MoveType=WallObject. Shop logos (including
-- Gas2Go) are ordinary attached WallOverlay sprites and vanilla Moveables does
-- not reject them when placing another WallObject over them.
-- Native aging, trim and tile finishes do not occupy a poster's wall space.
-- Use only reviewed native families/ranges; furniture, signs and vines still block.
function P.isWallWeathering(sprite)
    local name = sprite and sprite:getName()
    if not name then return false end
    local props = sprite:getProperties()
    if not props or props:has('IsMoveAble') or props:has('MoveType') or props:has('BlocksPlacement') then return false end
    -- Structural eaves sit above the poster. Moveable awnings and collision
    -- pieces are deliberately excluded from this native geometry exception.
    if props:has(IsoFlagType.isEave) and not props:has(IsoFlagType.collideN)
            and not props:has(IsoFlagType.collideW) and not props:has(IsoFlagType.solid) then return true end
    -- These four native conduit segments run along the base of the wall.
    -- Adjacent tiles contain electrical boxes or cables at poster height.
    local conduit = tonumber(string.match(name, '^industry_02_(%d+)$'))
    if conduit and conduit >= 208 and conduit <= 211 and not props:has(IsoFlagType.collideN)
            and not props:has(IsoFlagType.collideW) and not props:has(IsoFlagType.solid) then return true end
    -- Reviewed vanilla finishes only. The excluded exterior ranges contain
    -- railings; walls_detailing_02 also contains clocks and is not a finish family.
    local exterior = tonumber(string.match(name, '^walls_detailing_01_(%d+)$'))
    local exteriorFinish = exterior and ((exterior >= 0 and exterior <= 63)
        or (exterior >= 88 and exterior <= 91) or (exterior >= 96 and exterior <= 107))
    if not (string.match(name, '^overlay_grime_wall_01_%d+$')
            or string.match(name, '^overlay_blood_wall_01_%d+$')
            or string.match(name, '^walls_interior_detailing_01_%d+$')
            or string.match(name, '^walls_interior_detailing_bathroom_01_%d+$')
            or string.match(name, '^walls_interior_detailing_bathroom_02_%d+$')
            or string.match(name, '^walls_interior_detailing_bathroom_03_%d+$')
            or exteriorFinish) then return false end
    return true
end

function P.blocksPoster(props, facing, sprite)
    if not props then return false end
    local other = props:get('Facing')
    if props:has('MoveType') and props:get('MoveType') == 'WallObject' then
        return (not other or other == facing) and not props:has('IsLow')
    end
    if props:has(IsoFlagType.WallOverlay) or props:has(IsoFlagType.attachedN) or props:has(IsoFlagType.attachedW) then
        if P.isWallWeathering(sprite) then return false end
        -- Native roof-edge fascia lies above the poster's footprint.
        if props:has('FasciaEdge') then return false end
        if facing == 'S' and props:has(IsoFlagType.attachedW) and not props:has(IsoFlagType.attachedN) then return false end
        if facing == 'E' and props:has(IsoFlagType.attachedN) and not props:has(IsoFlagType.attachedW) then return false end
        return true
    end
    return props:has('BlocksPlacement') and not props:has('IsLow')
end

-- Overlay sprites can belong to a floor, low counter or perpendicular wall.
-- Evaluate their plane and height; keep unclassified decor on the target wall
-- occupied (some native clock sprites have no placement properties at all).
function P.overlayBlocksPoster(sprite, hostProps, facing)
    local props = sprite and sprite:getProperties()
    if not props then return true end
    if P.blocksPoster(props, facing, sprite) then return true end
    local wallKey = facing == 'S' and 'WallN' or 'WallW'
    if not hostProps or not (hostProps:has(wallKey) or hostProps:has('WallNW')) then return false end
    if P.isWallWeathering(sprite) or props:has('IsLow') or props:has('FasciaEdge')
            or props:has(IsoFlagType.solidfloor) then return false end
    -- These known wall properties reached here only because blocksPoster
    -- classified the sprite as non-blocking for this face.
    if props:get('MoveType') == 'WallObject' or props:has(IsoFlagType.WallOverlay)
            or props:has(IsoFlagType.attachedN) or props:has(IsoFlagType.attachedW) then return false end
    return true
end

function P.wallAvailable(square, facing, ignoreObject, allowConstructed, ignoreChild)
    if (facing ~= 'S' and facing ~= 'E') or not square or not square:getFloor() then return false end
    local north = facing == 'S'
    local wallKey, doorKey = north and 'WallN' or 'WallW', north and 'DoorWallN' or 'DoorWallW'
    local windowFlag = north and IsoFlagType.WindowN or IsoFlagType.WindowW
    local doorFlag = north and IsoFlagType.doorN or IsoFlagType.doorW
    local wall
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if object ~= ignoreObject then
            local sprite = object:getSprite()
            local props = sprite and sprite:getProperties()
            if props then
                if props:has(windowFlag) or props:has(doorFlag) or props:has(doorKey) then return false end
                if props:has(wallKey) or props:has('WallNW') then wall = object end
                if P.blocksPoster(props, facing, sprite) then return false end
            end
            local overlay = object:getOverlaySprite()
            if overlay and P.overlayBlocksPoster(overlay, props, facing) then return false end
            local children = object:getChildSprites()
            if children then
                for j = 0, children:size() - 1 do
                    local instance = children:get(j)
                    local child = instance:getParentSprite()
                    if instance ~= ignoreChild and child and P.blocksPoster(child:getProperties(), facing, child) then return false end
                end
            end
        end
    end
    return wall ~= nil and (allowConstructed or not instanceof(wall, 'IsoThumpable'))
end

-- The inputs stay below Lua's exact-integer range. No client RNG or chunk-load
-- ordering is involved in the selection of a location or of a poster design.
function P.hash(text, seed)
    local value = seed or 0
    for i = 1, #text do value = (value * 131 + string.byte(text, i)) % 2147483647 end
    return value
end

return P
