ProjectALife = ProjectALife or {}

local Plan = {
    metrics = { built = 0, refused = 0, previews = 0, sent = 0, accepted = 0, failed = 0, undone = 0 },
    sequence = 0,
}
ProjectALife.SpawnPlan = Plan

Plan.KINDS = {
    { id = "squad", label = "Faction squad", tip = "A squad drawn from one faction's members. The server picks the members unless you fix the roster." },
    { id = "member", label = "Single member", tip = "One chosen member, copied as many times as the count says." },
    { id = "roster", label = "Custom roster", tip = "Up to eight chosen members, exactly as listed." },
    { id = "encounter", label = "Encounter", tip = "A ready-made encounter such as a patrol, checkpoint or camp, cast from a faction." },
    { id = "outpost", label = "Staffed outpost", tip = "Builds an outpost preset on the spot and staffs it. The build is sliced over several seconds." },
    { id = "visitor", label = "Base visitor", tip = "Forces a base visit or safehouse event for your test base, using the safehouse director." },
    { id = "raid", label = "Raid", tip = "Starts a forced full-scale raid with waves against you." },
    { id = "support", label = "Support call", tip = "Makes the NPC nearest to you call for reinforcements." },
}

Plan.STANCES = {
    { id = "profile", label = "Use faction", tip = "Each member keeps the stance its faction gives toward players." },
    { id = "friendly", label = "Friendly", tip = "Ally: helps you and does not attack." },
    { id = "neutral", label = "Neutral", tip = "Leaves you alone and defends itself." },
    { id = "careful", label = "Careful", tip = "Warns first, then shoots if you stay or come closer." },
    { id = "hostile", label = "Hostile", tip = "Attacks on sight." },
}

Plan.MODES = {
    { id = "roam", label = "Roam", tip = "Moves through the area and attacks threats it detects." },
    { id = "patrol", label = "Patrol", tip = "Circulates around the spawn point and returns to its route." },
    { id = "scavenge", label = "Scavenge", tip = "Searches nearby containers and collects supplies." },
    { id = "hunt", label = "Hunt", tip = "Actively searches the local area for targets." },
    { id = "manhunt", label = "Manhunt", tip = "Tracks the requesting player and keeps re-engaging." },
    { id = "guard", label = "Guard", tip = "Treats the spawn point as home and defends its radius." },
    { id = "camp", label = "Camp", tip = "Builds a campsite and lives there." },
    { id = "blockade", label = "Blockade", tip = "Cars across the road with a line of guns behind them." },
    { id = "assault", label = "Assault", tip = "Advances on nearby players as an attacking group." },
}

Plan.WHERE = {
    { id = "player", label = "Near me", tip = "At your position, or at a distance and heading from you." },
    { id = "target", label = "Clicked target", tip = "At the square you chose with the right-click entry Use as A-Life spawn target." },
    { id = "coords", label = "Coordinates", tip = "At an exact X, Y, Z." },
    { id = "marker", label = "Marker", tip = "At a live encounter, squad or outpost marker." },
    { id = "rule", label = "Encounter rule", tip = "Where the encounter's own placement rule puts it, near you." },
}

Plan.HEADINGS = {
    { id = "ahead", label = "Ahead of me" },
    { id = "N", label = "North" }, { id = "NE", label = "North-east" },
    { id = "E", label = "East" }, { id = "SE", label = "South-east" },
    { id = "S", label = "South" }, { id = "SW", label = "South-west" },
    { id = "W", label = "West" }, { id = "NW", label = "North-west" },
}

Plan.COMPASS = {
    N = { 0, -1 }, NE = { 0.70710678, -0.70710678 }, E = { 1, 0 }, SE = { 0.70710678, 0.70710678 },
    S = { 0, 1 }, SW = { -0.70710678, 0.70710678 }, W = { -1, 0 }, NW = { -0.70710678, -0.70710678 },
}

Plan.RADIANS = {
    N = 0, NE = 0.7853981634, E = 1.5707963268, SE = 2.3561944902,
    S = 3.1415926536, SW = 3.9269908170, W = 4.7123889804, NW = 5.4977871438,
}

Plan.LIMITS = { count = 8, raidCount = 12, distance = 80, delay = 600, serverDelay = 30, roster = 8,
    coordinate = 10000000, history = 40, presets = 24, presetName = 32 }

Plan.ADVANCED = {
    { key = "doctrine", label = "Behaviour doctrine", kind = "choice", group = "AI",
      tip = "Overrides how the group coordinates. Use profile keeps each member's saved behaviour.",
      choices = { { "Use profile", "profile" }, { "Individual AI", "individual" },
          { "Fireteam coordination", "fireteam" }, { "CQB entry team", "cqb" } } },
    { key = "role", label = "Specialist role", kind = "choice", group = "AI",
      tip = "Gives the first member a specialist role.",
      choices = { { "Use profile", "profile" }, { "Generalist", "none" }, { "Team leader", "leader" },
          { "Medic", "medic" }, { "Marksman", "sniper" }, { "Gunner / suppression", "gunner" } } },
    { key = "invulnerable", label = "Invulnerable", kind = "bool", group = "AI",
      tip = "Members take no damage. Cheat-like: for testing only." },
    { key = "stationary", label = "Position locked", kind = "bool", group = "AI",
      tip = "Members stand still and only turn and shoot." },
    { key = "persistent", label = "Save squad", kind = "choice", group = "AI",
      tip = "Keeps the squad across save and load, within the persistent squad limit.",
      choices = { { "Use profile", "profile" }, { "Yes", "true" }, { "No", "false" } } },
    { key = "facing", label = "Facing / line heading", kind = "choice", group = "Placement",
      tip = "The direction a formation, camp or blockade faces.",
      choices = { { "Automatic", "auto" }, { "North", "N" }, { "North-east", "NE" }, { "East", "E" },
          { "South-east", "SE" }, { "South", "S" }, { "South-west", "SW" }, { "West", "W" }, { "North-west", "NW" } } },
    { key = "separation", label = "Unit spacing", kind = "number", min = 1, max = 8, group = "Placement",
      tip = "Tiles between members when they appear." },
    { key = "radius", label = "Behaviour radius", kind = "number", min = 6, max = 80, group = "Placement",
      tip = "Patrol, guard and camp radius in tiles." },
    { key = "arrival", label = "How they arrive", kind = "choice", group = "Placement",
      tip = "Foot: just appear. Helicopter and car add an arrival delay and effect.",
      choices = { { "Just appear", "foot" }, { "Helicopter and rope", "heli" }, { "By car", "ground" } } },
    { key = "animation", label = "Arrival animation", kind = "choice", group = "Placement",
      tip = "The animation preset applied when the body appears.",
      choices = { { "Normal", "normal" } } },
    { key = "awareness", label = "Detection range", kind = "number", min = 2, max = 90, group = "Combat",
      tip = "How far members notice targets, in tiles." },
    { key = "leash", label = "Movement leash", kind = "number", min = 1, max = 100, group = "Combat",
      tip = "Members return when they wander farther than this from the spawn point." },
    { key = "health", label = "Exact HP", kind = "number", min = 1, max = 400, group = "Combat",
      tip = "Sets every member's health points." },
    { key = "damageReduction", label = "Damage reduction %", kind = "number", min = 0, max = 90, group = "Combat",
      tip = "Percent of incoming damage ignored." },
    { key = "damageOutput", label = "Damage output %", kind = "number", min = 1, max = 500, group = "Combat",
      tip = "Percent of the weapon's normal damage dealt." },
    { key = "weaponChance", label = "Weapon drop chance", kind = "drop", group = "Loot",
      tip = "Chance that the carried weapon drops on death." },
    { key = "weaponCondition", label = "Weapon condition", kind = "drop", group = "Loot",
      tip = "Condition of the dropped weapon." },
    { key = "clothingCondition", label = "Clothing condition", kind = "drop", group = "Loot",
      tip = "Condition of the dropped clothing." },
    { key = "canCallSupport", label = "Can call support", kind = "choice", group = "Support",
      tip = "Allows or forbids the squad to radio for backup.",
      choices = { { "Use profile", "profile" }, { "Yes", "true" }, { "No", "false" } } },
    { key = "supportPolicy", label = "Who may call", kind = "choice", group = "Support",
      tip = "Which member may place the call.",
      choices = { { "Use profile", "profile" }, { "Any squad member", "any" }, { "Radio operators only", "radio" },
          { "Nobody", "disabled" } } },
    { key = "supportType", label = "Allowed support", kind = "choice", group = "Support",
      tip = "Ground reinforcements, a helicopter or both.",
      choices = { { "Use profile", "profile" }, { "Ground + helicopter", "both" }, { "Ground", "ground" },
          { "Helicopter only", "heli" }, { "None", "none" } } },
    { key = "heli", label = "Helicopter", kind = "choice", group = "Support",
      tip = "Helicopter support mode for this squad.",
      choices = { { "Use profile", "profile" }, { "No helicopter", "none" }, { "Spotlight only", "spotlight" },
          { "Helicopter support", "support" } } },
    { key = "supportSize", label = "Support squad size", kind = "number", min = 1, max = 8, group = "Support",
      tip = "Members in the reinforcement squad." },
    { key = "supportMaxCalls", label = "Support calls (max)", kind = "number", min = 0, max = 10, group = "Support",
      tip = "How many calls the squad may place." },
    { key = "supportCooldownHours", label = "Support cooldown (h)", kind = "number", min = 0, max = 168, group = "Support",
      tip = "Game hours between calls." },
    { key = "waves", label = "Raid waves", kind = "number", min = 1, max = 12, group = "Raid",
      tip = "Number of attack waves of a forced raid." },
    { key = "waveDelayMinutes", label = "Game minutes per wave", kind = "number", min = 1, max = 60, group = "Raid",
      tip = "Game minutes between raid waves." },
    { key = "raidHeli", label = "Raid helicopter", kind = "choice", group = "Raid",
      tip = "Whether the raid arrives with a helicopter.",
      choices = { { "Use setting", "profile" }, { "Yes", "true" }, { "No", "false" } } },
}

Plan.ADVANCED_INDEX = {}
for _, row in ipairs(Plan.ADVANCED) do Plan.ADVANCED_INDEX[row.key] = row end

Plan.REFUSALS = {
    spawn_kind_invalid = "That spawn type is not known.",
    spawn_faction_required = "Pick a faction first.",
    spawn_member_required = "Pick a member first.",
    spawn_member_unknown = "That member is not in the catalog.",
    spawn_roster_empty = "The custom roster is empty. Add members to it.",
    spawn_encounter_required = "Pick an encounter first.",
    spawn_preset_required = "Pick an outpost preset first.",
    spawn_event_required = "Pick a visit type first.",
    spawn_target_missing = "No clicked target yet. Use the right-click entry Use as A-Life spawn target.",
    spawn_coordinates_invalid = "The coordinates are not valid numbers.",
    spawn_marker_missing = "That marker is gone. Refresh the marker list.",
    spawn_rule_needs_encounter = "Encounter rule placement only works with an encounter.",
    spawn_gate_closed = "The funnel or day window does not allow that faction right now.",
    spawn_dormant_unsupported = "This spawn type cannot be created dormant.",
    spawn_delay_invalid = "The delay is not a valid number of seconds.",
    spawn_history_full = "Too many batches are tracked. Undo or clear old ones.",
    undo_unknown_batch = "The server does not know that batch any more.",
    undo_nothing = "That batch has nothing left to remove.",
    undo_pending = "The batch is still spawning. It will be removed when it finishes.",
    faction_unknown = "That faction is not in the catalog.",
    outposts_unavailable = "The outpost systems are not loaded on this server.",
    preset_unknown = "That outpost preset is not known.",
    building_required = "This preset needs a building: right-click one and use it as the spawn target.",
    building_unreadable = "The building at that spot could not be read.",
    site_create_failed = "The outpost site could not be registered.",
    sheet_failed = "The outpost layout could not be resolved at that spot.",
    hostile_faction_not_found = "No hostile faction is available to staff the outpost.",
    safehouse_unavailable = "The safehouse director is not running.",
    support_unavailable = "The support system is not running.",
    no_living_actor = "No active NPC exists to place the call.",
    funnel_unavailable = "The funnel settings are not loaded.",
    unknown_encounter = "That encounter id is not known to the server.",
    admin_command_failed = "The server command failed. See the server log.",
    funnel_stage_invalid = "Funnel stages run from 0 to 7.",
    reputation_unavailable = "Reputation is not available on the server.",
    admin_required = "Admin access is required.",
    diagnostics_disabled = "Debug tools are switched off. Tick Diagnostics in Options.",
    rate_limited = "Too many requests. Wait a moment.",
}

function Plan.refusalText(reason)
    reason = tostring(reason or "unknown")
    local own = Plan.REFUSALS[reason]
    if own ~= nil then return own end
    local gate = string.match(reason, "^faction_out_of_window:(.+)$")
    if gate ~= nil then return "The faction " .. gate .. " is outside its day window. Tick Ignore gating to spawn it anyway." end
    local deleted = string.match(reason, "^faction_deleted:(.+)$")
    if deleted ~= nil then return "The faction " .. deleted .. " was deleted in the Creator." end
    local encounters = ProjectALife.Encounters
    if encounters ~= nil and type(encounters.refusalText) == "function" then
        local text = encounters.refusalText(reason)
        if text ~= nil and text ~= reason then return text end
    end
    return reason
end

function Plan.nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function Plan.finite(value)
    local number = tonumber(value)
    return number ~= nil and number == number and number > -Plan.LIMITS.coordinate
        and number < Plan.LIMITS.coordinate
end

function Plan.clamp(value, low, high, fallback)
    local number = tonumber(value)
    if number == nil or number ~= number then number = fallback end
    if number == nil then return nil end
    return math.max(low, math.min(high, number))
end

function Plan.defaultSpec()
    return {
        kind = "squad",
        factionId = nil, memberId = nil, roster = {}, encounterId = nil, presetId = nil, event = nil,
        count = 3, stance = "profile", mode = "roam",
        where = "player", distance = 0, heading = "ahead",
        x = nil, y = nil, z = 0, markerId = nil,
        delaySec = 0, dormant = false, ignoreGates = true, seed = nil,
        adv = {},
    }
end

function Plan.copySpec(spec)
    local result = {}
    for key, value in pairs(type(spec) == "table" and spec or {}) do
        if key ~= "adv" and key ~= "roster" then result[key] = value end
    end
    result.adv, result.roster = {}, {}
    for key, value in pairs(type(spec) == "table" and type(spec.adv) == "table" and spec.adv or {}) do
        result.adv[key] = value
    end
    for _, entry in ipairs(type(spec) == "table" and type(spec.roster) == "table" and spec.roster or {}) do
        if type(entry) == "table" then
            result.roster[#result.roster + 1] = { id = entry.id, count = entry.count }
        end
    end
    return result
end

function Plan.indexOf(list, id)
    for position, row in ipairs(list) do
        if row.id == id then return position end
    end
    return nil
end

function Plan.normalize(spec)
    local result = Plan.copySpec(spec)
    local base = Plan.defaultSpec()
    for key, value in pairs(base) do
        if result[key] == nil and key ~= "factionId" and key ~= "memberId" and key ~= "encounterId"
                and key ~= "presetId" and key ~= "event" and key ~= "x" and key ~= "y"
                and key ~= "markerId" and key ~= "seed" then
            result[key] = value
        end
    end
    local corrections = {}
    if Plan.indexOf(Plan.KINDS, result.kind) == nil then result.kind = "squad"; corrections[#corrections + 1] = "kind" end
    if Plan.indexOf(Plan.STANCES, result.stance) == nil then result.stance = "profile"; corrections[#corrections + 1] = "stance" end
    if Plan.indexOf(Plan.MODES, result.mode) == nil then result.mode = "roam"; corrections[#corrections + 1] = "mode" end
    if Plan.indexOf(Plan.WHERE, result.where) == nil then result.where = "player"; corrections[#corrections + 1] = "where" end
    if Plan.indexOf(Plan.HEADINGS, result.heading) == nil then result.heading = "ahead"; corrections[#corrections + 1] = "heading" end
    local limit = result.kind == "raid" and Plan.LIMITS.raidCount or Plan.LIMITS.count
    local count = math.floor(Plan.clamp(result.count, 1, limit, 3))
    if count ~= result.count then corrections[#corrections + 1] = "count" end
    result.count = count
    local distance = math.floor(Plan.clamp(result.distance, 0, Plan.LIMITS.distance, 0))
    if distance ~= result.distance then corrections[#corrections + 1] = "distance" end
    result.distance = distance
    local delay = math.floor(Plan.clamp(result.delaySec, 0, Plan.LIMITS.delay, 0))
    if delay ~= result.delaySec then corrections[#corrections + 1] = "delaySec" end
    result.delaySec = delay
    result.dormant = result.dormant == true
    result.ignoreGates = result.ignoreGates ~= false
    if result.seed ~= nil then
        local seed = tonumber(result.seed)
        if seed == nil or seed ~= seed then result.seed = nil; corrections[#corrections + 1] = "seed"
        else result.seed = math.floor(seed) end
    end
    local roster = {}
    for _, entry in ipairs(result.roster) do
        if type(entry.id) == "string" and entry.id ~= "" and #roster < Plan.LIMITS.roster then
            roster[#roster + 1] = { id = entry.id, count = math.floor(Plan.clamp(entry.count, 1, Plan.LIMITS.roster, 1)) }
        end
    end
    result.roster = roster
    return result, corrections
end

function Plan.rosterIds(spec)
    local ids = {}
    for _, entry in ipairs(spec.roster or {}) do
        for _ = 1, entry.count or 1 do
            if #ids < Plan.LIMITS.roster then ids[#ids + 1] = entry.id end
        end
    end
    return ids
end

function Plan.validate(spec)
    local kind = spec.kind
    if kind == "squad" and (type(spec.factionId) ~= "string" or spec.factionId == "") then return false, "spawn_faction_required" end
    if kind == "member" and (type(spec.memberId) ~= "string" or spec.memberId == "") then return false, "spawn_member_required" end
    if kind == "roster" and #Plan.rosterIds(spec) == 0 then return false, "spawn_roster_empty" end
    if kind == "encounter" and (type(spec.encounterId) ~= "string" or spec.encounterId == "") then return false, "spawn_encounter_required" end
    if kind == "outpost" and (type(spec.presetId) ~= "string" or spec.presetId == "") then return false, "spawn_preset_required" end
    if kind == "visitor" and (type(spec.event) ~= "string" or spec.event == "") then return false, "spawn_event_required" end
    if spec.where == "rule" and kind ~= "encounter" then return false, "spawn_rule_needs_encounter" end
    if spec.dormant == true and (kind == "visitor" or kind == "support" or kind == "raid" or kind == "outpost") then
        return false, "spawn_dormant_unsupported"
    end
    if spec.where == "coords" and (not Plan.finite(spec.x) or not Plan.finite(spec.y) or not Plan.finite(spec.z)) then
        return false, "spawn_coordinates_invalid"
    end
    return true
end

function Plan.forwardOf(context)
    local origin = type(context) == "table" and context.origin or nil
    if type(origin) == "table" and Plan.finite(origin.fx) and Plan.finite(origin.fy) then
        local length = math.sqrt(origin.fx * origin.fx + origin.fy * origin.fy)
        if length > 0.001 then return origin.fx / length, origin.fy / length end
    end
    return 0, -1
end

function Plan.position(spec, context)
    context = type(context) == "table" and context or {}
    local where = spec.where
    if where == "rule" then return nil, nil end
    if where == "coords" then
        if not Plan.finite(spec.x) or not Plan.finite(spec.y) then return nil, "spawn_coordinates_invalid" end
        return { x = math.floor(tonumber(spec.x)), y = math.floor(tonumber(spec.y)), z = math.floor(tonumber(spec.z) or 0) }
    end
    if where == "target" then
        local target = context.target
        if type(target) ~= "table" or not Plan.finite(target.x) or not Plan.finite(target.y) then
            return nil, "spawn_target_missing"
        end
        return { x = math.floor(target.x), y = math.floor(target.y), z = math.floor(tonumber(target.z) or 0) }
    end
    if where == "marker" then
        local marker = type(context.markers) == "table" and context.markers[spec.markerId] or nil
        if type(marker) ~= "table" or not Plan.finite(marker.x) or not Plan.finite(marker.y) then
            return nil, "spawn_marker_missing"
        end
        return { x = math.floor(marker.x), y = math.floor(marker.y), z = math.floor(tonumber(marker.z) or 0) }
    end
    local origin = context.origin
    if spec.distance <= 0 or type(origin) ~= "table" or not Plan.finite(origin.x) or not Plan.finite(origin.y) then
        return nil, nil
    end
    local dx, dy
    local compass = Plan.COMPASS[spec.heading]
    if compass ~= nil then dx, dy = compass[1], compass[2]
    else dx, dy = Plan.forwardOf(context) end
    return {
        x = math.floor(origin.x) + math.floor(dx * spec.distance + 0.5),
        y = math.floor(origin.y) + math.floor(dy * spec.distance + 0.5),
        z = math.floor(tonumber(origin.z) or 0),
    }
end

function Plan.requestId(kind, playerNum, now)
    Plan.sequence = Plan.sequence + 1
    return tostring(kind or "spawn") .. ":" .. tostring(math.floor(tonumber(playerNum) or 0)) .. ":"
        .. string.format("%.0f", math.floor(tonumber(now) or Plan.nowMs())) .. ":" .. tostring(Plan.sequence)
end

function Plan.advancedArguments(spec, args)
    local adv = spec.adv or {}
    local function choice(key)
        local value = adv[key]
        if value == nil or value == "" or value == "profile" then return nil end
        return value
    end
    local function number(key)
        local row = Plan.ADVANCED_INDEX[key]
        if adv[key] == nil or adv[key] == "" or row == nil then return nil end
        return Plan.clamp(adv[key], row.min, row.max, nil)
    end
    args.profile = choice("doctrine")
    local role = choice("role")
    if role ~= nil and role ~= "none" then args.conducts = { role } end
    if adv.invulnerable == true then args.invulnerable = true end
    if adv.stationary == true then args.stationary = true end
    local persistent = choice("persistent")
    if persistent ~= nil then args.persistent = persistent == "true" end
    local facing = choice("facing")
    if facing ~= nil and facing ~= "auto" then args.heading = Plan.RADIANS[facing] end
    args.separation = number("separation")
    args.radius = number("radius")
    local arrival = choice("arrival")
    if arrival ~= nil and arrival ~= "foot" then args.arrival = arrival end
    local animation = choice("animation")
    if animation ~= nil and animation ~= "normal" then args.animation = animation end
    args.awareness = number("awareness")
    args.leashRadius = number("leash")
    args.health = number("health")
    args.damageReduction = number("damageReduction")
    args.damageOutput = number("damageOutput")
    args.weaponChance = choice("weaponChance")
    args.weaponCondition = choice("weaponCondition")
    args.clothingCondition = choice("clothingCondition")
    local canCall = choice("canCallSupport")
    if canCall == "false" then args.supportPolicy = "disabled" end
    if choice("supportPolicy") ~= nil and canCall ~= "false" then args.supportPolicy = choice("supportPolicy") end
    args.supportType = choice("supportType")
    args.supportHeli = choice("heli")
    args.supportSize = number("supportSize")
    args.supportMaxCalls = number("supportMaxCalls")
    args.supportCooldownHours = number("supportCooldownHours")
    args.waves = number("waves")
    args.waveDelayMinutes = number("waveDelayMinutes")
    local raidHeli = choice("raidHeli")
    if raidHeli ~= nil then args.raidHeli = raidHeli == "true" end
    return args
end

function Plan.stanceArguments(spec, args)
    local stance = spec.stance
    if stance == "profile" then return args end
    args.playerStance = stance
    if stance == "friendly" or stance == "hostile" then args.hostileOverride = stance end
    return args
end

function Plan.build(spec, context)
    context = type(context) == "table" and context or {}
    local normal = Plan.normalize(spec)
    local valid, why = Plan.validate(normal)
    if not valid then
        Plan.metrics.refused = Plan.metrics.refused + 1
        return { ok = false, reason = why, text = Plan.refusalText(why) }
    end
    local position, positionWhy = Plan.position(normal, context)
    if positionWhy ~= nil then
        Plan.metrics.refused = Plan.metrics.refused + 1
        return { ok = false, reason = positionWhy, text = Plan.refusalText(positionWhy) }
    end
    local kind = normal.kind
    local requestId = context.requestId or Plan.requestId(kind, context.playerNum, context.now)
    local args = { kind = kind, requestId = requestId }
    if position ~= nil then args.x, args.y, args.z = position.x, position.y, position.z end
    local expected = normal.count
    if kind == "squad" then
        args.factionId, args.count, args.mode = normal.factionId, normal.count, normal.mode
        if type(context.rosterIds) == "table" and #context.rosterIds > 0 then
            args.profileIds = context.rosterIds
            expected = #context.rosterIds
        end
    elseif kind == "member" then
        args.profileId, args.count, args.mode = normal.memberId, normal.count, normal.mode
        args.factionId = normal.factionId
    elseif kind == "roster" then
        args.profileIds = Plan.rosterIds(normal)
        args.count, args.mode = #args.profileIds, normal.mode
        expected = #args.profileIds
    elseif kind == "encounter" then
        args.encounterId, args.factionId, args.count = normal.encounterId, normal.factionId, normal.count
        args.placementMode = normal.where == "rule" and "rule" or "here"
        expected = tonumber(context.encounterSize) or normal.count
    elseif kind == "raid" then
        args.encounterId, args.factionId, args.count = "fullscale_raid", normal.factionId, normal.count
        args.placementMode = "here"
        if normal.distance > 0 then args.distance = normal.distance end
    elseif kind == "outpost" then
        args.presetId, args.factionId, args.count = normal.presetId, normal.factionId, normal.count
    elseif kind == "visitor" then
        args.event = normal.event
        if position ~= nil then args.at = { x = position.x, y = position.y, z = position.z } end
    end
    if kind == "squad" or kind == "member" or kind == "roster" or kind == "encounter" or kind == "outpost" or kind == "raid" then
        Plan.stanceArguments(normal, args)
        Plan.advancedArguments(normal, args)
        if kind == "raid" or kind == "encounter" then args.separation = args.separation end
    end
    if kind == "raid" then args.distance = normal.distance > 0 and normal.distance or nil end
    if normal.seed ~= nil then args.seed = normal.seed end
    if normal.dormant == true then args.dormant = true end
    if normal.ignoreGates ~= true then args.respectGates = true end
    if normal.delaySec > 0 then
        if normal.delaySec <= Plan.LIMITS.serverDelay then args.spawnDelayMs = normal.delaySec * 1000 end
    end
    Plan.metrics.built = Plan.metrics.built + 1
    return {
        ok = true, command = "adminSpawn", args = args, requestId = requestId, kind = kind,
        expected = expected, position = position, summary = Plan.summary(normal, position),
        clientDelayMs = normal.delaySec > Plan.LIMITS.serverDelay and normal.delaySec * 1000 or 0,
        undoable = kind == "squad" or kind == "member" or kind == "roster" or kind == "encounter"
            or kind == "outpost",
    }
end

function Plan.previewArguments(spec, context)
    local built = Plan.build(spec, context)
    if not built.ok then return built end
    local args = built.args
    args.requestId = tostring(args.requestId) .. ":preview"
    args.preview = true
    built.command = "adminSpawnPreview"
    return built
end

function Plan.summary(spec, position)
    local parts = {}
    local kind = spec.kind
    local label = Plan.KINDS[Plan.indexOf(Plan.KINDS, kind) or 1].label
    if kind == "squad" then parts[#parts + 1] = tostring(spec.count) .. " x " .. label .. " " .. tostring(spec.factionId)
    elseif kind == "member" then parts[#parts + 1] = tostring(spec.count) .. " x " .. tostring(spec.memberId)
    elseif kind == "roster" then parts[#parts + 1] = tostring(#Plan.rosterIds(spec)) .. " custom members"
    elseif kind == "encounter" then parts[#parts + 1] = "encounter " .. tostring(spec.encounterId)
    elseif kind == "outpost" then parts[#parts + 1] = "outpost " .. tostring(spec.presetId)
    elseif kind == "visitor" then parts[#parts + 1] = "visit " .. tostring(spec.event)
    elseif kind == "raid" then parts[#parts + 1] = "raid of " .. tostring(spec.count)
    else parts[#parts + 1] = label end
    if spec.stance ~= "profile" and (kind == "squad" or kind == "member" or kind == "roster" or kind == "encounter") then
        parts[#parts + 1] = spec.stance
    end
    if kind == "squad" or kind == "member" or kind == "roster" then parts[#parts + 1] = spec.mode end
    if position ~= nil then
        parts[#parts + 1] = "@" .. tostring(position.x) .. "," .. tostring(position.y)
    else
        parts[#parts + 1] = spec.where == "rule" and "by rule" or "at you"
    end
    if spec.dormant == true then parts[#parts + 1] = "dormant" end
    if spec.delaySec > 0 then parts[#parts + 1] = "in " .. tostring(spec.delaySec) .. "s" end
    return table.concat(parts, " ")
end

Plan.QUICK = {
    { id = "test_squad", label = "Test squad of 3", tip = "3 hostile military 30 tiles ahead, roaming.",
      prefer = { "alife_guard", "alife_guard_infantry", "alife_delta_detachment", "alife_guard_remnants" },
      make = function(spec)
          spec.kind, spec.count, spec.stance, spec.mode = "squad", 3, "hostile", "roam"
          spec.where, spec.distance, spec.heading = "player", 30, "ahead"
          spec.adv = {}
      end },
    { id = "medic", label = "Friendly medic here", tip = "One friendly medic at your position, patrolling.",
      prefer = { "alife_county_ems", "alife_paramedics_offduty", "alife_army_medical", "alife_hospital" },
      make = function(spec)
          spec.kind, spec.count, spec.stance, spec.mode = "squad", 1, "friendly", "patrol"
          spec.where, spec.distance, spec.heading = "player", 3, "ahead"
          spec.adv = { role = "medic" }
      end },
    { id = "raid", label = "Raid now", tip = "A forced full-scale raid on you.",
      make = function(spec)
          spec.kind, spec.count, spec.stance, spec.mode = "raid", 6, "hostile", "assault"
          spec.where, spec.distance = "player", 0
          spec.adv = {}
      end },
    { id = "visitor", label = "Visitor now", tip = "A base visitor at your test base.",
      make = function(spec, context)
          spec.kind, spec.where, spec.distance, spec.stance = "visitor", "player", 0, "profile"
          local events = type(context) == "table" and type(context.visitEvents) == "table" and context.visitEvents or {}
          spec.event = events[1] or "trader"
          spec.adv = {}
      end },
}

function Plan.quick(id, base, context)
    local row
    for _, candidate in ipairs(Plan.QUICK) do
        if candidate.id == id then row = candidate end
    end
    if row == nil then return nil, "preset_unknown" end
    local spec = Plan.normalize(base or Plan.defaultSpec())
    row.make(spec, context)
    if row.prefer ~= nil then
        local known = type(context) == "table" and type(context.factionIds) == "table" and context.factionIds or {}
        spec.factionId = nil
        for _, candidate in ipairs(row.prefer) do
            if known[candidate] == true then spec.factionId = candidate; break end
        end
    end
    return Plan.normalize(spec)
end

function Plan.escape(text)
    return (string.gsub(tostring(text), "[%%|=%s,*:]", function(char)
        return string.format("%%%02X", string.byte(char))
    end))
end

function Plan.unescape(text)
    return (string.gsub(tostring(text), "%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

Plan.SPEC_KEYS = { "kind", "factionId", "memberId", "encounterId", "presetId", "event", "count", "stance", "mode",
    "where", "distance", "heading", "x", "y", "z", "markerId", "delaySec", "dormant", "ignoreGates", "seed" }

function Plan.encodeSpec(spec)
    local parts = {}
    for _, key in ipairs(Plan.SPEC_KEYS) do
        local value = spec[key]
        if value ~= nil then
            parts[#parts + 1] = key .. "=" .. Plan.escape(tostring(value))
        end
    end
    local roster = {}
    for _, entry in ipairs(spec.roster or {}) do roster[#roster + 1] = Plan.escape(entry.id) .. "*" .. tostring(entry.count or 1) end
    if #roster > 0 then parts[#parts + 1] = "roster=" .. table.concat(roster, ",") end
    local advanced = {}
    for _, row in ipairs(Plan.ADVANCED) do
        local value = spec.adv ~= nil and spec.adv[row.key] or nil
        if value ~= nil and value ~= "" then advanced[#advanced + 1] = row.key .. ":" .. Plan.escape(tostring(value)) end
    end
    if #advanced > 0 then parts[#parts + 1] = "adv=" .. table.concat(advanced, ",") end
    return table.concat(parts, "|")
end

Plan.NUMERIC_KEYS = { count = true, distance = true, x = true, y = true, z = true, delaySec = true, seed = true }
Plan.BOOLEAN_KEYS = { dormant = true, ignoreGates = true }

function Plan.decodeSpec(text)
    local spec = Plan.defaultSpec()
    spec.ignoreGates = true
    for field in string.gmatch(tostring(text or "") .. "|", "([^|]*)|") do
        local key, value = string.match(field, "^([%w]+)=(.*)$")
        if key ~= nil then
            if key == "roster" then
                for item in string.gmatch(value .. ",", "([^,]*),") do
                    local id, count = string.match(item, "^(.-)%*(%d+)$")
                    if id ~= nil and id ~= "" then
                        spec.roster[#spec.roster + 1] = { id = Plan.unescape(id), count = tonumber(count) }
                    end
                end
            elseif key == "adv" then
                for item in string.gmatch(value .. ",", "([^,]*),") do
                    local name, raw = string.match(item, "^([%w]+):(.*)$")
                    if name ~= nil and Plan.ADVANCED_INDEX[name] ~= nil then
                        local row = Plan.ADVANCED_INDEX[name]
                        local decoded = Plan.unescape(raw)
                        if row.kind == "bool" then spec.adv[name] = decoded == "true"
                        elseif row.kind == "number" then spec.adv[name] = tonumber(decoded)
                        else spec.adv[name] = decoded end
                    end
                end
            else
                local known = false
                for _, name in ipairs(Plan.SPEC_KEYS) do
                    if name == key then known = true end
                end
                if known then
                    local decoded = Plan.unescape(value)
                    if Plan.NUMERIC_KEYS[key] then spec[key] = tonumber(decoded)
                    elseif Plan.BOOLEAN_KEYS[key] then spec[key] = decoded == "true"
                    else spec[key] = decoded end
                end
            end
        end
    end
    return Plan.normalize(spec)
end

function Plan.cleanPresetName(name)
    local text = string.gsub(tostring(name or ""), "[%c|=%%]", "")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return string.sub(text, 1, Plan.LIMITS.presetName)
end

function Plan.encodeStore(map, order)
    local lines = {}
    for _, name in ipairs(order or {}) do
        local spec = map[name]
        if spec ~= nil then lines[#lines + 1] = "preset " .. Plan.escape(name) .. " " .. Plan.encodeSpec(spec) end
    end
    return table.concat(lines, "\n")
end

function Plan.decodeStore(text)
    local map, order = {}, {}
    for line in string.gmatch(tostring(text or "") .. "\n", "([^\n]*)\n") do
        local name, body = string.match(line, "^preset ([^ ]+) (.*)$")
        if name ~= nil and #order < Plan.LIMITS.presets then
            name = Plan.cleanPresetName(Plan.unescape(name))
            if name ~= "" and map[name] == nil then
                map[name] = Plan.decodeSpec(body)
                order[#order + 1] = name
            end
        end
    end
    return map, order
end

function Plan.newHistory(cap)
    return { cap = math.floor(tonumber(cap) or Plan.LIMITS.history), entries = {}, byRequest = {} }
end

function Plan.historyAdd(history, entry)
    if type(entry) ~= "table" or type(entry.requestId) ~= "string" then return nil, "history_entry_invalid" end
    if history.byRequest[entry.requestId] ~= nil then return history.byRequest[entry.requestId], "history_duplicate" end
    entry.state = entry.state or "sent"
    entry.accepted, entry.failed = tonumber(entry.accepted) or 0, tonumber(entry.failed) or 0
    entry.uids = type(entry.uids) == "table" and entry.uids or {}
    history.entries[#history.entries + 1] = entry
    history.byRequest[entry.requestId] = entry
    while #history.entries > history.cap do
        local dropped = table.remove(history.entries, 1)
        history.byRequest[dropped.requestId] = nil
    end
    Plan.metrics.sent = Plan.metrics.sent + 1
    return entry
end

function Plan.historyLast(history, undoableOnly)
    for index = #history.entries, 1, -1 do
        local entry = history.entries[index]
        if undoableOnly ~= true or Plan.undoable(entry) then return entry end
    end
    return nil
end

function Plan.undoable(entry)
    if type(entry) ~= "table" or entry.undone == true or entry.state == "refused" or entry.state == "failed" then return false end
    if entry.undoable == false then return false end
    return entry.groupId ~= nil or entry.siteId ~= nil or entry.sceneKey ~= nil or #(entry.uids or {}) > 0
end

function Plan.historyMine(history)
    local list = {}
    for index = #history.entries, 1, -1 do list[#list + 1] = history.entries[index] end
    return list
end

function Plan.historyAlive(history)
    local list = {}
    for _, entry in ipairs(history.entries) do
        if Plan.undoable(entry) then list[#list + 1] = entry end
    end
    return list
end

function Plan.ingest(history, command, payload)
    if type(payload) ~= "table" then return nil end
    local entry = history.byRequest[tostring(payload.requestId or "")]
    if entry == nil then return nil end
    if command == "adminSpawnResult" or command == "debugSpawnResult" then
        entry.accepted = tonumber(payload.accepted) or entry.accepted
        entry.failed = tonumber(payload.failed) or entry.failed
        entry.groupId = payload.groupId or entry.groupId
        entry.siteId = payload.siteId or payload.site or entry.siteId
        entry.origin = payload.origin or entry.origin
        if type(payload.plan) == "table" and type(payload.plan.key) == "string" then entry.sceneKey = payload.plan.key end
        entry.sceneKey = payload.sceneKey or entry.sceneKey
        if payload.ok == true then
            entry.state = entry.state == "settled" and "settled" or "accepted"
            Plan.metrics.accepted = Plan.metrics.accepted + entry.accepted
        else
            entry.state = "refused"
            entry.reason = payload.reason
            entry.text = payload.text or Plan.refusalText(payload.reason)
            Plan.metrics.failed = Plan.metrics.failed + math.max(1, entry.failed)
        end
        if tonumber(payload.failed) ~= nil and payload.ok == true then
            Plan.metrics.failed = Plan.metrics.failed + tonumber(payload.failed)
        end
    elseif command == "adminSpawnBatchResult" or command == "debugSpawnGroupResult" then
        entry.state = payload.ok == true and "settled" or (tonumber(payload.active) or 0) > 0 and "partial" or "failed"
        entry.groupId = payload.groupId or entry.groupId
        entry.active = tonumber(payload.active) or entry.active
        entry.failed = tonumber(payload.failed) or entry.failed
        if type(payload.actorUids) == "table" then entry.uids = payload.actorUids end
        if payload.reason ~= nil then entry.reason = payload.reason end
        if type(payload.reasons) == "table" then entry.reasons = payload.reasons end
    elseif command == "adminSpawnUndoResult" then
        if payload.ok == true then
            entry.undone = true
            entry.state = "undone"
            entry.removed = tonumber(payload.removed) or 0
            Plan.metrics.undone = Plan.metrics.undone + entry.removed
        else
            entry.undoReason = payload.reason
        end
    end
    return entry
end

function Plan.historyLine(entry)
    local state = tostring(entry.state)
    local parts = { entry.summary or entry.kind or "spawn", state }
    if state == "refused" then
        parts[#parts + 1] = tostring(entry.text or Plan.refusalText(entry.reason))
    elseif state == "undone" then
        parts[#parts + 1] = tostring(entry.removed or 0) .. " removed"
    else
        parts[#parts + 1] = tostring(entry.accepted) .. " accepted"
        if (entry.failed or 0) > 0 then parts[#parts + 1] = tostring(entry.failed) .. " failed" end
        if entry.active ~= nil then parts[#parts + 1] = tostring(entry.active) .. " active" end
        if type(entry.reasons) == "table" then
            local why = {}
            for reason, times in pairs(entry.reasons) do why[#why + 1] = Plan.refusalText(reason) .. " x" .. tostring(times) end
            table.sort(why)
            if #why > 0 then parts[#parts + 1] = "why: " .. table.concat(why, ", ") end
        end
    end
    return table.concat(parts, " | ")
end

function Plan.shortName(fullType)
    local text = tostring(fullType or "")
    if text == "" or text == "none" then return "-" end
    local first = string.match(text, "^([^|]+)") or text
    local alternatives = 0
    for _ in string.gmatch(text, "|") do alternatives = alternatives + 1 end
    first = string.gsub(first, "^Base%.", "")
    if alternatives > 0 then first = first .. " (+" .. tostring(alternatives) .. ")" end
    return first
end

function Plan.rosterLine(row)
    if type(row) ~= "table" then return "?" end
    local role = row.role
    if role == nil or role == "" or role == "none" then role = "member" end
    local weapon = Plan.shortName(row.primary)
    if weapon == "-" then weapon = Plan.shortName(row.melee) end
    return tostring(row.name or row.id) .. "  [" .. tostring(role) .. "]  " .. weapon
end

function Plan.previewLines(preview)
    local lines = {}
    if type(preview) ~= "table" then return lines end
    if preview.ok ~= true then
        lines[#lines + 1] = "Refused: " .. tostring(preview.text or Plan.refusalText(preview.reason))
        return lines
    end
    for _, row in ipairs(type(preview.roster) == "table" and preview.roster or {}) do
        lines[#lines + 1] = Plan.rosterLine(row)
    end
    local placement = preview.placement
    if type(placement) == "table" then
        if placement.ok == true then
            lines[#lines + 1] = "Square OK at " .. tostring(placement.x) .. "," .. tostring(placement.y) .. "," .. tostring(placement.z)
        else
            lines[#lines + 1] = "Square refused: " .. tostring(placement.text or Plan.refusalText(placement.reason))
        end
    end
    local gate = preview.gate
    if type(gate) == "table" and gate.ok ~= true then
        lines[#lines + 1] = "Gate: " .. tostring(gate.text or Plan.refusalText(gate.reason))
    end
    for _, note in ipairs(type(preview.notes) == "table" and preview.notes or {}) do lines[#lines + 1] = tostring(note) end
    return lines
end

function Plan.qaLine()
    local m = Plan.metrics
    return "[ALIFE-QA] client AdminSpawn: built=" .. tostring(m.built) .. " refused=" .. tostring(m.refused)
        .. " previews=" .. tostring(m.previews) .. " sent=" .. tostring(m.sent)
        .. " accepted=" .. tostring(m.accepted) .. " failed=" .. tostring(m.failed)
        .. " undone=" .. tostring(m.undone)
end

return Plan
