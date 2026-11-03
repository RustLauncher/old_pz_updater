-- Dog Tired Item Arrange: an add-on for Slayer's Item Arrange (Workshop 3767639280, mod ID ItemArrange).
--
-- 1. Profiles. Item Arrange only arranges the item types listed in IA.arrangables (about 700 vanilla items).
--    DTIA_Data.lua adds about 3,400 more, each sized from its own world model the way 42.20 draws it
--    (ItemModelRenderer.init: weapon fix, inverse "world" attachment, mesh node transform, model scale; core scale
--    1.5; level height 2.44949). Entries that already exist (Item Arrange's own, other patches') are never replaced.
-- 2. Items from the mods in the DogTiredCoop list are measured the same way (DTIA.modded, about 2,900). Any other
--    modded item whose world model reuses a vanilla mesh gets a profile from that mesh, scaled by its model scale.
-- 3. A new arranger replaces IA.ArrangeItems and IA.CheckSpace (both looked up globally by Item Arrange's callers):
--    once a surface's footprint is full, stacks of layer-able items carry on in further layers up to a sandbox
--    height, and long items (planks, logs, pipes...) turn a quarter on alternate layers. Item types are placed in a
--    fixed order (largest footprint first, then name; items by ID), so server and clients agree. Each model is
--    centred on its slot from its measured bounding box.
-- Item Arrange's surface detection (IA.getSurfaceInfo) is reused as is.
require "DTIA/DTIA_Data"

DTIA = DTIA or {}
DTIA.VERSION = "1.0.0"
local LEVEL = 2.44949
local EPS = 0.0005

-- ---------------------------------------------------------------- sandbox
local function opts()
    local sv = SandboxVars and SandboxVars.DogTiredItemArrange or {}
    local h = tonumber(sv.MaxPileHeight) or 90
    if h < 10 then h = 10 elseif h > 99 then h = 99 end
    return {
        enabled = sv.Arranger ~= false,
        layers = sv.Layers ~= false,
        cross = sv.CrossStack ~= false,
        floorMax = h / 100,
    }
end
DTIA.opts = opts

-- ---------------------------------------------------------------- profiles
local function classQz(class, dz)
    if dz <= 0 then return 1 end
    if class == "bag" then return math.max(1, math.min(4, math.floor(0.40 / dz))) end
    if class == "flat-top" then
        local q = math.max(1, math.min(12, math.floor(0.20 / dz)))
        if dz <= 0.1 and q < 2 then q = 2 end
        return q
    end
    if class == "rod" then return math.max(1, math.min(8, math.floor(0.20 / dz))) end
    if class == "thin" then return math.max(1, math.min(6, math.floor(0.20 / dz))) end
    if class == "log" then return math.max(1, math.min(4, math.floor(0.20 / dz))) end
    return 1
end
DTIA.classQz = classQz

local function r3(x) return math.floor(x * 1000 + 0.5) / 1000 end
local function f3(x)
    local s = string.format("%.3f", x)
    if s == "-0.000" then s = "0.000" end
    return s
end

-- top-level "scale = n" of a model script, last one wins, undoCoreScale x 2/3 (ModelScript.Load, 42.20)
local function modelScale(ms)
    local ok, bodies = pcall(function() return ms:getLoadedScriptBodies() end)
    if not ok or not bodies then return nil end
    local scale, undo = 1, false
    for i = 0, bodies:size() - 1 do
        local body = tostring(bodies:get(i)):gsub("/%*.-%*/", "")
        -- drop attachment blocks (their scale is the attachment's, not the model's), then read the rest in order
        body = body:gsub("[Aa][Tt][Tt][Aa][Cc][Hh][Mm][Ee][Nn][Tt]%s+[%w_%.]*%s*%b{}", "")
        for k, v in body:gmatch("([%a_]+)%s*=%s*([^,%s{}]+)") do
            local kl = k:lower()
            if kl == "scale" then scale = tonumber(v) or scale
            elseif kl == "undocorescale" then undo = (v:lower() == "true") end
        end
    end
    if undo then scale = scale * 0.6666667 end
    return scale
end
DTIA.modelScale = modelScale

local function firstOf(list)
    if list and list.size and list:size() > 0 then return list:get(0) end
end

-- the model the ground renderer uses (ItemModelRenderer.renderMain): WorldStaticModel, else a weapon's static model
local function worldModelOf(item)
    local name = item:getWorldStaticModel()
    if name and name ~= "" then return name, "world" end
    local okL, l = pcall(function() return item:getWorldStaticModelsByIndex() end)
    name = okL and firstOf(l)
    if name and name ~= "" then return name, "world" end
    local okT, t = pcall(function() return tostring(item:getItemType()) end)
    local okS, sprite = pcall(function() return item:getWeaponSprite() end)
    if (okT and t and t:lower():find("weapon")) or (okS and sprite and sprite ~= "") then
        name = item:getStaticModel()
        if not name or name == "" then local ok2, l2 = pcall(function() return item:getStaticModelsByIndex() end); name = ok2 and firstOf(l2) end
        if not name or name == "" then name = item:getWeaponSprite() end
        if not name or name == "" then local ok3, l3 = pcall(function() return item:getWeaponSpritesByIndex() end); name = ok3 and firstOf(l3) end
        if name and name ~= "" then return name, "weapon" end
    end
end

local function attSig(ms)
    local att = ms:getAttachmentById("world")
    if not att then return "-", 0 end
    local o, r = att:getOffset(), att:getRotate()
    local off = math.max(math.abs(o:x()), math.abs(o:y()), math.abs(o:z()))
    return table.concat({ f3(o:x()), f3(o:y()), f3(o:z()), f3(r:x()), f3(r:y()), f3(r:z()) }, ","), off
end

local function profileFromMesh(ref, scale, attOff)
    local ratio = scale / ref[7]
    if attOff > 0.001 and math.abs(ratio - 1) > 0.001 then return nil end -- an attachment offset does not scale
    local X, Z, H = ref[1] * ratio, ref[2] * ratio, ref[3] * ratio
    if X + 0.01 > 0.98 or Z + 0.01 > 0.98 then return nil end
    local dz = r3(H / LEVEL + 0.002)
    local miny = ref[6] * ratio
    local p = { dx = r3(X + 0.01), dy = r3(Z + 0.01), dz = dz, qz = classQz(ref[8], dz) }
    if math.abs(miny) > 0.004 then p.mz = r3(-miny / LEVEL) end
    return p, { ref[4] * ratio, ref[5] * ratio }
end

local registered = { vanilla = false, modded = false, meshes = false }

-- Item Arrange's own entries as loaded (other patches register later, at boot), and the entries DTIA added.
-- Flags and offsets were measured for these profiles only, so they are not applied to another patch's profile.
DTIA.iaOriginal = DTIA.iaOriginal or {}
if IA and IA.arrangables and not DTIA.iaSnapshot then
    for k, v in pairs(IA.arrangables) do DTIA.iaOriginal[k] = v end
    DTIA.iaSnapshot = true
end
DTIA.owned = DTIA.owned or {}
function DTIA.isMeasured(fullType, profile)
    return DTIA.owned[fullType] == profile or DTIA.iaOriginal[fullType] == profile
end

function DTIA.registerVanilla()
    if registered.vanilla then return end
    if not (IA and IA.arrangables) then
        print("[DT ItemArrange] Item Arrange data not loaded; nothing registered")
        return
    end
    local sm, n = getScriptManager(), 0
    for fullType, name in pairs(DTIA.sameAs) do
        local profile = IA.arrangableProfile and IA.arrangableProfile[name]
        if profile and not IA.arrangables[fullType] and sm:FindItem(fullType) then
            IA.arrangables[fullType] = profile
            DTIA.owned[fullType] = profile
            n = n + 1
        end
    end
    for fullType, profile in pairs(DTIA.vanilla) do
        if not IA.arrangables[fullType] and sm:FindItem(fullType) then
            IA.arrangables[fullType] = profile
            DTIA.owned[fullType] = profile
            n = n + 1
        end
    end
    registered.vanilla = true
    print("[DT ItemArrange] " .. n .. " vanilla item type(s) added to Item Arrange")
end

-- items from other mods, measured from their own models. Registered at game start, so a mod's own Item Arrange
-- patch (registered at boot, e.g. Dog Tired Firearms' and Buckets') always comes first.
function DTIA.registerModded()
    if registered.modded then return end
    if not (IA and IA.arrangables) then return end
    registered.modded = true
    local sm, n = getScriptManager(), 0
    for fullType, name in pairs(DTIA.moddedSameAs) do
        local profile = IA.arrangableProfile and IA.arrangableProfile[name]
        if profile and not IA.arrangables[fullType] and sm:FindItem(fullType) then
            IA.arrangables[fullType] = profile
            DTIA.owned[fullType] = profile
            n = n + 1
        end
    end
    for fullType, profile in pairs(DTIA.modded) do
        if not IA.arrangables[fullType] and sm:FindItem(fullType) then
            IA.arrangables[fullType] = profile
            DTIA.owned[fullType] = profile
            n = n + 1
        end
    end
    print("[DT ItemArrange] " .. n .. " item type(s) from other mods added to Item Arrange")
end

-- modded items whose world model uses a vanilla mesh (measured in DTIA.meshes)
function DTIA.registerByMesh()
    if registered.meshes then return end
    if not (IA and IA.arrangables) then return end
    registered.meshes = true
    local sm = getScriptManager()
    local items = sm:getAllItems()
    local n, byMod = 0, {}
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        local fullType = item:getFullName()
        if not IA.arrangables[fullType] then
            local ok, profile, off = pcall(function()
                local name, kind = worldModelOf(item)
                if not name then return nil end
                local ms = sm:getModelScript(name)
                if not ms then return nil end
                local mesh = ms:getMeshName()
                if not mesh or mesh == "" then return nil end
                local sig, attOff = attSig(ms)
                local ref = DTIA.meshes[mesh:gsub("\\", "/"):lower() .. "|" .. kind .. "|" .. sig]
                if not ref then return nil end
                local scale = modelScale(ms)
                if not scale then return nil end
                return profileFromMesh(ref, scale, attOff)
            end)
            if ok and profile then
                IA.arrangables[fullType] = profile
                DTIA.owned[fullType] = profile
                if off and (math.abs(off[1]) > 0.02 or math.abs(off[2]) > 0.02) then
                    DTIA.offsets[fullType] = { r3(off[1]), r3(off[2]) }
                end
                local qz = profile.qz or 1
                if qz > 1 then
                    local long = math.max(profile.dx, profile.dy) >= 0.4 and math.max(profile.dx, profile.dy) >= 2 * math.min(profile.dx, profile.dy)
                    DTIA.flags[fullType] = long and "lc" or "l"
                end
                n = n + 1
                local okM, mod = pcall(function() return item:getModID() end)
                mod = okM and mod or "?"
                byMod[mod] = (byMod[mod] or 0) + 1
            end
        end
    end
    for mod, c in pairs(byMod) do
        print("[DT ItemArrange] [" .. tostring(mod) .. "] " .. c .. " item type(s) added from their vanilla mesh")
    end
    if n == 0 then print("[DT ItemArrange] no modded items matched a vanilla mesh") end
end

-- ---------------------------------------------------------------- arranger
local CUR_N, CUR_W, CUR_S, CUR_E = 1, 2, 3, 4

local function isFurniture(square)
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local sprite = objects:get(i):getSprite()
        local name = sprite and sprite:getName()
        if name and IA.surfaces[name] then return true end
    end
    return false
end

local function itemId(item)
    local ok, id = pcall(function() return item:getID() end)
    return ok and id or 0
end

local function collect(square, extraItem)
    local groups, order = {}, {}
    local function add(item, witem)
        local fType = item:getFullType()
        local p = IA.arrangables[fType]
        if not p then return end
        local g = groups[fType]
        if not g then
            g = { fType = fType, p = p, list = {} }
            groups[fType] = g
            order[#order + 1] = g
        end
        g.list[#g.list + 1] = { item = item, witem = witem, id = witem and itemId(item) or math.huge, extra = (witem == nil) }
    end
    local wobs = square:getWorldObjects()
    for i = 0, wobs:size() - 1 do
        local witem = wobs:get(i)
        local item = witem:getItem()
        if item then add(item, witem) end
    end
    if extraItem then add(extraItem, nil) end
    table.sort(order, function(a, b)
        local aa, ab = a.p.dx * a.p.dy, b.p.dx * b.p.dy
        if math.abs(aa - ab) > 1e-9 then return aa > ab end
        return a.fType < b.fType
    end)
    for _, g in ipairs(order) do
        table.sort(g.list, function(a, b) return a.id < b.id end)
    end
    return order
end

-- one packing state per surface; u runs along the wall, v away from it
local function newState(s, cursorOrder, index)
    local alongX = (cursorOrder == CUR_N or cursorOrder == CUR_S)
    local st = {
        s = s, index = index, order = cursorOrder, alongX = alongX,
        umin = alongX and s.xmin or s.ymin, umax = alongX and s.xmax or s.ymax,
        vlen = alongX and (s.ymax - s.ymin) or (s.xmax - s.xmin),
        zmin = s.zmin or 0, zmax = s.zmax or 1,
        zb = s.zmin or 0, zt = s.zmin or 0, layer = 0, support = true, used = false,
    }
    st.u, st.v, st.row = st.umin, 0, 0
    return st
end

local function slotCentre(st, su, sv)
    local s, cu, cv = st.s, st.u + su / 2, st.v + sv / 2
    if st.order == CUR_N then return cu, s.ymin + cv
    elseif st.order == CUR_S then return cu, s.ymax - cv
    elseif st.order == CUR_W then return s.xmin + cv, cu
    else return s.xmax - cv, cu end
end

-- a quarter turn only makes a pile when at least 2 stacks fit side by side under one item's length;
-- with 1 (logs) the turned layer would be a corner pinwheel, so those stack straight
local function canTurn(p)
    local L, S = math.max(p.dx, p.dy), math.min(p.dx, p.dy)
    return S > 0 and math.floor(L / S + EPS) >= 2
end

-- size of one stack of this type on this state's current layer: world x/y size and quarter turn
local function footprint(st, g, o)
    local p = g.p
    local turn = o.cross and g.cross and canTurn(p) and (st.layer % 2 == 1)
    local sx, sy = p.dx, p.dy
    if turn then sx, sy = p.dy, p.dx end
    local su, sv = sx, sy
    if not st.alongX then su, sv = sy, sx end
    if turn and (su > st.umax - st.umin + EPS or sv > st.vlen + EPS) then
        -- the turned stack does not fit this surface: keep the normal direction on this layer
        turn = false
        su, sv = p.dx, p.dy
        if not st.alongX then su, sv = p.dy, p.dx end
    end
    return su, sv, turn
end

-- find the next slot for a stack of group g on state st; returns su, sv, turn or nil
local function nextSlot(st, g, o)
    local p = g.p
    local mz = p.mz or 0
    -- cross-stacked layers stay inside a square no wider than the item is long, so a turned layer never
    -- overhangs or floats past the layer under it (planks 0.86 x 0.12: 7 stacks per layer, not 8)
    local umax, vlen = st.umax, st.vlen
    if o.cross and g.cross and o.layers and g.layer and canTurn(p) then
        local L = math.max(p.dx, p.dy)
        umax, vlen = math.min(umax, st.umin + L), math.min(vlen, L)
    end
    for _ = 1, 64 do
        local su, sv, turn = footprint(st, g, o)
        if su > st.umax - st.umin + EPS or sv > st.vlen + EPS then return nil end
        if st.zb + p.dz > st.zmax + EPS then return nil end
        if st.u + su <= umax + EPS and st.v + sv <= vlen + EPS then
            return su, sv, turn
        end
        if st.u + su > umax + EPS and st.u > st.umin + EPS then
            st.u, st.v, st.row = st.umin, st.v + st.row, 0     -- next row
        else
            -- footprint full: start a new layer on top, if this type and everything under it allow it
            if not (o.layers and g.layer and st.support and st.used) then return nil end
            if st.zt + p.dz > st.zmax + EPS then return nil end
            st.zb, st.layer, st.support = st.zt, st.layer + 1, true
            st.u, st.v, st.row = st.umin, 0, 0
        end
    end
    return nil
end

local function arrange(square, extraItem, apply)
    local o = opts()
    local groups = collect(square, extraItem)
    if #groups == 0 then return true end
    local cursorOrder, surfaces = IA.getSurfaceInfo(square)
    if not surfaces or #surfaces == 0 then return false end
    if not isFurniture(square) then
        for _, s in ipairs(surfaces) do
            local zmin = s.zmin or 0
            s.zmax = math.max(zmin, math.min(s.zmax or 1, zmin + o.floorMax))
        end
    end
    -- smallest vertical band first, like Item Arrange, so shallow shelves keep shallow items
    local idx = {}
    for i = 1, #surfaces do idx[i] = i end
    table.sort(idx, function(a, b)
        local da = (surfaces[a].zmax or 1) - (surfaces[a].zmin or 0)
        local db = (surfaces[b].zmax or 1) - (surfaces[b].zmin or 0)
        if math.abs(da - db) > 1e-9 then return da < db end
        return a < b
    end)
    local states = {}
    for k, i in ipairs(idx) do states[k] = newState(surfaces[i], cursorOrder, k) end

    local allPlaced = true
    for _, g in ipairs(groups) do
        local mine = DTIA.isMeasured(g.fType, g.p)
        local flags = mine and DTIA.flags[g.fType] or ""
        g.layer = flags:find("l", 1, true) ~= nil
        g.cross = flags:find("c", 1, true) ~= nil
        local p = g.p
        if not p.dz or p.dz <= 0 then g.p = { dx = p.dx, dy = p.dy, dz = 0.01, qz = p.qz, mz = p.mz, fx = p.fx, fy = p.fy, fz = p.fz }; p = g.p end
        local qz = math.max(1, p.qz or 3)
        local mz = p.mz or 0
        local i = 1
        while i <= #g.list do
            local placed = false
            for _, st in ipairs(states) do
                local su, sv, turn = nextSlot(st, g, o)
                if su then
                    local room = math.floor((st.zmax - st.zb) / p.dz + EPS)
                    local n = math.min(qz, room, #g.list - i + 1)
                    if n >= 1 then
                        local cx, cy = slotCentre(st, su, sv)
                        local fz = (p.fz or 0) + (turn and 90 or 0)
                        local off = mine and DTIA.offsets[g.fType]
                        local ox, oy = 0, 0
                        if off then
                            ox, oy = off[1], off[2]
                            if turn then ox, oy = -oy, ox end      -- offsets turn with the model (+90, counter-clockwise)
                        end
                        for k = 0, n - 1 do
                            local e = g.list[i + k]
                            e.x, e.y, e.z, e.fz = cx - ox, cy - oy, st.zb + mz + k * p.dz, fz
                        end
                        i = i + n
                        st.u = st.u + su
                        if sv > st.row then st.row = sv end
                        local top = st.zb + n * p.dz
                        if top > st.zt then st.zt = top end
                        st.used = true
                        if not g.layer then st.support = false end
                        placed = true
                        break
                    end
                end
            end
            if not placed then
                allPlaced = false
                break
            end
        end
    end

    if apply then
        for _, g in ipairs(groups) do
            local p = g.p
            for _, e in ipairs(g.list) do
                if e.witem and e.x then
                    e.witem:setOffset(e.x, e.y, e.z)
                    e.item:setWorldXRotation(p.fx or 0)
                    e.item:setWorldYRotation(p.fy or 0)
                    e.item:setWorldZRotation(e.fz % 360)
                    e.item:setDoingExtendedPlacement(false)
                    e.witem:syncExtendedPlacement()
                end
            end
        end
    end
    if extraItem then
        for _, g in ipairs(groups) do
            for _, e in ipairs(g.list) do
                if e.extra then return e.x ~= nil end
            end
        end
    end
    return allPlaced
end
DTIA.arrange = arrange

function DTIA.ArrangeItems(square, simulate)
    if not opts().enabled and DTIA.originalArrange then return DTIA.originalArrange(square, simulate) end
    if not square then return false end
    return arrange(square, nil, not simulate)
end

function DTIA.CheckSpace(square, item)
    if not opts().enabled and DTIA.originalCheck then return DTIA.originalCheck(square, item) end
    if not square or not item then return false end
    if not IA.arrangables[item:getFullType()] then return true end
    return arrange(square, item, false)
end

function DTIA.install()
    if not (IA and IA.ArrangeItems and IA.CheckSpace and IA.getSurfaceInfo) then return false end
    if DTIA.installed then return true end      -- once only: re-wrapping another mod's wrapper would loop
    DTIA.originalArrange = IA.ArrangeItems
    DTIA.originalCheck = IA.CheckSpace
    IA.ArrangeItems = DTIA.ArrangeItems
    IA.CheckSpace = DTIA.CheckSpace
    DTIA.installed = true
    return true
end

local function onBoot()
    DTIA.registerVanilla()
    if DTIA.install() then print("[DT ItemArrange] " .. DTIA.VERSION .. " arranger installed") end
end
local function onStart()
    DTIA.registerVanilla()
    DTIA.registerModded()
    DTIA.registerByMesh()
    DTIA.install()
end

DTIA.install()
Events.OnGameBoot.Add(onBoot)
Events.OnGameStart.Add(onStart)
Events.OnServerStarted.Add(onStart)
