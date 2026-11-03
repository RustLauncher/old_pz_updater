CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

local pendingOldSave = false

local function popup(text, onclick)
    local w, h = ISModalDialog.CalcSize(300, 100, (text:gsub("\\n", "\n")))
    local core = getCore()
    local p = ISModalDialog:new((core:getScreenWidth() - w) / 2, (core:getScreenHeight() - h) / 2,
                                w, h, text, false, nil, onclick)
    p:setAlwaysOnTop(true)
    p:initialise()
    p:addToUIManager()
end

local function checkExistingSave(newGame)
    local md = ModData.getOrCreate(CD.MODULE)
    if newGame then
        md.bornWithMod = true
    elseif not md.bornWithMod then
        pendingOldSave = true
    end
end

local function rigClipCount(modelScript)
    local viewer = AnimationViewerState.checkInstance()
    if not viewer then return 0 end
    local n = 0
    local clips = viewer:fromLua1("getClipNames", modelScript)
    if clips then
        n = clips:size()
    end
    viewer:fromLua0("exit")
    return n
end

local function onGameStart()
    if pendingOldSave then
        pendingOldSave = false
        popup(getText("IGUI_PD_WarnOldSave"), function()
            ModData.getOrCreate(CD.MODULE).bornWithMod = true
        end)
    end
    if rigClipCount("Base.GermanShepherd_Body") == 0 then
        CD.log("nenhum clip em Base.GermanShepherd_Body")
        popup(getText("IGUI_PD_WarnRigMissing"))
    end
end

if not isClient() and not isServer() then
    Events.OnInitGlobalModData.Add(checkExistingSave)
    Events.OnGameStart.Add(onGameStart)
end
