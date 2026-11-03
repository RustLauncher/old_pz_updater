ProjectALife = ProjectALife or {}

local Fallback = {}
ProjectALife.VoiceTextFallback = Fallback

Fallback.lines = {
    CONTACT_PLAYER = "Someone there. Easy now",
    CONTACT_INFECTED = "Dead ones. Keep your distance",
    CONTACT_HOSTILE = "Careful with that one. Don't rush closer",
    PANIC = "Easy! Keep back!",
    HURT = "Aagh--!",
    COMBAT_ATTACK = "Get back!",
    CAREFUL_KEEP_BACK = "That's close enough. Give us some room",
    CAREFUL_KEEP_BACK_FIGHTING = "Not now. Keep your distance",
    CAREFUL_LAST_WARNING = "Last warning. Back off!",
    CAREFUL_HOSTILE = "That's enough! Stay back!",
    SHOUT_FRIENDLY = "We hear you. Come over carefully",
    SHOUT_NEUTRAL = "Keep your voice down, please",
    SHOUT_CAREFUL = "We hear you. Stay where you are",
    SHOUT_HOSTILE = "Keep shouting at us and you'll regret it",
    AIMED_AT = "Don't point that at me!",
    WARNING_STOP = "Stop right there!",
    WARNING_LOWER_WEAPON = "Lower the weapon. Don't make this worse",
    RETREAT = "Back away. We need some room",
    SURRENDER = "Enough! I give up!",
    ALLY_DOWN = "Somebody help them!",
    ALLY_HIT = "Are you hurt? Let me see!",
    LOST_TARGET = "Keep looking. Don't get careless",
    SEARCH_START = "Let's have a look around",
    ORDER_ACK = "Alright. I hear you",
    STEADY = "Breathe. One thing at a time",
    RELOAD = "Give me a second!",
    OUT_OF_AMMO = "I need to get back!",
    WEAPON_JAM = "Damn it! Give me a moment!",
    BREACH = "Stand back a little. Give me room",
    KILL_CONFIRMED = "Don't get careless now",
    FOUND_GEAR = "Let's see if it's any use",
    FOUND_TOOL = "That might come in handy",
    FOUND_FOOD = "Let's check what we can use",
    FOUND_MEDICINE = "We ought to keep that for someone who needs it",
    FOUND_AMMO = "Check whether any of that fits",
    IDLE = "I could use a moment to think",
}

Fallback.categories = {
    combat = "Easy. Don't get careless",
    infected = "Keep your distance. I don't want to take chances",
    tactics = "Stay together. Let's think this through",
    awareness = "Quiet a moment. I want to pay attention",
    navigation = "Take it carefully. No sense rushing",
    scavenge = "Let's see what we can use",
    group = "Don't run off on your own",
    social = "Give me a moment, would you?",
    ambient = "I miss having less to worry about",
    weather = "Let's be careful about where we go next",
}

function Fallback.caption(event, specification)
    local line = Fallback.lines[event]
    if line ~= nil then return line end
    local category = type(specification) == "table" and specification.category or nil
    return Fallback.categories[category] or "Let me think a moment"
end

return Fallback
