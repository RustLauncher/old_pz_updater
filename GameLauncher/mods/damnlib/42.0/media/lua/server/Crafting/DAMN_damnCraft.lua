--[[
    This file is part of that DAMN Library (Workshop ID 3171167894) authored by KI5 / bikinihorst.
    No permission is given for redistribution, repacking or modifying this or other files contained within the named
    workshop item, regardless of visibility or target community size, except if explicitly allowed by the author.
    TIS / Steam modding policy: https://projectzomboid.com/blog/modding-policy/
    This mod is "On Lockdown": https://theindiestone.com/forums/index.php?/topic/2530-mod-permissions/#findComment-36479
]]--

DAMN = DAMN or {}
DAMN.OnCreate = {}
DAMN.OnGiveXP = {}
DAMN.OnTest = {}

--Packing... heat

function DAMN.OnCreate.PackStuff(craftRecipeData, character)

    local allCond = 0;
    local items = craftRecipeData:getAllConsumedItems();
    local result = craftRecipeData:getAllCreatedItems():get(0);

    for i=0,items:size() - 1 do
        allCond = allCond + items:get(i):getCondition()
    end

    local averageCond = allCond / items:size();

    if averageCond > 100 then
        averageCond = 100
    end

    result:setCondition(averageCond)
    
end 

function DAMN.OnCreate.UnpackStuff(craftRecipeData, character)

    local item = craftRecipeData:getAllConsumedItems():get(0);
    local itemCond = item:getCondition();
    local results = craftRecipeData:getAllCreatedItems();

    for i = 0, results:size() - 1 do
        results:get(i):setCondition(itemCond)
    end

end

function DAMN.OnCreate.PassSecondCond(craftRecipeData, character)

    local item = craftRecipeData:getAllConsumedItems():get(1);
    local itemCond = item:getCondition();
    local result = craftRecipeData:getAllCreatedItems():get(0);

    result:setCondition(itemCond)

end

function DAMN.OnCreate.CombineFirstTwo(craftRecipeData, character)

    local allCond = 0;
    local items = craftRecipeData:getAllConsumedItems();
    local result = craftRecipeData:getAllCreatedItems():get(0);

    for i = 0, 1 do
        if i < items:size() then
            allCond = allCond + items:get(i):getCondition()
        end
    end

    local averageCond = allCond / 2

    if averageCond > 100 then
        averageCond = 100
    end

    result:setCondition(averageCond)
    
end

function DAMN.OnCreate.CombineFirstFour(craftRecipeData, character)

    local allCond = 0;
    local items = craftRecipeData:getAllConsumedItems();
    local result = craftRecipeData:getAllCreatedItems():get(0);

    for i = 0, 3 do
        if i < items:size() then
            allCond = allCond + items:get(i):getCondition()
        end
    end

    local averageCond = allCond / 4

    if averageCond > 100 then
        averageCond = 100
    end

    result:setCondition(averageCond)
    
end

--Rubber

function DAMN.OnCreate.MakeRubberStrips(craftRecipeData, character)

    local item = craftRecipeData:getAllConsumedItems():get(0);
    local tireCond = item:getCondition();

    if tireCond < 26 then
        character:getInventory():AddItem("damnCraft.RubberStrip")
    elseif tireCond < 81 then
        character:getInventory():AddItem("damnCraft.RubberStrip")
        character:getInventory():AddItem("damnCraft.RubberStrip")
        character:getInventory():AddItem("damnCraft.RubberStrip")
    else
        character:getInventory():AddItem("damnCraft.RubberStrip")
        character:getInventory():AddItem("damnCraft.RubberStrip")
        character:getInventory():AddItem("damnCraft.RubberStrip")
        character:getInventory():AddItem("damnCraft.RubberStrip")
        character:getInventory():AddItem("damnCraft.RubberStrip")
        character:getInventory():AddItem("damnCraft.RubberStrip")
    end

end

--Scrap metal

function DAMN.OnCreate.GetScrapMetal(craftRecipeData, character)

    local chance = ZombRandBetween(0,100);

    if chance < 41 then
        character:getInventory():AddItem("Base.ScrapMetal");
    elseif chance < 82 then
        character:getInventory():AddItem("Base.ScrapMetal");
        character:getInventory():AddItem("Base.ScrapMetal");
    else
        character:getInventory():AddItem("Base.ScrapMetal");
        character:getInventory():AddItem("Base.ScrapMetal");
        character:getInventory():AddItem("Base.ScrapMetal");
        character:getInventory():AddItem("Base.ScrapMetal");
    end

end

--Tire Repair Kit

function DAMN.OnCreate.RepairTireOne(craftRecipeData, character)

    DAMN.RepairTire(craftRecipeData, character, 1, craftRecipeData:getFirstInputItemWithFlag("IsDamaged"))

end

function DAMN.OnCreate.RepairTireTwo(craftRecipeData, character)

    DAMN.RepairTire(craftRecipeData, character, 2, craftRecipeData:getFirstInputItemWithFlag("IsDamaged"))

end

function DAMN.OnCreate.RepairTireFour(craftRecipeData, character)

    DAMN.RepairTire(craftRecipeData, character, 4, craftRecipeData:getFirstInputItemWithFlag("IsDamaged"))

end

function DAMN.RepairTire(craftRecipeData, character, amount, item, skill)

    if not item then item = craftRecipeData:getFirstInputItemWithFlag("IsDamaged") end
    if not amount then amount = 1 end
    if not character then character = craftRecipeData:getPlayer() end
    if not skill then skill  = character:getPerkLevel(Perks.Mechanics); end

    local tireCond = item:getCondition();
    local maxCond = item:getConditionMax();

    local newCond = tireCond + (ZombRand((2 + skill * 5), (5 + skill * 10)));

        if newCond > maxCond then item:setCondition(maxCond);
        else item:setCondition(newCond);
        end
        item:syncItemFields();

end

--Dismantling

function DAMN.OnCreate.DismantleTireSmallMounted(craftRecipeData, character)

    local item = craftRecipeData:getAllConsumedItems():get(0)
    local itemCond = item:getCondition()
    local addType

    if itemCond < 26 then
        addType = "damnCraft.TireRubberDestroyedSmall"
    elseif itemCond < 81 then
        addType = "damnCraft.TireRubberUsedSmall"
    else
        addType = "damnCraft.TireRubberNewSmall"
    end

    local tire = character:getInventory():AddItem(addType)
    tire:setCondition(itemCond)
end

function DAMN.OnCreate.DismantleTireLargeMounted(craftRecipeData, character)

    local item = craftRecipeData:getAllConsumedItems():get(0)
    local itemCond = item:getCondition()
    local addType

    if itemCond < 26 then
        addType = "damnCraft.TireRubberDestroyedLarge"

    elseif itemCond < 81 then
        addType = "damnCraft.TireRubberUsedLarge"
    else
        addType = "damnCraft.TireRubberNewLarge"
    end

    local tire = character:getInventory():AddItem(addType)
    tire:setCondition(itemCond)

end

--Recycling

function DAMN.OnCreate.DismantleTireSmall(craftRecipeData, character)

    local item = craftRecipeData:getAllConsumedItems():get(0)
    if not item or not item:hasTag("damnTire") then return end
    local itemCond = item:getCondition()
    local addType

    if itemCond < 26 then
        addType = "damnCraft.TireRubberDestroyedSmall"
    elseif itemCond < 81 then
        addType = "damnCraft.TireRubberUsedSmall"
    else
        addType = "damnCraft.TireRubberNewSmall"
    end

    local tire = character:getInventory():AddItem(addType)
    tire:setCondition(itemCond)
end

function DAMN.OnCreate.DismantleTireLargeMedium(craftRecipeData, character)

    local item = craftRecipeData:getAllConsumedItems():get(0)
    if not item or (not item:hasTag("damnTireMedium") and not item:hasTag("damnTireLarge")) then return end
    local itemCond = item:getCondition()
    local addType

    if itemCond < 26 then
        addType = "damnCraft.TireRubberDestroyedLarge"

    elseif itemCond < 81 then
        addType = "damnCraft.TireRubberUsedLarge"
    else
        addType = "damnCraft.TireRubberNewLarge"
    end

    local tire = character:getInventory():AddItem(addType)
    tire:setCondition(itemCond)

end

function DAMN.OnCreate.DismantleHood(craftRecipeData, character)
    local item = craftRecipeData:getAllConsumedItems():get(0)
    if not item or not item:hasTag("damnHood") then return end

    local itemCond = item:getCondition()

    if itemCond < 10 then
        character:getInventory():AddItem("Base.ScrapMetal");
    elseif itemCond < 81 then
        character:getInventory():AddItem("Base.ScrapMetal");
        character:getInventory():AddItem("damnCraft.HingeLarge");
        character:getInventory():AddItem("Base.Screws");
    else
        character:getInventory():AddItem("damnCraft.HingeLarge");
        character:getInventory():AddItem("damnCraft.HingeLarge");
        character:getInventory():AddItem("Base.Screws");
        character:getInventory():AddItem("Base.SheetMetal");
    end
end

function DAMN.OnCreate.DismantleTrunkLid(craftRecipeData, character)
    local item = craftRecipeData:getAllConsumedItems():get(0)
    if not item or not item:hasTag("damnTrunkLid") then return end

    local itemCond = item:getCondition()

    if itemCond < 10 then
        character:getInventory():AddItem("Base.ScrapMetal");
    elseif itemCond < 81 then
        character:getInventory():AddItem("Base.ScrapMetal");
        character:getInventory():AddItem("damnCraft.HingeLarge");
        character:getInventory():AddItem("Base.Screws");
    else
        character:getInventory():AddItem("damnCraft.HingeLarge");
        character:getInventory():AddItem("damnCraft.HingeLarge");
        character:getInventory():AddItem("Base.Screws");
        character:getInventory():AddItem("Base.SheetMetal");
    end
end

function DAMN.OnCreate.DismantleTrunkLids(craftRecipeData, character)
    local item = craftRecipeData:getAllConsumedItems():get(0)
    if not item or not item:hasTag("damnTrunkLids") then return end

    local itemCond = item:getCondition()

    if itemCond < 10 then
        character:getInventory():AddItem("Base.ScrapMetal");
    elseif itemCond < 81 then
        character:getInventory():AddItem("Base.ScrapMetal");
        character:getInventory():AddItem("damnCraft.HingeLarge");
        character:getInventory():AddItem("damnCraft.HingeLarge");
        character:getInventory():AddItem("Base.Screws");
    else
        character:getInventory():AddItem("damnCraft.HingeLarge");
        character:getInventory():AddItem("damnCraft.HingeLarge");
        character:getInventory():AddItem("damnCraft.HingeLarge");
        character:getInventory():AddItem("damnCraft.HingeLarge");
        character:getInventory():AddItem("Base.Screws");
        character:getInventory():AddItem("Base.Screws");
        character:getInventory():AddItem("Base.SheetMetal");
        character:getInventory():AddItem("Base.SheetMetal");
    end
end

function DAMN.OnCreate.DismantleDoorModern(craftRecipeData, character)
    local item = craftRecipeData:getAllConsumedItems():get(0)
    if not item or not item:hasTag("damnDoorModern") then return end

    local itemCond = item:getCondition()

    if itemCond < 10 then
        character:getInventory():AddItem("Base.ScrapMetal");
        character:getInventory():AddItem("damnCraft.HingeSmall");
    elseif itemCond < 81 then
        character:getInventory():AddItem("Base.ScrapMetal");
        character:getInventory():AddItem("damnCraft.HingeSmall");
        character:getInventory():AddItem("damnCraft.HandleModern");
        character:getInventory():AddItem("Base.Screws");
    else
        character:getInventory():AddItem("damnCraft.HingeSmall");
        character:getInventory():AddItem("damnCraft.HingeSmall");
        character:getInventory():AddItem("Base.Wire");
        character:getInventory():AddItem("damnCraft.HandleModern");
        character:getInventory():AddItem("Base.Screws");
        character:getInventory():AddItem("Base.SheetMetal");
    end
end

function DAMN.OnCreate.DismantleDoorClassic(craftRecipeData, character)
    local item = craftRecipeData:getAllConsumedItems():get(0)
    if not item or not item:hasTag("damnDoorClassic") then return end

    local itemCond = item:getCondition()

    if itemCond < 10 then
        character:getInventory():AddItem("Base.ScrapMetal");
        character:getInventory():AddItem("damnCraft.HingeSmall");
    elseif itemCond < 81 then
        character:getInventory():AddItem("Base.ScrapMetal");
        character:getInventory():AddItem("damnCraft.HingeSmall");
        character:getInventory():AddItem("damnCraft.HandleClassic");
        character:getInventory():AddItem("Base.Screws");
    else
        character:getInventory():AddItem("damnCraft.HingeSmall");
        character:getInventory():AddItem("damnCraft.HingeSmall");
        character:getInventory():AddItem("Base.Wire");
        character:getInventory():AddItem("damnCraft.HandleClassic");
        character:getInventory():AddItem("Base.Screws");
        character:getInventory():AddItem("Base.SheetMetal");
    end
end

function DAMN.OnCreate.DismantleWindshield(craftRecipeData, character)
    local item = craftRecipeData:getAllConsumedItems():get(0)
    if not item or not item:hasTag("damnWindshield") then return end

    local itemCond = item:getCondition()

    if itemCond < 10 then
        character:getInventory():AddItem("damnCraft.RubberStrip");
        character:getInventory():AddItem("Base.BrokenGlass");
    elseif itemCond < 81 then
        character:getInventory():AddItem("damnCraft.RubberStrip");
        character:getInventory():AddItem("Base.BrokenGlass");
        character:getInventory():AddItem("Base.GlassPanel");
    else
        character:getInventory():AddItem("damnCraft.RubberStrip");
        character:getInventory():AddItem("damnCraft.RubberStrip");
        character:getInventory():AddItem("Base.GlassPanel");
        character:getInventory():AddItem("Base.GlassPanel");
    end
end

function DAMN.OnCreate.DismantleWindow(craftRecipeData, character)
    local item = craftRecipeData:getAllConsumedItems():get(0)
    if not item or not item:hasTag("damnWindow") then return end

    local itemCond = item:getCondition()

    if itemCond < 10 then
        character:getInventory():AddItem("Base.BrokenGlass");
    elseif itemCond < 81 then
        character:getInventory():AddItem("Base.BrokenGlass");
    else
        character:getInventory():AddItem("Base.GlassPanel");
    end
end

function DAMN.OnCreate.DismantleWoodenArmor(craftRecipeData, character)
    local item = craftRecipeData:getAllConsumedItems():get(0)
    if not item or not item:hasTag("damnWoodenArmor") then return end

    local itemCond = item:getCondition()

    if itemCond < 26 then
        character:getInventory():AddItem("Base.UnusableWood");
    elseif itemCond < 70 then
        character:getInventory():AddItem("Base.Plank");
    	character:getInventory():AddItem("Base.UnusableWood");
    	character:getInventory():AddItem("Base.Nails");
    	character:getInventory():AddItem("Base.Nails");
    else
        character:getInventory():AddItem("Base.Plank");
        character:getInventory():AddItem("Base.Plank");
    	character:getInventory():AddItem("Base.UnusableWood");
    	character:getInventory():AddItem("Base.Nails");
    	character:getInventory():AddItem("Base.Nails");
    	character:getInventory():AddItem("Base.Nails");
    end
end

function DAMN.OnCreate.DismantleMetalArmor(craftRecipeData, character)
    local item = craftRecipeData:getAllConsumedItems():get(0)
    if not item or not item:hasTag("damnMetalArmor") then return end

    local itemCond = item:getCondition()

    if itemCond < 10 then
        character:getInventory():AddItem("Base.ScrapMetal");
    elseif itemCond < 81 then
        character:getInventory():AddItem("Base.ScrapMetal");
        character:getInventory():AddItem("Base.MetalPipe");
        character:getInventory():AddItem("Base.Screws");
    else
        character:getInventory():AddItem("Base.ScrapMetal");
        character:getInventory():AddItem("Base.MetalPipe");
        character:getInventory():AddItem("Base.SmallSheetMetal");
        character:getInventory():AddItem("Base.Screws");
    end
end

function DAMN.OnCreate.DismantleMudflaps(craftRecipeData, character)
    local item = craftRecipeData:getAllConsumedItems():get(0)
    if not item or not item:hasTag("damnMudflaps") then return end

    local itemCond = item:getCondition()

    if itemCond < 50 then
        character:getInventory():AddItem("damnCraft.RubberStrip");
    else
        character:getInventory():AddItem("damnCraft.RubberStrip");
        character:getInventory():AddItem("damnCraft.RubberStrip");
    end
end

function DAMN.OnCreate.DismantleSidesteps(craftRecipeData, character)
    local item = craftRecipeData:getAllConsumedItems():get(0)
    if not item or not item:hasTag("damnSidesteps") then return end

    local itemCond = item:getCondition()

    if itemCond < 10 then
        character:getInventory():AddItem("Base.ScrapMetal");
    elseif itemCond < 81 then
        character:getInventory():AddItem("Base.ScrapMetal");
        character:getInventory():AddItem("Base.Screws");
    else
        character:getInventory():AddItem("Base.ScrapMetal");
        character:getInventory():AddItem("Base.SmallSheetMetal");
        character:getInventory():AddItem("Base.Screws");
    end
end

function DAMN.OnCreate.DismantleMetalBumper(craftRecipeData, character)
    local item = craftRecipeData:getAllConsumedItems():get(0)
    if not item or not item:hasTag("damnMetalBumper") then return end

    local itemCond = item:getCondition()

    if itemCond < 10 then
        character:getInventory():AddItem("Base.ScrapMetal");
    elseif itemCond < 81 then
        character:getInventory():AddItem("Base.ScrapMetal");
        character:getInventory():AddItem("Base.SmallSheetMetal");
        character:getInventory():AddItem("Base.Screws");
    else
        character:getInventory():AddItem("Base.ScrapMetal");
        character:getInventory():AddItem("Base.SmallSheetMetal");
        character:getInventory():AddItem("Base.SmallSheetMetal");
        character:getInventory():AddItem("Base.Screws");
    end
end

function DAMN.OnCreate.DismantleMetalRoofrack(craftRecipeData, character)
    local item = craftRecipeData:getAllConsumedItems():get(0)
    if not item or not item:hasTag("damnMetalRoofrack") then return end

    local itemCond = item:getCondition()

    if itemCond < 10 then
        character:getInventory():AddItem("Base.ScrapMetal");
    elseif itemCond < 81 then
        character:getInventory():AddItem("Base.ScrapMetal");
        character:getInventory():AddItem("Base.MetalPipe");
        character:getInventory():AddItem("Base.Screws");
    else
        character:getInventory():AddItem("Base.ScrapMetal");
        character:getInventory():AddItem("Base.MetalPipe");
        character:getInventory():AddItem("Base.MetalPipe");
        character:getInventory():AddItem("Base.Screws");
        character:getInventory():AddItem("Base.Screws");
    end
end

function DAMN.OnCreate.DismantleToolbox(craftRecipeData, character)
    local item = craftRecipeData:getAllConsumedItems():get(0)
    if not item or not item:hasTag("damnToolbox") then return end

    local itemCond = item:getCondition()

    if itemCond < 10 then
        character:getInventory():AddItem("Base.ScrapMetal");
    elseif itemCond < 81 then
        character:getInventory():AddItem("Base.ScrapMetal");
        character:getInventory():AddItem("Base.Screws");
    else
        character:getInventory():AddItem("Base.Screws");
        character:getInventory():AddItem("Base.SheetMetal");
    end
end

function DAMN.OnCreate.DismantleTarpSmall(craftRecipeData, character)
    local item = craftRecipeData:getAllConsumedItems():get(0)
    if not item or not item:hasTag("damnTarpSmall") then return end

    local itemCond = item:getCondition()

    if itemCond < 10 then
        character:getInventory():AddItem("damnCraft.RubberStrip");
    elseif itemCond < 81 then
        character:getInventory():AddItem("damnCraft.RubberStrip");
        character:getInventory():AddItem("damnCraft.RubberStrip");
    else
        character:getInventory():AddItem("damnCraft.RubberStrip");
        character:getInventory():AddItem("Base.Tarp");
    end
end

function DAMN.OnCreate.DismantleTarpLarge(craftRecipeData, character)
    local item = craftRecipeData:getAllConsumedItems():get(0)
    if not item or not item:hasTag("damnTarpLarge") then return end

    local itemCond = item:getCondition()

    if itemCond < 10 then
        character:getInventory():AddItem("damnCraft.RubberStrip");
    elseif itemCond < 81 then
        character:getInventory():AddItem("damnCraft.RubberStrip");
        character:getInventory():AddItem("Base.Tarp");
    else
        character:getInventory():AddItem("damnCraft.RubberStrip");
        character:getInventory():AddItem("Base.Tarp");
        character:getInventory():AddItem("Base.Tarp");
    end
end

--Repair Metal

function DAMN.OnCreate.RepairMetal(craftRecipeData, character)
    local item = craftRecipeData:getFirstInputItemWithFlag("IsDamaged")
    character = character or craftRecipeData:getPlayer()
    local skill = character:getPerkLevel(Perks.MetalWelding)

    if not item then return end

    local itemCond = item:getCondition()
    local maxCond = item:getConditionMax()

    local newCond = itemCond + ZombRand((2 + skill * 5), (5 + skill * 10))

    if newCond > maxCond then
        item:setCondition(maxCond)
    else
        item:setCondition(newCond)
    end

    item:syncItemFields()
end

--Plastic Welding Kit

function DAMN.OnCreate.PlasticWeldingGunBatteryRemoval(craftRecipeData, character)

    local items = craftRecipeData:getAllKeepInputItems();
	local result = craftRecipeData:getAllCreatedItems():get(0);

    for i=0, items:size()-1 do
        local item = items:get(i)
        if item:getFullType() == "damnCraft.PlasticWeldingGun"  then
            result:setUsedDelta(item:getCurrentUsesFloat());
			item:setUsedDelta(0);
        end
    end
    item:syncItemFields();

end

function DAMN.OnCreate.PlasticWeldingGunBatteryInsert(craftRecipeData, character)

    local items = craftRecipeData:getAllConsumedItems();
	local result = craftRecipeData:getAllCreatedItems():get(0);

    for i=0, items:size()-1 do
    if items:get(i):getType() == "Battery" then
        result:setUsedDelta(items:get(i):getCurrentUsesFloat());
    end
  end

end

function DAMN.OnCreate.RepairPlastic(craftRecipeData, character)
    local items = craftRecipeData:getAllKeepInputItems()
    local item = craftRecipeData:getFirstInputItemWithFlag("IsDamaged")
    character = character or craftRecipeData:getPlayer()
    local skill = character:getPerkLevel(Perks.Mechanics)

    local itemCond = item:getCondition()
    local maxCond = item:getConditionMax()
    local newCond = itemCond + ZombRand((2 + skill * 5), (5 + skill * 10))

    if newCond > maxCond then
        item:setCondition(maxCond)
    else
        item:setCondition(newCond)
    end

    for i = 0, items:size() - 1 do
        local welder = items:get(i)
        if welder:getFullType() == "damnCraft.PlasticWeldingGun" then
            local currentCharge = welder:getCurrentUsesFloat() 
            local usageCost = 0.05

            if currentCharge >= usageCost then
                welder:setCurrentUsesFloat(currentCharge - usageCost)
                welder:syncItemFields()
            end
        end
    end
end

--Repair Tarp

function DAMN.OnCreate.RepairTarp(craftRecipeData, character)

    if not item then item = craftRecipeData:getFirstInputItemWithFlag("IsDamaged") end
    if not character then character = craftRecipeData:getPlayer() end
    if not skill then skill  = character:getPerkLevel(Perks.Mechanical); end

    local itemCond = item:getCondition();
    local maxCond = item:getConditionMax();

    local newCond = itemCond + (ZombRand((2 + skill * 5), (5 + skill * 10)));

        if newCond > maxCond then item:setCondition(maxCond);
        else item:setCondition(newCond);
        end
        item:syncItemFields();

end

--Plastic Molding

function DAMN.OnCreate.MakePlasterMold(craftRecipeData, character)
    local item = craftRecipeData:getAllConsumedItems():get(0)
    local originalItem = item:getFullType()
    local itemCond = item:getCondition()

    local result = craftRecipeData:getAllCreatedItems():get(0)

    local text = getText(item:getDisplayName())
    result:setName(text .. " Plaster Mold")

    local modData = result:getModData()
    modData.damnOriginalItemType = originalItem
    modData.damnOriginalDisplayName = text
    modData.damnOriginalItemCond = itemCond
end

function DAMN.OnCreate.RemoveOldPartFromMold(craftRecipeData, character)
    local item = craftRecipeData:getAllConsumedItems():get(0)
    local result = craftRecipeData:getAllCreatedItems():get(0)

    local modData = item:getModData()
    local damnOriginalItemType = modData.damnOriginalItemType
    local damnOriginalDisplayName = modData.damnOriginalDisplayName
    local damnOriginalItemCond = modData.damnOriginalItemCond

    if damnOriginalItemType and damnOriginalItemCond then
        local oldItem = character:getInventory():AddItem(damnOriginalItemType)
        oldItem:setCondition(damnOriginalItemCond)

        result:setName(damnOriginalDisplayName .. " Negative Mold")

        local resultModData = result:getModData()
        resultModData.damnOriginalItemType = damnOriginalItemType
        resultModData.damnOriginalDisplayName = damnOriginalDisplayName
    end
end

function DAMN.OnCreate.PourPasteInMold(craftRecipeData, character)
    local item = craftRecipeData:getAllConsumedItems():get(0)
    local modData = item:getModData()
    local damnOriginalItemType = modData.damnOriginalItemType
    local damnOriginalDisplayName = modData.damnOriginalDisplayName

    if not damnOriginalDisplayName then
        character:Say("What did i expect?")
        damnOriginalDisplayName = "Failed mess"
    end

    local result = craftRecipeData:getAllCreatedItems():get(0)
    result:setName(damnOriginalDisplayName .. " in Negative Filled Mold")

    local resultModData = result:getModData()
    resultModData.damnOriginalItemType = damnOriginalItemType
end


function DAMN.OnCreate.RemoveNewPartFromMold(craftRecipeData, character)
    local item = craftRecipeData:getAllConsumedItems():get(0)
    local modData = item:getModData()
    local damnOriginalItemType = modData.damnOriginalItemType

    local newItem = character:getInventory():AddItem(damnOriginalItemType)
    if not newItem then return end
    newItem:setCondition(ZombRandBetween(75,90))
end