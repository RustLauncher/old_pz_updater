require "ProjectALife/Behaviours/ALifeModuleRegistry"
require "ProjectALife/Loot/ALifeScavenging"

ProjectALife = ProjectALife or {}
local Search = { active = {}, claims = setmetatable({}, { __mode = "k" }),
    metrics = { bodies = 0, items = 0 } }
ProjectALife.ModuleSearch = Search
local Registry = ProjectALife.ModuleRegistry
local Scavenging = ProjectALife.Scavenging

Search.combatStampMs = 1000

function Search.noteCombat(actor, now, persist)
    local memory = actor.memory or {}
    local last = tonumber(memory.searchCombatAtMs) or -1e12

    if now - last > 30000 then
        persist(actor, "searchBodiesLeft", 2)
        persist(actor, "searchZombiesLeft", 1)
    end
    if now < last or now - last >= Search.combatStampMs then
        persist(actor, "searchCombatAtMs", now)
    end
end

function Search.arm(actor, now, persist)
    persist(actor, "searchUntilMs", now + 120000)
end

function Search.eligible(item)
    local ok, eligible = pcall(function()

        if item:IsClothing() or item:getBodyLocation() ~= nil or item:canBeEquipped() ~= nil then return false end
        if type(instanceof) == "function" and instanceof(item, "InventoryContainer") then return false end
        local kind = item:getFullType()
        return kind ~= "Base.BareHands" and kind ~= "Base.Maggots"
    end)
    return ok and eligible == true
end

function Search.selectItems(container, infected)
    local candidates = {}
    pcall(function()
        local items = container:getItems()
        for index = 0, math.min(items:size(), 256) - 1 do
            local item = items:get(index)
            if Search.eligible(item) then
                candidates[#candidates + 1] = { item = item,
                    weapon = item:IsWeapon() == true, index = index }
            end
        end
    end)
    table.sort(candidates, function(a, b)
        if a.weapon ~= b.weapon then return a.weapon end
        return a.index < b.index
    end)
    local limit = math.min(infected and 2 or 8, math.ceil(#candidates * 0.25))
    local selected = {}
    for index = 1, limit do selected[index] = candidates[index].item end
    return selected
end

local function position(object)
    return { x = object:getX(), y = object:getY(), z = object:getZ() }
end

local function distance(a, b)
    return (a.x-b.x)^2 + (a.y-b.y)^2
end

local function release(actor)
    if Search.scans then Search.scans[actor.uid] = nil end
    local active = Search.active[actor.uid]
    if active and active.readyAtMs and ProjectALife.Animations then
        local ok, data = pcall(function() return active.shell:getModData() end)
        local executor = ProjectALife.Executor
        local lease = not (executor and executor.clientAuthority())
            or (executor.executed[actor.uid] and executor.authorityFor(active.shell) == true)
        if lease and ok and data.ProjectALifeUID == actor.uid
                and tonumber(data.ProjectALifeGeneration) == active.generation then
            ProjectALife.Animations.clear(active.shell)
        end
    end
    if active and Search.claims[active.body] and Search.claims[active.body].uid == actor.uid then
        Search.claims[active.body] = nil
    end
    Search.active[actor.uid] = nil
end

function Search.cancel(uid)
    if Search.scans then Search.scans[uid] = nil end
    release({uid=uid})
end

Search.scans = {}
local function findBody(actor, shell, now)
    local here = position(shell)
    if here == nil then Search.scans[actor.uid] = nil; return nil end
    local scan = Search.scans[actor.uid]
    if scan == nil or distance(here, scan.origin) > 16 then
        scan = { origin = here, index = 0 }
        Search.scans[actor.uid] = scan
    end
    local best, bestScore = scan.best, scan.score

    local last = math.min(441, scan.index + 32)
    for cursor = scan.index, last - 1 do
        local dx, dy = math.floor(cursor / 21) - 10, cursor % 21 - 10
        if dx*dx + dy*dy <= 100 then pcall(function()
            local square = getCell():getGridSquare(math.floor(scan.origin.x)+dx, math.floor(scan.origin.y)+dy, math.floor(scan.origin.z))
            local bodies = square and square:getDeadBodys()
            if not bodies then return end
            for index = 0, math.min(bodies:size(), 8)-1 do
                local body = bodies:get(index)
                local data = body:getModData()
                local infected = body:isZombie() and not data.ProjectALifeUID
                local claim = Search.claims[body]
                if not data.ProjectALifeBodySearched and not body:isAnimal()
                        and (not infected or (actor.memory.searchZombiesLeft or 0)>0)
                        and (not claim or now>=claim.untilMs or claim.uid==actor.uid) then
                    local point = position(body)
                    local score = distance(here,point) + (infected and 1000 or 0)
                    if (not bestScore or score<bestScore) and #Search.selectItems(body:getContainer(),infected)>0 then
                        best, bestScore = { body=body,point=point,infected=infected }, score
                    end
                end
            end
        end) end
    end
    scan.index, scan.best, scan.score = last, best, bestScore
    if last < 441 then return nil end
    Search.scans[actor.uid] = nil
    if best then
        local claim = Search.claims[best.body]
        if claim and now < claim.untilMs and claim.uid ~= actor.uid then return nil end
    end
    return best
end

function Search.evaluate(actor, shell, context)
    if type(isClient)=="function" and isClient()
            and not (ProjectALife.Executor ~= nil and ProjectALife.Executor.clientAuthority()) then return nil end
    local memory, now = actor.memory or {}, context.now
    if (tonumber(memory.searchBodiesLeft) or 0)<=0 or now>(tonumber(memory.searchUntilMs) or 0) then
        release(actor); return nil
    end
    local active = Search.active[actor.uid]
    if active and (active.generation~=actor.generation or now>=active.untilMs) then release(actor);active=nil end
    if not active then
        if Search.scans[actor.uid] == nil and now<(tonumber(memory.searchScanAtMs) or 0) then return nil end
        if Search.scans[actor.uid] == nil then context.persistMemory(actor,"searchScanAtMs",now+8000) end
        active = findBody(actor,shell,now)
        if not active then return nil end
        active.untilMs, active.generation, active.shell = now+18000, actor.generation, shell
        Search.active[actor.uid] = active
        Search.claims[active.body] = { uid=actor.uid,untilMs=active.untilMs }
    end
    local here, square, container, data
    local ok = pcall(function()
        here=position(shell);square=active.body:getSquare();container=active.body:getContainer();data=active.body:getModData()
    end)
    if not ok or not square or not container or not data or data.ProjectALifeBodySearched then release(actor);return nil end
    if distance(here,active.point)>2.25 then
        local stand=Scavenging.standPoint(active.point)
        if not stand then release(actor);return nil end
        return context.startMovement(actor,shell,stand,"search_bodies",{timeoutMs=12000,tolerance=1.0})
    end
    local reachable, canReach=pcall(function()
        local from = shell:getCurrentSquare()
        return from ~= nil and from:canReachTo(square)
    end)
    if not reachable or not canReach then release(actor);return nil end
    pcall(function()shell:faceLocationF(active.point.x,active.point.y)end)
    if not active.readyAtMs then
        active.readyAtMs=now+4500
        if ProjectALife.Animations then ProjectALife.Animations.apply(shell,"search_low") end
        context.setActivity(actor,"idle","search_body")
        return {kind="idle",intent="search_body",cooldownUntilMs=active.readyAtMs}
    end
    if now<active.readyAtMs then return {kind="idle",intent="search_body",cooldownUntilMs=active.readyAtMs} end
    local source=tostring(data.ProjectALifeUID or active.body:getObjectIDAsLong())
    local items=Search.selectItems(container,active.infected)

    data.ProjectALifeBodySearched=true
    context.persistMemory(actor,"searchBodiesLeft",math.max(0,memory.searchBodiesLeft-1))
    if active.infected then context.persistMemory(actor,"searchZombiesLeft",0) end
    for _,item in ipairs(items) do
        if #Scavenging.cargo(shell)>=ProjectALife.ShellState.maximumCarriedItems then break end
        local weapons=0
        local inventoryItems=shell:getInventory():getItems()
        for index=0,inventoryItems:size()-1 do
            if inventoryItems:get(index):IsWeapon() then weapons=weapons+1 end
        end
        local room = not item:IsWeapon() or weapons<ProjectALife.ShellState.maximumWeapons
        if room and Scavenging.transfer(shell,{container=container,item=item,x=active.point.x,
                y=active.point.y,z=active.point.z,supplyRun=true}) then
            item:getModData().ProjectALifeRecoveredFrom=source
            item:getModData().ProjectALifeRecoveredItemID=tostring(item:getID())
            Search.metrics.items=Search.metrics.items+1
        end
    end

    Search.metrics.bodies=Search.metrics.bodies+1
    release(actor)
    return {kind="idle",intent="body_searched",cooldownUntilMs=now+1500}
end

Registry.register({
    id = "search",
    label = "Search",
    kind = "upkeep",
    defaultEnabled = true,
    summary = "After combat, search up to two bodies for a bounded share of non-clothing loot.",
    evaluate = Search.evaluate,
})
return Search
