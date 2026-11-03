require "WaterRestoration/WR_Config"
WR.Laptop=WR.Laptop or {}
local L=WR.Laptop
L.ITEM="Base.WRMilitaryLaptop"
L.HOURS=168
function L.isLaptop(item) return item and item:getFullType()==L.ITEM end
function L.data(item)
 local md=item:getModData()
 md.WRLaptop=md.WRLaptop or {opened=false,powered=false,hours=0,cells=0}
 return md.WRLaptop
end
function L.now() return getGameTime():getWorldAgeHours() end
function L.remaining(d,now)
 return math.max(0,(d.hours or 0)-(d.powered and math.max(0,(now or L.now())-(d.updatedAt or now or L.now())) or 0))
end
function L.settle(item)
 local d=L.data(item);local now=L.now()
 d.hours=L.remaining(d,now);d.updatedAt=now
 if d.hours<=0 then d.powered=false end
 return d
end
function L.visual(item)
 local opened=L.data(item).opened
 local model=opened and "WR_MilitaryLaptopOpen" or "WR_MilitaryLaptopClosed"
 item:setStaticModel(model);item:setWorldStaticModel(model)
 local texture=getTexture and getTexture("media/textures/Item_WRMilitaryLaptop"..(opened and "Open" or "Closed")..".png")
 if texture then item:setTexture(texture) end
 -- The native placed-item atlas checks rotation, but does not check model name.
 -- A deterministic 0.01-degree offset invalidates that cache on open/close.
 if item.getWorldZRotation and item.setWorldZRotation then
  local md=item:getModData();local angle=item:getWorldZRotation()
  local previous=md.WRVisualOpened and .01 or 0
  if md.WRVisualBaseAngle==nil or math.abs(angle-(md.WRVisualBaseAngle+previous))>.001 then md.WRVisualBaseAngle=angle-previous end
  item:setWorldZRotation(md.WRVisualBaseAngle+(opened and .01 or 0));md.WRVisualOpened=opened
 end
 local world=item:getWorldItem()
 if world then
  if world.setSpriteModelName then world:setSpriteModelName(model) end
  if world.updateSprite then world:updateSprite() end
 end
end
function L.onCreate(item) L.data(item);L.visual(item) end
Events.LoadGridsquare.Add(function(square)
 local objects=square and square:getWorldObjects()
 if objects then for i=0,objects:size()-1 do
  local item=objects:get(i):getItem()
  if L.isLaptop(item) then L.visual(item) end
 end end
end)
function L.walk(container,callback)
 if not container then return end
 local items=container:getItems()
 for i=0,items:size()-1 do
  local item=items:get(i)
  callback(item)
  if instanceof(item,"InventoryContainer") then L.walk(item:getInventory(),callback) end
 end
end
function L.find(player,id,x,y,z)
 local found
 L.walk(player:getInventory(),function(item) if item:getID()==id and L.isLaptop(item) then found=item end end)
 if found then return found end
 if not x or not y or not z or player:getZ()~=z then return end
 if (player:getX()-x)^2+(player:getY()-y)^2>9 then return end
 local sq=getCell():getGridSquare(x,y,z);local objects=sq and sq:getWorldObjects()
 if objects then for i=0,objects:size()-1 do
  local item=objects:get(i):getItem()
  if L.isLaptop(item) and item:getID()==id then return item end
 end end
end
