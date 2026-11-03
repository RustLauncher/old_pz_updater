require "KitsUI"
require "KitsClient"

local function onKeyPressed(key)
    if key == Keyboard.KEY_K then
        local player = getPlayer()
        if player and player:isAlive() then
            KitsUI.Toggle()
        end
    end
end

Events.OnKeyPressed.Add(onKeyPressed)
