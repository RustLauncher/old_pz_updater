-- Optional rendering assets only. The normal freezer owns its sprites,
-- inventories, electricity, movement and saved data in every camera mode.
local owner = 'CocaColaICEFreezer'
local manifest = 'media/modelpacks/vini_cocacola_ice/pack.properties'
local reportedErrors = {}
local reportedSuccess = false

local function enabled()
    -- Multiplayer's activated list contains the server's mods. A client-only
    -- Java renderer is tracked by ZombieBuddy separately from that list.
    -- API presence alone is insufficient: inspect the loader's active record.
    local javaActive = false
    local loader = ZombieBuddy
    if loader and loader.getActiveJavaMods then
        local ok, active, banned = pcall(function()
            local mods = loader.getActiveJavaMods()
            local mod = mods and (mods.Viewpoint or mods['\\Viewpoint'])
            return mod and mod.flags and mod.flags.active == true,
                mod and mod.flags and mod.flags.banned == true
        end)
        if ok and banned == true then return false end
        javaActive = ok and active == true
    end
    local ok, active = pcall(function()
        local mods = getActivatedMods and getActivatedMods()
        return mods and (mods:contains('Viewpoint') or mods:contains('\\Viewpoint'))
    end)
    if ok and active == true then return true end
    return javaActive
end

local function register()
    if not enabled() then return end
    local api = Viewpoint and Viewpoint.ModelPacks
    if not api or not api.register then return end
    local ok, result = pcall(function()
        return api.register(owner, manifest)
    end)
    if not ok or not result then
        local reason = ok and 'Model-pack registration was not accepted.' or tostring(result)
        if not reportedErrors[reason] then
            print('[CocaColaICEFreezer/Viewpoint] ' .. reason ..
                ' If the mod download has finished, restart Project Zomboid; Viewpoint caches a failed first attempt for the current session.')
            reportedErrors[reason] = true
        end
        return
    end
    if not reportedSuccess then
        print('[CocaColaICEFreezer/Viewpoint] Optional ICE and Coca-Cola ICE models registered.')
        reportedSuccess = true
    end
end

register()
-- Check after client Lua loads and when entering a world. Successful native
-- registrations are idempotent; failed native first attempts require a restart.
Events.OnGameBoot.Add(register)
Events.OnGameStart.Add(register)
