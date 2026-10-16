require "WaterRestoration/WR_PowerDisplay"
require "WaterRestoration/WR_Power"
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "WaterRestoration/WR_Laptop"
require "WaterRestoration/WR_Regions"
local L=WR.Laptop
L.Panel=ISPanel:derive("WRMilitaryLaptopPanel")
local P=L.Panel
local green={.5,.82,.55};local amber={.95,.72,.3}
-- Keep Calfer coordinates independent of the surrounding physical case.
function P:drawRect(x,y,w,h,a,r,g,b)
 ISPanel.drawRect(self,self.displayX+x*self.displayScale,self.displayY+y*self.displayScale,w*self.displayScale,h*self.displayScale,a,r,g,b)
end
function P:drawRectBorder(x,y,w,h,a,r,g,b)
 ISPanel.drawRectBorder(self,self.displayX+x*self.displayScale,self.displayY+y*self.displayScale,w*self.displayScale,h*self.displayScale,a,r,g,b)
end
function P:drawText(text,x,y,r,g,b,a,font)
 ISPanel.drawText(self,text,self.displayX+x*self.displayScale,self.displayY+y*self.displayScale,r,g,b,a,font)
end
function P:drawHousing(powered)
 local w,h=self.width,self.height
 -- Clip the metal and rubber to four 44-pixel diagonal corner cuts.
 -- Draw only the corner strips by scanline; the middle remains one rectangle.
 local function rect(x,y,rw,rh,r,g,b)
  local cut=44;local top=14;local bottom=h-12
  local function strip(py,ph)
   local inset=math.max(0,cut-(py-top),cut-(bottom-py-1))
   local left=math.max(x,12+inset);local right=math.min(x+rw,w-12-inset)
   if right>left then ISPanel.drawRect(self,left,py,right-left,ph,1,r,g,b) end
  end
  local first=math.max(y,top);local last=math.min(y+rh,bottom)
  if last<=first then return end
  if x>=12+cut and x+rw<=w-12-cut then
   ISPanel.drawRect(self,x,first,rw,last-first,1,r,g,b);return
  end
  local upper=math.min(last,top+cut)
  local py=first
  while py<upper do local ph=math.min(1,upper-py);strip(py,ph);py=py+ph end
  local middle=math.min(last,bottom-cut)
  if middle>py then strip(py,middle-py);py=middle end
  while py<last do local ph=math.min(1,last-py);strip(py,ph);py=py+ph end
 end
 local function border(x,y,rw,rh,r,g,b) ISPanel.drawRectBorder(self,x,y,rw,rh,1,r,g,b) end
 local function text(t,x,y,r,g,b) ISPanel.drawText(self,t,x,y,r,g,b,1,UIFont.Small) end
 local sx=self.displayX+22*self.displayScale;local sy=self.displayY+22*self.displayScale
 local sw=996*self.displayScale;local sh=576*self.displayScale;local bottom=sy+sh
 -- Lid silhouette, stepped corners and raised olive plates match the WR-01 model.
 rect(24,14,w-48,bottom+24,.12,.14,.11)
 rect(14,30,w-28,bottom-2,.12,.14,.11)
 rect(29,19,w-58,bottom+13,.39,.43,.29)
 rect(35,24,w-70,bottom+3,.30,.35,.23)
 rect(43,28,w-86,4,.56,.59,.40)
 rect(43,32,w-86,17,.36,.40,.27)
 -- Recessed glass surrounded by a substantial black gasket.
 rect(sx-12,sy-12,sw+24,sh+24,.09,.11,.09)
 border(sx-12,sy-12,sw+24,sh+24,.48,.52,.37)
 rect(sx-6,sy-6,sw+12,sh+12,.19,.22,.18)
 rect(sx-3,sy-3,sw+6,sh+6,.04,.06,.05)
 -- Long rubber side guards, metal screw heads and slotted fasteners.
 for _,x in ipairs({12,w-41}) do
  rect(x,31,29,bottom-5,.13,.15,.12)
  rect(x+3,38,5,bottom-20,.23,.26,.21)
  for _,y in ipairs({69,bottom-21}) do
   rect(x+10,y,10,10,.60,.61,.49);rect(x+12,y+4,6,2,.17,.19,.15)
  end
 end
 -- Hinge rail and front deck: visible equipment, without an ornamental keyboard.
 local deck=bottom+40
 rect(41,bottom+23,w-82,20,.08,.10,.08)
 for _,x in ipairs({82,w-172}) do
  rect(x,bottom+22,90,24,.17,.19,.15);rect(x+8,bottom+23,74,3,.44,.47,.35)
  for i=1,4 do rect(x+12+i*12,bottom+28,2,15,.08,.10,.08) end
 end
 rect(25,deck,w-50,h-deck-20,.32,.37,.24)
 rect(36,deck+5,w-72,6,.56,.60,.42)
 rect(36,deck+11,w-72,19,.40,.45,.30)
 rect(46,deck+35,w-92,h-deck-66,.25,.30,.20)
 border(46,deck+35,w-92,h-deck-66,.45,.49,.33)
 text('WR-01  /  RUGGED FIELD TERMINAL',64,deck+15,.85,.86,.69)
 -- Identification plate and speaker slits.
 rect(w/2-98,deck+37,196,23,.66,.66,.49)
 text('CALFER / AQUACONTROL',w/2-82,deck+41,.16,.19,.13)
 for i=0,9 do rect(67+i*9,deck+41,4,17,.08,.12,.08) end
 for i=0,9 do rect(w-152+i*9,deck+41,4,17,.08,.12,.08) end
 rect(w-210,deck+16,8,8,powered and .48 or .18,powered and .80 or .24,.32)
 text('PWR',w-195,deck+13,.76,.80,.61)
 -- Protective base corners and the model's carry handle.
 for _,x in ipairs({16,w-54}) do
  rect(x,deck+3,38,h-deck-15,.12,.15,.11)
  rect(x+5,deck+9,28,7,.26,.29,.22)
 end
 local hx=w*.23;local hw=w*.54
 rect(hx-23,h-49,28,30,.63,.64,.47);rect(hx+hw-5,h-49,28,30,.63,.64,.47)
 rect(hx,h-43,hw,23,.13,.16,.12);rect(hx+4,h-42,hw-8,4,.31,.34,.26)
 rect(hx+7,h-23,hw-14,4,.08,.10,.08)
end
function P:button(x,y,w,h,text,callback)
 local scale=self.displayScale
 local b=ISButton:new(self.displayX+x*scale,self.displayY+y*scale,w*scale,h*scale,text,self,callback)
 b.backgroundColor={r=.66,g=.68,b=.64,a=1};b.backgroundColorMouseOver={r=.79,g=.81,b=.76,a=1}
 b.borderColor={r=.12,g=.14,b=.12,a=1};b.textColor={r=.08,g=.1,b=.08,a=1}
 b:initialise();b:instantiate();self:addChild(b)
 b.prerender=function(key)
  ISButton.prerender(key)
  key:drawRect(1,1,key.width-2,1,1,.9,.91,.87)
  key:drawRect(1,1,1,key.height-2,1,.9,.91,.87)
  key:drawRect(2,key.height-2,key.width-3,1,1,.29,.31,.27)
 end
 self.controls[#self.controls+1]=b
 return b
end
function P:close()
 self:removeFromUIManager();if P.instance==self then P.instance=nil end
end
function P:click()
 if self.preferences.audio then self.player:playSound("WR_ConsoleButton") end
end
function P:power()
 self:click();local d=L.data(self.item)
 if not d.powered and L.remaining(d)>0 then
  self.bootUntil=getTimestampMs()+1500
  if self.preferences.audio then self.player:playSound("WR_ConsoleBoot") end
 end
 L.request(self.player,self.item,d.powered and "off" or "on",true)
end
function P:showNotice(key)
 self.noticeKey=key;self.noticeUntil=getTimestampMs()+10000
end
function P:launchElectric()
 self:click()
 if not (L.data(self.item).links or {}).electric then self:showNotice("IGUI_WR_Link_LockedElectric");return end
 if ER and ER.openLaptopMonitor then self.noticeKey=nil;ER.openLaptopMonitor(self.player,self.item)
 else self:showNotice("IGUI_WR_Link_ElectricUnavailable") end
end
function P:launch()
 self:click()
 if not (L.data(self.item).links or {}).water then self:showNotice("IGUI_WR_Link_LockedWater");return end
 self.noticeKey=nil
 self.electricApp=false;self.browser=false;self.app=true;self.tab="Resumen"
end
function P:tabClick(button) self:click();self.tab=button.label end
function P:refresh()
 L.request(self.player,self.item,"status")
 self.lastRefresh=getTimestampMs()
end
function P:diagnose()
 self:click();self:refresh();self.reportAt=getTimestampMs();self.tab="Diagnostico"
end
function P:createChildren()
 ISPanel.createChildren(self);self.controls={};self.tabs={}
 self.exitButton=self:button(self.contentWidth-64,25,36,24,"X",self.close)
 self.powerButton=self:button(self.contentWidth-150,self.contentHeight-55,120,28,getText("IGUI_WR_Release_Text1"),self.power)
 self.appButton=self:button(64,90,116,86,"",self.launch)
 self.browserButton=self:button(64,304,116,86,"",function(panel) panel:click();panel.electricApp=false;panel.app=false;panel.browser=true end)
 self.trashButton=self:button(64,411,116,86,"",function() end)
 self.electricButton=self:button(64,197,116,86,"",self.launchElectric)
 for _,b in ipairs({self.appButton,self.browserButton,self.trashButton,self.electricButton}) do
  b.backgroundColor={r=0,g=0,b=0,a=0};b.borderColor={r=0,g=0,b=0,a=0}
  b.backgroundColorMouseOver={r=.65,g=.75,b=.66,a=.13}
  b.prerender=ISButton.prerender
 end
 self.startButton=self:button(30,self.contentHeight-55,108,28,"calfer",function(panel) panel:click();panel.electricApp=false;panel.app=false;panel.browser=false end)
 self.volumeButton=self:button(self.contentWidth-530,self.contentHeight-55,58,28,"VOL",function(panel) panel:click();panel.preferences.audio=not panel.preferences.audio end)
 for i,label in ipairs({"Resumen","Equipos","Red regional","Diagnostico","Ajustes","Power"}) do
  local b=self:button(64+(i-1)*143,160,138,28,getText(({Resumen="IGUI_WR_Release_Text3",Equipos="IGUI_WR_Release_Text4",["Red regional"]="IGUI_WR_Release_Text5",Diagnostico="IGUI_WR_Release_Text6",Power="IGUI_WR_LaptopPower_Tab",Ajustes="IGUI_WR_Release_Text7"})[label]),self.tabClick);b.label=label;self.tabs[#self.tabs+1]=b
 end
 self.backButton=self:button(self.contentWidth-213,119,143,26,getText("IGUI_WR_Release_Text8"),function(panel) panel.electricApp=false;panel.app=false;panel.browser=false;panel:click() end)
 self.diagButton=self:button(self.contentWidth-236,self.contentHeight-116,165,28,getText("IGUI_WR_Laptop_Text1"),self.diagnose)
 self.settingButtons={}
 for i,key in ipairs({"brightness","threshold","audio"}) do
  local b=self:button(84+(i-1)*286,307,248,32,"",function(panel,button)
   panel:click()
   if button.setting=="brightness" then panel.preferences.brightness=panel.preferences.brightness==1 and .7 or 1
   elseif button.setting=="threshold" then local v=panel.preferences.threshold;panel.preferences.threshold=v==35 and 50 or (v==50 and 65 or 35)
   else panel.preferences.audio=not panel.preferences.audio end
  end)
  b.setting=key;self.settingButtons[#self.settingButtons+1]=b
 end
 self.regionButtons={}
 for i,r in ipairs(WR.REGIONS) do
  local col=(i-1)%2;local row=math.floor((i-1)/2)
  local b=self:button(76+col*430,213+row*72,413,58,r.name,function(panel,button) panel.regionId=button.regionId;panel.tab="Sector";panel:click() end)
  b.regionId=r.id;self.regionButtons[#self.regionButtons+1]=b
 end
end
function P:bar(x,y,w,value,color)
 self:drawRect(x,y,w,12,1,.12,.17,.15)
 self:drawRect(x+2,y+2,math.max(0,(w-4)*math.min(1,math.max(0,value))),8,1,color[1],color[2],color[3])
 self:drawRectBorder(x,y,w,12,1,.35,.43,.36)
end
function P:label(text,x,y,r,g,b,font) self:drawText(text,x,y,r or .12,g or .18,b or .15,1,font or UIFont.Small) end
function P:summary(state)
 local bottom=self.contentHeight-90
 local supplied=0;for _,r in ipairs(WR.REGIONS) do if WR.regionSupplied(state,r.id,state.serverDay or 0) then supplied=supplied+1 end end
 local cards={{getText("IGUI_WR_Release_Text9"),state.waterActive and getText("IGUI_WR_Release_Text10") or getText("IGUI_WR_Release_Text11")},
 {getText("IGUI_WR_Release_Text12"),supplied.." / 6"},{getText("IGUI_WR_Laptop_Text2"),state.originalService and "--" or string.format(getText("IGUI_WR_Laptop_Text3"),state.remainingDays or 0)}}
 for i,c in ipairs(cards) do local x=76+(i-1)*286
  self:drawRect(x,212,268,88,1,.82,.85,.79);self:drawRectBorder(x,212,268,88,1,.48,.54,.46)
  self:label(c[1],x+14,225);self:label(c[2],x+14,255,.12,.27,.2,UIFont.Medium)
 end
 self:label(getText(state.originalService and "IGUI_WR_PhaseNormal" or "IGUI_WR_Laptop_Text4"),80,319)
 self:label(state.networkReady and getText("IGUI_WR_Laptop_Text5") or getText("IGUI_WR_Laptop_Text6"),80,345)
 local g=state.generator or {}
 self:label(getText("IGUI_WR_Gen_Remote").." "..math.floor(g.fuel or 0).." L / "..string.format("%.1f",WR.Power.hours({fuel=g.fuel or 0})/24).." d",80,375)
 if not WR.Power.available(state) then self:label(getText("IGUI_WR_Gen_NoPower"),80,402,.55,.18,.08) end
 local t=getTimestampMs()/240
 for i=0,35 do local h=7+math.sin(t+i*.45)*5
  self:drawRect(84+i*19,bottom-14-h,9,h,1,.27,.47,.35)
 end
end
function P:equipment(state)
 self:label(getText("IGUI_WR_Release_Text13"),80,205);self:label(getText("IGUI_WR_Laptop_Text8"),450,205);self:label(getText("IGUI_WR_Release_Text14"),665,205)
 for i,id in ipairs(WR.ALL_IDS) do
  local y=229+(i-1)*20;local condition=(state.conditions or {})[id] or 0
  local ready=(id=="central" and state.centralRepaired) or (state.panels or {})[id] or (state.valves or {})[id]
  self:label(getText("IGUI_WR_Plant_"..id),80,y)
  self:bar(450,y+3,155,condition/100,condition<=self.preferences.threshold and amber or green)
  self:label(ready and string.format(getText("IGUI_WR_Laptop_Text9"),condition,condition*21/100) or getText("IGUI_WR_Laptop_Text10"),665,y)
 end
end
function P:sector(state)
 local r=WR.REGION_BY_ID[self.regionId or "south"];local s=(state.regions or {})[r.id] or {}
 local day=state.serverDay or 0;local health=WR.stationCondition(s,day)
 self:label(r.name,80,211,.1,.28,.21,UIFont.Medium)
 self:label(WR.regionSupplied(state,r.id,day) and getText("IGUI_WR_Release_Text15") or getText("IGUI_WR_Release_Text16"),80,248)
 self:label(getText("IGUI_WR_Release_Text17")..(s.repaired and getText("IGUI_WR_Release_Text18") or getText("IGUI_WR_Release_Text19")).." / "..(s.activated and getText("IGUI_WR_Release_Text20") or getText("IGUI_WR_Release_Text21")),80,278)
 self:bar(80,313,500,health/100,health<=self.preferences.threshold and amber or green)
 self:label(string.format(getText("IGUI_WR_Laptop_Text11"),health,health*21/100),80,341)
 self:label(getText("IGUI_WR_Release_Text22")..table.concat(r.cities,", "),80,372)
 local target=s.terminal or r
 self:label(getText("IGUI_WR_Laptop_Text12")..target.x.." / Y "..target.y,80,402)
end
function P:diagnostics(state)
 local faults=0;for _,id in ipairs(WR.ALL_IDS) do if ((state.conditions or {})[id] or 0)<=self.preferences.threshold then faults=faults+1 end end
 self:label(getText("IGUI_WR_Laptop_Text13"),80,211,.1,.28,.21,UIFont.Medium)
 self:label("["..(state.centralRepaired and "OK" or getText("IGUI_WR_Release_Text23"))..getText("IGUI_WR_Release_Text26"),80,250)
 self:label("["..(state.networkReady and "OK" or getText("IGUI_WR_Release_Text24"))..getText("IGUI_WR_Laptop_Text14"),80,280)
 self:label("["..(faults==0 and "OK" or getText("IGUI_WR_Release_Text25")).."] "..faults..getText("IGUI_WR_Release_Text27"),80,310)
 self:label(getText("IGUI_WR_Release_Text28"),80,340)
 self:label(self.reportAt and getText("IGUI_WR_Laptop_Text15") or getText("IGUI_WR_Laptop_Text16"),80,377)
end
function P:settings()
 for i,title in ipairs({getText("IGUI_WR_Release_Text29"),getText("IGUI_WR_Release_Text30"),"AUDIO"}) do local x=76+(i-1)*286
  self:drawRect(x,218,268,161,1,.82,.85,.79);self:drawRectBorder(x,218,268,161,1,.48,.54,.46)
  self:label(title,x+12,231)
  self:label(({getText("IGUI_WR_Release_Text31"),getText("IGUI_WR_Release_Text32"),getText("IGUI_WR_Release_Text33")})[i],x+12,266)
 end
 self.settingButtons[1]:setTitle(getText("IGUI_WR_Release_Text34")..math.floor(self.preferences.brightness*100).."%")
 self.settingButtons[2]:setTitle(getText("IGUI_WR_Release_Text35")..self.preferences.threshold.."%")
 self.settingButtons[3]:setTitle("Audio: "..(self.preferences.audio and getText("IGUI_WR_Laptop_Text17") or getText("IGUI_WR_Release_Text36")))
 self:label(getText("IGUI_WR_Laptop_Text18"),80,403)
end
function P:logo(x,y,size)
 local pixel=size/32
 for row=0,31 do
  local run
  for col=0,32 do
   local dx,dy=col-15.5,row-15.5
   local circle=dx*dx+dy*dy<=225
   local outer=(math.abs(dx)/12)^.55+(math.abs(dy)/12)^.55<=1
   local inner=(math.abs(dx)/4)^.7+(math.abs(dy)/4)^.7<=1
   local ink=col<32 and circle and ((not outer and not (dx>0 and math.abs(dy)<2)) or inner)
   if ink and not run then run=col end
   if not ink and run then self:drawRect(x+run*pixel,y+row*pixel,(col-run)*pixel,pixel,1,.58,.69,.49);run=nil end
  end
 end
end
function P:desktopIcon(kind,x,y)
 if kind=="plant" then
  self:drawRect(x,y+7,40,28,1,.7,.75,.62);self:drawRect(x+4,y+11,32,19,1,.16,.29,.24)
  self:drawRect(x+16,y+35,8,7,1,.62,.67,.54);self:drawRect(x+8,y+42,24,3,1,.7,.75,.62)
  for i=0,3 do self:drawRect(x+8+i*7,y+24-i*3,4,3+i*3,1,.57,.79,.51) end
 elseif kind=="browser" then
  self:drawRect(x+5,y+7,31,32,1,.47,.66,.62);self:drawRect(x+11,y+3,19,40,1,.47,.66,.62)
  self:drawRectBorder(x+15,y+5,11,36,1,.77,.83,.67)
  for i=0,2 do self:drawRect(x+5,y+14+i*9,31,2,1,.77,.83,.67) end
 else
  self:drawRect(x+10,y+11,23,31,1,.64,.69,.58);self:drawRect(x+7,y+7,29,4,1,.8,.83,.72)
  self:drawRect(x+17,y+3,10,4,1,.8,.83,.72)
  for i=0,2 do self:drawRect(x+14+i*6,y+16,2,21,1,.32,.4,.32) end
 end
end
function P:prerender()
 ISPanel.prerender(self)
 local w,h=self.contentWidth,self.contentHeight;local d=L.data(self.item);local left=L.remaining(d)
 local powered=d.powered and left>0;local boot=powered and getTimestampMs()<(self.bootUntil or 0)
 self:drawHousing(powered)
 self:drawRect(22,22,w-44,h-44,1,powered and .16 or .025,powered and .31 or .04,powered and .29 or .03)
 self.powerButton:setTitle(powered and getText("IGUI_WR_Release_Text2") or getText("IGUI_WR_Release_Text1"))
 if self.electricTabs then for _,b in ipairs(self.electricTabs) do b:setVisible(powered and not boot and self.electricApp==true) end end
 local desktop=powered and not boot and not self.app and not self.browser and not self.electricApp
 self.appButton:setVisible(desktop);self.browserButton:setVisible(desktop);self.trashButton:setVisible(desktop);self.electricButton:setVisible(desktop)
 self.startButton:setVisible(powered and not boot);self.volumeButton:setVisible(powered and not boot)
 self.volumeButton:setTitle(self.preferences.audio and "VOL +" or getText("IGUI_WR_Release_Text37"))
 self.backButton:setVisible(powered and not boot and (self.app==true or self.browser==true or self.electricApp==true))
 for _,b in ipairs(self.tabs) do b:setVisible(powered and not boot and self.app==true) end
 self.diagButton:setVisible(powered and not boot and self.app==true and self.tab=="Diagnostico")
 for _,b in ipairs(self.settingButtons) do b:setVisible(powered and not boot and self.app==true and self.tab=="Ajustes") end
 for _,b in ipairs(self.regionButtons) do b:setVisible(powered and not boot and self.app==true and self.tab=="Red regional") end
 if powered and boot then
  self:label("CALFER / BIOS 1.93",72,110,.63,.88,.61,UIFont.Medium)
  self:label(getText("IGUI_WR_Laptop_Text19"),72,159,.63,.88,.61)
 elseif powered then
  self:drawRect(24,24,w-48,28,1,.09,.16,.28)
  self:label(getText("IGUI_WR_Release_Text38"),35,30,.92,.94,.86)
  if self.electricApp and ER and ER.drawLaptop then ER.drawLaptop(self)
  elseif self.app then
   self:drawRect(56,115,w-112,h-182,1,.72,.75,.7)
   self:label(getText("IGUI_WR_Laptop_Text20"),70,122,.1,.2,.17,UIFont.Medium)
   local state=WR.ClientState or {}
   if self.tab=="Power" then WR.drawPowerDisplay(self,state,76,205,840,false)
   elseif self.tab=="Equipos" then self:equipment(state)
   elseif self.tab=="Sector" then self:sector(state)
   elseif self.tab=="Diagnostico" then self:diagnostics(state)
   elseif self.tab=="Ajustes" then self:settings()
   elseif self.tab=="Red regional" then self:label(getText("IGUI_WR_Release_Text39"),80,443)
   else self:summary(state) end
  elseif self.browser then
   self:drawRect(56,115,w-112,h-182,1,.72,.75,.7)
   self:label("Calfer Navigator",70,122,.1,.2,.17,UIFont.Medium)
   self:drawRect(74,165,w-148,30,1,.87,.88,.83)
   self:label(getText("IGUI_WR_Laptop_Text21"),84,172)
   self:label(getText("IGUI_WR_Laptop_Text22"),112,250,.2,.3,.24,UIFont.Medium)
   self:label(getText("IGUI_WR_Laptop_Text23"),112,292)
   self:label(getText("IGUI_WR_Laptop_Text24"),112,324)
   self:label(getText("IGUI_WR_Release_Text40"),112,369)
  else
   self:desktopIcon("plant",100,104);self:label("AquaControl",82,157,.83,.89,.79)
   self:desktopIcon("browser",100,318);self:label(getText("IGUI_WR_Release_Text41"),86,371,.83,.89,.79)
   self:desktopIcon("plant",100,211);self:label("ElectroControl",75,264,.83,.89,.79)
   self:desktopIcon("trash",100,425);self:label(getText("IGUI_WR_Release_Text42"),90,478,.83,.89,.79)
   self:logo(w/2-45,181,132)
   self:label("calfer",w/2-15,332,.76,.83,.68,UIFont.Large)
   self:label(getText("IGUI_WR_Release_Text43"),w/2-66,367,.55,.67,.54)
  end
  if self.noticeKey and getTimestampMs()<(self.noticeUntil or 0) then
   self:drawRect(190,405,w-260,112,1,.10,.17,.20)
   self:drawRectBorder(190,405,w-260,112,1,.72,.66,.39)
   self:label(getText("IGUI_WR_Link_Notice"),210,421,.97,.85,.55,UIFont.Medium)
   self:label(getText(self.noticeKey),210,461,.93,.95,.88)
  end
  if self.preferences.brightness<1 then self:drawRect(24,54,w-48,h-121,.18,0,0,0) end
 else
  self:label(getText("IGUI_WR_Release_Text44"),w/2-123,h/2-28,.42,.57,.45,UIFont.Medium)
  self:label(left>0 and getText("IGUI_WR_Release_Text45") or getText("IGUI_WR_Laptop_Text25"),w/2-220,h/2+10,.42,.57,.45)
 end
 -- Battery tray and power control inside the screen.
 self:drawRect(24,h-62,w-48,40,1,.64,.68,.61)
 self:drawRect(25,h-62,w-50,2,1,.88,.91,.84)
 self:label(powered and (self.electricApp and "ElectroControl" or self.app and "AquaControl" or (self.browser and "Navigator" or getText("IGUI_WR_Release_Text8"))) or getText("IGUI_WR_Release_Text46"),150,h-50)
 if powered then self:label(getText("IGUI_WR_Laptop_Text26"),w-654,h-50,.35,.25,.2) end
 local bx=w-460;local by=h-49
 self:drawRectBorder(bx,by,30,16,1,.19,.25,.19)
 self:drawRect(bx+30,by+5,3,6,1,.19,.25,.19)
 local charge=left/L.HOURS;local c=charge<=.2 and amber or {.24,.48,.3}
 for i=0,3 do if charge>i/4 then self:drawRect(bx+3+i*6,by+3,4,10,1,c[1],c[2],c[3]) end end
 self:label(string.format("%d%% %.1fd",math.ceil(charge*100),left/24),bx+40,h-50)
 local clock=getGameTime()
 if clock.getDay and clock.getMonth and clock.getYear and clock.getTimeOfDay then
  local time=clock:getTimeOfDay();local hours=math.floor(time);local minutes=math.floor((time-hours)*60)
  self:label(string.format("%02d/%02d/%04d",clock:getDay()+1,clock:getMonth()+1,clock:getYear()),w-310,h-57)
  self:label(string.format("%02d:%02d",hours,minutes),w-310,h-41)
 end
end
function P:update()
 ISPanel.update(self)
 if self.electricApp and ER and getTimestampMs()-(self.electricRefresh or 0)>5000 then ER.request("state",nil,{player=self.player});self.electricRefresh=getTimestampMs() end
 local d=L.data(self.item)
 if not d.opened then self:close();return end
 if not L.find(self.player,self.item:getID(),self.worldX,self.worldY,self.worldZ) then self:close();return end
 if d.powered and getTimestampMs()-(self.lastRefresh or 0)>10000 then self:refresh() end
 if d.powered and L.remaining(d)<=0 then L.request(self.player,self.item,"off") end
end
function P.open(player,item)
 if P.instance then
  if P.instance.item==item then return end
  P.instance:close()
 end
 local w=math.min(1176,getCore():getScreenWidth()-24);local h=math.min(800,getCore():getScreenHeight()-24)
 local o=P:new((getCore():getScreenWidth()-w)/2,(getCore():getScreenHeight()-h)/2,w,h)
 o.contentWidth=1040;o.contentHeight=620
 o.displayScale=math.min((w-112)/1040,(h-164)/620)
 o.displayX=(w-1040*o.displayScale)/2;o.displayY=44
 o.player=player;o.item=item;o.app=false;o.tab="Resumen";o.lastRefresh=getTimestampMs()
 o.backgroundColor={r=0,g=0,b=0,a=0};o.borderColor={r=0,g=0,b=0,a=0}
 local preferences=player:getModData();preferences.WRConsolePreferences=preferences.WRConsolePreferences or {}
 preferences.WRConsolePreferences.laptop=preferences.WRConsolePreferences.laptop or {brightness=1,threshold=35,audio=true}
 o.preferences=preferences.WRConsolePreferences.laptop;o.bootUntil=L.data(item).powered and getTimestampMs()+1500 or 0
 local world=item:getWorldItem();local sq=world and world:getSquare()
 if sq then o.worldX=sq:getX();o.worldY=sq:getY();o.worldZ=sq:getZ() end
 o:initialise();o:instantiate();o:addToUIManager();P.instance=o
 if L.data(item).powered and o.preferences.audio then player:playSound("WR_ConsoleBoot") end
end
