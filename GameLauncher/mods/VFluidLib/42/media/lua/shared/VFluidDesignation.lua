-- The designation machine: service, mode and fluid per tank, frozen deterministically at
-- first sight, changed only through drain-and-clean. designationOf reports;
-- setDesignation is the one write path.

VFluid = VFluid or {}

local DKEY = "designation"

VFluid.MODE_SINGLE = "single"
VFluid.MODE_MULTI  = "multi"

--------------------------------------------------------------------------------
---- storage
--------------------------------------------------------------------------------

function VFluid.cleaningEnabled()
	if not VFluid.tankCleaningLevel then return true end
	return VFluid.tankCleaningLevel() ~= (VFluid.CLEAN_OFF or 1)
end

local function stored(part, create)
	local mod = VFluid.partMod and VFluid.partMod(part, create)
	if not mod then return nil end
	if not mod[DKEY] then
		if not create then return nil end
		mod[DKEY] = {}
	end
	return mod[DKEY]
end

--------------------------------------------------------------------------------
---- the seed: an initial designation nobody had to store
--------------------------------------------------------------------------------

local function hashOf(vehicleId, partId)
	local h = math.abs((tonumber(vehicleId) or 0)) * 73856093
	partId = tostring(partId or "")
	for i = 1, #partId do
		h = (h * 31 + string.byte(partId, i)) % 2147483647
	end
	return math.abs(h) % 100
end

local function contents(vehicle, part, axis)
	local led = VFluid.rawLedger and VFluid.rawLedger(part)
	local n, only = 0, nil
	if led then
		for name, q in pairs(led) do
			if q and q > 0 then n = n + 1; only = name end
		end
	end
	if n == 0 and VFluid.amount and VFluid.amount(part) > 0 then
		return 1, axis and axis.defaultFluid or nil
	end
	return n, (n == 1) and only or nil
end

function VFluid.designationSeed(vehicle, part, axis)
	local n, only = contents(vehicle, part, axis)
	if n > 1 then
		return { mode = VFluid.MODE_MULTI, fluid = nil, residue = true }
	end
	local roll = hashOf(vehicle and vehicle.getId and vehicle:getId() or 0, part and part.getId and part:getId() or "")
	if roll < 60 then
		return { mode = VFluid.MODE_MULTI, fluid = nil, residue = false }
	elseif roll < 90 then
		local f = only or (axis and axis.defaultFluid) or nil
		if not f then return { mode = VFluid.MODE_MULTI, fluid = nil, residue = false } end
		return { mode = VFluid.MODE_SINGLE, fluid = f, residue = false }
	end
	return { mode = VFluid.MODE_MULTI, fluid = nil, residue = true }
end

function VFluid.fixedDesignationOf(vehicle, part)
	if not vehicle or not part then return nil end
	local name = vehicle.getScript and vehicle:getScript() and vehicle:getScript():getName()
	local cfg = name and VFluid.vehicles and VFluid.vehicles[name]
	local fixed = cfg and cfg.fixedDesignation
	if type(fixed) ~= "table" then return nil end
	local id = part.getId and part:getId()
	return id and fixed[id] or nil
end

local function permissive()
	return { mode = VFluid.MODE_MULTI, fluid = nil, residue = false,
		locked = false, fixed = false, userLocked = false,
		unserviceable = false, compromised = false, mixed = false, soiled = false,
		vanillaRules = true }
end

function VFluid.designationOf(vehicle, part, axis)
	if VFluid.vanillaRules and VFluid.vanillaRules() then return permissive() end
	local fixedFluid = VFluid.fixedDesignationOf(vehicle, part)
	if fixedFluid then
		return { mode = VFluid.MODE_SINGLE, fluid = fixedFluid, residue = false,
			locked = true, fixed = true, userLocked = true,
			unserviceable = false, compromised = false, mixed = false }
	end
	local st = stored(part, false)
	local base = st and st.mode and st or nil
	if not base then
		base = VFluid.designationSeed(vehicle, part, axis)
		if not (isClient and isClient()) then
			local w = stored(part, true)
			if w then
				w.mode, w.fluid, w.residue = base.mode, base.fluid, base.residue
				if vehicle and vehicle.transmitPartModData then
					pcall(function() vehicle:transmitPartModData(part) end)
				end
			end
		end
	end
	local n, only = contents(vehicle, part, axis)
	local residue = base.residue == true

	local unserviceable = false
	local led = VFluid.rawLedger and VFluid.rawLedger(part)
	if led and Fluid and Fluid.Get and VFluid.axisAdmits then
		for name, q in pairs(led) do
			if q and q > 0 then
				local f = Fluid.Get(name)
				if f and not VFluid.axisAdmits(axis, f) then unserviceable = true break end
			end
		end
	end
	local mixed = (not unserviceable) and (n > 1 or residue) or false

	local resolved = base.fluid
	if base.mode == VFluid.MODE_SINGLE and not resolved and n == 1 and only then
		resolved = (axis and axis.variantOf and axis.variantOf[only]) or only
		if not (isClient and isClient()) then
			local w = stored(part, true)
			if w then
				w.fluid = resolved
				if vehicle and vehicle.transmitPartModData then
					pcall(function() vehicle:transmitPartModData(part) end)
				end
			end
		end
	end
	local compromised = (base.mode == VFluid.MODE_SINGLE) and base.fluid ~= nil
		and n == 1 and only ~= nil and only ~= base.fluid
	return {
		mode = base.mode or VFluid.MODE_MULTI,
		fluid = resolved,
		residue = residue,
		unserviceable = unserviceable == true,
		compromised = unserviceable == true,
		mixed = mixed == true,
		userLocked = (st and st.unrestricted) ~= true,
		fixed = false,
		locked = VFluid.cleaningEnabled() and (mixed or unserviceable) or false,
	}
end

--------------------------------------------------------------------------------
---- the gate
--------------------------------------------------------------------------------

function VFluid.designationAdmits(vehicle, part, axis, fluidName)
	local d = VFluid.designationOf(vehicle, part, axis)
	if not d.userLocked then return true end
	if d.mode ~= VFluid.MODE_SINGLE then return true end
	if not d.fluid then return true end
	if fluidName == nil or fluidName == d.fluid then return true end
	return false, "this tank is designated for " .. tostring(d.fluid)
end

--------------------------------------------------------------------------------
---- transitions
--------------------------------------------------------------------------------

function VFluid.canDesignate(vehicle, part, axis, mode, fluid)
	local d = VFluid.designationOf(vehicle, part, axis)
	if d.fixed then return false, "this tank's designation is fixed" end
	if mode == VFluid.MODE_MULTI then return true end
	if mode ~= VFluid.MODE_SINGLE then return false, "unknown mode" end
	if d.locked then
		return false, VFluid.cleaningEnabled()
			and "the tank carries several fluids - clean it to dedicate it to one"
			or "the tank carries several fluids - drain it to dedicate it to one"
	end
	if not fluid then return false, "no fluid chosen" end
	local n, only = contents(vehicle, part, axis)
	if n == 0 then return true end
	if n == 1 and only == fluid then return true end
	if n == 1 then return false, "the tank holds " .. tostring(only) end
	if not VFluid.cleaningEnabled() then
		return false, "the tank carries several fluids - drain it to dedicate it to one"
	end
	return false, "the tank carries several fluids - clean it to dedicate it to one"
end

local function materialise(vehicle, part, axis)
	local st = stored(part, true)
	if not st then return nil end
	if st.mode == nil then
		local d = VFluid.designationOf(vehicle, part, axis)
		st.mode, st.fluid, st.residue = d.mode, d.fluid, d.residue
	end
	return st
end

local function commitmentPriced()
	return VFluid.tankCleaningLevel and VFluid.CLEAN_ALL
		and VFluid.tankCleaningLevel() == VFluid.CLEAN_ALL
end

local function narrowBlocker(d)
	if d.fixed then return "this tank's designation is fixed" end
	if d.unserviceable then
		return "holds something it is not designated for - "
			.. (VFluid.cleaningEnabled() and "clean the tank" or "drain the tank")
	end
	if d.locked then
		return VFluid.cleaningEnabled()
			and "Requires drain and clean to switch."
			or "carrying a mixture - drain the tank if you want it dedicated to one fluid again"
	end
	return nil
end

function VFluid.designationModes(vehicle, part, axis)
	if not axis then return {} end
	if axis.kind ~= "fluid" then
		return { { mode = VFluid.MODE_SINGLE, current = true, enabled = false } }
	end
	local d = VFluid.designationOf(vehicle, part, axis)
	local blocked = narrowBlocker(d)
	return {
		{ mode = VFluid.MODE_SINGLE, current = (d.mode == VFluid.MODE_SINGLE),
		  enabled = (blocked == nil), reason = blocked },
		{ mode = VFluid.MODE_MULTI, current = (d.mode == VFluid.MODE_MULTI),
		  enabled = (d.fixed ~= true),
		  reason = d.fixed and "this tank's designation is fixed" or nil },
	}
end

function VFluid.designationFluids(vehicle, part, axis, asMode)
	local out = {}
	if not axis then return out end
	if axis.kind ~= "fluid" then
		return { { kind = "unit", axis = axis.id, current = true, enabled = false } }
	end
	local d = VFluid.designationOf(vehicle, part, axis)
	local mode = asMode or d.mode
	local n, only = contents(vehicle, part, axis)
	local blocked = narrowBlocker(d)

	if mode == VFluid.MODE_MULTI then
		if d.mixed or n > 1 then
			out[1] = { kind = "mixture", current = true, enabled = false,
				reason = blocked or ("this tank carries a mixture and works normally - "
					.. (VFluid.cleaningEnabled()
						and "cleaning is only needed to dedicate it to one fluid again"
						or "draining is only needed to dedicate it to one fluid again")) }
		elseif n == 1 and only then
			out[1] = { kind = "fluid", fluid = only, current = true, enabled = false }
		else
			out[1] = { kind = "empty", current = true, enabled = false,
				reason = "nothing in the tank - switch to Single Fluid to designate it" }
		end
		return out
	end

	if not d.fluid then
		out[#out + 1] = { kind = "empty", current = true, enabled = false,
			reason = "choose the fluid this tank is for" }
	end
	local names = VFluid.axisFluids and VFluid.axisFluids(axis) or {}
	local variant = axis.variantOf or {}
	for i = 1, #names do
		local f = names[i]
		local ok, why
		if blocked then ok, why = false, blocked
		elseif n == 0 then
			if commitmentPriced() and VFluid.rinsesClean
					and not VFluid.rinsesClean(d.fluid) and f ~= d.fluid then
				ok, why = false, (VFluid.cleaningEnabled()
					and ("the tank is still committed to " .. tostring(VFluid.fluidLabel and VFluid.fluidLabel(d.fluid) or d.fluid) .. " - clean it to change that")
					or ("the tank is still committed to " .. tostring(VFluid.fluidLabel and VFluid.fluidLabel(d.fluid) or d.fluid)))
			else
				ok = true
			end
		elseif n == 1 and only == f then ok = true
		else ok, why = false, "the tank holds " .. tostring(only or "something else") end
		if not variant[f] or f == d.fluid then
			out[#out + 1] = { kind = "fluid", fluid = f, current = (f == d.fluid),
				enabled = (ok == true), reason = why }
		end
	end
	return out
end

function VFluid.reconcileService(vehicle, part, axis)
	if VFluid.vanillaRules and VFluid.vanillaRules() then return false end
	if isClient and isClient() then return false end
	if not axis or axis.kind ~= "fluid" then return false end
	local led = VFluid.rawLedger and VFluid.rawLedger(part)
	if not led then return false end

	local names, fits = {}, true
	for name, q in pairs(led) do
		if q and q > 0 then
			names[#names + 1] = name
			local f = Fluid and Fluid.Get and Fluid.Get(name)
			if not f or not VFluid.axisAdmits(axis, f) then fits = false end
		end
	end

	local changed = false
	if #names > 1 then
		local st = stored(part, true)
		if st and st.mode == VFluid.MODE_SINGLE then
			st.mode, st.fluid = VFluid.MODE_MULTI, nil
			changed = true
		end
	end

	if fits or #names == 0 then
		if changed and vehicle and vehicle.transmitPartModData then
			pcall(function() vehicle:transmitPartModData(part) end)
		end
		return changed
	end

	local want = VFluid.serviceCovering and VFluid.serviceCovering(names)
	if not want or want == axis.id then
		if changed and vehicle and vehicle.transmitPartModData then
			pcall(function() vehicle:transmitPartModData(part) end)
		end
		return changed
	end

	local mod = VFluid.partMod and VFluid.partMod(part, true)
	if not mod then return false end
	mod.axis = want
	local st = stored(part, true)
	if st then st.mode, st.fluid = VFluid.MODE_MULTI, nil end
	if vehicle and vehicle.transmitPartModData then
		pcall(function() vehicle:transmitPartModData(part) end)
	end
	return true
end

function VFluid.serviceOptions(vehicle, part)
	local out = {}
	if not part then return out end
	local axis = VFluid.axisFor and VFluid.axisFor(vehicle, part)
	if not axis then return out end
	local d = VFluid.designationOf(vehicle, part, axis)
	local n = select(1, contents(vehicle, part, axis))

	local why = nil
	if d.fixed then why = "this tank's designation is fixed"
	elseif axis.kind ~= "fluid" then why = "This is a closed system."
	elseif n > 0 or d.mixed or d.unserviceable then
		why = VFluid.cleaningEnabled() and "Requires drain and clean to switch."
			or "empty the tank to change its service"
	elseif commitmentPriced() and VFluid.rinsesClean and not VFluid.rinsesClean(d.fluid) then
		why = VFluid.cleaningEnabled()
			and "the tank is still committed to what it last carried - clean it to change that"
			or "the tank is still committed to what it last carried"
	end

	if axis.kind ~= "fluid" then
		return { { axis = axis.id, current = true, enabled = false, reason = why } }
	end

	for i = 1, #(VFluid.axisOrder or {}) do
		local a = VFluid.axes[VFluid.axisOrder[i]]
		if a and a.kind == "fluid" then
			out[#out + 1] = { axis = a.id, current = (a.id == axis.id),
				enabled = (why == nil), reason = why }
		end
	end
	return out
end

function VFluid.afterServiceModes()
	return {
		{ mode = VFluid.MODE_SINGLE, current = true,  enabled = true },
		{ mode = VFluid.MODE_MULTI,  current = false, enabled = true },
	}
end

function VFluid.afterServiceFluids(axisId)
	local out = {}
	local a = VFluid.axes and VFluid.axes[axisId]
	if not a or a.kind ~= "fluid" then return out end
	out[1] = { kind = "empty", current = true, enabled = false,
		reason = "choose the fluid this tank is for" }
	local names = VFluid.axisFluids and VFluid.axisFluids(a) or {}
	local variant = a.variantOf or {}
	for i = 1, #names do
		if not variant[names[i]] then
			out[#out + 1] = { kind = "fluid", fluid = names[i], current = false, enabled = true }
		end
	end
	return out
end

function VFluid.setService(vehicle, part, axisId)
	if VFluid.vanillaRules and VFluid.vanillaRules() then return false end
	local a = VFluid.axes and VFluid.axes[axisId]
	if not a or a.kind ~= "fluid" then return false end
	local allowed = false
	for _, o in ipairs(VFluid.serviceOptions(vehicle, part)) do
		if o.axis == axisId and o.enabled then allowed = true break end
	end
	if not allowed then return false end

	local mod = VFluid.partMod and VFluid.partMod(part, true)
	if not mod then return false end
	mod.axis = axisId

	local st = stored(part, true)
	if st then st.mode, st.fluid, st.residue = VFluid.MODE_SINGLE, nil, false end
	if vehicle and vehicle.transmitPartModData then
		pcall(function() vehicle:transmitPartModData(part) end)
	end
	return true
end

function VFluid.applyClean(vehicle, part, axis)
	if not part or not axis then return false end
	if (VFluid.amount and VFluid.amount(part) or 0) > 0.01 then return false end
	if VFluid.cleaningNeed and VFluid.cleaningNeed(vehicle, part, axis) == VFluid.NEED_NONE then
		return false
	end
	VFluid.clearResidue(vehicle, part, axis)
	local st = stored(part, true)
	if st then
		st.mode, st.fluid, st.residue = VFluid.MODE_SINGLE, nil, false
	end
	if vehicle and vehicle.transmitPartModData then
		pcall(function() vehicle:transmitPartModData(part) end)
	end
	return true
end

function VFluid.designationDefaultFluid(vehicle, part, axis)
	local n, only = contents(vehicle, part, axis)
	if n == 1 and only then return (axis and axis.variantOf and axis.variantOf[only]) or only end
	if n > 1 then return nil end
	local names = VFluid.axisFluids and VFluid.axisFluids(axis) or {}
	local def = axis and axis.defaultFluid
	if def then
		for i = 1, #names do if names[i] == def then return def end end
	end
	return names[1]
end

function VFluid.designationEditable(vehicle, part, axis)
	for _, o in ipairs(VFluid.designationModes(vehicle, part, axis)) do
		if o.enabled and not o.current then return true end
	end
	for _, o in ipairs(VFluid.designationFluids(vehicle, part, axis)) do
		if o.enabled and not o.current then return true end
	end
	return false, narrowBlocker(VFluid.designationOf(vehicle, part, axis))
end

function VFluid.setDesignation(vehicle, part, axis, mode, fluid)
	if VFluid.vanillaRules and VFluid.vanillaRules() then return false end
	local ok, why = VFluid.canDesignate(vehicle, part, axis, mode, fluid)
	if not ok then return false, why end
	local st = materialise(vehicle, part, axis)
	if not st then return false, "no part data" end
	st.mode = mode
	st.fluid = (mode == VFluid.MODE_SINGLE) and fluid or nil
	if vehicle and vehicle.transmitPartModData then vehicle:transmitPartModData(part) end
	return true
end

function VFluid.setDesignationLock(vehicle, part, axis, locked)
	if VFluid.vanillaRules and VFluid.vanillaRules() then return false end
	local d = VFluid.designationOf(vehicle, part, axis)
	if d.fixed then return false, "this tank's designation is fixed" end
	local st = materialise(vehicle, part, axis)
	if not st then return false, "no part data" end
	st.unrestricted = (locked ~= true)
	if vehicle and vehicle.transmitPartModData then vehicle:transmitPartModData(part) end
	return true
end

--------------------------------------------------------------------------------
---- the spawn writer
--------------------------------------------------------------------------------

function VFluid.spawnDesignate(vehicle, part, axisId, mode, fluid)
	if VFluid.vanillaRules and VFluid.vanillaRules() then return false end
	if not part or not axisId or not VFluid.axes[axisId] then return false end
	local natural = VFluid.axisFor and VFluid.axisFor(vehicle, part)
	if not natural or natural.id ~= axisId then
		local mod = VFluid.partMod and VFluid.partMod(part, true)
		if not mod then return false end
		mod.axis = axisId
	end
	local st = stored(part, true)
	if not st then return false end
	st.mode, st.fluid = mode or VFluid.MODE_MULTI, fluid
	return true
end

--------------------------------------------------------------------------------
---- residue
--------------------------------------------------------------------------------

function VFluid.markResidue(vehicle, part, axis)
	local st = materialise(vehicle, part, axis)
	if not st then return false end
	st.residue = true
	if st.mode == VFluid.MODE_SINGLE then st.mode, st.fluid = VFluid.MODE_MULTI, nil end
	return true
end

function VFluid.clearResidue(vehicle, part, axis)
	local st = materialise(vehicle, part, axis)
	if not st then return false end
	st.residue = false
	if vehicle and vehicle.transmitPartModData then vehicle:transmitPartModData(part) end
	return true
end
