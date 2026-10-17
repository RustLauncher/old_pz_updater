-- Item-only debug commands, separate from the Fix13 costume command channel.
require "HalloweenEvent/EVHalloween_Items"
require "HalloweenEvent/EVHalloween_ItemFunctions"
local Items = HalloweenEvent.Items
local Debug = {}
Items.DebugServer = Debug

local function log(message)
    HalloweenEvent.log("ITEMS " .. tostring(message))
end

local function authoritative()
    return not (type(isClient) == "function" and isClient())
        or (type(isServer) == "function" and isServer())
end

local function permitted(player)
    if not player then return false end
    if not (type(isServer) == "function" and isServer()) then return authoritative() end
    local level = tostring(player:getAccessLevel() or ""):lower()
    return level == "admin" or level == "moderator" or level == "overseer"
end

local function give(player, fullType, variant)
    fullType=Items.typeAliases[fullType] or fullType
    if not Items.byType[fullType] then return false end
    if variant~=nil and (fullType~=Items.Functions.doormatType or (variant~=0 and variant~=1)) then return false end
    local inventory = player:getInventory()
    local ok, item = pcall(function() return inventory:AddItem(fullType) end)
    if not ok or not item then
        log("SPAWN_FAILED type=" .. fullType .. " reason=" .. tostring(item))
        return false
    end
    if variant~=nil then Items.Functions.setDoormatVariant(item,variant) end
    if type(isServer) == "function" and isServer() then
        sendAddItemToContainer(inventory, item)
    end
    log("SPAWN_OK type=" .. fullType .. " name=" .. tostring(item:getDisplayName())
        .. " worldModel=" .. tostring(item:getWorldStaticItem())
        .. " staticModel=" .. tostring(item:getStaticModel())
        .. " role=" .. Items.byType[fullType].role
        .. " expectedModelScale=" .. tostring(Items.byType[fullType].modelScale))
    return true
end

-- Validate the entire footprint before creating anything: a blocked grid leaves
-- no partial gallery or duplicates when the administrator retries elsewhere.
function Debug.groundGallery(player, referenceOnly, doormatsOnly)
    if not authoritative() or not permitted(player) then return false end
    local cell = getCell()
    if not cell then return false end
    local px, py, pz = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
    local placements = {}
    local attempts,layout=0,"grid"
    local count = doormatsOnly and 2 or (referenceOnly and 4 or #Items.catalog)
    local origins={{x=px-4,y=py+3}}
    for radius=2,12,2 do
        for dx=-radius,radius,2 do for dy=-radius,radius,2 do
            if math.abs(dx)==radius or math.abs(dy)==radius then origins[#origins+1]={x=px-4+dx,y=py+3+dy} end
        end end
    end
    for _,origin in ipairs(origins) do
        attempts=attempts+1
        local candidate={};local valid=true
        for i=1,count do
            local x=origin.x+((i-1)%5)*2;local y=origin.y+math.floor((i-1)/5)*2
            local square=cell:getGridSquare(x,y,pz)
            if not square or not square:isFree(false) or not square:TreatAsSolidFloor()
                or (IsoFlagType and square:getProperties():has(IsoFlagType.water)) then valid=false;break end
            candidate[i]={square=square,x=x,y=y,z=pz}
        end
        if valid then placements=candidate;break end
    end
    if #placements~=count then
        -- A partially obstructed area can still supply 25 points on the same
        -- two-tile lattice; never place a partial batch on a failed search.
        local candidate={}
        for row=0,6 do for col=0,6 do
            if #candidate<count then
                local x=px-6+col*2;local y=py+3+row*2
                local sq=cell:getGridSquare(x,y,pz)
                if sq and sq:isFree(false) and sq:TreatAsSolidFloor()
                    and not (IsoFlagType and sq:getProperties():has(IsoFlagType.water)) then
                    candidate[#candidate+1]={square=sq,x=x,y=y,z=pz}
                end
            end
        end end
        if #candidate==count then placements=candidate;layout="sparse" end
    end
    if #placements~=count then
        log("GROUND_ABORT reason=no_clear_loaded_layout searchRadius=12 requested="..count)
        local text=HalloweenEvent.text("GroundBlocked")
        if isServer() then sendServerCommand(player,"EVHalloweenItems","DebugFeedback",{key="GroundBlocked"}) else player:Say(text) end
        return false
    end
    log("GROUND_LAYOUT x="..placements[1].x.." y="..placements[1].y.." count="..count.." attempts="..attempts.." layout="..layout)
    local successful = 0
    for i, position in ipairs(placements) do
        local ft = doormatsOnly and Items.Functions.doormatType or referenceOnly and (i == 1 and "Base.HalloweenCandyBucket" or Items.catalog[i-1].fullType)
            or Items.catalog[i].fullType
        local ok, item = pcall(function()
            -- Return value is InventoryItem, not IsoWorldInventoryObject.
            -- transmit=true uses the native synchronized spawn path once.
            local created = instanceItem(ft)
            if not created then return nil end
            HalloweenEvent.Items.Functions.init(created)
            created:setWorldZRotation(0)
            if doormatsOnly then Items.Functions.setDoormatVariant(created,i-1) end
            local result = position.square:AddWorldInventoryItem(created,0.5,0.5,0,true)
            if Items.Runtime then Items.Runtime.register(created) end
            return result
        end)
        if ok and item then
            successful = successful + 1
            log("GROUND_OK index=" .. i .. " type=" .. ft .. " x=" .. position.x
                .. " y=" .. position.y .. " z=" .. position.z)
        else log("GROUND_FAILED index=" .. i .. " type=" .. ft .. " reason=" .. tostring(item)) end
    end
    log("GROUND_RESULT placed=" .. successful .. "/" .. count .. " spacing=2 version=" .. Items.VERSION)
    return successful == count
end

function Debug.handle(player, command, args)
    if not authoritative() or not permitted(player) then return false end
    if command == "GiveOne" then
        return give(player, args and args.fullType, args and args.variant)
    elseif command == "GiveAll" then
        local count = 0
        for _, entry in ipairs(Items.catalog) do
            if give(player, entry.fullType) then count = count + 1 end
        end
        log("SPAWN_ALL result=" .. count .. "/" .. #Items.catalog)
        return count == #Items.catalog
    elseif command == "Audit" then
        return Items.audit()
    elseif command == "GiveAllGround" then
        return Debug.groundGallery(player, false)
    elseif command == "DoormatGround" then
        return Debug.groundGallery(player,false,true)
    elseif command == "BucketComparison" then
        return Debug.groundGallery(player, true)
    end
    return false
end

local function onCommand(module, command, player, args)
    if module == "EVHalloweenItems" then Debug.handle(player, command, args) end
end

if Events and Events.OnClientCommand then Events.OnClientCommand.Add(onCommand) end
log("DEBUG_SERVER_READY version=" .. Items.VERSION .. " count=" .. #Items.catalog)
return Debug
