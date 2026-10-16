OfflineSurvivorV2 = OfflineSurvivorV2 or {}

local OS = OfflineSurvivorV2

OS.MODULE = "OfflineSurvivorV2"
OS.DATA_KEY = "OfflineSurvivorV2.Records"
OS.LOOT_DATA_KEY = "OfflineSurvivorV2.LootCooldowns"
OS.OFFLINE_MARKER = "offlineSurvivorV2"
OS.VISUAL_CLONE_MARKER = "offlineSurvivorV2VisualClone"
OS.RENDERER = "corpse"
-- Server authority: this does not depend on a client command arriving during logout.
OS.SERVER_SCAN_SECONDS = 1
OS.LOOT_SESSION_SECONDS = 60
-- Corpse Add/Remove packets may be reordered while a client is streaming a
-- chunk. Keep an exact, marker-based stale-body cleanup alive long enough for
-- the late packet to arrive instead of leaving a second visual corpse behind.
OS.STALE_BODY_CLEANUP_SECONDS = 90

-- IsoDeadBody uses the engine's frozen player dead-body pose.  It is a real
-- human mesh, not a mannequin, tile, sprite or live NPC.
OS.CORPSE_POSE = "player_deadbody"

-- Zombies feed on the offline body through the engine's own corpse behaviour.
-- IsoZombie.updateSearchForCorpse scans this same 10 tile radius, and the engine
-- refuses a fourth zombie on one corpse, so the mod stays inside both limits.
OS.ZOMBIE_LURE_RADIUS = 10
OS.ZOMBIE_MAX_EATERS = 3
-- How long a body must be fed on before the offline death lands is the
-- ZombieKillMinutes Sandbox option, in real minutes.
-- A zombie is handed the body at most this often. Re-assigning it every tick
-- restarts its pathing and its eating state, which made zombies visibly stand
-- up and drop back down over and over. The engine clears bodyToEat on its own
-- whenever the zombie gets distracted, so this cannot be a long interval or
-- zombies simply ignore the body.
OS.ZOMBIE_LURE_COOLDOWN_SECONDS = 4
-- Multiplayer zombie simulation belongs to the client that owns the zombie.
-- Keep reports short lived so the server advances the offline-death timer only
-- while a local client is seeing the native eating state.
OS.ZOMBIE_FEED_REPORT_SECONDS = 1
OS.ZOMBIE_FEED_REPORT_TTL_SECONDS = 3
OS.ZOMBIE_FEED_PROGRESS_GRACE_SECONDS = 10
OS.ZOMBIE_CLIENT_LURE_COOLDOWN_SECONDS = 1
OS.ZOMBIE_CLIENT_SCAN_TICKS = 15

-- getOnlinePlayers() can briefly omit a player who is still streaming in. One
-- missing tick is not a logout: acting on it spawned a body under a player who
-- never left and then removed it, flooding every client with corpse packets.
OS.OFFLINE_CONFIRM_TICKS = 5
-- Squared tile distance at which a zombie counts as being on top of the body,
-- used to decide that it is feeding.
OS.ZOMBIE_CONTACT_DISTANCE_SQ = 3.0625
-- IsoZombie.updateEatBodyTarget only starts the feeding animation at 1.0. Stop
-- steering the zombie only once it is inside that exact range, otherwise it
-- parks just short of the body and never begins to eat.
OS.ZOMBIE_EAT_DISTANCE_SQ = 1.0

OS.COMMAND_REQUEST_LOOT = "RequestLoot"
OS.COMMAND_COMMIT_LOOT = "CommitLoot"
OS.COMMAND_CANCEL_LOOT = "CancelLoot"
OS.COMMAND_OPEN_LOOT = "OpenLoot"
OS.COMMAND_LOOT_RESULT = "LootResult"
OS.COMMAND_LOOT_NOTICE = "LootNotice"
OS.COMMAND_REQUEST_BODY_DRAG = "RequestBodyDrag"
OS.COMMAND_START_BODY_DRAG = "StartBodyDrag"
OS.COMMAND_BODY_DRAG_PICKED_UP = "BodyDragPickedUp"
OS.COMMAND_BODY_DRAG_HEARTBEAT = "BodyDragHeartbeat"
OS.COMMAND_FINISH_BODY_DRAG = "FinishBodyDrag"
OS.COMMAND_BODY_DRAG_RESULT = "BodyDragResult"
-- A RemoveCorpse packet can arrive before an older AddCorpse packet on one
-- client. The server uses this command to let that client remove only the
-- identified offline-survivor remnant during a short retry window.
OS.COMMAND_CLEANUP_STALE_BODY = "CleanupStaleBody"
-- In multiplayer the client owns its own position, so a server-side teleport is
-- overwritten. The owning client has to perform the move itself.
OS.COMMAND_TELEPORT_TO_BODY = "TeleportToBody"
OS.COMMAND_ZOMBIE_FEEDING = "ZombieFeeding"

function OS.getOption(name, default)
    -- SandboxVars can briefly omit a custom page after a dedicated-server
    -- restart, even though SandboxOptions already holds the saved value. Read
    -- the option object first; it is the authoritative server setting and is
    -- updated by the normal SandboxOptions packet as well.
    local value = nil
    pcall(function()
        local sandboxOptions = getSandboxOptions and getSandboxOptions() or nil
        local option = sandboxOptions and sandboxOptions:getOptionByName(OS.MODULE .. "." .. tostring(name)) or nil
        if option then value = option:getValue() end
    end)
    if value ~= nil then return value end

    -- Keep the Lua-table fallback for game versions or load phases where the
    -- Java option is not exposed yet. Never cache either source.
    local options = SandboxVars and SandboxVars[OS.MODULE]
    if options and options[name] ~= nil then return options[name] end
    return default
end

function OS.isEnabled()
    return OS.getOption("EnableMod", true) ~= false
end

function OS.getSteamId(player)
    local steamId = player and player:getSteamID()
    if steamId and tostring(steamId) ~= "0" then return tostring(steamId) end
    return player and player:getUsername() or nil
end
