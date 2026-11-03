require "DAMN_Armor_Shared";

--***********************************************************
--**                   KI5 / bikinihorst                   **
--***********************************************************
--v2.0.0

M911 = M911 or {};

function M911.activeArmor(player, vehicle)

		--

			local protection = vehicle:getPartById("M911Bullbar")
			local inventoryItem = protection:getInventoryItem();
			local part = vehicle:getPartById("EngineDoor")
				if part and protection and part:getInventoryItem() and inventoryItem and part:getModData()
				then 
					if inventoryItem:getFullType() ~= "Base.M911Bullbar0" then
						local partCond = tonumber(part:getModData().saveCond)
						if protection:getCondition() > 0 and partCond
						then
							if part:getCondition() < partCond
							then
								DAMN.Armor:setPartCondition(part, partCond);
								local cond = protection:getCondition() - (ZombRandBetween(0,100) <= 30 and ZombRandBetween(0,4) or 0);
								DAMN.Armor:setPartCondition(protection, cond);
							end
						end
					elseif inventoryItem:getFullType() == "Base.M911Bullbar0" then
						local partCond = tonumber(part:getModData().saveCond)
						if protection:getCondition() > 0 and partCond
						then
							if part:getCondition() < partCond
							then
								DAMN.Armor:setPartCondition(part, partCond);
								local cond = protection:getCondition() - (ZombRandBetween(0,100) <= 25 and ZombRandBetween(0,3) or 0);
								DAMN.Armor:setPartCondition(protection, cond);
							end
						end
					end
					else
						local protection = vehicle:getPartById("M911Bullbar")
						local inventoryItem = protection:getInventoryItem();
						local part = vehicle:getPartById("Engine")
							if protection and inventoryItem and part and part:getModData()
							then
								local partCond = tonumber(part:getModData().saveCond)
									if protection:getCondition() > 0 and partCond
									then
										if part:getCondition() < partCond
										then
											DAMN.Armor:setPartCondition(part, partCond);
											local cond = protection:getCondition() - ZombRandBetween(1,2);
											DAMN.Armor:setPartCondition(protection, cond);
										end
									end
							end
				end

        --
                
            local part = vehicle:getPartById("Engine")
                if part:getCondition() < 19 then
                    DAMN.Armor:setPartCondition(part, 19);
            end

            local part = vehicle:getPartById("M911Trunk")
                if part:getCondition() < 14 then
                    DAMN.Armor:setPartCondition(part, 14);
            end

            local part = vehicle:getPartById("M911Toolbox")
                if part:getCondition() < 26 then
                    DAMN.Armor:setPartCondition(part, 26);
            end

		--

			for partId, armorPartId in pairs({
				["WindowFrontLeft"] = "M911DoorFrontLeftArmor",
				["WindowFrontRight"] = "M911DoorFrontRightArmor",
			}) do
				local part = vehicle:getPartById(partId);
				local protection = vehicle:getPartById(armorPartId);
				if protection and protection:getInventoryItem() and part and part:getModData()
				then
					local partCond = tonumber(part:getModData().saveCond);
					if protection:getCondition() > 0 and partCond and part:getCondition() < partCond
					then
						DAMN.Armor:setPartCondition(part, partCond);
                        local cond = protection:getCondition() - ZombRandBetween(0,2)
						DAMN.Armor:setPartCondition(protection, cond);
					end
				end
			end

		--

			for partId, armorPartId in pairs({
				["HeadlightLeft"] = "M911Bullbar",
				["HeadlightRight"] = "M911Bullbar",
			}) do
				local part = vehicle:getPartById(partId);
				local protection = vehicle:getPartById(armorPartId);
				if protection and protection:getInventoryItem() and part and part:getModData()
				then
					local partCond = tonumber(part:getModData().saveCond);
					if protection:getCondition() > 0 and partCond and part:getCondition() < partCond
					then
						DAMN.Armor:setPartCondition(part, partCond);
						local cond = protection:getCondition() - (ZombRandBetween(0,100) <= 70 and ZombRandBetween(0,3) or 0)
						DAMN.Armor:setPartCondition(protection, cond);
					end
				end
			end

		--

            for partId, armorPartId in pairs({
				["Windshield"] = "M911WindshieldArmor",
				["WindshieldRear"] = "M911WindshieldRearArmor",
			}) do
				local part = vehicle:getPartById(partId);
				local protection = vehicle:getPartById(armorPartId);
				if protection and protection:getInventoryItem() and part and part:getModData()
				then
					local partCond = tonumber(part:getModData().saveCond);
					if protection:getCondition() > 0 and partCond and part:getCondition() < partCond
					then
						DAMN.Armor:setPartCondition(part, partCond);
                        local cond = protection:getCondition() - (ZombRandBetween(0,100) <= 65 and ZombRandBetween(0,3) or 0)
						DAMN.Armor:setPartCondition(protection, cond);
					end
				end
			end

		--

		for i, freezeState in ipairs ({"M911SpareTire", "GasTank"})
				do
					if vehicle:getPartById(freezeState) then
						local part = vehicle:getPartById(freezeState)
						local freezeCond = tonumber(part:getModData().saveCond)
					    	if freezeCond and part:getCondition() < freezeCond then
					    		DAMN.Armor:setPartCondition(part, freezeCond)
							end
					end
			end

end

DAMN.Armor:add("Base.82oshkoshM911", M911.activeArmor);
DAMN.Armor:add("Base.82oshkoshM911B", M911.activeArmor);