require "HalloweenEvent/HalloweenEvent_Server"
local Codec = require "HalloweenEvent/HalloweenEvent_HiddenAppearance"
local HWE = HalloweenEvent

local function install()
    if type(isClient) == "function" and isClient()
        and not (type(isServer) == "function" and isServer()) then return end
    local HAZ = HideAnywhereZombies
    if not HAZ or not HAZ.FrameworkAvailable then return end
    require "HAZ/Server"
    local server = HAZ.Server
    if not server or server._hweHiddenCompatInstalled then return end
    if type(server.sendToPlayer) ~= "function" then return end
    server._hweHiddenCompatInstalled = true

    local prepare = server.prepareEncounterAppearance
    server.prepareEncounterAppearance = function(appearance)
        if type(prepare) == "function" then prepare(appearance) end
        if type(HWE.Server)~="table" or type(HWE.Server.prepareHiddenAppearance)~="function" then
            HWE.log("HIDDEN_PREPARE_UNAVAILABLE reason=server_not_ready")
            return
        end
        local ok,prepared=pcall(HWE.Server.prepareHiddenAppearance,appearance)
        if ok then appearance.hweHiddenAppearance=prepared
        else HWE.log("HIDDEN_PREPARE_FAIL error="..tostring(prepared)) end
    end
    local apply = server.applyEncounterAppearance
    server.applyEncounterAppearance = function(zombie, appearance)
        if type(apply) == "function" then apply(zombie, appearance) end
        if appearance.hweHiddenAppearance then
            if type(HWE.Server)=="table" and type(HWE.Server.applyHiddenAppearance)=="function" then
                local ok,err=pcall(HWE.Server.applyHiddenAppearance,zombie,appearance.hweHiddenAppearance)
                if not ok then HWE.log("HIDDEN_SPAWN_APPLY_FAIL error="..tostring(err)) end
            end
        end
    end

    local send = server.sendToPlayer
    server.sendToPlayer = function(player, command, args)
        if command == "Discovered" and type(args) == "table" then
            -- Encounters are small and transient; scan only when a discovery is
            -- sent, never per frame or across the world zombie list.
            for _, record in pairs(server.activeEncounters or {}) do
                if record.sessionId == args.sessionId then
                    local appearances = record.appearances or {record.appearance}
                    for index, appearance in ipairs(appearances) do
                        local ok, err = pcall(Codec.encode, args, index, appearance.hweHiddenAppearance)
                        if not ok then HWE.log("HIDDEN_PACKET_ENCODE_FAIL error=" .. tostring(err)) end
                    end
                    break
                end
            end
        end
        return send(player, command, args)
    end
end

install()
if Events and Events.OnGameStart then Events.OnGameStart.Add(install) end
if Events and Events.OnServerStarted then Events.OnServerStarted.Add(install) end
