ProjectALife = ProjectALife or {}
require "ProjectALife/Talk/ALifeDialogueData"

local Intents = {
    threshold = 30,
    expansions = {
        u = "you", ya = "you", yall = "you all", ur = "your", r = "are", y = "why",
        yea = "yes", yeah = "yes", yep = "yes", yup = "yes", ye = "yes", yas = "yes",
        aye = "yes", sure = "yes sure", ok = "ok", okay = "ok", k = "ok", kk = "ok", okey = "ok",
        nah = "no", nope = "no", naw = "no", nay = "no",
        wanna = "want to", gonna = "going to", gotta = "got to", lemme = "let me", gimme = "give me",
        dunno = "do not know", kinda = "kind of", sorta = "sort of", outta = "out of",
        dont = "do not", doesnt = "does not", didnt = "did not", cant = "can not", cannot = "can not",
        wont = "will not", isnt = "is not", arent = "are not", wasnt = "was not", werent = "were not",
        havent = "have not", hasnt = "has not", shouldnt = "should not", wouldnt = "would not", couldnt = "could not",
        im = "i am", ive = "i have", ill = "i will", id = "i would", youre = "you are", youve = "you have",
        youll = "you will", hes = "he is", shes = "she is", theyre = "they are",
        whats = "what is", wheres = "where is", whos = "who is", hows = "how is", whens = "when is",
        whys = "why is", thats = "that is", theres = "there is", heres = "here is", lets = "let us",
        its = "it is", thx = "thanks", ty = "thanks", thanx = "thanks", pls = "please", plz = "please",
        bro = "brother", dude = "man", fam = "family", bc = "because", cuz = "because", coz = "because",
        rn = "right now", idk = "i do not know", wtf = "what the fuck", omg = "oh my god", lol = "haha",
        lmao = "haha", hehe = "haha", hahaha = "haha", hah = "haha", westpoint = "west point",
        zeds = "zombies", zed = "zombie", zombs = "zombies", biters = "zombies", biter = "zombie",
    },
    cache = {},
    metrics = { classified = 0, unknown = 0 },
}
ProjectALife.TalkIntents = Intents

function Intents.normalize(text)
    local value = string.lower(tostring(text or ""))
    value = string.gsub(value, "'", "")
    value = string.gsub(value, "[^a-z0-9 ]", " ")
    local words = {}
    for word in string.gmatch(value, "%S+") do
        local expanded = Intents.expansions[word]
        words[#words + 1] = expanded or word
    end
    return table.concat(words, " ")
end

function Intents.doorFor(text, intent)
    if intent == "NPC_OPEN" or intent == "GREETING" then return "DOOR_WHO" end
    if intent == "DOOR_WHO" or intent == "DOOR_LEAVE" or intent == "DOOR_LEAVE_RUDE" or intent == "DOOR_GIVE"
            or intent == "DOOR_CENSUS_CLEAR" or intent == "DOOR_CENSUS_BITTEN" or intent == "DOOR_WEAPONS_DOWN"
            or intent == "DOOR_SEARCH" or intent == "DOOR_INVITE" or intent == "GUEST_LEAVE" or intent == "DOOR_TREAT"
            or intent == "DOOR_PAY" or intent == "DOOR_BLUFF" or intent == "DOOR_CALLSIGN" or intent == "DOOR_JOB"
            or intent == "DOOR_LEND" or intent == "DOOR_HAND_GUNS" or intent == "DOOR_TREAT_ME" then return intent end
    if intent == "DOOR_ASK_A" or intent == "DOOR_ASK_B" or intent == "DOOR_ASK_C" or intent == "DOOR_ASK_ID"
            or intent == "DOOR_THANK" or intent == "DOOR_KEEP" or intent == "DOOR_HAGGLE" then return intent end
    if intent == "DOOR_NEED" or intent == "DOOR_HEALTH" or intent == "DOOR_COMPANY" or intent == "DOOR_STAY"
            or intent == "DOOR_WHAT" then return intent end
    local words = Intents.normalize(text)
    if words == "what brings you here" then return "DOOR_WHO" end
    if words == "what do you need" or words == "what do you need from me" then return "DOOR_NEED" end
    if words == "what exactly do you need" or words == "what do you need it for" then return "DOOR_WHAT" end
    if words == "are you hurt" or words == "are you bitten" or words == "are you hurt or bitten" then return "DOOR_HEALTH" end
    if words == "did you come alone" or words == "are you alone" then return "DOOR_COMPANY" end
    if words == "how long do you need to stay" then return "DOOR_STAY" end
    if words == "who is it" or words == "who are you" then return "DOOR_WHO" end
    if words == "leave" or words == "go away" or words == "no thanks" then return "DOOR_LEAVE" end
    if words == "fuck off" then return "DOOR_LEAVE_RUDE" end
    if words == "give food" then return "DOOR_GIVE" end
    if words == "search them" or words == "search you" or words == "let me search you" then return "DOOR_SEARCH" end
    if words == "put your weapons down" or words == "put your weapon down" or words == "drop your weapon"
            or words == "lower your weapon" then return "DOOR_WEAPONS_DOWN" end
    if words == "come in" or words == "you can stay the night" then return "DOOR_INVITE" end
    if words == "time to go" or words == "its time for you to go" then return "GUEST_LEAVE" end
    if words == "no known bites" then return "DOOR_CENSUS_CLEAR" end
    if words == "someone has been bitten" then return "DOOR_CENSUS_BITTEN" end
    return nil
end

local function normalizedPattern(pattern)
    local cached = Intents.cache[pattern]
    if cached == nil then
        cached = Intents.normalize(pattern)
        Intents.cache[pattern] = cached
    end
    return cached
end

local function countWords(value)
    local n = 0
    for _ in string.gmatch(value, "%S+") do n = n + 1 end
    return n
end

local function containsPhrase(padded, phrase)
    if phrase == "" then return false end
    return string.find(padded, " " .. phrase .. " ", 1, true) ~= nil
end

function Intents.score(entry, normalized)
    if type(entry) ~= "table" or normalized == "" then return 0 end
    local padded = " " .. normalized .. " "
    for _, group in ipairs(entry.none or {}) do
        for _, word in ipairs(group) do
            if containsPhrase(padded, normalizedPattern(word)) then return -1 end
        end
    end
    local best = 0
    for _, pattern in ipairs(entry.patterns or {}) do
        local p = normalizedPattern(pattern)
        if p == normalized then
            best = math.max(best, 100)
        elseif containsPhrase(padded, p) then
            best = math.max(best, 60 + math.min(20, countWords(p) * 4))
        end
    end
    if #(entry.all or {}) > 0 then
        local satisfied = true
        for _, group in ipairs(entry.all) do
            local hit = false
            for _, word in ipairs(group) do
                if containsPhrase(padded, normalizedPattern(word)) then hit = true; break end
            end
            if not hit then satisfied = false; break end
        end
        if satisfied then best = math.max(best, 40 + 5 * #entry.all) end
    end
    return best
end

function Intents.classify(text, pending, data)
    data = data or ProjectALife.DialogueData
    if data ~= nil and type(data.load) == "function" then data.load() end
    local normalized = Intents.normalize(text)
    Intents.metrics.classified = Intents.metrics.classified + 1
    if normalized == "" or data == nil then
        Intents.metrics.unknown = Intents.metrics.unknown + 1
        return nil, 0
    end
    local bestId, bestScore, bestPriority = nil, 0, -1
    local wordCount = countWords(normalized)
    for _, entry in ipairs(data.intents or {}) do
        local score = Intents.score(entry, normalized)
        if entry.id == "REPEAT" and wordCount > 2 and score < 100 then score = 0 end
        if pending == true and (entry.id == "YES" or entry.id == "NO") and score > 0 then
            score = score + 1000
        end
        local priority = tonumber(entry.priority) or 0
        if score > bestScore or (score == bestScore and score > 0 and priority > bestPriority) then
            bestId, bestScore, bestPriority = entry.id, score, priority
        end
    end
    if bestScore < Intents.threshold then
        Intents.metrics.unknown = Intents.metrics.unknown + 1
        return nil, bestScore
    end
    return bestId, bestScore
end

function Intents.townIn(text)
    local normalized = " " .. Intents.normalize(text) .. " "
    local regions = ProjectALife.TownRegions
    if regions == nil or type(regions.definitions) ~= "table" then return nil end
    for _, definition in ipairs(regions.definitions) do
        local label = Intents.normalize(definition.label)
        if string.find(normalized, " " .. label .. " ", 1, true) ~= nil then return definition end
    end
    return nil
end

function Intents.reset()
    Intents.cache = {}
    Intents.metrics = { classified = 0, unknown = 0 }
end

Intents.groups = {
    { id = "Personal", label = "Talk" },
    { id = "World", label = "Ask" },
    { id = "Supplies", label = "Supplies" },
}
Intents.groupAlias = { Talk = "Personal", Ask = "World", Trade = "Supplies" }
Intents.exclusiveAnswers = {}

function Intents.contextual(id)
    return function(view)
        local social = type(view) == "table" and view.social or nil
        return type(social) == "table" and type(social.ctx) == "table" and social.ctx[id] == true
    end
end

function Intents.whenSocial(view)
    local social = type(view) == "table" and view.social or nil
    return type(social) == "table" and social.on == true
end

function Intents.followHidden(choice)
    if type(choice) ~= "table" or (choice.id ~= "WALK_WITH_ME" and choice.id ~= "ORDER_FOLLOW") then return false end
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    return not (type(vars) == "table" and vars.Talk_FollowOptions == true)
end

Intents.choices = {
    { id = "NPC_OPEN", text = "", words = "", hidden = true },
    { id = "DOOR_WHO", text = "What brings you here?", words = "what brings you here", topic = "Personal", door = true },
    { id = "DOOR_NEED", text = "What do you need from me?", words = "what do you need", topic = "Personal", door = true },
    { id = "DOOR_WHAT", text = "What exactly do you need?", words = "what exactly do you need", topic = "Personal", door = true },
    { id = "DOOR_HEALTH", text = "Are you hurt or bitten?", words = "are you hurt or bitten", topic = "Personal", door = true },
    { id = "DOOR_COMPANY", text = "Did you come alone?", words = "did you come alone", topic = "Personal", door = true },
    { id = "DOOR_STAY", text = "How long do you need to stay?", words = "how long do you need to stay", topic = "Personal", door = true },
    { id = "DOOR_ASK_A", text = "Tell me more", words = "tell me more about it", topic = "Personal", door = true },
    { id = "DOOR_ASK_B", text = "Anything else?", words = "anything else to tell me", topic = "Personal", door = true },
    { id = "DOOR_ASK_C", text = "What should I know?", words = "what should i know about this", topic = "Personal", door = true },
    { id = "DOOR_ASK_ID", text = "Can I see some ID?", words = "can i see some id", topic = "Personal", door = true },
    { id = "DOOR_THANK", text = "Thank you", words = "thank you so much for this", topic = "Personal", door = true },
    { id = "DOOR_KEEP", text = "Keep some of it, you earned it", words = "keep some of it", topic = "Personal", door = true },
    { id = "DOOR_HAGGLE", text = "Can we make it less?", words = "can we make it less", topic = "Personal", door = true },
    { id = "DOOR_GIVE", text = "I can spare some food [give one item]", words = "give food", topic = "Personal", door = true },
    { id = "DOOR_TRADE", text = "What have you got to trade?", words = "show me a trade", topic = "Personal", door = true },
    { id = "DOOR_TRADE_CONFIRM", text = "Agreed, let's swap [confirm trade]", words = "confirm displayed trade", topic = "Personal", door = true },
    { id = "DOOR_TRADE_CANCEL", text = "No deal, I'll keep my things", words = "cancel this trade", topic = "Personal", door = true },
    { id = "DOOR_WEAPONS_DOWN", text = "Put the weapon away before we talk", words = "put your weapons down", topic = "Personal", door = true },
    { id = "DOOR_SEARCH", text = "Let me check what you're carrying [search]", words = "search them", topic = "Personal", door = true },
    { id = "DOOR_CENSUS_CLEAR", text = "Here's who's home, no bites that we know of", words = "no known bites", topic = "Personal", door = true },
    { id = "DOOR_CENSUS_BITTEN", text = "Here's who's home... someone has been bitten", words = "someone has been bitten", topic = "Personal", door = true },
    { id = "DOOR_INVITE", text = "You can come inside", words = "come in", topic = "Personal", door = true },
    { id = "DOOR_TREAT", text = "Let me help with that [use bandage or disinfectant]", words = "let me treat that", topic = "Personal", door = true },
    { id = "DOOR_JOB", text = "Alright, I'll help [accept job]", words = "ill do it", topic = "Personal", door = true },
    { id = "DOOR_LEND", text = "You can borrow a tool [lend one]", words = "take a tool", topic = "Personal", door = true },
    { id = "DOOR_HAND_GUNS", text = "Take them [hand over held weapons]", words = "take my weapons", topic = "Personal", door = true },
    { id = "DOOR_TREAT_ME", text = "Have a look at me [pay two supplies]", words = "check me over", topic = "Personal", door = true },
    { id = "DOOR_CALLSIGN", text = "What's your callsign?", words = "whats your callsign", topic = "Personal", door = true },
    { id = "DOOR_PAY", text = "Take it and leave us alone [pay three supplies]", words = "here take it", topic = "Personal", door = true },
    { id = "DOOR_BLUFF", text = "We're armed and there are more of us. Walk away.", words = "walk away", topic = "Personal", door = true },
    { id = "GUEST_LEAVE", text = "It's time for you to leave", words = "time to go", topic = "Personal", door = true },
    { id = "DOOR_LEAVE", text = "I can't help you, please leave", words = "please leave", topic = "Personal", door = true },
    { id = "DOOR_LEAVE_RUDE", text = "Get the hell away from my home!", words = "get away", topic = "Personal", door = true },
    { id = "GREETING", text = "Good to see another person.", words = "hello", topic = "Personal", hidden = true,
        variants = { "Hey. Good to see somebody alive.", "Didn't expect company out here.", "Mind if we talk a minute?" } },
    { id = "HOW_ARE_YOU", text = "How are you holding up?", words = "how are you", topic = "Personal", show = Intents.whenSocial,
        variants = { "How are you holding up?", "You doing alright?", "How's it going out here?" } },
    { id = "ASK_OKAY", text = "Are you hurt? You don't look right", words = "are you hurt", topic = "Personal",
        show = Intents.contextual("ASK_OKAY"),
        variants = { "Are you hurt? You don't look right", "Hey, you okay? Anything broken?", "Easy. You hurt?" } },
    { id = "OFFER_HELP", text = "Need a hand with that?", words = "do you need help", topic = "Personal",
        show = Intents.contextual("OFFER_HELP"),
        variants = { "Need a hand with that?", "Let me help you, sit down a second", "Can I do anything for you?" } },
    { id = "ENCOURAGE", text = "Hang in there, you're still standing", words = "hang in there", topic = "Personal",
        show = Intents.contextual("ENCOURAGE"),
        variants = { "Hang in there, you're still standing", "Breathe. It's over for now", "You're alright, I've got you" } },
    { id = "THANKS", text = "Thanks, I mean it", words = "thanks", topic = "Personal", show = Intents.contextual("THANKS"),
        variants = { "Thanks, I mean it", "I appreciate that", "Thanks for that" } },
    { id = "SORRY", text = "Sorry, that came out wrong", words = "sorry", topic = "Personal", show = Intents.contextual("SORRY"),
        variants = { "Sorry, that came out wrong", "My bad, I'll back off", "Didn't mean to push" } },
    { id = "FAREWELL", text = "Take care. See you around", words = "goodbye", topic = "Personal", show = Intents.contextual("FAREWELL"),
        variants = { "Take care. See you around", "I'll let you get back to it", "Later, stay alive" } },
    { id = "ASK_JOB_BEFORE", text = "What did you do before all this?", words = "what was your job before", topic = "Personal" },
    { id = "TELL_STORY", text = "You got a story? I could use a distraction.", words = "tell me a story", topic = "Personal" },
    { id = "ASK_FAMILY", text = "You got family out there?", words = "do you have family", topic = "Personal" },
    { id = "ASK_MISS", text = "What do you miss most?", words = "what do you miss", topic = "Personal" },
    { id = "ASK_GROUP", text = "Who are you running with?", words = "who are you with", topic = "Personal" },
    { id = "ASK_ABOUT_ME", text = "What have you heard about me?", words = "what have you heard about me", topic = "Personal" },
    { id = "ASK_HOME", text = "Where do you live?", words = "where do you live", topic = "Personal" },
    { id = "WALK_WITH_ME", text = "Walk with me for a while?", words = "walk with me", topic = "Personal", friendly = true },
    { id = "WALK_STOP", text = "Thanks, that's far enough.", words = "thats far enough", topic = "Personal" },
    { id = "ASK_DESTINATION", text = "Where are you headed?", words = "where are you going", topic = "Personal" },
    { id = "JOIN_REQUEST", text = "Maybe we can work together?", words = "can i join your group", topic = "Personal", friendly = true },
    { id = "ASK_NAME", text = "What's your name?", words = "what is your name", topic = "World", untilKnown = true },
    { id = "ASK_NEWS", text = "Heard anything around here?", words = "any news", topic = "World" },
    { id = "ASK_DANGER", text = "Anything I should watch out for here?", words = "is it dangerous here", topic = "World" },
    { id = "ASK_LOOT_SPOT", text = "Anywhere worth checking for supplies?", words = "where can i find supplies", topic = "World" },
    { id = "ASK_ADVICE", text = "Got any advice?", words = "got any advice", topic = "World" },
    { id = "ASK_WHAT_HAPPENED", text = "How did it get this bad?", words = "what happened", topic = "World" },
    { id = "ASK_MILITARY", text = "What happened to the army?", words = "where is the army", topic = "World",
        variants = { "Any word from the National Guard?", "Think the army's still out there?", "You heard anything about the soldiers?" } },
    { id = "ASK_FORT_KNOX", text = "You heard anything about Fort Knox?", words = "what about fort knox", topic = "World" },
    { id = "ASK_RADIO", text = "Anything useful on the radio?", words = "heard the radio", topic = "World" },
    { id = "ASK_FOOD", text = "Got any food to spare?", words = "got any food", topic = "Supplies" },
    { id = "ASK_WATER", text = "Know where I can find drinking water?", words = "got any water", topic = "Supplies" },
    { id = "ASK_MEDS", text = "Can you spare any medical supplies?", words = "got any medicine", topic = "Supplies" },
    { id = "YES", text = "Yeah, alright.", words = "yes", answer = true },
    { id = "NO", text = "No, not right now.", words = "no", answer = true },
}

Intents.encounterQuestions = { ENC_OPEN = true, ENC_ASK_WHO = true, ENC_ASK_HOWMANY = true, ENC_ASK_CARRY = true,
    ENC_ASK_INTENT = true, ENC_DEMAND_DROP = true, ENC_DEMAND_TOLL = true, ENC_DEMAND_LEAVE = true }
Intents.encounterRows = {
    { id = "ENC_ANS_PASSING", text = "Nobody. Just passing through.", words = "just passing through" },
    { id = "ENC_ANS_ALONE", text = "It's just me.", words = "it's just me" },
    { id = "ENC_ANS_GROUP", text = "There's more of us, close by.", words = "there's more of us" },
    { id = "ENC_ANS_LITTLE", text = "Not much. Some food, a little water.", words = "not much" },
    { id = "ENC_ANS_COMPLY", text = "Alright. Weapon's down.", words = "it's down" },
    { id = "ENC_ANS_PAY", text = "Take what you need. No trouble.", words = "take what you need" },
    { id = "ENC_ANS_LEAVING", text = "I'm going. We don't have a problem.", words = "i'm going" },
    { id = "ENC_ANS_REFUSE", text = "No. Not happening.", words = "not happening" },
    { id = "ENC_ANS_FLANKER", text = "Tell your friend to stay where I can see him.", words = "your friend" },
    { id = "ENC_ANS_JOIN", text = "You could use another pair of hands.", words = "another pair of hands" },
}
for _, row in ipairs(Intents.encounterRows) do
    row.answer, row.encounter, row.answerTo = true, true, Intents.encounterQuestions
    Intents.choices[#Intents.choices + 1] = row
end

function Intents.encounterPending(pending)
    return type(pending) == "string" and string.sub(pending, 1, 4) == "ENC_"
end

Intents.choiceTopics = { ASK_NEWS = "World", ASK_DESTINATION = "Personal", ASK_JOB_BEFORE = "Personal",
    ASK_ADVICE = "World", ASK_FOOD = "Supplies", JOIN_REQUEST = "Personal", ASK_NAME = "World",
    ASK_HOME = "Personal", ASK_ABOUT_ME = "Personal", WALK_WITH_ME = "Personal", WALK_STOP = "Personal" }
Intents.choiceVariants = {
    ASK_NEWS = { "Heard anything I ought to know?", "What's the word around here?", "Any news from outside town?" },
    ASK_DESTINATION = { "Where are you headed next?", "You staying around here?", "What's your next stop?" },
    ASK_ADVICE = { "What have you figured out so far?", "Any advice for staying alive?", "Anything you wish you'd known sooner?" },
    ASK_FOOD = { "You have any food you can spare?", "Got anything to eat? I'm running low.", "Could you spare a bite?" },
    ASK_JOB_BEFORE = { "What was your work, before this?", "What did a normal day look like for you?", "You from around here? What did you do?" },
}

function Intents.groupOf(choice)
    if type(choice) ~= "table" then return nil end
    local group = choice.group or choice.topic or Intents.choiceTopics[choice.id]
    return Intents.groupAlias[group] or group
end

function Intents.addGroup(group)
    if type(group) ~= "table" or type(group.id) ~= "string" or group.id == "" then return false end
    for index, row in ipairs(Intents.groups) do
        if row.id == group.id then Intents.groups[index] = group; return true end
    end
    Intents.groups[#Intents.groups + 1] = group
    return true
end

function Intents.addChoice(choice, before)
    if type(choice) ~= "table" or type(choice.id) ~= "string" or choice.id == ""
            or type(choice.text) ~= "string" or type(choice.words) ~= "string" then return false end
    for index, row in ipairs(Intents.choices) do
        if row.id == choice.id then Intents.choices[index] = choice; return true end
    end
    local at = #Intents.choices + 1
    for index, row in ipairs(Intents.choices) do
        if (before ~= nil and row.id == before) or (before == nil and row.answer == true and not choice.answer) then
            at = index
            break
        end
    end
    table.insert(Intents.choices, at, choice)
    return true
end

function Intents.choiceById(id)
    for _, row in ipairs(Intents.choices) do
        if row.id == id then return row end
    end
    return nil
end

function Intents.offered(choice, view)
    if type(choice) ~= "table" or choice.hidden or type(view) ~= "table" then return false end
    if choice.answer or choice.answerTo ~= nil then return false end
    if Intents.groupOf(choice) ~= view.topic then return false end
    if choice.friendly and view.stance ~= "friendly" then return false end
    if type(choice.stances) == "table" and choice.stances[tostring(view.stance)] ~= true then return false end
    if choice.untilKnown and view.known == true then return false end
    if type(choice.show) == "function" then
        local ok, shown = pcall(choice.show, view)
        return ok and shown == true
    end
    return true
end

function Intents.answers(choice, pending)
    if type(choice) ~= "table" or pending == nil then return false end
    if type(choice.answerTo) == "table" then return choice.answerTo[pending] == true end
    if Intents.exclusiveAnswers[pending] then return false end
    return choice.answer == true
end

function Intents.choiceLabel(choice, turn)
    local variants = choice.variants or Intents.choiceVariants[choice.id]
    if variants == nil then return choice.text end
    return variants[(math.max(0, tonumber(turn) or 0) % #variants) + 1]
end

return Intents
