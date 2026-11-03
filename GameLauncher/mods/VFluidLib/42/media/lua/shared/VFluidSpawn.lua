-- Spawn loads: what a tank holds when the world creates it. Fill chance gates first; one of
-- five branches picks the composition; then every valid (service, mode, fluid) state is
-- derived and one is frozen as the tank's designation.
-- Sorts after VFluidShared.lua and reaches the core through the VFluid table at run time,
-- never at load time. No require. DO NOT RENAME - the filename is load-bearing.

VFluid = VFluid or {}

local function log(msg) print("VFluidLib: " .. tostring(msg)) end

--------------------------------------------------------------------------------
-- SPAWN LOADS - what a tank holds when the world creates it.
--------------------------------------------------------------------------------

VFluid.spawnDefaults = VFluid.spawnDefaults or {
	branches = { origin = 35, flavor = 10, mixSmall = 30, mixMedium = 23, mixLarge = 2 },
	counts = { [1] = 18, [2] = 12, [3] = 11, [4] = 7, [5] = 5, [6] = 10, [7] = 6, [8] = 4 },
	rarity = {
		overrides  = { Water = 40, TaintedWater = 24, CarbonatedWater = 10 },
		categories = { Water = 50, Beverage = 15, Alcoholic = 12, Fuel = 8,
			Chemical = 6, Industrial = 4, Dyes = 3, HairDyes = 3, Poisons = 1 },
	},
	waterChance = 50,
	narrowestShare = 60,
}

--------------------------------------------------------------------------------
-- FLAVORS: curated spawn loads.
--------------------------------------------------------------------------------

VFluid.spawnFlavors = VFluid.spawnFlavors or {}
VFluid._flavorList = nil

function VFluid.registerFlavor(spec)
	if type(spec) ~= "table" or type(spec.id) ~= "string" then
		log("registerFlavor: needs a string id"); return false
	end
	if type(spec.fluids) ~= "table" then
		log("registerFlavor: " .. spec.id .. " needs a fluids table"); return false
	end
	spec.w = tonumber(spec.w) or 10
	if spec.origins then
		local set = {}
		for _, id in ipairs(spec.origins) do set[id] = true end
		spec._origins = set
	end
	VFluid.spawnFlavors[spec.id] = spec
	VFluid._flavorList = nil
	return true
end

function VFluid.unregisterFlavor(id)
	VFluid.spawnFlavors[id] = nil
	VFluid._flavorList = nil
end

local function flavorList()
	if not VFluid._flavorList then
		local out = {}
		for _, f in pairs(VFluid.spawnFlavors) do out[#out + 1] = f end
		table.sort(out, function(a, b) return tostring(a.id) < tostring(b.id) end)
		VFluid._flavorList = out
	end
	return VFluid._flavorList
end

function VFluid.flavorsFor(axis)
	local id = axis and axis.id
	local out = {}
	local all = flavorList()
	for i = 1, #all do
		local f = all[i]
		if (f.w or 0) > 0 and (not f._origins or (id and f._origins[id])) then out[#out + 1] = f end
	end
	return out
end

VFluid.registerFlavor{ id = "vfluid.milk",      w = 20, fluids = { CowMilk = 100 } }
VFluid.registerFlavor{ id = "vfluid.milkwater", w = 15, fluids = { CowMilk = 80, Water = 20 } }
VFluid.registerFlavor{ id = "vfluid.whisky",    w = 12, fluids = { Whiskey = 100 } }
VFluid.registerFlavor{ id = "vfluid.wine",      w = 12, fluids = { Wine = 100 } }
VFluid.registerFlavor{ id = "vfluid.beer",      w = 12, fluids = { Beer = 100 } }
VFluid.registerFlavor{ id = "vfluid.cocktail",  w = 10,
	fluids = { Vodka = 40, JuiceOrange = 35, Grenadine = 25 } }
VFluid.registerFlavor{ id = "vfluid.hairdye",   w = 10, fluids = { HairDye = 100 } }
VFluid.registerFlavor{ id = "vfluid.cleaning",  w =  9,
	fluids = { Bleach = 60, CleaningLiquid = 40 } }

function VFluid.spawnBranchWeights()
	local d = VFluid.spawnDefaults.branches
	local sv = SandboxVars and SandboxVars.VFluidLib or {}
	local function n(v, dflt)
		v = tonumber(v)
		if v == nil or v < 0 then return dflt end
		return v
	end
	return {
		{ id = "origin",    w = n(sv.SpawnOrigin,    d.origin) },
		{ id = "flavor",    w = n(sv.SpawnFlavor,    d.flavor) },
		{ id = "mixSmall",  w = n(sv.SpawnMixSmall,  d.mixSmall) },
		{ id = "mixMedium", w = n(sv.SpawnMixMedium, d.mixMedium) },
		{ id = "mixLarge",  w = n(sv.SpawnMixLarge,  d.mixLarge) },
	}
end

local function weightedPick(rand, entries, weightOf)
	local total = 0
	for i = 1, #entries do total = total + math.floor((weightOf(entries[i]) or 0) * 10 + 0.5) end
	if total <= 0 then return nil end
	local r = rand(total)
	local acc = 0
	for i = 1, #entries do
		acc = acc + math.floor((weightOf(entries[i]) or 0) * 10 + 0.5)
		if r < acc then return entries[i] end
	end
	return entries[#entries]
end

local function fluidSpawnWeight(f, rarity)
	local name = f.getFluidTypeString and f:getFluidTypeString()
	if not name then return 0 end
	local o = rarity.overrides[name]
	if o ~= nil then return o end
	local best = 0
	for cat, w in pairs(rarity.categories) do
		if FluidCategory and FluidCategory[cat] ~= nil then
			local ok, is = pcall(function() return f:isCategory(FluidCategory[cat]) end)
			if ok and is and w > best then best = w end
		end
	end
	return best
end

function VFluid.spawnFluidPool()
	if not (Fluid and Fluid.getAllFluids) then return nil end
	local ok, all = pcall(function() return Fluid.getAllFluids() end)
	if not ok or not all then return nil end
	local rarity = VFluid.spawnDefaults.rarity
	local pool = {}
	for i = 0, all:size() - 1 do
		local f = all:get(i)
		if f then
			local w = fluidSpawnWeight(f, rarity)
			if w > 0 then pool[#pool + 1] = { name = f:getFluidTypeString(), w = w } end
		end
	end
	if #pool == 0 then return nil end
	return pool
end

function VFluid.rollComposition(axis, rand)
	local d = VFluid.spawnDefaults
	local branch = weightedPick(rand, VFluid.spawnBranchWeights(), function(e) return e.w end)
	if not branch then return nil end

	if branch.id == "origin" then
		local f = axis and axis.defaultFluid
		if not f then return nil end
		return { [f] = 100 }
	end

	if branch.id == "flavor" then
		local eligible = VFluid.flavorsFor(axis)
		local combo = weightedPick(rand, eligible, function(e) return e.w end)
		if not combo then
			local f = axis and axis.defaultFluid
			return f and { [f] = 100 } or nil
		end
		local out = {}
		for name, share in pairs(combo.fluids) do out[name] = share end
		return out
	end

	local lo, hi = 1, 2
	if branch.id == "mixMedium" then lo, hi = 3, 5 elseif branch.id == "mixLarge" then lo, hi = 6, 8 end
	local tier = {}
	for c = lo, hi do tier[#tier + 1] = { n = c, w = d.counts[c] or 1 } end
	local count = weightedPick(rand, tier, function(e) return e.w end)
	count = count and count.n or lo

	local pool = VFluid.spawnFluidPool()
	if not pool then
		local f = axis and axis.defaultFluid
		return f and { [f] = 100 } or nil
	end
	local picked, out = {}, {}
	for _ = 1, count do
		local candidates = {}
		for i = 1, #pool do
			if not picked[pool[i].name] then candidates[#candidates + 1] = pool[i] end
		end
		local hit = weightedPick(rand, candidates, function(e) return e.w end)
		if not hit then break end
		picked[hit.name] = true
		out[hit.name] = 10 + rand(91)
	end
	local any = false
	for _ in pairs(out) do any = true break end
	return any and out or nil
end

function VFluid.rollFillTotal(axis, capacity, rand)
	if not capacity or capacity <= 0 then return 0 end
	local sv = SandboxVars or {}
	if sv.VehicleEasyUse == true then
		return rand(math.floor(capacity / 2), math.floor(capacity) + 1)
	end
	local chance = VFluid.spawnDefaults.waterChance
	if axis and axis.id == "fuel" then
		chance = 35
		if sv.ChanceHasGas == 1 then chance = 15 elseif sv.ChanceHasGas == 3 then chance = 60 end
	end
	if rand(100) >= chance then return 0 end
	local top = math.max(4, math.floor(capacity / 3))
	return rand(3, top + 1)
end

function VFluid.spawnStates(originAxis, contents)
	local names = {}
	for name, amt in pairs(contents or {}) do
		if amt and amt > 0 then names[#names + 1] = name end
	end
	local d = VFluid.spawnDefaults
	local states, rank = {}, 0
	local function push(axis, mode, fluid)
		local w = (rank == 0) and d.narrowestShare
			or math.max(1, math.floor(d.narrowestShare / (2 ^ rank) + 0.5))
		rank = rank + 1
		states[#states + 1] = { axisId = axis.id, mode = mode, fluid = fluid, w = w }
	end

	if #names == 0 then
		if originAxis and originAxis.kind == "fluid" then
			push(originAxis, VFluid.MODE_SINGLE, nil)
		end
		for i = 1, #(VFluid.axisOrder or {}) do
			local ax = VFluid.axes[VFluid.axisOrder[i]]
			if ax and ax.kind == "fluid" and ax ~= originAxis then
				push(ax, VFluid.MODE_SINGLE, nil)
			end
		end
		return states
	end

	local objs = {}
	for i = 1, #names do
		local ok, f = pcall(function() return Fluid.Get(names[i]) end)
		if not ok or not f then return {} end
		objs[i] = f
	end
	for i = 1, #(VFluid.axisOrder or {}) do
		local ax = VFluid.axes[VFluid.axisOrder[i]]
		if ax and ax.kind == "fluid" then
			local all = true
			for k = 1, #objs do
				if not VFluid.axisAdmits(ax, objs[k]) then all = false break end
			end
			if all then
				if #names == 1 then
					local base = (ax.variantOf and ax.variantOf[names[1]]) or names[1]
					push(ax, VFluid.MODE_SINGLE, base)
				end
				push(ax, VFluid.MODE_MULTI, nil)
			end
		end
	end
	return states
end

function VFluid.applySpawn(vehicle, part, axis, rand)
	if not vehicle or not part or not axis then return nil end
	if VFluid.vanillaRules and VFluid.vanillaRules() then return nil end
	rand = rand or ZombRand
	if not rand then return nil end
	local capacity = part.getContainerCapacity and part:getContainerCapacity() or 0

	if axis.kind ~= "fluid" then
		local total
		local ucfg = VFluid.getConfig and VFluid.getConfig(vehicle)
		local uentry = ucfg and ucfg.spawn and ucfg.spawn[part:getId()]
		if type(uentry) == "function" then
			local ok, n = pcall(uentry, vehicle, part, axis, capacity, rand)
			if ok and type(n) == "number" then total = n end
		elseif type(uentry) == "number" then
			total = uentry
		elseif type(uentry) == "table" and uentry.fill then
			total = capacity * math.min(100, tonumber(uentry.fill) or 0) / 100
		end
		if total == nil then total = VFluid.rollFillTotal(axis, capacity, rand) end
		if total < 0 then total = 0 end
		if total > capacity then total = capacity end
		VFluid.setAmount(vehicle, part, math.floor(total + 0.5))
		return { units = math.floor(total + 0.5) }
	end

	local shares, total
	local fixedFluid = VFluid.fixedDesignationOf and VFluid.fixedDesignationOf(vehicle, part) or nil
	local cfg = VFluid.getConfig and VFluid.getConfig(vehicle)
	local entry = cfg and cfg.spawn and cfg.spawn[part:getId()]
	local dictate = nil
	if type(entry) == "function" then
		local ok, amounts, designate = pcall(entry, vehicle, part, axis, capacity, rand)
		if ok and type(amounts) == "table" then
			return VFluid.finishSpawn(vehicle, part, axis, amounts, rand,
				type(designate) == "table" and designate or nil)
		end
		entry = nil
	end
	if type(entry) == "table" and type(entry.fluids) == "table" then
		shares = entry.fluids
		dictate = type(entry.designate) == "table" and entry.designate or nil
		if entry.fill then total = capacity * math.min(100, tonumber(entry.fill) or 0) / 100
		else total = VFluid.rollFillTotal(axis, capacity, rand) end
	elseif fixedFluid then
		total = VFluid.rollFillTotal(axis, capacity, rand)
		if total > 0 then shares = { [fixedFluid] = 1 } end
	else
		total = VFluid.rollFillTotal(axis, capacity, rand)
		if total > 0 then shares = VFluid.rollComposition(axis, rand) end
	end

	local amounts = {}
	if shares and total and total > 0 then
		local sum = 0
		for _, sh in pairs(shares) do sum = sum + (sh or 0) end
		if sum > 0 then
			for name, sh in pairs(shares) do
				if sh and sh > 0 then amounts[name] = total * sh / sum end
			end
		end
	end
	return VFluid.finishSpawn(vehicle, part, axis, amounts, rand, dictate)
end

function VFluid.finishSpawn(vehicle, part, axis, amounts, rand, dictate)
	amounts = amounts or {}
	VFluid.setLedger(vehicle, part, amounts)
	local n = 0
	for _, amt in pairs(amounts) do if amt and amt > 0 then n = n + 1 end end
	if n > 1 and VFluid.markResidue then VFluid.markResidue(vehicle, part, axis) end

	local state = nil
	if VFluid.fixedDesignationOf and VFluid.fixedDesignationOf(vehicle, part) then
		if vehicle.transmitPartModData then pcall(function() vehicle:transmitPartModData(part) end) end
		return { amounts = amounts, fluids = n, state = nil, compromised = false }
	end
	if dictate and dictate.axis and VFluid.axes[dictate.axis] and VFluid.spawnDesignate then
		VFluid.spawnDesignate(vehicle, part, dictate.axis, dictate.mode or "single", dictate.fluid)
		if vehicle.transmitPartModData then pcall(function() vehicle:transmitPartModData(part) end) end
		return { amounts = amounts, fluids = n,
			state = { axisId = dictate.axis, mode = dictate.mode or "single", fluid = dictate.fluid },
			compromised = false }
	end
	local states = VFluid.spawnStates(axis, amounts)
	if #states > 0 then
		if n == 0 then
			state = states[1]
		else
			state = weightedPick(rand, states, function(e) return e.w end)
		end
		if state and VFluid.spawnDesignate then
			VFluid.spawnDesignate(vehicle, part, state.axisId, state.mode, state.fluid)
		end
	end
	if vehicle.transmitPartModData then pcall(function() vehicle:transmitPartModData(part) end) end
	return { amounts = amounts, fluids = n, state = state, compromised = (n > 0 and #states == 0) }
end
