-- Compatibility module for earlier overrides. The complete authored lit
-- pumpkin model now renders through its real IsoWorldInventoryObject. There
-- is no camera-dependent, separately projected glow overlay.
require "HalloweenEvent/EVHalloween_ItemFunctions"
local FX={disabled=true,proxies={},parents={},levels={}}
HalloweenEvent.Items.CandleEyes=FX
function FX.render() end
return FX
