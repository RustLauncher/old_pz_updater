 require 'Definitions/HairOutfitDefinitions' 

local excludedHairs = {
"M_BabySpike",
"M_Bobby",
"M_Buzz",
"M_Flowing",
"M_Heartthrob",
"M_LibertySpike",
"M_Parted",
"M_PrettyBoy",
"M_Short",
"F_Banshee",
"F_Frankie",
"F_Lynn",




}

for k,v in pairs(excludedHairs) do
	local cat = {name = v, onlyFor = "ZombiesDontLike"};
	table.insert(HairOutfitDefinitions.haircutDefinition, cat);
end