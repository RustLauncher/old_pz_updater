-- Radial usability patch for Water Trailer tanks.
-- VFluid intentionally limits fluid radials to equipped containers. These
-- trailers historically accepted a bottle carried in the main inventory, so
-- add a fallback only when VFluid emitted no equipped-container action.

if not (VFluid and VFluid.CAPS and VFluid.CAPS.transfer == 1
		and VFluidMenu and VRadial and VRadial.register) then return end

local function isOurVehicle(ctx)
	return rWaterTrailer and rWaterTrailer.VFluid
		and rWaterTrailer.VFluid.IsWaterTrailer(ctx and ctx.vehicle)
end

local function label(direction, fluidName, item, vehicle)
	local verb = direction == "withdraw" and "ContextMenu_VFluid_TakeFluid"
		or "ContextMenu_VFluid_AddFluid"
	local fluid = VFluid.fluidLabel and VFluid.fluidLabel(fluidName) or tostring(fluidName)
	local from = direction == "withdraw"
		and VFluidMenu.vehicleLabel(vehicle) or tostring(item:getName())
	local to = direction == "withdraw"
		and tostring(item:getName()) or VFluidMenu.vehicleLabel(vehicle)
	return VFluid.surfaceLabel("outside",
		getText(verb) .. " " .. fluid,
		getText("ContextMenu_VFluid_From") .. " " .. from,
		getText("ContextMenu_VFluid_To") .. " " .. to)
end

local function pickCarriedContainer(playerObj, axis, wantSource, validate)
	-- Include containers inside worn bags, matching VFluid's context-menu scan.
	if VFluidMenu.allHandContainers then
		local list = VFluidMenu.allHandContainers(playerObj, axis, wantSource)
		for i = 1, #list do
			local row = list[i]
			if not validate or validate(row.item, row.ep, wantSource) then
				return row.item, row.ep
			end
		end
	end
	return VFluidMenu.pickHandContainer(playerObj, axis, wantSource, validate)
end

local function isNaturalWaterEndpoint(endpoint)
	return endpoint and endpoint.holder and VFluid.isOpenWaterSquare
		and VFluid.isOpenWaterSquare(endpoint.holder)
end

-- Build 42 exposes public-grid power on outdoor fuel-pump squares through
-- hasGridPower().  VFluid currently only checks haveElectricity(), which is
-- normally false outdoors until an exterior generator is connected.  Correct
-- the result for our trailers using the same rule as vanilla's vehicle menu.
local function gasPumpHasPower(endpoint)
	if not endpoint or endpoint.supplyKind ~= "gaspump" then return nil end
	local holder = endpoint.holder
	local square = holder and holder.getSquare and holder:getSquare()
	if not square then return false end
	if square.hasGridPower and square:hasGridPower() then return true end
	return SandboxVars and SandboxVars.AllowExteriorGenerator == true
		and square.haveElectricity and square:haveElectricity() or false
end

if type(VFluidMenu.supplyTargets) == "function"
		and not rWaterTrailer.VFluid._gasPumpPowerWrapped then
	local previousSupplyTargets = VFluidMenu.supplyTargets
	VFluidMenu.supplyTargets = function(playerObj, axis, fluidName)
		local targets = previousSupplyTargets(playerObj, axis, fluidName)
		for i = 1, #(targets or {}) do
			local powered = gasPumpHasPower(targets[i].ep)
			if powered ~= nil then targets[i].powered = powered end
		end
		return targets
	end
	rWaterTrailer.VFluid._gasPumpPowerWrapped = true
end

VRadial.register{
	id = "rwatertrailer.vfluid.inventoryfallback",
	order = 121,
	surfaces = { "outside" },
	when = isOurVehicle,
	build = function(ctx, add)
		if not rWaterTrailer.VFluid.IsLidOpen(ctx.vehicle) then return end
		local tanks = VFluid.tanksOn(ctx.vehicle)
		for i = 1, #tanks do
			local part, axis = tanks[i].part, tanks[i].axis
			local endpoint = VFluid.transferEndpointFor(ctx.vehicle, part)
			if endpoint and axis and axis.kind == "fluid" then
				local validate = VFluidMenu.transferFilter(ctx.vehicle, part, axis, endpoint)

				local equippedSource = VFluidMenu.equippedHandContainer(ctx.player, axis, true, validate)
				if not equippedSource then
					local item, itemEndpoint = pickCarriedContainer(ctx.player, axis, true, validate)
					local fluidName = item and VFluid.itemFluidName(item)
					if item and fluidName and VFluid.canTransfer(itemEndpoint, endpoint, fluidName) then
						add{ text = label("deposit", fluidName, item, ctx.vehicle),
							icon = "media/ui/vfluid/deposit_any.png",
							handler = VFluidMenu.onTransfer,
							args = { ctx.player, part, "deposit", fluidName, item } }
					end
				end

				local equippedDest = VFluidMenu.equippedHandContainer(ctx.player, axis, false, validate)
				if not equippedDest then
					local item, itemEndpoint = pickCarriedContainer(ctx.player, axis, false, validate)
					local fluidName = VFluid.primaryFluidOf(ctx.vehicle, part, axis)
					if item and fluidName and VFluid.canTransfer(endpoint, itemEndpoint, fluidName) then
						add{ text = label("withdraw", fluidName, item, ctx.vehicle),
							icon = "media/ui/vfluid/withdraw_any.png",
							handler = VFluidMenu.onTransfer,
							args = { ctx.player, part, "withdraw", fluidName, item } }
					end
				end
			end
		end
	end,
}

-- VFluid's generic natural-water endpoint has no fluid identity and therefore
-- defaults to clean Water. For these tanks, open lakes and rivers supply
-- TaintedWater; a fitted outlet filter purifies it later when filling a bottle.
if type(VFluidMenu.onFillFromSupply) == "function"
		and not rWaterTrailer.VFluid._supplyMenuWrapped then
	local previousFillFromSupply = VFluidMenu.onFillFromSupply
	VFluidMenu.onFillFromSupply = function(playerObj, part, supplyEndpoint, fluidName)
		local vehicle = part and part:getVehicle()
		if rWaterTrailer.VFluid.IsCargoTank(vehicle, part)
				and isNaturalWaterEndpoint(supplyEndpoint) then
			fluidName = "TaintedWater"
		end
		return previousFillFromSupply(playerObj, part, supplyEndpoint, fluidName)
	end
	rWaterTrailer.VFluid._supplyMenuWrapped = true
end
