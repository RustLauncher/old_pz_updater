TunaWRServer = TunaWRServer or {}

local MODULE = 'Tuna_WeaponRack'

-- exact addressing, no fallback: a command that cannot name its object is refused
local function findObject(args)
    if not args then return nil end
    local cell = getCell()
    if not cell then return nil end
    local sq = cell:getGridSquare(args.x, args.y, args.z)
    if not sq then return nil end
    local objs = sq:getObjects()
    if not objs then return nil end
    if not (args.oi and args.oi >= 0 and args.oi < objs:size()) then return nil end
    local o = objs:get(args.oi)
    if not o then return nil end
    if not TunaWRItem.pieceOf(o) then return nil end
    return o
end

local function target(player, args)
    local obj = findObject(args)
    if not obj then return nil, 'noObject' end
    local ok, d = TunaWRItem.inRange(player, obj)
    -- the refusal carries its measurement: a wrong constant and a wrong position must not read alike
    if not ok then
        return nil, string.format('outOfRange d2=%.2f limit=%.2f', d, TunaWRItem.RANGE_SQ)
    end

    -- re-installed on EVERY accepted command: the authority never runs the client discovery sweep
    TunaWRItem.installPredicates(obj)
    return obj, nil
end

function TunaWRServer.prepareRack(player, args)
    local obj, why = target(player, args)
    if not obj then return false, why end
    local c, created, err = TunaWRItem.prepareRack(obj)
    if err and err ~= 'migrated' and err ~= 'noDrawerForPiece' then return false, err end
    return true, created and 'created' or (err or (c and 'present' or 'noDrawer'))
end

function TunaWRServer.apply(player, args)
    local obj, why = target(player, args)
    if not obj then return false, why end

    local piece = TunaWRItem.pieceOf(obj)
    local slots = piece and TunaWRSlots.PIECES[piece] or nil
    if not slots then return false, 'noSlots' end

    local cont = obj:getContainer()
    if not cont then return false, 'noContainer' end

    local ok, reason = TunaWRSlots.validate(slots, args.ids, TunaWRItem.itemsOf(cont))
    if not ok then return false, reason end

    local mv = TunaWRItem.movable(obj, true)
    if not mv then return false, 'noModData' end

    -- writing the schema key is what puts the rack into CUSTOM mode, and it is one-way
    TunaWRSlots.encode(mv, args.ids, #slots)
    obj:transmitModData()

    if isServer() then
        sendServerCommand(MODULE, 'slotsChanged',
            { x = args.x, y = args.y, z = args.z, oi = args.oi })
    end
    return true, nil
end

-- FOUR params here, THREE on the client handler; and _module must be filtered first
function TunaWRServer.onClientCommand(_module, _command, _player, _args)
    if _module ~= 'Tuna_WeaponRack' then return end

    if _command == 'setSlots' then
        local ok, reason = TunaWRServer.apply(_player, _args)
        if not ok then
            print('[Tuna_WeaponRack] setSlots REFUSED reason=' .. tostring(reason))
        end
        return
    end

    if _command == 'prepareRack' then
        local ok, reason = TunaWRServer.prepareRack(_player, _args)
        print('[Tuna_WeaponRack] prepareRack ok=' .. tostring(ok) ..
              ' reason=' .. tostring(reason))
        return
    end
end

-- server/ loads on clients too; this guard is not decoration
if isServer() then Events.OnClientCommand.Add(TunaWRServer.onClientCommand) end
