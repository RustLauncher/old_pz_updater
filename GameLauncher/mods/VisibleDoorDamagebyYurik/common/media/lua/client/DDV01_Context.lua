local D = require "DDV01_Shared"
local V = require "DDV01_Visual"

function D.notify(player, message)
    if player then player:setHaloNote(message, 210, 235, 210, 300) end
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= D.MODULE or command ~= "Result" or type(args) ~= "table" then return end
    D.notify(getSpecificPlayer(0), tostring(args.message))
    D.log(args.message)
end)

local function request(player, command, args)
    if isClient() then
        sendClientCommand(player, D.MODULE, command, args)
    elseif D.handleCommand then
        D.handleCommand(player, command, args)
        V.scan()
    else D.notify(player, "Command module not loaded. See console.txt.") end
end

local function doorArgs(door)
    local square = door:getSquare()
    if not square or door:getObjectIndex() < 0 then return nil end
    return { x = square:getX(), y = square:getY(), z = square:getZ(),
        index = door:getObjectIndex(), north = door:getNorth(), keyId = door:getKeyId() }
end

local function forceStage(door, player, stage)
    local args = doorArgs(door)
    if not args then return end
    args.stage = stage
    request(player, "Force", args)
end

local function setHealth(door, player, percent)
    local args = doorArgs(door)
    if not args then return end
    args.percent = percent
    request(player, "Health", args)
end

local function createDoor(square, player, north, family)
    request(player, "Create", { x = square:getX(), y = square:getY(), z = square:getZ(), north = north, family = family })
end

local function addDoorMenu(context, root, door, player)
    local square = door:getSquare()
    local title = string.format("Door %s (%d, %d) - HP %d/%d",
        door:getNorth() and "N" or "W", square:getX(), square:getY(), door:getHealth(), door:getMaxHealth())
    local option = root:addOption(title)
    local menu = ISContextMenu:getNew(context)
    root:addSubMenu(option, menu)
    menu:addOption("Automatic based on HP", door, forceStage, player, -1)
    menu:addOption("Stage 0 - Original (HP unchanged)", door, forceStage, player, 0)
    menu:addOption("Stage 1 - Light damage (HP unchanged)", door, forceStage, player, 1)
    menu:addOption("Stage 2 - Medium damage (HP unchanged)", door, forceStage, player, 2)
    menu:addOption("Stage 3 - Heavy damage (HP unchanged)", door, forceStage, player, 3)
    local hpOption = menu:addOption("TEST - Change actual HP")
    local hpMenu = ISContextMenu:getNew(context)
    menu:addSubMenu(hpOption, hpMenu)
    hpMenu:addOption("100 % - Repair for testing", door, setHealth, player, 100)
    hpMenu:addOption("65 % - Stage 1", door, setHealth, player, 65)
    hpMenu:addOption("40 % - Stage 2", door, setHealth, player, 40)
    hpMenu:addOption("15 % - Stage 3", door, setHealth, player, 15)
    menu:addOption("Write diagnostics to console.txt", door, function(target)
        V.diagnostic(target)
        D.notify(player, "Diagnostics written to console.txt: search for [DDV01].")
    end)
end

Events.OnFillWorldObjectContextMenu.Add(function(playerIndex, context, worldobjects, test)
    if test then return end
    if not (SandboxVars and SandboxVars.VisibleDoorDamage
        and SandboxVars.VisibleDoorDamage.EnableTestMenu == true) then return end
    local player = getSpecificPlayer(playerIndex)
    if not D.canTest(player) then return end
    local square
    local doors, seen = {}, {}
    local function collect(candidate)
        if D.isSupported(candidate) and not seen[candidate] and D.near(player, candidate:getSquare(), 4) then
            seen[candidate] = true
            doors[#doors + 1] = candidate
        end
    end
    for _, object in ipairs(worldobjects) do
        if object and object:getSquare() then
            square = square or object:getSquare()
            collect(object)
            local specials = object:getSquare():getSpecialObjects()
            for i = 0, specials:size() - 1 do collect(specials:get(i)) end
        end
    end
    if not square or not D.near(player, square, 4) then return end
    local option = context:addOption("Damaged doors - Test 0.5.5-HD")
    local root = ISContextMenu:getNew(context)
    context:addSubMenu(option, root)
    for _, door in ipairs(doors) do addDoorMenu(context, root, door, player) end
    root:addOption("Spawn ALL - 61 models (west-facing)",square,function(target)
        request(player,"CreateBatch",{x=target:getX(),y=target:getY(),z=target:getZ(),north=false,batch="all"})
    end)
    root:addOption(V.garageSurface and "Garages [ON]: restore previous rendering" or "Garages [OFF]: enable main sprite",
        nil,function() V.setGarageSurface(not V.garageSurface) end)
    root:addOption("Nearby door diagnostics",nil,function()
        for _,door in ipairs(doors) do V.diagnostic(door) end
        D.notify(player,"Diagnostics written to console.txt: [DDV01].")
    end)
    root:addOption(D.whiteHD and "White door [HD]: compare with original quality" or "White door [ORIGINAL]: switch to HD",
        nil,function() V.setWhiteHD(not D.whiteHD) end)
    local hdCreate=root:addOption("Spawn a white door to compare HD / original")
    local hdMenu=ISContextMenu:getNew(context)
    root:addSubMenu(hdCreate,hdMenu)
    hdMenu:addOption("West-facing",square,createDoor,player,false,"white")
    hdMenu:addOption("North-facing",square,createDoor,player,true,"white")
    local individual = root:addOption("Choose a model to spawn (54 doors and 7 garages)")
    local individualMenu = ISContextMenu:getNew(context)
    root:addSubMenu(individual,individualMenu)
    for _, family in ipairs(D.FAMILIES) do
        local create = individualMenu:addOption(family.label)
        local createMenu = ISContextMenu:getNew(context)
        individualMenu:addSubMenu(create,createMenu)
        createMenu:addOption("West-facing",square,createDoor,player,false,family.id)
        createMenu:addOption("North-facing",square,createDoor,player,true,family.id)
    end
    local batch = root:addOption("Spawn a batch of doors")
    local batchMenu = ISContextMenu:getNew(context)
    root:addSubMenu(batch,batchMenu)
    local function createBatch(target,id,north)
        request(player,"CreateBatch",{x=target:getX(),y=target:getY(),z=target:getZ(),north=north,batch=id})
    end
    for _, item in ipairs(D.BATCHES) do
        local option = batchMenu:addOption(item.label)
        local choices = ISContextMenu:getNew(context)
        batchMenu:addSubMenu(option,choices)
        choices:addOption("West-facing",square,createBatch,item.id,false)
        choices:addOption("North-facing",square,createBatch,item.id,true)
    end
    local appearance = root:addOption("Nearby batch appearance (test doors only)")
    local appearanceMenu = ISContextMenu:getNew(context)
    root:addSubMenu(appearance, appearanceMenu)
    for stage = -1, 3 do
        appearanceMenu:addOption(stage == -1 and "Automatic based on HP" or "Stage " .. tostring(stage) .. " - HP unchanged",
            square, function(target, value)
                request(player, "ForceBatch", { x=target:getX(), y=target:getY(), z=target:getZ(), stage=value })
            end, stage)
    end
    root:addOption(V.enabled and "Disable damage visuals (local session)" or "Enable damage visuals (local session)",
        nil, function() V.setEnabled(not V.enabled) end)
    root:addOption("Check resource loading", nil, function()
        local ready = V.preflight()
        D.notify(player, ready and "900 textures available. Check models and overlays in game."
            or "Missing resources: see [DDV01] in console.txt.")
    end)
end)
