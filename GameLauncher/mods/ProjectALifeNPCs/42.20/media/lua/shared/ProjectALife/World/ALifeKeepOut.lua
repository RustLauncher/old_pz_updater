ProjectALife = ProjectALife or {}

local KeepOut = {
    hydrateDistance = 60,
    hydrateMargin = 10,
    partyBand = 10,
}
KeepOut.ringTiles = KeepOut.hydrateDistance - KeepOut.hydrateMargin - KeepOut.partyBand
ProjectALife.KeepOut = KeepOut

function KeepOut.partyRing()
    return KeepOut.ringTiles, KeepOut.ringTiles + KeepOut.partyBand
end

function KeepOut.inCone(px, py, fx, fy, x, y, halfCos, range)
    local dx, dy = x - px, y - py
    local d = math.sqrt(dx * dx + dy * dy)
    if d > range or d < 0.001 then return false end
    local fl = math.sqrt(fx * fx + fy * fy)
    if fl < 0.001 then return false end
    return (dx * fx + dy * fy) / (d * fl) >= halfCos
end

function KeepOut.spotAllowed(x, y, list, minimumDistance, coneRange, halfCos)
    for _, p in ipairs(list or {}) do
        local dx, dy = x - p.x, y - p.y
        if dx * dx + dy * dy < minimumDistance * minimumDistance then return false, "too_close" end
        if (p.fx ~= nil or p.fy ~= nil)
                and KeepOut.inCone(p.x, p.y, p.fx or 0, p.fy or 0, x, y, halfCos, coneRange) then
            return false, "in_cone"
        end
    end
    return true
end

return KeepOut
