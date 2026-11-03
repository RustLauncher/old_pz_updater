if ISMoodlesInLua == nil then return end -- do not remove this

local name = "Simple Moodle Indicators" -- Name of your texture set
local path = "media/ui/MIL/SimpleMoodleIndicators" -- Path to your textures

ISMoodlesInLuaHandle:registerBorderTextureSet(name, path)

local nameB = "Simple Moodle Indicators (Square)" -- Name of your texture set
local pathB = "media/ui/MIL/SimpleMoodleIndicatorsSquare" -- Path to your textures
local optionsB = { iconOffsetX = -9 } -- actual is -9.5

ISMoodlesInLuaHandle:registerBorderTextureSet(nameB, pathB, optionsB)
