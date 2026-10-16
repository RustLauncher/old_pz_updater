require "ProjectALife/Admin/ALifeAdminConsole"

ProjectALife = ProjectALife or {}

local Tab = {}
ProjectALife.AdminCleanupTab = Tab

function Tab.launch(playerNum)
    local window = ProjectALife["CleanupWindow"]
    if window == nil or type(window.open) ~= "function" then return nil end
    return window.open(playerNum)
end

function Tab.register()
    local tab = ProjectALife.AdminActions.tab("cleanup")
    return ProjectALife.AdminConsole.addTab({ id = "cleanup", title = tab.title, order = tab.order, tip = tab.tip, builtin = true,
        launcher = Tab.launch,
        description = "Scan and clean A-Life leftovers: NPCs, outposts and bases, vehicles, markers and world data. The cleanup tool opens its own window, starts with a scan that deletes nothing and asks you to type a confirmation phrase before it removes anything." })
end

Tab.register()

return Tab
