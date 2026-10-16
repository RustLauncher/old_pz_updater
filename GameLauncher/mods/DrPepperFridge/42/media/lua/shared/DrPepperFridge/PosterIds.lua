require 'DrPepperFridge/Posters'
local P=DrPepperPosters
DrPepperPosterIds=DrPepperPosterIds or {}
local M=DrPepperPosterIds
M.oldBase=1275592704
M.legacyPrefix='drpepper_legacy_01_'
M.squareRevision=1
local oldChunks={}
local hasIndex=false
local managerForWorld=nil
local stateKey='DrPepperPosters_IdMigration'
local presentationKey='DrPepperPosters_LegacyPresentation'
M.presentationKey=presentationKey
M.blocked=false
M.status={mode='identity-only',warnings={},recoveredObjects=0,recoveredAttachments=0,retainedAttachments=0}
local function warn(key,message)
    if M.status.warnings[key] then return end
    M.status.warnings[key]=message
    print('[DrPepper] '..message)
end
function M.protect(reason)
    if not M.blocked then M.previousNoSave=getCore():isNoSave() end
    M.blocked=true
    getCore():setNoSave(true)
    -- The Java GameTime table survives the Lua environment reset when exiting
    -- to the menu. Lua-only fields do not. NoSave prevents this temporary
    -- ownership record from being written to the protected world's time file.
    getGameTime():getModData().DrPepperPosterNoSaveOverride={previous=M.previousNoSave}
    if not isServer() then setGameSpeed(0) end
    print('[DrPepper] SAVE PROTECTED: '..tostring(reason))
end
local function validChunkKey(key)
    if type(key)~='string' then return false end
    local x,y=key:match('^(%-?%d+),(%-?%d+)$')
    if not x then return false end
    x,y=tonumber(x),tonumber(y)
    return x and y and math.abs(x)<2147483648 and math.abs(y)<2147483648
        and key==string.format('%d,%d',x,y)
end
local function countChunks(chunks)
    assert(type(chunks)=='table','Invalid persisted Dr Pepper chunk map')
    local count=0
    for key,value in pairs(chunks) do
        assert(validChunkKey(key) and value==true,'Invalid persisted Dr Pepper chunk entry')
        count=count+1
    end
    return count
end

local function hex(s)
    -- Kahlua strings expose Java UTF-16 code units through string.byte.
    -- Encode UTF-8 explicitly so accented save names match the Windows helper.
    local result={}
    local i=1
    while i<=#s do
        local c=string.byte(s,i)
        if c>=55296 and c<=56319 then
            local low=string.byte(s,i+1)
            if low and low>=56320 and low<=57343 then
                c=65536+(c-55296)*1024+(low-56320);i=i+1
            else c=65533 end
        elseif c>=56320 and c<=57343 then c=65533 end
        if c<128 then result[#result+1]=string.format('%02x',c)
        elseif c<2048 then result[#result+1]=string.format('%02x%02x',192+math.floor(c/64),128+c%64)
        elseif c<65536 then result[#result+1]=string.format('%02x%02x%02x',224+math.floor(c/4096),128+math.floor(c/64)%64,128+c%64)
        else result[#result+1]=string.format('%02x%02x%02x%02x',240+math.floor(c/262144),128+math.floor(c/4096)%64,128+math.floor(c/64)%64,128+c%64) end
        i=i+1
    end
    return table.concat(result)
end
function M.indexPath()
    return 'DrPepperPosterMigration/'..hex(getCore():getGameMode())..'/'..hex(getWorld():getWorld())..'.txt'
end
function M.loadIndex()
    oldChunks={}
    hasIndex=false
    local reader=getFileReader(M.indexPath(),false)
    if not reader then return end
    local ok,result=pcall(function()
        assert(reader:readLine()=='DrPepperPosterMigration-v2','Invalid or obsolete Dr Pepper preparation index')
        local source=reader:readLine()
        assert(source=='source=legacy-dr-only' or source=='source=first-install','Invalid Dr Pepper preparation source')
        local identity=hex(getCore():getGameMode())..'/'..hex(getWorld():getWorld())
        assert(reader:readLine()=='world='..identity,'Preparation index belongs to another world')
        local countLine=reader:readLine() or ''
        local count=tonumber(countLine:match('^chunks=(%d+)$'))
        assert(count and count<=10000000,'Invalid Dr Pepper chunk count')
        assert(source~='source=first-install' or count==0,'First installation must not claim legacy chunks')
        local chunks={}
        for n=1,count do
            local line=reader:readLine()
            assert(validChunkKey(line) and not chunks[line],'Invalid or duplicate Dr Pepper chunk entry')
            chunks[line]=true
        end
        assert(reader:readLine()=='end='..count,'Truncated Dr Pepper preparation index')
        assert(reader:readLine()==nil,'Unexpected data after Dr Pepper preparation index')
        return chunks
    end)
    local closed,closeError=pcall(function() reader:close() end)
    if not ok then error(result) end
    if not closed then error(closeError) end
    oldChunks=result
    hasIndex=true
end
local function oldIndex(sprite)
    if not sprite then return nil end
    local i=sprite:getID()-M.oldBase
    if i>=0 and i<=9 and i==math.floor(i) then return i end
end
local function existingWorldFiles()
    -- OnInitGlobalModData's isNewGame flag is not reliable on dedicated
    -- reloads in 42.21. This read-only native API resolves the CURRENT save.
    -- createWorld creates directories but not these persisted binary files;
    -- do not use the always-created map directory or a world-age heuristic.
    for _,name in ipairs({'global_mod_data.bin','map_t.bin','map_meta.bin','WorldDictionary.bin','map_ver.bin','map_worldgen.bin','map.bin'}) do
        local exists=checkSaveFileExists(name)
        assert(type(exists)=='boolean','Invalid native save-file existence result')
        if exists then return true end
    end
    return false
end
local function usableCanonical(sprite)
    return sprite and (isServer() or not sprite:hasNoTextures())
end
-- Verified legacy chunks certify the original Dr-Pepper-only native placement
-- route: AttachExistingAnim(sprite,0,0,false,0,false,0), with zero offsets and
-- no flipped animation. The native Lua API exposes no setters/readers for
-- hidden offsets/flip. This route covers those original standard placements,
-- not attachments modified by other scripts. Detect visible custom state and
-- retain it; never rebuild a visibly nonstandard child and lose its tint/frame.
local function replacementForStandardAttachment(instance,canonical)
    local replacement=canonical:newInstance()
    local getters={'getTintR','getTintG','getTintB','isCopyTargetAlpha','isMultiplyObjectAlpha','getFrame','isFinished'}
    local ok,standard=pcall(function()
        for _,getter in ipairs(getters) do
            if not instance[getter] or not replacement[getter]
                    or instance[getter](instance)~=replacement[getter](replacement) then return false end
        end
        replacement:setScale(instance:getScaleX(),instance:getScaleY())
        replacement:SetAlpha(instance:getAlpha())
        replacement:SetTargetAlpha(instance:getTargetAlpha())
        return true
    end)
    if ok and standard then return replacement end
    return nil
end
function M.stamp(object,index,playerPlaced)
    local md=object:getModData()
    md.DrPepperPoster=P.designs[math.floor(index/2)+1]
    md.DrPepperPosterSpriteIndex=index
    if playerPlaced then md.DrPepperPosterPlayerPlaced=true end
    -- Persist the exact name too; native constructors using an IsoSprite do
    -- not populate spriteName until this accessor is called.
    local name=P.prefix..index
    if object:getSpriteName()~=name then
        local canonical=getSprite(name)
        object:setSprite(name);object:setSprite(canonical)
    end
end
local function recoverSquare(square)
    if M.blocked or isClient() or not square then return end
    local size=getChunkSizeInSquares()
    local key=math.floor(square:getX()/size)..','..math.floor(square:getY()/size)
    local indexed=oldChunks[key]
    local sqmd=indexed and square:getModData() or nil
    local ownsLegacy=indexed and sqmd.DrPepperPosterIdsRevision~=M.squareRevision
    local objects=square:getObjects()
    for n=0,objects:size()-1 do
        local object=objects:get(n)
        local attached=object:getAttachedAnimSprite()
        if attached then
            for a=0,attached:size()-1 do
                local instance=attached:get(a)
                local child=instance:getParentSprite()
                local old=oldIndex(child)
                if old then
                    -- Wall metadata describes a previously placed poster, not
                    -- the ownership of a later attachment sharing its old ID.
                    -- Only a verified, unmigrated legacy square proves it.
                    -- The current alias name is not historical ownership.
                    if ownsLegacy then
                        local canonical=getSprite(P.prefix..old)
                        assert(usableCanonical(canonical),'Missing canonical attached poster')
                        local replacement=replacementForStandardAttachment(instance,canonical)
                        if replacement then
                            attached:set(a,replacement)
                            local md=object:getModData()
                            md.DrPepperPosterAttachments=md.DrPepperPosterAttachments or {}
                            md.DrPepperPosterAttachments[P.prefix..old]=true
                            M.status.recoveredAttachments=M.status.recoveredAttachments+1
                            if isServer() then object:transmitUpdatedSpriteToClients();object:transmitModData() end
                        else
                            M.status.retainedAttachments=M.status.retainedAttachments+1
                            warn('attachment-fields','Custom legacy attachment retained with its original numeric ID: its native attachment state cannot be copied safely.')
                        end
                    end
                end
            end
        end
        local sprite=object:getSprite()
        if sprite or object:getSpriteName() then
            local name=sprite and sprite:getName() or ''
            local design,facing=P.spriteInfo(name)
            local index=design and ((design-1)*2+(facing=='S' and 1 or 0)) or nil
            local old=oldIndex(sprite)
            if not index then
                local md=object:getModData()
                local savedDesign,savedFacing=P.spriteInfo(object:getSpriteName())
                local taggedDesign=nil
                for i,d in ipairs(P.designs) do if md.DrPepperPoster==d then taggedDesign=i;break end end
                if savedDesign then
                    index=(savedDesign-1)*2+(savedFacing=='S' and 1 or 0)
                elseif taggedDesign and type(md.DrPepperPosterSpriteIndex)=='number'
                        and md.DrPepperPosterSpriteIndex==math.floor(md.DrPepperPosterSpriteIndex)
                        and md.DrPepperPosterSpriteIndex>=0 and md.DrPepperPosterSpriteIndex<=9
                        and math.floor(md.DrPepperPosterSpriteIndex/2)+1==taggedDesign then
                    index=md.DrPepperPosterSpriteIndex
                elseif old and taggedDesign and math.floor(old/2)+1==taggedDesign then
                    index=old
                elseif old and ownsLegacy then index=old end
            end
            if index then
                local canonical=getSprite(P.prefix..index)
                if usableCanonical(canonical) then
                    if sprite~=canonical then
                        -- Native setSprite(string) creates a temporary sprite
                        -- while storing its name. Restore the canonical pointer
                        -- immediately so save() writes its registered numeric ID.
                        object:setSprite(P.prefix..index)
                        object:setSprite(canonical)
                        M.status.recoveredObjects=M.status.recoveredObjects+1
                        if isServer() then object:transmitUpdatedSpriteToClients() end
                    end
                    M.stamp(object,index,false)
                    if isServer() then object:transmitModData() end
                else
                    error('Dr Pepper canonical poster missing: '..index)
                end
            end
        end
    end
    -- Once this square is loaded, later MDO additions belong to MDO even if
    -- they reuse one of the ten numeric IDs formerly owned by Dr Pepper.
    if indexed then sqmd.DrPepperPosterIdsRevision=M.squareRevision end
end
function M.recoverSquare(square)
    if M.blocked then return end
    local ok,err=pcall(function() recoverSquare(square) end)
    if not ok then M.protect('Poster migration failed; original world must not be saved: '..tostring(err)) end
end
local function legacySlotsVacant(manager)
    for i=0,9 do
        local occupant=manager:getSprite(M.oldBase+i)
        if occupant and occupant~=getSprite(M.legacyPrefix..i) then return false end
    end
    return true
end
local function registerLegacyAliases(manager,presentationAllowed)
    assert(legacySlotsVacant(manager),'Another mod owns the legacy numeric slots')
    local needsRegistration=false
    for i=0,9 do if not manager:getSprite(M.oldBase+i) then needsRegistration=true end end
    if needsRegistration then
        local info=getModInfoByID('DrPepperFridge')
        getWorld():LoadTileDefinitions(manager,info:getVersionDir()..'/media/DrPepperLegacyPosters.tiles',4864)
    end
    for i=0,9 do
        local sprite=manager:getSprite(M.oldBase+i)
        local alias=getSprite(M.legacyPrefix..i)
        assert(sprite and sprite==alias and sprite:getID()==M.oldBase+i,'Legacy poster alias could not be registered: '..i)
        -- Unknown ownership still needs a registered placeholder before native
        -- deserialization: otherwise the engine discards attached children.
        -- An inert placeholder has no Dr Pepper interaction properties/image.
        -- Reuse the existing sprite pointers already held by received objects.
        -- Restore approved metadata by copying canonical properties, never by
        -- reloading the tile definitions and replacing registered pointers.
        local properties=alias:getProperties()
        properties:Clear()
        if presentationAllowed then properties:AddProperties(getSprite(P.prefix..i):getProperties()) end
        properties:CreateKeySet()
        if not isServer() and presentationAllowed then
            alias:LoadSingleTexture(P.prefix..i)
            assert(not alias:hasNoTextures(),'Missing legacy poster display texture: '..i)
        elseif not isServer() and not alias:hasNoTextures() then
            -- An earlier world/decision must not leave a presentation texture
            -- on the new world's unconfirmed or explicitly inert placeholder.
            alias:LoadSingleTexture('__DrPepperLegacyPresentationDisabled__')
            assert(alias:hasNoTextures(),'Cannot make legacy presentation inert: '..i)
        end
    end
    M.status.legacyAliases=true
    M.status.legacyPresentation=presentationAllowed==true
end
local function requestPresentationDecision()
    if not isClient() or not M.clientPresentationAliases then return end
    local ok,problem=pcall(function() ModData.request(presentationKey) end)
    if not ok then warn('client-request','Waiting for the server legacy-presentation decision: '..tostring(problem)) end
end
Events.OnLoadedTileDefinitions.Add(function(manager)
    managerForWorld=manager
    M.clientPresentationAliases=false
    -- Register inert identities before chunk packets can arrive. Textures and
    -- Dr Pepper interaction properties wait for the server's current decision.
    -- Clients never recover or stamp authoritative objects.
    if isClient() and not getActivatedMods():contains('MoreDamagedObjects') and legacySlotsVacant(manager) then
        local ok,problem=pcall(function() registerLegacyAliases(manager,false) end)
        if not ok then warn('client-alias','Legacy poster presentation could not be registered: '..tostring(problem)) end
        M.clientPresentationAliases=ok
        if ok then requestPresentationDecision() end
    end
end)
Events.OnReceiveGlobalModData.Add(function(key,data)
    if not isClient() or key~=presentationKey or not M.clientPresentationAliases then return end
    local allowed=type(data)=='table' and data.schema==1 and data.legacyAliasesAllowed==true and data.mdoSeen==false
    local ok,problem=pcall(function() registerLegacyAliases(managerForWorld,allowed) end)
    if not ok then warn('client-decision','Server legacy-presentation decision could not be applied: '..tostring(problem)) end
end)
Events.OnMainMenuEnter.Add(function()
    -- Restore before the next world's native dictionary/global-data loaders.
    -- Waiting until OnInitGlobalModData would leave NoSave active while those
    -- loaders start when the player returns to the menu instead of quitting.
    local timeData=getGameTime():getModData()
    local override=timeData.DrPepperPosterNoSaveOverride
    if override and (override.previous==true or override.previous==false) then
        getCore():setNoSave(override.previous)
        timeData.DrPepperPosterNoSaveOverride=nil
    elseif M.blocked then getCore():setNoSave(M.previousNoSave) end
    M.blocked=false;M.started=false;M.modalShown=false;M.clientPresentationAliases=false
end)
Events.OnInitGlobalModData.Add(function(isNewGame)
    if isClient() then requestPresentationDecision();return end
    if M.blocked then getCore():setNoSave(M.previousNoSave) end
    M.blocked=false
    M.started=false;M.modalShown=false
    M.status={mode='identity-only',warnings={},recoveredObjects=0,recoveredAttachments=0,retainedAttachments=0}
    oldChunks={};hasIndex=false
    local ok,err=pcall(function()
    assert(managerForWorld,'Missing sprite manager')
    for i=0,9 do
        local sprite=getSprite(P.prefix..i)
        assert(usableCanonical(sprite),'Missing Dr Pepper poster texture')
        assert(sprite:getID()==1275854848+i and managerForWorld:getSprite(sprite:getID())==sprite,'Dr Pepper poster ID conflict')
        assert(sprite:getProperties():has('IsMoveAble'),'Missing Dr Pepper poster properties')
    end
    for _,prefix in ipairs({'DrPepperFridge_01_','DrPepperFridgeWorn_01_'}) do
        for i=0,7 do
            local sprite=getSprite(prefix..i)
            assert(usableCanonical(sprite),'Missing Dr Pepper fridge texture')
            assert(managerForWorld:getSprite(sprite:getID())==sprite,'Dr Pepper fridge ID conflict')
            assert(sprite:getProperties():has('IsMoveAble'),'Missing Dr Pepper fridge properties')
        end
    end
    local state=ModData.getOrCreate(stateKey)
    -- Loaded state (including malformed records) takes precedence over a
    -- misleading new-game event. Read this before adding runtime decisions.
    local hasStoredState=false
    for _ in pairs(state) do hasStoredState=true;break end
    local fileProbeValid,worldFiles=true,false
    if isNewGame then fileProbeValid,worldFiles=pcall(existingWorldFiles) end
    local genuinelyNew=isNewGame and not hasStoredState and fileProbeValid and not worldFiles
    M.status.freshWorld=genuinelyNew==true
    state.legacyAliasesAllowed=false
    local mdoActive=getActivatedMods():contains('MoreDamagedObjects')
    local stateValid=true
    if not fileProbeValid then
        stateValid=false
        warn('save-files','Cannot verify the current save files; continuing with exact identities and inert legacy placeholders only. No new preparation ownership is accepted. '..tostring(worldFiles))
    elseif genuinelyNew then
        oldChunks={};hasIndex=false
        -- The empty ownership boundary of a genuinely new world is complete,
        -- not an unprepared legacy state that a later file may expand.
        state.schema=1;state.chunks={};state.chunkCount=0;state.mdoSeen=mdoActive;state.prepared=true
    else
        if state.schema==1 and state.chunks then
            local valid,count=pcall(function()
                local count=countChunks(state.chunks)
                assert(state.chunkCount==nil or state.chunkCount==count,'Damaged persisted Dr Pepper chunk count')
                assert(state.mdoSeen==nil or type(state.mdoSeen)=='boolean','Invalid persisted MDO history marker')
                assert(state.prepared==nil or type(state.prepared)=='boolean','Invalid persisted preparation marker')
                return count
            end)
            if valid then
                oldChunks=state.chunks;state.chunkCount=count
                if count>0 then
                    -- Older tested preparation records predate this marker.
                    -- Their nonempty validated ownership map remains proof.
                    state.prepared=true;M.status.mode='verified-chunks'
                elseif state.prepared~=true and state.mdoSeen==false then
                    -- An identity-only first launch used to persist chunks={}.
                    -- Permit a verified preparation created afterwards, until
                    -- MDO has actually been observed in this world's runtime.
                    local indexed,problem=pcall(M.loadIndex)
                    if indexed and hasIndex then
                        state.chunks=oldChunks;state.chunkCount=countChunks(oldChunks);state.prepared=true
                        if state.chunkCount>0 then M.status.mode='verified-chunks' end
                    elseif not indexed then
                        oldChunks={};hasIndex=false
                        stateValid=false
                        warn('invalid-index','Poster preparation file is invalid; continuing with exact object identities only. '..tostring(problem))
                    end
                elseif state.prepared~=true and state.mdoSeen==true then
                    -- After MDO has been observed, a new external ownership map
                    -- could claim its later additions. Never enlarge it then.
                    warn('preparation-locked','MDO was already observed in this world; additional legacy chunk ownership will not be accepted. Exact object identities remain available.')
                end
            else
                stateValid=false
                warn('invalid-state','Stored poster preparation is invalid; continuing with exact object identities only. '..tostring(count))
            end
        else
            if state.schema==nil then
                if state.chunks~=nil or state.chunkCount~=nil or state.prepared==true then
                    stateValid=false
                    warn('invalid-state','Stored poster preparation is missing its schema; preserving that record and continuing with exact identities only.')
                elseif (state.mdoSeen~=nil and type(state.mdoSeen)~='boolean')
                        or (state.prepared~=nil and type(state.prepared)~='boolean') then
                    stateValid=false
                    warn('invalid-state','Stored poster history is invalid; continuing with exact object identities and inert legacy placeholders only.')
                elseif state.mdoSeen==true then
                    -- Keep the monotonic history evidence even if another
                    -- field is absent; a new index cannot erase prior MDO use.
                    state.schema=1;state.chunks={};state.chunkCount=0;state.prepared=false
                    warn('preparation-locked','MDO was already observed in this world; additional legacy chunk ownership will not be accepted. Exact object identities remain available.')
                else
                    local valid,problem=pcall(M.loadIndex)
                    if valid and hasIndex then
                        state.schema=1;state.chunks=oldChunks;state.chunkCount=countChunks(oldChunks);state.mdoSeen=mdoActive;state.prepared=true
                        if state.chunkCount>0 then M.status.mode='verified-chunks' end
                    elseif valid then
                    -- No index is a normal upgrade/first installation. Do not
                    -- claim any old numeric slots and do not disable saving.
                        state.schema=1;state.chunks={};state.chunkCount=0;state.mdoSeen=mdoActive;state.prepared=false
                    else
                        oldChunks={};hasIndex=false
                        stateValid=false
                        warn('invalid-index','Poster preparation file is invalid; continuing with exact object identities only. '..tostring(problem))
                    end
                end
            else
                stateValid=false
                warn('unsupported-state','Stored poster preparation is incomplete or unsupported; continuing with exact object identities only.')
            end
        end
    end
    if mdoActive then state.mdoSeen=true end
    if not mdoActive then
        local vacant=legacySlotsVacant(managerForWorld)
        if not stateValid or state.mdoSeen==nil then
            -- Damaged/incomplete history is not evidence that the old numeric
            -- objects were Dr Pepper posters. Keep bytes and placeholders,
            -- but do not display/enable interaction as a Dr Pepper collectible.
            oldChunks={};M.status.mode='identity-only'
            if vacant then registerLegacyAliases(managerForWorld,false) end
            warn('unverified-history','Legacy poster history could not be verified; vacant overlapping numeric slots are kept inert. Exact Dr Pepper identities remain available.')
        elseif state.mdoSeen==true then
            -- MDO may have left its numeric objects in unloaded old chunks.
            -- Never reassign those slots merely because it is now disabled.
            oldChunks={}
            M.status.mode='identity-only'
            if vacant then registerLegacyAliases(managerForWorld,false) end
            warn('mdo-disabled','More Damaged Objects was previously present and is now disabled; vacant legacy numeric slots are retained as inert placeholders. Exact Dr Pepper identities can still be restored.')
        elseif not vacant then
            oldChunks={}
            M.status.mode='identity-only'
            warn('foreign-legacy','Another loaded mod owns the legacy numeric slots; its registration is preserved. Only exact Dr Pepper identities are restored.')
        else
            -- Give retained aliases a visible image while preserving their
            -- original numeric recovery data. Dedicated servers only require
            -- the registered identity, not a texture manager.
            registerLegacyAliases(managerForWorld,true)
            state.legacyAliasesAllowed=true
        end
    end
    end)
    if not ok then M.protect(err) end
    if isServer() and not M.blocked then
        -- Network only the compact presentation decision. The persisted
        -- ownership map may be much larger than the native UDP packet buffer.
        local presentation=ModData.getOrCreate(presentationKey)
        for key in pairs(presentation) do presentation[key]=nil end
        presentation.schema=1
        presentation.legacyAliasesAllowed=M.status.legacyPresentation==true
        presentation.mdoSeen=ModData.getOrCreate(stateKey).mdoSeen~=false
        local sent,problem=pcall(function() ModData.transmit(presentationKey) end)
        if not sent then warn('server-decision','Legacy-presentation decision will be supplied on client request: '..tostring(problem)) end
    end
end)
local function showProtection()
    if not M.blocked or M.modalShown or isServer() then return end
    require 'ISUI/ISModalDialog'
    local text='Dr Pepper asset conflict\n\nA required Dr Pepper sprite is missing or another mod registered its current ID.\nSaving is disabled for this exceptional asset conflict.\nExit this world and check the game log before continuing.\nNormal existing worlds do not require preparation to play.\nOptional legacy recovery tools and their backup instructions are included in the mod.'
    local modal=ISModalDialog:new(0,0,540,240,text,false,nil,nil,0)
    modal:initialise();modal:addToUIManager()
    M.modalShown=true
end
Events.OnGameStart.Add(function()
    M.started=true
    requestPresentationDecision()
    showProtection()
end)
Events.OnTickEvenPaused.Add(function()
    if M.started and M.blocked and not isServer() then
        showProtection()
    end
end)
Events.LoadGridsquare.Add(M.recoverSquare)
