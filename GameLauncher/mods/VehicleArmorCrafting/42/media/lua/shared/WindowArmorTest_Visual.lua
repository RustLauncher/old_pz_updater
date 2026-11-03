--[[
    Vehicle Armor Crafting - visuals: 3D bars on windows and armor plates on hood/trunk.

    How it works:
      * every supported vehicle has ready-made models for each part
        (media/models_X/vehicles/WAT_<Body>_<Part>.fbx), built from the vehicle's own mesh.
      * one part may use several models: the hood plate, for instance, is made of three -
        light plate, dark frame and bolts. That way each piece gets its own flat colour
        texture and does not depend on how the game maps a texture onto the model.
      * on world load the mod appends those models to the vehicle script parts
        (VehicleScript:Load); by default the models are hidden.
      * when a part is armored the model is shown (part:setModelVisible).

    Models exist for every vanilla body (23 of them covering 152 vehicles). The tables live in
    WindowArmorTest_VisualData.lua: WAT.VISUAL_BODIES (body -> part -> models) and
    WAT.VEHICLE_BODY (vehicle script -> body). On a vehicle without models (modded, trailer)
    the armor still installs and works - it is simply not visible.

    Debug (Lua console):
      WindowArmorTest.previewVisuals(true)            -- show bars on every window of nearby vehicles
      WindowArmorTest.previewVisuals(false)           -- back to normal (only where armor is installed)
      WindowArmorTest.tuneVisuals(scale, ox, oy, oz)  -- tweak model scale/offset on the fly
]]
require "WindowArmorTest_Shared"
require "WindowArmorTest_VisualData"

local WAT = WindowArmorTest

WAT.VISUAL_MODEL_ID = "WAT_Armor" -- base model name inside the part script (WAT_Armor, WAT_Armor2, ...)

-- Manual additions: vehicle -> part -> model (or a list of models).
-- The main tables live in WindowArmorTest_VisualData.lua.
WAT.VISUALS = WAT.VISUALS or {}

-- Parts that have models for this vehicle, or nil
function WAT.partsFor(scriptName)
    if WAT.VISUALS[scriptName] then return WAT.VISUALS[scriptName] end
    local body = WAT.VEHICLE_BODY and WAT.VEHICLE_BODY[scriptName]
    return body and WAT.VISUAL_BODIES and WAT.VISUAL_BODIES[body] or nil
end

-- Every vehicle that has models
function WAT.allVisualVehicles()
    local list = {}
    for name in pairs(WAT.VISUALS) do list[name] = true end
    if WAT.VEHICLE_BODY then
        for name in pairs(WAT.VEHICLE_BODY) do list[name] = true end
    end
    return list
end

WAT.visualTune = WAT.visualTune or { scale = 1.0, ox = 0.0, oy = 0.0, oz = 0.0 }
WAT.visualState = WAT.visualState or {} -- vehicle -> { [partId] = true/false }
WAT.previewAll = WAT.previewAll or false
WAT.visualsInjected = WAT.visualsInjected or false

local function getVehicleScript(fullName)
    local sm = getScriptManager()
    if not sm then return nil end
    local script = sm:getVehicle(fullName)
    if not script then
        local short = string.match(fullName, "%.(.+)$")
        if short then script = sm:getVehicle(short) end
    end
    return script
end

-- Models of one part: { { id = "WAT_Armor", file = "..." }, ... }
function WAT.modelsFor(partId, entry)
    local list = {}
    if type(entry) == "table" then
        for i, file in ipairs(entry) do
            list[i] = { id = (i == 1) and WAT.VISUAL_MODEL_ID or (WAT.VISUAL_MODEL_ID .. i), file = file }
        end
    else
        list[1] = { id = WAT.VISUAL_MODEL_ID, file = entry }
    end
    return list
end

local function partBlock(partId, entry)
    local t = WAT.visualTune
    local blocks = {}
    for _, m in ipairs(WAT.modelsFor(partId, entry)) do
        blocks[#blocks + 1] = "model " .. m.id .. " { file = " .. m.file .. ", scale = " .. t.scale
            .. ", offset = " .. t.ox .. " " .. t.oy .. " " .. t.oz .. ", }"
    end
    return "part " .. partId .. " { setAllModelsVisible = false, " .. table.concat(blocks, " ") .. " }"
end

-- Append the armor models to the vehicle scripts. force = rewrite the parameters (for tuneVisuals)
function WAT.injectVisuals(force)
    if WAT.isDedicated() then return 0 end   -- the server draws nothing
    local count = 0
    for fullName in pairs(WAT.allVisualVehicles()) do
        local parts = WAT.partsFor(fullName)
        local script = parts and getVehicleScript(fullName)
        if script then
            local blocks = {}
            for partId, entry in pairs(parts) do
                local sp = script:getPartById(partId)
                if sp then
                    local missing = force
                    for _, m in ipairs(WAT.modelsFor(partId, entry)) do
                        if sp:getModelById(m.id) == nil then missing = true end
                    end
                    if missing then blocks[#blocks + 1] = partBlock(partId, entry) end
                end
            end
            if #blocks > 0 then
                local body = "vehicle " .. script:getName() .. " { " .. table.concat(blocks, " ") .. " }"
                local ok, err = pcall(function() script:Load(script:getName(), body) end)
                if ok then
                    count = count + #blocks
                else
                    WAT.log("visual inject FAILED for", fullName, err)
                end
            end
            WAT.visualsInjected = true
        end
    end
    if count > 0 then WAT.log("visual models injected:", count) end
    return count
end

-- Show/hide the armor models of a vehicle depending on the installed armor
function WAT.updateVisual(vehicle)
    if not vehicle or WAT.isDedicated() then return end   -- nothing to draw on a dedicated server
    local parts = WAT.partsFor(vehicle:getScriptName())
    if not parts then return end
    local st = WAT.visualState[vehicle]
    if not st then
        st = {}
        WAT.visualState[vehicle] = st
    end
    for partId, entry in pairs(parts) do
        local part = vehicle:getPartById(partId)
        if part then
            local want = WAT.previewAll or (WAT.getPartEntry(part) ~= nil)
            want = want and true or false
            if st[partId] ~= want then
                for _, m in ipairs(WAT.modelsFor(partId, entry)) do
                    local ok, err = pcall(function() part:setModelVisible(m.id, want) end)
                    if not ok then WAT.log("setModelVisible failed", partId, m.id, err) end
                end
                st[partId] = want
            end
        end
    end
end

function WAT.forgetVisual(vehicle)
    WAT.visualState[vehicle] = nil
end

-- ---------- debug ----------
local function nearbyVehicle()
    local p = getPlayer()
    if not p then return nil end
    return p:getVehicle() or WAT.findNearestVehicle(p, 6)
end

function WAT.previewVisuals(on)
    WAT.previewAll = on and true or false
    WAT.visualState = {}
    local v = nearbyVehicle()
    if v then WAT.updateVisual(v) end
    WAT.log("previewVisuals", WAT.previewAll)
end

function WAT.tuneVisuals(scale, ox, oy, oz)
    local t = WAT.visualTune
    t.scale = scale or t.scale
    t.ox, t.oy, t.oz = ox or t.ox, oy or t.oy, oz or t.oz
    WAT.injectVisuals(true)
    WAT.visualState = {}
    local v = nearbyVehicle()
    if v then
        -- recreate the models so the new parameters are picked up
        local parts = WAT.partsFor(v:getScriptName())
        if parts then
            for partId, entry in pairs(parts) do
                local part = v:getPartById(partId)
                if part then
                    for _, m in ipairs(WAT.modelsFor(partId, entry)) do
                        pcall(function() part:setModelVisible(m.id, false) end)
                    end
                end
            end
        end
        WAT.updateVisual(v)
    end
    print(string.format("[WindowArmorTest] tuneVisuals scale=%s offset=%s %s %s", t.scale, t.ox, t.oy, t.oz))
end

local function tryInject()
    local ok, err = pcall(WAT.injectVisuals, false)
    if not ok then WAT.log("injectVisuals error:", err) end
end

Events.OnGameBoot.Add(tryInject)
Events.OnInitWorld.Add(tryInject)
