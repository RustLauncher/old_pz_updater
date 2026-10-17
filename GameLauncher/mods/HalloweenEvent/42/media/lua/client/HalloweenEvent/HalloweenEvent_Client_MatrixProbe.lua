-- v8: read-only native-outfit observer + cohort census. No random costume assignment.
-- Build 42 coop may report zombie onlineID=-1 on the server: a unique,
-- short-range spatial match is allowed, but ambiguous candidates are NEVER
-- counted as a success or failure.
require "HalloweenEvent/HalloweenEvent_Shared"
local HWE=HalloweenEvent
local probes={}
local census=nil
local tick=0
local stats={requests=0, early=0, late=0, missing=0, failed=0,
    online=0,spatial=0,marker=0,ambiguous=0,unmatched=0}
local GRID=5
local function safe(o,m,...) return HWE.safeCall(o,m,...) end
local function activeClient()
    return type(isClient)=="function" and isClient()==true
        and not (type(isServer)=="function" and isServer()==true)
end
local function bucket(x,y,z)
    return math.floor(x/GRID)..":"..math.floor(y/GRID)..":"..math.floor(z)
end
local function visualStamp(visuals)
    local count=tonumber(safe(visuals,"size"))
    if not count then return "" end
    local found={}
    for i=0,math.min(count,64)-1 do
        local v=safe(visuals,"get",i)
        local name=safe(v,"getItemType")
        if name and tostring(name)~="" then found[#found+1]=tostring(name) end
    end
    table.sort(found)
    return table.concat(found,",")
end
local function raw(z)
    local items=visualStamp(safe(z,"getItemVisuals"))
    if items~="" then return items,"item",0 end
    local human=safe(z,"getHumanVisual")
    local humanItems=visualStamp(safe(human,"getItemVisuals"))
    if humanItems~="" then return humanItems,"human",0 end
    local worn=safe(z,"getWornItems")
    local wornCount=tonumber(safe(worn,"size")) or 0
    return "",wornCount>0 and "worn_only" or "none",wornCount
end
local function valid(p,z)
    if not z or safe(z,"isAlive")~=true then return false end
    local x,y,zpos=tonumber(safe(z,"getX")),tonumber(safe(z,"getY")),tonumber(safe(z,"getZ"))
    if not x or not y or not zpos or math.abs(zpos-p.z)>1.5 then return false end
    if type(p.female)=="boolean" and (safe(z,"isFemale")==true)~=p.female then return false end
    return true,x,y
end
local function sendReport(p,stage)
    local z=p.zombie
    local yes,x,y=valid(p,z)
    if not yes then return false end
    if (x-p.x)^2+(y-p.y)^2>2500 then return false end
    local types,source,worn=raw(z)
    local payload={Trial=p.trial,Nonce=p.nonce,Batch=p.batch,
        OnlineID=p.onlineID,MatchedOnlineID=tonumber(safe(z,"getOnlineID")) or -1,
        MatchMode=p.mode,MatchDistance=p.distance,Stage=stage,
        Types=string.sub(types,1,2000),Source=source,WornCount=worn,
        NativeID=tonumber(safe(z,"getPersistentOutfitID")) or 0,
        X=x,Y=y,Z=tonumber(safe(z,"getZ"))}
    local player=type(getPlayer)=="function" and getPlayer() or nil
    if not player or type(sendClientCommand)~="function" then return false end
    local ok=pcall(sendClientCommand,player,HWE.MOD_ID,"MatrixClientResult",payload)
    if ok then
        HWE.log("MATRIX_CLIENT_PROBE stage="..stage.." trial="..p.trial
            .." mode="..tostring(p.mode).." distance="..tostring(p.distance)
            .." visible="..tostring(types~="").." worn="..worn)
        if stage==1 then stats.early=stats.early+1 else stats.late=stats.late+1 end
    else stats.failed=stats.failed+1 end
    return ok
end
local function register(args)
    if type(args)~="table" then return end
    local x,y,z=tonumber(args.X),tonumber(args.Y),tonumber(args.Z)
    local id=tonumber(args.OnlineID) or -1
    if not x or not y or not z or type(args.Trial)~="string"
        or type(args.Nonce)~="string" or #args.Nonce>100 then return end
    local old=probes[args.Trial]
    if old and old.nonce==args.Nonce then return end
    if stats.requests>=1200 then return end
    probes[args.Trial]={trial=args.Trial,nonce=args.Nonce,batch=args.Batch,
        onlineID=id,x=x,y=y,z=z,female=args.Female, native=tonumber(args.NativeID) or 0,
        start=tick,early=false,late=false,mode=nil,distance=nil}
    stats.requests=stats.requests+1
end
local function serverCommand(module,cmd,args)
    if not activeClient() or module~=HWE.MOD_ID or type(args)~="table" then return end
    if cmd=="MatrixCensusSchema" then
        if type(args.Signatures)~="table" or type(args.Positions)~="table"
            or #args.Signatures>450 or #args.Positions>450
            or type(args.Nonce)~="string" or #args.Nonce>100 then return end
        local known={}
        for i,row in ipairs(args.Signatures) do
            if type(row)~="table" or type(row.Stamp)~="string" or #row.Stamp>2000 then return end
            known[row.Stamp]=i
        end
        local cells={}
        for _,pos in ipairs(args.Positions) do
            if type(pos)~="table" then return end
            local x,y,z=tonumber(pos[1]),tonumber(pos[2]),tonumber(pos[3])
            if x and y and z then
                local key=bucket(x,y,z)
                cells[key]=cells[key] or {}
                cells[key][#cells[key]+1]={x,y,z}
            end
        end
        census={batch=tonumber(args.Batch),nonce=args.Nonce,
            known=known,signatures=args.Signatures,cells=cells,
            radius=math.min(tonumber(args.Radius) or 14,20),start=tick,
            early=false,late=false}
        HWE.log("MATRIX_CENSUS_CLIENT_READY batch="..tostring(args.Batch)
            .." signatures="..#args.Signatures.." seedLocations="..#args.Positions)
        return
    end
    if cmd=="MatrixProbeBatch" and type(args.Entries)=="table" then
        for i=1,math.min(#args.Entries,48) do register(args.Entries[i]) end
    elseif cmd=="MatrixProbeRequest" then register(args) end
end
local function buildIndex()
    local cell=type(getCell)=="function" and getCell() or nil
    local zombies=safe(cell,"getZombieList")
    local count=tonumber(safe(zombies,"size")) or 0
    local spatial,byOnline,byMarker,markerConflict={},{},{},{}
    for i=0,math.min(count,1800)-1 do
        local z=safe(zombies,"get",i)
        if z and safe(z,"isAlive")==true then
            local x,y,level=tonumber(safe(z,"getX")),tonumber(safe(z,"getY")),tonumber(safe(z,"getZ"))
            if x and y and level then
                local info={z=z,x=x,y=y,level=level,female=(safe(z,"isFemale")==true),
                    online=tonumber(safe(z,"getOnlineID")) or -1}
                local key=bucket(x,y,level)
                spatial[key]=spatial[key] or {}
                spatial[key][#spatial[key]+1]=info
                if info.online>=0 then byOnline[info.online]=info end
                local md=safe(z,"getModData")
                local trial=type(md)=="table" and md.HalloweenEventMatrixTrialID or nil
                if trial~=nil then
                    trial=tostring(trial)
                    if byMarker[trial] then markerConflict[trial]=true end
                    byMarker[trial]=info
                end
            end
        end
    end
    for key in pairs(markerConflict) do byMarker[key]=nil end
    return spatial,byOnline,byMarker
end
local function match(p,spatial,byOnline,byMarker)
    -- If the engine synchronized the server marker with this exact zombie,
    -- this is stronger than any positional guess in a 400-zombie horde.
    local marked=byMarker[p.trial]
    if marked and marked.female==p.female and math.abs(marked.level-p.z)<1.5 then
        local d2=(marked.x-p.x)^2+(marked.y-p.y)^2
        if d2<=2500 then return marked.z,"marker",math.sqrt(d2) end
    end
    if p.onlineID>=0 then
        local info=byOnline[p.onlineID]
        if info and info.female==p.female then
            local d2=(info.x-p.x)^2+(info.y-p.y)^2
            if math.abs(info.level-p.z)<1.5 and d2<=2.56 then
                return info.z,"online",math.sqrt(d2)
            end
        end
        return nil
    end
    -- This is not outfit-based: matching by costume would bias the result.
    -- Require a unique gender-and-position candidate within 1.6 tiles.
    local best,first,second=nil,nil,nil
    for dx=-1,1 do for dy=-1,1 do
        local key=bucket(p.x+dx*GRID,p.y+dy*GRID,p.z)
        for _,info in ipairs(spatial[key] or {}) do
            if info.female==p.female and math.abs(info.level-p.z)<1.5 then
                local d2=(info.x-p.x)^2+(info.y-p.y)^2
                if d2<=9 then
                    if not first or d2<first then
                        best,second,first=info,first,d2
                    elseif not second or d2<second then second=d2 end
                end
            end
        end
    end end
    if not best or first>2.56 then return nil,"unmatched" end
    if second and second-first<2.25 then return nil,"ambiguous" end
    return best.z,"spatial",math.sqrt(first)
end
local function bindPending()
    local spatial,byOnline,byMarker=buildIndex()
    local occupied={}
    for _,p in pairs(probes) do
        if p.zombie and valid(p,p.zombie) then occupied[p.zombie]=p.trial end
    end
    local keys={}
    for id,p in pairs(probes) do
        if not p.zombie or not valid(p,p.zombie) then keys[#keys+1]=id end
    end
    table.sort(keys,function(a,b)return tonumber(a)<tonumber(b) end)
    for _,id in ipairs(keys) do
        local p=probes[id]
        local z,mode,distance=match(p,spatial,byOnline,byMarker)
        if z and not occupied[z] then
            p.zombie,p.mode,p.distance=z,mode,distance
            occupied[z]=p.trial
            if mode=="online" then stats.online=stats.online+1
            elseif mode=="marker" then stats.marker=stats.marker+1
            else stats.spatial=stats.spatial+1 end
        elseif mode=="ambiguous" then stats.ambiguous=stats.ambiguous+1
        else stats.unmatched=stats.unmatched+1 end
    end
end
-- Census counts the *entire local population* within the saved trial area.
-- It never tries to identify an individual zombie by recycled positions/IDs.
local function takeCensus(stage)
    if not census then return false end
    local cell=type(getCell)=="function" and getCell() or nil
    local zombies=safe(cell,"getZombieList")
    local count=tonumber(safe(zombies,"size"))
    if not count then return false end
    local c=census
    local counts={}
    for i=1,#c.signatures do counts[i]=0 end
    local inside,available,recognized=0,0,0
    local limit=math.min(count,3500)
    for i=0,limit-1 do
        local z=safe(zombies,"get",i)
        if z and safe(z,"isAlive")==true then
            local x,y,level=tonumber(safe(z,"getX")),tonumber(safe(z,"getY")),tonumber(safe(z,"getZ"))
            if x and y and level then
                local candidate=false
                for dx=-3,3 do
                    for dy=-3,3 do
                        local key=bucket(x+dx*GRID,y+dy*GRID,level)
                        for _,pos in ipairs(c.cells[key] or {}) do
                            if math.abs(level-pos[3])<1.5
                                and (x-pos[1])^2+(y-pos[2])^2<=c.radius*c.radius then
                                candidate=true; break
                            end
                        end
                        if candidate then break end
                    end
                    if candidate then break end
                end
                if candidate then
                    inside=inside+1
                    local types=raw(z)
                    if types~="" then
                        available=available+1
                        local which=c.known[types]
                        if which then
                            recognized=recognized+1
                            counts[which]=counts[which]+1
                        end
                    end
                end
            end
        end
    end
    local p=type(getPlayer)=="function" and getPlayer() or nil
    if not p or type(sendClientCommand)~="function" then return false end
    local ok=pcall(sendClientCommand,p,HWE.MOD_ID,"MatrixClientResult",
        {Census=true,Batch=c.batch,Nonce=c.nonce,Stage=stage,
        Inside=inside,Available=available,Recognized=recognized,Counts=counts})
    if ok then
        HWE.log("MATRIX_CENSUS_CLIENT stage="..stage.." scanned="..limit
            .." inTrialArea="..inside.." visualAvailable="..available
            .." recognizable="..recognized
            .." note=population_signatures_not_trial_identity")
    end
    return ok
end
local function onTick()
    if not activeClient() then return end
    tick=tick+1
    if census then
        local age=tick-census.start
        if not census.early and age>=30 then census.early=takeCensus(1) end
        if census.early and not census.late and age>=360 then
            census.late=takeCensus(2)
        end
        if census.late or age>=1200 then census=nil end
    end
    if tick%30==0 then
        local any=false
        for _ in pairs(probes) do any=true;break end
        if any then bindPending() end
    end
    for id,p in pairs(probes) do
        local elapsed=tick-p.start
        if elapsed>=60 and not p.early and p.zombie then
            if sendReport(p,1) then p.early=true end
        end
        -- Build 42 may lazily initialize human item visuals well after a
        -- zombie appears. Sample late only when readable (or at timeout),
        -- never declare an empty visual set to be a failed persistence test.
        if elapsed>=360 and not p.late and p.zombie then
            local types=raw(p.zombie)
            if types~="" or elapsed>=1680 then
                if sendReport(p,2) then p.late=true end
            end
        end
        if p.late or elapsed>=1800 then
            if not p.late then stats.missing=stats.missing+1 end
            probes[id]=nil
        end
    end
    if tick%600==0 then
        local pending=0
        for _ in pairs(probes) do pending=pending+1 end
        HWE.log("MATRIX_CLIENT_PROBE_SUMMARY requests="..stats.requests
            .." early="..stats.early.." late="..stats.late
            .." spatial="..stats.spatial.." online="..stats.online
            .." marker="..stats.marker
            .." ambiguous="..stats.ambiguous.." unmatched="..stats.unmatched
            .." missing="..stats.missing.." errors="..stats.failed
            .." pending="..pending)
    end
end
if Events then
    if Events.OnServerCommand then Events.OnServerCommand.Add(serverCommand) end
    if Events.OnTick then Events.OnTick.Add(onTick) end
end
HWE.log("MATRIX_CLIENT_PROBE_LOADED version=8 readOnly=true cohortCensus=true markerFirst=true")
