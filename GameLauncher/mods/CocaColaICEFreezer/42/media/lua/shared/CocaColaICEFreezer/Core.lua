-- Native objects/containers are preserved. Only their registered tile changes.
CocaColaICEFreezer = CocaColaICEFreezer or {}
local M = CocaColaICEFreezer
M.dataKey = 'CocaColaICEFreezerRoll'
M.styleDataKey = 'CocaColaICEFreezerStyle'
M.tiles = {}
M.names = {}
M.distributionChoices = {1,5,10,15,25,35,50,75,90,100}
local original = {20, 21, 38, 39}
local offsets = {{0,1}, {0,0}, {0,0}, {1,0}}
for i = 1, 4 do
    local entry = {
        index = i-1,
        vanilla = 'appliances_refrigeration_01_' .. original[i],
        coke = 'CocaColaICEFreezer_01_' .. (i-1),
        dx = offsets[i][1], dy = offsets[i][2],
        facing = i <= 2 and 'E' or 'S',
    }
    M.tiles[entry.vanilla] = entry
    M.tiles[entry.coke] = entry
    M.names[#M.names+1] = entry.vanilla
    M.names[#M.names+1] = entry.coke
    for _,power in ipairs({'on','off'}) do
        for level=0,2 do
            local name='CocaColaICEFreezer_State_'..power..'_'..level..'_'..(i-1)
            M.tiles[name]=entry
            M.names[#M.names+1]=name
        end
    end
end

function M.isCokeName(name)
    local entry=name and M.tiles[name]
    return entry ~= nil and name ~= entry.vanilla
end

function M.normalizePercent(value)
    value = tonumber(value)
    if not value or value ~= value then return 100 end
    value = math.max(0, math.min(100, value))
    -- Chance remains a real percentage, never a menu row or a multiple of 25.
    return math.floor(value + 0.5)
end

function M.percent()
    local options = SandboxVars and SandboxVars.CocaColaICEFreezer
    return M.normalizePercent(options and options.Chance)
end

function M.readRoll(object)
    if not object or not object:hasModData() then return nil end
    local data = object:getModData().movableData
    local roll = type(data) == 'table' and data[M.dataKey]
    if type(roll) == 'number' and roll >= 0 and roll < 100 and roll == math.floor(roll) then
        return roll
    end
    return nil
end

function M.writeRoll(object, roll)
    local data = object:getModData()
    -- Do not overwrite another mod's unexpected data structure.
    if data.movableData ~= nil and type(data.movableData) ~= 'table' then return false end
    data.movableData = data.movableData or {}
    if data.movableData[M.dataKey] == roll then return false end
    data.movableData[M.dataKey] = roll
    return true
end

-- Transported and explicit custom freezers retain their selected appearance;
-- untouched map furniture still follows deliberate spawn-setting changes.
function M.readStyle(object)
    if not object or not object:hasModData() then return end
    local data=object:getModData().movableData
    local style=type(data)=='table' and data[M.styleDataKey]
    if style=='vanilla' or style=='coke' then return style end
end
function M.savedStyle(object)
    local style=M.readStyle(object)
    if style then return style end
    if M.readRoll(object)==nil and M.spriteStyle(object)=='coke' then return 'coke' end
end
function M.spriteStyle(object)
    local entry=M.entry(object)
    if entry then return M.isCokeName(object:getSprite():getName()) and 'coke' or 'vanilla' end
end
function M.writeStyle(object,style)
    if style~='vanilla' and style~='coke' then return false end
    local data=object:getModData()
    if data.movableData~=nil and type(data.movableData)~='table' then return false end
    data.movableData=data.movableData or {}
    if data.movableData[M.styleDataKey]==style then return false end
    data.movableData[M.styleDataKey]=style;return true
end

function M.entry(object)
    local sprite = object and object:getSprite()
    return sprite and M.tiles[sprite:getName()]
end

function M.anchor(object, entry)
    local square = object:getSquare()
    return square:getX()-entry.dx, square:getY()-entry.dy, square:getZ()
end

-- The same world seed + anchor always gives both halves the same roll, even
-- when the other half is in an unloaded chunk. Saved movableData takes priority.
function M.rollAt(x, y, z, seed)
    local text = tostring(seed) .. ':' .. x .. ':' .. y .. ':' .. z
    local hash = 7
    for i = 1, #text do hash = (hash * 131 + string.byte(text,i)) % 2147483647 end
    hash = (hash * 48271) % 2147483647
    return hash % 100
end
