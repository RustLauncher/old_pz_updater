-- Fletcher: put the bow's worn-visual slots and the quiver's (registered in media/registries.lua) into the human
-- body-location group, after vanilla's own (shared/NPCs/BodyLocations.lua loads first).
require "NPCs/BodyLocations"

for _, id in ipairs({ "fletcher:bow", "fletcher:arrow", "fletcher:quiver", "fletcher:backquiver", "fletcher:backquiverlook" }) do
    local ok, err = pcall(function()
        BodyLocations.getGroup("Human"):getOrCreateLocation(ItemBodyLocation.get(ResourceLocation.of(id)))
    end)
    if not ok then print("[Fletcher] body location " .. id .. " not added: " .. tostring(err)) end
end
