-- Server-side handler for Better Corpse Burning
-- Sequential fire spread with chain reaction using IsoFireManager

local BCBConfig = require("BetterCorpseBurning/config")

local spreadQueue = {}
local spreadFrameCount = 0
local spreadActive = false
local function getFramesPerTile()
	return BCBConfig.FIRE_SPREAD_SPEED or 150
end

-- "Extinguish Fire When Done": yangını ceset yığınından kaçtığı yerde kovalar.
-- Eski tasarım sadece ceset karelerinin sabit 4-tile çevresini tek sefer süpürüyordu;
-- ceset yangını kendiliğinden sönünce (StartFire life=500) 0 yangın bulup pes ediyor,
-- duvara/eşyaya sıçrayıp uzaklaşan yangın hiç söndürülmüyordu.
-- Yeni tasarım: her süpürmede (1) her ceset karesinin BASE_RADIUS kadar çevresi taranır
-- (evin hemen yanındaki yangınlar), (2) bir önceki süpürmede YANAN bulunan her kare de
-- SCAN_RADIUS ile taranır ve o kareler sonraki süpürmenin iz sürme merkezi olur.
-- Böylece yangın zeminden duvara, duvardan eşyaya sıçradıkça adım adım kovalanır.
local EXTINGUISH_GRACE_FRAMES = 600   -- son ceset tutuştuktan sonra bekle (cesetler yanıp bitsin)
local EXTINGUISH_SWEEP_INTERVAL = 150 -- süpürmeler arası süre
local EXTINGUISH_BASE_RADIUS = 8      -- her ceset karesi etrafındaki güvenlik taraması
local EXTINGUISH_SCAN_RADIUS = 4      -- bilinen yanan kare etrafındaki iz sürme yarıçapı
local EXTINGUISH_CLEAN_STREAK = 2     -- ardışık "temiz" süpürme = iş bitti
local EXTINGUISH_MAX_SWEEPS = 45      -- güvenlik: azami süpürme sayısı
local EXTINGUISH_MAX_CENTERS = 250    -- güvenlik: azami iz sürülen kare sayısı

local extinguishSeeds = {}      -- bekleyen ceset kareleri {x,y,z}
local extinguishCenters = {}    -- iz sürülecek merkezler {x,y,z} (önceki süpürmede yananlar)
local extinguishActive = false
local extinguishSweeps = 0
local extinguishCleanStreak = 0
local extinguishTotalStopped = 0
local extinguishNextSweepAt = nil
local extinguishSeen = {}
local extinguishSeenCount = 0
local extinguishCapped = false

local ashWatchList = {}
local ASH_CHECK_INTERVAL = 30

local function ensureTickActive()
	if not spreadActive then
		spreadActive = true
		Events.OnTick.Add(onSpreadTick)
	end
end

--- Ceset karesini söndürme operasyonuna tohum olarak ekle.
local function addExtinguishSeed(square)
	if not BCBConfig.AUTO_EXTINGUISH then return end
	if not square then return end
	extinguishSeeds[#extinguishSeeds + 1] = {
		x = math.floor(square:getX()),
		y = math.floor(square:getY()),
		z = square:getZ(),
	}
	-- Operasyon zaten kovalıyorsa yeni yığına kendi grace süresini tanı
	-- (cesetlerin yanıp kül olması için alevin bir süre kalması gerekir)
	if extinguishActive then
		extinguishNextSweepAt = spreadFrameCount + EXTINGUISH_GRACE_FRAMES
		extinguishCleanStreak = 0
	end
	ensureTickActive()
end

--- Tek süpürme: seeds + iz sürme merkezleri çevresini tara, yananları söndür,
--- yeni yanan kareleri bir sonraki süpürme için merkez olarak topla.
local function runExtinguishSweep()
	local stopped = 0
	local foundByKey = {}
	local foundList = {}
	local cell = getCell()

	local function scan(x, y, z, radius)
		for dx = -radius, radius do
			for dy = -radius, radius do
				local ok, sq = pcall(cell.getGridSquare, cell, x + dx, y + dy, z)
				if ok and sq then
					local okBurning, burning = pcall(sq.has, sq, IsoFlagType.burning)
					if okBurning and burning then
						-- Server-side: stopFire() global fonksiyonu (vanilla ISPutOutFire ile doğrulanmış API)
						local okStop = pcall(stopFire, sq)
						if okStop then
							stopped = stopped + 1
							local fx = x + dx
							local fy = y + dy
							local key = fx .. "," .. fy
							if not foundByKey[key] then
								foundByKey[key] = true
								foundList[#foundList + 1] = { x = fx, y = fy, z = z }
							end
						end
					end
				end
			end
		end
	end

	for _, s in ipairs(extinguishSeeds) do
		scan(s.x, s.y, s.z, EXTINGUISH_BASE_RADIUS)
	end
	for _, c in ipairs(extinguishCenters) do
		scan(c.x, c.y, c.z, EXTINGUISH_SCAN_RADIUS)
	end

	-- Yeni yanan kareleri iz sürme merkezlerine ekle (tekilleştirerek, bütçe sınırıyla)
	local nextCenters = {}
	for _, f in ipairs(foundList) do
		local key = f.x .. "," .. f.y .. "," .. f.z
		if not extinguishSeen[key] then
			extinguishSeen[key] = true
			extinguishSeenCount = extinguishSeenCount + 1
		end
		if extinguishSeenCount <= EXTINGUISH_MAX_CENTERS then
			nextCenters[#nextCenters + 1] = f
		end
	end
	if extinguishSeenCount > EXTINGUISH_MAX_CENTERS and not extinguishCapped then
		extinguishCapped = true
		print("[BCB] Extinguish WARNING: fire area too large, chase capped at " .. tostring(EXTINGUISH_MAX_CENTERS) .. " tiles")
	end
	extinguishCenters = nextCenters
	extinguishTotalStopped = extinguishTotalStopped + stopped
	return stopped
end

--- Yanık zemin tile'larını kaldır (vanilla ISClearAshes ile doğrulanmış API)
--- Kalan burnt tile sayısını döndürür (0 = temizlendi)
local function removeBurntTiles(square)
	local okObjs, objects = pcall(square.getObjects, square)
	if not okObjs or not objects then return 0 end
	local removed = 0
	for i = objects:size() - 1, 0, -1 do
		local obj = objects:get(i)
		local okSpr, spr = pcall(obj.getSprite, obj)
		if okSpr and spr then
			local okName, nm = pcall(spr.getName, spr)
			if okName and nm and tostring(nm):find("floors_burnt_01_", 1, true) then
				-- Vanilla ISClearAshes: transmitRemoveItemFromSquare + getObjects():remove()
				pcall(square.transmitRemoveItemFromSquare, square, obj)
				pcall(objects.remove, objects, obj)
				removed = removed + 1
			end
		end
	end
	if removed > 0 then
		print("[BCB] NoAsh: removed " .. tostring(removed) .. " burnt tiles")
	end
	-- Count remaining burnt tiles after removal
	local remaining = 0
	local okObjs2, objects2 = pcall(square.getObjects, square)
	if okObjs2 and objects2 then
		for i = 0, objects2:size() - 1 do
			local obj = objects2:get(i)
			local okSpr, spr = pcall(obj.getSprite, obj)
			if okSpr and spr then
				local okName, nm = pcall(spr.getName, spr)
				if okName and nm and tostring(nm):find("floors_burnt_01_", 1, true) then
					remaining = remaining + 1
				end
			end
		end
	end
	return remaining
end

local function checkAshWatchList()
	for i = #ashWatchList, 1, -1 do
		local w = ashWatchList[i]
		local sq = getCell():getGridSquare(w.x, w.y, w.z)
		if not sq then
			table.remove(ashWatchList, i)
		else
			-- Ateş hâlâ yanıyor mu? (vanilla ISPutOutFire: square:has(IsoFlagType.burning))
			local hasFire = false
			local ok, burning = pcall(sq.has, sq, IsoFlagType.burning)
			if ok then hasFire = burning end
			if not hasFire then
				-- Ateş söndü, kül ve yanık zemin temizliği
				local remaining = removeBurntTiles(sq)
				if remaining > 0 then
					-- Hâlâ burnt tile var, bir sonraki kontrole kadar bekle
					print("[BCB] NoAsh: " .. tostring(remaining) .. " tiles still remaining, will retry")
				else
					-- Temizlendi, listeden çıkar
					table.remove(ashWatchList, i)
				end
			end
		end
	end
end

local function findCorpseSquaresNearby(originSquare, radius)
	local found = {}
	if not originSquare then return found end
	local cell = getCell()
	local z = originSquare:getZ()
	local bx = originSquare:getX()
	local by = originSquare:getY()
	local seen = {}
	for dx = -radius, radius do
		for dy = -radius, radius do
			if dx ~= 0 or dy ~= 0 then
				local ok, sq = pcall(cell.getGridSquare, cell, bx + dx, by + dy, z)
				if ok and sq and not seen[sq] then
					seen[sq] = true
					local okObjs, objects = pcall(sq.getStaticMovingObjects, sq)
					if okObjs and objects then
						for i = 0, objects:size() - 1 do
							local obj = objects:get(i)
							if instanceof(obj, "IsoDeadBody") then
								local dist = math.abs(dx) + math.abs(dy)
								found[#found + 1] = {square = sq, dist = dist}
								break
							end
						end
					end
				end
			end
		end
	end
	table.sort(found, function(a, b) return a.dist < b.dist end)
	return found
end

local function queueSpread(square, frameDelay, spread)
	if not square then return end
	spreadQueue[#spreadQueue + 1] = {
		square = square,
		fireAtFrame = spreadFrameCount + frameDelay,
		spread = spread,
	}
	if not spreadActive then
		spreadActive = true
		Events.OnTick.Add(onSpreadTick)
	end
end

function onSpreadTick()
	spreadFrameCount = spreadFrameCount + 1
	if not spreadActive then return end

	if #ashWatchList > 0 and spreadFrameCount % ASH_CHECK_INTERVAL == 0 then
		checkAshWatchList()
	end

	local toRemove = {}
	for i, entry in ipairs(spreadQueue) do
		if spreadFrameCount >= entry.fireAtFrame then
			local cell = getCell()
			IsoFireManager.StartFire(cell, entry.square, true, 100, 500)

			-- Söndürme için bu kareyi tohum olarak ekle (zincirleme yaysa bile)
			addExtinguishSeed(entry.square)

			if BCBConfig.NO_ASH then
				ashWatchList[#ashWatchList + 1] = {
					x = math.floor(entry.square:getX()),
					y = math.floor(entry.square:getY()),
					z = entry.square:getZ(),
				}
			end

			if entry.spread then
				local nearby = findCorpseSquaresNearby(entry.square, 1)
				for _, n in ipairs(nearby) do
					local okFire, hasFire = pcall(n.square.has, n.square, IsoFlagType.burning)
					if not (okFire and hasFire) then
						queueSpread(n.square, getFramesPerTile(), true)
					end
				end
			end

			toRemove[#toRemove + 1] = i
		end
	end

	for i = #toRemove, 1, -1 do
		table.remove(spreadQueue, toRemove[i])
	end

	-- Söndürme operasyonu: kuyruk boşalınca (tüm cesetler tutuşunca) başla.
	if not BCBConfig.AUTO_EXTINGUISH then
		extinguishActive = false
		extinguishSeeds = {}
		extinguishCenters = {}
	end
	if #spreadQueue == 0 and BCBConfig.AUTO_EXTINGUISH and (extinguishActive or #extinguishSeeds > 0) then
		if not extinguishActive then
			extinguishActive = true
			extinguishSweeps = 0
			extinguishCleanStreak = 0
			extinguishTotalStopped = 0
			extinguishCapped = false
			extinguishSeen = {}
			extinguishSeenCount = 0
			extinguishNextSweepAt = spreadFrameCount + EXTINGUISH_GRACE_FRAMES
			print("[BCB] Extinguish armed: " .. tostring(#extinguishSeeds) .. " corpse squares, first sweep in " .. tostring(EXTINGUISH_GRACE_FRAMES) .. " frames")
		end
		if spreadFrameCount >= extinguishNextSweepAt then
			local stopped = runExtinguishSweep()
			extinguishSweeps = extinguishSweeps + 1
			if stopped > 0 then
				extinguishCleanStreak = 0
				print("[BCB] Extinguish sweep " .. tostring(extinguishSweeps) .. ": stopped " .. tostring(stopped) .. " fires (chasing " .. tostring(#extinguishCenters) .. " tiles)")
			else
				extinguishCleanStreak = extinguishCleanStreak + 1
			end
			local giveUp = extinguishSweeps >= EXTINGUISH_MAX_SWEEPS
			local done = extinguishCleanStreak >= EXTINGUISH_CLEAN_STREAK
			if done and not giveUp then
				print("[BCB] Extinguish finished after " .. tostring(extinguishSweeps) .. " sweeps, total " .. tostring(extinguishTotalStopped) .. " fires stopped")
			end
			if giveUp then
				print("[BCB] Extinguish stopped after " .. tostring(extinguishSweeps) .. " sweeps (max reached), total " .. tostring(extinguishTotalStopped) .. " fires stopped")
			end
			if done or giveUp then
				extinguishActive = false
				extinguishSeeds = {}
				extinguishCenters = {}
			else
				extinguishNextSweepAt = spreadFrameCount + EXTINGUISH_SWEEP_INTERVAL
			end
		end
	end

	-- Tick'i kapat (tüm işler bitince)
	if #spreadQueue == 0 and not extinguishActive and #extinguishSeeds == 0 and #ashWatchList == 0 then
		spreadActive = false
		Events.OnTick.Remove(onSpreadTick)
		print("[BCB] Tick deactivated")
	end
end

Events.OnClientCommand.Add(function(module, command, player, args)
	if module ~= "BCB" then return end
	print("[BCB Server] OnClientCommand: module=" .. tostring(module) .. ", command=" .. tostring(command) .. ", player=" .. tostring(player))
	local cell = getCell()

	if command == "burnCorpse" then
		print("[BCB Server] burnCorpse args: x=" .. tostring(args.x) .. ", y=" .. tostring(args.y) .. ", z=" .. tostring(args.z) .. ", spread=" .. tostring(args.spreadRadius))
		-- Validate coordinates
		if not args.x or not args.y or not args.z then
			print("[BCB Server] invalid args")
			return
		end
		local square = cell:getGridSquare(args.x, args.y, args.z)
		if not square then print("[BCB Server] square not found!") return end

		-- Validate: must have at least one corpse on the square
		local okObjs, objects = pcall(square.getStaticMovingObjects, square)
		if not okObjs or not objects then print("[BCB Server] cannot read square objects") return end
		local hasCorpse = false
		for i = 0, objects:size() - 1 do
			if instanceof(objects:get(i), "IsoDeadBody") then hasCorpse = true break end
		end
		if not hasCorpse then print("[BCB Server] no corpse on square") return end

		local okRoom, room = pcall(square.getRoom, square)
		if not BCBConfig.ALLOW_INDOOR and okRoom and room then
			print("[BCB Server] indoor burn not allowed, skipping")
			return
		end

		print("[BCB Server] starting fire on square (" .. square:getX() .. "," .. square:getY() .. "," .. square:getZ() .. ")")
		local okFire, errFire = pcall(IsoFireManager.StartFire, cell, square, true, 100, 500)
		if not okFire then
			print("[BCB Server] StartFire FAILED: " .. tostring(errFire))
		else
			print("[BCB Server] StartFire OK")
		end
		addExtinguishSeed(square)

		if BCBConfig.NO_ASH then
			ashWatchList[#ashWatchList + 1] = {
				x = math.floor(square:getX()),
				y = math.floor(square:getY()),
				z = square:getZ(),
			}
			ensureTickActive()
		end

		if args.spreadRadius and args.spreadRadius > 0 then
			local nearby = findCorpseSquaresNearby(square, args.spreadRadius)
			print("[BCB Server] fire spread: " .. tostring(#nearby) .. " nearby corpses")
			for _, entry in ipairs(nearby) do
				queueSpread(entry.square, entry.dist * getFramesPerTile(), true)
			end
		end
	else
		print("[BCB Server] unknown command: " .. tostring(command))
	end
end)

-- Register action type on server so it's recognized in multiplayer
-- (client registers via _G[ISBCBBurnAction.Type] = ISBCBBurnAction)
local ISBCBBurnAction = ISBaseTimedAction:derive("BCB_ISBCBBurnAction")
if ISBCBBurnAction.Type then
	_G[ISBCBBurnAction.Type] = ISBCBBurnAction
end

print("[BCB] Server-side loaded")
