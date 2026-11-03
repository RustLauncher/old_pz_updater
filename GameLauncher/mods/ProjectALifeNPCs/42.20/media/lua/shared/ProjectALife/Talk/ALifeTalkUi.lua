ProjectALife = ProjectALife or {}

local Ui = {
    minOpacity = 40,
    maxOpacity = 100,
}
ProjectALife.TalkUi = Ui

function Ui.opacity()
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    local value = type(vars) == "table" and tonumber(vars.Talk_UIOpacity) or nil
    if value == nil or value ~= value then return 1 end
    value = math.floor(value)
    if value < Ui.minOpacity then value = Ui.minOpacity end
    if value > Ui.maxOpacity then value = Ui.maxOpacity end
    return value / 100
end

function Ui.shade(alpha)
    return alpha * Ui.opacity()
end

function Ui.startButton()
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    if type(vars) == "table" and vars.Talk_StartButton == false then return false end
    return true
end

function Ui.chatMode()
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    local value = type(vars) == "table" and tonumber(vars.Text_NpcChatLog) or nil
    if value == nil or value ~= value then return 0 end
    value = math.floor(value)
    if value >= 3 then return 2 end
    if value == 2 then return 1 end
    return 0
end

function Ui.visitStamp(record)
    if type(record) ~= "table" then return nil end
    local memory = record.memory
    local stamp = type(memory) == "table" and memory.visit or nil
    if type(stamp) == "table" and stamp.generation == record.generation then return stamp end
    return nil
end

function Ui.no()
    return false
end

function Ui.passThrough(element)
    if element == nil then return element end
    if type(element.setWantMouseEvents) == "function" then element:setWantMouseEvents(false) end
    element.wantMouseEvents = false
    element.onMouseDown, element.onMouseUp = Ui.no, Ui.no
    element.onRightMouseDown, element.onRightMouseUp = Ui.no, Ui.no
    element.onMouseWheel = Ui.no
    return element
end

Ui.faults = 0

function Ui.guarded(fn)
    return function(...)
        local ok, result = pcall(fn, ...)
        if ok then return result end
        Ui.faults = Ui.faults + 1
        Ui.lastFault = string.sub(tostring(result), 1, 160)
        return nil
    end
end

return Ui
