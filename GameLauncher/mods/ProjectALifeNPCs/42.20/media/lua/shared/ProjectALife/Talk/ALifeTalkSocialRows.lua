ProjectALife = ProjectALife or {}

local Rows = {
    cats = {},
    static = {},
    contextual = { ASK_OKAY = true, OFFER_HELP = true, ENCOURAGE = true, THANKS = true, SORRY = true, FAREWELL = true },
    tier = { greet = 1, smalltalk = 1, info = 1, kind = 1, offer = 1, personal = 2, request = 2, probe = 3, threat = 3,
        farewell = 3 },
    exempt = { answer = true, system = true, order = true },
}
ProjectALife.TalkSocialRows = Rows

function Rows.put(category, ids)
    for id in string.gmatch(ids, "%S+") do Rows.cats[id] = category end
end

function Rows.mark(ids)
    for id in string.gmatch(ids, "%S+") do Rows.static[id] = true end
end

Rows.put("system", "NPC_OPEN WALK_STOP ASK_WHY_HOSTILE SURRENDER DONT_SHOOT BRIBE")
Rows.put("answer", "YES NO MAYBE REPEAT OK_ACK")
Rows.put("greet", "GREETING")
Rows.put("farewell", "FAREWELL")
Rows.put("smalltalk", "HOW_ARE_YOU SMALL_TALK TELL_JOKE LAUGH ASK_SING ASK_FAVORITE_FOOD ASK_SPORTS ASK_MUSIC ASK_PRESIDENT "
    .. "ASK_WEATHER ASK_TIME ASK_DATE ASK_COLD_FEEL ASK_GOT_COLD ASK_STAY_WARM ASK_REMEDY ASK_WINTER ASK_SEASON ASK_SNOW "
    .. "ASK_HEAT ASK_WARM_PLACE ASK_HARVEST COMPLIMENT TELL_STORY ASK_SLEEP ASK_REAL ASK_GOD ASK_HOPE")
Rows.put("personal", "ASK_JOB_BEFORE ASK_FAMILY ASK_KIDS ASK_PETS ASK_AGE ASK_HOMETOWN ASK_HOW_SURVIVED ASK_HOW_LONG ASK_SCARED "
    .. "ASK_MISS ASK_BEFORE ASK_ORIGIN_TODAY")
Rows.put("probe", "ASK_GROUP ASK_LEADER ASK_HOW_MANY ASK_BASE ASK_HOME ASK_BITTEN ASK_WILL_ROB ASK_PLANS FLIRT")
Rows.put("request", "ASK_FOOD ASK_WATER ASK_MEDS ASK_AMMO ASK_WEAPON ASK_SMOKE ASK_DRINK ASK_CAR_FUEL ASK_TRADE JOIN_REQUEST "
    .. "WALK_WITH_ME COME_WITH_ME FOLLOW_ME WAIT_HERE ASK_HELP ASK_ALONE_NIGHT ASK_LOCKED_DOOR BEG GIVE_BACK")
Rows.put("offer", "OFFER_ITEM OFFER_HELP ASK_NEED")
Rows.put("kind", "THANKS SORRY ENCOURAGE ASK_OKAY CALM_DOWN I_AM_FRIENDLY NEGOTIATE WARN_ZOMBIES WARN_DANGER")
Rows.put("threat", "INSULT THREATEN GO_AWAY")
Rows.put("order", "HANDS_UP DROP_WEAPON STOP_FREEZE DEMAND_ITEMS LOWER_WEAPON ORDER_HANDS_UP ORDER_DROP_WEAPON ORDER_SURRENDER "
    .. "ORDER_ROB ORDER_GET_OUT ORDER_LEAVE_AREA ORDER_FOLLOW FRISK_WEAPONS FRISK_ITEMS ORDER_AT_EASE PRO_LAW PRO_MEDIC "
    .. "PRO_MILITARY PRO_TRADE ASK_ORDERS ASK_TOLL ASK_SHELTER PARTY_JOIN PARTY_LEAVE PARTY_TASK_ASK PARTY_TASK_REMIND "
    .. "PARTY_TASK_DONE PARTY_STORY")
Rows.mark("ASK_NAME TELL_NAME WHO_ARE_YOU ASK_GROUP ASK_LEADER ASK_HOW_MANY ASK_BASE ASK_HOME ASK_HOMETOWN ASK_JOB_BEFORE "
    .. "ASK_FAMILY ASK_KIDS ASK_PETS ASK_AGE ASK_HOW_SURVIVED ASK_HOW_LONG ASK_SCARED ASK_MISS ASK_BEFORE ASK_ORIGIN_TODAY")

function Rows.category(intent)
    local id = tostring(intent or "")
    local cat = Rows.cats[id]
    if cat ~= nil then return cat end
    if string.sub(id, 1, 4) == "ENC_" or string.sub(id, 1, 5) == "DOOR_" or string.sub(id, 1, 6) == "PLAYER" then return "system" end
    return "info"
end

function Rows.exemptIntent(intent)
    return Rows.exempt[Rows.category(intent)] == true
end

function Rows.windowKind(intent)
    if Rows.static[tostring(intent or "")] == true then return "S" end
    return "D"
end

function Rows.risky(id, stance, social)
    local cat = Rows.category(id)
    if cat == "probe" then return stance ~= "friendly" end
    if cat == "request" then return stance == "careful" end
    if cat == "personal" then return type(social) == "table" and social.fam ~= true end
    return false
end

function Rows.arrange(choices, view)
    local social = type(view) == "table" and view.social or nil
    if type(social) ~= "table" or social.on ~= true or social.focus == false or type(choices) ~= "table" then return choices, nil end
    if view.pending ~= nil then return choices, nil end
    local present = {}
    for _, choice in ipairs(choices) do present[choice.id] = true end
    local asked = type(social.asked) == "table" and social.asked or {}
    local ctx = type(social.ctx) == "table" and social.ctx or {}
    local rank = {}
    for index, id in ipairs(type(social.sug) == "table" and social.sug or {}) do rank[id] = index end
    local listed, marks = {}, {}
    for index, choice in ipairs(choices) do
        local id = choice.id
        local cat = Rows.category(id)
        local drop = false
        if id == "WALK_STOP" and social.walk ~= true then drop = true
        elseif id == "JOIN_REQUEST" and present.PARTY_JOIN == true then drop = true
        elseif cat == "personal" and social.fam ~= true then drop = true
        elseif Rows.contextual[id] == true and ctx[id] ~= true then drop = true end
        if not drop then
            local tier = Rows.tier[cat] or 2
            if asked[id] == true then tier = 4 elseif rank[id] ~= nil then tier = 0 end
            listed[#listed + 1] = { choice = choice, tier = tier, rank = rank[id] or 0, index = index }
            local mark = {}
            if rank[id] ~= nil and asked[id] ~= true then mark.sug = true end
            if asked[id] == true then mark.asked = true end
            if Rows.risky(id, view.stance, social) then mark.risky = true end
            if mark.sug or mark.asked or mark.risky then marks[id] = mark end
        end
    end
    table.sort(listed, function(a, b)
        if a.tier ~= b.tier then return a.tier < b.tier end
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.index < b.index
    end)
    local out = {}
    for _, entry in ipairs(listed) do out[#out + 1] = entry.choice end
    return out, marks
end

return Rows
