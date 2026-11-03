ProjectALife = ProjectALife or {}
local Supplies = { requests = {}, cooldownMs = 900000, chance = 15 }
ProjectALife.TalkSupplies = Supplies

function Supplies.handles(intent)
    return intent == "ASK_FOOD" or intent == "ASK_MEDS" or intent == "ASK_WATER"
end

Supplies.petFood = { ["Base.Dogfood"] = true }

function Supplies.sealed(item)
    if item.getOpeningRecipe == nil then return false end
    local recipe = item:getOpeningRecipe()
    return type(recipe) == "string" and recipe ~= ""
end

function Supplies.matches(item, intent)
    if item == nil or item:isEquipped() then return false end
    local category = tostring(item:getDisplayCategory() or "")
    local full = tostring(item:getFullType() or "")
    if intent == "ASK_MEDS" then return category == "FirstAid" or category == "Medical" end
    if intent == "ASK_WATER" then
        if full ~= "Base.WaterBottle" and full ~= "Base.WaterBottleFull" then return false end
        local fluid = item.getFluidContainer ~= nil and item:getFluidContainer() or nil
        if fluid == nil or fluid:isEmpty() or Fluid == nil then return false end
        if fluid:isPureFluid(Fluid.Water) then return true end
        return Fluid.CarbonatedWater ~= nil and fluid:isPureFluid(Fluid.CarbonatedWater)
    end
    if tostring(item:getCategory()) ~= "Food" then return false end
    if Supplies.petFood[full] == true then return false end
    if item.isRotten ~= nil and item:isRotten() then return false end
    if item.isPoison ~= nil and item:isPoison() then return false end
    if item.getPoisonPower ~= nil and (tonumber(item:getPoisonPower()) or 0) > 0 then return false end
    if not Supplies.sealed(item) and (item.getHungerChange == nil or item:getHungerChange() >= 0) then return false end
    return not (item.isDangerousUncooked ~= nil and item:isDangerousUncooked() and not item:isCooked())
end

Supplies.kindOf = { ASK_FOOD = "FOOD", ASK_WATER = "WATER", ASK_MEDS = "MEDS" }

function Supplies.pick(record, shell, player, event)
    local speech, talk, data = ProjectALife.Speech, ProjectALife.Talk, ProjectALife.DialogueData
    if speech == nil or talk == nil or data == nil or type(speech.pick) ~= "function" then return nil end
    data.load()
    local pool = data.barks[event]
    if pool == nil then return nil end
    local context = speech.contextFor(record, player)
    context.stance = talk.stance(record, player)
    local key = speech.playerKey(player)
    local chosen = speech.pick(pool, context, record.uid, key)
    if chosen == nil then return nil end
    speech.remember(record.uid, key, chosen.t)
    return speech.render(chosen.t, nil, shell, context.psex)
end

function Supplies.respond(record, shell, player, intent, now)
    local speech, talk = ProjectALife.Speech, ProjectALife.Talk
    if not speech.authoritative() then return nil, "server_authority_required" end
    local key = speech.playerKey(player)
    if key == nil or talk.inCombat(record) or talk.stance(record, player) == "hostile" then return nil, "refused" end
    local dx, dy = shell:getX() - player:getX(), shell:getY() - player:getY()
    if dx*dx + dy*dy > 36 or math.floor(shell:getZ()) ~= math.floor(player:getZ())
            or not talk.lineOfSight(player, shell) then return nil, "too_far" end
    local m = record.memory or {}
    local group = tostring(m.outpostId or m.groupId or record.uid)
    local requestKey = group .. ":" .. key
    local count = 0
    for id, request in pairs(Supplies.requests) do
        if now - request.atMs >= Supplies.cooldownMs then Supplies.requests[id] = nil else count = count + 1 end
    end
    local previous = Supplies.requests[requestKey]
    local words, reason
    if previous then
        words = previous.uid ~= record.uid
            and (Supplies.pick(record, shell, player, "SUPPLY_ASKED_ELSE")
                or "Didn't you just ask one of ours? Word gets around... we're short too, sorry")
            or (Supplies.pick(record, shell, player, "SUPPLY_ASKED_SELF") or "I heard you, but I can't keep handing stuff out")
        reason = "already_asked"
    else
        if count >= 256 then return nil, "busy" end
        Supplies.requests[requestKey] = { uid = record.uid, atMs = now }
        local source, destination = shell:getInventory(), player:getInventory()
        local chosen
        local chance = talk.stance(record, player) == "friendly" and Supplies.chance or 5
        if source ~= nil and destination ~= nil and ZombRand(100) < chance then
            local items = source:getItems()
            for index = 0, math.min(items:size(), 256) - 1 do
                local item = items:get(index)
                if Supplies.matches(item, intent) then chosen = item; break end
            end
        end
        words, reason = Supplies.pick(record, shell, player, "SUPPLY_NO_" .. tostring(Supplies.kindOf[intent]))
            or "Sorry, nothing to spare, we gotta stretch what we've got", "no_spare"
        if chosen ~= nil and source:getItems():contains(chosen) then
            local label = tostring(chosen:getDisplayName())
            source:Remove(chosen)
            local ok, received = pcall(function() return destination:AddItem(chosen) end)
            if ok and received ~= nil then
                if type(isServer) == "function" and isServer() then
                    sendRemoveItemFromContainer(source, chosen)
                    sendAddItemToContainer(destination, chosen)
                end
                words, reason = (Supplies.pick(record, shell, player, "SUPPLY_GIVE_" .. tostring(Supplies.kindOf[intent]))
                    or "Uhh... fine, take this, it's all I can spare") .. " [Received: " .. label .. "]", "supplied"
            else
                source:AddItem(chosen)
            end
        end
    end
    speech.say(shell, words, {})
    return words, reason
end

return Supplies
