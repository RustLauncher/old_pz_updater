require "ProjectALife/Outposts/ALifeOutpostPresets"
require "ProjectALife/Compat/ALifeInterop"
ProjectALife = ProjectALife or {}

local Interop = ProjectALife.Interop
local Registry = {
    TAG = "ProjectALife.Outposts.v1",
    SCHEMA = 1,
    adapters = {},
    storage = nil,
    dirty = false,

    settings = { tombstoneHours = 48, drainAttempts = 3 },
    metrics = { created = 0, expired = 0, erased = 0, rejected = 0 },
}
ProjectALife.OutpostRegistry = Registry

local function copy(value, depth)
    depth = depth or 0
    if type(value) ~= "table" or depth > 8 then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item, depth + 1) end
    return result
end

local function lightCopy(site)
    if type(site) ~= "table" then return nil end
    local result = {}
    for key, item in pairs(site) do
        if key ~= "props" then result[key] = copy(item) end
    end
    result.propCount = type(site.props) == "table" and #site.props or 0
    return result
end

function Registry.propsOf(id)
    local state = Registry.storageForProps and Registry.storageForProps() or nil
    local site = state and state.sites[id] or nil
    if site == nil or type(site.props) ~= "table" then return {} end
    return copy(site.props)
end

local function storage()
    if Registry.storage ~= nil then return Registry.storage end
    local result
    if type(Registry.adapters.getOrCreate) == "function" then
        result = Registry.adapters.getOrCreate(Registry.TAG)
    elseif ModData ~= nil and type(ModData.getOrCreate) == "function" then
        result = ModData.getOrCreate(Registry.TAG)
    end
    if type(result) ~= "table" then return nil, "mod_data_unavailable" end
    if result.schema == nil then
        result.schema = Registry.SCHEMA
        result.sites, result.cityCounts, result.order, result.sequence = {}, {}, {}, 0
        Registry.dirty = true
    elseif result.schema ~= Registry.SCHEMA then
        return nil, "outposts_schema_unsupported:" .. tostring(result.schema)
    end
    result.sites = result.sites or {}
    result.cityCounts = result.cityCounts or {}
    result.order = result.order or {}
    Registry.storage = result
    return result
end

Registry.storageForProps = storage

function Registry.configure(adapters)
    Registry.adapters = adapters or {}
    Registry.storage = nil
    Registry.dirty = false
    return true
end

function Registry.reset()
    local state = storage()
    if state == nil then return false end
    state.sites, state.cityCounts, state.order, state.sequence = {}, {}, {}, 0
    state.fixedSiteIds = {}
    Registry.dirty = true
    return true
end

function Registry.cityKeyFor(x, y, townName)
    local key = tostring(math.floor((tonumber(x) or 0) / 300)) .. "_"
        .. tostring(math.floor((tonumber(y) or 0) / 300))
    if type(townName) == "string" and townName ~= "" then key = key .. ":" .. townName end
    return key
end

function Registry.countIn(cityKey)
    local state = storage()
    return state and (state.cityCounts[cityKey] or 0) or 0
end

function Registry.count()
    local state = storage()
    if state == nil then return 0 end
    local count = 0
    for _, id in ipairs(state.order) do
        local site = state.sites[id]
        if site ~= nil and site.state ~= "expired" then count = count + 1 end
    end
    return count
end

function Registry.create(fields)
    local gate = ProjectALife.CleanupLock
    if gate ~= nil and gate.refuse("outpost_site") then return nil, "cleanup_locked" end
    local state, err = storage()
    if state == nil then return nil, err end
    if type(fields) ~= "table" or type(fields.presetId) ~= "string" then return nil, "site_fields_invalid" end
    if not Interop.run("outpost.siting", fields) then return nil, "interop_siting" end
    state.sequence = (state.sequence or 0) + 1
    local id = "site:" .. tostring(state.sequence)
    local cityKey = tostring(fields.cityKey or Registry.cityKeyFor(fields.x, fields.y))
    local site = {
        id = id, revision = 1,
        presetId = fields.presetId,
        state = "proposed",
        cityKey = cityKey,
        bounds = copy(fields.bounds) or { x1 = 0, y1 = 0, x2 = 0, y2 = 0, z = 0 },
        x = tonumber(fields.x) or 0, y = tonumber(fields.y) or 0,
        createdHours = tonumber(fields.createdHours) or 0,
        minLifeHours = tonumber(fields.minLifeHours) or 48,
        maxLifeHours = tonumber(fields.maxLifeHours) or 120,
        factionId = fields.factionId,
        hostileToPlayers = fields.hostileToPlayers,
        pressureTicket = type(fields.pressureTicket) == "table" and copy(fields.pressureTicket) or nil,
        props = {}, garrison = {}, squads = {},
        backups = 0, commsDisabled = false, thefts = 0,
        mainEntrance = nil,
    }
    local preset = ProjectALife.OutpostPresets.get(fields.presetId)
    if preset and preset.hostileToPlayers == true then site.hostileToPlayers = true end

    if preset and tonumber(preset.planVersion) ~= nil then site.planVersion = tonumber(preset.planVersion) end
    state.sites[id] = site
    state.order[#state.order + 1] = id
    state.cityCounts[cityKey] = (state.cityCounts[cityKey] or 0) + 1
    if preset and preset.fixedSite == true then
        state.fixedSiteIds = type(state.fixedSiteIds) == "table" and state.fixedSiteIds or {}
        state.fixedSiteIds[fields.presetId] = id
    end
    Registry.dirty = true
    Registry.metrics.created = Registry.metrics.created + 1
    return copy(site)
end

function Registry.read(id)
    local state = storage()
    local site = state and state.sites[id] or nil
    return site and lightCopy(site) or nil
end

function Registry.fixedSiteId(presetId)
    local state = storage()
    if state == nil then return nil end
    state.fixedSiteIds = type(state.fixedSiteIds) == "table" and state.fixedSiteIds or {}
    if state.fixedSiteIds[presetId] ~= nil then return state.fixedSiteIds[presetId] end
    for _, site in pairs(state.sites) do
        if site.presetId == presetId then
            state.fixedSiteIds[presetId] = site.id
            Registry.dirty = true
            return site.id
        end
    end
    return nil
end

function Registry.list()
    local state = storage()
    if state == nil then return {} end
    local result = {}
    for _, id in ipairs(state.order) do
        local site = state.sites[id]
        if site ~= nil then result[#result + 1] = lightCopy(site) end
    end
    return result
end

function Registry.update(id, expectedRevision, mutation)
    local state = storage()
    if state == nil then return nil, "mod_data_unavailable" end
    local site = state.sites[id]
    if site == nil then return nil, "site_not_found" end
    if site.revision ~= expectedRevision then
        Registry.metrics.rejected = Registry.metrics.rejected + 1
        return nil, "site_revision_conflict"
    end
    local ok, err = pcall(mutation, site)
    if not ok then return nil, "site_mutation_failed:" .. tostring(err) end
    site.revision = site.revision + 1
    Registry.dirty = true
    return lightCopy(site)
end

function Registry.expire(id, expectedRevision, hours, reason)
    local state = storage()
    if state == nil then return nil, "mod_data_unavailable" end
    local site = state.sites[id]
    if site == nil then return nil, "site_not_found" end
    if site.revision ~= expectedRevision then return nil, "site_revision_conflict" end
    if site.state == "expired" then return lightCopy(site) end
    site.state = "expired"
    site.expiredHours = tonumber(hours) or 0
    site.expiredReason = reason
    site.revision = site.revision + 1
    state.cityCounts[site.cityKey] = math.max(0, (state.cityCounts[site.cityKey] or 1) - 1)
    Registry.dirty = true
    Registry.metrics.expired = Registry.metrics.expired + 1
    return lightCopy(site)
end

function Registry.sweep(hours)
    local state = storage()
    if state == nil then return 0 end
    local erased = 0
    for index = #state.order, 1, -1 do
        local id = state.order[index]
        local site = state.sites[id]

        local owed = type(site) == "table" and type(site.props) == "table" and #site.props or 0
        if site ~= nil and site.state == "expired" and owed == 0
                and (tonumber(hours) or 0) - (tonumber(site.expiredHours) or 0) >= Registry.settings.tombstoneHours then
            state.sites[id] = nil
            table.remove(state.order, index)
            erased = erased + 1
        end
    end
    if erased > 0 then
        Registry.dirty = true
        Registry.metrics.erased = Registry.metrics.erased + erased
    end
    return erased
end

function Registry.drainOpen(limits)
    if type(limits) ~= "table" then return true end
    if (tonumber(limits.units) or 1) <= 0 then return false end
    local deadline = tonumber(limits.deadline)
    if deadline ~= nil and type(limits.now) == "function" and (tonumber(limits.now()) or 0) >= deadline then
        return false
    end
    return true
end

function Registry.propsBox(id)
    local state = storage()
    local site = state and state.sites[id] or nil
    if site == nil or type(site.props) ~= "table" then return nil end
    local count = #site.props
    local box = site.drainBox
    if type(box) ~= "table" or tonumber(box.n) ~= count then
        box = { n = count }
        for _, row in ipairs(site.props) do
            if type(row) == "table" then
                local x, y = tonumber(row.x), tonumber(row.y)
                if x ~= nil and y ~= nil then
                    if box.x1 == nil then
                        box.x1, box.y1, box.x2, box.y2 = x, y, x, y
                    else
                        box.x1, box.y1 = math.min(box.x1, x), math.min(box.y1, y)
                        box.x2, box.y2 = math.max(box.x2, x), math.max(box.y2, y)
                    end
                end
            end
        end
        site.drainBox = box
        Registry.dirty = true
    end
    if box.x1 == nil then return nil end
    return box.x1, box.y1, box.x2, box.y2
end

function Registry.drainProps(id, visit, limits)
    local state = storage()
    local site = state and state.sites[id] or nil
    if site == nil or type(site.props) ~= "table" or type(visit) ~= "function" then return 0, 0, 0, nil end
    local props = site.props
    if type(limits) ~= "table" then limits = {} end
    local count = #props
    local index = math.floor(tonumber(site.drainCursor) or 0)
    if index < 1 or index > count then index = count end
    local cap = tonumber(limits.rows) or count
    local gone, removed, visited, dropped, abandoned = 0, 0, 0, 0, nil
    while index >= 1 and visited < cap do
        if visited > 0 and not Registry.drainOpen(limits) then break end
        visited = visited + 1
        local row = props[index]
        local drop = type(row) ~= "table"
        if not drop then
            local ok, verdict, objects, cost = pcall(visit, row, id, limits)
            if not ok then
                row.drainErrors = (tonumber(row.drainErrors) or 0) + 1
                if row.drainErrors >= (tonumber(Registry.settings.drainAttempts) or 3) then
                    drop = true
                    site.drainAbandoned = (tonumber(site.drainAbandoned) or 0) + 1
                    abandoned = abandoned or {}
                    abandoned[#abandoned + 1] = { x = row.x, y = row.y, z = row.z, sprite = row.sprite,
                        class = row.class, error = tostring(verdict) }
                end
            elseif verdict == "gone" then
                drop = true
                gone = gone + 1
                removed = removed + (tonumber(objects) or 0)
                limits.units = (tonumber(limits.units) or math.huge) - (tonumber(cost) or 0)
            end
        end
        if drop then
            props[index] = false
            dropped = dropped + 1
        end
        index = index - 1
    end
    if dropped > 0 then

        local write = index + 1
        for read = index + 1, count do
            local row = props[read]
            if row ~= false then
                props[write] = row
                write = write + 1
            end
        end
        for read = count, write, -1 do props[read] = nil end
    end
    if index >= 1 then site.drainCursor = index else site.drainCursor = nil end
    site.drainRemoved = (tonumber(site.drainRemoved) or 0) + gone
    if type(site.drainBox) == "table" then site.drainBox.n = #props end
    if visited > 0 then
        site.revision = site.revision + 1
        Registry.dirty = true
    end
    return gone, removed, #props, abandoned
end

function Registry.tallyLoss(site, isTarget)
    local total, sampled, lost, burn = 0, 0, 0, 0
    for _, row in ipairs(site.props) do
        if type(row) == "table" and isTarget(row) then
            total = total + 1
            local seen = row.ls
            if seen ~= nil then
                sampled = sampled + 1
                if seen == 2 or seen == 3 then lost = lost + 1 end
                if seen == 3 then burn = burn + 1 end
            end
        end
    end
    site.lossN, site.lossTotal, site.lossSampled, site.lossLost, site.lossBurn = #site.props, total, sampled, lost, burn
end

function Registry.sampleLoss(id, count, probe, isTarget, recheck)
    local state = storage()
    local site = state and state.sites[id] or nil
    if site == nil or type(site.props) ~= "table" or type(probe) ~= "function" or type(isTarget) ~= "function" then
        return nil
    end
    local props = site.props
    local n = #props
    if n == 0 then return nil end
    local cap = math.max(1, math.floor(tonumber(count) or 24))
    local visited, changed = 0, false
    local function look(row)
        local ok, verdict = pcall(probe, row)
        if not ok or verdict == nil then return end
        visited = visited + 1
        local mark = 1
        if verdict == "lost" then mark = 2 elseif verdict == "burn" then mark = 3 end
        if row.ls ~= mark then
            row.ls = mark
            changed = true
        end
    end
    if recheck == true then
        for index = 1, n do
            if visited >= cap then break end
            local row = props[index]
            if type(row) == "table" and (row.ls == 2 or row.ls == 3) then look(row) end
        end
    else
        local cursor = math.floor(tonumber(site.lossCursor) or 0)
        for _ = 1, math.min(n, 512) do
            if visited >= cap then break end
            cursor = cursor % n + 1
            local row = props[cursor]
            if type(row) == "table" and isTarget(row) then look(row) end
        end
        site.lossCursor = cursor
    end
    if changed or site.lossN ~= n or site.lossTotal == nil then
        Registry.tallyLoss(site, isTarget)
        Registry.dirty = true
    end
    return { visited = visited, total = site.lossTotal, sampled = site.lossSampled, lost = site.lossLost,
        burn = site.lossBurn }
end

function Registry.flush()
    if not Registry.dirty then return true, false end
    if type(Registry.adapters.transmit) == "function" then
        local ok, result = pcall(Registry.adapters.transmit, Registry.TAG)
        if not ok or result == false then return false, "outposts_transmit_failed" end
    end
    Registry.dirty = false
    return true, true
end

return Registry
