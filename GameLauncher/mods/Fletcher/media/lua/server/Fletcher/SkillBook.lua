--[[
    Fletcher: the Archery skill books (scripts/Fletcher/Fletcher_Books.txt). Vanilla's reading code
    looks books up in SkillBook by their SkillTrained name: an entry here is all a new skill needs.
    Multipliers as vanilla's Aiming books (x1.5 to x8; crafting skills get x3 to x16).
]]
require "XpSystem/XPSystem_SkillBook"
require "Fletcher/Skill"

SkillBook["Archery"] = {
    perk = Fletcher.perk(),
    maxMultiplier1 = 1.5,
    maxMultiplier2 = 2.5,
    maxMultiplier3 = 4,
    maxMultiplier4 = 6,
    maxMultiplier5 = 8,
}
