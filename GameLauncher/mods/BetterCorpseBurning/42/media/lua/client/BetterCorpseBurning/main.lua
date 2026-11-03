local BCBConfig = require("BetterCorpseBurning/config")
local BCBActions = require("BetterCorpseBurning/bcb_actions")

local TEXT_QUICK = getText("IGUI_BCB_QuickBurnCorpse")

local function onQuickBurn(worldobjects, playerIdx, corpse)
	local playerObj = getSpecificPlayer(playerIdx)
	if not (corpse and corpse:getSquare()) then return end
	-- walkAdj adds walk action to queue if needed; always add burn action after
	luautils.walkAdj(playerObj, corpse:getSquare())
	ISTimedActionQueue.add(BCBActions.BurnAction:new(playerObj, corpse))
end

Events.OnFillWorldObjectContextMenu.Add(function(playerIdx, context, worldobjects, test)
	if test then return end
	local playerObj = getSpecificPlayer(playerIdx)
	if not playerObj then return end

	if BCBConfig.REMOVE_VANILLA_BURN then
		context:removeOptionByName(getText("ContextMenu_Burn_Corpse"))
	end

	local fire = BCBActions.findFireItem(playerObj)
	if not fire then return end

	-- Check fuel requirements (OR logic: at least one active fuel type must be available)
	local hasPetrol = BCBConfig.NEED_PETROL and BCBActions.findPetrolItem(playerObj) ~= nil
	local hasAlcohol = BCBConfig.NEED_ALCOHOL and BCBActions.findAlcoholItem(playerObj) ~= nil
	local hasCologne = BCBConfig.NEED_COLOGNE and BCBActions.findCologneItem(playerObj) ~= nil
	if BCBConfig.NEED_PETROL or BCBConfig.NEED_ALCOHOL or BCBConfig.NEED_COLOGNE then
		if not hasPetrol and not hasAlcohol and not hasCologne then return end
	end

	local seenSquares = {}
	for _, obj in ipairs(worldobjects) do
		local square = obj and obj.getSquare and obj:getSquare()
		if square and not seenSquares[square] then
			seenSquares[square] = true
			local corpses = BCBActions.findCorpsesOnSquare(square)
			if #corpses > 0 and (BCBConfig.ALLOW_INDOOR or not BCBActions.isIndoorSquare(square)) then
				local fireIcon = fire:getTex()
				local optQuick = context:addOption(TEXT_QUICK, worldobjects, onQuickBurn, playerIdx, corpses[1])
				optQuick.iconTexture = fireIcon
			end
		end
	end
end)

print("[BetterCorpseBurning] loaded")
