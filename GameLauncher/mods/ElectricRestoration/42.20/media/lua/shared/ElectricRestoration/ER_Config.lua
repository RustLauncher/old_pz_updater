ER=ER or {}
ER.DATA_KEY="ElectricRestorationData"
ER.MACHINE_COUNT=48
ER.MINIMUM=75
ER.LIFE_DAYS=45*1.20
ER.TERMINALS={"protection","cooling","regulation","balance","communications"}
ER.TARGETS={
 protection={id="protection",kind="terminal",x=14740,y=4096,z=0},
 cooling={id="cooling",kind="terminal",x=14769,y=4107,z=0},
 regulation={id="regulation",kind="terminal",x=14778,y=4107,z=0},
 balance={id="balance",kind="terminal",x=14768,y=4065,z=0},
 communications={id="communications",kind="terminal",x=14778,y=4064,z=0},
 dispatch={id="dispatch",kind="dispatch",x=7166,y=12570,z=0}
}
ER.MACHINE_ROWS={4095,4089,4083,4076}
for row,y in ipairs(ER.MACHINE_ROWS) do for col=1,12 do
 local index=(row-1)*12+col;local id=string.format("m%02d",index)
 ER.TARGETS[id]={id=id,index=index,kind="machine",x=14752+(col-1)*3,y=y,z=0}
end end
function ER.resolve(object)
 local sq=object and object:getSquare();local sp=object and object:getSprite()
 if not sq or not sp or sq:getZ()~=0 then return end
 local name=sp:getName() or "";local props=sp:getProperties();local custom=props and props:get("CustomName")
 local sprite=tonumber(name:match("^industry_02_(%d+)$"))
 -- The southern huts expose the back of the same industrial cabinet.
 -- All 16 orientations/sections are cabinets; walls remain excluded.
 local console=custom=="Terminal" or custom=="Computer" or (sprite and sprite>=160 and sprite<=175)
 local machine=sprite==62 or sprite==63
 if not console and not machine then return end
 local best,distance
 for _,t in pairs(ER.TARGETS) do
  if (t.kind=="machine" and machine) or (t.kind~="machine" and console) then
   local dx,dy=sq:getX()-t.x,sq:getY()-t.y;local d=dx*dx+dy*dy
   local allowed=t.kind=="machine" and math.abs(dx)<=1 and math.abs(dy)<=1 or t.kind~="machine" and math.abs(dx)<=3 and math.abs(dy)<=3
   if allowed and (not distance or d<distance) then best=t;distance=d end
  end
 end
 if best then return {id=best.id,kind=best.kind,index=best.index,x=sq:getX(),y=sq:getY(),z=0} end
end
function ER.targetAt(x,y,z,id)
 local sq=getCell():getGridSquare(x,y,z);if not sq then return end
 local objects=sq:getObjects()
 for i=0,objects:size()-1 do local t=ER.resolve(objects:get(i));if t and t.id==id then return t end end
end
ER.REGIONS={
 {id="south",name="Rosewood / March Ridge",demand=1.4,areas={{4800,10000,9500,16000},{9500,11500,11000,14000}}},
 {id="riverside",name="Riverside / Fallas Lake",demand=1.3,areas={{4800,4800,9500,10000}}},
 {id="irvington",name="Irvington / Echo Creek",demand=1,areas={{0,10000,4800,16000}}},
 {id="brandenburg",name="Ekron / Brandenburg",demand=1,areas={{0,4800,4800,10000}}},
 {id="muldraugh",name="Muldraugh / West Point",demand=2,areas={{9500,5500,14500,11500}}},
 {id="louisville",name="Louisville / Valley Station",demand=4,areas={{11000,0,16000,5500}}}
}
function ER.regionAt(x,y)
 for _,r in ipairs(ER.REGIONS) do for _,a in ipairs(r.areas) do
  if x>=a[1] and y>=a[2] and x<a[3] and y<a[4] then return r end
 end end
end

-- Dedicated station service footprints, independent of public region selection.
ER.PLANT_AREAS={{14728,4052,14797,4121},{7156,12558,7189,12595}}
function ER.inPlant(x,y)
 for _,a in ipairs(ER.PLANT_AREAS) do if x>=a[1] and x<a[3] and y>=a[2] and y<a[4] then return true end end
 return false
end
