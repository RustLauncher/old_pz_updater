local vanilla_prerender = ISVehicleDashboard.prerender
function ISVehicleDashboard:prerender()
    vanilla_prerender(self)

    local player = getPlayer()
    if not player then return end
	local vehicle = player:getVehicle()
    if not vehicle then return end

    local engine = vehicle:getPartById("Engine")
    local battery = vehicle:getPartById("Battery") and vehicle:getPartById("Battery"):getInventoryItem() and vehicle:getPartById("Battery") or nil
    local headlightLeft = vehicle:getPartById("HeadlightLeft") and vehicle:getPartById("HeadlightLeft"):getInventoryItem() and vehicle:getPartById("HeadlightLeft") or nil
    local headlightRight = vehicle:getPartById("HeadlightRight") and vehicle:getPartById("HeadlightRight"):getInventoryItem() and vehicle:getPartById("HeadlightRight") or nil

    if engine and engine:getCondition() then
        self.engineTex.mouseovertext = getText("IGUI_VehiclePartEngine") .. " (" .. getText("IGUI_invpanel_Condition") .. ": " .. engine:getCondition() .. "%)"
    end
    
    if battery and battery:getCondition() and battery:getInventoryItem() then
        local cond = battery:getCondition()
        local charge = math.floor(vehicle:getBatteryCharge() * 100)
        self.batteryTex.mouseovertext = getText("Tooltip_Dashboard_Battery") .. " (" .. getText("IGUI_invpanel_Condition") .. ": " .. cond .. "%, " .. getText("IGUI_invpanel_Remaining") .. ": " .. charge .. "%)"
    else
        self.batteryTex.mouseovertext = getText("Tooltip_Dashboard_Battery") .. " (" .. getText("IGUI_Missing") .. ")"
    end
    
    local leftConditionText = headlightLeft and (headlightLeft:getCondition() .. "%") or getText("IGUI_Missing")
    self.lightsTex.mouseovertext = getText("Tooltip_Dashboard_Headlights") .. ": (" .. getText("IGUI_VehiclePartHeadlightLeft") .. ": " .. leftConditionText .. ", "

    local rightConditionText = headlightRight and (headlightRight:getCondition() .. "%") or getText("IGUI_Missing")
    self.lightsTex.mouseovertext = self.lightsTex.mouseovertext .. getText("IGUI_VehiclePartHeadlightRight") .. ": " .. rightConditionText .. ")"
end