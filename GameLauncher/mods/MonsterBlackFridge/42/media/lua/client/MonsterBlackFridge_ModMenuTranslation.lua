-- B42 can cache mod.info before Languages.init(), retaining English metadata.
-- Refresh only this mod from its existing Mod.json after the language is ready.
local function refreshModMenuTranslation()
    local info = getModInfoByID("MonsterBlackFridge")
    if info then
        Translator.readModTranslation(info)
    end
end

Events.OnMainMenuEnter.Add(refreshModMenuTranslation)
