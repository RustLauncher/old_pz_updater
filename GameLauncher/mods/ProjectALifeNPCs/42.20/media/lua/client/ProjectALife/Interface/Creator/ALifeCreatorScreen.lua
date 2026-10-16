require "ProjectALife/Talk/ALifeTalkUi"
require "ProjectALife/Interface/Creator/ALifeCreatorCore"
require "ProjectALife/Interface/Creator/ALifeCreatorIdentity"
require "ProjectALife/Interface/Creator/ALifeCreatorAppearance"
require "ProjectALife/Interface/Creator/ALifeCreatorWardrobe"
require "ProjectALife/Interface/Creator/ALifeCreatorSeasonalActions"
require "ProjectALife/Interface/Creator/ALifeCreatorClothingView"
require "ProjectALife/Interface/Creator/ALifeCreatorOutfitHealth"
require "ProjectALife/Interface/Creator/ALifeCreatorFaces"
require "ProjectALife/Interface/Creator/ALifeCreatorLoadout"
require "ProjectALife/Interface/Creator/ALifeCreatorCombat"
require "ProjectALife/Interface/Creator/ALifeCreatorBehavior"
require "ProjectALife/Interface/Creator/ALifeCreatorModules"
require "ProjectALife/Interface/Creator/ALifeCreatorFactionIdentity"
require "ProjectALife/Interface/Creator/ALifeCreatorFactionRelations"
require "ProjectALife/Interface/Creator/ALifeCreatorFactionSpawning"
require "ProjectALife/Interface/Creator/ALifeCreatorFactionSupport"
require "ProjectALife/Interface/Creator/ALifeCreatorFactionModules"
require "ProjectALife/Interface/Creator/ALifeCreatorHelp"
require "ProjectALife/Interface/Creator/ALifeCreatorSaveQueue"
require "ProjectALife/Interface/Creator/ALifeCreatorLoadProgress"

local Creator = ProjectALife.CreatorScreen

if type(Events) == "table" and Events.OnMainMenuEnter
        and type(Events.OnMainMenuEnter.Add) == "function" then
    Events.OnMainMenuEnter.Add(Creator.onMainMenuEnter)
end

if type(Events) == "table" and Events.OnPreUIDraw
        and type(Events.OnPreUIDraw.Add) == "function" then
    Events.OnPreUIDraw.Add(Creator.syncMainMenuBrand)
end
if type(Events) == "table" and Events.OnServerCommand
        and type(Events.OnServerCommand.Add) == "function" then
    Events.OnServerCommand.Add(Creator.onCreatorServerCommand)
end
if type(Events) == "table" and Events.OnKeyPressed
        and type(Events.OnKeyPressed.Add) == "function" then
    Events.OnKeyPressed.Add(Creator.onKeyPressed)
end
if type(Events) == "table" and Events.OnFillWorldObjectContextMenu
        and type(Events.OnFillWorldObjectContextMenu.Add) == "function" then
    Events.OnFillWorldObjectContextMenu.Add(ProjectALife.TalkUi.guarded(Creator.onCreatorWorldContext))
end

return Creator
