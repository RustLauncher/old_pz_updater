require "KitsConfig"

KitsClient = KitsClient or {}
KitsClient.Cooldowns = {}
KitsClient.Permissions = {}
KitsClient.IsAdmin = false
KitsClient.TempRoles = {}
KitsClient.OnlinePlayers = {}
KitsClient.AllPlayers = {}
KitsClient.PlayerRole = "user"
KitsClient.PlayerRoleDaysLeft = -1
KitsClient.RoleColors = {}
KitsClient.OnlineRoles = {}

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
    local v = KitsClient.Permissions[kitId]
    if v == nil then
        return false
    end
    return v == "yes"
end

function KitsClient.AdminSetTempRole(targetName, roleName, days)
    sendClientCommand("Kits", "adminSetTempRole", {
        targetName = targetName,
        roleName = roleName,
        days = days,
    })
end

function KitsClient.AdminRemoveTempRole(targetName)
    sendClientCommand("Kits", "adminRemoveTempRole", { targetName = targetName })
end

function KitsClient.AdminListTempRoles()
    sendClientCommand("Kits", "adminListTempRoles", {})
end

function KitsClient.AdminListOnline()
    sendClientCommand("Kits", "adminListOnline", {})
end

function KitsClient.AdminListAllPlayers()
    sendClientCommand("Kits", "adminListAllPlayers", {})
end

function KitsClient.AdminGetKits()
    sendClientCommand("Kits", "adminGetKits", {})
end

function KitsClient.AdminSaveKit(kitId, name, icon, cooldown, permission, itemsStr)
    sendClientCommand("Kits", "adminSaveKit", {
        kitId = kitId,
        name = name,
        icon = icon,
        cooldown = tostring(cooldown),
        permission = permission,
        items = itemsStr,
    })
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

    elseif command == "tempRolesList" then
        KitsClient.TempRoles = args.roles or {}
        if KitsUI and KitsUI.instance then
            KitsUI.instance:updateTempRolesList()
        end

    elseif command == "onlineList" then
        KitsClient.OnlinePlayers = args.players or {}
        if KitsUI and KitsUI.instance then
            KitsUI.instance:updateOnlineList()
        end

    elseif command == "allPlayersList" then
        KitsClient.AllPlayers = args.players or {}
        if KitsUI and KitsUI.instance then
            KitsUI.instance:updatePlayerList()
        end

    elseif command == "kitsList" then
        local kits = args.kits or {}
        KitsConfig.Kits = {}
        for _, kd in ipairs(kits) do
            table.insert(KitsConfig.Kits, {
                id = kd.id,
                name = kd.name,
                icon = kd.icon,
                cooldown = tonumber(kd.cooldown) or 360,
                permission = kd.permission or "all",
                items = KitsConfig.DeserializeItems(kd.items),
            })
        end
        if KitsUI and KitsUI.instance then
            KitsUI.instance:rebuildKitsPanel()
        end

    elseif command == "playerRoleInfo" then
        KitsClient.PlayerRole = args.role or "user"
        KitsClient.PlayerRoleDaysLeft = tonumber(args.daysLeft) or -1
        if KitsUI and KitsUI.instance then
            KitsUI.instance:updateRoleBar()
        end

    elseif command == "onlineRoles" then
        KitsClient.OnlineRoles = args or {}
        local onlinePlayers = getOnlinePlayers()
        if onlinePlayers then
            for i = 0, onlinePlayers:size() - 1 do
                local p = onlinePlayers:get(i)
                if p and p.setShowAdminTag then
                    p:setShowAdminTag(false)
                end
            end
        end

    elseif command == "roleColors" then
        KitsClient.RoleColors = {}
        if args then
            for name, cStr in pairs(args) do
                local r, g, b = cStr:match("([%d%.]+),([%d%.]+),([%d%.]+)")
                if r then
                    KitsClient.RoleColors[name:lower()] = {
                        r = tonumber(r), g = tonumber(g), b = tonumber(b), a = 1,
                    }
                end
            end
        end

    elseif command == "error" then
        local player = getPlayer()
        if player then
            player:Say(tostring(args.msg))
        end
    end
end

Events.OnServerCommand.Add(onServerCommand)

local function onGameStart()
    sendClientCommand("Kits", "requestCooldowns", {})
end

Events.OnGameStart.Add(onGameStart)

local ROLE_TAG_COLORS = {
    admin     = { r = 255, g = 77,  b = 77  },
    moderator = { r = 77,  g = 153, b = 255 },
    gm        = { r = 204, g = 128, b = 255 },
    observer  = { r = 153, g = 153, b = 153 },
    priority  = { r = 255, g = 217, b = 51  },
    ultimate  = { r = 230, g = 38,  b = 89  },
    vip       = { r = 255, g = 217, b = 51  },
}

local roleTextCache = {}

local function getRoleTagColor(roleName)
    local c = ROLE_TAG_COLORS[roleName:lower()]
    if c then return c end
    return { r = 200, g = 200, b = 200 }
end

local function getPlayerScreenPosition(player)
    local worldX = player:getX()
    local worldY = player:getY()
    local worldZ = player:getZ()
    local screenX = IsoUtils.XToScreen(worldX, worldY, worldZ, 0)
    local screenY = IsoUtils.YToScreen(worldX, worldY, worldZ, 0)
    screenX = screenX - IsoCamera.getOffX()
    screenY = screenY - IsoCamera.getOffY()
    screenY = screenY - (128 / (2 / Core.getTileScale()))
    local zoom = Core.getInstance():getZoom(0)
    screenX = screenX / zoom
    screenY = screenY / zoom
    return screenX, screenY
end

local function calculateUsernameWidth(player)
    local username = player:getUsername()
    if not username or username == "" then return 0 end
    local displayUsername = getServerOptions():getBoolean("DisplayUserName")
    local showFirstAndLastName = getServerOptions():getBoolean("ShowFirstAndLastName")
    local namePart = ""
    if showFirstAndLastName then
        namePart = player:getFullName() or ""
    end
    if displayUsername then
        if namePart ~= "" then
            namePart = string.format("%s (%s)", namePart, username)
        else
            namePart = username
        end
    elseif not showFirstAndLastName then
        namePart = username
    end
    local tag = player.getTagPrefix and player:getTagPrefix() or nil
    if tag and tag ~= "" then
        namePart = "[" .. tag .. "] " .. namePart
    end
    local access = player:getAccessLevel()
    if access and access ~= "None" and player.isShowAdminTag and player:isShowAdminTag() then
        namePart = access .. " " .. namePart
    end
    if player.isSpeek or player.isVoiceMute then
        namePart = "   " .. namePart
    end
    return getTextManager():MeasureStringX(UIFont.Small, namePart)
end

local function getPlayerUsernameHeight(player)
    if player.getUserNameHeight then
        return player:getUserNameHeight()
    end
    return getTextManager():MeasureStringY(UIFont.Small, player:getUsername() or "")
end

local function renderRoleTags()
    local localPlayer = getPlayer()
    if not localPlayer then return end
    if not KitsClient.OnlineRoles then return end

    local displayUsername = getServerOptions():getBoolean("DisplayUserName")
    local showFirstAndLastName = getServerOptions():getBoolean("ShowFirstAndLastName")
    if not displayUsername and not showFirstAndLastName then return end

    local onlinePlayers = getOnlinePlayers()
    if not onlinePlayers then return end

    for i = 0, onlinePlayers:size() - 1 do
        local player = onlinePlayers:get(i)
        if player then
            if player.setShowAdminTag then
                player:setShowAdminTag(false)
            end
            local username = player:getUsername()
            local roleName = KitsClient.OnlineRoles[username]
            if roleName and roleName ~= "user" then
                local currentSquare = player:getCurrentSquare()
                if currentSquare and currentSquare:getCanSee(localPlayer:getPlayerNum()) then
                    local dx = localPlayer:getX() - player:getX()
                    local dy = localPlayer:getY() - player:getY()
                    local dist = math.sqrt(dx * dx + dy * dy)
                    if dist <= 20 then
                        local alpha = 1.0
                        if dist > 15 then
                            alpha = 1.0 - (dist - 15) / 5
                        end
                        if alpha > 0.1 then
                            local c = getRoleTagColor(roleName)
                            local tagStr = "[col=" .. c.r .. "," .. c.g .. "," .. c.b .. "][" .. roleName:upper() .. "][/]"
                            local onlineID = player:getOnlineID()
                            if not roleTextCache[onlineID] then
                                roleTextCache[onlineID] = TextDrawObject.new(255, 255, 255, true, true, true, true, true, true)
                                roleTextCache[onlineID]:setDefaultFont(UIFont.Small)
                            end
                            local textObj = roleTextCache[onlineID]
                            if textObj:getOriginal() ~= tagStr then
                                textObj:ReadString(tagStr)
                            end
                            local screenX, screenY = getPlayerScreenPosition(player)
                            local tagWidth = textObj:getWidth()
                            local finalX = screenX - (tagWidth / 2)
                            local usernameHeight = getPlayerUsernameHeight(player)
                            local tagHeight = getTextManager():MeasureStringY(UIFont.Small, "X")
                            local finalY = screenY - usernameHeight - tagHeight
                            textObj:AddBatchedDraw(finalX, finalY, true, alpha)
                        end
                    end
                end
            end
        end
    end
end

Events.OnPostRender.Add(renderRoleTags)
