require "ISUI/ISModalDialog"

CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

local function onTameNameApply(_, button, dog, owner)
    if button.internal == "OK" and dog then
        local text = button.parent.entry:getText()
        if text and text ~= "" then
            CD.request("rename", dog, { text = text }, owner)
        end
    end
end

local function cdBreedNoun(args)
    return CD.breedNounFromKey(args and args.breed)
end

local function cdSubject(args)
    local breed = cdBreedNoun(args)
    local name = args and args.name
    if name and name ~= "" then return breed .. " " .. name end
    return breed
end

local function cdSpeciesText(args, key, ...)
    return CD.speciesTextFromKey(args and args.breed, key, ...)
end

local function haloGood(p, txt) if CD.showNotifications() then HaloTextHelper.addGoodText(p, txt) end end
local function haloBad(p, txt) if CD.showNotifications() then HaloTextHelper.addBadText(p, txt) end end
local function haloInfo(p, txt) if CD.showNotifications() then HaloTextHelper.addText(p, txt) end end

local function notifyState(player, args, command)
    if command == "tamed" then
        haloGood(player, getText("IGUI_PD_Tamed", cdSubject(args)))
        local dog = (args and args.animal) or getAnimal(tonumber(args and args.id))
        if dog then
            local modal = ISTextBox:new(0, 0, 290, 180, getText("IGUI_PD_NameTitle"),
                "", nil, onTameNameApply, player:getPlayerNum(), dog, player)
            modal:initialise()
            modal:addToUIManager()
        end
    elseif command == "trust" then
        local progress = ""
        if args and args.trust and args.max then
            progress = " " .. tostring(args.trust) .. "/" .. tostring(args.max)
        end
        haloInfo(player, getText("IGUI_PD_Trust", cdSubject(args)) .. progress)
    elseif command == "fed" then
        haloGood(player, getText("IGUI_PD_Fed", cdSubject(args)))
    elseif command == "goingtomate" then
        haloInfo(player, getText("IGUI_PD_GoingToMate", (args and args.name) or ""))
    elseif command == "bred" then
        haloGood(player, getText("IGUI_PD_Bred", (args and args.name) or ""))
    elseif command == "whelped" then
        haloGood(player, getText("IGUI_PD_Whelped", (args and args.name) or ""))
    elseif command == "matured" then
        haloGood(player, getText("IGUI_PD_Matured", (args and args.name) or ""))
    elseif command == "sick" then
        haloBad(player, getText("IGUI_PD_Sick", cdSubject(args)))
    elseif command == "weak" then
        haloBad(player, getText("IGUI_PD_Weak", cdSubject(args)))
    elseif command == "vetwound" then
        haloBad(player, getText("IGUI_PD_VetWound", cdSubject(args)))
    elseif command == "vetinfected" then
        haloBad(player, getText("IGUI_PD_VetInfected", cdSubject(args)))
    elseif command == "vetfracture" then
        haloBad(player, getText("IGUI_PD_VetFracture", cdSubject(args)))
    elseif command == "vethealed" then
        haloGood(player, getText("IGUI_PD_VetHealed", cdSubject(args)))
    elseif command == "vetbleedstopped" then
        haloGood(player, getText("IGUI_PD_VetBleedStopped", cdSubject(args)))
    elseif command == "vettreated" then
        haloGood(player, getText("IGUI_PD_VetTreated", cdSubject(args)))
    elseif command == "vetalready" then
        haloInfo(player, getText("IGUI_PD_VetAlready", cdSubject(args)))
    elseif command == "vetnothing" then
        haloInfo(player, getText("IGUI_PD_VetNothing", cdSubject(args)))
    elseif command == "vetneedsterile" then
        haloBad(player, getText("IGUI_PD_VetNeedSterile", cdSubject(args)))
    elseif command == "vetneedcalm" then
        haloBad(player, getText("IGUI_PD_VetNeedCalm", cdSubject(args)))
    elseif command == "vetsprain" then
        haloBad(player, getText("IGUI_PD_VetSprain", cdSubject(args)))
    elseif command == "vetfever" then
        haloBad(player, getText("IGUI_PD_VetFever", cdSubject(args)))
    elseif command == "vetcritical" then
        haloBad(player, getText("IGUI_PD_VetCritical", cdSubject(args)))
    elseif command == "vetdying" then
        haloBad(player, getText("IGUI_PD_VetDying", cdSubject(args)))
    elseif command == "vetrecovered" then
        haloGood(player, getText("IGUI_PD_VetRecovered", cdSubject(args)))
    elseif command == "vetgastro" then
        haloBad(player, getText("IGUI_PD_VetGastro", cdSubject(args)))
    elseif command == "vetgastrohealed" then
        haloGood(player, getText("IGUI_PD_VetGastroHealed", cdSubject(args)))
    elseif command == "vetworms" then
        haloBad(player, getText("IGUI_PD_VetWorms", cdSubject(args)))
    elseif command == "vetdewormgiven" then
        haloGood(player, getText("IGUI_PD_VetDewormGiven", cdSubject(args)))
    elseif command == "vetmedicated" then
        haloGood(player, getText("IGUI_PD_VetMedicated", cdSubject(args)))
    elseif command == "vetflu" then
        haloBad(player, getText("IGUI_PD_VetFlu", cdSubject(args)))
    elseif command == "vetflucured" then
        haloGood(player, getText("IGUI_PD_VetFluCured", cdSubject(args)))
    elseif command == "vetheartworm" then
        haloBad(player, getText("IGUI_PD_VetHeartworm", cdSubject(args)))
    elseif command == "vetheartwormcured" then
        haloGood(player, getText("IGUI_PD_VetHeartwormCured", cdSubject(args)))
    elseif command == "vetallergy" then
        haloBad(player, getText("IGUI_PD_VetAllergy", cdSubject(args)))
    elseif command == "vetallergen" then
        haloBad(player, getText("IGUI_PD_VetAllergen", cdSubject(args),
            getText("IGUI_PD_VetProtein_" .. tostring(args.protein))))
    elseif command == "vetallergycured" then
        haloGood(player, getText("IGUI_PD_VetAllergyCured", cdSubject(args)))
    elseif command == "vetfleas" then
        haloBad(player, getText("IGUI_PD_VetFleas", cdSubject(args)))
    elseif command == "vetticks" then
        haloBad(player, getText("IGUI_PD_VetTicks", cdSubject(args)))
    elseif command == "vetinfestcured" then
        haloGood(player, getText("IGUI_PD_VetInfestCured", cdSubject(args)))
    elseif command == "vetdewormed" then
        haloGood(player, getText("IGUI_PD_VetDewormed", cdSubject(args)))
    elseif command == "vetserum" then
        haloGood(player, getText("IGUI_PD_VetSerum", cdSubject(args)))
    elseif command == "vetvaccinated" then
        haloGood(player, getText("IGUI_PD_VetVaccinated", cdSubject(args)))
    elseif command == "vetgrass" then
        haloGood(player, getText("IGUI_PD_VetGrass", cdSubject(args)))
    elseif command == "vetabxgiven" then
        haloGood(player, getText("IGUI_PD_VetAbxGiven", cdSubject(args)))
    elseif command == "vetabxhuman" then
        haloGood(player, getText("IGUI_PD_VetAbxHuman", cdSubject(args)))
    elseif command == "vetabxfailed" then
        haloBad(player, getText("IGUI_PD_VetAbxFailed", cdSubject(args)))
    elseif command == "vetnoinfection" then
        haloInfo(player, getText("IGUI_PD_VetNoInfection", cdSubject(args)))
    elseif command == "vetabxlate" then
        haloBad(player, getText("IGUI_PD_VetAbxLate", cdSubject(args)))
    elseif command == "vetalreadyimmune" then
        haloInfo(player, getText("IGUI_PD_VetAlreadyImmune", cdSubject(args)))
    elseif command == "vetnoneed" then
        haloInfo(player, getText("IGUI_PD_VetNoNeed", cdSubject(args)))
    elseif command == "vetundressed" then
        haloInfo(player, getText("IGUI_PD_VetUndressed", cdSubject(args)))
    elseif command == "vetbathed" then
        haloGood(player, getText("IGUI_PD_VetBathed", cdSubject(args)))
    elseif command == "vetbathkit" then
        haloInfo(player, getText("IGUI_PD_VetBathNeed"))
    elseif command == "vettweezers" then
        haloGood(player, getText("IGUI_PD_VetTweezersDone", cdSubject(args)))
    elseif command == "watered" then
        haloGood(player, getText("IGUI_PD_Watered", cdSubject(args)))
    elseif command == "bagequipped" then
        haloGood(player, getText("IGUI_PD_BagEquipped"))
    elseif command == "bagunequipped" then
        haloGood(player, getText("IGUI_PD_BagUnequipped"))
    elseif command == "bagalready" then
        haloBad(player, getText("IGUI_PD_BagAlready"))
    elseif command == "bagfull" then
        haloBad(player, getText("IGUI_PD_BagFull"))
    elseif command == "baglive" then
        haloBad(player, getText("IGUI_PD_BagLive"))
    elseif command == "bagdata" then
        if CD.BagWindow and CD.BagWindow.onData then
            CD.BagWindow.onData(args)
        end
    elseif command == "dishplaced" then
        haloGood(player, getText("IGUI_PD_DishPlaced"))
    elseif command == "dishnospace" then
        haloBad(player, getText("IGUI_PD_DishNoSpace"))
    elseif command == "dishfilled" then
        haloGood(player, getText("IGUI_PD_DishFilled"))
    elseif command == "dishwatered" then
        haloGood(player, getText("IGUI_PD_DishWatered"))
    elseif command == "dishfull" then
        haloBad(player, getText("IGUI_PD_DishFull"))
    elseif command == "dishgone" then
        haloBad(player, getText("IGUI_PD_DishGone"))
    elseif command == "dishnowater" then
        haloBad(player, getText("IGUI_PD_DishNoWater"))
    elseif command == "dishhaswater" then
        haloBad(player, getText("IGUI_PD_BowlHasWater"))
    elseif command == "dishhasfood" then
        haloBad(player, getText("IGUI_PD_BowlHasFood"))
    elseif command == "dishemptied" then
        haloGood(player, getText("IGUI_PD_BowlEmptied"))
    else
        return false
    end
    return true
end

local function notifyCombat(player, args, command)
    if command == "teleported" then
        haloGood(player, getText("IGUI_PD_Teleported", cdSubject(args)))
    elseif command == "wounded" then
        haloBad(player, getText("IGUI_PD_Wounded", cdSubject(args)))
    elseif command == "woundedcritical" then
        haloBad(player, getText("IGUI_PD_WoundedCritical", cdSubject(args)))
    elseif command == "recovered" then
        haloGood(player, getText("IGUI_PD_Recovered", cdSubject(args)))
    elseif command == "panic" then
        haloBad(player, getText("IGUI_PD_PanicWarn", cdSubject(args)))
    elseif command == "petted" then
        if CD.bondingEnabled() then
            CD.relieveMood(player, CD.petMoodRelief())
        end
        haloGood(player, getText("IGUI_PD_Petted", cdSubject(args)))
    elseif command == "petcooldown" then
        haloInfo(player, getText("IGUI_PD_PetCooldown", cdSubject(args)))
    elseif command == "attacking" then
        haloGood(player, getText("IGUI_PD_Attacking", cdSubject(args)))
    elseif command == "notarget" then
        haloInfo(player, getText("IGUI_PD_NoTarget", cdSubject(args)))
    elseif command == "refused" then
        local reason = args and args.reason
        local key = "IGUI_PD_Refused_disloyal"
        if reason == "panicked" then key = "IGUI_PD_Refused_panicked"
        elseif reason == "wounded" then key = "IGUI_PD_Refused_wounded"
        elseif reason == "bleeding" then key = "IGUI_PD_Refused_bleeding"
        elseif reason == "critical" then key = "IGUI_PD_Refused_critical"
        elseif reason == "sick" then key = "IGUI_PD_Refused_sick"
        elseif reason == "lame" then key = "IGUI_PD_Refused_lame"
        elseif reason == "invehicle" then key = "IGUI_PD_Refused_invehicle"
        elseif reason == "carried" then key = "IGUI_PD_Refused_carried"
        elseif reason == "nodata" then key = "IGUI_PD_Refused_nodata"
        elseif reason == "recallcd" then key = "IGUI_PD_Refused_recallcd"
        elseif reason == "distracted" then key = "IGUI_PD_Refused_distracted" end
        haloBad(player, cdSpeciesText(args, key, cdSubject(args)))
    elseif command == "lost" then
        haloBad(player, cdSpeciesText(args, "IGUI_PD_DogLost", cdSubject(args)))
    elseif command == "warn" then
        local kind = args and args.kind
        local key = "IGUI_PD_Hungry"
        if kind == "thirsty" then key = "IGUI_PD_Thirsty"
        elseif kind == "disloyal" then key = "IGUI_PD_Disloyal"
        elseif kind == "refused" then key = "IGUI_PD_Ignored" end
        haloBad(player, getText(key, cdSubject(args)))
    elseif command == "alert" then
        local tier = args and args.tier
        if tier == "group" then
            haloBad(player, cdSpeciesText(args, "IGUI_PD_AlertGroup", cdSubject(args)))
        elseif tier == "close" then
            haloBad(player, getText("IGUI_PD_AlertClose", cdSubject(args)))
        elseif tier == "far" then
            haloInfo(player, getText("IGUI_PD_AlertFar", cdSubject(args)))
        else
            haloInfo(player, getText("IGUI_PD_AlertNear", cdSubject(args)))
        end
    elseif command == "selected" then
        haloGood(player, getText("IGUI_PD_Selected", cdSubject(args)))
    elseif command == "dismissed" then
        haloInfo(player, getText("IGUI_PD_Dismissed", cdSubject(args)))
    elseif command == "inherited" then
        haloGood(player, getText("IGUI_PD_Inherited", cdSubject(args)))
    elseif command == "limitreached" then
        haloBad(player, getText("IGUI_PD_FeedLimit", tostring(args and args.max or 0)))
    elseif command == "notyourdog" then
        haloBad(player, getText("IGUI_PD_NotYourDog", CD.speciesNounFromKey(args and args.breed)))
    elseif command == "released" then
        local name = (args and args.name) or getText("IGUI_PD_DogDefaultName")
        haloGood(player, getText("IGUI_PD_Released", name))
        local open = ISCDStatusWindow.instanceFor(player)
        if open then
            open:close()
        end
    elseif command == "died" then
        haloBad(player, getText("IGUI_PD_Died", cdSubject(args)))
    elseif command == "spawnsreset" then
        haloGood(player, getText("IGUI_PD_SpawnsReset", tostring(args and args.count or 0)))
    elseif command == "debugmsg" then
        haloInfo(player, tostring(args and args.text or ""))
        CD.log("[CD-DEBUG] " .. tostring(args and args.text or ""))
    else
        return false
    end
    return true
end

local function notifyHunt(player, args, command)
    if command == "huntmode" then
        local on = args and args.on
        haloInfo(player, getText(on and "IGUI_PD_HuntModeOnMsg" or "IGUI_PD_HuntModeOffMsg", cdSubject(args)))
    elseif command == "huntpoint" then
        haloInfo(player, getText("IGUI_PD_HuntPoint", cdSubject(args)))
    elseif command == "caremode" then
        local on = args and args.on
        haloInfo(player, getText(on and "IGUI_PD_CareOnMsg" or "IGUI_PD_CareOffMsg", cdSubject(args)))
    elseif command == "carenopen" then
        haloBad(player, getText("IGUI_PD_CareNoPen", cdSubject(args)))
    elseif command == "carealert" then
        local kind = args and args.kind
        haloBad(player, getText(kind == "stress" and "IGUI_PD_CareAlertStress" or "IGUI_PD_CareAlertZombie", cdSubject(args)))
    elseif command == "carecoop" then
        local act = args and args.act
        haloInfo(player, getText(act == "open" and "IGUI_PD_CareCoopOpen" or "IGUI_PD_CareCoopShut", cdSubject(args)))
    elseif command == "dogzombiekill" then
        player:setZombieKills(player:getZombieKills() + 1)
    elseif command == "huntkill" then
        haloGood(player, getText("IGUI_PD_HuntKill", cdSubject(args)))
    elseif command == "huntdelivered" then
        haloGood(player, getText("IGUI_PD_HuntDelivered", cdSubject(args)))
    elseif command == "huntwoundeddeer" then
        haloInfo(player, getText("IGUI_PD_HuntWoundedDeer", cdSubject(args)))
    elseif command == "hunttrackwounded" then
        haloInfo(player, getText("IGUI_PD_HuntTrackWounded", cdSubject(args)))
    elseif command == "foragefound" then
        haloInfo(player, getText("IGUI_PD_ForageFound", cdSubject(args)))
    else
        return false
    end
    return true
end

local function notifyTrick(player, args, command)
    if command == "tricklocked" then
        haloBad(player, getText("IGUI_PD_TrickLockedHalo", cdSubject(args), tostring(args and args.level or 0)))
    elseif command == "trickcooldown" then
        haloInfo(player, getText("IGUI_PD_TrickCooldown", cdSubject(args)))
    elseif command == "trickdistract" then
        haloGood(player, cdSpeciesText(args, "IGUI_PD_TrickDistractDone", cdSubject(args)))
    elseif command == "trickgoto" then
        haloGood(player, getText("IGUI_PD_TrickGotoSent", cdSubject(args)))
    elseif command == "trickgotodone" then
        haloGood(player, getText("IGUI_PD_TrickGotoArrived", cdSubject(args)))
    elseif command == "trickgotofail" then
        haloBad(player, getText("IGUI_PD_TrickGotoFail", cdSubject(args)))
    elseif command == "trickgotofar" then
        haloBad(player, getText("IGUI_PD_TrickGotoFar", cdSubject(args)))
    elseif command == "trickgotobad" then
        haloBad(player, getText("IGUI_PD_TrickGotoBad", cdSubject(args)))
    elseif command == "tricksniff" then
        haloGood(player, getText("IGUI_PD_TrickSniffDone", cdSubject(args), tostring(args and args.item or "?")))
    elseif command == "sniffnoitem" then
        haloBad(player, cdSpeciesText(args, "IGUI_PD_TrickSniffNoItem"))
    elseif command == "sniffstopped" then
        haloInfo(player, getText("IGUI_PD_SniffStopped", cdSubject(args)))
    elseif command == "sniffnear" then
        haloInfo(player, getText("IGUI_PD_SniffNear", cdSubject(args), tostring(args and args.item or "?")))
    elseif command == "sniffat" then
        haloGood(player, getText("IGUI_PD_SniffAt", cdSubject(args), tostring(args and args.item or "?")))
    elseif command == "trickfetcharmed" then
        haloGood(player, getText("IGUI_PD_TrickFetchArmed", cdSubject(args), tostring(args and args.item or "?")))
    elseif command == "trickfetchheavy" then
        haloBad(player, getText("IGUI_PD_TrickFetchHeavy", cdSubject(args), tostring(args and args.item or "?")))
    elseif command == "trickfetchunknown" then
        haloBad(player, getText("IGUI_PD_TrickFetchUnknown", cdSubject(args), tostring(args and args.item or "?")))
    elseif command == "trickfetchslept" then
        haloGood(player, getText("IGUI_PD_TrickFetchSlept", cdSubject(args), tostring(args and args.item or "?")))
    elseif command == "trickfetchnone" then
        haloBad(player, getText("IGUI_PD_TrickFetchNone", cdSubject(args), tostring(args and args.item or "?")))
    elseif command == "trickfetchnoitem" then
        haloBad(player, cdSpeciesText(args, "IGUI_PD_TrickFetchNoItem"))
    elseif command == "fetchstopped" then
        haloInfo(player, getText("IGUI_PD_FetchStopped", cdSubject(args)))
    else
        return false
    end
    return true
end

---Handles a notification command for a local player, mostly halo texts; unknown commands are ignored.
---@param command string
---@param args table|nil payload of the command
---@param owner IsoPlayer|nil local player it is addressed to; getPlayer() when nil
function CD.clientNotify(command, args, owner)
    local player = owner or getPlayer()
    if not player then return end
    if CD.DEBUG_NOTIFY then
        CD.log(string.format("[CD-NOTIFY] recebi '%s' halos=%s item=%s",
            tostring(command), CD.showNotifications() and "on" or "OFF",
            tostring(args and args.item or "-")))
    end
    if notifyState(player, args, command) then return end
    if notifyCombat(player, args, command) then return end
    if notifyHunt(player, args, command) then return end
    if notifyTrick(player, args, command) then return end
end

local function argAnimal(args)
    if args.__animal then return args.__animal end
    return getAnimal(tonumber(args.id))
end

---Removes this client's copy of a despawned animal, including a copy orphaned in the cell list.
---@param args table server payload { id }
function CD.onDespawn(args)
    if not isClient() or not args then return end
    local id = tonumber(args.id)
    if id == nil then return end
    local a = getAnimal(id)
    if CD.DEBUG_DESPAWN then
        CD.log(string.format("[CD-DESPAWN] cli recebeu id=%s getAnimal=%s", tostring(id), tostring(a ~= nil)))
    end
    if a then
        CD.releaseAnimalSounds(a)
        removeAnimal(id)
        return
    end
    -- Copia que sobrou no objectList da cell sem estar no AnimalInstanceManager: a engine nunca mais a toca.
    local cell = getCell()
    local list = cell and cell:getAnimals()
    if not list then return end
    for i = list:size() - 1, 0, -1 do
        local o = list:get(i)
        if o and o:getOnlineID() == id then
            if CD.DEBUG_DESPAWN then
                CD.log("[CD-DESPAWN] cli apagando copia orfa id=" .. tostring(id))
            end
            CD.releaseAnimalSounds(o)
            o:delete()
        end
    end
end

-- cao no objectList cujo id n resolve de volta para ele proprio esta fora da camada de sync:
-- n recebe update nem delete, fica congelado até o chunk descarregar. Duas passadas seguidas confirmam.
local orphanSeen = {}
local orphanTick = 0
local function tickOrphanDogs()
    orphanTick = orphanTick + 1
    if orphanTick < 120 then return end
    orphanTick = 0
    local dogs = CD.regDogs()
    local now = {}
    for i = 1, #dogs do
        local a = dogs[i]
        local id = a:getOnlineID()
        if id ~= -1 and getAnimal(id) ~= a then
            now[id] = true
            if orphanSeen[id] then
                if CD.DEBUG_DESPAWN then
                    CD.log(string.format("[CD-DESPAWN] cli orfao id=%s nome=%s pos(%.1f,%.1f) getAnimal=%s",
                        tostring(id), tostring(CD.data(a).name), a:getX(), a:getY(), tostring(getAnimal(id) ~= nil)))
                end
                CD.releaseAnimalSounds(a)
                a:delete()
            end
        end
    end
    orphanSeen = now
end


local soundSeenMs = {}
local SOUND_DUP_MS = 120

-- Em tela dividida os dois jogadores locais dividem UMA conexao, entao o servidor manda um pacote por
-- jogador no alcance e o mesmo som chegaria dobrado (evento de banco nao tem maxInstancesPerEmitter).
---@param args table server payload { id, sound }
function CD.playDogSound(args)
    if not args or not args.id or not args.sound then return end
    local animal = argAnimal(args)
    if not animal then return end
    local key = tostring(args.id) .. "|" .. tostring(args.sound)
    local now = getTimestampMs()
    local last = soundSeenMs[key]
    if last and (now - last) < SOUND_DUP_MS then return end
    soundSeenMs[key] = now
    CD.playAnimalSound(animal, args.sound)
end

---@param args table server payload { id, sound }
function CD.stopDogSound(args)
    if not args or not args.id or not args.sound then return end
    local animal = argAnimal(args)
    if animal then
        CD.stopAnimalSound(animal, args.sound)
    end
end

---Sets the variable to tostring(value) when a value comes, else to the boolean on.
---@param args table server payload { id, var, value or on }
function CD.setDogAnimVar(args)
    if not args or not args.id or not args.var then return end
    local animal = argAnimal(args)
    if animal then
        if args.value ~= nil then
            animal:setVariable(args.var, tostring(args.value))
        else
            animal:setVariable(args.var, args.on and true or false)
        end
    end
end

CD.dishStock = CD.dishStock or {}
---Key of CD.dishStock: the tile, plus the dish item id when known.
---@param x number
---@param y number
---@param z number
---@param id number|nil dish item id
---@return string
---@nodiscard
function CD.dishStockKey(x, y, z, id)
    local key = tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
    if id then
        key = key .. "#" .. tostring(id)
    end
    return key
end
---Caches the stock the server reports for a dish and copies it onto the dish item lying on that tile.
---@param args table server payload { x, y, z, id, food, water }
function CD.cacheDishStock(args)
    if not args or args.x == nil then return end
    local id = tonumber(args.id)
    CD.dishStock[CD.dishStockKey(args.x, args.y, args.z, id)] = { food = args.food or 0, water = args.water or 0 }
    local sq = getCell() and getCell():getGridSquare(args.x, args.y, args.z)
    local wobs = sq and sq:getWorldObjects()
    if not wobs then return end
    local target
    for i = 0, wobs:size() - 1 do
        local wo = wobs:get(i)
        local item = wo:getItem()
        if item and CD.isDishType(item:getFullType()) then
            if not id then
                target = item
                break
            end
            if item:getID() == id then
                target = item
                break
            end
        end
    end
    if not target then return end
    local md = target:getModData()
    md.cdFoodMeals = args.food or 0
    md.cdWater = args.water or 0
    CD.refreshDishModel(target, true)
end

local pendingAttackClear = {}

local function clearAttackVars(animal)
    if not animal then return end
    local vars = CD.ATTACK_ANIM_VARS or { CD.ATTACK_ANIM_VAR }
    for i = 1, #vars do
        animal:setVariable(vars[i], false)
    end
end

---Raises the attack anim variable for ATTACK_ANIM_MS; var defaults to ATTACK_ANIM_VAR.
---@param args table server payload { id, var }
function CD.playDogAttack(args)
    if not args or not args.id then return end
    local animal = argAnimal(args)
    if not animal then return end
    local var = args.var or CD.ATTACK_ANIM_VAR
    clearAttackVars(animal)
    animal:setVariable(var, true)
    pendingAttackClear[animal:getOnlineID()] = { animal = animal, deadlineMs = getTimestampMs() + CD.ATTACK_ANIM_MS }
end

local function processAttackClears()
    local now
    for id, e in pairs(pendingAttackClear) do
        now = now or getTimestampMs()
        if now >= e.deadlineMs then
            pendingAttackClear[id] = nil
            clearAttackVars(e.animal)
        end
    end
end

---Knocks down the live zombie closest to the point, within 1.5 tiles.
---@param args table server payload { zx, zy, zz }
function CD.knockdownZombie(args)
    if not args or not args.zx then return end
    local cell = getCell()
    if not cell then return end
    local zx, zy = args.zx, args.zy
    local ax, ay, az = math.floor(zx), math.floor(zy), math.floor(args.zz or 0)
    local best, bestDist = nil, 1.5
    for dx = -2, 2 do
        for dy = -2, 2 do
            local sq = cell:getGridSquare(ax + dx, ay + dy, az)
            local mo = sq and sq:getMovingObjects()
            if mo then
                for i = 0, mo:size() - 1 do
                    local o = mo:get(i)
                    if instanceof(o, "IsoZombie") and not o:isDead() and not CD.isFriendlyNPC(o) then
                        local ddx, ddy = o:getX() - zx, o:getY() - zy
                        local dist = math.sqrt(ddx * ddx + ddy * ddy)
                        if dist <= bestDist then
                            best, bestDist = o, dist
                        end
                    end
                end
            end
        end
    end
    if best then
        CD.applyKnockdown(best)
    end
end

---Kills the zombie with that online id within 5 tiles of the point, then acks the server with the outcome.
---@param args table server payload { id, zx, zy, zz }
function CD.killZombie(args)
    if not args or not args.zx or not args.id then return end
    local cell = getCell()
    if not cell then return end
    local zx, zy = args.zx, args.zy
    local ax, ay, az = math.floor(zx), math.floor(zy), math.floor(args.zz or 0)
    local target = nil
    local sqSeen, nearO, nearD = 0, nil, 9999
    for dx = -5, 5 do
        for dy = -5, 5 do
            local sq = cell:getGridSquare(ax + dx, ay + dy, az)
            local mo = sq and sq:getMovingObjects()
            if sq then
                sqSeen = sqSeen + 1
            end
            if mo then
                for i = 0, mo:size() - 1 do
                    local o = mo:get(i)
                    if instanceof(o, "IsoZombie") and not CD.isFriendlyNPC(o) then
                        if CD.DMG_DEBUG and not o:isDead() then
                            local dd = math.abs(o:getX() - zx) + math.abs(o:getY() - zy)
                            if dd < nearD then
                                nearD, nearO = dd, o
                            end
                        end
                        if o:getOnlineID() == args.id then
                            target = o
                            break
                        end
                    end
                end
            end
            if target and not CD.DMG_DEBUG then break end
        end
        if target and not CD.DMG_DEBUG then break end
    end
    local already = false
    if target then
        already = target:isDead()
        if not already then
            target:setHealth(0)
            target:Kill(getPlayer())
        end
    end
    CD.request("killzombieack", nil, {
        id = args.id, ok = target ~= nil,
        motivo = (target and (already and "ja-morto" or "-")) or (sqSeen == 0 and "sem-celula" or "id-nao-bate"),
    })
    if CD.DMG_DEBUG then
        if nearO then
            CD.log(string.format("[CD-DMG] cli killzombie z=%s ponto=(%.1f,%.1f,%d) achou=%s dist=%.2f sq=%d maisPerto=%s@%.2f",
                tostring(args.id), zx, zy, az, target and "S" or "N",
                target and (math.abs(target:getX() - zx) + math.abs(target:getY() - zy)) or -1,
                sqSeen, nearO and tostring(nearO:getOnlineID()) or "-", nearO and nearD or -1))
        end
    end
end

local SHOOTABLE_THROTTLE = 15
local shootableTick = 0
local function cdClearShootable(a) a:setShootable(false) end
local function clearCompanionShootable()
    shootableTick = shootableTick + 1
    if shootableTick < SHOOTABLE_THROTTLE then return end
    shootableTick = 0
    local comps = CD.regCompanions()
    for i = 1, #comps do
        cdClearShootable(comps[i])
    end
end

-- A flag de queda que o servidor poe no cao nao vai pela rede, e a copia do client cai sozinha:
-- pousar de 1,5 tile ou mais e o NPE do addHole, que no client derruba o jogador do servidor.
local FALL_FLAG_MEMO_MS = 30000
local fallFlagMemo = {}
local fallFlagTick = 0
local fallFlagClearMs = 0
local function fallFlagSweep()
    local now = getTimestampMs()
    if now >= fallFlagClearMs then
        fallFlagClearMs = now + FALL_FLAG_MEMO_MS
        fallFlagMemo = {}
    end
    local dogs = CD.regDogs()
    CD.perfCount("fallguard.check", #dogs)
    for i = 1, #dogs do
        local a = dogs[i]
        if not fallFlagMemo[a] then
            CD.perfCount("fallguard.miss")
            if not a:isDead() then
                fallFlagMemo[a] = true
                CD.suppressFallFlag(a)
            end
        end
    end
end
local function tickFallFlagClient()
    fallFlagTick = fallFlagTick + 1
    if fallFlagTick < CD.DOG_REG_TICKS then return end
    fallFlagTick = 0
    CD.pz("cli.fallguard", fallFlagSweep)
end

local lastWeapon, lastWeaponRanged = nil, false
local function isFirearmThreat(player)
    if not player then return false end
    local w = player:getPrimaryHandItem()
    if w == nil then
        lastWeapon = nil
        lastWeaponRanged = false
        return false
    end
    if w ~= lastWeapon then
        lastWeapon = w
        lastWeaponRanged = instanceof(w, "HandWeapon") and w:isRanged()
    end
    if not lastWeaponRanged then return false end
    return player:isAiming()
        or player:isAttacking()
        or player:isPerformingHostileAnimation()
end

local GUN_GUARD_REFRESH = 15
local GUN_HINT_RADIUS = 30
local gunGuardTick = 0
local clientGunGuarded = {}
local nearDogs, nearIds, nearCount = {}, {}, 0
local hintDogNear = false
local dogsBuiltTick = -1000
local AIM_HINT_SEND_INTERVAL = 45
local aimHintSendTick = 1000

local function rebuildNearDogs(player)
    nearCount = 0
    hintDogNear = false
    local comps = CD.regCompanions()
    local px, py = player:getX(), player:getY()
    local R = CD.GUN_RISK_RADIUS
    local R2, H2 = R * R, GUN_HINT_RADIUS * GUN_HINT_RADIUS
    for i = 1, #comps do
        local a = comps[i]
        local dx, dy = a:getX() - px, a:getY() - py
        local d2 = dx * dx + dy * dy
        if d2 <= H2 then
            hintDogNear = true
        end
        if d2 <= R2 then
            nearCount = nearCount + 1
            nearDogs[nearCount], nearIds[nearCount] = a, a:getOnlineID()
        end
    end
end

local function releaseClientGunGuarded()
    for id, a in pairs(clientGunGuarded) do
        if a then
            a:setInvulnerable(false)
        end
        clientGunGuarded[id] = nil
    end
end
local function tickGunGuardClient()
    gunGuardTick = gunGuardTick + 1
    local player = getPlayer()
    if not player or not isFirearmThreat(player) then
        releaseClientGunGuarded()
        aimHintSendTick = 1000
        return
    end
    if gunGuardTick - dogsBuiltTick >= GUN_GUARD_REFRESH then
        dogsBuiltTick = gunGuardTick
        rebuildNearDogs(player)
        for id, a in pairs(clientGunGuarded) do
            local still = false
            for j = 1, nearCount do
                if nearIds[j] == id then
                    still = true
                    break
                end
            end
            if not still then
                if a then
                    a:setInvulnerable(false)
                end
                clientGunGuarded[id] = nil
            end
        end
    end
    for j = 1, nearCount do
        local a, id = nearDogs[j], nearIds[j]
        clientGunGuarded[id] = a
        a:setInvulnerable(true)
    end
    if hintDogNear then
        aimHintSendTick = aimHintSendTick + 1
        if aimHintSendTick >= AIM_HINT_SEND_INTERVAL then
            aimHintSendTick = 0
            CD.request("aimhint")
        end
    end
end

local WILD_BARK_THROTTLE = 30
local wildBarkTick = 0
local wildBarkNext = {}
local function tickWildDogBark()
    if not CD.WILD_BARK_ENABLED then return end
    wildBarkTick = wildBarkTick + 1
    if wildBarkTick < WILD_BARK_THROTTLE then return end
    wildBarkTick = 0
    local strays = CD.regStrays()
    local now = getTimestampMs()
    local seen
    for i = 1, #strays do
        local a = strays[i]
        if not a:isDead() then
            local id = a:getOnlineID()
            seen = seen or {}
            seen[id] = true
            local nextMs = wildBarkNext[id]
            if nextMs == nil then
                wildBarkNext[id] = now + ZombRand(CD.WILD_BARK_MIN_SEC, CD.WILD_BARK_MAX_SEC + 1) * 1000
            elseif now >= nextMs then
                if CD.nearAnyLocalPlayer(a, CD.WILD_BARK_RADIUS) then
                    CD.playAnimalSound(a, CD.breedVoice(a, "wildbark"))
                end
                wildBarkNext[id] = now + ZombRand(CD.WILD_BARK_MIN_SEC, CD.WILD_BARK_MAX_SEC + 1) * 1000
            end
        end
    end
    for id in pairs(wildBarkNext) do
        if not (seen and seen[id]) then
            wildBarkNext[id] = nil
        end
    end
end

local IDLE_VOICE_THROTTLE = 30
local idleVoiceTick = 0
local idleVoiceNext = {}
local function tickDogIdleVoice()
    if not CD.IDLE_VOICE_ENABLED then return end
    idleVoiceTick = idleVoiceTick + 1
    if idleVoiceTick < IDLE_VOICE_THROTTLE then return end
    idleVoiceTick = 0
    local dogs = CD.IDLE_VOICE_STRAYS and CD.regDogs() or CD.regCompanions()
    local now = getTimestampMs()
    local seen
    for i = 1, #dogs do
        local a = dogs[i]
        if not a:isDead() then
            local id = a:getOnlineID()
            seen = seen or {}
            seen[id] = true
            local nextMs = idleVoiceNext[id]
            if nextMs == nil then
                idleVoiceNext[id] = now + ZombRand(CD.IDLE_VOICE_MIN_SEC, CD.IDLE_VOICE_MAX_SEC + 1) * 1000
            elseif now >= nextMs then
                if CD.nearAnyLocalPlayer(a, CD.IDLE_VOICE_RADIUS) then
                    CD.playAnimalSound(a, CD.breedVoice(a, "idle"))
                end
                idleVoiceNext[id] = now + ZombRand(CD.IDLE_VOICE_MIN_SEC, CD.IDLE_VOICE_MAX_SEC + 1) * 1000
            end
        end
    end
    for id in pairs(idleVoiceNext) do
        if not (seen and seen[id]) then
            idleVoiceNext[id] = nil
        end
    end
end

local EAT_FOLEY_KILL_THROTTLE = 5
local eatFoleyKillTick = 0
local function tickEatFoleyKill()
    eatFoleyKillTick = eatFoleyKillTick + 1
    if eatFoleyKillTick < EAT_FOLEY_KILL_THROTTLE then return end
    eatFoleyKillTick = 0
    -- Antes do corte por lista vazia: o loop orfão aparece justamente quando n sobrou animal nenhum.
    CD.reapSoundRefs()
    local now = getTimestampMs()
    for key, seenMs in pairs(soundSeenMs) do
        if (now - seenMs) > SOUND_DUP_MS then
            soundSeenMs[key] = nil
        end
    end
    local dogs = CD.regDogs()
    if #dogs == 0 then return end
    local muted
    for _, name in ipairs(CD.ENGINE_VOICES) do
        if CD.Settings.getVolumeFactor(name) <= 0 then
            muted = muted or {}
            muted[#muted + 1] = name
        end
    end
    for i = 1, #dogs do
        local a = dogs[i]
        if not a:isDead() then
            local em = a:getEmitter()
            em:stopSoundByName("AnimalFoleyEatGrass")
            if muted then
                for _, name in ipairs(muted) do em:stopSoundByName(name) end
            end
        end
    end
    -- Loop preso no piso do rolloff quando o player se afasta e o stopsound n chega. So os cães
    -- com loop nosso em curso, nao a cell inteira. O reaper la em cima ja tirou os ids sem animal,
    -- entao aqui todo id resolve.
    for id, refs in pairs(CD.soundRefs) do
        local a = getAnimal(id)
        for name in pairs(refs) do
            if CD.SOUND_LOOPED[name]
               and not CD.nearAnyLocalPlayer(a, CD.soundRange(name) + CD.SOUND_RANGE_MARGIN) then
                CD.stopAnimalSound(a, name)
            end
        end
    end
end

-- Sem isto o client cai no teto curto do registro e reconstroi a cada 250 ms.
local regTick = 0
local function tickDogRegClient()
    regTick = regTick + 1
    if regTick < CD.DOG_REG_TICKS then return end
    regTick = 0
    CD._regTickDriven = true
    CD.rebuildDogRegIfChanged()
end

local clientFenceHops = {}
local clientBlinkHops = {}
local clientFenceSettle = {}

local naiWritable = nil
local function redirectInit(animal)
    if naiWritable == false then return nil end
    local nai = animal:getNetworkCharacterAI()
    if not nai then
        naiWritable = false
        return nil
    end
    if naiWritable == nil then
        naiWritable = nai.targetX ~= nil
    end
    if naiWritable == false then return nil end
    nai.usePathFind = false
    nai.forcePathFinder = false
    nai.needToMovingUsingPathFinder = false
    return nai
end

local function redirectTick(h, nx, ny, nz)
    local nai = h.nai
    nai.targetX = nx
    nai.targetY = ny
    if nai.targetZ ~= nil then
        nai.targetZ = math.floor(nz)
    end
    nai.forcePathFinder = false
    nai.needToMovingUsingPathFinder = false
    if h.ux and h.uy and nai.direction then
        nai.direction:set(h.ux, h.uy)
    end
end

local function snapHopFacing(animal, dir, ux, uy)
    if dir then
        animal:setDir(dir)
    elseif ux and uy then
        animal:setForwardDirection(ux, uy)
    end
    local f = animal:getForwardDirection()
    if f then
        animal:setTargetAndCurrentDirection(f:getX(), f:getY())
    end
end

CD.snapDogFacing = snapHopFacing

local function restoreHopState(animal)
    if animal then
        animal:setDeferredMovementEnabled(true)
        animal:setMaxTwist(0)
        animal:setVariable("cdJump", false)
        animal:setVariable("cdGlide", false)
        animal:setVariable("bMoving", false)
        animal:setVariable("cdNetGait", false)
        local f = animal:getForwardDirection()
        if f then
            animal:setTargetAndCurrentDirection(f:getX(), f:getY())
        end
    end
end
CD.restoreDogNetState = restoreHopState


local function beginFenceSettle(id, animal, x, y, z, fx, fy)
    if not animal or not x then
        if animal then
            restoreHopState(animal)
        end
        return
    end
    clientFenceSettle[id] = { animal = animal, x = x, y = y, z = z, fx = fx, fy = fy,
                              untilMs = getTimestampMs() + CD.FENCE_HOP_SETTLE_MS }
    animal:setHasObstacleOnPath(false)
end

---@param args table server payload { id, sx, sy, sz, cx, cy, z, dir, dx, dy, step, arc }
function CD.startFenceHopLocal(args)
    if not args or not args.id then return end
    local id = tonumber(args.id)
    local animal = getAnimal(id)
    if not animal then return end
    clientFenceSettle[id] = nil
    if CD.FENCE_HOP_MP_BLINK then
        clientBlinkHops[id] = { animal = animal, untilMs = getTimestampMs() + 3000 }
        animal:setInvisible(true, true)
        return
    end
    local dir = IsoDirections.fromIndex(args.dir)
    local h = {
        animal = animal, sx = args.sx, sy = args.sy, sz = args.sz, cx = args.cx, cy = args.cy, z = args.z,
        dir = dir, ux = args.dx, uy = args.dy, prog = 0, step = args.step or 0.05, arc = args.arc or 0.5,
        startMs = getTimestampMs(),
    }
    clientFenceHops[id] = h
    animal:setVariable("animalRunning", false)
    animal:setVariable("cdJump", true)
    animal:setMaxTwist(0)
    animal:setDeferredMovementEnabled(false)
    if CD.FENCE_HOP_REDIRECT then
        h.nai = redirectInit(animal)
    end
    snapHopFacing(animal, dir, h.ux, h.uy)
end

---Lands the dog on the point the server sent, or on the planned landing, and starts the settle phase.
---@param args table server payload { id, x, y, z }
function CD.endFenceHopLocal(args)
    if not args or not args.id then return end
    local id = tonumber(args.id)
    local animal = getAnimal(id)
    local h = clientFenceHops[id]
    local lx, ly, lz
    if animal and args.x then
        lx, ly, lz = args.x, args.y, args.z
        animal:setX(lx)
        animal:setY(ly)
        animal:setNextX(lx)
        animal:setNextY(ly)
        animal:setZ(lz)
    elseif h then
        lx, ly, lz = h.cx, h.cy, h.z
    end
    local blink = clientBlinkHops[id]
    if blink then
        clientBlinkHops[id] = nil
        local vis = animal or blink.animal
        if vis then
            vis:setInvisible(false, true)
        end
    end
    clientFenceHops[id] = nil
    if animal then
        animal:setVariable("cdJump", false)
        animal:setVariable("ClimbFence", false)
        animal:setVariable("climbDown", false)
        animal:setVariable("ClimbingFence", false)
        beginFenceSettle(id, animal, lx, ly, lz, h and h.ux, h and h.uy)
    end
end

-- devolve true quando o pulo acabou e o registro deve sair de clientFenceHops
local function stepFenceHop(id, h, landBlend)
    local animal = h.animal
    if not animal or not animal:isExistInTheWorld() then return true end
    h.prog = h.startMs and math.min(1, (getTimestampMs() - h.startMs) / CD.FENCE_HOP_DURATION_MS)
             or math.min(1, h.prog + (h.step or 0.05))
    local p = h.prog
    local ph = p * p * (3 - 2 * p)
    local arc = (h.arc or 0.5) * 4 * p * (1 - p)
    local nx = h.sx + (h.cx - h.sx) * ph
    local ny = h.sy + (h.cy - h.sy) * ph
    local nz = h.sz + (h.z - h.sz) * ph + arc
    animal:setX(nx)
    animal:setY(ny)
    animal:setNextX(nx)
    animal:setNextY(ny)
    animal:setZ(nz)
    animal:setVariable("animalRunning", false)
    animal:setVariable("cdJump", p < landBlend)
    animal:setMaxTwist(0)
    snapHopFacing(animal, h.dir, h.ux, h.uy)
    if h.nai then
        redirectTick(h, nx, ny, nz)
    end
    if p >= 1 then
        animal:setX(h.cx)
        animal:setY(h.cy)
        animal:setNextX(h.cx)
        animal:setNextY(h.cy)
        animal:setZ(h.z)
        animal:setVariable("cdJump", false)
        beginFenceSettle(id, animal, h.cx, h.cy, h.z, h.ux, h.uy)
        return true
    end
    return false
end

local function tickClientFenceHops()
    local nowMs = getTimestampMs()
    for bid, rec in pairs(clientBlinkHops) do
        if nowMs >= rec.untilMs then
            clientBlinkHops[bid] = nil
            if rec.animal then
                rec.animal:setInvisible(false, true)
            end
        end
    end
    local landBlend = CD.FENCE_HOP_LAND_BLEND
    for id, h in pairs(clientFenceHops) do
        if stepFenceHop(id, h, landBlend) then
            clientFenceHops[id] = nil
        end
    end
end

-- devolve true quando o assentamento acabou e o registro deve sair de clientFenceSettle
local function stepFenceSettle(s, nowMs)
    local a = s.animal
    if not a or not a:isExistInTheWorld() or nowMs >= s.untilMs then return true end
    a:setX(s.x)
    a:setY(s.y)
    a:setNextX(s.x)
    a:setNextY(s.y)
    a:setZ(s.z)
    a:setVariable("animalRunning", false)
    a:setMaxTwist(0)
    a:setDeferredMovementEnabled(false)
    a:setHasObstacleOnPath(false)
    if s.fx then
        snapHopFacing(a, nil, s.fx, s.fy)
    end
    return false
end

-- A manqueira sai do ModData que ja viaja: sem pacote proprio, e quem conecta no meio ve no primeiro segundo.
local limpVarsNextMs = 0
local limpDeepNextMs = 0
local function tickLimpVars()
    local now = getTimestampMs()
    if now < limpVarsNextMs then return end
    limpVarsNextMs = now + 1000
    if now >= limpDeepNextMs then
        limpDeepNextMs = now + 10000
        CD.vetForgetLimpMarks()
    end
    CD.regEach(CD.regCompanions(), CD.vetApplyLimpVars)
end

local function tickClientFenceSettle()
    local nowMs = getTimestampMs()
    for id, s in pairs(clientFenceSettle) do
        if stepFenceSettle(s, nowMs) then
            local a = s.animal
            if a then
                restoreHopState(a)
            end
            clientFenceSettle[id] = nil
        end
    end
end

-- O pacote do servidor chega por conexao, sem indice de jogador, entao na tela dividida os dois
-- locais recebem o mesmo evento. Quem e o destinatario vem no corpo, carimbado por CD.notifyOwner.
local function notifyTarget(args)
    local u = args and args.__to
    if u == nil then return nil end
    if (getNumActivePlayers() or 1) <= 1 then return nil end
    local found
    CD.eachLocalPlayer(function(p) if found == nil and p:getUsername() == u then found = p end end)
    return found
end

local function OnServerCommand(module, command, args)
    if module ~= CD.MODULE then return end
    if CD._perfLv and CD._perfLv > 0 then
        CD.perfCount("rx." .. tostring(command))
    end
    if command == "fencehop" then
        CD.startFenceHopLocal(args)
        return
    end
    if command == "fencehopend" then
        CD.endFenceHopLocal(args)
        return
    end
    if command == "followb" then
        CD.onFollowBatch(args)
        return
    end
    if command == "netauth" then
        CD.onNetAuth(args)
        return
    end
    if command == "followstop" then
        CD.onFollowStop(args)
        return
    end
    if command == "sound" then
        CD.playDogSound(args)
        return
    end
    if command == "stopsound" then
        CD.stopDogSound(args)
        return
    end
    if command == "animvar" then
        CD.setDogAnimVar(args)
        return
    end
    if command == "dishstock" then
        CD.cacheDishStock(args)
        return
    end
    if command == "anim" then
        CD.playDogAttack(args)
        return
    end
    if command == "despawn" then
        CD.onDespawn(args)
        return
    end
    if command == "knockdown" then
        CD.knockdownZombie(args)
        return
    end
    if command == "killzombie" then
        CD.killZombie(args)
        return
    end
    if command == "dmgdebug" then
        CD.DMG_DEBUG = args and args.on == true
        CD.log("[CD-DMG] diagnostico " .. (CD.DMG_DEBUG and "ON" or "off") .. " (lado=" .. (CD.perfSide() or "?") .. ")")
        return
    end
    if command == "huntenabled" then
        CD.HUNT_ENABLED = not (args and args.on == false)
        return
    end
    if command == "kenneladminlist" then
        CD.onKennelAdminList(args)
        return
    end
    if command == "tuninglist" then
        CD.onTuningList(args)
        return
    end
    CD.clientNotify(command, args, notifyTarget(args))
end
CD.onServerCommand = OnServerCommand

local bagVisualTick = 0
local bagPaint = {}
local function tickBagVisuals()
    bagVisualTick = bagVisualTick + 1
    if bagVisualTick < 10 then return end
    bagVisualTick = 0
    local dogs = CD.regDogs()
    local best, order = {}, {}
    for i = 1, #dogs do
        local a = dogs[i]
        local id = tostring(a:getOnlineID())
        local active = a:hasActiveModel()
        local cur = best[id]
        if not cur then
            best[id] = { a = a, active = active }
            order[#order + 1] = id
        elseif active and not cur.active then
            cur.a = a
            cur.active = true
        end
    end
    local nowMs = getTimestampMs()
    for _, id in ipairs(order) do
        local e = best[id]
        local a = e.a
        local st = bagPaint[id]
        if not st then
            st = {}
            bagPaint[id] = st
        end
        if not CD.ensureAttachSlots(a) then
            bagPaint[id] = nil
        elseif CD.hasBag(a) then
            if e.active then
                local token = nil
                local mi = a:getModelInstance()
                if mi then
                    token = tostring(mi)
                end
                local missing = false
                for _, p in ipairs(CD.SADDLEBAG_PARTS) do
                    if a:getAttachedItem(p.loc) == nil then
                        missing = true
                        break
                    end
                end
                local justActivated = st.act ~= true
                local tokenChanged = token ~= nil and st.tok ~= nil and token ~= st.tok
                    and (not st.ms or (nowMs - st.ms) > 1000)
                if missing or justActivated or tokenChanged then
                    st.burst = nowMs
                end
                if st.burst and (nowMs - st.burst) < 800 then
                    CD.applyBagVisualLocal(a)
                    st.ms = nowMs
                end
                if token ~= nil then
                    st.tok = token
                end
                st.act = true
            else
                st.act = false
            end
        else
            if a:getAttachedItem("saddlebags_l") ~= nil then
                CD.removeBagVisualLocal(a)
            end
            bagPaint[id] = nil
        end
    end
    for id in pairs(bagPaint) do
        if not best[id] then
            bagPaint[id] = nil
        end
    end
end

local followStream = {}
local gaitHold = {}
-- O quadro chega como uma string so com todos os caes perto deste jogador. Formato por cao:
-- id,seq,x,y,z,fx,fy,rs,ws,flags  (flags: 1 = correndo, 2 = mexeu desde o ultimo quadro)
local function pushSample(id, seq, x, y, z, fx, fy, rs, ws, flags)
    local st = followStream[id]
    if not st then
        st = { buf = {}, lastSeq = -1 }
        followStream[id] = st
    end
    if seq <= st.lastSeq and (st.lastSeq - seq) < 1000 then return end
    st.lastSeq = seq
    local buf = st.buf
    local n = #buf
    local rt = getTimestampMs()
    -- Espacamento médio entre chegadas: e o q dimensiona o atraso de render. Cao conduzido pelo
    -- dono chega a 5 Hz e cão conduzido pelo servidor a 10 Hz, o tick do dedicado; um atraso fixo
    -- serve mal aos dois.
    if n > 0 then
        local gap = rt - buf[n].rt
        if gap > 0 and gap < 1000 then
            st.gap = st.gap and (st.gap * 0.8 + gap * 0.2) or gap
        end
        if CD._perfLv > 0 and gap > 0 then
            local cs = CD._perfCStream
            cs.gapN = cs.gapN + 1
            cs.gapSum = cs.gapSum + gap
            cs.gapSq = cs.gapSq + gap * gap
            if gap > cs.gapMax then
                cs.gapMax = gap
            end
        end
    end
    buf[n + 1] = { x = x, y = y, z = z, fx = fx, fy = fy,
                   run = (flags % 2) == 1, rs = rs, ws = ws,
                   mov = flags >= 2, rt = rt }
    local maxN = CD.FOLLOW_STREAM_BUF
    while #buf > maxN do
        -- So conta como perda a amostra descartada antes de chegar a vez dela no render.
        if CD._perfLv > 0
           and buf[1].rt > rt - math.max(CD.FOLLOW_INTERP_DELAY_MS, (st.gap or 0) * 1.5) then
            CD._perfCStream.overflow = CD._perfCStream.overflow + 1
        end
        table.remove(buf, 1)
    end
end

---Queues the samples of a follow stream frame for interpolation.
---@param args table server payload; args.s holds one sample per dog, separated by semicolons
function CD.onFollowBatch(args)
    local blob = args and args.s
    if type(blob) ~= "string" then return end
    local from = 1
    local len = string.len(blob)
    while from <= len do
        local semi = string.find(blob, ";", from, true)
        local chunk = string.sub(blob, from, (semi or (len + 1)) - 1)
        from = (semi or len) + 1
        local id, seq, x, y, z, fx, fy, rs, ws, flags = string.match(chunk,
            "^(-?%d+),(%d+),(-?[%d%.]+),(-?[%d%.]+),(-?[%d%.]+),(-?[%d%.]+),(-?[%d%.]+),(-?[%d%.]+),(-?[%d%.]+),(%d+)$")
        if id then
            pushSample(tonumber(id), tonumber(seq), tonumber(x), tonumber(y), tonumber(z),
                       tonumber(fx), tonumber(fy), tonumber(rs), tonumber(ws), tonumber(flags))
        end
    end
end

---Ends the follow stream of a dog: puts it on the final position and drops its buffered samples.
---@param args table server payload { id, x, y, z }
function CD.onFollowStop(args)
    if not args or not args.id then return end
    local id = tonumber(args.id)
    if not id then return end
    local animal = getAnimal(id)
    if animal and args.x then
        animal:setX(args.x)
        animal:setY(args.y)
        animal:setNextX(args.x)
        animal:setNextY(args.y)
        animal:setZ(args.z)
    end
    if animal then
        restoreHopState(animal)
    end
    followStream[id] = nil
    gaitHold[id] = nil
end

---@param id integer animal online id
function CD.clearFollowStreamFor(id)
    followStream[id] = nil
    gaitHold[id] = nil
end

---@param id integer animal online id
---@return boolean
---@nodiscard
function CD.followStreamActive(id)
    return followStream[id] ~= nil
end

local clientTrace, clientBeat

-- devolve true quando o stream expirou e o registro deve sair de followStream
local JUMP_SRC = { i = "jump.cli.interp", e = "jump.cli.extrap", s = "jump.cli.snap" }

local function stepFollowStream(id, st, nowMs, baseDelay, timeout)
    if clientFenceHops[id] or clientBlinkHops[id] then
        st.buf = {}
        return false
    end
    local buf = st.buf
    local n = #buf
    if n == 0 then return false end
    local age = nowMs - buf[n].rt
    if age > timeout then return true end
    local animal = getAnimal(id)
    if not animal or not animal:isExistInTheWorld() then return false end
    -- Atrasar menos que o espacamento de chegada obriga a extrapolar, e extrapolar em curva
    -- e o que produz o solavanco. Um passo e meio de folga cobre a variacao normal.
    local delay = baseDelay
    local gap = st.gap
    if gap and (gap * 1.5) > delay then
        delay = gap * 1.5
    end
    local renderTime = nowMs - delay
    local a, b
    for i = 1, n do
        if buf[i].rt <= renderTime then
            a = buf[i]
        else
            b = buf[i]
            break
        end
    end
    local nx, ny, nz, fx, fy, run, rs, ws, mov
    local src = "i"
    if not a then
        src = "s"
        local s = buf[1]
        nx, ny, nz, fx, fy, run, rs, ws, mov = s.x, s.y, s.z, s.fx, s.fy, s.run, s.rs, s.ws, s.mov
    elseif not b then
        src = "e"
        nx, ny, nz, fx, fy, run, rs, ws, mov = a.x, a.y, a.z, a.fx, a.fy, a.run, a.rs, a.ws, a.mov
        local prev = buf[n - 1]
        local ahead = renderTime - a.rt
        if prev and ahead > 0 then
            local dt = a.rt - prev.rt
            if dt > 0 then
                local k = math.min(ahead, CD.FOLLOW_EXTRAP_MAX_MS) / dt
                nx = a.x + (a.x - prev.x) * k
                ny = a.y + (a.y - prev.y) * k
                nz = a.z + (a.z - prev.z) * k
            end
        end
    else
        local span = b.rt - a.rt
        local al = span > 0 and ((renderTime - a.rt) / span) or 0
        if al < 0 then al = 0 elseif al > 1 then al = 1 end
        nx = a.x + (b.x - a.x) * al
        ny = a.y + (b.y - a.y) * al
        nz = a.z + (b.z - a.z) * al
        fx = a.fx + (b.fx - a.fx) * al
        fy = a.fy + (b.fy - a.fy) * al
        run = b.run
        rs = b.rs
        ws = b.ws
        mov = b.mov
    end
    if CD._perfLv > 0 then
        local cs = CD._perfCStream
        cs[src] = cs[src] + 1
        if age > cs.ageMax then
            cs.ageMax = age
        end
        cs.ids[id] = true
        -- Descontinuidade na REPRODUCAO: o quadro anterior estava longe do que este aplica. Diz se
        -- o salto que se ve nasceu aqui (amostra velha, buraco no buffer) ou ja veio do servidor.
        if CD._perfLv > 1 then
            local px, py = st.appX, st.appY
            if px and (math.abs(nx - px) + math.abs(ny - py)) >= CD.JUMP_WATCH_TILES then
                CD.perfCount("jump.cli")
                CD.perfCount(JUMP_SRC[src])
            end
            st.appX, st.appY = nx, ny
        end
    end
    animal:setX(nx)
    animal:setY(ny)
    animal:setNextX(nx)
    animal:setNextY(ny)
    animal:setZ(nz)
    animal:setVariable("animalRunning", run == true)
    -- cdGlide troca os nodes pelos gemeos sem root motion. Nao usar setDeferredMovementEnabled:
    -- ele so guarda o integrador local e o moveToPoint le getDeferredMovement direto.
    animal:setVariable("cdGlide", true)
    if mov ~= false then
        gaitHold[id] = nowMs + CD.NET_GAIT_HOLD_MS
    end
    animal:setVariable("cdNetGait", (gaitHold[id] or 0) > nowMs)
    -- Nao escrever bMoving aqui: a engine reescreve dentro do IsoWorld.update, antes do OnTick do Lua.
    CD.setGaitScaleRaw(animal, rs or CD.PATH_RUN_SCALE, ws or CD.PATH_WALK_SCALE)
    animal:setMaxTwist(0)
    local len = math.sqrt(fx * fx + fy * fy)
    if len > 0.0001 then
        snapHopFacing(animal, nil, fx / len, fy / len)
    end
    clientTrace(animal, id, nowMs, buf[n].rt, src)
    return false
end

local function tickFollowStreamClient()
    local nowMs = getTimestampMs()
    local baseDelay = CD.FOLLOW_INTERP_DELAY_MS
    local timeout = CD.FOLLOW_STREAM_TIMEOUT_MS
    local beatN = 0
    for id, st in pairs(followStream) do
        beatN = beatN + 1
        if stepFollowStream(id, st, nowMs, baseDelay, timeout) then
            if CD._perfLv > 0 then
                CD._perfCStream.timeout = CD._perfCStream.timeout + 1
            end
            local animal = getAnimal(id)
            if animal then
                restoreHopState(animal)
            end
            followStream[id] = nil
            gaitHold[id] = nil
        end
    end
    if clientBeat then
        clientBeat(nowMs, beatN)
    end
end

local ctraceN, ctraceX, ctraceY, ctraceMs = 0, nil, nil, nil
local ctraceBeatMs = nil
local ctraceRunUntil = nil
local ctraceVec = nil
clientTrace = function(a, id, nowMs, lastPacketMs, src)
    if not CD.DEBUG_FOLLOW_TRACE then return end
    if ctraceN >= CD.DEBUG_TRACE_MAX then return end
    if a:getVariableBoolean("bMoving") or a:getVariableBoolean("animalRunning") then
        ctraceRunUntil = nowMs + 400
    elseif not ctraceRunUntil or nowMs > ctraceRunUntil then
        ctraceX, ctraceY, ctraceMs = nil, nil, nil
        return
    end
    local x, y = a:getX(), a:getY()
    if ctraceMs then
        local dt = nowMs - ctraceMs
        if dt > 0 then
            local dx, dy = x - ctraceX, y - ctraceY
            local dist = math.sqrt(dx * dx + dy * dy)
            local p = getPlayer()
            local gap = -1
            if p then
                local gx, gy = p:getX() - x, p:getY() - y
                gap = math.sqrt(gx * gx + gy * gy)
            end
            local st = tostring(a:getAnimationStateName())
            local ac = tostring(a:getActionStateName())
            local rl = -1
            if not ctraceVec then
                ctraceVec = Vector2.new()
            end
            local v = a:getDeferredMovement(ctraceVec)
            if v then
                rl = v:getLength()
            end
            ctraceN = ctraceN + 1
            CD.log(string.format(
                "[CD-CTRACE] %d dt=%d d=%.4f v=%.2f rl=%.4f gl=%s src=%s gap=%.1f x=%.2f y=%.2f st=%s ac=%s bp=%s ng=%s bMov=%s run=%s rs=%.3f ws=%.3f age=%d col=%s",
                ctraceN, dt, dist, dist / (dt / 1000), rl,
                tostring(a:getVariableBoolean("cdGlide")), src or "?", gap, x, y, st, ac,
                tostring(a:getVariableBoolean("bPathfind")),
                tostring(a:getVariableBoolean("cdNetGait")),
                tostring(a:getVariableBoolean("bMoving")), tostring(a:getVariableBoolean("animalRunning")),
                a:getVariableFloat("cdRunScale", -1), a:getVariableFloat("cdWalkScale", -1),
                lastPacketMs and (nowMs - lastPacketMs) or -1,
                tostring(a:isCollidedThisFrame())))
        end
    end
    ctraceX, ctraceY, ctraceMs = x, y, nowMs
end

clientBeat = function(nowMs, n)
    if not CD.DEBUG_FOLLOW_TRACE then return end
    if ctraceBeatMs and (nowMs - ctraceBeatMs) < 1000 then return end
    ctraceBeatMs = nowMs
    CD.log(string.format("[CD-CBEAT] caes flagados=%d traces=%d", n, ctraceN))
end

local sniffLitBy = {}
local sniffLitNextMs = 0
local function clearSniffHighlight(pn)
    local lit = sniffLitBy[pn]
    if not lit then return end
    local o, idx = lit.obj, lit.playerIdx or pn
    sniffLitBy[pn] = nil
    o:setHighlighted(idx, false, false)
end

local function sniffHighlightFor(player)
    local idx = player:getPlayerNum()
    local dog = CD.getCompanionAnimal(player)
    local d = dog and CD.data(dog) or nil
    local mark = d and d.sniffMark
    local scent = d and d.sniffed
    if not mark or not scent or not scent.t then
        clearSniffHighlight(idx)
        return
    end

    local cell = getCell()
    local sq = cell and cell:getGridSquare(mark.x, mark.y, mark.z)
    if not sq then
        clearSniffHighlight(idx)
        return
    end
    local holder = CD.sniffHolderAtSquare(sq, scent.t)
    if not holder then
        clearSniffHighlight(idx)
        d.sniffMark = nil
        return
    end
    local lit = sniffLitBy[idx]
    if lit and lit.obj == holder then
        return
    end
    clearSniffHighlight(idx)
    -- RenderOnce=false e obrigatorio: no padrao o IsoGridSquare apaga o brilho logo depois de desenhar.
    holder:setHighlighted(idx, true, false)
    holder:setHighlightColor(idx, CD.SNIFF_HIGHLIGHT_R, CD.SNIFF_HIGHLIGHT_G,
        CD.SNIFF_HIGHLIGHT_B, CD.SNIFF_HIGHLIGHT_A)
    sniffLitBy[idx] = { obj = holder, playerIdx = idx, x = mark.x, y = mark.y, z = mark.z }
end

local function tickSniffHighlight()
    local nowMs = getTimestampMs()
    if nowMs < sniffLitNextMs then return end
    sniffLitNextMs = nowMs + CD.SNIFF_HIGHLIGHT_TICK_MS
    CD.eachLocalPlayer(sniffHighlightFor)
end

local CD_SBX_PAGE = "CompanionDogs."

local function cdSandboxOptionValue(o)
    local t = o:getType()
    if t == "boolean" then
        local b = o:getValue()
        return b == true
    end
    local s = o:getValueAsString()
    local n = tonumber(s)
    if n ~= nil then return n end
    local v = o:getValue()
    return v
end

local function cdSandboxPageFromJava(opts)
    local page = SandboxVars.CompanionDogs
    if type(page) ~= "table" then return 0 end
    local n = opts:getNumOptions()
    local pre = string.len(CD_SBX_PAGE)
    local changed = 0
    for i = 1, n do
        local o = opts:getOptionByIndex(i - 1)
        local name = o:getName()
        if type(name) == "string" and string.sub(name, 1, pre) == CD_SBX_PAGE then
            local short = string.sub(name, pre + 1)
            local v = cdSandboxOptionValue(o)
            if v ~= nil and page[short] ~= v then
                page[short] = v
                changed = changed + 1
            end
        end
    end
    return changed
end

local function cdSandboxSyncFromJava()
    local opts = getSandboxOptions()
    opts:toLua()
    local changed = cdSandboxPageFromJava(opts)
    if changed > 0 then
        CD.log("[CD-SANDBOX] " .. changed .. " opcao(oes) reespelhada(s) do Java; confianca para domesticar = " ..
              tostring(CD.tameThreshold()))
    end
end

local function cdWrapSandboxScreen()
    if ISServerSandboxOptionsUI.cdApplyWrapped then return end
    local vanillaApply = ISServerSandboxOptionsUI.onButtonApply
    ISServerSandboxOptionsUI.onButtonApply = function(self)
        vanillaApply(self)
        cdSandboxSyncFromJava()
    end
    ISServerSandboxOptionsUI.cdApplyWrapped = true
end

if not isClient() and not isServer() then
    cdWrapSandboxScreen()
    Events.OnGameStart.Add(cdWrapSandboxScreen)
end

-- Cada personagem que nasce pede as receitas de ervas; quem decide pela opcao de sandbox e o servidor.
local function requestVetRecipes(_, player)
    CD.request("vetrecipes", nil, {}, player)
end

if isClient() then
    Events.OnGameStart.Add(function() CD.request("huntstate", nil, {}) end)
    CD.evAdd(Events.OnTick, tickFollowStreamClient, "cli.followstream")
    CD.evAdd(Events.OnTick, tickClientFenceHops, "cli.fencehop")
    CD.evAdd(Events.OnTick, tickClientFenceSettle, "cli.fencesettle")
    CD.evAdd(Events.OnTick, tickGunGuardClient, "cli.gunguard")
    CD.evAdd(Events.OnTick, tickOrphanDogs, "cli.orphandogs")
    CD.evAdd(Events.OnTick, tickLimpVars, "cli.limpvars")
    CD.evAdd(Events.OnTick, tickDogRegClient, "cli.dogreg")
end

if isClient() or not isServer() then
    Events.OnCreatePlayer.Add(requestVetRecipes)
    CD.evAdd(Events.OnServerCommand, OnServerCommand, "cli.servercmd")
    CD.evAdd(Events.OnTick, processAttackClears, "cli.attackclears")
    CD.evAdd(Events.OnTick, clearCompanionShootable, "cli.shootable")
    Events.OnTick.Add(tickFallFlagClient)
    CD.evAdd(Events.OnTick, tickWildDogBark, "cli.wildbark")
    CD.evAdd(Events.OnTick, tickDogIdleVoice, "cli.idlevoice")
    CD.evAdd(Events.OnTick, tickEatFoleyKill, "cli.eatfoley")
    CD.evAdd(Events.OnTick, tickBagVisuals, "cli.bagvisuals")
    CD.evAdd(Events.OnTick, tickSniffHighlight, "cli.sniffhighlight")
    Events.OnTick.Add(CD.perfSampleClient)
    Events.OnTick.Add(CD.perfTickEnd)
    CD.BOOT_CLIENT = (CD.BOOT_CLIENT or 0) + 1
    if CD.DEBUG_BOOT then
        CD.log(string.format("[CD-BOOT] client: loops registrados (carga #%d)", CD.BOOT_CLIENT))
        if CD.BOOT_CLIENT > 1 then
            CD.log("[CD-BOOT] *** ATENCAO: Lua de client do Companion Dogs carregado " .. CD.BOOT_CLIENT ..
                  " VEZES. Ha uma segunda copia do mod ativa. ***")
        end
    end
end
