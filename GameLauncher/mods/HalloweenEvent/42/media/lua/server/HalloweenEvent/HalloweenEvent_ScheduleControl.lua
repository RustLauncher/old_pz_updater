require "HalloweenEvent/HalloweenEvent_Shared"
local HWE,S=HalloweenEvent,HalloweenEvent.Schedule
if HWE.ScheduleControl then return HWE.ScheduleControl end
local C={}
HWE.ScheduleControl=C
local fallback={}
local function state()
    if ModData and type(ModData.getOrCreate)=="function" then return ModData.getOrCreate("HalloweenEvent.ScheduleControl") end
    return fallback
end
local function signature()
    local sb=SandboxVars and SandboxVars.HalloweenEvent or {}
    local keys,parts={},{}
    for key in pairs(sb) do keys[#keys+1]=tostring(key) end
    table.sort(keys)
    for _,key in ipairs(keys) do
        local value=tostring(sb[key]);parts[#parts+1]=key.."="..#value..":"..value
    end
    return table.concat(parts,";")
end
local function key(mode,window)
    return window and tostring(mode)..":"..tostring(window.start) or nil
end
function C.sample(cfg)
    local mode=cfg.ScheduleClock==2 and 2 or 1
    local first,last,now
    if mode==2 then
        first=S.date(cfg.StartSchedule);last=S.date(cfg.EndSchedule);now=S.now()
    else
        first=S.date(nil,cfg.StartMonth,cfg.StartDay,cfg.StartHour,cfg.StartMinute)
        last=S.date(nil,cfg.EndMonth,cfg.EndDay,cfg.EndHour,cfg.EndMinute)
        local gt=type(getGameTime)=="function" and getGameTime() or nil
        if gt then now=S.epoch(HWE.safeCall(gt,"getYear") or 1993,{
            month=(HWE.safeCall(gt,"getMonth") or 0)+1,day=HWE.safeCall(gt,"getDayPlusOne") or ((HWE.safeCall(gt,"getDay") or 0)+1),
            hour=HWE.safeCall(gt,"getHour") or 0,minute=HWE.safeCall(gt,"getMinutes") or 0}) end
    end
    local startSignature=tostring(mode)..":"..(first and string.format("%02d/%02d %02d:%02d",first.month,first.day,first.hour,first.minute) or tostring(cfg.StartSchedule))
    if not first or not last or not now then return {mode=mode,startSignature=startSignature,now=now,error="Invalid schedule date or clock unavailable"} end
    local sample,err=S.inspect({ScheduleClock=mode,StartMonth=first.month,StartDay=first.day,StartHour=first.hour,StartMinute=first.minute,
        EndMonth=last.month,EndDay=last.day,EndHour=last.hour,EndMinute=last.minute},now)
    sample=sample or {now=now,error=err}
    sample.mode,sample.startSignature=mode,startSignature
    return sample
end
local function rememberConfig(data,cfg,sample)
    data.signature=signature();data.startSignature=sample.startSignature
    data.enabled=cfg.EnableEvent;data.automatic=cfg.UseCalendarTrigger;data.mode=sample.mode
end
local function close(data,sample)
    local window
    if data.activeStart and sample.now and data.activeStart<=sample.now and data.mode==sample.mode then
        window={start=data.activeStart}
    else window=sample.past end
    data.closed=key(sample.mode,window)
    data.used=data.closed
    data.active=false;data.activeStart=nil;data.activeEnd=nil
end
local function anchor(data,sample,window)
    if not window then return end
    data.activeStart=window.start;data.activeEnd=window.finish
    data.used=key(sample.mode,window)
end
function C.noteApplied() C.applied=true end
function C.force(active,cfg)
    local data,sample=state(),C.sample(cfg)
    if active and cfg.EnableEvent then
        data.active=true;data.closed=nil;data.blockContinuous=false
        if cfg.UseCalendarTrigger then anchor(data,sample,sample.window) end
    else
        close(data,sample);data.blockContinuous=true
    end
    rememberConfig(data,cfg,sample);C.initialized=true
end
function C.clean(cfg)
    C.force(false,cfg)
    C.applied=false
    HWE.log("SCHEDULE_CLEAN_SLATE active=false nextFutureStartArmed=true pastStartHeld=true")
end
function C.resume()
    local data=state();data.closed=nil;data.used=nil;data.blockContinuous=false
    C.resumeRequested=true
end
local function endWindow(data,sample,startChanged)
    if sample.window and sample.window.active then return sample.window end
    if sample.past and sample.past.start==data.activeStart then return sample.past end
    if startChanged and sample.past and S.utc(sample.past.start).year==S.utc(sample.now).year then return sample.past end
    return sample.future
end
function C.evaluate(cfg,liveActive)
    local data,sample=state(),C.sample(cfg)
    local initial=not C.initialized
    local active=liveActive
    if initial and data.active~=nil then active=data.active end
    C.initialized=true
    local changed=data.signature~=signature()
    local applied=C.applied==true;C.applied=false
    local startChanged=data.startSignature~=sample.startSignature
    local reenabled=data.enabled==false and cfg.EnableEvent
    local autoChanged=data.automatic~=nil and data.automatic~=cfg.UseCalendarTrigger
    if startChanged or reenabled or autoChanged then
        data.closed=nil;data.used=nil;data.blockContinuous=false
    end
    local reason=changed and "sandbox_changed" or (applied and "sandbox_applied" or "schedule_tick")
    local desired,expired=false,false
    if not cfg.EnableEvent then
        if active then close(data,sample) end
        desired=false;reason="master_disabled"
    elseif not cfg.UseCalendarTrigger then
        desired=active or not data.blockContinuous
        data.activeStart=nil;data.activeEnd=nil
    elseif sample.error then
        desired=active==true
        if data.error~=sample.error then HWE.log("SCHEDULE_CONTROL_INVALID "..sample.error) end
        data.error=sample.error
    else
        data.error=nil
        if active then
            local window=endWindow(data,sample,startChanged)
            if window then
                anchor(data,sample,window)
                expired=sample.now>=window.finish
            end
            desired=not expired
            if expired then close(data,sample);reason="schedule_end" end
        end
        local window=sample.window
        if (not active or expired) and window and window.active then
            local occurrence=key(sample.mode,window)
            if occurrence~=data.closed and occurrence~=data.used then
                desired=true;anchor(data,sample,window);reason="schedule_start"
            end
        end
        -- First load catches up inside an unconsumed window; a closed saved
        -- occurrence stays off. Future annual starts have different keys.
        if initial and data.active==nil and not liveActive and window and window.active and not data.closed and not data.used then
            desired=true;anchor(data,sample,window);reason="schedule_start"
        end
    end
    data.active=desired==true
    rememberConfig(data,cfg,sample)
    local clearManual=changed or applied or C.resumeRequested or reason=="schedule_start" or reason=="schedule_end"
    C.resumeRequested=false
    if changed or applied then HWE.log("SCHEDULE_RECONCILE active="..tostring(desired).." newStart="..tostring(startChanged)
        .." closed="..tostring(data.closed).." automatic="..tostring(cfg.UseCalendarTrigger).." reason="..reason) end
    return desired==true,reason,clearManual,expired and desired==true
end
return C
