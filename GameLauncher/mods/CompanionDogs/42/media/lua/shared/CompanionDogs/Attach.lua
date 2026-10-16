local group = AttachedLocations.getGroup("Animal")
if group then
    for _, name in ipairs({ "saddlebags_l", "saddlebags_r", "saddlebags_c" }) do
        group:getOrCreateLocation(name):setAttachmentName(name)
    end
end
