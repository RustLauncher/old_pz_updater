require "ProjectALife/Core/ALifeText"
require "ProjectALife/Records/ALifeRepLevels"

ProjectALife = ProjectALife or {}

local Levels = ProjectALife.RepLevels
local Icons = {
    dir = "media/ui/ProjectALife/RepIcons/",
    lockedName = "rep_locked",
    retryMs = 20000,
    textures = {},
    missing = {},
    ramp = {
        { 0.545, 0.118, 0.176 }, { 0.753, 0.224, 0.169 }, { 0.851, 0.329, 0.118 }, { 0.902, 0.494, 0.133 },
        { 0.831, 0.675, 0.051 }, { 0.541, 0.576, 0.608 }, { 0.345, 0.702, 0.408 }, { 0.153, 0.682, 0.561 },
        { 0.204, 0.596, 0.859 }, { 0.357, 0.424, 0.941 }, { 0.945, 0.769, 0.059 },
    },
}
ProjectALife.RepIcons = Icons

function Icons.path(id)
    return Icons.dir .. tostring(id or Icons.lockedName) .. ".png"
end

function Icons.texture(id)
    local key = tostring(id or Icons.lockedName)
    local cached = Icons.textures[key]
    if cached ~= nil then return cached end
    local now = type(getTimestampMs) == "function" and getTimestampMs() or 0
    local failed = Icons.missing[key]
    if failed ~= nil and now - failed < Icons.retryMs then return nil end
    local texture = nil
    if type(getTexture) == "function" then
        local ok, result = pcall(getTexture, Icons.path(key))
        if ok then texture = result end
    end
    if texture == nil then
        Icons.missing[key] = now
        return nil
    end
    Icons.missing[key] = nil
    Icons.textures[key] = texture
    return texture
end

function Icons.scaled(score)
    local value = Levels.clamp(score) / 10
    local out
    if value >= 0 then out = math.floor(value + 0.5) else out = -math.floor(-value + 0.5) end
    if out == 0 then return 0 end
    return out
end

function Icons.signed(score)
    local number = Icons.scaled(score)
    if number > 0 then return "+" .. tostring(number) end
    return tostring(number)
end

function Icons.deltaText(delta)
    local value = (tonumber(delta) or 0) / 10
    local magnitude = math.abs(value)
    local tenths = math.floor(magnitude * 10 + 0.5)
    if tenths == 0 then return "0" end
    local text
    if magnitude >= 10 then
        text = tostring(math.floor(magnitude + 0.5))
    elseif tenths % 10 == 0 then
        text = tostring(math.floor(tenths / 10))
    else
        local whole = math.floor(tenths / 10)
        text = tostring(whole) .. "." .. tostring(tenths - whole * 10)
    end
    if value < 0 then return "-" .. text end
    return "+" .. text
end

function Icons.rangeText(index)
    local low, high = Levels.rangeOf(index)
    if low == nil then return nil end
    return ProjectALife.Text.ui("{low} to {high}", { low = Icons.signed(low), high = Icons.signed(high) })
end

function Icons.label(levelId, score, showScore)
    local name = Levels.name(levelId)
    if name == nil then return nil end
    if showScore ~= false and tonumber(score) ~= nil then return name .. " (" .. Icons.signed(score) .. ")" end
    return name
end

function Icons.reach(low, high, index)
    local neutral, count = Levels.neutralIndex(), Levels.count()
    local lo = math.floor(tonumber(low) or neutral)
    local hi = math.floor(tonumber(high) or neutral)
    if lo < 1 then lo = 1 end
    if lo > neutral then lo = neutral end
    if hi > count then hi = count end
    if hi < neutral then hi = neutral end
    if tonumber(index) ~= nil and index >= 1 and index <= count then
        if index < lo then lo = index end
        if index > hi then hi = index end
    end
    return lo, hi
end

function Icons.entries(view)
    local rows = Levels.rows
    view = type(view) == "table" and view or {}
    local current = Levels.indexOf(view.level)
    local lo, hi = Icons.reach(view.reachedMin, view.reachedMax, current)
    local list = {}
    for index = 1, #rows do
        list[index] = {
            index = index,
            id = rows[index].id,
            unlocked = index >= lo and index <= hi,
            current = index == current,
        }
    end
    return list, lo, hi
end

function Icons.color(index, alpha, lift)
    local ramp = Icons.ramp
    local count = Levels.count()
    local t = 0.5
    if count > 1 then t = (math.min(math.max(tonumber(index) or 1, 1), count) - 1) / (count - 1) end
    local position = t * (#ramp - 1) + 1
    local low = math.floor(position)
    local high = math.min(#ramp, low + 1)
    local mix = position - low
    local a, b = ramp[low], ramp[high]
    local r, g, bl = a[1] + (b[1] - a[1]) * mix, a[2] + (b[2] - a[2]) * mix, a[3] + (b[3] - a[3]) * mix
    local up = tonumber(lift) or 0
    if up > 0 then
        r, g, bl = r + (1 - r) * up, g + (1 - g) * up, bl + (1 - bl) * up
    end
    return { r = r, g = g, b = bl, a = tonumber(alpha) or 1 }
end

function Icons.reasonOf(cause)
    local key = tostring(cause or "")
    local words = Icons.reasons[key]
    if words == nil then return nil end
    return ProjectALife.Text.ui(words)
end

Icons.reasons = {
    kill_hostile = "killed a hostile survivor",
    kill_crime = "killed a criminal",
    kill_neutral = "killed someone who meant no harm",
    kill_careful = "killed someone who kept their distance",
    kill_friendly = "killed a friend",
    kill_surrendered = "shot someone who had given up",
    kill_attackedFirst = "killed someone you attacked first",
    kill_unknown = "killed a survivor",
    door_rude = "slammed the door on a visitor",
    deed_let_in = "let a visitor in",
    deed_let_sleep = "gave a guest a roof",
    deed_treated_wounded = "patched up a visitor",
    deed_sheltered_chased = "sheltered someone being chased",
    deed_neighbour_watch = "watched out for a neighbour",
    deed_gave_food = "shared food at the door",
    deed_kind_word = "had a kind word at the door",
    deed_fair_trade = "traded fairly",
    deed_census_answer = "answered the census",
    deed_finished_job = "finished a job for a neighbour",
    deed_answered_call = "answered a call for help",
    deed_helped_fight = "fought beside a survivor",
    deed_walk = "walked the road with a survivor",
    deed_party_task = "came through for the group",
    deed_robbery = "robbed a survivor",
    deed_betrayal = "broke a deal",
    deed_party_desert = "left the group behind",
    deed_party_fail = "let the group down",
    deed_threat_failed = "made an empty threat",
    interrogated = "roughed up an injured survivor",
    saved = "helped an injured survivor",
    helped = "helped a survivor",
    robbed = "robbed a survivor",
    betrayed = "broke a deal",
}

return Icons
