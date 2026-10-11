-- Build side (singleplayer and the MP server): stack barricades on big
-- openings, one vanilla object per four planks, sheet or set of bars.
--
-- B42 barricades are BUILD RECIPES: the planks / sheet metal / bars
-- recipes end in BuildRecipeCode.barricade (server/BuildRecipeCode/
-- buildRecipeCode.lua) - OnIsValidPlanks / OnIsValid decide where the
-- build cursor may go and OnCreate adds the IsoBarricade to the cursor's
-- square (the opening's own for a barricade facing n/w, the far square
-- for one facing s/e) or a plank to the barricade already there. The
-- game resolves those functions BY NAME on every call
-- (BaseCraftingLogic.callLuaBool / callLuaObject ->
-- LuaManager.getFunctionObject, which caches a name only once it has
-- resolved to a function and clears that cache whenever a Lua file
-- loads), so replacing the table fields is enough. WHEN matters: the
-- server dir - buildRecipeCode.lua and this file - is not loaded at
-- boot with shared and client (GameWindow: LoadDirBase then OnGameBoot)
-- but when a world loads (GameLoadingState in SP, GameServer on a
-- dedicated server), so on OnGameBoot there is no BuildRecipeCode yet.
-- The wrap is therefore attempted at this file's own load (vanilla's
-- server files come first) and again on OnGameBoot, OnGameStart and
-- OnServerStarted; it installs once, whichever comes first with the
-- table present, and logs that it did.
--
-- Vanilla only ever looks at the FIRST barricade on the square
-- (getBarricadeOnSameSquare / OppositeSquare = IsoBarricade.
-- GetBarricadeOnSquare): full, and it refuses more planks; metal, and it
-- refuses a second sheet. Each override asks vanilla first and keeps a
-- yes; on a no, and only for an opening with a size class, it asks the
-- stack (FB.canAdd): the same kind of object, and fewer than the class
-- holds. OnCreate on an opening with a size class is the mod's: with
-- nothing on the square it builds the first layer through the very
-- Java vanilla's OnCreate calls (BarricadeAble.addBarricadesFromCraft
-- Recipe: IsoBarricade.AddBarricadeToObject, then addFromCraftRecipe);
-- with a stack there it puts a plank on the first layer with room, or
-- starts a new layer - a fresh IsoBarricade on the square, fed through
-- the same addPlank / addFromCraftRecipe Java as vanilla's, so
-- condition and skill modifiers apply as they do to the first layer.
-- On an opening without a class the vanilla OnCreate runs untouched.
-- A layer is always the LAST of the square's special objects (Java
-- consults them in that order, and an MP client appends the object it
-- receives - IsoObject.loadFromRemoteBuffer - so server and client
-- agree on which layer is first); in the square's OBJECT list, the
-- render order, a near-side layer goes straight after its opening
-- (FB_Core.lua order: under the curtain and any canopy hung over the
-- window, which vanilla's end-of-list placement paints over), a far-
-- side one where vanilla puts it. A layer is placed before it is
-- transmitted, so the clients build the same list; a square streaming
-- in on the MP server has its fitted sides ordered on LoadGridsquare,
-- before any client is sent it (ServerMap loads a cell's chunks and
-- fires the event for each before players are let in). Vanilla's own
-- OnCreate transmits the barricade itself, which is why the first
-- layer of a fitted opening is built here and not left to it.
--
-- Afterwards, on the rendering side (singleplayer / a hosting client -
-- the server dir also loads in SP), the barricades on that square are
-- handed to the registry so the fresh state is fitted on this very
-- tick. On a dedicated server FB_Client.lua is not loaded and this does
-- nothing; the clients get the new object through OnObjectAdded, or its
-- new state through the object sync.

require "FittedBarricades/FB_Core"

local FB = FittedBarricades

-- The IsoDirections of the barricade a recipe facing builds: on the
-- cursor's square, facing the opening (n/w on the opening's own square,
-- s/e on the far one - vanilla's rule).
local FACING_DIR = { n = IsoDirections.N, s = IsoDirections.S, w = IsoDirections.W, e = IsoDirections.E }

-- The stack a build on the cursor's square would add to: the opening,
-- its size class, the side's IsoDirections and its layers. nil when
-- vanilla's answer stands - no stack yet (the first layer is always
-- vanilla's), no opening, or no size class. The opening is the one
-- Java resolves for the stack's first layer (getBarricadedObject: the
-- barricade-able object facing its way, on its square for n/w and the
-- square beyond for s/e) - the same lookup the rendering side fits the
-- stack's art to, so both sides answer for one class.
local function stackAt(square, facing)
	local dir = FACING_DIR[facing]
	local layers = FB.layers(square, dir)
	if #layers == 0 then return nil end
	local opening = layers[1]:getBarricadedObject()
	if not opening then return nil end
	local class = FB.targetClass(opening)
	if class == nil then return nil end
	return opening, class, dir, layers
end

-- Whether the stack on the cursor's square lets one more `kind` on: nil
-- when vanilla's answer stands (no opening, no size class, no stack).
FB.stackAllows = function(params, kind)
	local opening, class, _dir, layers = stackAt(params.square, params.facing)
	if not opening then return nil end
	if instanceof(opening, "IsoDoor") and opening:IsOpen() then return false end
	return FB.canAdd(layers, class, kind)
end

-- The opening a build from the cursor's square, facing `facing`, is
-- nailed to - vanilla's own search (buildRecipeCode.lua OnCreate): the
-- LAST door, window, window frame or player-built door / window of
-- that facing on the cursor's square (n/w) or the square beyond (s/e).
-- Returns it and whether the cursor is on its far side.
local function barricadeAble(o)
	if instanceof(o, "IsoThumpable") then return o:isDoor() or o:isWindow() end
	return instanceof(o, "IsoDoor") or instanceof(o, "IsoWindow") or instanceof(o, "IsoWindowFrame")
end
local function openingAt(square, facing)
	local check, opposite = square, false
	if facing == "s" then
		check, opposite = getCell():getGridSquare(square:getX(), square:getY() + 1, square:getZ()), true
	elseif facing == "e" then
		check, opposite = getCell():getGridSquare(square:getX() + 1, square:getY(), square:getZ()), true
	end
	if not check then return nil end
	local north = facing == "n" or facing == "s"
	local objects = check:getObjects()
	for i = objects:size() - 1, 0, -1 do
		local obj = objects:get(i)
		if barricadeAble(obj) and obj:getNorth() == north then return obj, opposite end
	end
	return nil
end

-- A new layer of a stack: on a near side straight after the opening
-- and the layers there (FB.nearIndex), on a far side where vanilla's
-- AddBarricadeToObject would put it - in front of the facing's curtain
-- in the square's object list, else at the end. (Always at the end of
-- the special-object list.)
local function newLayer(square, dir, opening, layers)
	local layer = IsoBarricade.new(square, dir)
	local index = FB.nearIndex(square, opening, layers)
	if not index then
		index = -1
		local objects = square:getObjects()
		for i = 0, objects:size() - 1 do
			local obj = objects:get(i)
			if instanceof(obj, "IsoCurtain") then
				local t = obj:getType()
				if (t == IsoObjectType.curtainW and dir == IsoDirections.W)
						or (t == IsoObjectType.curtainN and dir == IsoDirections.N)
						or (t == IsoObjectType.curtainE and dir == IsoDirections.E)
						or (t == IsoObjectType.curtainS and dir == IsoDirections.S) then
					index = i
					break
				end
			end
		end
	end
	square:AddSpecialObject(layer, index)
	return layer
end

-- OnCreate for an opening with a size class - its first layer, or one
-- more on its stack: true when handled, false to leave it to vanilla.
FB.fittedCreate = function(params)
	local thumpable, character, data = params.thumpable, params.character, params.craftRecipeData
	local square = thumpable:getSquare()
	local kind = FB.recipeKind(FB.spriteName(thumpable))
	if not kind then return false end
	local opening, class, dir, layers = stackAt(square, params.facing)
	local opposite = false
	if not opening then
		-- nothing on the square yet: the first layer
		opening, opposite = openingAt(square, params.facing)
		class = FB.targetClass(opening)
		if class == nil then return false end
		dir, layers = FACING_DIR[params.facing], {}
	end
	if not FB.canAdd(layers, class, kind) then return false end

	local items = data and data:getAllRecordedConsumedItems()
	local target, created
	if kind == FB.KIND.planks then
		for _, layer in ipairs(layers) do
			if layer:canAddPlank() then target = layer break end
		end
	end
	if target then
		local plank = items and not items:isEmpty() and items:get(0) or nil
		if plank then target:addPlank(character, plank) else target:addPlank(character) end
	else
		if not items or items:isEmpty() then
			items = ArrayList.new()
			items:add(instanceItem(FB.RECIPE[kind].item))
		end
		if #layers == 0 then
			-- the Java vanilla's OnCreate calls, then the near-side place
			target = opening:addBarricadesFromCraftRecipe(character, items, data, opposite)
			if not target then return false end
			FB.orderLayers(square, opening, FB.layers(square, dir))
		else
			target = newLayer(square, dir, opening, layers)
			target:addFromCraftRecipe(character, items)
		end
		created = true
	end
	if thumpable:hasModData() then
		target:setModData(thumpable:getModData())
	end
	square:RemoveTileObject(thumpable) -- the thumpable was only ever on this side
	if isServer() then
		if created then
			target:transmitCompleteItemToClients()
		else
			target:sendObjectChange(IsoObjectChange.STATE)
		end
	end
	return true
end

local function wrap()
	local code = BuildRecipeCode and BuildRecipeCode.barricade
	if not code or not code.OnCreate or code.FittedBarricadesWrapped then return end
	local vanillaOnCreate = code.OnCreate
	local vanillaOnIsValidPlanks = code.OnIsValidPlanks
	local vanillaOnIsValid = code.OnIsValid

	code.OnIsValidPlanks = function(params)
		if vanillaOnIsValidPlanks(params) then return true end
		return FB.stackAllows(params, FB.KIND.planks) == true
	end

	-- shared by the sheet metal and metal bar recipes: the cursor's tile
	-- says which
	code.OnIsValid = function(params)
		if vanillaOnIsValid(params) then return true end
		local kind = FB.recipeKind(params.tileInfo and params.tileInfo:getSpriteName())
		if kind == nil or kind == FB.KIND.planks then return false end
		return FB.stackAllows(params, kind) == true
	end

	code.OnCreate = function(params)
		-- the square before the create removes the cursor's thumpable
		local square = params and params.thumpable and params.thumpable:getSquare()
		local result
		if square and FB.fittedCreate(params) then
			result = { objectAlreadyTransmitted = true }
		else
			result = vanillaOnCreate(params)
		end
		local track = FB.trackSquare
		if track and square then
			track(square)
		end
		return result
	end
	code.FittedBarricadesWrapped = true
	print("FittedBarricades: barricade recipe overrides installed")
end

-- A square streaming in on the MP server: its fitted sides' layers put
-- after their openings before any client is sent it (saves and maps
-- from before this rule, and the map's own barricades, which
-- MOBarricade.lua - a vanilla server file, so registered first - has
-- just made IsoBarricades of). Singleplayer orders on the rendering
-- side (FB_Client.lua, on every fit) and an MP client never does.
local function onLoadGridsquare(square)
	if not isServer() then return end
	FB.orderSquare(square)
end

wrap()
for _, name in ipairs({ "OnGameBoot", "OnGameStart", "OnServerStarted" }) do
	if Events[name] then Events[name].Add(wrap) end
end
Events.LoadGridsquare.Add(onLoadGridsquare)
