CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

local function lvl(animal, skill)
    if not CD.skillsEnabled() then return 0 end
    return CD.getSkillLevel(animal, skill)
end

CD.TRICKS = {
    { id = "goto",     cmd = "trickgoto",     minLevel = 1,  xp = 3, labelKey = "IGUI_PD_TrickGoto",     descKey = "IGUI_PD_TrickGotoDesc",     needsBag = false },
    { id = "distract", cmd = "trickdistract", minLevel = 3,  xp = 4, labelKey = "IGUI_PD_TrickDistract", descKey = "IGUI_PD_TrickDistractDesc", needsBag = false },
    { id = "sniff",    cmd = "tricksniff",    minLevel = 5,  xp = 5, labelKey = "IGUI_PD_TrickSniff",    descKey = "IGUI_PD_TrickSniffDesc",    needsBag = false, needsHeld = true, skill = "scent",
      memory = "sniffed", noItemKey = "IGUI_PD_TrickSniffNoItem", stopCmd = "tricksniffstop", stopKey = "IGUI_PD_TrickSniffStop", stopDescKey = "IGUI_PD_TrickSniffStopDesc" },
    { id = "fetch",    cmd = "trickfetch",    minLevel = 10, xp = 8, labelKey = "IGUI_PD_TrickFetch",    descKey = "IGUI_PD_TrickFetchDesc",    needsBag = true,  needsHeld = true, skill = "scent", wide = true,
      memory = "fetched", noItemKey = "IGUI_PD_TrickFetchNoItem", stopCmd = "trickfetchstop", stopKey = "IGUI_PD_TrickFetchStop", stopDescKey = "IGUI_PD_TrickFetchStopDesc" },
}

CD.TRICK_BY_ID = {}
for _, t in ipairs(CD.TRICKS) do CD.TRICK_BY_ID[t.id] = t end

---@param id string trick id
---@return table|nil def the CD.TRICKS row
---@nodiscard
function CD.trickDef(id) return CD.TRICK_BY_ID[id] end

---Obedience level checked against each trick's minLevel; the max level with skills off.
---@param animal IsoAnimal
---@return integer level
---@nodiscard
function CD.trickLevel(animal)
    if not CD.skillsEnabled() then return CD.SKILL_MAX_LEVEL end
    return CD.getSkillLevel(animal, "obedience")
end

---The breed learns tricks and has the trick's skill; the level is not checked.
---@param animal IsoAnimal|table|nil the dog, or the stash proxy
---@param id string trick id
---@return boolean
---@nodiscard
function CD.breedHasTrick(animal, id)
    local def = CD.TRICK_BY_ID[id]
    if not def or not animal then return false end
    if not CD.breedCanLearnTricks(animal) then return false end
    if def.skill and not CD.breedHasSkill(animal, def.skill) then return false end
    return true
end

---Tricks the breed can learn, locked or not; every trick without an animal.
---@param animal IsoAnimal|table|nil the dog, or the stash proxy
---@return table[] defs CD.TRICKS rows
---@nodiscard
function CD.tricksFor(animal)
    local out = {}
    for i = 1, #CD.TRICKS do
        local d = CD.TRICKS[i]
        if animal == nil or CD.breedHasTrick(animal, d.id) then
            out[#out + 1] = d
        end
    end
    return out
end

---The breed has the trick and the obedience level reaches its minLevel.
---@param animal IsoAnimal|nil
---@param id string trick id
---@return boolean
---@nodiscard
function CD.trickUnlocked(animal, id)
    local def = CD.TRICK_BY_ID[id]
    if not def or not animal then return false end
    if not CD.breedHasTrick(animal, id) then return false end
    return CD.trickLevel(animal) >= def.minLevel
end

---Scent record { t = item full type, name, sinceMin } kept in the given ModData field.
---@param animal IsoAnimal|nil
---@param field string|nil
---@return table|nil memory nil when nothing is remembered
---@nodiscard
function CD.trickMemoryOf(animal, field)
    local s = animal and field and CD.data(animal)[field]
    if type(s) ~= "table" or s.t == nil then return nil end
    return s
end

---@param animal IsoAnimal
---@return table|nil memory the item scent the sniff trick follows
---@nodiscard
function CD.sniffedScent(animal) return CD.trickMemoryOf(animal, "sniffed") end
---@param animal IsoAnimal
---@return table|nil memory the item scent the fetch trick looks for
---@nodiscard
function CD.fetchedScent(animal) return CD.trickMemoryOf(animal, "fetched") end

---@param animal IsoAnimal
---@param def table|string trick def or id
---@return table|nil memory nil for tricks without memory or when nothing is remembered
---@nodiscard
function CD.trickMemory(animal, def)
    if type(def) == "string" then
        def = CD.TRICK_BY_ID[def]
    end
    if not def or not def.memory then return nil end
    return CD.trickMemoryOf(animal, def.memory)
end

---Item in the primary hand, else in the secondary one.
---@param player IsoPlayer|nil
---@return InventoryItem|nil
---@nodiscard
function CD.heldSniffItem(player)
    if not player then return nil end
    local it = player:getPrimaryHandItem()
    if not it then
        it = player:getSecondaryHandItem()
    end
    return it
end

---Translation key of what keeps the trick from starting now; nil when nothing does.
---@param animal IsoAnimal|nil
---@param def table|string trick def or id
---@param player IsoPlayer|nil whose held item a scent trick takes
---@return string|nil reasonKey
---@return string|nil minLevel only with IGUI_PD_TrickLocked
---@return string|nil level the dog's level, only with IGUI_PD_TrickLocked
---@nodiscard
function CD.trickBlockReason(animal, def, player)
    if type(def) == "string" then
        def = CD.TRICK_BY_ID[def]
    end
    if not def or not animal then return nil end
    if def.soon then return "IGUI_PD_TrickSoon" end
    if def.stopCmd and CD.trickMemory(animal, def) then return nil end
    if def.needsBag and not CD.hasBag(animal) then return "IGUI_PD_TrickNeedsBag" end
    if not CD.breedHasTrick(animal, def.id) then return "IGUI_PD_TrickUnavailable" end
    if not CD.trickUnlocked(animal, def.id) then
        return "IGUI_PD_TrickLocked", tostring(def.minLevel), tostring(CD.trickLevel(animal))
    end
    if def.needsHeld and not CD.trickMemory(animal, def) and not CD.heldSniffItem(player) then
        return def.noItemKey or "IGUI_PD_TrickSniffNoItem"
    end
    return nil
end

---Button label; while the trick holds a scent, the stop label with the item name.
---@param animal IsoAnimal|nil
---@param def table|string trick def or id
---@return string label empty for an unknown trick
---@nodiscard
function CD.trickLabel(animal, def)
    if type(def) == "string" then
        def = CD.TRICK_BY_ID[def]
    end
    if not def then return "" end
    local mem = animal and CD.trickMemory(animal, def)
    if mem and def.stopKey then return getText(def.stopKey, mem.name or "?") end
    return getText(def.labelKey)
end

---Tooltip text in the species wording; the stop text while the trick holds a scent.
---@param animal IsoAnimal|nil
---@param def table|string trick def or id
---@return string description empty for an unknown trick
---@nodiscard
function CD.trickDescription(animal, def)
    if type(def) == "string" then
        def = CD.TRICK_BY_ID[def]
    end
    if not def then return "" end
    local mem = animal and CD.trickMemory(animal, def)
    if mem and def.stopDescKey then return CD.speciesText(animal, def.stopDescKey) end
    return CD.speciesText(animal, def.descKey)
end

---Server command to send: the stop command while the trick holds a scent.
---@param animal IsoAnimal|nil
---@param def table|string trick def or id
---@return string|nil command nil for an unknown trick
---@nodiscard
function CD.trickCommandFor(animal, def)
    if type(def) == "string" then
        def = CD.TRICK_BY_ID[def]
    end
    if not def then return nil end
    if animal and def.stopCmd and CD.trickMemory(animal, def) then return def.stopCmd end
    return def.cmd
end

---Obedience XP for an obeyed command, once per cooldown and boosted at low levels; server only.
---@param animal IsoAnimal
---@return boolean granted false on the client or during the cooldown
function CD.grantObedienceXP(animal)
    if isClient() then return false end
    local d = CD.data(animal)
    local now = CD.worldMinutes()
    if d.lastObeyXpMin and (now - d.lastObeyXpMin) < CD.OBEDIENCE_XP_COOLDOWN_MIN then return false end
    d.lastObeyXpMin = now
    local amount = CD.OBEDIENCE_XP_PER_CMD
    if CD.getSkillLevel(animal, "obedience") < CD.OBEDIENCE_EARLY_LEVEL then
        amount = amount * CD.OBEDIENCE_EARLY_MULT
    end
    CD.addSkillXP(animal, "obedience", amount)
    return true
end

---Lower with obedience level, higher while weak.
---@param animal IsoAnimal
---@return number chance 0..1 that the dog ignores an order
---@nodiscard
function CD.obeyFailChance(animal)
    local chance = CD.OBEY_FAIL_BASE - CD.OBEY_FAIL_PER_LEVEL * lvl(animal, "obedience")
    if CD.isWeak(animal) then
        chance = chance + CD.WEAK_OBEY_FAIL_ADD
    end
    return clamp(chance, 0, 1)
end

---@param animal IsoAnimal
---@param player IsoPlayer|nil who gets the refusal notice
---@return boolean disobeyed
function CD.rollDisobey(animal, player)
    if isClient() then return false end
    if CD.distractActive and CD.distractActive(animal) then
        if player then
            CD.notifyOwner(player, "refused", {
                reason = "distracted", name = CD.data(animal).name, breed = CD.getBreed(animal),
            })
        end
        return true
    end
    if not CD.obedienceFailureEnabled() then return false end
    if not CD.skillsEnabled() then return false end
    if not CD.breedCanLearnTricks(animal) then return false end
    local d = CD.data(animal)
    local nowMs = getTimestampMs()
    local lockMs = CD.OBEY_LOCK_MS
    if d.obeyLockUntilMs then
        local left = d.obeyLockUntilMs - nowMs
        if left > lockMs then
            d.obeyLockUntilMs = nil
        elseif left > 0 then
            if CD.DEBUG_OBEY then
                CD.log(string.format("[CD-OBEY] BLOQUEADO restam=%dms", left))
            end
            if player then
                CD.notifyOwner(player, "refused", {
                    reason = "distracted", name = d.name, breed = CD.getBreed(animal),
                })
            end
            return true
        else
            d.obeyLockUntilMs = nil
        end
    end
    if d.lastObeyFailMs and (nowMs - d.lastObeyFailMs) < CD.OBEY_FAIL_GRACE_MS then
        d.lastObeyFailMs = nil
        return false
    end
    local chance = CD.obeyFailChance(animal)
    local roll = ZombRand(0, 1000)
    if CD.DEBUG_OBEY then
        CD.log(string.format("[CD-OBEY] nivel=%d chance=%.0f%% dado=%d -> %s",
            CD.getSkillLevel(animal, "obedience"), chance * 100, roll,
            roll < chance * 1000 and "IGNOROU" or "obedeceu"))
    end
    if roll >= chance * 1000 then return false end
    d.lastObeyFailMs = nowMs
    d.obeyLockUntilMs = nowMs + lockMs
    CD.grantObedienceXP(animal)
    if CD.barkOnce then
        CD.barkOnce(animal)
    end
    if player then
        CD.notifyOwner(player, "refused", {
            reason = "distracted", name = d.name, breed = CD.getBreed(animal),
        })
    end
    return true
end

---The trick's XP to obedience, and to alsoSkill when given, once per trick cooldown; server only.
---@param animal IsoAnimal
---@param id string trick id
---@param alsoSkill string|nil
---@return boolean granted false on the client, for an unknown trick or during the cooldown
function CD.grantTrickXP(animal, id, alsoSkill)
    if isClient() then return false end
    local def = CD.TRICK_BY_ID[id]
    if not def then return false end
    local d = CD.data(animal)
    local now = CD.worldMinutes()
    d.trickXp = d.trickXp or {}
    local last = d.trickXp[id]
    if last and (now - last) < CD.TRICK_XP_COOLDOWN_MIN then return false end
    d.trickXp[id] = now
    CD.addSkillXP(animal, "obedience", def.xp)
    if alsoSkill then
        CD.addSkillXP(animal, alsoSkill, def.xp)
    end
    return true
end

---Drops the pending go-to target.
---@param animal IsoAnimal|nil
function CD.cancelTrickGoto(animal)
    if not animal then return end
    local d = CD.data(animal)
    if not d.gotoSpot then return end
    d.gotoSpot = nil
    d.gotoPathMs, d.gotoProbeMs, d.dbgGotoX, d.dbgGotoY = nil, nil, nil, nil
end
