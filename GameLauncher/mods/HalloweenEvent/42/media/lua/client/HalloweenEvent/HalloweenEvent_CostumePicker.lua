require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISTextEntryBox"
require "ISUI/ISComboBox"
require "ISUI/ISScrollingListBox"
require "HalloweenEvent/HalloweenEvent_Shared"
require "HalloweenEvent/EVHalloween_Items"

local HWE = HalloweenEvent
local Picker = ISPanel:derive("HWECostumePicker")
HWE.CostumePicker = Picker

local function measure(text, font)
    return getTextManager():MeasureStringX(font or UIFont.Small, text)
end

local function wrap(text, width)
    local lines, line = {}, ""
    for word in tostring(text):gmatch("%S+") do
        local candidate = line == "" and word or (line .. " " .. word)
        if measure(candidate) <= width then
            line = candidate
        else
            if line ~= "" then lines[#lines+1] = line; line = "" end
            -- Long item IDs and names without spaces also wrap. Preserve UTF-8.
            for character in word:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
                if line ~= "" and measure(line .. character) > width then
                    lines[#lines+1] = line; line = ""
                end
                line = line .. character
            end
        end
    end
    if line ~= "" or #lines == 0 then lines[#lines+1] = line end
    return lines
end

-- A stationary screen-space drag origin avoids feedback from moving grips.
local Grip = ISPanel:derive("HWEPickerResizeGrip")
function Grip:new(owner, side)
    local o=ISPanel.new(self,0,0,20,20)
    o.owner,o.side,o.background=owner,side,false
    o.anchorLeft,o.anchorRight,o.anchorTop,o.anchorBottom=true,false,true,false
    return o
end
function Grip:onMouseDown(x,y)
    local p=self.owner
    self.start={x=p.x,y=p.y,w=p.width,h=p.height,mx=getMouseX(),my=getMouseY()}
    self.wasMovable=p.moveWithMouse
    p.moving=false; p.moveWithMouse=false; p:bringToTop()
    self.resizing=true; self:setCapture(true)
    return true
end
function Grip:onMouseMove(dx,dy)
    if self.resizing and self.start then
        self.owner:resizeFromCorner(self.side,self.start,
            getMouseX()-self.start.mx,getMouseY()-self.start.my)
    end
    return true
end
Grip.onMouseMoveOutside=Grip.onMouseMove
function Grip:finishDrag()
    if self.resizing then self.owner.moveWithMouse=self.wasMovable end
    self.resizing=false; self.start=nil; self:setCapture(false)
end
function Grip:onMouseUp(x,y) self:finishDrag(); return true end
Grip.onMouseUpOutside=Grip.onMouseUp
function Grip:prerender() end
function Grip:render() end

function Picker:new(entry)
    local longest = 0
    for _, c in ipairs(HWE.Costumes) do longest = math.max(longest, measure(HWE.choiceName(c))) end
    for _, c in ipairs(HWE.Items.catalog) do longest = math.max(longest, measure(HWE.choiceName(c))) end
    local status = math.max(measure(HWE.text("Enabled")), measure(HWE.text("Disabled"))) + 36
    local w = math.min(math.max(780, longest+status+64), getCore():getScreenWidth() - 40)
    local h = math.min(680, getCore():getScreenHeight() - 40)
    local o = ISPanel.new(self, (getCore():getScreenWidth()-w)/2,
        (getCore():getScreenHeight()-h)/2, w, h)
    o.entry = entry
    o.disabled, o.unknown = HWE.CostumeFilter.parse(entry:getText())
    o.backgroundColor = {r=0.08,g=0.08,b=0.08,a=0.98}
    o.moveWithMouse = true
    o.minimumWidth, o.minimumHeight = 0, 0
    o.resizeBarHeight = 20
    o.resizeimage = getTexture("media/ui/ResizeIcon.png")
    o.statusbarbkg = getTexture("media/ui/Panel_StatusBar.png")
    return o
end

function Picker:createChildren()
    ISPanel.createChildren(self)
    self.search = ISTextEntryBox:new("", 16, 74, self.width-245, 26)
    self.search:initialise(); self.search:instantiate(); self:addChild(self.search)
    self.search.tooltip = HWE.text("SearchHelp")
    self.category = ISComboBox:new(self.width-217, 74, 201, 26, self, self.refresh)
    self.category:initialise(); self:addChild(self.category)
    self.category:addOption(HWE.text("AllCategories"))
    self.categories={}
    for _,name in ipairs(HWE.CostumeCategoryOrder) do self.category:addOption(HWE.groupName(name));self.categories[#self.categories+1]=name end
    for _,name in ipairs({"Items","Items: Decorations","Items: Functional"}) do self.category:addOption(HWE.groupName(name));self.categories[#self.categories+1]=name end
    self.list = ISScrollingListBox:new(16, 110, self.width-32, self.height-202)
    self.list:initialise(); self.list:instantiate()
    self.list.doDrawItem = Picker.drawRow
    self.list:setOnMouseDownFunction(self, Picker.toggle)
    self:addChild(self.list)
    local function button(x, y, w, title, callback)
        local b = ISButton:new(x, y, w, 26, title, self, callback)
        b:initialise(); b:instantiate(); self:addChild(b); return b
    end
    self.enableButton = button(16, 0, 150, HWE.text("EnableShown"), Picker.enableShown)
    self.disableButton = button(174, 0, 150, HWE.text("DisableShown"), Picker.disableShown)
    self.cancelButton = button(16, 0, 150, HWE.text("Cancel"), Picker.close)
    self.applyButton = button(16, 0, 150, HWE.text("UseSelection"), Picker.apply)
    self.resizeRight = Grip:new(self, "right")
    self.resizeBottom = Grip:new(self, "bottom")
    for _, grip in ipairs({self.resizeBottom, self.resizeRight}) do
        grip:initialise(); grip:instantiate(); self:addChild(grip)
    end
    self:layout()
    self:refresh()
end

function Picker:summary()
    local count, itemCount = 0, 0
    for _, c in ipairs(HWE.Costumes) do if self.disabled[c.id] then count = count + 1 end end
    for _, c in ipairs(HWE.Items.catalog) do if self.disabled[c.fullType] then itemCount = itemCount + 1 end end
    return HWE.text("PickerCount",count,#HWE.Costumes,itemCount)
end

function Picker:layoutRows()
    local height = 0
    local scrollWidth = self.list.vscroll and self.list.vscroll:getWidth() or 17
    local available = math.max(60, self.list.width-self.nameX-scrollWidth-8)
    self.list.itemheight = self.lineHeight*2+8
    for _, row in ipairs(self.list.items or {}) do
        row.nameLines = wrap(HWE.choiceName(row.item), available)
        row.detailLines = wrap(HWE.groupName(row.item.category) .. " / " .. row.item.id, available)
        row.height = (#row.nameLines+#row.detailLines)*self.lineHeight+8
        height = height + row.height
    end
    self.list:setScrollHeight(height)
    -- setWidth/setHeight alone leave the scrollbar's Lua position/height stale.
    -- Refresh native geometry and clamp the scroll offset after every reflow.
    local scrollbar = self.list.vscroll
    if scrollbar then
        scrollbar:setX(self.list:getWidth()-16)
        scrollbar:setY(0)
        scrollbar:setHeight(self.list:getHeight())
    end
    self.list:updateScrollbars()
end

function Picker:layout()
    if self.layoutBusy or not self.list then return end
    self.layoutBusy = true
    self.fontHeight = getTextManager():getFontHeight(UIFont.Small)
    self.lineHeight = self.fontHeight+3
    local buttonWidth = 128
    for _, b in ipairs({self.enableButton,self.disableButton,self.cancelButton,self.applyButton}) do
        buttonWidth = math.max(buttonWidth,math.ceil(measure(b.title))+24)
    end
    self.minimumWidth = math.min(math.max(480,buttonWidth*2+40),getCore():getScreenWidth()-16)
    if self.width < self.minimumWidth then
        self:setWidth(self.minimumWidth)
        self:setX(math.max(8,math.min(self.x,getCore():getScreenWidth()-8-self.width)))
    end
    self.nameX = math.max(measure(HWE.text("Enabled")),measure(HWE.text("Disabled")))+24
    self.countY = 12+getTextManager():getFontHeight(UIFont.Medium)+8
    local countLines = wrap(HWE.text("PickerCount",#HWE.Costumes,#HWE.Costumes,25), self.width-32)
    local searchY = self.countY+#countLines*self.lineHeight+10
    local buttonHeight = math.max(26,self.fontHeight+12)
    local categoryWidth = math.min(280,math.floor((self.width-32)*.38))
    self.category:setX(self.width-16-categoryWidth); self.category:setY(searchY)
    self.category:setWidth(categoryWidth); self.category:setHeight(buttonHeight)
    self.search:setWidth(self.category.x-24); self.search:setY(searchY); self.search:setHeight(buttonHeight)
    local help = #self.unknown > 0 and HWE.text("UnknownEntries",table.concat(self.unknown, ", "))
        or HWE.text("PickerApplyHelp")
    self.helpLines = wrap(help, self.width-32)
    self.helpText = help
    buttonWidth = math.min(buttonWidth,math.floor((self.width-40)/2))
    local bottomY = self.height-24-buttonHeight
    local upperY = bottomY-buttonHeight-8
    self.helpY = upperY-10-#self.helpLines*self.lineHeight
    self.list:setY(searchY+buttonHeight+10)
    self.list:setWidth(self.width-32)
    self.list:setHeight(math.max(50,self.helpY-12-self.list.y))
    for _, b in ipairs({self.enableButton,self.disableButton,self.cancelButton,self.applyButton}) do
        b:setWidth(buttonWidth); b:setHeight(buttonHeight)
    end
    self.enableButton:setY(upperY)
    self.disableButton:setX(24+buttonWidth); self.disableButton:setY(upperY)
    self.cancelButton:setY(bottomY)
    self.applyButton:setX(self.width-16-buttonWidth); self.applyButton:setY(bottomY)
    local rh = self.resizeBarHeight
    self.resizeRight:setX(self.width-rh); self.resizeRight:setY(self.height-rh)
    self.resizeBottom:setX(0); self.resizeBottom:setY(self.height-rh)
    self.resizeBottom:setWidth(self.width-rh); self.resizeBottom:setHeight(rh)
    self.minimumHeight = math.min(self.list.y+80+(self.height-self.helpY)+12,getCore():getScreenHeight()-16)
    self:layoutRows()
    self.layoutBusy = false
end

function Picker:onResize()
    ISPanel.onResize(self)
    self:layout()
end

function Picker:resizeFromCorner(side, start, dx, dy)
    local screenWidth, screenHeight = getCore():getScreenWidth(), getCore():getScreenHeight()
    local x, width = start.x, start.w
    if side == "left" then
        local right = start.x+start.w
        x = math.max(8, math.min(start.x+dx,right-self.minimumWidth))
        width = right-x
    elseif side ~= "bottom" then
        width = math.max(self.minimumWidth,math.min(start.w+dx,screenWidth-8-start.x))
    end
    self:setX(x); self:setWidth(width)
    self:layout()
    local height = math.max(self.minimumHeight,math.min(start.h+dy,screenHeight-8-start.y))
    self:setHeight(height)
    self:layout()
end

function Picker:refresh()
    if not self.list then return end
    self.list:clear()
    local search = self.search:getText():lower()
    local selected = self.category.selected
    local category = selected > 1 and self.categories[selected-1] or nil
    local choices={}
    for _,c in ipairs(HWE.Costumes) do choices[#choices+1]=c end
    for _,entry in ipairs(HWE.Items.catalog) do choices[#choices+1]={id=entry.fullType,name=entry.name,category="Items",poolGroup=entry.group} end
    for _, c in ipairs(choices) do
        local text = table.concat({HWE.choiceName(c),HWE.groupName(c.category),c.name,c.id,c.category,c.poolFamily or "",c.poolGroup or "",c.menuGroup or ""}, " ")
        if (not category or c.category == category or (c.category=="Items" and category=="Items: "..c.poolGroup))
            and text:lower():find(search, 1, true) then
            self.list:addItem(HWE.choiceName(c), c)
        end
    end
    self.lastSearch = search
    self:layoutRows()
end

function Picker:toggle(costume)
    if not costume then return end
    self.disabled[costume.id] = not self.disabled[costume.id] or nil
end
function Picker:setShown(disabled)
    for _, row in ipairs(self.list.items) do self.disabled[row.item.id] = disabled or nil end
end
function Picker:enableShown() self:setShown(false) end
function Picker:disableShown() self:setShown(true) end
function Picker:close()
    for _, grip in ipairs({self.resizeBottom,self.resizeRight}) do
        grip:finishDrag()
    end
    self:removeFromUIManager()
end
function Picker:apply()
    self.entry:setText(HWE.CostumeFilter.serialize(self.disabled, self.unknown))
    self:close()
end
function Picker:update()
    ISPanel.update(self)
    -- Release capture even if focus changed before the mouse-up event arrived.
    if type(isMouseButtonDown)=="function" and not isMouseButtonDown(0) then
        for _,grip in ipairs({self.resizeBottom,self.resizeRight}) do
            if grip.resizing then grip:finishDrag() end
        end
    end
    if self.fontHeight ~= getTextManager():getFontHeight(UIFont.Small) then self:layout() end
    if self.search and self.search:getText():lower() ~= self.lastSearch then self:refresh() end
    if not self.entry.parent or not self.entry.parent:isVisible() then self:close() end
end
function Picker:prerender()
    ISPanel.prerender(self)
    self:drawText(HWE.text("PickerTitle"), 16, 12, 1,0.65,0.2,1,UIFont.Medium)
    for i, line in ipairs(wrap(self:summary(),self.width-32)) do
        self:drawText(line,16,self.countY+(i-1)*self.lineHeight,.9,.9,.9,1,UIFont.Small)
    end
    for i, line in ipairs(self.helpLines) do
        self:drawText(line,16,self.helpY+(i-1)*self.lineHeight,.9,.8,.5,1,UIFont.Small)
    end
end
function Picker:render()
    -- The same status bar and triangle texture used by vanilla inventory.
    -- Render after the children so the resize cue remains visible.
    local rh, width, height = self.resizeBarHeight, self:getWidth(), self:getHeight()
    self:drawRectBorder(0, height-rh, width, rh, .7, 1, 1, 1)
    self:drawTextureScaled(self.statusbarbkg, 1, height-rh+1, width-2, rh-2, 1, 1, 1, 1)
    self:drawTextureScaled(self.resizeimage, width-rh+1, height-rh+1, rh-2, rh-2, 1, 1, 1, 1)
end
function Picker.drawRow(list, y, row, alt)
    local c = row.item
    local blocked = list.parent.disabled[c.id]
    list:drawRect(0,y,list.width,row.height,0.65,alt and 0.14 or 0.10,0.10,0.10)
    list:drawText(blocked and HWE.text("Disabled") or HWE.text("Enabled"), 8,y+4,
        blocked and 1 or 0.45, blocked and 0.5 or 0.9, 0.45,1,UIFont.Small)
    local textY = y+4
    for _, line in ipairs(row.nameLines) do
        list:drawText(line,list.parent.nameX,textY,1,1,1,1,UIFont.Small)
        textY = textY+list.parent.lineHeight
    end
    for _, line in ipairs(row.detailLines) do
        list:drawText(line,list.parent.nameX,textY,.65,.65,.65,1,UIFont.Small)
        textY = textY+list.parent.lineHeight
    end
    return y + row.height
end
function Picker.open(entry)
    if Picker.instance then Picker.instance:close() end
    local ui = Picker:new(entry); Picker.instance = ui
    ui:initialise(); ui:addToUIManager(); ui:bringToTop()
end

-- Keep the native text entry: presets and admin Save use their usual serializer.
-- The companion button only edits this window's draft, never SandboxVars directly.
local function install(class)
    if not class or class.HWEFilterInstalled then return end
    class.HWEFilterInstalled = true
    local original = class.createPanel
    local function decorate(entry)
        if not entry or entry.HWEFilterInstalled then return end
        entry.HWEFilterInstalled = true
        local oldWidth = entry:getWidth()
        local reserved = math.min(88, oldWidth-50)
        entry:setWidth(oldWidth-reserved)
        -- Reserve the button when vanilla later re-centers this control.
        local setX = entry.setX
        entry.setX = function(control, x) setX(control, x-reserved) end
        local b = ISButton:new(entry:getRight()+6,entry:getY(),82,entry:getHeight(),
            HWE.text("Choose"), entry, Picker.open)
        b:initialise(); b:instantiate(); entry.parent:addChild(b)
        b.tooltip = HWE.text("ChooseHelp")
        b.update = function(button)
            ISButton.update(button)
            button:setX(entry:getRight()+6); button:setY(entry:getY())
        end
    end
    class.createPanel = function(self, page)
        local panel = original(self, page)
        local entry = panel.controls and panel.controls["HalloweenEvent.CostumeBlacklist"]
        decorate(entry)
        return panel
    end
    -- Some menu screens already exist when OnGameBoot runs.
    local instance = class.instance
    if instance and instance.controls then
        decorate(instance.controls["HalloweenEvent.CostumeBlacklist"])
    end
end
local function boot()
    require "OptionScreens/SandboxOptions"
    require "ISUI/AdminPanel/ISServerSandboxOptionsUI"
    install(SandboxOptionsScreen); install(ISServerSandboxOptionsUI)
end
if Events and Events.OnGameBoot then Events.OnGameBoot.Add(boot) end
return Picker
