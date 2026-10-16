MonsterBlackFridge = MonsterBlackFridge or {}
local M = MonsterBlackFridge
M.dataKey = 'MonsterBlackFridgeRoll'
M.styleDataKey = 'MonsterBlackFridgeStyle'
M.tiles, M.names = {}, {}
for i, original in ipairs({22,23,36,37}) do
    local entry = {vanilla='appliances_refrigeration_01_'..original,
        monster='MonsterBlackFridge_01_'..(i-1), direction=original}
    M.tiles[entry.vanilla], M.tiles[entry.monster] = entry, entry
    M.names[#M.names+1], M.names[#M.names+2] = entry.vanilla, entry.monster
end

-- Keep the original saved IDs: 1=0%, 2=25%, 3=50%, 4=75%, 5=100%.
-- Append IDs for new values; UI order must not reinterpret old worlds.
M.distributionPercents = {0,25,50,75,100,1,5,10,15,35,90}
M.distributionChoices = {6,7,8,9,2,10,3,4,11,5}
function M.percent()
    local options = SandboxVars and SandboxVars.MonsterBlackFridge
    local selection = tonumber(options and options.Distribution)
    if not selection or selection ~= math.floor(selection) then return 100 end
    return M.distributionPercents[selection] or 100
end

function M.entry(object)
    local sprite = object and object:getSprite()
    return sprite and M.tiles[sprite:getName()]
end

function M.isMonster(object)
    local entry = M.entry(object)
    return entry and object:getSprite():getName() == entry.monster or false
end

function M.readRoll(object)
    if not object or not object:hasModData() then return nil end
    local data = object:getModData().movableData
    local roll = type(data)=='table' and data[M.dataKey]
    if type(roll)=='number' and roll>=0 and roll<100 and roll==math.floor(roll) then return roll end
end

function M.writeRoll(object, roll)
    local data = object:getModData()
    if data.movableData~=nil and type(data.movableData)~='table' then return false end
    data.movableData = data.movableData or {}
    if data.movableData[M.dataKey]==roll then return false end
    data.movableData[M.dataKey]=roll
    return true
end

-- Transported furniture carries an explicit identity. Untouched map furniture
-- retains its saved roll so deliberate spawn-setting changes still apply.
function M.readStyle(object)
    if not object or not object:hasModData() then return end
    local data=object:getModData().movableData
    local style=type(data)=='table' and data[M.styleDataKey]
    if style=='vanilla' or style=='monster' then return style end
end
function M.savedStyle(object)
    local style=M.readStyle(object)
    if style then return style end
    if M.readRoll(object)==nil and M.isMonster(object) then return 'monster' end
end
function M.spriteStyle(object)
    local entry=M.entry(object)
    if entry then return M.isMonster(object) and 'monster' or 'vanilla' end
end
function M.writeStyle(object,style)
    if style~='vanilla' and style~='monster' then return false end
    local data=object:getModData()
    if data.movableData~=nil and type(data.movableData)~='table' then return false end
    data.movableData=data.movableData or {}
    if data.movableData[M.styleDataKey]==style then return false end
    data.movableData[M.styleDataKey]=style;return true
end

-- Saved movableData is carried by the game's single-tile pickup/place code.
-- A location hash supplies a stable initial choice, including reloaded chunks.
function M.rollAt(x,y,z,seed)
    local text = tostring(seed)..':'..x..':'..y..':'..z
    local hash = 7
    for i=1,#text do hash=(hash*131+string.byte(text,i))%2147483647 end
    return ((hash*48271)%2147483647)%100
end

-- Nick enumerates vanilla sprites only. Extend its guarded property fix to our
-- four new equivalents, on both server and client, without requiring the mod.
function M.prepareSprite(sprite)
    if sprite and TurnOffFridges and TurnOffFridges.clearFridgeProperty then
        TurnOffFridges.clearFridgeProperty(sprite:getProperties())
    end
end
local function prepareSprites()
    for _,name in ipairs(M.names) do
        local entry=M.tiles[name]
        if name==entry.monster then M.prepareSprite(getSprite(name)) end
    end
end
Events.OnGameStart.Add(prepareSprites)
Events.OnServerStarted.Add(prepareSprites)
