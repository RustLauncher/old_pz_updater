-- Shared vehicle CONTEXT-MENU registry: suppress entries other mods add - matching a parent by
-- its children where nothing else identifies it - and reorder what is left. Sweeps the BUILT
-- menu, after every builder has run.
-- VENDORED FILE - copied verbatim into every carrying library, never edited in place.
-- Highest VERSION wins and upgrades the live table in place, so rules already registered
-- survive the election.

local VERSION = 3

if VContext and VContext.VERSION and VContext.VERSION >= VERSION then return end

VContext            = VContext or {}
VContext.VERSION    = VERSION
VContext.entries    = VContext.entries  or {}
VContext.rules      = VContext.rules    or {}
VContext.orders     = VContext.orders   or {}
VContext.owners     = VContext.owners   or {}
VContext.debug      = VContext.debug    or false
VContext._entryList = nil
VContext._ruleList  = nil
VContext._orderList = nil
VContext._ruleCount = VContext._ruleCount or 0
VContext._probe     = false

local function log(msg) print("[VContext] " .. tostring(msg)) end

local function safeCall(row, fn, a, b)
	local ok, result = pcall(fn, a, b)
	if ok then return result, true end
	row._errors = (row._errors or 0) + 1
	if row._errors >= 3 and not row._broken then
		row._broken = true
		log("rule '" .. tostring(row.id) .. "' disabled after 3 errors: " .. tostring(result))
	end
	return nil, false
end

local function listOf(map)
	local out = {}
	for _, v in pairs(map) do out[#out + 1] = v end
	table.sort(out, function(a, b)
		if a.order ~= b.order then return (a.order or 100) < (b.order or 100) end
		return tostring(a.id) < tostring(b.id)
	end)
	return out
end

local function ruleList()
	if not VContext._ruleList then VContext._ruleList = listOf(VContext.rules) end
	return VContext._ruleList
end

local function orderList()
	if not VContext._orderList then VContext._orderList = listOf(VContext.orders) end
	return VContext._orderList
end

local function entryList()
	if not VContext._entryList then VContext._entryList = listOf(VContext.entries) end
	return VContext._entryList
end

--------------------------------------------------------------------------------
-- registration
--------------------------------------------------------------------------------

function VContext.suppress(rule)
	if type(rule) ~= "table" or type(rule.id) ~= "string" then
		log("suppress: a rule needs a string id"); return false
	end
	if rule.match == nil and rule.icon == nil and rule.text == nil and rule.handler == nil then
		log("suppress: " .. rule.id .. " matches nothing - give it icon, text, handler or match")
		return false
	end
	if type(rule.icon) == "string" then rule.icon = getTexture(rule.icon) end
	rule.order = tonumber(rule.order) or 100
	rule.owner = rule.owner or rule.id
	rule._errors, rule._broken = nil, nil
	VContext.rules[rule.id] = rule
	VContext._ruleList = nil
	VContext._ruleCount = 0
	for _ in pairs(VContext.rules) do VContext._ruleCount = VContext._ruleCount + 1 end
	return true
end

function VContext.unsuppress(id)
	VContext.rules[id] = nil
	VContext._ruleList = nil
	VContext._ruleCount = 0
	for _ in pairs(VContext.rules) do VContext._ruleCount = VContext._ruleCount + 1 end
end

VContext.DEFAULT_ORDER = 100

function VContext.reorder(spec)
	if type(spec) ~= "table" or type(spec.id) ~= "string" then
		log("reorder: a spec needs a string id"); return false
	end
	if spec.match == nil then log("reorder: " .. spec.id .. " needs a match"); return false end
	if tonumber(spec.to) == nil then log("reorder: " .. spec.id .. " needs a numeric `to`"); return false end
	spec.owner = spec.owner or spec.id
	spec.order = tonumber(spec.order) or 100
	spec._errors, spec._broken = nil, nil
	VContext.orders[spec.id] = spec
	VContext._orderList = nil
	return true
end

function VContext.unreorder(id)
	VContext.orders[id] = nil
	VContext._orderList = nil
end

function VContext.setOwnerEnabled(owner, enabled)
	if type(owner) ~= "string" then return false end
	VContext.owners[owner] = (enabled ~= false)
	return true
end

function VContext.isOwnerEnabled(owner)
	return VContext.owners[owner] ~= false
end

function VContext.probe(on)
	VContext._probe = (on ~= false)
	log("probe " .. (VContext._probe and "ARMED - right-click a vehicle" or "off"))
end

function VContext.register(row)
	if type(row) ~= "table" or type(row.id) ~= "string" or type(row.build) ~= "function" then
		log("register: needs { id = string, build = function }")
		return false
	end
	row.order = tonumber(row.order) or 100
	row._errors, row._broken = nil, nil
	VContext.entries[row.id] = row
	VContext._entryList = nil
	return true
end

function VContext.unregister(id)
	VContext.entries[id] = nil
	VContext._entryList = nil
end

--------------------------------------------------------------------------------
-- emit: our own entries, rendered with NESTING
--------------------------------------------------------------------------------

local function renderSubmenu(root, menu, option, list, depth)
	if type(list) ~= "table" or #list == 0 or depth > 6 then return end
	local sub = ISContextMenu:getNew(root)
	menu:addSubMenu(option, sub)
	for k = 1, #list do
		local it = list[k]
		if type(it) == "table" and it.text ~= nil then
			local sargs = it.args or {}
			local sh = (not it.disabled) and it.handler or nil
			local sopt = sub:addOption(it.text, sargs[1], sh,
				sargs[2], sargs[3], sargs[4], sargs[5], sargs[6])
			if sopt then
				local sicon = it.icon
				if type(sicon) == "string" then sicon = getTexture(sicon) end
				if sicon then sopt.iconTexture = sicon end
				if it.disabled then
					sopt.notAvailable = true
					if it.reason and ISInventoryPaneContextMenu
							and ISInventoryPaneContextMenu.addToolTip then
						local tt = ISInventoryPaneContextMenu.addToolTip()
						tt.description = it.reason
						sopt.toolTip = tt
					end
				end
				renderSubmenu(root, sub, sopt, it.submenu, depth + 1)
			end
		end
	end
end

local function emitItem(item, context)
	if type(item) ~= "table" or item.text == nil or not context then return end
	local icon = item.icon
	if type(icon) == "string" then icon = getTexture(icon) end
	local handler = item.handler
	if item.disabled then handler = nil end
	local args = item.args or {}
	local option = context:addOption(item.text, args[1], handler, args[2], args[3], args[4], args[5], args[6])
	if not option then return end
	if icon then option.iconTexture = icon end
	renderSubmenu(context, context, option, item.submenu, 1)
	if item.disabled then
		option.notAvailable = true
		if item.reason and ISInventoryPaneContextMenu and ISInventoryPaneContextMenu.addToolTip then
			local tt = ISInventoryPaneContextMenu.addToolTip()
			tt.description = item.reason
			option.toolTip = tt
		end
	end
end

function VContext.emit(ctx, context)
	local rows = entryList()
	for i = 1, #rows do
		local row = rows[i]
		if not row._broken and VContext.owners[row.owner or row.id] ~= false then
			local add = function(item) emitItem(item, context) end
			local _, ok = safeCall(row, row.build, ctx, add)
			if not ok and VContext.debug then log("entry " .. row.id .. " failed") end
		end
	end
end

--------------------------------------------------------------------------------
-- the sweep: read the BUILT menu, match, remove, reorder
--------------------------------------------------------------------------------

local function textureName(texture)
	if texture == nil then return "nil" end
	local ok, name = pcall(function() return texture:getName() end)
	if ok and name then return tostring(name) end
	return "?"
end

local function entryOf(option, ctx, menu)
	return {
		text    = option.name,
		icon    = option.iconTexture,
		handler = option.onSelect,
		target  = option.target,
		arg1    = option.param1,  arg2 = option.param2,
		arg3    = option.param3,  arg4 = option.param4,
		arg5    = option.param5,  arg6 = option.param6,
		surface = "context",
		option  = option,
		-- VERSION 3: the menu being swept, so a match() can resolve a parent's children -
		menu    = menu,
	}
end

function VContext.matchRules(entry, ctx)
	local rules = ruleList()
	for i = 1, #rules do
		local rule = rules[i]
		if not rule._broken and VContext.owners[rule.owner] ~= false then
			local hit = true
			if rule.icon    ~= nil and rule.icon    ~= entry.icon    then hit = false end
			if hit and rule.text    ~= nil and rule.text    ~= entry.text    then hit = false end
			if hit and rule.handler ~= nil and rule.handler ~= entry.handler then hit = false end
			if hit then
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
					if matched then return rule end
				end
			end
		end
	end
	return nil
end

local function removeAt(menu, index)
	local opt = menu.options[index]
	if not opt then return end
	if menu.optionPool then table.insert(menu.optionPool, opt) end
	for i = index + 1, #menu.options do
		menu.options[i - 1] = menu.options[i]
		menu.options[i - 1].id = i - 1
	end
	menu.options[#menu.options] = nil
	if menu.numOptions then menu.numOptions = menu.numOptions - 1 end
	if menu.calcHeight then pcall(function() menu:calcHeight() end) end
end

function VContext.sweep(menu, ctx)
	if not menu or type(menu.options) ~= "table" then return 0, false end
	if VContext._ruleCount == 0 and #orderList() == 0 and not VContext._probe then return 0, false end

	local removed = 0
	local i = 1
	while i <= #menu.options do
		local entry = entryOf(menu.options[i], ctx, menu)
		if VContext._probe then
			log('probe: text="' .. tostring(entry.text) .. '" icon=' .. textureName(entry.icon)
				.. ' handler=' .. tostring(entry.handler ~= nil)
				.. ' target=' .. tostring(entry.target))
		end
		local rule = (VContext._ruleCount > 0) and VContext.matchRules(entry, ctx) or nil
		if rule then
			if VContext.debug then
				log('swallowed "' .. tostring(entry.text) .. '" by rule ' .. rule.id)
			end
			removeAt(menu, i)
			removed = removed + 1
		else
			i = i + 1
		end
	end

	local specs = orderList()
	local moved = false
	if #specs > 0 and #menu.options > 1 then
		local keyed = {}
		for k = 1, #menu.options do
			local entry = entryOf(menu.options[k], ctx, menu)
			local key = VContext.DEFAULT_ORDER
			for si = 1, #specs do
				local spec = specs[si]
				if not spec._broken and VContext.owners[spec.owner] ~= false then
					local result, ok = safeCall(spec, spec.match, entry, ctx)
					if ok and result then key = tonumber(spec.to) or key break end
				end
			end
			keyed[k] = { opt = menu.options[k], key = key, idx = k }
			if key ~= VContext.DEFAULT_ORDER then moved = true end
		end
		if moved then
			table.sort(keyed, function(a, b)
				if a.key ~= b.key then return a.key < b.key end
				return a.idx < b.idx
			end)
			for k = 1, #keyed do
				menu.options[k] = keyed[k].opt
				menu.options[k].id = k
			end
		end
	end

	return removed, moved
end

--------------------------------------------------------------------------------
-- the hook
--------------------------------------------------------------------------------

function VContext.install()
	if not ISVehicleMenu or VContext._fillHooked then return end
	if type(ISVehicleMenu.FillPartMenu) ~= "function" then return end
	local prev = ISVehicleMenu.FillPartMenu
	ISVehicleMenu.FillPartMenu = function(playerIndex, context, slice, vehicle)
		local result = prev(playerIndex, context, slice, vehicle)
		local ok, err = pcall(function()
			if slice or not context then return end
			if not vehicle then return end
			local playerObj = getSpecificPlayer(playerIndex)
			if not playerObj then return end
			if playerObj:DistToProper(vehicle) >= 4 then return end
			local ctx = {
				player    = playerObj,
				playerNum = playerIndex,
				vehicle   = vehicle,
				seated    = playerObj:getVehicle() ~= nil,
				surface   = "context",
			}
			VContext.emit(ctx, context)
			VContext.sweep(context, ctx)
			return
		end)
		if not ok then log("FillPartMenu: " .. tostring(err)) end
		return result
	end
	VContext._fillHooked = true
end

function VContext.report()
	local rows = {}
	for _, e in pairs(VContext.entries) do rows[#rows + 1] = "entry " .. e.id .. (e._broken and " BROKEN" or "") end
	for _, r in pairs(VContext.rules)  do rows[#rows + 1] = "rule "  .. r.id .. " owner=" .. tostring(r.owner) .. (r._broken and " BROKEN" or "") end
	for _, o in pairs(VContext.orders) do rows[#rows + 1] = "order " .. o.id .. " to=" .. tostring(o.to) .. (o._broken and " BROKEN" or "") end
	table.sort(rows)
	return { version = VERSION, hooked = VContext._fillHooked == true, rows = rows }
end

VContext.install()
if Events and Events.OnGameStart then Events.OnGameStart.Add(VContext.install) end
