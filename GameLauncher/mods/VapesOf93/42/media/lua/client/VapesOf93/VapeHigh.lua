require "VapesOf93/VapeShared"
local change = VapesOf93.change

local GREENOUT_AT = 150

-- Per-minute modifiers by strain
local STRAIN = {
    Sativa = { fatigue = -0.0002, pain = -0.2, boredom = -0.9, hunger = 0.0008 },
    Indica = { fatigue =  0.0015, pain = -0.6, boredom = -0.4, hunger = 0.0014 },
    Hybrid = { fatigue =  0.0006, pain = -0.3, boredom = -0.5, hunger = 0.0011 },
}

local function onMinute()
    local p = getSpecificPlayer(0)
    if not p or p:isDead() then return end
    local md = p:getModData()
    local high = md.VapeHigh or 0
    if high <= 0 then return end
    local s = STRAIN[md.VapeStrain or "Hybrid"] or STRAIN.Hybrid

    -- Depression & anxiety relief
    change(p, "UNHAPPINESS", -0.6)
    change(p, "STRESS", -0.006)
    change(p, "PANIC", -2)

    -- Body: mellow, pain relief, munchies, cottonmouth
    change(p, "BOREDOM", s.boredom)
    change(p, "PAIN", s.pain)
    change(p, "HUNGER", s.hunger)
    change(p, "THIRST", 0.0010)
    change(p, "FATIGUE", s.fatigue)

    if high > GREENOUT_AT then
        -- Too much: you green out
        change(p, "FOOD_SICKNESS", 0.6)
        change(p, "ENDURANCE", -0.004)
        if ZombRand(40) == 0 then p:Say("I took too much... I don't feel so good.") end
    elseif ZombRand(90) == 0 then
        p:Say("I could really go for a snack.")
    end

    md.VapeHigh = high - 1
    if md.VapeHigh == 0 then p:Say("Coming down...") end
end

Events.EveryOneMinute.Add(onMinute)
