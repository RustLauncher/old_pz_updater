require "ProjectALife/Behaviours/ALifeModuleRegistry"

ProjectALife = ProjectALife or {}

local Registry = ProjectALife.ModuleRegistry

local Module = {
    settings = { approachTol = 0.9, standTol = 0.45, roomTol = 1.2, paceTol = 0.7, farewellTol = 0.9, followTol = 2.5, lookTol = 0.5,
        planMs = 4000, idleMs = 1200, moveTimeoutMs = 20000, snapTries = 4, turnSteps = 8,
        washMs = { wash = 14000, bath = 18000 }, useWater = false, attendSq = 4, noticeSq = 64, hurryMs = 1500,
        fidgetFirstMs = 4000, fidgetMinMs = 12000, fidgetSpreadMs = 15000, attendMs = 2500, rearmMs = 8000,
        aroundMs = 2500, stareKeepMs = 3000 },
    attends = {},
    stares = {},
    posed = setmetatable({}, { __mode = "k" }),
    plans = setmetatable({}, { __mode = "k" }),
    washes = setmetatable({}, { __mode = "k" }),
    devices = setmetatable({}, { __mode = "k" }),
    tries = setmetatable({}, { __mode = "k" }),
    fidgetAt = setmetatable({}, { __mode = "k" }),
    metrics = { runs = 0, walks = 0, refused = 0, holds = 0, sits = 0, gone = 0, washes = 0, rinsed = 0, dry = 0,
        devices = 0, deviceDead = 0, suspended = 0, lastWhy = "-", attended = 0, fidgets = 0, hurried = 0, plain = 0,
        attendCapped = 0, arounds = 0 },
}
ProjectALife.ModuleVisitorLife = Module

Module.fallback = {
    bed_asleep = { "doze_sit", "sit_bench" }, bed_awake = { "sit_bench" }, doze_sit = { "sit_bench" },
    sit_wall = { "sit_ground" }, wash_face = { "wash_hands" }, change_top = { "heal_body" }, yawn = { "tired" },
}
Module.chains = {
    sit = { "sit_bench" }, read = { "sit_bench" }, tv = { "sit_bench" }, rest = { "doze_sit", "sit_bench" },
    restBed = { "bed_asleep", "bed_awake", "sit_bench" }, shelf = { "read" }, warm = { "warm_hands" },
    change = { "change_top" }, drink = { "drink" }, eat = { "eat" }, cook = { "search_mid" }, warmCan = { "eat" },
    coffee = { "drink" }, fridge = { "search_high", "search_mid" }, rinse = { "wash_hands" }, tidy = { "search_mid" },
}
Module.fidgets = { "shrug", "breathe", "undecided", "tired", "yawn" }
Module.seatedPoses = { sit_bench = true, doze_sit = true, bed_asleep = true, bed_awake = true, sit_wall = true, sit_ground = true }
Module.rooted = { "bed_asleep", "bed_awake", "doze_sit", "sit_wall", "wash_hands", "wash_face", "write", "photo" }
Module.vector = { N = { 0, -1 }, S = { 0, 1 }, E = { 1, 0 }, W = { -1, 0 } }
Module.kitchen = { cook = "cook", warm_can = "warmCan", make_coffee = "coffee", check_fridge = "fridge",
    rinse_cup = "rinse", tidy = "tidy" }
Module.ring = { { 0, -1, "N" }, { 0, 1, "S" }, { 1, 0, "E" }, { -1, 0, "W" }, { 1, -1 }, { -1, -1 }, { 1, 1 }, { -1, 1 } }

function Module.nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function Module.life()
    return ProjectALife.VisitorLife
end

function Module.squareAt(x, y, z)
    local life = Module.life()
    if life ~= nil and type(life.squareAt) == "function" then return life.squareAt(x, y, z) end
    if type(getCell) ~= "function" then return nil end
    local cell = getCell()
    if cell == nil or type(cell.getGridSquare) ~= "function" then return nil end
    return cell:getGridSquare(x, y, z)
end

function Module.positionOf(shell)
    if shell == nil or type(shell.getX) ~= "function" or type(shell.getY) ~= "function" then return nil end
    return { x = shell:getX(), y = shell:getY(), z = type(shell.getZ) == "function" and shell:getZ() or 0 }
end

function Module.drives(shell)
    local fence = ProjectALife.AIFence
    return fence ~= nil and type(fence.drivesBody) == "function" and fence.drivesBody(shell) == true
end

function Module.idle(actor, context, intent, now)
    if type(context.setActivity) == "function" then context.setActivity(actor, "idle", intent) end
    return { kind = "idle", intent = intent, cooldownUntilMs = now + Module.settings.idleMs }
end

function Module.hold(actor, context, now)
    Module.metrics.holds = Module.metrics.holds + 1
    return Module.idle(actor, context, "visitor_hold", now)
end

function Module.gone(actor, context, now, why)
    Module.metrics.gone = Module.metrics.gone + 1
    Module.metrics.lastWhy = tostring(why)
    return Module.idle(actor, context, "visitor_gone", now)
end

function Module.walkRefused(actor, shell, target, now)
    local movement = ProjectALife.Movement
    if movement == nil or type(target) ~= "table" then return false end
    if type(movement.goalRefused) == "function" and movement.goalRefused(actor.uid, target, now) then return true end
    return type(movement.climbSettling) == "function" and movement.climbSettling(shell, now) == true
end

function Module.preset(chain)
    local animations = ProjectALife.Animations
    if animations == nil or type(animations.supports) ~= "function" or type(chain) ~= "table" then return nil end
    for position = 1, #chain do
        local id = chain[position]
        if animations.supports(id) then return id end
        for _, alternative in ipairs(Module.fallback[id] or {}) do
            if animations.supports(alternative) then return alternative end
        end
    end
    return nil
end

function Module.holdsPose(shell)
    local id = Module.posed[shell]
    return id ~= nil and Module.seatedPoses[id] == true
end

function Module.holster(shell)
    local adapter = ProjectALife.ShellAdapter
    if adapter ~= nil and type(adapter.dropFlashlight) == "function" then adapter.dropFlashlight(shell) end
    pcall(function() shell:setHideWeaponModel(true) end)
end

function Module.unpose(shell)
    local animations = ProjectALife.Animations
    if Module.posed[shell] ~= nil and animations ~= nil and type(animations.clear) == "function" then
        animations.clear(shell)
    end
    Module.posed[shell] = nil
end

function Module.pose(shell, chain)
    local animations = ProjectALife.Animations
    local id = Module.preset(chain)
    if id == nil or animations == nil or type(animations.apply) ~= "function" then
        Module.unpose(shell)
        return nil
    end
    if animations.current ~= nil and animations.current[shell] == id then
        Module.posed[shell] = id
        return id
    end
    if animations.apply(shell, id, Module.seatedPoses[id] == true) == true then Module.posed[shell] = id end
    return id
end

function Module.face(shell, x, y, now)
    local fence = ProjectALife.AIFence
    if fence == nil or type(fence.faceAimPoint) ~= "function" then return false end
    local turned = false
    for step = 0, Module.settings.turnSteps - 1 do
        turned = fence.faceAimPoint(shell, x, y, now + step * 100) == true or turned
    end
    return turned
end

function Module.free(square)
    if square == nil then return false end
    if type(square.isFree) == "function" and square:isFree(false) ~= true then return false end
    return true
end

function Module.standSquare(shell, sx, sy, z, facing, strict)
    local seats = ProjectALife.SeatApi
    local origin = Module.squareAt(sx, sy, z)
    if origin == nil then return nil end
    local here = Module.positionOf(shell)
    local front = Module.vector[facing or ""]
    local best, bestCost = nil, math.huge
    local room = type(origin.getRoom) == "function" and origin:getRoom() or nil
    local building = type(origin.getBuilding) == "function" and origin:getBuilding() or nil
    for _, step in ipairs(Module.ring) do
        local square = Module.squareAt(sx + step[1], sy + step[2], z)
        local open = (step[3] ~= nil or strict ~= true) and Module.free(square)
        if open and strict == true and room ~= nil and type(square.getRoom) == "function" and square:getRoom() ~= room then
            open = false
        end
        if open and building ~= nil and type(square.getBuilding) == "function" and square:getBuilding() ~= building then
            open = false
        end
        if open and seats ~= nil and type(seats.passable) == "function" then
            open = seats.passable(square, origin) == true and seats.passable(origin, square) == true
        end
        if open then
            local cx, cy = sx + step[1] + 0.5, sy + step[2] + 0.5
            local cost = 0
            if here ~= nil then cost = math.sqrt((cx - here.x) ^ 2 + (cy - here.y) ^ 2) end
            if front ~= nil and step[1] == front[1] and step[2] == front[2] then cost = cost - 1.5 end
            if step[3] == nil then cost = cost + 0.5 end
            if cost < bestCost then best, bestCost = { x = cx, y = cy, z = z }, cost end
        end
    end
    return best
end

function Module.standNear(shell, poi)
    local here = Module.positionOf(shell)
    local best, bestCost = nil, math.huge
    for dx = -3, 3 do
        for dy = -3, 3 do
            local distance = math.max(math.abs(dx), math.abs(dy))
            if distance >= 2 then
                local square = Module.squareAt(poi.x + dx, poi.y + dy, poi.z)
                if Module.free(square) then
                    local cx, cy = poi.x + dx + 0.5, poi.y + dy + 0.5
                    local cost = distance * 2
                    if here ~= nil then cost = cost + math.sqrt((cx - here.x) ^ 2 + (cy - here.y) ^ 2) end
                    if cost < bestCost then best, bestCost = { x = cx, y = cy, z = poi.z }, cost end
                end
            end
        end
    end
    return best
end

function Module.bedSeat(poi)
    if Module.life() == nil or Module.life().objectOf(poi) == nil then return nil end
    return { x = poi.x + 0.5, y = poi.y + 0.5, z = poi.z, sx = poi.x, sy = poi.y, key = poi.key, facing = poi.facing or "S" }
end

function Module.seatPlan(shell, poi, now, chain)
    local seats = ProjectALife.SeatApi
    if seats == nil or type(seats.at) ~= "function" then return { gone = "no_seat_api" } end
    local seat
    if poi.kind == "bed" then
        seat = Module.bedSeat(poi)
    else
        seat = seats.at(shell, poi.x, poi.y, poi.z, now, nil)
    end
    if seat == nil then return { gone = "seat_gone" } end
    local stand = Module.standSquare(shell, seat.sx, seat.sy, seat.z, seat.facing)
    if stand == nil then return { gone = "no_approach" } end
    return { seat = seat, target = stand, tol = Module.settings.approachTol, pose = chain, cache = true }
end

function Module.fixturePlan(shell, poi, chain, face)
    local stand = Module.standSquare(shell, poi.x, poi.y, poi.z, nil, true)
    if stand == nil then return { gone = "no_approach" } end
    return { target = stand, tol = Module.settings.standTol, pose = chain,
        face = face and { x = poi.x + 0.5, y = poi.y + 0.5 } or nil, cache = true }
end

function Module.build(actor, shell, life, now)
    local kind, poi = life.k, life.poi
    local settings = Module.settings
    if kind == "stand" then return { tol = 0 } end
    if kind == "around" then return { tol = 0, around = true } end
    if type(poi) ~= "table" then return { gone = "poi_missing" } end
    if kind == "follow" then return { target = { x = poi.x, y = poi.y, z = poi.z }, tol = settings.followTol } end
    if kind == "walk" or kind == "bathroom" or kind == "floor" then
        return { target = { x = poi.x + 0.5, y = poi.y + 0.5, z = poi.z }, tol = settings.roomTol }
    end
    if kind == "pace" then
        return { target = { x = poi.x + 0.5, y = poi.y + 0.5, z = poi.z }, tol = settings.paceTol }
    end
    if kind == "farewell" then
        return { target = { x = poi.x + 0.5, y = poi.y + 0.5, z = poi.z }, tol = settings.farewellTol }
    end
    if kind == "change" then
        return { target = { x = poi.x + 0.5, y = poi.y + 0.5, z = poi.z }, tol = settings.roomTol, pose = Module.chains.change }
    end
    if kind == "look" then
        local vector = Module.vector[poi.facing or ""] or Module.vector.S
        return { target = { x = poi.x + 0.5, y = poi.y + 0.5, z = poi.z }, tol = settings.lookTol,
            face = { x = poi.x + 0.5 + vector[1] * 4, y = poi.y + 0.5 + vector[2] * 4 } }
    end
    if poi.kind == "seat" or poi.kind == "bed" then
        local chain = Module.chains[kind]
        if kind == "rest" and poi.kind == "bed" then chain = Module.chains.restBed end
        return Module.seatPlan(shell, poi, now, chain or Module.chains.sit)
    end
    local life_ = Module.life()
    if life_ ~= nil and life_.objectOf(poi) == nil then return { gone = "fixture_gone" } end
    if kind == "wash" or kind == "bath" then
        local plan = Module.fixturePlan(shell, poi, nil, true)
        plan.action = "wash"
        return plan
    end
    if kind == "read" then return Module.fixturePlan(shell, poi, Module.chains.shelf, true) end
    if kind == "warm" then return Module.fixturePlan(shell, poi, Module.chains.warm, true) end
    if kind == "drink" then return Module.fixturePlan(shell, poi, Module.chains.drink, true) end
    if kind == "eat" then return Module.fixturePlan(shell, poi, Module.chains.eat, true) end
    local chain = Module.kitchen[kind]
    if chain ~= nil then
        local plan = Module.fixturePlan(shell, poi, Module.chains[chain], true)
        if kind == "rinse_cup" then plan.action = "rinse" end
        return plan
    end
    if kind == "tv" or kind == "radio" then
        local stand = Module.standNear(shell, poi)
        if stand == nil then return { gone = "no_approach" } end
        return { target = stand, tol = settings.approachTol, face = { x = poi.x + 0.5, y = poi.y + 0.5 }, action = "device",
            cache = true }
    end
    return { gone = "kind_unknown" }
end

function Module.planFor(actor, shell, life, now)
    local cached = Module.plans[shell]
    if cached ~= nil and cached.seq == life.seq and cached.uid == actor.uid and now - cached.at < Module.settings.planMs
            and cached.plan.gone == nil then
        return cached.plan
    end
    local plan = Module.build(actor, shell, life, now)
    if plan.cache == true then Module.plans[shell] = { seq = life.seq, uid = actor.uid, at = now, plan = plan }
    else Module.plans[shell] = nil end
    return plan
end

function Module.arrived(shell, plan)
    local here = Module.positionOf(shell)
    if here == nil or plan.target == nil then return plan.target == nil end
    if math.abs((plan.target.z or 0) - here.z) > 0.8 then return false end
    local dx, dy = plan.target.x - here.x, plan.target.y - here.y
    return dx * dx + dy * dy <= plan.tol * plan.tol
end

function Module.walk(actor, shell, context, plan, now)
    Module.metrics.walks = Module.metrics.walks + 1
    if Module.walkRefused(actor, shell, plan.target, now) then
        Module.metrics.refused = Module.metrics.refused + 1
        return Module.hold(actor, context, now)
    end
    Module.unpose(shell)
    local state = context.startMovement(actor, shell, plan.target, "visitor_move", {
        pace = "walk", timeoutMs = Module.settings.moveTimeoutMs, doorsOnly = true, tolerance = plan.tol,
    })
    if state == nil then
        Module.metrics.refused = Module.metrics.refused + 1
        return Module.hold(actor, context, now)
    end
    return state
end

function Module.cleanBody(shell)
    local cleaned = 0
    if type(shell.getHumanVisual) == "function" then
        local visual = shell:getHumanVisual()
        if visual ~= nil then
            if type(visual.removeBlood) == "function" then
                visual:removeBlood()
                cleaned = cleaned + 1
            end
            if type(visual.removeDirt) == "function" then
                visual:removeDirt()
                cleaned = cleaned + 1
            end
        end
    end
    if type(shell.getItemVisuals) == "function" then
        local worn = shell:getItemVisuals()
        if worn ~= nil and type(worn.size) == "function" then
            for index = 0, worn:size() - 1 do
                local item = worn:get(index)
                if item ~= nil then
                    if type(item.removeBlood) == "function" then item:removeBlood() end
                    if type(item.removeDirt) == "function" then item:removeDirt() end
                    cleaned = cleaned + 1
                end
            end
        end
    end
    if cleaned > 0 and type(shell.resetModelNextFrame) == "function" then shell:resetModelNextFrame() end
    return cleaned
end

function Module.rinse(shell, poi)
    local life = Module.life()
    local sink = life ~= nil and life.objectOf(poi) or nil
    if sink == nil then return "dry" end
    if type(sink.hasWater) == "function" and sink:hasWater() ~= true then return "dry" end
    local cleaned = Module.cleanBody(shell)
    if cleaned == 0 then return "dry" end
    if Module.settings.useWater and type(sink.useFluid) == "function" and not (type(isClient) == "function" and isClient() == true) then
        sink:useFluid(1)
    end
    Module.metrics.rinsed = Module.metrics.rinsed + 1
    return "clean"
end

function Module.wash(shell, life, now, hurry)
    local row = Module.washes[shell]
    if row == nil or row.seq ~= life.seq then
        row = { seq = life.seq, startMs = now }
        Module.washes[shell] = row
        Module.metrics.washes = Module.metrics.washes + 1
    end
    local total = Module.settings.washMs[life.k] or 9000
    if hurry and row.hurryAt == nil then
        row.hurryAt = now
        Module.metrics.hurried = Module.metrics.hurried + 1
    end
    if row.hurryAt ~= nil then total = math.min(total, row.hurryAt - row.startMs + Module.settings.hurryMs) end
    if row.result == nil then
        if now - row.startMs >= total then
            row.result = Module.rinse(shell, life.poi)
            if row.result == "dry" then Module.metrics.dry = Module.metrics.dry + 1 end
            Module.unpose(shell)
        else
            local late = now - row.startMs >= total / 2
            Module.pose(shell, late and { "wash_face", "wash_hands" } or { "wash_hands", "wash_face" })
        end
    end
    if row.result == "dry" then return "visitor_wash_dry" end
    if row.result == "clean" then return "visitor_wash_done" end
    return nil
end

function Module.device(shell, life)
    local act = life.act
    if type(act) ~= "table" or act.k ~= "device_on" or Module.devices[shell] == life.seq then return end
    local owner = Module.life()
    local object = owner ~= nil and owner.objectOf(type(act.poi) == "table" and act.poi or life.poi) or nil
    local data = object ~= nil and type(object.getDeviceData) == "function" and object:getDeviceData() or nil
    Module.devices[shell] = life.seq
    if data == nil or type(data.getIsTurnedOn) ~= "function" then return end
    if data:getIsTurnedOn() == true then return end
    if type(data.canBePoweredHere) == "function" and data:canBePoweredHere() ~= true then
        Module.metrics.deviceDead = Module.metrics.deviceDead + 1
        return
    end
    if type(data.setIsTurnedOn) == "function" then
        data:setIsTurnedOn(true)
        Module.metrics.devices = Module.metrics.devices + 1
    end
end

function Module.sit(actor, shell, context, life, plan, now, near)
    local seats = ProjectALife.SeatApi
    local seat = plan.seat
    if not seats.seated(shell, seat) then
        if not seats.claim(seat, shell, now) then return Module.gone(actor, context, now, "seat_claimed") end
        if not seats.snap(shell, seat) then
            local tries = (Module.tries[shell] or 0) + 1
            Module.tries[shell] = tries
            if tries >= Module.settings.snapTries then
                Module.tries[shell] = nil
                seats.release(seat, shell)
                return Module.gone(actor, context, now, "snap_refused")
            end
            return Module.hold(actor, context, now)
        end
    end
    Module.tries[shell] = nil
    seats.claim(seat, shell, now)
    seats.face(shell, seat)
    Module.pose(shell, plan.pose)
    Module.metrics.sits = Module.metrics.sits + 1
    return Module.idle(actor, context, "visitor_" .. life.k, now)
end

function Module.players()
    local rows = {}
    if type(getOnlinePlayers) == "function" then
        local online = getOnlinePlayers()
        if online ~= nil and type(online.size) == "function" then
            for index = 0, online:size() - 1 do rows[#rows + 1] = online:get(index) end
        end
    end
    if #rows == 0 and type(getSpecificPlayer) == "function" then
        for number = 0, 3 do
            local player = getSpecificPlayer(number)
            if player ~= nil then rows[#rows + 1] = player end
        end
    end
    local list = {}
    for _, player in ipairs(rows) do
        if type(player.getX) == "function" and type(player.getY) == "function" and type(player.getZ) == "function" then
            list[#list + 1] = { x = player:getX(), y = player:getY(), z = player:getZ() }
        end
    end
    return list
end

function Module.nearest(actor, shell)
    local life = Module.life()
    local here = Module.positionOf(shell)
    if life == nil or here == nil or type(life.houseOf) ~= "function" or type(life.residents) ~= "function" then return nil end
    local house = life.houseOf(actor)
    local list = house ~= nil and life.residents(house) or Module.players()
    local row, d2 = life.nearest(list, here.x, here.y, here.z)
    if row == nil or d2 > Module.settings.noticeSq then return nil end
    return { x = row.x, y = row.y, z = row.z, d2 = d2 }
end

function Module.fidget(shell, now)
    local at = Module.fidgetAt[shell]
    local settings = Module.settings
    if at == nil then
        Module.fidgetAt[shell] = now + settings.fidgetFirstMs
        return false
    end
    if now < at then return false end
    local life = Module.life()
    local roll = life ~= nil and type(life.rand) == "function" and life.rand(settings.fidgetSpreadMs) or 0
    Module.fidgetAt[shell] = now + settings.fidgetMinMs + roll
    local animations = ProjectALife.Animations
    if animations == nil or type(animations.apply) ~= "function" or type(animations.supports) ~= "function" then return false end
    if animations.current ~= nil and animations.current[shell] ~= nil then return false end
    local pick = Module.fidgets[1 + (life ~= nil and life.rand(#Module.fidgets) or 0)]
    if not animations.supports(pick) then return false end
    Module.metrics.fidgets = Module.metrics.fidgets + 1
    return animations.apply(shell, pick) == true
end

function Module.attending(actor, key, now)
    local row = Module.attends[actor.uid]
    if row == nil or row.key ~= key or now - row.lastMs > Module.settings.rearmMs then
        row = { key = key, sinceMs = now, lastMs = now }
        Module.attends[actor.uid] = row
    end
    row.lastMs = now
    if now - row.sinceMs <= Module.settings.attendMs then return true end
    Module.metrics.attendCapped = Module.metrics.attendCapped + 1
    return false
end

function Module.avert(shell, near, now)
    local here = Module.positionOf(shell)
    if here == nil then return false end
    local dx, dy = near.x - here.x, near.y - here.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.2 then return false end
    local side = (math.floor(here.x) + math.floor(here.y)) % 2 == 0 and 1 or -1
    return Module.face(shell, here.x - dy / length * 4 * side, here.y + dx / length * 4 * side, now)
end

function Module.lookAround(shell, life, now)
    local here = Module.positionOf(shell)
    if here == nil then return false end
    local step = (math.floor(now / Module.settings.aroundMs) + (tonumber(life.seq) or 0)) % 4
    local vector = Module.ring[step + 1]
    Module.metrics.arounds = Module.metrics.arounds + 1
    return Module.face(shell, here.x + vector[1] * 4, here.y + vector[2] * 4, now)
end

function Module.track(actor, life, standing, now)
    local row = Module.stares[actor.uid]
    if not standing then
        Module.stares[actor.uid] = nil
        return
    end
    if row == nil or row.seq ~= life.seq or now - row.lastMs > Module.settings.stareKeepMs then
        row = { seq = life.seq, sinceMs = now }
        Module.stares[actor.uid] = row
    end
    row.lastMs = now
end

function Module.stareMs(uid, now)
    local row = Module.stares[uid]
    if row == nil or now - row.lastMs > Module.settings.stareKeepMs then return nil end
    return now - row.sinceMs
end

function Module.forget(uid)
    Module.stares[uid] = nil
    Module.attends[uid] = nil
end

function Module.settle(actor, shell, context, life, plan, now)
    local near = Module.nearest(actor, shell)
    local close = near ~= nil and near.d2 <= Module.settings.attendSq
    local idler = plan.seat == nil and plan.pose == nil and plan.action == nil and plan.around == nil and plan.face == nil
    Module.track(actor, life, idler and near ~= nil, now)
    if plan.around == true then
        Module.lookAround(shell, life, now)
        Module.pose(shell, nil)
        return Module.idle(actor, context, "visitor_" .. life.k, now)
    end
    local attending = near ~= nil and (close or plan.face == nil) and Module.attending(actor, life.seq, now)
    if plan.seat ~= nil then return Module.sit(actor, shell, context, life, plan, now, attending and near or nil) end
    if attending then
        Module.metrics.attended = Module.metrics.attended + 1
        Module.face(shell, near.x, near.y, now)
    elseif plan.face ~= nil then
        Module.face(shell, plan.face.x, plan.face.y, now)
    elseif near ~= nil then
        Module.avert(shell, near, now)
    end
    local intent = "visitor_" .. life.k
    if plan.action == "wash" then
        intent = Module.wash(shell, life, now, close and life.poi ~= nil and life.poi.room == "bathroom") or intent
    else
        Module.pose(shell, plan.pose)
        if plan.action == "device" then Module.device(shell, life) end
        if plan.pose == nil and plan.action == nil and not attending then Module.fidget(shell, now) end
    end
    return Module.idle(actor, context, intent, now)
end

function Module.run(actor, shell, context, life, now)
    Module.metrics.runs = Module.metrics.runs + 1
    local plan = Module.planFor(actor, shell, life, now)
    if plan.gone ~= nil then return Module.gone(actor, context, now, plan.gone) end
    local seated = plan.seat ~= nil and ProjectALife.SeatApi.seated(shell, plan.seat)
    if not seated and plan.target ~= nil and not Module.arrived(shell, plan) then
        return Module.walk(actor, shell, context, plan, now)
    end
    return Module.settle(actor, shell, context, life, plan, now)
end

function Module.evaluate(actor, shell, context)
    local memory = type(actor) == "table" and actor.memory or nil
    if type(memory) ~= "table" then return nil end
    local life = memory.life
    if type(life) ~= "table" or type(life.k) ~= "string" then return nil end
    if type(memory.guest) ~= "table" or actor.lifecycle ~= "active" then return nil end
    if type(memory.person) ~= "table" then
        local life_ = Module.life()
        if life_ == nil or type(life_.options) ~= "function" or life_.options().guestLife == false then return nil end
        Module.metrics.plain = Module.metrics.plain + 1
    end
    if not Registry.allows(actor, "visitorLife") then return nil end
    if not Module.drives(shell) then return nil end
    if context.threat ~= nil then
        Module.metrics.suspended = Module.metrics.suspended + 1
        Module.unpose(shell)
        pcall(function() shell:setHideWeaponModel(false) end)
        return nil
    end
    Module.holster(shell)
    return Module.run(actor, shell, context, life, tonumber(context.now) or Module.nowMs())
end

function Module.rootPoses()
    local fence = ProjectALife.AIFence
    local table_ = fence ~= nil and fence.crowd ~= nil and fence.crowd.rootedPoses or nil
    if type(table_) ~= "table" then return 0 end
    local added = 0
    for _, id in ipairs(Module.rooted) do
        if table_[id] ~= true then
            table_[id] = true
            added = added + 1
        end
    end
    return added
end
Module.rootPoses()

function Module.reset()
    Module.attends, Module.stares = {}, {}
    Module.posed = setmetatable({}, { __mode = "k" })
    Module.plans = setmetatable({}, { __mode = "k" })
    Module.washes = setmetatable({}, { __mode = "k" })
    Module.devices = setmetatable({}, { __mode = "k" })
    Module.tries = setmetatable({}, { __mode = "k" })
    Module.fidgetAt = setmetatable({}, { __mode = "k" })
    for key in pairs(Module.metrics) do Module.metrics[key] = type(Module.metrics[key]) == "number" and 0 or "-" end
end

function Module.qaLine()
    local m = Module.metrics
    return "[ALIFE-QA] VisitorLifeModule runs=" .. tostring(m.runs) .. " walks=" .. tostring(m.walks)
        .. " refused=" .. tostring(m.refused) .. " holds=" .. tostring(m.holds) .. " sits=" .. tostring(m.sits)
        .. " gone=" .. tostring(m.gone) .. " washes=" .. tostring(m.washes) .. " rinsed=" .. tostring(m.rinsed)
        .. " dry=" .. tostring(m.dry) .. " devices=" .. tostring(m.devices) .. " plain=" .. tostring(m.plain)
        .. " attended=" .. tostring(m.attended) .. " fidgets=" .. tostring(m.fidgets) .. " hurried=" .. tostring(m.hurried)
        .. " capped=" .. tostring(m.attendCapped) .. " arounds=" .. tostring(m.arounds)
        .. " why=" .. tostring(m.lastWhy)
end

Registry.register({
    id = "visitorLife",
    label = "Visitor life",
    summary = "A guest inside the house walks around, sits, reads, looks out of a window, washes and warms up.",
    kind = "orders",
    priority = 93,
    defaultEnabled = true,
    evaluate = Module.evaluate,
})

return Module
