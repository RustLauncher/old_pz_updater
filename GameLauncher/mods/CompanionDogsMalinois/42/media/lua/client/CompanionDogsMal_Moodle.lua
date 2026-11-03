local CD = CompanionDogs
if not (CD and CD.DogMoodles and (CD.API_VERSION or 0) >= 11) then return end

CD.MAL_SCENT_RADIUS = 25
CD.MAL_SCENT_PERIOD_MS = 5000

---Hunger and thirst both below MOODLE_NEGLECT_MAX.
---@param dog IsoAnimal
---@return boolean
---@nodiscard
local function dogIsCaredFor(dog)
    local h = dog:getHunger()
    local t = dog:getThirst()
    return h < CD.MOODLE_NEGLECT_MAX and t < CD.MOODLE_NEGLECT_MAX
end

local nextScan = {}
local marks = {}

-- targetAlpha por jogador e o que a engine zera quando o zumbi sai da vista dele (cone, parede ou
-- escuro), entao "fora de vista" aqui e o mesmo criterio que esconde o zumbi na tela.
---@param player IsoPlayer
---@param pn integer player number
---@return IsoZombie|nil zombie closest to the player within MAL_SCENT_RADIUS that this player cannot see
---@nodiscard
local function nearestHidden(player, pn)
    local zs = getCell():getZombieList()
    local px, py, pz = player:getX(), player:getY(), player:getZ()
    local best, bestD2 = nil, CD.MAL_SCENT_RADIUS * CD.MAL_SCENT_RADIUS
    for i = 0, zs:size() - 1 do
        local z = zs:get(i)
        if not z:isDead() and not z:isFakeDead() and z:getCurrentSquare()
            and math.abs(z:getZ() - pz) <= 1 and z:getTargetAlpha(pn) < 0.01 then
            local dx, dy = z:getX() - px, z:getY() - py
            local d2 = dx * dx + dy * dy
            if d2 <= bestD2 then
                best, bestD2 = z, d2
            end
        end
    end
    return best
end

---Removes the player's scent arrow, if any.
---@param pn integer player number
local function clearMark(pn)
    if marks[pn] then
        marks[pn]:remove()
        marks[pn] = nil
    end
end

CD.DogMoodles[#CD.DogMoodles + 1] = {
    id = "k9scent",
    breed = "malinois",
    nameKey = "IGUI_PD_Moodle_K9Scent",
    descKey = "IGUI_PD_Moodle_K9Scent_desc",
    icon = "CD_Moodle_K9Scent",
    fg = "CD_MoodK9ScentFG",
    tintR = 0.80, tintG = 0.58, tintB = 0.28,
    ---@param player IsoPlayer
    ---@param dog IsoAnimal|nil
    ---@return integer level 1 to show the moodle, 0 to hide it
    ---@nodiscard
    condition = function(player, dog)
        if not dog or dog:isDead() then return 0 end
        if CD.getBreed(dog) ~= "malinois" then return 0 end
        if CD.isDisloyal(dog) then return 0 end
        if CD.isSick(dog) then return 0 end
        if not dogIsCaredFor(dog) then return 0 end
        return 1
    end,
    -- A seta e a mesma do forrageio (homing point): fica em volta do personagem apontando para onde o
    -- zumbi foi farejado e pousa no lugar quando ele cabe na tela. Marca a posicao da varredura, nao
    -- segue o zumbi entre uma varredura e outra.
    ---@param player IsoPlayer
    ---@param dog IsoAnimal|nil nil while the moodle lingers with the dog out of range
    ---@param elapsedMin number game minutes since the last call
    apply = function(player, dog, elapsedMin)
        if not dog then return end
        local pn = player:getPlayerNum()
        local now = getTimestampMs()
        if now < (nextScan[pn] or 0) then return end
        nextScan[pn] = now + CD.MAL_SCENT_PERIOD_MS
        local z = nearestHidden(player, pn)
        if not z then
            clearMark(pn)
            return
        end
        local x, y = math.floor(z:getX()), math.floor(z:getY())
        if marks[pn] then
            marks[pn]:setX(x)
            marks[pn]:setY(y)
        else
            marks[pn] = getWorldMarkers():addPlayerHomingPoint(player, x, y, 0.80, 0.58, 0.28, 1.0)
        end
    end,
    ---Stops the scan and removes the arrow.
    ---@param player IsoPlayer
    onDeactivate = function(player)
        if player then
            local pn = player:getPlayerNum()
            nextScan[pn] = nil
            clearMark(pn)
        end
    end,
}
