if isServer() and not isClient() then return end

require "ISUI/ISInventoryPane"
require "ISUI/ISInventoryPaneContextMenu"
require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISTimedActionQueue"

XPR_OpenRewardBoxAction = ISBaseTimedAction:derive("XPR_OpenRewardBoxAction")

function XPR_OpenRewardBoxAction:isValid()
	return self.item and self.character and self.character:getInventory():contains(self.item)
end

function XPR_OpenRewardBoxAction:perform()
	sendClientCommand(self.character, "XPRanks", "openRewardBox", { itemID = self.item:getID() })
	ISBaseTimedAction.perform(self)
end

function XPR_OpenRewardBoxAction:new(character, item)
	local o = ISBaseTimedAction.new(self, character)
	o.item = item
	o.maxTime = 0
	return o
end

local function onOpenRewardBox(item, player)
	if not item or not player then return end
	local inventory = player:getInventory()
	local container = item:getContainer()
	if (item.hasWorldItem and item:hasWorldItem()) or container ~= inventory then
		ISInventoryPaneContextMenu.transferIfNeeded(player, item)
		ISTimedActionQueue.add(XPR_OpenRewardBoxAction:new(player, item))
		return
	end

	sendClientCommand(player, "XPRanks", "openRewardBox", { itemID = item:getID() })
end

local function onFillInventoryObjectContextMenu(playerNum, context, items)
	local player = getSpecificPlayer(playerNum)
	if not player then return end

	for i = 1, #items do
		local item = items[i]
		if not instanceof(item, "InventoryItem") then
			item = item.items and item.items[1]
		end

		if item and XPR_RewardBox.isRewardBox(item) then
			local label = getText("IGUI_XPR_RewardBox_ContextOpen") or "Open Reward Box"
			local option = context:addOption(label, item, onOpenRewardBox, player)
			local icon = item.getTex and item:getTex()
			if icon then option.iconTexture = icon end
			break
		end
	end
end

Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryObjectContextMenu)

local vanilla_doContextualDblClick = ISInventoryPane.doContextualDblClick

function ISInventoryPane:doContextualDblClick(item)
	if item and XPR_RewardBox.isRewardBox(item) then
		local player = getSpecificPlayer(self.player)
		onOpenRewardBox(item, player)
		return
	end
	vanilla_doContextualDblClick(self, item)
end

local function onOpenWorldRewardBox(item, args)
	if not item or not args or not args.player then return end
	onOpenRewardBox(item, args.player)
end

local function onFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
	local player = getSpecificPlayer(playerNum)
	if not player then return end

	for _, obj in ipairs(worldobjects) do
		if instanceof(obj, "IsoWorldInventoryObject") then
			local item = obj:getItem()
			if item and XPR_RewardBox.isRewardBox(item) then
				local label = getText("IGUI_XPR_RewardBox_ContextOpen") or "Open Reward Box"
				local option = context:addOption(label, item, onOpenWorldRewardBox, {
					player = player,
				})
				local icon = item.getTex and item:getTex()
				if icon then option.iconTexture = icon end
				break
			end
		end
	end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)

return true
