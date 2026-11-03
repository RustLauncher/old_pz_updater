require "ProjectALife/Audio/ALifeHumanReactionBanks"
require "ProjectALife/Audio/ALifeAudioPolicy"

ProjectALife = ProjectALife or {}

local Banks = ProjectALife.HumanReactionBanks or { death = {}, pain = {}, announcement = {} }

local Reactions = {
    banks = Banks,
    settings = {
        enabled = true,

        painCooldownMs = 1000,

        painSpread = 6,
        deathSpread = 24,
    },
    lastPainMs = {},
    metrics = { death = 0, pain = 0, announcement = 0, refused = 0, throttled = 0 },
}
ProjectALife.HumanReactions = Reactions

function Reactions.hash(uid)
    local text = tostring(uid or "")
    local total = 0
    for index = 1, #text do
        total = (total * 31 + string.byte(text, index)) % 2147483647
    end
    return total
end

function Reactions.pick(bank, uid, roll, spread)
    local size = type(bank) == "table" and #bank or 0
    if size == 0 then return nil end
    spread = math.max(1, math.min(size, math.floor(tonumber(spread) or 1)))
    local base = Reactions.hash(uid) % size
    local offset = math.floor((tonumber(roll) or 0) * spread) % spread
    return bank[1 + (base + offset) % size]
end

function Reactions.painDue(lastMs, now, cooldownMs)
    if lastMs == nil then return true end
    return (tonumber(now) or 0) - (tonumber(lastMs) or 0) >= (tonumber(cooldownMs) or 0)
end

local function unitRoll()
    if type(ZombRandFloat) == "function" then return ZombRandFloat(0, 1) end
    if type(ZombRand) == "function" then return ZombRand(1000) / 1000 end
    return 0.5
end

local function nowMs()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return 0
end

Reactions.adapters = {}

local function emit(shell, sound)
    if not ProjectALife.AudioPolicy.allowsNPC() then return false end
    if type(Reactions.adapters.play) == "function" then
        return Reactions.adapters.play(shell, sound) ~= false
    end

    if type(isServer) == "function" and isServer() and type(sendPlaySound) == "function" then
        return pcall(sendPlaySound, sound, false, shell) == true
    end
    local played = false
    pcall(function()
        shell:playSound(sound)
        played = true
    end)
    return played
end

local function actorBank(shell, kind)
    local library = ProjectALife.VoiceLegacyLibrary
    if library == nil then return Reactions.banks[kind] end
    local bank
    pcall(function()
        local data=shell:getModData()
        local profile=library.reactions[data.ProjectALifeVoiceProfile]
        bank=profile and profile[kind]
        local female=data.ProjectALifeFemale==true
        if not female then female=tostring(shell:GetVariable("ALifeFemale"))=="true" end
        if (bank==nil or #bank==0) and female then bank=library.female[kind] end
    end)
    return bank and #bank>0 and bank or Reactions.banks[kind]
end

function Reactions.death(shell, uid)
    if Reactions.settings.enabled ~= true or shell == nil then
        Reactions.metrics.refused = Reactions.metrics.refused + 1
        return nil
    end
    local sound = Reactions.pick(actorBank(shell, "death"), uid, unitRoll(),
        Reactions.settings.deathSpread)
    if sound == nil or not emit(shell, sound) then
        Reactions.metrics.refused = Reactions.metrics.refused + 1
        return nil
    end
    Reactions.lastPainMs[tostring(uid or "")] = nil
    Reactions.metrics.death = Reactions.metrics.death + 1
    return sound
end

function Reactions.pain(shell, uid, now)
    if Reactions.settings.enabled ~= true or shell == nil then
        Reactions.metrics.refused = Reactions.metrics.refused + 1
        return nil
    end
    local key = tostring(uid or "")
    now = tonumber(now) or nowMs()
    if not Reactions.painDue(Reactions.lastPainMs[key], now,
            Reactions.settings.painCooldownMs) then
        Reactions.metrics.throttled = Reactions.metrics.throttled + 1
        return nil
    end
    local sound = Reactions.pick(actorBank(shell, "pain"), uid, unitRoll(),
        Reactions.settings.painSpread)
    if sound == nil or not emit(shell, sound) then
        Reactions.metrics.refused = Reactions.metrics.refused + 1
        return nil
    end
    Reactions.lastPainMs[key] = now
    Reactions.metrics.pain = Reactions.metrics.pain + 1
    return sound
end

function Reactions.announcement(shell, which)
    if Reactions.settings.enabled ~= true or shell == nil then
        Reactions.metrics.refused = Reactions.metrics.refused + 1
        return nil
    end
    local bank = Reactions.banks.announcement
    local sound = Reactions.pick(bank, tostring(which or "any"), unitRoll(), #bank)
    if sound == nil or not emit(shell, sound) then
        Reactions.metrics.refused = Reactions.metrics.refused + 1
        return nil
    end
    Reactions.metrics.announcement = Reactions.metrics.announcement + 1
    return sound
end

function Reactions.forget(uid)
    Reactions.lastPainMs[tostring(uid or "")] = nil
end

function Reactions.reset()
    Reactions.lastPainMs = {}
    Reactions.metrics = { death = 0, pain = 0, announcement = 0,
        refused = 0, throttled = 0 }
end

return Reactions
