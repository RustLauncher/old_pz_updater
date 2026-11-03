require "OfflineSurvivorSilentDeath/OS_BodyLifecycle"
local OS = OfflineSurvivorSilentDeath
local H = OS.BodyLifecycle

local function text(key, fallback, ...)
    if OS.translate then return OS.translate(key, fallback, ...) end
    return fallback
end

local function request(_, playerIndex)
    local player=getSpecificPlayer(playerIndex)
    if H.isAdmin(player) then sendClientCommand(player,OS.MODULE,"AdminRemoveBodies",{}) end
end

Events.OnFillWorldObjectContextMenu.Add(function(playerIndex,context,worldObjects,test)
    if test then return end
    local player=getSpecificPlayer(playerIndex)
    if not H.isAdmin(player) then return end
    local radius=math.max(1,math.min(50,math.floor(H.finite(OS.getOption("AdminCleanupRadius",15)) or 15)))
    local option=context:addOption(text("AdminCleanup","[Admin] Remove bodies nearby (%1 tiles)",radius))
    local menu=ISContextMenu:getNew(context)
    context:addSubMenu(option,menu)
    menu:addOption(text("AdminCleanupConfirm","Confirm removal (same floor; corpse loot is deleted)"),
        OS,request,playerIndex)
end)

Events.OnServerCommand.Add(function(module,command,args)
    if module~=OS.MODULE or command~="AdminCleanupResult" then return end
    local player=getSpecificPlayer(0)
    if not player then return end
    args=args or {}
    if args.status=="finished" then
        player:Say(text("AdminCleanupFinished","Removed bodies: %1. Sleeping players were not killed.",args.count or 0))
    elseif args.status=="busy" then
        player:Say(text("AdminCleanupBusy","A cleanup is in progress. Wait before trying again."))
    else
        player:Say(text("AdminCleanupStarted","Area cleanup started."))
    end
end)
