require "ProjectALife/Decisions/ALifeReputation"

ProjectALife = ProjectALife or {}
local Standing = { TAG = "ProjectALife.Standing.v1", SCHEMA = 1, enabled = false,
    adapters = {}, storage = nil, dirty = false, settings = { decayPercent = 100, gainCapPerDay = 15, countedCap = 256 } }
ProjectALife.Standing = Standing

function Standing.authoritative()
    return not (type(isClient) == "function" and isClient() == true)
end

function Standing.enabledHere()
    if not Standing.enabled then return false end
    if type(SandboxVars) == "table" and type(SandboxVars.ALife) == "table" then
        return tonumber(SandboxVars.ALife.Reputation_Mode) == 2
    end
    return true
end

function Standing.hours()
    if type(Standing.adapters.nowHours) == "function" then return tonumber(Standing.adapters.nowHours()) or 0 end
    if type(getGameTime) == "function" then
        local time = getGameTime()
        if time ~= nil and type(time.getWorldAgeHours) == "function" then return tonumber(time:getWorldAgeHours()) or 0 end
    end
    return 0
end

function Standing.configure(options)
    options = type(options) == "table" and options or {}
    Standing.enabled = options.enabled == true
    Standing.settings.decayPercent = math.max(0, math.min(300, tonumber(options.decayPercent) or 100))
    Standing.adapters = type(options.adapters) == "table" and options.adapters or {}
    Standing.storage, Standing.dirty = nil, false
end

function Standing.store()
    if not Standing.enabledHere() or not Standing.authoritative() then return nil, "standing_disabled" end
    if Standing.storage ~= nil then return Standing.storage end
    local state
    if type(Standing.adapters.getOrCreate) == "function" then
        state = Standing.adapters.getOrCreate(Standing.TAG)
    elseif ModData ~= nil and type(ModData.getOrCreate) == "function" then
        state = ModData.getOrCreate(Standing.TAG)
    end
    if type(state) ~= "table" then return nil, "mod_data_unavailable" end
    if state.schema == nil then state.schema, state.players, Standing.dirty = Standing.SCHEMA, {}, true end
    if state.schema ~= Standing.SCHEMA then return nil, "standing_schema_unsupported" end
    if type(state.players) ~= "table" then return nil, "standing_store_invalid" end
    Standing.storage = state
    return state
end

function Standing.forgetPlayer(key)
    if type(key) ~= "string" or key == "" then return false end
    local state = Standing.store()
    if state == nil or state.players[key] == nil then return false end
    state.players[key], Standing.dirty = nil, true
    return true
end

function Standing.row(key, faction, create)
    if type(key) ~= "string" or key == "" or #key > 160
            or type(faction) ~= "string" or faction == "" or #faction > 160 then return nil, "deed_identity_invalid" end
    local state, why = Standing.store()
    if state == nil then return nil, why end
    local rows = state.players[key]
    if rows == nil and create then rows = {}; state.players[key], Standing.dirty = rows, true end
    if type(rows) ~= "table" then return nil end
    local row = rows[faction]
    if row == nil and create then
        local now = Standing.hours()
        row = { score = 0, hours = now, day = math.floor(now / 24), gain = 0, counted = {} }
        rows[faction], Standing.dirty = row, true
    end
    return type(row) == "table" and row or nil
end

function Standing.decay(row)
    local now = Standing.hours()
    local score = math.max(-100, math.min(100, tonumber(row.score) or 0))
    local elapsed = math.max(0, now - (tonumber(row.hours) or now)) / 24
    local speed = score < 0 and 1.5 or 1
    if score <= -80 then speed = speed * 0.5 end
    local drift = elapsed * speed * Standing.settings.decayPercent / 100
    local changed = score < 0 and math.min(0, score + drift) or math.max(0, score - drift)
    if row.score ~= changed or now > (tonumber(row.hours) or -math.huge) then
        row.score, row.hours, Standing.dirty = changed, math.max(now, tonumber(row.hours) or now), true
    end
    return changed
end

function Standing.score(key, faction)
    local row = Standing.row(key, faction, false)
    return row ~= nil and Standing.decay(row) or 0
end

function Standing.tierFor(key, faction)
    local row = Standing.row(key, faction, false)
    if row == nil then return nil end
    local score = Standing.decay(row)
    local reputation = ProjectALife.Reputation
    local baseline, blood
    if reputation ~= nil and type(reputation.baselineFor) == "function" then baseline = reputation.baselineFor(key, faction) end
    if reputation ~= nil and type(reputation.recordedStatus) == "function" then blood = reputation.recordedStatus(key, faction) end
    local anchors = { hostile = -60, careful = -30, neutral = 0, friendly = 35, allied = 75 }
    score = score + (anchors[baseline] or 0)
    if baseline == "hostile" then score = math.min(-15, score) end
    if baseline == "allied" then score = math.max(0, score) end
    if blood == "hostile" then score = math.min(-45, score) end
    if score <= -80 then return "hated" end
    if score < -44 then return "hostile" end
    if score < -14 then return "careful" end
    if score < 20 then return "neutral" end
    if score < 60 then return "friendly" end
    return "allied"
end

Standing.doorDeeds = { treated_wounded = 8, sheltered_chased = 10, neighbour_watch = 5, finished_job = 15, answered_call = 10 }

function Standing.onDeed(kind, key, faction, uid, token)
    if not Standing.authoritative() then return false, "client_authority" end
    if not Standing.enabledHere() then return false, "standing_disabled" end
    local delta = Standing.doorDeeds[kind] or kind == "let_sleep" and 5 or kind == "gave_food" and 3
        or (kind == "fair_trade" or kind == "census_answer") and 2 or nil
    if delta == nil then return false, "standing_deed_unsupported" end
    if type(token) ~= "string" or token == "" or #token > 160 then return false, "deed_token_invalid" end
    local row, why = Standing.row(key, faction, true)
    if row == nil then return false, why or "standing_row_unavailable" end
    if row.counted ~= nil and type(row.counted) ~= "table" then return false, "deed_ledger_invalid" end
    row.counted = row.counted or {}
    for _, counted in ipairs(row.counted) do if counted == token then return false, "deed_replayed" end end
    if #row.counted >= Standing.settings.countedCap then return false, "deed_ledger_full" end
    local day = math.floor(Standing.hours() / 24)
    if kind == "fair_trade" and row.tradeDay == day then return false, "trade_counted_today" end
    Standing.decay(row)
    if row.day ~= day then row.day, row.gain = day, 0 end
    local gain = math.max(0, math.min(delta, Standing.settings.gainCapPerDay - (tonumber(row.gain) or 0), 100 - row.score))
    table.insert(row.counted, token)
    if kind == "fair_trade" then row.tradeDay = day end
    row.score, row.gain, row.cause, row.uid = row.score + gain, (tonumber(row.gain) or 0) + gain, kind, uid
    Standing.dirty = true
    return true, gain == 0 and "daily_gain_capped" or "deed_counted"
end

function Standing.flush()
    if not Standing.dirty or not Standing.authoritative() then return false end
    if type(Standing.adapters.save) == "function" then
        local ok = Standing.adapters.save(Standing.TAG, Standing.storage)
        if ok == false then return false end
    end
    Standing.dirty = false
    return true
end

return Standing
