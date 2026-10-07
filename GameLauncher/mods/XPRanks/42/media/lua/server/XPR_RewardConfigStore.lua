if not XPR_Env or not XPR_Env.runsServerLogic() then return end

XPR_RewardConfigStore = XPR_RewardConfigStore or {}

local GLOBAL_KEY = "XPR_Global"

local function seedFromStaticLists(cfg)
	cfg.items = {}
	for _, id in ipairs(XPR_RewardItems.COMMON or {}) do cfg.items[id] = { tier = "COMMON", active = true } end
	for _, id in ipairs(XPR_RewardItems.UNCOMMON or {}) do cfg.items[id] = { tier = "UNCOMMON", active = true } end
	for _, id in ipairs(XPR_RewardItems.RARE or {}) do cfg.items[id] = { tier = "RARE", active = true } end

	for _, id in ipairs(XPR_RewardItems.getDefaultSkillVhsIds and XPR_RewardItems.getDefaultSkillVhsIds() or {}) do
		local tier = (XPR_RewardItems.getDefaultSkillVhsTier and XPR_RewardItems.getDefaultSkillVhsTier(id)) or "UNCOMMON"
		cfg.items[id] = { tier = tier, active = true }
	end

	XPR_dprint("[XPR] XPR_RewardConfigStore: seeded persisted config from static lists")
end

local function migrateLegacyStringShape(items)
	local migrated = false
	for id, entry in pairs(items) do
		if type(entry) == "string" then
			items[id] = { tier = entry, active = true }
			migrated = true
		end
	end
	return migrated
end

function XPR_RewardConfigStore.get()
	local gmd = ModData.getOrCreate(GLOBAL_KEY)
	if not gmd.rewardConfig then
		gmd.rewardConfig = {}
	end
	if not gmd.rewardConfig.items then
		seedFromStaticLists(gmd.rewardConfig)
	elseif migrateLegacyStringShape(gmd.rewardConfig.items) then
		XPR_dprint("[XPR] XPR_RewardConfigStore: migrated legacy string-tier entries to {tier,active}")
		ModData.transmit(GLOBAL_KEY)
	end
	return gmd.rewardConfig
end

function XPR_RewardConfigStore.getPool(band)
	local cfg = XPR_RewardConfigStore.get()
	local pool = {}
	for id, entry in pairs(cfg.items) do
		if entry.tier == band and entry.active ~= false then pool[#pool + 1] = id end
	end
	return pool
end

function XPR_RewardConfigStore.broadcast(targetPlayer)
	if XPR_Env and XPR_Env.isDedicated() and not XPR_Env.isServerNetworkReady() then return end
	if not XPR_Env then return end

	local cfg = XPR_RewardConfigStore.get()
	local payload = { items = cfg.items }

	if targetPlayer then
		XPR_Env.sendToClient(targetPlayer, "XPRanks", "rewardConfigSync", payload)
		return
	end

	XPR_Env.sendToAllClients("XPRanks", "rewardConfigSync", payload)
end

function XPR_RewardConfigStore.apply(newItems)
	if not newItems then return end
	local cfg = XPR_RewardConfigStore.get()
	cfg.items = newItems
	ModData.transmit(GLOBAL_KEY)
	XPR_RewardConfigStore.broadcast()
	XPR_dprint("[XPR] XPR_RewardConfigStore.apply: config updated and broadcast")
end

local GET_REWARD_CONFIG_COOLDOWN_MS = 1000

local function onClientCommand(module, command, player, args)
	if module ~= "XPRanks" then return end
	if command == "getRewardConfig" then
		if not player then return end
		if XPR_Env and not XPR_Env.checkCooldown("getRewardConfig", player, GET_REWARD_CONFIG_COOLDOWN_MS) then return end
		XPR_RewardConfigStore.broadcast(player)
	elseif command == "rewardAdminApply" then
		if not player then return end
		if not XPR_AdminAccess or not XPR_AdminAccess.hasAdminCmdAccess(player) then
			XPR_dprint("[XPR] onClientCommand REJECTED (not admin): command=rewardAdminApply player="
				.. tostring(player:getUsername()))
			return
		end
		if not args or not args.items then return end
		XPR_RewardConfigStore.apply(args.items)
		XPR_dprint("[XPR] Admin applied reward config changes ("
			.. tostring(player:getUsername()) .. ")")
	end
end

Events.OnClientCommand.Add(onClientCommand)

return XPR_RewardConfigStore
