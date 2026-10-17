-- UTC calendar math uses the native epoch clock, never the machine's timezone.
-- No os.date/os.time dependency: the same dates work in SP, co-op and servers.
HalloweenEvent=HalloweenEvent or {}
local S={}
HalloweenEvent.Schedule=S
local beforeMonth={0,31,59,90,120,151,181,212,243,273,304,334}
local monthDays={31,28,31,30,31,30,31,31,30,31,30,31}
local function leap(year)
    return year%4==0 and (year%100~=0 or year%400==0)
end
local function yearDays(year)
    local y=year-1
    return 365*y+math.floor(y/4)-math.floor(y/100)+math.floor(y/400)-719162
end
function S.now()
    if type(getTimestamp)~="function" then return nil end
    local value=tonumber(getTimestamp())
    if not value or value~=value or math.abs(value)==math.huge then return nil end
    return math.floor(value)
end
function S.utc(epoch)
    if not epoch then return nil end
    local day=math.floor(epoch/86400)
    local seconds=epoch-day*86400
    local year=1970+math.floor(day/365.2425)
    while day<yearDays(year) do year=year-1 end
    while day>=yearDays(year+1) do year=year+1 end
    day=day-yearDays(year)
    local month=1
    while true do
        local count=monthDays[month]+((month==2 and leap(year)) and 1 or 0)
        if day<count then break end
        day=day-count;month=month+1
    end
    return {year=year,month=month,day=day+1,hour=math.floor(seconds/3600),
        minute=math.floor(seconds%3600/60),second=seconds%60}
end
function S.format(epoch)
    local date=S.utc(epoch)
    if not date then return "--" end
    return string.format("%04d-%02d-%02d %02d:%02d:%02d",date.year,date.month,date.day,date.hour,date.minute,date.second)
end
local function valid(date,year)
    if not date then return false end
    for _,key in ipairs({"month","day","hour","minute"}) do
        local v=date[key]
        if type(v)~="number" or v~=math.floor(v) then return false end
    end
    if date.month<1 or date.month>12 or date.hour<0 or date.hour>23 or date.minute<0 or date.minute>59 then return false end
    local max=monthDays[date.month]
    if date.month==2 and (not year or leap(year)) then max=29 end
    return date.day>=1 and date.day<=max
end
function S.epoch(year,date)
    if not valid(date,year) then return nil end
    local days=yearDays(year)+beforeMonth[date.month]+date.day-1
    if date.month>2 and leap(year) then days=days+1 end
    return days*86400+date.hour*3600+date.minute*60
end
local function parse(raw,month,day,hour,minute)
    local date
    if raw~=nil then
        local text=tostring(raw):match("^%s*(.-)%s*$")
        -- CustomStringSandboxOption keeps the quotes in script defaults.
        -- Old saves therefore need paired outer quotes removed before parsing.
        local first,last=text:sub(1,1),text:sub(-1)
        if #text>=2 and (first=='"' or first=="'") and last==first then
            text=text:sub(2,-2):match("^%s*(.-)%s*$")
        end
        local m,d,h,n=text:match("^(%d%d?)/(%d%d?)%s+(%d%d?):(%d%d?)$")
        date={month=tonumber(m),day=tonumber(d),hour=tonumber(h),minute=tonumber(n)}
    else date={month=month,day=day,hour=hour,minute=minute} end
    return valid(date) and date or nil
end
local function order(date)
    return ((date.month*32+date.day)*24+date.hour)*60+date.minute
end
function S.inspect(cfg,now)
    now=now or S.now()
    if not now then return nil,"UTC clock unavailable" end
    local start=parse(cfg.StartSchedule,cfg.StartMonth,cfg.StartDay,cfg.StartHour,cfg.StartMinute)
    local finish=parse(cfg.EndSchedule,cfg.EndMonth,cfg.EndDay,cfg.EndHour,cfg.EndMinute)
    if not start or not finish then return nil,"Use a valid MM/DD HH:MM date (no year), with hours 00-23 and minutes 00-59" end
    local year=S.utc(now).year
    local wraps=order(finish)<order(start)
    local nextWindow,previousWindow
    -- Keep the previous occurrence as well as the next one for closed/manual
    -- states. Eight years cover Feb 29 across a non-leap century in either direction.
    for y=year-8,year+8 do
        local first=S.epoch(y,start)
        local last=S.epoch(y+(wraps and 1 or 0),finish)
        if first and last then
            -- Real time ends at HH:MM:00; retain the existing inclusive game minute.
            if cfg.ScheduleClock==1 then last=last+60 end
            local window={start=first,finish=last,active=now>=first and now<last}
            if first<=now and (not previousWindow or first>previousWindow.start) then previousWindow=window end
            if first>now and (not nextWindow or first<nextWindow.start) then nextWindow=window end
        end
    end
    local window=previousWindow and previousWindow.active and previousWindow or nextWindow
    if not window then return nil,"No valid upcoming date" end
    return {now=now,past=previousWindow,future=nextWindow,window=window}
end
function S.resolve(cfg,now)
    local sample,err=S.inspect(cfg,now)
    return sample and sample.window or nil,err
end
function S.date(raw,month,day,hour,minute)
    return parse(raw,month,day,hour,minute)
end
function S.active(cfg)
    local window,err=S.resolve(cfg)
    local key=err and (tostring(cfg.StartSchedule)..":"..tostring(cfg.EndSchedule)..":"..err)
        or (tostring(window.start)..":"..tostring(window.finish))
    if S.lastLog~=key then
        S.lastLog=key
        if err then HalloweenEvent.log("SCHEDULE_INVALID clock=UTC reason="..err
            .." start="..string.format("%q",tostring(cfg.StartSchedule):sub(1,120))
            .." end="..string.format("%q",tostring(cfg.EndSchedule):sub(1,120)))
        else HalloweenEvent.log("SCHEDULE_WINDOW clock=UTC start="..S.format(window.start)
            .." end="..S.format(window.finish).." annual=true") end
    end
    return window and window.active or false
end
return S
