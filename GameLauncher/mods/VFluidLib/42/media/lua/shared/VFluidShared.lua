-- Vehicle Fluid Logistics - the library. Registries and recognition, the tank ledger,
-- endpoints for everything fluid can move between, and the transfer rules.
-- Recognition keys on (contentType, partId), never on vehicle identity.

VFluid = VFluid or {}

VFluid.CAPS = VFluid.CAPS or {}
VFluid.CAPS.registry   = 1
VFluid.CAPS.registry2  = 1
VFluid.CAPS.gasTankGuard = 1
VFluid.CAPS.ledger     = 1
VFluid.CAPS.endpoints  = 1
VFluid.CAPS.units      = 1
VFluid.CAPS.transfer   = 1

VFluid.axes     = VFluid.axes     or {}
VFluid.axisOrder = VFluid.axisOrder or {}
VFluid.vehicles = VFluid.vehicles or {}
VFluid.refusals = VFluid.refusals or {}

local ENGINE_TANK_PART = "GasTank"

local function log(msg) print("VFluidLib: " .. tostring(msg)) end

--------------------------------------------------------------------------------
-- registry
--------------------------------------------------------------------------------

function VFluid.registerAxis(axis)
	if type(axis) ~= "table" or type(axis.id) ~= "string" then
		log("registerAxis: an axis needs a string id"); return false
	end
	if type(axis.contentTypes) ~= "table" then
		log("registerAxis: " .. axis.id .. " needs a contentTypes table"); return false
	end
	if VFluid.axes[axis.id] then
		log("registerAxis: '" .. axis.id .. "' already exists - REFUSED. To widen it use "
			.. "acceptContentType/acceptFluid/acceptCategory; to replace it deliberately use "
			.. "VFluid.replaceAxis.")
		return false
	end
	axis.kind         = axis.kind or "fluid"
	axis.accept       = axis.accept or {}
	axis.variantOf    = axis.variantOf or {}
	axis.roundTo      = axis.roundTo or 3
	axis.secondsPerUnit = axis.secondsPerUnit or 12
	axis.duplicates   = axis.duplicates or {}
	if not VFluid.axes[axis.id] then
		VFluid.axisOrder[#VFluid.axisOrder + 1] = axis.id
	end
	VFluid.axes[axis.id] = axis
	return true
end

function VFluid.registerVehicle(scriptName, cfg)
	if type(scriptName) ~= "string" or type(cfg) ~= "table" then
		log("registerVehicle: needs (scriptName, cfg)"); return false
	end
	VFluid.vehicles[scriptName] = cfg
	return true
end

function VFluid.updateVehicle(scriptName, patch)
	if type(scriptName) == "table" then
		local ok = #scriptName > 0
		for i = 1, #scriptName do ok = VFluid.updateVehicle(scriptName[i], patch) and ok end
		return ok
	end
	if type(scriptName) ~= "string" or type(patch) ~= "table" then
		log("updateVehicle: needs (scriptName|{scriptNames}, patch)"); return false
	end
	local cfg = VFluid.vehicles[scriptName]
	if not cfg then cfg = {}; VFluid.vehicles[scriptName] = cfg end
	for k, v in pairs(patch) do cfg[k] = v end
	return true
end

function VFluid.getConfig(vehicle)
	if not vehicle then return nil end
	local script = vehicle:getScript()
	if not script then return nil end
	return VFluid.vehicles[script:getName()]
end

--------------------------------------------------------------------------------
-- recognition
--------------------------------------------------------------------------------

local function hasEngine(vehicle)
	if not vehicle then return false end
	return vehicle:getPartById("Engine") ~= nil
end

local function axisForContentType(contentType, partId)
	local refused, refusedBy = nil, nil
	for i = 1, #VFluid.axisOrder do
		local axis = VFluid.axes[VFluid.axisOrder[i]]
		local rule = axis.contentTypes[contentType]
		if rule == true then return axis end
		if rule == "notGasTank" then
			if partId ~= ENGINE_TANK_PART then return axis end
			refused, refusedBy = "engine-supply tank, not cargo", axis
		end
	end
	return nil, refused, refusedBy
end

VFluid.refusalSeen = VFluid.refusalSeen or {}

local function noteRefusal(vehicle, partId, contentType, reason)
	local script = vehicle and vehicle:getScript() and vehicle:getScript():getName() or "?"
	local key = script .. "|" .. tostring(partId) .. "|" .. tostring(contentType)
	if VFluid.refusalSeen[key] then return end
	VFluid.refusalSeen[key] = true
	VFluid.refusals[#VFluid.refusals + 1] = {
		vehicle = script, part = partId, contentType = contentType, reason = reason,
	}
end

VFluid.ignoreContentTypes = VFluid.ignoreContentTypes or { ["Air"] = true }

VFluid.unknownContainers = VFluid.unknownContainers or {}

local function noteUnknown(vehicle, part, contentType)
	if VFluid.ignoreContentTypes[contentType] then return end
	local partId = part:getId()
	local key = tostring(contentType) .. "|" .. tostring(partId)
	if VFluid.unknownContainers[key] then return end
	local script = vehicle and vehicle:getScript() and vehicle:getScript():getName() or "?"
	VFluid.unknownContainers[key] = { contentType = contentType, part = partId, vehicle = script }
	log(string.format(
		"unclaimed fluid container: contentType='%s' part='%s' on '%s' - no axis handles it",
		tostring(contentType), tostring(partId), script))
end

function VFluid.surfaceLabel(surface, ...)
	if surface == "context" then
		local out, n = {}, 0
		for i = 1, select("#", ...) do
			local piece = select(i, ...)
			if piece and piece ~= "" then n = n + 1; out[n] = piece end
		end
		return table.concat(out, " - ")
	end
	return VFluid.radialLabel(...)
end

function VFluid.radialLabel(...)
	local out, n = {}, 0
	for i = 1, select("#", ...) do
		local s = select(i, ...)
		if s and s ~= "" and n < 3 then n = n + 1; out[n] = s end
	end
	return table.concat(out, "\n")
end

function VFluid.axisFor(vehicle, part)
	if not part or not part:isContainer() then return nil end
	if not part:getInventoryItem() then return nil end
	local contentType = part:getContainerContentType()
	if not contentType or contentType == "" then return nil end
	local partId = part:getId()

	if part:hasModData() then
		local md = part:getModData().VFluid
		if md and md.axis and VFluid.axes[md.axis] then return VFluid.axes[md.axis] end
	end

	local axis, refused, refusedBy = axisForContentType(contentType, partId)
	if not axis then
		if refused then
			noteRefusal(vehicle, partId, contentType, refused)
			return nil, "supply", refusedBy
		end
		noteUnknown(vehicle, part, contentType)
		return nil, "unknown", nil
	end

	if partId == ENGINE_TANK_PART and hasEngine(vehicle) then
		noteRefusal(vehicle, partId, contentType, "GasTank on an engine-bearing vehicle")
		return nil, "supply", axis
	end
	return axis
end

function VFluid.isSupplyTank(vehicle, part)
	if not part or not part.getId or part:getId() ~= ENGINE_TANK_PART then return false end
	if not part:isContainer() then return false end
	local axis, why, byAxis = VFluid.axisFor(vehicle, part)
	if axis then return false end
	if why ~= "supply" then return false end
	return byAxis ~= nil and byAxis.id == "fuel"
end

function VFluid.tanksOn(vehicle)
	local out = {}
	if not vehicle then return out end
	local count = vehicle:getPartCount()
	for i = 0, count - 1 do
		local part = vehicle:getPartByIndex(i)
		if part then
			local axis = VFluid.axisFor(vehicle, part)
			if axis then out[#out + 1] = { part = part, axis = axis } end
		end
	end
	return out
end

function VFluid.isTank(vehicle, part) return VFluid.axisFor(vehicle, part) ~= nil end

--------------------------------------------------------------------------------
-- Diagnostics - the phase-2 acceptance test
--------------------------------------------------------------------------------

function VFluid.dump()
	local player = getPlayer()
	local cell = player and player:getCell()
	if not cell then log("dump: no cell"); return end
	VFluid.refusals = {}
	local vehicles = cell:getVehicles()
	local seen, tanks = 0, 0
	for i = 0, vehicles:size() - 1 do
		local vehicle = vehicles:get(i)
		if vehicle then
			seen = seen + 1
			local list = VFluid.tanksOn(vehicle)
			for j = 1, #list do
				tanks = tanks + 1
				local part = list[j].part
				log(string.format("tank  %s  part=%s  contentType=%s  axis=%s  amount=%.1f/%d",
					vehicle:getScript() and vehicle:getScript():getName() or "?",
					part:getId(), tostring(part:getContainerContentType()), list[j].axis.id,
					part:getContainerContentAmount(), part:getContainerCapacity()))
			end
		end
	end
	for i = 1, #VFluid.refusals do
		local r = VFluid.refusals[i]
		log(string.format("REFUSED  %s  part=%s  contentType=%s  (%s)",
			r.vehicle, r.part, tostring(r.contentType), r.reason))
	end
	log(string.format("dump: %d vehicles, %d tanks, %d refusals", seen, tanks, #VFluid.refusals))
end

--------------------------------------------------------------------------------
-- The axis rows.

VFluid.registerAxis{
	id           = "fuel",
	kind         = "fluid",
	contentTypes = { ["Gasoline Storage"] = true, ["Gasoline"] = "notGasTank" },
	defaultFluid = "Petrol",
	accept       = { categories = { "Fuel" } },
	roundTo      = 3,
	duplicates   = { "tsarslib", "rSemiTruck" },
}

VFluid.registerAxis{
	id           = "potable",
	kind         = "fluid",
	contentTypes = { ["Water Storage"] = true, ["Water"] = "notGasTank" },
	defaultFluid = "Water",
	accept       = { categories = { "Water" } },
	variantOf    = { TaintedWater = "Water" },
	roundTo      = 3,
	duplicates   = { "rWaterTrailerB42", "rSemiTruck" },
}

VFluid.registerAxis{
	id           = "beverage",
	kind         = "fluid",
	contentTypes = { ["Beverage Storage"] = true },
	defaultFluid = "CowMilk",
	variantOf    = { TaintedWater = "Water" },
	accept       = { categories = { "Beverage", "Water" } },
	roundTo      = 3,
	duplicates   = {},
}

VFluid.registerAxis{
	id           = "propane",
	kind         = "unit",
	contentTypes = { ["Propane Storage"] = true },
	roundTo      = 3,
	duplicates   = {},
}

VFluid.registerAxis{
	id           = "chemical",
	kind         = "fluid",
	contentTypes = { ["Chemical Storage"] = true },
	defaultFluid = "Bleach",
	accept       = { exclusive = true, fluidNames = { "Bleach", "Acid", "CleaningLiquid" } },
	roundTo      = 3,
	duplicates   = {},
}

VFluid.registerAxis{
	id           = "dye",
	kind         = "fluid",
	contentTypes = { ["Dye Storage"] = true },
	defaultFluid = "Dye",
	accept       = { exclusive = true, fluidNames = { "Dye", "HairDye" } },
	roundTo      = 3,
	duplicates   = {},
}

VFluid.registerAxis{
	id           = "industrial",
	kind         = "fluid",
	contentTypes = { ["Industrial Storage"] = true },
	defaultFluid = "Blood",
	accept       = { exclusive = true,
		fluidNames = { "Blood", "Cologne", "Perfume", "SecretFlavoring", "RubbingAlcohol" } },
	roundTo      = 3,
	duplicates   = {},
}

--------------------------------------------------------------------------------
-- the ledger, the rented rules engine, and the mirror invariant
--   part:getContainerContentAmount()  ==  sum of the ledger,  ALWAYS.
--------------------------------------------------------------------------------

local MODKEY = "VFluid"
local EPS = 0.05

-- The ONLY read path. Everything above L2 must come through here, or the invariant is
function VFluid.amount(part)
	if not part then return 0 end
	return part:getContainerContentAmount()
end

-- The ONLY write path.
function VFluid.setAmount(vehicle, part, value)
	if not part then return 0 end
	local cap = part:getContainerCapacity() or 0
	if value < 0 then value = 0 end
	if value > cap then value = cap end
	part:setContainerContentAmount(value)
	if vehicle and vehicle.transmitPartModData then vehicle:transmitPartModData(part) end
	return value
end

local function modOf(part, create)
	if not part then return nil end
	if not create and not part:hasModData() then return nil end
	local md = part:getModData()
	if not md then return nil end
	if not md[MODKEY] then
		if not create then return nil end
		md[MODKEY] = { fluids = {} }
	end
	if create and not md[MODKEY].fluids then md[MODKEY].fluids = {} end
	return md[MODKEY]
end

local function sumOf(fluids)
	local total = 0
	if fluids then for _, v in pairs(fluids) do total = total + (v or 0) end end
	return total
end

local function creditArrival(fluids, delta, axis, fluidName, shares)
	local credited = false
	if shares then
		for fname, share in pairs(shares) do
			if share and share > 0 then
				fluids[fname] = (fluids[fname] or 0) + delta * share
				credited = true
			end
		end
	end
	if not credited then
		local name = fluidName or (axis and axis.defaultFluid)
		if name then
			fluids[name] = (fluids[name] or 0) + delta
			credited = true
		end
	end
	return credited
end

function VFluid.ledger(vehicle, part, axis)
	axis = axis or VFluid.axisFor(vehicle, part)
	if not axis or axis.kind ~= "fluid" then return nil end
	local mod = modOf(part, true)
	local amount = VFluid.amount(part)
	local total = sumOf(mod.fluids)

	if amount <= 0 then
		if total > 0 then mod.fluids = {} end
		return mod.fluids
	end
	if total <= 0 then
		mod.fluids = { [axis.defaultFluid or "Water"] = amount }
		return mod.fluids
	end
	local diff = amount - total
	if diff > EPS then
		creditArrival(mod.fluids, diff, axis, axis.defaultFluid or "Water", nil)
	elseif diff < -EPS then
		local scale = amount / total
		for name, v in pairs(mod.fluids) do mod.fluids[name] = v * scale end
	end
	return mod.fluids
end

function VFluid.partMod(part, create)
	return modOf(part, create)
end

function VFluid.rawLedger(part)
	local mod = modOf(part, true)
	return mod.fluids
end

function VFluid.setLedger(vehicle, part, fluids)
	local mod = modOf(part, true)
	mod.fluids = fluids or {}
	VFluid._ledgerRev = (VFluid._ledgerRev or 0) + 1
	local total = sumOf(mod.fluids)
	VFluid.setAmount(vehicle, part, total)
	return mod.fluids
end

--------------------------------------------------------------------------------
-- The rented rules engine: vanilla's own blend, poison and mixture logic, borrowed per
--------------------------------------------------------------------------------

function VFluid.rent(capacity)
	if not FluidContainer or not FluidContainer.CreateContainer then return nil end
	local fc = FluidContainer.CreateContainer()
	if not fc then return nil end
	fc:setCapacity(capacity and capacity > 0 and capacity or 1)
	return fc
end

function VFluid.release(fc)
	if fc and FluidContainer and FluidContainer.DisposeContainer then
		FluidContainer.DisposeContainer(fc)
	end
end

function VFluid.fill(fc, fluids)
	if not fc or not fluids then return fc, nil end
	local unadded = nil
	local function short(name, amt)
		unadded = unadded or {}
		unadded[name] = (unadded[name] or 0) + amt
	end
	for name, amt in pairs(fluids) do
		if amt and amt > 0 then
			local f = Fluid and Fluid.Get and Fluid.Get(name)
			if not f then
				short(name, amt)
			else
				local before = fc:getAmount()
				fc:addFluid(f, amt)
				local gained = fc:getAmount() - before
				if gained < amt - EPS then
					short(name, amt - math.max(0, gained))
				end
			end
		end
	end
	return fc, unadded
end

function VFluid.unrepresentable(unadded)
	if not unadded then return nil end
	local best, bestAmt
	for name, amt in pairs(unadded) do
		if not bestAmt or amt > bestAmt then best, bestAmt = name, amt end
	end
	return best, bestAmt
end

function VFluid.readBack(fc)
	local out = {}
	if not fc or not fc.createFluidSample then return out end
	local s = fc:createFluidSample()
	if not s then return out end
	local total = s:getAmount() or 0
	for i = 0, s:size() - 1 do
		local f = s:getFluid(i)
		if f then
			local pct = s:getPercentage(i) or 0
			out[f:getFluidTypeString()] = total * pct
		end
	end
	if s.release then s:release() end
	return out
end

local fluidByName

function VFluid.axisAdmits(axis, fluid)
	if not axis or not fluid then return false end
	local acc = axis.accept
	if not acc then return true end

	local cats = acc.categories
	local names = acc.fluidNames
	if acc.exclusive and names and #names > 0 then
		for i = 1, #names do
			local f = fluidByName(names[i])
			if f and f == fluid then return true end
		end
		return false
	end
	if not cats or #cats == 0 then return true end

	for i = 1, (names and #names or 0) do
		local f = fluidByName(names[i])
		if f and f == fluid then return true end
	end

	for i = 1, #cats do
		local c = FluidCategory and FluidCategory[cats[i]]
		if c and fluid:isCategory(c) then return true end
	end
	return false
end

--------------------------------------------------------------------------------
-- Mod compatibility: admitting fluids this library has never heard of.
--------------------------------------------------------------------------------

local function axisOrLog(axisId, what)
	local axis = VFluid.axes[axisId]
	if not axis then log(what .. ": no such axis '" .. tostring(axisId) .. "'") end
	return axis
end

function VFluid.replaceAxis(axis)
	if type(axis) ~= "table" or type(axis.id) ~= "string" then
		log("replaceAxis: needs an axis table with a string id"); return false
	end
	local existing = VFluid.axes[axis.id]
	if existing then
		VFluid.axes[axis.id] = nil
		log("replaceAxis: replacing '" .. axis.id .. "'")
	end
	local ok = VFluid.registerAxis(axis)
    if not ok and existing then VFluid.axes[axis.id] = existing end
	return ok
end

function VFluid.acceptContentType(axisId, contentType, rule)
	local axis = axisOrLog(axisId, "acceptContentType")
	if not axis or type(contentType) ~= "string" or contentType == "" then return false end
	if rule ~= nil and rule ~= "notGasTank" then
		log("acceptContentType: rule must be nil or 'notGasTank', got " .. tostring(rule))
		return false
	end
	axis.contentTypes = axis.contentTypes or {}
	axis.contentTypes[contentType] = (rule == "notGasTank") and "notGasTank" or true
	return true
end

function VFluid.acceptFluid(axisId, fluidName)
	local axis = axisOrLog(axisId, "acceptFluid")
	if not axis or type(fluidName) ~= "string" then return false end
	axis.accept = axis.accept or {}
	axis.accept.fluidNames = axis.accept.fluidNames or {}
	local list = axis.accept.fluidNames
	for i = 1, #list do if list[i] == fluidName then return true end end
	list[#list + 1] = fluidName
	return true
end

function VFluid.acceptCategory(axisId, categoryName)
	local axis = axisOrLog(axisId, "acceptCategory")
	if not axis or type(categoryName) ~= "string" then return false end
	if FluidCategory and FluidCategory[categoryName] == nil then
		log("acceptCategory: '" .. categoryName .. "' is not a FluidCategory")
		return false
	end
	axis.accept = axis.accept or {}
	axis.accept.categories = axis.accept.categories or {}
	local cats = axis.accept.categories
	for i = 1, #cats do if cats[i] == categoryName then return true end end
	cats[#cats + 1] = categoryName
	return true
end

--------------------------------------------------------------------------------
-- the read model behind the Fluid Info panel.
--------------------------------------------------------------------------------

local function fluidFace(name)
	local f = fluidByName(name)
	if not f then return name, nil end
	local label = name
	if f.getTranslatedName then
		local ok, n = pcall(function() return f:getTranslatedName() end)
		if ok and n and n ~= "" then label = n end
	end
	local col
	if f.getColor then
		local ok, c = pcall(function() return f:getColor() end)
		if ok and c then
			local okr, r = pcall(function() return c:getR() end)
			local okg, g = pcall(function() return c:getG() end)
			local okb, b = pcall(function() return c:getB() end)
			if okr and okg and okb then col = { r = r, g = g, b = b } end
		end
	end
	return label, col
end

function VFluid.partLabel(partId)
	if not partId then return "?" end
	if getTextOrNull then
		local ok, n = pcall(function() return getTextOrNull("IGUI_VehiclePart" .. partId) end)
		if ok and n and n ~= "" then return n end
	end
	return partId
end

local function pctOf(amount, capacity)
	if not capacity or capacity <= 0 then return 0 end
	local p = amount / capacity * 100
	if p < 0 then return 0 elseif p > 100 then return 100 end
	return p
end

function VFluid.mixtureOf(vehicle, part, axis)
	axis = axis or VFluid.axisFor(vehicle, part)
	if not axis or axis.kind ~= "fluid" then return nil end
	local led = VFluid.ledger(vehicle, part, axis)
	if not led then return nil end
	local total, rows = 0, {}
	for name, amt in pairs(led) do
		if amt and amt > 0 then
			total = total + amt
			local label, col = fluidFace(name)
			rows[#rows + 1] = { fluid = name, label = label, color = col, amount = amt }
		end
	end
	if axis.variantOf then
		local byName = {}
		for i = 1, #rows do byName[rows[i].fluid] = i end
		for variant, base in pairs(axis.variantOf) do
			local vi, bi = byName[variant], byName[base]
			if vi and bi then
				rows[bi].amount = rows[bi].amount + rows[vi].amount
				rows[vi].amount = 0
			elseif vi and not bi then
				rows[vi].fluid = base
				rows[vi].label = (select(1, fluidFace(base)))
				rows[vi].color = (select(2, fluidFace(base)))
			end
		end
		local kept = {}
		for i = 1, #rows do if rows[i].amount > 0 then kept[#kept + 1] = rows[i] end end
		rows = kept
	end
	for i = 1, #rows do rows[i].pct = total > 0 and (rows[i].amount / total * 100) or 0 end
	table.sort(rows, function(a, b)
		if a.amount ~= b.amount then return a.amount > b.amount end
		return a.fluid < b.fluid
	end)
	return rows
end

local function tr(key, default)
	if getTextOrNull then
		local ok, n = pcall(getTextOrNull, key)
		if ok and n and n ~= "" then return n end
	end
	if getText then
		local ok, n = pcall(getText, key)
		if ok and n and n ~= "" and n ~= key then return n end
	end
	return default
end
VFluid.tr = tr

function VFluid.fluidLabel(name)
	if not name then return nil end
	local unit = VFluid.axes[name]
	if unit and unit.kind == "unit" then return VFluid.axisLabel(unit) end
	return (select(1, fluidFace(name)))
end

function VFluid.primaryFluidOf(vehicle, part, axis)
	axis = axis or VFluid.axisFor(vehicle, part)
	if not axis then return nil end
	if axis.kind == "unit" then return axis.id end
	local led = VFluid.rawLedger(part)
	local best, bestAmt
	for name, amt in pairs(led or {}) do
		if amt and amt > 0 and (bestAmt == nil or amt > bestAmt) then best, bestAmt = name, amt end
	end
	return best or axis.defaultFluid
end

function VFluid.contentsLabel(vehicle, part, axis, nameVariant)
	axis = axis or VFluid.axisFor(vehicle, part)
	if not axis then return nil end
	if axis.kind == "unit" then
		if VFluid.amount(part) <= 0 then return nil end
		return VFluid.axisLabel(axis)
	end
	local rows = VFluid.mixtureOf(vehicle, part, axis)
	if not rows or #rows == 0 then return nil end
	if #rows > 1 then
		return VFluid.axisMixLabel(axis)
	end
	if nameVariant and VFluid.isTaintedTank(vehicle, part, axis) and axis.variantOf then
		for variant, base in pairs(axis.variantOf) do
			if base == rows[1].fluid then
				return (select(1, fluidFace(variant)))
			end
		end
	end
	return rows[1].label or rows[1].fluid
end

function VFluid.axisLabel(axis)
	if not axis then return "?" end
	return tr("IGUI_VFluid_Axis_" .. tostring(axis.id), tostring(axis.id))
end

function VFluid.axisMixLabel(axis)
	if not axis then return "?" end
	return tr("IGUI_VFluid_AxisMix_" .. tostring(axis.id), VFluid.axisLabel(axis))
end

function VFluid.itemFluidName(item)
	if not item then return nil end
	local ownAxis = VFluid.unitsAxis[item.getFullType and item:getFullType() or ""]
	if ownAxis then
		local a = VFluid.axes[ownAxis]
		if a and a.kind == "unit" then
			local uses = item.getCurrentUses and item:getCurrentUses() or 0
			return uses > 0 and ownAxis or nil
		end
	end
	if not item.getFluidContainer then return nil end
	local fc = item:getFluidContainer()
	if not fc or fc:getAmount() <= 0 then return nil end
	local f = fc.getPrimaryFluid and fc:getPrimaryFluid()
	if not f then return nil end
	local okName, named = pcall(function() return f:getFluidTypeString() end)
	if okName and named and named ~= "" then return named end
	for i = 1, #VFluid.axisOrder do
		local a = VFluid.axes[VFluid.axisOrder[i]]
		for _, nm in ipairs({ a.defaultFluid }) do
			if nm and fluidByName(nm) == f then return nm end
		end
		if a.variantOf then
			for variant, _ in pairs(a.variantOf) do
				if fluidByName(variant) == f then return variant end
			end
		end
	end
	return nil
end

function VFluid.axisHasVariants(axis)
	if not axis or axis.kind ~= "fluid" or not axis.variantOf then return false end
	for _ in pairs(axis.variantOf) do return true end
	return false
end

function VFluid.isTaintedTank(vehicle, part, axis)
	axis = axis or VFluid.axisFor(vehicle, part)
	if not axis or not axis.variantOf or axis.kind ~= "fluid" then return false end
	local led = VFluid.ledger(vehicle, part, axis)
	if not led then return false end
	for variant, _ in pairs(axis.variantOf) do
		if (led[variant] or 0) > 0 then return true end
	end
	return false
end

--------------------------------------------------------------------------------
-- Drinking straight from a tank, and the safety on it.
--------------------------------------------------------------------------------

function VFluid.isHarmfulFluid(name)
	local f = fluidByName(name)
	if not f then return false end
	local ok, poison = pcall(function() return f:isPoisonous() end)
	if ok and poison then return true end
	for _, cat in ipairs({ "Hazardous", "Poisons" }) do
		local c = FluidCategory and FluidCategory[cat]
		if c then
			local okc, isc = pcall(function() return f:isCategory(c) end)
			if okc and isc then return true end
		end
	end
	return false
end

function VFluid.hitchedRefuelAllowed()
	local sv = SandboxVars and SandboxVars.VFluidLib
	return sv ~= nil and sv.HitchedRefuel == true
end

VFluid.CLEAN_OFF, VFluid.CLEAN_MIXTURES, VFluid.CLEAN_ALL = 1, 2, 3

function VFluid.rinsesClean(fluidName)
	if not fluidName then return true end
	local f = Fluid and Fluid.Get and Fluid.Get(fluidName)
	if not f or not f.isCategory or not FluidCategory then return false end
	local ok, watery = pcall(function() return f:isCategory(FluidCategory.Water) end)
	return (ok and watery) == true
end

function VFluid.serviceCovering(names)
	if not names or #names == 0 then return nil end
	for i = 1, #(VFluid.axisOrder or {}) do
		local a = VFluid.axes[VFluid.axisOrder[i]]
		if a and a.kind == "fluid" then
			local all = true
			for j = 1, #names do
				local f = Fluid and Fluid.Get and Fluid.Get(names[j])
				if not f or not VFluid.axisAdmits(a, f) then all = false break end
			end
			if all then return a.id end
		end
	end
	return nil
end

function VFluid.serviceAfterAdding(vehicle, part, axis, adding)
	local names, seen = {}, {}
	local led = VFluid.rawLedger and VFluid.rawLedger(part)
	if led then
		for name, q in pairs(led) do
			if q and q > 0 and not seen[name] then seen[name] = true; names[#names + 1] = name end
		end
	end
	if adding and not seen[adding] then names[#names + 1] = adding end
	if #names == 0 then return axis and axis.id or nil end
	return VFluid.serviceCovering(names)
end

function VFluid.serviceOverrideAllowed()
	local sv = SandboxVars and SandboxVars.VFluidLib
	return (sv and sv.ServiceOverride) == true
end

function VFluid.vanillaRules()
	local sv = SandboxVars and SandboxVars.VFluidLib
	return (sv and sv.VanillaRules) == true
end

function VFluid.tankCleaningLevel()
	local sv = SandboxVars and SandboxVars.VFluidLib
	local n = sv and tonumber(sv.TankCleaning) or nil
	if not n or n < VFluid.CLEAN_OFF or n > VFluid.CLEAN_ALL then return VFluid.CLEAN_ALL end
	return n
end

VFluid.SYNC_MS = 100
VFluid.SYNC_SLICES = 60
VFluid.SYNC_MAX_MS = 250

function VFluid.holdsOnlyWater(vehicle, part, axis)
	if not part or not axis or axis.kind ~= "fluid" then return false end
	local led = VFluid.rawLedger and VFluid.rawLedger(part)
	if not led then return false end
	local any = false
	for name, q in pairs(led) do
		if q and q > 0 then
			any = true
			local f = Fluid and Fluid.Get and Fluid.Get(name)
			local watery = f and FluidCategory and f.isCategory
				and f:isCategory(FluidCategory.Water)
			if not watery then return false end
		end
	end
	return any
end

function VFluid.drinkWashMenuEnabled()
	local opt = VFluid.options and VFluid.options.drinkWashMenu
	if not opt or not opt.getValue then return true end
	local ok, v = pcall(function() return opt:getValue() end)
	if not ok then return true end
	return v ~= false
end

function VFluid.taintedWaterWarned()
	if not getSandboxOptions then return true end
	local ok, v = pcall(function()
		local o = getSandboxOptions():getOptionByName("EnableTaintedWaterText")
		return o and o:getValue()
	end)
	if not ok then return true end
	return v == true
end

function VFluid.drinkHarmfulAllowed()
	local sv = SandboxVars and SandboxVars.VFluidLib
	return sv ~= nil and sv.DrinkHarmful == true
end

function VFluid.axisIsDrinkable(axis)
	if not axis or axis.kind ~= "fluid" then return false end
	local cats = axis.accept and axis.accept.categories
	if not cats or #cats == 0 then return false end
	for i = 1, #cats do
		if cats[i] == "Water" or cats[i] == "Beverage" then return true end
	end
	return false
end

function VFluid.canDrink(vehicle, part, axis)
	axis = axis or VFluid.axisFor(vehicle, part)
	if not axis then return false, "not a tank" end
	if axis.kind ~= "fluid" then return false, "not drinkable" end
	if not VFluid.axisIsDrinkable(axis) then return false, "not drinkable" end
	local amount = VFluid.amount(part)
	if not amount or amount <= 0 then return false, "empty" end
	if VFluid.drinkHarmfulAllowed() then return true end
	local led = VFluid.ledger(vehicle, part, axis)
	for name, amt in pairs(led or {}) do
		local isVariant = axis.variantOf and axis.variantOf[name] ~= nil
		if (amt or 0) > 0 and VFluid.isHarmfulFluid(name) then
			if isVariant then
				if VFluid.taintedWaterWarned() then return false, "tainted" end
			else
				return false, "unsafe to drink"
			end
		end
	end
	return true
end

function VFluid.describe(vehicle)
	local out = { tanks = {}, mounted = {}, supply = nil, consumers = {} }
	if not vehicle then return out end
	out.consumers = VFluid.consumptionRows(vehicle)
	out.consumerBlocks = VFluid.consumptionBlocks(vehicle)
	local script = vehicle:getScript()
	out.vehicle = script and script:getName() or "?"

	local eps = VFluid.vehicleEndpoints(vehicle)
	for i = 1, #eps do
		local ep = eps[i]
		local amount, cap = ep.get(), ep.cap()
		local partId = ep.part and ep.part:getId() or tostring(ep.label)
		local row = {
			part = partId,
			label = VFluid.partLabel(partId),
			axis = ep.axis and ep.axis.id or nil,
			litres = (ep.axis and ep.axis.kind == "fluid") or false,
			amount = amount, capacity = cap, pct = pctOf(amount, cap),
		}
		if ep.kind ~= "tank" and ep.axis then
			if ep.axis.kind == "fluid" then
				row.contents = VFluid.contentsLabel(vehicle, ep.part, ep.axis)
					or VFluid.axisLabel(ep.axis)
			else
				row.tipName = VFluid.axisLabel(ep.axis)
			end
		end
		if ep.kind == "tank" then
			row.mixture = VFluid.mixtureOf(vehicle, ep.part, ep.axis)
			if ep.axis and ep.axis.kind ~= "fluid" then
				row.tipName = VFluid.axisLabel(ep.axis)
			end
			row.tainted = VFluid.isTaintedTank(vehicle, ep.part, ep.axis)
			row.empty = (amount or 0) <= 0
			row.drinkable = (VFluid.canDrink(vehicle, ep.part, ep.axis)) == true
			if VFluid.designationOf and not VFluid.vanillaRules() then
				local d = VFluid.designationOf(vehicle, ep.part, ep.axis)
				if d then
					row.mode       = d.mode
					row.designated = d.fluid
					row.locked     = d.locked == true
					row.residue    = d.residue == true
					row.fixed      = d.fixed == true
					row.userLocked = d.userLocked == true
				end
			end
			out.tanks[#out.tanks + 1] = row
		elseif ep.kind == "mounted" then
			out.mounted[#out.mounted + 1] = row
		elseif ep.kind == "supply" then
			out.supply = row
		end
	end
	table.sort(out.tanks, function(a, b) return a.part < b.part end)
	table.sort(out.mounted, function(a, b) return a.part < b.part end)
	return out
end

--------------------------------------------------------------------------------
-- Diagnostics: the invariant as one pass/fail
--------------------------------------------------------------------------------

function VFluid.auditVehicle(vehicle)
	local out = {}
	local list = VFluid.tanksOn(vehicle)
	for i = 1, #list do
		local part, axis = list[i].part, list[i].axis
		local amount = VFluid.amount(part)
		local row = { part = part:getId(), axis = axis.id, amount = amount, kind = axis.kind }
		if axis.kind == "fluid" then
			local fluids = VFluid.ledger(vehicle, part, axis)
			local total = sumOf(fluids)
			row.ledgerTotal = total
			row.drift = amount - total
			row.ok = (row.drift <= EPS and row.drift >= -EPS)
		else
			row.ok = true
		end
		out[#out + 1] = row
	end
	return out
end

--------------------------------------------------------------------------------
-- one interface over every endpoint a transfer can touch.
--------------------------------------------------------------------------------

local WELL_BAND = 9999

function VFluid.axisFluids(axis)
	local out = {}
	if not axis or not Fluid or not Fluid.getAllFluids then return out end
	local ok, all = pcall(function() return Fluid.getAllFluids() end)
	if not ok or not all or not all.size then return out end
	for i = 0, all:size() - 1 do
		local f = all:get(i)
		if f and VFluid.axisAdmits(axis, f) then
			local okn, nm = pcall(function() return f:getFluidTypeString() end)
			if okn and nm and nm ~= "" then out[#out + 1] = nm end
		end
	end
	table.sort(out)
	return out
end

fluidByName = function(name)
	if not name or not Fluid or not Fluid.Get then return nil end
	return Fluid.Get(name)
end

local function containerAccepts(fc, item, axis, fluidName)
	local f = fluidByName(fluidName)
	if not f then return false, "unknown fluid" end
	if fc:isFull() then return false, "full" end
	if fc.isInputLocked and fc:isInputLocked() then return false, "input locked" end
	if not fc:canAddFluid(f) then return false, "container refuses this fluid" end
	if item and item.canStoreWater and (fluidName == "Water" or fluidName == "TaintedWater") then
		if not item:canStoreWater() then return false, "item cannot store water" end
	end
	return true
end

--------------------------------------------------------------------------------
-- kind: tank - a registered cargo tank. Ledger-backed, mirror-invariant bound.
--------------------------------------------------------------------------------
function VFluid.applyLevel(vehicle, part, axis, n, fluidName, shares)
	local before = VFluid.amount(part) or 0
	local cap = (part.getContainerCapacity and part:getContainerCapacity()) or 0
	local after = n
	if after < 0 then after = 0 end
	if after > cap then after = cap end

	if not axis or axis.kind ~= "fluid" then
		return VFluid.setAmount(vehicle, part, after)
	end

	local delta = after - before
	if delta > 0 then
		local fluids = VFluid.ledger(vehicle, part, axis) or {}
		local credited = creditArrival(fluids, delta, axis, fluidName, shares)
		if credited then
			VFluid.setLedger(vehicle, part, fluids)
			local n = 0
			for _, q in pairs(fluids) do if q and q > 0 then n = n + 1 end end
			if n > 1 and VFluid.markResidue then VFluid.markResidue(vehicle, part, axis) end
			if VFluid.reconcileService then VFluid.reconcileService(vehicle, part, axis) end
			return after
		end
		return VFluid.setAmount(vehicle, part, after)
	end

	local written = VFluid.setAmount(vehicle, part, after)
	if delta < 0 then VFluid.ledger(vehicle, part, axis) end
	return written
end

local function tankEndpoint(vehicle, part, axis)
	return {
		kind = "tank", label = part:getId(), axis = axis, vehicle = vehicle, part = part,
		mixture = function() return VFluid.mixtureShares(vehicle, part, axis) end,
		get  = function() return VFluid.amount(part) end,
		cap  = function() return part:getContainerCapacity() or 0 end,
		free = function() return (part:getContainerCapacity() or 0) - VFluid.amount(part) end,
		canAccept = function(fluidName)
			if axis.kind == "unit" then
				if fluidName == nil or fluidName == axis.id then return true end
				return false, "this tank holds " .. axis.id .. ", not a fluid"
			end
			local f = fluidByName(fluidName)
			if not f then return false, "unknown fluid" end
			local unlocked = false
			if VFluid.designationOf then
				unlocked = VFluid.designationOf(vehicle, part, axis).userLocked == false
			end
			if VFluid.vanillaRules and VFluid.vanillaRules() then
				if not VFluid.axisAdmits(axis, f) then
					return false, "this tank is for " .. tostring(VFluid.axisLabel(axis) or "something else")
				end
				local function baseOf(n)
					return (axis.variantOf and axis.variantOf[n]) or n
				end
				local want = baseOf(fluidName)
				local led = VFluid.ledger(vehicle, part, axis) or {}
				for name, amt in pairs(led) do
					if amt and amt > 0 and baseOf(name) ~= want then
						return false, "this tank already holds "
							.. tostring(select(1, fluidFace(name))) .. ", and fluids do not mix"
					end
				end
			elseif unlocked then
				if not VFluid.serviceOverrideAllowed() then
					if not VFluid.serviceAfterAdding(vehicle, part, axis, fluidName) then
						return false, "nothing carries this together with what is already in there"
					end
				end
			elseif not VFluid.axisAdmits(axis, f) then
				return false, "the service refuses this fluid"
			end
			if not unlocked and VFluid.designationAdmits then
				local okD, whyD = VFluid.designationAdmits(vehicle, part, axis, fluidName)
				if okD == false then return false, whyD end
			end
			if VFluid.designationOf then
				local dc = VFluid.designationOf(vehicle, part, axis)
				if dc.unserviceable
						and not (dc.userLocked == false and VFluid.serviceOverrideAllowed()) then
					return false, "this tank is compromised - clean it before adding anything"
				end
			end
			local fluids = VFluid.ledger(vehicle, part, axis)
			local need = 0
			for _, amt in pairs(fluids or {}) do if amt and amt > 0 then need = need + amt end end
			local cap = part:getContainerCapacity() or 0
			local fc = VFluid.rent(need > cap and need or cap)
			if not fc then return true end
			local _, unadded = VFluid.fill(fc, fluids)
			if unadded then
				VFluid.release(fc)
				local name = VFluid.unrepresentable(unadded)
				return false, "this tank holds something that cannot be identified ("
					.. tostring(name) .. ")"
			end
			local ok = fc:canAddFluid(f)
			VFluid.release(fc)
			if not ok then return false, "will not blend with the current contents" end
			return true
		end,
		set  = function(n, fluidName, shares)
			return VFluid.applyLevel(vehicle, part, axis, n, fluidName, shares)
		end,
		sync = function() if vehicle then vehicle:transmitPartModData(part) end end,
	}
end

--------------------------------------------------------------------------------
-- kind: engine - the GasTank part that feeds an engine. Never a registered tank.
--------------------------------------------------------------------------------
local function supplyEndpoint(vehicle, part)
	return {
		kind = "supply", label = part:getId(), vehicle = vehicle, part = part,
		get  = function() return part:getContainerContentAmount() end,
		cap  = function() return part:getContainerCapacity() or 0 end,
		free = function() return (part:getContainerCapacity() or 0) - part:getContainerContentAmount() end,
		canAccept = function(fluidName)
			if fluidName ~= "Petrol" then return false, "an engine tank takes fuel only" end
			if vehicle and vehicle:isEngineStarted() then return false, "engine running" end
			return true
		end,
		set  = function(n) part:setContainerContentAmount(n)
			if vehicle then vehicle:transmitPartModData(part) end return n end,
		sync = function() if vehicle then vehicle:transmitPartModData(part) end end,
	}
end

--------------------------------------------------------------------------------
-- kind: item / world / pump - anything carrying a native FluidContainer.
--------------------------------------------------------------------------------
local function fluidContainerEndpoint(kind, holder, fc, axis, label, sourceOnly)
	return {
		kind = kind, label = label, axis = axis, holder = holder, fc = fc,
		mixture = function()
			local okRB, back = pcall(VFluid.readBack, fc)
			if not okRB or not back then return nil end
			local total = 0
			for _, amt in pairs(back) do if amt and amt > 0 then total = total + amt end end
			if total <= 0 then return nil end
			local out = {}
			for name, amt in pairs(back) do
				if amt and amt > 0 then out[name] = amt / total end
			end
			return out
		end,
		sourceOnly = sourceOnly or nil,
		get  = function() return fc:getAmount() end,
		cap  = function() return fc:getCapacity() end,
		free = function() return fc:getFreeCapacity() end,
		canAccept = function(fluidName)
			if sourceOnly then return false, "this is a supply, not a container" end
			return containerAccepts(fc, kind == "item" and holder or nil, axis, fluidName)
		end,
		set  = function(n, fluidName, shares)
			local cur = fc:getAmount()
			local delta = n - cur
			if delta > 0 then
				if shares then
					local any = false
					for name, share in pairs(shares) do
						local f = share and share > 0 and fluidByName(name)
						if f then fc:addFluid(f, delta * share); any = true end
					end
					if any then return fc:getAmount() end
				end
				local f = fluidName and fluidByName(fluidName) or fc:getPrimaryFluid()
				if not f then return cur end
				fc:addFluid(f, delta)
			elseif delta < 0 then
				if n <= 0.0005 and fc.Empty then
					fc:Empty()
				else
					fc:removeFluid(-delta)
					if fc:getAmount() < 0 and fc.Empty then fc:Empty() end
				end
			end
			return fc:getAmount()
		end,
		sync = function()
			if kind == "item" and holder and holder.syncItemFields then holder:syncItemFields() end
			if kind ~= "item" and holder and holder.syncFluidContainerSend then holder:sync() end
		end,
	}
end

--------------------------------------------------------------------------------
-- kind: drainable - propane bottle, lantern canister, blowtorch. No engine Fluid exists for
-- these; they count uses.
--------------------------------------------------------------------------------
VFluid.unitsWhenFull = VFluid.unitsWhenFull or {}

VFluid.unitsAxis = VFluid.unitsAxis or {}

-- Devices are served by their own menu row, never offered as a generic vessel to fill or empty.
VFluid.unitsDevice = VFluid.unitsDevice or {}

function VFluid.registerUnits(fullType, value, axisId, opts)
	if type(fullType) ~= "string" then return false end
	if type(value) ~= "number" and type(value) ~= "function" then return false end
	VFluid.unitsWhenFull[fullType] = value
	if axisId then VFluid.unitsAxis[fullType] = axisId end
	VFluid.unitsDevice[fullType] = (type(opts) == "table" and opts.device == true) or nil
	return true
end

function VFluid.isUnitDevice(item)
	if not item or not item.getFullType then return false end
	return VFluid.unitsDevice[item:getFullType()] == true
end

VFluid.registerUnits("Base.PropaneTank", 80, "propane")

local TORCH_UNITS_PER_USE_FALLBACK = 1.12

local function bottleUsesPerUnit()
	local sm = getScriptManager and getScriptManager()
	local script = sm and sm.getItem and sm:getItem("Base.PropaneTank")
	local mu = script and script.getMaxUses and script:getMaxUses()
	local units = VFluid.unitsWhenFull["Base.PropaneTank"]
	if type(mu) == "number" and mu > 0 and type(units) == "number" and units > 0 then
		return mu / units
	end
	return nil
end

VFluid.registerUnits("Base.BlowTorch", function(item)
	local m = item and item.getMaxUses and item:getMaxUses() or 0
	if m <= 0 then return nil end
	local spend = ZomboidGlobals and ZomboidGlobals.refillBlowtorchPropaneAmount
	local perUnit = bottleUsesPerUnit()
	if type(spend) == "number" and spend > 0 and perUnit then
		return m * (spend / perUnit)
	end
	return m * TORCH_UNITS_PER_USE_FALLBACK
end, "propane", { device = true })

local function unitsFull(item)
	local ft = item:getFullType()
	local entry = VFluid.unitsWhenFull[ft]
	if type(entry) == "function" then return entry(item) end
	if type(entry) == "number" then return entry end
	return nil
end

local function drainableEndpoint(item, axis)
	local ownAxis = VFluid.unitsAxis[item:getFullType()]
	if ownAxis and VFluid.axes[ownAxis] then axis = VFluid.axes[ownAxis] end
	local full = unitsFull(item)
	if not full or full <= 0 then return nil end
	local maxUses = item:getMaxUses()
	if not maxUses or maxUses <= 0 then return nil end
	local perUse = full / maxUses
	return {
		-- Uses are integers in the engine, so perUse is the smallest amount this vessel can hold.
		-- Transfers snap to it; without that the sub-use remainder is lost on every write.
		kind = "drainable", label = item:getName(), axis = axis, holder = item, quantum = perUse,
		get  = function() return item:getCurrentUses() * perUse end,
		cap  = function() return full end,
		free = function() return full - (item:getCurrentUses() * perUse) end,
		canAccept = function() return item:getCurrentUses() < maxUses, "full" end,
		set  = function(n)
			local uses = math.floor((n / perUse) + 0.5)
			if uses < 0 then uses = 0 end
			if uses > maxUses then uses = maxUses end
			item:setCurrentUses(uses)
			return uses * perUse
		end,
		sync = function() if item.syncItemFields then item:syncItemFields() end end,
	}
end

--------------------------------------------------------------------------------
-- Resolution
--------------------------------------------------------------------------------

local function pipedFuelEndpoint(obj, axis)
	local amount = obj:getPipedFuelAmount()
	if not amount or amount <= 0 then return nil end
	return {
		kind = "pump", supplyKind = "gaspump",
		label = "fuel pump", axis = axis, holder = obj, sourceOnly = true,
		get  = function() return obj:getPipedFuelAmount() end,
		cap  = function() return obj:getPipedFuelAmount() end,
		free = function() return 0 end,
		canAccept = function() return false, "this is a supply, not a container" end,
		set  = function(n) obj:setPipedFuelAmount(math.floor(n + 0.5)) return obj:getPipedFuelAmount() end,
		sync = function() end,
	}
end

function VFluid.axisTakesWater(axis)
	if not axis or axis.kind ~= "fluid" then return false end
	local cats = axis.accept and axis.accept.categories
	if not cats or #cats == 0 then return true end
	for i = 1, #cats do if cats[i] == "Water" then return true end end
	return false
end

function VFluid.isOpenWaterSquare(square)
	if not square or not square.getProperties then return false end
	if not IsoFlagType then return false end
	local ok, has = pcall(function()
		local props = square:getProperties()
		if not props then return false end
		if props:has(IsoFlagType.water) then return true end
		return IsoFlagType.taintedWater ~= nil and props:has(IsoFlagType.taintedWater)
	end)
	return ok and has == true
end

function VFluid.naturalWaterEndpoint(square, axis)
	if not square or not VFluid.axisTakesWater(axis) then return nil end
	if not VFluid.isOpenWaterSquare(square) then return nil end
	return {
		kind = "pump", supplyKind = "water", label = "open water",
		supplyRank = 30,
		axis = axis, holder = square, sourceOnly = true, needsSuction = true, endless = true,
		needsPower = false,
		get  = function() return math.huge end,
		cap  = function() return math.huge end,
		free = function() return 0 end,
		canAccept = function() return false, "this is a supply, not a container" end,
		set  = function() return math.huge end,
		sync = function() end,
	}
end

function VFluid.supplyKindOf(axis, sourceOnly, containerName)
	if not sourceOnly then return nil end
	if axis and axis.id == "fuel" then return "gaspump" end
	if containerName == "Well" then return "well" end
	return "water"
end

function VFluid.supplyAt(x, y, z, axis, playerObj)
	if not x or not y then return nil end
	local cell = getWorld and getWorld() and getWorld():getCell()
	if not cell then return nil end
	local sq = cell:getGridSquare(x, y, z or 0)
	if not sq then return nil end
	local wet = VFluid.naturalWaterEndpoint(sq, axis)
	if wet then return wet end
	local objs = sq:getObjects()
	for i = 0, (objs and objs:size() or 0) - 1 do
		local ep = VFluid.worldEndpoint(objs:get(i), axis, playerObj)
		if ep and ep.sourceOnly then return ep end
	end
	return nil
end

--------------------------------------------------------------------------------
-- Applying a transfer slice from a description rather than from an endpoint pair.
--------------------------------------------------------------------------------
function VFluid.encodeShares(shares)
	if not shares then return nil end
	local parts = {}
	for name, share in pairs(shares) do
		if share and share > 0 then
			parts[#parts + 1] = tostring(name) .. "=" .. string.format("%.6f", share)
		end
	end
	if #parts == 0 then return nil end
	table.sort(parts)
	return table.concat(parts, ";")
end

function VFluid.decodeShares(str)
	if type(str) ~= "string" or str == "" then return nil end
	local out, any = {}, false
	for pair in string.gmatch(str, "[^;]+") do
		local name, val = string.match(pair, "^(.-)=([%d%.]+)$")
		local n = val and tonumber(val)
		if name and n and n > 0 then out[name] = n; any = true end
	end
	return any and out or nil
end

function VFluid.resolveEndpoint(spec, axis, playerObj)
	if not spec or not spec.kind then return nil end
	if spec.kind == "vpart" then
		local v = getVehicleById and getVehicleById(spec.vehicle)
		local part = v and v:getPartById(spec.part)
		if not part then return nil end
		local eps = VFluid.vehicleEndpoints(v)
		for i = 1, #eps do
			if eps[i].part and eps[i].part:getId() == spec.part then return eps[i] end
		end
		return VFluid.transferEndpointFor(v, part)
	elseif spec.kind == "supply" then
		return VFluid.supplyAt(spec.x, spec.y, spec.z, axis, playerObj)
	elseif spec.kind == "item" then
		local inv = playerObj and playerObj:getInventory()
		local it = inv and spec.item and inv:getItemById(spec.item)
		if not it then return nil end
		return VFluid.itemEndpoint(it, axis)
	elseif spec.kind == "ground" then
		return VFluid.voidEndpoint(axis)
	elseif spec.kind == "mouth" then
		return VFluid.mouthEndpoint(playerObj, axis)
	end
	return nil
end

function VFluid.applyMove(playerObj, srcSpec, dstSpec, amount, fluidName, shares)
	if not amount or amount <= 0 then return 0 end
	local axis = nil
	for _, spec in ipairs({ srcSpec, dstSpec }) do
		if spec and spec.kind == "vpart" then
			local v = getVehicleById and getVehicleById(spec.vehicle)
			local part = v and v:getPartById(spec.part)
			if part then axis = VFluid.axisFor(v, part) end
			if axis then break end
		end
	end
	if not axis then return 0 end

	local src = VFluid.resolveEndpoint(srcSpec, axis, playerObj)
	local dst = VFluid.resolveEndpoint(dstSpec, axis, playerObj)
	if not src or not dst then return 0 end

	if dstSpec and dstSpec.kind == "vpart" and VFluid.designationAdmits then
		local v = getVehicleById and getVehicleById(dstSpec.vehicle)
		local part = v and v:getPartById(dstSpec.part)
		if part then
			local okD = VFluid.designationAdmits(v, part, axis, fluidName)
			if okD == false then return 0 end
			if shares then
				for fname, share in pairs(shares) do
					if share and share > 0 and VFluid.designationAdmits(v, part, axis, fname) == false then
						return 0
					end
				end
			end
		end
	end

	local moved = math.min(amount, src.get(), dst.free())
	moved = VFluid.snapToQuantum(moved, VFluid.transferQuantum(src, dst))
	if moved <= 0 then return 0 end
	-- Destination first, then debit exactly what it took: a quantised vessel may store less than
	-- it was handed, and the difference must stay in the source rather than vanish. A sink
	-- (ground, mouth) has no level to read back: it took what it was handed.
	local before = dst.get()
	dst.set(before + moved, fluidName, shares)
	local applied = dst.sinkOnly and moved or (dst.get() - before)
	if applied <= 0 then return 0 end
	src.set(src.get() - applied)
	if src.sync then src.sync() end
	if dst.sync then dst.sync() end
	return applied
end

function VFluid.bestSupplyNear(playerObj, axis, range)
	if not playerObj or not axis then return nil end
	local cell = getWorld and getWorld() and getWorld():getCell()
	if not cell then return nil end
	range = range or 6
	local px = math.floor(playerObj:getX())
	local py = math.floor(playerObj:getY())
	local pz = math.floor(playerObj:getZ())
	local best = nil
	for dx = -range, range do
		for dy = -range, range do
			local ep = VFluid.supplyAt(px + dx, py + dy, pz, axis, playerObj)
			if ep and ep.get() > 0 then
				local r = ep.supplyRank or 0
				local br = best and (best.supplyRank or 0) or -1
				if not best or r > br or (r == br and ep.get() > best.get()) then best = ep end
			end
		end
	end
	return best
end

function VFluid.worldEndpoint(obj, axis, playerObj)
	if not obj then return nil end
	if obj.hasModData and obj:hasModData() and obj:getModData().LGEPGhost == true then return nil end
	if VFluid.isHydrant and VFluid.isHydrant(obj) then
		return VFluid.hydrantEndpoint(obj, axis, playerObj)
	end
	if obj.getPipedFuelAmount then
		local ep = pipedFuelEndpoint(obj, axis)
		if ep then return ep end
	end
	if not obj.getFluidContainer then return nil end
	local fc = obj:getFluidContainer()
	if not fc then return nil end
	local cap = fc:getCapacity()
	if not cap or cap <= 0 then return nil end
	if fc.canPlayerEmpty and not fc:canPlayerEmpty() then return nil end
	local sourceOnly = cap >= WELL_BAND or nil
	local kind = sourceOnly and "pump" or "world"
	local ep = fluidContainerEndpoint(kind, obj, fc, axis, fc:getContainerName() or "container", sourceOnly)
	ep.needsSuction = (sourceOnly and axis and axis.id ~= "fuel") or nil
	ep.supplyKind = VFluid.supplyKindOf(axis, sourceOnly, fc:getContainerName())
	return ep
end

function VFluid.itemEndpoint(item, axis)
	if not item then return nil end
	if axis and axis.kind == "unit" then
		if item.getMaxUses and item.getCurrentUses then return drainableEndpoint(item, axis) end
		return nil
	end
	if item.getFluidContainer then
		local fc = item:getFluidContainer()
		if fc and fc:getCapacity() > 0 then
			return fluidContainerEndpoint("item", item, fc, axis, item:getName())
		end
	end
	if item.getMaxUses and item.getCurrentUses then return drainableEndpoint(item, axis) end
	return nil
end

--------------------------------------------------------------------------------
-- kind: void - the ground. A sink that accepts anything and keeps nothing.
--------------------------------------------------------------------------------
function VFluid.transferEndpointFor(vehicle, part)
	if not vehicle or not part then return nil end
	local eps = VFluid.vehicleEndpoints(vehicle)
	for i = 1, #eps do
		local ep = eps[i]
		if ep.part == part then
			if ep.kind == "tank" then return ep end
			if ep.kind == "mounted" and VFluid.mountedActive(ep) then return ep end
		end
	end
	return nil
end

-- Which tank supplies a device on this vehicle, and the ranked alternatives behind it.
-- Least content first, so a nearly-spent vessel is emptied and retired before a full one is opened.
-- canTransfer already refuses a source too small for one whole charge, so a tank left holding an
-- unusable remnant drops out and the next attempt defaults to the tank behind it.
function VFluid.deviceSupplyFor(vehicle, axis, deviceEp)
	local out = {}
	if not vehicle or not axis or not deviceEp then return nil, out end
	local eps = VFluid.vehicleEndpoints(vehicle)
	for i = 1, #eps do
		local ep = eps[i]
		local usable = (ep.kind == "tank") or (ep.kind == "mounted" and VFluid.mountedActive(ep))
		if usable and ep.axis and ep.axis.id == axis.id and ep ~= deviceEp then
			if VFluid.canTransfer(ep, deviceEp, axis.id) then
				out[#out + 1] = { ep = ep, part = ep.part,
					label = ep.label or (ep.part and ep.part.getId and ep.part:getId()) or "?",
					held = ep.get() }
			end
		end
	end
	table.sort(out, function(a, b)
		if a.held ~= b.held then return a.held < b.held end
		return tostring(a.label) < tostring(b.label)
	end)
	return out[1], out
end

function VFluid.voidEndpoint(axis)
	if axis and axis.kind == "unit" then return nil end
	return {
		kind = "void", label = "ground", axis = axis, sinkOnly = true,
		get  = function() return 0 end,
		cap  = function() return math.huge end,
		free = function() return math.huge end,
		canAccept = function() return true end,
		set  = function() return 0 end,
		sync = function() end,
	}
end

--------------------------------------------------------------------------------
-- that reports the character's THIRST as its free capacity.
--------------------------------------------------------------------------------
VFluid._shareCache = VFluid._shareCache or {}

function VFluid.mixtureShares(vehicle, part, axis)
	axis = axis or VFluid.axisFor(vehicle, part)
	if not axis or axis.kind ~= "fluid" then return nil end
	local key = tostring(part.getId and part:getId() or part)
		.. "@" .. tostring(vehicle and vehicle.getId and vehicle:getId() or "?")
	local amount = VFluid.amount(part)
	local hit = VFluid._shareCache[key]
	if hit and hit.rev == (VFluid._ledgerRev or 0) and hit.amount == amount then
		return hit.shares
	end
	local led = VFluid.ledger(vehicle, part, axis)
	if not led then return nil end
	local total, any = 0, false
	for _, amt in pairs(led) do if amt and amt > 0 then total = total + amt; any = true end end
	if not any or total <= 0 then return nil end
	local out = {}
	for name, amt in pairs(led) do
		if amt and amt > 0 then out[name] = amt / total end
	end
	VFluid._shareCache[key] = { rev = VFluid._ledgerRev or 0, amount = amount, shares = out }
	return out
end

function VFluid.blendedFluidCount(into, adding)
	local seen, n = {}, 0
	for _, t in ipairs({ into or {}, adding or {} }) do
		for name, amt in pairs(t) do
			if amt and amt > 0 and not seen[name] then seen[name] = true; n = n + 1 end
		end
	end
	return n
end

VFluid.MAX_FLUIDS = 8

function VFluid.mouthEndpoint(character, axis, mixtureOf)
	if not character then return nil end
	if axis and axis.kind ~= "fluid" then return nil end
	local function thirstUnits()
		if not character.getStats then return 0 end
		local ok, n = pcall(function()
			return character:getStats():get(CharacterStat.THIRST)
		end)
		if not ok or not n then return 0 end
		return math.max(0, n * 2)
	end
	return {
		kind = "mouth", label = "drink", axis = axis, sinkOnly = true,
		get  = function() return 0 end,
		cap  = thirstUnits,
		free = thirstUnits,
		canAccept = function() return true end,
		set  = function(n, fluidName)
			if not n or n <= 0 then return 0 end
			if not FluidContainer or not FluidContainer.CreateContainer then return 0 end

			local list, total = {}, 0
			if mixtureOf then
				local m = mixtureOf()
				if m then
					for name, amt in pairs(m) do
						if amt and amt > 0 and fluidByName(name) then
							list[#list + 1] = { name = name, amt = amt }
						end
					end
				end
			end
			if #list == 0 then
				if not (fluidName and fluidByName(fluidName)) then return 0 end
				list[1] = { name = fluidName, amt = 1 }
			end

			table.sort(list, function(a, b)
				if a.amt ~= b.amt then return a.amt > b.amt end
				return a.name < b.name
			end)
			while #list > VFluid.MAX_FLUIDS do table.remove(list) end
			for i = 1, #list do total = total + list[i].amt end
			if total <= 0 then return 0 end

			local fc = FluidContainer.CreateContainer()
			fc:setCapacity(n + 1)
			for i = 1, #list do
				local f = fluidByName(list[i].name)
				if f then fc:addFluid(f, n * (list[i].amt / total)) end
			end
			character:DrinkFluid(fc, 1)
			FluidContainer.DisposeContainer(fc)
			return 0
		end,
		sync = function() end,
	}
end

--------------------------------------------------------------------------------
-- kind: mounted - vessels carried on the vehicle
--------------------------------------------------------------------------------
function VFluid.mountedHandContainersEnabled()
	local sv = SandboxVars and SandboxVars.VFluidLib
	return sv ~= nil and sv.MountedHandContainers == true
end

VFluid.mountedAxes = VFluid.mountedAxes or { propane = true }

VFluid.mountedParts = VFluid.mountedParts or {}

function VFluid.registerMounted(vehicleScript, partId)
	if type(vehicleScript) ~= "string" or vehicleScript == "" then
		log("registerMounted: needs (vehicleScript, partId|{partIds})"); return false
	end
	if type(partId) == "table" then
		local ok = #partId > 0
		for i = 1, #partId do ok = VFluid.registerMounted(vehicleScript, partId[i]) and ok end
		return ok
	end
	if type(partId) ~= "string" or partId == "" then
		log("registerMounted: needs (vehicleScript, partId|{partIds})"); return false
	end
	VFluid.mountedParts[vehicleScript .. "\0" .. partId] = true
	return true
end

function VFluid.unregisterMounted(vehicleScript, partId)
	local k = tostring(vehicleScript) .. "\0" .. tostring(partId)
	if not VFluid.mountedParts[k] then return false end
	VFluid.mountedParts[k] = nil
	return true
end

function VFluid.mountedActive(ep)
	return ep ~= nil and (ep.byDefault == true
		or (ep.registered == true and VFluid.mountedHandContainersEnabled()))
end

local function mountedRegistered(vehicle, part)
	local script = vehicle and vehicle.getScript and vehicle:getScript()
	local name = script and script.getName and script:getName()
	local id = part and part.getId and part:getId()
	return name ~= nil and id ~= nil
		and VFluid.mountedParts[name .. "\0" .. id] == true
end

local function mountedByDefault(ep)
	local id = ep and ep.axis and ep.axis.id
	return id ~= nil and VFluid.mountedAxes[id] == true
end

local function mountedEndpoint(vehicle, part, item)
	local ep = VFluid.itemEndpoint(item, nil)
	if not ep then return nil end
	ep.byDefault = mountedByDefault(ep)
	ep.registered = mountedRegistered(vehicle, part)
	ep.kind    = "mounted"
	ep.vehicle = vehicle
	ep.part    = part
	ep.label   = part:getId()
	ep.sync = function()
		if not vehicle then return end
		pcall(function() vehicle:transmitPartItem(part) end)
		pcall(function() vehicle:transmitPartUsedDelta(part) end)
	end
	return ep
end

function VFluid.vehicleEndpoints(vehicle)
	local out = {}
	if not vehicle then return out end
	local tanks = VFluid.tanksOn(vehicle)
	for i = 1, #tanks do
		out[#out + 1] = tankEndpoint(vehicle, tanks[i].part, tanks[i].axis)
	end
	local gas = vehicle:getPartById(ENGINE_TANK_PART)
	if gas and VFluid.isSupplyTank(vehicle, gas) then
		out[#out + 1] = supplyEndpoint(vehicle, gas)
	end
	for i = 0, vehicle:getPartCount() - 1 do
		local part = vehicle:getPartByIndex(i)
		if part and not part:isContainer() then
			local item = part:getInventoryItem()
			if item then
				local ep = mountedEndpoint(vehicle, part, item)
				if ep and VFluid.mountedActive(ep) then
					out[#out + 1] = ep
				end
			end
		end
	end
	return out
end

--------------------------------------------------------------------------------
-- Pairing: which endpoint may hand to which.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- The intake gate: a tank may be required to carry a working pump before it can draw.
--------------------------------------------------------------------------------

VFluid.PUMP_PART_DEFAULT = "VFluidPump"

local function declaredPump(vehicle, axis)
	local cfg = VFluid.getConfig(vehicle)
	if cfg and cfg.requiresPump ~= nil then
		if cfg.requiresPump == false then return nil end
		return cfg.requiresPump
	end
	return axis and axis.requiresPump or nil
end

function VFluid.pumpsEnabled()
	local sv = SandboxVars and SandboxVars.VFluidLib
	return sv ~= nil and sv.PumpsEnabled == true
end

function VFluid.pumpIdFor(vehicle, axis)
	if not VFluid.pumpsEnabled() then return nil end
	return declaredPump(vehicle, axis)
end

VFluid.pumpParts = VFluid.pumpParts or {}
VFluid.pumpPartOrder = VFluid.pumpPartOrder or {}

function VFluid.registerPumpPart(partId)
	if type(partId) ~= "string" or partId == "" then
		log("registerPumpPart: needs a part id"); return false
	end
	if not VFluid.pumpParts[partId] then
		VFluid.pumpPartOrder[#VFluid.pumpPartOrder + 1] = partId
	end
	VFluid.pumpParts[partId] = true
	return true
end

VFluid.registerPumpPart(VFluid.PUMP_PART_DEFAULT)

function VFluid.pumpPartFor(vehicle, axis)
	local cfg = VFluid.getConfig(vehicle)
	if cfg and type(cfg.pumpPart) == "string" then return cfg.pumpPart end
	local declared = declaredPump(vehicle, axis)
	if declared then return declared end
	for i = 1, #VFluid.pumpPartOrder do
		local id = VFluid.pumpPartOrder[i]
		if vehicle and vehicle.getPartById and vehicle:getPartById(id) then return id end
	end
	return nil
end

function VFluid.functionalPump(vehicle, partId)
	if not vehicle or not partId then return nil end
	local pump = vehicle:getPartById(partId)
	if not pump then return nil end
	if (pump:getCondition() or 0) <= 0 then return nil end
	local types = pump.getItemType and pump:getItemType()
	local takesItem = types ~= nil and not types:isEmpty()
	if takesItem and not pump:getInventoryItem() then return nil end
	return pump
end

VFluid.PUMP_SPEED_DEFAULT = 2.0
VFluid.pumpRates = VFluid.pumpRates or {}

function VFluid.registerPumpRate(fullType, multiplier)
	if type(fullType) ~= "string" or type(multiplier) ~= "number" then return false end
	if multiplier < 1 then return false end
	VFluid.pumpRates[fullType] = multiplier
	return true
end

function VFluid.pumpSpeed(from, to)
	if not VFluid.pumpsEnabled() then return 1.0 end
	local vehicle = to and to.vehicle
	if not vehicle then return 1.0 end
	local fromKind = from and from.kind
	if fromKind == "item" or fromKind == "drainable" then return 1.0 end
	local axis = (to and to.axis) or (from and from.axis)
	local partId = VFluid.pumpPartFor(vehicle, axis)
	if not partId then return 1.0 end
	local pump = VFluid.functionalPump(vehicle, partId)
	if not pump then return 1.0 end
	local item = pump:getInventoryItem()
	local base = (item and item.getFullType and VFluid.pumpRates[item:getFullType()])
		or VFluid.PUMP_SPEED_DEFAULT
	local cond = pump:getCondition() or 0
	if cond < 0 then cond = 0 elseif cond > 100 then cond = 100 end
	return 1.0 + (base - 1.0) * (cond / 100)
end

function VFluid.pumpGate(from, to)
	if not from or not from.needsSuction then return true end
	local vehicle, axis = to and to.vehicle, to and to.axis
	if not vehicle then return true end
	local partId = VFluid.pumpIdFor(vehicle, axis)
	if not partId then return true end
	if VFluid.functionalPump(vehicle, partId) then return true end
	return false, "requires a working pump to draw from this"
end

--------------------------------------------------------------------------------
-- Quantised endpoints: a vessel storing whole units cannot take a fraction of one.
--------------------------------------------------------------------------------

-- The coarsest step the pair can store. Zero means continuous on both sides.
function VFluid.transferQuantum(from, to)
	local a = (from and from.quantum) or 0
	local b = (to and to.quantum) or 0
	if a > b then return a end
	return b
end

-- The largest whole multiple of q that fits in amount. Never rounds up: rounding up invents fluid.
function VFluid.snapToQuantum(amount, q)
	if not q or q <= 0 then return amount or 0 end
	if not amount or amount <= 0 then return 0 end
	return math.floor(amount / q + 1e-9) * q
end

-- What this pair can actually move right now, already snapped.
function VFluid.movableBetween(from, to)
	if not from or not to then return 0 end
	local have = from.get and from.get() or 0
	local room = (to.free and to.free()) or have
	local most = (have < room) and have or room
	return VFluid.snapToQuantum(most, VFluid.transferQuantum(from, to))
end

function VFluid.canTransfer(from, to, fluidName)
	if not from or not to then return false, "missing endpoint" end
	if from == to then return false, "same endpoint" end
	local fromUnit = from.axis and from.axis.kind == "unit"
	local toUnit   = to.axis   and to.axis.kind   == "unit"
	if fromUnit or toUnit then
		if not (fromUnit and toUnit) then
			local u = fromUnit and from.axis or to.axis
			return false, u.id .. " only moves between " .. u.id .. " tanks, bottles and devices"
		end
		if from.axis.id ~= to.axis.id then return false, "different unit systems" end
		if from.get() <= 0 then return false, "source is empty" end
		if to.free and to.free() <= 0 then
			return false, (to.label and ("no room in " .. tostring(to.label))) or "no room for it"
		end
		local upumped, upumpWhy = VFluid.pumpGate(from, to)
		if not upumped then return false, upumpWhy end
		if VFluid.movableBetween(from, to) <= 0 then
			return false, "not enough for a whole charge"
		end
		return to.canAccept(from.axis.id)
	end
	if from.kind == "void" then return false, "nothing can be drawn from the ground" end
	if from.get() <= 0 then return false, "source is empty" end
	if to.free and to.free() <= 0 then
		return false, (to.label and ("no room in " .. tostring(to.label))) or "no room for it"
	end

	if to.kind ~= "void" and from.part and from.axis and VFluid.designationOf then
		local ds = VFluid.designationOf(from.vehicle, from.part, from.axis)
		if ds.unserviceable then
			return false, "this tank is compromised - it can only be drained"
		end
	end
	local pumped, pumpWhy = VFluid.pumpGate(from, to)
	if not pumped then return false, pumpWhy end
	if to.kind ~= "void" and VFluid.movableBetween(from, to) <= 0 then
		return false, "not enough for a whole charge"
	end
	if from.mixture and to.mixture then
		local okA, a = pcall(from.mixture)
		local okB, b = pcall(to.mixture)
		if okA and okB and a and b
				and VFluid.blendedFluidCount(b, a) > VFluid.MAX_FLUIDS then
			return false, "too many different fluids to mix"
		end
	end
	return to.canAccept(fluidName)
end

--------------------------------------------------------------------------------
-- a host mod happens to be installed. Ours is the default; a per-host mod option flips it.
--------------------------------------------------------------------------------

VFluid.deferTo = VFluid.deferTo or {}

local activeCache

local function modActive(id)
	if activeCache == nil then
		activeCache = {}
		local mods = getActivatedMods and getActivatedMods()
		for i = 0, (mods and mods:size() or 0) - 1 do activeCache[mods:get(i)] = true end
	end
	return activeCache[id] == true
end

function VFluid.clearModCache() activeCache = nil end

function VFluid.yieldsTo(axis)
	if not axis or not axis.duplicates then return false end
	for i = 1, #axis.duplicates do
		local id = axis.duplicates[i]
		if VFluid.deferTo[id] and modActive(id) then return true, id end
	end
	return false
end
