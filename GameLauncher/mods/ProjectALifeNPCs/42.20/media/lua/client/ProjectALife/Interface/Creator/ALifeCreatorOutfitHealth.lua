require "ProjectALife/Interface/Creator/ALifeCreatorCore"
require "ProjectALife/Records/ALifeClothingMaster"
require "ProjectALife/Records/ALifeClothingAdvisor"
require "ProjectALife/Records/ALifeClothingHealth"

local Creator = ProjectALife.CreatorScreen

local Badge = { interval = 250, frames = 0, GREEN = { 0.30, 0.86, 0.46 }, AMBER = { 0.92, 0.62, 0.25 },
    GREY = { 0.35, 0.37, 0.38 } }
Creator.outfitHealth = Badge

function Badge.now()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    Badge.frames = Badge.frames + 1
    return Badge.frames * 16
end

function Badge.services()
    return { collide = Creator.locationsCollide, locationOf = Creator.itemBodyLocation }
end

function Badge.enabled()
    if Creator.clothingAdvice == false then return false end
    local prefs = ProjectALife.MenuPrefs
    if prefs ~= nil and type(prefs.creatorSeasonFilterOn) == "function" and not prefs.creatorSeasonFilterOn() then
        return false
    end
    local Master = ProjectALife.ClothingMaster
    return Master ~= nil and ProjectALife.ClothingHealth ~= nil and Master.available() == true
end

function Badge.signature(window, letter)
    local profile = window.currentProfile
    local outfit = profile.outfits ~= nil and profile.outfits[letter] or nil
    local season = profile.outfitSeason ~= nil and profile.outfitSeason[letter] or ""
    if outfit == nil then return "missing@" .. tostring(season) end
    return ProjectALife.ClothingHealth.signature(outfit, Creator.clothingOrder) .. "@" .. tostring(season)
end

function Badge.evaluate(window, letter)
    local profile = window.currentProfile
    local outfit = profile.outfits ~= nil and profile.outfits[letter] or nil
    if outfit == nil then return nil end
    local Advisor = ProjectALife.ClothingAdvisor
    local season = Advisor.setSeason(profile, letter, window.seasonFixed == true)
    local role = Advisor.role(profile, window.currentFaction)
    return ProjectALife.ClothingHealth.evaluate(outfit, season, role, Badge.services()), season, role
end

function Badge.refresh(window, force)
    local state = window.healthState
    if state == nil then
        state = { checked = -1000000, letters = {}, context = "" }
        window.healthState = state
    end
    local now = Badge.now()
    if not force and now >= state.checked and now - state.checked < Badge.interval then return state end
    state.checked = now
    local profile = window.currentProfile
    state.enabled = Badge.enabled()
    if profile == nil or not state.enabled then
        state.letters = {}
        state.context = ""
        return state
    end
    local general = profile.general or {}
    local bloc = window.currentFaction ~= nil and window.currentFaction.relations ~= nil
        and window.currentFaction.relations.bloc or ""
    local context = tostring(general.npcClass) .. "|" .. tostring(bloc) .. "|" .. tostring(window.seasonFixed)
    local contextChanged = context ~= state.context
    state.context = context
    for _, letter in ipairs(Creator.outfitIds) do
        local signature = Badge.signature(window, letter)
        local entry = state.letters[letter]
        if contextChanged or entry == nil or entry.signature ~= signature then
            local result, season, role = Badge.evaluate(window, letter)
            entry = { signature = signature, result = result, season = season, role = role }
            entry.status = Badge.statusOf(entry)
            entry.line = Badge.lineFor(letter, entry)
            local tab = window.outfitButtons ~= nil and window.outfitButtons[letter] or nil
            if tab ~= nil and result ~= nil then
                Creator.addTooltip(tab, ProjectALife.ClothingHealth.detail(result, season))
            end
            state.letters[letter] = entry
            state.recomputed = (state.recomputed or 0) + 1
            if letter == (window.activeOutfit or "A") then state.activeChanged = true end
        end
    end
    return state
end

function Badge.statusOf(entry)
    if entry == nil or entry.result == nil or entry.result.empty then return "grey" end
    if entry.result.ok then return "green" end
    return "amber"
end

function Badge.lineFor(letter, entry)
    if entry == nil or entry.result == nil then return letter .. ": no clothing data" end
    local text = letter .. ": " .. ProjectALife.ClothingHealth.summary(entry.result, entry.season)
    if not entry.result.ok and not entry.result.empty then text = text .. " - " .. entry.result.issues[1].text end
    return text
end

function Badge.color(status)
    if status == "green" then return Badge.GREEN end
    if status == "amber" then return Badge.AMBER end
    return Badge.GREY
end

function Badge.activeEntry(window)
    local state = window.healthState
    if state == nil then return nil end
    return state.letters[window.activeOutfit or "A"]
end

function Badge.summaryLine(window)
    local entry = Badge.activeEntry(window)
    if entry == nil then return (window.activeOutfit or "A") .. ": no clothing data" end
    return entry.line
end

function Badge.syncControls(window)
    local entry = Badge.activeEntry(window)
    local signature = entry ~= nil and entry.signature or ""
    if window.healthShown == signature then return end
    window.healthShown = signature
    if window.healthBadge ~= nil then
        local detail = entry ~= nil and ProjectALife.ClothingHealth.detail(entry.result, entry.season)
            or "No clothing data for this set."
        Creator.addTooltip(window.healthBadge, detail)
    end
    if window.healthFixButton ~= nil and window.healthFixButton.setEnable ~= nil then
        local fixable = entry ~= nil and entry.result ~= nil and not entry.result.ok and not entry.result.empty
        window.healthFixButton:setEnable(fixable == true)
    end
end

function Badge.install(window, appearance, formW, outfitsY)
    if window.healthBadge ~= nil then return end
    local px = Creator.px
    local width = math.max(px(60), formW - px(110) - px(132))
    local badge = ISButton:new(px(110), outfitsY - px(2), width, px(19), "", appearance, function() end)
    badge:initialise()
    badge:instantiate()
    badge.displayBackground = false
    badge.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    badge.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    badge.window = window
    badge.prerender = function(self)
        local owner = self.window
        Badge.refresh(owner)
        if owner.healthState.enabled ~= true then
            if owner.healthShown ~= "off" then
                owner.healthShown = "off"
                if self.window.healthFixButton ~= nil and self.window.healthFixButton.setEnable ~= nil then
                    self.window.healthFixButton:setEnable(false)
                end
            end
            return
        end
        Badge.syncControls(owner)
        local entry = Badge.activeEntry(owner)
        local color = Badge.color(entry ~= nil and entry.status or "grey")
        self:drawRect(0, px(5), px(9), px(9), 1, color[1], color[2], color[3])
        local line = Badge.summaryLine(owner)
        if self.fitSource ~= line or self.fitWidth ~= self.width then
            self.fitSource, self.fitWidth = line, self.width
            self.fitted = Creator.fitText(line, UIFont.Small, self.width - px(16))
        end
        local palette = Creator.palette
        self:drawText(self.fitted, px(14), px(1), palette.TEXT.r, palette.TEXT.g, palette.TEXT.b, 1, UIFont.Small)
    end
    appearance:addChild(badge)
    window.healthBadge = badge
    window.healthFixButton = Creator.addButton(appearance, formW - px(124), outfitsY - px(5), px(112), "SUGGEST FIX",
        function() Badge.openFix(window) end, true)
    Creator.addTooltip(window.healthFixButton,
        "Proposes replacements for the first problem of this outfit set. Nothing changes until you press APPLY on a proposal.")
    for _, id in ipairs(Creator.outfitIds) do
        local tab = window.outfitButtons ~= nil and window.outfitButtons[id] or nil
        if tab ~= nil then
            local original = tab.prerender
            tab.healthId, tab.healthWindow = id, window
            tab.prerender = function(self)
                if original ~= nil then original(self) end
                local state = self.healthWindow.healthState
                if state == nil or state.enabled ~= true then return end
                local entry = state.letters[self.healthId]
                local color = Badge.color(entry ~= nil and entry.status or "grey")
                self:drawRect(self.width - px(11), self.height - px(9), px(6), px(6), 1, color[1], color[2], color[3])
            end
        end
    end
    Badge.refresh(window, true)
end

function Badge.closeFix(window)
    local panel = window.healthFixPanel
    if panel == nil then return end
    panel:setVisible(false)
    pcall(function() window:removeChild(panel) end)
    window.healthFixPanel = nil
    if window.itemPreviewProfile ~= nil then
        window.itemPreviewProfile = nil
        Creator.refreshAvatar(window)
    end
end

function Badge.proposals(window)
    local entry = Badge.activeEntry(window)
    if entry == nil or entry.result == nil or entry.result.ok then return nil, {} end
    local issue = entry.result.issues[1]
    local profile = window.currentProfile
    local outfit = profile.outfits[window.activeOutfit or "A"]
    local list = ProjectALife.ClothingHealth.suggest(issue, outfit, entry.season, entry.role, Badge.services(), 4)
    return issue, list
end

function Badge.preview(window, proposal)
    window.itemPreviewProfile = Creator.itemPreview(window.currentProfile, "clothing", proposal.slot, proposal.value,
        window.activeOutfit or "A")
    Creator.refreshAvatar(window)
end

function Badge.apply(window, proposal)
    local combo = window.clothingCombos ~= nil and window.clothingCombos[proposal.slot] or nil
    if combo == nil then return false end
    Creator.selectData(combo, proposal.value)
    local tints = Creator.currentOutfitTints(window)
    if tints ~= nil then tints[proposal.slot] = nil end
    window.itemPreviewProfile = nil
    Creator.showOutfit(window, window.activeOutfit or "A")
    if window.syncLoadoutTiles ~= nil then window.syncLoadoutTiles() end
    Badge.refresh(window, true)
    Badge.closeFix(window)
    return true
end

function Badge.openFix(window)
    Badge.closeFix(window)
    Badge.refresh(window, true)
    local issue, list = Badge.proposals(window)
    if issue == nil then return nil end
    local px = Creator.px
    local width = math.min(px(640), window.width - px(32))
    local height = px(150) + #list * px(54)
    local panel = Creator.createFramedPanel(window, math.floor((window.width - width) / 2),
        math.max(px(8), math.floor((window.height - height) / 3)), width, height)
    window.healthFixPanel = panel
    panel:bringToTop()
    Creator.addLabel(panel, px(16), px(12), "SUGGESTED FIX FOR OUTFIT " .. (window.activeOutfit or "A"), Creator.palette.ROSE,
        UIFont.Medium)
    Creator.addLabel(panel, px(16), px(42), Creator.fitText(issue.text, UIFont.Small, width - px(32)), Creator.palette.TEXT)
    Creator.addLabel(panel, px(16), px(62), "Nothing changes until you press APPLY. PREVIEW shows it on the character.",
        Creator.palette.MUTED)
    local y = px(92)
    if #list == 0 then
        Creator.addLabel(panel, px(16), y, "No automatic proposal for this issue. Use the slot picker (SHOW ALL) and choose by hand.",
            Creator.palette.MUTED)
        y = y + px(30)
    end
    for _, proposal in ipairs(list) do
        local verb = proposal.id == nil and "REMOVE" or (proposal.replaces ~= nil and "REPLACE" or "ADD")
        local name = proposal.name or proposal.replaces or "item"
        local text = verb .. " " .. string.upper(name) .. " (" .. proposal.slot .. ")"
        if proposal.note ~= nil then text = text .. " - " .. proposal.note end
        Creator.addLabel(panel, px(16), y + px(4), Creator.fitText(text, UIFont.Small, width - px(260)), Creator.palette.TEXT)
        Creator.addButton(panel, width - px(236), y, px(104), "PREVIEW", function() Badge.preview(window, proposal) end)
        Creator.addButton(panel, width - px(124), y, px(104), "APPLY", function() Badge.apply(window, proposal) end, true)
        y = y + px(54)
    end
    Creator.addButton(panel, width - px(124), height - px(44), px(104), "CLOSE", function() Badge.closeFix(window) end)
    window.healthFixProposals = list
    return panel
end

return Badge
