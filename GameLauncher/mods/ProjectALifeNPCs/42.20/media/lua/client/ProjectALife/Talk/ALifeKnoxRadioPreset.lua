require "RadioCom/RadioWindowModules/RWMChannel"

ProjectALife = ProjectALife or {}
local Preset = { frequency = 99600, name = "Knox County Radio" }
ProjectALife.KnoxRadioPreset = Preset

function Preset.ensure(device)
    local options = SandboxVars and SandboxVars.ALife
    if options ~= nil and options.Radio_KnoxCounty == false then return false end
    local frequency = tonumber(options and options.Radio_KnoxFrequency) or 99600
    frequency = math.max(88000, math.min(108000, math.floor(frequency)))

    if device == nil or device:getIsTelevision() or device:isNoTransmit() then return false end
    if frequency < device:getMinChannelRange() or frequency > device:getMaxChannelRange() then return false end
    local bank = device:getDevicePresets()
    if bank == nil then return false end
    local list = bank:getPresets()
    if list == nil then return false end
    for index = 0, list:size() - 1 do
        if list:get(index):getFrequency() == frequency then return false end
    end
    if list:size() >= bank:getMaxPresets() then return false end
    list:add(PresetEntry.new(Preset.name, frequency))
    device:transmitPresets()
    return true
end

if not RWMChannel.alifeKnoxPreset then
    local original = RWMChannel.readFromObject
    RWMChannel.readFromObject = function(self, player, object, device, deviceType)
        Preset.ensure(device)
        return original(self, player, object, device, deviceType)
    end
    RWMChannel.alifeKnoxPreset = true
end
return Preset
