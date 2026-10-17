require "HalloweenEvent/HalloweenEvent_AnnouncementText"
local HWE = HalloweenEvent
if HWE.AnnouncementServer then return HWE.AnnouncementServer end
local A = {requests={}}
HWE.AnnouncementServer = A
local fallback = {}

local function state()
    if ModData and type(ModData.getOrCreate)=="function" then
        return ModData.getOrCreate("HalloweenEvent.StartAnnouncement")
    end
    return fallback
end

local function activationKey(cfg)
    local server = HWE.Server
    if not cfg or not cfg.UseCalendarTrigger or (server and server.runtimeManualOverride~=nil) then return "active" end
    if cfg.ScheduleClock==2 then
        local window = HWE.Schedule.resolve(cfg,HWE.Schedule.now())
        if window and window.active then return "UTC:"..tostring(window.start) end
    else
        local gt = type(getGameTime)=="function" and getGameTime() or nil
        local year = HWE.safeCall(gt,"getYear") or 0
        local function value(m,d,h,minute) return (((m*32+d)*24+h)*60+minute) end
        local first = value(cfg.StartMonth,cfg.StartDay,cfg.StartHour,cfg.StartMinute)
        local finish = value(cfg.EndMonth,cfg.EndDay,cfg.EndHour,cfg.EndMinute)
        local current = value((HWE.safeCall(gt,"getMonth") or 0)+1,HWE.safeCall(gt,"getDayPlusOne") or 1,
            HWE.safeCall(gt,"getHour") or 0,HWE.safeCall(gt,"getMinutes") or 0)
        if finish<first and current<first then year=year-1 end
        return "Game:"..tostring(year)..":"..tostring(cfg.StartSchedule)..":"..tostring(cfg.EndSchedule)
    end
    return "active"
end

local function authoritative()
    return not (type(isClient)=="function" and isClient()) or (type(isServer)=="function" and isServer())
end
local function account(player)
    if not player then return nil end
    local username = HWE.safeCall(player,"getUsername")
    if username and username~="" then return "account:"..tostring(username) end
    if type(isServer)=="function" and isServer() then return nil end
    return "local:"..tostring(HWE.safeCall(player,"getPlayerNum") or 0)
end
local function ledger()
    local data=state()
    data.seenStart=data.seenStart or {}
    data.seenEnd=data.seenEnd or {}
    return data
end
local function stamp()
    return type(getTimestampMs)=="function" and getTimestampMs() or 0
end
local function makeRecord(data,kind,cfg)
    data.serial=(tonumber(data.serial) or 0)+1
    return {id=tostring(stamp())..":"..tostring(data.serial)..":"..kind,kind=kind,
        message=HWE.AnnouncementText.clean(cfg and (kind=="end" and cfg.EventEndMessage or cfg.EventStartMessage),kind)}
end
local function send(command,args,player)
    if type(isServer)=="function" and isServer() then
        if type(sendServerCommand)~="function" then return false end
        if not player then
            local players=type(getOnlinePlayers)=="function" and getOnlinePlayers() or nil
            if not players or players:size()==0 then return false end
        end
        local ok,err
        if player then ok,err=pcall(sendServerCommand,player,HWE.MOD_ID,command,args)
        else ok,err=pcall(sendServerCommand,HWE.MOD_ID,command,args) end
        if not ok then HWE.log("ANNOUNCEMENT_SEND_FAILED command="..command.." error="..tostring(err)) end
        return ok
    elseif HWE.AnnouncementUI then
        HWE.AnnouncementUI.receive(HWE.MOD_ID,command,args)
        return true
    end
    return false
end
local function offer(record,player)
    return send(record.kind=="end" and "EventEnded" or "EventStarted",record,player)
end

function A.transition(active,changed,cfg)
    if not authoritative() then return end
    active=active==true
    local data=ledger()
    local wasActive=data.active==true
    local previousKey,key=data.key,active and activationKey(cfg) or nil
    data.active,data.key=active,key
    if active then
        local same=wasActive and (previousKey==key or previousKey=="active" or key=="active")
        if changed and not same then
            data.started=makeRecord(data,"start",cfg)
            offer(data.started)
            HWE.log("START_ANNOUNCEMENT id="..data.started.id.." delivery=live+unseen-login")
        elseif not data.started then
            -- Upgrade an active Fix28 save to the per-account receipt protocol.
            -- Login requests deliver this record; ordinary refreshes never replay it.
            data.started=makeRecord(data,"start",cfg)
        end
    elseif changed then
        data.ended=makeRecord(data,"end",cfg)
        offer(data.ended)
        HWE.log("END_ANNOUNCEMENT id="..data.ended.id.." delivery=live")
    end
end

function A.sync(player)
    if not authoritative() then return false end
    local key=account(player)
    if not key then return false end
    local data=ledger()
    local active=HWE.Server and HWE.Server.active==true
    local record=active and data.started or nil
    local seen=record and data.seenStart[key]==record.id or false
    if record and not seen then
        local requestKey=key..":"..tostring(HWE.safeCall(player,"getOnlineID") or "local")
        local last=A.requests[requestKey]
        local time=stamp()
        if not last or last.id~=record.id or time<last.time or time-last.time>=5000 then
            A.requests[requestKey]={id=record.id,time=time}
            offer(record,player)
            HWE.log("ANNOUNCEMENT_LOGIN id="..record.id.." unseen=true")
        end
    end
    send("AnnouncementStatus",{active=active,seen=seen,id=record and record.id or nil},player)
    return true
end

function A.acknowledge(player,args)
    if not authoritative() then return false end
    local key=account(player)
    if not key or type(args)~="table" then return false end
    local data=ledger()
    local record=args.kind=="start" and data.started or (args.kind=="end" and data.ended or nil)
    if not record or record.id~=args.id then return false end
    local receipts=args.kind=="end" and data.seenEnd or data.seenStart
    local first=receipts[key]~=record.id
    receipts[key]=record.id
    send("AnnouncementReceipt",{id=record.id,kind=args.kind},player)
    if first then HWE.log("ANNOUNCEMENT_SEEN id="..record.id.." kind="..args.kind) end
    return true
end

function A.reset(player,cfg)
    if not authoritative() then return false end
    local key=account(player)
    if not key then return false end
    local data=ledger()
    data.seenStart[key],data.seenEnd[key]=nil,nil
    local active=HWE.Server and HWE.Server.active==true
    local kind=active and "start" or "end"
    local record=active and data.started or data.ended
    local args={id=record and record.id or "preview:"..tostring(stamp()),kind=kind,preview=record==nil,
        message=HWE.AnnouncementText.clean(cfg and (kind=="end" and cfg.EventEndMessage or cfg.EventStartMessage),kind)}
    HWE.log("ANNOUNCEMENT_RESET kind="..kind.." scope=requesting_admin eventUnchanged=true")
    return send("ResetAnnouncements",args,player)
end
return A
