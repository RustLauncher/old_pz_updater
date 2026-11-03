require "ProjectALife/Visitors/ALifeVisitorTalk"

ProjectALife = ProjectALife or {}

local Talk = ProjectALife.VisitorTalk

local Actions = {
    adapters = {},
    map = {},
    logged = {},
    settings = { sounds = false },
    metrics = { ran = 0, ok = 0, refused = 0, deferred = 0, unknown = 0, lastWhy = "-" },
}
ProjectALife.VisitorActions = Actions

Actions.DEFERRED = { "open_picker", "give_item", "take_item", "ask_leave", "stay_extend", "treat_flow", "search_flow", "rumor",
    "gift_back" }
Actions.LIFE_KINDS = { wash = "wash", rest = "rest", walk = "walk", read = "read", look = "look", sit = "sit", pace = "pace",
    follow = "follow" }

function Actions.log(text)
    if type(Actions.adapters.log) == "function" then return Actions.adapters.log(text) end
    if type(print) == "function" then print(text) end
end

function Actions.finish(verb, ok, why)
    local m = Actions.metrics
    m.ran = m.ran + 1
    if ok == true then
        m.ok = m.ok + 1
        return true
    end
    m.refused = m.refused + 1
    m.lastWhy = tostring(verb) .. ":" .. tostring(why)
    return false, why
end

function Actions.defer(verb)
    return function(ctx, arg)
        local m = Actions.metrics
        m.ran, m.deferred = m.ran + 1, m.deferred + 1
        m.lastWhy = verb .. ":deferred"
        if not Actions.logged[verb] then
            Actions.logged[verb] = true
            Actions.log("[ALIFE-QA] VisitorActions: " .. verb .. " is not wired yet, skipped")
        end
        return false, "deferred"
    end
end

function Actions.life()
    local life = ProjectALife.VisitorLife
    if life == nil or type(life.intent) ~= "function" or type(life.context) ~= "function" then return nil end
    return life
end

function Actions.base(ctx)
    local life = Actions.life()
    if life == nil then return nil, "life_missing" end
    local record = ctx.record or Talk.recordOf(ctx.uid)
    if record == nil then return nil, "not_visitor" end
    local house = life.houseOf(record)
    if house == nil then return nil, "no_house" end
    local cache = life.cacheOf(house)
    if cache == nil or cache.done ~= true then return nil, "scan_pending" end
    return { life = life, record = record, house = house, cache = cache }
end

function Actions.lifeIntent(ctx, kind)
    local base, why = Actions.base(ctx)
    if base == nil then return false, why end
    local life = base.life
    local nowMs = life.nowMs() or 0
    local mem = life.stateOf(ctx.uid, nowMs)
    local visitor = { uid = ctx.uid, record = base.record, house = base.house }
    local lifeCtx = life.context(visitor, mem, nowMs, life.options(), base.cache)
    local picked, poi = life.pickPoi(lifeCtx, kind)
    if not picked then return false, "no_poi" end
    life.release(ctx.uid)
    return life.intent(ctx.uid, kind, poi, nil, nil)
end

function Actions.device(ctx, kind)
    local base, why = Actions.base(ctx)
    if base == nil then return false, why end
    local life = base.life
    local list = base.cache.by[kind]
    if type(list) ~= "table" or #list == 0 then return false, "no_" .. kind end
    local poi = list[1]
    local here = life.position(base.record)
    if here ~= nil then poi = life.nearest(list, here.x, here.y, here.z) or poi end
    life.release(ctx.uid)
    return life.intent(ctx.uid, kind, poi, nil, { k = "device_on", poi = life.clean(poi) })
end

function Actions.approach(uid, record)
    return Actions.lifeIntent({ uid = uid, record = record }, "follow")
end

function Actions.map.tv_on(ctx, arg)
    local ok, why = Actions.device(ctx, "tv")
    return Actions.finish("tv_on", ok, why)
end

function Actions.map.radio_on(ctx, arg)
    local ok, why = Actions.device(ctx, "radio")
    return Actions.finish("radio_on", ok, why)
end

function Actions.map.life(ctx, arg)
    local word = string.match(tostring(arg or ""), "^(%a+)")
    local kind = word ~= nil and Actions.LIFE_KINDS[word] or nil
    if kind == nil then return Actions.finish("life", false, "intent_unknown") end
    local ok, why = Actions.lifeIntent(ctx, kind)
    return Actions.finish("life", ok, why)
end

function Actions.map.window_look(ctx, arg)
    local ok, why = Actions.lifeIntent(ctx, "look")
    return Actions.finish("window_look", ok, why)
end

function Actions.map.privacy_begin(ctx, arg)
    local life = Actions.life()
    if life == nil or type(life.beginChange) ~= "function" then return Actions.finish("privacy_begin", false, "life_missing") end
    local ok, why = life.beginChange(ctx.uid, {})
    return Actions.finish("privacy_begin", ok == true, why)
end

function Actions.map.set(ctx, arg)
    local record = ctx.record or Talk.recordOf(ctx.uid)
    if record == nil or ctx.player == nil then return Actions.finish("set", false, "not_visitor") end
    local env = Talk.env(ctx.player, record, nil, nil, nil)
    if env.key == nil or env.person == nil then return Actions.finish("set", false, "no_player_key") end
    local plan = Talk.newPlan(env)
    Talk.fx.set(env, plan, tostring(arg or ""))
    local ok, why = Talk.commit(env, plan)
    return Actions.finish("set", ok == true, why)
end

function Actions.map.gset(ctx, arg)
    local name = string.match(tostring(arg or ""), "^gflag:([%w_]+)$")
    if name == nil then return Actions.finish("gset", false, "flag_invalid") end
    Talk.gflags({ name })
    return Actions.finish("gset", true, nil)
end

function Actions.map.sound(ctx, arg)
    local id = string.match(tostring(arg or ""), "^([%w_]+)$")
    if id == nil then return Actions.finish("sound", false, "sound_invalid") end
    if Actions.settings.sounds ~= true then return Actions.finish("sound", false, "silent") end
    local shell = Talk.shellOf(ctx.uid)
    if shell == nil or type(shell.playSound) ~= "function" then return Actions.finish("sound", false, "no_body") end
    shell:playSound(id)
    return Actions.finish("sound", true, nil)
end

for _, verb in ipairs(Actions.DEFERRED) do Actions.map[verb] = Actions.defer(verb) end

function Actions.run(ctx, text)
    local verb, arg = string.match(tostring(text or ""), "^([%w_]+)%s*(.-)$")
    local handler = verb ~= nil and Actions.map[verb] or nil
    if handler == nil then
        Actions.metrics.unknown = Actions.metrics.unknown + 1
        Actions.metrics.lastWhy = tostring(verb) .. ":unknown"
        return false, "unknown_action"
    end
    return handler(ctx, arg)
end

function Actions.reset()
    Actions.logged = {}
    for key, value in pairs(Actions.metrics) do Actions.metrics[key] = type(value) == "number" and 0 or "-" end
end

return Actions
