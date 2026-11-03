require "WaterRestoration/WR_PlantPanel"
require "WaterRestoration/WR_Regions"
WR.DistributionPanel=WR.PlantPanel:derive("WRWideDistributionPanel")
local D=WR.DistributionPanel
local function tr(k) return getText("IGUI_WR_Console_"..k) end
local colors={{.78,.64,.28},{.25,.68,.68},{.62,.44,.72},{.43,.66,.32},{.34,.53,.80},{.78,.43,.32}}
local function project(x,y) return (x-y)*.70710678,(x+y)*.35355339 end
function D:layout()
    return 40,160,self.width-406,self.height-350
end
function D:monitorFrames()
    local mx,my,mw,mh=self:layout();local sx=self.width-320
    self:rounded(24,78,mw+32,my+mh-60,20,1,.39,.45,.38)
    self:rounded(31,85,mw+18,my+mh-74,16,1,.025,.045,.041)
    self:rounded(sx-16,78,306,290,20,1,.39,.45,.38)
    self:rounded(sx-9,85,292,276,16,1,.025,.045,.041)
    self:rounded(24,self.height-166,mw+32,122,12,1,.38,.42,.37)
    self:rounded(25,self.height-165,mw+30,120,11,1,.21,.24,.22)
    self:rounded(sx-16,378,306,self.height-422,12,1,.38,.42,.37)
    self:rounded(sx-15,379,304,self.height-424,11,1,.21,.24,.22)
end
function D:cityInitial(city) return string.upper(string.sub(city.name,1,1)) end
function D:drawMapHover()
    if not self.getMouseX or not self.getMouseY then return end
    local mx,my,mw,mh=self:layout();local x,y=self:getMouseX(),self:getMouseY()
    for _,hit in ipairs(self.mapHits or {}) do
        if (math.abs(x-hit.x)<=12 and math.abs(y-hit.y)<=12) or (hit.labelX and x>=hit.labelX-5 and x<=hit.labelX+hit.labelW+7 and y>=hit.labelY-3 and y<=hit.labelY+19) then
            local city=hit.city or WR.SupplyLocations[hit.index]
            local width=self:labelWidth(city.name)
            self:mapLabel(city.name,math.max(mx+8,math.min(x+20,mx+mw-width-15)),math.max(my+8,math.min(y-28,my+mh-30)),{.99,.91,.57})
            return
        end
    end
end
function D:labelWidth(text)
    if getTextManager then return getTextManager():MeasureStringX(UIFont.Small,text) end
    return #text*7
end
function D:mapLabel(text,x,y,color)
    local width=self:labelWidth(text)
    self:rounded(x-5,y-3,width+12,22,4,.96,.025,.045,.041)
    self:drawRect(x-5,y-1,2,18,1,color[1],color[2],color[3])
    self:ink(text,x+1,y,nil,color)
end
function D:distributorIcon(x,y,index)
    local c=colors[index]
    self:rounded(x-12,y-12,25,25,5,1,.025,.045,.041)
    self:drawRectBorder(x-11,y-11,23,23,1,c[1],c[2],c[3])
    -- Regional valve: round handwheel, hub and four spokes.
    self:rounded(x-7,y-7,15,15,7,1,c[1],c[2],c[3])
    self:rounded(x-5,y-5,11,11,5,1,.025,.045,.041)
    self:drawRect(x-1,y-7,3,15,1,c[1],c[2],c[3])
    self:drawRect(x-7,y-1,15,3,1,c[1],c[2],c[3])
    self:mapLabel(string.format("D%02d",index),x-12,y+18,c)
end
function D:plantIcon(x,y)
    local c={.92,.94,.78}
    self:rounded(x-15,y-15,31,31,5,1,.025,.045,.041)
    self:drawRectBorder(x-14,y-14,29,29,1,c[1],c[2],c[3])
    -- Main plant: two stacks and a pump-house, unlike regional valves.
    self:drawRect(x-9,y-10,5,15,1,c[1],c[2],c[3])
    self:drawRect(x+3,y-8,5,13,1,c[1],c[2],c[3])
    self:drawRect(x-10,y+1,21,9,1,c[1],c[2],c[3])
    self:drawRect(x-2,y+4,5,6,1,.025,.045,.041)
end
function D:cityName(city,x,y,color,boxes)
    local mx,my,mw,mh=self:layout();local name=city.name:gsub(" Trailer Park","")
    local tw=self:labelWidth(name);local lx=math.max(mx+6,math.min(x-tw/2,mx+mw-tw-8));local ly=y-7
    local found=false
    for _,dy in ipairs({0,-22,22,-44,44,-66,66,-88,88}) do
        for _,dx in ipairs({0,-tw*.55,tw*.55}) do
            local px=math.max(mx+6,math.min(x-tw/2+dx,mx+mw-tw-8));local py=y-7+dy
            local clear=py>my+4 and py+18<my+mh-28
            for _,b in ipairs(boxes) do if px-5<b[3] and px+tw+5>b[1] and py-3<b[4] and py+18>b[2] then clear=false end end
            if clear then lx=px;ly=py;found=true;break end
        end
        if found then break end
    end
    self:ink(name,lx,ly,nil,color)
    boxes[#boxes+1]={lx-5,ly-3,lx+tw+5,ly+18}
    return lx,ly,tw
end
function D:nameHit(hit,x,y)
    return hit.labelX and x>=hit.labelX-5 and x<=hit.labelX+hit.labelW+5 and y>=hit.labelY-3 and y<=hit.labelY+18
end
function D:onMouseDown(x,y)
    if self.showSettings then return ISPanel.onMouseDown(self,x,y) end
    for _,hit in ipairs(self.mapHits or {}) do
        if self:nameHit(hit,x,y) then
            self.cityIndex=hit.index
            local city=WR.SupplyLocations[hit.index]
            self.centerU,self.centerV=project(city.x,city.y);self.mapZoom=math.max(2.5,self.mapZoom or 1)
            self:sound();return true
        end
    end
    for _,hit in ipairs(self.stationHits or {}) do
        if math.abs(x-hit.x)<=12 and math.abs(y-hit.y)<=12 then
            self:regionSelect({region=hit.region.id});self:locateStation();self:sound();return true
        end
    end
    return ISPanel.onMouseDown(self,x,y)
end
function D:cityPosition(city)
    local x,y,w,h=self:layout();local u,v=project(city.x,city.y)
    local scale=math.min(w/22628,h/11314)*.9*(self.mapZoom or 1)
    return x+w/2+(u-(self.centerU or 0))*scale,y+h/2+(v-(self.centerV or 5656.85))*scale
end
function D:locateStation()
    local r=WR.cityRegion(WR.SupplyLocations[self.cityIndex or 1]);if not r then return end
    local s=((WR.ClientState or {}).regions or {})[r.id];local t=s and s.terminal or r
    self.centerU,self.centerV=project(t.x,t.y);self.mapZoom=2.5
end
function D:cityZoom() self.mapZoom=1;self.centerU=0;self.centerV=5656.85 end
function D:cityStep(button)
    self.cityIndex=((self.cityIndex or 1)-1+button.step)%#WR.SupplyLocations+1
    if (self.mapZoom or 1)>1 then
        local c=WR.SupplyLocations[self.cityIndex];self.centerU,self.centerV=project(c.x,c.y)
    end
end
function D:regionSelect(button)
    for i,c in ipairs(WR.SupplyLocations) do if WR.cityRegion(c).id==button.region then self.cityIndex=i;break end end
    if (self.mapZoom or 1)>1 then self:locateStation() end
end
function D:onMouseWheel(delta)
    if self.showSettings then return false end
    local x,y,w,h=self:layout();local mx,my=self:getMouseX(),self:getMouseY()
    if mx<x or mx>x+w or my<y or my>y+h then return false end
    local old=self.mapZoom or 1;local new=math.max(1,math.min(4,old*(1.2^(-delta))))
    local scale=math.min(w/22628,h/11314)*.9
    self.centerU=(self.centerU or 0)+(mx-x-w/2)/scale*(1/old-1/new)
    self.centerV=(self.centerV or 5656.85)+(my-y-h/2)/scale*(1/old-1/new)
    self.mapZoom=new
    if new==1 then self:cityZoom() end
    return true
end
function D:createChildren()
    ISPanel.createChildren(self)
    local sx=self.width-320
    self:button(sx,388,274,36,tr("LocateStation"),D.locateStation)
    self:button(sx,434,132,32,"< "..tr("Location"),D.cityStep).step=-1
    self:button(sx+142,434,132,32,tr("Location").." >",D.cityStep).step=1
    self:button(sx,476,274,32,tr("RegionView"),D.cityZoom)
    self.serviceButton=self:button(sx,522,274,36,tr("Service"),D.service)
    self:button(sx,568,274,32,tr("Diagnose"),D.refresh)
    self.brightnessButton=self:button(sx,self.height-130,132,28,tr("BrightnessShort"),D.setting)
    self.brightnessButton.setting="brightness"
    self.audioButton=self:button(sx+142,self.height-130,132,28,"AUDIO",D.setting)
    self.audioButton.setting="audio"
    self:button(sx,self.height-90,274,34,tr("Close"),D.close)
    self.regionButtons={}
    local _,_,mw=self:layout()
    for i,r in ipairs(WR.REGIONS) do
        local col=(i-1)%3;local row=math.floor((i-1)/3);local bw=(mw-16)/3
        local b=self:button(40+col*(bw+8),self.height-132+row*42,bw,34,string.format("%02d  ",i)..r.name,D.regionSelect)
        b.region=r.id;self.regionButtons[i]=b
    end
    self:initMapSettings()
end
function D:segment(x1,y1,x2,y2,c,thickness)
    local x,y,w,h=self:layout();local steps=math.max(1,math.ceil(math.max(math.abs(x2-x1),math.abs(y2-y1))/2))
    for i=0,steps do
        local px=x1+(x2-x1)*i/steps;local py=y1+(y2-y1)*i/steps
        if px>=x+2 and px<=x+w-4 and py>=y+2 and py<=y+h-4 then self:drawRect(px,py,thickness or 2,thickness or 2,1,c[1],c[2],c[3]) end
    end
end
function D:area(a,c,selected)
    local points={}
    for _,p in ipairs({{a[1],a[2]},{a[3],a[2]},{a[3],a[4]},{a[1],a[4]}}) do
        local x,y=self:cityPosition({x=p[1],y=p[2]});points[#points+1]={x,y}
    end
    local mx,my,mw,mh=self:layout()
    local low,high=math.huge,-math.huge
    for _,p in ipairs(points) do low=math.min(low,p[2]);high=math.max(high,p[2]) end
    for y=math.max(my+2,math.floor(low)),math.min(my+mh-2,math.ceil(high)),2 do
        local hits={}
        for i=1,4 do local p,q=points[i],points[i%4+1]
            if (p[2]<=y and q[2]>y) or (q[2]<=y and p[2]>y) then hits[#hits+1]=p[1]+(y-p[2])*(q[1]-p[1])/(q[2]-p[2]) end
        end
        table.sort(hits)
        if #hits>=2 then local left,right=math.max(mx+2,hits[1]),math.min(mx+mw-2,hits[#hits])
            if right>left then self:drawRect(left,y,right-left,2,selected and .40 or .20,c[1],c[2],c[3]) end
        end
    end
    for i=1,4 do local p,q=points[i],points[i%4+1];self:segment(p[1],p[2],q[1],q[2],c,selected and 3 or 2) end
end
function D:prerender()
    if not WR.Power.available(WR.ClientState or {}) then self:removeFromUIManager();return end
    ISPanel.prerender(self)
    local state=WR.ClientState or {};local day=state.serverDay or 0
    local selected=WR.SupplyLocations[self.cityIndex or 1];local region=WR.cityRegion(selected)
    local station=(state.regions or {})[region.id] or {};local health=WR.stationCondition(station,day)
    local supplied=WR.regionSupplied(state,region.id,day)
    local w,h=self.width,self.height;local sx=w-320;local mx,my,mw,mh=self:layout()
    self:drawRect(0,0,w,h,1,.16,.19,.18)
    self:drawRectBorder(5,5,w-10,h-10,1,.49,.53,.47)
    self:drawRect(15,15,w-30,48,1,.07,.09,.085)
    self:drawText(getText("IGUI_WR_Hardware_Label6"),32,28,.72,.78,.67,1,UIFont.Medium)
    self:drawText("RD-93 / TERMINAL 03",w-274,32,.58,.69,.59,1,UIFont.Small)
    if self:drawMapSettings() then return end
    self:monitorFrames()
    self:ink(tr("Atlas"),46,101,UIFont.Large)
    local online=0;for _,r in ipairs(WR.REGIONS) do if WR.regionSupplied(state,r.id,day) then online=online+1 end end
    self:ink(tr("RegionsOnline")..": "..online.." / 6",46,134)
    self:ink(string.format("ZOOM %.1fx  /  1x - 4x",self.mapZoom or 1),mx+mw-210,134)
    self:drawRect(mx,my,mw,mh,1,.025,.065,.061)
    for x=mx,mx+mw,28 do self:drawRect(x,my,1,mh,.35,.15,.29,.26) end
    for y=my,my+mh,28 do self:drawRect(mx,y,mw,1,.35,.15,.29,.26) end
    for i,r in ipairs(WR.REGIONS) do for _,a in ipairs(r.areas) do self:area(a,colors[i],r==region) end end
    self.mapHits={};self.stationHits={};local boxes={}
    for _,r in ipairs(WR.REGIONS) do
        local rs=(state.regions or {})[r.id];local x,y=self:cityPosition(rs and rs.terminal or r)
        if x>mx+12 and x<mx+mw-12 and y>my+18 and y<my+mh-18 then boxes[#boxes+1]={x-18,y-16,x+26,y+42} end
    end
    local px,py=self:cityPosition(WR.TARGETS.central)
    boxes[#boxes+1]={px-18,py-18,px+125,py+47}
    local order={self.cityIndex or 1};for i=1,#WR.SupplyLocations do if i~=(self.cityIndex or 1) then order[#order+1]=i end end
    for _,i in ipairs(order) do local c=WR.SupplyLocations[i];local x,y=self:cityPosition(c)
        if x>mx+12 and x<mx+mw-12 and y>my+16 and y<my+mh-16 then
            local active=i==(self.cityIndex or 1);local cr=WR.cityRegion(c);local on=WR.regionSupplied(state,cr.id,day)
            local color=active and {.99,.89,.55} or (on and {.62,.93,.77} or {.73,.78,.69})
            local lx,ly,tw=self:cityName(c,x,y,color,boxes)
            self.mapHits[#self.mapHits+1]={index=i,x=x,y=y,labelX=lx,labelY=ly,labelW=tw}
        end
    end
    for i,r in ipairs(WR.REGIONS) do local rs=(state.regions or {})[r.id];local x,y=self:cityPosition(rs and rs.terminal or r)
        if x>mx+12 and x<mx+mw-12 and y>my+18 and y<my+mh-18 then
            self:distributorIcon(x,y,i)
            self.stationHits[#self.stationHits+1]={region=r,x=x,y=y}
        end
    end
    if px>mx+18 and px<mx+mw-140 and py>my+18 and py<my+mh-35 then
        self:plantIcon(px,py);self:mapLabel(tr("PlantFeed"),px-12,py+22,{.92,.94,.78})
    end
    self:ink(tr("MapLegend"),mx+10,my+mh-24)
    self:ink(tr("SelectedRegion"),sx,105)
    self:ink(selected.name,sx,134,UIFont.Medium)
    self:ink(tr(supplied and "CityOnline" or "CityOffline"),sx,169,UIFont.Large,supplied and {.56,.9,.66} or {.96,.67,.36})
    local index=1;for i,r in ipairs(WR.REGIONS) do if r==region then index=i end end
    self:ink(string.format("D%02d / ",index)..tr("StationShort"),sx,213)
    self:ink(region.name,sx,237)
    local t=station.terminal or region
    self:ink("X "..t.x.." / Y "..t.y,sx,264)
    local status=not station.repaired and "Unfinished" or (not station.activated and "ReadyActivate" or (health<=0 and "Failed" or (health<=(self.preferences.threshold or 35) and "Warn" or "OK")))
    self:ink(tr(status).." / "..math.floor(health).."%",sx,291)
    self:drawRect(sx,318,274,8,1,.12,.18,.14)
    self:drawRect(sx,318,274*health/100,8,1,.51,.74,.46)
    self:ink(string.format("%.1f",health*WR.getRequirements().maintenanceDays/100).." "..tr("Days").." / "..tr("RemainingShort"),sx,337)
    for i,r in ipairs(WR.REGIONS) do local bx=40+((i-1)%3)*((mw-16)/3+8);local by=h-132+math.floor((i-1)/3)*42
        self:drawRect(bx,by-5,(mw-16)/3,3,1,colors[i][1],colors[i][2],colors[i][3])
    end
    self:drawText(tr("AtlasHint"),42,h-31,.65,.76,.64,1,UIFont.Small)
end
function D:update()
    ISPanel.update(self)
    local t=WR.TARGETS.panel3
    if self.player:getZ()~=t.z or (self.player:getX()-t.x)^2+(self.player:getY()-t.y)^2>9 then self:close();return end
    local now=getTimestampMs();if now-self.lastRefresh>2000 then self.lastRefresh=now;self:refresh() end
    if self.queuedAt and now-self.queuedAt>15000 then self.queuedAt=nil end
    self.brightnessButton:setTitle(tr("BrightnessShort").." "..math.floor(self.preferences.brightness*100).."%")
    self.audioButton:setTitle("AUDIO "..(tr(self.preferences.audio and "AudioOn" or "AudioOff")))
    local s=WR.ClientState or {};local q=WR.getRequirements();local inv=self.player:getInventory()
    self.serviceButton:setEnable(not self.queuedAt and s.wasActivated and s.manualRead and self:health(s,"panel3")<99.99
        and self.player:getPerkLevel(Perks.Electricity)>=q.electricity and self.player:getPerkLevel(Perks.Mechanics)>=q.mechanics
        and self.player:getPerkLevel(Perks.Strength)>=q.strength and inv:containsTypeRecurse("Screwdriver") and WR.countElectronicScrap(inv)>=q.maintenanceScrap)
end
function D.open(player)
    local state=WR.ClientState or {};local t=WR.TARGETS.panel3
    if not (state.panels or {}).panel3 or player:getZ()~=t.z or (player:getX()-t.x)^2+(player:getY()-t.y)^2>9 then return end
    if WR.PlantPanel.instance then WR.PlantPanel.instance:close() end
    local width=math.min(1360,getCore():getScreenWidth()-24);local height=math.min(820,getCore():getScreenHeight()-24)
    local p=D:new((getCore():getScreenWidth()-width)/2,(getCore():getScreenHeight()-height)/2,width,height)
    local md=player:getModData();md.WRConsolePreferences=md.WRConsolePreferences or {}
    md.WRConsolePreferences.panel3=md.WRConsolePreferences.panel3 or {brightness=1,threshold=35,audio=true}
    p.player=player;p.terminalId="panel3";p.tab="Network";p.preferences=md.WRConsolePreferences.panel3;p.lastRefresh=getTimestampMs()
    p.cityIndex=1;p.moveWithMouse=false;p:initialise();p:addToUIManager();WR.PlantPanel.instance=p;p:sound("boot");p:refresh();p:update()
end
