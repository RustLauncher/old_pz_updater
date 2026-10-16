ProjectALife = ProjectALife or {}

local Door = {
    intents = { DOOR_ASK_A = true, DOOR_ASK_B = true, DOOR_ASK_C = true, DOOR_ASK_ID = true, DOOR_THANK = true,
        DOOR_KEEP = true, DOOR_HAGGLE = true },
    slots = { "DOOR_ASK_A", "DOOR_ASK_B", "DOOR_ASK_C" },
    patience = 5,
    haggleChance = 40,
    thankDeed = "kind_word",
}
ProjectALife.DoorEncounters = Door

Door.rows = {
    beggar = {
        A = { label = "How long since you ate?", "Two days, maybe three.. I lost count", "Still two days, nothing's changed since you asked", "Same answer, please, I'm too tired for more questions" },
        B = { label = "Where are you coming from?", "Down past the highway, everything there is picked clean", "Like I said, the highway, nothing left there", "I walked a long way, can we stop going over it?" },
        C = { label = "Can you work for it?", "I can carry, chop wood, dig, anything.. just not tonight", "I told you, anything you need doing, I'm not proud", "I'll sweep your porch for a can of beans, please" },
    },
    trader = {
        A = { label = "What do you usually trade?", "Tools, tins, whatever the road gives me", "Tools and tins, same as I said", "You know what I carry, so are we swapping or not?" },
        B = { label = "Where do you get the goods?", "Houses nobody's coming back to, and a few friends who owe me", "A trader never gives up his houses, friend", "That's my business, not the swap's business" },
        C = { label = "Is there anything you won't take?", "Anything bitten, bloody or open.. I'm careful", "Nothing that could make me sick, that's all", "Look, show me what you've got and we'll see" },
    },
    law_stay_inside = {
        A = { label = "Why stay inside? What's out there?", "Infected movement in the area, we're asking everyone to stay put", "I said, movement in the area, stay put", "Ma'am, sir, please, just keep the door shut" },
        B = { label = "How long will this last?", "I can't give you a day, sorry.. maybe a week", "Still no date, I'd tell you if I had one", "I don't know, and I'm not going to lie to you" },
        C = { label = "Who gave the order?", "County emergency office, it's on every sheet at the station", "The county, like I told you", "It's on the posted notice, I'm just the one delivering it" },
        ID = { label = "Can I see your ID?", real = { "Sure thing, deputy badge number is right here on the lanyard", "Same badge as a minute ago, take your time", "That's the third look, I'm real, I promise" } },
    },
    law_census = {
        A = { label = "What is the count for?", "Food and medicine, they send it where people live", "Supplies, it goes where the list says people live", "It's only a head count, nothing more" },
        B = { label = "What happens to the list?", "It goes to the station, then the county, nobody else", "Station, then county, that's the whole route", "It's not going anywhere bad, trust me" },
        C = { label = "Is any help coming?", "I hope so, I really do.. I just write the numbers down", "I can't promise anything, I'm sorry", "Please, I don't have more than what I said" },
        ID = { label = "Can I see your ID?", real = { "Of course, deputy badge, you can read the number", "Same badge, it hasn't changed since you looked", "It's still real, I swear it on the station's name" } },
    },
    law_guns = {
        A = { label = "Why do you want the guns?", "Too many fights over them, the county's collecting the loose ones", "Too many fights, I said", "It's an order, I didn't write it" },
        B = { label = "Do I get them back?", "When it's over, yes, you'd get a receipt", "A receipt and a promise, that's what I have", "I won't lie to you, I can't say" },
        C = { label = "Which station are you from?", "County sheriff's office, the one up the main road", "The sheriff's office up the main road, like I said", "Ask the dispatcher, if she's still answering" },
        ID = { label = "Can I see your ID?", real = { "Here, badge and unit card, check the number", "Same card, same number, hold it as long as you want", "You've looked three times, it's real, deputy badge" } },
    },
    law_fake = {
        A = { label = "Which station are you from?", "Uh.. main station, the one on the, uh, the main road", "The main station, I said, why does it matter?!", "Stop asking me questions and open the door" },
        B = { label = "Who is your sergeant?", "Sergeant.. Miller, yeah, Miller, he sent us", "I said Miller, what are you, a lawyer?", "You're wasting my time, open up" },
        C = { label = "What is the warrant for?", "No warrant, we're just.. checking, it's a welfare check", "A welfare check, I told you, don't make this hard", "Last time, open up before we do it the hard way" },
        ID = { label = "Can I see some ID?", real = { "Uh.. yeah, my badge is in the car, I'll show you inside", "I said it's in the car, are you deaf?!", "I'm done asking nicely, open the door" },
            fake = { "My badge is.. in the car, just open up, will you?", "I told you it's in the car, you're making this difficult!", "That's enough, open the door NOW" } },
    },
    sleep_one_night = {
        A = { label = "Where did you sleep last night?", "In a car, back seat, it was freezing", "A car, like I said, I won't make it a second night", "Please, a roof, I keep telling you" },
        B = { label = "Are you running from anything?", "Only from the cold and the dark, nothing else", "Nothing, just tired, just cold", "I'm not hiding anything, I swear" },
        C = { label = "What can you do around here?", "I can keep watch at night so you can sleep", "Watch, cook, clean, anything, I keep saying", "Whatever you need, I'll do it in the morning" },
    },
    chased = {
        A = { label = "What is chasing you?", "Dead ones, a pack of them, off the road!", "I said, dead ones, they're coming, open the door!", "THEY'RE COMING, please, PLEASE!" },
        B = { label = "How many are there?", "A handful.. five, maybe six, I didn't stop to count!", "Five or six, they're close, hurry!", "Too many, are we really doing this right now?!" },
        C = { label = "Did they see where you went?", "I think so, one of them saw me turn here!", "One saw me, I'm sure of it, open up!", "Please, they know I'm here!" },
    },
    wounded = {
        A = { label = "How did it happen?", "Fell through a window, climbing out of a house.. glass everywhere", "A window, the glass cut me deep, I told you", "It hurts too much to repeat it, please" },
        B = { label = "Is it infected?", "I don't think so, but it's not clean either", "Not yet, I don't think, but it stings", "Don't make me guess, just look at it" },
        C = { label = "Do you have any medicine?", "Nothing, I used my last bandage two days ago", "Nothing left, that's why I'm here", "Please, nothing, I'd tell you" },
    },
    racket = {
        A = { label = "Who are you with?", "Friends of the neighbourhood, we keep things quiet", "I told you, friends of the neighbourhood", "Don't push it, you know who we are" },
        B = { label = "What happens if I say no?", "Then things get unpleasant for your property, nothing personal", "Accidents happen to houses, I said", "You really want to find out, huh?" },
        C = { label = "Who else do you collect from?", "Everyone on this road who wants to keep sleeping at night", "The whole road, friend", "Enough, pay or don't" },
        HAGGLE = { label = "Two supplies, not three", "Two.. fine, but don't call it a habit", "Three, that's the price, no haggling", "I said three, we're finished here",
            denied = "Three, friend, I don't negotiate on my own doorstep" },
    },
    neighbour = {
        A = { label = "What kind of people?", "Armed, a few of them, they didn't stop to talk to anyone", "Armed, like I said, walking like they owned the road", "I told you what I saw, I can't make it prettier" },
        B = { label = "Which way were they heading?", "Down toward the crossroads, maybe an hour ago", "The crossroads, the way I said", "Toward the crossroads, I'm sure of it" },
        C = { label = "How many were there?", "Three, four.. I only saw them from a window", "Three or four, I didn't count twice", "Look, I came to warn you, not to testify" },
        THANK = { label = "Thanks for the warning", "Glad you took it seriously, stay safe", "Easy, it's what neighbours do", "You're welcome again, now lock up!", deed = true },
    },
    returning_things = {
        A = { label = "Where did you find it?", "By the fence, past the bend, a little way out", "By the fence, like I said, you must have dropped it", "By the fence, honest, I didn't touch anything else" },
        B = { label = "Did you see anyone near it?", "No one, just crows, it was quiet", "No one, I would've said something", "Nobody, honestly, I'd tell you if I had" },
        THANK = { label = "Thank you, really", "No trouble at all, I'd want someone to do the same", "You already thanked me, it's fine, honestly", "Okay, okay, you're too kind, I'm blushing", deed = true },
        KEEP = { label = "Keep some of it, you earned it", "Oh, I couldn't.. well, only a little then", "No, really, you've given me plenty", "Stop, I won't take more, it was the right thing to do", deed = true },
    },
    drunk = {
        A = { label = "What do you want?", "Company! A drink! A song! In whatever order!", "I want.. company, I said, didn't I?", "I want you to stop asking and open up!" },
        B = { label = "How much have you had?", "Enough to forget my own name, hah, hic", "Enough, that's all you need to know", "A few, a few more, who's counting?" },
        C = { label = "Where is your home?", "Home, home, somewhere.. down the road, lost the key", "Down the road, that's all I remember", "I don't remember, just leave me alone, friend!" },
        LEAVE = { label = "Go home and sleep it off", "Fine, fine, going home, sorry about the singing", "Okay, okay, I'm going" },
    },
    preacher = {
        A = { label = "What kind of service is it?", "Plain and quiet, hymns and bread, nothing fancy", "Plain and quiet, like I said", "All are welcome, that's all there is to it" },
        B = { label = "Where do you hold it?", "I don't have a place I can promise you. We gather when we can", "Like I said, wherever we can manage it. I'd rather be honest about that", "A few people together is enough. Doesn't have to be a chapel" },
        C = { label = "Do you take donations?", "No, no, just company and an open hand", "Just company, truly, no collection plate", "We ask for nothing, friend, only your time" },
        THANK = { label = "Thank you, but no", "That's alright, the invitation stays open", "No pressure at all, I'll move along", "Bless you, I'll leave you in peace", deed = false },
        LEAVE = { label = "Not today, thank you", "Understood, peace be with you", "Of course, God keep you" },
    },
    medic_rounds = {
        A = { label = "What do you treat?", "Cuts, fevers, infections, anything short of surgery", "Cuts, fevers, infections, I said", "Ask me about a specific problem, I'll tell you honestly" },
        B = { label = "What does it cost?", "Two supplies for the treatment, looking is free", "Two supplies, looking is free, I said", "Same price, I'm not going to bargain over bandages" },
        C = { label = "Where were you trained?", "County hospital, third year of residency, before it all went wrong", "County hospital, I told you, no tricks", "I'm a nurse, not a magician, are we doing this?" },
        ID = { label = "Do you have a license?", real = { "Right here, hospital badge and the license card, check the date", "Same card, same date, it hasn't expired", "It's real, I'd never ask for pay if it wasn't" } },
    },
    messenger = {
        A = { label = "Who is the note from?", "A man at the camp, he asked me to carry it, wouldn't say his name", "The man at the camp, I told you, no name", "I don't know the name, I'm only the courier" },
        B = { label = "What is in it?", "I haven't read it, it's sealed, I swear", "Sealed, I haven't read a word", "If it's sealed, it's not my business, is it?" },
        C = { label = "Why not deliver it yourself?", "My leg's bad, I can't make that walk twice", "My leg, I said, I'd only slow it down", "Please, the note matters more than my excuses" },
        THANK = { label = "Thanks for the trouble", "You're kind, not many say that", "Appreciated, truly, now the note?", "Okay, okay, now the note, please", deed = false },
    },
    neighbour_borrow = {
        A = { label = "How long did you say?", "A day or two, three at most, I'll bring it back clean", "A day or two, I said, three at the very most", "I keep my word, I'll bring it back" },
        B = { label = "What happened to yours?", "Rusted through, I left it out in the rain, my own fault", "Rusted through, like I said, my own fault", "It's gone, can we leave it at that?" },
        C = { label = "Who are you, exactly?", "Just somebody trying to get a little work done without ruining another tool", "Nobody special, like I said. I'm only asking to borrow it", "Just a neighbour trying to fix a fence, I promise" },
        THANK = { label = "Glad to help a neighbour", "That means a lot, I won't forget it", "I appreciate it, truly, really", "You're too generous, I'll owe you one", deed = false },
    },
    asks_help = {
        A = { label = "What happened to your friend?", "Fell through a floor, can't climb out, been there since morning", "Fell through a floor, I told you, can't climb out", "Please, no more questions, they could be hurt worse" },
        B = { label = "Is it dangerous there?", "A few of them wandering the yard, but I can lead you around", "A few of them, but there's a way around, I know it", "It's safe if we move fast, please hurry" },
        C = { label = "How many are with them?", "Just one, it's only the two of us out here", "Only one, I swear it", "Just us two, no tricks, I don't have the strength for tricks" },
    },
    family_in_need = {
        A = { label = "Where are you coming from?", "The east side, our street burned two nights ago", "The east side, our street burned, I said", "Please, we have nowhere else, don't make me retell it" },
        B = { label = "Do you have kids with you?", "Yes, one small one, she's tired and hungry", "Yes, one small one, I told you", "Yes, please, let her warm up" },
        C = { label = "What happened to your home?", "Fire, someone's cooking pot, the whole row went up", "A fire, the whole row, I said", "It's gone, it's all gone, please" },
    },
    returning_guest = {
        A = { label = "How have you been?", "Better than the last time, thanks to your roof", "Better, still alive, still thankful", "I'm okay, honestly, I just wanted to see you" },
        B = { label = "Where have you been staying?", "A cabin up the ridge, quiet, nobody's bothered me", "The cabin up the ridge, like I said", "Up the ridge, same cabin, same quiet" },
        C = { label = "Has anyone given you trouble?", "Not really, just a wild dog, I scared it off", "Not really, a dog, like I said", "No trouble, I promise, don't worry" },
        THANK = { label = "Glad you came back", "Thank you, that means more than you know", "You're kind, I won't forget it", "I'm going to blush, stop it", deed = true },
    },
    lodger_request = {
        A = { label = "What can you do to help?", "Repairs, cooking, laundry, I'm handy with a hammer", "Repairs, cooking, laundry, I said", "Tell me what you need and I'll do it" },
        B = { label = "Why did you leave your last place?", "The owner turned on us when the food ran thin", "He turned on us, over food, I told you", "I'd rather not get into the rest" },
        C = { label = "How long are we talking about?", "A few weeks, until I can find something steady", "A few weeks, like I said", "Until I find a place, that's all I can say" },
    },
    panic_knock = {
        A = { label = "What is chasing you?", "The dead ones, a bunch, just behind me!", "The dead ones, just behind me, I said!", "They're coming, PLEASE open the door!" },
        B = { label = "How many are there?", "Three, four, I didn't wait to count!", "Three or four, hurry!", "Enough! Let me in already!" },
        C = { label = "Did anyone see you come here?", "Only them, I hope.. I don't think anyone else", "Only them, I'm sure, just let me in!", "Nobody, I swear, open up!" },
    },
    weather_shelter = {
        A = { label = "Where are you headed?", "To my sister's place, two towns over, if the road holds", "My sister's place, two towns over, I said", "Just somewhere dry, nowhere special" },
        B = { label = "Do you need anything dry?", "A dry shirt would be a gift, but I'll manage", "A dry shirt, if there's one spare", "I'll take anything, I'm soaked to the bone" },
        C = { label = "How long will it last?", "Another hour, maybe two, the clouds look thick", "Another hour or two, I said", "Longer than I'd like, honestly" },
    },
    medical_visit = {
        A = { label = "How long has it been like this?", "Since yesterday, it got worse overnight", "Since yesterday, I said, it's getting worse", "It's getting bad, please look at it" },
        B = { label = "Where does it hurt?", "Right here, deep, and it throbs when I walk", "Right here, I showed you", "Everywhere near it, honestly" },
        C = { label = "Have you taken anything for it?", "Just water, I ran out of everything else", "Only water, I told you", "Nothing, please, anything would help" },
        THANK = { label = "Glad you came to me", "Thank you, really, I mean it", "Thanks, that helps, I mean it", "You're a kind soul, I won't forget it", deed = false },
    },
    radio_rumour = {
        A = { label = "What did they say about me?", "Only that someone out here holds a house and keeps the door shut", "Same thing, a house with a door that stays shut", "I told you everything I heard, I promise" },
        B = { label = "Which station was it?", "The one on the low band, a woman reads the news at noon", "The low band, a woman, at noon", "The low band, I don't know the name" },
        C = { label = "Who else heard it?", "Everyone with a radio on this road, I'd guess", "Everyone with a radio, I'd guess", "More people than you'd like, friend" },
        THANK = { label = "Thanks for telling me", "Of course, I'd want to know if it was me", "Anytime, just watch your back", "Easy, it's what neighbours do", deed = true },
    },
}

Door.default = {
    A = { label = "Tell me more", "Not much more to say, honestly", "I already told you what I know", "That's all I have, I promise" },
    B = { label = "Anything else?", "Not really, no", "Nothing else, I said", "No, please, that's it" },
    C = { label = "What should I know?", "Just be careful", "Be careful, I mean it", "Careful, that's all I've got" },
}

Door.leaveLines = {
    beggar = { "Alright.. thank you anyway", "Please, you could spare something small!" },
    law_guns = { "Understood, but we'll be back", "Don't make this a problem for yourself" },
    law_fake = { "Fine, we'll see how long that door lasts", "You'll regret this, I promise" },
    racket = { "Your call.. you'll regret it", "Then you've made your choice" },
    drunk = { "Okay, okay, I'm going", "Hey! Fine, fine!" },
    preacher = { "Understood, peace be with you", "God forgive you.. goodbye" },
    chased = { "No! Please, they're right behind me!", "You're killing me, you know that?!" },
    panic_knock = { "No, please, PLEASE, they're coming!", "You'll hear it when they get me, you know!" },
    wounded = { "Alright.. I'll find another door", "Fine.. rot then" },
}

Door.tells = {
    law_fake = "no_badge",
}

function Door.row(event)
    return Door.rows[event]
end

function Door.has(event)
    return Door.rows[event] ~= nil
end

function Door.isThemed(intent)
    return Door.intents[intent] == true
end

function Door.slotKey(intent)
    if intent == "DOOR_ASK_A" then return "A" end
    if intent == "DOOR_ASK_B" then return "B" end
    if intent == "DOOR_ASK_C" then return "C" end
    if intent == "DOOR_ASK_ID" then return "ID" end
    if intent == "DOOR_THANK" then return "THANK" end
    if intent == "DOOR_KEEP" then return "KEEP" end
    if intent == "DOOR_HAGGLE" then return "HAGGLE" end
    return nil
end

function Door.entry(event, intent)
    local key = Door.slotKey(intent)
    if key == nil then return nil end
    local row = Door.rows[event]
    if row ~= nil and row[key] ~= nil then return row[key] end
    if event ~= nil and (key == "A" or key == "B" or key == "C") and row == nil then return Door.default[key] end
    return nil
end

function Door.choicesFor(event)
    local set = {}
    for intent in pairs(Door.intents) do
        if Door.entry(event, intent) ~= nil then set[intent] = true end
    end
    return set
end

function Door.labelsFor(event)
    local labels = {}
    for intent in pairs(Door.intents) do
        local entry = Door.entry(event, intent)
        if entry ~= nil and type(entry.label) == "string" then labels[intent] = entry.label end
    end
    local row = Door.rows[event]
    if row ~= nil and type(row.LEAVE) == "table" then labels.DOOR_LEAVE = row.LEAVE.label end
    return labels
end

function Door.stage(count)
    local value = math.floor(tonumber(count) or 0) + 1
    if value < 1 then value = 1 end
    if value > 3 then value = 3 end
    return value
end

function Door.line(event, intent, count, fake)
    local entry = Door.entry(event, intent)
    if entry == nil then return nil end
    local pool = entry
    if intent == "DOOR_ASK_ID" and fake == true and type(entry.fake) == "table" then pool = entry.fake
    elseif intent == "DOOR_ASK_ID" then pool = type(entry.real) == "table" and entry.real or entry end
    return pool[Door.stage(count)] or pool[#pool]
end

function Door.leaveLine(event, rude)
    local row = Door.rows[event]
    if row ~= nil and type(row.LEAVE) == "table" then return row.LEAVE[rude and 2 or 1] or row.LEAVE[1] end
    local pair = Door.leaveLines[event]
    if pair ~= nil then return rude and pair[2] or pair[1] end
    return nil
end

return Door
