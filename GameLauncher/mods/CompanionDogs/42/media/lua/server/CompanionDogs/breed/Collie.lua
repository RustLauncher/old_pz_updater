CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

local function worldMinutes()
    return getGameTime():getWorldAgeHours() * 60
end

---Server side, throttled: a breed with calmMult above 1 lowers and caps the stress of the tame livestock around it.
---@param animal IsoAnimal
---@param d table companion ModData
function CD.collieCalmPass(animal, d)
    if isClient() then return end
    if (CD.getBreedDef(animal).calmMult or 1) <= 1 then return end
    if CD.isDisloyal(animal) or CD.blocksBreedPassive(animal) then return end
    local h = CD.getHunger(animal)
    local t = animal:getThirst()
    if h >= CD.MOODLE_NEGLECT_MAX or t >= CD.MOODLE_NEGLECT_MAX then return end

    local now = worldMinutes()
    if d.lastCollieCalmMin and (now - d.lastCollieCalmMin) < CD.collieCalmThrottleMin() then return end
    d.lastCollieCalmMin = now

    local delta = CD.effectiveCalmStrength(animal)
    if delta > 0 then return end
    local cap = CD.effectiveCalmCap(animal)

    local cell = getCell()
    if not cell then return end
    CD.perfCount("sweep.animals")
    local list = cell:getAnimals()

    local ax, ay, az = animal:getX(), animal:getY(), math.floor(animal:getZ())
    local radius = CD.collieCalmRadius()
    local maxHerd = CD.COLLIE_CALM_MAX_HERD
    local n, applied = 0, false
    for i = 0, list:size() - 1 do
        if n >= maxHerd then break end
        local la = list:get(i)
        local ok = false
        if la then
            ok = la ~= nil and not CD.isDog(la) and not la:isWild() and not la:isDead()
                and math.floor(la:getZ()) == az
                and math.abs(la:getX() - ax) <= radius and math.abs(la:getY() - ay) <= radius
        end
        if ok then
            n = n + 1
            applied = true
            if delta ~= 0 then
                la:changeStress(delta)
            end
            if cap < 100 then
                if la:getStress() > cap then
                    la:setDebugStress(cap)
                end
            end
        end
    end
    if applied then
        if not d.lastCollieTendXpMin or (now - d.lastCollieTendXpMin) >= CD.CARE_XP_TEND_THROTTLE_MIN then
            d.lastCollieTendXpMin = now
            CD.addSkillXP(animal, "herding", CD.CARE_XP_PER_TEND)
        end
    end
end
