DrPepperFridge = DrPepperFridge or {}
local M=DrPepperFridge
M.dataKey='DrPepperFridgeRoll'
M.wornDataKey='DrPepperFridgeWornRoll'
M.styleDataKey='DrPepperFridgeStyle'
M.tiles,M.names={},{}
local definitions={{16,'E',0,1},{17,'E',0,0},{18,'S',0,0},{19,'S',1,0},
    {44,'W',0,1},{45,'W',0,0},{46,'N',0,0},{47,'N',1,0}}
for i,d in ipairs(definitions) do
    local entry={vanilla='appliances_refrigeration_01_'..d[1],
        clean='DrPepperFridge_01_'..(i-1),worn='DrPepperFridgeWorn_01_'..(i-1),
        direction=d[1],facing=d[2],gx=d[3],gy=d[4],front=i<=4}
    for _,name in ipairs({entry.vanilla,entry.clean,entry.worn}) do
        M.tiles[name]=entry;M.names[#M.names+1]=name
    end
end
function M.option(name,fallback)
    local options=SandboxVars and SandboxVars.DrPepperFridge
    local value=options and options[name]
    if value==nil then return fallback end
    return value
end
function M.normalizePercent(value,fallback)
    value=tonumber(value)
    if not value or value~=value then return fallback or 100 end
    return math.floor(math.max(0,math.min(100,value))+.5)
end
function M.percent() return M.normalizePercent(M.option('Chance',100),100) end
function M.wornPercent() return M.normalizePercent(M.option('WornChance',25),25) end
function M.fillThresholds()
    local values={M.normalizePercent(M.option('FillLevel1',10),10),
        M.normalizePercent(M.option('FillLevel2',20),20),M.normalizePercent(M.option('FillLevel3',30),30)}
    table.sort(values)
    return values[1]/100,values[2]/100,values[3]/100
end
function M.entry(object)
    local sprite=object and object:getSprite()
    return sprite and M.tiles[sprite:getName()]
end
function M.isDrPepper(object)
    local e=M.entry(object)
    return e and object:getSprite():getName()~=e.vanilla or false
end
function M.isWorn(object)
    local e=M.entry(object)
    return e and object:getSprite():getName()==e.worn or false
end
function M.anchor(object)
    local e=M.entry(object);local sq=object and object:getSquare()
    if not e or not sq then return end
    return sq:getX()-e.gx,sq:getY()-e.gy,sq:getZ(),e.facing
end
-- Match both parts by native grid position, including a pair whose style is
-- temporarily mixed while a network update arrives. Adjacent fridges stay separate.
function M.parts(object)
    local x,y,z,facing=M.anchor(object)
    if not x then return {} end
    local cell=object:getSquare():getCell();local parts={}
    for _,offset in ipairs((facing=='E' or facing=='W') and {{0,0},{0,1}} or {{0,0},{1,0}}) do
        local sq=cell and cell:getGridSquare(x+offset[1],y+offset[2],z)
        if sq then
            local objects=sq:getObjects()
            for i=0,objects:size()-1 do
                local candidate=objects:get(i);local e=M.entry(candidate)
                if e and e.facing==facing and e.gx==offset[1] and e.gy==offset[2] then
                    parts[#parts+1]=candidate;break
                end
            end
        end
    end
    return parts
end
function M.isAnchor(object)
    local e=M.entry(object)
    return e and e.gx==0 and e.gy==0 or false
end
local function readRoll(object,key)
    if not object or not object:hasModData() then return end
    local data=object:getModData().movableData
    local roll=type(data)=='table' and data[key]
    if type(roll)=='number' and roll>=0 and roll<100 and roll==math.floor(roll) then return roll end
end
function M.readRoll(object) return readRoll(object,M.dataKey) end
function M.readWornRoll(object) return readRoll(object,M.wornDataKey) end
function M.readStyle(object)
    if not object or not object:hasModData() then return end
    local data=object:getModData().movableData
    local value=type(data)=='table' and data[M.styleDataKey]
    if value=='vanilla' or value=='clean' or value=='worn' then return value end
end
function M.savedStyle(object)
    local style=M.readStyle(object)
    if style then return style end
    -- Migrate 1.0.0 choices from their actual saved appearance, not today's
    -- sandbox values. Explicit clean/worn tiles placed in debug also keep style.
    if M.isWorn(object) then return 'worn' end
    if M.isDrPepper(object) then return 'clean' end
    if M.readRoll(object)~=nil then return 'vanilla' end
end
function M.writeRoll(object,key,roll)
    local data=object:getModData()
    if data.movableData~=nil and type(data.movableData)~='table' then return false end
    data.movableData=data.movableData or {}
    if data.movableData[key]==roll then return false end
    data.movableData[key]=roll;return true
end
function M.rollAt(x,y,z,seed)
    local text=tostring(seed)..':'..x..':'..y..':'..z;local hash=7
    for i=1,#text do hash=(hash*131+string.byte(text,i))%2147483647 end
    return ((hash*48271)%2147483647)%100
end
function M.prepareSprite(sprite)
    if sprite and TurnOffFridges and TurnOffFridges.clearFridgeProperty then
        TurnOffFridges.clearFridgeProperty(sprite:getProperties())
    end
end
local function prepareSprites()
    for _,name in ipairs(M.names) do
        local e=M.tiles[name]
        if name~=e.vanilla then M.prepareSprite(getSprite(name)) end
    end
end
Events.OnGameStart.Add(prepareSprites)
Events.OnServerStarted.Add(prepareSprites)
