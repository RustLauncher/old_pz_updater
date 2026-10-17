require "HalloweenEvent/EVHalloween_ItemFunctions"
local Items, F = HalloweenEvent.Items, HalloweenEvent.Items.Functions
local R = {world={},minutes=0}
Items.Runtime = R
local function authority() return not isClient() or isServer() end
local function now() return getGameTime():getWorldAgeHours() end

function R.register(item)
    if not item then return end
    if F.bucketTypes[item:getFullType()] or item:getFullType()==Items.coffinType then F.visual(item) end
    if F.lights[item:getFullType()] then
        F.state(item)
        if item:getWorldItem() then R.world[item:getID()] = item end
    end
end

function R.publish(item, player)
    if not isServer() then return end
    local world = item:getWorldItem()
    local square = world and world:getSquare()
    -- SyncItemModDataPacket addresses an inventory container. A floor item
    -- has none; B42 throws during packet parsing before applying its state.
    -- Floor item modData is persisted with the native saved item. LightState
    -- carries the complete light state to clients. Do not retransmit a world
    -- object's creation packet on each update: it can add duplicate objects.
    if not world and player and item:getContainer() and type(syncItemModData) == "function" then
        sendItemStats(item)
        syncItemModData(player,item)
    end
    local state = F.state(item)
    sendServerCommand("EVHalloweenItems", "LightState", {
        id=item:getID(),fullType=item:getFullType(),active=item:isActivated(),
        charge=F.charge(item),bulbLife=state.bulbLife,bulbType=state.bulbType,
        lastHours=state.lastHours or now(),
        x=square and square:getX() or nil,y=square and square:getY() or nil,
        z=square and square:getZ() or nil,
        owner=player and player:getOnlineID() or nil,
    })
end

local function visitInventory(container, callback, depth)
    if not container or (depth or 0)>12 then return end
    local list=container:getItems()
    for i=0,list:size()-1 do
        local item=list:get(i)
        if F.lights[item:getFullType()] or F.bucketTypes[item:getFullType()]
            or item:getFullType()==Items.coffinType then callback(item) end
        if item:IsInventoryContainer() then visitInventory(item:getInventory(),callback,(depth or 0)+1) end
    end
end

function R.scanSquare(square)
    if not authority() or not square then return end
    local list=square:getWorldObjects()
    for i=0,list:size()-1 do R.register(list:get(i):getItem()) end
end

-- Discover native drops as well as debug spawns. Only loaded squares around
-- players are scanned once per ten game minutes; no global world/zombie polling.
function R.minute()
    if not authority() then return end
    R.minutes=R.minutes+1
    local clock=now()
    local players=isServer() and getOnlinePlayers() or nil
    local count=players and players:size() or getNumActivePlayers()
    for i=0,count-1 do
        local player=players and players:get(i) or getSpecificPlayer(i)
        if player then
            visitInventory(player:getInventory(),function(item)
                if F.bucketTypes[item:getFullType()] or item:getFullType()==Items.coffinType then F.visual(item)
                else F.stepFuel(item,clock);R.publish(item,player) end
            end)
            local x,y,z=math.floor(player:getX()),math.floor(player:getY()),math.floor(player:getZ())
            if R.minutes%10==1 then for dx=-16,16 do for dy=-16,16 do
                R.scanSquare(getCell():getGridSquare(x+dx,y+dy,z))
            end end end
        end
    end
    for id,item in pairs(R.world) do
        local world=item:getWorldItem()
        local square=world and world:getSquare()
        if not square or getCell():getGridSquare(square:getX(),square:getY(),square:getZ()) ~= square then
            R.world[id]=nil
        else F.stepFuel(item,clock);R.publish(item) end
    end
end

local function accessible(player,args)
    if type(args)~="table" or type(args.id)~="number" then return nil end
    local item=F.find(player:getInventory(),args.id)
    if item then return item end
    if type(args.x)~="number" or type(args.y)~="number" or type(args.z)~="number" then return nil end
    if math.floor(player:getZ())~=args.z or math.abs(player:getX()-args.x)>3.5
        or math.abs(player:getY()-args.y)>3.5 then return nil end
    return F.worldItem(getCell():getGridSquare(args.x,args.y,args.z),args.id)
end

function R.handle(player,command,args)
    if not authority() or not player or command~="ToggleLight" then return false end
    local item=accessible(player,args)
    if not item or not F.lights[item:getFullType()] then return false end
    F.stepFuel(item,now())
    local on=args.on==true
    if on and not F.canLight(item) then return false end
    item:setActivated(on)
    F.state(item).lastHours=now()
    F.visual(item)
    R.register(item);R.publish(item,player)
    HalloweenEvent.log("ITEMS LIGHT_TOGGLE type="..item:getFullType().." on="..tostring(on)
        .." charge="..tostring(F.charge(item)).." bulb="..tostring(F.state(item).bulbLife))
    return true
end

if Events.LoadGridsquare then Events.LoadGridsquare.Add(R.scanSquare) end
if Events.EveryOneMinute then Events.EveryOneMinute.Add(function()
    local ok,err=pcall(R.minute)
    if not ok and not R.warned then R.warned=true;HalloweenEvent.log("ITEMS RUNTIME_UNAVAILABLE reason="..tostring(err)) end
end) end
if Events.OnClientCommand then Events.OnClientCommand.Add(function(module,command,player,args)
    if module=="EVHalloweenItems" then R.handle(player,command,args) end
end) end
return R
