-- Street hydrants as a fluid supply, with ONE reserve per hydrant: mods that track hydrant
-- water in their own keys are reconciled onto a single deterministic number, written back
-- everywhere so nothing disagrees.
-- Loads before VFluidShared.lua by filename and must stay free of require. DO NOT RENAME.

VFluid = VFluid or {}

VFluid.HYDRANT_SPRITE   = "street_decoration_01_12"
VFluid.HYDRANT_MIN      = 100
VFluid.HYDRANT_MAX      = 10000
VFluid.HYDRANT_KEYS = {
	"amGeneralTankerHydrantRemainingWater",
	"w900HydrantRemainingWater",
}

function VFluid.isHydrant(obj)
	if not obj or not obj.getSprite then return false end
	local ok, sprite = pcall(function() return obj:getSprite() end)
	if not ok or not sprite or not sprite.getName then return false end
	local okn, name = pcall(function() return sprite:getName() end)
	return okn and name == VFluid.HYDRANT_SPRITE
end

function VFluid.hydrantSeed(square)
	if not square then return 0 end
	local range = VFluid.HYDRANT_MAX - VFluid.HYDRANT_MIN + 1
	local seed = math.abs(square:getX() * 73856093 + square:getY() * 19349663 + square:getZ() * 83492791)
	return VFluid.HYDRANT_MIN + (seed % range)
end

local function modOf(obj)
	local square = obj and obj.getSquare and obj:getSquare() or nil
	if not square or not square.getModData then return nil end
	local ok, md = pcall(function() return square:getModData() end)
	return ok and md or nil
end

function VFluid.hydrantReserve(obj)
	local md = modOf(obj)
	if not md then return 0 end
	local lowest = nil
	for i = 1, #VFluid.HYDRANT_KEYS do
		local v = tonumber(md[VFluid.HYDRANT_KEYS[i]])
		if v then
			v = math.max(0, v)
			if lowest == nil or v < lowest then lowest = v end
		end
	end
	if lowest ~= nil then return lowest end
	return VFluid.hydrantSeed(obj.getSquare and obj:getSquare() or nil)
end

function VFluid.setHydrantReserve(obj, amount)
	if isClient and isClient() then return false end
	local md = modOf(obj)
	if not md then return false end
	local n = math.max(0, amount or 0)
	for i = 1, #VFluid.HYDRANT_KEYS do md[VFluid.HYDRANT_KEYS[i]] = n end
	local square = obj.getSquare and obj:getSquare() or nil
	if square and square.transmitModdata then pcall(function() square:transmitModdata() end) end
	return true
end

function VFluid.reconcileHydrant(obj)
	local before = VFluid.hydrantReserve(obj)
	VFluid.setHydrantReserve(obj, before)
	return before
end

local function mainsWaterOn()
	local so = getSandboxOptions and getSandboxOptions()
	local gt = getGameTime and getGameTime()
	if not so or not gt then return false end
	local shut
	if SandboxVars and SandboxVars.WaterShutModifier ~= nil then
		shut = tonumber(SandboxVars.WaterShutModifier)
	else
		local opt = so.getOptionByName and so:getOptionByName("WaterShutModifier")
		shut = opt and opt.getValue and tonumber(opt:getValue()) or nil
	end
	if shut == nil or shut < 0 then return false end
	local days = gt:getWorldAgeHours() / 24
	local offset = (so:getTimeSinceApo() - 1) * 30
	return (days + offset) < shut
end
VFluid.mainsWaterOn = mainsWaterOn

function VFluid.hasHose(playerObj)
	if not playerObj or not playerObj.getInventory then return false end
	local inv = playerObj:getInventory()
	if not inv then return false end
	local ok, found = pcall(function()
		return inv:containsTypeRecurse("RubberHose")
	end)
	return ok and found == true
end

function VFluid.hydrantHasPower(obj)
	local square = obj and obj.getSquare and obj:getSquare() or nil
	if not square then return false end
	local ok, live = pcall(function() return square:haveElectricity() end)
	if ok and live then return true end
	if not getCell then return false end
	for dy = -1, 1 do
		for dx = -1, 1 do
			local sq = getCell():getGridSquare(square:getX() + dx, square:getY() + dy, square:getZ())
			local objs = sq and sq:getObjects()
			for i = 0, (objs and objs:size() or 0) - 1 do
				local o = objs:get(i)
				if instanceof(o, "IsoGenerator") and o:isActivated() then return true end
			end
		end
	end
	return false
end

function VFluid.hydrantEndpoint(obj, axis, playerObj)
	if not VFluid.isHydrant(obj) then return nil end
	if not axis or not VFluid.axisTakesWater or not VFluid.axisTakesWater(axis) then return nil end
	if not playerObj then return nil end
	if not VFluid.hasHose(playerObj) then return nil end
	if not VFluid.hydrantHasPower(obj) then return nil end
	local endless = mainsWaterOn()
	return {
		kind = "pump", supplyKind = "hydrant", label = "Fire Hydrant",
		supplyRank = 20,
		axis = axis, holder = obj, sourceOnly = true, endless = endless,
		powered = true,
		get  = function() return endless and math.huge or VFluid.hydrantReserve(obj) end,
		cap  = function() return endless and math.huge or VFluid.HYDRANT_MAX end,
		free = function() return 0 end,
		canAccept = function() return false, "a hydrant is a supply, not a container" end,
		set  = function(n)
			if endless then return math.huge end
			VFluid.setHydrantReserve(obj, n)
			return VFluid.hydrantReserve(obj)
		end,
		sync = function() end,
	}
end
