ProjectALife = ProjectALife or {}
require "ProjectALife/Talk/ALifeTalkIntents"

local Intents = ProjectALife.TalkIntents

local Rows = {
    defs = {},
    metrics = { rows = 0 },
}
ProjectALife.PartyRows = Rows

function Rows.show(row)
    return function(view)
        local party = view.party == true
        if row.needParty == true and not party then return false end
        if row.hideParty == true and party then return false end
        if row.needTask == true and view.partyTask ~= true then return false end
        if row.hideTask == true and view.partyTask == true then return false end
        return true
    end
end

function Rows.add(row)
    row.show = Rows.show(row)
    Rows.defs[#Rows.defs + 1] = row
    if Intents.addChoice(row) then Rows.metrics.rows = Rows.metrics.rows + 1 end
end

Rows.add({ id = "PARTY_JOIN", text = "Can I join you?", words = "can i join you", topic = "Personal",
    hideParty = true, stances = { friendly = true, neutral = true },
    tip = "Ask the group to take you in. Their leader decides: how they feel about you, how big the group is and what is going on around them." })
Rows.add({ id = "PARTY_LEAVE", text = "I'm leaving the group.", words = "i am leaving the group", topic = "Personal",
    needParty = true, tip = "Leave the group on good terms." })
Rows.add({ id = "PARTY_TASK_ASK", text = "What should I do?", words = "what should i do", topic = "Personal",
    needParty = true, hideTask = true, tip = "Ask the group leader for a job." })
Rows.add({ id = "PARTY_TASK_REMIND", text = "What was the job again?", words = "what was the job", topic = "Personal",
    needParty = true, needTask = true, tip = "Hear your current job again." })
Rows.add({ id = "PARTY_TASK_DONE", text = "About that job. It's done.", words = "the job is done", topic = "Personal",
    needParty = true, needTask = true, tip = "Report in. Supplies you were sent for are handed over here." })
Rows.add({ id = "PARTY_STORY", text = "Tell us a story, someone.", words = "tell us a story", topic = "Personal",
    stances = { friendly = true, neutral = true }, tip = "Ask the group to pass the time. Works when they are settled and nothing is wrong." })

return Rows
