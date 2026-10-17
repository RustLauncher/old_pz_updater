require "HalloweenEvent/HalloweenEvent_Shared"
require "ISUI/ISLabel"
require "ISUI/ISButton"
local HWE=HalloweenEvent
local UI={}
HWE.ScheduleUI=UI
local function remote()
    return type(isClient)=="function" and isClient()
        and not (type(isServer)=="function" and isServer())
end
local function dispatch(command,args)
    require "HalloweenEvent/HalloweenEvent_Client"
    if HWE.Client and HWE.Client.dispatch then return HWE.Client.dispatch(command,args,0) end
    return false
end
local function liveWorld()
    return type(getPlayer)=="function" and getPlayer()~=nil
end
function UI.cleanSlate()
    if liveWorld() then dispatch("CleanSlate",{}) end
end
function UI.clockText(now)
    if not remote() then return getText("IGUI_EVH_LocalUTC",HWE.Schedule.format(now)) end
    if not UI.nextRequest or (UI.lastRequest and now<UI.lastRequest) or now>=UI.nextRequest then
        local player=type(getSpecificPlayer)=="function" and getSpecificPlayer(0) or nil
        if player and type(sendClientCommand)=="function" then
            local ok=pcall(sendClientCommand,player,HWE.MOD_ID,"ScheduleClock",{})
            if ok then UI.lastRequest=now;UI.nextRequest=now+15 end
        end
    end
    if UI.epoch and now>=UI.received and now-UI.received<=90 then
        return getText("IGUI_EVH_ServerUTC",HWE.Schedule.format(UI.epoch+now-UI.received))
    end
    return getText("IGUI_EVH_ServerUTCWaiting")
end
function UI.receive(module,command,args)
    if module~=HWE.MOD_ID or command~="ScheduleClock" or type(args)~="table" or args.zone~="UTC" then return end
    local epoch=tonumber(args.epoch)
    local now=HWE.Schedule.now()
    if epoch and epoch==epoch and math.abs(epoch)~=math.huge and now then
        UI.epoch=math.floor(epoch);UI.received=now
    end
end
local function tips(panel,irl)
    for _,part in ipairs({"Start","End"}) do
        local key="HalloweenEvent."..part.."Schedule"
        local control=panel.controls[key]
        local tooltip=getText("Sandbox_HWE_"..(irl and "IRL"..part or "Schedule"..part).."_tooltip")
        if control then control.tooltip=tooltip end
        if panel.labels and panel.labels[key] then panel.labels[key].tooltip=tooltip end
    end
end
function UI.attach(panel)
    local clock=panel and panel.controls and panel.controls["HalloweenEvent.ScheduleClock"]
    if not clock or panel.EVHScheduleClock then return end
    panel.EVHScheduleClock=true
    local parent=clock.parent
    local height=getTextManager():getFontHeight(UIFont.Small)
    local enabled=panel.controls["HalloweenEvent.EnableEvent"]
    if enabled then
        local title=HWE.text("CleanSlate")
        local width=getTextManager():MeasureStringX(UIFont.Small,title)+20
        local button=ISButton:new(enabled:getX()+28,enabled:getY(),width,enabled:getHeight(),title,UI,UI.cleanSlate)
        button:initialise();button:instantiate();parent:addChild(button)
        button.tooltip=HWE.text("CleanSlateHelp")
        button:setEnable(liveWorld())
        panel.EVHCleanSlate=button
    end
    local padding=height+10
    local bottom=clock:getBottom()
    -- Reserve one read-only clock row; the existing controls and draft values
    -- remain stock sandbox widgets. No fake/editable clock setting is saved.
    local rows={}
    for _,child in pairs(parent:getChildren()) do
        if child:getY()>bottom then rows[#rows+1]={child=child,y=child:getY()} end
    end
    local scrollHeight=parent:getScrollHeight()
    local label=ISLabel:new(10,bottom+3,height,"",.75,.85,1,1,UIFont.Small,true)
    label:initialise();label:instantiate();parent:addChild(label)
    label:setVisible(false)
    local original=panel.prerender
    panel.prerender=function(self,...)
        if original then original(self,...) end
        if self.EVHCleanSlate then self.EVHCleanSlate:setEnable(liveWorld()) end
        local irl=clock.selected==2
        label:setVisible(irl)
        if self.EVHClockMode~=irl then
            for _,row in ipairs(rows) do row.child:setY(row.y+(irl and padding or 0)) end
            parent:setScrollHeight(scrollHeight+(irl and padding or 0))
            tips(self,irl);self.EVHClockMode=irl
        end
        if irl then
            local now=HWE.Schedule.now()
            if now and self.EVHClockLastSecond~=now then
                self.EVHClockLastSecond=now
                label:setName(UI.clockText(now))
            end
        end
    end
    panel.EVHClockLabel=label
end
local function install(class)
    if not class or class.EVHScheduleClockInstalled then return end
    class.EVHScheduleClockInstalled=true
    local original=class.createPanel
    class.createPanel=function(self,page)
        local panel=original(self,page)
        UI.attach(panel)
        return panel
    end
end
local function boot()
    require "OptionScreens/SandboxOptions"
    require "ISUI/AdminPanel/ISServerSandboxOptionsUI"
    install(SandboxOptionsScreen);install(ISServerSandboxOptionsUI)
    local class=ISServerSandboxOptionsUI
    if class and not class.EVHSandboxApplyInstalled then
        class.EVHSandboxApplyInstalled=true
        local original=class.onButtonApply
        class.onButtonApply=function(self,...)
            original(self,...)
            -- Native SP Apply updates Java options without refreshing SandboxVars.
            if not remote() and type(getSandboxOptions)=="function" then getSandboxOptions():toLua() end
            local expected={}
            for _,field in ipairs({"EnableEvent","UseCalendarTrigger","ScheduleClock","StartSchedule","EndSchedule"}) do
                local option=self.options:getOptionByName("HalloweenEvent."..field)
                if option then expected[field]=option:getValue() end
            end
            dispatch("SandboxApplied",expected)
        end
    end
end
if Events.OnGameBoot then Events.OnGameBoot.Add(boot) end
if Events.OnServerCommand then Events.OnServerCommand.Add(UI.receive) end
return UI
