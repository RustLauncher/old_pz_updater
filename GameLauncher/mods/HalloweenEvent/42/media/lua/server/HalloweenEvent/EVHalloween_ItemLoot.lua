require "HalloweenEvent/EVHalloween_Items"
require "HalloweenEvent/EVHalloween_ItemFunctions"
local HWE,Items=HalloweenEvent,HalloweenEvent.Items
if Items.Loot then return Items.Loot end
local Loot={};Items.Loot=Loot
function Loot.choose(pool)
    local allowed={}
    local seen={}
    for _,ft in ipairs(pool or {}) do
        ft=Items.typeAliases[ft] or ft
        if not seen[ft] and HWE.CostumeFilter.isItemAllowed(ft) then
            allowed[#allowed+1]=ft;seen[ft]=true
        end
    end
    if #allowed==0 then return nil end
    return allowed[ZombRand(1,#allowed+1)]
end
local storageRooms={garage=true,garagestorage=true,storageunit=true,storageroom=true,bedroom=true,closet=true,laundry=true}
local storageTypes={crate=true,metal_shelves=true,shelves=true,counter=true,locker=true}
function Loot.eligible(room,kind,container)
    if not container then return false end
    local parent=container:getParent()
    if not parent or not instanceof(parent,"IsoObject") or instanceof(parent,"IsoDeadBody") then return false end
    -- Player built crates must not generate loot when used as empty storage.
    local md=parent:getModData();if md and (md.player or md.playerMade) then return false end
    local r=tostring(room or ""):lower();local k=tostring(kind or ""):lower()
    return (k=="wardrobe" and (r=="bedroom" or r=="closet" or r=="all"))
        or (storageRooms[r] and storageTypes[k])
end
function Loot.onFill(room,kind,container)
    if isClient() and not isServer() then return end
    if not Loot.eligible(room,kind,container) then return end
    local cfg=HWE.readSandbox()
    local active=HWE.Server and HWE.Server.active
    if active==nil then active=cfg.EnableEvent and HWE.isCalendarActive(cfg) end
    if not cfg.EnableEvent or not active or cfg.MaxDecorationsPerContainer<=0 then return end
    local parent=container:getParent();local md=parent:getModData()
    -- A persistent first-fill attempt prevents opening/reloading the same storage
    -- from rerolling. Loot respawn doesn't turn this container into an item farm.
    md.EVHStorageRollItems8=md.EVHStorageRollItems8 or {}
    if md.EVHStorageRollItems8[kind] then return end
    md.EVHStorageRollItems8[kind]=true
    local list=container:getItems();local current=0
    for i=0,list:size()-1 do if Items.byType[list:get(i):getFullType()] then current=current+1 end end
    if current>=cfg.MaxDecorationsPerContainer or not HWE.rollPercent(cfg.WorldDecorationChancePercent) then return end
    local ft=Loot.choose(Items.rewards);if not ft then return end
    local item=instanceItem(ft);if not item then HWE.log("ITEMS STORAGE_CREATE_FAILED type="..ft);return end
    if container:getCapacityWeight()+item:getUnequippedWeight()>container:getCapacity() then return end
    Items.Functions.init(item);container:AddItem(item)
    if isServer() then sendAddItemToContainer(container,item) end
    HWE.log("ITEMS STORAGE_DROP room="..tostring(room).." container="..tostring(kind).." type="..ft)
end
if Events.OnFillContainer then Events.OnFillContainer.Add(Loot.onFill) end
return Loot
