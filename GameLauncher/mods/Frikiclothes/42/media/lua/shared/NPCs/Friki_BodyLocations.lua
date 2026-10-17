-- FrikiClothes_BodyLocations.lua
-- Build 42.13+

require "NPCs/BodyLocations"

local BodyAPI = BodyLocations
local SlotAPI = ItemBodyLocation
local RL = ResourceLocation

------------------------------------------------------------
-- Copia las reglas de una ubicación vanilla
------------------------------------------------------------
local function cloneLocationRules(sourceGroup, locationId, targetGroup)
    for i = 0, sourceGroup:size() - 1 do
        local otherId = sourceGroup:getLocationByIndex(i):getId()

        if sourceGroup:isExclusive(locationId, otherId) then
            targetGroup:setExclusive(locationId, otherId)
        end

        if sourceGroup:isHideModel(locationId, otherId) then
            targetGroup:setHideModel(locationId, otherId)
        end

        if sourceGroup:isAltModel(locationId, otherId) then
            targetGroup:setAltModel(locationId, otherId)
        end
    end
end

------------------------------------------------------------
-- Reconstruye el grupo Human e inserta nuevos BodyLocations
------------------------------------------------------------
local function rebuildGroupWithInsertions(targetGroupId, insertions)

    local created = {}

    local groupView = BodyAPI.getAllGroups()
    local groupSnapshot = {}

    for i = 0, groupView:size() - 1 do
        groupSnapshot[#groupSnapshot + 1] = groupView:get(i)
    end

    BodyAPI.reset()

    for _, oldGroup in ipairs(groupSnapshot) do

        local newGroup = BodyAPI.getGroup(oldGroup:getId())

        for i = 0, oldGroup:size() - 1 do

            local existingId = oldGroup:getLocationByIndex(i):getId()

            -- Insertar antes
            if oldGroup:getId() == targetGroupId then
                for _, def in ipairs(insertions) do

                    if def.before then

                        local anchorId = type(def.anchor) == "string"
                            and RL.of(def.anchor)
                            or def.anchor

                        if anchorId == existingId then

                            local newId = SlotAPI.get(RL.of(def.id))

                            created[def.id] = newGroup:getOrCreateLocation(newId)

                        end
                    end
                end
            end

            newGroup:getOrCreateLocation(existingId)

            -- Insertar después
            if oldGroup:getId() == targetGroupId then
                for _, def in ipairs(insertions) do

                    if not def.before then

                        local anchorId = type(def.anchor) == "string"
                            and RL.of(def.anchor)
                            or def.anchor

                        if anchorId == existingId then

                            local newId = SlotAPI.get(RL.of(def.id))

                            created[def.id] = newGroup:getOrCreateLocation(newId)

                        end
                    end
                end
            end
        end

        -- Restaurar comportamiento vanilla
        for i = 0, oldGroup:size() - 1 do

            local locId = oldGroup:getLocationByIndex(i):getId()

            newGroup:setMultiItem(locId, oldGroup:isMultiItem(locId))

            cloneLocationRules(oldGroup, locId, newGroup)

        end
    end
end

------------------------------------------------------------
-- Crear BodyLocations de FrikiClothes
------------------------------------------------------------
local function setupFrikiBodyLocations()

    local outerVestLayer =
        SlotAPI.TORSO_EXTRA_VEST_BULLET
        or SlotAPI.TORSO_EXTRA_VEST
        or SlotAPI.TORSO_EXTRA

    rebuildGroupWithInsertions("Human", {

        -- Garras (después de los guantes)
        {
            id = "Friki:ClawsLeft",
            anchor = SlotAPI.HANDS_LEFT
        },

        {
            id = "Friki:ClawsRight",
            anchor = SlotAPI.HANDS_RIGHT
        },
        -- Hombreras
        {
            id = "Friki:ShouldersLeft",
            anchor = SlotAPI.LEFT_ARM
        },

        {
            id = "Friki:ShouldersRight",
            anchor = SlotAPI.RIGHT_ARM
        },

        -- Capa extra
        {
            id = "Friki:CapeExtra",
            anchor = SlotAPI.BACK
        },

        -- Alas
        {
            id = "Friki:Wings",
            anchor = SlotAPI.BACK
        },

        -- Cola
        {
            id = "Friki:Tail",
            anchor = SlotAPI.SHOES,
            before = true
        },

        -- Arnés / accesorios de torso
        {
            id = "Friki:TorsoExtra",
            anchor = outerVestLayer
        },
    })
end

Events.OnGameBoot.Add(setupFrikiBodyLocations)