-- EXPERIMENT ONLY. 50 costumes x 8; 32 method variants. v8 adds group-level census.
-- No scanning/world dressing unless an admin explicitly starts the matrix.
-- Tracks raw visuals across a subsequent server restart without assigning a
-- fresh costume to a confidently matched returning test subject.
local HWE = HalloweenEvent
local M = {}
local KEY = "HalloweenEvent_PersistenceMatrix_v1"
local LIMIT = 400
local PER_TICK = 2
local VARIANTS = 32
local CELL = 8
local db, index, claimed = nil, {}, {}
local pending, pendingIndex, observations = nil, 1, {}
local probeRetries = {}
local dispatchStats = {batches=0, delivered=0, noPlayer=0, maxQueue=0}
local runStats, lastObservationTick, needAutoReport = nil, nil, false
local censusSession = nil
local censusSeq = 0

local function safe(o, method, ...)
    return HWE.safeCall(o, method, ...)
end
local function stamp(z)
    local v = HWE.visualTypes(z) or {}
    local names = {}
    for i = 1, #v do names[#names + 1] = tostring(v[i]) end
    table.sort(names)
    return table.concat(names, ",")
end
local function cell(x,y,z)
    return math.floor(x/CELL)..":"..math.floor(y/CELL)..":"..math.floor(z)
end
local function init()
    if db then return db end
    if not ModData or type(ModData.getOrCreate) ~= "function" then return nil end
    local ok, data = pcall(ModData.getOrCreate, KEY)
    if not ok or type(data) ~= "table" then return nil end
    db = data
    if type(db.Entries) ~= "table" then db.Entries = {} end
    db.Batch = tonumber(db.Batch) or 0
    index, claimed = {}, {}
    local count = 0
    for id, entry in pairs(db.Entries) do
        if type(entry) == "table" and tonumber(entry.X) and tonumber(entry.Y) and tonumber(entry.Z)
            and type(entry.CostumeID) == "string" then
            -- A new server run must not inherit a previous boot's results.
            entry.LastSeenMatched=nil
            entry.LastSeenExact=nil
            entry.LastSeenTypes=nil
            entry.ServerVisualAvailable=nil
            entry.ClientEarly=nil
            entry.ClientLate=nil
            entry.LiveOnlineID=nil
            entry.ProbeNonce=nil
            local key = cell(entry.X,entry.Y,entry.Z)
            index[key] = index[key] or {}
            index[key][#index[key]+1] = tostring(id)
            count = count + 1
        end
    end
    HWE.log("MATRIX_LOADED batch="..db.Batch.." trials="..count
        .." diagnosticMode=cohort_only automaticSpatialInterception=false")
    return db
end
local function indexEntry(id, entry)
    local key = cell(entry.X, entry.Y, entry.Z)
    index[key] = index[key] or {}
    index[key][#index[key]+1] = id
end
local function eligible(z)
    if not z or safe(z,"isAlive") ~= true or safe(z,"isUsingWornItems") == true then return false end
    local md = safe(z,"getModData")
    return md and md.HalloweenEventGalleryTest ~= true and md.HalloweenEventSpawnQueued ~= true
        and md.HalloweenEventMatrixTrialID == nil
end

M.stamp = stamp

-- Read-only server-to-client cohort census. This intentionally does NOT claim
-- that a zombie at the old coordinates is the very same individual. B42.21 can
-- regenerate zombies and their online ID; outfit prevalence remains measurable.
local function censusSchema()
    local data=init()
    if not data then return nil end
    local signatures,lookup,positions={}, {}, {}
    local n=0
    for _,rec in pairs(data.Entries) do
        if type(rec)=="table" then
            n=n+1
            local sig=type(rec.Expected)=="string" and rec.Expected or ""
            if sig~="" then
                local row=lookup[sig]
                if not row then
                    row={Stamp=sig,SeedCount=0,Costumes={},Variants={}}
                    lookup[sig]=row
                    signatures[#signatures+1]=row
                end
                row.SeedCount=row.SeedCount+1
                row.Costumes[tostring(rec.CostumeID)]=true
                row.Variants[tonumber(rec.Variant) or 0]=true
            end
            if rec.X and rec.Y and rec.Z then
                positions[#positions+1]={math.floor(rec.X*10+0.5)/10,
                    math.floor(rec.Y*10+0.5)/10,tonumber(rec.Z)}
            end
        end
    end
    if n==0 then return nil end
    table.sort(signatures,function(a,b) return a.Stamp<b.Stamp end)
    for i,row in ipairs(signatures) do
        local names,methods={},{}
        for c in pairs(row.Costumes) do names[#names+1]=c end
        for v in pairs(row.Variants) do methods[#methods+1]=v end
        table.sort(names);table.sort(methods)
        row.Costumes=table.concat(names,"|")
        row.Variants=table.concat(methods,"|")
        row.Index=i
    end
    return {Batch=data.Batch,Signatures=signatures,Positions=positions,
        TrialCount=n,Radius=14}
end

function M.requestCensus()
    local schema=censusSchema()
    if not schema then return false end
    local players=type(getOnlinePlayers)=="function" and getOnlinePlayers() or nil
    if not players or type(sendServerCommand)~="function" then return false end
    censusSeq=censusSeq+1
    local nonce=tostring(schema.Batch)..":"..tostring(censusSeq)
    schema.Nonce=nonce
    local delivered=0
    for i=0,math.min(players:size()-1,16) do
        local p=players:get(i)
        if p then
            if pcall(sendServerCommand,p,HWE.MOD_ID,"MatrixCensusSchema",schema) then
                delivered=delivered+1
            end
        end
    end
    censusSession={Batch=schema.Batch,Nonce=nonce,Signatures=schema.Signatures,
        TrialCount=schema.TrialCount}
    HWE.log("MATRIX_CENSUS_REQUEST batch="..schema.Batch.." recipients="..delivered
        .." trials="..schema.TrialCount.." uniqueSignatures="..#schema.Signatures
        .." radius="..schema.Radius.." note=cohort_only_no_individual_identity")
    return delivered>0
end

function M.receiveCensus(player,args)
    local c=censusSession
    if not c or type(args)~="table" or args.Census~=true
        or tostring(args.Nonce or "")~=c.Nonce
        or tonumber(args.Batch)~=tonumber(c.Batch) then return false end
    local stage=tonumber(args.Stage)
    if stage~=1 and stage~=2 then return false end
    local counts=type(args.Counts)=="table" and args.Counts or nil
    if not counts or #counts>#c.Signatures then return false end
    local inside=tonumber(args.Inside) or -1
    local available=tonumber(args.Available) or -1
    local recognized=tonumber(args.Recognized) or -1
    if inside<0 or inside>5000 or available<0 or available>inside
        or recognized<0 or recognized>available then return false end
    local sum,rows=0,{}
    for i=1,#c.Signatures do
        local count=tonumber(counts[i]) or 0
        if count<0 or count>5000 or count~=math.floor(count) then return false end
        sum=sum+count
        local row=c.Signatures[i]
        rows[#rows+1]={row=row, count=count}
    end
    if sum~=recognized then return false end
    HWE.log("MATRIX_CENSUS_SUMMARY stage="..stage.." batch="..c.Batch
        .." inside="..inside.." visualAvailable="..available
        .." matchingCostumeSignatures="..recognized
        .." nonmatching="..(available-recognized)
        .." unavailable="..(inside-available)
        .." seedTrials="..c.TrialCount
        .." IMPORTANT=population_prevalence_NOT_individual_persistence")
    -- 50 outfits => normally a small number of distinct signatures. Only
    -- publish active signatures so a single census remains compact in logs.
    for _,result in ipairs(rows) do
        if result.count>0 then
            local row=result.row
            HWE.log("MATRIX_CENSUS_SIGNATURE stage="..stage.." id="..row.Index
                .." seed="..row.SeedCount.." seen="..result.count
                .." costumes="..row.Costumes.." variants="..row.Variants)
        end
    end
    return true
end

function M.start(player, zombieList)
    if pending then HWE.log("MATRIX_START_REJECT alreadyRunning=true"); return false end
    if not init() then HWE.log("MATRIX_START_REJECT modDataUnavailable=true"); return false end
    if not zombieList then HWE.log("MATRIX_START_REJECT noZombieList=true"); return false end
    local male, female, mixed = {}, {}, {}
    for i=0,zombieList:size()-1 do
        local z = zombieList:get(i)
        -- Starting a new run explicitly retires older test markers so the
        -- same nearby horde can be reused without a world reset.
        local md = safe(z,"getModData")
        if md and md.HalloweenEventMatrixTrialID then
            md.HalloweenEventMatrixTrialID=nil
            md.HalloweenEventSeenVersion=nil
        end
        if eligible(z) then
            if safe(z,"isFemale") == true then female[#female+1] = z
            else male[#male+1] = z end
        end
    end
    local males, females = #male, #female
    local function take(costume, alternate)
        local preferred = costume.femaleOnly and female or (costume.maleOnly and male or
            (alternate and female or male))
        local backup = costume.femaleOnly and nil or (costume.maleOnly and nil or
            (alternate and male or female))
        local z = table.remove(preferred)
        if not z and backup then z = table.remove(backup) end
        return z
    end
    -- Keep existing batches for historical comparison only; never mix old
    -- batch records into the new test's identity lookup.
    db.Batch = db.Batch + 1
    db.Entries = {}
    index, claimed = {}, {}
    local jobs = {}
    local costumes = HWE.Costumes or {}
    for round=0,7 do
        for ci=1,#costumes do
            if #jobs < LIMIT then
                local costume = costumes[ci]
                local z = take(costume, (round+ci)%2 == 0)
                if z then
                    -- Eight distinct variants per costume; all 32 variants
                    -- are sampled across the 50 costume definitions.
                    -- One costume maps to one treatment throughout the batch.
                    -- A census can compare cohorts even when B42 regenerates
                    -- individual zombies with new IDs. Rotate next batch if
                    -- a promising variant needs independent costume controls.
                    local variant = (ci-1) % VARIANTS
                    jobs[#jobs+1] = {zombie=z, costume=costume, variant=variant,
                        id=tostring(#jobs+1), batch=db.Batch}
                end
            end
        end
    end
    if #jobs == 0 then HWE.log("MATRIX_START_REJECT eligible=0"); return false end
    probeRetries={}
    pending, pendingIndex, runStats = jobs, 1, {saved=0,failed=0, methods={},costumes={}}
    HWE.log("MATRIX_START batch="..db.Batch.." planned="..#jobs.." capacity="..LIMIT
        .." costumes="..#costumes.." variants="..VARIANTS.." male="..males.." female="..females
        .." note=loaded_zombies_only_no_spawning_two_per_tick")
    return true
end

function M.onDressed(job, success, methods, before, after, target)
    local data = init()
    local z, costume = job.zombie, job.costume
    local valid = safe(z,"isAlive") == true
    local md = valid and safe(z,"getModData") or nil
    local x,y,zpos = tonumber(safe(z,"getX")), tonumber(safe(z,"getY")), tonumber(safe(z,"getZ"))
    if valid and md and x and y and zpos and before ~= nil and after ~= nil then
        local rec = {CostumeID=costume.id, Variant=job.variant, X=x, Y=y, Z=zpos,
            Female=safe(z,"isFemale") == true, OriginalID=tonumber(md.HalloweenEventOriginalPersistentID) or 0,
            OriginalName=tostring(md.HalloweenEventOriginalOutfitName or ""),
            OnlineID=tonumber(safe(z,"getOnlineID")) or -1, Expected=target or after,
            Before=before, SeedActual=after, MethodResult=tostring(methods), Batch=job.batch,
            SeedHasVisual=(after~=""), SeedSucceeded=success==true}
        data.Entries[job.id] = rec
        indexEntry(job.id, rec)
        md.HalloweenEventMatrixTrialID = job.id
        claimed[job.id] = true -- don't re-match this same live zombie before restart
        runStats.saved = runStats.saved + 1
        local ms = runStats.methods[job.variant] or {total=0, exact=0}
        ms.total=ms.total+1
        if success then ms.exact=ms.exact+1 end
        runStats.methods[job.variant]=ms
        local cs=runStats.costumes[costume.id] or {total=0, exact=0}
        cs.total=cs.total+1
        if success then cs.exact=cs.exact+1 end
        runStats.costumes[costume.id]=cs
        HWE.log("MATRIX_CASE phase=seed batch="..job.batch.." trial="..job.id
            .." costume="..costume.id.." variant="..job.variant
            .." nativeID="..rec.OriginalID.." onlineID="..rec.OnlineID
            .." visible="..tostring(rec.SeedHasVisual).." sameAsDressed="..tostring(success)
            .." methods="..tostring(methods).." visuals="..after)
    else
        runStats.failed = runStats.failed + 1
        HWE.log("MATRIX_CASE phase=seed_failed trial="..job.id
            .." costume="..costume.id.." variant="..job.variant.." methods="..tostring(methods))
    end
end

local function match(z)
    if not init() then return nil end
    local x,y,zpos = tonumber(safe(z,"getX")),tonumber(safe(z,"getY")),tonumber(safe(z,"getZ"))
    if not x or not y or not zpos then return nil end
    local native = tonumber(safe(z,"getPersistentOutfitID")) or 0
    local sex = safe(z,"isFemale") == true
    local choice, id, best, ambiguous = nil, nil, nil, false
    for dx=-1,1 do for dy=-1,1 do
        local key=cell(x+dx*CELL,y+dy*CELL,zpos)
        for _,candidate in ipairs(index[key] or {}) do
            local rec=db.Entries[candidate]
            if rec and not claimed[candidate] and rec.Female == sex
                and math.abs(zpos-rec.Z)<0.25 then
                local dist=(x-rec.X)^2+(y-rec.Y)^2
                local idOK = native~=0 and (tonumber(rec.OriginalID) or 0)==native
                -- Short-range position fallback is deliberately narrow and
                -- rejected on ambiguity, unlike earlier Spiffo proximity guesses.
                if (idOK and dist<=6.25) or dist<=0.16 then
                    local rank=dist+(idOK and 0 or 25)
                    if best==nil or rank<best-0.05 then
                        choice,id,best,ambiguous=rec,candidate,rank,false
                    elseif math.abs(rank-best)<=0.05 then ambiguous=true end
                end
            end
        end
    end end
    if ambiguous then return nil end
    return choice,id
end

-- Diagnostic archive mode (v10): these older trials were matched by
-- position, which is NOT zombie identity in Build 42.21. Returning zombies
-- must not be intercepted, marked or excluded from event/wardrobe logic.
-- Keep the 400 saved records for explicit admin census and comparison.
function M.observeCreated(z, currentTick)
    return false
end

-- Retained only as inactive reference; NOT called from onZombieCreate.
-- The previous spatial identity/hold path is deliberately removed.
-- It assigned saved matrix trial IDs to unrelated nearby zombies.

function M.tick(processOne, now)
    -- Transport in bounded 32-trial packets. A zombie without an online ID
    -- must still reach the client; no match is declared until the client
    -- establishes a unique local candidate. Delay retries until an actual
    -- nearby player can receive them (rather than dropping at login).
    local due={}
    for i=#probeRetries,1,-1 do
        local p=probeRetries[i]
        if p.record.ClientLate or p.remaining<=0 then
            table.remove(probeRetries,i)
        elseif now>=p.due and #due<32 then
            if safe(p.zombie,"isAlive")==true then
                due[#due+1]=p
            else
                table.remove(probeRetries,i)
            end
        end
    end
    if #due>0 then
        local players=type(getOnlinePlayers)=="function" and getOnlinePlayers() or nil
        local delivery={}
        if players and type(sendServerCommand)=="function" then
            for pi=0,players:size()-1 do
                local player=players:get(pi)
                local px,py,pz=tonumber(safe(player,"getX")),tonumber(safe(player,"getY")),tonumber(safe(player,"getZ"))
                if px and py and pz then
                    local entries={}
                    for j=1,#due do
                        local msg=due[j].msg
                        if math.abs(pz-msg.Z)<1.5 and (px-msg.X)^2+(py-msg.Y)^2<22500 then
                            entries[#entries+1]=msg
                        end
                    end
                    if #entries>0 then
                        local ok=pcall(sendServerCommand,player,HWE.MOD_ID,
                            "MatrixProbeBatch",{Entries=entries})
                        if ok then
                            dispatchStats.batches=dispatchStats.batches+1
                            for j=1,#entries do delivery[entries[j].Trial]=true end
                        end
                    end
                end
            end
        end
        local sent,notReady=0,0
        for j=1,#due do
            local p=due[j]
            if delivery[p.msg.Trial] then
                p.remaining=p.remaining-1
                p.due=now+360
                sent=sent+1
            else
                p.due=now+120
                notReady=notReady+1
            end
        end
        dispatchStats.delivered=dispatchStats.delivered+sent
        dispatchStats.noPlayer=dispatchStats.noPlayer+notReady
        if sent>0 or (now%600)<2 then
            HWE.log("MATRIX_PROBE_DISPATCH packets="..dispatchStats.batches
                .." queued="..#probeRetries.." wave="..#due
                .." delivered="..sent.." waiting="..notReady
                .." totalDelivered="..dispatchStats.delivered)
        end
    end
    if pending then
        for _=1,PER_TICK do
            local job=pending[pendingIndex]
            if not job then break end
            pendingIndex=pendingIndex+1
            local ok, err=pcall(processOne, job)
            if not ok then
                runStats.failed=runStats.failed+1
                HWE.log("MATRIX_CASE phase=exception trial="..job.id.." error="..tostring(err))
            end
        end
        if pendingIndex>#pending then
            HWE.log("MATRIX_SEED_SUMMARY batch="..db.Batch.." saved="..runStats.saved
                .." failed="..runStats.failed.." planned="..#pending
                .." note=restart_once_to_measure_native_persistence")
            for v=0,VARIANTS-1 do
                local ms=runStats.methods[v] or {total=0,exact=0}
                HWE.log("MATRIX_VARIANT phase=seed variant="..v.." count="..ms.total
                    .." sameAsDressed="..ms.exact)
            end
            for _,profile in ipairs(HWE.Costumes or {}) do
                local cs=runStats.costumes[profile.id] or {total=0,exact=0}
                HWE.log("MATRIX_COSTUME phase=seed costume="..profile.id
                    .." tested="..cs.total.." sameAsDressed="..cs.exact)
            end
            if ModData and type(ModData.transmit)=="function" then pcall(ModData.transmit,KEY) end
            pending,pendingIndex=nil,1
        end
    end
    local count=0
    for i=#observations,1,-1 do
        local job=observations[i]
        if now>=job.due and count<8 then
            local rec=job.record
            local actual=stamp(job.zombie)
            local hasVisual=actual~=""
            local exact=nil
            if hasVisual and rec.SeedHasVisual==true then exact=(actual==rec.Expected) end
            rec.LastSeenMatched = true
            rec.LastSeenExact = exact
            rec.LastSeenTypes = actual
            rec.ServerVisualAvailable = hasVisual
            HWE.log("MATRIX_CASE phase=reload batch="..tostring(rec.Batch).." trial="..job.id
                .." costume="..rec.CostumeID.." variant="..rec.Variant
                .." serverVisual="..(hasVisual and "available" or "unavailable")
                .." exact="..(hasVisual and tostring(exact) or "unknown")
                .." actual="..actual)
            -- The test holds the raw appearance. No new random costume and no
            -- wardrobe restore; the user can inspect the real engine outcome.
            table.remove(observations,i)
            count=count+1
        end
    end
    if needAutoReport and lastObservationTick and now-lastObservationTick>600 and #observations==0 then
        needAutoReport=false
        M.status()
    end
end


-- Client reports are diagnostic only. Match against a server-issued candidate,
-- the current world incarnation and the request nonce before accepting.
function M.receiveClientProbe(player, args)
    if type(args)=="table" and args.Census==true then
        return M.receiveCensus(player,args)
    end
    if not init() or type(args)~="table" then return false end
    local id=tostring(args.Trial or "")
    local rec=db.Entries[id]
    local stage=tonumber(args.Stage)
    if not rec or rec.ProbeNonce == nil or tostring(args.Nonce or "")~=rec.ProbeNonce
        or tonumber(args.Batch)~=tonumber(rec.Batch) or (stage~=1 and stage~=2) then return false end
    local mode=tostring(args.MatchMode or "")
    if mode~="online" and mode~="spatial" and mode~="marker" then return false end
    local serverID=tonumber(rec.LiveOnlineID) or -1
    if serverID>=0 then
        if mode~="online" and mode~="marker" then return false end
        if mode=="online" and tonumber(args.MatchedOnlineID)~=serverID then return false end
    elseif mode~="spatial" and mode~="marker" then return false end
    local d=tonumber(args.MatchDistance)
    if not d or d<0 or d>(mode=="marker" and 50 or 1.6) then return false end
    local x,y,z=tonumber(args.X),tonumber(args.Y),tonumber(args.Z)
    if not x or not y or not z or math.abs(z-(rec.LiveZ or rec.Z))>1.5 or
        (x-(rec.LiveX or rec.X))^2+(y-(rec.LiveY or rec.Y))^2>2500 then return false end
    local types=type(args.Types)=="string" and args.Types or ""
    if #types>2000 then return false end
    local worn=tonumber(args.WornCount) or -1
    local source=tostring(args.Source or "unknown")
    if #source>24 then return false end
    local available=types~=""
    local exact=available and rec.SeedHasVisual==true and types==rec.Expected
    -- The engine may shuffle/recreate zombie incarnations on world reload.
    -- Distinguish a different matrix outfit from ordinary/unreadable visuals,
    -- without pretending a spatially matched zombie has proven identity.
    local otherNames={}
    if available and not exact then
        local hits={}
        for _,other in pairs(db.Entries) do
            if other.Expected==types and other.SeedHasVisual==true then
                hits[tostring(other.CostumeID)]=true
            end
        end
        for costume in pairs(hits) do otherNames[#otherNames+1]=costume end
        table.sort(otherNames)
    end
    local class=not available and "unavailable" or
        (exact and "exact" or (#otherNames>0 and "other_matrix_costume" or "different"))
    local sameNative=(tonumber(args.NativeID)~=nil and tonumber(rec.OriginalID)~=nil
        and tonumber(rec.OriginalID)~=0 and tonumber(args.NativeID)==tonumber(rec.OriginalID))
    local key=stage==1 and "ClientEarly" or "ClientLate"
    if rec[key] and rec[key].Available and not available then return true end
    rec[key]={Available=available,Exact=exact==true,Source=source,WornCount=worn,
        Types=types,Stage=stage,MatchMode=mode,MatchDistance=d,
        Class=class,OtherMatrixCostumes=table.concat(otherNames,"|"),SameOriginalNative=sameNative}
    HWE.log("MATRIX_CLIENT_CASE stage="..stage.." trial="..id.." costume="..rec.CostumeID
        .." variant="..rec.Variant.." source="..source.." available="..tostring(available)
        .." worn="..worn.." exact="..(available and tostring(exact) or "unknown")
        .." nativeID="..tostring(args.NativeID).." match="..mode
        .." distance="..tostring(d).." class="..class
        .." other="..table.concat(otherNames,"|")
        .." sameOriginalNative="..tostring(sameNative).." raw="..types)
    return true
end

function M.clear(list)
    if not init() then return false end
    pending,pendingIndex,observations=nil,1,{}
    probeRetries={}
    dispatchStats={batches=0,delivered=0,noPlayer=0,maxQueue=0}
    censusSession=nil
    claimed,index={},{}
    db.Entries={}
    if list then
        for i=0,list:size()-1 do
            local z=list:get(i)
            local md=safe(z,"getModData")
            if md and md.HalloweenEventMatrixTrialID then
                md.HalloweenEventMatrixTrialID=nil
                md.HalloweenEventSeenVersion=nil
            end
        end
    end
    HWE.log("MATRIX_CLEARED subjects_released=true")
    return true
end

function M.status()
    if not init() then HWE.log("MATRIX_STATUS unavailable=true"); return end
    local counts, exact, seed, costumes, total = {}, {}, {}, {}, 0
    for _,rec in pairs(db.Entries) do
        local v=tonumber(rec.Variant) or 0
        counts[v]=(counts[v] or 0)+(rec.LastSeenMatched and 1 or 0)
        if rec.LastSeenExact then exact[v]=(exact[v] or 0)+1 end
        if rec.SeedSucceeded then seed[v]=(seed[v] or 0)+1 end
        local costume=tostring(rec.CostumeID)
        costumes[costume]=costumes[costume] or {matched=0,exact=0,total=0}
        local cc=costumes[costume]
        cc.total=cc.total+1
        if rec.LastSeenMatched then cc.matched=cc.matched+1 end
        if rec.LastSeenExact then cc.exact=cc.exact+1 end
        total=total+1
    end
    local matched,serverAvailable,earlySeen,lateSeen,lateAvailable,lateExact=0,0,0,0,0,0
    local lateCross,lateDifferent,lateUnknown,lateNativeMatch,lateMarker=0,0,0,0,0
    local byVariant={}
    for _,rec in pairs(db.Entries) do
        local v=tonumber(rec.Variant) or 0
        if rec.LastSeenMatched then matched=matched+1 end
        if rec.ServerVisualAvailable then serverAvailable=serverAvailable+1 end
        if rec.ClientEarly then earlySeen=earlySeen+1 end
        if rec.ClientLate then
            lateSeen=lateSeen+1
            if rec.ClientLate.Available then lateAvailable=lateAvailable+1 end
            if rec.ClientLate.Exact then lateExact=lateExact+1 end
            if rec.ClientLate.Class=="other_matrix_costume" then lateCross=lateCross+1 end
            if rec.ClientLate.Class=="different" then lateDifferent=lateDifferent+1 end
            if rec.ClientLate.Class=="unavailable" then lateUnknown=lateUnknown+1 end
            if rec.ClientLate.SameOriginalNative then lateNativeMatch=lateNativeMatch+1 end
            if rec.ClientLate.MatchMode=="marker" then lateMarker=lateMarker+1 end
            local row=byVariant[v] or {probed=0,available=0,exact=0}
            row.probed=row.probed+1
            if rec.ClientLate.Available then row.available=row.available+1 end
            if rec.ClientLate.Exact then row.exact=row.exact+1 end
            byVariant[v]=row
        end
    end
    HWE.log("MATRIX_PROBE_STATUS packets="..dispatchStats.batches
        .." delivered="..dispatchStats.delivered.." waitNoPlayer="..dispatchStats.noPlayer
        .." peakQueue="..dispatchStats.maxQueue.." pending="..#probeRetries)
    HWE.log("MATRIX_STATUS batch="..db.Batch.." trials="..total
        .." pending="..tostring(pending and (#pending-pendingIndex+1) or 0)
        .." observed="..tostring(#observations).." matched="..matched
        .." serverVisualAvailable="..serverAvailable.." clientEarly="..earlySeen
        .." clientLate="..lateSeen.." clientLateVisual="..lateAvailable
        .." clientLateExact="..lateExact
        .." clientOtherCostume="..lateCross.." clientDifferent="..lateDifferent
        .." clientUnavailable="..lateUnknown.." clientOriginalNative="..lateNativeMatch
        .." clientMarker="..lateMarker)
    for v=0,VARIANTS-1 do
        local cr=byVariant[v] or {probed=0,available=0,exact=0}
        HWE.log("MATRIX_VARIANT phase=reload variant="..v
            .." matched="..(counts[v] or 0).." serverExact="..(exact[v] or 0)
            .." clientProbed="..cr.probed.." clientVisual="..cr.available
            .." clientExact="..cr.exact.." seedExact="..(seed[v] or 0))
    end
    for name,cc in pairs(costumes) do
        HWE.log("MATRIX_COSTUME costume="..name.." planned="..cc.total
            .." matched="..cc.matched.." exact="..cc.exact)
    end
    HWE.log("MATRIX_STATUS_NOTE spatial_matches_are_not_guaranteed_same_zombie; other_matrix_costume_is_a_signature_match_not_proof_of_swap; empty_visuals_are_unknown")
    HWE.log("MATRIX_VARIANT_CAUTION v4-v7_cohorts_mix_variants_per_costume; per_method_persistence_rank_is_inconclusive_without_stable_identity")
    M.requestCensus()
end

return M
