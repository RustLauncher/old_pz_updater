-- Cleaning policy: what restoring a tank takes - mop, gloves, water and bleach, amounts
-- scaling with capacity - and what applying it changes.

VFluid = VFluid or {}
VFluid.CAPS = VFluid.CAPS or {}
VFluid.CAPS.cleaning = 1

VFluid.NEED_NONE = "none"
VFluid.NEED_FULL = "full"

VFluid.FULL_WATER  = 2
VFluid.FULL_BLEACH = 2

VFluid.CLEAN_REACH = 6

VFluid.cleaningTools = { "Base.Mop" }
VFluid.cleaningGear  = { "Base.Gloves_Dish", "Base.Gloves_Surgical" }

local function addTo(list, fullType)
	if type(fullType) ~= "string" or fullType == "" then return false end
	for _, t in ipairs(list) do if t == fullType then return false end end
	list[#list + 1] = fullType
	return true
end

function VFluid.registerCleaningTool(fullType) return addTo(VFluid.cleaningTools, fullType) end
function VFluid.registerCleaningGear(fullType) return addTo(VFluid.cleaningGear, fullType) end

--------------------------------------------------------------------------------
-- WHAT does this tank need?
--------------------------------------------------------------------------------
function VFluid.cleaningNeed(vehicle, part, axis)
	if not VFluid.cleaningEnabled or not VFluid.cleaningEnabled() then return VFluid.NEED_NONE end
	local d = VFluid.designationOf and VFluid.designationOf(vehicle, part, axis)
	if not d then return VFluid.NEED_NONE end

	if d.mixed or d.unserviceable then return VFluid.NEED_FULL end

	if VFluid.tankCleaningLevel() ~= VFluid.CLEAN_ALL then return VFluid.NEED_NONE end
	if d.fluid and VFluid.rinsesClean and not VFluid.rinsesClean(d.fluid) then
		return VFluid.NEED_FULL
	end
	return VFluid.NEED_NONE
end

--------------------------------------------------------------------------------
-- CAN the player pay for it, right now?
--------------------------------------------------------------------------------
local function invItems(playerObj)
	local inv = playerObj and playerObj.getInventory and playerObj:getInventory()
	if not inv or not inv.getItems then return nil end
	return inv:getItems()
end

local function findAny(playerObj, types)
	local inv = playerObj and playerObj.getInventory and playerObj:getInventory()
	if not inv or not inv.getFirstTypeRecurse then return nil end
	for _, t in ipairs(types) do
		local it = inv:getFirstTypeRecurse(t)
		if it then return it, t end
	end
	return nil
end

local function carriedFluid(playerObj, wanted, need)
	local out, total = {}, 0
	local items = invItems(playerObj)
	if not items then return out, 0 end
	for i = 0, items:size() - 1 do
		local it = items:get(i)
		local name = VFluid.itemFluidName and VFluid.itemFluidName(it)
		if name and wanted(name) then
			local ep = VFluid.itemEndpoint and VFluid.itemEndpoint(it, nil)
			local have = ep and ep.get and ep.get() or 0
			if have > 0 then
				local take = math.min(have, need - total)
				out[#out + 1] = { item = it, amount = take, ep = ep }
				total = total + take
				if total >= need then break end
			end
		end
	end
	return out, total
end

local function isRinsing(name)
	return VFluid.rinsesClean and VFluid.rinsesClean(name) and name ~= nil
end
local function isBleach(name) return name == "Bleach" end

local function litres(n)
	if n == math.floor(n) then return string.format("%d L", n) end
	return string.format("%.1f L", n)
end

local function displayName(fullType)
	local sd = getScriptManager and getScriptManager():FindItem(fullType)
	local n = sd and sd.getDisplayName and sd:getDisplayName()
	if n and n ~= "" then return n end
	return (string.gsub(fullType, "^.*%.", ""))
end

function VFluid.cleaningPlan(playerObj, vehicle, part, axis)
	local p = { need = VFluid.cleaningNeed(vehicle, part, axis), ok = false,
		water = 0, bleach = 0, waterItems = {}, bleachItems = {} }

	if p.need == VFluid.NEED_NONE then
		p.why = "this tank does not need cleaning"
		return p
	end

	local level = VFluid.amount and VFluid.amount(part) or 0
	if level > 0.01 then
		p.why = "drain the tank first - " .. litres(level) .. " still inside"
		return p
	end

	p.water, p.bleach = VFluid.FULL_WATER, VFluid.FULL_BLEACH
	p.tool = findAny(playerObj, VFluid.cleaningTools)
	if not p.tool then
		p.why = "you need a " .. displayName(VFluid.cleaningTools[1] or "Base.Mop")
		return p
	end
	p.gear = findAny(playerObj, VFluid.cleaningGear)
	if not p.gear then
		p.why = "you need " .. displayName(VFluid.cleaningGear[1] or "Base.Gloves_Dish")
		return p
	end

	local ep = VFluid.bestSupplyNear
		and VFluid.bestSupplyNear(playerObj, VFluid.axes and VFluid.axes.potable, VFluid.CLEAN_REACH)
	if ep and ep.get and ep.get() >= p.water then
		p.waterEp = ep
		p.waterFrom = ep.label or "a water supply"
	else
		local got, total = carriedFluid(playerObj, isRinsing, p.water)
		if total + 0.01 < p.water then
			p.why = "you need " .. litres(p.water) .. " of water - a supply in reach, or carried"
			return p
		end
		p.waterItems = got
		p.waterFrom = "carried water"
	end

	if p.bleach > 0 then
		local got, total = carriedFluid(playerObj, isBleach, p.bleach)
		if total + 0.01 < p.bleach then
			p.why = "you need " .. litres(p.bleach) .. " of bleach"
			return p
		end
		p.bleachItems = got
	end

	p.ok = true
	return p
end

--------------------------------------------------------------------------------
-- RUN it: spend what it costs, then release the tank.
--------------------------------------------------------------------------------
function VFluid.performClean(playerObj, vehicle, part, axis)
	local plan = VFluid.cleaningPlan(playerObj, vehicle, part, axis)
	if not plan.ok then return false, plan.why end

	local function spend(ep, amount)
		if not ep or not ep.get or not ep.set or not amount or amount <= 0 then return 0 end
		local take = math.min(amount, ep.get())
		if take <= 0 then return 0 end
		ep.set(ep.get() - take)
		if ep.sync then ep.sync() end
		return take
	end
	local paidWater, paidBleach = 0, 0

	if plan.waterEp then
		paidWater = spend(plan.waterEp, plan.water)
	else
		for _, w in ipairs(plan.waterItems) do paidWater = paidWater + spend(w.ep, w.amount) end
	end
	for _, b in ipairs(plan.bleachItems) do paidBleach = paidBleach + spend(b.ep, b.amount) end

	return VFluid.applyClean(vehicle, part, axis), paidWater, paidBleach
end
