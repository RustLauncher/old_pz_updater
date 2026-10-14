require "client/KitsUI"
require "client/KitsClient"

local KEY_BIND_NAME = "[Kits]"

local function onGameStart()
    local current = getCore():getKey(KEY_BIND_NAME)
    if current == nil or current == 0 then
        getCore():addKeyBinding(KEY_BIND_NAME, Keyboard.KEY_K)
    end
end

local function onKeyPressed(key)
    if key == getCore():getKey(KEY_BIND_NAME) then
        local player = getPlayer()
        if player and player:isAlive() then
            KitsUI.Toggle()
        end
    end
end

Events.OnGameStart.Add(onGameStart)
Events.OnKeyPressed.Add(onKeyPressed)
