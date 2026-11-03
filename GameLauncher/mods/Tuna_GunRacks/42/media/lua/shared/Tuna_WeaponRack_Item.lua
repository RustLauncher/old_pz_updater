TunaWRItem = TunaWRItem or {}

function TunaWRItem.modelKeyOf(item)
    local key = nil
    pcall(function()
        local n = item:getWorldStaticItem()
        if n == nil or n == '' then n = item:getStaticModel() end
        if n == nil or n == '' then return end
        key = n
    end)
    return key
end

function TunaWRItem.modelScriptOf(item)
    local n = TunaWRItem.modelKeyOf(item)
    if n == nil then return nil end
    local ok, script = pcall(function()
        return getScriptManager():getModelScript(n)
    end)
    if not ok then return nil end
    return script
end

-- classification IS eligibility IS acceptance: one function, so the three cannot drift
function TunaWRItem.classify(item)
    if not item then return nil end
    -- guard order: HandWeapon first, then a resolvable model, or a slot draws nothing
    if not instanceof(item, 'HandWeapon') then return nil end
    if not TunaWRItem.modelScriptOf(item) then return nil end
    if item:isRanged() then
        if item:isTwoHandWeapon() then return 'LONG_GUN' end
        return 'HANDGUN'
    end
    return 'MELEE'
end

function TunaWRItem.pieceOf(obj)
    local v = nil
    pcall(function()
        local props = obj:getSprite():getProperties()
        if props and props:has('TunaRackPiece') then v = props:get('TunaRackPiece') end
    end)
    return v
end

-- from the tile property, NEVER the sprite cell index - vanilla cell order disagrees
function TunaWRItem.facingOf(obj)
    local v = nil
    pcall(function()
        local props = obj:getSprite():getProperties()
        if props and props:has('Facing') then v = props:get('Facing') end
    end)
    return v
end

-- the one canonical satellite->master walk, from authored data only, never a sprite index
function TunaWRItem.masterOf(obj)
    if obj == nil then return nil end
    local piece = TunaWRItem.pieceOf(obj)
    if piece == nil then return nil end
    local masterPiece = TunaWRSlots.masterPieceOf(piece)
    if masterPiece == nil then return obj end          -- not a satellite: it IS the master

    local found = nil
    pcall(function()
        local facing = TunaWRItem.facingOf(obj)
        local off = facing and TunaWRSlots.PARTNER_OFFSET[facing] or nil
        if off == nil then return end
        local sq = obj:getSquare()
        if sq == nil then return end
        local anchor = getCell():getGridSquare(sq:getX() - off[1], sq:getY() - off[2], sq:getZ())
        if anchor == nil then return end               -- partner square loaded, anchor's is not
        local objs = anchor:getObjects()
        for i = 0, objs:size() - 1 do
            local o = objs:get(i)
            if o and TunaWRItem.pieceOf(o) == masterPiece then found = o; return end
        end
    end)
    return found
end

function TunaWRItem.itemsOf(cont)
    local out = {}
    local ok = pcall(function()
        local items = cont:getItems()
        for i = 0, items:size() - 1 do
            local it = items:get(i)
            if it then
                out[#out + 1] = { id = it:getID(), cat = TunaWRItem.classify(it), item = it }
            end
        end
    end)
    if not ok then return {} end
    return out
end

function TunaWRItem.movable(obj, create)
    local md = obj and obj.getModData and obj:getModData()
    if not md then return nil end
    if type(md.movableData) ~= 'table' then
        if not create then return nil end
        md.movableData = {}
    end
    return md.movableData
end

function TunaWRItem.boundOf(obj, n)
    return TunaWRSlots.decode(TunaWRItem.movable(obj, false), n)
end

-- the crafted-furniture branch, NOT the radio branch's 2.25 - that refused every command
TunaWRItem.RANGE_SQ = 1.5 * 4.0

function TunaWRItem.inRange(player, obj)
    if not (player and obj) then return false, -1 end
    if not obj:getSquare() then return false, -1 end
    local d = player:DistToSquared(obj:getX() + 0.5, obj:getY() + 0.5)
    return d < TunaWRItem.RANGE_SQ, d
end

-- fleet median over the 13 models that declare recoilpad; no estimator, 2*world-muzzle fails
TunaWRItem.BUTT_Y_DEFAULT = -0.150

-- returns drop AND whether recoilpad was used: the number alone is truthy either way
function TunaWRItem.buttDrop(item)
    local drop, usedRp = nil, false
    pcall(function()
        local ms = TunaWRItem.modelScriptOf(item)
        if not ms then return end
        local w = ms:getAttachmentById('world')
        if not w then return end          -- unnormalised by the engine too
        local wy = w:getOffset():y()

        local by = TunaWRItem.BUTT_Y_DEFAULT
        local rp = ms:getAttachmentById('recoilpad')
        if rp then by = rp:getOffset():y(); usedRp = true end

        drop = wy - by
    end)
    return drop, usedRp
end

local BARREL_REVERSED = {}

-- a semantic barrel-axis test, not a rotation whitelist; cached per model script
function TunaWRItem.barrelReversed(item)
    local reversed = false
    pcall(function()
        local key = TunaWRItem.modelKeyOf(item)
        if key == nil then return end

        local cached = BARREL_REVERSED[key]
        if cached ~= nil then reversed = cached; return end

        local ms = getScriptManager():getModelScript(key)
        local a = ms and ms:getAttachmentById('world')
        local v = a and a:getRotate()
        if v == nil then BARREL_REVERSED[key] = false; return end

        local d = math.pi / 180
        local x, y, z = v:x() * d, v:y() * d, v:z() * d
        local barrel = math.cos(z) * math.cos(x) - math.sin(z) * math.sin(y) * math.sin(x)

        reversed = (barrel < 0)
        BARREL_REVERSED[key] = reversed
    end)
    return reversed
end

TunaWRItem.BAY_TYPE = 'shelves'

-- mod-owned so it inherits no vanilla desk LOOT; container type is the distribution key
TunaWRItem.DRAWER_TYPE = 'TunaWeaponRackAmmoDrawer'

-- migration only - never reuse, and do not remove while a save can still carry one
TunaWRItem.DRAWER_TYPE_LEGACY = 'desk'

function TunaWRItem.containerOfType(obj, t)
    local hit = nil
    pcall(function()
        for i = 0, obj:getContainerCount() - 1 do
            local c = obj:getContainerByIndex(i)
            if c and c:getType() == t then hit = c; return end
        end
    end)
    return hit
end

function TunaWRItem.replicateContainers(obj)
    if not isServer() then return end
    pcall(function() obj:sendObjectChange(IsoObjectChange.CONTAINERS) end)
end

function TunaWRItem.ensureDrawer(obj)
    if isClient() then return nil, false, 'client' end

    local existing = TunaWRItem.containerOfType(obj, TunaWRItem.DRAWER_TYPE)
    if existing then return existing, false, nil end

    local legacy = TunaWRItem.containerOfType(obj, TunaWRItem.DRAWER_TYPE_LEGACY)
    if legacy then
        local ok, err = pcall(function()
            -- migrate in place, never delete: its contents are indistinguishable from player property
            legacy:setType(TunaWRItem.DRAWER_TYPE)
            TunaWRItem.replicateContainers(obj)
        end)
        if not ok then return nil, false, 'migrate:' .. tostring(err) end
        return legacy, false, 'migrated'
    end

    local made = nil
    local ok, err = pcall(function()
        local sq = obj:getSquare()
        if not sq then return end
        local c = ItemContainer.new(TunaWRItem.DRAWER_TYPE, sq, obj)
        if not c then return end
        obj:addSecondaryContainer(c)

        local cap = TunaWRSlots.infoOf(TunaWRItem.pieceOf(obj))
        cap = cap and cap.drawerCapacity
        if cap then c:setCapacity(cap) end

        -- scoped exception to the never-setExplored rule: OUR container, just created, must start empty
        c:setExplored(true)
        made = c
        TunaWRItem.replicateContainers(obj)
    end)
    if not ok then return nil, false, tostring(err) end
    return made, made ~= nil, nil
end

-- the arrangement's ONE sender, shared, and it reuses the existing setSlots command
function TunaWRItem.applyArrangement(player, obj, ids)
    if ids == nil then return false, 'noArrangement' end
    if not (player and obj) then return false, 'noTarget' end

    local args = { x = obj:getX(), y = obj:getY(), z = obj:getZ(),
                   oi = obj:getObjectIndex(), ids = ids }

    if isClient() then
        sendClientCommand(player, 'Tuna_WeaponRack', 'setSlots', args)
        return true, 'sent'
    end

    if not (TunaWRServer and TunaWRServer.apply) then return false, 'noServerModule' end
    return TunaWRServer.apply(player, args)
end

TunaWRAccept = TunaWRAccept or {}

TunaWRAccept.COMPAT_DRAWER_CATEGORIES = {
    WepAmmo    = true,   -- "Weapon - Ammunition"  - loose rounds and boxes
    WepAmmoMag = true,   -- "Weapon - Magazine"    - magazines and clips
    WepPart    = true,   -- "Weapon - Part"        - scopes, slings, choke tubes
}

function TunaWRAccept.Drawer(container, item)
    local ok, allowed = pcall(function()
        local cat = TunaWRItem.classify(item)
        if cat == 'LONG_GUN' or cat == 'HANDGUN' then return true end
        if cat then return false end                      -- MELEE
        if instanceof(item, 'HandWeapon') then return false end

        cat = item.getDisplayCategory and item:getDisplayCategory() or nil
        if cat == 'Ammo' or cat == 'WeaponPart' then return true end

        if cat and TunaWRAccept.COMPAT_DRAWER_CATEGORIES[cat] then return true end

        if item.IsInventoryContainer and item:IsInventoryContainer() then return true end

        return false
    end)
    if not ok then return true end
    return allowed
end

-- acceptItemFunction is a runtime field, never saved: every process must install its own
function TunaWRItem.installPredicates(obj)
    pcall(function()
        local bay = TunaWRItem.containerOfType(obj, TunaWRItem.BAY_TYPE)
        if not bay then bay = obj:getContainer() end
        if bay and bay:getAcceptItemFunction() ~= 'TunaWRAccept.Bay' then
            bay:setAcceptItemFunction('TunaWRAccept.Bay')
        end
    end)
    pcall(function()
        local drw = TunaWRItem.containerOfType(obj, TunaWRItem.DRAWER_TYPE)
        if drw and drw:getAcceptItemFunction() ~= 'TunaWRAccept.Drawer' then
            drw:setAcceptItemFunction('TunaWRAccept.Drawer')
        end
    end)
end

function TunaWRItem.prepareRack(obj)
    local info = TunaWRSlots.infoOf(TunaWRItem.pieceOf(obj))
    local c, created, err = nil, false, nil
    if info and info.hasAmmoDrawer then
        c, created, err = TunaWRItem.ensureDrawer(obj)
    else
        err = 'noDrawerForPiece'
    end
    TunaWRItem.installPredicates(obj)
    return c, created, err
end

-- counts ITEMS PRESENT against STATIONS AUTHORED - free bindings is the wrong question
function TunaWRAccept.Bay(container, item)
    local ok, allowed = pcall(function()
        local cat = TunaWRItem.classify(item)
        if not cat then return false end

        local obj = container:getParent()
        if not obj then return true end
        local piece = TunaWRItem.pieceOf(obj)
        local slots = piece and TunaWRSlots.PIECES[piece] or nil
        if not slots then return true end

        return TunaWRSlots.hasRoomFor(slots, TunaWRItem.itemsOf(container), cat)
    end)
    if not ok then return true end
    return allowed
end
