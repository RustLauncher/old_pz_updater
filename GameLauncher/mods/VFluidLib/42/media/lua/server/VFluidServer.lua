-- Server commands: designation writes, cleaning, and on-use draws. Every write is
-- proximity-guarded - clients request, the server decides.

require "Vehicles/Vehicles"

VFluid = VFluid or {}

local function nearVehicle(playerObj, vehicle)
	if not playerObj or not vehicle then return false end
	if playerObj:getVehicle() == vehicle then return true end
	return playerObj:DistTo(vehicle:getX(), vehicle:getY()) < 15
end

local function vehicleOfMove(args)
	local ids = { args.dstVehicle, args.srcVehicle }
	for i = 1, #ids do
		local v = ids[i] and getVehicleById(ids[i])
		if v then return v end
	end
	return nil
end

local Commands = {}

function Commands.move(playerObj, args)
	local src = { kind = args.srcKind, vehicle = args.srcVehicle, part = args.srcPart,
		x = args.srcX, y = args.srcY, z = args.srcZ, item = args.srcItem }
	local dst = { kind = args.dstKind, vehicle = args.dstVehicle, part = args.dstPart,
		x = args.dstX, y = args.dstY, z = args.dstZ, item = args.dstItem }
	local shares = VFluid.decodeShares(args.shares)
	local moved = VFluid.applyMove(playerObj, src, dst, tonumber(args.amount) or 0,
		args.fluid, shares)
	if moved > 0 and VFluid.debugSupply then
		print("[VFluidServer] moved " .. tostring(moved) .. " of asked " .. tostring(args.amount)
			.. " " .. tostring(args.fluid) .. "  " .. tostring(args.srcKind)
			.. " -> " .. tostring(args.dstKind))
	end
end

function Commands.setmode(playerObj, args)
	local v = getVehicleById(args.vehicle)
	local part = v and v:getPartById(args.part)
	if not part then return end
	local axis = VFluid.axisFor(v, part)
	if not axis then return end
	if args.lock ~= nil then
		VFluid.setDesignationLock(v, part, axis, args.lock == true)
		return
	end
	if args.axis then
		if VFluid.setService then VFluid.setService(v, part, args.axis) end
		return
	end
	VFluid.setDesignation(v, part, axis, args.mode, args.fluid)
end

function Commands.clean(playerObj, args)
	local v = getVehicleById(args.vehicle)
	local part = v and v:getPartById(args.part)
	if not part then return end
	local axis = VFluid.axisFor(v, part)
	if not axis then return end
	VFluid.performClean(playerObj, v, part, axis)
end

function Commands.use(playerObj, args)
	local v = getVehicleById(args.vehicle)
	local c = v and VFluid.consumerSpecs and VFluid.consumerSpecs[args.id]
	if not c then return end
	VFluid.applyUse(v, c)
end

local function onClientCommand(module, command, playerObj, args)
	if module ~= "vfluid" or not Commands[command] then return end
	args = args or {}
	local vehicle = vehicleOfMove(args) or (args.vehicle and getVehicleById(args.vehicle))
	if not nearVehicle(playerObj, vehicle) then return end
	Commands[command](playerObj, args)
end

Events.OnClientCommand.Add(onClientCommand)
