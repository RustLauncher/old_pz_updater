require 'PepsiFridge/Core'
require 'ISUI/ISComboBox'
require 'OptionScreens/ServerSettingsScreen'

-- Keep real percentages on disk and on the network. Only the menu changes.
-- Preserve existing 0% and custom integer settings until another choice is selected.
local M = PepsiFridge
local CHANCE_TEXT = 'Sandbox_PepsiFridge_Chance'
local configs = {
    ['PepsiFridge.Chance']={text=CHANCE_TEXT,defaultPercent=100,defaultIndex=10},
    ['PepsiFridge.WornChance']={text='Sandbox_PepsiFridge_WornChance',defaultPercent=25,defaultIndex=5},
}
local function indexFor(value,defaultPercent)
    local percent = M.normalizePercent(value,defaultPercent)
    for i,choice in ipairs(M.distributionChoices) do
        if choice == percent then return i end
    end
    return 0 -- Saved values outside the ten choices do not add menu entries.
end

local function setupPage(page)
    local changed = false
    for _,setting in ipairs(page.settings or {}) do
        local config=configs[setting.name]
        if config then
            setting.type = 'enum'
            setting.values = {}
            -- Both chances use the same ten numeric choices. The worn row has
            -- its own translated explanation, not the clean-spawn tooltip.
            for i=1,10 do setting.values[i] = getText(CHANCE_TEXT .. '_option' .. i) end
            setting.default = config.defaultIndex
            setting.tooltip = getText(config.text .. '_tooltip')
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
        local config=configs[arg1] or (arg1=='Sandbox' and configs[arg2])
        if config then
            control.pepsiPercentage = true
            function control:setText(value)
                self.savedPercentage = M.normalizePercent(value,config.defaultPercent)
                self.selected = indexFor(self.savedPercentage,config.defaultPercent)
                -- B42 draws this text for a saved percentage outside the ten
                -- choices. getOptionText(0) alone is not rendered by the box.
                self.noSelectionText = (getText(CHANCE_TEXT..'_saved_value'):gsub('{value}', function()
                    return tostring(self.savedPercentage)
                end))
            end
            function control:getText()
                local value = self.selected == 0 and self.savedPercentage or M.distributionChoices[self.selected]
                return tostring(value or config.defaultPercent)
            end
            local previousOptionText=control.getOptionText
            function control:getOptionText(index)
                if index == 0 then
                    return (getText(CHANCE_TEXT..'_saved_value'):gsub('{value}', function()
                        return tostring(self.savedPercentage or 0)
                    end))
                end
                return previousOptionText(self,index)
            end
            function control:getOptionTooltip(index)
                if index >= 1 and index <= 10 then
                    if config.text==CHANCE_TEXT then
                        return getText(CHANCE_TEXT .. '_option' .. index .. '_tooltip')
                    end
                    return getText(config.text .. '_tooltip')
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
        if combo.pepsiPercentage then
            for i,item in ipairs(self.items) do item.tooltip = combo:getOptionTooltip(i) end
        end
    end

    local originalUpdateTooltip = ISComboBoxPopup.updateTooltip
    function ISComboBoxPopup:updateTooltip()
        originalUpdateTooltip(self)
        if self.parentCombo and self.parentCombo.pepsiPercentage and self.tooltipUI then
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
                    local values={}
                    for key,config in pairs(configs) do
                        local oldControl=previous and previous.controls[key]
                        values[key]=oldControl and oldControl:getText() or tostring(config.defaultPercent)
                    end
                    item.panel = editor:createPanel(category, item.page)
                    for key,value in pairs(values) do
                        local control=item.panel.controls[key]
                        if control then control:setText(value) end
                    end
                    if editor.currentPanel == previous then editor:onMouseDownListBox(item) end
                end
            end
        end
        return result
    end
end
