-- Exceptional recovery asset/registry failures must not be followed by saving
-- missing sprites. Own only the false->true NoSave transition this mod makes.
ViniFridgeRecovery=ViniFridgeRecovery or {}
local R=ViniFridgeRecovery
local key='ViniFridgeRecovery_NoSaveGuard'
local owner='ViniFridgeRecovery'
local function valid(value)
    return type(value)=='table' and value.schema==1 and value.owner==owner
        and type(value.previous)=='boolean' and value.owns==(not value.previous)
end
local function persist()
    if not R.blocked then return end
    local data=getGameTime():getModData()
    if data[key]==nil or valid(data[key]) then
        data[key]={schema=1,owner=owner,previous=R.previousNoSave,owns=R.ownsNoSave}
    end
end
function R.protect(reason)
    if not R.blocked then
        R.previousNoSave=getCore():isNoSave()
        R.ownsNoSave=not R.previousNoSave
    end
    R.blocked=true
    R.protectionReason=tostring(reason)
    getCore():setNoSave(true)
    persist()
    print('[VINI Furniture Recovery] SAVE BLOCKED: '..R.protectionReason..'. Close this world/server and enable the original VINI mod(s), or resolve the conflicting registration. Recovery did not safely initialize.')
end
function R.restoreProtection()
    local data=getGameTime():getModData()
    local saved=data[key]
    local owns=R.blocked and R.ownsNoSave or valid(saved) and saved.owns
    -- If NoSave was already enabled, this helper never owns it and never
    -- unlocks it. Do not reinstate another guard after it has already cleared.
    if owns and getCore():isNoSave() then getCore():setNoSave(false) end
    if valid(saved) then data[key]=nil end
    R.blocked=false;R.previousNoSave=nil;R.ownsNoSave=nil;R.protectionReason=nil
    if R.protectionModal then R.protectionModal:removeFromUIManager();R.protectionModal=nil end
end
Events.OnInitWorld.Add(R.restoreProtection)
-- OnLoadedTileDefinitions precedes GameTime.load. Refresh our temporary marker
-- after that loader, so it can also survive the normal Lua reset/menu route.
Events.OnInitGlobalModData.Add(persist)
Events.OnMainMenuEnter.Add(R.restoreProtection)
Events.OnGameStart.Add(function()
    if not R.blocked or isServer() then return end
    if setGameSpeed then setGameSpeed(0) end
    if ISModalDialog then
        local text='Furniture Recovery could not safely load the old furniture. Saving is disabled to protect this world. Return to the main menu and enable the original VINI mod(s), or resolve the conflicting mod before trying Recovery again.'
        local modal=ISModalDialog:new(0,0,540,190,text,false,nil,nil)
        modal:initialise();modal:addToUIManager();R.protectionModal=modal
    end
end)
