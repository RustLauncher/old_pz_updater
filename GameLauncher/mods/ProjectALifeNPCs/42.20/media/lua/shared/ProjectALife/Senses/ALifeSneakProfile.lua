ProjectALife = ProjectALife or {}

local Profile = {
    id = "sneak_profile",
    settings = { noticePercent = 50, floor = 0.1, ceiling = 0.9 },
    factor = { [1] = 1.4, [2] = 1, [3] = 0.6, [4] = 1, [5] = 0.8 },
}
ProjectALife.SneakProfile = Profile

function Profile.option(name, default)
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    if type(vars) ~= "table" then return default end
    local value = vars[name]
    if value == nil then return default end
    return value
end

function Profile.enabled()
    return Profile.option("Stealth_Enabled", true) ~= false
end

function Profile.frequency()
    local value = tonumber(Profile.option("Stealth_Frequency", 30)) or 30
    return math.max(0, math.min(100, value))
end

function Profile.lore(key)
    local lore = type(SandboxVars) == "table" and SandboxVars.ZombieLore or nil
    local value = type(lore) == "table" and tonumber(lore[key]) or nil
    return Profile.factor[value or 2] or 1
end

function Profile.reduction(sense)
    local percent = tonumber(Profile.option("Stealth_NoticePercent", Profile.settings.noticePercent))
        or Profile.settings.noticePercent
    percent = math.max(10, math.min(100, percent))
    local base = 1 - percent / 100
    local scale = 1 + (1 - Profile.lore(sense)) * 0.5
    return math.max(0, math.min(Profile.settings.ceiling, base * scale))
end

function Profile.sneaking(body)
    if body == nil or type(body.hasModData) ~= "function" or body:hasModData() ~= true then return false end
    local data = body:getModData()
    return type(data) == "table" and data.ProjectALifeSneakActive == true
end

function Profile.noticeScale(body)
    if not Profile.enabled() or not Profile.sneaking(body) then return 1 end
    return math.max(Profile.settings.floor, 1 - Profile.reduction("Sight"))
end

function Profile.senseScale(body)
    if not Profile.enabled() or not Profile.sneaking(body) then return 1 end
    return math.max(Profile.settings.floor, 1 - Profile.reduction("Hearing"))
end

return Profile
