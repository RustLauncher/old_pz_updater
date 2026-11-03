--[[
████  █  █   ███     ████  █   █    █     █████ █   █ █████  ████ 
█   █ █  █  █   █    █   █  █ █     █     █     ██ ██ █     █     
████  █████    █     ████    █      █     ████  █ █ █ ████   ███  
█   █    █    █      █   █   █      █     █     █   █ █         █ 
████     █  █████    ████    █      █████ █████ █   █ █████ ████
--]]  

UsableSafe = UsableSafe or {}

local function log(msg)
	print("[UsableSafe] " .. tostring(msg))
end
UsableSafe.log = log

UsableSafe.FACING_SPRITE = {
	N = "location_business_bank_01_68",
	E = "location_business_bank_01_69",
	S = "location_business_bank_01_70",
	W = "location_business_bank_01_71",
}

UsableSafe.SPRITE_FACING = {}
for facing, sprite in pairs(UsableSafe.FACING_SPRITE) do
	UsableSafe.SPRITE_FACING[sprite] = facing
end

UsableSafe.CONTAINER_TYPE = "banksafe"
UsableSafe.CONTAINER_CAPACITY = 50
UsableSafe.MODDATA_LOOTED_KEY = "UsableSafe_Looted_v7"

local JEWELRY = {
	"Base.Ring_Right_MiddleFinger_Gold",
	"Base.Ring_Left_MiddleFinger_Gold",
	"Base.Ring_Right_RingFinger_Gold",
	"Base.Ring_Left_RingFinger_Gold",
	"Base.Necklace_GoldRuby",
	"Base.Necklace_GoldDiamond",
	"Base.Necklace_Pearl",
	"Base.Necklace_DogTag",
}
local PAPERS = {
	"Base.SheetPaper2",
	"Base.Paperwork",
}

local ALLOWED_TYPES = { ["Base.Money"] = true, ["Base.Key_Blank"] = true }
for _, t in ipairs(JEWELRY) do ALLOWED_TYPES[t] = true end
for _, t in ipairs(PAPERS) do ALLOWED_TYPES[t] = true end

function UsableSafe.getSpriteName(obj)
	local sprite = obj and obj:getSprite()
	return sprite and sprite:getName() or nil
end

function UsableSafe.isSafeTile(obj)
	if obj == nil then return false end
	local name = UsableSafe.getSpriteName(obj)
	return name ~= nil and UsableSafe.SPRITE_FACING[name] ~= nil
end

local function clearContainer(container)
	local items = container:getItems()
	for i = items:size() - 1, 0, -1 do
		container:Remove(items:get(i))
	end
end

function UsableSafe.spawnLoot(container)
	if instanceItem == nil then
		log("spawnLoot: instanceItem not available in this context")
		return false
	end

	clearContainer(container)

	local moneyCount = ZombRand(10, 61)
	for _ = 1, moneyCount do
		local item = instanceItem("Base.Money")
		if item then container:AddItem(item) end
	end

	local jewelryCount = ZombRand(4, 11)
	for _ = 1, jewelryCount do
		local fullType = JEWELRY[ZombRand(1, #JEWELRY + 1)]
		local item = instanceItem(fullType)
		if item then container:AddItem(item) end
	end

	local paperCount = ZombRand(5, 16)
	for _ = 1, paperCount do
		local fullType = PAPERS[ZombRand(1, #PAPERS + 1)]
		local item = instanceItem(fullType)
		if item then container:AddItem(item) end
	end

	local key = instanceItem("Base.Key_Blank")
	if key then container:AddItem(key) end

	log("Loot spawned, item count: " .. tostring(container:getItems():size()))
	return true
end

local ourContainers = setmetatable({}, { __mode = "k" })

function UsableSafe.ensureContainer(obj, squareHint)
	if obj == nil then return nil end

	if isClient() and not isServer() then
		return obj:getContainer()
	end

	local container = obj:getContainer()

	if container == nil then
		local square = squareHint or obj:getSquare()
		if square == nil then
			return nil
		end

		local ok1, res1 = pcall(ItemContainer.new, UsableSafe.CONTAINER_TYPE, square, obj)
		if not ok1 then
			log("STEP new: " .. tostring(res1))
			return nil
		end
		container = res1
		if container == nil then
			log("STEP new: returned nil")
			return nil
		end

		ourContainers[container] = true

		local okExp, errExp = pcall(function() container:setExplored(true) end)
		if not okExp then
			log("STEP setExplored: " .. tostring(errExp))
		end

		local ok2, err2 = pcall(function() obj:setContainer(container) end)
		if not ok2 then
			log("STEP setContainer: " .. tostring(err2))
			ourContainers[container] = nil
			return nil
		end
	end

	local ok3, err3 = pcall(function() container:setCapacity(UsableSafe.CONTAINER_CAPACITY) end)
	if not ok3 then
		log("STEP setCapacity: " .. tostring(err3))
	end

	local ok4, modData = pcall(function() return obj:getModData() end)
	if ok4 and modData ~= nil and not modData[UsableSafe.MODDATA_LOOTED_KEY] then
		if UsableSafe.spawnLoot(container) then
			modData[UsableSafe.MODDATA_LOOTED_KEY] = true
			if obj.transmitModData then pcall(function() obj:transmitModData() end) end
		end
	end

	return container
end

local function onFillContainer(containerType, container)
	if ourContainers[container] == nil then return end

	local ok, parent = pcall(function() return container:getParent() end)
	if not ok or parent == nil then return end

	local ok2, modData = pcall(function() return parent:getModData() end)
	if not ok2 or modData == nil then return end

	if modData[UsableSafe.MODDATA_LOOTED_KEY] then
		return -- already looted once - never touch contents again
	end

	log("OnFillContainer intercepted (type=" .. tostring(containerType) .. ")")
	if UsableSafe.spawnLoot(container) then
		modData[UsableSafe.MODDATA_LOOTED_KEY] = true
		if parent.transmitModData then pcall(function() parent:transmitModData() end) end
	end
end
Events.OnFillContainer.Add(onFillContainer)

local function onLoadGridsquare(square)
	if square == nil then return end
	local objects = square:getObjects()
	for i = 0, objects:size() - 1 do
		local obj = objects:get(i)
		if UsableSafe.isSafeTile(obj) then
			UsableSafe.ensureContainer(obj, square)
		end
	end
end
Events.LoadGridsquare.Add(onLoadGridsquare)

log("UsableSafe_Shared.lua loaded")
