-- Shared keep-alive for the vehicle part-update loop: sustain predicates, an explicit wake,
-- and the script-side init latch. Vanilla's own server Lua switches the loop OFF from inside
-- the loop; a sustain predicate keeps it armed while a feature needs ticks, and wake() starts
-- a dark loop when a feature switches on.
-- VENDORED FILE - copied verbatim into every carrying library, never edited in place.
-- Highest VERSION wins and upgrades the live table in place, so predicates already registered
-- survive the election.

local VERSION = 1

if VUpdate and VUpdate.VERSION and VUpdate.VERSION >= VERSION then return end

local firstLoad = (VUpdate == nil)

VUpdate            = VUpdate or {}
VUpdate.VERSION    = VERSION
VUpdate.predicates = VUpdate.predicates or {}
VUpdate.debug      = VUpdate.debug or false
VUpdate._gen       = VUpdate._gen or 0
VUpdate._predList  = nil
VUpdate.stats      = VUpdate.stats or { installs = 0, wakes = 0, engineCalls = 0, rearms = 0 }

local function log(msg) print("[VUpdate] " .. tostring(msg)) end

local function safeCall(row, fn, a)
	local ok, result = pcall(fn, a)
	if ok then return result, true end
	row._errors = (row._errors or 0) + 1
	if row._errors >= 3 and not row._broken then
		row._broken = true
		log("predicate '" .. tostring(row.id) .. "' disabled after 3 errors: " .. tostring(result))
	end
	return nil, false
end

local function predList()
	if not VUpdate._predList then
		local out = {}
		for _, p in pairs(VUpdate.predicates) do out[#out + 1] = p end
		table.sort(out, function(a, b) return tostring(a.id) < tostring(b.id) end)
		VUpdate._predList = out
	end
	return VUpdate._predList
end

function VUpdate.register(spec)
	if type(spec) ~= "table" or type(spec.id) ~= "string" or spec.id == "" then
		log("register: needs { id, sustain }"); return false
	end
	if type(spec.sustain) ~= "function" then
		log("register: '" .. spec.id .. "' needs a sustain function"); return false
	end
	VUpdate.predicates[spec.id] = { id = spec.id, sustain = spec.sustain }
	VUpdate._predList = nil
	return true
end

function VUpdate.unregister(id)
	if not VUpdate.predicates[id] then return false end
	VUpdate.predicates[id] = nil
	VUpdate._predList = nil
	return true
end

function VUpdate.sustains(vehicle)
	local list = predList()
	for i = 1, #list do
		local p = list[i]
		if not p._broken then
			local want = safeCall(p, p.sustain, vehicle)
			if want then return true, p.id end
		end
	end
	return false
end

function VUpdate.wake(vehicle)
	if not vehicle or not vehicle.setNeedPartsUpdate then return false end
	vehicle:setNeedPartsUpdate(true)
	VUpdate.stats.wakes = VUpdate.stats.wakes + 1
	if VUpdate.debug then log("wake -> " .. tostring(vehicle.getId and vehicle:getId() or "?")) end
	return true
end

VUpdate.Init = VUpdate.Init or {}
function VUpdate.Init.Wake(vehicle, part)
	VUpdate.wake(vehicle)
end

-- The behaviour half of the wrapper, dispatched THROUGH THE TABLE so a version upgrade takes
function VUpdate._onEngine(orig, vehicle, part, elapsedMinutes)
	VUpdate.stats.engineCalls = VUpdate.stats.engineCalls + 1
	orig(vehicle, part, elapsedMinutes)
	if vehicle then
		local want, byId = VUpdate.sustains(vehicle)
		if want and vehicle.setNeedPartsUpdate then
			vehicle:setNeedPartsUpdate(true)
			VUpdate.stats.rearms = VUpdate.stats.rearms + 1
			if VUpdate.debug then
				log("sustain '" .. tostring(byId) .. "' -> "
					.. tostring(vehicle.getId and vehicle:getId() or "?"))
			end
		end
	end
end

function VUpdate.install()
	if not (Vehicles and Vehicles.Update and type(Vehicles.Update.Engine) == "function") then
		return false
	end
	Vehicles.Init = Vehicles.Init or {}
	Vehicles.Init.VUpdateWake = function(vehicle, part) return VUpdate.Init.Wake(vehicle, part) end

	local cur = Vehicles.Update.Engine
	if cur == VUpdate._wrapper then return true end
	VUpdate._gen = VUpdate._gen + 1
	local myGen, orig = VUpdate._gen, cur
	local w = function(vehicle, part, elapsedMinutes)
		if VUpdate._gen ~= myGen or not VUpdate._onEngine then
			return orig(vehicle, part, elapsedMinutes)
		end
		return VUpdate._onEngine(orig, vehicle, part, elapsedMinutes)
	end
	VUpdate._wrapper = w
	Vehicles.Update.Engine = w
	VUpdate.stats.installs = VUpdate.stats.installs + 1
	if VUpdate.debug then log("installed (gen " .. myGen .. ")") end
	return true
end

function VUpdate.report()
	local rows = {}
	local list = predList()
	for i = 1, #list do
		rows[#rows + 1] = "predicate " .. list[i].id .. (list[i]._broken and "  BROKEN" or "")
	end
	local wrapped = (Vehicles and Vehicles.Update and Vehicles.Update.Engine == VUpdate._wrapper)
		and true or false
	return { version = VUpdate.VERSION, wrapped = wrapped, gen = VUpdate._gen,
		rows = rows, stats = VUpdate.stats }
end

if firstLoad and Events then
	if Events.OnInitGlobalModData then
		Events.OnInitGlobalModData.Add(function() VUpdate.install() end)
	end
	if Events.OnGameStart then
		Events.OnGameStart.Add(function() VUpdate.install() end)
	end
end
