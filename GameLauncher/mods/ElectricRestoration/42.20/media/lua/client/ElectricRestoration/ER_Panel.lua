require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ElectricRestoration/ER_Actions"
ER.Panel=ISPanel:derive("ERElectricControlPanel")
local P=ER.Panel
local function tr(k) return getText("IGUI_ER_"..k) end
function P:close() self:removeFromUIManager();if P.instance==self then P.instance=nil end end
function P:button(x,y,w,label,fn)
 local b=ISButton:new(x,y,w,32,label,self,fn);b:initialise();b:instantiate()
 b.backgroundColor={r=.16,g=.21,b=.26,a=1};b.borderColor={r=.63,g=.62,b=.44,a=1};self:addChild(b);return b
end
function P:createChildren()
 ISPanel.createChildren(self)
 self:button(self.width-110,24,80,tr("Close"),P.close)
 if not self.readOnly then
  self:button(32,self.height-62,205,tr("Repair"),function(p) if ER.queue(p.player,p.target,"repair") then p:close() end end)
  if self.target.kind=="terminal" then
   self:button(250,self.height-62,205,tr("Test"),function(p) if ER.queue(p.player,p.target,"test") then p:close() end end)
  elseif self.target.kind=="dispatch" then
   self:button(250,self.height-62,205,tr("ApplyRegions"),function(p) ER.request("regions",p.target,{selected=p.selected,expected=p.selectionRevision,player=p.player});p.changed=false end)
   self:button(468,self.height-62,150,tr("Start"),function(p) ER.queue(p.player,p.target,"start") end)
   self:button(630,self.height-62,150,tr("Stop"),function(p) ER.queue(p.player,p.target,"stop") end)
  end
 end
 self.regionButtons={}
 if self.target.id=="dispatch" or self.readOnly then
  for i,r in ipairs(ER.REGIONS) do
   local b=self:button(690,135+(i-1)*58,345,r.name,function(p,button) p.selected[button.region]=not p.selected[button.region];p.changed=true end)
   b.region=r.id;b:setEnable(not self.readOnly);self.regionButtons[#self.regionButtons+1]=b
  end
 end
end
function P:ink(t,x,y,font,color)
 local c=color or {.83,.86,.87};self:drawText(t,x,y,c[1],c[2],c[3],1,font or UIFont.Small)
end
function P:prerender()
 ISPanel.prerender(self);local s=ER.State or {};local machines=s.machines or {};local terminals=s.terminals or {}
 self:drawRect(8,8,self.width-16,self.height-16,1,.20,.25,.30)
 self:drawRect(20,78,self.width-40,self.height-165,1,.055,.09,.13)
 self:drawRect(20,78,self.width-40,3,1,.88,.64,.25)
 self:ink(tr("Title"),32,25,UIFont.Large);self:ink(tr("Emergency"),32,56,nil,{.91,.71,.39})
 local id=self.target.id
 self:ink(self.target.kind=="machine" and (tr("Machines").." / "..id:upper()) or tr(self.readOnly and "Remote" or id),32,96,UIFont.Medium)
 local ready=0;for _,m in ipairs(machines) do if m.condition>=75 then ready=ready+1 end end
 self:ink(tr("Machines").." "..ready.." / 48",32,128)
 self:ink(tr(s.online and (s.networkReady==false and "Connecting" or "Online") or "Offline"),32,153,UIFont.Medium,s.online and {.49,.83,.60} or {.95,.64,.37})
 if self.target.kind=="machine" then
  local m=machines[self.target.index] or {};self:ink(string.format("M%02d / %.1f%%",self.target.index,m.condition or 0),60,223,UIFont.Large)
  self:drawRect(60,275,570,20,1,.12,.19,.24);self:drawRect(62,277,566*(m.condition or 0)/100,16,1,.84,.63,.27)
  self:ink(tr("MachineCost"),60,328);self:ink(tr("RepairStep"),60,358)
 else
  -- Diagnostic matrix, not an imitation of the water consoles.
  for i,m in ipairs(machines) do
   local col=(i-1)%12;local row=math.floor((i-1)/12);local x=32+col*52;local y=208+row*64
   local ok=m.condition>=75;self:drawRect(x,y,46,54,1,ok and .14 or .36,ok and .29 or .18,.18)
   self:ink(string.format("%02d",i),x+7,y+5);self:ink(string.format("%.0f%%",m.condition),x+5,y+29)
  end
  for i,key in ipairs(ER.TERMINALS) do
   local t=terminals[key] or {};local y=484+(i-1)*23
   self:ink(tr(key).." / "..tr(t.tested and "TestedShort" or (t.repaired and "ReadyTest" or "Broken")),32,y)
  end
  if id~="dispatch" and not self.readOnly then self:ink(tr("Function_"..id),32,185) end
 end
 if id=="dispatch" or self.readOnly then
  local preview={selected=self.selected};local demand=ER.Core.demand(preview)
  self:ink(tr("Demand")..string.format(" %.1f",demand),690,505,UIFont.Medium)
  self:ink(tr("Lifetime").." "..(demand>0 and string.format("%.1f d",45/(.6+.4*demand)) or "--"),690,539)
  local hours=s.initialized and ER.Core.hoursUntilService(s) or 0
  self:ink(tr("NextService").." "..(hours<math.huge and string.format("%.1f d",hours/24) or "--"),690,570)
  for _,b in ipairs(self.regionButtons) do b:setTitle((self.selected[b.region] and "[ON] " or "[OFF] ")..ER.REGIONS[_].name) end
 end
 self:ink(tr("ServiceHint"),32,self.height-104)
end
function P:update()
 ISPanel.update(self)
 if self.readOnly then
  if not WR or not WR.Laptop or not WR.Laptop.find(self.player,self.laptop:getID(),self.worldX,self.worldY,self.worldZ) or not WR.Laptop.data(self.laptop).opened or not WR.Laptop.data(self.laptop).powered or WR.Laptop.remaining(WR.Laptop.data(self.laptop))<=0 then self:close();return end
 elseif self.player:getZ()~=self.target.z or (self.player:getX()-self.target.x)^2+(self.player:getY()-self.target.y)^2>16 then self:close();return end
 local s=ER.State or {}
 if self.pendingApply and (s.selectionRevision~=self.selectionRevision or getTimestampMs()-self.pendingApply>6000) then
  self.pendingApply=nil;self.changed=false
 end
 if not self.changed and s.selectionRevision~=self.selectionRevision then self.selectionRevision=s.selectionRevision;self.selected={};for k,v in pairs(s.selected or {}) do self.selected[k]=v end end
 if getTimestampMs()-(self.lastRefresh or 0)>5000 then ER.request("state",nil,{player=self.player});self.lastRefresh=getTimestampMs() end
end
function P.open(player,target,readOnly,laptop)
 if P.instance then P.instance:close() end
 local wide=target.id=="dispatch" or readOnly;local w=wide and 1070 or 1120;local h=wide and 740 or 780
 local o=P:new((getCore():getScreenWidth()-w)/2,(getCore():getScreenHeight()-h)/2,w,h)
 o.player=player;o.target=target;o.readOnly=readOnly;o.laptop=laptop;o.selected={};o.selectionRevision=(ER.State or {}).selectionRevision or 0
 for k,v in pairs((ER.State or {}).selected or {}) do o.selected[k]=v end
 if laptop then local world=laptop:getWorldItem();local sq=world and world:getSquare();if sq then o.worldX=sq:getX();o.worldY=sq:getY();o.worldZ=sq:getZ() end end
 o.backgroundColor={r=.08,g=.11,b=.14,a=1};o.borderColor={r=.54,g=.59,b=.61,a=1};o:initialise();o:instantiate();o:addToUIManager();P.instance=o
end

-- Physical cabinet, phosphor diagnostics and an independent service LCD.
local oldButton=P.button
function P:button(x,y,w,label,fn)
 local b=oldButton(self,x,y,w,label,fn)
 b.backgroundColor={r=.29,g=.31,b=.32,a=1}
 b.backgroundColorMouseOver={r=.40,g=.43,b=.43,a=1}
 b.borderColor={r=.08,g=.09,b=.10,a=1}
 b.prerender=function(button)
  ISButton.prerender(button)
  local light=button.pressed and .13 or .59
  button:drawRect(2,2,button.width-4,2,1,light,light,light)
  button:drawRect(2,2,2,button.height-4,1,light,light,light)
  button:drawRect(2,button.height-4,button.width-4,2,1,.09,.10,.11)
  button:drawRect(button.width-4,2,2,button.height-4,1,.09,.10,.11)
 end
 return b
end
local oldChildren=P.createChildren
function P:createChildren()
 if self.target.id=="dispatch" or self.readOnly then oldChildren(self);return end
 ISPanel.createChildren(self);self.serviceMode="repair"
 self:button(self.width-115,30,80,tr("Close"),P.close)
 self.repairButton=self:button(56,708,236,tr("Repair"),function(p)
  if ER.queue(p.player,p.target,"repair") then p:close() end
 end)
 if self.target.kind=="terminal" then
  self.testButton=self:button(310,708,236,tr("Test"),function(p)
   if ER.queue(p.player,p.target,"test") then p:close() end
  end)
 end
 self.repairTab=self:button(775,165,132,tr("CheckRepair"),function(p) p.serviceMode="repair" end)
 if self.target.kind=="terminal" then self.testTab=self:button(923,165,132,tr("CheckTest"),function(p) p.serviceMode="test" end) end
 self.regionButtons={}
end
function P:bezel(x,y,w,h)
 self:drawRect(x,y,w,h,1,.075,.08,.08)
 self:drawRect(x+3,y+3,w-6,3,1,.12,.13,.13)
 self:drawRect(x+3,y+h-5,w-6,2,1,.53,.55,.54)
 self:drawRect(x+7,y+7,w-14,h-14,1,.035,.085,.075)
end
function P:serviceScreen()
 self:bezel(755,120,324,535)
 self:ink(tr("ServiceDisplay"),775,134,UIFont.Medium,{.76,.79,.58})
 if (ER.State or {}).originalService then
  self:ink(tr("Overview"),775,240,nil,{.76,.79,.65})
  return
 end
 local ok,rows=ER.Requirements.check(self.player,ER.State or {},self.target,self.serviceMode)
 self:ink(tr("Requirements"),775,220,nil,{.77,.81,.72})
 local y=256
 for _,row in ipairs(rows) do
  local color=row.ok and {.56,.72,.55} or {.96,.61,.39}
  if row.key=="NeedsService" and not row.ok then color={.65,.71,.67} end
  self:drawRect(776,y+4,6,6,1,color[1],color[2],color[3])
  self:ink(tr((row.key=="NeedsService" and not row.ok) and "NoRepairNeeded" or row.key),791,y,nil,color)
  if row.need>1 or row.key=="Screwdriver" or row.key=="Wrench" then
   self:ink(tostring(row.have).." / "..row.need,991,y,nil,color)
  end
  y=y+28
 end
 local node=ER.Requirements.node(ER.State or {},self.target) or {}
 local summary=ok and "ReadyAction" or "MissingAction"
 if self.serviceMode=="repair" and (node.condition or 0)>=100 then summary="NoRepairNeeded" end
 if self.serviceMode=="test" and node.tested then summary="TestedShort" end
 self:ink(tr(summary),775,620,nil,{.76,.79,.65})
 if self.repairButton then
  local can,missing=ER.Requirements.check(self.player,ER.State or {},self.target,"repair")
  self.repairButton:setEnable(can);self.repairButton.tooltip=can and nil or ER.Requirements.missing(missing)
 end
 if self.testButton then
  local can,missing=ER.Requirements.check(self.player,ER.State or {},self.target,"test")
  self.testButton:setEnable(can);self.testButton.tooltip=can and nil or ER.Requirements.missing(missing)
 end
end
local oldPrerender=P.prerender
function P:prerender()
 if self.target.id=="dispatch" or self.readOnly then oldPrerender(self);return end
 ISPanel.prerender(self)
 self:drawRect(8,8,self.width-16,self.height-16,1,.28,.30,.30)
 self:drawRect(14,14,self.width-28,3,1,.54,.56,.54)
 for _,x in ipairs({25,self.width-31}) do for _,y in ipairs({25,self.height-31}) do
  self:drawRect(x,y,7,7,1,.10,.11,.11);self:drawRect(x+1,y+3,5,1,1,.59,.60,.58)
 end end
 self:ink("ER / "..tr("PanelTag"),40,30,UIFont.Large,{.88,.88,.81})
 self:ink(tr((ER.State or {}).originalService and "PhaseNormal" or "Emergency"),40,66,nil,{.83,.73,.45})
 self:drawRect(40,92,1040,3,1,.15,.17,.16)
 self:bezel(40,120,690,535)
 for y=132,640,4 do self:drawRect(49,y,672,1,.12,.04,.10,.075) end
 local state=ER.State or {};local node=ER.Requirements.node(state,self.target) or {}
 local green={.64,.83,.68}
 self:ink(self.target.kind=="machine" and self.target.id:upper() or tr(self.target.id),62,137,UIFont.Medium,green)
 self:ink("X "..self.target.x.." / Y "..self.target.y,62,165,nil,{.40,.62,.48})
 self:ink(tr("Condition")..string.format("  %.0f%%",node.condition or 0),420,165,nil,green)
 if self.target.kind=="machine" then
  self:ink(string.format("%.1f%%",node.condition or 0),70,233,UIFont.Large,green)
  self:drawRect(70,285,570,22,1,.10,.16,.12)
  self:drawRect(72,287,566*(node.condition or 0)/100,18,1,.43,.66,.45)
  self:ink(tr("RepairStep"),70,342,nil,green)
 else
  self:diagnostic(state,node)
 end
 self:ink(tr("SequenceTitle"),62,456,UIFont.Medium,green)
 for i,id in ipairs(ER.TERMINALS) do
  local t=(state.terminals or {})[id] or {};local y=489+(i-1)*27
  local color=t.tested and green or {.66,.62,.42}
  self:drawRect(63,y+4,6,6,1,color[1],color[2],color[3])
  self:ink(tr(id),80,y,nil,color)
  self:ink(tr(t.tested and "TestedShort" or (t.repaired and "ReadyTest" or "Broken")),430,y,nil,color)
 end
 self:drawRect(40,680,1040,75,1,.20,.22,.22)
 self:ink(tr("ServiceHint"),575,717,nil,{.66,.69,.67})
 self:serviceScreen()
end

function P:diagnostic(state,node)
 local green={.64,.83,.68};local amber={.86,.65,.39}
 local id=self.target.id;local phase=math.floor(getTimestampMs()/160)%18
 local active=node.tested and (node.condition or 0)>=75
 local color=active and green or amber
 local function box(x,y,w,h,label)
  self:drawRect(x,y,w,h,1,.09,.15,.13)
  self:drawRectBorder(x,y,w,h,1,color[1]*.65,color[2]*.65,color[3]*.65)
  self:ink(label,x+10,y+10,nil,color)
 end
 self:ink(tr("View_"..id),62,205,UIFont.Medium,green)
 if id=="protection" then
  -- A single-line diagram: auxiliary reserve, isolation, protection, bus.
  local labels={"Reserve","Isolation","Protection","Bus"}
  self:drawRect(84,291,574,3,1,.28,.42,.32)
  for i,key in ipairs(labels) do
   local x=70+(i-1)*160;box(x,253,140,81,tr(key))
   self:drawRect(x+25,301,28,3,1,color[1],color[2],color[3])
   self:drawRect(x+84,301,28,3,1,color[1],color[2],color[3])
   if active or i==1 then self:drawRect(x+53,301,31,3,1,.56,.75,.57)
   else for j=0,10 do self:drawRect(x+53+j*3,300-j*2,3,3,1,.8,.57,.33) end end
  end
  box(70,355,620,67,tr(active and "TestedShort" or "ReadyTest"))
  self:ink(tr("ProtectionHint"),80,391,nil,green)
 elseif id=="cooling" then
  -- Four banks mirror the four actual machinery rows.
  for row=1,4 do
   local y=247+(row-1)*45;local health,ready=0,0
   for i=(row-1)*12+1,row*12 do local m=(state.machines or {})[i]
    if m then health=health+m.condition;if m.condition>=75 then ready=ready+1 end end
   end
   self:ink(tr("Bank").." "..row,70,y,nil,green)
   self:drawRect(160,y,335,22,1,.09,.17,.14)
   self:drawRect(162,y+2,331*health/1200,18,1,.26,.47,.42)
   if active then self:drawRect(162+phase*17,y+3,10,16,1,.57,.77,.65) end
   self:ink(string.format("%.0f%%",health/12),510,y+3,nil,green)
   self:ink(tostring(ready).." / 12",600,y+3,nil,green)
  end
  self:ink(tr("CoolingHint"),70,432,nil,green)
 elseif id=="regulation" then
  -- Individual condition is the measured value, not fabricated voltage.
  for i,m in ipairs(state.machines or {}) do
   local col=(i-1)%12;local row=math.floor((i-1)/12);local x=62+col*53;local y=237+row*48
   local ready=m.condition>=75
   self:drawRect(x,y,46,39,1,ready and .12 or .21,ready and .23 or .15,.12)
   self:ink(string.format("%02d",i),x+6,y+2,nil,green)
   self:ink(string.format("%.0f%%",m.condition),x+6,y+19,nil,ready and green or amber)
  end
  self:ink(tr("RegulationHint"),62,432,nil,green)
 elseif id=="balance" then
  -- Clearly labelled schematic traces, not simulated electrical measurements.
  for y=245,389,24 do self:drawRect(70,y,620,1,1,.10,.22,.17) end
  for x=70,690,31 do self:drawRect(x,245,1,144,1,.10,.22,.17) end
  local colors={{.58,.82,.63},{.77,.67,.41},{.43,.68,.73}}
  for channel=1,3 do
   local c=colors[channel];local shift=active and getTimestampMs()/900 or 0
   for x=0,306 do
    local y=317+math.sin(x/32+channel*2.094-shift)*48
    self:drawRect(72+x*2,y,2,2,1,c[1],c[2],c[3])
   end
   self:ink(tr("Phase").." "..string.char(64+channel),85+(channel-1)*200,402,nil,c)
  end
  self:ink(tr("Schematic"),70,432,nil,green)
 elseif id=="communications" then
  box(70,255,180,130,tr("LocalLink"))
  self:ink(tr(active and "TestedShort" or "Broken"),80,295,nil,color)
  self:ink("7166 / 12570",80,342,nil,green)
  self:drawRect(250,318,78,3,1,.3,.46,.36)
  if active then self:drawRect(253+(phase%9)*8,313,5,12,1,.63,.83,.67) end
  for i,r in ipairs(ER.REGIONS) do
   local x=330+(i-1)%2*185;local y=242+math.floor((i-1)/2)*61
   local on=state.online and (state.selected or {})[r.id]
   box(x,y,174,49,tr("Region_"..r.id))
   self:ink(tr(on and "LinkOn" or "LinkOff"),x+10,y+29,nil,on and green or amber)
  end
  self:ink(tr("LinkHint"),70,432,nil,green)
 end
end

-- Dispatch and Calfer share the same complete, read-only-capable telemetry views.
local localChildren=P.createChildren
function P:createChildren()
 if self.target.id~="dispatch" and not self.readOnly then return localChildren(self) end
 ISPanel.createChildren(self);self.section="Overview";self.regionButtons={};self.controlButtons={}
 self:button(self.width-112,25,80,tr("Close"),P.close)
 for i,key in ipairs({"Overview","Plant","Equipment","RegionsTab","ServiceTab"}) do
  local b=self:button(32+(i-1)*202,100,190,tr(key),function(p,button) p.section=button.section end);b.section=key
 end
 for i,r in ipairs(ER.REGIONS) do
  local b=self:button(55,200+(i-1)*61,425,r.name,function(p,button) p.selected[button.region]=not p.selected[button.region];p.changed=true end)
  b.region=r.id;b:setEnable(not self.readOnly);b:setVisible(false);self.regionButtons[#self.regionButtons+1]=b
 end
 if not self.readOnly then
  local function control(x,w,label,section,fn)
   local b=self:button(x,678,w,tr(label),fn);b.section=section;b:setVisible(false);self.controlButtons[#self.controlButtons+1]=b;return b
  end
  self.repairButton=control(40,220,"Repair","ServiceTab",function(p) if ER.queue(p.player,p.target,"repair") then p:close() end end)
  self.applyButton=control(40,220,"ApplyRegions","RegionsTab",function(p)
   if p.pendingApply then return end
   p.pendingApply=getTimestampMs();ER.request("regions",p.target,{selected=p.selected,expected=p.selectionRevision,player=p.player})
  end)
  self.startButton=control(280,190,"Start","RegionsTab",function(p)
   if p.changed or p.pendingApply then return end
   local ok,rows=ER.Requirements.check(p.player,ER.State or {},p.target,"start")
   if not ok then p.startBlocked=ER.Requirements.missing(rows);p.player:Say(p.startBlocked);return end
   p.startBlocked=nil;ER.queue(p.player,p.target,"start")
  end)
  self.stopButton=control(490,190,"Stop","RegionsTab",function(p) ER.queue(p.player,p.target,"stop") end)
 end
end
local localPrerender=P.prerender
function P:prerender()
 if self.target.id~="dispatch" and not self.readOnly then
  localPrerender(self)
  local state=ER.State or {}
  for _,button in pairs({self.repairButton,self.testButton,self.repairTab,self.testTab}) do button:setVisible(not state.originalService) end
  if state.originalService then
   -- Local service buttons are child controls at the bottom of the cabinet.
   for _,button in pairs({self.repairButton,self.testButton}) do button:setVisible(false) end
   self:drawRect(44,609,1030,55,1,.09,.15,.14)
   self:ink(tr("PhaseNormal"),62,620,UIFont.Medium)
   self:ink(tr("OriginalService"),62,646)
  end
  return
 end
 ISPanel.prerender(self);local s=ER.State or {};local green={.62,.82,.71};local amber={.86,.67,.41}
 self:drawRect(8,8,self.width-16,self.height-16,1,.25,.28,.29)
 self:ink(tr(self.readOnly and "Remote" or "dispatch"),32,27,UIFont.Large)
 self:ink(tr(s.originalService and "PhaseNormal" or (not s.commissioned and "PhaseInterrupted" or (s.initialized and ER.Core.plantReady(s) and "StationPower" or "Emergency"))),32,62,nil,amber)
 self:bezel(32,150,self.width-64,502)
 for _,b in ipairs(self.regionButtons) do b:setVisible(self.section=="RegionsTab") end
 for _,b in ipairs(self.controlButtons) do b:setVisible(b.section==self.section and not s.originalService) end
 local machines=s.machines or {};local ready,sum,worst=0,0,nil
 for _,m in ipairs(machines) do sum=sum+m.condition;if m.condition>=75 then ready=ready+1 end;if not worst or m.condition<worst.condition then worst=m end end
 local validated=0;for _,id in ipairs(ER.TERMINALS) do if ((s.terminals or {})[id] or {}).tested then validated=validated+1 end end
 local hours=s.initialized and ER.Core.hoursUntilService(s) or math.huge
 local eta=not s.originalService and hours<math.huge and string.format("%.1f d",hours/24) or "--"
 local function ink(t,x,y,font,c) self:ink(t,x,y,font,c or green) end
 local function card(x,y,w,label,value)
  self:drawRect(x,y,w,90,1,.09,.15,.14);ink(label,x+15,y+13);ink(value,x+15,y+43,UIFont.Large)
 end
 if self.section=="Overview" then
  ink(tr(s.online and (s.networkReady==false and "Connecting" or "Online") or "Offline"),55,176,UIFont.Medium,s.online and green or amber)
  card(55,222,300,tr("ValidatedCount"),validated.." / 5")
  card(380,222,300,tr("Machines"),ready.." / 48")
  card(705,222,300,tr("NextService"),eta)
  card(55,338,300,tr("ActiveRegions"),tostring(s.initialized and ER.Core.activeRegions(s) or 0).." / 6")
  card(380,338,300,tr("LiveDemand"),string.format("%.1f",s.selected and ER.Core.demand(s) or 0))
  card(705,338,300,tr("Condition"),string.format("%.0f%%",(s.dispatch or {}).condition or 0))
  ink(tr("PlantLocation"),55,474,UIFont.Medium);ink(tr("DispatchLocation"),55,515,UIFont.Medium)
  ink(tr("PairHint"),55,582)
 elseif self.section=="Plant" then
  ink(tr("PlantLocation"),55,179,UIFont.Medium)
  for i,id in ipairs(ER.TERMINALS) do
   local t=(s.terminals or {})[id] or {};local ref=(s.locations or {})[id] or ER.TARGETS[id];local y=228+(i-1)*71
   self:drawRect(55,y,950,60,1,.09,.15,.14)
   ink(tr(id),70,y+9,UIFont.Medium);ink("X "..ref.x.." / Y "..ref.y,70,y+35)
   ink(string.format("%.1f%%",t.condition or 0),510,y+19,UIFont.Medium)
   ink(tr(t.tested and "TestedShort" or (t.repaired and "ReadyTest" or "Broken")),675,y+19,nil,t.tested and green or amber)
  end
 elseif self.section=="Equipment" then
  ink(tr("Machines").." "..ready.." / 48",55,180,UIFont.Medium)
  for i,m in ipairs(machines) do
   local x=55+(i-1)%12*79;local y=227+math.floor((i-1)/12)*79
   self:drawRect(x,y,72,66,1,m.condition>=75 and .10 or .22,.18,.13)
   ink(string.format("M%02d",i),x+10,y+8);ink(string.format("%.1f%%",m.condition),x+10,y+35,nil,m.condition>=75 and green or amber)
  end
  if worst then local ref=ER.TARGETS[string.format("m%02d",worst.id)]
   ink(tr("WorstEquipment")..string.format(" / M%02d / X %d / Y %d",worst.id,ref.x,ref.y),55,563)
  end
  ink(tr("NextService").." "..eta,55,598)
 elseif self.section=="RegionsTab" then
  local dirty=false
  for _,r in ipairs(ER.REGIONS) do if (self.selected[r.id]==true)~=((s.selected or {})[r.id]==true) then dirty=true end end
  self.changed=dirty or self.pendingApply~=nil
  for i,key in ipairs({"StepSelect","StepSave","StepConnect"}) do
   local x=55+(i-1)*320
   self:drawRect(x,165,305,31,1,.14,.23,.24)
   ink(tr(key),x+10,172)
  end
  for i,b in ipairs(self.regionButtons) do local r=ER.REGIONS[i];local y=207+(i-1)*61
   b:setTitle((self.selected[r.id] and "[x] " or "[ ] ")..r.name)
   b:setEnable(not s.originalService and not self.readOnly and not self.pendingApply)
   local applied=(s.selected or {})[r.id]
   ink(tr(applied and "SavedYes" or "SavedNo"),520,y)
   local live=s.online and s.networkReady~=false and applied
   self:drawRect(782,y+3,10,10,1,live and .3 or .55,live and .8 or .4,.3)
   ink(tr(live and "LinkOn" or (s.online and applied and "Connecting" or "LinkOff")),810,y)
  end
  local demand=ER.Core.demand({selected=self.selected})
  ink(tr("Demand")..string.format(" %.1f",demand),55,584)
  ink(tr("ActiveRegions")..": "..tostring(s.initialized and ER.Core.activeRegions(s) or 0).." / 6",520,584)
  ink(tr(self.pendingApply and "SavingPlan" or (dirty and "UnsavedPlan" or (s.online and (s.networkReady==false and "Connecting" or "LivePlan") or "SavedPlan"))),55,618,nil,dirty and amber or green)
  if self.applyButton then
   self.applyButton:setEnable(dirty and not self.pendingApply and (s.dispatch or {}).repaired==true)
   local ok,rows=ER.Requirements.check(self.player,s,self.target,"start")
   self.startButton:setEnable(not dirty and not self.pendingApply and not s.online)
   local missing=not ok and ER.Requirements.missing(rows) or nil
   self.startButton.tooltip=dirty and tr("UnsavedPlan") or missing
   if not s.originalService and not dirty and not self.pendingApply and not s.online and missing then
    local first=missing:match("^[^;]+") or missing
    self:drawRect(44,609,980,35,1,.09,.15,.14)
    ink(first,55,618,nil,amber)
   end
   self.stopButton:setEnable(s.online==true)
  end
 elseif self.section=="ServiceTab" then
  ink(tr("DispatchLocation"),55,177,UIFont.Medium)
  ink(tr("Condition")..string.format(" %.1f%%",(s.dispatch or {}).condition or 0),55,213)
  if self.readOnly then
   ink(tr("MonitorOnly"),55,266,UIFont.Medium)
   ink(tr("NextService").." "..eta,55,323)
   ink(tr("PendingCount").." "..(48-ready),55,363)
   ink(tr("ValidatedCount").." "..validated.." / 5",55,403)
  else
   local ok,rows=ER.Requirements.check(self.player,s,self.target,"repair")
   self.repairButton:setEnable(ok);self.repairButton.tooltip=ok and nil or ER.Requirements.missing(rows)
   for i,row in ipairs(rows) do
    local x=i<=7 and 55 or 550;local y=269+((i-1)%7)*44
    ink(ER.Requirements.label(row),x,y,nil,row.ok and green or amber)
    if not row.ref and row.need>1 then ink(row.have.." / "..row.need,x+350,y) end
   end
  end
 end
 if self.readOnly then ink(tr("MonitorOnly"),40,688) end
end
