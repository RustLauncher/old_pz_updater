require "WaterRestoration/WR_Requirements"
require "WaterRestoration/WR_DistributionPanel"
require "WaterRestoration/WR_Regions"
WR.StationPanel=WR.DistributionPanel:derive("WRRegionalStationPanel")
local S=WR.StationPanel
local function tr(k) return getText("IGUI_WR_Console_"..k) end
local colors={{.78,.64,.28},{.25,.68,.68},{.62,.44,.72},{.43,.66,.32},{.34,.53,.80},{.78,.43,.32}}
local function project(x,y) return (x-y)*.70710678,(x+y)*.35355339 end
function S:layout() return 40,160,self.width-406,self.height-350 end
function S:resetMap()
    local region=WR.REGION_BY_ID[self.target.id]
    local minU,minV,maxU,maxV=math.huge,math.huge,-math.huge,-math.huge
    for _,a in ipairs(region.areas) do
        for _,point in ipairs({{a[1],a[2]},{a[3],a[2]},{a[3],a[4]},{a[1],a[4]}}) do
            local u,v=project(point[1],point[2]);minU=math.min(minU,u);minV=math.min(minV,v);maxU=math.max(maxU,u);maxV=math.max(maxV,v)
        end
    end
    local _,_,w,h=self:layout()
    self.localScale=math.min(w/(maxU-minU),h/(maxV-minV))*.8
    self.centerU=(minU+maxU)/2;self.centerV=(minV+maxV)/2;self.mapZoom=1
end
function S:cityPosition(city)
    local x,y,w,h=self:layout();local u,v=project(city.x,city.y)
    return x+w/2+(u-self.centerU)*self.localScale*(self.mapZoom or 1),y+h/2+(v-self.centerV)*self.localScale*(self.mapZoom or 1)
end
function S:onMouseWheel(delta)
    if self.showSettings then return false end
    local x,y,w,h=self:layout();local mx,my=self:getMouseX(),self:getMouseY()
    if mx<x or mx>x+w or my<y or my>y+h then return false end
    local old=self.mapZoom or 1;local zoom=math.max(1,math.min(4,old*1.2^(-delta)))
    self.centerU=self.centerU+(mx-x-w/2)/self.localScale*(1/old-1/zoom)
    self.centerV=self.centerV+(my-y-h/2)/self.localScale*(1/old-1/zoom)
    self.mapZoom=zoom;if zoom==1 then self:resetMap() end;return true
end
function S:onMouseDown(x,y)
    if self.showSettings then return ISPanel.onMouseDown(self,x,y) end
    for _,hit in ipairs(self.mapHits or {}) do
        if self:nameHit(hit,x,y) then
            self.selectedCity=hit.city.name;self.centerU,self.centerV=project(hit.city.x,hit.city.y)
            self.mapZoom=math.max(2.5,self.mapZoom or 1);self:sound();return true
        end
    end
    return ISPanel.onMouseDown(self,x,y)
end
function S:createChildren()
    ISPanel.createChildren(self)
    local sx=self.width-320
    self.repairButton=self:button(sx,382,274,38,tr("RepairStation"),S.repair)
    self.activateButton=self:button(sx,430,274,38,tr("ActivateStation"),S.activate)
    self.maintainButton=self:button(sx,478,274,38,tr("Service"),S.maintain)
    self:button(sx,536,274,32,tr("RegionView"),S.resetMap)
    self:button(sx,578,274,32,tr("Diagnose"),S.refresh)
    self:button(sx,self.height-90,274,34,tr("Close"),S.close)
    self:initMapSettings()
end
function S:queueStation(command)
    if self.queuedAt then return end
    if not WR.canMaterials(self.player,self.target,command) then
        self.player:Say(WR.requirementsText(self.player,self.target,command));return
    end
    if WR.queueInteraction(self.player,self.target,command,command=="repairStation" and 450 or 350) then self.queuedAt=getTimestampMs();self:close() end
end
function S:repair() self:queueStation("repairStation") end
function S:activate() self:queueStation("activateStation") end
function S:maintain() self:queueStation("maintainStation") end
function S:close() self:removeFromUIManager();if S.instance==self then S.instance=nil end end
function S:update()
    local t=self.target
    if self.player:getZ()~=t.z or (self.player:getX()-t.x)^2+(self.player:getY()-t.y)^2>9 then self:close();return end
    local stamp=getTimestampMs()
    if stamp-self.lastRefresh>2000 then self.lastRefresh=stamp;self:refresh() end
    if self.queuedAt and stamp-self.queuedAt>12000 then self.queuedAt=nil end
    local state=WR.ClientState or {};local station=(state.regions or {})[t.id] or {}
    local condition=WR.stationCondition(station,state.serverDay or 0)
    self.repairButton.tooltip=WR.requirementsText(self.player,self.target,"repairStation")
    self.maintainButton.tooltip=WR.requirementsText(self.player,self.target,"maintainStation")
    self.activateButton.tooltip=WR.requirementsText(self.player,self.target,"activateStation")
    local hasScrewdriver=self.player:getInventory():containsTypeRecurse("Screwdriver")
    self.repairButton:setEnable(WR.canMaterials(self.player,self.target,"repairStation") and not self.queuedAt and not station.repaired and state.manualRead and state.centralRepaired)
    self.activateButton:setEnable(not self.queuedAt and station.repaired and not station.activated and state.waterActive and state.manualRead)
    self.maintainButton:setEnable(WR.canMaterials(self.player,self.target,"maintainStation") and not self.queuedAt and station.activated and condition<99.99 and state.manualRead)
end

function S:prerender()
    local normal=(WR.ClientState or {}).originalService
    for _,b in ipairs({self.repairButton,self.activateButton,self.maintainButton}) do b:setVisible(not normal) end
    if not WR.Power.available(WR.ClientState or {}) then self:removeFromUIManager();return end
    ISPanel.prerender(self)
    local state=WR.ClientState or {};local region=WR.REGION_BY_ID[self.target.id]
    local station=(state.regions or {})[region.id] or {};local day=state.serverDay or 0
    local health=WR.stationCondition(station,day);local supplied=WR.regionSupplied(state,region.id,day)
    local w,h=self.width,self.height;local sx=w-320;local mx,my,mw,mh=self:layout()
    local index=1;for i,r in ipairs(WR.REGIONS) do if r==region then index=i end end
    local color=colors[index]
    self:drawRect(0,0,w,h,1,.16,.19,.18)
    self:drawRectBorder(5,5,w-10,h-10,1,.49,.53,.47)
    self:drawRect(15,15,w-30,48,1,.07,.09,.085)
    self:drawText(getText("IGUI_WR_Hardware_Label7"),32,28,.72,.78,.67,1,UIFont.Medium)
    self:drawText(string.format(getText("IGUI_WR_Hardware_Label8"),index),w-275,32,.58,.69,.59,1,UIFont.Small)
    if self:drawMapSettings() then return end
    self:monitorFrames()
    self:rounded(24,78,mw+32,h-144,20,1,.39,.45,.38)
    self:rounded(31,85,mw+18,h-158,16,1,.025,.045,.041)
    self:drawRect(42,96,4,44,1,color[1],color[2],color[3])
    self:ink(region.name,56,100,UIFont.Large)
    self:ink(tr("LocalServiceMap"),56,133)
    self:ink(string.format("ZOOM %.1fx",self.mapZoom or 1),mx+mw-100,133)
    self:drawRect(mx,my,mw,mh,1,.025,.065,.061)
    for x=mx,mx+mw,28 do self:drawRect(x,my,1,mh,.35,.15,.29,.26) end
    for y=my,my+mh,28 do self:drawRect(mx,y,mw,1,.35,.15,.29,.26) end
    for _,a in ipairs(region.areas) do self:area(a,color,true) end
    local stations=station.terminal or region;local tx,ty=self:cityPosition(stations)
    local boxes={};self.mapHits={}
    if tx>mx+12 and tx<mx+mw-12 and ty>my+18 and ty<my+mh-26 then
        self:distributorIcon(tx,ty,index)
        boxes[#boxes+1]={tx-18,ty-16,tx+26,ty+42}
    end
    for _,city in ipairs(WR.SupplyLocations) do
        if WR.cityRegion(city)==region then
            local x,y=self:cityPosition(city)
            if x>mx+12 and x<mx+mw-12 and y>my+18 and y<my+mh-30 then
                local active=self.selectedCity==city.name;local c=active and {.99,.91,.57} or {.72,.86,.76}
                local labelX,labelY,tw=self:cityName(city,x,y,c,boxes)
                self.mapHits[#self.mapHits+1]={city=city,x=x,y=y,labelX=labelX,labelY=labelY,labelW=tw}
            end
        end
    end
    if region.id=="south" then
        local x,y=self:cityPosition(WR.TARGETS.central)
        if x>mx+12 and x<mx+mw-120 and y>my+18 and y<my+mh-30 then
            self:plantIcon(x,y);self:mapLabel(tr("PlantFeed"),x+22,y-7,{.92,.94,.78})
        end
    end
    self:ink(tr("MapLegend"),mx+10,my+mh-23)
    self:ink(string.format("D%02d / ",index)..tr("StationShort"),sx,105)
    self:ink(tr(supplied and "CityOnline" or "CityOffline"),sx,140,UIFont.Large,supplied and {.56,.9,.66} or {.96,.67,.36})
    local status=not station.repaired and "Unfinished" or (not station.activated and "ReadyActivate" or (health<=0 and "Failed" or (health<=(self.preferences.threshold or 35) and "Warn" or "OK")))
    self:ink(tr(status),sx,183,UIFont.Medium)
    self:ink(tr("Integrity")..": "..math.floor(health).."%",sx,220)
    self:drawRect(sx,247,274,10,1,.12,.18,.14)
    self:drawRect(sx,247,274*health/100,10,1,color[1],color[2],color[3])
    self:ink(string.format("%.1f",health*WR.getRequirements().maintenanceDays/100).." "..tr("Days").." / "..tr("RemainingShort"),sx,274)
    self:ink(tr("PlantFeed")..": "..tr(state.waterActive and "On" or "Off"),sx,307)
    self:ink("X "..self.target.x.." / Y "..self.target.y.." / Z "..self.target.z,sx,337)
    self:drawRect(mx,h-178,mw,1,1,.27,.39,.32)
    for i=1,2 do
        local name=region.cities[i];local x=mx+(i-1)*(mw/2+4);local y=h-158
        self:ink(name,x+14,y,UIFont.Medium)
        self:ink(tr(supplied and "CityOnline" or "CityOffline"),x+14,y+28,nil,supplied and {.56,.9,.66} or {.96,.67,.36})
    end
    local q=WR.getRequirements()
    self:drawText(tr("RepairStation")..": "..q.stationScrap.." / "..tr("Service")..": "..q.maintenanceScrap.."  |  "..tr("LocalHint"),42,h-35,.65,.76,.64,1,UIFont.Small)
    if self.queuedAt then self:ink(tr("InProgress"),sx,625,nil,{.99,.8,.38}) end
end
function S.open(player,target)
    if not WR.REGION_BY_ID[target.id] then return end
    if S.instance then S.instance:close() end
    local width=math.min(1280,getCore():getScreenWidth()-24);local height=math.min(800,getCore():getScreenHeight()-24)
    local panel=S:new((getCore():getScreenWidth()-width)/2,(getCore():getScreenHeight()-height)/2,width,height)
    local md=player:getModData();md.WRConsolePreferences=md.WRConsolePreferences or {}
    local key="region_"..target.id;md.WRConsolePreferences[key]=md.WRConsolePreferences[key] or {brightness=1,threshold=35,audio=true}
    panel.player=player;panel.target=target;panel.preferences=md.WRConsolePreferences[key];panel.selectedCity=WR.REGION_BY_ID[target.id].cities[1]
    panel.lastRefresh=getTimestampMs();panel.moveWithMouse=false;panel:resetMap()
    panel:initialise();panel:addToUIManager();S.instance=panel;panel:sound("boot");panel:update()
end
