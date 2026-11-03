require "ISUI/ISComboBox"
require "ProjectALife/Records/ALifePresetValues"

ProjectALife = ProjectALife or {}

local UI = ProjectALife.SandboxPresetUI or {}
ProjectALife.SandboxPresetUI = UI
local Values = ProjectALife.PresetValues

function UI.controls(owner)
    local controls = owner and owner.controls
    if type(controls) ~= "table" then return {} end
    return controls.Sandbox or controls
end

function UI.enum(key)
    return key == "Preset_World" or key == "Preset_Difficulty" or key == "Combat_AimDifficulty"
end

function UI.set(control, key, value)
    if control == nil then return end
    if UI.enum(key) then control.selected = value
    elseif type(control.setText) == "function" then control:setText(tostring(value)) end
end

function UI.writeOption(option, value)
    if option:getType() == "enum" or option:getType() == "boolean" then option:setValue(value)
    else option:parse(tostring(value)) end
end

function UI.eachOption(options, callback)
    if options == nil or type(options.getNumOptions) ~= "function" or type(options.getOptionByIndex) ~= "function" then return end
    for index = 0, options:getNumOptions() - 1 do
        local option = options:getOptionByIndex(index)
        local name = option:getName()
        if string.sub(name, 1, 6) == "ALife." then callback(option, string.sub(name, 7)) end
    end
end

function UI.capture(owner, options)
    local state = owner.alifePresetUI
    state.options = options
    state.pending, state.seen = {}, {}
end

function UI.hydrate(owner)
    local state, controls = owner.alifePresetUI, UI.controls(owner)
    for key, value in pairs(state.pending) do
        local control = controls["ALife." .. key]
        if control ~= nil and state.seen[key] ~= control then
            UI.set(control, key, value)
            state.seen[key] = control
        end
    end
end

function UI.serialize(owner, options)
    local state, controls = owner.alifePresetUI, UI.controls(owner)
    UI.eachOption(options, function(option, key)
        local value = state.pending[key]
        if value ~= nil then
            local control = controls["ALife." .. key]
            if control == nil then UI.writeOption(option, value) end
        end
    end)
end

function UI.installOwner(owner)
    if owner == nil or owner.alifePresetUI ~= nil then return end
    owner.alifePresetUI = { pending = {}, seen = {} }
    if type(owner.settingsToUIAux) == "function" and type(owner.settingsFromUIAux) == "function" then
        local toUI, fromUI = owner.settingsToUIAux, owner.settingsFromUIAux
        owner.settingsToUIAux = function(self, category, options)
            if category == "Sandbox" then UI.capture(self, options) end
            return toUI(self, category, options)
        end
        owner.settingsFromUIAux = function(self, category, options)
            if category == "Sandbox" then UI.serialize(self, options) end
            return fromUI(self, category, options)
        end
    elseif type(owner.settingsToUI) == "function" and type(owner.settingsFromUI) == "function" then
        local toUI, fromUI = owner.settingsToUI, owner.settingsFromUI
        owner.settingsToUI = function(self, options)
            UI.capture(self, options)
            return toUI(self, options)
        end
        owner.settingsFromUI = function(self, options)
            UI.serialize(self, options)
            return fromUI(self, options)
        end
    end
    if type(owner.createPanel) == "function" then
        local create = owner.createPanel
        owner.createPanel = function(self, ...)
            local panel = create(self, ...)
            UI.hydrate(self)
            return panel
        end
    end
end

function UI.selected(owner, combo, optionName)
    local key = string.sub(optionName, 7)
    local tier = tonumber(combo.selected)
    local maximum = key == "Preset_World" and 5 or 4
    if tier == nil or tier < 1 or tier > maximum then return end
    local source, controls = {}, UI.controls(owner)
    local state = owner.alifePresetUI
    UI.eachOption(state.options, function(option, name) source[name] = option:getValue() end)
    for name, value in pairs(state.pending) do source[name] = value end
    for name, control in pairs(controls) do
        if string.sub(name, 1, 6) == "ALife." then
            local setting = string.sub(name, 7)
            if UI.enum(setting) then source[setting] = control.selected
            elseif type(control.getText) == "function" then source[setting] = tonumber(control:getText()) end
        end
    end
    local values = Values.reapply(source, key, math.floor(tier))
    for name, value in pairs(values) do
        state.pending[name] = value
        local control = controls["ALife." .. name]
        UI.set(control, name, value)
        state.seen[name] = control
    end
end

if type(ISComboBox) == "table" and type(ISComboBox.new) == "function" and not ISComboBox.ProjectALifePresetUIHook then
    ISComboBox.ProjectALifePresetUIHook = true
    local original = ISComboBox.new
    function ISComboBox:new(x, y, width, height, target, callback, arg1, arg2)
        local optionName = arg2 or arg1
        if optionName == "ALife.Preset_World" or optionName == "ALife.Preset_Difficulty" then
            UI.installOwner(target)
            local previous = callback
            callback = function(owner, combo, first, second)
                if previous ~= nil then previous(owner, combo, first, second) end
                UI.selected(owner, combo, optionName)
            end
        end
        return original(self, x, y, width, height, target, callback, arg1, arg2)
    end
end

return UI
