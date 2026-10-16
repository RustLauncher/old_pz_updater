-- Minimal Build 42 compatibility layer for the APIs used by Water Trailer.
-- Keep this namespace private to the mod. W900 owns its global compatibility API.

rWaterTrailer = rWaterTrailer or {}
rWaterTrailer.Compat = rWaterTrailer.Compat or {}

local compat = rWaterTrailer.Compat
compat.Washing = compat.Washing or {}
compat.UI = compat.UI or {}
compat.Commands = compat.Commands or {}
compat.Events = compat.Events or { Current = nil, Listeners = {} }

function compat.dprint(text, ...)
    if getDebug() then
        print(string.format(text, ...))
    end
end

function compat.dhalo(player, text, ...)
    if getDebug() then
        player:setHaloNote(string.format(text, ...))
    end
end

function compat.Washing.GetBloodAndDirt(player)
    local total = 0
    local visual = player:getHumanVisual()
    for i = 0, BloodBodyPartType.MAX:index() - 1 do
        local part = BloodBodyPartType.FromIndex(i)
        total = total + visual:getBlood(part) + visual:getDirt(part)
    end
    return total
end

function compat.UI.UpdateAndCall(func, ...)
    UIManager.update()
    func(...)
end

function compat.Commands.SendToServer(player, command, args, debug)
    if debug then
        compat.dprint("[WaterTrailerB42] -> %s", command)
        args._dbg_ = true
    end
    sendClientCommand(player, "rWaterTrailerB42", command, args)
end

function compat.Events.On(name, func)
    compat.Events.Listeners[name] = compat.Events.Listeners[name] or {}
    table.insert(compat.Events.Listeners[name], func)
end

function compat.Events.Run(name, ...)
    compat.Events.Current = name
    for _, func in ipairs(compat.Events.Listeners[name] or {}) do
        func(...)
    end
    compat.Events.Current = nil
end

return compat
