require "TimedActions/ISReadABook"

-- Sandbox variable functions

-- Sandbox Blacklist
-- This will run on each readStart
function ISReadABook:setSkillBlacklist()
    self.skillBlacklistCache = {}
    local sandboxBlacklist = SandboxVars.SkillBooksGiveXP.SkillBlacklist
    -- Example: converts "Woodwork;Cooking;Fishing" into { Woodwork = true, Cooking = true, Fishing = true }
    if sandboxBlacklist and sandboxBlacklist ~= "" then
        for skillName in string.gmatch(sandboxBlacklist, "([^;]+)") do
            self.skillBlacklistCache[string.trim(skillName)] = true
        end
    end
end

-- Getter
function ISReadABook:getSkillBlacklist()
    return self.skillBlacklistCache
end

-- Sandbox Book Volume limit
-- Set a maximum volume limit so higher book volumes do not award XP
function ISReadABook:getBookVolumeLimit()
    return SandboxVars.SkillBooksGiveXP.BookVolumeLimit
end

-- Sandbox: limit skill books to only grant the first level trained, not both
function ISReadABook:isLimitedToFirstLevel()
    return SandboxVars.SkillBooksGiveXP.LimitToFirstLevel == true
end

-- Calculate how much xp does the player get per page v2
function ISReadABook:getXpPerPage(level1, level2, perk, numberOfPages)
    local perkObj = PerkFactory.getPerk(perk)
    local totalXp = perkObj:getXpForLevel(level1)

    if not self:isLimitedToFirstLevel() then
        totalXp = totalXp + perkObj:getXpForLevel(level2)
    end

    return math.ceil((totalXp / numberOfPages) * 100) / 100
end

-- -- Calculate how much xp does the player get per page v1
-- function ISReadABook:getXpPerPage(level1, level2, perk, numberOfPages)
--     return math.ceil(((PerkFactory.getPerk(perk):getXpForLevel(level1) + PerkFactory.getPerk(perk):getXpForLevel(level2)) / numberOfPages ) * 100) / 100
-- end

-- Initialize the counter for MP
function ISReadABook:initPageReadDuringSession()
    self.pageReadDuringSession = self.item:getAlreadyReadPages()
end

-- Getter
function ISReadABook:getPageReadDuringSession()
    return self.pageReadDuringSession
end

-- Setter
function ISReadABook:setPageReadDuringSession(pages)
    self.pageReadDuringSession = pages
end

-- Required to initialize the pages reda during session
local vanillaBookStart = ISReadABook.start
function ISReadABook:start()
    self:initPageReadDuringSession()
    self:setSkillBlacklist()
    vanillaBookStart(self)
end

-- Extension of update function to calculate single player turn page
local vanillaBookUpdate = ISReadABook.update
function ISReadABook:update()
    vanillaBookUpdate(self)
    if SkillBook[self.item:getSkillTrained()] ~= nil then
        self:awardReadingXP()
    end
end

-- Function that adds xp to the player
function ISReadABook:awardReadingXP()

    local currentPage = self.item:getAlreadyReadPages()
    local perk = SkillBook[self.item:getSkillTrained()].perk;
    local blacklist = self:getSkillBlacklist()
    local lvlSkillTrained = self.item:getLvlSkillTrained()
    local levelFromBookLimit = self:getBookVolumeLimit() * 2

    if currentPage > self:getPageReadDuringSession() and not blacklist[tostring(perk)] and lvlSkillTrained < levelFromBookLimit then
        local pages = currentPage - self:getPageReadDuringSession()
        self:setPageReadDuringSession(currentPage)

        local numberOfPages = self.item:getNumberOfPages()
        local xpAmount = self:getXpPerPage(lvlSkillTrained, (lvlSkillTrained + 1), perk, numberOfPages) * pages

        if isClient() then
            local args = {}
            args.perk = tostring(perk)
            args.xpAmount = xpAmount
            sendClientCommand(self.character, "SBGXP", "AddXP", args)
        else
        addXpNoMultiplier(self.character, perk, xpAmount)
        end

        local haloXpText = perk:getName() .. " " .. string.format("%.1f", xpAmount) -- Rounding to avoid displaying too many decimals
        HaloTextHelper.addTextWithArrow(self.character, haloXpText, true, HaloTextHelper.getColorGreen())
    end
end

-- OnClientCommand Event to add xp on servers
function ISReadABook.awardReadingXPOnServer(module, command, player, args)
    if module == "SBGXP" and command == "AddXP" then
        local perk = PerkFactory.Perks.FromString(args.perk)
        addXpNoMultiplier(player, perk, args.xpAmount)
    end
end

Events.OnClientCommand.Add(ISReadABook.awardReadingXPOnServer)