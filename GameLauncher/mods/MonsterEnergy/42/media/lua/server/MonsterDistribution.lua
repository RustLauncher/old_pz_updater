require "Items/ProceduralDistributions"

local FRIDGES = {
  FridgeSoda = 2,
  FridgeBreakRoom = 2,
  FridgeVIPLounge = 2,
  FridgeGeneric = 1,
  FridgeOffice = 1,
}

local CANS = {
  MonsterCan = 2,
  MonsterUltraWhite = 1,
  MonsterUltraParadise = 1,
  MonsterUltraSunrise = 1,
  MonsterUltraViolet = 1,
  MonsterUltraRed = 1,
  MonsterUltraPeachyKeen = 1,
  MonsterPipelinePunch = 1,
  MonsterMangoLoco = 1,
  MonsterKhaotic = 1,
}

local function addMonsterToFridges()
  for listName, base in pairs(FRIDGES) do
    local list = ProceduralDistributions.list[listName]
    if list then
      for can, multiplier in pairs(CANS) do
        table.insert(list.items, can)
        table.insert(list.items, base * multiplier)
      end
    end
  end
end

Events.OnPreDistributionMerge.Add(addMonsterToFridges)
