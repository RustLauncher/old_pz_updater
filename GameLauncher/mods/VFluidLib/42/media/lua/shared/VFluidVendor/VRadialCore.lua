-- Shared vehicle RADIAL registry: declare an entry once and it reaches the outside and seated
-- radials; declare a rule and it hides slices other mods add. The context menu is
-- VContextCore's surface, not this one's - entries registered here still emit there.
-- VENDORED FILE - copied verbatim into every carrying library, never edited in place.
-- Highest VERSION wins and upgrades the live table in place, so entries and rules already
-- registered survive the election.

local VERSION = 5

if VRadial and VRadial.VERSION and VRadial.VERSION >= VERSION then return end

VRadial            = VRadial or {}
VRadial.VERSION    = VERSION
VRadial.entries    = VRadial.entries or {}
VRadial.rules      = VRadial.rules   or {}
VRadial.owners     = VRadial.owners  or {}
VRadial.debug      = VRadial.debug   or false
VRadial._entryList = nil
VRadial._ruleList  = nil
VRadial._ruleCount = VRadial._ruleCount or 0
VRadial._rearms    = VRadial._rearms or 0
VRadial._probe     = false

local MAX_REARMS = 3
local MAX_ARGS   = 6

local function log(msg)
	print("[VRadial] " .. tostring(msg))
end

local MAX_ERRORS = 3

local function safeCall(row, fn, a, b)
	if type(fn) ~= "function" then return nil, true end
	local ok, result = pcall(fn, a, b)
	if not ok then
		row._errors = (row._errors or 0) + 1
		if row._errors < MAX_ERRORS then
			log("callback error in " .. tostring(row.id) .. ": " .. tostring(result))
		elseif row._errors == MAX_ERRORS then
			row._broken = true
			log("DISABLED " .. tostring(row.id) .. " after " .. MAX_ERRORS .. " errors: " .. tostring(result))
		end
		return nil, false
	end
	return result, true
end

local function surfaceSet(list, default)
	local set = {}
	if type(list) ~= "table" then
		for i = 1, #default do set[default[i]] = true end
		return set
	end
	for i = 1, #list do set[list[i]] = true end
	return set
end

local function byOrderThenId(a, b)
	if a.order ~= b.order then return a.order < b.order end
	return a.id < b.id
end

local function listOf(map)
	local list = {}
	for _, row in pairs(map) do list[#list + 1] = row end
	table.sort(list, byOrderThenId)
	return list
end

local function entryList()
	if not VRadial._entryList then VRadial._entryList = listOf(VRadial.entries) end
	return VRadial._entryList
end

local function ruleList()
	if not VRadial._ruleList then VRadial._ruleList = listOf(VRadial.rules) end
	return VRadial._ruleList
end

--------------------------------------------------------------------------------
-- registration
--------------------------------------------------------------------------------

function VRadial.register(row)
	if type(row) ~= "table" or type(row.id) ~= "string" then
		log("register: a row needs a string id")
		return false
	end
	if type(row.build) ~= "function" then
		log("register: " .. row.id .. " needs a build function")
		return false
	end
	row.order    = tonumber(row.order) or 100
	row.surfaces = surfaceSet(row.surfaces, { "outside", "seated" })
	if row.surfaces.context then
		row.surfaces.context = nil
		log("register: " .. row.id .. " declared surface 'context' - register it with "
			.. "VContext.register for that; it stays armed here for the radial surfaces only")
	end
	row._errors, row._broken = nil, nil
	VRadial.entries[row.id] = row
	VRadial._entryList = nil
	return true
end

function VRadial.unregister(id)
	VRadial.entries[id] = nil
	VRadial._entryList = nil
end

function VRadial.suppress(rule)
	if type(rule) ~= "table" or type(rule.id) ~= "string" then
		log("suppress: a rule needs a string id")
		return false
	end
	if rule.match == nil and rule.icon == nil and rule.text == nil and rule.handler == nil then
		log("suppress: " .. rule.id .. " matches nothing - give it icon, text, handler or match")
		return false
	end
	if type(rule.icon) == "string" then rule.icon = getTexture(rule.icon) end
	rule.order    = tonumber(rule.order) or 100
	rule.owner    = rule.owner or rule.id
	rule.surfaces = surfaceSet(rule.surfaces, { "outside", "seated" })
	if rule.surfaces.context then
		rule.surfaces.context = nil
		log("suppress: " .. rule.id .. " declared surface 'context' - this component cannot serve "
			.. "it (see VContextCore); the rule stays armed for the radial surfaces only")
	end
	rule._errors, rule._broken = nil, nil
	VRadial.rules[rule.id] = rule
	VRadial._ruleList = nil
	VRadial._ruleCount = 0
	for _ in pairs(VRadial.rules) do VRadial._ruleCount = VRadial._ruleCount + 1 end
	return true
end

function VRadial.unsuppress(id)
	VRadial.rules[id] = nil
	VRadial._ruleList = nil
	VRadial._ruleCount = 0
	for _ in pairs(VRadial.rules) do VRadial._ruleCount = VRadial._ruleCount + 1 end
end

function VRadial.setOwnerEnabled(owner, enabled)
	if enabled == false then
		VRadial.owners[owner] = false
	else
		VRadial.owners[owner] = nil
	end
end

function VRadial.isOwnerEnabled(owner)
	return VRadial.owners[owner] ~= false
end

--------------------------------------------------------------------------------
-- context, derived from the menu itself - never from "we are the outermost wrapper"
--------------------------------------------------------------------------------

local function contextFor(menu)
	local playerNum = menu and menu.playerNum
	if playerNum == nil then return nil end
	local playerObj = getSpecificPlayer(playerNum)
	if not playerObj then return nil end
	local vehicle = playerObj:getVehicle()
	local seated = vehicle ~= nil
	if not vehicle and ISVehicleMenu and ISVehicleMenu.getVehicleToInteractWith then
		vehicle = ISVehicleMenu.getVehicleToInteractWith(playerObj)
	end
	if not vehicle then return nil end
	return {
		player    = playerObj,
		playerNum = playerNum,
		vehicle   = vehicle,
		seated    = seated,
		surface   = seated and "seated" or "outside",
	}
end

local function textureName(texture)
	if texture == nil then return "nil" end
	local ok, name = pcall(function() return texture:getName() end)
	if ok and name then return tostring(name) end
	return "?"
end

--------------------------------------------------------------------------------
-- suppression, at the sink
--------------------------------------------------------------------------------

function VRadial.swallow(menu, text, texture, command, arg1, arg2)
	local rules = ruleList()
	local ctx = nil
	if VRadial._probe then
		ctx = contextFor(menu)
		log('probe: text="' .. tostring(text) .. '" icon=' .. textureName(texture)
			.. ' handler=' .. tostring(command ~= nil)
			.. ' surface=' .. (ctx and ctx.surface or "none"))
	end
	if ctx == nil then ctx = contextFor(menu) end
	if not ctx then return false end
	local entry = { text = text, icon = texture, handler = command,
		arg1 = arg1, arg2 = arg2, surface = ctx.surface }
	return VRadial.matchRules(entry, ctx) ~= nil
end

function VRadial.matchRules(entry, ctx)
	local rules = ruleList()
	for i = 1, #rules do
		local rule = rules[i]
		if not rule._broken and VRadial.owners[rule.owner] ~= false then
			local hit = true
			if rule.icon    ~= nil and rule.icon    ~= entry.icon    then hit = false end
			if hit and rule.text    ~= nil and rule.text    ~= entry.text    then hit = false end
			if hit and rule.handler ~= nil and rule.handler ~= entry.handler then hit = false end
			if hit then
				if ctx and rule.surfaces[entry.surface or ctx.surface] then
					local whenOk = true
					if rule.when then
						local result, ok = safeCall(rule, rule.when, ctx)
						whenOk = ok and result and true or false
					end
					if whenOk then
						local matched = true
						if rule.match then
							local result, ok = safeCall(rule, rule.match, entry, ctx)
							matched = ok and result and true or false
						end
						if matched then
							if VRadial.debug then
								log('swallowed "' .. tostring(entry.text) .. '" by rule ' .. rule.id)
							end
							return rule
						end
					end
				end
			end
		end
	end
	return nil
end

function VRadial.probe(on)
	VRadial._probe = (on ~= false)
	log("probe " .. (VRadial._probe and "ARMED - open a vehicle radial" or "off"))
end

--------------------------------------------------------------------------------
-- reorder: move slices of the FINISHED radial, foreign ones included
--------------------------------------------------------------------------------

VRadial.DEFAULT_ORDER = 100
VRadial.orders = VRadial.orders or {}
VRadial._orderList = nil

local function orderList()
	if not VRadial._orderList then VRadial._orderList = listOf(VRadial.orders) end
	return VRadial._orderList
end

function VRadial.reorder(spec)
	if type(spec) ~= "table" or type(spec.id) ~= "string" then
		log("reorder: a spec needs a string id"); return false
	end
	if spec.match == nil then log("reorder: " .. spec.id .. " needs a match"); return false end
	if tonumber(spec.to) == nil then log("reorder: " .. spec.id .. " needs a numeric `to`"); return false end
	spec.owner = spec.owner or spec.id
	spec.order = tonumber(spec.order) or 100
	spec._errors, spec._broken = nil, nil
	VRadial.orders[spec.id] = spec
	VRadial._orderList = nil
	return true
end

function VRadial.unreorder(id)
	VRadial.orders[id] = nil
	VRadial._orderList = nil
end

local function entryOfSlice(sl, surface)
	local c = sl.command or {}
	return { text = sl.text, icon = sl.texture, handler = c[1],
		arg1 = c[2], arg2 = c[3], arg3 = c[4], arg4 = c[5], arg5 = c[6], arg6 = c[7],
		surface = surface }
end

function VRadial.sweepSlices(menu, ctx)
	if not menu or type(menu.slices) ~= "table" or #menu.slices < 2 then return false end
	local specs = orderList()
	if #specs == 0 then return false end
	local keyed, moved = {}, false
	for k = 1, #menu.slices do
		local entry = entryOfSlice(menu.slices[k], ctx and ctx.surface or "outside")
		local key = VRadial.DEFAULT_ORDER
		for si = 1, #specs do
			local spec = specs[si]
			if not spec._broken and VRadial.owners[spec.owner] ~= false
					and (not spec.surfaces or spec.surfaces[entry.surface]) then
				local result, ok = safeCall(spec, spec.match, entry, ctx)
				if ok and result then key = tonumber(spec.to) or key break end
			end
		end
		keyed[k] = { sl = menu.slices[k], key = key, idx = k }
		if key ~= VRadial.DEFAULT_ORDER then moved = true end
	end
	if not moved then return false end
	table.sort(keyed, function(a, b)
		if a.key ~= b.key then return a.key < b.key end
		return a.idx < b.idx
	end)
	for k = 1, #keyed do menu.slices[k] = keyed[k].sl end
	return true
end

--------------------------------------------------------------------------------
-- emit
--------------------------------------------------------------------------------

local function emitItem(item, ctx, slice)
	if type(item) ~= "table" or item.text == nil then return end
	if not slice then return end
	local icon = item.icon
	if type(icon) == "string" then icon = getTexture(icon) end
	local handler = item.handler
	if item.disabled then handler = nil end
	local args = item.args or {}
	slice:addSlice(item.text, icon, handler, args[1], args[2], args[3], args[4], args[5], args[6])
end

function VRadial.emit(ctx, slice)
	local rows = entryList()
	for i = 1, #rows do
		local row = rows[i]
		if not row._broken and row.surfaces[ctx.surface] then
			local pass = true
			if row.when then
				local result, ok = safeCall(row, row.when, ctx)
				pass = ok and result and true or false
			end
			if pass then
				local add = function(item) emitItem(item, ctx, slice) end
				safeCall(row, row.build, ctx, add)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- install: three hooks, none of which needs to be the outermost link in its chain
--------------------------------------------------------------------------------

local function installSliceShadow()
	if not ISRadialMenu or type(ISRadialMenu.addSlice) ~= "function" then return end
	if ISRadialMenu.addSlice == VRadial._shadow then return end
	if VRadial._shadow and VRadial._rearms >= MAX_REARMS then return end
	if VRadial._shadow then VRadial._rearms = VRadial._rearms + 1 end
	local prev = ISRadialMenu.addSlice
	local shadow = function(self, text, texture, command, a1, a2, a3, a4, a5, a6)
		if (VRadial._ruleCount > 0 or VRadial._probe) and VRadial.swallow(self, text, texture, command, a1, a2) then
			return
		end
		return prev(self, text, texture, command, a1, a2, a3, a4, a5, a6)
	end
	VRadial._shadow = shadow
	ISRadialMenu.addSlice = shadow
end

local function installMenuHooks()
	if not ISVehicleMenu then return end

	if not VRadial._fillHooked and type(ISVehicleMenu.FillPartMenu) == "function" then
		local prev = ISVehicleMenu.FillPartMenu
		ISVehicleMenu.FillPartMenu = function(playerIndex, context, slice, vehicle)
			local result = prev(playerIndex, context, slice, vehicle)
			local ok, err = pcall(function()
				if not slice then return end
				if not vehicle then return end
				local playerObj = getSpecificPlayer(playerIndex)
				if not playerObj then return end
				if playerObj:DistToProper(vehicle) >= 4 then return end
				local ctx = {
					player    = playerObj,
					playerNum = playerIndex,
					vehicle   = vehicle,
					seated    = playerObj:getVehicle() ~= nil,
					surface   = "outside",
				}
				VRadial.emit(ctx, slice)
				VRadial.sweepSlices(slice, ctx)
			end)
			if not ok then log("FillPartMenu: " .. tostring(err)) end
			return result
		end
		VRadial._fillHooked = true
	end

	if not VRadial._seatedHooked and type(ISVehicleMenu.showRadialMenu) == "function" then
		local prev = ISVehicleMenu.showRadialMenu
		ISVehicleMenu.showRadialMenu = function(playerObj)
			prev(playerObj)
			local ok, err = pcall(function()
				if UIManager.getSpeedControls() and UIManager.getSpeedControls():getCurrentGameSpeed() == 0 then return end
				local vehicle = playerObj:getVehicle()
				if not vehicle then return end
				local menu = getPlayerRadialMenu(playerObj:getPlayerNum())
				if not menu then return end
				if menu:isReallyVisible() then return end
				local ctx = {
					player    = playerObj,
					playerNum = playerObj:getPlayerNum(),
					vehicle   = vehicle,
					seated    = true,
					surface   = "seated",
				}
				VRadial.emit(ctx, menu)
				VRadial.sweepSlices(menu, ctx)
			end)
			if not ok then log("showRadialMenu: " .. tostring(err)) end
		end
		VRadial._seatedHooked = true
	end
end

function VRadial.install()
	if getCore() and getCore():isDedicated() then return end
	installSliceShadow()
	installMenuHooks()
end

function VRadial.report()
	log("version " .. VERSION .. ", " .. #entryList() .. " entries, " .. #ruleList() .. " rules, "
		.. "shadow=" .. tostring(ISRadialMenu and ISRadialMenu.addSlice == VRadial._shadow)
		.. " fill=" .. tostring(VRadial._fillHooked == true)
		.. " seated=" .. tostring(VRadial._seatedHooked == true))
	local rules = ruleList()
	for i = 1, #rules do
		log("  rule " .. rules[i].id .. " owner=" .. tostring(rules[i].owner)
			.. " enabled=" .. tostring(VRadial.owners[rules[i].owner] ~= false))
	end
end

if Events and not VRadial._eventsHooked then
	local arm = function() VRadial.install() end
	if Events.OnGameBoot then Events.OnGameBoot.Add(arm) end
	if Events.OnGameStart then Events.OnGameStart.Add(arm) end
	if Events.OnCreatePlayer then Events.OnCreatePlayer.Add(arm) end
	VRadial._eventsHooked = true
end
