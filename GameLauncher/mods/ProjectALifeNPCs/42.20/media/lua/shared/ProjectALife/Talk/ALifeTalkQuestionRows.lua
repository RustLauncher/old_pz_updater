require "ProjectALife/Talk/ALifeTalkIntents"

ProjectALife = ProjectALife or {}
local Intents = ProjectALife.TalkIntents
local Rows = {
    events = { "NPC_ASKS_COPING", "NPC_ASKS_DESTINATION", "NPC_ASKS_ROAD" },
    answers = {
        { id = "NPC_ANSWER_COPING_GOOD", text = "I'm holding up, thanks for asking", ask = "NPC_ASKS_COPING", kind = true },
        { id = "NPC_ANSWER_COPING_BAD", text = "Not great, to be honest", ask = "NPC_ASKS_COPING", kind = true },
        { id = "NPC_ANSWER_COPING_PRIVATE", text = "I'd rather not get into it", ask = "NPC_ASKS_COPING" },
        { id = "NPC_ANSWER_DESTINATION_HOME", text = "Back to where I'm staying", ask = "NPC_ASKS_DESTINATION" },
        { id = "NPC_ANSWER_DESTINATION_SUPPLIES", text = "Looking for supplies", ask = "NPC_ASKS_DESTINATION" },
        { id = "NPC_ANSWER_DESTINATION_PRIVATE", text = "I'd rather keep that to myself", ask = "NPC_ASKS_DESTINATION" },
        { id = "NPC_ANSWER_ROAD_CLEAR", text = "Nothing worth mentioning where I've been", ask = "NPC_ASKS_ROAD", kind = true },
        { id = "NPC_ANSWER_ROAD_DEAD", text = "I've seen dead people on the road, be careful", ask = "NPC_ASKS_ROAD", kind = true },
        { id = "NPC_ANSWER_ROAD_UNKNOWN", text = "I haven't been far, I can't tell you much", ask = "NPC_ASKS_ROAD" },
    },
}
ProjectALife.TalkQuestionRows = Rows
for _, event in ipairs(Rows.events) do Intents.exclusiveAnswers[event] = true end
for _, row in ipairs(Rows.answers) do
    Intents.addChoice({ id = row.id, text = row.text, words = row.text, answer = true,
        answerTo = { [row.ask] = true }, npcAnswer = true, kind = row.kind })
end
return Rows
