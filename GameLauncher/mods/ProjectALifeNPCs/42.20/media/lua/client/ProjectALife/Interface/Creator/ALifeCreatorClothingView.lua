require "ProjectALife/Interface/Creator/ALifeCreatorCore"
require "ProjectALife/Records/ALifeClothingMaster"
require "ProjectALife/Records/ALifeClothingAdvisor"
require "ProjectALife/Records/ALifeClothingHealth"

local Creator = ProjectALife.CreatorScreen

local View = { showAll = false, headHeight = 26, stripOne = 16, stripTwo = 30, tallCard = 124 }
View.__index = View
Creator.clothingView = View

View.DOT = { { 0.30, 0.30, 0.33 }, { 0.84, 0.62, 0.22 }, { 0.62, 0.76, 0.34 }, { 0.30, 0.86, 0.46 } }
View.GROUP_AMBER = { offseason = true, role = true, era = true, novelty = true }
View.deadCache = {}

function View.collectionSize(collection)
    if type(collection) == "table" then return #collection end
    if collection ~= nil and collection.size ~= nil then
        local ok, size = pcall(collection.size, collection)
        if ok and type(size) == "number" then return size end
    end
    return 0
end

function Creator.slotIsDead(slot)
    local cached = View.deadCache[slot]
    if cached ~= nil then return cached end
    local dead = false
    local locations = Creator.clothingLocations ~= nil and Creator.clothingLocations[slot] or nil
    if type(getAllItemsForBodyLocation) == "function" and type(locations) == "table" and #locations > 0
            and not (Creator.moddedSlots ~= nil and Creator.moddedSlots[slot])
            and not (Creator.makeupItems ~= nil and Creator.makeupItems[slot] ~= nil) then
        dead = true
        for _, location in ipairs(locations) do
            local ok, items = pcall(getAllItemsForBodyLocation, location)
            if ok and View.collectionSize(items) > 0 then dead = false end
        end
        for id, target in pairs(Creator.extraLocations or {}) do
            if target == slot then dead = false end
        end
    end
    View.deadCache[slot] = dead
    return dead
end

function View.enabled()
    if Creator.clothingAdvice == false then return false end
    local prefs = ProjectALife.MenuPrefs
    if prefs ~= nil and type(prefs.creatorSeasonFilterOn) == "function" and not prefs.creatorSeasonFilterOn() then
        return false
    end
    local Master = ProjectALife.ClothingMaster
    return Master ~= nil and ProjectALife.ClothingAdvisor ~= nil and ProjectALife.ClothingHealth ~= nil
        and Master.available() == true
end

function View.open(window, slot, picker, search, all, selection, services)
    if not View.enabled() or window.currentProfile == nil then return nil end
    if slot == "Faces" or string.sub(tostring(slot), 1, 6) == "MakeUp" then return nil end
    local known = 0
    for _, entry in ipairs(all) do
        if entry.id ~= "none" and entry.id ~= "remove" and ProjectALife.ClothingMaster.has(entry.id) then known = known + 1 end
    end
    if known == 0 then return nil end
    local Advisor = ProjectALife.ClothingAdvisor
    local profile = window.currentProfile
    local letter = window.activeOutfit or "A"
    local self = setmetatable({ window = window, slot = slot, picker = picker, all = all, selection = selection,
        services = services, collisions = {}, decors = {}, tips = {}, plans = {}, confirmed = {}, arranged = {},
        season = Advisor.setSeason(profile, letter, window.seasonFixed == true),
        role = Advisor.role(profile, window.currentFaction) }, View)
    self.ctx = Advisor.context(slot, self.season, self.role, View.showAll)
    self.ratings = Advisor.ratingsFor(self.ctx)
    self:attach(search)
    return self
end

function View:attach(search)
    local px = Creator.px
    local picker = self.picker
    local x = ((search ~= nil and search.x) or px(300)) + ((search ~= nil and search.width) or px(500)) + px(12)
    local tick = ISTickBox:new(x, px(78), px(140), px(22), "", self, function(target, _, enabled)
        target:setShowAll(enabled == true)
    end)
    tick:initialise()
    tick:addOption("Show all items")
    tick:setSelected(1, View.showAll)
    picker:addChild(tick)
    self.tick = tick
    local labelX = x + px(150)
    self.summaryWidth = math.max(px(60), picker.width - labelX - px(24))
    self.summaryLabel = Creator.addLabel(picker, labelX, px(80), "", Creator.palette.MUTED)
end

function View:bind(redraw)
    self.redraw = redraw
end

function View:setShowAll(value)
    View.showAll = value == true
    self.ctx.showAll = View.showAll
    self.cellsKey = nil
    if self.redraw ~= nil then self.redraw() end
end

function View:summaryText(shown, hidden)
    if View.showAll then
        return "Everything is listed (" .. tostring(shown) .. "). Amber groups are off-season, off-role or novelty."
    end
    local seasonWord = self.season ~= nil and (string.lower(ProjectALife.ClothingHealth.SEASON_WORD[self.season]) .. " set")
        or "any-season set"
    local role = self.role ~= nil and self.role.kind or "civilian"
    return seasonWord .. ", " .. role .. ": " .. tostring(shown) .. " shown, " .. tostring(hidden)
        .. " hidden. SHOW ALL lists every item."
end

function View:filter(query)
    query = tostring(query or "")
    local key = query .. "|" .. (View.showAll and "1" or "0")
    if self.cellsKey == key and self.cells ~= nil then return self.cells end
    local Advisor = ProjectALife.ClothingAdvisor
    self.ctx.showAll = View.showAll
    local flag = View.showAll and "1" or "0"
    local arranged = self.arranged[flag]
    if arranged == nil then
        arranged = Advisor.arrange(self.all, self.ctx, self.ratings)
        self.arranged[flag] = arranged
    end
    local built = Advisor.narrow(arranged, query)
    local cells = {}
    for _, section in ipairs(built.sections) do
        if section.title ~= nil then
            cells[#cells + 1] = { heading = section.title, count = #section.items, amber = View.GROUP_AMBER[section.id] == true }
        end
        for _, entry in ipairs(section.items) do cells[#cells + 1] = entry end
    end
    if built.shown == 0 and built.hidden > 0 then
        cells[#cells + 1] = { heading = "NO MATCH IN THIS VIEW - SHOW ALL FINDS " .. tostring(built.hidden) .. " MORE",
            count = 0, amber = true, note = true }
    end
    if self.summaryLabel ~= nil then
        local hiddenTotal, listed = 0, 0
        for _, entry in ipairs(self.all) do
            local rating = self.ratings[entry.id]
            if rating ~= nil and not rating.excluded and not rating.fixed then
                if rating.group == nil then hiddenTotal = hiddenTotal + 1 end
                if View.showAll or rating.group ~= nil then listed = listed + 1 end
            end
        end
        self.summaryLabel:setName(Creator.fitText(self:summaryText(listed, hiddenTotal), UIFont.Small, self.summaryWidth))
    end
    self.cells, self.cellsKey, self.built = cells, key, built
    return cells
end

function View:paginate(cells, columns, cardW, cardH, gap, areaW, areaH)
    local headH = Creator.px(View.headHeight)
    local pages, page = {}, { items = {}, heads = {} }
    local col, y, current = 0, 0, nil
    local function newPage(continued)
        pages[#pages + 1] = page
        page = { items = {}, heads = {} }
        col, y = 0, 0
        if continued and current ~= nil then
            page.heads[#page.heads + 1] = { title = current.heading .. " (CONTINUED)", count = current.count,
                amber = current.amber, x = 0, y = 0, w = areaW, h = headH }
            y = headH + gap
        end
    end
    for _, cell in ipairs(cells) do
        if cell.heading ~= nil then
            if col > 0 then
                y = y + cardH + gap
                col = 0
            end
            if y + headH + gap + (cell.note and 0 or cardH) > areaH + 2 and (#page.items > 0 or #page.heads > 0) then
                newPage(false)
            end
            page.heads[#page.heads + 1] = { title = cell.heading, count = cell.count, amber = cell.amber, note = cell.note,
                x = 0, y = y, w = areaW, h = headH }
            y = y + headH + gap
            current = cell
        else
            if col == 0 and y + cardH > areaH + 2 and (#page.items > 0 or #page.heads > 0) then newPage(true) end
            page.items[#page.items + 1] = { item = cell, x = col * (cardW + gap), y = y, w = cardW, h = cardH }
            col = col + 1
            if col >= columns then
                col = 0
                y = y + cardH + gap
            end
        end
    end
    pages[#pages + 1] = page
    return pages
end

function View:layout(cells, page, columns, areaW, areaH, cardW, cardH, gap)
    local key = table.concat({ columns, areaW, areaH, cardW, cardH, gap }, ":")
    local cached = self.plans
    if cached.cells ~= cells or cached.key ~= key then
        cached.cells, cached.key = cells, key
        cached.pages = self:paginate(cells, columns, cardW, cardH, gap, areaW, areaH)
    end
    local count = #cached.pages
    page = math.max(1, math.min(page, count))
    local current = cached.pages[page]
    return { pages = count, page = page, items = current.items, heads = current.heads }
end

function View:headings(area, plan, cards)
    local px = Creator.px
    for _, head in ipairs(plan.heads) do
        local panel = ISPanel:new(head.x, head.y, head.w, head.h)
        panel:initialise()
        panel.backgroundColor = { r = 0.045, g = 0.058, b = 0.066, a = 0.95 }
        panel.borderColor = { r = 0.115, g = 0.145, b = 0.152, a = 1 }
        panel.head = head
        panel.prerender = function(self)
            ISPanel.prerender(self)
            local info = self.head
            local palette = Creator.palette
            local r, g, b = palette.ROSE.r, palette.ROSE.g, palette.ROSE.b
            if info.amber then r, g, b = 0.92, 0.62, 0.25 end
            if info.fitted == nil then info.fitted = Creator.fitText(info.title, UIFont.Small, self.width - px(90)) end
            self:drawRect(0, self.height - 2, self.width, 2, 0.8, r, g, b)
            self:drawText(info.fitted, px(10), px(4), r, g, b, 1, UIFont.Small)
            if not info.note then
                if info.countText == nil then
                    info.countText = tostring(info.count) .. (info.count == 1 and " item" or " items")
                end
                self:drawTextRight(info.countText, self.width - px(10), px(4), palette.MUTED.r, palette.MUTED.g,
                    palette.MUTED.b, 1, UIFont.Small)
            end
        end
        area:addChild(panel)
        cards[#cards + 1] = panel
    end
end

function View:collision(item)
    if item.id == "none" or item.id == "remove" then return nil end
    local cached = self.collisions[item.id]
    if cached ~= nil then return cached or nil end
    local services = self.services
    local outfit = services ~= nil and type(services.outfit) == "function" and services.outfit(self.window) or nil
    local found = ProjectALife.ClothingHealth.collisionFor(item, outfit, self.slot, services)
    self.collisions[item.id] = found or false
    return found
end

function View:info(item)
    local rating = self.ratings[item.id]
    if rating == nil then
        rating = ProjectALife.ClothingAdvisor.rate(item, self.ctx)
        self.ratings[item.id] = rating
    end
    return rating
end

function View:decor(item)
    local cached = self.decors[item.id]
    if cached ~= nil then return cached end
    local Advisor = ProjectALife.ClothingAdvisor
    local rating = self:info(item)
    local rec = rating.rec
    local decor = { rec = rec }
    if rec ~= nil then
        decor.tags = Advisor.tags(rec)
        local words = Advisor.flagWords(rec)
        local hide = rating.hideReason
        local parts = {}
        if hide ~= nil and hide ~= "novelty" then parts[1] = Advisor.HIDE_WORD[hide] or string.upper(hide) end
        for _, word in ipairs(words) do parts[#parts + 1] = word end
        decor.flagLine = table.concat(parts, "  ")
        decor.markWord = parts[1]
    end
    local found = self:collision(item)
    if found ~= nil then decor.collide = "COLLIDES WITH " .. string.upper(found[1].name) end
    self.decors[item.id] = decor
    return decor
end

function View:tooltipFor(item)
    local cached = self.tips[item.id]
    if cached ~= nil then return cached end
    local text = ProjectALife.ClothingAdvisor.tooltip(item, self:info(item), self.ctx, self:collision(item))
    self.tips[item.id] = text
    return text
end

function View:decorate(card, choose)
    local px = Creator.px
    card.stripH = card.height >= px(View.tallCard) and px(View.stripTwo) or px(View.stripOne)
    local tip = self:tooltipFor(card.item)
    if tip ~= nil and tip ~= "" then Creator.addTooltip(choose, tip) end
end

function View:paintStrip(card, decor, y)
    local px = Creator.px
    local tags = decor.tags
    local size, gap = px(8), px(3)
    local x = px(6)
    for index = 1, 4 do
        local color = View.DOT[(tags.dots[index] or 0) + 1]
        card:drawRect(x, y + px(4), size, size, 1, color[1], color[2], color[3])
        if self.season == index then
            card:drawRectBorder(x - 1, y + px(3), size + 2, size + 2, 1, 0.9, 0.92, 0.9)
        end
        x = x + size + gap
    end
    local palette = Creator.palette
    card:drawText(tags.warmth, x + px(3), y, palette.TEXT.r, palette.TEXT.g, palette.TEXT.b, 1, UIFont.Small)
    local right = card.width - px(6)
    if tags.rain then
        card:drawTextRight("R", right, y, 0.45, 0.65, 1, 1, UIFont.Small)
        right = right - px(14)
    end
    if tags.wind then card:drawTextRight("W", right, y, 0.55, 0.85, 0.95, 1, UIFont.Small) end
end

function View:paint(card)
    local item = card.item
    if item == nil or item.id == "none" or item.id == "remove" then return end
    local px = Creator.px
    local decor = self:decor(item)
    local picked = card.selection ~= nil and card.selection[item.id] == true
    local stripH = card.stripH or 0
    local rowY = card.height - px(50) - stripH + px(8)
    if decor.tags ~= nil then self:paintStrip(card, decor, rowY) end
    local collide = (not picked) and decor.collide or nil
    if collide ~= nil then
        card:drawRect(0, 0, card.width, card.height, 0.10, 0.9, 0.1, 0.1)
        card:drawRectBorder(0, 0, card.width, card.height, 0.9, 0.95, 0.12, 0.12)
        card:drawTextCentre(Creator.fitText(collide, UIFont.Small, card.width - px(8)), card.width / 2, px(5),
            1, 0.22, 0.22, 1, UIFont.Small)
    end
    if decor.tags ~= nil and decor.flagLine ~= "" and not picked then
        if stripH >= px(View.stripTwo) then
            card:drawText(Creator.fitText(decor.flagLine, UIFont.Small, card.width - px(10)), px(6), rowY + px(14),
                0.92, 0.62, 0.25, 1, UIFont.Small)
        elseif collide == nil and decor.markWord ~= nil then
            card:drawTextCentre(Creator.fitText(decor.markWord, UIFont.Small, card.width - px(8)), card.width / 2, px(5),
                0.92, 0.62, 0.25, 1, UIFont.Small)
        end
    end
end

function View:guard(item, selected, proceed)
    if selected == true or item == nil or self.confirmed[item.id] then return false end
    local found = self:collision(item)
    if found == nil then return false end
    if ISModalDialog == nil or type(ISModalDialog.new) ~= "function" then return false end
    local px = Creator.px
    local name = ProjectALife.ClothingAdvisor.nameOf(item.id)
    if item.label ~= nil and item.label ~= "" then name = tostring(item.label) end
    local text = ProjectALife.ClothingHealth.collisionMessage(name, found) .. "\nPick it anyway?"
    local modal = ISModalDialog:new(0, 0, px(520), px(170), text, true, { view = self, id = item.id, proceed = proceed },
        function(subject, button)
            if button.internal ~= "YES" then return end
            subject.view.confirmed[subject.id] = true
            subject.proceed()
        end, nil)
    modal:initialise()
    modal:addToUIManager()
    modal.moveWithMouse = true
    modal:setAlwaysOnTop(true)
    modal:bringToTop()
    return true
end

return View
