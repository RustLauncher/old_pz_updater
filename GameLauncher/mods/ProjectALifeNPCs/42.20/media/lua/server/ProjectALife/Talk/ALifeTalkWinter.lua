require "ProjectALife/Talk/ALifeTalk"
require "ProjectALife/Talk/ALifeTalkWinterRows"
require "ProjectALife/Behaviours/ALifeCold"

ProjectALife = ProjectALife or {}

local Winter = {
    metrics = { answered = 0, fellBack = 0 },
}
ProjectALife.TalkWinter = Winter

function Winter.keyFor(id, record, shell, now)
    local rows = ProjectALife.TalkWinterRows
    local snapshot = rows.snapshot()
    local state = ProjectALife.Cold.view(record)
    local season, sky = string.upper(snapshot.season), snapshot.sky
    if id == "ASK_COLD_FEEL" then
        if state == "sick" then return "COLDQ_SICK" end
        if state == "freezing" then return "COLDQ_FREEZING" end
        if state == "chilled" then return "COLDQ_CHILLED" end
        return rows.chilly(snapshot) and "COLDQ_WELL_COLD" or "COLDQ_WELL_MILD"
    elseif id == "ASK_GOT_COLD" then
        if state == "sick" then return "GOTQ_SICK" end
        if state == "freezing" or state == "chilled" then return "GOTQ_CHILLED" end
        return "GOTQ_WELL"
    elseif id == "ASK_STAY_WARM" then
        return rows.chilly(snapshot) and "WARMQ_COLD" or "WARMQ_MILD"
    elseif id == "ASK_REMEDY" then
        return state == "sick" and "REMQ_SICK" or "REMQ_WELL"
    elseif id == "ASK_WINTER" then
        return "WINQ_" .. season
    elseif id == "ASK_WEATHER" then
        return "WXQ_" .. string.upper(sky)
    elseif id == "ASK_SEASON" then
        return "SEAQ_" .. season
    elseif id == "ASK_SNOW" then
        return snapshot.snowing and "SNOWQ_FALLING" or "SNOWQ_GROUND"
    elseif id == "ASK_HEAT" then
        return "HEATQ"
    elseif id == "ASK_WARM_PLACE" then
        local fire = nil
        local weather = ProjectALife.Seasons.weather(now)
        if shell ~= nil then
            local ok, found = pcall(ProjectALife.Cold.nearestFire, shell, weather, now)
            if ok then fire = found end
        end
        return fire ~= nil and "FIREQ_NEAR" or "FIREQ_NONE"
    elseif id == "ASK_HARVEST" then
        if season == "WINTER" then return nil end
        return "HARQ_" .. season
    end
    return nil
end

function Winter.handler(id)
    return function(record, shell, player, context, now, text)
        local key = Winter.keyFor(id, record, shell, now)
        local data = ProjectALife.DialogueData
        local pool = key ~= nil and data.replies[key] or nil
        if pool == nil or #pool == 0 then
            Winter.metrics.fellBack = Winter.metrics.fellBack + 1
            return nil
        end
        local talk = ProjectALife.Talk
        local said, chosen = talk.speak(record, shell, player, pool, context, talk.varsFor(id, record, shell, player, text))
        if said == nil then return nil end
        Winter.metrics.answered = Winter.metrics.answered + 1
        return said, chosen ~= nil and chosen.beats ~= nil and "scripted" or "answered"
    end
end

for _, row in ipairs(ProjectALife.TalkWinterRows.defs) do
    ProjectALife.Talk.choiceHandlers[row.id] = Winter.handler(row.id)
end

return Winter
