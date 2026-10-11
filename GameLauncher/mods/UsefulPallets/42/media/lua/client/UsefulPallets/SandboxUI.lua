require "UsefulPallets/Config"
require "OptionScreens/ServerSettingsScreen"

local capacityOptions = {}
for _, material in ipairs(UsefulPallets.materials) do
    local name = "UsefulPallets." .. string.sub(material.item, 6)
    capacityOptions[name .. "ConstructionCapacity"] = true
    capacityOptions[name .. "MilitaryCapacity"] = true
end

local function addLimitsHeading(page)
    for _, setting in ipairs(page.settings or {}) do
        if capacityOptions[setting.name] then
            if setting.title == "UsefulPalletsItemLimits" then return false end
            setting.title = "UsefulPalletsItemLimits"
            return true
        end
    end
    return false
end

-- New-game settings use a copy of the native page definitions.
local originalSettings = ServerSettingsScreen.getSandboxSettingsTable
function ServerSettingsScreen.getSandboxSettingsTable(...)
    local pages = originalSettings(...)
    for _, page in ipairs(pages) do addLimitsHeading(page) end
    return pages
end

-- Hosted settings use the original definitions, exposed through the page list.
local originalCreate = ServerSettingsScreen.create
function ServerSettingsScreen:create(...)
    local result = originalCreate(self, ...)
    local editor = self.pageEdit
    local category
    for _, entry in ipairs(editor.listbox.items) do
        local item = entry.item
        if item.category then category = item.category end
        if item.page and addLimitsHeading(item.page) then
            local oldPanel = item.panel
            item.panel = editor:createPanel(category, item.page)
            if editor.currentPanel == oldPanel then
                editor:onMouseDownListBox(item)
            end
        end
    end
    return result
end
