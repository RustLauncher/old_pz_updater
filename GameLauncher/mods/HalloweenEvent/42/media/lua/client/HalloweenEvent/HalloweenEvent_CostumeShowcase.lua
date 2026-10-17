-- Client-only promotional paper dolls. No spawn, server command or event change.
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISUI3DModel"
require "ISUI/ISContextMenu"
require "HalloweenEvent/HalloweenEvent_Shared"

local HWE = HalloweenEvent
local Gallery = ISPanel:derive("HWECostumeShowcase")
local function entries()
    local result = {}
    for _, costume in ipairs(HWE.Costumes or {}) do
        result[#result+1] = {costume=costume, name=costume.name or costume.id}
    end
    return result
end

-- Whole-row scrolling keeps UI3DModel viewports away from the header/footer.
-- Its GL renderer does not obey Lua panel clipping for partial paper dolls.
local Track = ISPanel:derive("HWEShowcaseScrollTrack")
function Track:new(owner)
    local o=ISPanel.new(self,owner.width-22,86,14,owner.height-126)
    o.owner=owner; o.backgroundColor={r=0.12,g=0.12,b=0.12,a=1}
    return o
end
function Track:prerender()
    ISPanel.prerender(self)
    local g=self.owner
    local h=math.max(24,self.height*g.visibleRows/g.rows)
    local range=math.max(1,g.rows-g.visibleRows)
    local y=(self.height-h)*(g.firstRow-1)/range
    self:drawRect(1,y,self.width-2,h,1,0.55,0.55,0.55)
end
function Track:moveThumb()
    local g=self.owner
    local h=math.max(24,self.height*g.visibleRows/g.rows)
    local y=getMouseY()-self:getAbsoluteY()-h/2
    local fraction=math.max(0,math.min(1,y/math.max(1,self.height-h)))
    g:setFirstRow(1+math.floor(fraction*(g.rows-g.visibleRows)+0.5))
end
function Track:onMouseDown(x,y)
    self.dragging=true; self:setCapture(true); self:moveThumb(); return true
end
function Track:onMouseMove(dx,dy)
    if self.dragging then self:moveThumb() end
    return true
end
Track.onMouseMoveOutside=Track.onMouseMove
function Track:onMouseUp(x,y)
    self.dragging=false; self:setCapture(false); return true
end
Track.onMouseUpOutside=Track.onMouseUp
function Track:onMouseWheel(delta) return self.owner:onMouseWheel(delta) end

local function clipped(text, width)
    local tm = getTextManager()
    if tm:MeasureStringX(UIFont.Small, text) <= width then return text end
    while #text > 0 and tm:MeasureStringX(UIFont.Small, text .. "...") > width do
        text = text:sub(1, -2)
    end
    return text .. "..."
end

function Gallery:new(all)
    local o = ISPanel.new(self, 0, 0, getCore():getScreenWidth(), getCore():getScreenHeight())
    o.backgroundColor = {r=0.12,g=0.12,b=0.12,a=1}
    o.borderColor = {r=0.24,g=0.24,b=0.24,a=1}
    o.entries, o.models, o.dolls = entries(), {}, {}
    o.capture, o.ready, o.failed = false, 0, 0
    o.queue, o.queued, o.firstRow = {}, {}, 1
    for i=1,#o.entries do o.queue[#o.queue+1]=i; o.queued[i]=true end
    o.pending, o.retryFrames, o.zoom = nil, 0, 0
    return o
end

function Gallery:createChildren()
    ISPanel.createChildren(self)
    local n = #self.entries
    self.columns = 5
    self.rows = math.max(1,math.ceil(n/self.columns))
    self.visibleRows = math.min(3,self.rows)
    self.cellW = (self.width-60)/self.columns
    self.cellH = (self.height-126)/self.visibleRows
    for i,entry in ipairs(self.entries) do
        entry.x=24+((i-1)%self.columns)*self.cellW
        entry.row=math.floor((i-1)/self.columns)+1
        entry.female=entry.costume.femaleOnly==true or
            (entry.costume.maleOnly~=true and i%2==0)
    end
    self.track=Track:new(self)
    self.track:initialise(); self.track:instantiate(); self:addChild(self.track)
    self:layoutRows()
    local function button(x, w, title, callback)
        local b=ISButton:new(x, self.height-32, w, 24, title, self, callback)
        b:initialise(); b:instantiate(); self:addChild(b)
        return b
    end
    self.buttons = {
        button(24,160,"Hide controls (capture)",Gallery.toggleCapture),
        button(194,100,"Rotate all",Gallery.rotate),
        button(304,80,"Zoom +",Gallery.zoomIn),
        button(394,80,"Zoom -",Gallery.zoomOut),
        button(self.width-104,80,"Close",Gallery.close)
    }
    self.direction = IsoDirections.SE
end

function Gallery:toggleCapture()
    self.capture = not self.capture
    for _, b in ipairs(self.buttons) do b:setVisible(not self.capture) end
    self.track:setVisible(not self.capture)
end
function Gallery:onMouseDoubleClick(x,y)
    if self.capture then self:toggleCapture(); return true end
    return false
end
function Gallery:rotate()
    self.direction=IsoDirectionSet.rotate(self.direction,1)
    for _,m in pairs(self.models) do m:setDirection(self.direction) end
end
function Gallery:zoomIn() self:setModelZoom(self.zoom+1) end
function Gallery:zoomOut() self:setModelZoom(self.zoom-1) end
function Gallery:setModelZoom(value)
    self.zoom=math.max(-8,math.min(8,value))
    for _,m in pairs(self.models) do m:setZoom(self.zoom) end
end

function Gallery:layoutRows()
    for i,entry in ipairs(self.entries) do
        entry.y=86+(entry.row-self.firstRow)*self.cellH
        entry.visible=entry.row>=self.firstRow and entry.row<self.firstRow+self.visibleRows
        local model=self.models[i]
        if model then model:setY(entry.y+12); model:setVisible(entry.visible) end
    end
end
function Gallery:setFirstRow(row)
    self.firstRow=math.max(1,math.min(math.max(1,self.rows-self.visibleRows+1),row))
    self:layoutRows()
end
function Gallery:onMouseWheel(delta)
    self:setFirstRow(self.firstRow+(delta>0 and -1 or 1))
    return true
end
function Gallery:regenerate(index)
    local entry=self.entries[index]
    if not entry then return end
    local model=self.models[index]
    if model then
        model:setVisible(false); self:removeChild(model)
        self.models[index],self.dolls[index]=nil,nil
        self.ready=self.ready-1
    end
    if entry.error then self.failed=self.failed-1; entry.error=nil end
    entry.female=entry.costume.femaleOnly==true or
        (entry.costume.maleOnly~=true and ZombRand(2)==1)
    if self.activeIndex==index then self.pending=nil; self.retryFrames=0 end
    if not self.queued[index] and self.activeIndex~=index then
        table.insert(self.queue,1,index); self.queued[index]=true
    end
end
function Gallery:entryMenu(index)
    local player=getPlayer()
    local menu=ISContextMenu.get(player and player:getPlayerNum() or 0,getMouseX(),getMouseY())
    menu:addOption("Regenerate zombie",self,function(owner) owner:regenerate(index) end)
    return true
end
function Gallery:onRightMouseUp(x,y)
    for i,entry in ipairs(self.entries) do
        if entry.visible and x>=entry.x and x<entry.x+self.cellW and
            y>=entry.y and y<entry.y+self.cellH then return self:entryMenu(i) end
    end
    return true
end

function Gallery:prepare(entry)
    -- Zero-position constructor creates a presentation-only zombie. Never add
    -- it to a square, cell list, zombie manager or multiplayer spawn system.
    local zombie=IsoZombie.new(getCell())
    zombie:setFemaleEtc(entry.female)
    zombie:setDressInRandomOutfit(false)
    self.pending=zombie
    return zombie
end

function Gallery:finishEntry(entry,zombie)
    local costume=entry.costume
    -- Select once for this generated doll; regeneration rolls a new choice.
    if costume.optionalItems and costume.visualItems then
        local recipe={}
        for k,v in pairs(costume) do recipe[k]=v end
        recipe.visualItems={}
        for _,v in ipairs(costume.visualItems) do recipe.visualItems[#recipe.visualItems+1]=v end
        if HWE.rollPercent(costume.optionalChance) then
            local selected=costume.optionalItems[ZombRand(1,#costume.optionalItems+1)]
            recipe.visualItems[#recipe.visualItems+1]=selected
        end
        costume=recipe
    end
    if costume.visualItems and #costume.visualItems > 0 then
        local ok,reason=HWE.applyCostumeVisuals(zombie,costume,"client_showcase")
        if not ok then return false,reason end
    end
    if costume.additionalItems then
        for _, fullType in ipairs(costume.additionalItems) do
            local v=ItemVisual.new(); v:setItemType(fullType)
            local clothing=v:getClothingItem()
            if not clothing then return false,"Waiting for " .. fullType end
            v:pickUninitializedValues(clothing)
            zombie:getItemVisuals():add(v)
        end
    end
    if zombie:getItemVisuals():size()==0 then return false,"Waiting for outfit assets" end
    local m=ISUI3DModel:new(entry.x+6,entry.y+12,self.cellW-12,self.cellH-52)
    m:initialise(); m:instantiate()
    m:setCharacter(zombie)
    m:setIsometric(true); m:setDirection(self.direction)
    m:setAnimSetName("zombie"); m:setState("idle")
    m:setDoRandomExtAnimations(false); m:setZoom(self.zoom)
    -- Freeze a stable pose even while the game is running.
    m.prerender=function(model)
        ISUIElement.prerender(model)
        model.javaObject:setAnimate(false)
    end
    local index=self.activeIndex
    m.onRightMouseUp=function() return self:entryMenu(index) end
    m.onMouseWheel=function(_,delta) return self:onMouseWheel(delta) end
    m.onMouseDoubleClick=function(_,x,y) return self:onMouseDoubleClick(x,y) end
    self:addChild(m); m:setVisible(entry.visible)
    self.models[index],self.dolls[index]=m,zombie
    self.ready=self.ready+1
    return true
end

function Gallery:update()
    ISPanel.update(self)
    if not self.activeIndex then
        self.activeIndex=table.remove(self.queue,1)
        if self.activeIndex then self.queued[self.activeIndex]=nil end
    end
    local entry=self.activeIndex and self.entries[self.activeIndex]
    if not entry then return end
    -- Stage one doll at a time; retries are bounded and never repeat errors
    -- every frame. Native clothing/model assets may load asynchronously.
    self.retryFrames=self.retryFrames+1
    if self.retryFrames % 15 ~= 1 then return end
    local success,result,reason=pcall(function()
        local zombie=self.pending or self:prepare(entry)
        zombie:dressInNamedOutfit(entry.costume.outfit)
        return self:finishEntry(entry,zombie)
    end)
    if success and result then
        self.activeIndex=nil; self.pending=nil; self.retryFrames=0
    elseif not success or self.retryFrames > 600 then
        entry.error=not success and tostring(result) or tostring(reason)
        self.failed=self.failed+1
        print("[HalloweenEvent] SHOWCASE_FAILED id=" .. entry.costume.id .. " reason=" .. entry.error)
        self.activeIndex=nil; self.pending=nil; self.retryFrames=0
    end
end

local function roundedRect(panel,x,y,w,h,r,color)
    panel:drawRect(x,y+r,w,h-2*r,1,color,color,color)
    for row=0,r-1 do
        local d=r-row-0.5
        local inset=math.ceil(r-math.sqrt(r*r-d*d))
        panel:drawRect(x+inset,y+row,w-2*inset,1,1,color,color,color)
        panel:drawRect(x+inset,y+h-row-1,w-2*inset,1,1,color,color,color)
    end
end

function Gallery:prerender()
    ISPanel.prerender(self)
    self:drawTextCentre("HALLOWEEN EVENT",self.width/2,16,0.94,0.94,0.94,1,UIFont.Large)
    self:drawTextCentre("by Mattnetic  |  " .. tostring(#HWE.Costumes) .. " costume profiles",
        self.width/2,48,0.85,0.85,0.85,1,UIFont.Small)
    for i,entry in ipairs(self.entries) do
      if entry.visible then
        roundedRect(self,entry.x+2,entry.y+2,self.cellW-4,self.cellH-4,6,0.24)
        roundedRect(self,entry.x+3,entry.y+3,self.cellW-6,self.cellH-6,5,0.18)
        local label=entry.name
        self:drawTextCentre(clipped(label,self.cellW-14),entry.x+self.cellW/2,
            entry.y+self.cellH-31,0.92,0.92,0.92,1,UIFont.Small)
        if entry.error then
            self:drawTextCentre("Preview unavailable (see log)",entry.x+self.cellW/2,
                entry.y+20,1,0.4,0.3,1,UIFont.Small)
        elseif not self.models[i] then
            self:drawTextCentre("Loading...",entry.x+self.cellW/2,entry.y+20,0.6,0.6,0.6,1,UIFont.Small)
        end
      end
    end
    if not self.capture then
        self:drawTextCentre("Ready " .. self.ready .. "/" .. #self.entries ..
            " | Errors " .. self.failed .. " | Rows " .. self.firstRow .. "-" .. (self.firstRow+self.visibleRows-1) ..
            "/" .. self.rows .. " | Wheel: scroll | Right-click: regenerate",
            self.width/2,self.height-29,0.8,0.8,0.8,1,UIFont.Small)
    end
end

function Gallery:close()
    self:setVisible(false); self:removeFromUIManager()
    for _,m in pairs(self.models) do m:setVisible(false); self:removeChild(m) end
    self.models,self.dolls,self.pending={},{},nil
    self.queue,self.queued,self.activeIndex={},{},nil
    self.track.dragging=false; self.track:setCapture(false)
    if HWE.CostumeShowcaseWindow==self then HWE.CostumeShowcaseWindow=nil end
end

function HWE.ShowCostumeShowcase(all)
    if HWE.CostumeShowcaseWindow then HWE.CostumeShowcaseWindow:close() end
    local p=Gallery:new(all==true)
    p:initialise(); p:instantiate(); p:addToUIManager(); p:bringToTop()
    HWE.CostumeShowcaseWindow=p
    return p
end

function EVHalloweenCostumeShowcase(all) return HWE.ShowCostumeShowcase(all) end
return Gallery
