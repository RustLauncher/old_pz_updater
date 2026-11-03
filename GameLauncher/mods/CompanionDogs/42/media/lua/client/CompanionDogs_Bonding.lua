CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

local wasAsleep = {}
local sleptNear = {}
local pendingFetch = {}

local function onPlayerUpdate(player)
    if not player then return end
    local idx = player:getPlayerNum()
    local asleep = player:isAsleep()
    local prev = wasAsleep[idx]
    local bonding = CD.bondingEnabled()

    if asleep and not prev then
        if bonding then
            sleptNear[idx] = CD.findNearbyCompanion(player, CD.sleepNearRadius())
        end
    elseif prev and not asleep then
        if bonding and sleptNear[idx] then
            CD.relieveMood(player, CD.sleepMoodRelief())
            if CD.restedBuffEnabled() then
                CD.startRestedBuff(player)
            end
            HaloTextHelper.addGoodText(player, getText("IGUI_PD_SleptWithDog", CD.breedNoun(sleptNear[idx])))
        end
        sleptNear[idx] = nil
        pendingFetch[idx] = getTimestampMs() + CD.SLEEP_FETCH_DELAY_MS
    end

    if pendingFetch[idx] then
        if asleep then
            pendingFetch[idx] = nil
        elseif getTimestampMs() >= pendingFetch[idx] then
            pendingFetch[idx] = nil
            if CD.tricksEnabled() and CD.getCompanionAnimal then
                local dog = CD.findNearbyCompanion(player, CD.sleepNearRadius())
                if dog and CD.trickUnlocked(dog, "fetch") and CD.hasBag(dog) and CD.fetchedScent(dog) then
                    CD.request("trickfetch", dog, { slept = true }, player)
                end
            end
        end
    end

    wasAsleep[idx] = asleep
end

if isClient() or not isServer() then
    CD.evAdd(Events.OnPlayerUpdate, onPlayerUpdate, "cli.bonding")
end
