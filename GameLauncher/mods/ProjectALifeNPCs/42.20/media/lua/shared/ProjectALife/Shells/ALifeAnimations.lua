require "ProjectALife/Shells/ALifeShellSimulation"
require "ProjectALife/Shells/ALifeDeathInventory"
require "ProjectALife/Shells/ALifeTraversalHands"
require "ProjectALife/Compat/ALifeEquipEventShield"

ProjectALife = ProjectALife or {}

local Animations = {
    adapters = {},

    metrics = { propsApplied = 0, propsRefusedDedicated = 0, propsNoFactory = 0, propsCleared = 0, remoteBeats = 0 },
    active = setmetatable({}, { __mode = "k" }),
    current = setmetatable({}, { __mode = "k" }),
    serial = setmetatable({}, { __mode = "k" }),
    remoteToken = setmetatable({}, { __mode = "k" }),
    ownerPose = setmetatable({}, { __mode = "k" }),
    fishing = setmetatable({}, { __mode = "k" }),
    weaponVisuals = setmetatable({}, { __mode = "k" }),

    combatHold = setmetatable({}, { __mode = "k" }),

    readyCarry = setmetatable({}, { __mode = "k" }),

    fallback = setmetatable({}, { __mode = "k" }),
    oneShotTimeoutMs = 2800,

    oneShotMinimumMs = 350,

    settings = { actChannel = false },

    actSet = setmetatable({}, { __mode = "k" }),
    actBeat = setmetatable({}, { __mode = "k" }),
}
ProjectALife.Animations = Animations
Animations.metrics.actApplied, Animations.metrics.actCleared, Animations.metrics.actOrphans = 0, 0, 0

Animations.metrics.presetsRefusedDown = 0

local presets = {
    { id = "normal", label = "None" },
    { id = "surrender", label = "Surrender", bumpType = "ALifeYieldHands", held = true },
    { id = "wave", label = "Wave", bumpType = "ALifeWave",
        preserveWeaponLocation = true },
    { id = "follow", label = "Follow me", bumpType = "ALifeFollow",
        preserveWeaponLocation = true },
    { id = "stop", label = "Stop", bumpType = "ALifeStop",
        preserveWeaponLocation = true },
    { id = "thumbs_up", label = "Thumbs up", bumpType = "ALifeThumbsUp" },
    { id = "salute", label = "Salute", bumpType = "ALifeSalute",
        preserveWeaponLocation = true },
    { id = "yes", label = "Yes", bumpType = "ALifeAgreeNod" },
    { id = "no", label = "No", bumpType = "ALifeDissentShake" },
    { id = "shrug", label = "Shrug", bumpType = "ALifeUnsureShoulders" },
    { id = "shout", label = "Shout", bumpType = "ALifeShout" },
    { id = "come_here", label = "Come here", bumpType = "ALifeComeHere",
        preserveWeaponLocation = true },
    { id = "insult", label = "Taunt", bumpType = "ALifeInsult" },
    { id = "thumbs_down", label = "Thumbs down", bumpType = "ALifeThumbsDown" },
    { id = "undecided", label = "Hesitate", bumpType = "ALifeUndecided" },
    { id = "breathe", label = "Heavy breathing", bumpType = "ALifeBreathe" },
    { id = "tired", label = "Tired stretch", bumpType = "ALifeTired" },
    { id = "no_thanks", label = "Refuse", bumpType = "ALifeNoThanks" },
    { id = "combat_handgun", bumpType = "ALifeSidearmDischarge", hidden = true,
        combat = true, timeoutMs = 900 },
    { id = "combat_rifle", bumpType = "ALifeLongarmDischarge", hidden = true,
        combat = true, timeoutMs = 1100 },
    { id = "combat_melee", bumpType = "ALifeAttackMelee", hidden = true,
        combat = true, timeoutMs = 900 },

    { id = "combat_unarmed", bumpType = "ALifeAttackUnarmed", hidden = true,
        combat = true, timeoutMs = 800 },

    { id = "combat_floor", bumpType = "ALifeAttackFloor", hidden = true,
        combat = true, timeoutMs = 900 },
    { id = "combat_floor_knife", bumpType = "ALifeAttackFloorKnife", hidden = true,
        combat = true, timeoutMs = 1000 },

    { id = "combat_1h_b", bumpType = "ALifeAttack1HB", hidden = true,
        combat = true, timeoutMs = 900 },
    { id = "combat_1h_c", bumpType = "ALifeAttack1HC", hidden = true,
        combat = true, timeoutMs = 900 },
    { id = "combat_1h_d", bumpType = "ALifeAttack1HD", hidden = true,
        combat = true, timeoutMs = 900 },
    { id = "combat_1h_e", bumpType = "ALifeAttack1HE", hidden = true,
        combat = true, timeoutMs = 900 },
    { id = "combat_2h_a", bumpType = "ALifeAttack2HA", hidden = true,
        combat = true, timeoutMs = 1300 },
    { id = "combat_2h_b", bumpType = "ALifeAttack2HB", hidden = true,
        combat = true, timeoutMs = 1300 },
    { id = "combat_2h_c", bumpType = "ALifeAttack2HC", hidden = true,
        combat = true, timeoutMs = 1300 },
    { id = "combat_2h_d", bumpType = "ALifeAttack2HD", hidden = true,
        combat = true, timeoutMs = 1300 },
    { id = "combat_knife", bumpType = "ALifeBladeThrust", hidden = true,
        combat = true, timeoutMs = 800 },
    { id = "combat_spear_a", bumpType = "ALifeAttackSpearA", hidden = true,
        combat = true, timeoutMs = 1000 },
    { id = "combat_spear_b", bumpType = "ALifeAttackSpearB", hidden = true,
        combat = true, timeoutMs = 1000 },
    { id = "combat_punch_a", bumpType = "ALifeAttackPunchA", hidden = true,
        combat = true, timeoutMs = 800 },
    { id = "combat_punch_b", bumpType = "ALifeAttackPunchB", hidden = true,
        combat = true, timeoutMs = 800 },
    { id = "combat_punch_c", bumpType = "ALifeAttackPunchC", hidden = true,
        combat = true, timeoutMs = 800 },
    { id = "combat_punch_d", bumpType = "ALifeAttackPunchD", hidden = true,
        combat = true, timeoutMs = 800 },
    { id = "combat_punch_e", bumpType = "ALifeAttackPunchE", hidden = true,
        combat = true, timeoutMs = 800 },
    { id = "combat_2h_heavy_a", bumpType = "ALifeAttack2HHeavyA", hidden = true,
        combat = true, timeoutMs = 1100 },
    { id = "combat_2h_heavy_b", bumpType = "ALifeAttack2HHeavyB", hidden = true,
        combat = true, timeoutMs = 1100 },
    { id = "combat_floor_2h", bumpType = "ALifeAttackFloor2H", hidden = true,
        combat = true, timeoutMs = 1000 },
    { id = "combat_floor_spear", bumpType = "ALifeAttackFloorSpear", hidden = true,
        combat = true, timeoutMs = 1000 },

    { id = "draw_back_reach", bumpType = "ALifeDrawBackReach", hidden = true,
        combat = true, timeoutMs = 450, preserveWeaponLocation = true },
    { id = "draw_holster_reach", bumpType = "ALifeDrawHolsterReach", hidden = true,
        combat = true, timeoutMs = 420, preserveWeaponLocation = true },
    { id = "draw_belt_right_reach", bumpType = "ALifeDrawBeltRightReach", hidden = true,
        combat = true, timeoutMs = 420, preserveWeaponLocation = true },
    { id = "draw_belt_left_reach", bumpType = "ALifeDrawBeltLeftReach", hidden = true,
        combat = true, timeoutMs = 420, preserveWeaponLocation = true },

    { id = "draw_back", bumpType = "ALifeDrawBack", hidden = true,
        combat = true, timeoutMs = 850, weaponAtFraction = 0 },
    { id = "draw_holster", bumpType = "ALifeDrawHolster", hidden = true,
        combat = true, timeoutMs = 750, weaponAtFraction = 0 },
    { id = "draw_belt_right", bumpType = "ALifeDrawBeltRight", hidden = true,
        combat = true, timeoutMs = 750, weaponAtFraction = 0 },
    { id = "draw_belt_left", bumpType = "ALifeDrawBeltLeft", hidden = true,
        combat = true, timeoutMs = 750, weaponAtFraction = 0 },

    { id = "reload_handgun", bumpType = "ALifeReloadHandgun", hidden = true,
        combat = true, timeoutMs = 2800 },
    { id = "reload_rifle", bumpType = "ALifeLongarmRefill", hidden = true,
        combat = true, timeoutMs = 2800 },
    { id = "reload_shotgun", bumpType = "ALifeReloadShotgun", hidden = true,
        combat = true, timeoutMs = 2800 },
    { id = "reload_revolver", bumpType = "ALifeReloadRevolver", hidden = true,
        combat = true, timeoutMs = 2800 },

    { id = "reload_shotgun_loop", bumpType = "ALifeReloadShotgunLoop", hidden = true,
        combat = true, timeoutMs = 9000 },
    { id = "reload_rifle_loop", bumpType = "ALifeReloadRifleLoop", hidden = true,
        combat = true, timeoutMs = 9000 },
    { id = "reload_revolver_loop", bumpType = "ALifeReloadRevolverLoop", hidden = true,
        combat = true, timeoutMs = 9000 },
    { id = "jam_handgun", bumpType = "ALifeJamHandgun", hidden = true,
        combat = true, timeoutMs = 700 },
    { id = "jam_rifle", bumpType = "ALifeJamRifle", hidden = true,
        combat = true, timeoutMs = 700 },
    { id = "rack_handgun", bumpType = "ALifeRackHandgun", hidden = true,
        combat = true, timeoutMs = 1500 },
    { id = "rack_rifle", bumpType = "ALifeLongarmChamber", hidden = true,
        combat = true, timeoutMs = 1500 },
    { id = "rack_shotgun", bumpType = "ALifeScattergunChamber", hidden = true,
        combat = true, timeoutMs = 1500 },
    { id = "rack_revolver", bumpType = "ALifeWheelgunCock", hidden = true,
        combat = true, timeoutMs = 1500 },

    { id = "cycle_bolt_aim", bumpType = "ALifeCycleBoltAim", hidden = true,
        combat = true, timeoutMs = 1500 },
    { id = "cycle_lever_aim", bumpType = "ALifeCycleLeverAim", hidden = true,
        combat = true, timeoutMs = 1500 },
    { id = "cycle_shotgun_aim", bumpType = "ALifeCycleShotgunAim", hidden = true,
        combat = true, timeoutMs = 1500 },

    { id = "shove_bat", bumpType = "ALifeClubFend", hidden = true,
        combat = true, timeoutMs = 900 },
    { id = "shove_default", bumpType = "ALifeShoveDefault", hidden = true,
        combat = true, timeoutMs = 900 },
    { id = "shove_heavy", bumpType = "ALifeShoveHeavy", hidden = true,
        combat = true, timeoutMs = 800 },
    { id = "shove_handgun", bumpType = "ALifeSidearmFend", hidden = true,
        combat = true, timeoutMs = 700 },
    { id = "shove_rifle", bumpType = "ALifeLongarmFend", hidden = true,
        combat = true, timeoutMs = 700 },
    { id = "combat_chainsaw", bumpType = "ALifeAttackChainsaw", hidden = true,
        combat = true, timeoutMs = 900 },

    { id = "combat_stomp", bumpType = "ALifeHeelFinish", hidden = true,
        combat = true, timeoutMs = 1000 },

    { id = "breach_window", bumpType = "ALifePaneStrike", hidden = true,
        timeoutMs = 800 },

    { id = "hit_react", bumpType = "ALifeHitReact", hidden = true,
        timeoutMs = 200 },

    { id = "drag_grab", bumpType = "ALifeDragGrab", hidden = true, held = true, timeoutMs = 6500 },
    { id = "drag_fall", bumpType = "ALifeDragFall", hidden = true, timeoutMs = 1500 },
    { id = "drag_struggle", bumpType = "ALifeDragStruggle", hidden = true, looped = true,
        timeoutMs = 9000 },
    { id = "drag_lie", bumpType = "ALifeInjuredLie", hidden = true, held = true },
    { id = "drag_writhe", bumpType = "ALifeInjuredWrithe", hidden = true, held = true },
    { id = "drag_body", bumpType = "ALifeDragBody", hidden = true, held = true },
    { id = "drag_carry", bumpType = "ALifeDragCarry", hidden = true, held = true },

    { id = "get_up_front", bumpType = "ALifeGetUpFront", hidden = true,
        timeoutMs = 1100, preserveWeaponLocation = true },
    { id = "get_up_back", bumpType = "ALifeGetUpBack", hidden = true,
        timeoutMs = 1100, preserveWeaponLocation = true },

    { id = "zombie_bite", bumpType = "ALifeGnawUpright", hidden = true,
        foreign = true, timeoutMs = 1600 },
    { id = "zombie_bite_low", bumpType = "ALifeGnawDowned", hidden = true,
        foreign = true, timeoutMs = 1600 },
    { id = "zombie_claw", bumpType = "ALifeClawUpright", hidden = true,
        foreign = true, timeoutMs = 1600 },

    { id = "ready_melee", bumpType = "ALifeReadyMelee", hidden = true,
        combat = true, held = true },
    { id = "ready_melee_2h", bumpType = "ALifeReadyMelee2H", hidden = true,
        combat = true, held = true },
    { id = "ready_spear", bumpType = "ALifeReadySpear", hidden = true,
        combat = true, held = true },
    { id = "ready_handgun", bumpType = "ALifeReadyHandgun", hidden = true,
        combat = true, held = true },
    { id = "ready_rifle", bumpType = "ALifeReadyRifle", hidden = true,
        combat = true, held = true },

    { id = "heal_bandage", bumpType = "ALifeBandage", hidden = true,
        timeoutMs = 4500 },
    { id = "heal_arm", bumpType = "ALifeBandageArm", hidden = true, timeoutMs = 5600 },
    { id = "heal_body", bumpType = "ALifeBandageBody", hidden = true, timeoutMs = 5600 },
    { id = "heal_head", bumpType = "ALifeHeadDressing", hidden = true, timeoutMs = 5600 },
    { id = "farm_tend", bumpType = "ALifeFarmTend", hidden = true, held = true, idle = true, timeoutMs = 12000, handsFree = true },

    { id = "eat", bumpType = "ALifeSnackBite", hidden = true, looped = true, timeoutMs = 12000, idle = true, handsFree = true,
        variants = {
            { bumpType = "ALifeSnackBite", prop = "Base.Crisps" },
            { bumpType = "ALifeHandBite", prop = "Base.Apple" },
            { bumpType = "ALifeHandBite", prop = "Base.Banana" },
            { bumpType = "ALifeHandBite", prop = "Base.Orange" },
        } },
    { id = "drink", bumpType = "ALifeBottleSip", hidden = true, looped = true, timeoutMs = 9000, idle = true, handsFree = true,
        variants = {
            { bumpType = "ALifeBottleSip", prop = "Base.WaterBottle", hand = "primary" },
            { bumpType = "ALifeBottleSip", prop = "Base.PopBottle" },
            { bumpType = "ALifeTeaSip", prop = "Base.Mugl" },
        } },
    { id = "smoke", bumpType = "ALifeTobaccoBreak", hidden = true, looped = true, timeoutMs = 20000, idle = true, prop = "Base.CigaretteSingle", handsFree = true },
    { id = "read", bumpType = "ALifeReadBook", hidden = true, looped = true, timeoutMs = 20000, idle = true, handsFree = true,
        variants = {
            { bumpType = "ALifeReadBook", prop = "Base.Book" },
            { bumpType = "ALifeReadNews", prop = "Base.Newspaper" },
        } },
    { id = "sit_ground", bumpType = "ALifeSitGround", hidden = true, held = true, idle = true,
        timeoutMs = 20000, handsFree = true },
    { id = "warm_hands", bumpType = "ALifeWarmHands", hidden = true, held = true, idle = true,
        timeoutMs = 20000, handsFree = true },
    { id = "sit_bench", bumpType = "ALifeSitBench", hidden = true, held = true, idle = true,
        timeoutMs = 20000, handsFree = true },
    { id = "fish_wait", bumpType = "ALifeFishingIdle", hidden = true, held = true, idle = true,
        timeoutMs = 65000, handsFree = true, fishing = true, prop = "Base.FishingRod", hand = "both" },
    { id = "fish_cast", bumpType = "ALifeFishingCast", hidden = true, held = true, idle = true,
        timeoutMs = 2400, handsFree = true, fishing = true, prop = "Base.FishingRod", hand = "both" },
    { id = "fish_pull", bumpType = "ALifeFishingPull", hidden = true, held = true, idle = true,
        timeoutMs = 2400, handsFree = true, fishing = true, prop = "Base.FishingRod", hand = "both" },

    { id = "play_guitar", bumpType = "ALifeSitGround", hidden = true, held = true, idle = true,
        timeoutMs = 20000, prop = "Base.GuitarAcoustic", handsFree = true },

    { id = "sit_down", bumpType = "ALifeSitDown", hidden = true, idle = true,
        timeoutMs = 2400, handsFree = true },
    { id = "sit_up", bumpType = "ALifeSitUp", hidden = true,
        timeoutMs = 1000, handsFree = true },
    { id = "chop_wood", bumpType = "ALifeChopTree", hidden = true, looped = true, idle = true, timeoutMs = 9000,
        prop = "Base.Axe", hand = "both", handsFree = true },
    { id = "saw_planks", bumpType = "ALifeSawLog", hidden = true, looped = true, idle = true, timeoutMs = 9000,
        prop = "Base.Saw", hand = "primary", handsFree = true },
    { id = "build_crate", bumpType = "ALifeBuild", hidden = true, looped = true, idle = true, timeoutMs = 9000,
        prop = "Base.Hammer", hand = "primary", handsFree = true },
    { id = "board_up", bumpType = "ALifeBuild", hidden = true, held = true,
        timeoutMs = 5000, prop = "Base.Hammer", hand = "primary", handsFree = true },
    { id = "search_low", bumpType = "ALifeSearchLow", hidden = true, idle = true,
        held = true, timeoutMs = 12000, handsFree = true },
    { id = "search_mid", bumpType = "ALifeSearchMid", hidden = true, idle = true,
        held = true, timeoutMs = 12000, handsFree = true },
    { id = "search_high", bumpType = "ALifeSearchHigh", hidden = true, idle = true,
        held = true, timeoutMs = 12000, handsFree = true },
    { id = "forage", bumpType = "ALifeGroundGather", hidden = true, idle = true,
        held = true, timeoutMs = 12000, handsFree = true,
        variants = {
            { bumpType = "ALifeGroundGather", prop = "Base.BerryBlack" },
            { bumpType = "ALifeGroundGather", prop = "Base.BerryBlue" },
            { bumpType = "ALifeGroundGather", prop = "Base.MushroomGeneric1" },
        } },

    { id = "ready_kneel", bumpType = "ALifeReadyKneel", hidden = true,
        combat = true, held = true },

    { id = "sneeze", bumpType = "ALifeSneeze", hidden = true, timeoutMs = 2400 },
    { id = "cough", bumpType = "ALifeCough", hidden = true, timeoutMs = 2400 },
    { id = "shiver", bumpType = "ALifeShiver", hidden = true, timeoutMs = 2600 },

    { id = "bed_asleep", bumpType = "ALifeBedAsleep", hidden = true, held = true, idle = true,
        timeoutMs = 20000, handsFree = true },
    { id = "bed_awake", bumpType = "ALifeBedAwake", hidden = true, held = true, idle = true,
        timeoutMs = 20000, handsFree = true },
    { id = "sit_wall", bumpType = "ALifeSitWall", hidden = true, held = true, idle = true,
        timeoutMs = 20000, handsFree = true },
    { id = "doze_sit", bumpType = "ALifeDozeSit", hidden = true, held = true, idle = true,
        timeoutMs = 20000, handsFree = true },
    { id = "wash_hands", bumpType = "ALifeWashHands", hidden = true, idle = true,
        timeoutMs = 5200, handsFree = true },
    { id = "wash_face", bumpType = "ALifeWashFace", hidden = true, idle = true,
        timeoutMs = 5000, handsFree = true },
    { id = "write", bumpType = "ALifeWriteJournal", hidden = true, looped = true, idle = true,
        timeoutMs = 20000, handsFree = true,
        variants = {
            { bumpType = "ALifeWriteJournal", prop = "Base.Notebook" },
            { bumpType = "ALifeWriteJournal", prop = "Base.Journal" },
        } },
    { id = "photo", bumpType = "ALifeLookPhoto", hidden = true, looped = true, idle = true,
        timeoutMs = 20000, handsFree = true, prop = "Base.Photo" },
    { id = "change_top", bumpType = "ALifeBandageBody", hidden = true, idle = true,
        timeoutMs = 5600, handsFree = true },
    { id = "yawn", bumpType = "ALifeYawn", hidden = true, timeoutMs = 3000 },
    { id = "spooked", bumpType = "ALifeSpooked", hidden = true, timeoutMs = 3600 },
    { id = "pain_head", bumpType = "ALifePainHead", hidden = true, timeoutMs = 3000 },
    { id = "bow_head", bumpType = "ALifeBowHead", hidden = true, timeoutMs = 3700 },

    { id = "feed_in", bumpType = "ALifeFeedIn", hidden = true, timeoutMs = 1200 },
    { id = "feed_knees", bumpType = "ALifeFeedKnees", hidden = true, held = true },
    { id = "feed_up", bumpType = "ALifeFeedUp", hidden = true, timeoutMs = 1900 },
    { id = "stab_loop", bumpType = "ALifeStabLoop", hidden = true, looped = true, timeoutMs = 12000 },
}

local byId = {}
for _, preset in ipairs(presets) do byId[preset.id] = preset end

Animations.aliases = {}

function Animations.presetOf(id)
    return byId[Animations.aliases[id] or id]
end

Animations.registerFields = {}
for kind, names in pairs({
    string = { "id", "label", "bumpType", "fallbackTo", "prop", "hand" },
    boolean = { "hidden", "held", "looped", "idle", "handsFree", "combat", "preserveWeaponLocation" },
    number = { "timeoutMs", "weaponAtFraction" },
    table = { "variants" },
}) do
    for position = 1, #names do Animations.registerFields[names[position]] = kind end
end

function Animations.registerRefusal(preset)
    if type(preset) ~= "table" then return "preset_invalid" end
    for key, value in pairs(preset) do
        if Animations.registerFields[key] ~= type(value) then return "preset_field_" .. tostring(key) end
    end
    local id = preset.id
    if type(id) ~= "string" or string.len(id) > 40 or string.find(id, "^[a-z][a-z0-9_]*$") == nil then
        return "preset_id"
    end
    if byId[id] ~= nil or Animations.aliases[id] ~= nil then return "preset_duplicate" end
    if preset.fallbackTo ~= nil then
        if preset.bumpType ~= nil then return "preset_fallback_with_node" end
        if byId[preset.fallbackTo] == nil then return "preset_fallback_unknown" end
        return nil
    end
    local bump = preset.bumpType
    if type(bump) ~= "string" or string.len(bump) > 60 or string.find(bump, "^[A-Za-z][A-Za-z0-9_]*$") == nil then
        return "preset_bump"
    end
    if preset.held == true and preset.looped == true then return "preset_held_and_looped" end
    local timeout = preset.timeoutMs
    if timeout ~= nil and (timeout ~= timeout or timeout < 200 or timeout > 600000) then return "preset_timeout" end
    if preset.variants ~= nil then
        if #preset.variants == 0 then return "preset_variants" end
        for position = 1, #preset.variants do
            local variant = preset.variants[position]
            if type(variant) ~= "table" or type(variant.bumpType) ~= "string"
                    or string.find(variant.bumpType, "^[A-Za-z][A-Za-z0-9_]*$") == nil
                    or (variant.prop ~= nil and type(variant.prop) ~= "string") then return "preset_variants" end
        end
    end
    return nil
end

function Animations.registerPreset(preset)
    local refusal = Animations.registerRefusal(preset)
    if refusal ~= nil then
        Animations.metrics.presetsRefusedRegister = (Animations.metrics.presetsRefusedRegister or 0) + 1
        Animations.metrics.lastRegisterRefusal = refusal
        return false, refusal
    end
    if preset.fallbackTo ~= nil then
        Animations.aliases[preset.id] = preset.fallbackTo
    else
        local row = {}
        for key, value in pairs(preset) do row[key] = value end
        if row.hidden ~= true and row.label == nil then row.label = row.id end
        presets[#presets + 1] = row
        byId[row.id] = row
    end
    Animations.metrics.presetsRegistered = (Animations.metrics.presetsRegistered or 0) + 1
    return true
end

Animations.registerPreset({ id = "cry", fallbackTo = "pain_head" })
Animations.registerPreset({ id = "pray", fallbackTo = "bow_head" })
Animations.registerPreset({ id = "sit_bed_edge", fallbackTo = "sit_bench" })
Animations.registerPreset({ id = "wash_body", fallbackTo = "wash_face" })
Animations.registerPreset({ id = "look_window", fallbackTo = "normal" })

function Animations.variantOf(shell, preset)
    local list = preset ~= nil and preset.variants or nil
    if type(list) ~= "table" or #list == 0 then return preset or {} end
    local uid = ""
    pcall(function()
        if shell:hasModData() then uid = tostring(shell:getModData().ProjectALifeUID or "") end
    end)
    local seed = 0
    for index = 1, #uid do seed = (seed * 31 + string.byte(uid, index)) % 2147483647 end
    return list[seed % #list + 1]
end

Animations.actPresets = {
    surrender = "loop",
    wave = "beat", follow = "beat", stop = "beat", thumbs_up = "beat",
    salute = "beat", yes = "beat", no = "beat", shrug = "beat", shout = "beat",
    come_here = "beat", insult = "beat", thumbs_down = "beat", undecided = "beat",
    breathe = "beat", tired = "beat", no_thanks = "beat",
    heal_bandage = "loop", heal_arm = "loop", heal_body = "loop", heal_head = "loop",
    farm_tend = "loop", eat = "loop", drink = "loop", smoke = "loop",
    sit_ground = "loop", play_guitar = "loop", sit_down = "once", sit_up = "once",
    chop_wood = "loop", saw_planks = "loop", build_crate = "loop", read = "loop", warm_hands = "loop",
    board_up = "loop", search_low = "loop", search_mid = "loop", search_high = "loop",
    forage = "loop",
}

Animations.retiredBumps = {
    ALifeYes = true, ALifeNo = true, ALifeShrug = true, ALifeSmoke = true,
    ALifeDrink = true, ALifeEat = true, ALifeSurrender = true, ALifeForage = true,
    ALifeBandageHead = true, ALifeWindowSmash = true, ALifeAttackKnife = true,
    ALifeAttackRifle = true, ALifeRackRifle = true, ALifeRackShotgun = true,
    ALifeRackRevolver = true, ALifeReloadRifle = true,
    ALifeZombieBite = "ALifeGnawUpright", ALifeZombieBiteLow = "ALifeGnawDowned",
    ALifeShoveBat = "ALifeClubFend", ALifeShoveHandgun = "ALifeSidearmFend",
    ALifeShoveRifle = "ALifeLongarmFend", ALifeAttackHandgun = "ALifeSidearmDischarge",
    ALifeAttackStomp = "ALifeHeelFinish",
}

function Animations.bumpName(value)
    local renamed = Animations.retiredBumps[value]
    if type(renamed) == "string" then return renamed end
    return value
end

function Animations.renameLiveBump(shell, live)
    local renamed = Animations.retiredBumps[live]
    if type(renamed) ~= "string" or shell == nil
            or type(shell.setBumpType) ~= "function" then return live end
    if not pcall(shell.setBumpType, shell, renamed) then return live end
    return renamed
end

function Animations.renameHeldBump(shell, data)
    local old = data.ProjectALifeHeldBump
    if type(shell.isDead) ~= "function" or type(shell.getBumpType) ~= "function" then return false end
    local aliveOk, dead = pcall(shell.isDead, shell)
    if aliveOk ~= true or dead == true then return false end
    local readOk, live = pcall(shell.getBumpType, shell)
    if readOk ~= true then return false end
    if live == old and Animations.renameLiveBump(shell, live) == live then return false end
    data.ProjectALifeHeldBump = Animations.retiredBumps[old]
    return true
end

local function setVariable(shell, name, value)
    if shell == nil then return false end
    local text = tostring(value)
    local ok = pcall(shell.SetVariable, shell, name, text)
    if not ok then ok = pcall(shell.setVariable, shell, name, text) end
    return ok
end

function Animations.migrateHeldBump(shell, data)
    if shell == nil or type(data) ~= "table" or data.ProjectALifeCorpseOf ~= nil
            or (data.ProjectALifeActor ~= true and data.ProjectALifeOwned ~= true) then return false end

    if data.ProjectALifeHeldAct ~= nil and Animations.current[shell] == nil
            and type(shell.isDead) == "function" then
        local aliveOk, dead = pcall(shell.isDead, shell)
        if aliveOk and dead ~= true then
            data.ProjectALifeHeldAct, data.ProjectALifeHeldBump = nil, nil
        end
    end
    local retired = Animations.retiredBumps[data.ProjectALifeHeldBump]
    if type(retired) == "string" then return Animations.renameHeldBump(shell, data) end
    if retired ~= true then return false end
    if type(shell.isDead) ~= "function" or type(shell.getBumpType) ~= "function"
            or type(shell.setBumpType) ~= "function" or type(shell.setBumpDone) ~= "function" then return false end
    local writeVariable = type(shell.SetVariable) == "function" and shell.SetVariable or shell.setVariable
    if type(writeVariable) ~= "function" then return false end
    local aliveOk, dead = pcall(shell.isDead, shell)
    if not aliveOk or dead == true then return false end
    local ok, live = pcall(shell.getBumpType, shell)
    if not ok then return false end
    if live == "" or Animations.retiredBumps[live] then
        if not pcall(shell.setBumpType, shell, "") then return false end
        if not pcall(shell.setBumpDone, shell, true) then return false end
        if not pcall(writeVariable, shell, "BumpAnimFinished", "true") then return false end
        Animations.current[shell], Animations.active[shell] = nil, nil
        Animations.fallback[shell], Animations.remoteToken[shell] = nil, nil
    end
    data.ProjectALifeHeldBump = nil
    return true
end

local function getVariable(shell, name)
    if shell == nil then return nil end
    local ok, value = pcall(shell.GetVariable, shell, name)
    if ok then return value end
    ok, value = pcall(shell.getVariableString, shell, name)
    return ok and value or nil
end

function Animations.actRoute(id)
    if Animations.settings.actChannel ~= true then return nil end
    return Animations.actPresets[id]
end

function Animations.startAct(shell, id, mode)
    if mode == "beat" then
        local beat = "a"
        if Animations.actBeat[shell] == "a" then beat = "b" end
        if not setVariable(shell, "ALifeActBeat", beat) then return false end
        Animations.actBeat[shell] = beat
    end
    if not setVariable(shell, "ALifeActDone", false) then return false end
    if not setVariable(shell, "ALifeAct", id) then return false end
    Animations.actSet[shell] = id
    Animations.metrics.actApplied = Animations.metrics.actApplied + 1
    return true
end

function Animations.stopAct(shell)
    setVariable(shell, "ALifeAct", "")
    Animations.actSet[shell] = nil
    Animations.metrics.actCleared = Animations.metrics.actCleared + 1
end

function Animations.reset()
    local live = {}
    for shell in pairs(Animations.actSet) do live[#live + 1] = shell end
    for _, shell in ipairs(live) do Animations.stopAct(shell) end
    Animations.settings = { actChannel = false }
    Animations.actBeat = setmetatable({}, { __mode = "k" })
    Animations.metrics.actApplied, Animations.metrics.actCleared, Animations.metrics.actOrphans = 0, 0, 0
end

local function metadata(shell)
    if shell == nil then return nil end
    local ok, value = pcall(shell.getModData, shell)
    return ok and type(value) == "table" and value or nil
end

local function nowMs()
    if type(Animations.adapters.nowMs) == "function" then return Animations.adapters.nowMs() end
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function Animations.dragLocked(shell)
    local data = metadata(shell)
    local until_ = data ~= nil and tonumber(data.ProjectALifeDragUntilMs) or nil
    return until_ ~= nil and nowMs() < until_
end

local function animationSerial(shell, advance)
    local data = metadata(shell)
    local value = tonumber(data and data.ProjectALifeAnimationSerial)
        or tonumber(Animations.serial[shell]) or 0
    if advance == true then value = value + 1 end
    Animations.serial[shell] = value
    if data ~= nil then data.ProjectALifeAnimationSerial = value end
    return value
end

local function setAnimationSerial(shell, value)
    value = math.max(0, math.floor(tonumber(value) or 0))
    Animations.serial[shell] = value
    local data = metadata(shell)
    if data ~= nil then data.ProjectALifeAnimationSerial = value end
end

local handLocation = "ALife Weapon Hand"

local function weaponClass(itemType, fallback)
    local lowered = string.lower(tostring(itemType or ""))
    if string.find(lowered, "pistol", 1, true)
            or string.find(lowered, "revolver", 1, true) then return "handgun" end
    if string.find(lowered, "rifle", 1, true)
            or string.find(lowered, "shotgun", 1, true) then return "rifle" end
    if string.find(lowered, "spear", 1, true) then return "spear" end
    return tostring(fallback or "melee")
end

Animations.ARMS = { rifle = "longarm", handgun = "sidearm", spear = "polearm", melee = "melee" }

function Animations.armsOf(class)
    if type(class) ~= "string" then return nil end
    return Animations.ARMS[class] or class
end

function Animations.weaponClassOf(data)
    if type(data) ~= "table" then return nil end
    return data.ProjectALifeWeaponClass
end

local function attachmentSlotFor(item)
    if item == nil or ISHotbarAttachDefinition == nil then return nil end
    local ok, attachmentType = pcall(function() return item:getAttachmentType() end)
    if not ok or attachmentType == nil or attachmentType == "" then return nil end
    local resolved
    pcall(function()
        for _, definition in pairs(ISHotbarAttachDefinition) do
            if type(definition) == "table" and type(definition.attachments) == "table" then
                for category, location in pairs(definition.attachments) do
                    if category == attachmentType then
                        resolved = location
                        return
                    end
                end
            end
        end
    end)
    return resolved
end

local function homeLocation(item, itemType, class)
    local slot = attachmentSlotFor(item)
    if slot ~= nil then return slot end

    if class == "handgun" then return "Holster Right" end
    if class == "rifle" then return "Rifle On Back" end
    return nil
end

local function detachWeapon(shell, entry)
    if entry == nil or entry.item == nil then return true end

    if entry.location == handLocation
            and not (type(isServer) == "function" and isServer()) then
        pcall(function()
            if shell:getPrimaryHandItem() == entry.item then shell:setPrimaryHandItem(nil) end
        end)
        pcall(function()
            if shell:getSecondaryHandItem() == entry.item then
                shell:setSecondaryHandItem(nil)
            end
        end)
    end
    return pcall(function() shell:removeAttachedItem(entry.item) end)
end

local function rebuildDeathItems(shell, attachedItem)

    if type(isClient) == "function" and isClient() then return true end
    local inventoryOk, items = pcall(function()
        return shell:getInventory():getItems()
    end)
    if not inventoryOk or items == nil then return false end
    local cleared = pcall(function() ProjectALife.DeathInventory.clear(shell) end)
    if not cleared then return false end
    local countOk, count = pcall(function() return items:size() end)
    if not countOk then return false end
    for index = 0, count - 1 do
        local itemOk, item = pcall(function() return items:get(index) end)
        if itemOk and item ~= nil and item ~= attachedItem then
            local weaponOk, weapon = pcall(function() return item:IsWeapon() end)
            local dataOk, data = pcall(function() return item:getModData() end)
            local scavenged = dataOk and type(data) == "table"
                and data.ProjectALifeScavenged == true
            local identityCard = dataOk and type(data) == "table"
                and data.ProjectALifeIdentityCard == true
            local pocketLoot = dataOk and type(data) == "table"
                and data.ProjectALifePocketLoot == true
            local itemType = ""
            pcall(function() itemType = tostring(item:getFullType() or "") end)
            if itemType ~= "Base.BareHands" and ((weaponOk and weapon == true)
                    or scavenged or identityCard or pocketLoot) then
                pcall(function() ProjectALife.DeathInventory.add(shell, item) end)
            end
        end
    end
    return true
end

function Animations.forget(shell)
    if shell == nil then return false end
    return ProjectALife.EquipEventShield.withCleanup(shell, function()
    Animations.clearIdleProp(shell)
    local entry = Animations.weaponVisuals[shell]
    local function ours(item)
        if item == nil then return false end
        if entry ~= nil and item == entry.item then return true end
        local ok, data = pcall(function() return item:getModData() end)
        return ok and type(data) == "table" and (data.ProjectALifeWeaponSlot ~= nil
            or data.ProjectALifeActiveWeapon == true)
    end

    if not (type(isServer) == "function" and isServer()) then
        pcall(function()
            if ours(shell:getPrimaryHandItem()) then shell:setPrimaryHandItem(nil) end
        end)
        pcall(function()
            if ours(shell:getSecondaryHandItem()) then shell:setSecondaryHandItem(nil) end
        end)
    end
    if entry ~= nil and entry.item ~= nil then
        pcall(function() shell:removeAttachedItem(entry.item) end)
        pcall(function() shell:resetModelNextFrame() end)
    end

    if Animations.actSet[shell] ~= nil then Animations.stopAct(shell) end
    for _, name in ipairs({ "active", "current", "serial", "remoteToken", "weaponVisuals",
            "combatHold", "readyCarry", "fallback", "ownerPose", "actBeat", "fishing" }) do
        Animations[name][shell] = nil
    end
    for _, name in ipairs({ "ALifeWeaponHeld", "ALifeGrip", "ALifeArms", "ALifeReadyCarry" }) do
        setVariable(shell, name, "")
    end
    return true
    end)
end

Animations.bodyCaches = { "active", "current", "serial", "remoteToken", "weaponVisuals", "idleProps",
    "combatHold", "readyCarry", "fallback", "ownerPose", "actBeat", "fishing" }

function Animations.dropCaches(shell)
    if shell == nil then return false end
    if Animations.actSet[shell] ~= nil then pcall(Animations.stopAct, shell) end
    local names = Animations.bodyCaches
    for index = 1, #names do
        local cache = Animations[names[index]]
        if type(cache) == "table" then cache[shell] = nil end
    end
    return true
end

function Animations.repairGrip(shell, item, class)
    return pcall(function()

        local twoHand = class == "rifle" or item:isRequiresEquippedBothHands() == true
            or item:isTwoHandWeapon() == true
        local off = shell:getSecondaryHandItem()
        local changed = false
        if twoHand and Animations.idleProps[shell] == nil then
            if off ~= item then shell:setSecondaryHandItem(item); changed = true end
        elseif not twoHand and off == item then
            shell:setSecondaryHandItem(nil); changed = true
        end
        local grip = twoHand and "2hand" or "1hand"
        if tostring(getVariable(shell, "ALifeGrip") or "") ~= grip then
            setVariable(shell, "ALifeGrip", grip)
        end
        local data = metadata(shell)
        if data ~= nil then data.ProjectALifeGrip = grip end
        if changed then shell:resetModelNextFrame() end
    end)
end

function Animations.visitWeaponsDown(shell)
    local data, registry = metadata(shell), ProjectALife.ActorRegistry
    if type(data) ~= "table" or type(data.ProjectALifeUID) ~= "string"
            or registry == nil or type(registry.peek) ~= "function" then return false end
    local actor = registry.peek(data.ProjectALifeUID)
    local memory = actor and actor.memory
    local visit = type(memory) == "table" and memory.visit or nil
    if actor == nil or actor.lifecycle ~= "active" or actor.generation ~= tonumber(data.ProjectALifeGeneration)
            or memory.natural ~= true or memory.debugSpawn == true or type(visit) ~= "table"
            or visit.generation ~= actor.generation or visit.weaponsDown ~= true or type(getGameTime) ~= "function" then return false end
    local activity, intent = tostring(actor.activity or ""), tostring(actor.intent or "")
    if activity == "combat" or string.find(intent, "attack", 1, true) ~= nil
            or string.find(intent, "engage", 1, true) ~= nil or string.find(intent, "manhunt", 1, true) ~= nil then return false end
    local clock = getGameTime()
    if clock == nil or type(clock.getWorldAgeHours) ~= "function" then return false end
    local ok, hours = pcall(clock.getWorldAgeHours, clock)
    if not ok or type(hours) ~= "number" or hours ~= hours
            or hours > (tonumber(visit.untilHours) or -math.huge)
            or hours > (tonumber(visit.renewedHours) or -math.huge) + 3 then return false end
    if not (type(isClient) == "function" and isClient()) then
        local visits = ProjectALife.SafehouseVisit
        if visits == nil or type(visits.live) ~= "function" or visits.live(actor.uid) == nil then return false end
    end
    return true
end

function Animations.lowerVisitHands(shell, item)
    detachWeapon(shell, { item = item, location = handLocation })
    local changed = false
    for _, slot in ipairs({ { "getPrimaryHandItem", "setPrimaryHandItem" }, { "getSecondaryHandItem", "setSecondaryHandItem" } }) do
        pcall(function()
            if type(shell[slot[1]]) ~= "function" or type(shell[slot[2]]) ~= "function" then return end
            local held = shell[slot[1]](shell)
            if held ~= nil and type(held.IsWeapon) == "function" and held:IsWeapon() == true then
                shell[slot[2]](shell, nil)
                changed = true
            end
        end)
    end
    if changed and type(shell.resetModelNextFrame) == "function" then pcall(shell.resetModelNextFrame, shell) end
end

function Animations.presentWeapon(shell, item, itemType, class, held)
    if shell == nil then return false, "weapon_shell_missing" end
    if instanceof ~= nil and instanceof(shell, "IsoPlayer") then return false, "player_presentation_forbidden" end
    if ProjectALife.TraversalHands.held(shell) then return true end
    local previous = Animations.weaponVisuals[shell]
    if item == nil or type(itemType) ~= "string" or itemType == "" then
        detachWeapon(shell, previous)

        if not (type(isServer) == "function" and isServer()) then
            pcall(function()
                local prop = Animations.idleProps[shell]
                if prop == nil or shell:getPrimaryHandItem() ~= prop.item then shell:setPrimaryHandItem(nil) end
            end)
            pcall(function()
                local prop = Animations.idleProps[shell]
                if prop == nil or shell:getSecondaryHandItem() ~= prop.item then shell:setSecondaryHandItem(nil) end
            end)
        end

        setVariable(shell, "ALifeGrip", "")
        pcall(function()
            local stale = metadata(shell)
            if stale ~= nil then stale.ProjectALifeGrip = nil end
        end)
        Animations.weaponVisuals[shell] = nil
        rebuildDeathItems(shell, nil)
        local data = metadata(shell)
        if data ~= nil then
            data.ProjectALifeWeaponAttachmentLocation = nil
            data.ProjectALifeWeaponHeld = false
        end
        setVariable(shell, "ALifeWeaponHeld", false)
        pcall(function() shell:resetModelNextFrame() end)
        return item == nil
    end

    class = weaponClass(itemType, class)
    setVariable(shell, "ALifeArms", Animations.armsOf(class))
    local home = homeLocation(item, itemType, class)

    local canEquip = not (type(isServer) == "function" and isServer())

    local lower = Animations.visitWeaponsDown(shell)
    local useHand = canEquip and not lower
    if lower and canEquip then Animations.lowerVisitHands(shell, item) end

    pcall(function()
        local busy = shell:getModData()
        if busy == nil then return end
        local until_ = tonumber(busy.ProjectALifeHandsBusyUntilMs)
        if until_ == nil then return end
        local now = type(getTimestampMs) == "function" and getTimestampMs()
            or math.floor(os.time() * 1000)
        if now < until_ then
            useHand = false
        else

            busy.ProjectALifeHandsBusyUntilMs = nil
        end
    end)
    local location = useHand and handLocation or home

    if location == nil then
        detachWeapon(shell, previous)
        Animations.weaponVisuals[shell] = nil
        local data = metadata(shell)
        if data ~= nil then
            data.ProjectALifeWeaponAttachmentLocation = nil
            data.ProjectALifeWeaponHeld = false
        end
        rebuildDeathItems(shell, nil)
        pcall(function() shell:resetModelNextFrame() end)
        return true
    end
    if previous ~= nil and previous.item == item and previous.location == location then

        if location == handLocation then
            local handOk, held = pcall(function() return shell:getPrimaryHandItem() end)
            if handOk and held == item then return Animations.repairGrip(shell, item, class) end
        else
            local currentOk, current = pcall(function() return shell:getAttachedItem(location) end)
            if not currentOk or current == item then return true end
        end
    end
    if previous ~= nil then detachWeapon(shell, previous) end

    if location == handLocation then

        pcall(function()
            if shell:getPrimaryHandItem() ~= item then shell:setPrimaryHandItem(item) end
        end)
        local equipped = false
        pcall(function() equipped = shell:getPrimaryHandItem() == item end)
        if equipped then

            setVariable(shell, "ALifeWeaponHeld", true)
            Animations.repairGrip(shell, item, class)
            Animations.weaponVisuals[shell] = {
                item = item, itemType = itemType, class = class,
                homeLocation = home, location = handLocation,
            }
            local heldData = metadata(shell)
            if heldData ~= nil then
                heldData.ProjectALifeActiveWeaponType = itemType
                heldData.ProjectALifeWeaponClass = class
                heldData.ProjectALifeWeaponAttachmentLocation = handLocation
                heldData.ProjectALifeWeaponHeld = true
            end

            rebuildDeathItems(shell, nil)
            pcall(function() shell:resetModelNextFrame() end)
            return true
        end

        location = home
        if location == nil then return true end
    end

    local staticOk, staticModel = pcall(function() return item:getStaticModel() end)
    if not staticOk or type(staticModel) ~= "string" or staticModel == "" then
        Animations.weaponVisuals[shell] = nil
        return false, "weapon_static_model_missing"
    end
    local attached = pcall(function() shell:setAttachedItem(location, item) end)
    if not attached and location ~= home then
        location = home
        attached = pcall(function() shell:setAttachedItem(location, item) end)
    end
    if not attached then return false, "weapon_attachment_failed" end

    Animations.weaponVisuals[shell] = {
        item = item,
        itemType = itemType,
        class = class,
        homeLocation = home,
        location = location,
    }
    local data = metadata(shell)
    if data ~= nil then
        data.ProjectALifeActiveWeaponType = itemType
        data.ProjectALifeWeaponClass = class
        data.ProjectALifeWeaponAttachmentLocation = location
        data.ProjectALifeWeaponHeld = location == handLocation
    end
    setVariable(shell, "ALifeWeaponHeld", location == handLocation)

    rebuildDeathItems(shell, item)
    pcall(function() shell:resetModelNextFrame() end)
    return true
end

local function activeInventoryWeapon(shell)
    local ok, items = pcall(function() return shell:getInventory():getItems() end)
    if not ok or items == nil then return nil end
    local countOk, count = pcall(function() return items:size() end)
    if not countOk then return nil end

    local wantedType
    pcall(function()
        wantedType = shell:getModData().ProjectALifeActiveWeaponType
    end)
    local byType, bySlot, fallback, fallbackFirearm
    local prop = Animations.idleProps[shell]
    for index = 0, count - 1 do
        local item = items:get(index)
        local weaponOk, isWeapon = pcall(function() return item:IsWeapon() end)
        if weaponOk and isWeapon == true and not (prop ~= nil and prop.item == item) then
            local firearm = false
            pcall(function() firearm = item:isAimedFirearm() == true end)
            if fallback == nil or (firearm and not fallbackFirearm) then
                fallback, fallbackFirearm = item, firearm
            end
            local itemDataOk, itemData = pcall(function() return item:getModData() end)
            if itemDataOk and type(itemData) == "table" then
                if itemData.ProjectALifeActiveWeapon == true then return item end
                if bySlot == nil and itemData.ProjectALifeWeaponSlot == "primary" then
                    bySlot = item
                end
            end
            if byType == nil and wantedType ~= nil then
                pcall(function()
                    if tostring(item:getFullType()) == tostring(wantedType) then
                        byType = item
                    end
                end)
            end
        end
    end

    return byType or bySlot or fallback
end

function Animations.refreshWeapon(shell, held)
    if shell == nil then return false end
    local data = metadata(shell)
    local item = activeInventoryWeapon(shell)
    if item == nil then
        local previous = Animations.weaponVisuals[shell]
        if previous == nil then return false end

        return Animations.presentWeapon(shell, previous.item, previous.itemType,
            previous.class, held)
    end
    local typeOk, itemType = pcall(function() return item:getFullType() end)
    itemType = typeOk and tostring(itemType) or data and data.ProjectALifeActiveWeaponType
    return Animations.presentWeapon(shell, item, itemType,
        Animations.weaponClassOf(data), held)
end

function Animations.setCombatHold(shell, on, deferEquip)
    if shell == nil then return false end
    if on then
        Animations.combatHold[shell] = true
    else
        Animations.combatHold[shell] = nil
    end

    return Animations.refreshWeapon(shell,
        Animations.readyCarry[shell] == true
            or (on == true and deferEquip ~= true))
end

function Animations.setReadyCarry(shell, on)
    if shell == nil then return false end
    if on then
        Animations.readyCarry[shell] = true
    else
        Animations.readyCarry[shell] = nil
    end
    local data = metadata(shell)
    if data ~= nil then data.ProjectALifeReadyCarry = on == true end
    setVariable(shell, "ALifeReadyCarry", on == true)
    return Animations.refreshWeapon(shell, on == true)
end

Animations.idleProps = setmetatable({}, { __mode = "k" })

function Animations.fishingRodVisual(body, wanted)
    if body == nil or type(body.getHumanVisual) ~= "function" then return false end
    local visual = body:getHumanVisual()
    if visual == nil or type(visual.hasBodyVisualFromItemType) ~= "function"
            or type(visual.addBodyVisualFromItemType) ~= "function"
            or type(visual.removeBodyVisualFromItemType) ~= "function" then return false end
    local proxy = "ProjectALife.PALPreview_FishingRod_Modern"
    wanted = wanted == true
    local present = visual:hasBodyVisualFromItemType(proxy) == true
    if present == wanted then return true end
    if type(body.resetModelNextFrame) ~= "function" and type(body.invalidateCorpse) ~= "function" then return false end
    if wanted then
        visual:addBodyVisualFromItemType(proxy)
    else
        visual:removeBodyVisualFromItemType(proxy)
    end
    if visual:hasBodyVisualFromItemType(proxy) ~= wanted then return false end
    if type(body.resetModelNextFrame) == "function" then
        body:resetModelNextFrame()
    else
        body:invalidateCorpse()
    end
    return true
end

Animations.propLocations = { right = "ALife Prop Right", left = "ALife Prop Left" }
Animations.propBones = { right = "Bip01_Prop1", left = "Bip01_Prop2" }

function Animations.registerPropLocations()
    if AttachedLocations == nil or type(AttachedLocations.getGroup) ~= "function" then return false end
    local grouped, group = pcall(AttachedLocations.getGroup, "Human")
    if not grouped or group == nil or type(group.getOrCreateLocation) ~= "function" then return false end
    local ready = true
    for side, name in pairs(Animations.propLocations) do
        local made, location = pcall(group.getOrCreateLocation, group, name)
        if not made or location == nil or type(location.setAttachmentName) ~= "function"
                or not pcall(location.setAttachmentName, location, Animations.propBones[side]) then
            ready = false
        end
    end
    Animations.propLocationsReady = ready
    return ready
end

function Animations.propLocationFor(item, hand)
    if Animations.propLocationsReady ~= true or item == nil or type(item.IsWeapon) ~= "function" then return nil end
    local ok, weapon = pcall(item.IsWeapon, item)
    if not ok or weapon == true then return nil end
    if hand == "primary" or hand == "both" then return Animations.propLocations.right end
    return Animations.propLocations.left
end

function Animations.attachProp(shell, entry)
    if type(shell.setAttachedItem) ~= "function" then return false end
    return pcall(shell.setAttachedItem, shell, entry.location, entry.item)
end

function Animations.holdProp(shell, item, hand)
    if hand == "primary" or hand == "both" then shell:setPrimaryHandItem(item) end
    if hand == "secondary" or hand == "both" then shell:setSecondaryHandItem(item) end
end

function Animations.propInHand(shell, entry)
    if entry.location ~= nil then
        local attached, current = pcall(function() return shell:getAttachedItem(entry.location) end)
        return attached == true and current == entry.item
    end
    local ok, primary, secondary = pcall(function()
        return shell:getPrimaryHandItem(), shell:getSecondaryHandItem()
    end)
    if not ok then return false end
    local hand = entry.hand
    if (hand == "primary" or hand == "both") and primary ~= entry.item then return false end
    if (hand == "secondary" or hand == "both") and secondary ~= entry.item then return false end
    return true
end

function Animations.dropPropItem(shell, entry)
    local weapon = Animations.weaponVisuals[shell]
    if weapon ~= nil and weapon.item == entry.item then
        detachWeapon(shell, weapon)
        Animations.weaponVisuals[shell] = nil
        local data = metadata(shell)
        if data ~= nil then
            data.ProjectALifeActiveWeaponType, data.ProjectALifeWeaponClass = nil, nil
            data.ProjectALifeWeaponAttachmentLocation, data.ProjectALifeWeaponHeld = nil, false
        end
    end
    if entry.location ~= nil then
        pcall(function() shell:removeAttachedItem(entry.item) end)
        return
    end
    pcall(function()
        if shell:getPrimaryHandItem() == entry.item then shell:setPrimaryHandItem(nil) end
        if shell:getSecondaryHandItem() == entry.item then shell:setSecondaryHandItem(nil) end
    end)
    pcall(function()
        local inventory = shell:getInventory()
        if inventory ~= nil then inventory:Remove(entry.item) end
    end)
end

function Animations.clearIdleProp(shell)
    Animations.fishingRodVisual(shell, false)
    local entry = Animations.idleProps[shell]
    if entry then
        Animations.dropPropItem(shell, entry)
        pcall(function() shell:resetModelNextFrame() end)
        Animations.idleProps[shell] = nil
    end
    pcall(function()
        local data = shell:getModData()
        if data.ProjectALifeIdleHandsBusy then
            data.ProjectALifeIdleHandsBusy = nil
            data.ProjectALifeHandsBusyUntilMs = nil
        end
    end)
end

function Animations.presentIdleProp(shell, preset)
    pcall(function()
        local data = shell:getModData()
        data.ProjectALifeIdleHandsBusy = true
        data.ProjectALifeHandsBusyUntilMs = nowMs() + (preset.timeoutMs or 12000) + 1000
    end)
    Animations.refreshWeapon(shell, false)

    local pick = Animations.variantOf(shell, preset)
    local propType = pick.prop or preset.prop
    if not propType then return end
    local hand = pick.hand or preset.hand or "secondary"
    local server = type(isServer) == "function" and isServer() == true
    local client = type(isClient) == "function" and isClient() == true
    local dedicated = server and not client
    if dedicated then
        Animations.metrics.propsRefusedDedicated = Animations.metrics.propsRefusedDedicated + 1
        return
    end
    local entry = Animations.idleProps[shell]

    if entry and entry.id == preset.id and entry.propType == propType then
        if Animations.propInHand(shell, entry) then return end
        Animations.dropPropItem(shell, entry)
        Animations.idleProps[shell] = nil
    elseif entry then
        Animations.dropPropItem(shell, entry)
        Animations.idleProps[shell] = nil
    end

    if type(instanceItem) ~= "function" then
        Animations.metrics.propsNoFactory = Animations.metrics.propsNoFactory + 1
        return
    end
    pcall(function()
        local item = instanceItem(propType)
        if not item then return end

        local location = nil
        if preset.fishing ~= true then location = Animations.propLocationFor(item, hand) end
        if location ~= nil then
            local attached = { id = preset.id, item = item, hand = hand, propType = propType, location = location }
            if Animations.attachProp(shell, attached) then
                Animations.idleProps[shell] = attached
                Animations.metrics.propsApplied = Animations.metrics.propsApplied + 1
                shell:resetModelNextFrame()
                return
            end
        end

        pcall(function()
            local inventory = shell:getInventory()
            if inventory ~= nil then inventory:AddItem(item) end
        end)

        Animations.holdProp(shell, item, hand)
        Animations.idleProps[shell] = { id = preset.id, item = item, hand = hand, propType = propType }
        Animations.metrics.propsApplied = Animations.metrics.propsApplied + 1
        shell:resetModelNextFrame()
    end)
end

function Animations.drawSequenceFor(shell, item)
    if shell == nil then return nil, 0 end
    local entry = Animations.weaponVisuals[shell]
    local home = string.lower(tostring(entry and (entry.homeLocation
        or entry.location) or ""))
    if string.find(home, "holster", 1, true) then
        return "draw_holster_reach", 420, "draw_holster", 750
    end
    if string.find(home, "left", 1, true) then
        return "draw_belt_left_reach", 420, "draw_belt_left", 750
    end
    if string.find(home, "belt", 1, true)
            or string.find(home, "right", 1, true) then
        return "draw_belt_right_reach", 420, "draw_belt_right", 750
    end
    local both = false
    pcall(function()
        both = item ~= nil and (item:isRequiresEquippedBothHands() == true
            or item:isTwoHandWeapon() == true)
    end)
    if both or string.find(home, "back", 1, true) then
        return "draw_back_reach", 450, "draw_back", 850
    end

    return "draw_belt_right_reach", 420, "draw_belt_right", 750
end

function Animations.drawPresetFor(shell, item)
    local _, _, preset, duration = Animations.drawSequenceFor(shell, item)
    return preset, duration
end

function Animations.weaponIsHeld(shell)
    if shell == nil then return false end

    local server = type(isServer) == "function" and isServer()
    if not server then
        local handOk, held = pcall(function() return shell:getPrimaryHandItem() end)
        if handOk then
            if held == nil then return false end
            local active = activeInventoryWeapon(shell)
            return active == nil or held == active
        end
    end

    if server and Animations.readyCarry[shell] == true then return true end
    if server and Animations.combatHold[shell] == true then return true end
    local entry = Animations.weaponVisuals[shell]
    if entry ~= nil and entry.location == handLocation then return true end
    local data = metadata(shell)
    return data ~= nil and data.ProjectALifeWeaponHeld == true
end

local function setWeaponHeld(shell, held)

    return Animations.refreshWeapon(shell, held)
end

local function ownsAnimation(shell)
    if Animations.current[shell] ~= nil or Animations.active[shell] ~= nil then return true end
    if Animations.actSet[shell] ~= nil then return true end
    if tostring(getVariable(shell, "ALifeGesture") or "") ~= "" then return true end
    local ok, bumpType = pcall(function() return shell:getBumpType() end)
    return ok and string.sub(tostring(bumpType or ""), 1, 5) == "ALife"
end

function Animations.floorFlags(shell)
    return shell:isOnFloor() == true or shell:isKnockedDown() == true
        or shell:isProne() == true or shell:isCrawling() == true
        or (type(shell.isRagdoll) == "function" and shell:isRagdoll() == true)
end

local function onTheFloor(shell)
    local ok, grounded = pcall(Animations.floorFlags, shell)
    return ok and grounded == true
end

Animations.floorStatePrefixes = { "onground", "falldown", "falling", "getdown", "getup", "knockeddown", "fakedead",
    "hitreaction-onfloor", "hitreaction-gettingup", "staggerback-knockeddown",
    "vehiclecollision-falldown", "vehiclecollision-onground" }
function Animations.blocksLocomotion(shell)
    if shell == nil then return true end
    local id = Animations.current[shell]
    if id == "get_up_front" or id == "get_up_back" then return true end
    local data = metadata(shell)
    local recovery = data ~= nil and tonumber(data.ProjectALifeGroundRecoveryUntilMs) or nil
    if recovery ~= nil and nowMs() < recovery then return true end
    local injured = data ~= nil and tonumber(data.ProjectALifeInjuryHoldUntilMs) or nil
    if injured ~= nil and nowMs() < injured then return true end
    return Animations.bodyDown(shell)
end

function Animations.bodyDown(shell)
    if shell == nil then return false end
    if onTheFloor(shell) then return true end
    local state = ""
    if shell.getActionStateName ~= nil then state = string.lower(tostring(shell:getActionStateName() or "")) end

    if string.find(state, "ragdoll", 1, true) ~= nil then return true end
    local prefixes = Animations.floorStatePrefixes
    for index = 1, #prefixes do
        local prefix = prefixes[index]
        if string.sub(state, 1, #prefix) == prefix then return true end
    end
    return false
end

local function recoverPosture(shell, combat, standUp)
    pcall(function() shell:setBumpFall(false) end)
    pcall(function() shell:setBumpFallType("") end)
    pcall(function() shell:setBumpType("") end)
    pcall(function() shell:setCrawler(false) end)
    pcall(function() shell:setBecomeCrawler(false) end)
    pcall(function() shell:setCanWalk(true) end)
    pcall(function() shell:setFakeDead(false) end)
    pcall(function() shell:setForceFakeDead(false) end)

    if standUp == true or not onTheFloor(shell) then
        pcall(function() shell:setKnockedDown(false) end)
        pcall(function() shell:setOnFloor(false) end)
        pcall(function() shell:setFallOnFront(false) end)
    end
    pcall(function()

        local state = string.lower(tostring(shell:getActionStateName() or ""))
        if string.sub(state, 1, 11) ~= "hitreaction" then
            shell:setHitReaction("")
        end
    end)
    setVariable(shell, "BumpDone", true)
    setVariable(shell, "BumpAnimFinished", true)
    setVariable(shell, "BumpFall", false)
    setVariable(shell, "BumpFallType", "")
    setVariable(shell, "BumpFallAnimFinished", true)
    setVariable(shell, "bCrawler", false)
    setVariable(shell, "bCrawling", false)
    if standUp == true or not onTheFloor(shell) then
        setVariable(shell, "bOnFloor", false)
        setVariable(shell, "FallOnFront", false)
    end
    setVariable(shell, "ALifeGesture", "")
    if Animations.actSet[shell] ~= nil then Animations.stopAct(shell) end
    if combat == true then
        setVariable(shell, "Attack", false)
        setVariable(shell, "AttackStarted", false)
        setVariable(shell, "AttackDidDamage", false)
        setVariable(shell, "AttackOutcome", "")
        setVariable(shell, "ShoveAnim", false)
    end
end

local function sync(shell, id, poseOnly)
    if Animations.suppressSync == true then return end
    if type(isClient) == "function" and isClient() then
        local executor = ProjectALife.Executor
        local uid = executor and executor.byShell and executor.byShell[shell]
        local entry = uid and executor.executed[uid]
        if entry ~= nil then
            local pose = Animations.capturePose(shell)
            if type(executor.sendPose) == "function" then executor.sendPose(shell, pose) end
            for key, value in pairs(pose) do
                if entry.lastPoseSent == nil or entry.lastPoseSent[key] ~= value then
                    entry.poseDirty = true
                    break
                end
            end
        end
        return
    end
    if type(isServer) ~= "function" or not isServer()
            or type(sendServerCommand) ~= "function" then return end
    local onlineOk, onlineId = pcall(function() return shell:getOnlineID() end)
    local identityOk, uid, generation, weaponType, weaponClassValue,
        weaponLocation, weaponHeld, pace, combatPhase, aimWalk,
        dangerPosture, readyCarry, presentation = pcall(function()
        local data = shell:getModData()
        return data.ProjectALifeUID, tonumber(data.ProjectALifeGeneration),
            data.ProjectALifeActiveWeaponType, data.ProjectALifeWeaponClass,
            data.ProjectALifeWeaponAttachmentLocation,
            data.ProjectALifeWeaponHeld == true,
            getVariable(shell, "ALifePace") or data.ProjectALifePace or "walk",
            data.ProjectALifeCombatPhase or getVariable(shell, "ALifeCombatPhase") or "idle",
            data.ProjectALifeAimWalk == true,
            data.ProjectALifeDangerPosture or "relaxed",
            Animations.readyCarry[shell] == true
                or data.ProjectALifeReadyCarry == true, {
                female = data.ProjectALifeFemale,
                voiceProfile = data.ProjectALifeVoiceProfile,
                skin = data.ProjectALifeSkin,
                skinTexture = data.ProjectALifeSkinTexture,
                hair = data.ProjectALifeHairStyle,
                hairColor = data.ProjectALifeHairColor,
                beard = data.ProjectALifeBeardStyle,
                beardColor = data.ProjectALifeBeardColor,
                clothing = data.ProjectALifeClothingTypes,
                clothingTints = data.ProjectALifeClothingTints,
                appearanceSeed = data.ProjectALifeAppearanceSeed,
                bandages = data.ProjectALifeBandages,
            }
    end)
    if not identityOk or type(uid) ~= "string" then
        identityOk, uid, generation = pcall(function()
            return shell:GetVariable("ALifeUID"),
                tonumber(shell:GetVariable("ALifeGeneration"))
        end)
    end
    local message = {
        onlineId = onlineOk and onlineId or -1,
          uid = identityOk and uid or nil,
        generation = identityOk and generation or nil,
        weaponType = weaponType,
        weaponClass = weaponClassValue,
        weaponLocation = weaponLocation,
        weaponHeld = weaponHeld,

        handsBusyUntilMs = (function()
            local value
            pcall(function()
                value = tonumber(shell:getModData().ProjectALifeHandsBusyUntilMs)
            end)
            return value
        end)(),
        pace = pace,
        combatPhase = combatPhase,
        aimWalk = aimWalk,
        dangerPosture = dangerPosture,
        combatHold = Animations.combatHold[shell] == true,
        readyCarry = readyCarry == true,
        presentation = presentation,
        simulation = ProjectALife.ShellSimulation and ProjectALife.ShellSimulation.capture(shell) or nil,
        animation = id,
        animationSerial = animationSerial(shell, false),

        sneak = (function()
            local value = false
            pcall(function()
                value = shell:getModData().ProjectALifeSneakActive == true
            end)
            return value
        end)(),
        limp = (function()
            local value = false
            pcall(function()
                local data = shell:getModData()
                if data.ProjectALifeWoundLeg ~= true then return end

                local health = ProjectALife.Health
                local armed = health ~= nil and type(health.settings) == "table"
                    and health.settings.limpWithWeapon == true
                value = armed or data.ProjectALifeWeaponHeld ~= true
            end)
            return value
        end)(),
    }

    local pose = Animations.ownerPose[shell]
    if pose ~= nil then
        for key, value in pairs(pose) do message[key] = value end
        if message.presentation ~= nil then message.presentation.bandages = Animations.poseBandages(pose.bandages) end
    end
    if poseOnly then message.presentation = nil end
    pcall(sendServerCommand, "ProjectALife", "animationSync", message)
end

function Animations.capturePose(shell)
    local data = metadata(shell) or {}
    return { animation = Animations.current[shell] or "normal",
        animationSerial = animationSerial(shell, false),
        aimWalk = data.ProjectALifeAimWalk == true,
        weaponHeld = data.ProjectALifeWeaponHeld == true,
        combatHold = Animations.combatHold[shell] == true,
        readyCarry = Animations.readyCarry[shell] == true,
        pace = data.ProjectALifePace == "sprint" and "sprint" or (data.ProjectALifePace == "run" and "run" or "walk"),
        combatPhase = tostring(data.ProjectALifeCombatPhase or "idle"),
        limp = data.ProjectALifeWoundLeg == true and (data.ProjectALifeWeaponHeld ~= true
            or (ProjectALife.Health ~= nil and ProjectALife.Health.settings.limpWithWeapon == true)),
        wounds = math.max(0, math.min(10000, math.floor(tonumber(data.ProjectALifeWounds) or 0))),
        woundZone = tostring(data.ProjectALifeLastWoundZone or ""),
        injured = tostring(data.ProjectALifeInjured or ""),
        bandages = table.concat(type(data.ProjectALifeBandages) == "table" and data.ProjectALifeBandages or {}, "|") }
end

Animations.bandageTypes = { ["Base.Bandage_Head"] = true, ["Base.Bandage_Chest"] = true,
    ["Base.Bandage_LeftLowerArm"] = true, ["Base.Bandage_RightLowerArm"] = true,
    ["Base.Bandage_LeftLowerLeg"] = true, ["Base.Bandage_RightLowerLeg"] = true }

function Animations.poseBandages(value)
    if type(value) ~= "string" or #value > 128 then return nil end
    local out, seen = {}, {}
    for itemType in string.gmatch(value, "[^|]+") do
        if not Animations.bandageTypes[itemType] or seen[itemType] or #out >= 3 then return nil end
        seen[itemType] = true
        out[#out + 1] = itemType
    end
    return out
end

function Animations.validWoundPose(pose)
    if pose.limp ~= nil and type(pose.limp) ~= "boolean" then return false end
    if pose.wounds ~= nil and (type(pose.wounds) ~= "number" or pose.wounds ~= pose.wounds
            or pose.wounds < 0 or pose.wounds > 10000 or pose.wounds ~= math.floor(pose.wounds)) then return false end
    if pose.bandages ~= nil and Animations.poseBandages(pose.bandages) == nil then return false end
    if pose.woundZone ~= nil and pose.woundZone ~= "" and pose.woundZone ~= "head"
            and pose.woundZone ~= "torso" and pose.woundZone ~= "body" and pose.woundZone ~= "limb" then return false end
    if pose.injured ~= nil and pose.injured ~= "" and pose.injured ~= "down" and pose.injured ~= "dragged"
            and pose.injured ~= "healing" and pose.injured ~= "recovering" then return false end
    return true
end

function Animations.receiveOwnerPose(shell, pose)
    if type(pose) ~= "table" or not Animations.supports(pose.animation) or not Animations.validWoundPose(pose) then return false end
    local serial = pose.animationSerial
    if type(serial) ~= "number" or serial ~= serial or serial < 0 or serial > 2147483647 then return false end
    local previous = Animations.ownerPose[shell]
    if previous ~= nil and serial < previous.animationSerial then return false end
    if type(pose.combatPhase) ~= "string" or #pose.combatPhase > 32
            or not string.match(pose.combatPhase, "^[%w_]+$") then return false end
    Animations.ownerPose[shell] = { animation = pose.animation, animationSerial = math.floor(serial),
        aimWalk = pose.aimWalk == true, weaponHeld = pose.weaponHeld == true,
        combatHold = pose.combatHold == true, readyCarry = pose.readyCarry == true,
        pace = pose.pace == "sprint" and "sprint" or (pose.pace == "run" and "run" or "walk"), combatPhase = pose.combatPhase,
        limp = pose.limp == true, wounds = pose.wounds, woundZone = pose.woundZone,
        injured = pose.injured, bandages = pose.bandages }
    local data = metadata(shell)
    if data ~= nil and pose.injured ~= nil then
        data.ProjectALifeInjured = pose.injured ~= "" and pose.injured or nil
    end
    sync(shell, pose.animation, true)
    return true
end

function Animations.holdsProp(preset)
    if type(preset) ~= "table" then return false end
    if preset.prop ~= nil then return true end
    if type(preset.variants) ~= "table" then return false end
    for index = 1, #preset.variants do
        if preset.variants[index].prop ~= nil then return true end
    end
    return false
end

function Animations.noteRemoteActivity(shell, activity)
    if shell == nil or type(activity) ~= "string" then return false end
    local id = string.match(activity, "^idle_(%w+)$")
    local preset = id ~= nil and byId[id] or nil
    if Animations.holdsProp(preset) then
        Animations.current[shell] = id
        Animations.metrics.remoteBeats = (Animations.metrics.remoteBeats or 0) + 1
        return true
    end

    local current = byId[Animations.current[shell]]
    if Animations.holdsProp(current) then Animations.current[shell] = nil end
    return false
end

function Animations.syncPresentation(shell)
    if shell == nil then return false end
    local currentPreset = byId[Animations.current[shell]]
    Animations.refreshWeapon(shell, Animations.readyCarry[shell] == true
        or Animations.combatHold[shell] == true
        or (currentPreset ~= nil and currentPreset.combat == true))
    sync(shell, Animations.current[shell] or "normal")
    return true
end

function Animations.syncState(shell)
    if shell == nil then return false end
    sync(shell, Animations.current[shell] or "normal")
    return true
end

function Animations.installFishingVisualHooks()
    local event = type(Events) == "table" and Events.OnDeadBodySpawn or nil
    if event ~= nil and type(event.Add) == "function" and ProjectALife.FishingCorpseVisualHook == nil then
        local callback = function(body) ProjectALife.Animations.fishingRodVisual(body, false) end
        event.Add(callback)
        ProjectALife.FishingCorpseVisualHook = callback
    end
    local loaded = type(Events) == "table" and Events.LoadGridsquare or nil
    if loaded ~= nil and type(loaded.Add) == "function" and ProjectALife.FishingSquareVisualHook == nil then
        local callback = function(square)
            if square == nil or type(square.getStaticMovingObjects) ~= "function" then return end
            local objects = square:getStaticMovingObjects()
            if objects == nil or type(objects.size) ~= "function" or type(objects.get) ~= "function" then return end
            for i = 0, objects:size() - 1 do
                local body = objects:get(i)
                if body ~= nil and type(instanceof) == "function" and instanceof(body, "IsoDeadBody") then
                    ProjectALife.Animations.fishingRodVisual(body, false)
                end
            end
        end
        loaded.Add(callback)
        ProjectALife.FishingSquareVisualHook = callback
    end
end

function Animations.configure(adapters)
    Animations.adapters = adapters or {}
    Animations.oneShotTimeoutMs = math.max(500, math.min(10000,
        math.floor(tonumber(Animations.adapters.oneShotTimeoutMs) or 2800)))
    Animations.installFishingVisualHooks()
    Animations.registerPropLocations()
end

function Animations.list()
    local result = {}
    for _, preset in ipairs(presets) do
        if preset.hidden ~= true then
            result[#result + 1] = { id = preset.id, label = preset.label }
        end
    end
    return result
end

function Animations.supports(id)
    return type(id) == "string" and (byId[id] ~= nil or Animations.aliases[id] ~= nil)
end

function Animations.clear(shell)
    if shell == nil then return false end
    if Animations.dragLocked(shell) then return false end
    Animations.fishing[shell] = nil
    Animations.clearIdleProp(shell)
    Animations.fallback[shell] = nil
    pcall(function()
        local data = shell:getModData()
        if type(data) == "table" then data.ProjectALifeHeldBump, data.ProjectALifeHeldAct = nil, nil end
    end)
    local previousId = Animations.current[shell]
    local previous = byId[previousId]
    local owned = ownsAnimation(shell)
    recoverPosture(shell, previous ~= nil and previous.combat == true)

    pcall(function() shell:setBumpDone(true) end)
    setWeaponHeld(shell, Animations.readyCarry[shell] == true
        or Animations.combatHold[shell] == true)
    Animations.active[shell] = nil
    Animations.current[shell] = nil
    if owned then animationSerial(shell, true) end
    sync(shell, "normal")
    return true
end

function Animations.apply(shell, id, force)
    id = Animations.aliases[id] or id
    local preset = byId[id]
    if shell == nil or preset == nil then return false, "animation_invalid" end
    if preset.bumpType == nil then return Animations.clear(shell) end
    if preset.fishing ~= true then Animations.fishing[shell] = nil end
    if id == "drag_grab" then
        local data = metadata(shell)
        local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
        local duration = tonumber(data and data.ProjectALifeDragDurationMs)
            or (tonumber(type(vars) == "table" and vars.Zombies_DragDownTenths) or 30) * 100
        setVariable(shell, "ALifeDragSpeed", 3533.333333 / math.max(500, math.min(6000, duration)))
    end
    if preset.idle == true and force ~= true and Animations.suppressSync ~= true
            and type(Animations.idleGate) == "function" then
        local gateOk, danger = pcall(Animations.idleGate, shell)
        if gateOk and danger ~= nil then
            Animations.metrics.idleRefused = (Animations.metrics.idleRefused or 0) + 1
            return false, "idle_danger"
        end
    end
    local bumpType = Animations.variantOf(shell, preset).bumpType or preset.bumpType
    if string.sub(id, 1, 5) ~= "drag_" and Animations.dragLocked(shell) then
        return false, "animation_drag_locked"
    end

    if id ~= "get_up_front" and id ~= "get_up_back" and Animations.bodyDown(shell) then
        Animations.metrics.presetsRefusedDown = (Animations.metrics.presetsRefusedDown or 0) + 1
        return false, "animation_body_down"
    end
    if (preset.held == true or preset.looped == true) and Animations.current[shell] == id then
        if preset.handsFree then Animations.presentIdleProp(shell, preset) end
        if preset.combat == true then setWeaponHeld(shell, true) end
        return true
    end

    if id == "hit_react" then Animations.fallback[shell] = nil end

    local previous = byId[Animations.current[shell]]
    Animations.clearIdleProp(shell)
    if preset.handsFree then
        pcall(function()
            local data = shell:getModData()
            data.ProjectALifeIdleHandsBusy = true
            data.ProjectALifeHandsBusyUntilMs = nowMs() + (preset.timeoutMs or 12000) + 1000
        end)
    end
    local standUp = id == "get_up_front" or id == "get_up_back"
    if ownsAnimation(shell) then
        recoverPosture(shell, previous ~= nil and previous.combat == true, standUp)
    else

        recoverPosture(shell, false, standUp)
    end
    setVariable(shell, "BumpFall", false)
    pcall(function() shell:setBumpFall(false) end)
    local act = Animations.actRoute(id)
    if act ~= nil then

        if type(shell.setBumpDone) == "function" then pcall(shell.setBumpDone, shell, true) end
        if not Animations.startAct(shell, id, act) then return false, "animation_shell_unsupported" end
    else
        local ok = pcall(function() shell:setBumpType(bumpType) end)
        if not ok then return false, "animation_shell_unsupported" end

        pcall(function() shell:setBumpDone(false) end)
        setVariable(shell, "BumpDone", false)
        setVariable(shell, "BumpAnimFinished", false)
        setVariable(shell, "BumpFall", false)
    end
    setVariable(shell, "ALifeGesture", id)
    Animations.current[shell] = id
    pcall(function()
        local blackBox = ProjectALife.BlackBox
        if blackBox ~= nil then blackBox.note(shell, "preset", id) end
    end)

    pcall(function()
        local data = shell:getModData()
        if type(data) == "table" then
            data.ProjectALifeHeldBump = (preset.held == true or preset.looped == true
                    or (preset.combat == true and preset.timeoutMs
                        and preset.timeoutMs >= 2000)) and bumpType or nil

            if act ~= nil and data.ProjectALifeHeldBump ~= nil then
                data.ProjectALifeHeldAct = id
            else
                data.ProjectALifeHeldAct = nil
            end
        end
    end)
    if preset.held ~= true then
        local timeout = preset.timeoutMs or Animations.oneShotTimeoutMs
        local startedAt = nowMs()
        local identity = metadata(shell) or {}
        Animations.active[shell] = {
            id = id,
            uid = identity.ProjectALifeUID,
            generation = identity.ProjectALifeGeneration,
            startedAtMs = startedAt,
            deadlineAtMs = startedAt + timeout,
            weaponAtMs = preset.weaponAtFraction ~= nil
                and (startedAt + math.floor(timeout * preset.weaponAtFraction)) or nil,
            weaponMoved = false,
            act = act ~= nil,
        }
    else
        Animations.active[shell] = nil
    end

    if preset.weaponAtFraction ~= nil and preset.weaponAtFraction <= 0 then
        local entry = Animations.active[shell]
        if entry ~= nil then entry.weaponMoved = true end
        setWeaponHeld(shell, true)
    end
    if preset.combat == true and preset.held == true then
        Animations.fallback[shell] = id
    end
    if preset.id ~= "hit_react" and preset.weaponAtFraction == nil
            and preset.preserveWeaponLocation ~= true then

        setWeaponHeld(shell, preset.combat == true
            or Animations.combatHold[shell] == true
            or Animations.readyCarry[shell] == true)
    end
    if preset.handsFree then Animations.presentIdleProp(shell, preset) end
    animationSerial(shell, true)
    sync(shell, id)
    return true
end

function Animations.isFishing(shell)
    local preset = byId[Animations.current[shell]]
    return preset ~= nil and preset.fishing == true
end

function Animations.fishCycle(shell, now)
    local fence = ProjectALife.AIFence
    if shell == nil or fence == nil or type(fence.drivesBody) ~= "function" or not fence.drivesBody(shell) then
        if shell ~= nil then Animations.fishing[shell] = nil end
        return false
    end
    local vars = type(SandboxVars) == "table" and SandboxVars.ALife or nil
    if type(vars) == "table" and vars.Idle_FishingAnim == false then
        if Animations.isFishing(shell) then Animations.clear(shell) end
        Animations.fishing[shell] = nil
        return false
    end
    now = tonumber(now) or nowMs()
    local data = metadata(shell) or {}
    local state = Animations.fishing[shell]
    if state ~= nil and (state.uid ~= data.ProjectALifeUID or state.generation ~= data.ProjectALifeGeneration
            or state.phase ~= Animations.current[shell] or now < state.startedMs) then
        state = nil
        Animations.fishing[shell] = nil
    end
    if state == nil and Animations.current[shell] ~= nil and not Animations.isFishing(shell) then return false end
    local phase, duration
    if state == nil then
        phase = "fish_cast"
        duration = 2400
    elseif now < state.untilMs then
        return Animations.apply(shell, state.phase)
    elseif state.phase == "fish_wait" then
        phase = "fish_pull"
        duration = 2400
    else
        phase = "fish_wait"
        duration = 20000 + ZombRand(40001)
    end
    if Animations.apply(shell, phase) ~= true then
        if Animations.isFishing(shell) then Animations.clear(shell) end
        Animations.fishing[shell] = nil
        return false
    end
    Animations.fishing[shell] = { phase = phase, startedMs = now, untilMs = now + duration,
        uid = data.ProjectALifeUID, generation = data.ProjectALifeGeneration }
    return true
end

function Animations.applyRemote(shell, id, serial)
    local numericSerial = tonumber(serial)
    local token = tostring(id) .. ":" .. tostring(numericSerial or "legacy")
    if Animations.remoteToken[shell] == token and (Animations.current[shell] == id
            or (id == "normal" and Animations.current[shell] == nil)) then
        local preset = byId[id]
        if preset ~= nil and preset.handsFree then Animations.presentIdleProp(shell, preset) end
        return true
    end
    local previous = Animations.suppressSync
    Animations.suppressSync = true
    local ok, result, reason = pcall(function()
        if id == "normal" then return Animations.clear(shell) end
        return Animations.apply(shell, id)
    end)
    Animations.suppressSync = previous
    if not ok then return false, tostring(result) end
    if result == true then
        Animations.remoteToken[shell] = token
        if numericSerial ~= nil then setAnimationSerial(shell, numericSerial) end
    end
    return result, reason
end

Animations.dressHoldMs = 4000

function Animations.cancelForCombat(shell)
    if Animations.blocksLocomotion(shell) then return false end
    local data = metadata(shell)
    local healing = data ~= nil and data.ProjectALifeHealDoneAtMs ~= nil
    if healing then

        data.ProjectALifeHealDoneAtMs, data.ProjectALifeHealToFraction = nil, nil
        data.ProjectALifeHandsBusyUntilMs = nil
        local at = type(getTimestampMs) == "function" and getTimestampMs() or 0
        data.ProjectALifeDressHoldUntilMs = at + (tonumber(Animations.dressHoldMs) or 4000)
    end
    local current = byId[Animations.current[shell]]
    if (current == nil or current.combat == true) and not healing then return false end
    return Animations.clear(shell)
end

function Animations.cancelForLocomotion(shell)
    if shell == nil then return false end
    if Animations.blocksLocomotion(shell) then return false end
    local current = byId[Animations.current[shell]]

    if current ~= nil and current.id == "surrender" then return false end

    return Animations.clear(shell)
end

function Animations.reassertProp(shell, prop)
    if not Animations.propInHand(shell, prop) then
        if prop.location ~= nil then
            Animations.attachProp(shell, prop)
        else
            Animations.holdProp(shell, prop.item, prop.hand or "secondary")
        end
        shell:resetModelNextFrame()
    end
end

function Animations.tick(budget)

    local processed, now = 0, nowMs()

    for shell, id in pairs(Animations.actSet) do
        if Animations.current[shell] ~= id then
            Animations.stopAct(shell)
            Animations.metrics.actOrphans = Animations.metrics.actOrphans + 1
        end
    end
    for shell, entry in pairs(Animations.active) do
        processed = processed + 1
        local identity = metadata(shell) or {}
        if entry.uid ~= nil and (entry.uid ~= identity.ProjectALifeUID
                or entry.generation ~= identity.ProjectALifeGeneration) then

            Animations.active[shell], Animations.current[shell], Animations.fallback[shell] = nil, nil, nil
            Animations.weaponVisuals[shell], Animations.idleProps[shell] = nil, nil
            Animations.combatHold[shell], Animations.readyCarry[shell], Animations.ownerPose[shell] = nil, nil, nil
            Animations.serial[shell], Animations.remoteToken[shell] = nil, nil
            if Animations.actSet[shell] ~= nil then Animations.stopAct(shell) end
        else

        local prop = Animations.idleProps[shell]
        if prop ~= nil and prop.id == entry.id and prop.item ~= nil then
            pcall(Animations.reassertProp, shell, prop)
        end

        local doneVariable = "BumpAnimFinished"
        if entry.act == true then doneVariable = "ALifeActDone" end
        local finished = string.lower(tostring(
            getVariable(shell, doneVariable) or "")) == "true"
        if finished and entry.startedAtMs ~= nil
                and now - entry.startedAtMs < Animations.oneShotMinimumMs then
            finished = false
        end
        local movingOk, moving = pcall(shell.isMoving, shell)
        local preset = byId[entry.id]

        if entry.weaponAtMs ~= nil and entry.weaponMoved ~= true
                and (now >= entry.weaponAtMs or finished) then
            entry.weaponMoved = true
            setWeaponHeld(shell, true)
            sync(shell, entry.id)
        end

        local interrupted = movingOk and moving == true
            and not (preset ~= nil and (preset.combat == true
                or preset.id == "get_up_front" or preset.id == "get_up_back"))
        local fence = ProjectALife.AIFence
        local remoteLoop = preset ~= nil and preset.looped == true and Animations.remoteToken[shell] ~= nil
            and fence ~= nil and type(fence.drivesBody) == "function" and not fence.drivesBody(shell)
        if not remoteLoop and ((finished and not (preset and preset.looped)) or interrupted or now >= entry.deadlineAtMs) then
            local fallbackId = Animations.fallback[shell]

            if preset ~= nil and preset.preserveWeaponLocation == true
                    and preset.combat == true then

                recoverPosture(shell, false)
                Animations.active[shell] = nil
                Animations.current[shell] = nil
                animationSerial(shell, true)
                sync(shell, "normal")
            elseif fallbackId ~= nil and byId[fallbackId] ~= nil then
                Animations.active[shell] = nil

                if Animations.apply(shell, fallbackId) ~= true then Animations.clear(shell) end
            else
                Animations.clear(shell)
            end
        end
        end
    end
    return processed
end

Animations.installFishingVisualHooks()
Animations.registerPropLocations()

return Animations
