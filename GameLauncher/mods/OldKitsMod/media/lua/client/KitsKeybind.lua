--[[
    KitsKeybind.lua
    Registra la tecla para abrir la UI de kits.
    Por defecto: K
    Se puede cambiar desde Opciones -> Controles en el juego.
]]

require "client/KitsUI"

local KEY_BIND_NAME = "[Kits]"

local function onGameStart()
    if not getCore():getKey(KEY_BIND_NAME) then
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
