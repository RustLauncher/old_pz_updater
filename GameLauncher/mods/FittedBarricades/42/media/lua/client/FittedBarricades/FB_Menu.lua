-- Context menu (singleplayer and MP clients): offer the next plank,
-- sheet or set of bars on a big opening whose first barricade is full.
--
-- The window / door menus are built in Java
-- (ISWorldObjectContextMenuLogic.doBarricadeMenu) from the FIRST
-- barricade on the player's side alone: "Barricade (Planks)" only while
-- it can take a plank, the metal options only while there is none. So
-- when the stack has room and vanilla offers nothing, the same option
-- is added here - same text and icon, and the same action: the build
-- cursor for the vanilla recipe (ISWorldObjectContextMenu.onBarricade),
-- whose validity and materials the recipe itself checks again
-- (FB_Build.lua). The option lands in the "Window" / "Door" submenu
-- next to vanilla's, or at the top level when there is no submenu (a
-- window frame). Material checks mirror the Java menu's so the option
-- shows up under the same conditions vanilla's would.

require "FittedBarricades/FB_Core"

if isServer() then return end

local FB = FittedBarricades

local function predicateNotBroken(item)
	return not item:isBroken()
end

-- a torch with fuel left, as the Java menu counts one
-- (ISWorldObjectContextMenuLogic.checkBlowTorchForBarricade)
local function predicateBlowTorch(item)
	return item:getType() == "BlowTorch" and item:getCurrentUses() >= 1
end

local function hasWelding(playerObj, inv, rods)
	return inv:getFirstEvalRecurse(predicateBlowTorch) ~= nil
		and inv:getItemCountRecurse("Base.WeldingRods") >= rods
		and playerObj:getPerkLevel(Perks.MetalWelding) >= 3
end

-- whether the player has the materials for one kind (or the build
-- cheat), as the Java menu counts them
local function affordable(playerObj, kind)
	if playerObj:isBuildCheat() then return true end
	local inv = playerObj:getInventory()
	if kind == FB.KIND.planks then
		return inv:containsTagEvalRecurse(ItemTag.HAMMER, predicateNotBroken) and inv:containsTypeRecurse("Plank")
			and inv:getItemCountRecurse("Base.Nails") >= 2
	end
	if kind == FB.KIND.metal then
		return hasWelding(playerObj, inv, 1) and inv:containsTypeRecurse("SheetMetal")
	end
	return hasWelding(playerObj, inv, 3)
		and (inv:getItemCountRecurse("Base.MetalBar") >= 3 or inv:getItemCountRecurse("Base.IronBar") >= 3)
end

-- the "Window" / "Door" submenu vanilla put the object's options in
local function submenu(context, isDoor)
	local option = context:getOptionFromName(getText(isDoor and "ContextMenu_Door_option" or "ContextMenu_Window"))
	if option and option.subOption then
		return context:getSubMenu(option.subOption)
	end
	return nil
end

FB.fillMenu = function(player, context, worldobjects, test)
	if test then return end
	local playerObj = getSpecificPlayer(player)
	if not playerObj then return end
	local opening
	for _, o in ipairs(worldobjects) do
		if FB.isOpening(o) then opening = o break end
	end
	if not opening then return end
	local first = opening:getBarricadeForCharacter(playerObj)
	if not first then return end -- an empty side: vanilla offers everything
	local class = FB.targetClass(opening)
	if class == nil then return end
	local layers = FB.stackOf(first)
	local menu = submenu(context, class == FB.DOOR_CLASS) or context
	for _, kind in ipairs(FB.KINDS) do
		local opt = FB.RECIPE[kind]
		if FB.canAdd(layers, class, kind) and affordable(playerObj, kind)
				and not menu:getOptionFromName(getText(opt.text)) then
			local option = menu:addGetUpOption(getText(opt.text), opt.tile, ISWorldObjectContextMenu.onBarricade, playerObj)
			option.iconTexture = getTexture(opt.icon)
		end
	end
end

Events.OnFillWorldObjectContextMenu.Add(FB.fillMenu)
