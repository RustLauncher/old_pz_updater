UsefulPallets = UsefulPallets or {}
local WP = UsefulPallets
WP.VERSION = 1
WP.TRANSFER_TIME = 20
WP.materials = {
    { item = "Base.GoldBar", key = "gold" },
    { item = "Base.SilverBar", key = "silver" },
    { item = "Base.CopperIngot", key = "copper" },
    { item = "Base.IronIngot", key = "iron" },
    { item = "Base.SteelIngot", key = "steel" },
    { item = "Base.BrassIngot", key = "brass" },
    { item = "Base.SmallGoldBar", key = "small-gold", small = true },
    { item = "Base.SmallSilverBar", key = "small-silver", small = true },
    { item = "Base.ClayBrick", key = "bricks", bricks = true },
    { item = "Base.Plank", key = "planks",
      capacities = {construction = 48, military = 64, stacked = 128},
      sprites = {construction = "usefulpallets_01_35", military = "usefulpallets_01_36", stacked = "usefulpallets_01_37"},
      emptyTopSprite = "usefulpallets_01_38" },
    { item = "Base.SheetMetal", key = "sheet-steel",
      capacities = {construction = 48, military = 69, stacked = 138},
      sprites = {construction = "usefulpallets_01_39", military = "usefulpallets_01_40", stacked = "usefulpallets_01_41"},
      emptyTopSprite = "usefulpallets_01_42" },
    { item = "Base.SmallSheetMetal", key = "sheet-small-steel",
      capacities = {construction = 512, military = 720, stacked = 1440},
      sprites = {construction = "usefulpallets_01_43", military = "usefulpallets_01_44", stacked = "usefulpallets_01_45"},
      emptyTopSprite = "usefulpallets_01_46" },
    { item = "Base.CopperSheet", key = "sheet-copper",
      capacities = {construction = 70, military = 98, stacked = 196},
      sprites = {construction = "usefulpallets_01_47", military = "usefulpallets_01_48", stacked = "usefulpallets_01_49"},
      emptyTopSprite = "usefulpallets_01_50" },
    { item = "Base.SmallCopperSheet", key = "sheet-small-copper",
      capacities = {construction = 690, military = 980, stacked = 1960},
      sprites = {construction = "usefulpallets_01_51", military = "usefulpallets_01_52", stacked = "usefulpallets_01_53"},
      emptyTopSprite = "usefulpallets_01_54" },
    { item = "Base.GoldSheet", key = "sheet-gold",
      capacities = {construction = 512, military = 720, stacked = 1440},
      sprites = {construction = "usefulpallets_01_55", military = "usefulpallets_01_56", stacked = "usefulpallets_01_57"},
      emptyTopSprite = "usefulpallets_01_58" },
    { item = "Base.SilverSheet", key = "sheet-silver",
      capacities = {construction = 512, military = 720, stacked = 1440},
      sprites = {construction = "usefulpallets_01_59", military = "usefulpallets_01_60", stacked = "usefulpallets_01_61"},
      emptyTopSprite = "usefulpallets_01_62" },
    { item = "Base.StoneBlock", key = "stone-block",
      capacities = {construction = 84, military = 126, stacked = 252},
      sprites = {construction = "usefulpallets_01_63", military = "usefulpallets_01_64", stacked = "usefulpallets_01_65"},
      emptyTopSprite = "usefulpallets_01_66" },
    { item = "Base.ClayTile", key = "clay-tile",
      capacities = {construction = 44, military = 64, stacked = 128},
      sprites = {construction = "usefulpallets_01_67", military = "usefulpallets_01_68", stacked = "usefulpallets_01_69"},
      emptyTopSprite = "usefulpallets_01_70" },
    { item = "Base.MetalPipe", key = "iron-pipe",
      capacities = {construction = 54, military = 90, stacked = 180},
      sprites = {construction = "usefulpallets_01_71", military = "usefulpallets_01_72", stacked = "usefulpallets_01_73"},
      emptyTopSprite = "usefulpallets_01_74" },
    { item = "Base.MetalBar", key = "steel-rod",
      capacities = {construction = 114, military = 152, stacked = 304},
      sprites = {construction = "usefulpallets_01_75", military = "usefulpallets_01_76", stacked = "usefulpallets_01_77"},
      emptyTopSprite = "usefulpallets_01_78" },
    { item = "Base.SteelBar", key = "steel-bar",
      capacities = {construction = 126, military = 189, stacked = 378},
      sprites = {construction = "usefulpallets_01_79", military = "usefulpallets_01_80", stacked = "usefulpallets_01_81"},
      emptyTopSprite = "usefulpallets_01_82" },
    { item = "Base.IronBar", key = "iron-bar",
      capacities = {construction = 126, military = 189, stacked = 378},
      sprites = {construction = "usefulpallets_01_83", military = "usefulpallets_01_84", stacked = "usefulpallets_01_85"},
      emptyTopSprite = "usefulpallets_01_86" },
    { item = "Base.Pipe", key = "plastic-pipe",
      capacities = {construction = 33, military = 44, stacked = 88},
      sprites = {construction = "usefulpallets_01_87", military = "usefulpallets_01_88", stacked = "usefulpallets_01_89"},
      emptyTopSprite = "usefulpallets_01_90" },
    { item = "Base.IronBlock", key = "iron-block",
      capacities = {construction = 168, military = 280, stacked = 560},
      sprites = {construction = "usefulpallets_01_91", military = "usefulpallets_01_92", stacked = "usefulpallets_01_93"},
      emptyTopSprite = "usefulpallets_01_94" },
    { item = "Base.SteelBlock", key = "steel-block",
      capacities = {construction = 168, military = 280, stacked = 560},
      sprites = {construction = "usefulpallets_01_95", military = "usefulpallets_01_96", stacked = "usefulpallets_01_97"},
      emptyTopSprite = "usefulpallets_01_98" },
    { item = "Base.ClayShingle", key = "clay-shingle",
      capacities = {construction = 12, military = 20, stacked = 40},
      sprites = {construction = "usefulpallets_01_99", military = "usefulpallets_01_100", stacked = "usefulpallets_01_101"},
      emptyTopSprite = "usefulpallets_01_102" },
    { item = "Base.LeadPipe", key = "lead-pipe",
      capacities = {construction = 54, military = 90, stacked = 180},
      sprites = {construction = "usefulpallets_01_103", military = "usefulpallets_01_104", stacked = "usefulpallets_01_105"},
      emptyTopSprite = "usefulpallets_01_106" },
    { item = "Base.Log", key = "logs",
      capacities = {construction = 8, military = 16, stacked = 32},
      sprites = {construction = "usefulpallets_01_107", military = "usefulpallets_01_108", stacked = "usefulpallets_01_109"},
      emptyTopSprite = "usefulpallets_01_110" },
    { item = "Base.Firewood", key = "firewood",
      capacities = {construction = 112, military = 140, stacked = 280},
      sprites = {construction = "usefulpallets_01_111", military = "usefulpallets_01_112", stacked = "usefulpallets_01_113"},
      emptyTopSprite = "usefulpallets_01_114" },
    { item = "Base.WoodenStick2", key = "wooden-stick",
      capacities = {construction = 95, military = 133, stacked = 266},
      sprites = {construction = "usefulpallets_01_115", military = "usefulpallets_01_116", stacked = "usefulpallets_01_117"},
      emptyTopSprite = "usefulpallets_01_118" },
    { item = "Base.LongStick", key = "long-stick",
      capacities = {construction = 168, military = 231, stacked = 462},
      sprites = {construction = "usefulpallets_01_119", military = "usefulpallets_01_120", stacked = "usefulpallets_01_121"},
      emptyTopSprite = "usefulpallets_01_122" },
    { item = "Base.TreeBranch2", key = "tree-branch",
      capacities = {construction = 39, military = 65, stacked = 130},
      sprites = {construction = "usefulpallets_01_123", military = "usefulpallets_01_124", stacked = "usefulpallets_01_125"},
      emptyTopSprite = "usefulpallets_01_126" },
    { item = "Base.LargeBranch", key = "large-branch",
      capacities = {construction = 8, military = 16, stacked = 32},
      sprites = {construction = "usefulpallets_01_127", military = "usefulpallets_01_128", stacked = "usefulpallets_01_129"},
      emptyTopSprite = "usefulpallets_01_130" },
    { item = "Base.IronBarHalf", key = "iron-bar-half",
      capacities = {construction = 240, military = 360, stacked = 720},
      sprites = {construction = "usefulpallets_01_131", military = "usefulpallets_01_132", stacked = "usefulpallets_01_133"},
      emptyTopSprite = "usefulpallets_01_134" },
    { item = "Base.IronBarQuarter", key = "iron-bar-quarter",
      capacities = {construction = 1127, military = 1610, stacked = 3220},
      sprites = {construction = "usefulpallets_01_135", military = "usefulpallets_01_136", stacked = "usefulpallets_01_137"},
      emptyTopSprite = "usefulpallets_01_138" },
    { item = "Base.SteelBarHalf", key = "steel-bar-half",
      capacities = {construction = 240, military = 360, stacked = 720},
      sprites = {construction = "usefulpallets_01_139", military = "usefulpallets_01_140", stacked = "usefulpallets_01_141"},
      emptyTopSprite = "usefulpallets_01_142" },
    { item = "Base.SteelBarQuarter", key = "steel-bar-quarter",
      capacities = {construction = 1127, military = 1610, stacked = 3220},
      sprites = {construction = "usefulpallets_01_143", military = "usefulpallets_01_144", stacked = "usefulpallets_01_145"},
      emptyTopSprite = "usefulpallets_01_146" },
    { item = "Base.SteelRodHalf", key = "steel-rod-half",
      capacities = {construction = 228, military = 304, stacked = 608},
      sprites = {construction = "usefulpallets_01_147", military = "usefulpallets_01_148", stacked = "usefulpallets_01_149"},
      emptyTopSprite = "usefulpallets_01_150" },
    { item = "Base.SteelRodQuarter", key = "steel-rod-quarter",
      capacities = {construction = 770, military = 1100, stacked = 2200},
      sprites = {construction = "usefulpallets_01_151", military = "usefulpallets_01_152", stacked = "usefulpallets_01_153"},
      emptyTopSprite = "usefulpallets_01_154" },
}
WP.byItem = {}
WP.loadedSprites = {}
for i, material in ipairs(WP.materials) do
    WP.byItem[material.item] = material
    if material.bricks then
        -- Append brick variants after the original 24 sprites to preserve save IDs.
        material.sprites = {
            construction = "construction_01_4",
            military = "usefulpallets_01_24",
            stacked = "usefulpallets_01_25",
        }
        WP.loadedSprites[material.sprites.military] = { kind = "military", item = material.item }
        WP.loadedSprites[material.sprites.stacked] = { kind = "stacked", item = material.item }
    elseif material.sprites then
        -- Explicit appended IDs keep all existing save sprite registrations stable.
        for kind, sprite in pairs(material.sprites) do
            WP.loadedSprites[sprite] = {kind = kind, item = material.item}
        end
    else
        material.sprites = {}
        for j, kind in ipairs({ "construction", "military", "stacked" }) do
            local sprite = "usefulpallets_01_" .. ((i - 1) * 3 + j - 1)
            material.sprites[kind] = sprite
            WP.loadedSprites[sprite] = { kind = kind, item = material.item }
        end
    end
end
WP.vanilla = {
    construction_01_5 = { kind = "construction", count = 0 },
    construction_01_4 = { kind = "construction", item = "Base.ClayBrick", count = 20 },
    location_military_knox_01_0 = { kind = "military", count = 0 },
    location_military_knox_01_1 = { kind = "military", item = "Base.GoldBar", count = 30 },
    location_military_knox_01_2 = { kind = "stacked", item = "Base.GoldBar", count = 60, bottomCount = 45, vanillaIntact = true },
}
for i, material in ipairs(WP.materials) do
    material.emptyTopSprite = material.emptyTopSprite or "usefulpallets_01_" .. (25 + i)
    WP.loadedSprites[material.emptyTopSprite] = {kind = "stacked", item = material.item}
end
WP.emptySprites = { construction = "construction_01_5", military = "location_military_knox_01_0" }

function WP.defaultCapacity(kind, item)
    local material = WP.byItem[item]
    if not material then return 0 end
    if material.capacities then return material.capacities[kind] or 0 end
    local base = ({ construction = 32, military = 45, stacked = 90 })[kind] or 0
    return base * (material.small and 8 or 1)
end

function WP.capacity(kind, item)
    if not WP.byItem[item] then return 0 end
    if kind == "stacked" then return WP.capacity("military", item) * 2 end
    if kind ~= "construction" and kind ~= "military" then return 0 end
    local options = SandboxVars and SandboxVars.UsefulPallets
    local key = string.sub(item, 6) .. (kind == "construction" and "ConstructionCapacity" or "MilitaryCapacity")
    local value = options and options[key]
    if type(value) == "number" and value >= 1 and value <= 10000 and value == math.floor(value) then return value end
    return WP.defaultCapacity(kind, item)
end

-- Old mod-created stacks omitted bottomCount because the bottom was always full.
function WP.bottomCount(state)
    return state.kind == "stacked" and (state.bottomCount or WP.defaultCapacity("military", state.item)) or 0
end

function WP.totalCapacity(state, item)
    if state.kind == "stacked" then return WP.bottomCount(state) + WP.capacity("military", item) end
    return WP.capacity(state.kind, item)
end

function WP.spriteFor(kind, item, count, bottomCount)
    if count == 0 then return WP.emptySprites[kind] end
    local material = WP.byItem[item]
    if not material or WP.capacity(kind, item) == 0 then return nil end
    if kind == "stacked" and count == (bottomCount or WP.capacity("military", item)) then return material.emptyTopSprite end
    return material.sprites[kind]
end

-- Reads do not initialize mod data: simply opening the menu must not mutate the world.
function WP.state(pallet)
    if not pallet or not pallet:getSprite() then return nil end
    local sprite = pallet:getSprite():getName()
    local known = WP.vanilla[sprite] or WP.loadedSprites[sprite]
    if not known then return nil end
    local saved = pallet:getModData().UsefulPallets
    if saved then
        if type(saved) ~= "table" then return nil end
        if saved.version ~= WP.VERSION or saved.kind ~= known.kind then return nil end
        if type(saved.count) ~= "number" or saved.count < 0 or saved.count > 20000 or saved.count ~= math.floor(saved.count) then return nil end
        -- Lowering sandbox limits must never invalidate or delete existing stock.
        if saved.count > 0 and not WP.byItem[saved.item] then return nil end
        if saved.count == 0 and saved.item ~= nil then return nil end
        if saved.units and (type(saved.units) ~= "table" or #saved.units ~= saved.count) then return nil end
        if saved.stackRevision ~= nil and (type(saved.stackRevision) ~= "number" or saved.stackRevision < 0
            or saved.stackRevision ~= math.floor(saved.stackRevision) or saved.stackRevision == math.huge) then return nil end
        if saved.kind == "stacked" then
            local top = saved.topPallet
            local bottom = WP.bottomCount(saved)
            if type(bottom) ~= "number" or bottom < 1 or bottom > 10000 or bottom ~= math.floor(bottom) then return nil end
            if saved.count < bottom then return nil end
            if type(top) ~= "table" or type(top.itemType) ~= "string" or top.sprite ~= WP.emptySprites.military then return nil end
            if type(top.weight) ~= "number" or top.weight < 0 or top.weight ~= top.weight or top.weight == math.huge then return nil end
        elseif saved.topPallet ~= nil or saved.bottomCount ~= nil then return nil end
        if saved.vanillaIntact ~= nil then
            if saved.vanillaIntact ~= true or sprite ~= "location_military_knox_01_2"
                or saved.item ~= "Base.GoldBar" or (saved.bottomCount ~= 30 and saved.bottomCount ~= 45) or saved.count < 60 then return nil end
        end
        return { version = WP.VERSION, kind = saved.kind, item = saved.item, count = saved.count, units = saved.units, topPallet = saved.topPallet, stackRevision = saved.stackRevision, bottomCount = saved.kind == "stacked" and WP.bottomCount(saved) or nil, vanillaIntact = saved.vanillaIntact }
    end
    local initial = WP.vanilla[sprite]
    if not initial then return nil end -- Never invent contents for an orphaned custom sprite.
    local state = copyTable(initial)
    state.version = WP.VERSION
    if state.kind == "stacked" then
        -- A map stack has no consumed inventory pallet to remember. Read its
        -- recoverable empty top from the native movable definition, never guess weight.
        local item = instanceItem("Moveables." .. WP.emptySprites.military)
        if not item or not item:ReadFromWorldSprite(WP.emptySprites.military) then return nil end
        state.topPallet = WP.captureItem(item)
        state.topPallet.itemType = "Moveables." .. WP.emptySprites.military
        state.topPallet.sprite = WP.emptySprites.military
        state.topPallet.weight = item:getActualWeight()
    end
    return state
end

function WP.canTransfer(state, itemType, direction)
    if not state or not WP.byItem[itemType] then return false end
    if direction == "add" then
        return (not state.item or state.item == itemType) and state.count < WP.totalCapacity(state, itemType)
    elseif direction == "take" then
        local floor = WP.bottomCount(state)
        return state.item == itemType and state.count > floor
    end
    return false
end

-- Transfers always target the upper pallet while attached. The stored count and
-- unit list remain total/bottom-first, preserving old single-pallet saves.
function WP.activeState(state)
    if state.kind ~= "stacked" then return state end
    return {kind = "military", item = state.item, count = state.count - WP.bottomCount(state)}
end

function WP.canAttach(state)
    return state and state.kind == "military" and state.item ~= nil
        and state.count >= WP.capacity("military", state.item)
end

function WP.canDetach(state)
    return state and state.kind == "stacked" and state.topPallet ~= nil
        and state.count == WP.bottomCount(state)
end

function WP.isMilitaryPalletItem(item)
    return item and instanceof(item, "Moveable") and item:getWorldSprite() == WP.emptySprites.military
end

function WP.carriedPallets(character)
    local result = {}
    local items = character:getInventory():getAllEvalRecurse(WP.isMilitaryPalletItem)
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if not item:isFavorite() and not character:isEquipped(item) then result[#result + 1] = item end
    end
    return result
end

function WP.captureItem(item)
    return {condition = item:getCondition(), customName = item:isCustomName(),
        name = item:isCustomName() and item:getName() or nil,
        modData = item:hasModData() and copyTable(item:getModData()) or nil}
end

function WP.restoreItem(item, record)
    if record.condition then item:setCondition(record.condition) end
    if record.customName then item:setName(record.name); item:setCustomName(true) end
    if record.modData then item:copyModData(record.modData) end
end
