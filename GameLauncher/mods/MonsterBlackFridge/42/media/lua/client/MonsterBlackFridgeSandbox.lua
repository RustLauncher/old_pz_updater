require 'MonsterBlackFridge/Core'
require 'ISUI/ISComboBox'
require 'OptionScreens/ServerSettingsScreen'

-- Preserve saved enum IDs through an integer storage option. Present only
-- the ten requested percentages, sorted by value, in native combo controls.
local M = MonsterBlackFridge
local KEY = 'MonsterBlackFridge.Distribution'
local TEXT = 'Sandbox_MonsterBlackFridge_Distribution'
local function indexFor(value)
    local id=tonumber(value)
    if id==1 then return 0 end -- Retain legacy 0% without adding an 11th choice.
    for i,savedID in ipairs(M.distributionChoices) do if savedID==id then return i end end
    return 10
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
            control.monsterPercentage = true
            function control:setText(value)
                self.selected = indexFor(value)
                -- Native ISComboBox does not call getOptionText for row zero.
                -- Keep the preserved legacy 0% value visible while closed.
                self.noSelectionText = self.selected==0 and getText(TEXT..'_legacy_zero') or nil
            end
            function control:getText() return tostring(self.selected==0 and 1 or (M.distributionChoices[self.selected] or 5)) end
            local previousOptionText=control.getOptionText
            function control:getOptionText(index)
                if index==0 then return getText(TEXT..'_legacy_zero') end
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
        if combo.monsterPercentage then
            for i,item in ipairs(self.items) do item.tooltip = combo:getOptionTooltip(i) end
        end
    end

    local originalUpdateTooltip = ISComboBoxPopup.updateTooltip
    function ISComboBoxPopup:updateTooltip()
        originalUpdateTooltip(self)
        if self.parentCombo and self.parentCombo.monsterPercentage and self.tooltipUI then
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
                    local value = oldControl and oldControl:getText() or '5'
                    item.panel = editor:createPanel(category, item.page)
                    item.panel.controls[KEY]:setText(value)
                    if editor.currentPanel == previous then editor:onMouseDownListBox(item) end
                end
            end
        end
        return result
    end
end
