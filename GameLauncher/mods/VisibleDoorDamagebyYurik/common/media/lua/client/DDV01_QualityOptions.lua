require "PZAPI/ModOptions"
local D=require "DDV01_Shared"
local V=require "DDV01_Visual"
local options=PZAPI.ModOptions:create("VisibleDoorDamageQuality","Visible Door Damage")
options:addDescription("Local visual quality. Other players keep their own preference. Unavailable HD families use Standard.")
local quality=options:addComboBox("quality","Door texture quality",
    "Standard preserves the original textures. HD uses available detailed atlases; it may use more video memory.")
quality:addItem("Standard",true)
quality:addItem("HD",false)
function options:apply()
    V.setHDQuality(quality:getValue()==2)
end
Events.OnGameStart.Add(function() options:apply() end)
