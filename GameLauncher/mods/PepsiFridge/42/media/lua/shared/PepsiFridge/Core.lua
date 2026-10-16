PepsiFridge = PepsiFridge or {}
local M = PepsiFridge
M.dataKey = 'PepsiFridgeRoll'
M.styleDataKey = 'PepsiFridgeStyle'
M.wornDataKey = 'PepsiFridgeWornRoll'
M.legacyCleanKey = 'PepsiFridgeLegacyClean'
M.tiles, M.names = {}, {}
for i, original in ipairs({40,41,42,43}) do
    local entry = {vanilla='appliances_refrigeration_01_'..original,
        pepsi='PepsiFridge_01_'..(i-1),
        worn='PepsiFridgeWorn_01_'..(i-1), direction=original}
    M.tiles[entry.vanilla], M.tiles[entry.pepsi], M.tiles[entry.worn] = entry, entry, entry
    M.names[#M.names+1], M.names[#M.names+2], M.names[#M.names+3] =
        entry.vanilla, entry.pepsi, entry.worn
end

M.distributionChoices = {1,5,10,15,25,35,50,75,90,100}
function M.normalizePercent(value, fallback)
    value = tonumber(value)
    if not value or value ~= value then return fallback or 100 end
    value = math.max(0, math.min(100, value))
    -- Chance remains a real percentage, never a menu row or a multiple of 25.
    return math.floor(value + 0.5)
end

function M.percent()
    local options = SandboxVars and SandboxVars.PepsiFridge
    return M.normalizePercent(options and options.Chance)
end

function M.wornPercent()
    local options = SandboxVars and SandboxVars.PepsiFridge
    return M.normalizePercent(options and options.WornChance, 25)
end


function M.entry(object)
    local sprite = object and object:getSprite()
    return sprite and M.tiles[sprite:getName()]
end

function M.isPepsi(object)
    local entry = M.entry(object)
    if not entry then return false end
    local name=object:getSprite():getName()
    return name==entry.pepsi or name==entry.worn
end

function M.isWorn(object)
    local entry=M.entry(object)
    return entry and object:getSprite():getName()==entry.worn or false
end

local function readRoll(object, key)
    if not object or not object:hasModData() then return nil end
    local data = object:getModData().movableData
    local roll = type(data)=='table' and data[key]
    if type(roll)=='number' and roll>=0 and roll<100 and roll==math.floor(roll) then return roll end
end

function M.readRoll(object) return readRoll(object,M.dataKey) end
function M.readWornRoll(object) return readRoll(object,M.wornDataKey) end
function M.isLegacyClean(object)
    if not object or not object:hasModData() then return false end
    local data=object:getModData().movableData
    return type(data)=='table' and data[M.legacyCleanKey]==true or false
end

local function writeRoll(object, key, roll)
    local data = object:getModData()
    if data.movableData~=nil and type(data.movableData)~='table' then return false end
    data.movableData = data.movableData or {}
    if data.movableData[key]==roll then return false end
    data.movableData[key]=roll
    return true
end

function M.writeRoll(object, roll) return writeRoll(object,M.dataKey,roll) end
function M.writeWornRoll(object, roll) return writeRoll(object,M.wornDataKey,roll) end
function M.markLegacyClean(object) return writeRoll(object,M.legacyCleanKey,true) end

-- Preserve transported and explicitly placed clean/worn appearances. Normal
-- map furniture retains its roll and follows deliberate spawn-setting changes.
function M.readStyle(object)
    if not object or not object:hasModData() then return end
    local data=object:getModData().movableData
    local style=type(data)=='table' and data[M.styleDataKey]
    if style=='vanilla' or style=='pepsi' or style=='worn' then return style end
end
function M.savedStyle(object)
    local style=M.readStyle(object)
    if style then return style end
    if M.readRoll(object)==nil then
        if M.isWorn(object) then return 'worn' end
        if M.isPepsi(object) then return 'pepsi' end
    end
end
function M.spriteStyle(object)
    if not M.entry(object) then return end
    if M.isWorn(object) then return 'worn' end
    return M.isPepsi(object) and 'pepsi' or 'vanilla'
end
function M.writeStyle(object,style)
    if style~='vanilla' and style~='pepsi' and style~='worn' then return false end
    return writeRoll(object,M.styleDataKey,style)
end

-- Saved movableData is carried by the game's single-tile pickup/place code.
-- A location hash supplies a stable initial choice, including reloaded chunks.
function M.rollAt(x,y,z,seed)
    local text = tostring(seed)..':'..x..':'..y..':'..z
    local hash = 7
    for i=1,#text do hash=(hash*131+string.byte(text,i))%2147483647 end
    return ((hash*48271)%2147483647)%100
end

-- A separate hash namespace keeps wear independent of the original spawn roll.
function M.wornRollAt(x,y,z,seed)
    return M.rollAt(x,y,z,tostring(seed)..':worn')
end

-- Nick enumerates vanilla sprites only. Extend its guarded property fix to our
-- custom equivalents, on both server and client, without requiring the mod.
function M.prepareSprite(sprite)
    if sprite and TurnOffFridges and TurnOffFridges.clearFridgeProperty then
        TurnOffFridges.clearFridgeProperty(sprite:getProperties())
    end
end
local function prepareSprites()
    for _,name in ipairs(M.names) do
        local entry=M.tiles[name]
        if name==entry.pepsi or name==entry.worn then M.prepareSprite(getSprite(name)) end
    end
end
Events.OnGameStart.Add(prepareSprites)
Events.OnServerStarted.Add(prepareSprites)
