local D = require "DDV01_Shared"

local function reply(player, message)
    D.log(message)
    if isServer() then
        sendServerCommand(player, D.MODULE, "Result", { message = message })
    elseif D.notify then D.notify(player, message) end
end

local function whole(value)
    return type(value) == "number" and value == value and value == math.floor(value)
        and math.abs(value) < 10000000
end

local function empty(data)
    for _ in pairs(data) do return false end
    return true
end

local function findSquare(player, args)
    if not whole(args.x) or not whole(args.y) or not whole(args.z) then return nil end
    local square = getCell():getGridSquare(args.x, args.y, args.z)
    if not D.near(player, square, 4) then return nil end
    return square
end

local function findDoor(square, args)
    local objects = square:getObjects()
    if not whole(args.index) or args.index < 0 or args.index >= objects:size() then return nil end
    local door = objects:get(args.index)
    if not D.isSupported(door) or door:isDestroyed() then return nil end
    -- A click queued against an old/replaced object must not blindly use its index.
    if args.north ~= door:getNorth() or args.keyId ~= door:getKeyId() then return nil end
    return door
end

local function freeForTest(square)
    return square and square:getFloor() and square:isFree(false)
        and square:getSpecialObjects():size() == 0
        and not square:has(IsoFlagType.collideN) and not square:has(IsoFlagType.collideW)
end

local function createTestDoor(square, north, family, part)
    local source = family.tileset .. "_" .. tostring(family.base + (family.garage and ((north and 3 or 0)+(part or 0)) or (north and 1 or 0)))
    local door = IsoDoor.new(getCell(), square, source, north)
    door:setLocked(false)
    door:setLockedByKey(false, false)
    door:getModData()[D.DATA_KEY] = { createdForTest = true }
    square:AddSpecialObject(door)
    square:RecalcAllWithNeighbours(true)
    door:transmitCompleteItemToClients()
end

function D.handleCommand(player, command, args)
    if not D.canTest(player) then return end
    if type(args) ~= "table" then return end
    local square = findSquare(player, args)
    if not square then return reply(player, "Place-toi a moins de 4 cases de la cible.") end

    if command == "CreateBatch" then
        if type(args.north) ~= "boolean" or type(args.batch) ~= "string" then return end
        local batch = D.BATCH_BY_ID[args.batch]
        if not batch then return end
        local pending = {}
        local regular, garages = 0, 0
        for i, id in ipairs(batch.families) do
            local family=D.FAMILY_BY_ID[id]
            local x,y
            if family.garage then
                x=args.x+(garages%4)*4-8
                y=args.y+8+math.floor(garages/4)*4
                garages=garages+1
            else
                x=args.x+(regular%9)*2-8
                y=args.y+math.floor(regular/9)*2-10
                regular=regular+1
            end
            for part=0,(family.garage and 2 or 0) do
                local target=getCell():getGridSquare(x+(args.north and part or 0),y-(args.north and 0 or part),args.z)
                if not D.near(player,target,18) or not freeForTest(target) then
                    return reply(player, "Lot non cree : une case est occupee ou non chargee. Choisis une grande zone libre (19 x 23 cases).")
                end
                pending[#pending+1]={square=target,family=family,part=part}
            end
        end
        for _, item in ipairs(pending) do createTestDoor(item.square,args.north,item.family,item.part) end
        return reply(player, tostring(#batch.families) .. " modeles crees (" .. #pending .. " objets/sections). Apparence du lot pour comparer les niveaux.")
    elseif command == "ForceBatch" then
        if not whole(args.stage) or args.stage < -1 or args.stage > 3 then return end
        local count = 0
        for dx = -18, 18 do
            for dy = -18, 18 do
                local target = getCell():getGridSquare(args.x + dx, args.y + dy, args.z)
                if D.near(player, target, 18) then
                    local objects = target:getSpecialObjects()
                    for index = 0, objects:size() - 1 do
                        local door = objects:get(index)
                        if D.isSupported(door) and not door:isDestroyed() then
                            local data = door:getModData()[D.DATA_KEY]
                            if type(data) == "table" and data.createdForTest == true then
                                local before = D.snapshot(door)
                                data.force = args.stage == -1 and nil or args.stage
                                if args.stage == -1 then data.force = nil end
                                door:transmitModData()
                                local same, changed = D.sameState(before, D.snapshot(door))
                                if not same then D.log("ALERTE lot : invariant " .. tostring(changed)) end
                                count = count + 1
                            end
                        end
                    end
                end
            end
        end
        return reply(player, tostring(count) .. " portes de test mises a jour ; HP inchanges.")
    end

    if command == "Create" then
        if type(args.north) ~= "boolean" then return end
        local family = D.FAMILY_BY_ID[args.family or "white"]
        if not family then return end
        if family.garage then
            local pending={}
            for part=0,2 do
                local target=getCell():getGridSquare(args.x+(args.north and part or 0),args.y-(args.north and 0 or part),args.z)
                if not freeForTest(target) then return reply(player,"Garage non cree : il faut trois cases libres.") end
                pending[#pending+1]=target
            end
            for i,target in ipairs(pending) do createTestDoor(target,args.north,family,i-1) end
            return reply(player,"Garage complet cree : "..family.label)
        end
        if not freeForTest(square) then return reply(player, "Choisis un sol libre sans mur ni objet special.") end
        createTestDoor(square,args.north,family)
        return reply(player, "Porte de test creee : " .. family.label)
    end

    local door = findDoor(square, args)
    if not door then return reply(player, "Porte absente, remplacee ou non compatible : reclique dessus.") end

    if command == "Force" then
        if not whole(args.stage) or args.stage < -1 or args.stage > 3 then return end
        local before = D.snapshot(door)
        local data = door:getModData()[D.DATA_KEY]
        if type(data) ~= "table" then data = {}; door:getModData()[D.DATA_KEY] = data end
        if args.stage == -1 then data.force = nil else data.force = args.stage end
        if empty(data) then door:getModData()[D.DATA_KEY] = nil end
        door:transmitModData()
        local same, changed = D.sameState(before, D.snapshot(door))
        if not same then D.log("ALERTE invariants commande visuelle : " .. tostring(changed)) end
        reply(player, args.stage == -1 and "Suivi automatique des HP actif."
            or "Apparence " .. tostring(args.stage) .. " imposee ; HP et verrous inchanges.")
    elseif command == "Health" then
        local allowed = { [100] = true, [65] = true, [40] = true, [15] = true }
        if not allowed[args.percent] then return end
        local data = door:getModData()[D.DATA_KEY]
        if type(data) == "table" then
            data.force = nil
            if empty(data) then door:getModData()[D.DATA_KEY] = nil end
            door:transmitModData()
        end
        local maximum = door:getMaxHealth()
        if maximum <= 0 then return end
        local health = math.max(1, math.floor(maximum * args.percent / 100))
        door:setHealth(health)
        -- setHealth alone does not replicate health in 42.20.4.
        if isServer() then door:sync() end
        reply(player, "HP reels de test : " .. tostring(health) .. "/" .. tostring(maximum)
            .. ". Suivi automatique reactive.")
    end
end

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= D.MODULE then return end
    local ok, err = pcall(D.handleCommand, player, command, args)
    if not ok then D.log("Commande refusee/erreur : " .. tostring(err)) end
end)
