require "ProjectALife/Admin/ALifeAdminActions"
require "ProjectALife/Admin/ALifeSpawnPlan"

ProjectALife = ProjectALife or {}

local Prefs = {
    fileName = "alife_admin_console.ini",
    presetFile = "alife_admin_spawn_presets.ini",
    loaded = false,
    favourites = {},
    values = { classic = false, autoRefresh = true, verbosity = "normal", tab = "spawn" },
    verbosities = { "quiet", "normal", "verbose" },
    presets = {}, presetOrder = {}, presetsLoaded = false,
    metrics = { loads = 0, saves = 0, failures = 0 },
}
ProjectALife.AdminPrefs = Prefs

function Prefs.readLines(name)
    if type(getFileReader) ~= "function" then return nil end
    local reader = getFileReader(name, true)
    if reader == nil then return nil end
    local lines = {}
    while true do
        local line = reader:readLine()
        if line == nil then break end
        lines[#lines + 1] = line
    end
    reader:close()
    return lines
end

function Prefs.writeText(name, text)
    if type(getFileWriter) ~= "function" then return false end
    local writer = getFileWriter(name, true, false)
    if writer == nil then return false end
    writer:write(text)
    writer:close()
    return true
end

function Prefs.load()
    if Prefs.loaded then return Prefs.values end
    Prefs.loaded = true
    Prefs.metrics.loads = Prefs.metrics.loads + 1
    local lines = Prefs.readLines(Prefs.fileName)
    if lines == nil then return Prefs.values end
    local text = table.concat(lines, "\n")
    Prefs.favourites = ProjectALife.AdminActions.decodeFavourites(text)
    for _, line in ipairs(lines) do
        local key, value = string.match(line, "^%s*([%a]+)%s*=%s*([%w_%-]+)%s*$")
        if key == "classic" or key == "autoRefresh" then
            Prefs.values[key] = value == "true"
        elseif key == "verbosity" then
            for _, name in ipairs(Prefs.verbosities) do
                if name == value then Prefs.values.verbosity = value end
            end
        elseif key == "tab" and ProjectALife.AdminActions.tab(value) ~= nil then
            Prefs.values.tab = value
        end
    end
    return Prefs.values
end

function Prefs.persist()
    local values = Prefs.values
    local text = "classic = " .. tostring(values.classic == true) .. "\n"
        .. "autoRefresh = " .. tostring(values.autoRefresh ~= false) .. "\n"
        .. "verbosity = " .. tostring(values.verbosity) .. "\n"
        .. "tab = " .. tostring(values.tab) .. "\n"
        .. ProjectALife.AdminActions.encodeFavourites(Prefs.favourites) .. "\n"
    local ok, written = pcall(Prefs.writeText, Prefs.fileName, text)
    if ok and written == true then
        Prefs.metrics.saves = Prefs.metrics.saves + 1
        return true
    end
    Prefs.metrics.failures = Prefs.metrics.failures + 1
    return false
end

function Prefs.get(key)
    return Prefs.load()[key]
end

function Prefs.set(key, value)
    Prefs.load()[key] = value
    return Prefs.persist()
end

function Prefs.cycleVerbosity()
    local current = Prefs.load().verbosity
    local nextName = Prefs.verbosities[1]
    for index, name in ipairs(Prefs.verbosities) do
        if name == current then nextName = Prefs.verbosities[(index % #Prefs.verbosities) + 1] end
    end
    Prefs.set("verbosity", nextName)
    return nextName
end

function Prefs.favouriteList()
    Prefs.load()
    return Prefs.favourites
end

function Prefs.toggleFavourite(id)
    Prefs.load()
    local list, changed, reason = ProjectALife.AdminActions.toggleFavourite(Prefs.favourites, id)
    if changed then
        Prefs.favourites = list
        Prefs.persist()
    end
    return changed, reason
end

function Prefs.loadPresets()
    if Prefs.presetsLoaded then return Prefs.presets, Prefs.presetOrder end
    Prefs.presetsLoaded = true
    local ok, lines = pcall(Prefs.readLines, Prefs.presetFile)
    if ok and lines ~= nil then
        Prefs.presets, Prefs.presetOrder = ProjectALife.SpawnPlan.decodeStore(table.concat(lines, "\n"))
    end
    return Prefs.presets, Prefs.presetOrder
end

function Prefs.savePreset(name, spec)
    local plan = ProjectALife.SpawnPlan
    Prefs.loadPresets()
    name = plan.cleanPresetName(name)
    if name == "" then return false, "preset_name_required" end
    if Prefs.presets[name] == nil then
        if #Prefs.presetOrder >= plan.LIMITS.presets then return false, "preset_store_full" end
        Prefs.presetOrder[#Prefs.presetOrder + 1] = name
    end
    Prefs.presets[name] = plan.normalize(spec)
    local ok, written = pcall(Prefs.writeText, Prefs.presetFile, plan.encodeStore(Prefs.presets, Prefs.presetOrder))
    if ok and written == true then return true end
    Prefs.metrics.failures = Prefs.metrics.failures + 1
    return false, "preset_write_failed"
end

function Prefs.deletePreset(name)
    local plan = ProjectALife.SpawnPlan
    Prefs.loadPresets()
    if Prefs.presets[name] == nil then return false, "preset_unknown" end
    Prefs.presets[name] = nil
    for index, value in ipairs(Prefs.presetOrder) do
        if value == name then table.remove(Prefs.presetOrder, index); break end
    end
    local ok, written = pcall(Prefs.writeText, Prefs.presetFile, plan.encodeStore(Prefs.presets, Prefs.presetOrder))
    return ok and written == true, "preset_write_failed"
end

function Prefs.getPreset(name)
    Prefs.loadPresets()
    local spec = Prefs.presets[name]
    if spec == nil then return nil end
    return ProjectALife.SpawnPlan.copySpec(spec)
end

return Prefs
