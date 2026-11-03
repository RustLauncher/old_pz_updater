if isServer() then return end   -- a server has no viewport (Bobber.lua:32 idiom)

local PREFIX      = 'tuna_weaponrack_01_'   -- our own cells, and only ours
local RADIUS      = 8
local SWEEP_TICKS = 30
local MAX_RACKS   = 32

if not (TunaWRSlots and TunaWRSlots.PIECES) then
    print('[Tuna_WeaponRack] FATAL shared/Tuna_WeaponRack_Slots.lua did not load first')
    return
end
if not (TunaWRItem and TunaWRItem.classify) then
    print('[Tuna_WeaponRack] FATAL shared/Tuna_WeaponRack_Item.lua did not load first')
    return
end
local PIECE_SLOTS = TunaWRSlots.PIECES

TunaWRItem.TRACE = TunaWRItem.TRACE or false

-- difference (x-y) is lateral; the SUM is vertical AND the in-front-of-own-sprite threshold
local PIVOT = {
    cabinet  = { x = 0.189, y = 0.311 },   -- sum 0.50, difference -0.122

    armory   = { x = 0.625, y = 0.625 },
    handguncase = { x = 0.4235, y = 0.4525 },-- sum 0.876, difference -0.029
}

-- replaces PIVOT for ONE facing; overrides that change their piece's sum are enumerated in tools\common\WeaponRackSlots.ps1
local PIVOT_FACING = {
    cabinet     = { S = { x = 0.264,  y = 0.486  }, E = { x = 0.533,  y = 0.217  } },
    handguncase = { N = { x = 0.4235, y = 0.3998 }, E = { x = 0.4762, y = 0.4525 }, S = { x = 0.4235, y = 0.5052 }, W = { x = 0.3708, y = 0.4525 } },
    armory      = { E = { x = 0.679,  y = 0.400  } },
}

-- applied BEFORE the pivot, and it mirrors about the piece's own extent, never about one tile
local FRAME = {
    N = function(dx, dy, ex, ey) return dx,        dy        end,
    E = function(dx, dy, ex, ey) return ey - dy,   dx        end,
    S = function(dx, dy, ex, ey) return ex - dx,   ey - dy   end,
    W = function(dx, dy, ex, ey) return dy,        ex - dx   end,
}
local TURNS = { N = 0, E = 1, S = 2, W = 3 }

-- eyes-only: nothing here can tell which way the engine turns a yaw
local YAW_SIGN = 1

local DERIVED = {}
for piece, slots in pairs(PIECE_SLOTS) do
    DERIVED[piece] = {}
    local ex, ey = TunaWRSlots.extentOf(piece)
    for facing, turns in pairs(TURNS) do
        local out = {}
        local resolved = TunaWRSlots.resolvedFor(piece, facing)
        local pInfo = TunaWRSlots.infoOf(piece)
        local buttScale = pInfo and pInfo.buttScale
        for i = 1, #slots do
            local s = slots[i]
            local r = resolved and resolved[i]
            if r then
                out[i] = {
                    cat = s.cat, dx = r.dx, dy = r.dy, dz = r.dz, butt = s.butt,
                    rx = r.rx, ry = r.ry, rz = r.rz, buttScale = buttScale,
                    noBarrelFlip = (pInfo and pInfo.noBarrelFlip) and true or false,
                }
            else
            local wx, wy = FRAME[facing](s.dx, s.dy, ex, ey)
            local pf = PIVOT_FACING[piece]
            local p = (pf and pf[facing]) or PIVOT[piece]
            if p then wx, wy = wx + p.x, wy + p.y end
            out[i] = {
                cat = s.cat, dx = wx, dy = wy, dz = s.dz, butt = s.butt,
                rx = s.rx, ry = s.ry,
                rz = (s.rz + YAW_SIGN * 90 * turns) % 360,
                buttScale = buttScale,
            }
            end
        end
        DERIVED[piece][facing] = out
    end
end

local function say(s) print('[Tuna_WeaponRack] ' .. s) end

do
    local LEGACY = {
        N = function(dx, dy) return dx,       dy       end,
        E = function(dx, dy) return 1 - dy,   dx       end,
        S = function(dx, dy) return 1 - dx,   1 - dy   end,
        W = function(dx, dy) return dy,       1 - dx   end,
    }
    local moved, checked = 0, 0
    for piece, slots in pairs(PIECE_SLOTS) do
        local ex, ey = TunaWRSlots.extentOf(piece)
        if ex == 1 and ey == 1 then
            for facing, _ in pairs(TURNS) do
                for i = 1, #slots do
                    local s = slots[i]
                    local ox, oy = LEGACY[facing](s.dx, s.dy)
                    local nx, ny = FRAME[facing](s.dx, s.dy, ex, ey)
                    checked = checked + 1
                    if ox ~= nx or oy ~= ny then moved = moved + 1 end
                end
            end
        end
    end
    if moved > 0 then
        say('⛔ REGRESSION: ' .. moved .. ' of ' .. checked ..
            ' single-square stations moved when FRAME took the extent. The accepted cabinet ' ..
            'and handgun case positions are NOT preserved - do not judge any frame from this build.')
    else
        say('extent transform: ' .. checked ..
            ' single-square stations identical to the one-tile formulas (cabinet and case unmoved)')
    end
end

local racks = {}   -- rebuilt every sweep: { obj, cont, sq, key, facing, piece }
local noted = {}   -- key -> true, so a refusal or a failure logs once
local prepared = {}   -- key -> the OBJECT, so a re-placed rack prepares and a revisited one does not

-- a fact about PZ's fixed camera, not a property of any piece
local REAR_FACING = { N = true, W = true }

local ALPHA_OPAQUE = 0.999

local playerNum = 0   -- refreshed by the sweep, which already holds the player

-- read the engine's own alpha, never invent a distance; never SET alpha; fails closed
local function engineIsFading(obj)
    local fading = false
    pcall(function()
        local a = obj:getAlpha(playerNum)
        if a and a < ALPHA_OPAQUE then fading = true end
    end)
    return fading
end

-- a 1x2 has two carcasses faded independently: BOTH, or the far half reveals early
local function partnerIsFading(r)
    local ex, ey = TunaWRSlots.extentOf(r.piece)
    if ex == 1 and ey == 1 then return true end

    local off = TunaWRSlots.PARTNER_OFFSET[r.facing]
    if off == nil then return false end

    local partner = nil
    pcall(function()
        local sq = r.obj:getSquare()
        if sq == nil then return end
        local psq = getCell():getGridSquare(sq:getX() + off[1], sq:getY() + off[2], sq:getZ())
        if psq == nil then return end
        local objs = psq:getObjects()
        for i = 0, objs:size() - 1 do
            local o = objs:get(i)
            if o and TunaWRSlots.masterPieceOf(TunaWRItem.pieceOf(o)) == r.piece then
                partner = o
                return
            end
        end
    end)
    if partner == nil then return false end
    return engineIsFading(partner)
end

-- fieldrack: open welded frame, no back for a weapon to draw through
-- the handgun case is NOT exempt: on N and W its pistols show only while the piece is fading
local REAR_FACING_EXEMPT = { fieldrack = true }

local function shouldDraw(r)
    if not REAR_FACING[r.facing] then return true end
    if REAR_FACING_EXEMPT[TunaWRSlots.masterPieceOf(r.piece) or r.piece] then return true end
    return engineIsFading(r.obj) and partnerIsFading(r)
end

local function spriteNameOf(obj)
    local n = nil
    pcall(function()
        local sp = obj:getSprite()
        if sp then n = sp:getName() end
    end)
    return n
end

-- the ONLY place a satellite is rejected; racks is written here alone
local function isOurRack(obj, sq)
    if sq:getFloor() == obj then return nil end   -- B42 floors are moveable too
    local name = spriteNameOf(obj)
    if not name then return nil end
    if string.sub(name, 1, #PREFIX) ~= PREFIX then return nil end
    if TunaWRSlots.isSatellitePiece(TunaWRItem.pieceOf(obj)) then return nil end
    return name
end

-- a re-placed 1x2 loses its entity: the engine refuses to transfer multi-square components
local function restoreMultiSquareEntity(obj, sq, name)
    local piece = TunaWRItem.pieceOf(obj)
    if piece == nil then return end

    local ex, ey = TunaWRSlots.extentOf(TunaWRSlots.masterPieceOf(piece) or piece)
    if ex == 1 and ey == 1 then return end

    local intact = true
    pcall(function() intact = obj:hasComponents() end)
    if intact then return end

    local key = 'ent@' .. sq:getX() .. ',' .. sq:getY() .. ',' .. sq:getZ() .. '@' .. name
    if noted[key] then return end
    noted[key] = true

    -- resolve the global first: the jar is not the binding, and calling nil threw 12 stacks a tick
    local factory = nil
    pcall(function() factory = GameEntityFactory.CreateIsoObjectEntity end)
    if factory == nil then
        say('entity rebuild UNAVAILABLE on ' .. key .. ' - GameEntityFactory.CreateIsoObjectEntity is not bound in Lua')
        return
    end

    local script = nil
    pcall(function()
        local info = SpriteConfigManager.getObjectInfoFromSprite(name)
        if info and info:getScript() then script = info:getScript():getParent() end
    end)
    if script == nil then
        say('entity rebuild SKIPPED on ' .. key .. ' - no entity script resolves from that sprite')
        return
    end

    local ok, err = pcall(function() GameEntityFactory.CreateIsoObjectEntity(obj, script, true) end)
    local back = false
    pcall(function() back = obj:hasComponents() end)
    say('entity rebuilt on ' .. key .. ' call=' .. tostring(ok) ..
        ' components=' .. tostring(back) .. ' err=' .. tostring(err))
end

local function propOf(obj, key)
    local v = nil
    pcall(function()
        local props = obj:getSprite():getProperties()
        if props and props:has(key) then v = props:get(key) end
    end)
    return v
end

local function facingOf(obj) return TunaWRItem.facingOf(obj) end

local function reconcile(p, r)
    local slots = r.piece and PIECE_SLOTS[r.piece] or nil
    if not slots then return end

    local bound = TunaWRItem.boundOf(r.obj, #slots)
    if bound == nil then return end                     -- AUTO already shows it
    if not TunaWRItem.inRange(p, r.obj) then return end

    local items = TunaWRItem.itemsOf(r.cont)
    local cur   = TunaWRSlots.resolve(slots, bound, items)
    local ids   = TunaWRSlots.reconcile(slots, cur, items)

    local nk = 'recon@' .. r.key
    if not ids then noted[nk] = nil; return end

    local ok, why = TunaWRItem.applyArrangement(p, r.obj, ids)
    if not noted[nk] then
        noted[nk] = true
        say('RECONCILE key=' .. r.key .. ' ok=' .. tostring(ok) .. ' ' .. tostring(why))
    end
end

local function sweep()
    local p = getPlayer()
    if not p then racks = {}; return end
    pcall(function() playerNum = p:getPlayerNum() or 0 end)
    local px, py, pz = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
    local found = {}

    for dx = -RADIUS, RADIUS do
        for dy = -RADIUS, RADIUS do
            local sq = getCell():getGridSquare(px + dx, py + dy, pz)
            if sq then
                local objs = sq:getObjects()
                for i = 0, objs:size() - 1 do
                    local o = objs:get(i)

                    local spr = o and spriteNameOf(o)
                    if spr and string.sub(spr, 1, #PREFIX) == PREFIX then
                        restoreMultiSquareEntity(o, sq, spr)
                    end

                    local name = o and isOurRack(o, sq)
                    if name and #found < MAX_RACKS then
                        local key = sq:getX() .. ',' .. sq:getY() .. ',' .. sq:getZ() .. '@' .. name

                        local prepKey = 'prep@' .. key
                        -- keyed on the OBJECT, never on drawer state: the request is what makes the
                        -- AUTHORITY install its accept filters, and it has no other path to them
                        if prepared[prepKey] ~= o then
                            if isClient() then
                                if TunaWRItem.inRange(p, o) then
                                    prepared[prepKey] = o
                                    sendClientCommand(p, 'Tuna_WeaponRack', 'prepareRack', {
                                        x = sq:getX(), y = sq:getY(), z = sq:getZ(),
                                        oi = o:getObjectIndex(),
                                    })
                                    say('PREPARE-REQUEST key=' .. key)
                                end
                            else
                                prepared[prepKey] = o
                                local c, created, err = TunaWRItem.prepareRack(o)
                                say('PREPARE key=' .. key ..
                                    ' created=' .. tostring(created) ..
                                    ' drawer=' .. tostring(c ~= nil) ..
                                    ' count=' .. tostring(o:getContainerCount()) ..
                                    ' err=' .. tostring(err))
                            end
                        end

                        TunaWRItem.installPredicates(o)

                        local c = TunaWRItem.containerOfType(o, TunaWRItem.BAY_TYPE)
                        if not c then pcall(function() c = o:getContainer() end) end
                        if c then
                            table.insert(found, {
                                obj = o, cont = c, sq = sq,
                                facing = facingOf(o),
                                piece  = propOf(o, 'TunaRackPiece'),
                                key = key,
                            })
                        end
                    end
                end
            end
        end
    end
    racks = found

    local seenKeys = {}
    for _, r in ipairs(found) do seenKeys[r.key] = true end
    for k in pairs(noted) do
        local at = k:find('@', 1, true)
        if at and k:sub(1, at) == 'recon@'
           and not seenKeys[k:sub(at + 1)] then
            noted[k] = nil
        end
    end

    for _, r in ipairs(racks) do pcall(reconcile, p, r) end

    for _, r in ipairs(racks) do
        if not noted[r.key] then
            if not (r.piece and DERIVED[r.piece]) then
                noted[r.key] = true
                say('SKIP key=' .. r.key .. ' TunaRackPiece=' .. tostring(r.piece) ..
                    ' (no slot table for that piece)')
            elseif not (r.facing and FRAME[r.facing]) then
                noted[r.key] = true
                say('SKIP key=' .. r.key .. ' facing=' .. tostring(r.facing) ..
                    ' (not one of N/E/S/W)')
            end
        end
    end
end

local ORIGIN_BUTT_DROP = -TunaWRItem.BUTT_Y_DEFAULT

local OFFSET_REF = 0.150
local OFFSET_K   = 1.0

local function worldOffsetX(item)
    local x
    pcall(function()
        local ms = TunaWRItem.modelScriptOf(item)
        if not ms then return end
        local a = ms:getAttachmentById('world')
        if not a then return end
        local v = a:getOffset()
        if v then x = v:x() end
    end)
    return x
end

local function worldOffsetY(item)
    local y
    pcall(function()
        local ms = TunaWRItem.modelScriptOf(item)
        if not ms then return end
        local a = ms:getAttachmentById('world')
        if not a then return end
        local v = a:getOffset()
        if v then y = v:y() end
    end)
    return y
end

local function onRenderWorld()
    for _, r in ipairs(racks) do
        local byFacing = r.piece and DERIVED[r.piece]
        local slots = byFacing and r.facing and byFacing[r.facing]
        if slots and shouldDraw(r) then
            local pool = TunaWRItem.itemsOf(r.cont)
            local byId = {}
            for pi = 1, #pool do byId[pool[pi].id] = pool[pi].item end
            local placed = TunaWRSlots.resolve(slots, TunaWRItem.boundOf(r.obj, #slots), pool)

            for i = 1, #slots do
                local it = placed[i] and byId[placed[i]] or nil

                if it then
                    local s = slots[i]

                    local drop, usedRp = TunaWRItem.buttDrop(it)
                    local noWorld = (drop == nil)
                    drop = drop or ORIGIN_BUTT_DROP
                    -- read ONCE and flip ry per draw only; s.ry is shared, derived at load, never mutated
                    local rev = TunaWRItem.barrelReversed(it)
                    local flipped = (not s.noBarrelFlip) and rev or false
                    local ry = s.ry
                    if flipped then ry = (ry + 180) % 360 end

                    -- the APPLIED drop, never the computed one - a flat slot adds nothing
                    local applied = s.butt and (drop * (s.buttScale or 1)) or 0
                    local dz   = s.dz + applied

                    if TunaWRItem.TRACE then
                        local poseKey = 'pose@' .. r.key .. '#' .. i .. '@' .. tostring(it:getFullType())
                        if not noted[poseKey] then
                            noted[poseKey] = true
                            local woy = worldOffsetY(it)
                            local ms = TunaWRItem.modelScriptOf(it)
                            local msc, prx, pry, prz = nil, nil, nil, nil
                            pcall(function() msc = ms and ms.scale end)
                            pcall(function()
                                prx = it:getWorldXRotation()
                                pry = it:getWorldYRotation()
                                prz = it:getWorldZRotation()
                            end)
                            say(string.format(
                                'POSE %s facing=%s slot=%d mode=%s item=%s | d=(%.3f,%.3f,%.3f) rot=(%d,%d,%d) ' ..
                                'pre=(%s,%s,%s) | world=(%.3f,%.3f) anchor=%s drop=%.3f rp=%s scale=%s ' ..
                                'rev=%s flip=%s noworld=%s authored_ry=%d',
                                r.key, tostring(r.facing), i,
                                TunaWRItem.boundOf(r.obj, #slots) and 'custom' or 'auto',
                                tostring(it:getFullType()),
                                s.dx, s.dy, dz, s.rx, ry, s.rz,
                                tostring(prx), tostring(pry), tostring(prz),
                                worldOffsetX(it) or -1, woy or -1, s.butt and 'butt' or 'flat', applied,
                                usedRp and 'yes' or 'DEFAULT',
                                tostring(msc),
                                rev and 'YES' or 'no',
                                flipped and 'YES' or 'no',
                                noWorld and 'YES' or 'no',
                                s.ry))
                        end
                    end

                    local ox, oy, oz = 0, 0, 0
                    pcall(function()
                        ox = it:getWorldXRotation()
                        oy = it:getWorldYRotation()
                        oz = it:getWorldZRotation()
                    end)

                    -- set - draw - restore; the restore below is unconditional and sits after the pcall
                    local ok, err = pcall(function()
                        it:setWorldXRotation(s.rx)
                        it:setWorldYRotation(ry)          -- station ry, +180 when flagged
                        it:setWorldZRotation(s.rz)
                        -- the trailing -1 is a SENTINEL, not a rotation: any value >= 0 zeroes rx and ry
                        Render3DItem(it, r.sq,
                            r.sq:getX() + s.dx,
                            r.sq:getY() + s.dy,
                            r.sq:getZ() + dz,
                            -1)
                    end)

                    pcall(function()
                        it:setWorldXRotation(ox)
                        it:setWorldYRotation(oy)
                        it:setWorldZRotation(oz)
                    end)

                    if not ok and not noted[r.key .. '#' .. i] then
                        noted[r.key .. '#' .. i] = true
                        say('DRAW-FAIL key=' .. r.key .. ' slot=' .. i ..
                            ' type=' .. tostring(it:getFullType()) .. ' err=' .. tostring(err))
                    end
                end
            end
        end
    end
end

local tick = 0
Events.OnTick.Add(function()
    tick = tick + 1
    if (tick % SWEEP_TICKS) == 0 then pcall(sweep) end
end)

Events.RenderOpaqueObjectsInWorld.Add(function() pcall(onRenderWorld) end)

local loadedPieces = {}
for piece in pairs(TunaWRSlots.PIECE_INFO) do loadedPieces[#loadedPieces + 1] = piece end
table.sort(loadedPieces)
say('display loaded (M3: all four facings derived, judge S and E, ' ..
    'pieces ' .. table.concat(loadedPieces, '/') .. ', radius ' .. RADIUS .. ')')
