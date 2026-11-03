local function tr(k) return getText("IGUI_ER_"..k) end
function ER.openLaptopMonitor(player,item)
 if not (WR.Laptop.data(item).links or {}).electric then player:Say(tr("NeedLink"));return end
 local p=WR.Laptop.Panel.instance
 if not p or p.item~=item then WR.Laptop.Panel.open(player,item);p=WR.Laptop.Panel.instance end
 if ER.Panel.instance and ER.Panel.instance.readOnly then ER.Panel.instance:close() end
 p.app=false;p.browser=false;p.electricApp=true;p.electricSection="Overview"
 if not p.electricTabs then
  p.electricTabs={}
  for i,key in ipairs({"Overview","Plant","Equipment","RegionsTab","ServiceTab"}) do
   local b=p:button(64+(i-1)*172,160,166,28,tr(key),function(panel,button) panel:click();panel.electricSection=button.section end)
   b.section=key;p.electricTabs[#p.electricTabs+1]=b
   b.backgroundColor={r=.31,g=.40,b=.51,a=1};b.backgroundColorMouseOver={r=.43,g=.55,b=.66,a=1}
  end
 end
 ER.request("state",nil,{player=player});p.electricRefresh=getTimestampMs()
end
function ER.drawLaptop(p)
 local s=ER.State or {};local section=p.electricSection or "Overview"
 local function text(t,x,y,font) p:label(t,x,y,.10,.20,.29,font) end
 local function card(x,y,w,h) p:drawRect(x,y,w,h,1,.78,.83,.87);p:drawRectBorder(x,y,w,h,1,.39,.48,.56) end
 p:drawRect(56,115,p.contentWidth-112,p.contentHeight-182,1,.63,.70,.77)
 text("ElectroControl / "..tr(s.originalService and "PhaseNormal" or "Overview"),70,122,UIFont.Medium)
 local ready,sum=0,0;for _,m in ipairs(s.machines or {}) do sum=sum+m.condition;if m.condition>=75 then ready=ready+1 end end
 local validated=0;for _,id in ipairs(ER.TERMINALS) do if ((s.terminals or {})[id] or {}).tested then validated=validated+1 end end
 local hours=s.initialized and ER.Core.hoursUntilService(s) or math.huge
 local eta=not s.originalService and s.online and hours<math.huge and string.format("%.1f d",hours/24) or "--"
 if section=="Overview" then
  local entries={{tr("Machines"),ready.." / 48"},{tr("ValidatedCount"),validated.." / 5"},{tr("NextService"),eta},
   {tr("FleetHealth"),string.format("%.1f%%",sum/48)},{tr("LiveDemand"),string.format("%.1f",s.selected and ER.Core.demand(s) or 0)},{tr("dispatch"),string.format("%.0f%%",(s.dispatch or {}).condition or 0)}}
  for i,e in ipairs(entries) do local x=76+(i-1)%3*286;local y=212+math.floor((i-1)/3)*104
   card(x,y,268,88);text(e[1],x+12,y+12);text(e[2],x+12,y+43,UIFont.Medium)
  end
  text(tr(s.online and (s.networkReady==false and "Connecting" or "Online") or "Offline"),80,430,UIFont.Medium)
  text(tr("PendingCount")..": "..(48-ready),80,467)
  text(tr("ActiveRegions")..": "..tostring(s.initialized and ER.Core.activeRegions(s) or 0).." / 6",500,467)
  text(tr("MonitorOnly"),80,509)
 elseif section=="Plant" then
  for i,id in ipairs(ER.TERMINALS) do local t=(s.terminals or {})[id] or {};local ref=(s.locations or {})[id] or ER.TARGETS[id];local y=208+(i-1)*60
   card(76,y,840,52);text(tr(id),88,y+8);text("X "..ref.x.." / Y "..ref.y,88,y+29)
   text(string.format("%.1f%%",t.condition or 0),525,y+17)
   text(tr(t.tested and "TestedShort" or (t.repaired and "ReadyTest" or "Broken")),657,y+17)
  end
 elseif section=="Equipment" then
  for i,m in ipairs(s.machines or {}) do local x=76+(i-1)%12*70;local y=212+math.floor((i-1)/12)*68
   card(x,y,64,59);text(string.format("M%02d",i),x+7,y+8);text(string.format("%.0f%%",m.condition),x+7,y+31)
   p:drawRect(x+4,y+54,56*math.min(1,m.condition/100),3,1,m.condition>=75 and .24 or .65,.39,.30)
  end
  text(tr("Machines")..": "..ready.." / 48",80,500)
 elseif section=="RegionsTab" then
  for i,r in ipairs(ER.REGIONS) do local x=76+(i-1)%2*430;local y=212+math.floor((i-1)/2)*96
   card(x,y,413,82);text(r.name,x+12,y+10,UIFont.Medium)
   local on=s.online and s.networkReady~=false and (s.selected or {})[r.id]
   text(tr(on and "LinkOn" or "LinkOff"),x+12,y+42)
  end
 elseif section=="ServiceTab" then
  text(tr("PlantLocation"),80,217,UIFont.Medium);text(tr("DispatchLocation"),80,254,UIFont.Medium)
  text(tr("PendingCount")..": "..(48-ready),80,304)
  text(tr("NextService")..": "..eta,80,342)
  text(tr("MonitorOnly"),80,391)
  text(tr("RepairStep"),80,432)
  text(tr("LinkHint"),80,473)
 end
end
