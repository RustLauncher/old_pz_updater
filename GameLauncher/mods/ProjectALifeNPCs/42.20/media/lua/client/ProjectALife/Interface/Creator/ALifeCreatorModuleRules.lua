require "ProjectALife/Interface/Creator/ALifeCreatorCore"

local Creator = ProjectALife.CreatorScreen

Creator.ruleWarnColor = { r = 0.92, g = 0.55, b = 0.18, a = 1 }

function Creator.moduleRuleNote(id)
    local rules = ProjectALife.ModuleRules
    if rules == nil or type(rules.notes) ~= "function" then return "" end
    local notes = rules.notes(id)
    if #notes == 0 then return "" end
    return " RULES: " .. table.concat(notes, " ")
end

function Creator.moduleStatesFor(id, states)
    local rules = ProjectALife.ModuleRules
    if rules == nil or type(rules.optIn) ~= "function" or not rules.optIn(id) then return states end
    local result = {}
    for index, state in ipairs(states) do
        if index == 1 then result[1] = { state[1] .. " (Off)", state[2] } else result[index] = state end
    end
    return result
end

function Creator.moduleLabelOf(id)
    for _, spec in ipairs(Creator.memberModules) do
        if spec[1] ~= nil and spec[2] == id then return tostring(spec[1]) end
    end
    return tostring(id)
end

function Creator.moduleRuleWarnings(id, lookup)
    local rules = ProjectALife.ModuleRules
    local result = {}
    if rules == nil or type(rules.entries) ~= "table" then return result end
    local own = lookup(id)
    for _, entry in ipairs(rules.entries) do
        if entry.builtin ~= true and entry.module == id then
            if entry.kind == "requires" and own == "on" and lookup(entry.needs) == "off" then
                result[#result + 1] = "Disabled: " .. Creator.moduleLabelOf(entry.needs) .. " is Off. " .. entry.note
            elseif entry.kind == "disabledBy" and own ~= "off" and lookup(entry.by) == entry.state then
                result[#result + 1] = "Disabled by " .. Creator.moduleLabelOf(entry.by) .. " = " .. tostring(entry.state)
                    .. ". " .. entry.note
            end
        end
    end
    return result
end

function Creator.refreshModuleRuleHints(destination)
    if type(destination) ~= "table" then return end
    local function stateOf(id)
        local combo = destination[id]
        if combo == nil or type(combo.getOptionData) ~= "function" then return "inherit" end
        return combo:getOptionData(combo.selected) or "inherit"
    end
    for _, spec in ipairs(Creator.memberModules) do
        local combo = destination[spec[2]]
        if combo ~= nil then
            combo.ruleBorder = combo.ruleBorder or combo.borderColor
            local warnings = Creator.moduleRuleWarnings(spec[2], stateOf)
            if #warnings > 0 then
                local warn = Creator.ruleWarnColor
                combo.borderColor = { r = warn.r, g = warn.g, b = warn.b, a = warn.a }
                Creator.addTooltip(combo, table.concat(warnings, " ") .. " | " .. tostring(combo.ruleTip or ""))
            else
                combo.borderColor = combo.ruleBorder
                Creator.addTooltip(combo, combo.ruleTip)
            end
        end
    end
end

function Creator.installModuleRuleHints(destination)
    if type(destination) ~= "table" then return end
    for _, spec in ipairs(Creator.memberModules) do
        local combo = destination[spec[2]]
        if combo ~= nil and type(combo.setOnChange) == "function" then
            combo:setOnChange(destination, function(target) Creator.refreshModuleRuleHints(target) end)
        end
    end
    Creator.refreshModuleRuleHints(destination)
end

return Creator
