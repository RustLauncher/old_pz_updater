require "ProjectALife/Core/ALifeText"
require "ProjectALife/Talk/ALifeTalkUi"
require "ProjectALife/Visitors/ALifeVisitorSchema"
require "ProjectALife/Visitors/ALifeVisitorInstance"
require "ProjectALife/Visitors/ALifeVisitorPeople"

ProjectALife = ProjectALife or {}

local Text = ProjectALife.Text
local Instance = ProjectALife.VisitorInstance
local People = ProjectALife.VisitorPeople

local Panel = {
    tabOrder = { "talk", "past", "now", "house", "world", "offer", "closer" },
    limits = { rows = 60, label = 80, text = 200, bytes = 6000, tabs = 8, events = 6, seen = 24, notes = 24, worn = 24 },
    staleMs = 4000, retryMs = 700, retryMax = 12, refreshMs = 5000,
    statuses = { open = true, new = true, asked = true, later = true },
    needWords = { hunger = "hungry", thirst = "thirsty", cold = "shivering", fear = "frightened", fatigue = "worn out",
        sick = "grey-faced", pain = "in pain" },
    needWants = { hunger = "something to eat", thirst = "water", cold = "warmth", fatigue = "rest", sick = "medicine",
        pain = "something for the pain" },
    EMPTY = {},
    visitGroup = { id = "Personal", label = "Visit", visitor = true, plain = true },
    lookGroup = { id = "look", label = "Look", plain = true },
    mirror = { at = -100000, on = false },
    metrics = { attached = 0, taken = 0, stale = 0, rejected = 0, tabRequests = 0 },
    wantTable = {
    wn_food = { "NOW_HUNGRY", "something to eat" },
    wn_hot_meal = { "NOW_HUNGRY", "a hot meal" },
    wn_water = { "NOW_THIRSTY", "water" },
    wn_coffee = { "NOW_WANT", "a cup of coffee" },
    wn_rest = { "NOW_TIRED", "some rest" },
    wn_bed = { "HOUSE_BED", "a bed for the night" },
    wn_shower = { "HOUSE_BATH", "a shower" },
    wn_wash = { "NOW_WASH", "to wash up" },
    wn_change_clothes = { "NOW_CLOTHES", "clean clothes" },
    wn_blanket = { "NOW_COLD", "a blanket" },
    wn_warm_stove = { "HOUSE_STOVE", "a warm stove" },
    wn_boots = { "NOW_SHOES", "better boots" },
    wn_glasses = { "NOW_GLASSES", "glasses" },
    wn_bandage = { "NOW_HURT", "a bandage" },
    wn_pain_pills = { "NOW_HURT", "something for the pain" },
    wn_medicine = { "NOW_SICK", "medicine" },
    wn_medicine_for_son = { "NOW_PARTNER", "medicine for a son" },
    wn_medicine_for_wife = { "NOW_PARTNER", "medicine for a wife" },
    wn_cigarettes = { "NOW_SMOKE", "cigarettes" },
    wn_tobacco = { "NOW_SMOKE", "tobacco" },
    wn_lighter = { "NOW_SMOKE", "a lighter" },
    wn_drink = { "NOW_DRINK", "a drink" },
    wn_the_shakes_to_stop = { "NOW_CRAVING", "the shakes to stop" },
    wn_news_of_army = { "WORLD_ARMY", "news of the Army" },
    wn_news_of_town = { "WORLD_TOWN", "news of the town" },
    wn_news_of_family = { "PAST_FAMILY", "news of family" },
    wn_radio = { "HOUSE_RADIO", "a radio" },
    wn_tv = { "HOUSE_TV", "a television" },
    wn_phone = { "HOUSE_PHONE", "a phone" },
    wn_directions = { "NOW_ROAD", "directions" },
    wn_map = { "OFFER_MAP", "a map" },
    wn_ride = { "NOW_PLAN", "a ride" },
    wn_gas = { "WORLD_TRUCKS", "gasoline" },
    wn_company = { "TALK_QUIET", "company" },
    wn_quiet = { "TALK_QUIET", "quiet" },
    wn_time_alone = { "TALK_QUIET", "time alone" },
    wn_to_be_useful = { "NOW_HELP", "to be useful" },
    wn_work = { "NOW_HELP", "work to do" },
    wn_tools = { "NOW_HELP", "tools" },
    wn_forgiveness = { "PAST_REGRET", "forgiveness" },
    wn_to_be_believed = { "NOW_TRUST", "to be believed" },
    wn_to_talk = { "TALK_STORY", "to talk" },
    wn_church = { "HOUSE_PRAYER", "a church" },
    wn_prayer = { "HOUSE_PRAYER", "a moment to pray" },
    wn_book = { "HOUSE_BOOK", "a book" },
    wn_cards = { "OFFER_CARDS", "a game of cards" },
    wn_music = { "TALK_MUSIC", "music" },
    wn_pen_paper = { "NOW_WANT", "pen and paper" },
    wn_letter_delivered = { "NOW_WANT", "a letter delivered" },
    wn_find_family = { "PAST_FAMILY", "to find family" },
    wn_find_him = { "NOW_PLAN", "to find someone" },
    wn_to_bury_someone = { "PAST_LOST", "to bury someone" },
    wn_safe_place = { "HOUSE_SAFE", "a safe place" },
    wn_lock_doors = { "HOUSE_LOCKS", "doors that lock" },
    wn_candle = { "OFFER_CANDLE", "a candle" },
    wn_batteries = { "OFFER_BATTERIES", "batteries" },
    wn_seeds = { "NOW_PLAN", "seeds" },
    wn_dog_food = { "PAST_PETS", "food for a dog" },
    wn_hat = { "NOW_WANT", "a hat" },
    wn_photo_kept_safe = { "PAST_PHOTO", "a photo kept safe" },
    wn_to_leave_before_dark = { "NOW_LEAVE", "to leave before dark" },
    wn_to_stay_the_winter = { "NOW_STAY", "to stay the winter" },
    wn_to_stay_a_few_nights = { "NOW_STAY", "to stay a few nights" },
    wn_to_get_home = { "NOW_DEST", "to get home" },
    wn_to_cross_the_river = { "NOW_DEST", "to cross the river" },
    wn_to_reach_louisville = { "NOW_DEST", "to reach Louisville" },
    wn_to_see_a_doctor = { "WORLD_HOSPITAL", "to see a doctor" },
    wn_a_door_that_locks = { "HOUSE_LOCKS", "a door that locks" },
    wn_quiet_corner = { "TALK_QUIET", "a quiet corner" },
    wn_to_be_forgiven_by_son = { "PAST_SON", "forgiveness from a son" },
    },
}
ProjectALife.VisitorPanel = Panel

Panel.needOrder = { "hunger", "thirst", "cold", "fear", "fatigue", "sick", "pain" }
Panel.wantOrder = { "hunger", "thirst", "cold", "fatigue", "sick", "pain" }

function Panel.now()
    if type(getTimestampMs) ~= "function" then return 0 end
    return getTimestampMs()
end

function Panel.clean(text, limit)
    if type(text) ~= "string" then return nil end
    local shown = string.gsub(text, "[%c<>]", " ")
    if #shown > limit then shown = string.sub(shown, 1, limit) end
    return shown
end

function Panel.validId(id)
    return type(id) == "string" and #id <= 64 and string.match(id, "^[%w_:%.%-]+$") ~= nil
end

function Panel.person(record)
    if type(record) ~= "table" or type(record.memory) ~= "table" then return nil end
    local person = record.memory.person
    if type(person) ~= "table" or type(person.id) ~= "string" then return nil end
    return person
end

function Panel.isVisitor(record)
    return Panel.person(record) ~= nil
end

function Panel.valid(menu)
    if type(menu) ~= "table" or menu.v ~= 1 or tonumber(menu.rev) == nil then return false end
    if type(menu.header) ~= "table" or type(menu.tabs) ~= "table" or type(menu.rows) ~= "table" then return false end
    local bytes = 0
    for index = 1, #menu.rows do
        local row = menu.rows[index]
        if type(row) == "table" then bytes = bytes + #tostring(row.label or "") + #tostring(row.id or "") + 24 end
    end
    return bytes <= Panel.limits.bytes
end

function Panel.cleanTabs(list)
    local tabs = {}
    for index = 1, #list do
        local tab = list[index]
        if #tabs >= #Panel.tabOrder then break end
        if type(tab) == "table" and Panel.validId(tab.id) and tab.id ~= "look" and tab.id ~= "Personal" then
            tabs[#tabs + 1] = { id = tab.id, label = Panel.clean(tab.label, 24) or tab.id,
                count = math.max(0, math.floor(tonumber(tab.count) or 0)), new = math.max(0, math.floor(tonumber(tab.new) or 0)) }
        end
    end
    return tabs
end

function Panel.buildRows(list, tab)
    local rows, marks = {}, {}
    if type(list) ~= "table" then return rows, marks end
    for index = 1, #list do
        if #rows >= Panel.limits.rows then break end
        local row = list[index]
        if type(row) == "table" and Panel.validId(row.id) and string.sub(row.id, 1, 3) == "VQ_" then
            local label = Panel.clean(row.label, Panel.limits.label)
            if label ~= nil and label ~= "" then
                local status = Panel.statuses[row.st] and row.st or "open"
                rows[#rows + 1] = { id = row.id, text = label, st = status, visitor = true, tab = tab }
                if status ~= "open" then
                    marks[row.id] = { asked = status == "asked", new = status == "new", later = status == "later" }
                end
            end
        end
    end
    return rows, marks
end

function Panel.pendingOf(source)
    if type(source) ~= "table" or type(source.id) ~= "string" or #source.id > 48
            or string.match(source.id, "^[%w_]+$") == nil or type(source.choices) ~= "table" then return nil end
    local prompt = Panel.clean(source.prompt, Panel.limits.text)
    if prompt == nil or prompt == "" then return nil end
    local choices = {}
    for index = 1, #source.choices do
        local item = source.choices[index]
        local number = type(item) == "table" and tonumber(item.i) or nil
        local label = type(item) == "table" and Panel.clean(item.label, Panel.limits.label) or nil
        if number ~= nil and number >= 1 and number <= 9 and number % 1 == 0 and label ~= nil and label ~= ""
                and #choices < Panel.limits.events then
            choices[#choices + 1] = { i = number, label = label }
        end
    end
    if #choices == 0 then return nil end
    return { id = source.id, prompt = prompt, choices = choices, cancel = source.cancel ~= false }
end

function Panel.pendingRows(pending)
    local rows = {}
    for index = 1, #pending.choices do
        local item = pending.choices[index]
        rows[index] = { id = "EV:" .. pending.id .. ":" .. tostring(item.i), text = item.label, visitor = true, event = true }
    end
    if pending.cancel then
        rows[#rows + 1] = { id = "EV:" .. pending.id .. ":0", text = Text.ui("Not now"), visitor = true, event = true }
    end
    return rows
end

function Panel.picker(source)
    if type(source) ~= "table" or type(source.token) ~= "string" or #source.token > 256 or type(source.rows) ~= "table" then
        return nil
    end
    local rows = {}
    for index, row in ipairs(source.rows) do
        if index > 256 then break end
        if type(row) == "table" and type(row.name) == "string" and #row.name <= 160 and type(row.count) == "number"
                and row.count > 0 and row.count <= 256 and type(row.itemId) == "number" and row.itemId == row.itemId
                and row.itemId % 1 == 0 then
            rows[#rows + 1] = { name = row.name, count = row.count, itemId = row.itemId }
        end
    end
    if #rows == 0 then return nil end
    return { token = source.token, rows = rows }
end

function Panel.pickerRows(picker)
    local rows = {}
    for index, row in ipairs(picker.rows) do
        rows[index] = { id = picker.intent, text = row.name .. " x" .. tostring(row.count), itemId = row.itemId, gift = true }
    end
    rows[#rows + 1] = { id = "GIFT_CANCEL", text = Text.ui("Cancel"), localOnly = true }
    return rows
end

function Panel.newState()
    return { menu = nil, rev = -1, at = 0, rows = {}, marks = {}, tabs = nil, groups = nil, pending = nil, pendingRows = nil,
        promptId = nil, opened = false, seen = {}, pollAt = Panel.now(), retries = 0,
        header = { name = nil, desc = nil, opinion = nil, lines = {} } }
end

function Panel.attach(panel, args, record)
    if type(panel) ~= "table" then return false end
    local state = panel.visitor
    if state == nil then
        local offered = type(args) == "table" and type(args.visitorMenu) == "table"
        if not offered and not Panel.isVisitor(record) then return false end
        state = Panel.newState()
        panel.visitor = state
        Panel.metrics.attached = Panel.metrics.attached + 1
    end
    if type(args) == "table" then Panel.take(panel, state, args) end
    Panel.rebuild(panel)
    return true
end

function Panel.take(panel, state, args)
    local menu = args.visitorMenu
    if type(args.searchItems) == "table" then Panel.noteSeen(state, args.searchItems) end
    if type(menu) ~= "table" then return false end
    if not Panel.valid(menu) then
        Panel.metrics.rejected = Panel.metrics.rejected + 1
        return false
    end
    local now = Panel.now()
    if state.menu ~= nil and menu.rev < state.rev and now - state.at < Panel.staleMs then
        Panel.metrics.stale = Panel.metrics.stale + 1
        return false
    end
    Panel.metrics.taken = Panel.metrics.taken + 1
    state.menu, state.rev, state.at = menu, menu.rev, now
    state.tabs = Panel.cleanTabs(menu.tabs)
    if type(menu.tab) == "string" and Panel.validId(menu.tab) then
        state.rows[menu.tab], state.marks[menu.tab] = Panel.buildRows(menu.rows, menu.tab)
        if not state.opened and panel.doorPeer ~= true then panel.topic, panel.page = menu.tab, 1 end
    end
    state.opened = true
    local header = menu.header
    local shown = Panel.clean(header.name, Panel.limits.label)
    if shown ~= nil and shown ~= "" then
        panel.npcName, panel.known = shown, true
    else
        panel.npcName, panel.known = nil, false
    end
    state.header.name = panel.npcName
    state.header.desc = Panel.clean(header.desc, Panel.limits.text) or state.header.desc
    state.header.opinion = type(header.opinion) == "table" and header.opinion or nil
    panel.descWrap, state.subFor = nil, nil
    if state.header.opinion ~= nil and type(args.opinion) ~= "table" then panel.opinion = state.header.opinion end
    local pending = Panel.pendingOf(menu.pending)
    state.pending = pending
    if pending ~= nil then
        state.pendingRows = Panel.pendingRows(pending)
        panel.pending = "VISITOR_EVENT"
        if state.promptId ~= pending.id then
            state.promptId = pending.id
            panel:append(pending.prompt, panel:shownName())
        end
    else
        state.pendingRows, state.promptId = nil, nil
        if panel.pending == "VISITOR_EVENT" then panel.pending = nil end
    end
    Panel.takeOffer(panel, args.offer)
    if type(panel.refreshTitle) == "function" then panel:refreshTitle() end
    return true
end

function Panel.takeOffer(panel, offer)
    if type(offer) ~= "table" then return end
    local picker = Panel.picker(offer.picker)
    if picker ~= nil and type(panel.lastIntent) == "string" then
        picker.intent = panel.lastIntent
        panel.giftPicker = picker
        panel:append(Text.ui("Choose what to hand over"), "A-LIFE")
    elseif picker == nil then
        panel:append(Text.ui("You have nothing to hand over for that right now."), "A-LIFE")
    end
end

function Panel.noteSeen(state, items)
    local list = {}
    for index = 1, #items do
        local item = items[index]
        if #list >= Panel.limits.seen then break end
        if type(item) == "table" and type(item.name) == "string" and type(item.count) == "number" and item.count > 0 then
            list[#list + 1] = item.name .. " x" .. tostring(item.count)
        end
    end
    state.seen = list
end

function Panel.buildGroups(panel, state)
    local groups = {}
    if panel.doorPeer == true then groups[1] = Panel.visitGroup end
    local tabs = state.tabs
    if tabs == nil or #tabs == 0 then
        groups[#groups + 1] = { id = "talk", label = "Talk", count = 0, new = 0 }
    else
        for index = 1, #tabs do groups[#groups + 1] = tabs[index] end
    end
    groups[#groups + 1] = Panel.lookGroup
    local capacity = (panel.tabs ~= nil and #panel.tabs > 0) and #panel.tabs or 100
    while #groups > capacity and #groups > 1 do table.remove(groups, #groups == 2 and 2 or #groups - 1) end
    state.groups = groups
    return groups
end

function Panel.groups(panel)
    local state = panel.visitor
    if state == nil then return Panel.EMPTY end
    return state.groups or Panel.buildGroups(panel, state)
end

function Panel.slots(panel)
    return #Panel.tabOrder + 1 + (panel.doorPeer == true and 1 or 0)
end

function Panel.badge(group)
    if group.plain == true then return "" end
    local count = tonumber(group.count) or 0
    if count <= 0 then return nil end
    local fresh = tonumber(group.new) or 0
    if fresh > 0 then return tostring(count) .. " +" .. tostring(fresh) end
    return tostring(count)
end

function Panel.syncTabs(panel)
    local tabs, groups = panel.tabs, Panel.groups(panel)
    if tabs == nil then return false end
    local menu = ProjectALife.TalkMenu
    local cinema = panel.isCinema == true
    local width = (panel.width - 32) / math.max(1, math.min(#groups, #tabs))
    for index = 1, #tabs do
        local tab, group = tabs[index], groups[index]
        if group ~= nil then
            tab.topic, tab.new, tab.badgeText = group.id, group.new or 0, Panel.badge(group)
            tab.count = group.plain == true and 1 or group.count or 0
            tab:setVisible(true)
            local label = menu.groupLabel(group)
            if not cinema then
                if tab.new > 0 then label = label .. " +" .. tostring(tab.new) end
                tab:setX(16 + (index - 1) * width)
                tab:setWidth(width - 4)
            end
            tab:setTitle(label)
        else
            tab.topic, tab.new, tab.badgeText, tab.count = nil, 0, nil, 0
            tab:setVisible(false)
        end
    end
    return true
end

function Panel.rebuild(panel)
    local state = panel.visitor
    local groups = Panel.buildGroups(panel, state)
    local found = false
    for index = 1, #groups do
        if groups[index].id == panel.topic then found = true end
    end
    if not found then panel.topic, panel.page = groups[1].id, 1 end
    if state.header.desc == nil then
        local record = ProjectALife.TalkMenu.recordFor(panel.uid)
        local person = Panel.person(record)
        local card = person ~= nil and People.card(person.id) or nil
        if card ~= nil then
            state.header.desc = Panel.clean(card.desc, Panel.limits.text)
            panel.descWrap, state.subFor = nil, nil
        end
    end
    if panel.tabs ~= nil then Panel.syncTabs(panel) end
end

function Panel.owns(panel, topic)
    local state = panel.visitor
    if state == nil then return false end
    if state.pending ~= nil or type(panel.giftPicker) == "table" then return true end
    return topic ~= nil and topic ~= "Personal"
end

function Panel.rows(panel, topic)
    local state = panel.visitor
    if state == nil then return Panel.EMPTY end
    if type(panel.giftPicker) == "table" then return Panel.pickerRows(panel.giftPicker) end
    if state.pending ~= nil then return state.pendingRows end
    if topic == "look" then return Panel.lookRows(panel, state) end
    return state.rows[topic] or Panel.EMPTY
end

function Panel.marks(panel, topic)
    local state = panel.visitor
    if state == nil or state.pending ~= nil or topic == "look" then return Panel.EMPTY end
    return state.marks[topic] or Panel.EMPTY
end

function Panel.poll(panel, now)
    local state = panel.visitor
    if state == nil or panel.waitingAt ~= nil or panel.interrupted or type(panel.send) ~= "function" then return false end
    local missing = state.menu == nil
    if now - state.pollAt < (missing and Panel.retryMs or Panel.refreshMs) then return false end
    if missing and state.retries >= Panel.retryMax then return false end
    state.pollAt = now
    if missing then state.retries = state.retries + 1 end
    local topic = panel.topic
    panel:send("talkChoose", { uid = panel.uid, choice = "VT_TAB", tab = (topic ~= "look" and topic ~= "Personal") and topic or nil })
    return true
end

function Panel.onTab(panel)
    local state = panel.visitor
    if state == nil or panel.topic == "look" or panel.topic == "Personal" or state.pending ~= nil then return false end
    if type(panel.send) ~= "function" then return false end
    Panel.metrics.tabRequests = Panel.metrics.tabRequests + 1
    panel:send("talkChoose", { uid = panel.uid, choice = "VT_TAB", tab = panel.topic })
    return true
end

function Panel.decorate(panel, args, choice)
    if panel.visitor == nil then return args end
    if panel.topic ~= "Personal" and panel.topic ~= "look" then args.tab = panel.topic end
    if args.gift ~= nil and type(choice) == "table" and string.sub(tostring(choice.id), 1, 3) == "VQ_" then
        args.args = { gift = args.gift }
    end
    return args
end

function Panel.header(panel)
    local state = panel.visitor
    if state == nil then return nil end
    return state.header
end

function Panel.subtitle(panel, width)
    local state = panel.visitor
    local desc = state ~= nil and state.header.desc or nil
    if desc == nil then return "" end
    if state.subFor ~= width then
        state.subFor = width
        state.subText = ProjectALife.TalkMenu.clip(desc, width)
    end
    return state.subText
end

function Panel.doLine(panel, record, trust)
    local provider = ProjectALife.VisitorDoLines
    local state = panel.visitor
    if state == nil or provider == nil or type(provider.lines) ~= "function" then return nil end
    local list = provider.lines(record, { trust = trust, shell = panel.shell, door = panel.doorPeer == true,
        turn = panel.doTurns or 0, previous = panel.doLine })
    state.header.lines = list
    if type(list) ~= "table" or #list == 0 then return nil end
    return list[1], "visitor", list[1]
end

function Panel.wornNames(shell)
    local names = {}
    if shell == nil or type(shell.getWornItems) ~= "function" then return names end
    local worn = shell:getWornItems()
    if worn == nil or type(worn.size) ~= "function" or type(worn.getItemByIndex) ~= "function" then return names end
    for index = 0, math.min(worn:size(), Panel.limits.worn) - 1 do
        local item = worn:getItemByIndex(index)
        if item ~= nil and type(item.getDisplayName) == "function" then
            local name = item:getDisplayName()
            if type(name) == "string" and name ~= "" then names[#names + 1] = name end
        end
    end
    return names
end

function Panel.heldNames(shell)
    local names = {}
    if shell == nil then return names end
    local hands = { "getPrimaryHandItem", "getSecondaryHandItem" }
    for index = 1, #hands do
        local method = shell[hands[index]]
        if type(method) == "function" then
            local item = method(shell)
            local name = item ~= nil and type(item.getDisplayName) == "function" and item:getDisplayName() or nil
            if type(name) == "string" and name ~= "" and names[1] ~= name then names[#names + 1] = name end
        end
    end
    return names
end

function Panel.worldHours()
    if type(getGameTime) ~= "function" then return nil end
    local clock = getGameTime()
    if clock == nil or type(clock.getWorldAgeHours) ~= "function" then return nil end
    return clock:getWorldAgeHours()
end

function Panel.looks(person)
    local words = {}
    for index = 1, #Panel.needOrder do
        local name = Panel.needOrder[index]
        if Instance.need(person, name) >= 3 then words[#words + 1] = Text.ui(Panel.needWords[name]) end
    end
    if Instance.need(person, "dirty") >= 3 then
        words[#words + 1] = Text.ui("dirty")
    elseif Instance.cleanState(person, Panel.worldHours()) == "fresh" then
        words[#words + 1] = Text.ui("freshly washed")
    end
    return words
end

function Panel.wants(record, key)
    local out = {}
    local person = Panel.person(record)
    if person == nil then return out end
    local card = People.card(person.id)
    local row = key ~= nil and Instance.vt(person, key, false) or nil
    if card ~= nil and row ~= nil then
        for index = 1, #card.wants do
            local info = Panel.wantTable[card.wants[index].id]
            if info ~= nil and (Instance.asked(row, "VQ_" .. info[1])) > 0 then out[#out + 1] = Text.ui(info[2]) end
        end
    end
    for index = 1, #Panel.wantOrder do
        local name = Panel.wantOrder[index]
        if Instance.need(person, name) >= 3 then
            local phrase = Text.ui(Panel.needWants[name])
            local present = false
            for slot = 1, #out do
                if out[slot] == phrase then present = true end
            end
            if not present then out[#out + 1] = phrase end
        end
    end
    return out
end

function Panel.notes(record, key)
    local out = {}
    local person = Panel.person(record)
    if person == nil or key == nil then return out end
    local card = People.card(person.id)
    local row = Instance.vt(person, key, false)
    if card == nil or row == nil then return out end
    local known = Instance.facts(row)
    for index = 1, #known do
        local fact = card.facts[known[index]]
        if fact ~= nil and type(fact.label) == "string" and fact.label ~= "" and #out < Panel.limits.notes then
            out[#out + 1] = fact.label
        end
    end
    return out
end

function Panel.look(record, shell, state)
    local person = Panel.person(record)
    local view = { desc = state ~= nil and state.header.desc or nil, worn = Panel.wornNames(shell), held = Panel.heldNames(shell),
        looks = {}, wants = {}, notes = {}, seen = state ~= nil and state.seen or {}, hasBody = shell ~= nil }
    if person == nil then return view end
    view.looks = Panel.looks(person)
    local speech = ProjectALife.Speech
    local key = nil
    if speech ~= nil and type(speech.localPlayers) == "function" then
        local players = speech.localPlayers()
        key = players[1] ~= nil and speech.playerKey(players[1]) or nil
    end
    view.wants, view.notes = Panel.wants(record, key), Panel.notes(record, key)
    return view
end

function Panel.addInfo(rows, text)
    rows[#rows + 1] = { id = "VIEW_" .. tostring(#rows + 1), text = text, tip = text, info = true, visitor = true }
end

function Panel.viewRows(view)
    local rows = {}
    if view.desc ~= nil then Panel.addInfo(rows, view.desc) end
    if #view.worn > 0 then
        Panel.addInfo(rows, Text.ui("Wearing: {list}", { list = table.concat(view.worn, ", ") }))
    elseif view.hasBody then
        Panel.addInfo(rows, Text.ui("Wearing: nothing you can make out"))
    end
    if #view.held > 0 then Panel.addInfo(rows, Text.ui("Holding: {list}", { list = table.concat(view.held, ", ") })) end
    if #view.looks > 0 then Panel.addInfo(rows, Text.ui("They look: {list}", { list = table.concat(view.looks, ", ") })) end
    if #view.wants > 0 then Panel.addInfo(rows, Text.ui("They could use: {list}", { list = table.concat(view.wants, ", ") })) end
    if #view.seen > 0 then Panel.addInfo(rows, Text.ui("Seen in their bags: {list}", { list = table.concat(view.seen, ", ") })) end
    for index = 1, #view.notes do
        Panel.addInfo(rows, Text.ui("You know: {note}", { note = view.notes[index] }))
    end
    if #rows == 0 then Panel.addInfo(rows, Text.ui("Nothing to see yet.")) end
    return rows
end

function Panel.lookRows(panel, state)
    local record = ProjectALife.TalkMenu.recordFor(panel.uid)
    return Panel.viewRows(Panel.look(record, panel.shell, state))
end

function Panel.mirrors(shell, uid)
    if uid == nil or tostring(uid) == "" then return false end
    local now = Panel.now()
    local mirror = Panel.mirror
    if now - mirror.at > 5000 or now < mirror.at then
        local schema = ProjectALife.VisitorSchema
        local options = schema ~= nil and type(schema.options) == "function" and schema.options() or nil
        mirror.at, mirror.on = now, type(options) == "table" and options.chatMirror == true
    end
    if not mirror.on then return false end
    local menu = ProjectALife.TalkMenu
    local record = menu ~= nil and type(menu.recordFor) == "function" and menu.recordFor(tostring(uid)) or nil
    return Panel.isVisitor(record)
end

function Panel.offer(record, kind, payload)
    local prompt = ProjectALife.TalkPrompt
    local shell = type(payload) == "table" and payload.shell or nil
    if prompt == nil or type(prompt.note) ~= "function" or type(record) ~= "table" or record.uid == nil then return false end
    if kind ~= "start" and kind ~= "answer" then return false end
    return prompt.note(shell, "?", "directed", record.uid) == true
end

function Panel.withdraw(record, kind)
    local prompt = ProjectALife.TalkPrompt
    if prompt == nil or type(prompt.forget) ~= "function" or type(record) ~= "table" or record.uid == nil then return false end
    prompt.forget(record.uid)
    return true
end

function Panel.qaLine()
    local m = Panel.metrics
    return "[ALIFE-QA] VisitorPanel attached=" .. tostring(m.attached) .. " taken=" .. tostring(m.taken) .. " stale=" .. tostring(m.stale)
        .. " rejected=" .. tostring(m.rejected) .. " tabRequests=" .. tostring(m.tabRequests)
end

return Panel
