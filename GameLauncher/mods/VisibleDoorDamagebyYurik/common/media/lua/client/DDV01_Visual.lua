local D = require "DDV01_Shared"
require "DDV01_HD2D"
local V = { enabled = true, ticks = 0, ready = false, missing = {}, warned = {} }
V.garageSurface = true -- test release: direct closed-garage rendering enabled at startup
local tracked = setmetatable({}, { __mode = "k" })
-- Six cohorts spread health/pose polling over frames. Weak keys do not keep
-- unloaded world objects alive. Full scans remain available for explicit tools.
local cohorts = {}
for i=1,6 do cohorts[i]=setmetatable({}, {__mode="k"}) end
local nextCohort = 0
local sleeping = {}
for i=1,120 do sleeping[i]=setmetatable({}, {__mode="k"}) end
local nextSleeping = 0
local intactPose = setmetatable({}, {__mode="k"})
local dirty = setmetatable({}, {__mode="k"})
local stats = {full=0, light=0, wakeups=0}
V.stats=stats
local discoveryCursor = {}
local function track(door)
    local entry={}
    nextCohort=nextCohort%6+1
    tracked[door]=entry
    cohorts[nextCohort][door]=entry
    entry.queue=cohorts[nextCohort]
    return entry
end
D.Visual = V

local function warnOnce(key, message)
    if not V.warned[key] then V.warned[key] = true; D.log(message) end
end

local function invalidate(door)
    door:invalidateRenderChunkLevel(256)
end

local function restore(door, entry)
    if entry and entry.surface then
        if door:getSprite()==entry.surface then door:setSprite(entry.originalSprite) end
        entry.surface=nil;entry.originalSprite=nil;entry.surfaceTarget=nil
        invalidate(door)
    end
    if entry and entry.overlay then
        local overlay=door:getOverlaySprite()
        if overlay and overlay:getName()==entry.overlay then door:setOverlaySprite(nil,false) end
        entry.overlay=nil
    end
    if D.isOurModel(door:getSpriteModel()) then
        door:setSpriteModelName(nil)
        invalidate(door)
    end
    if entry then entry.applied = nil end
end

function V.preflight()
    V.ready = true
    V.missing = {}
    for _, name in ipairs(D.MODEL_NAMES) do
        local model = ScriptManager.instance:getSpriteModel(name)
        local texture = getTexture(name)
        if not model or not texture then
            V.ready = false
            V.missing[#V.missing + 1] = name .. (model and " [texture]" or " [modele]")
        end
    end
    for _,name in ipairs(D.TEXTURE_NAMES) do
        if not getTexture(name) then V.ready=false; V.missing[#V.missing+1]=name end
    end
    -- VDD R2: preserve native animated-door routing in ViewpointDoor.
    for _,family in ipairs(D.FAMILIES) do
        if not family.garage then
            for view=0,3 do
                local native=ScriptManager.instance:getSpriteModel(family.sources[view+1])
                local runtime=(native and native:getRuntimeString()) or D.NATIVE_RUNTIME[family.sources[view+1]]
                if not runtime or runtime=="" then
                    runtime="standard_door "..(view%2==0 and "w" or "n")..(view<2 and " closed" or " open")
                end
                if D.INTACT_HD_FAMILIES[family.id] then
                    local intact=ScriptManager.instance:getSpriteModel("ct_hd_"..family.id.."_"..tostring(12+view))
                    if intact then intact:setRuntimeString(runtime) end
                end
                for stage=1,3 do
                    local name="ct_hd_"..family.id.."_"..tostring((stage-1)*4+view)
                    local model=ScriptManager.instance:getSpriteModel(name)
                    if model then model:setRuntimeString(runtime) end
                    local standard=ScriptManager.instance:getSpriteModel(family.prefix..tostring((stage-1)*family.stride+family.offset+view))
                    if standard then standard:setRuntimeString(runtime) end
                end
            end
        end
    end
    V.hdReady=true
    D.hd2DReady={}
    for id,records in pairs(D.HD_2D_FAMILIES or {}) do
        local ready=true
        for _,record in ipairs(records) do
            local texture=getTexture(record[1])
            if texture then
                -- Keep high-resolution UVs but draw at the original tile size.
                -- Only our private HD pack textures are touched.
                local ok=pcall(function()
                    texture:setWidth(record[2])
                    texture:setHeight(record[3])
                end)
                if not ok then ready=false end
            else ready=false end
        end
        D.hd2DReady[id]=ready
    end
    D.intactHDReady={}
    for id in pairs(D.INTACT_HD_FAMILIES) do
        local ready=getTexture("media/textures/ct_hd_"..id.."_texture_0.png")~=nil
        for i=12,15 do
            if not ScriptManager.instance:getSpriteModel("ct_hd_"..id.."_"..i) then ready=false end
        end
        D.intactHDReady[id]=ready
    end
    D.extraHDReady={}
    for id in pairs(D.EXTRA_HD_FAMILIES or {}) do
        local ready=true
        for i=0,11 do if not ScriptManager.instance:getSpriteModel("ct_hd_"..id.."_"..i) then ready=false end end
        for stage=1,(D.HD_ATLAS_FAMILIES[id] and 1 or 3) do
            if not getTexture("media/textures/ct_hd_"..id.."_texture_"..stage..".png") then ready=false end
        end
        D.extraHDReady[id]=ready
    end
    for _,name in ipairs(D.HD_MODEL_NAMES) do
        if not ScriptManager.instance:getSpriteModel(name) then V.hdReady=false end
    end
    for stage=1,3 do
        if not getTexture("media/textures/ct_hd_white_texture_"..stage..".png") then V.hdReady=false end
    end
    if not V.hdReady then
        D.whiteHD=false
        warnOnce("hd-missing","Textures HD indisponibles : retour qualite originale pour la blanche.")
    end
    D.log("Porte blanche HD : "..tostring(D.whiteHD).." ; ressources="..tostring(V.hdReady))
    D.log("v" .. D.VERSION .. " : " .. (V.ready and tostring(#D.TEXTURE_NAMES) .. " textures/modeles enregistres."
        or "RESSOURCES MANQUANTES : " .. table.concat(V.missing, ", ")))
    return V.ready
end

local function refreshVisual(door)
    if not door or not door:getSquare() or door:getObjectIndex() < 0 then
        tracked[door] = nil
        return
    end
    local entry = tracked[door]
    if not D.isSupported(door) or door:isDestroyed() then
        if entry then restore(door, entry); tracked[door] = nil end
        return
    end
    local family=D.SOURCE_FAMILY[D.sourceName(door)]
    -- Only replace the displayed closed sprite during the opt-in experiment.
    -- IsoDoor's closed/open sprite references and all mechanical state stay native.
    if family.garage and V.garageSurface and not door:isOpen() then
        if not entry then entry=track(door) end
        local target=V.enabled and V.ready and D.modelName(door,D.stage(door)) or nil
        if entry.failed or not target then restore(door,entry);return end
        if entry.surface and door:getSprite()==entry.surface and entry.surfaceTarget==target then return end
        restore(door,entry)
        if door:getOverlaySprite() or door:getSpriteModel() then
            warnOnce("garage-surface-foreign","Essai garage ignore : visuel tiers present.")
            return
        end
        local before=D.snapshot(door)
        local original=door:getSprite()
        local surface=IsoSprite.new()
        if not surface:LoadSingleTexture(target) then return end
        surface:AddProperties(original)
        surface:setType(original:getType())
        surface:setName(original:getName())
        entry.originalSprite=original;entry.surface=surface;entry.surfaceTarget=target
        door:setSprite(surface)
        local same,changed=D.sameState(before,D.snapshot(door))
        if not same then
            restore(door,entry);entry.failed=true
            D.log("ARRET essai garage : "..tostring(changed))
        end
        invalidate(door)
        return
    elseif entry and entry.surface then
        restore(door,entry)
    end
    if family.overlay and not (D.hdQuality and D.extraHDReady[family.id]) then
        if not entry then entry=track(door) end
        if D.isOurModel(door:getSpriteModel()) then restore(door,entry) end
        local current=door:getOverlaySprite()
        local currentName=current and current:getName() or nil
        if currentName and currentName~=entry.overlay then
            warnOnce("overlay:"..currentName,"Surcouche tierce conservee : "..currentName)
            return
        end
        local target=V.enabled and V.ready and D.modelName(door,D.stage(door)) or nil
        if entry.failed or not target then restore(door,entry);return end
        if currentName==target then return end
        local before=D.snapshot(door)
        -- WallOverlay + attached orientation makes B42 inherit the parent's
        -- depth texture (IsoSprite.getParentSpriteDepthTextureToUse).
        -- Modify only our custom overlay sprite, never the mechanical sprite.
        if family.garage then
            local sprite=getSprite(target)
            if not sprite then restore(door,entry);return end
            local props=sprite:getProperties()
            props:set(IsoFlagType.WallOverlay)
            props:set(door:getNorth() and IsoFlagType.attachedN or IsoFlagType.attachedW)
        end
        door:setOverlaySprite(target,false)
        entry.overlay=target
        invalidate(door)
        local same,changed=D.sameState(before,D.snapshot(door))
        if not same then restore(door,entry);entry.failed=true;D.log("ARRET surcouche : "..tostring(changed)) end
        return
    end
    if entry and entry.overlay then restore(door,entry) end
    local current = door:getSpriteModel()
    local currentID = D.modelID(current)
    local ourCurrent = D.isOurModel(current)
    -- Never erase another mod's per-door model override (e.g. custom doors).
    if current and not ourCurrent and not D.isNativeModel(current,D.sourceName(door)) then
        tracked[door] = nil
        warnOnce("foreign:" .. tostring(D.sourceName(door)) .. ":" .. tostring(currentID), "Modele non natif conserve : source=" .. tostring(D.sourceName(door)) .. " id=" .. tostring(currentID))
        return
    end
    if not entry then entry = track(door) end
    if entry.failed then return end
    if not V.enabled or not V.ready then restore(door, entry); return end
    local stage = D.stage(door)
    local target = D.modelName(door, stage)
    if not target then restore(door, entry); return end
    if ourCurrent and currentID == target then entry.applied = target; return end
    local model = ScriptManager.instance:getSpriteModel(target)
    if not model then restore(door, entry); return end
    local before = D.snapshot(door)
    door:setSpriteModelName(target)
    invalidate(door)
    local same, changed = D.sameState(before, D.snapshot(door))
    if not same then
        restore(door, entry)
        entry.failed = true
        D.log("ARRET sur cette porte : invariant modifie " .. tostring(changed))
        return
    end
    entry.applied = target
end

local function signature(door,entry,save)
    local sprite=door:getSprite()
    local source=sprite and sprite:getName()
    local surfacePointer=entry.surface and sprite or nil
    local model=door:getSpriteModel()
    local overlay=door:getOverlaySprite()
    local overlayName=overlay and overlay:getName()
    local health,maximum=door:getHealth(),door:getMaxHealth()
    local open,north=door:isOpen(),door:getNorth()
    local data=door:getModData()[D.DATA_KEY]
    local force=type(data)=="table" and data.force or nil
    local changed=not entry.signatureReady or entry.health~=health or entry.maximum~=maximum
        or entry.open~=open or entry.north~=north or entry.source~=source
        or entry.sprite~=surfacePointer or entry.model~=model or entry.overlayName~=overlayName or entry.force~=force
    if save then
        entry.health=health;entry.maximum=maximum;entry.open=open;entry.north=north
        entry.source=source;entry.sprite=surfacePointer;entry.model=model;entry.overlayName=overlayName
        entry.force=force;entry.signatureReady=true
    end
    return changed
end

function V.refresh(door)
    stats.full=stats.full+1
    refreshVisual(door)
    local entry=tracked[door]
    if not entry then intactPose[door]=nil; return end
    intactPose[door]=(D.stage(door)==0 and entry.applied~=nil) and entry or nil
    -- Stage-zero HD is cosmetic: keep healthy doors on the sleeping schedule.
    local active=D.stage(door)>0 and (entry.applied~=nil or entry.surface~=nil or entry.overlay~=nil)
    if entry.active~=active then
        if entry.queue then entry.queue[door]=nil end
        if active then
            nextCohort=nextCohort%6+1;entry.queue=cohorts[nextCohort]
        else
            nextSleeping=nextSleeping%120+1;entry.queue=sleeping[nextSleeping]
        end
        entry.queue[door]=entry;entry.active=active
    end
    signature(door,entry,true)
end

-- Called after a hit callback; HP changes occur AFTER OnWeaponHitThumpable.
-- Also available to cooperating client-side repair/visual integrations.
function V.markDoorDirty(door)
    if door and D.isSupported(door) then dirty[door]=true end
end

local function markGarageNeighbors(door)
    local family=D.SOURCE_FAMILY[D.sourceName(door)]
    if not family or not family.garage then return end
    local seen={[door]=true}
    for _,step in ipairs({IsoDoor.getGarageDoorPrev,IsoDoor.getGarageDoorNext}) do
        local current=door
        for i=1,32 do
            current=step(current)
            if not current or seen[current] or not D.isSupported(current)
                or D.SOURCE_FAMILY[D.sourceName(current)]~=family then break end
            seen[current]=true;dirty[current]=true
        end
    end
end

local function safelyRefresh(door)
    local ok, err = pcall(V.refresh, door)
    if not ok then
        pcall(restore, door, tracked[door])
        tracked[door] = nil
        warnOnce("refresh", "Echec rendu ; retour vanilla : " .. tostring(err))
    end
end

local function isNearby(square, radius)
    for index = 0, getNumActivePlayers() - 1 do
        if D.near(getSpecificPlayer(index), square, radius) then return true end
    end
    return false
end

local function scanSquare(square, discoverOnly)
    if not square then return end
    local objects = square:getSpecialObjects()
    for index = 0, objects:size() - 1 do
        local door = objects:get(index)
        if (not discoverOnly or not tracked[door]) and D.isSupported(door) then safelyRefresh(door) end
    end
end

function V.scan()
    local cell = getCell()
    if not cell then return end
    for index = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(index)
        if player then
            local x, y, z = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
            for dx = -18, 18 do
                for dy = -18, 18 do scanSquare(cell:getGridSquare(x + dx, y + dy, z)) end
            end
        end
    end
end

if Events.OnWeaponHitThumpable then
    Events.OnWeaponHitThumpable.Add(function(character,weapon,object) V.markDoorDirty(object) end)
end

local function discoverNearby()
    local cell=getCell()
    if not cell then return end
    for index=0,getNumActivePlayers()-1 do
        local player=getSpecificPlayer(index)
        if player then
            local x,y,z=math.floor(player:getX()),math.floor(player:getY()),math.floor(player:getZ())
            local cursor=discoveryCursor[index] or 0
            -- 24 cells per local player per tick; a 37x37 sweep takes 58 ticks.
            for i=1,24 do
                scanSquare(cell:getGridSquare(x+cursor%37-18,y+math.floor(cursor/37)-18,z),true)
                cursor=(cursor+1)%1369
            end
            discoveryCursor[index]=cursor
        end
    end
end

function V.setWhiteHD(enabled)
    D.whiteHD=enabled==true and V.hdReady==true
    for door in pairs(tracked) do safelyRefresh(door) end
    V.scan()
    D.log("Porte blanche : "..(D.whiteHD and "HD" or "qualite originale"))
end

function V.setHDQuality(enabled)
    D.hdQuality=enabled==true
    D.whiteHD=D.hdQuality and V.hdReady==true
    for door in pairs(tracked) do safelyRefresh(door) end
    V.scan()
end

function V.setGarageSurface(enabled)
    for door,entry in pairs(tracked) do pcall(restore,door,entry) end
    V.garageSurface=enabled==true
    D.log("Essai sprite principal garage : "..tostring(V.garageSurface))
    V.scan()
end

function V.setEnabled(enabled)
    V.enabled = enabled == true
    if not V.enabled then
        for door, entry in pairs(tracked) do pcall(restore, door, entry) end
    else V.scan() end
end

function V.diagnostic(door)
    local s = D.snapshot(door)
    local model = door:getSpriteModel()
    local id = D.modelID(model) or "aucun"
    local line = "HP=" .. s.health .. "/" .. s.maximum .. " ouvert=" .. tostring(s.open)
        .. " verrou=" .. tostring(s.locked) .. " parCle=" .. tostring(s.lockedByKey)
        .. " cle=" .. tostring(s.keyId) .. " sprite=" .. tostring(s.sprite)
        .. " modele=" .. id .. " palier=" .. tostring(D.stage(door))
        .. " cible=" .. tostring(D.modelName(door,D.stage(door)))
        .. " support=" .. tostring(D.isSupported(door))
        .. " garageSurface=" .. tostring(V.garageSurface)
        .. " natif=" .. tostring(D.isNativeModel(model,D.sourceName(door)))
    D.log(line)
    return line
end

Events.OnGameStart.Add(function()
    V.preflight()
    D.log("Garages fermes : sprite principal ACTIF (retour possible dans le menu).")
    V.scan()
end)

Events.LoadGridsquare.Add(function(square)
    if V.enabled and V.ready and isNearby(square, 18) then scanSquare(square) end
end)

Events.OnTick.Add(function()
    V.ticks = V.ticks + 1
    if not V.enabled or not V.ready then return end
    -- Intact HD still sleeps for HP checks, but its pose cannot wait 120 ticks.
    -- Read only the two pose flags; never reset an unchanged model/animation.
    for door,entry in pairs(intactPose) do
        if tracked[door]~=entry or not entry.applied then
            intactPose[door]=nil
        elseif door:isOpen()~=entry.open or door:getNorth()~=entry.north then
            safelyRefresh(door)
        end
    end
    local function poll(cohort)
      for door, entry in pairs(cohort) do
        local square = door:getSquare()
        if tracked[door]~=entry then cohort[door]=nil
        elseif not square or door:getObjectIndex() < 0 then tracked[door] = nil;cohort[door]=nil
        elseif not isNearby(square, 20) then
            pcall(restore, door, entry)
            tracked[door] = nil;cohort[door]=nil
        else
            stats.light=stats.light+1
            -- Garage topology/group damage can change without this section's HP.
            -- Keep a slow complete check for garages as a correctness fallback.
            local family=D.SOURCE_FAMILY[D.sourceName(door)]
            if signature(door,entry,false) or door:isDestroyed()
                or (family and family.garage and (not entry.groupTick or V.ticks-entry.groupTick>=120)) then
                markGarageNeighbors(door)
                safelyRefresh(door)
                entry.groupTick=V.ticks
            end
        end
      end
    end
    poll(cohorts[(V.ticks-1)%6+1])
    poll(sleeping[(V.ticks-1)%120+1])
    -- Swap queues so anything invalidated during this pass is deferred, never lost.
    local pending=dirty;dirty=setmetatable({}, {__mode="k"})
    for door in pairs(pending) do
        local square=door:getSquare()
        if square and door:getObjectIndex()>=0 and isNearby(square,20) then
            stats.wakeups=stats.wakeups+1
            if not tracked[door] or signature(door,tracked[door],false) then markGarageNeighbors(door) end
            safelyRefresh(door)
        end
    end
    discoverNearby()
end)

-- GameWindow.save fires OnSave before currentCell.save in the audited build.
-- Reapply on a subsequent gameplay tick, not OnPostSave (also fired while quitting).
Events.OnSave.Add(function()
    for door, entry in pairs(tracked) do
        local wasActive=entry.active or entry.applied~=nil or entry.surface~=nil or entry.overlay~=nil
        pcall(restore, door, entry)
        if wasActive then entry.signatureReady=false;dirty[door]=true end
    end
end)

return V
