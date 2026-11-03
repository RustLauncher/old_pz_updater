-- The transfer menu, built once and delivered to both surfaces: the radial gets slices, the
-- right-click menu gets grouped entries. Rows appear only when they can actually run - what
-- a tank offers follows what it holds, and a container is only offered where it fits.

VFluidMenu = VFluidMenu or {}

function VFluidMenu.vehicleLabel(v)
	if not v then return getText("IGUI_VFluid_AVehicle") end
	if ISVehicleMenu and ISVehicleMenu.getVehicleDisplayName then
		local ok, n = pcall(ISVehicleMenu.getVehicleDisplayName, v)
		if ok and n and n ~= "" then return n end
	end
	local script = v:getScript()
	local name = script and script:getName()
	if not name then return getText("IGUI_VFluid_AVehicle") end
	return getTextOrNull("IGUI_VehicleName" .. name) or name
end
local vehicleLabel = VFluidMenu.vehicleLabel

local function axisIcon(axis)
	local guess = {
		fuel    = "media/ui/vehicles/vehicle_refuel_from_pump.png",
		potable = "media/ui/vehicles/vehicle_add_gas.png",
		propane = "Item_PropaneTank",
	}
	return getTexture(guess[axis and axis.id] or "Item_Petrol")
end

local SUPPLY_ICON = {
	gaspump = "media/ui/vfluid/refuel.png",
	water   = "media/ui/vfluid/supply_water.png",
	well    = "media/ui/vfluid/supply_well.png",
	hydrant = "media/ui/vfluid/supply_hydrant.png",
}

local function TANK_TO_TANK_ICON()
	return getTexture("media/ui/vfluid/tank2tank.png")
end

local DIR_ICON = {
	deposit  = { fuel = "media/ui/vfluid/deposit_fuel.png",
	             potable = "media/ui/vfluid/deposit_potable.png",
	             beverage = "media/ui/vfluid/deposit_beverage.png",
	             propane = "media/ui/vfluid/deposit_propane.png",
	             [1] = "media/ui/vfluid/deposit_any.png" },
	withdraw = { fuel = "media/ui/vfluid/withdraw_fuel.png",
	             potable = "media/ui/vfluid/withdraw_potable.png",
	             beverage = "media/ui/vfluid/withdraw_beverage.png",
	             propane = "media/ui/vfluid/withdraw_propane.png",
	             [1] = "media/ui/vfluid/withdraw_any.png" },
}

local function dirIcon(axis, direction)
	local set = DIR_ICON[direction]
	if not set then return axisIcon(axis) end
	local path = (axis and set[axis.id]) or set[1]
	if path then return getTexture(path) end
	return axisIcon(axis)
end

local function supplyIcon(supplyEp, axis)
	local k = supplyEp and supplyEp.supplyKind
	if k and SUPPLY_ICON[k] then return getTexture(SUPPLY_ICON[k]) end
	return axisIcon(axis)
end

VFluidMenu.lastBuilds = VFluidMenu.lastBuilds or {}

local function recordBuild(ctx, rows)
	local v = ctx and ctx.vehicle
	local entry = {
		vehicle = v and ((v:getScript() and v:getScript():getName() or "?") .. "#" .. tostring(v:getId())) or "nil",
		vx = v and string.format("%.1f", v:getX()) or "?",
		vy = v and string.format("%.1f", v:getY()) or "?",
		surface = tostring(ctx and ctx.surface),
		player = ctx and ctx.player and string.format("%.1f,%.1f", ctx.player:getX(), ctx.player:getY()) or "?",
		ctxKeys = "",
		rows = rows,
	}
	local keys = {}
	for k, _ in pairs(ctx or {}) do keys[#keys + 1] = tostring(k) end
	table.sort(keys)
	entry.ctxKeys = table.concat(keys, ",")
	table.insert(VFluidMenu.lastBuilds, 1, entry)
	while #VFluidMenu.lastBuilds > 6 do table.remove(VFluidMenu.lastBuilds) end
end

local function hasTransferTarget(ctx)
	local vehicle = ctx and ctx.vehicle
	if not vehicle then return false end
	if #VFluid.tanksOn(vehicle) > 0 then return true end
	if VFluid.isSupplyTank(vehicle, vehicle:getPartById("GasTank")) then return true end
	local eps = VFluid.vehicleEndpoints(vehicle)
	for i = 1, #eps do
		if eps[i].kind == "mounted" and eps[i].byDefault == true then return true end
	end
	return false
end

local function containerRow(c, asSource)
	local name = tostring(c.item:getName())
	local n = asSource and c.ep.get() or c.ep.free()
	return string.format("%s (%.1f)", name, n)
end

local function fluidDisplay(name)
	if not name then return "?" end
	if VFluid.fluidLabel then
		local ok, n = pcall(VFluid.fluidLabel, name)
		if ok and n and n ~= "" then return n end
	end
	return tostring(name)
end

local function makeEntry(ctx, add, axis, part, fluidName)
	return function(direction, item, itemName, fluid)
		local who = itemName or (item and tostring(item:getName())) or "?"
		local what = fluid and VFluid.fluidLabel(fluid) or fluid
		local text
		local here = vehicleLabel(ctx.vehicle)
		local verb, src, dst
		if direction == "withdraw" then
			verb, src, dst = "ContextMenu_VFluid_TakeFluid", here, who
		else
			verb, src, dst = "ContextMenu_VFluid_AddFluid", who, here
		end
		text = VFluid.surfaceLabel(ctx.surface,
			getText(verb) .. " " .. (what or ""),
			getText("ContextMenu_VFluid_From") .. " " .. src,
			getText("ContextMenu_VFluid_To") .. " " .. dst)
		add{ text = text, icon = dirIcon(axis, direction),
			handler = VFluidMenu.onTransfer,
			args = { ctx.player, part, direction, fluid or fluidName, item } }
	end
end

-- A mounted vessel keeps its contents in the item, not in a part container, so VFluid.amount
-- reads zero for it and the label has to come from the endpoint instead.
local function heldLabel(ctx, ep, axis, part)
	if axis.kind == "unit" or ep.kind == "mounted" then
		if (ep.get and ep.get() or 0) <= 0 then return nil end
		return VFluid.axisLabel(axis)
	end
	return VFluid.contentsLabel(ctx.vehicle, part, axis, true)
end

-- Designation is a fluid-axis concept: a unit axis carries no ledger and cannot be mixed.
local function designationApplies(ep, axis)
	return axis.kind ~= "unit" and ep.kind ~= "mounted"
end

local function emitContextTake(ctx, ep, axis, part, fluidName, takeGroups)

	local ruined = false
	if VFluid.designationOf and designationApplies(ep, axis) then
		ruined = VFluid.designationOf(ctx.vehicle, part, axis).unserviceable == true
	end
	local takeName = (not ruined) and heldLabel(ctx, ep, axis, part) or nil
	if takeName then
		local rows, any = {}, false
		local list = VFluidMenu.allHandContainers(ctx.player, axis, false)
		for k = 1, #list do
			local c = list[k]
			local ok = VFluid.canTransfer(ep, c.ep, fluidName)
			if ok then
				any = true
				rows[#rows + 1] = {
					text = containerRow(c, false),
					icon = dirIcon(axis, "withdraw"),
					handler = VFluidMenu.onTransfer,
					args = { ctx.player, part, "withdraw", fluidName, c.item },
				}
			end
		end
		takeGroups[#takeGroups + 1] = {
			part = part, axis = axis, rows = rows, fluid = takeName, any = any,
			icon = dirIcon(axis, "withdraw"),
			reason = (not any) and getText("IGUI_VFluid_NoEmptyHandContainer") or nil,
		}
	end
end

local function emitContextAdd(ctx, ep, axis, part, addGroups)
	local rows = {}
	local anyAxis = false
	if VFluid.designationOf and VFluid.serviceOverrideAllowed and designationApplies(ep, axis) then
		anyAxis = VFluid.designationOf(ctx.vehicle, part, axis).userLocked == false
			and VFluid.serviceOverrideAllowed()
	end
	local src = VFluidMenu.allHandContainers(ctx.player, axis, true, anyAxis)
	for k = 1, #src do
		local c = src[k]
		local fname = VFluid.itemFluidName(c.item) or axis.defaultFluid
		if VFluid.canTransfer(c.ep, ep, fname) then
			rows[#rows + 1] = {
				text = containerRow(c, true),
				icon = dirIcon(axis, "deposit"),
				handler = VFluidMenu.onTransfer,
				args = { ctx.player, part, "deposit", fname, c.item },
			}
		end
	end
	if #rows > 0 then
		local addLabel = getText("ContextMenu_VFluid_AddFluidGeneric")
		if not addLabel or addLabel == "" or addLabel == "ContextMenu_VFluid_AddFluidGeneric" then
			addLabel = getText("ContextMenu_VFluid_AddFluid") .. " " .. getText("IGUI_VFluid_FluidWord")
			if string.find(addLabel, "IGUI_VFluid_FluidWord") then addLabel = "Add Fluid" end
		end
		addGroups[#addGroups + 1] = { part = part, axis = axis, rows = rows,
			label = addLabel, icon = dirIcon(axis, "deposit") }
	end
end

local function emitRadialTransfers(ctx, add, entry, ep, axis, part, tankName)
	local unit = (axis.kind == "unit")
	local pick = unit and VFluidMenu.pickHandContainer or VFluidMenu.equippedHandContainer

	local validate = VFluidMenu.transferFilter(ctx.vehicle, part, axis, ep)
	local srcItem, srcEp = pick(ctx.player, axis, true, validate)
	local dstItem, dstEp = pick(ctx.player, axis, false, validate)

	if srcItem then
		local giving = VFluid.itemFluidName(srcItem)
		if giving and VFluid.canTransfer(srcEp, ep, giving) then
			entry("deposit", srcItem, nil, giving)
		end
	end
	if dstItem then
		local taking = VFluid.primaryFluidOf(ctx.vehicle, part, axis)
		if taking and VFluid.canTransfer(ep, dstEp, taking) then
			entry("withdraw", dstItem, nil, taking)
		end
	end

	if unit and not srcItem and not dstItem
			and not VFluidMenu.pickTorch(ctx.player, axis) then
		add{ anyTank = "unitdead:" .. tostring(axis.id),
			text = VFluid.surfaceLabel(ctx.surface, tankName,
				getText("IGUI_VFluid_NoPropaneCarried")),
			icon = getTexture("media/ui/vfluid/propane_none.png"),
			disabled = true,
			reason = getText("IGUI_VFluid_NoPropaneCarried") }
	end
end

-- One row per vehicle, not per tank: the supply is chosen, and the chosen tank is named on it.
local function emitTorchRefill(ctx, add, axis, fluidName)
	local torch, torchEp = VFluidMenu.pickTorch(ctx.player, axis)
	if not torch or not torchEp then return end
	local best, ranked = VFluid.deviceSupplyFor(ctx.vehicle, axis, torchEp)
	if not best then return end

	local refill = getText("ContextMenu_VFluid_RefillTorch") .. " " .. tostring(torch:getName())
	local icon = getTexture("media/ui/vfluid/refill_torch.png")
	local function row(entry, forceName)
		-- partLabel, not the raw part id: every other row on this menu names a tank the way the
		-- mechanics window does.
		local name = VFluid.partLabel and VFluid.partLabel(entry.label) or entry.label
		if not name or name == "" then name = entry.label end
		-- Two mounts on one vehicle share a part label, so the submenu would offer two identical
		-- rows. The amount held separates them and shows why the default is the default.
		if forceName then name = string.format("%s (%.1f)", tostring(name), entry.held or 0) end
		return { text = VFluid.surfaceLabel(ctx.surface, refill,
				(ctx.surface ~= "context" or forceName)
					and (getText("ContextMenu_VFluid_From") .. " " .. tostring(name)) or nil),
			icon = icon,
			handler = VFluidMenu.onTransfer,
			args = { ctx.player, entry.part, "withdraw", fluidName, torch } }
	end

	-- More than one tank can serve it, and the context menu has room to offer the choice.
	if ctx.surface == "context" and #ranked > 1 then
		local rows = {}
		for i = 1, #ranked do rows[#rows + 1] = row(ranked[i], true) end
		add{ anyTank = "torch:" .. tostring(axis.id), text = refill, icon = icon, submenu = rows }
		return
	end

	local e = row(best)
	e.anyTank = "torch:" .. tostring(axis.id)
	add(e)
end

local function emitDrinkWash(ctx, add, ep, axis, part, isTank)
	if isTank and VFluid.drinkWashMenuEnabled() then
		local canDrink, whyNot = VFluid.canDrink(ctx.vehicle, part, axis)
		local what = VFluid.contentsLabel(ctx.vehicle, part, axis, true)
		if canDrink then
			local mouth = VFluid.mouthEndpoint(ctx.player, axis)
			if mouth and mouth.free() > 0 then
				add{ anyTank = "drink", text = getText("ContextMenu_VFluid_Drink") .. " " .. (what or ""),
					icon = getTexture("media/ui/vfluid/drink.png"),
					handler = VFluidMenu.onDrink,
					args = { ctx.player, part } }
			end
		elseif whyNot == "tainted" and ctx.surface == "context" then
			add{ anyTank = "drink", text = getText("ContextMenu_VFluid_Drink") .. " " .. (what or ""),
				icon = getTexture("media/ui/vfluid/drink.png"),
				disabled = true,
				reason = " <RGB:1,0.5,0.5> " .. getText("Tooltip_item_TaintedWater") }
		end

		if ctx.surface == "context"
				and VFluid.holdsOnlyWater and VFluid.holdsOnlyWater(ctx.vehicle, part, axis)
				and ep.get() > 0 then
			local rows = { {
				text = getText("ContextMenu_VFluid_WashYourself"),
				handler = VFluidMenu.onWash,
				args = { ctx.player, part },
			} }
			local worn = VFluidMenu.wornClothing(ctx.player)
			if #worn > 0 then
				rows[#rows + 1] = {
					text = getText("ContextMenu_VFluid_WashAllClothing"),
					handler = VFluidMenu.onWashClothing,
					args = { ctx.player, part, nil },
				}
				for k = 1, #worn do
					local it = worn[k]
					rows[#rows + 1] = {
						text = tostring(it:getName()),
						icon = it.getTexture and it:getTexture() or nil,
						handler = VFluidMenu.onWashClothing,
						args = { ctx.player, part, it },
					}
				end
			end
			add{ anyTank = "wash", text = getText("ContextMenu_VFluid_Wash"), submenu = rows }
		end
	end
end

local function emitRadialLogistics(ctx, add, ep, axis, part, fluidName, tankName, isTank)
	if isTank and ctx.surface ~= "context" then
	local ground = VFluid.voidEndpoint(axis)
	if ground then
		local okDr = VFluid.canTransfer(ep, ground, fluidName)
		local text = getText("ContextMenu_VFluid_Drain") .. " " .. tankName
		if okDr then
		add{ selfNamed = true, text = text, icon = getTexture("media/ui/vfluid/drain.png"),
			handler = VFluidMenu.onDrain,
			args = { ctx.player, part, fluidName } }
		end
	end

	local supplies = VFluidMenu.supplyTargets(ctx.player, axis, fluidName)
	if VFluid.debugSupply then
		print("[VFluidMenu] axis=" .. tostring(axis and axis.id) .. " fluid=" .. tostring(fluidName)
			.. " supplies=" .. tostring(#supplies))
	end
	for k = 1, #supplies do
		local s = supplies[k]
		local ok, why = VFluid.canTransfer(s.ep, ep, fluidName)
		if ok and not s.powered then ok, why = false, getText("IGUI_VFluid_NoPower") end
		if VFluid.debugSupply then
			print("[VFluidMenu]   " .. tostring(s.label) .. " powered=" .. tostring(s.powered)
				.. " get=" .. tostring(s.ep and s.ep.get()) .. " ok=" .. tostring(ok)
				.. " why=" .. tostring(why))
		end
		local text = VFluid.surfaceLabel(ctx.surface, getText("ContextMenu_VFluid_FillFromSupply"), s.label,
			(not ok) and why or nil)
		if not ok and why and why ~= "" then text = text .. " (" .. why .. ")" end
		if ok then
			add{ text = text, icon = supplyIcon(s.ep, axis),
				handler = VFluidMenu.onFillFromSupply,
				args = { ctx.player, part, s.ep, fluidName } }
		end
	end

	if ep.free() > 0 then
		local sources = VFluidMenu.sourcesInReach(ctx.player, ctx.vehicle, ep)
		for k = 1, #sources do
			local s = sources[k]
			local ok = VFluid.canTransfer(s.ep, ep, fluidName)
			if ok then
				add{ text = VFluid.surfaceLabel(ctx.surface,
						getText("ContextMenu_VFluid_Transfer") .. " "
							.. (VFluid.fluidLabel(fluidName) or fluidName),
						getText("ContextMenu_VFluid_From") .. " " .. s.label,
						getText("ContextMenu_VFluid_To") .. " " .. vehicleLabel(ctx.vehicle)),
					icon = TANK_TO_TANK_ICON(),
					handler = VFluidMenu.onRefuel,
					args = { ctx.player, s.part, ep.part, fluidName } }
			end
		end
	end
	end
end

local function emitTakeGroups(add, takeGroups)
	local function takeLabel()
		local t = getText("ContextMenu_VFluid_TakeFluid")
		local w = getText("IGUI_VFluid_FluidWord")
		if not w or w == "" or string.find(w, "IGUI_VFluid_FluidWord") then return "Take Fluid" end
		return t .. " " .. w
	end
	if #takeGroups == 1 then
		local g = takeGroups[1]
		local nm = VFluid.partLabel and VFluid.partLabel(g.part:getId()) or nil
		local label = getText("ContextMenu_VFluid_TakeFluid") .. " " .. g.fluid
		if nm and nm ~= "" then label = label .. " (" .. nm .. ")" end
		add{ text = label, icon = g.icon, disabled = not g.any, reason = g.reason,
			submenu = (#g.rows > 0) and g.rows or nil }
	elseif #takeGroups > 1 then
		local tankRows = {}
		for i = 1, #takeGroups do
			local g = takeGroups[i]
			local nm = VFluid.partLabel and VFluid.partLabel(g.part:getId()) or g.part:getId()
			tankRows[#tankRows + 1] = { text = g.fluid .. " (" .. nm .. ")", icon = g.icon,
				disabled = not g.any, reason = g.reason,
				submenu = (#g.rows > 0) and g.rows or nil }
		end
		add{ text = takeLabel(), icon = takeGroups[1].icon, submenu = tankRows }
	end
end

local function emitAddGroups(add, addGroups)
	if #addGroups == 1 then
		local g = addGroups[1]
		local nm = VFluid.partLabel and VFluid.partLabel(g.part:getId()) or nil
		local label = (nm and nm ~= "") and (g.label .. " (" .. nm .. ")") or g.label
		add{ text = label, icon = g.icon, submenu = g.rows }
	elseif #addGroups > 1 then
		local tankRows = {}
		for i = 1, #addGroups do
			local g = addGroups[i]
			local nm = VFluid.partLabel and VFluid.partLabel(g.part:getId()) or g.part:getId()
			tankRows[#tankRows + 1] = { text = nm, icon = g.icon, submenu = g.rows }
		end
		add{ text = addGroups[1].label, icon = addGroups[1].icon, submenu = tankRows }
	end
end

local function emitEngineRefuel(ctx, add, eps)
	for i = 1, #eps do
		local ep = eps[i]
		if ep.kind == "supply" and ep.free() > 0 and ctx.surface ~= "context" then
			local sources = VFluidMenu.sourcesInReach(ctx.player, ctx.vehicle, ep)
			for k = 1, #sources do
				local s = sources[k]
				local ok, why = VFluid.canTransfer(s.ep, ep, "Petrol")
				if ok then
					add{ text = VFluid.surfaceLabel(ctx.surface, getText("ContextMenu_VFluid_RefuelFrom"), s.label),
						icon = getTexture("media/ui/vfluid/refuel.png"),
						handler = VFluidMenu.onRefuel,
						args = { ctx.player, s.part, ep.part, "Petrol" } }
				end
			end
		end
	end
end

local function build(ctx, add0)
	local rows = {}
	local multiTank, curPart = 0, nil
	local addGroups, takeGroups, anyTankSeen = {}, {}, {}
	local add = function(e)
		if e.anyTank then
			if anyTankSeen[e.anyTank] then return end
			anyTankSeen[e.anyTank] = true
		end
		if multiTank > 1 and curPart and not e.anyTank and not e.selfNamed and VFluid.partLabel then
			local ok, nm = pcall(function() return VFluid.partLabel(curPart:getId()) end)
			if ok and nm and nm ~= "" then
				e.text = tostring(e.text) .. " (" .. nm .. ")"
			end
		end
		rows[#rows + 1] = tostring(e.text) .. (e.disabled and "  [DISABLED]" or "")
		if ctx.surface == "context" then e.icon = nil end
		return add0(e)
	end
	recordBuild(ctx, rows)
	local eps = VFluid.vehicleEndpoints(ctx.vehicle)
	for i = 1, #eps do
		if eps[i].kind == "tank" or (eps[i].kind == "mounted" and eps[i].byDefault == true) then
			multiTank = multiTank + 1
		end
	end
	for i = 1, #eps do
		local ep = eps[i]
		curPart = ep.part
		local isTank    = (ep.kind == "tank")
		local isMounted = (ep.kind == "mounted" and ep.byDefault == true)
		if (isTank or isMounted) and not VFluid.yieldsTo(ep.axis) then
			local axis, part = ep.axis, ep.part
			local icon = axisIcon(axis)
			local fluidName = axis.kind == "unit" and axis.id or axis.defaultFluid
			local tankName = VFluid.partLabel(part:getId())
			local entry = makeEntry(ctx, add, axis, part, fluidName)

			if ctx.surface == "context" then
				emitContextTake(ctx, ep, axis, part, fluidName, takeGroups)
				emitContextAdd(ctx, ep, axis, part, addGroups)
			else
				emitRadialTransfers(ctx, add, entry, ep, axis, part, tankName)
			end

			emitTorchRefill(ctx, add, axis, fluidName)
			emitDrinkWash(ctx, add, ep, axis, part, isTank)
			emitRadialLogistics(ctx, add, ep, axis, part, fluidName, tankName, isTank)
		end
	end

	curPart = nil

	emitTakeGroups(add, takeGroups)
	emitAddGroups(add, addGroups)
	emitEngineRefuel(ctx, add, eps)
end

VFluidMenu.build = build

if VRadial and VRadial.register then
	VFluid.radial = VRadial
	VRadial.register{
		id       = "vfluid.tank.transfer",
		order    = 120,
		surfaces = { "outside" },
		when     = hasTransferTarget,
		build    = build,
	}
end
if VContext and VContext.register then
	VContext.register{
		id    = "vfluid.tank.transfer",
		order = 120,
		build = function(ctx, add)
			if not hasTransferTarget(ctx) then return end
			return build(ctx, add)
		end,
	}
end
