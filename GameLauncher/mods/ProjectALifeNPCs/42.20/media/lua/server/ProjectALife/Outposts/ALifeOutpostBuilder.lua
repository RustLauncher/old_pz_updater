require "ProjectALife/Outposts/ALifeOutpostPresets"
require "ProjectALife/Records/ALifeLootRarity"
require "ProjectALife/Senses/ALifeFoliage"
require "ProjectALife/Outposts/ALifeOutpostArchitect"
require "ProjectALife/Outposts/ALifeBlueprintData"
require "ProjectALife/Outposts/ALifeOutpostLights"
require "ProjectALife/Compat/ALifeInterop"

ProjectALife = ProjectALife or {}

local Presets = ProjectALife.OutpostPresets
local Interop = ProjectALife.Interop

local Builder = {
    metrics = { resolved = 0, executed = 0, placed = 0, refused = 0, failed = 0,

        skipped = 0,

        vehiclesMissed = 0,

        doorsShut = 0, doorsStuckOpen = 0, streamHeld = 0 },

    litterCap = 18,

    clearanceDivisor = 6, clearanceMin = 1, clearanceMax = 4,

    clearanceSquaresPerUnit = 2,

    windowBoards = 3,

    generatorFuel = 1, generatorCondition = 80,
}
ProjectALife.OutpostBuilder = Builder

function Builder.boardsFor(item)
    local wanted = type(item) == "table" and tonumber(item.planks) or nil
    return math.max(1, math.min(4, math.floor(wanted or Builder.windowBoards)))
end

local function rng(seed)
    local state = math.floor(tonumber(seed) or 1) % 2147483647
    if state == 0 then state = 1 end
    return function()
        state = (state * 48271) % 2147483647
        return state / 2147483647
    end
end

local function randomUnit()
    if type(ZombRandFloat) == "function" then return ZombRandFloat(0, 1) end
    if type(ZombRand) == "function" then return ZombRand(1000000) / 1000000 end
    return 0.5
end

local function outward(side)
    if side == "N" then return 0, -1 end
    if side == "S" then return 0, 1 end
    if side == "W" then return -1, 0 end
    return 1, 0
end

local function along(side)
    if side == "N" or side == "S" then return 1, 0 end
    return 0, 1
end

function Builder.mainEntrance(doors, roadSide)
    if type(doors) ~= "table" or #doors == 0 then return nil end
    if roadSide ~= nil then
        for _, door in ipairs(doors) do
            if door.side == roadSide then return door end
        end
    end
    return doors[1]
end

local function interiorPoint(site, roll)
    local b = site.bounds
    local x = b.x1 + 1 + math.floor(roll() * math.max(1, b.x2 - b.x1 - 1))
    local y = b.y1 + 1 + math.floor(roll() * math.max(1, b.y2 - b.y1 - 1))
    return x, y, b.z or 0
end

local function yardPoint(site, roll, entrance)
    local b = site.bounds
    local ox, oy = 0, 1
    if entrance ~= nil then ox, oy = outward(entrance.side) end
    local baseX = entrance and entrance.x or math.floor((b.x1 + b.x2) / 2)
    local baseY = entrance and entrance.y or b.y2
    local reach = 3 + math.floor(roll() * 4)
    local sideways = math.floor(roll() * 5) - 2
    local ax, ay = along(entrance and entrance.side or "S")
    return baseX + ox * reach + ax * sideways, baseY + oy * reach + ay * sideways, b.z or 0
end

local function kitPoint(item, site, roll, entrance)
    if type(item.offset) == "table" then
        local b = site.bounds
        return math.floor((b.x1 + b.x2) / 2) + (tonumber(item.offset.x) or 0),
            math.floor((b.y1 + b.y2) / 2) + (tonumber(item.offset.y) or 0),
            b.z or 0
    end
    if item.at == "center" then
        local b = site.bounds
        return math.floor((b.x1 + b.x2) / 2), math.floor((b.y1 + b.y2) / 2), b.z or 0
    end

    local claimed = Builder.claimed
    local x, y, z
    for _ = 1, 6 do
        if item.at == "yard" then x, y, z = yardPoint(site, roll, entrance)
        else x, y, z = interiorPoint(site, roll) end
        if claimed == nil or not claimed[x .. ":" .. y .. ":" .. z] then break end
    end
    return x, y, z
end

Builder.trackSprites = { "blends_natural_01_69", "blends_natural_01_70",
    "blends_natural_01_71" }
Builder.trackFringe = { "blends_natural_01_80", "blends_natural_01_85",
    "blends_natural_01_86", "blends_natural_01_87" }

function Builder.trackOps(x1, y1, x2, y2, z, width)
    local ops = {}
    width = math.max(1, math.floor(tonumber(width) or 1))
    local stepX = (x2 > x1 and 1) or (x2 < x1 and -1) or 0
    local stepY = (y2 > y1 and 1) or (y2 < y1 and -1) or 0
    if stepX ~= 0 and stepY ~= 0 then return ops end  
    if stepX == 0 and stepY == 0 then return ops end

    local perpX = (stepY ~= 0) and 1 or 0
    local perpY = (stepX ~= 0) and 1 or 0
    local low = -math.floor((width - 1) / 2)
    local high = low + width - 1
    local px, py = x1, y1
    for _ = 0, 512 do
        for offset = low - 1, high + 1 do
            local tx, ty = px + perpX * offset, py + perpY * offset
            local edge = offset < low or offset > high
            local bag = edge and Builder.trackFringe or Builder.trackSprites
            local index = (math.abs(tx * 7 + ty * 13 + (edge and 3 or 0)) % #bag) + 1
            ops[#ops + 1] = { op = "floor", x = tx, y = ty, z = z, sprite = bag[index] }
        end
        if px == x2 and py == y2 then break end
        px, py = px + stepX, py + stepY
    end
    return ops
end

function Builder.resolve(preset, site, seed, probe)
    if type(preset) ~= "table" or type(site) ~= "table" or type(site.bounds) ~= "table" then
        return nil, "resolve_arguments_invalid"
    end
    probe = probe or {}
    if probe.complete == false then return nil, "building_not_loaded" end
    local roll = rng(seed)
    local sheet = { presetId = preset.id, siteId = site.id, ops = {}, mainEntrance = nil }
    local doors = type(probe.doors) == "function" and probe.doors() or {}
    local windows = type(probe.windows) == "function" and probe.windows() or {}
    local entrance
    local claimed = {}
    Builder.claimed = claimed
    local function put(op)
        sheet.ops[#sheet.ops + 1] = op
        if op.sprite ~= nil and op.x ~= nil then
            claimed[math.floor(op.x) .. ":" .. math.floor(op.y) .. ":" .. math.floor(op.z or 0)] = true
        end
    end
    for _, item in ipairs(preset.kit or {}) do
        local kind = item.op
        if kind == "mark_entrances" then
            entrance = Builder.mainEntrance(doors, probe.roadSide)
            if entrance ~= nil then
                sheet.mainEntrance = { x = entrance.x, y = entrance.y, z = entrance.z or 0, side = entrance.side }
                put({ op = "mark_entrance", x = entrance.x, y = entrance.y, z = entrance.z or 0, sprite = nil,
                    north = entrance.north, doorX = entrance.objectX, doorY = entrance.objectY })
            end
            for _, door in ipairs(doors) do
                if door ~= entrance then
                    put({ op = "lock_door", x = door.objectX or door.x, y = door.objectY or door.y,
                        z = door.z or 0, north = door.north, sprite = nil })
                end
            end
        elseif kind == "barricade_doors" then

            local planks = math.max(1, math.floor(tonumber(item.planks) or 3))
            for _, door in ipairs(doors) do
                if door ~= entrance then
                    put({ op = "barricade_door", x = door.objectX or door.x, y = door.objectY or door.y,
                        z = door.z or 0, north = door.north, planks = planks, sprite = nil })
                end
            end
        elseif kind == "barricade_windows" then
            local chance = tonumber(item.chance) or 100
            local boards = Builder.boardsFor(item)
            for _, window in ipairs(windows) do
                if roll() * 100 < chance then
                    put({ op = "barricade_window", x = window.objectX or window.x, y = window.objectY or window.y,
                        z = window.z or 0, north = window.north, sprite = nil, planks = boards,
                        material = item.material })
                end
            end
        elseif kind == "entry_barrier" then

            local anchor = sheet.mainEntrance
            if anchor ~= nil then
                local ox, oy = outward(anchor.side)
                local ax, ay = along(anchor.side)
                local run = math.max(1, math.floor(tonumber(item.run) or 1))
                local standoff = math.max(1, math.floor(tonumber(item.standoff) or 1))
                local pieces = type(item.pieces) == "table" and item.pieces or {}
                local sprite = ax ~= 0 and pieces.alongX or (pieces.alongY or pieces.alongX)
                local first = -math.floor((run - 1) / 2)
                for step = first, first + run - 1 do
                    put({ op = "tile", x = anchor.x + ox * standoff + ax * step,
                        y = anchor.y + oy * standoff + ay * step, z = anchor.z or 0, sprite = sprite })
                end
            end
        elseif kind == "yard_barrier" then

            local anchor = sheet.mainEntrance
            local span = math.max(1, math.floor(tonumber(item.span) or 1))
            local x, y, z = yardPoint(site, roll, nil)
            local ax, ay = 1, 0
            if anchor ~= nil then
                local ox, oy = outward(anchor.side)
                ax, ay = along(anchor.side)
                local reach = math.max(1, math.floor(tonumber(item.standoff) or 1))
                local shift = math.floor(roll() * (span + 1)) - span
                x, y, z = anchor.x + ox * reach + ax * shift, anchor.y + oy * reach + ay * shift, anchor.z or 0
            end
            for step = 0, span - 1 do
                put({ op = "tile", x = x + ax * step, y = y + ay * step, z = z, sprite = item.sprite })
            end
        elseif kind == "fortified_perimeter" then

            local b = site.bounds
            local z = b.z or 0
            local gateCenter = math.floor((b.x1 + b.x2) / 2)
            local gateX = gateCenter - 1
            local family = ProjectALife.OutpostArchitect.family[item.family or "palisade"] or ProjectALife.OutpostArchitect.family.palisade
            local plan = ProjectALife.OutpostArchitect.newPlan(seed)
            local gate = item.gate == "single"
                and { side = "S", at = gateCenter, kind = "wicket" }
                or { side = "S", at = gateX, kind = "gate" }
            ProjectALife.OutpostArchitect.box(plan, b.x1, b.y1, b.x2, b.y2, z, family, { gate })
            Builder.absorbPlan(sheet, plan, put)
            if sheet.mainEntrance == nil then
                sheet.mainEntrance = { x = gateCenter, y = b.y2 + 1, z = z, side = "S" }
            end
        elseif kind == "guard_tower" then

            local x, y, z = kitPoint(item, site, roll, sheet.mainEntrance)
            local plan = ProjectALife.OutpostArchitect.newPlan(seed)
            ProjectALife.OutpostArchitect.tower(plan, x, y, z, item.door or "S", item.facing or "S")
            Builder.absorbPlan(sheet, plan, put)
        elseif kind == "compound" then

            local b = site.bounds
            local cx = math.floor((b.x1 + b.x2) / 2)
            local cy = math.floor((b.y1 + b.y2) / 2)
            local half = math.floor((b.x2 - b.x1) / 2)
            local plan = ProjectALife.OutpostArchitect.compound(cx, cy, b.z or 0, half, seed)
            Builder.absorbPlan(sheet, plan, put)
            sheet.mainEntrance = { x = cx, y = cy + half + 1, z = b.z or 0, side = "S" }
            sheet.conflicts = (sheet.conflicts or 0) + (plan.conflicts or 0)
            sheet.refusals = plan.refusals
        elseif kind == "checkpoint" then

            local plan = ProjectALife.OutpostArchitect.checkpoint(math.floor(site.x), math.floor(site.y),
                site.bounds and site.bounds.z or 0, seed)
            Builder.absorbPlan(sheet, plan, put)
            sheet.mainEntrance = sheet.mainEntrance or { x = math.floor(site.x), y = math.floor(site.y) - 8,
                z = site.bounds and site.bounds.z or 0, side = "S" }
            sheet.conflicts = (sheet.conflicts or 0) + (plan.conflicts or 0)
            sheet.refusals = plan.refusals
        elseif kind == "blueprint" then
            local spec = type(preset.blueprint) == "table" and preset.blueprint or {}
            local plan, why = ProjectALife.Blueprints.plan(item.id, { posts = preset.posts, loot = spec.loot })
            if plan == nil then
                Builder.claimed = nil
                return nil, why
            end
            Builder.absorbPlan(sheet, plan, put)
            local door = type(spec.entrance) == "table" and spec.entrance or { x = 0, y = 0, side = "S" }
            sheet.mainEntrance = { x = plan.anchor.x + door.x, y = plan.anchor.y + door.y,
                z = plan.anchor.z, side = door.side or "S" }
            sheet.conflicts = (sheet.conflicts or 0) + (plan.conflicts or 0)
            sheet.refusals = plan.refusals
        elseif kind == "path" then

            local b = site.bounds
            local cx = math.floor((b.x1 + b.x2) / 2)
            local cy = math.floor((b.y1 + b.y2) / 2)
            local pz = b.z or 0
            local points = type(item.points) == "table" and item.points or {}
            for index = 1, #points - 1 do
                local from, to = points[index], points[index + 1]
                for _, op in ipairs(Builder.trackOps(cx + from.x, cy + from.y,
                        cx + to.x, cy + to.y, pz, item.width)) do put(op) end
            end
        elseif kind == "pen" then
            local x, y, z = kitPoint(item, site, roll, sheet.mainEntrance)
            local plan = ProjectALife.OutpostArchitect.newPlan(seed)
            ProjectALife.OutpostArchitect.pen(plan, x, y, item.w or 7, item.h or 5, z, item.animals)
            Builder.absorbPlan(sheet, plan, put)
        elseif kind == "tent" then
            local x, y, z = kitPoint(item, site, roll, sheet.mainEntrance)

            put({ op = "object", x = x - 1, y = y, z = z, sprite = "camping_01_2" })
            put({ op = "object", x = x, y = y, z = z, sprite = "camping_01_3" })
        elseif kind == "campfire" then
            local x, y, z = kitPoint(item, site, roll, sheet.mainEntrance)

            put({ op = "campfire", x = x, y = y, z = z, sprite = "camping_01_4" })
        elseif kind == "object" and type(item.pieces) == "table" then

            local x, y, z = kitPoint(item, site, roll, sheet.mainEntrance)
            for _, piece in ipairs(item.pieces) do
                put({ op = "object", x = x + (piece[2] or 0), y = y + (piece[3] or 0), z = z,
                    sprite = piece[1] })
            end
        elseif kind == "object" or kind == "radio" or kind == "container" then
            local x, y, z = kitPoint(item, site, roll, sheet.mainEntrance)
            if kind == "radio" then

                put({ op = "object", x = x, y = y, z = z, sprite = Presets.Dressing.table })
            end
            put({ op = kind, x = x, y = y, z = z, sprite = item.sprite, loot = item.loot,
                draws = item.draws })
        elseif kind == "blood" then

            local count = math.max(1, math.floor(tonumber(item.count) or 6))
            for _ = 1, count do
                local x, y, z = kitPoint(item, site, roll, sheet.mainEntrance)
                put({ op = "blood", x = x, y = y, z = z,
                    splats = 1 + math.floor(roll() * 4), sprite = nil })
            end
        elseif kind == "items" then
            local count = math.max(1, math.floor(tonumber(item.count) or 3))
            for _ = 1, count do
                local x, y, z = kitPoint(item, site, roll, sheet.mainEntrance)
                put({ op = "items", x = x, y = y, z = z, item = item.item,
                    quantity = 1 + math.floor(roll() * math.max(1,
                        tonumber(item.stack) or 1)), sprite = nil })
            end
        elseif kind == "light" or kind == "generator" then
            local x, y, z = kitPoint(item, site, roll, sheet.mainEntrance)
            put({ op = kind, x = x, y = y, z = z, sprite = item.sprite,
                fuel = item.fuel, condition = item.condition })
        elseif kind == "dress_litter" then

            local b = site.bounds
            local kinds = type(item.kinds) == "table" and item.kinds or {}
            local laid = 0
            for _ = 1, (#kinds > 0) and math.max(0, math.floor(tonumber(item.heaps) or 0)) or 0 do
                local cx, cy, cz = interiorPoint(site, roll)
                local pool = Presets.Dressing.litter[kinds[1 + math.floor(roll() * #kinds) % #kinds]]
                for _ = 1, 2 + math.floor(roll() * 2) do
                    if laid >= Builder.litterCap or type(pool) ~= "table" or #pool == 0 then break end
                    local x = math.max(b.x1 + 1, math.min(b.x2 - 1, cx + math.floor(roll() * 3) - 1))
                    local y = math.max(b.y1 + 1, math.min(b.y2 - 1, cy + math.floor(roll() * 3) - 1))
                    put({ op = "litter", x = x, y = y, z = cz,
                        sprite = pool[1 + math.floor(roll() * #pool) % #pool] })
                    laid = laid + 1
                end
            end
        elseif kind == "site_survey" or kind == "site_clearance" then

            local b = site.bounds
            local w = tonumber(item.w) or (b.x2 - b.x1 + 1)
            local h = tonumber(item.h) or (b.y2 - b.y1 + 1)
            local margin = tonumber(item.margin)
            if kind == "site_clearance" and margin == nil then
                margin = math.max(Builder.clearanceMin, math.min(Builder.clearanceMax,
                    math.floor(math.min(w, h) / Builder.clearanceDivisor)))
            end
            if kind == "site_clearance" then

                local ring = math.max(0, math.floor(margin))
                for row = b.y1 - ring, b.y1 + math.floor(h) - 1 + ring do
                    put({ op = kind, x = b.x1 - ring, y = row, z = b.z or 0,
                        w = math.floor(w) + 2 * ring, h = 1, ring = ring, sprite = nil })
                end
            else
                put({ op = kind, x = b.x1, y = b.y1, z = b.z or 0, w = w, h = h, margin = margin,
                    sprite = nil, roadAllowance = item.roadAllowance })
            end
        end
    end
    Builder.claimed = nil
    sheet.planVersion = tonumber(preset.planVersion)

    for _, op in ipairs(sheet.ops) do
        if op.op == "thumpable" then
            op.op, op.north, op.parapet, op.fence = "tile", nil, nil, nil
        end
    end
    Builder.metrics.resolved = Builder.metrics.resolved + 1
    return sheet
end

function Builder.absorbPlan(sheet, plan, put)
    for _, op in ipairs(plan.ops) do
        if op.op == "track" then
            for _, floor in ipairs(Builder.trackOps(op.x, op.y, op.x2, op.y2, op.z, op.width)) do
                put(floor)
            end
        else
            put(op)
        end
    end
    sheet.posts = sheet.posts or {}
    for _, post in ipairs(plan.posts) do sheet.posts[#sheet.posts + 1] = post end
end

local function authoritative()
    if type(isClient) == "function" and isClient() then return false end
    return true
end

local function squareAt(x, y, z)
    local fx, fy, fz = math.floor(x), math.floor(y), math.floor(z or 0)
    local square
    if Builder.groundLoaded(fx, fy) then
        pcall(function()
            square = getCell():getGridSquare(fx, fy, fz)
            if square == nil and getWorld():isValidSquare(fx, fy, fz) then
                square = getCell():createNewGridSquare(fx, fy, fz, true)
            end
        end)
    end
    return square
end

local function transmit(object)
    if type(isServer) == "function" and isServer() then
        pcall(function() object:transmitCompleteItemToClients() end)
    end
end

function Builder.placeObject(x, y, z, sprite)
    local placed
    pcall(function()
        local square = squareAt(x, y, z)
        if square == nil then return end

        local texture = getSprite(sprite)
        if texture == nil then
            Builder.metrics = Builder.metrics or {}
            Builder.metrics.objectsRefusedNoSprite =
                (Builder.metrics.objectsRefusedNoSprite or 0) + 1
            return
        end
        local object = IsoObject.new(getCell(), square, texture)
        if object == nil then return end
        square:AddTileObject(object)
        transmit(object)

        pcall(function() square:RecalcProperties() end)
        pcall(function() square:RecalcAllWithNeighbours(true) end)
        placed = object
    end)
    return placed
end

function Builder.thumpableInfo(name, sprite, north, extra)
    local info = {
        name = tostring(name or "Fortification"), sprite = sprite, northSprite = sprite,
        north = north == true, canBarricade = false, canPassThrough = false,
        blockAllTheSquare = true, isThumpable = true, isWallLike = true, hoppable = false,
        dismantable = false, canBePlastered = false, isContainer = false, isDoor = false,
        isDoorFrame = false, isStairs = false, isCorner = false, isFloor = false,
        thumpDmg = 8, crossSpeed = 1.0, modData = {},
    }
    if type(extra) == "table" then
        for key, value in pairs(extra) do info[key] = value end
    end
    return info
end

function Builder.applyThumpableInfo(object, info)
    pcall(function() object:setName(info.name) end)
    pcall(function() object:setCanPassThrough(info.canPassThrough == true) end)
    pcall(function() object:setCanBarricade(info.canBarricade == true) end)
    pcall(function() object:setThumpDmg(math.floor(tonumber(info.thumpDmg) or 8)) end)
    pcall(function() object:setIsContainer(info.isContainer == true) end)
    pcall(function() object:setIsDoor(info.isDoor == true) end)
    pcall(function() object:setIsDoorFrame(info.isDoorFrame == true) end)
    pcall(function() object:setCrossSpeed(tonumber(info.crossSpeed) or 1.0) end)
    pcall(function() object:setBlockAllTheSquare(info.blockAllTheSquare == true) end)
    pcall(function() object:setIsDismantable(info.dismantable == true) end)
    pcall(function() object:setCanBePlastered(info.canBePlastered == true) end)
    pcall(function() object:setIsHoppable(info.hoppable == true) end)
    pcall(function() object:setIsThumpable(info.isThumpable == true) end)
    pcall(function() object:setIsFloor(info.isFloor == true) end)
    if info.isStairs then pcall(function() object:setIsStairs(true) end) end
    if info.isCorner then pcall(function() object:setCorner(true) end) end
end

function Builder.flagHas(properties, name)
    local flag = IsoFlagType ~= nil and IsoFlagType[name] or nil
    return flag ~= nil and properties:has(flag) == true
end

function Builder.nameHas(properties, name)
    return properties:has(name) == true
end

function Builder.flag(properties, name)
    if properties == nil then return false end
    local ok, found = pcall(Builder.flagHas, properties, name)
    if ok and found == true then return true end
    ok, found = pcall(Builder.nameHas, properties, name)
    return ok and found == true
end

Builder.flagGroups = {
    wall = { "WallN", "WallW", "WallNW", "collideN", "collideW" },
    fixture = { "WallN", "WallW", "WallNW", "DoorWallN", "DoorWallW", "WindowN", "WindowW", "solidfloor" },
}
Builder.flagMemo = { wall = {}, fixture = {} }
Builder.flagMemoSize = 0
Builder.flagMemoCap = 4096

function Builder.spriteHas(group, sprite, name)
    if Builder.flagMemoOwner ~= IsoFlagType then
        Builder.flagMemo, Builder.flagMemoSize, Builder.flagMemoOwner = { wall = {}, fixture = {} }, 0, IsoFlagType
    end
    local memo = Builder.flagMemo[group]
    local known
    if type(name) == "string" then known = memo[name] end
    if known ~= nil then return known end
    local props = sprite ~= nil and type(sprite.getProperties) == "function" and sprite:getProperties() or nil
    if props == nil then return nil end
    local flags, found = Builder.flagGroups[group], false
    for index = 1, #flags do
        if Builder.flag(props, flags[index]) then
            found = true
            break
        end
    end
    if type(name) == "string" and IsoFlagType ~= nil then
        if Builder.flagMemoSize >= Builder.flagMemoCap then
            Builder.flagMemo, Builder.flagMemoSize = { wall = {}, fixture = {} }, 0
            memo = Builder.flagMemo[group]
        end
        memo[name] = found
        Builder.flagMemoSize = Builder.flagMemoSize + 1
    end
    return found
end

function Builder.groundLoaded(x, y)
    if type(Builder.adapters) == "table" and type(Builder.adapters.groundLoaded) == "function" then
        return Builder.adapters.groundLoaded(x, y) == true
    end
    if type(getCell) ~= "function" then return true end
    local loaded = false
    pcall(function()
        local cell = getCell()
        if cell == nil then return end
        local square = cell:getGridSquare(math.floor(x), math.floor(y), 0)
        loaded = square ~= nil and (square.getChunk == nil or square:getChunk() ~= nil)
    end)
    return loaded
end

function Builder.isOpeningSprite(spriteName)
    local opening = false
    pcall(function()
        local sprite = getSprite(spriteName)
        local props = sprite and sprite:getProperties() or nil
        if props == nil then return end
        for _, name in ipairs({ "doorN", "doorW", "windowN", "windowW", "WindowN", "WindowW" }) do
            if Builder.flag(props, name) then opening = true return end
        end
    end)
    return opening
end

function Builder.clearable(object)
    if object == nil then return false end
    if instanceof(object, "IsoWorldInventoryObject") then return false end
    local removable = false
    pcall(function()
        if instanceof(object, "IsoTree") then
            removable = true
            return
        end

        if instanceof(object, "IsoWindow") or instanceof(object, "IsoDoor")
                or instanceof(object, "IsoThumpable") then
            return
        end

        if type(object.isStairsObject) == "function" and object:isStairsObject() == true then
            return
        end
        local sprite = object:getSprite()
        if sprite == nil then return end
        local name = sprite:getName()
        if Builder.spriteHas("fixture", sprite, name) ~= false then return end

        removable = ProjectALife.Foliage.clearable(sprite:getName())
    end)
    return removable
end

function Builder.clearSquare(square)
    pcall(function()
        local objects = square:getObjects()
        for index = (objects and objects:size() or 0) - 1, 0, -1 do
            local object = objects:get(index)
            if Builder.clearable(object) then

                square:transmitRemoveItemFromSquare(object)
            end
        end
    end)
end

function Builder.clearVehicles(square)
    local removed = 0
    pcall(function()
        local vehicle = square:getVehicleContainer()
        if vehicle == nil or not instanceof(vehicle, "BaseVehicle") then return end
        local data = vehicle:getModData()
        if type(data) == "table" and data.ProjectALifeOutpostVehicle == true then return end
        if vehicle:getDriver() ~= nil or vehicle:isKeysInIgnition() then return end
        vehicle:permanentlyRemove()
        removed = 1
    end)
    return removed
end

function Builder.clearSpace(x, y, z, w, h, margin)
    margin = math.max(0, math.floor(tonumber(margin) or 0))
    w = math.max(1, math.floor(tonumber(w) or 1))
    h = math.max(1, math.floor(tonumber(h) or 1))
    local removed = 0
    for px = math.floor(x) - margin, math.floor(x) + w - 1 + margin do
        for py = math.floor(y) - margin, math.floor(y) + h - 1 + margin do
            local square = squareAt(px, py, z)
            if square ~= nil then
                pcall(function()
                    local objects = square:getObjects()
                    for index = (objects and objects:size() or 0) - 1, 0, -1 do
                        local object = objects:get(index)
                        if Builder.clearable(object) then
                            square:transmitRemoveItemFromSquare(object)
                            removed = removed + 1
                        end
                    end
                end)
                removed = removed + Builder.clearVehicles(square)
            end
        end
    end
    return removed
end

function Builder.placeThumpable(x, y, z, sprite, north, extra)
    local placed
    pcall(function()
        local square = squareAt(x, y, z)
        if square == nil then return end

        Builder.clearSquare(square)
        local info = Builder.thumpableInfo("Fortification", sprite, north, extra)
        local object = IsoThumpable.new(getCell(), square, sprite, north == true, info)
        if object == nil then return end
        Builder.applyThumpableInfo(object, info)
        object:setMaxHealth(600)
        object:setHealth(600)
        object:setBreakSound("BreakObject")
        object:setThumpSound("ZombieThumpGeneric")
        square:AddSpecialObject(object)
        transmit(object)
        placed = object
    end)
    return placed
end

function Builder.placeStairs(x, y, z, sprite, north, level)
    local placed
    pcall(function()
        local square = squareAt(x, y, z)
        if square == nil then return end
        local object
        pcall(function()
            if square.AddStairs ~= nil then
                object = square:AddStairs(north == true, math.floor(tonumber(level) or 0), sprite, nil, nil)
            end
        end)
        if object == nil then
            local info = Builder.thumpableInfo("Stairs", sprite, north, { isStairs = true, canPassThrough = true, blockAllTheSquare = false })
            object = IsoThumpable.new(getCell(), square, sprite, north == true, info)
            if object == nil then return end
            Builder.applyThumpableInfo(object, info)
            square:AddSpecialObject(object)
        end
        pcall(function() object:setIsStairs(true) end)
        pcall(function() object:setCanBarricade(false) end)
        pcall(function() object:setMaxHealth(700); object:setHealth(700) end)
        pcall(function() square:RecalcAllWithNeighbours(true) end)
        transmit(object)
        placed = object
    end)
    return placed
end

function Builder.placeFloor(x, y, z, sprite)
    local placed, previous
    pcall(function()
        local square = squareAt(x, y, z)
        if square == nil then return end

        Builder.clearSquare(square)

        if math.floor(tonumber(z) or 0) == 0 then
            pcall(function()
                local floor = square:getFloor()
                local was = floor and floor:getSprite() and floor:getSprite():getName()
                if type(was) == "string" and was ~= sprite then previous = was end
            end)
        end
        local object = square:addFloor(sprite)
        if object == nil then return end

        placed = object
    end)
    return placed, previous
end

function Builder.placeMapTile(x, y, z, spriteName)
    local placed
    pcall(function()
        local square = squareAt(x, y, z)
        if square == nil then return end
        Builder.clearSquare(square)
        local sprite = getSprite(spriteName)
        if sprite == nil then return end
        local props = sprite:getProperties()

        local function has(name) return Builder.flag(props, name) end
        local object
        if has("doorN") or has("doorW") then
            object = IsoDoor.new(getCell(), square, spriteName, has("doorN"))
            if object ~= nil then pcall(function() object:setLockedByKey(false) end) end
        elseif has("WallN") or has("WallW") then
            object = IsoThumpable.new(getCell(), square, spriteName, has("WallN"), {})

            if object ~= nil then pcall(function() object:setIsThumpable(false) end) end
        elseif has("windowN") or has("windowW") then
            pcall(function()
                object = IsoWindow.new(getCell(), square, sprite, has("windowN"))
                object:setIsLocked(false)
            end)
        elseif has("WindowN") or has("WindowW") then
            pcall(function() object = IsoWindowFrame.new(getCell(), square, sprite, has("WindowN")) end)
        end
        if object == nil then object = IsoObject.new(getCell(), square, sprite) end
        if object == nil then return end
        square:AddSpecialObject(object)
        transmit(object)
        pcall(function() square:RecalcProperties() end)
        pcall(function() square:RecalcAllWithNeighbours(true) end)
        placed = object
    end)
    return placed
end

function Builder.placeVehicle(x, y, z, script, facing, fuel, siteId)
    local placed
    local gate = ProjectALife.CleanupLock
    if gate ~= nil and gate.refuse("vehicle") then return nil end
    pcall(function()
        local square = squareAt(x, y, z)
        if square == nil or type(addVehicleDebug) ~= "function" then return end
        local direction
        pcall(function() direction = IsoDirections[facing or "S"] end)
        local vehicle = addVehicleDebug(script, direction, nil, square)
        if vehicle == nil then return end
        pcall(function()
            local tank = vehicle:getPartById("GasTank")
            if tank ~= nil then
                tank:setContainerContentAmount(math.max(0, tonumber(fuel) or 0))
                vehicle:transmitPartModData(tank)
            end
        end)
        pcall(function()
            local data = vehicle:getModData()
            data.ProjectALifeOutpostVehicle = true
            data.ProjectALifeOutpostVehicleSite = siteId
        end)
        placed = vehicle
    end)
    return placed
end

function Builder.doorAt(square, north)
    local found
    pcall(function()
        local objects = square:getObjects()
        if objects == nil then return end
        for index = 0, objects:size() - 1 do
            local object = objects:get(index)
            local isDoor = false
            pcall(function()
                isDoor = type(instanceof) == "function" and instanceof(object, "IsoDoor")
            end)
            if isDoor then
                local sameWay = true
                pcall(function() sameWay = object:getNorth() == (north == true) end)
                if sameWay then found = object return end
            end
        end
    end)
    return found
end

function Builder.placeDoor(x, y, z, sprite, north)
    local placed
    pcall(function()
        local square = squareAt(x, y, z)
        if square == nil then return end

        local existing = Builder.doorAt(square, north)
        if existing ~= nil then
            Builder.metrics = Builder.metrics or {}
            Builder.metrics.doorsReused = (Builder.metrics.doorsReused or 0) + 1
            placed = existing
            return
        end
        local object = IsoDoor.new(getCell(), square, sprite, north == true)
        if object == nil then return end
        object:setLockedByKey(false)
        square:AddSpecialObject(object)
        transmit(object)
        placed = object
    end)
    return placed
end

function Builder.fillContainer(container, rows, draws, roll)
    if container == nil or type(rows) ~= "table" or #rows == 0 then return 0 end
    roll = type(roll) == "function" and roll or randomUnit
    local total = 0
    for _, row in ipairs(rows) do total = total + math.max(0, tonumber(row[2]) or 0) end
    if total <= 0 then return 0 end
    local added = 0
    for _ = 1, math.max(0, math.floor(tonumber(draws) or 0)) do
        local ticket, chosen = roll() * total, rows[#rows]
        for _, row in ipairs(rows) do
            ticket = ticket - math.max(0, tonumber(row[2]) or 0)
            if ticket < 0 then chosen = row; break end
        end
        local pack = 1 + math.floor(roll() * math.max(1, tonumber(chosen[3]) or 1))
        if not ProjectALife.LootRarity.allowedItem(chosen[1]) then pack = 0 end
        for _ = 1, pack do
            local ok = pcall(function() container:AddItem(chosen[1]) end)
            if ok then added = added + 1 end
        end
    end
    return added
end

function Builder.addContents(container, list)
    local added = 0
    if container == nil or type(list) ~= "table" then return 0 end
    for _, entry in ipairs(ProjectALife.LootRarity.filterList(list)) do
        for _ = 1, math.max(1, math.floor(tonumber(entry[2]) or 1)) do
            if pcall(function() container:AddItem(entry[1]) end) then added = added + 1 end
        end
    end
    return added
end

function Builder.alreadyThere(x, y, z, sprite)
    local found = false
    if type(sprite) ~= "string" then return false end
    pcall(function()
        local square = squareAt(x, y, z)
        local objects = square ~= nil and square:getObjects() or nil
        for index = 0, (objects and objects:size() or 0) - 1 do
            local object = objects:get(index)
            local art = object ~= nil and object:getSprite() or nil
            if art ~= nil and art:getName() == sprite then
                found = true
                return
            end
        end
    end)
    return found
end

function Builder.placeContainer(x, y, z, sprite, loot, draws, roll, contents)
    local placed, added = nil, 0
    pcall(function()
        local square = squareAt(x, y, z)
        if square == nil then return end

        local texture = getSprite(sprite)
        if texture == nil then
            Builder.metrics = Builder.metrics or {}
            Builder.metrics.cratesRefusedNoSprite =
                (Builder.metrics.cratesRefusedNoSprite or 0) + 1
            return
        end
        local object = IsoObject.new(getCell(), square, texture)
        if object == nil then return end

        local container = ItemContainer.new("crate", square, object)
        if container == nil then return end
        object:setContainer(container)
        container = object:getContainer() or container
        pcall(function() container:setType("crate") end)
        pcall(function() container:setCapacity(50) end)
        pcall(function() container:setExplored(true) end)
        square:AddTileObject(object)
        added = Builder.fillContainer(container, Presets.Stores[loot], draws, roll)
            + Builder.addContents(container, contents)
        transmit(object)
        placed = object
    end)
    return placed, added
end

local function objectOn(square, className, north)
    local found
    pcall(function()
        local objects = square:getObjects()
        for index = 0, objects:size() - 1 do
            local object = objects:get(index)
            if object ~= nil and instanceof(object, className)
                    and (north == nil or object:getNorth() == north) then found = object return end
        end
    end)
    return found
end

function Builder.closeSheet(window)
    local ready, changed = false, false
    pcall(function()
        if window == nil then return end

        if window.canAddCurtain ~= nil and window.isCurtainOpen ~= nil then
            if window:HasCurtains() == nil then
                if not window:canAddCurtain() then return end
                if window:getSquare() == nil or window:getOppositeSquare() == nil then return end
                window:addSheet(nil)
                changed = window:HasCurtains() ~= nil
            end
            if window:HasCurtains() == nil then return end
            if window:isCurtainOpen() then window:toggleCurtain(); changed = true end
            ready = not window:isCurtainOpen()
            return
        end
        local curtain = window:HasCurtains() 
        if curtain == nil then

            if window:getSquare() == nil or window:getOppositeSquare() == nil then return end
            window:addSheet(nil)
            curtain = window:HasCurtains()
            changed = curtain ~= nil
        end
        if curtain == nil then return end

        if curtain:IsOpen() then curtain:ToggleDoorSilent(); changed = true end
        ready = not curtain:IsOpen()
    end)
    return ready, changed
end

function Builder.closeDoor(door)
    if door == nil or type(door.IsOpen) ~= "function" then return false end
    local ok, open = pcall(door.IsOpen, door)
    if not ok then return false end
    if open ~= true then return true end
    local traversal = ProjectALife.ObstacleTraversal
    if type(door.isBarricaded) == "function" then
        local asked, barricaded = pcall(door.isBarricaded, door)
        if not asked or barricaded == true then return false end
    end
    if type(door.isObstructed) == "function" then
        local asked, blocked = pcall(door.isObstructed, door)
        if not asked or blocked == true then return false end
    end
    local grouped = traversal ~= nil and type(traversal.toggleGroup) == "function" and traversal.toggleGroup(door)
    if grouped ~= true then
        if type(door.ToggleDoorSilent) ~= "function" or not pcall(door.ToggleDoorSilent, door) then return false end
        if traversal ~= nil and type(traversal.settleLeaf) == "function" then traversal.settleLeaf(door) end
    end
    ok, open = pcall(door.IsOpen, door)
    return ok and open ~= true
end

function Builder.shutBeforeSealing(door)
    if door == nil or type(door.IsOpen) ~= "function" then return false end
    local ok, open = pcall(door.IsOpen, door)
    if not ok or open ~= true then return true end
    local shut = Builder.closeDoor(door)
    if shut then Builder.metrics.doorsShut = (Builder.metrics.doorsShut or 0) + 1
    else Builder.metrics.doorsStuckOpen = (Builder.metrics.doorsStuckOpen or 0) + 1 end
    return shut
end

function Builder.shutDoorAt(x, y, z, north)
    local shut = false
    pcall(function()
        for _, step in ipairs({ { 0, 0 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            local square = squareAt(x + step[1], y + step[2], z)
            local found = square and objectOn(square, "IsoDoor", north) or nil
            if found ~= nil then shut = Builder.shutBeforeSealing(found) return end
            if north ~= nil then return end
        end
    end)
    return shut
end

function Builder.barricadeFresh(barricade)
    local fresh = false
    pcall(function()
        fresh = (tonumber(barricade:getNumPlanks()) or 0) == 0 and barricade:isMetal() ~= true
            and barricade:isMetalBar() ~= true
    end)
    return fresh
end

function Builder.markBarricade(barricade, site)
    local id = type(site) == "table" and site.id or site
    if barricade == nil or id == nil then return false end
    local ok = pcall(function() barricade:getModData().ProjectALifeOutpostSite = tostring(id) end)
    return ok
end

function Builder.barricadeOpening(x, y, z, planks, className, material, north)
    local done, marked = false, false
    pcall(function()
        local target, home
        for _, step in ipairs({ { 0, 0 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            local square = squareAt(x + step[1], y + step[2], z)
            local found = square and objectOn(square, className, north) or nil
            if found ~= nil and (north ~= nil or not found:isBarricaded()) then target, home = found, square break end
            if north ~= nil then break end 
        end
        if target == nil then return end
        local sheetReady = true
        if className == "IsoWindow" then sheetReady = Builder.closeSheet(target)
        elseif className == "IsoDoor" then
            Builder.closeSheet(target)

            if not target:isBarricaded() and Builder.shutBeforeSealing(target) and target:getSquare() ~= home then
                target = objectOn(home, className, north) or target
            end
        end
        if target:isBarricaded() then done = sheetReady return end
        local barricade = IsoBarricade.AddBarricadeToObject(target, false)
        if barricade == nil then return end
        local fresh = Builder.barricadeFresh(barricade)
        local heat = ProjectALife.BaseHeat
        if heat ~= nil and type(heat.stampNpcBarricade) == "function" then heat.stampNpcBarricade(barricade) end
        if material == "metal" then

            barricade:addMetal(nil, nil)
        else
            for _ = 1, math.max(1, math.floor(tonumber(planks) or 2)) do
                barricade:addPlank(nil, nil)
            end
        end
        if fresh then marked = Builder.markBarricade(barricade, Builder.currentSite) end
        transmit(barricade)
        done = sheetReady
    end)
    return done, marked
end

function Builder.barricadeWindow(x, y, z, planks, material, north)
    local staged = ProjectALife.StagedBoarding
    if staged ~= nil and type(staged.board) == "function" then
        local ok, handled, result, marked = pcall(staged.board, x, y, z, planks, material, Builder.currentSite)
        if ok and handled == true then return result == true, marked == true end
    end
    return Builder.barricadeOpening(x, y, z, planks, "IsoWindow", material, north)
end

function Builder.barricadeDoor(x, y, z, planks, north)
    return Builder.barricadeOpening(x, y, z, planks, "IsoDoor", nil, north)
end

function Builder.lockDoor(x, y, z, north)
    local done = false
    pcall(function()

        local door, home
        for _, step in ipairs({ { 0, 0 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            local square = squareAt(x + step[1], y + step[2], z)
            local found = square and objectOn(square, "IsoDoor", north) or nil
            if found ~= nil then door, home = found, square break end
            if north ~= nil then break end
        end
        if door == nil then return end
        Builder.closeSheet(door)

        if Builder.shutBeforeSealing(door) and door:getSquare() ~= home then
            door = objectOn(home, "IsoDoor", north) or door
        end
        door:setLockedByKey(true)
        transmit(door)
        done = true
    end)
    return done
end

function Builder.silenceRadio(object)
    local was = false
    pcall(function()
        local data = object ~= nil and object.getDeviceData ~= nil and object:getDeviceData() or nil
        if data == nil then return end
        pcall(function() was = data:getIsTurnedOn() == true end)
        data:setTurnedOnRaw(false)

        if object.getObjectIndex ~= nil and object:getObjectIndex() >= 0 then transmit(object) end
    end)
    return was
end

function Builder.placeRadio(x, y, z, sprite, siteId)
    local placed
    pcall(function()
        local square = squareAt(x, y, z)
        if square == nil then return end

        local texture = getSprite(sprite)
        if texture == nil then
            Builder.metrics = Builder.metrics or {}
            Builder.metrics.radiosRefusedNoSprite =
                (Builder.metrics.radiosRefusedNoSprite or 0) + 1
            return
        end
        local object
        if IsoRadio ~= nil and type(IsoRadio.new) == "function" then
            object = IsoRadio.new(getCell(), square, texture)
        end
        if object == nil then object = IsoObject.new(getCell(), square, texture) end
        if object == nil then return end
        pcall(function() object:getModData().ProjectALifeRadioSite = siteId end)
        Builder.silenceRadio(object)
        square:AddSpecialObject(object)
        transmit(object)
        pcall(function() object:transmitModData() end)
        placed = object
    end)
    return placed
end

function Builder.placeBlood(x, y, z, splats)
    if type(addBloodSplat) ~= "function" then return false end
    local ok = false
    pcall(function()
        local square = squareAt(x, y, z)
        if square == nil then return end
        addBloodSplat(square, math.max(1, math.floor(tonumber(splats) or 1)))
        ok = true
    end)
    return ok
end

Builder.itemSpots = { { 0.5, 0.5 }, { 0.3, 0.3 }, { 0.7, 0.7 }, { 0.7, 0.3 }, { 0.3, 0.7 },
    { 0.5, 0.3 }, { 0.5, 0.7 }, { 0.3, 0.5 }, { 0.7, 0.5 } }

function Builder.placeItems(x, y, z, fullType, quantity)
    if type(fullType) ~= "string" or fullType == "" then return false end
    if not ProjectALife.LootRarity.allowedItem(fullType) then return true end
    local ok = false
    pcall(function()
        local square = squareAt(x, y, z)
        if square == nil then return end
        local spots = Builder.itemSpots
        local site = Builder.currentSite
        for index = 1, math.max(1, math.floor(tonumber(quantity) or 1)) do
            local spot = spots[(index - 1) % #spots + 1]
            local item = square:AddWorldInventoryItem(fullType, spot[1], spot[2], 0)
            if item ~= nil and type(site) == "table" and type(item.getModData) == "function" then
                pcall(function() item:getModData().ProjectALifeSiteId = tostring(site.id) end)
            end
        end
        ok = true
    end)
    return ok
end

function Builder.placeLight(x, y, z, sprite)
    local placed
    pcall(function()
        local square = squareAt(x, y, z)
        local art = square ~= nil and getSprite(sprite) or nil
        if art == nil then return end
        local object = IsoLightSwitch.new(getCell(), square, art, -1)
        if object == nil then return end

        object:addLightSourceFromSprite()
        local lights = ProjectALife.OutpostLights
        local selfPowered = lights ~= nil and lights.enabled() and lights.powerLamp(object)
        if not selfPowered then
            object:setUseBatteryDirect(false)
            object:setActive(true, true)
        end
        square:AddSpecialObject(object)
        if selfPowered then
            lights.placed(object, type(Builder.currentSite) == "table" and Builder.currentSite.id or nil)
        end
        transmit(object)
        placed = object
    end)
    return placed
end

function Builder.placeCampfire(x, y, z, sprite)
    local lights = ProjectALife.OutpostLights
    if lights ~= nil and lights.enabled() then
        local square = squareAt(x, y, z)
        local site = Builder.currentSite
        if square ~= nil then
            local _, _, fire = lights.campfireAt(square, type(site) == "table" and site.id or nil, lights.hours())
            if fire ~= nil then return fire end
        end
    end
    return Builder.placeObject(x, y, z, sprite)
end

function Builder.placeAnimal(x, y, z, animalType)
    local placed
    pcall(function()
        if type(addAnimal) ~= "function" then return end
        if type(AnimalDefinitions) ~= "table" or type(AnimalDefinitions.getDef) ~= "function" then
            return
        end
        local definition = AnimalDefinitions.getDef(animalType)
        if definition == nil then return end
        local breeds = definition:getBreeds()
        if breeds == nil or breeds:size() < 1 then return end
        local animal = addAnimal(getCell(), math.floor(x), math.floor(y), math.floor(z),
            animalType, breeds:get(0))
        if animal == nil then return end
        animal:addToWorld()
        placed = animal
    end)
    return placed
end

function Builder.placeGenerator(x, y, z, siteId, supply)
    local placed
    pcall(function()
        local square = squareAt(x, y, z)
        if square == nil then return end
        local fuelItem = instanceItem("Base.Generator")
        if fuelItem == nil then return end
        local object = IsoGenerator.new(fuelItem, getCell(), square)
        if object == nil then return end
        local kit = type(supply) == "table" and supply or {}
        local share = math.max(0, math.min(1, tonumber(kit.fuel) or Builder.generatorFuel))
        local tank = object.getMaxFuel ~= nil and tonumber(object:getMaxFuel()) or 10
        object:setCondition(math.max(1, math.min(100, math.floor(tonumber(kit.condition) or Builder.generatorCondition))))
        object:setFuel(tank * share)
        object:setConnected(true)
        object:setActivated(true)

        pcall(function() object:getModData().ProjectALifeOutpostSite = siteId end)
        transmit(object)
        pcall(function() object:transmitModData() end)
        placed = object
    end)
    return placed
end

function Builder.squareIsWater(square)
    local kind = type(square)
    if IsoFlagType == nil or (kind ~= "userdata" and kind ~= "table")
            or type(square.getProperties) ~= "function" then return false end
    local properties = square:getProperties()
    return properties ~= nil and type(properties.has) == "function" and properties:has(IsoFlagType.water) == true
end

function Builder.siteBlocker(square)
    if square == nil then return "unloaded" end
    if type(square.getVehicleContainer) == "function" and square:getVehicleContainer() ~= nil then return "vehicle" end
    if type(square.getObjects) ~= "function" then return "objects_unavailable" end
    local objects = square:getObjects()
    if objects == nil or type(objects.size) ~= "function" or type(objects.get) ~= "function" then
        return "objects_unavailable"
    end
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        if object ~= nil then
            if instanceof(object, "IsoGenerator") then return "generator" end
            if instanceof(object, "IsoThumpable") and type(object.isDismantable) == "function"
                    and object:isDismantable() == true then return "player_build" end
            local sprite = type(object.getSprite) == "function" and object:getSprite() or nil
            local name = sprite ~= nil and type(sprite.getName) == "function" and sprite:getName() or nil
            if type(name) == "string" and string.sub(name, 1, 18) == "vegetation_farming" then return "crop" end
            if Builder.spriteHas("wall", sprite, name) == true and not Builder.clearable(object) then
                return "wall_or_fence"
            end
        end
    end
    return nil
end

Builder.naturalChunkSquares = 4

Builder.coarseStrides = { 8, 4, 2, 1 }

function Builder.naturalBegin(x, y, z, w, h, roadAllowance, coarse)
    local wMax, hMax = (tonumber(w) or 1) - 1, (tonumber(h) or 1) - 1
    local job = { x = x, y = y, z = z, wMax = wMax, hMax = hMax,
        allowance = roadAllowance, road = nil, dx = 0, dy = 0, sampled = 0, roads = 0,
        ok = true, reason = nil, checked = true, done = false, units = 0, level = 1,
        coarse = coarse == true }
    if coarse == true then
        local total = (math.floor(math.max(wMax, -1)) + 1) * (math.floor(math.max(hMax, -1)) + 1)
        job.roadCap = math.floor(total * math.max(0, math.min(0.5, tonumber(roadAllowance) or 0)))
    end
    return job
end

function Builder.naturalSquare(job, dx, dy)
    local square = squareAt(job.x + dx, job.y + dy, job.z)
    job.sampled = job.sampled + 1
    if square == nil then
        job.ok, job.reason, job.done = false, "ground_unloaded", true
        return
    end
    if type(square.getBuilding) ~= "function"
            or square:getBuilding() ~= nil or Builder.squareIsWater(square)
            or Builder.siteBlocker(square) ~= nil then
        job.ok, job.done = false, true
        return
    end
    local road = job.road
    if road ~= nil and type(road.isRoadSquare) == "function" and road.isRoadSquare(square) then
        job.roads = job.roads + 1
        if job.roadCap ~= nil and job.roads > job.roadCap then job.ok, job.done = false, true end
    end
end

function Builder.naturalFinish(job)
    local allowed = math.floor(job.sampled * math.max(0, math.min(0.5,
        tonumber(job.allowance) or 0)))
    if job.roads > allowed then job.ok = false end
    job.done = true
end

function Builder.naturalChunk(job, count)
    if job.coarse then return Builder.naturalCoarse(job, count) end
    while count > 0 do
        if job.dx > job.wMax then
            Builder.naturalFinish(job)
            return
        end
        if job.dy > job.hMax then
            job.dx, job.dy = job.dx + 1, 0
        else
            local dy = job.dy
            job.dy = dy + 1
            Builder.naturalSquare(job, job.dx, dy)
            if job.done then return end
            count = count - 1
        end
    end
end

function Builder.naturalCoarse(job, count)
    local strides = Builder.coarseStrides
    while count > 0 do
        local stride = strides[job.level]
        if stride == nil then
            Builder.naturalFinish(job)
            return
        end
        if job.dx > job.wMax then
            job.level, job.dx, job.dy = job.level + 1, 0, 0
        elseif job.dy > job.hMax then
            job.dx, job.dy = job.dx + stride, 0
        else
            local dx, dy = job.dx, job.dy
            job.dy = dy + stride
            if stride == 8 or dx % (stride * 2) ~= 0 or dy % (stride * 2) ~= 0 then
                Builder.naturalSquare(job, dx, dy)
                if job.done then return end
                count = count - 1
            end
        end
    end
end

function Builder.naturalStep(job, budgetMs, clock)
    local began = budgetMs ~= nil and clock ~= nil and clock() or 0
    if job.started ~= true then
        job.started = true
        job.road = ProjectALife.Road
    end
    while job.done ~= true do
        job.units = job.units + 1
        local fine = pcall(Builder.naturalChunk, job, Builder.naturalChunkSquares)
        if not fine then
            job.checked, job.done = false, true
        end
        if job.done ~= true and budgetMs ~= nil and clock() - began >= budgetMs then return false end
    end
    return true
end

function Builder.naturalResult(job)
    return job.checked and job.ok, job.reason
end

function Builder.naturalSpace(x, y, z, w, h, roadAllowance)
    local job = Builder.naturalBegin(x, y, z, w, h, roadAllowance)
    Builder.naturalStep(job, nil, nil)
    return Builder.naturalResult(job)
end

Builder.naturalSpaceBase = Builder.naturalSpace

Builder.cursorLayout = 2

function Builder.resumeCursor(sheet, cursor, layout)
    cursor = math.max(1, math.floor(tonumber(cursor) or 1))
    if cursor == 1 or tonumber(layout) == Builder.cursorLayout
            or type(sheet) ~= "table" or type(sheet.ops) ~= "table" then return cursor end
    local old, previous = 0, nil
    for index, op in ipairs(sheet.ops) do
        local row = previous ~= nil and op.op == "site_clearance" and previous.op == "site_clearance"
            and op.x == previous.x and op.w == previous.w and op.ring == previous.ring
            and op.y == previous.y + 1
        if not row then
            old = old + 1
            if old == cursor then return index end
        end
        previous = op
    end
    return #sheet.ops + 1
end

Builder.streamGuard = { chunk = 8, reach = 11, cell = 256, cellMargin = 1,
    stillMs = 5000, joinMs = 30000, jumpChunks = 8 }

Builder.watched = {}

Builder.structuralOps = { tile = true, thumpable = true, door = true, floor = true, stairs = true }

function Builder.structural(op)
    return type(op) == "table" and Builder.structuralOps[op.op] == true
end

Builder.lossOps = { tile = true, thumpable = true, door = true }

function Builder.lossRow(op)
    return type(op) == "table" and Builder.lossOps[op.op] == true and type(op.sprite) == "string"
        and op.decor ~= true
end

function Builder.streamActive()
    return type(isServer) == "function" and isServer() == true
end

function Builder.playerKey(p)
    local body = type(p) == "table" and p.player or nil
    if body ~= nil and type(body.getUsername) == "function" then
        local ok, name = pcall(body.getUsername, body)
        if ok and name ~= nil then return tostring(name) end
    end
    if type(p) == "table" and p.key ~= nil then return tostring(p.key) end
    return nil
end

function Builder.watchPlayers(list, now)
    local guard, seen, fresh = Builder.streamGuard, Builder.watched or {}, {}
    for _, p in ipairs(type(list) == "table" and list or {}) do
        local key, px, py = Builder.playerKey(p), tonumber(p.x), tonumber(p.y)
        if key ~= nil and px ~= nil and py ~= nil then
            local cx, cy = math.floor(px / guard.chunk), math.floor(py / guard.chunk)
            local row = seen[key]
            if row == nil then
                row = { cx = cx, cy = cy, movedAt = now, joinedAt = now }
            elseif row.cx ~= cx or row.cy ~= cy then
                if math.abs(row.cx - cx) > guard.jumpChunks or math.abs(row.cy - cy) > guard.jumpChunks then
                    row.joinedAt = now
                end
                row.cx, row.cy, row.movedAt = cx, cy, now
            end
            fresh[key] = row
        end
    end
    Builder.watched = fresh
end

function Builder.streamHeld(box, list, now)
    if not Builder.streamActive() or type(box) ~= "table" then return false end
    local guard = Builder.streamGuard
    local cell, size, reach, margin = guard.cell, guard.chunk, guard.reach, guard.cellMargin
    local x1, y1 = (math.floor(box.x1 / cell) - margin) * cell, (math.floor(box.y1 / cell) - margin) * cell
    local x2 = (math.floor(box.x2 / cell) + margin + 1) * cell - 1
    local y2 = (math.floor(box.y2 / cell) + margin + 1) * cell - 1
    local seen = Builder.watched or {}
    for _, p in ipairs(type(list) == "table" and list or {}) do
        local px, py = tonumber(p.x), tonumber(p.y)
        if px ~= nil and py ~= nil then
            local cx, cy = math.floor(px / size), math.floor(py / size)
            if (cx + reach + 1) * size - 1 >= x1 and (cx - reach) * size <= x2
                    and (cy + reach + 1) * size - 1 >= y1 and (cy - reach) * size <= y2 then
                local key = Builder.playerKey(p)
                local row = key ~= nil and seen[key] or nil
                if row == nil or row.cx ~= cx or row.cy ~= cy or now - row.movedAt < guard.stillMs
                        or now - row.joinedAt < guard.joinMs then
                    return true
                end
            end
        end
    end
    return false
end

function Builder.opCost(op)
    if type(op) ~= "table" or op.op ~= "site_clearance" then return 1 end
    local margin = math.max(0, math.floor(tonumber(op.margin) or 0))
    local w = math.max(1, math.floor(tonumber(op.w) or 1)) + 2 * margin
    local h = math.max(1, math.floor(tonumber(op.h) or 1)) + 2 * margin
    local per = math.max(1, math.floor(tonumber(Builder.clearanceSquaresPerUnit) or 1))
    return math.max(1, math.ceil(w * h / per))
end

function Builder.heldGroundOp(op)
    return type(op) == "table" and (op.op == "vehicle" or op.op == "blood")
        and (tonumber(op.z) or 0) == 0 and tonumber(op.x) ~= nil and tonumber(op.y) ~= nil
end

function Builder.execute(sheet, site, roll, budget, hold)
    if not authoritative() then
        Builder.metrics.refused = Builder.metrics.refused + 1
        return false, "builder_not_authoritative"
    end
    local gate = ProjectALife.CleanupLock
    if gate ~= nil and gate.refuse("outpost_build") then
        Builder.metrics.refused = Builder.metrics.refused + 1
        return false, "cleanup_locked"
    end
    if type(sheet) ~= "table" or type(sheet.ops) ~= "table" then return false, "sheet_invalid" end
    if not Interop.run("outpost.beforeBuildRound", site) then return true, 0, false end
    roll = type(roll) == "function" and roll or randomUnit
    local first = math.max(1, math.floor(tonumber(sheet.cursor) or 1))
    if type(sheet.finished) ~= "table" then
        sheet.finished = {}
        if type(site) == "table" and tonumber(site.buildLayout) == Builder.cursorLayout
                and type(site.buildFinishedOps) == "table" then
            for index, finished in pairs(site.buildFinishedOps) do
                if type(index) == "number" and index == math.floor(index) and index >= first
                        and finished == true and Builder.heldGroundOp(sheet.ops[index]) then
                    sheet.finished[index] = true
                end
            end
        end
    end
    if first == 1 then
        for _, op in ipairs(sheet.ops) do
            if op.op == "site_survey" then

                local x2, y2 = op.x + (op.w or 1) - 1, op.y + (op.h or 1) - 1
                if not (Builder.groundLoaded(op.x, op.y) and Builder.groundLoaded(x2, op.y)
                        and Builder.groundLoaded(op.x, y2) and Builder.groundLoaded(x2, y2)) then
                    Builder.metrics.waited = (Builder.metrics.waited or 0) + 1
                    return true, 0, false
                end
                local natural, reason = Builder.naturalSpace(op.x, op.y, op.z, op.w, op.h, op.roadAllowance)
                if reason == "ground_unloaded" then
                    Builder.metrics.waited = (Builder.metrics.waited or 0) + 1
                    return true, 0, false
                end
                if not natural then
                    return false, "ground_not_natural"
                end
            end
        end
    end
    local last = #sheet.ops
    local limit = tonumber(budget) ~= nil and math.max(1, math.floor(budget)) or nil
    local spent = 0
    local heldStructure = false

    for index = first, last do
        local op = sheet.ops[index]
        if limit ~= nil and not sheet.finished[index] then
            spent = spent + Builder.opCost(op)
            if spent > limit and index > first then
                last = index - 1
                break
            end
        end
        if hold == true and Builder.structural(op) then
            last = index - 1
            spent = spent - Builder.opCost(op)
            heldStructure = true
            Builder.metrics.streamHeld = (Builder.metrics.streamHeld or 0) + 1
            break
        end
        if tonumber(op.x) ~= nil and tonumber(op.y) ~= nil and not Builder.groundLoaded(op.x, op.y) then
            last = index - 1
            Builder.metrics.waited = (Builder.metrics.waited or 0) + 1
            break
        end
    end
    local selected = {}
    for index = first, last do
        if not sheet.finished[index] then selected[#selected + 1] = index end
    end
    if heldStructure then
        local independent = true
        for index = last + 1, #sheet.ops do
            local op = sheet.ops[index]
            if op.op == "site_clearance" or op.op == "site_survey" then independent = false; break end
        end
        if independent then
            for index = last + 1, #sheet.ops do
                local op = sheet.ops[index]
                if not sheet.finished[index] and Builder.heldGroundOp(op)
                        and (limit == nil or spent + Builder.opCost(op) <= limit)
                        and Builder.groundLoaded(op.x, op.y) then
                    selected[#selected + 1] = index
                    spent = spent + Builder.opCost(op)
                end
            end
        end
    end
    local done
    local props, containers, radio = {}, {}, nil

    local vehicles = {}
    local placed, failure = 0, sheet.failure
    Builder.currentSite = site
    for _, index in ipairs(selected) do
        local op = sheet.ops[index]
        local object, restore, marked, reused
        local kept = op.keep == true and Builder.alreadyThere(op.x, op.y, op.z, op.sprite)
        if kept then
            Builder.metrics.kept = (Builder.metrics.kept or 0) + 1
        elseif op.op == "tile" then
            object = Builder.placeMapTile(op.x, op.y, op.z, op.sprite)
        elseif op.op == "vehicle" then
            object = Builder.placeVehicle(op.x, op.y, op.z, op.script, op.facing, op.fuel, site and site.id or nil)

            vehicles[#vehicles + 1] = { x = op.x, y = op.y, z = op.z,
                script = op.script, facing = op.facing, fuel = op.fuel,
                placed = object ~= nil }
            if object == nil then
                Builder.metrics.vehiclesMissed = (Builder.metrics.vehiclesMissed or 0) + 1
            end
        elseif op.op == "thumpable" then
            object = Builder.placeThumpable(op.x, op.y, op.z, op.sprite, op.north)
        elseif op.op == "stairs" then
            object = Builder.placeStairs(op.x, op.y, op.z, op.sprite, op.north, op.level)
        elseif op.op == "floor" then
            object, restore = Builder.placeFloor(op.x, op.y, op.z, op.sprite)
        elseif op.op == "door" then
            local reusedBefore = Builder.metrics.doorsReused or 0
            object = Builder.placeDoor(op.x, op.y, op.z, op.sprite, op.north)
            reused = (Builder.metrics.doorsReused or 0) > reusedBefore
        elseif op.op == "campfire" then
            object = Builder.placeCampfire(op.x, op.y, op.z, op.sprite)
        elseif op.op == "object" or op.op == "litter" then
            object = Builder.placeObject(op.x, op.y, op.z, op.sprite)
        elseif op.op == "container" then
            local added
            object, added = Builder.placeContainer(op.x, op.y, op.z, op.sprite, op.loot, op.draws, roll,
                op.contents)
            if object ~= nil then containers[#containers + 1] = { x = op.x, y = op.y, z = op.z, expected = added or 0 } end
        elseif op.op == "radio" then
            object = Builder.placeRadio(op.x, op.y, op.z, op.sprite, site and site.id or nil)
            if object ~= nil then radio = { x = op.x, y = op.y, z = op.z } end
        elseif op.op == "barricade_door" then
            local sealed, tagged = Builder.barricadeDoor(op.x, op.y, op.z, op.planks, op.north)
            if sealed then object = true end
            marked = tagged == true
        elseif op.op == "blood" then
            if Builder.placeBlood(op.x, op.y, op.z, op.splats) then object = true end
        elseif op.op == "items" then
            if Builder.placeItems(op.x, op.y, op.z, op.item, op.quantity) then object = true end
        elseif op.op == "light" then
            object = Builder.placeLight(op.x, op.y, op.z, op.sprite)
        elseif op.op == "generator" then
            object = Builder.placeGenerator(op.x, op.y, op.z, site and site.id or nil, op)
        elseif op.op == "animal" then
            object = Builder.placeAnimal(op.x, op.y, op.z, op.animal)
        elseif op.op == "barricade_window" then
            local sealed, tagged = Builder.barricadeWindow(op.x, op.y, op.z, op.planks, op.material, op.north)
            if sealed then object = true end
            marked = tagged == true
        elseif op.op == "lock_door" then
            if Builder.lockDoor(op.x, op.y, op.z, op.north) then object = true end
        elseif op.op == "site_survey" then
            object = true
        elseif op.op == "site_clearance" then

            Builder.clearSpace(op.x, op.y, op.z, op.w or 1, op.h or 1, op.margin)
            object = true
        elseif op.op == "mark_entrance" then

            Builder.shutDoorAt(op.doorX or op.x, op.doorY or op.y, op.z, op.north)
            object = true
        end
        if (object == nil or object == false) and not kept then

            Builder.metrics.skipped = (Builder.metrics.skipped or 0) + 1

            if op.op ~= "blood" and op.op ~= "items" and op.op ~= "vehicle" and op.op ~= "animal"
                    and op.op ~= "litter" then
                failure = failure or ("placement_failed:" .. tostring(op.op))
            end
        end
        if object ~= nil and object ~= false then
            placed = placed + 1

            local row = { op = op.op, x = op.x, y = op.y, z = op.z,
                sprite = op.sprite, restore = restore,
                marked = marked or nil, decor = op.decor,
                class = (op.op == "generator" and "IsoGenerator")
                    or (op.op == "light" and "IsoLightSwitch")

                    or (op.op == "animal" and "IsoAnimal")

                    or (op.op == "vehicle" and "BaseVehicle") or nil }
            if op.op == "barricade_door" or op.op == "barricade_window" then row.north = op.north end
            if op.op == "items" and type(op.item) == "string" then
                row.item = op.item
                if type(site) == "table" and site.id ~= nil then row.sid = true end
            end
            if reused == true then row.reuse = true
            elseif Builder.tagPlaced(object, site) then row.sid = true end
            props[#props + 1] = row
        end
        sheet.finished[index] = true
    end
    Builder.currentSite = nil
    Builder.metrics.executed = Builder.metrics.executed + 1
    Builder.metrics.placed = Builder.metrics.placed + placed
    sheet.cursor = last + 1
    while sheet.finished[sheet.cursor] do sheet.cursor = sheet.cursor + 1 end
    done = sheet.cursor > #sheet.ops
    sheet.failure = failure
    if type(site) == "table" and ProjectALife.OutpostRegistry ~= nil then
        local registry = ProjectALife.OutpostRegistry
        local fresh = registry.read(site.id)
        if fresh ~= nil then
            registry.update(fresh.id, fresh.revision, function(record)

                for _, prop in ipairs(props) do record.props[#record.props + 1] = prop end
                record.containers = record.containers or {}
                if first == 1 and site.buildCursor == nil then record.containers = {} end
                for _, row in ipairs(containers) do record.containers[#record.containers + 1] = row end
                record.radio = radio or record.radio
                record.vehicles = record.vehicles or {}
                if first == 1 and site.buildCursor == nil then record.vehicles = {} end
                for _, row in ipairs(vehicles) do record.vehicles[#record.vehicles + 1] = row end

                if done then record.buildCursor = nil else record.buildCursor = sheet.cursor end
                if done then record.buildLayout = nil else record.buildLayout = Builder.cursorLayout end
                record.buildFinishedOps = nil
                if not done then
                    local finished = {}
                    for index in pairs(sheet.finished) do
                        if index >= sheet.cursor then finished[index] = true end
                    end
                    if selected[1] ~= nil or type(site.buildFinishedOps) == "table" then
                        record.buildFinishedOps = finished
                    end
                end
                if done then
                    record.mainEntrance = sheet.mainEntrance or record.mainEntrance

                    record.posts = type(sheet.posts) == "table" and sheet.posts or record.posts

                    record.openingsFixed = Builder.openingsVersion
                    record.planVersion = sheet.planVersion or record.planVersion
                    record.state = failure and "build_failed" or "built"
                    record.buildError = failure
                end
            end)
        end
    end
    if not done then return true, placed, false end
    if failure then
        Builder.metrics.failed = Builder.metrics.failed + 1
        return false, failure, placed
    end
    return true, placed, true
end

function Builder.tagPlaced(object, site)
    local id = type(site) == "table" and site.id or nil
    if id == nil or object == nil or type(object) == "boolean" or type(object.getModData) ~= "function" then
        return false
    end
    local ok = pcall(function() object:getModData().ProjectALifeSiteId = tostring(id) end)
    return ok
end

Builder.openingsVersion = 20260916

function Builder.repairOpenings(site, hold)
    local registry = ProjectALife.OutpostRegistry
    if type(site) ~= "table" or registry == nil or type(registry.propsOf) ~= "function" then return 0, 0 end
    local repaired, pending = 0, 0

    local preset = Presets.get(site.presetId)
    if preset ~= nil and preset.class == "building" then
        local building
        local b = site.bounds or {}
        for x = b.x1 or site.x, b.x2 or site.x do
            for y = b.y1 or site.y, b.y2 or site.y do
                local sq = getCell():getGridSquare(x, y, b.z or 0)
                if sq == nil then pending = pending + 1
                elseif building == nil then building = sq:getBuilding() end
            end
        end
        local probe = building and Builder.probeBuilding(building) or nil
        if probe == nil or not probe.complete then
            pending = pending + 1
        else
            Builder.currentSite = site
            for _, window in ipairs(probe.windows()) do
                local curtain = window.object:HasCurtains()
                local changed = not window.barricaded or curtain == nil or curtain:IsOpen()
                local material, boards = nil, Builder.boardsFor(nil)
                for _, item in ipairs(preset.kit or {}) do
                    if item.op == "barricade_windows" then
                        material, boards = item.material, Builder.boardsFor(item)
                    end
                end
                if Builder.barricadeWindow(window.objectX, window.objectY, window.z, boards, material, window.north) then
                    if changed then repaired = repaired + 1 end
                else pending = pending + 1 end
            end
            Builder.currentSite = nil
            for _, door in ipairs(probe.doors()) do
                local object = door.object
                if object.canAddCurtain ~= nil and (object:HasCurtains() ~= nil or object:canAddCurtain()) then
                    local ready, changed = Builder.closeSheet(object)
                    if not ready then pending = pending + 1
                    elseif changed then repaired = repaired + 1 end
                end
            end
        end
    end
    local known = {}
    for _, prop in ipairs(registry.propsOf(site.id) or {}) do
        local sprite = prop.sprite
        if prop.op == "tile" and type(sprite) == "string" then
            if known[sprite] == nil then known[sprite] = Builder.isOpeningSprite(sprite) end
            if known[sprite] then
                if hold == true or not Builder.groundLoaded(prop.x, prop.y) then
                    pending = pending + 1
                else
                    pcall(function()
                        local square = getCell():getGridSquare(prop.x, prop.y, prop.z or 0)
                        if square == nil then return end
                        local objects = square:getObjects()
                        for index = objects:size() - 1, 0, -1 do
                            local object = objects:get(index)
                            local name
                            pcall(function() name = object:getSprite() and object:getSprite():getName() end)
                            if name == sprite and not (instanceof(object, "IsoDoor") or instanceof(object, "IsoWindow")
                                    or instanceof(object, "IsoWindowFrame") or instanceof(object, "IsoThumpable")) then
                                square:transmitRemoveItemFromSquare(object)
                                local fresh = Builder.placeMapTile(prop.x, prop.y, prop.z or 0, sprite)
                                if fresh ~= nil then
                                    Builder.tagPlaced(fresh, site)
                                    repaired = repaired + 1
                                end
                            end
                        end
                    end)
                end
            end
        end
    end

    local r = site.radio
    if type(r) == "table" and tonumber(r.x) ~= nil and tonumber(r.y) ~= nil then
        if not Builder.groundLoaded(r.x, r.y) then
            pending = pending + 1
        else
            pcall(function()
                local square = getCell():getGridSquare(r.x, r.y, r.z or 0)
                local objects = square ~= nil and square:getObjects() or nil
                if objects == nil then return end
                for index = 0, objects:size() - 1 do
                    local object = objects:get(index)
                    if object.getDeviceData ~= nil and Builder.silenceRadio(object) then
                        Builder.metrics.radiosSilenced = (Builder.metrics.radiosSilenced or 0) + 1
                    end
                end
            end)
        end
    end
    Builder.metrics.openingsRepaired = (Builder.metrics.openingsRepaired or 0) + repaired
    return repaired, pending
end

Builder.probeSteps = { { 0, -1, "N" }, { 0, 1, "S" }, { -1, 0, "W" }, { 1, 0, "E" } }

function Builder.probeBuilding(building)
    local doors, windows, roadSide, bounds, complete = {}, {}, nil, nil, true
    local ok = pcall(function()
        local def = building:getDef()

        bounds = { x1 = def:getX(), y1 = def:getY(), x2 = def:getX2() - 1, y2 = def:getY2() - 1, z = 0 }
        local cell = getCell()
        local seen = {}
        local function add(list, object, ix, iy, z, side)
            if object == nil or seen[object] then return end
            seen[object] = true
            local sq = object:getSquare()
            list[#list + 1] = { x = ix, y = iy, z = z, side = side,
                objectX = sq:getX(), objectY = sq:getY(), north = object:getNorth(),
                object = object, kind = list == windows and "window" or "door",
                barricaded = object:isBarricaded() == true }
        end

        local steps, lowest = Builder.probeSteps, def:getMinLevel()
        local span = bounds.y2 - bounds.y1 + 1
        for z = def:getMinLevel(), def:getMaxLevel() do
            local squares, inside = {}, {}
            for x = bounds.x1, bounds.x2 do
                for y = bounds.y1, bounds.y2 do
                    local key = (x - bounds.x1) * span + (y - bounds.y1)
                    local square = cell:getGridSquare(x, y, z)
                    if z == lowest and (z == 0 and square == nil or z ~= 0 and cell:getGridSquare(x, y, 0) == nil) then
                        complete = false
                    end
                    if square ~= nil then
                        squares[key] = square
                        inside[key] = square:getBuilding() == building
                    end
                end
            end
            for x = bounds.x1, bounds.x2 do
                for y = bounds.y1, bounds.y2 do
                    local key = (x - bounds.x1) * span + (y - bounds.y1)
                    if inside[key] == true then
                        local here = squares[key]
                        for _, step in ipairs(steps) do
                            local nx, ny = x + step[1], y + step[2]
                            local outside, within
                            if nx >= bounds.x1 and nx <= bounds.x2 and ny >= bounds.y1 and ny <= bounds.y2 then
                                local near = (nx - bounds.x1) * span + (ny - bounds.y1)
                                outside, within = squares[near], inside[near] == true
                            else
                                outside, within = cell:getGridSquare(nx, ny, z), false
                            end
                            if z == 0 and outside == nil then complete = false end
                            if outside ~= nil and not within then
                                add(doors, here:getDoorTo(outside), x, y, z, step[3])
                                add(windows, here:getWindowTo(outside), x, y, z, step[3])
                            end
                        end
                    end
                end
            end
        end
        local road = ProjectALife.Road
        if road ~= nil then
            local cx, cy = math.floor((bounds.x1 + bounds.x2) / 2), math.floor((bounds.y1 + bounds.y2) / 2)
            for _, probe in ipairs({ { "S", cx, bounds.y2 + 3 }, { "N", cx, bounds.y1 - 3 },
                    { "E", bounds.x2 + 3, cy }, { "W", bounds.x1 - 3, cy } }) do
                local sq = cell:getGridSquare(probe[2], probe[3], 0)
                if sq ~= nil and road.isRoadSquare(sq) then roadSide = probe[1] break end
            end
        end
    end)
    if not ok or bounds == nil then return nil end
    return { doors = function() return doors end, windows = function() return windows end,
        roadSide = roadSide, complete = complete }, bounds
end

ProjectALife.Props = {
    placeObject = Builder.placeObject,
    placeThumpable = Builder.placeThumpable,
    placeContainer = Builder.placeContainer,
    barricadeWindow = Builder.barricadeWindow,
    lockDoor = Builder.lockDoor,
    placeRadio = Builder.placeRadio,
}

return Builder
