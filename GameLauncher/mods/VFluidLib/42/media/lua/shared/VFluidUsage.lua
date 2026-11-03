-- Usage: activity sources, registered consumers, the once-per-game-minute meter, and
-- on-use draws (a sink pays per use; brushes pay per hour).
-- Sorts after VFluidShared.lua and reaches the core through the VFluid table at run time,
-- never at load time. No require. DO NOT RENAME - the filename is load-bearing.

VFluid = VFluid or {}

local function log(msg) print("VFluidLib: " .. tostring(msg)) end

--------------------------------------------------------------------------------
-- ACTIVITY: anything that makes a tank's numbers move on their own.
VFluid.activitySources = VFluid.activitySources or {}
VFluid.activityOrder = VFluid.activityOrder or {}

function VFluid.registerActivity(id, fn)
	if type(id) ~= "string" or type(fn) ~= "function" then return false end
	if not VFluid.activitySources[id] then
		VFluid.activityOrder[#VFluid.activityOrder + 1] = id
	end
	VFluid.activitySources[id] = fn
	return true
end

function VFluid.isDrawing(vehicle)
	for i = 1, #VFluid.activityOrder do
		local fn = VFluid.activitySources[VFluid.activityOrder[i]]
		if fn then
			local ok, busy = pcall(fn, vehicle)
			if ok and busy then return true end
		end
	end
	return false
end

VFluid.consumerSpecs = VFluid.consumerSpecs or {}
VFluid.consumerOrder = VFluid.consumerOrder or {}

local function consumerCovers(c, name)
	local v = c.vehicle
	if v == nil or name == nil then return true end
	if type(v) == "table" then
		for i = 1, #v do if v[i] == name then return true end end
		return false
	end
	return v == name
end

function VFluid.registerConsumer(spec)
	if type(spec) ~= "table" then
		log("registerConsumer: takes a table, not (id, fn)"); return false
	end
	local id = spec.id
	if type(id) ~= "string" or id == "" then log("registerConsumer: needs an id"); return false end
	if type(spec.fluid) ~= "string" or spec.fluid == "" then
		log("registerConsumer: " .. id .. " needs a fluid"); return false
	end
	local function amountKind(v) return type(v) == "number" or type(v) == "function" end
	local hasRate, hasUse = amountKind(spec.rate), amountKind(spec.perUse)
	if hasRate == hasUse then
		log("registerConsumer: " .. id .. " needs exactly one of rate / perUse"); return false
	end
	if not VFluid.consumerSpecs[id] then
		VFluid.consumerOrder[#VFluid.consumerOrder + 1] = id
	end
	VFluid.consumerSpecs[id] = spec
	return true
end

function VFluid.unregisterConsumer(id)
	if not VFluid.consumerSpecs[id] then return false end
	VFluid.consumerSpecs[id] = nil
	for i = #VFluid.consumerOrder, 1, -1 do
		if VFluid.consumerOrder[i] == id then table.remove(VFluid.consumerOrder, i) end
	end
	return true
end

function VFluid.consumerAmount(c, key, vehicle)
	local v = c and c[key]
	if type(v) == "function" then
		local ok, n = pcall(v, vehicle)
		v = ok and n or nil
	end
	if type(v) ~= "number" or v ~= v or v < 0 then return 0 end
	return v
end

function VFluid.consumerSupply(vehicle, fluidName)
	local out = {}
	if not vehicle or type(fluidName) ~= "string" then return out end
	local f = Fluid and Fluid.Get and Fluid.Get(fluidName)
	local tanks = VFluid.tanksOn and VFluid.tanksOn(vehicle) or {}
	for i = 1, #tanks do
		local part = tanks[i].part or tanks[i]
		local axis = VFluid.axisFor and VFluid.axisFor(vehicle, part)
		if axis and axis.kind == "fluid" and (not f or VFluid.axisAdmits(axis, f)) then
			local led, n, held = VFluid.rawLedger(part) or {}, 0, 0
			for name, q in pairs(led) do
				if q and q > 0 then
					n = n + 1
					if name == fluidName then held = q end
				end
			end
			if n <= 1 then
				out[#out + 1] = { part = part, axis = axis,
					label = VFluid.partLabel(part.getId and part:getId() or nil), held = held }
			end
		end
	end
	return out
end

function VFluid.consumptionBlocks(vehicle)
	local byKey, useBlocks, rateBlocks = {}, {}, {}
	local function block(kind, fluid)
		local k = kind .. "\0" .. fluid
		local b = byKey[k]
		if not b then
			b = { kind = kind, fluid = fluid, rows = {}, totalRate = 0 }
			byKey[k] = b
			local list = (kind == "use") and useBlocks or rateBlocks
			list[#list + 1] = b
		end
		return b
	end

	for i = 1, #VFluid.consumerOrder do
		local c = VFluid.consumerSpecs[VFluid.consumerOrder[i]]
		if c and (not vehicle or not vehicle.getScript
				or consumerCovers(c, vehicle:getScript() and vehicle:getScript():getName())) then
			local label = c.label or VFluid.partLabel(c.part)
			if c.rate then
				local on = true
				if c.active then
					local ok, v = pcall(c.active, vehicle)
					on = ok and v and true or false
				end
				local r = on and VFluid.consumerAmount(c, "rate", vehicle) or 0
				local b = block("rate", c.fluid)
				b.rows[#b.rows + 1] = { label = label, value = r, unit = c.unit or "L/h" }
				b.totalRate = b.totalRate + r
			else
				local b = block("use", c.fluid)
				b.rows[#b.rows + 1] = { label = label,
					value = VFluid.consumerAmount(c, "perUse", vehicle), unit = c.unit or "L/use" }
			end
		end
	end

	local out = {}
	for i = 1, #useBlocks do out[#out + 1] = useBlocks[i] end
	for i = 1, #rateBlocks do out[#out + 1] = rateBlocks[i] end
	for i = 1, #out do
		local b = out[i]
		local sup, names, held = VFluid.consumerSupply(vehicle, b.fluid), {}, 0
		for j = 1, #sup do names[#names + 1] = sup[j].label; held = held + (sup[j].held or 0) end
		b.supply = names
		b.available = held
		if b.kind == "rate" and b.totalRate > 0 then b.runtimeHours = held / b.totalRate end
	end
	return out
end

VFluid.Update = VFluid.Update or {}

local function drawFrom(vehicle, fluidName, want)
	if want <= 0 then return 0 end
	local sup = VFluid.consumerSupply(vehicle, fluidName)
	local drawn = 0
	for i = 1, #sup do
		if want <= 0 then break end
		local e = sup[i]
		local take = math.min(want, e.held or 0)
		if take > 0 then
			VFluid.applyLevel(vehicle, e.part, e.axis, (VFluid.amount(e.part) or 0) - take)
			if vehicle.transmitPartModData then vehicle:transmitPartModData(e.part) end
			want, drawn = want - take, drawn + take
		end
	end
	return drawn
end

function VFluid.Update.Consumer(vehicle, part, elapsedMinutes)
	local mins = tonumber(elapsedMinutes) or 0
	if not vehicle or mins <= 0 then return end
	if VFluid.vanillaRules and VFluid.vanillaRules() then return end

	local now = (getGameTime and getGameTime() and getGameTime():getWorldAgeHours()) or nil
	local md = vehicle.getModData and vehicle:getModData() or nil
	local stamp = md and (md.VFluidMeteredAt or {}) or nil

	local script = vehicle.getScript and vehicle:getScript()
	local name = script and script:getName() or nil

	local want = {}
	for i = 1, #VFluid.consumerOrder do
		local c = VFluid.consumerSpecs[VFluid.consumerOrder[i]]
		if c and c.rate ~= nil and consumerCovers(c, name) then
			local on = true
			if c.active then
				local ok, v = pcall(c.active, vehicle)
				on = ok and v and true or false
			end
			if on then
				local r = VFluid.consumerAmount(c, "rate", vehicle)
				if r > 0 then want[c.fluid] = (want[c.fluid] or 0) + r end
			end
		end
	end

	for fluid, perHour in pairs(want) do
		local fresh = true
		if stamp and now then
			if stamp[fluid] == now then fresh = false else stamp[fluid] = now end
		end
		if fresh then
			drawFrom(vehicle, fluid, perHour * mins / 60)
		end
	end
	if md and stamp and now then md.VFluidMeteredAt = stamp end
end

function VFluid.useAvailable(vehicle, id)
	local c = VFluid.consumerSpecs[id]
	if not vehicle or not c or c.perUse == nil then return 0 end
	local sup, held = VFluid.consumerSupply(vehicle, c.fluid), 0
	for i = 1, #sup do held = held + (sup[i].held or 0) end
	return held
end

function VFluid.applyUse(vehicle, c)
	local want = VFluid.consumerAmount(c, "perUse", vehicle)
	if not vehicle or want <= 0 then return false end
	local sup = VFluid.consumerSupply(vehicle, c.fluid)
	local held = 0
	for i = 1, #sup do held = held + (sup[i].held or 0) end
	if held < want then return false end
	local left = want
	for i = 1, #sup do
		if left <= 0 then break end
		local e = sup[i]
		local take = math.min(left, e.held or 0)
		if take > 0 then
			VFluid.applyLevel(vehicle, e.part, e.axis, (VFluid.amount(e.part) or 0) - take)
			if vehicle.transmitPartModData then vehicle:transmitPartModData(e.part) end
			left = left - take
		end
	end
	return true
end

function VFluid.consumeUse(playerObj, vehicle, id)
	local c = VFluid.consumerSpecs[id]
	if not vehicle or not c or c.perUse == nil then return false end
	if VFluid.useAvailable(vehicle, id) < VFluid.consumerAmount(c, "perUse", vehicle) then
		return false
	end
	if isClient and isClient() then
		if not playerObj or not sendClientCommand then return false end
		sendClientCommand(playerObj, "vfluid", "use",
			{ vehicle = vehicle:getId(), id = id })
		return true
	end
	return VFluid.applyUse(vehicle, c)
end

function VFluid.consumptionRows(vehicle)
	local out = {}
	local blocks = VFluid.consumptionBlocks(vehicle)
	for i = 1, #blocks do
		local rows = blocks[i].rows
		for j = 1, #rows do
			out[#out + 1] = { label = rows[j].label, rate = rows[j].value, unit = rows[j].unit }
		end
	end
	return out
end
