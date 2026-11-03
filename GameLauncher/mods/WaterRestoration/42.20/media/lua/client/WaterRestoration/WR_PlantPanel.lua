require "WaterRestoration/WR_PowerDisplay"
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "WaterRestoration/WR_Config"
require "WaterRestoration/WR_Regions"

WR.PlantPanel = ISPanel:derive("WRConsolePanel")
local Panel = WR.PlantPanel
local function tr(k) return getText("IGUI_WR_Console_" .. k) end
local function equipment(id) return getText("IGUI_WR_Plant_" .. id) end
local groups = {
    central = WR.ALL_IDS,
    panel1 = {"panel1", "roundValve1", "roundValve2", "roundValve3"},
    panel2 = {"panel2", "basinValve1", "basinValve2", "basinValve3", "basinValve4"},
    panel3 = {"panel3"},
}
local function isReady(state, id)
    return (id == "central" and state.centralRepaired) or (state.panels or {})[id] or (state.valves or {})[id]
end
local function allReady(state)
    for _, id in ipairs(WR.ALL_IDS) do
        if not isReady(state, id) then return false end
        if state.wasActivated and ((state.conditions or {})[id] or 0) <= 0 then return false end
    end
    return true
end

function Panel:close()
    self:removeFromUIManager()
    if Panel.instance == self then Panel.instance = nil end
end
function Panel:sound(kind)
    if self.preferences.audio then self.player:playSound(kind == "boot" and "WR_ConsoleBoot" or "WR_ConsoleButton") end
end
function Panel:refresh()
    if isClient() then sendClientCommand("WR", "requestState", {})
    elseif WR.Server then WR.Server.sendState(self.player) end
end
function Panel:diagnose()
    self.diagnosed = true
    self.tab = "Network"
    self:refresh()
end
function Panel:setTab(button)
    self.tab = button.tab
end
function Panel:queue(command)
    if self.queuedAt then return end
    if WR.queueInteraction(self.player,WR.TARGETS[self.terminalId],command,command=="maintain" and 400 or 300) then
        self.queuedAt=getTimestampMs()
    end
end
function Panel:connect()
    if self.terminalId ~= "central" then return end
    local state = WR.ClientState or {}
    if not allReady(state) then return end
    local command = state.waterActive and "resyncWater" or "activateWater"
    print("[WaterRestoration] physical supply switch pressed; command=" .. command)
    if isClient() then sendClientCommand("WR", command, {target="central"})
    elseif WR.Server then WR.Server.handleCommand(command, self.player, {target="central"}) end
    self:refresh()
end
function Panel:service() self:queue("maintain") end
function Panel:setting(button)
    if button.setting == "brightness" then
        self.preferences.brightness = self.preferences.brightness == 1 and 0.7 or 1
    elseif button.setting == "threshold" then
        local v = self.preferences.threshold
        self.preferences.threshold = v == 35 and 50 or (v == 50 and 65 or 35)
    else self.preferences.audio = not self.preferences.audio end
    if self.mapSettingButtons then self:syncMapSettings() end
end
function Panel:button(x, y, w, h, title, callback)
    local b = ISButton:new(x, y, w, h, title, self, callback)
    b.backgroundColor = {r=0.14,g=0.16,b=0.14,a=1}
    b.backgroundColorMouseOver = {r=0.27,g=0.31,b=0.24,a=1}
    b.borderColor = {r=0.40,g=0.43,b=0.36,a=1}
    b.textColor = {r=0.80,g=0.87,b=0.67,a=1}
    b.sounds = b.sounds or {}
    b.sounds.activate = "WR_ConsoleButton"
    b.onMouseUp = function(key, x, y)
        if not key:getIsVisible() then return end
        local process = key.pressed == true or key.allowMouseUpProcessing
        key.pressed = false
        if key.enable and process and key.onclick then
            key.target:sound()
            key.onclick(key.target, key, key.onClickArgs[1], key.onClickArgs[2], key.onClickArgs[3], key.onClickArgs[4])
        end
    end
    b.prerender = function(key)
        ISButton.prerender(key)
        local pressed = key.pressed == true
        local light, dark = pressed and .12 or .58, pressed and .58 or .10
        key:drawRect(1,1,key.width-2,2,1,light,light,light*.88)
        key:drawRect(1,1,2,key.height-2,1,light,light,light*.88)
        key:drawRect(2,key.height-4,key.width-4,3,1,dark,dark,dark*.88)
        key:drawRect(key.width-4,2,3,key.height-4,1,dark,dark,dark*.88)
        key:drawRectBorder(4,4,key.width-9,key.height-10,1,.24,.26,.21)
    end
    self.consoleButtons=self.consoleButtons or {};self.consoleButtons[#self.consoleButtons+1]=b
    b:initialise(); self:addChild(b)
    return b
end
function Panel:createChildren()
    ISPanel.createChildren(self)
    for i, tab in ipairs(self.terminalId=="central" and {"Overview", "Network", "Settings", "Power"} or {"Overview", "Network", "Settings"}) do
        local b = self:button(58+(i-1)*(self.terminalId=="central" and 149 or 199), 620, self.terminalId=="central" and 140 or 188, 34, "0"..i.."  "..tr(self.terminalId ~= "central" and (tab=="Overview" and "LocalCircuit" or (tab=="Network" and "Process" or tab)) or tab), Panel.setTab)
        b.tab = tab
    end
    self.diagnoseButton = self:button(738, 335, 190, 34, tr("Diagnose"), Panel.diagnose)
    self.serviceButton = self:button(738, 379, 190, 42, tr("Service"), Panel.service)
    if self.terminalId == "central" then
        self.connectButton = self:button(738, 435, 190, 48, tr("Connect"), Panel.connect)
    end
    self:button(738, 553, 190, 30, tr("Close"), Panel.close)
    self.cityButtons={}
    if self.terminalId=="panel3" then
        for i,step in ipairs({-1,1}) do
            local b=self:button(738,435+(i-1)*38,190,30,tr(step==-1 and "PrevCity" or "NextCity"),Panel.cityStep)
            b.step=step;self.cityButtons[#self.cityButtons+1]=b
        end
        self.cityButtons[#self.cityButtons+1]=self:button(738,511,190,30,tr("ZoomCity"),Panel.cityZoom)
        self.locateButton=self:button(738,219,190,30,tr("LocateStation"),Panel.locateStation)
    end
    self.settingButtons = {}
    for i, key in ipairs({"brightness", "threshold", "audio"}) do
        local b = self:button(738, 335+(i-1)*54, 190, 38, "", Panel.setting)
        b.setting = key; self.settingButtons[i] = b
    end
end
function Panel:rounded(x,y,w,h,r,a,red,green,blue)
    self:drawRect(x+r,y,w-2*r,h,a,red,green,blue)
    self:drawRect(x,y+r,r,h-2*r,a,red,green,blue)
    self:drawRect(x+w-r,y+r,r,h-2*r,a,red,green,blue)
    for row=0,r-1 do
        local inset=math.ceil(r-math.sqrt(r*r-(r-row-.5)*(r-row-.5)))
        self:drawRect(x+inset,y+row,r-inset,1,a,red,green,blue)
        self:drawRect(x+w-r,y+row,r-inset,1,a,red,green,blue)
        self:drawRect(x+inset,y+h-row-1,r-inset,1,a,red,green,blue)
        self:drawRect(x+w-r,y+h-row-1,r-inset,1,a,red,green,blue)
    end
end

function Panel:ink(text, x, y, font, color)
    local b = self.preferences.brightness
    local c = color or {0.59, 0.83, 0.43}
    self:drawText(text, x, y, c[1]*b, c[2]*b, c[3]*b, 1, font or UIFont.Small)
end
function Panel:health(state,id)
    return (state.conditions or {})[id] or 0
end
function Panel:drawCentralDashboard(state)
    local t=getTimestampMs()/1000;local on=state.waterActive
    local green={.59,.83,.43};local cyan={.40,.78,.75}
    self:ink(getText("IGUI_WR_DashboardTitle"),66,195,UIFont.Medium)
    self:ink(getText(on and "IGUI_WR_FlowActive" or "IGUI_WR_FlowStopped"),66,222,nil,on and cyan or {.9,.65,.35})
    local ids={"central","panel1","panel2","panel3"}
    local titles={"CTRL","FILTER","TREAT","DIST"}
    for i,id in ipairs(ids) do
        local x=66+(i-1)*155;local health=self:health(state,id)
        self:rounded(x,252,138,85,8,1,.07,.13,.10)
        self:drawRectBorder(x+5,257,128,75,1,.24,.39,.28)
        self:ink(string.format("%02d / %s",i,titles[i]),x+12,264)
        self:ink(math.floor(health).."%",x+12,287,UIFont.Large)
        self:drawRect(x+12,320,112,4,1,.12,.19,.14)
        self:drawRect(x+12,320,112*health/100,4,1,green[1],green[2],green[3])
        if i<4 then
            self:drawRect(x+138,289,17,5,1,.24,.39,.28)
            if on then self:drawRect(x+139+(t*14)%11,289,5,5,1,cyan[1],cyan[2],cyan[3]) end
        end
    end
    self:ink(getText("IGUI_WR_FlowDiagram"),66,343)
    self:drawRect(66,365,602,3,1,.16,.29,.23)
    for i=0,59 do
        local wave=on and math.sin(i*.3-t*3)*8+math.sin(i*.7-t*2)*3 or 0
        self:drawRect(67+i*10,365+wave,4,3,1,cyan[1],cyan[2],cyan[3])
    end
    self:ink(tr("Equipment"),66,386);self:ink(tr("Integrity"),389,386);self:ink(tr("Health"),540,386)
    self.centralRows={}
    for i,id in ipairs(WR.ALL_IDS) do
        local y=410+(i-1)*18;local health=self:health(state,id);local ready=isReady(state,id)
        if self.selectedId==id then self:drawRect(62,y-1,610,18,.7,.12,.24,.17) end
        self:ink(equipment(id),66,y)
        self:drawRect(390,y+4,80,5,1,.10,.16,.08)
        self:drawRect(390,y+4,80*health/100,5,1,green[1],green[2],green[3])
        self:ink(math.floor(health).."%",482,y)
        self:ink(tr(not ready and "Unfinished" or (health<=0 and "Failed" or "OK")),540,y)
        self.centralRows[#self.centralRows+1]={id=id,y=y}
    end
    -- A running scan indicator is a local display animation, not measured pressure.
    self:drawRect(663,195,5,8,1,on and (.55+.25*math.sin(t*4)) or .35,.65,.40)
end
function Panel:drawEquipment(state)
    if self.terminalId=="central" then self:drawCentralDashboard(state);return end
    self:ink(tr("Equipment"), 66, 200)
    self:ink(tr("Integrity"), 389, 200)
    self:ink(tr("Health"), 540, 200)
    for i,id in ipairs(groups[self.terminalId]) do
        local y = 229+(i-1)*26
        local h = self:health(state,id)
        local ready = isReady(state,id)
        local status = not ready and "Unfinished" or (h<=0 and "Failed" or (h<=self.preferences.threshold and "Warn" or "OK"))
        local color = h<=self.preferences.threshold and {0.96,0.66,0.26} or {0.59,0.83,0.43}
        if self.selectedId==id then self:drawRect(60,y-2,620,24,0.8,0.14,0.22,0.10) end
        self:ink(equipment(id),66,y,nil,color)
        self:drawRect(390,y+6,80,7,1,0.10,0.16,0.08)
        self:drawRect(390,y+6,80*h/100,7,1,color[1]*.8,color[2]*.8,color[3]*.8)
        self:ink(tostring(math.floor(h)).."%",482,y,nil,color)
        self:ink(tr(status),540,y,nil,color)
    end
    if self.selectedId then
        local target=WR.TARGETS[self.selectedId]
        self:ink(tr("Position")..": "..target.x..", "..target.y..", Z="..target.z,66,527)
    else self:ink(tr("Select"),66,527) end
end
function Panel:block(x,y,w,label,ready)
    self:drawRect(x,y,w,52,1,0.07,0.12,0.055)
    self:drawRectBorder(x,y,w,52,1,ready and 0.38 or 0.6,ready and 0.60 or 0.32,0.22)
    self:ink(label,x+10,y+8)
    self:ink(tr(ready and "OK" or "Unfinished"),x+10,y+28)
end
function Panel:drawNetwork(state)
    if self.terminalId~="central" then self:drawProcess(state);return end
    local t=getTimestampMs()/1000;local on=state.waterActive
    self:ink(tr("Network").." / WT-93",66,198,UIFont.Medium)
    local labels={getText("IGUI_WR_Hardware_Label1"),getText("IGUI_WR_Hardware_Label2"),getText("IGUI_WR_Hardware_Label3"),getText("IGUI_WR_Hardware_Label4")}
    local ids={"central","panel1","panel2","panel3"}
    for i,id in ipairs(ids) do
        local x=66+(i-1)*155;local ready=isReady(state,id)
        self:block(x,240,138,labels[i],ready)
        self:ink(math.floor(self:health(state,id)).."%",x+10,302)
        if i<4 then
            self:drawRect(x+138,264,17,4,1,.22,.40,.29)
            if on then self:drawRect(x+138+(t*12)%12,264,5,4,1,.4,.85,.72) end
        end
    end
    self:ink(tr("RegionsOnline"),66,345,UIFont.Medium)
    local day=state.serverDay or 0
    for i,r in ipairs(WR.REGIONS) do
        local x=66+((i-1)%2)*305;local y=378+math.floor((i-1)/2)*62
        local supplied=WR.regionSupplied(state,r.id,day)
        self:rounded(x,y,290,51,7,1,.055,.105,.08)
        self:rounded(x+10,y+16,12,12,6,1,supplied and .35 or .65,supplied and .85 or .38,.32)
        self:ink(r.name,x+32,y+7)
        self:ink(tr(supplied and "CityOnline" or "CityOffline"),x+32,y+28,nil,supplied and {.45,.87,.67} or {.88,.63,.35})
    end
    self:ink(tr("Maintenance").." / "..WR.getRequirements().maintenanceDays.." "..tr("Days"),66,579)
end
function Panel:drawProcess(state)
    local ids=groups[self.terminalId]
    local warnings,pending=0,0
    for _,id in ipairs(ids) do
        if not isReady(state,id) then pending=pending+1
        elseif self:health(state,id)<=self.preferences.threshold then warnings=warnings+1 end
    end
    if self.terminalId~="panel3" then self:ink(tr(self.terminalId),66,201,UIFont.Medium) end
    if self.terminalId=="panel1" then
        for i=1,3 do
            local id="roundValve"..i;local x=93+(i-1)*190
            self:rounded(x,247,100,100,50,1,.09,.17,.075)
            self:ink("T-0"..i,x+30,267)
            self:ink(tostring(math.floor(self:health(state,id))).."%",x+30,295)
            self:ink(tr((state.valves or {})[id] and "ValveOpen" or "ValveClosed"),x+12,364)
        end
        self:ink(tr("FiltrationInfo"),66,408)
    elseif self.terminalId=="panel2" then
        for i=1,4 do
            local id="basinValve"..i;local x=78+(i-1)*148
            self:drawRect(x,250,130,90,1,.07,.14,.055)
            self:drawRectBorder(x,250,130,90,1,.35,.55,.23)
            self:ink("P-0"..i,x+45,267)
            self:ink(tostring(math.floor(self:health(state,id))).."%",x+45,297)
            self:ink(tr((state.valves or {})[id] and "ValveOpen" or "ValveClosed"),x+24,364)
        end
        self:ink(tr("TreatmentInfo"),66,408)
    else
        self:drawMunicipalMap(state)
        return
    end
    self:ink(tr("LocalPending")..": "..pending,66,448)
    self:ink(tr("LocalWarning")..": "..warnings,350,448)
    self:ink(tr("TerminalHealth")..": "..math.floor(self:health(state,self.terminalId)).."%",66,482)
    self:ink(tr("LocalOnly"),66,527)
end


function Panel:cityStep(button)
    self.cityIndex=((self.cityIndex or 1)-1+button.step)%#WR.SupplyLocations+1
    if (self.mapZoom or 1)>1 then
        local city=WR.SupplyLocations[self.cityIndex]
        self.mapCenterX=87+city.x*.039;self.mapCenterY=245+city.y*.012
    end
    self:sound()
end
function Panel:cityZoom()
    if (self.mapZoom or 1)>1 then
        self.mapZoom=1;self.mapCenterX=371.5;self.mapCenterY=337.5
    else
        local city=WR.SupplyLocations[self.cityIndex or 1]
        self.mapZoom=2;self.mapCenterX=87+city.x*.039;self.mapCenterY=245+city.y*.012
    end
end
function Panel:cityPosition(city)
    local zoom=self.mapZoom or 1
    return 371.5+(87+city.x*.039-(self.mapCenterX or 371.5))*zoom,
           337.5+(245+city.y*.012-(self.mapCenterY or 337.5))*zoom
end
function Panel:onMouseWheel(delta)
    if self.terminalId~="panel3" or self.tab~="Network" then return false end
    local x,y=self:getMouseX(),self:getMouseY()
    if x<62 or x>681 or y<232 or y>443 then return false end
    local old=self.mapZoom or 1
    local zoom=math.max(1,math.min(4,old*(1.2^(-delta))))
    self.mapCenterX=(self.mapCenterX or 371.5)+(x-371.5)*(1/old-1/zoom)
    self.mapCenterY=(self.mapCenterY or 337.5)+(y-337.5)*(1/old-1/zoom)
    self.mapZoom=zoom
    if zoom==1 then self.mapCenterX=371.5;self.mapCenterY=337.5 end
    return true
end
function Panel:locateStation()
    local r=WR.cityRegion(WR.SupplyLocations[self.cityIndex or 1])
    if not r then return end
    local station=((WR.ClientState or {}).regions or {})[r.id]
    local t=station and station.terminal or r
    self.mapCenterX=87+t.x*.039;self.mapCenterY=245+t.y*.012;self.mapZoom=3
end
function Panel:mapSegment(x1,y1,x2,y2,color)
    local steps=math.max(1,math.ceil(math.max(math.abs(x2-x1),math.abs(y2-y1))/3))
    for i=0,steps do
        local x=x1+(x2-x1)*i/steps;local y=y1+(y2-y1)*i/steps
        if x>=63 and x<=677 and y>=233 and y<=439 then self:drawRect(x,y,2,2,1,color[1],color[2],color[3]) end
    end
end
function Panel:drawMunicipalMap(state)
    local selected=WR.SupplyLocations[self.cityIndex or 1]
    local region=WR.cityRegion(selected)
    local day=state.serverDay or 0
    self:ink(tr("RegionalMap").." / 6",66,201,UIFont.Medium)
    self:drawRect(62,232,619,211,1,.035,.075,.047)
    for x=64,680,24 do self:drawRect(x,233,1,208,.35,.16,.28,.17) end
    for y=233,442,24 do self:drawRect(63,y,616,1,.35,.16,.28,.17) end
    -- Render the same exact areas used by the supply backend, clipped to the CRT.
    for _,r in ipairs(WR.REGIONS) do for _,a in ipairs(r.areas) do
        local x1,y1=self:cityPosition({x=a[1],y=a[2]});local x2,y2=self:cityPosition({x=a[3],y=a[4]})
        if region==r then
            local left,top=math.max(63,x1),math.max(233,y1)
            local right,bottom=math.min(679,x2),math.min(441,y2)
            if right>left and bottom>top then self:drawRect(left,top,right-left,bottom-top,.32,.20,.36,.15) end
        end
        local c=region==r and {.78,.72,.35} or {.19,.39,.32}
        self:mapSegment(x1,y1,x2,y1,c);self:mapSegment(x2,y1,x2,y2,c)
        self:mapSegment(x2,y2,x1,y2,c);self:mapSegment(x1,y2,x1,y1,c)
    end end
    self:ink(string.format("ZOOM %.1fx",self.mapZoom or 1),76,237)
    self:ink("N ^",641,239)
    self.mapHits={};local labels={}
    -- Selected name gets priority; nearby names wait until zoom gives them room.
    local order={self.cityIndex or 1}
    for i=1,#WR.SupplyLocations do if i~=(self.cityIndex or 1) then order[#order+1]=i end end
    for _,i in ipairs(order) do
        local city=WR.SupplyLocations[i];local x,y=self:cityPosition(city)
        if x>=76 and x<=660 and y>=252 and y<=422 then
            local active=i==(self.cityIndex or 1);local cr=WR.cityRegion(city)
            local supplied=cr and WR.regionSupplied(state,cr.id,day)
            local c=active and {.95,.84,.37} or (supplied and {.42,.85,.62} or {.76,.44,.26})
            self:drawRect(x-3,y-3,7,7,1,c[1],c[2],c[3])
            if active then self:drawRectBorder(x-7,y-7,15,15,1,c[1],c[2],c[3]) end
            local label=city.name:gsub(" Trailer Park","")
            local lx=math.min(x+10,675-#label*7);local ly=y-6;local width=#label*7
            local clear=true
            for _,box in ipairs(labels) do if lx<box[3] and lx+width>box[1] and ly<box[4] and ly+16>box[2] then clear=false end end
            if active or clear then self:ink(label,lx,ly,nil,c);labels[#labels+1]={lx,ly,lx+width,ly+16} end
            self.mapHits[#self.mapHits+1]={index=i,x=x,y=y}
        end
    end
    self.stationHits={}
    for _,r in ipairs(WR.REGIONS) do
        local rs=(state.regions or {})[r.id]
        local x,y=self:cityPosition(rs and rs.terminal or r)
        if x>=76 and x<=660 and y>=252 and y<=422 then
            local c=region==r and {.96,.86,.43} or {.48,.74,.84}
            self:drawRectBorder(x-5,y-5,11,11,1,c[1],c[2],c[3]);self:drawRect(x-1,y-8,2,17,1,c[1],c[2],c[3])
            self.stationHits[#self.stationHits+1]={region=r,x=x,y=y}
        end
    end
    local station=region and (state.regions or {})[region.id] or nil
    local health=WR.stationCondition(station,day)
    local supplied=region and WR.regionSupplied(state,region.id,day)
    self:ink(selected.name.." / "..tr(supplied and "CityOnline" or "CityOffline"),66,455,UIFont.Medium)
    if region then
        self:ink(tr("Station").." "..region.name,66,485)
        local t=station and station.terminal or region
        self:ink("X "..t.x.." / Y "..t.y.."  ["..(station and station.terminal and ("Z "..t.z) or tr("Reference")).."]",66,508)
        local status=(not station or not station.repaired) and "Unfinished" or (not station.activated and "ReadyActivate" or (health<=0 and "Failed" or "OK"))
        if type(status)~="string" then status="Unfinished" end
        self:ink(tr("StationStatus")..": "..tr(status).." / "..math.floor(health).."%",66,532)
        self:ink(tr("Remaining")..": "..string.format("%.1f",health*WR.getRequirements().maintenanceDays/100).." "..tr("Days"),66,554)
    end
    self:ink(tr("RegionalHint"),66,579)
end

function Panel:drawSettings(x,y,w)
    x=x or 66;y=y or 198;w=w or 602
    self:ink(tr("Settings").." / WT-93",x,y,UIFont.Medium)
    local values={math.floor(self.preferences.brightness*100).."%",self.preferences.threshold.."%",tr(self.preferences.audio and "Enabled" or "Disabled")}
    for i,key in ipairs({"Brightness","Threshold","Audio"}) do
        local cy=y+40+(i-1)*92
        self:rounded(x,cy,w,80,9,1,.055,.105,.08)
        self:ink(string.format("%02d / ",i)..tr(key),x+16,cy+12,UIFont.Medium)
        self:ink(values[i],x+w-188,cy+12,UIFont.Medium)
        local value=i==1 and self.preferences.brightness or (i==2 and self.preferences.threshold/100 or (self.preferences.audio and 1 or 0))
        local step=(w-48)/24
        for n=1,24 do
            local lit=n/24<=value
            self:drawRect(x+17+(n-1)*step,cy+49,step-5,14,1,lit and .43 or .10,lit and .73 or .18,lit and .42 or .13)
        end
    end
    self:drawRect(x,y+337,w,1,1,.23,.38,.27)
    self:ink(tr("Local"),x+10,y+351)
    self:ink(tr("Cycle")..": "..WR.getRequirements().maintenanceDays.." "..tr("Days"),x+10,y+378)
end
function Panel:initMapSettings()
    self.preferences.threshold=self.preferences.threshold or 35
    local sx=self.width-320
    self.mapSettingButtons={}
    self.settingsToggle=self:button(sx,620,274,32,tr("Settings"),Panel.toggleMapSettings)
    for i,key in ipairs({"brightness","threshold","audio"}) do
        local b=self:button(sx,388+(i-1)*54,274,38,"",Panel.setting)
        b.setting=key;self.mapSettingButtons[i]=b
    end
    self:syncMapSettings()
end
function Panel:toggleMapSettings()
    self.showSettings=not self.showSettings;self:syncMapSettings()
end
function Panel:syncMapSettings()
    local settings=self.showSettings==true
    for _,b in ipairs(self.consoleButtons or {}) do
        local keep=b==self.settingsToggle or b.onclick==self.close
        for _,key in ipairs(self.mapSettingButtons or {}) do if b==key then keep=true end end
        if not keep then b:setVisible(not settings) end
    end
    for _,b in ipairs(self.mapSettingButtons or {}) do b:setVisible(settings) end
    if self.brightnessButton then self.brightnessButton:setVisible(false) end
    if self.audioButton then self.audioButton:setVisible(false) end
    self.settingsToggle:setTitle(tr(settings and "Network" or "Settings"))
    self.mapSettingButtons[1]:setTitle(tr("BrightnessShort").." "..math.floor(self.preferences.brightness*100).."%")
    self.mapSettingButtons[2]:setTitle(tr("ThresholdShort").." "..self.preferences.threshold.."%")
    self.mapSettingButtons[3]:setTitle("AUDIO "..(tr(self.preferences.audio and "Enabled" or "Disabled")))
end
function Panel:drawMapSettings()
    if not self.showSettings then return false end
    self:syncMapSettings();self:monitorFrames()
    local mx,my,mw=self:layout()
    self:drawSettings(mx+16,108,mw-32)
    self:ink(tr("Settings"),self.width-320,110,UIFont.Medium)
    self:ink(tr("BrightnessShort")..": "..math.floor(self.preferences.brightness*100).."%",self.width-320,151)
    self:ink(tr("ThresholdShort")..": "..self.preferences.threshold.."%",self.width-320,181)
    self:ink("AUDIO: "..(tr(self.preferences.audio and "Enabled" or "Disabled")),self.width-320,211)
    return true
end
function Panel:prerender()
    if not WR.Power.available(WR.ClientState or {}) then self:removeFromUIManager();return end
    ISPanel.prerender(self)
    local state=WR.ClientState or {}
    -- Steel cabinet, raised bezel, screw slots and a recessed green CRT.
    self:drawRect(4,4,972,752,1,.27,.29,.27)
    self:drawRect(10,10,960,740,1,.35,.36,.32)
    self:drawRect(16,16,948,728,1,.25,.27,.24)
    self:drawRect(27,25,926,32,1,.11,.12,.10)
    self:drawText(getText("IGUI_WR_Hardware_Label5"),43,32,.75,.76,.64,1,UIFont.Small)
    self:drawText("WT-93  /  "..string.upper(self.terminalId),755,32,.65,.66,.55,1,UIFont.Small)
    for _,x in ipairs({20,953}) do for _,y in ipairs({17,731}) do
        self:drawRect(x,y,8,8,1,.12,.13,.11);self:drawRect(x+1,y+3,6,1,1,.5,.5,.43)
    end end
    self:rounded(32,66,674,548,26,1,.10,.11,.09)
    self:rounded(36,70,666,540,23,1,.45,.48,.38)
    self:rounded(40,74,658,532,20,1,.07,.085,.055)
    self:rounded(44,78,650,524,18,1,.025,.045,.024)
    for y=96,584,4 do self:drawRect(47,y,644,1,.12,.0,.01,.0) end
    self:ink(tr("Monitor").."  /  "..tr(self.terminalId=="central" and "Main" or self.terminalId),58,91)
    local status=state.waterActive and "On" or "Off"
    local remaining=state.wasActivated and (state.remainingDays or 0) or WR.getRequirements().maintenanceDays
    if self.terminalId~="central" then
        local health,ready=100,true
        for _,id in ipairs(groups[self.terminalId]) do
            health=math.min(health,self:health(state,id))
            if not isReady(state,id) or self:health(state,id)<=0 then ready=false end
        end
        status=ready and "CircuitReady" or "CircuitPending"
        remaining=health*WR.getRequirements().maintenanceDays/100
    end
    self:ink(state.originalService and getText("IGUI_WR_PhaseNormal") or (not state.wasActivated and getText("IGUI_WR_PhaseInterrupted") or tr(status)),58,116,UIFont.Medium)
    local days=string.format("%.1f",remaining)
    self:ink(state.originalService and getText("IGUI_WR_PhaseReadOnly") or (tr(self.terminalId=="central" and "Remaining" or "CircuitRemaining")..": "..days.." "..tr("Days")),58,145)
    self:drawRect(58,180,622,1,1,.24,.36,.18)
    if self.tab=="Overview" then self:drawEquipment(state)
    elseif self.tab=="Network" then self:drawNetwork(state)
    elseif self.tab=="Power" then WR.drawPowerDisplay(self,state,66,210,602,true)
    else self:drawSettings() end
    -- Cabinet lamps and service meter are actual state indicators.
    for i,key in ipairs({"Power","Link","Mains"}) do
        local on=i==1 and WR.Power.available(state) or (i==2 and state.centralRepaired) or (i==3 and state.waterActive)
        local y=87+(i-1)*53
        self:drawRect(736,y,14,14,1,on and .35 or .45,on and .70 or .18,.12)
        self:drawText(tr(key),758,y,.79,.80,.67,1,UIFont.Small)
    end
    self:drawText(tr("Integrity"),738,248,.76,.77,.65,1,UIFont.Small)
    local health=self:health(state,self.terminalId)
    self:drawRect(738,276,190,18,1,.10,.11,.08)
    self:drawRect(740,278,186*health/100,14,1,.50,.60,.30)
    self:drawText(tostring(math.floor(health)).."%",810,300,.79,.80,.67,1,UIFont.Small)
    if self.terminalId~="panel3" or self.tab~="Network" then self:drawText(tr("Device")..": "..string.upper(self.terminalId),738,504,.74,.75,.62,1,UIFont.Small) end
    -- Keyboard and ventilation below the CRT. Function keys above are clickable.
    self:drawRect(40,661,663,63,1,.13,.14,.12)
    for row=0,2 do for col=0,15 do
        self:drawRect(52+col*39,670+row*18,33,13,1,.36,.37,.31)
        self:drawRect(53+col*39,671+row*18,31,1,1,.50,.51,.44)
    end end
    for y=635,702,9 do self:drawRect(743,y,180,3,1,.09,.10,.08) end
    if self.queuedAt then self:drawText(tr("InProgress"),45,726,.98,.77,.35,1,UIFont.Small) end
end
function Panel:onMouseDown(x,y)
    if self.terminalId=="panel3" and self.tab=="Network" then
        for _,hit in ipairs(self.stationHits or {}) do
            if math.abs(x-hit.x)<=9 and math.abs(y-hit.y)<=9 then
                for i,c in ipairs(WR.SupplyLocations) do if WR.cityRegion(c)==hit.region then self.cityIndex=i;break end end
                self:sound();return true
            end
        end
        for _,hit in ipairs(self.mapHits or {}) do
            if math.abs(x-hit.x)<=10 and math.abs(y-hit.y)<=10 then
                self.cityIndex=hit.index;self:sound();return true
            end
        end
    end
    if self.tab=="Overview" and self.terminalId=="central" and x>=60 and x<=680 then
        for _,row in ipairs(self.centralRows or {}) do if y>=row.y-1 and y<row.y+17 then self.selectedId=row.id;return true end end
        return ISPanel.onMouseDown(self,x,y)
    end
    if self.tab=="Overview" and x>=60 and x<=680 and y>=227 then
        local index=math.floor((y-227)/26)+1
        local id=groups[self.terminalId][index]
        if id then self.selectedId=id;return true end
    end
    return ISPanel.onMouseDown(self,x,y)
end
function Panel:update()
    ISPanel.update(self)
    local target=WR.TARGETS[self.terminalId]
    local dx,dy=self.player:getX()-target.x,self.player:getY()-target.y
    if self.player:getZ()~=target.z or dx*dx+dy*dy>9 then self:close();return end
    local stamp=getTimestampMs()
    if self.queuedAt and stamp-self.queuedAt>15000 then self.queuedAt=nil end
    if stamp-self.lastRefresh>2000 then self.lastRefresh=stamp;self:refresh() end
    local state=WR.ClientState or {}
    if self.connectButton then
        self.connectButton:setTitle(tr(state.waterActive and "Reconnect" or "Connect"))
        self.connectButton:setEnable(not self.queuedAt and allReady(state))
    end
    local req=WR.getRequirements()
    local inv=self.player:getInventory()
    local canService=self.player:getPerkLevel(Perks.Electricity)>=req.electricity
        and self.player:getPerkLevel(Perks.Mechanics)>=req.mechanics
        and self.player:getPerkLevel(Perks.Strength)>=req.strength
        and inv:containsTypeRecurse("Screwdriver") and WR.countElectronicScrap(inv)>=req.maintenanceScrap
    self.serviceButton:setEnable(not self.queuedAt and canService and state.wasActivated==true and self:health(state,self.terminalId)<99.99 and state.manualRead==true)
    for _,b in ipairs(self.cityButtons or {}) do b:setVisible(self.tab=="Network") end
    if self.locateButton then self.locateButton:setVisible(self.tab=="Network") end
    local settings=self.tab=="Settings"
    self.diagnoseButton:setVisible(not settings)
    self.serviceButton:setVisible(not settings and not state.originalService)
    if self.connectButton then self.connectButton:setVisible(not settings and not state.originalService) end
    for _,b in ipairs(self.settingButtons) do b:setVisible(settings) end
    self.settingButtons[1]:setTitle(tr("BrightnessShort").." "..tostring(math.floor(self.preferences.brightness*100)).."%")
    self.settingButtons[2]:setTitle(tr("ThresholdShort").." "..tostring(self.preferences.threshold).."%")
    self.settingButtons[3]:setTitle("AUDIO  "..(tr(self.preferences.audio and "Enabled" or "Disabled")))
end
function Panel.open(player,terminalId)
    terminalId=terminalId or "central"
    if terminalId=="panel3" then
        require "WaterRestoration/WR_DistributionPanel"
        return WR.DistributionPanel.open(player)
    end
    if not groups[terminalId] then return end
    local state=WR.ClientState or {}
    if not isReady(state,terminalId) then return end
    local target=WR.TARGETS[terminalId]
    local dx,dy=player:getX()-target.x,player:getY()-target.y
    if player:getZ()~=target.z or dx*dx+dy*dy>9 then return end
    if Panel.instance then Panel.instance:close() end
    local data=player:getModData()
    data.WRConsolePreferences=data.WRConsolePreferences or {}
    data.WRConsolePreferences[terminalId]=data.WRConsolePreferences[terminalId] or {brightness=1,threshold=35,audio=true}
    local panel=Panel:new(math.max(0,(getCore():getScreenWidth()-980)/2),math.max(0,(getCore():getScreenHeight()-760)/2),980,760)
    panel.player=player;panel.terminalId=terminalId;panel.preferences=data.WRConsolePreferences[terminalId]
    panel.tab="Overview";panel.moveWithMouse=true;panel.lastRefresh=getTimestampMs()
    panel.backgroundColor={r=.08,g=.09,b=.07,a=1};panel.borderColor={r=.05,g=.06,b=.04,a=1}
    panel:initialise();panel:addToUIManager();Panel.instance=panel
    panel:sound("boot");panel:refresh();panel:update()
end
