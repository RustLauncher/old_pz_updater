-- FrikiClothesLoot.lua
-- Este archivo configura el loot para zombies que llevan el outfit "FrikiClothesOutfit".
-- Cuando un zombie con ese outfit muere, podrá soltar los siguientes juguetes:
--   - SpongeBobToy
--   - NemesisToy
--   - XenomorphToy
--   - ColossalTitanToy
--   - C3poToy
--

require "Items/FrikiLoot"

local outfitName = "FrikiClothesOutfit";
local modName = "FrikiClothes";     --Friki Toys
local lootChance = 5;    

LZFunc.LootZetaAddItemTable(outfitName, "FrikiToys.SpongeBobToy", lootChance, false, modName);
LZFunc.LootZetaAddItemTable(outfitName, "FrikiToys.NemesisToy", lootChance, false, modName);
LZFunc.LootZetaAddItemTable(outfitName, "FrikiToys.XenomorphToy", lootChance, false, modName);
LZFunc.LootZetaAddItemTable(outfitName, "FrikiToys.ColossalTitanToy", lootChance, false, modName);
LZFunc.LootZetaAddItemTable(outfitName, "FrikiToys.C3poToy", lootChance, false, modName);
LZFunc.LootZetaAddItemTable(outfitName, "FrikiNotes.Note1", 100, false, modName);
LZFunc.LootZetaAddItemTable(outfitName, "FrikiNotes.Note2", 30, false, modName);