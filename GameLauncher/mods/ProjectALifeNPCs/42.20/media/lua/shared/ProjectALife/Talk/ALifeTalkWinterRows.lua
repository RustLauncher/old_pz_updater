ProjectALife = ProjectALife or {}
require "ProjectALife/Talk/ALifeTalkIntents"
require "ProjectALife/World/ALifeSeasons"

local Intents = ProjectALife.TalkIntents

local Winter = {
    defs = {},
    metrics = { rows = 0 },
}
ProjectALife.TalkWinterRows = Winter

function Winter.snapshot()
    local seasons = ProjectALife.Seasons
    local w = seasons.weather()
    return { season = seasons.current(), sky = seasons.skyOf(w), air = w ~= nil and w.air or 15,
        ground = w ~= nil and w.ground or 0, snowing = w ~= nil and w.snowing == true }
end

function Winter.chilly(now)
    return now.air < 10 or now.sky == "snow" or now.sky == "cold" or now.season == "winter"
end

Winter.rules = {
    ASK_COLD_FEEL = function(now) return now.air < 13 or now.sky == "snow" or now.sky == "rain" or now.sky == "storm" end,
    ASK_GOT_COLD = function(now) return now.air < 16 end,
    ASK_STAY_WARM = function(now) return now.air < 9 or now.sky == "snow" end,
    ASK_REMEDY = function(now) return now.air < 14 end,
    ASK_WINTER = function(now) return now.season ~= "summer" or now.sky == "cold" end,
    ASK_WEATHER = function() return true end,
    ASK_SEASON = function() return true end,
    ASK_SNOW = function(now) return now.snowing or now.ground > 0.2 end,
    ASK_HEAT = function(now) return now.sky == "hot" or now.air >= 28 end,
    ASK_WARM_PLACE = function(now) return now.air < 8 or now.sky == "snow" end,
    ASK_HARVEST = function(now) return now.season ~= "winter" end,
}

function Winter.add(row)
    local rule = Winter.rules[row.id]
    row.show = function() return rule == nil or rule(Winter.snapshot()) == true end
    Winter.defs[#Winter.defs + 1] = row
    if Intents.addChoice(row) then Winter.metrics.rows = Winter.metrics.rows + 1 end
end

Winter.add({ id = "ASK_COLD_FEEL", text = "Are you cold?", words = "are you cold", topic = "Personal",
    variants = { "Are you cold?", "You warm enough out here?", "You look like you're freezing." } })
Winter.add({ id = "ASK_GOT_COLD", text = "You sound rough. Got a cold?", words = "do you have a cold", topic = "Personal",
    variants = { "You sound rough. Got a cold?", "That cough sound bad to you?", "Are you coming down with something?" } })
Winter.add({ id = "ASK_STAY_WARM", text = "How do you keep warm out here?", words = "how do you stay warm", topic = "Personal",
    variants = { "How do you keep warm out here?", "What do you do when it gets this cold?", "Any trick for staying warm?" } })
Winter.add({ id = "ASK_REMEDY", text = "Anything that helps with a cough?", words = "something for a cough", topic = "Personal" })
Winter.add({ id = "ASK_WINTER", text = "What's the winter like here?", words = "what is winter like here", topic = "World",
    variants = { "What's the winter like here?", "Is it a hard winter around here?", "How bad does it get in winter?" } })
Winter.add({ id = "ASK_WEATHER", text = "How's the weather been treating you?", words = "how is the weather", topic = "World",
    variants = { "How's the weather been treating you?", "Some weather, huh?", "What do you make of this weather?" } })
Winter.add({ id = "ASK_SEASON", text = "How do you like this time of year?", words = "how do you like this season", topic = "World",
    variants = { "How do you like this time of year?", "Season's changing. Notice?", "What do you think of the season so far?" } })
Winter.add({ id = "ASK_SNOW", text = "You ever see snow like this?", words = "have you seen snow like this", topic = "World" })
Winter.add({ id = "ASK_HEAT", text = "Hot enough for you?", words = "is it hot enough", topic = "World" })
Winter.add({ id = "ASK_WARM_PLACE", text = "Where can a person get warm around here?", words = "where can i get warm", topic = "World",
    variants = { "Where can a person get warm around here?", "Know anywhere with a fire going?", "Any place to warm up near here?" } })
Winter.add({ id = "ASK_HARVEST", text = "Anyone growing anything this year?", words = "is anyone growing food", topic = "World" })

return Winter
