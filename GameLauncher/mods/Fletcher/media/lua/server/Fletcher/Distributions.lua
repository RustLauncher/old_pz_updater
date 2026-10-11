--[[
    Fletcher: loot. The Compound Bow, the Crank Crossbow and Carbon Arrows / Aluminum Bolts can't
    be made, only found: where hunting gear is sold and kept. The Hip Quiver can be sewn too, and
    turns up in the same places. A Simple Bow (rare) and Fire-hardened Arrows turn up in hunters'
    homes, garages and outdoor-gear spots, so a player can stumble into archery; the Archery skill
    books (Vol. 1-5, rarer each volume) where vanilla keeps hunting and outdoors books, and the recipe
    magazines where vanilla's hunting magazines are.
    Every list is looked up by name and skipped (with a log line) if this
    build doesn't have it, since an insert into a missing list vanishes silently.
    Runs on OnPreDistributionMerge (tests/loot.lua checks every list exists and is used).
]]

require "Items/ProceduralDistributions"
require "Items/Distributions"
require "Fletcher/Core"
local F = Fletcher

F.LOOT = {
    ["Fletcher.CompoundBow"] = {
        { 2, "GunStoreRifles" },
        { 1, "GunStoreGuns" },
        { 1, "HuntingLockers" },
        { 0.5, "Hunter" },
        { 0.5, "PawnShopGuns" },
        { 0.3, "CampingStoreGear" },
    },
    ["Fletcher.CrankCrossbow"] = {
        { 1.5, "GunStoreRifles" },
        { 1, "GunStoreGuns" },
        { 1, "HuntingLockers" },
        { 0.4, "Hunter" },
        { 0.5, "PawnShopGuns" },
    },
    ["Fletcher.AluminumBoltBox"] = {
        { 3, "GunStoreAmmunition" },
        { 2, "GunStoreMagsAmmo" },
        { 1.5, "HuntingLockers" },
        { 1, "Hunter" },
        { 0.5, "PawnShopGuns" },
    },
    ["Fletcher.HipQuiver"] = {
        { 2, "HuntingLockers" },
        { 1.5, "Hunter" },
        { 1, "GunStoreGuns" },
        { 1, "CampingStoreGear" },
        { 0.5, "PawnShopGuns" },
    },
    ["Fletcher.BackQuiver"] = {             -- (0.7) rarer than the hip quiver
        { 1, "HuntingLockers" },
        { 0.8, "Hunter" },
        { 0.6, "CampingStoreGear" },
        { 0.4, "GunStoreGuns" },
        { 0.3, "PawnShopGuns" },
    },
    ["Fletcher.CarbonArrowBox"] = {
        { 4, "GunStoreAmmunition" },
        { 2, "GunStoreMagsAmmo" },
        { 2, "HuntingLockers" },
        { 1.5, "Hunter" },
        { 1, "CampingStoreGear" },
        { 0.5, "PawnShopGuns" },
    },
}

F.LOOT["Fletcher.SimpleBow"] = {
    { 2, "Hunter" },
    { 2, "Trapper" },
    { 1, "GarageFirearms" },
    { 1, "HuntingLockers" },
    { 0.5, "ClosetSportsEquipment" },
    { 0.5, "SurvivalGear" },
    { 0.5, "CampingStoreGear" },
    { 0.5, "PawnShopGuns" },
    { 0.02, "WardrobeRedneck" },
}
F.LOOT["Fletcher.WoodenArrow"] = {
    { 4, "Hunter" },
    { 4, "Trapper" },
    { 2, "GarageFirearms" },
    { 2, "HuntingLockers" },
    { 1, "ClosetSportsEquipment" },
    { 1, "SurvivalGear" },
}

-- Archery books: a weight per list for Vol. 1, scaled down for the later volumes (like vanilla's)
F.BOOK_LISTS = {
    { 6, "BookstoreOutdoors" }, { 6, "CampingStoreBooks" }, { 6, "GunStoreLiterature" },
    { 3, "Hunter" }, { 3, "Trapper" }, { 1, "HuntingLockers" }, { 1, "BookstoreBooks" },
    { 1, "LibraryBooks" }, { 1, "SurvivalGear" }, { 0.5, "CrateBooks" }, { 0.5, "PostOfficeBooks" },
    { 1, "SafehouseBookShelf" }, { 0.005, "LivingRoomShelfRedneck" },
}
F.BOOK_VOLUME_SCALE = { 1, 0.8, 0.6, 0.4, 0.2 }
for vol, k in ipairs(F.BOOK_VOLUME_SCALE) do
    local entries = {}
    for _, e in ipairs(F.BOOK_LISTS) do table.insert(entries, { e[1] * k, e[2] }) end
    F.LOOT["Fletcher.BookArchery" .. vol] = entries
end

-- Recipe magazines: where vanilla's hunting magazines turn up
F.MAG_LISTS = {
    { 6, "OutdoorSupplyMagazines" }, { 2, "GunStoreMagazineRack" }, { 2, "GunStoreLiterature" },
    { 2, "CampingStoreBooks" }, { 2, "BookstoreMisc" }, { 2, "Hunter" }, { 1, "GarageFirearms" },
    { 1, "SurvivalGear" }, { 1, "CrateMagazines" }, { 1, "MagazineRackMixed" }, { 1, "LibraryMagazines" },
    { 1, "PostOfficeMagazines" }, { 1, "CampingLockers" }, { 0.1, "LivingRoomShelfRedneck" },
    { 0.1, "LivingRoomSideTableRedneck" },
}
for n = 1, 4 do
    local entries = {}
    for _, e in ipairs(F.MAG_LISTS) do table.insert(entries, { e[1], e[2] }) end
    F.LOOT["Fletcher.ArcheryMag" .. n] = entries
end

-- What the "Bow and Crossbow Loot" sandbox option scales (0 = none found: craft everything)
F.BOW_LOOT = { ["Fletcher.SimpleBow"] = true, ["Fletcher.CompoundBow"] = true, ["Fletcher.CrankCrossbow"] = true,
               ["Fletcher.WoodenArrow"] = true, ["Fletcher.CarbonArrowBox"] = true, ["Fletcher.AluminumBoltBox"] = true }

--- The sandbox's loot multiplier for bows, crossbows and boxed arrows / bolts (default 1)
function F.bowLootMul()
    local sv = SandboxVars and SandboxVars.Fletcher
    local m = sv and tonumber(sv.BowLoot)
    return m and math.max(0, m) or 1
end

function F.insertLoot()
    local pd = ProceduralDistributions and ProceduralDistributions.list
    if not pd then
        F.log("ProceduralDistributions.list missing, no loot added")
        return
    end
    local mul = F.bowLootMul()
    F.lastBowLootMul = mul
    for fullType, entries in pairs(F.LOOT) do
        for _, e in ipairs(entries) do
            local list = pd[e[2]]
            local w = F.BOW_LOOT[fullType] and e[1] * mul or e[1]
            if w <= 0 then
                -- (switched off by the sandbox: not in the list at all)
            elseif list and list.items then
                -- name and weight go in together, or the flat list shifts
                table.insert(list.items, fullType)
                table.insert(list.items, w)
            else
                F.log("no loot list '" .. e[2] .. "' for " .. fullType .. ", skipped")
            end
        end
    end
end

-- 0.7: what zombies dressed for the woods carry (SuburbsDistributions.all.Outfit_*): arrows, bolts
-- and the odd Hip Quiver; their bows are on their backs (shared/Fletcher/ZombieGear.lua)
F.ZOMBIE_LOOT = {
    Outfit_Hunter = { { 6, "Fletcher.WoodenArrow" }, { 2, "Fletcher.BroadheadArrow" }, { 3, "Fletcher.WoodenBolt" },
                      { 1, "Fletcher.HipQuiver" }, { 0.5, "Fletcher.BackQuiver" } },
    Outfit_Ranger = { { 2, "Fletcher.WoodenArrow" } },
}
for _, outfit in ipairs({ "Outfit_Survivalist", "Outfit_Survivalist02", "Outfit_Survivalist03", "Outfit_Survivalist04",
                          "Outfit_Survivalist05" }) do
    F.ZOMBIE_LOOT[outfit] = { { 2, "Fletcher.WoodenArrow" }, { 1, "Fletcher.StoneArrow" } }
end

function F.insertZombieLoot()
    local all = SuburbsDistributions and SuburbsDistributions.all
    if not all then
        F.log("SuburbsDistributions.all missing, no zombie loot added")
        return
    end
    for outfit, entries in pairs(F.ZOMBIE_LOOT) do
        local list = all[outfit]
        if list and list.items then
            for _, e in ipairs(entries) do
                table.insert(list.items, e[2])
                table.insert(list.items, e[1])
            end
        else
            F.log("no zombie loot list '" .. outfit .. "', skipped")
        end
    end
end

Events.OnPreDistributionMerge.Add(F.insertLoot)
Events.OnPreDistributionMerge.Add(F.insertZombieLoot)
