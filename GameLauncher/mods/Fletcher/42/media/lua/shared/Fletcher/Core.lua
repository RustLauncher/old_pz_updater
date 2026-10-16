--[[
    Fletcher: archery overhaul for Build 42 (design: "Fletcher Design Notes.md" at the repo root).

    Shared core: the mod table, version and logging. Systems (items, crafting, the Archery skill,
    the server-authoritative projectile system) and the animation wiring come in later phases.
]]

Fletcher = Fletcher or {}
local F = Fletcher

F.VERSION = "0.9.0"

function F.log(msg)
    print("[Fletcher] " .. tostring(msg))
end

return F
