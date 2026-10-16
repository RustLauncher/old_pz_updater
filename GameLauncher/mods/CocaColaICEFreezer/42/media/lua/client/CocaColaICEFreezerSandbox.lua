require 'CocaColaICEFreezer/Core'
require 'ISUI/ISComboBox'
require 'OptionScreens/ServerSettingsScreen'

-- Keep real percentages on disk and on the network. Only the menu changes.
-- Preserve existing 0% and custom integer settings until another choice is selected.
local M = CocaColaICEFreezer
local KEY = 'CocaColaICEFreezer.Chance'
local TEXT = 'Sandbox_CocaColaICEFreezer_Chance'
local function indexFor(value)
    local percent = M.normalizePercent(value)
    for i,choice in ipairs(M.distributionChoices) do
        if choice == percent then return i end
    end
    return 0 -- Saved values outside the ten choices do not add menu entries.
end

local function setupPage(page)
    local changed = false
    for _,setting in ipairs(page.settings or {}) do
        if setting.name == KEY then
            setting.type = 'enum'
            setting.values = {}
            for i=1,10 do setting.values[i] = getText(TEXT .. '_option' .. i) end
            setting.default = 10
            setting.tooltip = getText(TEXT .. '_tooltip')
            changed = true
        end
    end
    return changed
end

if not M.sandboxComboV2Installed then
    M.sandboxComboV2Installed = true
    -- SettingsTable is LOCAL to vanilla ServerSettingsScreen.lua. Intercept
    -- the public getter actually used to construct the new-game sandbox menu.
    local originalGetSettings = ServerSettingsScreen.getSandboxSettingsTable
    function ServerSettingsScreen.getSandboxSettingsTable(...)
        local pages = originalGetSettings(...)
        for _,page in ipairs(pages) do setupPage(page) end
        return pages
    end

    local originalNew = ISComboBox.new
    function ISComboBox:new(x, y, width, height, target, onChange, arg1, arg2)
        local control = originalNew(self, x, y, width, height, target, onChange, arg1, arg2)
        if arg1 == KEY or (arg1 == 'Sandbox' and arg2 == KEY) then
            control.cocaColaPercentage = true
            function control:setText(value)
                self.savedPercentage = M.normalizePercent(value)
                self.selected = indexFor(self.savedPercentage)
            end
            function control:getText()
                local value = self.selected == 0 and self.savedPercentage or M.distributionChoices[self.selected]
                return tostring(value or 100)
            end
            local previousOptionText=control.getOptionText
            function control:getOptionText(index)
                if index == 0 then
                    return (getText(TEXT..'_saved_value'):gsub('{value}', function()
                        return tostring(self.savedPercentage or 0)
                    end))
                end
                return previousOptionText(self,index)
            end
            function control:getOptionTooltip(index)
                if index >= 1 and index <= 10 then
                    return getText(TEXT .. '_option' .. index .. '_tooltip')
                end
            end
        end
        return control
    end

    -- B42 fills its shared popup with labels only. Supply per-row descriptions
    -- so hovering any open choice shows its explanation before selecting it.
    local originalSetCombo = ISComboBoxPopup.setComboBox
    function ISComboBoxPopup:setComboBox(combo)
        originalSetCombo(self, combo)
        if combo.cocaColaPercentage then
            for i,item in ipairs(self.items) do item.tooltip = combo:getOptionTooltip(i) end
        end
    end

    local originalUpdateTooltip = ISComboBoxPopup.updateTooltip
    function ISComboBoxPopup:updateTooltip()
        originalUpdateTooltip(self)
        if self.parentCombo and self.parentCombo.cocaColaPercentage and self.tooltipUI then
            self.tooltipUI.maxLineWidth = 320
        end
    end

    -- Hosting uses the private table directly. Once its pages exist, rebuild
    -- just our page through its native factory; leave other pages untouched.
    local originalCreateServer = ServerSettingsScreen.create
    function ServerSettingsScreen:create(...)
        local result = originalCreateServer(self, ...)
        local editor = self.pageEdit
        if editor and editor.listbox then
            local category
            for _,row in ipairs(editor.listbox.items) do
                local item = row.item
                if item.category then category = item.category end
                if category and category.name == 'Sandbox' and item.page and setupPage(item.page) then
                    local previous = item.panel
                    local oldControl = previous and previous.controls[KEY]
                    local value = oldControl and oldControl:getText() or '100'
                    item.panel = editor:createPanel(category, item.page)
                    item.panel.controls[KEY]:setText(value)
                    if editor.currentPanel == previous then editor:onMouseDownListBox(item) end
                end
            end
        end
        return result
    end
end
