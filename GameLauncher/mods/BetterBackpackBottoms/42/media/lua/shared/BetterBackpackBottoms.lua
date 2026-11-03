local BBB = {}

local function initToolboxAttachment()
    local items = {
        { id = "Base.Toolbox",              model = "ToolBox_BagAttached" },
        { id = "Base.Toolbox_Farming",       model = "ToolBox_BagAttached" },
        { id = "Base.Toolbox_Fishing",       model = "ToolBox_BagAttached" },
        { id = "Base.Toolbox_Gardening",     model = "ToolBox_BagAttached" },
        { id = "Base.Toolbox_Mechanic",      model = "ToolBox_BagAttached" },
        { id = "Base.FirstAidKit",          model = "FirstAidKit_BagAttached" },
        { id = "Base.FirstAidKit_New",       model = "FirstAidKit_BagAttached" },
        { id = "Base.FirstAidKit_NewPro",    model = "FirstAidKit_BagAttached" },
        { id = "Base.Lunchbox",             model = "Lunchbox_BagAttached" },
        { id = "Base.PetrolCan",            model = "PetrolCan_BagAttached" },
        { id = "Base.JerryCan",             model = "JerryCan_BagAttached" },
        { id = "Base.WaterBottle",          model = "WaterBottle_BagAttached" },
        { id = "Base.Sportsbottle",         model = "Sportsbottle_BagAttached" },
        { id = "Base.Tacklebox",            model = "Tacklebox_BagAttached" },
    }

    for _, item in ipairs(items) do
        local scriptItem = ScriptManager.instance:getItem(item.id)
        if scriptItem then
            scriptItem:DoParam("AttachmentType = Canteen")
            scriptItem:DoParam("StaticModel = " .. item.model)
            print("[BBB] " .. item.id .. " -> AttachmentType = Canteen, StaticModel = " .. item.model)
        else
            print("[BBB] ERROR: " .. item.id .. " script item not found")
        end
    end

    local found = 0
    if ISHotbarAttachDefinition then
        for _, slotDef in ipairs(ISHotbarAttachDefinition) do
            if slotDef.type == "BedrollBottom"
                or slotDef.type == "BedrollBottomBig"
                or slotDef.type == "BedrollBottomALICE" then

                slotDef.attachments = slotDef.attachments or {}
                local bedrollLocation = slotDef.attachments.Bedroll
                if bedrollLocation and not slotDef.attachments.Canteen then
                    slotDef.attachments.Canteen = bedrollLocation
                    print("[BBB] " .. slotDef.type .. " -> Canteen uses location '" .. bedrollLocation .. "'")
                elseif not bedrollLocation then
                    print("[BBB] WARNING: " .. slotDef.type .. " has no Bedroll attachment to copy a location from")
                end
                found = found + 1
            end
        end
    end
    print("[BBB] Bottom slot definitions updated: " .. tostring(found))
end

Events.OnGameBoot.Add(initToolboxAttachment)

return BBB