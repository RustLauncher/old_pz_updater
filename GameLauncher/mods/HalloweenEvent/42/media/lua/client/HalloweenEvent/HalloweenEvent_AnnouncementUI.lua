require "HalloweenEvent/HalloweenEvent_Shared"
require "HalloweenEvent/HalloweenEvent_AnnouncementText"
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "Chat/ISChat"
local HWE, T = HalloweenEvent, HalloweenEvent.AnnouncementText
if HWE.AnnouncementUI then return HWE.AnnouncementUI end
local A = {seen={}, order={}, acknowledgements={}, ready=false}
HWE.AnnouncementUI = A
local Banner = ISPanel:derive("EVHalloweenAnnouncementBanner")

local function now()
    return getTimestampMs()
end

function A.wrap(text, width, font)
    local tm, lines, line = getTextManager(), {}, ""
    local function fits(value) return tm:MeasureStringX(font,value)<=width end
    for word in text:gmatch("%S+") do
        local candidate = line=="" and word or line.." "..word
        if fits(candidate) then
            line = candidate
        else
            if line~="" then lines[#lines+1], line = line, "" end
            if fits(word) then
                line = word
            else
                for _, char in ipairs(T.characters(word)) do
                    if line~="" and not fits(line..char) then
                        lines[#lines+1], line = line, ""
                    end
                    line = line..char
                end
            end
        end
    end
    if line~="" then lines[#lines+1] = line end
    if #lines>3 then
        local chars = T.characters(lines[3])
        while #chars>0 and not fits(table.concat(chars).."...") do table.remove(chars) end
        lines = {lines[1],lines[2],table.concat(chars).."..."}
    end
    return lines
end

function Banner:clampPosition()
    self:setX(math.max(0,math.min(self:getX(),getCore():getScreenWidth()-self.width)))
    self:setY(math.max(0,math.min(self:getY(),getCore():getScreenHeight()-self.height)))
end

function Banner:close()
    if self.closed then return end
    self.closed, self.moving = true, false
    self:setCapture(false)
    A.position = {x=self:getX(),y=self:getY()}
    self:setVisible(false)
    self:removeFromUIManager()
    if A.banner==self then A.banner=nil end
end

function Banner:createChildren()
    local size = math.max(24,getTextManager():getFontHeight(UIFont.Small)+6)
    local button = ISButton:new(self.width-size-5,5,size,size,"X",self,Banner.close)
    button:initialise()
    button.backgroundColor = {r=0,g=0,b=0,a=0.25}
    button.borderColor = {r=1,g=0.45,b=0.08,a=0.6}
    button.textColor = {r=1,g=0.65,b=0.2,a=1}
    button.tooltip = getText("IGUI_HWE_CloseAnnouncement")
    self:addChild(button)
    self.closeButton = button
end

function Banner:render()
    for i, line in ipairs(self.lines) do
        self:drawTextCentre(line,self.textCenter,14+(i-1)*self.lineHeight,1,0.65,0.2,1,UIFont.Medium)
    end
end

function Banner:update()
    if now()>=self.expires then self:close() end
end

function Banner:onMouseDown(x,y)
    if self.closed or not self:isMouseOver() then return false end
    self.moving = true
    self:setCapture(true)
    self:bringToTop()
    return true
end

function Banner:onMouseMove(dx,dy)
    if self.moving then
        self:setX(self:getX()+dx)
        self:setY(self:getY()+dy)
        self:clampPosition()
    end
    return true
end
Banner.onMouseMoveOutside = Banner.onMouseMove

function Banner:onMouseUp(x,y)
    self.moving = false
    self:setCapture(false)
    return true
end
Banner.onMouseUpOutside = Banner.onMouseUp

function A.stopSound()
    if A.sound and A.sound~=0 then
        pcall(function() getSoundManager():stopUISound(A.sound) end)
    end
    A.sound=nil
end

function A.show(message,kind)
    if A.banner then A.banner:close() end
    A.stopSound()
    local width = math.min(math.max(560,getTextManager():getFontHeight(UIFont.Medium)*28),getCore():getScreenWidth()-40)
    local closeSize = math.max(24,getTextManager():getFontHeight(UIFont.Small)+6)
    local textWidth = width-math.max(76,closeSize+48)
    local lines = A.wrap(message,textWidth,UIFont.Medium)
    local lineHeight = getTextManager():getFontHeight(UIFont.Medium)+4
    local height = 28+#lines*lineHeight
    local pos = A.position or {x=(getCore():getScreenWidth()-width)/2,y=35}
    local banner = Banner:new(pos.x,pos.y,width,height)
    banner.textCenter = 14+textWidth/2
    banner.lines, banner.lineHeight, banner.expires = lines,lineHeight,now()+15000
    banner.backgroundColor = {r=0,g=0,b=0,a=0.75}
    banner.borderColor = {r=1,g=0.45,b=0.08,a=1}
    banner.wantMouseEvents = true
    banner:initialise()
    banner:addToUIManager()
    banner:clampPosition()
    banner:bringToTop()
    A.banner = banner
    -- A 2D native UI sound plays once per client (including split-screen).
    -- Never use a world emitter: no distance attenuation or zombie attraction.
    local ok, err = pcall(function()
        A.sound=getSoundManager():playUISound(kind=="end" and "EVHalloween_EventEnded" or "EVHalloween_EventStarted")
    end)
    if not ok then HWE.log("ANNOUNCEMENT_SOUND_FAILED "..tostring(err)) end
end

function A.addChat(message)
    local chat = ISChat and ISChat.instance
    if not chat or not chat.tabs or #chat.tabs==0 then return false end
    -- Tab-added can precede default-tab selection during connection setup.
    -- Wait for the same focus/default state that native addLineInChat needs.
    local tab = chat.defaultTab or chat.chatText
    if not tab or tab.tabID==nil then return false end
    -- Stock ISChat accepts this message interface. Keep the record in its
    -- history so changing chat prefix/font settings does not discard the line.
    local record = {text=message}
    function record:getAuthor() return "Server" end
    function record:getText() return self.text end
    function record:setText(text) self.text=text end
    function record:getTextWithPrefix() return T.chatLine(self.text) end
    ISChat.addLineInChat(record,tab.tabID)
    return true
end

local function send(command,args)
    local player=type(getPlayer)=="function" and getPlayer() or nil
    if not player then return false end
    if type(isClient)=="function" and isClient() and not (type(isServer)=="function" and isServer()) then
        if type(sendClientCommand)~="function" then return false end
        return pcall(sendClientCommand,player,HWE.MOD_ID,command,args or {})
    elseif HWE.Server then
        return HWE.Server.handleAdminCommand(command,player,args or {})~=false
    end
    return false
end
local function localData()
    local player=type(getPlayer)=="function" and getPlayer() or nil
    return player and HWE.safeCall(player,"getModData") or nil
end
local function remember(record)
    A.seen[record.id]=true
    A.order[#A.order+1]=record.id
    if #A.order>64 then A.seen[table.remove(A.order,1)]=nil end
    if not record.preview then
        local data=localData()
        if data then data[record.kind=="end" and "HWEAnnouncementEnd" or "HWEAnnouncementStart"]=record.id end
        A.acknowledgements[record.id]={id=record.id,kind=record.kind,next=now(),expires=now()+60000}
    end
end
local function hasSeen(record)
    if A.seen[record.id] then return true end
    local data=localData()
    return data and data[record.kind=="end" and "HWEAnnouncementEnd" or "HWEAnnouncementStart"]==record.id
end

function A.flush()
    local time=now()
    if A.pending then
        local pending=A.pending
        if time>=pending.expires then
            A.pending=nil
        elseif A.ready and type(getPlayer)=="function" and getPlayer() then
            A.pending=nil
            if hasSeen(pending) then
                remember(pending) -- confirm a durable local receipt without replay
            else
                local ok,err=pcall(A.show,pending.message,pending.kind)
                if ok then
                    remember(pending)
                    A.chatPending={message=pending.message,expires=time+15000}
                else HWE.log("ANNOUNCEMENT_BANNER_FAILED "..tostring(err)) end
            end
        end
    end
    if A.chatPending then
        local pending=A.chatPending
        if time>=pending.expires then A.chatPending=nil
        else
            local ok,done=pcall(A.addChat,pending.message)
            if not ok then
                HWE.log("ANNOUNCEMENT_CHAT_FAILED "..tostring(done));A.chatPending=nil
            elseif done then A.chatPending=nil end
        end
    end
end

function A.tick()
    if A.ready and A.synced and not A.pending and not A.chatPending then
        -- PZ's Kahlua runtime does not provide the standard Lua next() global.
        local awaitingReceipt=false
        for _ in pairs(A.acknowledgements) do awaitingReceipt=true;break end
        if not awaitingReceipt then return end
    end
    local time=now()
    local readyDue=not A.ready and A.readyAt and time>=A.readyAt
    if not readyDue and A.lastTick and time>=A.lastTick and time-A.lastTick<200 then return end
    A.lastTick=time
    if not A.ready and A.readyAt and time>=A.readyAt and type(getPlayer)=="function" and getPlayer() then
        A.ready=true;A.nextSync=time
    end
    A.flush()
    if not A.ready then return end
    for id,receipt in pairs(A.acknowledgements) do
        if time>=receipt.expires then A.acknowledgements[id]=nil
        elseif time>=receipt.next then
            receipt.next=time+3000
            send("AnnouncementSeen",{id=receipt.id,kind=receipt.kind})
        end
    end
    if not A.synced and (not A.nextSync or time>=A.nextSync) then
        A.nextSync=time+5000
        send("AnnouncementSync",{})
    end
end

function A.receive(module,command,args)
    if module~=HWE.MOD_ID or type(args)~="table" then return end
    if command=="AnnouncementReceipt" then
        if type(args.id)=="string" and (args.kind=="start" or args.kind=="end") then
            A.acknowledgements[args.id]=nil;A.synced=true
        end
        return
    elseif command=="AnnouncementStatus" then
        A.synced=args.active~=true or args.seen==true
        if A.pending and A.pending.kind=="start" and (args.active~=true or (args.seen==true and A.pending.id==args.id)) then A.pending=nil end
        return
    elseif command=="EventState" or command=="Status" then
        if args.active~=true and A.pending and A.pending.kind=="start" then A.pending=nil end
        return
    elseif command=="ResetAnnouncements" then
        A.seen,A.order,A.acknowledgements={},{},{}
        A.pending,A.chatPending=nil,nil
        local data=localData()
        if data then data.HWEAnnouncementStart,data.HWEAnnouncementEnd=nil,nil end
        if A.banner then A.banner:close() end
        A.stopSound()
        if args.kind~="start" and args.kind~="end" then return end
        return A.receive(module,args.kind=="end" and "EventEnded" or "EventStarted",args)
    end
    if command~="EventStarted" and command~="EventEnded" then return end
    if type(args.id)~="string" or #args.id>80 or type(args.message)~="string" then return end
    local kind=command=="EventEnded" and "end" or "start"
    if kind=="end" and A.pending and A.pending.kind=="start" then A.pending=nil end
    local record={id=args.id,kind=kind,message=T.clean(args.message,kind),preview=args.preview==true,expires=now()+60000}
    if hasSeen(record) then
        if not record.preview then
            A.acknowledgements[record.id]={id=record.id,kind=kind,next=now(),expires=now()+60000}
        end
        return
    end
    if A.pending and A.pending.id==record.id then return end
    A.pending=record
    A.flush()
end

local function onGameStart()
    -- Request only after the world/UI has loaded, then allow five real seconds
    -- before showing a pending announcement or asking for an unseen start.
    A.ready=false;A.readyAt=now()+5000;A.synced=false;A.nextSync=A.readyAt
end
if Events.OnServerCommand then Events.OnServerCommand.Add(A.receive) end
if Events.OnTick then Events.OnTick.Add(A.tick) end
if Events.OnTickEvenPaused then Events.OnTickEvenPaused.Add(A.tick) end
if Events.OnGameStart then Events.OnGameStart.Add(onGameStart) end
return A
