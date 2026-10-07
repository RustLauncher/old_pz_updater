XPR_RewardCategoryResolver = XPR_RewardCategoryResolver or {}

local DISPLAY_CAT_MAP = {
	tool = "Tools",
	toolweapon = "Tools",
	gardening = "Tools",
	gardeningweapon = "Tools",
	cooking = "Tools",
	cookingweapon = "Tools",
	fishing = "Tools",
	fishingweapon = "Tools",
	lightsource = "Tools",
	firesource = "Tools",
	trapping = "Tools",
	security = "Tools",
	cartography = "Tools",
	vehiclemaintenance = "Tools",
	vehiclemaintenanceweapon = "Tools",
	weapon = "Weapons",
	weaponcrafted = "Weapons",
	weaponimprovised = "Weapons",
	weaponpart = "Weapons",
	explosives = "Weapons",
	ammo = "Weapons",
	brokenweapon = "Weapons",
	householdweapon = "Weapons",
	junkweapon = "Weapons",
	materialweapon = "Weapons",
	sportsweapon = "Weapons",
	instrumentweapon = "Weapons",
	animalpartweapon = "Weapons",
	firstaidweapon = "Weapons",
	clothing = "Clothing",
	accessories = "Clothing",
	accessory = "Clothing",
	appearance = "Other",
	ears = "Clothing",
	tail = "Clothing",
	bag = "Equipment",
	communications = "Equipment",
	container = "Equipment",
	protectivegear = "Equipment",
	water = "Equipment",
	watercontainer = "Equipment",
	camping = "Equipment",
	food = "Food",
	literature = "Literature",
	skillbook = "Literature",
	["recipe resource"] = "Literature",
	reciperesource = "Literature",
	memento = "Other",
	material = "Materials",
	firstaid = "Medical",
	bandage = "Medical",
	entertainment = "Other",
	electronics = "Other",
	furniture = "Other",
	household = "Other",
	instrument = "Other",
	junk = "Other",
	generic = "Other",
	sports = "Other",
	paint = "Other",
	animal = "Other",
	animalpart = "Materials",
	dog = "Other",
}

local EXCLUDED_CATEGORIES = { ["Corpse"] = true, ["RemovedItem"] = true, ["Debug"] = true }

function XPR_RewardCategoryResolver.resolve(scriptItem, fullType)
	if not scriptItem or not fullType then return "Other" end

	local displayCat = scriptItem.getDisplayCategory and scriptItem:getDisplayCategory()
	if displayCat then
		local dc = string.lower(displayCat)

		if dc == "gardeningweapon" then
			local lt = string.lower(fullType or "")
			if string.find(lt, "machete") then return "Weapons" end
			return "Tools"
		end

		local mapped = DISPLAY_CAT_MAP[dc]
		if mapped then return mapped end

		if EXCLUDED_CATEGORIES[displayCat] then return nil end
	end

	if scriptItem.getCategory then
		local cat = scriptItem:getCategory()
		if cat == "Clothing" then return "Clothing" end
		if cat == "Container" then return "Equipment" end
		if cat == "Communications" then return "Equipment" end
	end

	return "Other"
end

return XPR_RewardCategoryResolver
