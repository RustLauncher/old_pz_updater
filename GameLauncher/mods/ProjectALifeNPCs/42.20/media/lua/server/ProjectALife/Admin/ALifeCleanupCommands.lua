require "ProjectALife/Core/ALifeCleanupLock"
require "ProjectALife/Admin/ALifeCleanup"
require "ProjectALife/Admin/ALifeCleanupWorld"
require "ProjectALife/Admin/ALifeCleanupSites"
require "ProjectALife/Admin/ALifeCleanupNpcs"
require "ProjectALife/Admin/ALifeCleanupEvents"
require "ProjectALife/Admin/ALifeCleanupState"

ProjectALife = ProjectALife or {}

local Cleanup = ProjectALife.Cleanup
local Lock = ProjectALife.CleanupLock

local Commands = {
    names = { cleanupScan = true, cleanupRun = true, cleanupCancel = true, cleanupStatus = true,
        cleanupList = true, cleanupFinish = true },
    adapters = {},
    last = {},
    minimumIntervalMs = 250,
    registered = false,
    metrics = { handled = 0, denied = 0, rateLimited = 0 },
}
ProjectALife.CleanupCommands = Commands

function Commands.configure(adapters)
    Commands.adapters = type(adapters) == "table" and adapters or {}
    Commands.last = {}
end

function Commands.now()
    return Cleanup.now()
end

function Commands.authorized(player)
    if type(Commands.adapters.authorized) == "function" then
        return Commands.adapters.authorized(player) == true
    end
    if type(isServer) ~= "function" or not isServer() then return true end
    if player == nil or type(player.getAccessLevel) ~= "function" then return false end
    local ok, level = pcall(player.getAccessLevel, player)
    return ok and string.lower(tostring(level or "")) == "admin"
end

function Commands.username(player)
    if player ~= nil and type(player.getUsername) == "function" then
        local ok, name = pcall(player.getUsername, player)
        if ok and name ~= nil then return tostring(name) end
    end
    return "local"
end

function Commands.reply(player, command, payload)
    if type(Commands.adapters.send) == "function" then
        Commands.adapters.send(player, "ProjectALife", command, payload)
        return
    end
    if type(isServer) == "function" and isServer() then
        if type(sendServerCommand) == "function" then sendServerCommand(player, "ProjectALife", command, payload) end
        return
    end
    local client = ProjectALife.CleanupClient
    if client ~= nil and type(client.receive) == "function" then client.receive("ProjectALife", command, payload) end
end

function Commands.broadcast(command, payload)
    if type(Commands.adapters.broadcast) == "function" then
        Commands.adapters.broadcast(command, payload)
        return
    end
    if type(isServer) == "function" and isServer() then
        if type(sendServerCommand) ~= "function" then return end
        if command == "cleanupMarkers" then
            sendServerCommand("ProjectALife", "cleanupMarkers", payload)
        else
            sendServerCommand("ProjectALife", command, payload)
        end
        return
    end
    local client = ProjectALife.CleanupClient
    if client ~= nil and type(client.receive) == "function" then client.receive("ProjectALife", command, payload) end
end

function Commands.playerByName(name)
    if type(Commands.adapters.playerByName) == "function" then return Commands.adapters.playerByName(name) end
    local locator = ProjectALife.PlayerLocator
    if locator == nil or type(locator.list) ~= "function" then return nil end
    local ok, players = pcall(locator.list)
    if not ok or type(players) ~= "table" then return nil end
    for _, player in ipairs(players) do
        if Commands.username(player) == tostring(name) then return player end
    end
    if type(isServer) ~= "function" or not isServer() then return players[1] end
    return nil
end

function Commands.slice(list, offset, limit)
    local rows = {}
    list = type(list) == "table" and list or {}
    offset = math.max(0, math.floor(tonumber(offset) or 0))
    for index = offset + 1, math.min(#list, offset + limit) do rows[#rows + 1] = list[index] end
    return rows, #list
end

function Commands.activeJob()
    if Cleanup.job ~= nil then return Cleanup.job end
    local state = Lock.peek()
    local saved = type(state) == "table" and state.job or nil
    if type(saved) == "table" and type(saved.counts) == "table" then return saved end
    return nil
end

function Commands.payload(extra)
    local status = Cleanup.status()
    local job = Commands.activeJob()
    if job ~= nil then
        local summary = status.job or Cleanup.summary(job)
        local sites, total = Commands.slice(job.siteRows, 0, Cleanup.settings.listPage)
        summary.sites = sites
        summary.siteTotal = total
        summary.protected = nil
        status.job = summary
        status.listCounts = {
            sites = #(job.siteRows or {}), skipped = #(job.skipped or {}), protected = #(job.protectedRows or {}),
            unverified = #(job.unverifiedRows or {}), companions = #(job.companionRows or {}),
            report = #(job.report or {}),
        }
        status.pendingRows = Cleanup.pendingRows(job, 12)
        status.residual = job.residual
    end
    status.phrase = Cleanup.PHRASE
    status.phrase2 = Cleanup.PHRASE2
    if type(extra) == "table" then
        for key, value in pairs(extra) do status[key] = value end
    end
    return status
end

function Commands.list(args)
    local job = Commands.activeJob()
    local kind = tostring(args.kind or "")
    if job == nil then return { ok = false, reason = "no_job" } end
    local source
    if kind == "sites" then source = job.siteRows
    elseif kind == "skipped" then source = job.skipped
    elseif kind == "protected" then source = job.protectedRows
    elseif kind == "unverified" then source = job.unverifiedRows
    elseif kind == "companions" then source = job.companionRows
    elseif kind == "report" then source = job.report
    elseif kind == "pending" then source = Cleanup.pendingRows(job, 400)
    else return { ok = false, reason = "unknown_list" } end
    local rows, total = Commands.slice(source, args.offset, Cleanup.settings.listPage)
    return { ok = true, kind = kind, rows = rows, total = total, offset = math.max(0, math.floor(tonumber(args.offset) or 0)) }
end

function Commands.limited(player, command)
    local key = Commands.username(player) .. ":" .. command
    local now = Commands.now()
    local last = Commands.last[key]
    if last ~= nil and now - last < Commands.minimumIntervalMs then
        Commands.metrics.rateLimited = Commands.metrics.rateLimited + 1
        return true
    end
    Commands.last[key] = now
    return false
end

function Commands.audit(player, command, result)
    Cleanup.log("[ALIFE-CLEANUP] command=" .. tostring(command) .. " user=" .. Commands.username(player)
        .. " result=" .. tostring(result))
end

function Commands.handle(module, command, player, args)
    if module ~= "ProjectALife" or Commands.names[command] ~= true or player == nil then return false end
    args = type(args) == "table" and args or {}
    local resultCommand = command .. "Result"
    if not Commands.authorized(player) then
        Commands.metrics.denied = Commands.metrics.denied + 1
        Commands.audit(player, command, "admin_required")
        Commands.reply(player, resultCommand, { ok = false, reason = "admin_required" })
        return false
    end
    if Commands.limited(player, command) then
        Commands.reply(player, resultCommand, { ok = false, reason = "rate_limited" })
        return false
    end
    Commands.metrics.handled = Commands.metrics.handled + 1
    local by = Commands.username(player)
    if command == "cleanupScan" then
        local job, reason = Cleanup.scan({ scopes = args.scopes, by = by, radius = args.radius })
        Commands.audit(player, command, job ~= nil and "started" or reason)
        Commands.reply(player, resultCommand, Commands.payload({ ok = job ~= nil, reason = reason }))
        return job ~= nil
    elseif command == "cleanupRun" then
        local job, reason = Cleanup.run({ scopes = args.scopes, confirm = args.confirm, confirm2 = args.confirm2,
            overrides = args.overrides, by = by })
        Commands.audit(player, command, job ~= nil and "started" or reason)
        Commands.reply(player, resultCommand, Commands.payload({ ok = job ~= nil, reason = reason }))
        return job ~= nil
    elseif command == "cleanupCancel" then
        local ok, reason = Cleanup.cancel({ reopen = args.reopen == true })
        Commands.audit(player, command, tostring(reason))
        Commands.reply(player, resultCommand, Commands.payload({ ok = ok, reason = reason }))
        return ok
    elseif command == "cleanupFinish" then
        local ok, reason = Cleanup.finish({ confirm = args.confirm })
        Commands.audit(player, command, tostring(reason))
        Commands.reply(player, resultCommand, Commands.payload({ ok = ok, reason = reason }))
        return ok
    elseif command == "cleanupList" then
        Commands.reply(player, resultCommand, Commands.list(args))
        return true
    end
    Commands.reply(player, resultCommand, Commands.payload({ ok = true }))
    return true
end

function Commands.progress(job)
    local target = Commands.playerByName(job.by)
    if target == nil then return false end
    local summary = Cleanup.summary(job)
    summary.sites = nil
    summary.protected = nil
    local status = { ok = true, mode = Lock.mode(), job = summary, pendingRows = Cleanup.pendingRows(job, 6) }
    Commands.reply(target, "cleanupProgress", status)
    return true
end

function Commands.report(lines)
    if type(Commands.adapters.writeReport) == "function" then return Commands.adapters.writeReport(lines) end
    if type(getFileWriter) ~= "function" then return false end
    local writer
    local ok = pcall(function()
        writer = getFileWriter("alife_cleanup_report.txt", true, false)
        if writer == nil then return end
        writer:write(table.concat(lines, "\n") .. "\n")
    end)
    if writer == nil then return false end
    local closed = pcall(function() writer:close() end)
    return ok and closed
end

function Commands.install()
    Cleanup.configure({
        progress = function(job) return Commands.progress(job) end,
        broadcast = function(command, payload) return Commands.broadcast(command, payload) end,
        writeReport = function(lines) return Commands.report(lines) end,
        nowMs = Commands.adapters.nowMs,
        log = Commands.adapters.log,
        players = Commands.adapters.players,
        safehouses = Commands.adapters.safehouses,
        cell = Commands.adapters.cell,
        hours = Commands.adapters.hours,
        ready = Commands.adapters.ready,
    })
end

function Commands.hosted()
    if type(isClient) == "function" and isClient() == true
            and not (type(isServer) == "function" and isServer() == true) then
        return false
    end
    return true
end

function Commands.onTick()
    if not Commands.hosted() then return end
    local mode = Lock.mode()
    if mode == "idle" and Cleanup.job == nil then return end
    if mode == "running" and Cleanup.job == nil then Cleanup.resume() end
    local ok, reason = pcall(Cleanup.tick)
    if not ok then
        Cleanup.metrics.errors = Cleanup.metrics.errors + 1
        Cleanup.log("[ALIFE-CLEANUP] tick fault: " .. tostring(reason))
    end
end

function Commands.onSquare(square)
    local job = Cleanup.job
    if job == nil or job.stage ~= "pending" then return end
    Cleanup.onSquareLoaded(square)
end

function Commands.onStart()
    if not Commands.hosted() then return end
    Lock.refresh()
    if Lock.mode() == "running" then Cleanup.resume() end
end

function Commands.onSave()
    if not Commands.hosted() then return end
    if Lock.mode() == "done" then
        Cleanup.guardAt = nil
        Cleanup.guard()
    end
end

function Commands.register()
    if Commands.registered or type(Events) ~= "table" then return false end
    Commands.registered = true
    Commands.install()
    local function add(name, callback)
        local event = Events[name]
        if event ~= nil and type(event.Add) == "function" then event.Add(callback) end
    end
    add("OnClientCommand", Commands.handle)
    add("OnTick", Commands.onTick)
    add("LoadGridsquare", Commands.onSquare)
    add("OnGameStart", Commands.onStart)
    add("OnServerStarted", Commands.onStart)
    add("OnSave", Commands.onSave)
    return true
end

Commands.register()

return Commands
