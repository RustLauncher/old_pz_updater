require "OfflineSurvivorV2/OS_BodyLifecycle"
local OS = OfflineSurvivorV2
local H = OS.BodyLifecycle
local samples=setmetatable({}, {__mode="k"})
local cache=setmetatable({}, {__mode="k"})

-- CorpseCount/FliesSound are not Lua-exposed in B42.20. Do not patch Java,
-- change the global sandbox, or grant immunity to genuine corpses/poison.
-- Compensate only the measured extra FOOD_SICKNESS from marked visual proxies.
-- Counting follows the engine's 3x3 eight-tile chunks, floor and building.
local function countSources(player)
    local cell=getCell()
    local square=player:getSquare()
    if not cell or not square then return nil end
    local cx=math.floor(player:getX()/8)*8
    local cy=math.floor(player:getY()/8)*8
    local z=math.floor(player:getZ())
    local building=square:getBuilding()
    local now=getTimestampMs()
    local old=cache[player]
    if old and old.cx==cx and old.cy==cy and old.z==z and old.building==building
        and now<old.expires then return old end
    local real, sleepers=0,0
    for x=cx-8,cx+15 do
        for y=cy-8,cy+15 do
            local tile=cell:getGridSquare(x,y,z)
            if tile and tile:getBuilding()==building then
                local bodies=tile:getStaticMovingObjects()
                local genuineOnTile=false
                local sleeperOnTile=false
                for i=0,bodies:size()-1 do
                    local body=bodies:get(i)
                    if instanceof(body,"IsoDeadBody") then
                        if H.isProxy(body) then
                            H.freezeAge(body)
                            sleepers=sleepers+1
                            sleeperOnTile=true
                        else
                            real=real+1
                            genuineOnTile=true
                        end
                    end
                end
                -- Visual flies only; the native ambient sound has no safe
                -- per-corpse Lua switch and is deliberately not globally muted.
                if sleeperOnTile and not genuineOnTile then tile:setHasFlies(false) end
            end
        end
    end
    if SandboxVars and SandboxVars.ZombieHealthImpact then
        for x=cx-12,cx+12 do
            for y=cy-12,cy+12 do
                local tile=cell:getGridSquare(x,y,z)
                if tile and tile:getBuilding()==building then real=real+tile:getZombieCount() end
            end
        end
    end
    local result={real=real,sleepers=sleepers,cx=cx,cy=cy,z=z,building=building,expires=now+1000}
    cache[player]=result
    return result
end

-- Pure helper also used by the offline regression harness.
function H.sicknessCorrection(before, after, actualRate, multiplier, nativeRate, realRate)
    if nativeRate<=0 or actualRate<=0 or realRate>=nativeRate then return 0 end
    local fraction=math.max(0,math.min(1,1-realRate/nativeRate))
    return math.min(math.max(0,after-before),actualRate*multiplier*fraction)
end

local function update(player)
    if not player then return end
    if not player:isLocal() or player:isDead() or player:isGodMod() then
        samples[player]=nil
        return
    end
    local stats=player:getStats()
    local bodyDamage=player:getBodyDamage()
    local stat=CharacterStat.FOOD_SICKNESS
    local previous=samples[player]
    if previous then
        local after=stats:get(stat)
        local rate=player:getCorpseSicknessRate()
        local correction=H.sicknessCorrection(previous.before,after,rate,previous.multiplier,
            previous.nativeRate,previous.realRate)
        if correction>0 then
            stats:remove(stat,correction)
            player:setCorpseSicknessRate(rate*math.min(1,previous.realRate/previous.nativeRate))
        end
    end
    samples[player]=nil
    if not OS.isEnabled() then return end
    local nativeRate=bodyDamage:GetBaseCorpseSickness()
    if nativeRate<=0 then return end
    local counts=countSources(player)
    if not counts or counts.sleepers==0 then return end
    local realRate=BodyDamage.getSicknessFromCorpsesRate(counts.real)
    if realRate>=nativeRate then return end
    -- OnPlayerUpdate precedes the native BodyDamage.Update. The next event
    -- observes its actual increment, so existing sickness is never erased.
    samples[player]={before=stats:get(stat),nativeRate=nativeRate,realRate=realRate,
        multiplier=getGameTime():getMultiplier()}
end
Events.OnPlayerUpdate.Add(update)
