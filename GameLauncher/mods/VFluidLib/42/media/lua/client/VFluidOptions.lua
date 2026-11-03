-- VFluidLib: mod options. Registered at file scope; PZAPI applies saved values later and edits
-- take effect live. No percent signs anywhere in these strings - labels run through getText.

VFluid = VFluid or {}
VFluid.options = VFluid.options or {}

if not PZAPI or not PZAPI.ModOptions then return end

local o = PZAPI.ModOptions:create("VFluidLib", "Vehicle Fluid Logistics")

o:addTitle("Using a tank directly")

VFluid.options.drinkWashMenu = o:addTickBox("drinkWashMenu",
	"Drink and wash at a vehicle tank", true,
	"On by default. A tank carrying water offers the same drink and wash options a sink or rain barrel does, and the water comes out of that tank. Turn it off to keep those options off vehicle tanks entirely. Whether anything harmful may be drunk is a separate sandbox setting.")
