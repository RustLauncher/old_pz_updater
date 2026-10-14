require "KitsConfig"

KitsClient = KitsClient or {}
KitsClient.Cooldowns = {}
KitsClient.Permissions = {}
KitsClient.IsAdmin = false

function KitsClient.RequestKit(kitId)
    sendClientCommand("Kits", "requestKit", { kitId = kitId })
end

function KitsClient.RequestCooldowns()
    sendClientCommand("Kits", "requestCooldowns", {})
end

function KitsClient.CheckAdmin()
    sendClientCommand("Kits", "checkAdmin", {})
end


function KitsClient.HasPermission(kitId)
    if KitsClient.Permissions[kitId] == nil then
        return true
    end
    return KitsClient.Permissions[kitId]
end

local function refreshInventoryUI()
    local player = getPlayer()
    if not player then return end
    local inv = player:getInventory()
    if inv then
        inv:setDrawDirty(true)
    end
    if ISInventoryPage and ISInventoryPage.dirtySlice ~= nil then
        ISInventoryPage.dirtySlice = true
    end
    local pInv = getPlayerInventory(0)
    if pInv then
        pInv:refreshBackpacks()
    end
    local pLoot = getPlayerLoot(0)
    if pLoot then
        pLoot:refreshBackpacks()
    end
end

local function onServerCommand(module, command, args)
    if module ~= "Kits" then return end

    if command == "cooldowns" then
        KitsClient.Cooldowns = args
        if KitsUI and KitsUI.instance then
            KitsUI.instance:updateCooldowns()
        end

    elseif command == "permissionsUpdate" then
        KitsClient.Permissions = args
        if KitsUI and KitsUI.instance then
            KitsUI.instance:updateCooldowns()
        end

    elseif command == "adminStatus" then
        KitsClient.IsAdmin = args.isAdmin
        if KitsUI and KitsUI.instance then
            KitsUI.instance:updateAdminButton()
        end

    elseif command == "kitGiven" then
        local player = getPlayer()
        if player then
            player:Say("Kit '" .. tostring(args.name) .. "' recibido!")
        end
        refreshInventoryUI()
        if KitsUI and KitsUI.instance then
            KitsUI.instance:updateCooldowns()
        end

    elseif command == "error" then
        local player = getPlayer()
        if player then
            player:Say(tostring(args.msg))
        end
    end
end

Events.OnServerCommand.Add(onServerCommand)
