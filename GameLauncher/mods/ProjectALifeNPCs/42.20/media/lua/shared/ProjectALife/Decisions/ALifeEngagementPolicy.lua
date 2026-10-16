ProjectALife = ProjectALife or {}

local Policy = {}
ProjectALife.EngagementPolicy = Policy

function Policy.evaluate(facts)
    facts = type(facts) == "table" and facts or {}
    local kind = facts.targetKind
    if kind ~= "zombie" and kind ~= "player" and kind ~= "npc" then
        return "watch", "unknown_target"
    end
    local pressured = facts.exhausted == true or facts.wounded == true
        or facts.outnumbered == true
    if pressured and facts.canEscape == true then
        return "disengage", "survival_pressure"
    end
    if facts.immediateDanger == true or facts.targetAttacking == true then
        return "defend", "immediate_threat"
    end
    if pressured then return "watch", "avoid_commitment" end
    if kind == "zombie" then
        if facts.routeBlocked == true then return "commit", "route_blocked" end
        if facts.mission == "combat" or facts.mission == "rescue" then
            return "commit", "explicit_mission"
        end
        if facts.mission == "guard" and facts.inTerritory == true then
            return "commit", "defend_territory"
        end
        return "bypass", "continue_mission"
    end
    if facts.relation == "hostile" then
        if facts.holdOff ~= nil then return "disengage", "discretion_" .. tostring(facts.holdOff) end
        return "commit", "explicit_hostility"
    end
    if facts.mission == "guard" and facts.relation == "careful"
            and facts.inTerritory == true and facts.warned == true then
        return "commit", "territory_warning_exhausted"
    end
    return "watch", "no_hostile_commitment"
end

return Policy
