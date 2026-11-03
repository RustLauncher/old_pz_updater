ProjectALife = ProjectALife or {}

ProjectALife.VoiceDialogueRegister = function(Catalog)
    if Catalog.dialogueLoaded then return end
    Catalog.dialogueLoaded = true
    Catalog.events.AIMED_AT = { category="social", priority=94, chance=100,
        cooldownMs=18000, groupCooldownMs=3000, actorLockMs=2200, interrupt=true }
    Catalog.events.LOCAL_MEMORY = { category="ambient", priority=10, chance=35,
        cooldownMs=90000, groupCooldownMs=15000, actorLockMs=3500 }
    Catalog.events.DAILY_NEEDS = { category="ambient", priority=10, chance=35,
        cooldownMs=70000, groupCooldownMs=12000, actorLockMs=2500 }
    local civilian = {
        AIMED_AT={"PUT THAT FUCKING THING DOWN!", "Hey! Don't point that at me!", "Easy. Lower it. Nobody needs to die here."},
        SUPPRESS_FIRE={"Keep your head down! I'll cover you!", "Go! I'll keep them busy!"},
        RELOAD={"Cover me a second. I'm reloading!", "Empty. Give me a second!"},
        OUT_OF_AMMO={"That's it. I'm out!", "No ammo! I need to get back!"},
        SCAVENGE_START={"Food first. Then we get out.", "Check the cupboards. I'll watch the door."},
        CONTAINER_SEARCH={"Come on. Something useful.", "Give me a second to check this."},
        FOUND_FOOD={"Food. Finally.", "Something to eat. I'd almost forgotten what that feels like"},
        FOUND_MEDICINE={"Medicine. Hang on to that.", "We can use this for the wounded."},
        FOUND_AMMO={"Rounds here. Check if they fit.", "Found some ammunition."},
        LOOT_EMPTY={"Nothing left.", "Not much use to us. Let's try somewhere else"},
        DOOR_LOCKED={"Locked. Try another door.", "I'm not getting through this one."},
        SEARCH_COMPLETE={"Nothing else here. Let's move.", "I've checked what I can."},
        RETURN_WITH_LOOT={"Let's get this back to the others.", "We've got enough to carry."},
        AFTER_FIGHT={"Everybody still here?", "Give me a minute. My hands won't stop shaking."},
        DAILY_NEEDS={"Save me a little water.", "Got a light?", "Five minutes off my feet. That's all I want.",
            "Don't eat all of it. We still have to get through tomorrow.", "I could use a dry pair of socks, if we find any",
            "We should check what we're taking before we leave", "If it won't start, we walk. Same as yesterday."},
        LOCAL_MEMORY={"I used to complain about the drive to work. Can you believe that?",
            "I keep reaching for the phone. There's nobody to call.",
            "My neighbor left his porch light on. I wonder if it's still burning.",
            "I don't trust a broadcast that tells me everything is fine.",
            "We could try Muldraugh. I'm not saying it's safe. Just somewhere else.",
            "I miss hearing a dog bark and not worrying about what heard it.",
            "Someone said the road out was open. Someone always says that.",
            "When we find a decent place, I'm washing these clothes. Twice."}
    }
    local disciplined = {
        AIMED_AT={"Muzzle down! Now!", "Lower your weapon. Don't make this worse.", "Finger off the trigger. Look at me."},
        SUPPRESS_FIRE={"Suppressing fire! Move!", "Covering. Cross now!"},
        RELOAD={"Reloading. Cover my sector.", "Changing magazines."},
        SCAVENGE_START={"Supplies only. Keep someone on the entrance.", "Check storage. Don't split too far."},
        AFTER_FIGHT={"Head count. Then check the wounded.", "Hold security. Don't bunch up."},
        DAILY_NEEDS={"Drink while you can. I'll take this watch.", "Check your gear before we move.",
            "Take ten. One person stays on watch.", "Leave enough water for the return trip."},
        LOCAL_MEMORY={"They taught us how to hold a road. Not what to do when nobody came to relieve us.",
            "I keep the radio on. Doesn't mean I believe everything on it.",
            "We used to know who was on the other end of an order.",
            "I'm not promising anybody rescue. I can promise another watch."}
    }
    local rough = {
        AIMED_AT={"PUT THAT FUCKING THING DOWN!", "Point it somewhere else, asshole!", "Lower it. I'm not asking twice."},
        SUPPRESS_FIRE={"Keep their fucking heads down!", "Move! I've got you covered!"},
        RELOAD={"Reloading! Don't leave me hanging!", "Empty! Cover me!"},
        LOOT_EMPTY={"Picked clean. Fuck.", "Nothing. Check the next one."},
        AFTER_FIGHT={"Who's hurt? Say something.", "Shit. That was close."},
        DAILY_NEEDS={"Anybody got a dry cigarette?", "You finish that bottle, you find the next one.",
            "My feet are fucking killing me.", "Check carefully. People forget what matters when they're in a hurry"},
        LOCAL_MEMORY={"I had twenty bucks on the kitchen table. Went back for it. Stupidest thing I ever did.",
            "I don't want to hear another guy say he knows a safe place.",
            "You know what I miss? Not having to count every damn mouthful.",
            "Maybe we get through tonight. Let's worry about that first."}
    }
    for event,lines in pairs(civilian) do
        if Catalog.events[event] then
            Catalog.styles.calm[event]=lines
            Catalog.styles.aggressive[event]=rough[event] or lines
        end
    end
    for id,profile in pairs(Catalog.profiles) do
        local soldier = string.find(id,"military",1,true) or string.find(id,"law_enforcement",1,true)
            or string.find(id,"mercenary",1,true) or string.find(id,"dolg",1,true)
        local style = soldier and disciplined or (profile.tone=="aggressive" and rough or civilian)
        for event,lines in pairs(style) do
            if Catalog.events[event] and (profile.lines[event]==nil or #profile.lines[event]==0) then
                profile.lines[event]={}
                for _,text in ipairs(lines) do profile.lines[event][#profile.lines[event]+1]={text=text} end
            end
        end

        if profile.sourcePack=="project_alife" and profile.lines.WARNING_LOWER_WEAPON then
            for _,entry in ipairs(profile.lines.WARNING_LOWER_WEAPON) do
                profile.lines.AIMED_AT[#profile.lines.AIMED_AT+1]=entry
            end
        end
    end
    for _,state in ipairs({"idle","indoors","patrol"}) do
        local pool=Catalog.ambientPools and Catalog.ambientPools[state]
        if pool then pool[#pool+1]="LOCAL_MEMORY"; pool[#pool+1]="DAILY_NEEDS" end
    end

    if type(ProjectALife.FactionVoiceInstall) == "function" then
        ProjectALife.FactionVoiceInstall(Catalog)
    end
end
