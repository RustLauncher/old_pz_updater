--[[
████  █  █   ███     ████  █   █    █     █████ █   █ █████  ████ 
█   █ █  █  █   █    █   █  █ █     █     █     ██ ██ █     █     
████  █████    █     ████    █      █     ████  █ █ █ ████   ███  
█   █    █    █      █   █   █      █     █     █   █ █         █ 
████     █  █████    ████    █      █████ █████ █   █ █████ ████
--]]  

local function onFillWorldObjectContextMenu(playerIndex, context, worldobjects, test)
	for i = 1, #worldobjects do
		local obj = worldobjects[i]
		if UsableSafe.isSafeTile(obj) then
			UsableSafe.ensureContainer(obj)
		end
	end
end
Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)

UsableSafe.log("UsableSafe_Client.lua loaded")
