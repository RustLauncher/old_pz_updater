--[[ Trains -- every constant. Start here.

    "Whoops, somebody left all the trains running."

    DESIGN.md says what each of these is for; the section is named beside
    the ones a decision hangs on. Lengths are in tiles, speeds in tiles a
    second, times in seconds unless a name ends in Ms.
]]

TRN = TRN or {}

local C = {}
TRN.Config = C

C.Version   = "0.30.0"        -- the same number as modversion in mod.info
C.ModPrefix = "[TRN]"
C.NetModule = "TRN"
C.StateKey  = "TRN_State"    -- the authority's saved state (global mod data)
C.Debug     = false

-- The dev build: the test line, the clock skip, and in single player an
-- admin's menu without -debug. A server refuses every dev command with this
-- off. **Off in the source and in a release.** It is on only where TRN.Dev
-- is set, which only tools/deploy_windows.py does, by writing
-- shared/TRN/TRN_Dev.lua into the installed TrainsDev copy: the source tree
-- and the Workshop package never have that file (pz_sewars, SEW_Dev.lua).
-- That file sets this as well, for when it is read after this one is.
C.DevTools  = TRN.Dev == true

---------------------------------------------------------------------------
-- The beat (DESIGN.md 3.2) and the speed ceiling (DESIGN.md 6)
---------------------------------------------------------------------------
-- The fastest a train ever goes, at the top of its ease. The speed
-- anti-cheat strikes a character over 20 tiles a second, and a rider on a
-- deck moves at the train's speed plus their own walking along it.
C.TopSpeed  = 8             -- the default; sandbox Trains.TopSpeed replaces it
C.TopFloor  = 1             -- and what the sandbox may not go under or over
C.TopCeil   = 40            -- as fast as the sandbox may ask for. Past about 11 a rider running forward on a roof
                            -- is over the anti-cheat's 20, which the mod sets to log (sandbox SpeedCheck)
C.Dwell     = 120           -- parked at a stop; sandbox Trains.Dwell replaces it
C.MinMove   = 15            -- no leg is run in less than this, however short
-- An eased leg (smoothstep) peaks at this many times its mean speed.
C.EasePeak  = 1.5

---------------------------------------------------------------------------
-- The clock (DESIGN.md 3.1, Q1)
---------------------------------------------------------------------------
-- The trains' clock is the world's own, in seconds of play at normal
-- speed, counted by the authority a tick at a time. So fast-forward and
-- sleep carry a train with them, a pause stops it, and a save keeps it.
C.TickCapMs   = 250         -- the most of one tick's real time that counts: a hitch is not a jump
C.FastMost    = 400         -- and the most the world may be running faster than normal: past that it was set by hand
C.SyncEvery   = 2.0         -- a server tells its clients the time this often
C.SyncBlend   = 0.2         -- how much of a correction a client takes at once
C.SyncSnap    = 1.0         -- a correction bigger than this is taken whole
C.RenderLead  = 0.1         -- the most a frame may run ahead of the last tick

---------------------------------------------------------------------------
-- The cars (DESIGN.md 3.3)
---------------------------------------------------------------------------
-- Each kind of car is a model (media/scripts/trn_models.txt,
-- tools/gen_train_models.py), and says what a rider can do with it:
--
--   inside   the style of its room (C.Rooms.styles), or nil for a car there
--            is no way into: a tank, a flatcar
--   top      how high its top is, in levels: what a rider who climbs onto
--            it stands on. Under one level on purpose: a rider up there is
--            still on the ground's own level to the engine, on a square
--            that exists, and is only drawn higher (TRN_Deck)
--   topLen, topWid   half the size of what there is to stand on up there
--
-- Every car is the same length and width outside: twelve squares long and
-- three across. A model's front is its +x.
-- DESIGN.md 12 is the whole list of kinds; these are the ones built.
C.CarLen    = 12.0
C.HalfWidth = 1.5           -- half a car's width, outside: three squares. Its room is wider (C.Rooms.wid):
                            -- the outside and the inside need not agree (the author, 2026-10-08)
C.Gap       = 2.0           -- between the ends of two coupled cars
C.Cars = {
    -- `model` is what a car of this kind wears where nothing says otherwise (the test train);
    -- `skins` is every outside it may wear, and each car of a train of the map's is given one of
    -- them by the world's seed (TRN_Time.roll, TRN_Body.modelOf). All of them are the kit's
    -- (tools/gen_train_kit.py, DESIGN.md 12): built in code, in vanilla's own pixels.
    -- topWid is half of what there is to stand on.
    loco = { model = "TrnLocoGreen", len = 12.0, plow = true, inside = "loco", top = 0.92, topLen = 5.4, topWid = 0.9,
        skins = { "TrnLocoGreen", "TrnLocoBlue", "TrnLocoBlack" } },
    coach = { model = "TrnCoachWorn", len = 12.0, inside = "coach", top = 0.92, topLen = 5.6, topWid = 0.9,
        skins = { "TrnCoachWorn", "TrnCoachGreen" } },
    commuter = { model = "TrnCoachNew", len = 12.0, inside = "commuter", top = 0.92, topLen = 5.6, topWid = 0.9,
        skins = { "TrnCoachNew" } },
    sleeper = { model = "TrnCoachWorn", len = 12.0, inside = "sleeper", top = 0.92, topLen = 5.6, topWid = 0.9,
        skins = { "TrnCoachWorn", "TrnCoachGreen", "TrnCoachNew" } },
    galley = { model = "TrnCoachWorn", len = 12.0, inside = "galley", top = 0.92, topLen = 5.6, topWid = 0.9,
        skins = { "TrnCoachWorn", "TrnCoachGreen", "TrnCoachNew" } },
    hospital = { model = "TrnCoachMed", len = 12.0, inside = "hospital", top = 0.92, topLen = 5.6, topWid = 0.9,
        skins = { "TrnCoachMed" } },
    parlor = { model = "TrnCoachRed", len = 12.0, inside = "parlor", top = 0.92, topLen = 5.6, topWid = 0.9,
        skins = { "TrnCoachRed" } },
    private = { model = "TrnCoachRed", len = 12.0, inside = "private", top = 0.92, topLen = 5.6, topWid = 0.9,
        skins = { "TrnCoachRed" } },
    survivor = { model = "TrnBoxcarRed", len = 12.0, inside = "survivor", top = 0.92, topLen = 5.6, topWid = 0.9,
        skins = { "TrnBoxcarRed", "TrnBoxcarRedTag", "TrnBoxcarBrown", "TrnBoxcarBrownTag", "TrnBoxcarBlue", "TrnBoxcarBlueTag", "TrnBoxcarYellow", "TrnBoxcarYellowTag" } },
    box = { model = "TrnBoxcarRed", len = 12.0, inside = "box", top = 0.92, topLen = 5.6, topWid = 0.9,
        skins = { "TrnBoxcarRed", "TrnBoxcarRedTag", "TrnBoxcarBrown", "TrnBoxcarBrownTag", "TrnBoxcarBlue", "TrnBoxcarBlueTag", "TrnBoxcarYellow", "TrnBoxcarYellowTag" } },
    warehouse = { model = "TrnBoxcarRed", len = 12.0, inside = "warehouse", top = 0.92, topLen = 5.6, topWid = 0.9,
        skins = { "TrnBoxcarRed", "TrnBoxcarRedTag", "TrnBoxcarBrown", "TrnBoxcarBrownTag", "TrnBoxcarBlue", "TrnBoxcarBlueTag", "TrnBoxcarYellow", "TrnBoxcarYellowTag" } },
    dining = { model = "TrnCoachRed", len = 12.0, inside = "dining", top = 0.92, topLen = 5.6, topWid = 0.9,
        skins = { "TrnCoachRed" } },
    lounge = { model = "TrnCoachRed", len = 12.0, inside = "lounge", top = 0.92, topLen = 5.6, topWid = 0.9,
        skins = { "TrnCoachRed" } },
    dorm = { model = "TrnCoachWorn", len = 12.0, inside = "dorm", top = 0.92, topLen = 5.6, topWid = 0.9,
        skins = { "TrnCoachWorn", "TrnCoachGreen", "TrnCoachNew" } },
    workshop = { model = "TrnBoxcarRed", len = 12.0, inside = "workshop", top = 0.92, topLen = 5.6, topWid = 0.9,
        skins = { "TrnBoxcarRed", "TrnBoxcarRedTag", "TrnBoxcarBrown", "TrnBoxcarBrownTag", "TrnBoxcarBlue", "TrnBoxcarBlueTag", "TrnBoxcarYellow", "TrnBoxcarYellowTag" } },
    armory = { model = "TrnBoxcarRed", len = 12.0, inside = "armory", top = 0.92, topLen = 5.6, topWid = 0.9,
        skins = { "TrnBoxcarRed", "TrnBoxcarRedTag", "TrnBoxcarBrown", "TrnBoxcarBrownTag", "TrnBoxcarBlue", "TrnBoxcarBlueTag", "TrnBoxcarYellow", "TrnBoxcarYellowTag" } },
    baggage = { model = "TrnBoxcarRed", len = 12.0, inside = "baggage", top = 0.92, topLen = 5.6, topWid = 0.9,
        skins = { "TrnBoxcarRed", "TrnBoxcarRedTag", "TrnBoxcarBrown", "TrnBoxcarBrownTag", "TrnBoxcarBlue", "TrnBoxcarBlueTag", "TrnBoxcarYellow", "TrnBoxcarYellowTag" } },
    mail = { model = "TrnCoachWorn", len = 12.0, inside = "mail", top = 0.92, topLen = 5.6, topWid = 0.9,
        skins = { "TrnCoachWorn", "TrnCoachGreen", "TrnCoachNew" } },
    caboose = { model = "TrnCaboose", len = 12.0, inside = "caboose", top = 0.92, topLen = 4.4, topWid = 0.9,
        skins = { "TrnCaboose" } },
    reefer = { model = "TrnBoxcarWhite", len = 12.0, inside = "reefer", top = 0.92, topLen = 5.6, topWid = 0.9,
        skins = { "TrnBoxcarWhite" } },
    greenhouse = { model = "TrnCoachWorn", len = 12.0, inside = "greenhouse", top = 0.92, topLen = 5.6, topWid = 0.9,
        skins = { "TrnCoachWorn", "TrnCoachGreen", "TrnCoachNew" } },
    generator = { model = "TrnBoxcarRed", len = 12.0, inside = "generator", top = 0.92, topLen = 5.6, topWid = 0.9,
        skins = { "TrnBoxcarRed", "TrnBoxcarRedTag", "TrnBoxcarBrown", "TrnBoxcarBrownTag", "TrnBoxcarBlue", "TrnBoxcarBlueTag", "TrnBoxcarYellow", "TrnBoxcarYellowTag" } },
    livestock = { model = "TrnBoxcarRed", len = 12.0, inside = "livestock", top = 0.92, topLen = 5.6, topWid = 0.9,
        skins = { "TrnBoxcarRed", "TrnBoxcarRedTag", "TrnBoxcarBrown", "TrnBoxcarBrownTag", "TrnBoxcarBlue", "TrnBoxcarBlueTag", "TrnBoxcarYellow", "TrnBoxcarYellowTag" } },
    library = { model = "TrnCoachWorn", len = 12.0, inside = "library", top = 0.92, topLen = 5.6, topWid = 0.9,
        skins = { "TrnCoachWorn", "TrnCoachGreen", "TrnCoachNew" } },
    chapel = { model = "TrnCoachWorn", len = 12.0, inside = "chapel", top = 0.92, topLen = 5.6, topWid = 0.9,
        skins = { "TrnCoachWorn", "TrnCoachGreen", "TrnCoachNew" } },
    observation = { model = "TrnCoachRed", len = 12.0, inside = "observation", top = 0.92, topLen = 5.6, topWid = 0.9,
        skins = { "TrnCoachRed" } },
    tank = { model = "TrnTankBlack", len = 12.0, top = 0.92, topLen = 4.4, topWid = 0.6,
        skins = { "TrnTankBlack", "TrnTankWhite", "TrnTankRust" } },
    flat = { model = "TrnFlatcar", len = 12.0, top = 0.24, topLen = 5.7, topWid = 1.3,
        skins = { "TrnFlatcar" } },
    -- Vanilla's own open car, the green one that stands on the map's sidings as tiles, made a
    -- model (the author, 2026-10-10: "we would need to hop over the wall and be inside it"). Its
    -- top is its floor, inside its walls: a rider climbs in over the end.
    gondola = { model = "TrnGondolaGreen", len = 12.0, top = 0.24, topLen = 5.6, topWid = 1.15,
        skins = { "TrnGondolaGreen", "TrnGondolaRust" } },
}
C.DeckModel = "TrnDeck"     -- the platform between two cars
C.Carrier   = "Base.Bobber" -- the item handed to Render3DItem; never put anywhere

-- What a train is made of, front first. On a line the train never turns
-- round, so it has a plow at each end: the last car is a locomotive facing
-- backwards. A car's number is its place in this list, and is painted on it
-- (C.Numbers): the menus name cars by it, because which way is "ahead"
-- inside a room is not which way the train is going.
C.Consists = {
    -- Every car there is, for looking at: what the dev menu lays. The
    -- outsides are mostly the same model for now, so the numbers are how
    -- to tell them apart (DESIGN.md 12).
    all = { { kind = "loco" }, { kind = "coach" }, { kind = "commuter" }, { kind = "sleeper" }, { kind = "galley" },
            { kind = "hospital" }, { kind = "parlor" }, { kind = "private" }, { kind = "survivor" },
            { kind = "warehouse" }, { kind = "dining" }, { kind = "lounge" }, { kind = "dorm" }, { kind = "workshop" },
            { kind = "armory" }, { kind = "baggage" }, { kind = "mail" }, { kind = "caboose" }, { kind = "reefer" },
            { kind = "greenhouse" }, { kind = "generator" }, { kind = "livestock" }, { kind = "library" },
            { kind = "chapel" }, { kind = "observation" }, { kind = "box" }, { kind = "tank" }, { kind = "flat" },
            { kind = "gondola" }, { kind = "loco", flip = true } },
    dev = { { kind = "loco" }, { kind = "coach" }, { kind = "hospital" }, { kind = "tank" }, { kind = "flat" },
            { kind = "loco", flip = true } },
}

--- Whose a train is (DESIGN.md 5.8; TRN_Claims): how many trains a player
--- may own as the mod comes, and the most a host may allow.
C.Claims = {
    each  = 1,
    limit = 40,
}

--- The sidings: new track round the cars vanilla stands on its own
--- (DESIGN.md 4.3). Where they are is TRN_Sidings.lua, generated; this is
--- how the server lays them (TRN_Track.lua).
C.Track = {
    rev     = 1,            -- raise this to have every siding laid again: nothing is laid twice on one square
    z       = 0,
    every   = 20,           -- ticks between passes
    stretch = 16,           -- rows of a siding laid in one pass
    near    = 70,           -- squares: a siding is looked at when somebody is this near any of it. (A train is drawn at 90.)
}

--- A host's own lines (SERVERS.md): laid by an admin in the game, saved
--- with the world. A train of one is numbered after the map's and has a
--- cell of rooms as any train has (C.Rooms.trains is how many there are).
C.Lines = {
    most     = 12,          -- lines a world may have
    points   = 60,          -- points a line may have, as an admin lays it
    apart    = 12,          -- squares: two points of a line are no nearer than this: a car is twelve long
    legLeast = 40,          -- squares: nor two of its stops
    bend     = 14,          -- squares: the radius its corners are rounded to, as the map's are (tools/gen_rails.py BEND)
    nameMost = 28,          -- letters in a line's name, or a stop's
    reach    = 20,          -- squares: an admin this near a line of the host's is offered to take it up
}

-- A stop out on the line (DESIGN.md 4.1b; the author, 2026-10-09): pulled
-- from aboard, or asked for from beside the track. The train comes to a
-- stand, waits, and makes the time up before the next station, so that it
-- is there when it always would have been.
C.Stop = {
    brake   = 8,            -- seconds from the cord being pulled to standing
    hold    = 45,           -- seconds it stands
    fastest = 12,           -- the most it may go making the time up: with a rider's own running, under the anti-cheat's 20
    reach   = 14,           -- how near the track somebody must be to flag a train down
    clear   = 0.04,         -- no nearer a station than this part of the leg: wait for it there
}

-- What each train of the map's routes is called, in the order the routes
-- list their trains: the circle's nineteen, then the Louisville line's two
-- (the author, 2026-10-09: "Adirondack, Plattsburgh, Peru, Keeseville,
-- Ellenburg, Ausable. Then the remaining will be the names of adirondack 46
-- mountains": the fifteen here are the highest of the forty-six but one; and
-- Whiteface goes by its local name, Iceface, "since others might not realize
-- it's a mountain").
-- **A train keeps its name in every world**, as it keeps its number: it is
-- how somebody who made a home in one finds it again. Never reordered.
C.Names = { "Adirondack", "Plattsburgh", "Peru", "Keeseville", "Ellenburg", "Ausable",
            "Marcy", "Algonquin", "Haystack", "Skylight", "Iceface", "Dix", "Gray", "Iroquois", "Basin",
            "Gothics", "Colden", "Giant", "Santanoni", "Redfield", "Wright" }

-- Inside every car (the author, 2026-10-09): its number over its front door, and on the north
-- wall a sign of the time, as a station had in 1993: the world's clock, and under it how long,
-- by that clock, to the next stop, or to leaving this one. Drawn by each client for whoever is
-- in the car (TRN_Body, B.inside): the box is a model and so is every figure on it.
C.Signs = {
    plate   = "TrnNumIn",   -- .. the car's number
    plateUp = 0.86,         -- levels up the west wall, over the door
    out     = 0.07,         -- how far off a wall a thing hangs
    arr     = "TrnSignArr", -- the sign while the train is running: "NEXT STOP"
    dep     = "TrnSignDep", -- and while it stands: "DEPARTS"
    led     = "TrnLed",     -- .. a figure, or C for the colon
    dx      = 4.5,          -- along the north wall from the front: the bare square beside the speaker
    up      = 0.80,         -- levels up it, over the windows and the tallest shelf
    row     = 0.047,        -- each row of figures is this many levels above or below the sign's middle
    first   = -0.07,        -- where the first figure is, along the sign from its middle
    pitch   = 0.16,         -- and from one figure to the next
}

-- The trains on the game's map, and the map from aboard (TRN_Map).
C.Map = {
    see     = 70,           -- squares each side of the track a rider's map comes to know: what is seen from a train
    step    = 60,           -- and how far apart along the track it is made known
    everyMs = 1000,         -- how often
    mark    = 5,            -- half the size of a train's mark on the map, in pixels
    names   = 13.5,         -- the map's zoom from which each train's stop is written beside it
    zoom    = 15.0,         -- the zoom the map opens at from inside a car
    afoot   = 400,          -- within this of a stop, somebody is told when her own train is next due there
}

-- A rider's plans (TRN_Trip; the author, 2026-10-09): the stop she has said she gets off at,
-- and the train she is waiting for. Seconds are the trains' clock's.
C.Trip = {
    soon    = 60,           -- this long before her stop, or her train: she is woken, and a game run fast is set to normal
    alerts  = { 600, 300, 120, 60, 20 },    -- waiting: she is told when her train is this far off
    askMs   = 1500,         -- getting off: the server is not asked again in this long
    tries   = 3,            -- nor more often than this at one stop: a refusal (no room to step down) is said each time
    everyMs = 250,          -- how often a wait is looked at
    beside  = 6.0,          -- "it is here": this near the side of the standing train
    sound   = "UIActivateMainMenuItem",     -- vanilla's own, played as its own menus play it
}

-- The trains of the map's own routes (TRN_Routes.lua, DESIGN.md 4.1) run
-- whenever no test line is laid: a test line is a train on its own, and the
-- beat is one beat, so the two are never run together.
C.Network = true

-- What a train of the routes is made of (the author, 2026-10-09: "each
-- train always has the galley, the med car, the rich person's apartment, a
-- few passenger cars of varying quality randomly. Then the random others.
-- Trains can be many cars long, as much as we can handle"). Rolled once
-- for each world from its seed, the same on every machine (TRN_Time.roll):
-- a locomotive; every one of `always`; `seats.count` passenger cars, each
-- any of `seats.kinds`, and the same kind may come twice; `extra` more from
-- `pool`, no kind twice; all of it shuffled; and a locomotive facing back.
-- So a train is 13 to 23 cars, and its empties: 15 to 25 as the mod comes.
-- Thirty is the most there are rooms and number plates for (C.Rooms.rows,
-- C.Numbers.most).
C.Roll = {
    always = { "galley", "hospital", "private" },
    seats  = { kinds = { "coach", "commuter", "parlor" }, count = { 2, 4 } },
    pool   = { "sleeper", "dorm", "survivor", "warehouse", "reefer", "dining", "lounge", "workshop", "armory",
               "baggage", "mail", "caboose", "greenhouse", "generator", "livestock", "library", "chapel",
               "observation", "box", "tank", "flat", "gondola" },
    extra  = { 6, 14 },
    -- And empty boxcars to build in, as well as whatever the dice gave (the author, 2026-10-11:
    -- "there should be more default empty buildable cars"): this many, of `empty`, coupled on behind
    -- everything else and before the rear locomotive. The sandbox's Empties replaces the number.
    -- **They are added without moving anything**: a car's room is found by its `slot`, which is its
    -- place in the train unless it says otherwise, and the rear locomotive keeps the slot it had
    -- before there were any (TRN_Time.roll). So a world from before 0.29.0 keeps every room it has.
    empties = 2,
    emptiesMost = 6,
    empty  = "box",
    -- How many passenger cars and how many of the rest, by the sandbox's Length: 1 is what a train
    -- has always been, 13 to 23 cars; 2 is 8 to 12; 3 is 7 or 8. (And for a train of exactly
    -- these cars and no others, the sandbox's Consist.)
    carsAsBuilt = "1|",     -- TRN_Setup.cars() for a world that has never had the setting: long trains, rolled
    lengths = {
        { seats = { 2, 4 }, extra = { 6, 14 } },
        { seats = { 1, 2 }, extra = { 2, 5 } },
        { seats = { 1, 1 }, extra = { 1, 2 } },
    },
}

-- What a car is, on both its sides (the author, 2026-10-10: "mark the
-- crucial cars on both sides with some custom art so we can see the galley
-- and med car and housing cars"): an enamelled plate with a pictogram and a
-- word, low and to the left of the car's middle as somebody facing that side
-- sees it. A model of its own, so it is on whatever outside the car wears
-- (tools/gen_train_models.py PLATES: every kind with an inside has one). The
-- cars somebody lives by have theirs in solid colour.
C.Plates = {
    galley = "TrnPlateGalley", hospital = "TrnPlateHospital", private = "TrnPlatePrivate",
    sleeper = "TrnPlateSleeper", dorm = "TrnPlateDorm", survivor = "TrnPlateSurvivor",
    caboose = "TrnPlateCaboose", dining = "TrnPlateDining", lounge = "TrnPlateLounge",
    reefer = "TrnPlateReefer", greenhouse = "TrnPlateGreenhouse", livestock = "TrnPlateLivestock",
    coach = "TrnPlateCoach", commuter = "TrnPlateCommuter", parlor = "TrnPlateParlor",
    observation = "TrnPlateObservation", warehouse = "TrnPlateWarehouse", baggage = "TrnPlateBaggage",
    box = "TrnPlateBox", mail = "TrnPlateMail", library = "TrnPlateLibrary", chapel = "TrnPlateChapel",
    workshop = "TrnPlateWorkshop", generator = "TrnPlateGenerator", armory = "TrnPlateArmory",
}

-- A car's number, drawn on its top and on both its sides: a model for each
-- digit (tools/gen_train_models.py). `mirror` picks the set drawn the other
-- way round: the engine's view of an item's model is said to be mirrored
-- (pz-heros POWERS.md 3.5), and a digit is the first thing here that would
-- show it. If the numbers read backwards in the game, change it.
--
-- PLAYED 2026-10-08: the first plates were one big one in the middle of the
-- top and one on each side, and the author drew where they belong: small,
-- at each end of the top and on each end of the car, over its door.
C.Numbers = {
    top    = "TrnNumTop",   -- .. digit: lying on the car's top, one at each end of it
    ends   = "TrnNumEnd",   -- .. digit: on both the car's ends
    most   = 30,            -- the highest number there is a plate for (tools/gen_train_models.py NUMBERS)
    mirror = false,
    lift   = 0.02,          -- levels above the top, so it is not fought for depth
    fromEnd = 0.9,          -- how far in from each end a top's plate lies
    drop   = 0.17,          -- levels below the top an end's plate is
}

-- Where to click, shown in green to whoever can use it (the author,
-- 2026-10-08): round the door of each car a rider on a platform can go
-- into, on the top of each she can climb onto, on the platforms a rider on
-- a top can climb down to, and on the platform somebody beside a parked
-- train would board. Drawn for that player only, by their own machine.
C.Marks = {
    -- PLAYED 2026-10-08: they were drawn all the time, and the author asked
    -- for them only when the player is a tile from the thing, or less.
    near  = 1.75,           -- how far from a door, a ladder or a platform's edge its mark is shown
    door  = "TrnMarkDoor",  -- a frame round a car's end door
    flat  = "TrnMarkFlat",  -- a frame lying on a top or a platform
    lift  = 0.04,           -- levels above what it lies on
    fromEnd = 0.9,          -- how far in from a top's end it lies: where a climber lands
}

-- How a model's turn is worked out from the way the track runs. READ, not
-- played: a model's x is the world's x and its z is the world's y the other
-- way round (pz-heros tools/gen_snow.py), and the turn handed to
-- Render3DItem is about the model's upright, in degrees
-- (ItemModelRenderer$WorldModelCamera.Begin). If the cars are drawn across
-- the track or back to front, these two are what to change.
C.YawSign   = 1
C.YawOffset = 0

C.DrawRange = 90            -- cars further than this from the player are not drawn
-- A car is a rigid thing on two trucks, this far each side of its middle as
-- a part of its length: it lies along the line between them, so on a bend it
-- turns smoothly and cuts the corner a little, as a real one does.
C.Trucks    = 0.36

---------------------------------------------------------------------------
-- The decks (DESIGN.md 3.5)
---------------------------------------------------------------------------
C.Deck = {
    halfLen   = 0.75,       -- how far a rider may stand from the middle, along the train
    halfWid   = 1.20,       -- and across it
    walk      = 7.0,        -- the most a rider's own running adds to the train's speed (DESIGN.md 6)
    reach     = 3.0,        -- how near the side of a train a player must be to board
    offside   = 2.7,        -- getting off: this far from the middle of the track
    -- A runner this far past the end of what she stands on goes on to the next thing. Next to nothing, on
    -- purpose: it is one frame's step, which at a high frame rate is a hundredth of a square.
    runPast   = 0.002,
    runAskMs  = 400,        -- and does not ask the server again in this long
}

---------------------------------------------------------------------------
-- The insides of the cars (DESIGN.md 3.4, 5.2)
---------------------------------------------------------------------------
-- Rooms in a cell off the edge of the map, one a car. The vanilla map ends
-- at cell x 77; the RV interior mod is at 85,40, the TARDIS mod runs east
-- from 92,40 and the Shuttlecraft has 94..103 by 38..41. tools/gen_void_map.py
-- maps this cell and the ring round it as empty, so nothing grows there, and
-- reads the cell from here.
C.Rooms = {
    cell     = { x = 97, y = 20 },
    -- A host may put them elsewhere (sandbox RoomsX, RoomsY), anywhere off the game's map
    -- and a generated one's, which end at cells 77 and 79.
    cellLeast = { x = 82, y = 0 },
    cellMost  = { x = 300, y = 300 },
    -- Each train has a cell of its own, east of the last: the test line's
    -- train the first, then the routes' in the order they are listed. As
    -- many cells as this are mapped empty (tools/gen_void_map.py).
    --
    -- **Row 20, and why** (DEV_GUIDE.md, *Two maps on one cell stop the
    -- world loading*). The rooms were in row 46 until 0.28.0. The
    -- Shuttlecraft's map grew south over them (its cells are x 94 to 103,
    -- y 38 to 48 since its 1.21.0) and a world made with both would not
    -- load. Every interior mod there is sits round row 40: the Shuttlecraft,
    -- the Fifth-Wheel RV at 83 to 87 by 38 to 42, the TARDIS east from
    -- 92,40. Row 20 is sixteen cells north of all of them, and east of the
    -- game's own map (which ends at x 77) and of a generated one (79).
    -- tests/test_assets.py holds these cells two clear of every one of
    -- those, and of every map installed on the machine it is run on.
    trains   = 40,
    cellSize = 256,
    offset   = 32,          -- from the cell's corner to the first room's
    pitch    = 40,          -- from one room to the next, along and down
    len      = 12,          -- a room is this long, front to rear
    wid      = 5,           -- and this wide: an aisle, and two squares either side of it
    geom     = 16,           -- raise this when rooms move, or are refurnished: a world's old ones are swept away
    z        = 0,
    rev      = 6,           -- raise this when what is built changes: rooms are mended, not refurnished
    tidyRev  = 3,           -- a room raised before this revision has what the engine grew taken off it once more
    tag      = "TRN",       -- the mod data key on everything the builder places
    -- The hull is vanilla's: its walls have the collision and the depth a
    -- tile of ours cannot (tools/gen_train_tiles.py), and its invisible
    -- floor is the roof. What a car looks like is ours, laid over them.
    wallW    = "industry_01_0",
    wallN    = "industry_01_1",
    perRow   = 6,           -- rooms in a row
    rows     = 5,           -- rows a train has: thirty cars at most
    roof     = "invisible_01_0",
    -- A wall inside a room, with a doorway in it: vanilla's, as the hull's are.
    -- Running water and power (the author, 2026-10-08: "the sink empties - we
    -- should make them self-refilling like the shuttle craft"). What holds
    -- water in a car somebody is in is kept full, and a car with a `power`
    -- square has a generator nobody sees one level under it, kept fuelled
    -- and running (pz_trekship ADIRONDACK.md 9: under, because a generator
    -- in a room of ours would poison it).
    -- What a car's cupboards hold when its room is first raised (the author,
    -- 2026-10-08: "make sure it's loaded up with food"). A fitting names a
    -- list; each entry is an item and how many. Put in once, with the
    -- fitting, and never again.
    stock = {
        dry    = { { "Base.Rice", 3 }, { "Base.Pasta", 3 }, { "Base.Flour2", 2 }, { "Base.Sugar", 2 }, { "Base.Salt", 2 },
                   { "Base.Pepper", 2 }, { "Base.OilVegetable", 2 }, { "Base.Coffee2", 3 }, { "Base.Teabag2", 3 },
                   { "Base.Oatmeal", 2 }, { "Base.Cereal", 2 }, { "Base.Crackers", 4 }, { "Base.DriedBlackBeans", 2 },
                   { "Base.Yeast", 2 }, { "Base.Honey", 1 }, { "Base.PeanutButter", 2 }, { "Base.JamFruit", 2 } },
        cans   = { { "Base.TinnedBeans", 6 }, { "Base.CannedCorn", 4 }, { "Base.CannedChili", 4 }, { "Base.CannedTomato", 4 },
                   { "Base.CannedPeas", 4 }, { "Base.CannedCarrots", 4 }, { "Base.CannedPotato", 4 },
                   { "Base.CannedBolognese", 4 }, { "Base.TunaTin", 4 }, { "Base.CannedSardines", 3 },
                   { "Base.CannedFruitCocktail", 3 }, { "Base.CannedPeaches", 3 }, { "Base.CannedMilk", 3 },
                   { "Base.Macandcheese", 3 } },
        cold   = { { "Base.Steak", 4 }, { "Base.Chicken", 3 }, { "Base.PorkChop", 3 }, { "Base.Bacon", 3 }, { "Base.Sausage", 4 },
                   { "Base.Ham", 2 }, { "Base.EggCarton", 2 }, { "Base.Milk", 2 }, { "Base.Butter", 2 }, { "Base.Cheese", 3 },
                   { "Base.Lettuce", 2 }, { "Base.Tomato", 4 } },
        wares  = { { "Base.Plate", 8 }, { "Base.Bowl", 8 }, { "Base.Fork", 8 }, { "Base.Spoon", 8 }, { "Base.MugWhite", 6 },
                   { "Base.GlassTumbler", 6 }, { "Base.DishCloth", 3 } },
        pots   = { { "Base.Pot", 2 }, { "Base.Saucepan", 2 }, { "Base.Pan", 2 }, { "Base.RoastingPan", 1 },
                   { "Base.BakingPan", 1 }, { "Base.Kettle", 1 } },
        tools  = { { "Base.KitchenKnife", 2 }, { "Base.Spatula", 2 }, { "Base.Ladle", 2 }, { "Base.TinOpener", 2 },
                   { "Base.Matches", 2 }, { "Base.Lighter", 1 }, { "Base.Potato", 6 }, { "Base.Onion", 4 },
                   { "Base.Carrots", 4 }, { "Base.Cabbage", 2 }, { "Base.Bread", 2 } },
        -- the parlor
        parlor  = { { "Base.Book", 4 }, { "Base.Magazine", 4 }, { "Base.Newspaper", 3 }, { "Base.CardDeck", 2 }, { "Base.Dice", 2 },
                    { "Base.Cigar", 6 }, { "Base.Cigarillo", 4 }, { "Base.CigarettePack", 3 }, { "Base.Lighter", 2 },
                    { "Base.Chocolate", 4 }, { "Base.Candle", 4 } },
        liquor  = { { "Base.Whiskey", 2 }, { "Base.Scotch", 2 }, { "Base.Brandy", 2 }, { "Base.Gin", 1 }, { "Base.Vodka", 1 },
                    { "Base.Rum", 1 }, { "Base.Port", 1 }, { "Base.Sherry", 1 }, { "Base.Champagne", 2 }, { "Base.Wine", 2 },
                    { "Base.Wine2", 2 } },
        glasses = { { "Base.GlassTumbler", 6 }, { "Base.GlassWine", 6 }, { "Base.BeerBottle", 6 } },
        -- the private car
        study   = { { "Base.Book", 6 }, { "Base.Magazine", 3 }, { "Base.Newspaper", 2 }, { "Base.Journal", 2 }, { "Base.Notebook", 2 },
                    { "Base.Pen", 3 }, { "Base.Pencil", 2 }, { "Base.Map", 1 }, { "Base.LouisvilleMap1", 1 }, { "Base.ChessWhite", 1 },
                    { "Base.Photo", 2 } },
        finery  = { { "Base.Sheet", 4 }, { "Base.Pillow", 4 }, { "Base.BathTowel", 4 }, { "Base.Soap2", 3 }, { "Base.Comb", 1 },
                    { "Base.Mirror", 1 }, { "Base.Toothbrush", 2 }, { "Base.Toothpaste", 2 }, { "Base.Shoes_BlackBoots", 2 },
                    { "Base.Gloves_LeatherGloves", 2 }, { "Base.Jacket_Padded", 1 }, { "Base.Bag_DuffelBag", 1 } },
        -- the lived-in boxcar
        larder  = { { "Base.TinnedBeans", 4 }, { "Base.CannedCorn", 3 }, { "Base.CannedChili", 3 }, { "Base.Crackers", 3 },
                    { "Base.Rice", 2 }, { "Base.Oatmeal", 2 }, { "Base.PeanutButter", 1 }, { "Base.WaterBottle", 4 },
                    { "Base.Pot", 1 }, { "Base.Kettle", 1 }, { "Base.Bowl", 2 }, { "Base.Spoon", 2 }, { "Base.TinOpener", 1 } },
        gear    = { { "Base.Hammer", 1 }, { "Base.Saw", 1 }, { "Base.Screwdriver", 1 }, { "Base.NailsBox", 2 }, { "Base.HandAxe", 1 },
                    { "Base.Crowbar", 1 }, { "Base.Rope", 2 }, { "Base.Twine", 3 }, { "Base.DuctTape", 2 }, { "Base.Tarp", 2 },
                    { "Base.HandTorch", 1 }, { "Base.Battery", 4 }, { "Base.Matches", 3 }, { "Base.Candle", 6 },
                    { "Base.FishingRod", 1 }, { "Base.Bucket", 1 } },
        keepsakes = { { "Base.Book", 3 }, { "Base.Journal", 1 }, { "Base.Pencil", 2 }, { "Base.Photo", 2 }, { "Base.ToyBear", 1 },
                      { "Base.Doll", 1 }, { "Base.CardDeck", 1 }, { "Base.RadioRed", 1 }, { "Base.MuldraughMap", 1 },
                      { "Base.Soap2", 2 }, { "Base.Toothbrush", 2 }, { "Base.Toothpaste", 1 }, { "Base.Comb", 1 },
                      { "Base.Needle", 2 }, { "Base.Thread", 2 }, { "Base.Yarn", 2 }, { "Base.KnittingNeedles", 1 } },
        clothes = { { "Base.Sheet", 3 }, { "Base.Pillow", 2 }, { "Base.Hat_Beany", 2 }, { "Base.Jacket_Padded", 2 },
                    { "Base.Gloves_LeatherGloves", 2 }, { "Base.Shoes_BlackBoots", 2 }, { "Base.Socks_Long", 4 },
                    { "Base.Trousers_Denim", 2 }, { "Base.RippedSheets", 6 }, { "Base.Bandage", 3 },
                    { "Base.Bag_Schoolbag", 1 }, { "Base.Bag_DuffelBag", 1 } },
        -- the hospital car
        medicine = { { "Base.Pills", 6 }, { "Base.PillsBeta", 4 }, { "Base.PillsAntiDep", 4 }, { "Base.PillsSleepingTablets", 4 },
                     { "Base.PillsVitamins", 4 }, { "Base.Antibiotics", 6 }, { "Base.Disinfectant", 4 },
                     { "Base.AlcoholWipes", 6 }, { "Base.Coldpack", 3 } },
        dressings = { { "Base.Bandage", 8 }, { "Base.AlcoholBandage", 6 }, { "Base.Bandaid", 8 }, { "Base.CottonBalls", 4 },
                      { "Base.AlcoholedCottonBalls", 4 }, { "Base.Splint", 3 }, { "Base.RippedSheets", 8 } },
        instruments = { { "Base.SutureNeedle", 6 }, { "Base.SutureNeedleHolder", 2 }, { "Base.Tweezers", 2 },
                        { "Base.Scalpel", 2 }, { "Base.ScissorsBluntMedical", 2 }, { "Base.Stethoscope", 1 },
                        { "Base.Gloves_Surgical", 3 }, { "Base.Hat_SurgicalMask", 3 }, { "Base.Hat_SurgicalCap", 2 },
                        { "Base.Needle", 3 }, { "Base.Thread", 3 } },
        firstaid = { { "Base.FirstAidKit", 3 } },
        linen  = { { "Base.Sheet", 6 }, { "Base.Pillow", 4 }, { "Base.BathTowel", 4 }, { "Base.Soap2", 4 }, { "Base.Tissue", 4 },
                   { "Base.Bleach", 2 }, { "Base.WaterBottle", 6 }, { "Base.HandTorch", 2 }, { "Base.Battery", 4 } },
        drinks = { { "Base.WaterBottle", 6 }, { "Base.Pop", 6 }, { "Base.BeerBottle", 6 }, { "Base.Wine", 2 },
                   { "Base.Wine2", 2 }, { "Base.Apple", 4 }, { "Base.Orange", 4 }, { "Base.Chocolate", 4 } },
        -- the rest of the cars (0.16.0): the warehouse and the workshop
        hardware = { { "Base.NailsBox", 4 }, { "Base.ScrewsBox", 4 }, { "Base.Woodglue", 3 }, { "Base.Glue", 3 },
                     { "Base.DuctTape", 4 }, { "Base.Scotchtape", 3 }, { "Base.Hinge", 6 }, { "Base.Doorknob", 4 },
                     { "Base.Rope", 4 }, { "Base.Twine", 4 }, { "Base.Wire", 3 }, { "Base.Paintbrush", 2 },
                     { "Base.PaintWhite", 2 }, { "Base.PaintBlue", 1 }, { "Base.PlasterPowder", 2 },
                     { "Base.ConcretePowder", 2 } },
        lumber  = { { "Base.Plank", 8 }, { "Base.Log", 4 }, { "Base.TreeBranch2", 4 }, { "Base.Firewood", 6 },
                    { "Base.Charcoal", 2 }, { "Base.Tarp", 3 }, { "Base.Sandbag", 2 }, { "Base.Gravelbag", 2 } },
        metalwork = { { "Base.SheetMetal", 4 }, { "Base.SmallSheetMetal", 6 }, { "Base.MetalPipe", 4 }, { "Base.MetalBar", 4 },
                      { "Base.ScrapMetal", 6 }, { "Base.Aluminum", 3 }, { "Base.WeldingRods", 4 }, { "Base.BlowTorch", 2 },
                      { "Base.WeldingMask", 1 }, { "Base.PropaneTank", 1 } },
        fabric  = { { "Base.Sheet", 6 }, { "Base.Thread", 6 }, { "Base.Needle", 4 }, { "Base.Yarn", 4 },
                    { "Base.LeatherStrips", 6 }, { "Base.DenimStrips", 6 }, { "Base.RippedSheets", 8 }, { "Base.Scissors", 2 } },
        mechanic = { { "Base.Wrench", 2 }, { "Base.LugWrench", 1 }, { "Base.Jack", 1 }, { "Base.TirePump", 1 },
                     { "Base.Ratchet", 1 }, { "Base.Pliers", 2 }, { "Base.Screwdriver", 2 }, { "Base.File", 1 },
                     { "Base.ViseGrips", 1 }, { "Base.BallPeenHammer", 1 }, { "Base.ClubHammer", 1 },
                     { "Base.WoodenMallet", 1 }, { "Base.HandDrill", 1 }, { "Base.SmallSaw", 1 }, { "Base.Whetstone", 2 },
                     { "Base.Multitool", 1 } },
        electrics = { { "Base.ElectronicsScrap", 8 }, { "Base.ElectricWire", 6 }, { "Base.LightBulb", 6 }, { "Base.Battery", 8 },
                      { "Base.Amplifier", 2 }, { "Base.Receiver", 2 }, { "Base.CarBattery1", 1 },
                      { "Base.CarBatteryCharger", 1 }, { "Base.ElectronicsMag4", 1 }, { "Base.HandTorch", 2 },
                      { "Base.WalkieTalkie3", 2 } },
        fuel    = { { "Base.PetrolCan", 4 }, { "Base.PropaneTank", 2 }, { "Base.RubberHose", 2 }, { "Base.Extinguisher", 2 },
                    { "Base.Charcoal", 2 }, { "Base.Matches", 3 } },
        parts   = { { "Base.OldTire1", 2 }, { "Base.NormalTire1", 2 }, { "Base.OldBrake1", 2 },
                    { "Base.NormalSuspension1", 2 }, { "Base.CarBattery2", 1 }, { "Base.EngineParts", 6 } },
        -- the armory
        rifles  = { { "Base.Shotgun", 2 }, { "Base.HuntingRifle", 2 }, { "Base.VarmintRifle", 1 }, { "Base.AssaultRifle", 1 } },
        sidearms = { { "Base.Pistol", 3 }, { "Base.Pistol2", 1 }, { "Base.Revolver", 2 }, { "Base.HolsterSimple", 3 },
                     { "Base.Nightstick", 3 }, { "Base.HuntingKnife", 2 }, { "Base.9mmClip", 4 } },
        ammo    = { { "Base.Bullets9mmBox", 6 }, { "Base.Bullets45Box", 3 }, { "Base.Bullets38Box", 4 },
                    { "Base.ShotgunShellsBox", 6 }, { "Base.308Box", 4 }, { "Base.556Box", 3 } },
        armor   = { { "Base.Vest_BulletArmy", 2 }, { "Base.Vest_BulletPolice", 2 }, { "Base.Hat_Army", 2 },
                    { "Base.Hat_RiotHelmet", 2 }, { "Base.AmmoStraps", 2 }, { "Base.Bag_WeaponBag", 2 },
                    { "Base.WalkieTalkie4", 2 }, { "Base.HandTorch", 2 } },
        -- the baggage car and the mail car
        luggage = { { "Base.Suitcase", 4 }, { "Base.Briefcase", 2 }, { "Base.Bag_DuffelBag", 2 }, { "Base.Bag_NormalHikingBag", 1 },
                    { "Base.Bag_BigHikingBag", 1 }, { "Base.Purse", 2 }, { "Base.Handbag", 2 }, { "Base.Bag_Satchel", 2 },
                    { "Base.Bag_Schoolbag", 2 } },
        travel  = { { "Base.Camera", 1 }, { "Base.Shirt_FormalWhite", 3 }, { "Base.Trousers_Suit", 2 }, { "Base.Tie_Full", 2 },
                    { "Base.Hat_Fedora", 2 }, { "Base.Shoes_Black", 2 }, { "Base.Dress_Normal", 2 }, { "Base.Skirt_Normal", 2 },
                    { "Base.Socks_Long", 4 }, { "Base.Toothbrush", 2 }, { "Base.Toothpaste", 2 }, { "Base.Razor", 2 },
                    { "Base.Soap2", 2 }, { "Base.AlarmClock2", 1 }, { "Base.Book", 3 }, { "Base.Magazine", 3 } },
        mail    = { { "Base.GenericMail", 8 }, { "Base.LetterHandwritten", 6 }, { "Base.Postcard", 6 }, { "Base.Newspaper", 6 },
                    { "Base.Magazine", 6 }, { "Base.Bag_Mail", 2 }, { "Base.LetterOpener", 1 } },
        parcels = { { "Base.Parcel_ExtraSmall", 4 }, { "Base.Parcel_Small", 6 }, { "Base.Parcel_Medium", 4 },
                    { "Base.Parcel_Large", 2 } },
        stationery = { { "Base.Notebook", 4 }, { "Base.Pen", 4 }, { "Base.Pencil", 4 }, { "Base.BluePen", 2 }, { "Base.RedPen", 2 },
                       { "Base.Eraser", 2 }, { "Base.Paperclip", 6 }, { "Base.Stapler", 1 }, { "Base.SheetPaper2", 8 },
                       { "Base.Clipboard", 2 }, { "Base.Scissors", 1 }, { "Base.Calculator", 1 }, { "Base.Crayons", 2 } },
        -- the refrigerator car
        meat    = { { "Base.Steak", 6 }, { "Base.Chicken", 4 }, { "Base.PorkChop", 6 }, { "Base.MuttonChop", 4 },
                    { "Base.MincedMeat", 6 }, { "Base.Bacon", 4 }, { "Base.Sausage", 6 }, { "Base.Ham", 3 },
                    { "Base.Salami", 3 }, { "Base.Baloney", 3 } },
        fish    = { { "Base.Salmon", 4 }, { "Base.FishFillet", 6 }, { "Base.Lobster", 2 }, { "Base.Shrimp", 6 },
                    { "Base.Frozen_FishFingers", 4 } },
        dairy   = { { "Base.Milk", 4 }, { "Base.Butter", 4 }, { "Base.Cheese", 6 }, { "Base.Processedcheese", 4 },
                    { "Base.Yoghurt", 6 }, { "Base.EggCarton", 4 } },
        produce = { { "Base.Lettuce", 4 }, { "Base.Tomato", 6 }, { "Base.Carrots", 6 }, { "Base.Broccoli", 4 },
                    { "Base.Cabbage", 4 }, { "Base.Apple", 6 }, { "Base.Orange", 6 }, { "Base.Cherry", 4 },
                    { "Base.Grapes", 4 }, { "Base.Potato", 8 }, { "Base.Onion", 6 } },
        frozen  = { { "Base.Icecream", 4 }, { "Base.Peas", 4 }, { "Base.CornFrozen", 4 }, { "Base.Pizza", 3 },
                    { "Base.Burger", 4 }, { "Base.Hotdog", 4 }, { "Base.Frozen_ChickenNuggets", 3 },
                    { "Base.Frozen_FrenchFries", 3 }, { "Base.Pie", 2 } },
        -- the greenhouse and the livestock car
        seeds   = { { "Base.CarrotBagSeed2", 3 }, { "Base.BroccoliBagSeed2", 3 }, { "Base.CabbageBagSeed2", 3 },
                    { "Base.PotatoBagSeed2", 3 }, { "Base.TomatoBagSeed2", 3 }, { "Base.RedRadishBagSeed2", 3 },
                    { "Base.StrewberrieBagSeed2", 2 }, { "Base.LettuceBagSeed", 2 }, { "Base.OnionBagSeed", 2 },
                    { "Base.GarlicBagSeed", 2 }, { "Base.CornBagSeed", 2 } },
        garden  = { { "Base.HandShovel", 2 }, { "Base.GardenFork", 1 }, { "Base.GardenHoe", 1 }, { "Base.Rake", 1 },
                    { "Base.Shovel", 1 }, { "Base.HandFork", 2 }, { "Base.GardeningSprayEmpty", 2 }, { "Base.Fertilizer", 4 },
                    { "Base.CompostBag", 3 }, { "Base.Bucket", 2 }, { "Base.BookFarming1", 1 }, { "Base.Twine", 3 },
                    { "Base.Gloves_LeatherGloves", 2 } },
        feed    = { { "Base.AnimalFeedBag", 6 }, { "Base.HayTuft", 8 }, { "Base.Straw2", 8 }, { "Base.Corn", 6 },
                    { "Base.OatsRaw", 4 }, { "Base.WheatSack", 2 }, { "Base.Dogfood", 4 }, { "Base.Salt", 2 },
                    { "Base.Apple", 6 }, { "Base.Carrots", 6 } },
        tack    = { { "Base.Rope", 4 }, { "Base.Leash", 2 }, { "Base.Bucket", 2 }, { "Base.BucketEmpty", 2 }, { "Base.Twine", 4 },
                    { "Base.FeedingBottle", 2 }, { "Base.WaterDish", 2 }, { "Base.Shovel", 1 }, { "Base.GardenFork", 1 } },
        -- the library, the chapel, the dining car and the lounge
        books   = { { "Base.Book", 8 }, { "Base.BookFarming1", 1 }, { "Base.BookCarpentry1", 1 }, { "Base.BookCooking1", 1 },
                    { "Base.BookFirstAid1", 1 }, { "Base.BookMechanic1", 1 }, { "Base.BookElectrician1", 1 },
                    { "Base.BookFishing1", 1 }, { "Base.BookTrapping1", 1 }, { "Base.BookForaging1", 1 },
                    { "Base.BookTailoring1", 1 }, { "Base.BookMetalWelding1", 1 }, { "Base.ComicBook", 4 },
                    { "Base.Magazine", 4 } },
        chapel  = { { "Base.Book_Bible", 4 }, { "Base.Paperback_Bible", 4 }, { "Base.Candle", 8 }, { "Base.Matches", 2 },
                    { "Base.Necklace_Crucifix", 2 }, { "Base.Bell", 1 }, { "Base.Wine", 2 }, { "Base.Bread", 2 } },
        table   = { { "Base.Plate", 8 }, { "Base.Bowl", 6 }, { "Base.Fork", 8 }, { "Base.Spoon", 8 }, { "Base.ButterKnife", 8 },
                    { "Base.GlassWine", 8 }, { "Base.Teacup", 6 }, { "Base.Salt", 2 }, { "Base.Pepper", 2 }, { "Base.Ketchup", 2 },
                    { "Base.Mustard", 2 }, { "Base.Hotsauce", 1 }, { "Base.Sugar", 2 } },
        sweets  = { { "Base.Cupcake", 4 }, { "Base.Pie", 2 }, { "Base.CakeSlice", 6 }, { "Base.DoughnutPlain", 6 },
                    { "Base.Coffee2", 2 }, { "Base.Teabag2", 2 } },
        snacks  = { { "Base.Peanuts", 6 }, { "Base.Crisps", 4 }, { "Base.Crisps2", 4 }, { "Base.Pretzel", 4 }, { "Base.Popcorn", 4 },
                    { "Base.TortillaChips", 4 }, { "Base.Pop", 6 }, { "Base.BeerCan", 6 }, { "Base.CigarettePack", 3 },
                    { "Base.CardDeck", 2 } },
        -- the crew's: the dormitory and the caboose
        kit     = { { "Base.Boilersuit", 3 }, { "Base.Shoes_WorkBoots", 3 }, { "Base.Gloves_LeatherGloves", 3 },
                    { "Base.Hat_HardHat", 3 }, { "Base.Vest_HighViz", 3 }, { "Base.Hat_BaseballCap", 2 }, { "Base.Whistle", 2 },
                    { "Base.HandTorch", 3 }, { "Base.Lantern_Hurricane", 2 }, { "Base.AlarmClock2", 2 }, { "Base.Razor", 2 },
                    { "Base.Soap2", 3 }, { "Base.Toothbrush", 3 }, { "Base.Toothpaste", 2 } },
        crew    = { { "Base.CannedCornedBeef", 4 }, { "Base.Coffee2", 2 }, { "Base.Kettle", 1 }, { "Base.MugSpiffo", 2 },
                    { "Base.Pot", 1 }, { "Base.Lantern_Hurricane", 2 }, { "Base.Matches", 3 }, { "Base.Firewood", 6 },
                    { "Base.Whistle", 1 }, { "Base.CardDeck", 1 }, { "Base.Journal", 1 }, { "Base.Pencil", 2 },
                    { "Base.HandTorch", 1 }, { "Base.Battery", 4 } },
    },
    water    = 20,              -- what a sink is given to hold if it has nothing of its own
    -- **Every car is on the water and on the power** (the author, 2026-10-11: "all cars should be
    -- automatically connected to water and power"), whatever is in it and whoever put it there:
    -- anything in a car's room that is a water fixture by its tile's own properties (a sink, a
    -- bath, a rain barrel somebody built) is kept full, as the fittings a room comes with are.
    -- Never anything that holds something other than water. The sandbox's Water and Power.
    plumbed  = { "waterPiped", "waterMaxAmount", "IsWaterCollector" },
    serviceEvery = 60,          -- how many times the rooms are served between one topping-up and the next
    powerItem = "Trains.TrnPowerBus",
    -- Every car has power, always (the author, 2026-10-08: "make sure
    -- electricity is setup and always on"): its generator is under this
    -- square of its room unless its style names another.
    powerAt  = { dx = 6, dy = 2 },
    tvPower  = 1.0,             -- a television's own cell, kept full: it never asks the grid
    frameW   = "industry_01_10",
    frameN   = "industry_01_11",
    -- How many storeys up the roof is. It was one, and (PLAYED 2026-10-08,
    -- "still getting cabins sometimes showing like this") some of the time
    -- the north half of a room was not drawn: the part of it a floor one
    -- storey up stands over on the screen, three squares up and left of
    -- itself, except close round the player. Three storeys up it stands
    -- over nothing of the room, walls and all. A square is indoors for a
    -- solid floor on any storey above it (IsoCell.checkHaveRoof).
    roofUp   = 3,
    map      = "Trains",    -- the map under the rooms (tools/gen_void_map.py)
    light    = { r = 1.0, g = 0.92, b = 0.75, radius = 9 },
    settle   = 15,          -- ticks held after the floor is seen, while the engine settles it
    askEvery = 120,         -- an arrival asks the server for its room again this often
    timeout  = 1500,        -- ticks before an arrival gives up and asks to be put back outside
    lostAfter = 50,         -- updates off her floor before somebody inside is brought back
    -- Where the map under the rooms is not loaded (a save made before it
    -- was there), the ground round a room is wilderness. This far out from
    -- a room everything the engine grew is taken, ground and all, which
    -- leaves black: past what a rider can see from inside.
    clear    = 40,
    black    = "trains_02_62",  -- the floor laid there: black, and ours
    clearPerPass = 800,     -- squares looked at each time the server serves the rooms
    -- And much further out, as far as the engine keeps ground loaded round
    -- a rider, nothing that grows is left, for as long as somebody is
    -- inside: a tree drawn while a player stands in a room of ours throws
    -- in the engine's renderer and the rest of the frame is not drawn
    -- (DEV_GUIDE.md, "A room of ours is a room to the engine, and has none").
    grown    = 90,
    grownPerPass = 3000,
    -- Floors a room may be standing on that are not its own any more: the
    -- first rooms (revision 1) were floored in vanilla's tile.
    oldFloors = { "floors_interior_tilesandwood_01_0" },
    -- The plates on the floor in front of the two doors the camera cannot
    -- see: a room is looked at from the south-east, so only its north and
    -- west walls show their faces.
    matRear  = "trains_01_9",
    matSide  = "trains_01_10",
    -- What each kind of car is inside (design/art/train_room_<kind>.png).
    -- wallN is the picture on each square of the north wall, front to rear;
    -- wallW on each of the west wall, north to south, and the middle one is
    -- the front door. `fittings` are placed the first time a room is raised
    -- and never again: after that it is its riders' to furnish. dx along
    -- from the front, dy across from the north wall. `floor` is a pattern,
    -- rows of tiles repeated across the room; `aisle` is the middle row's.
    -- GENERATED: python tools/gen_train_tiles.py styles (its ROOMS is where
    -- a room is designed; tests/test_assets.py holds the two together).
    styles = {
        private = {
            base = { W = "walls_interior_house_03_16", N = "walls_interior_house_03_17", doorW = "walls_interior_house_03_26", doorN = "walls_interior_house_03_27" },
            inner = { W = "walls_interior_house_03_32", N = "walls_interior_house_03_33", doorW = "walls_interior_house_03_42", doorN = "walls_interior_house_03_43" },
            floor = { { "floors_interior_tilesandwood_01_44", "floors_interior_tilesandwood_01_44", "floors_interior_tilesandwood_01_44", "floors_interior_tilesandwood_01_44", "floors_interior_tilesandwood_01_44", "floors_interior_tilesandwood_01_44", "floors_interior_tilesandwood_01_44", "floors_interior_carpet_01_8", "floors_interior_carpet_01_8", "floors_interior_carpet_01_8", "floors_interior_tilesandwood_01_5", "floors_interior_tilesandwood_01_5" }, { "floors_interior_tilesandwood_01_44", "floors_interior_tilesandwood_01_44", "floors_interior_tilesandwood_01_44", "floors_interior_tilesandwood_01_44", "floors_interior_tilesandwood_01_44", "floors_interior_tilesandwood_01_44", "floors_interior_tilesandwood_01_44", "floors_interior_carpet_01_8", "floors_interior_carpet_01_8", "floors_interior_carpet_01_8", "floors_interior_tilesandwood_01_5", "floors_interior_tilesandwood_01_5" }, { "floors_interior_tilesandwood_01_44", "floors_interior_tilesandwood_01_44", "floors_interior_tilesandwood_01_44", "floors_interior_tilesandwood_01_44", "floors_interior_tilesandwood_01_44", "floors_interior_tilesandwood_01_44", "floors_interior_tilesandwood_01_44", "floors_interior_carpet_01_8", "floors_interior_carpet_01_8", "floors_interior_carpet_01_8", "floors_interior_carpet_01_8", "floors_interior_carpet_01_8" }, { "floors_interior_tilesandwood_01_44", "floors_interior_tilesandwood_01_44", "floors_interior_tilesandwood_01_44", "floors_interior_tilesandwood_01_44", "floors_interior_tilesandwood_01_44", "floors_interior_tilesandwood_01_44", "floors_interior_tilesandwood_01_44", "floors_interior_carpet_01_8", "floors_interior_carpet_01_8", "floors_interior_carpet_01_8", "floors_interior_carpet_01_8", "floors_interior_carpet_01_8" }, { "floors_interior_tilesandwood_01_44", "floors_interior_tilesandwood_01_44", "floors_interior_tilesandwood_01_44", "floors_interior_tilesandwood_01_44", "floors_interior_tilesandwood_01_44", "floors_interior_tilesandwood_01_44", "floors_interior_tilesandwood_01_44", "floors_interior_carpet_01_8", "floors_interior_carpet_01_8", "floors_interior_carpet_01_8", "floors_interior_carpet_01_8", "floors_interior_carpet_01_8" } },
            aisle = { "floors_interior_tilesandwood_01_44", "floors_interior_tilesandwood_01_44", "floors_interior_tilesandwood_01_44", "floors_interior_tilesandwood_01_44", "floors_interior_tilesandwood_01_44", "floors_interior_tilesandwood_01_44", "floors_interior_tilesandwood_01_44", "floors_interior_carpet_01_8", "floors_interior_carpet_01_8", "floors_interior_carpet_01_8", "floors_interior_carpet_01_8", "floors_interior_carpet_01_8" },
            wallN = { "trains_02_92", "trains_02_93", "trains_02_92", "trains_02_93", "", "trains_02_97", "trains_02_93", "trains_02_92", "trains_02_93", "trains_02_92", "trains_02_93", "trains_02_92" },
            wallW = { "", "", "trains_02_95", "", "" },
            walls = {
                { dx = 7, dy = 0, side = "W", sprite = "" },
                { dx = 7, dy = 1, side = "W", sprite = "" },
                { dx = 7, dy = 2, side = "W", sprite = "", door = true },
                { dx = 7, dy = 3, side = "W", sprite = "" },
                { dx = 7, dy = 4, side = "W", sprite = "" },
                { dx = 10, dy = 0, side = "W", sprite = "" },
                { dx = 10, dy = 1, side = "W", sprite = "" },
                { dx = 10, dy = 2, side = "N", sprite = "", door = true },
                { dx = 11, dy = 2, side = "N", sprite = "" },
            },
            lamps = { { dx = 3, dy = 2 }, { dx = 8, dy = 3 }, { dx = 10, dy = 0 } },
            fittings = {
                { dx = 1, dy = 0, sprite = "furniture_tables_high_01_26" },
                { dx = 2, dy = 0, sprite = "furniture_tables_high_01_27" },
                { dx = 1, dy = 1, sprite = "furniture_seating_indoor_03_47" },
                { dx = 3, dy = 0, sprite = "furniture_shelving_01_40", stock = "study" },
                { dx = 4, dy = 0, sprite = "furniture_shelving_01_44", stock = "study" },
                { dx = 5, dy = 0, sprite = "appliances_television_01_9", tv = "Base.TvAntique" },
                { dx = 6, dy = 0, sprite = "lighting_indoor_02_64" },
                { dx = 3, dy = 1, sprite = "floors_rugs_01_28" },
                { dx = 3, dy = 2, sprite = "floors_rugs_01_29" },
                { dx = 4, dy = 1, sprite = "floors_rugs_01_36" },
                { dx = 4, dy = 2, sprite = "floors_rugs_01_37" },
                { dx = 5, dy = 1, sprite = "floors_rugs_01_44" },
                { dx = 5, dy = 2, sprite = "floors_rugs_01_45" },
                { dx = 1, dy = 4, sprite = "furniture_seating_indoor_03_132" },
                { dx = 2, dy = 4, sprite = "furniture_seating_indoor_03_133" },
                { dx = 2, dy = 3, sprite = "furniture_tables_low_01_3" },
                { dx = 3, dy = 4, sprite = "furniture_seating_indoor_03_116" },
                { dx = 4, dy = 4, sprite = "furniture_seating_indoor_03_117" },
                { dx = 6, dy = 4, sprite = "furniture_storage_01_35", stock = "liquor" },
                { dx = 7, dy = 0, sprite = "furniture_storage_01_33", stock = "clothes" },
                { dx = 8, dy = 0, sprite = "furniture_bedding_01_5" },
                { dx = 8, dy = 1, sprite = "furniture_bedding_01_4" },
                { dx = 9, dy = 0, sprite = "furniture_bedding_01_7" },
                { dx = 9, dy = 1, sprite = "furniture_bedding_01_6" },
                { dx = 7, dy = 4, sprite = "furniture_storage_01_28", stock = "finery" },
                { dx = 8, dy = 4, sprite = "furniture_storage_01_29" },
                { dx = 9, dy = 4, sprite = "lighting_indoor_02_68" },
                { dx = 10, dy = 0, sprite = "fixtures_bathroom_01_0", water = true },
                { dx = 10, dy = 1, sprite = "fixtures_sinks_01_1", water = true },
                { dx = 11, dy = 0, sprite = "fixtures_bathroom_01_25", water = true },
                { dx = 11, dy = 1, sprite = "fixtures_bathroom_01_24" },
            },
        },
        parlor = {
            base = { W = "walls_interior_house_01_32", N = "walls_interior_house_01_33", doorW = "walls_interior_house_01_42", doorN = "walls_interior_house_01_43" },
            floor = { { "floors_interior_tilesandwood_01_44" } },
            aisle = { "floors_interior_carpet_01_9" },
            wallN = { "trains_02_92", "trains_02_93", "trains_02_92", "trains_02_93", "", "trains_02_97", "trains_02_93", "trains_02_92", "trains_02_93", "trains_02_92", "trains_02_93", "trains_02_92" },
            wallW = { "", "", "trains_02_95", "", "" },
            lamps = { { dx = 3, dy = 2 }, { dx = 8, dy = 2 } },
            fittings = {
                { dx = 1, dy = 0, sprite = "furniture_seating_indoor_03_74" },
                { dx = 2, dy = 0, sprite = "furniture_seating_indoor_03_75" },
                { dx = 3, dy = 0, sprite = "lighting_indoor_02_64" },
                { dx = 4, dy = 0, sprite = "furniture_storage_01_33", stock = "parlor" },
                { dx = 5, dy = 0, sprite = "appliances_television_01_9", tv = "Base.TvAntique" },
                { dx = 6, dy = 0, sprite = "recreational_01_8" },
                { dx = 7, dy = 0, sprite = "recreational_01_9" },
                { dx = 6, dy = 1, sprite = "recreational_01_10" },
                { dx = 7, dy = 1, sprite = "recreational_01_11" },
                { dx = 8, dy = 0, sprite = "location_restaurant_bar_01_64", stock = "liquor" },
                { dx = 9, dy = 0, sprite = "location_restaurant_bar_01_65", stock = "liquor" },
                { dx = 10, dy = 0, sprite = "location_restaurant_bar_01_66", stock = "glasses" },
                { dx = 8, dy = 1, sprite = "location_restaurant_bar_01_26" },
                { dx = 10, dy = 1, sprite = "location_restaurant_bar_01_26" },
                { dx = 2, dy = 1, sprite = "floors_rugs_01_24" },
                { dx = 2, dy = 2, sprite = "floors_rugs_01_25" },
                { dx = 3, dy = 1, sprite = "floors_rugs_01_32" },
                { dx = 3, dy = 2, sprite = "floors_rugs_01_33" },
                { dx = 4, dy = 1, sprite = "floors_rugs_01_40" },
                { dx = 4, dy = 2, sprite = "floors_rugs_01_41" },
                { dx = 1, dy = 4, sprite = "furniture_seating_indoor_03_92" },
                { dx = 2, dy = 4, sprite = "furniture_seating_indoor_03_93" },
                { dx = 3, dy = 4, sprite = "lighting_indoor_02_68" },
                { dx = 7, dy = 3, sprite = "furniture_tables_low_01_8" },
                { dx = 8, dy = 3, sprite = "furniture_tables_low_01_9" },
                { dx = 7, dy = 4, sprite = "furniture_seating_indoor_03_108" },
                { dx = 8, dy = 4, sprite = "furniture_seating_indoor_03_109" },
                { dx = 6, dy = 3, sprite = "furniture_seating_indoor_03_40" },
                { dx = 9, dy = 3, sprite = "furniture_seating_indoor_03_42" },
                { dx = 10, dy = 4, sprite = "lighting_indoor_02_64" },
            },
        },
        survivor = {
            base = { W = "walls_exterior_wooden_01_0", N = "walls_exterior_wooden_01_1", doorW = "walls_exterior_wooden_01_10", doorN = "walls_exterior_wooden_01_11" },
            floor = { { "floors_interior_tilesandwood_01_42" } },
            aisle = { "floors_interior_tilesandwood_01_42" },
            wallN = { "", "", "", "", "", "trains_02_97", "", "", "", "", "", "" },
            wallW = { "", "", "trains_02_96", "", "" },
            lamps = { { dx = 3, dy = 2 }, { dx = 8, dy = 2 } },
            fittings = {
                { dx = 1, dy = 0, sprite = "carpentry_02_79" },
                { dx = 1, dy = 1, sprite = "carpentry_02_78" },
                { dx = 3, dy = 0, sprite = "camping_02_20" },
                { dx = 4, dy = 0, sprite = "camping_02_21" },
                { dx = 6, dy = 0, sprite = "appliances_cooking_01_17" },
                { dx = 7, dy = 0, sprite = "carpentry_01_16", stock = "larder" },
                { dx = 8, dy = 0, sprite = "carpentry_01_16", stock = "gear" },
                { dx = 9, dy = 0, sprite = "crafted_05_32", stock = "keepsakes" },
                { dx = 10, dy = 0, sprite = "industry_01_23" },
                { dx = 8, dy = 3, sprite = "furniture_tables_high_01_14" },
                { dx = 7, dy = 3, sprite = "furniture_seating_indoor_02_1" },
                { dx = 9, dy = 3, sprite = "furniture_seating_indoor_02_3" },
                { dx = 1, dy = 4, sprite = "carpentry_01_19", stock = "clothes" },
                { dx = 2, dy = 4, sprite = "carpentry_01_16", stock = "larder" },
            },
        },
        hospital = {
            base = { W = "walls_interior_house_01_0", N = "walls_interior_house_01_1", doorW = "walls_interior_house_01_10", doorN = "walls_interior_house_01_11" },
            floor = { { "floors_interior_tilesandwood_01_5" } },
            aisle = { "floors_interior_tilesandwood_01_5" },
            wallN = { "trains_02_92", "trains_02_93", "trains_02_92", "trains_02_93", "", "trains_02_97", "trains_02_93", "trains_02_92", "trains_02_93", "trains_02_92", "trains_02_93", "trains_02_92" },
            wallW = { "", "", "trains_02_95", "", "" },
            lamps = { { dx = 3, dy = 2 }, { dx = 8, dy = 2 } },
            fittings = {
                { dx = 1, dy = 0, sprite = "location_community_medical_01_154", stock = "medicine" },
                { dx = 2, dy = 0, sprite = "location_community_medical_01_155", stock = "dressings" },
                { dx = 3, dy = 0, sprite = "fixtures_sinks_01_2", water = true },
                { dx = 4, dy = 0, sprite = "location_community_medical_01_37", stock = "instruments" },
                { dx = 5, dy = 0, sprite = "location_community_medical_01_88", stock = "firstaid" },
                { dx = 7, dy = 0, sprite = "location_community_medical_01_73" },
                { dx = 7, dy = 1, sprite = "location_community_medical_01_72" },
                { dx = 8, dy = 0, sprite = "location_community_medical_01_25" },
                { dx = 9, dy = 0, sprite = "location_community_medical_01_73" },
                { dx = 9, dy = 1, sprite = "location_community_medical_01_72" },
                { dx = 10, dy = 0, sprite = "location_community_medical_01_49" },
                { dx = 1, dy = 4, sprite = "location_community_medical_01_238", stock = "linen" },
                { dx = 2, dy = 4, sprite = "location_community_medical_01_239", stock = "dressings" },
                { dx = 7, dy = 4, sprite = "location_community_medical_01_62" },
                { dx = 8, dy = 4, sprite = "location_community_medical_01_63" },
            },
        },
        sleeper = {
            base = { W = "walls_interior_house_04_16", N = "walls_interior_house_04_17", doorW = "walls_interior_house_04_26", doorN = "walls_interior_house_04_27" },
            inner = { W = "walls_interior_house_03_32", N = "walls_interior_house_03_33", doorW = "walls_interior_house_03_42", doorN = "walls_interior_house_03_43" },
            floor = { { "floors_interior_carpet_01_2", "floors_interior_carpet_01_2", "floors_interior_carpet_01_2", "floors_interior_carpet_01_2", "floors_interior_carpet_01_2", "floors_interior_carpet_01_2", "floors_interior_carpet_01_2", "floors_interior_carpet_01_2", "floors_interior_carpet_01_2", "floors_interior_carpet_01_2", "floors_interior_carpet_01_2", "floors_interior_carpet_01_2" }, { "floors_interior_carpet_01_2", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_2", "floors_interior_tilesandwood_01_5", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_2" }, { "floors_interior_carpet_01_2", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_2", "floors_interior_tilesandwood_01_5", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_2" }, { "floors_interior_carpet_01_2", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_2", "floors_interior_tilesandwood_01_5", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_2" }, { "floors_interior_carpet_01_2", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_2", "floors_interior_tilesandwood_01_5", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_2" } },
            aisle = { "floors_interior_carpet_01_2", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_2", "floors_interior_tilesandwood_01_5", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_2" },
            wallN = { "trains_02_90", "trains_02_91", "trains_02_90", "trains_02_91", "", "trains_02_97", "trains_02_91", "trains_02_90", "trains_02_91", "trains_02_90", "trains_02_91", "trains_02_90" },
            wallW = { "", "", "trains_02_94", "", "" },
            walls = {
                { dx = 1, dy = 1, side = "N", sprite = "", door = true },
                { dx = 2, dy = 1, side = "N", sprite = "" },
                { dx = 3, dy = 1, side = "N", sprite = "", door = true },
                { dx = 4, dy = 1, side = "N", sprite = "" },
                { dx = 6, dy = 1, side = "N", sprite = "" },
                { dx = 7, dy = 1, side = "N", sprite = "", door = true },
                { dx = 8, dy = 1, side = "N", sprite = "" },
                { dx = 9, dy = 1, side = "N", sprite = "", door = true },
                { dx = 10, dy = 1, side = "N", sprite = "" },
                { dx = 1, dy = 1, side = "W", sprite = "" },
                { dx = 1, dy = 2, side = "W", sprite = "" },
                { dx = 1, dy = 3, side = "W", sprite = "" },
                { dx = 1, dy = 4, side = "W", sprite = "" },
                { dx = 3, dy = 1, side = "W", sprite = "" },
                { dx = 3, dy = 2, side = "W", sprite = "" },
                { dx = 3, dy = 3, side = "W", sprite = "" },
                { dx = 3, dy = 4, side = "W", sprite = "" },
                { dx = 5, dy = 1, side = "W", sprite = "" },
                { dx = 5, dy = 2, side = "W", sprite = "" },
                { dx = 5, dy = 3, side = "W", sprite = "" },
                { dx = 5, dy = 4, side = "W", sprite = "" },
                { dx = 6, dy = 1, side = "W", sprite = "" },
                { dx = 6, dy = 2, side = "W", sprite = "", door = true },
                { dx = 6, dy = 3, side = "W", sprite = "" },
                { dx = 6, dy = 4, side = "W", sprite = "" },
                { dx = 7, dy = 1, side = "W", sprite = "" },
                { dx = 7, dy = 2, side = "W", sprite = "" },
                { dx = 7, dy = 3, side = "W", sprite = "" },
                { dx = 7, dy = 4, side = "W", sprite = "" },
                { dx = 9, dy = 1, side = "W", sprite = "" },
                { dx = 9, dy = 2, side = "W", sprite = "" },
                { dx = 9, dy = 3, side = "W", sprite = "" },
                { dx = 9, dy = 4, side = "W", sprite = "" },
                { dx = 11, dy = 1, side = "W", sprite = "" },
                { dx = 11, dy = 2, side = "W", sprite = "" },
                { dx = 11, dy = 3, side = "W", sprite = "" },
                { dx = 11, dy = 4, side = "W", sprite = "" },
            },
            lamps = { { dx = 3, dy = 0 }, { dx = 8, dy = 0 }, { dx = 6, dy = 3 }, { dx = 1, dy = 3 }, { dx = 3, dy = 3 }, { dx = 7, dy = 3 }, { dx = 9, dy = 3 } },
            fittings = {
                { dx = 1, dy = 4, sprite = "trains_02_73" },
                { dx = 2, dy = 4, sprite = "trains_02_74" },
                { dx = 2, dy = 1, sprite = "trains_02_75" },
                { dx = 3, dy = 4, sprite = "trains_02_73" },
                { dx = 4, dy = 4, sprite = "trains_02_74" },
                { dx = 4, dy = 1, sprite = "trains_02_75" },
                { dx = 7, dy = 4, sprite = "trains_02_73" },
                { dx = 8, dy = 4, sprite = "trains_02_74" },
                { dx = 8, dy = 1, sprite = "trains_02_75" },
                { dx = 9, dy = 4, sprite = "trains_02_73" },
                { dx = 10, dy = 4, sprite = "trains_02_74" },
                { dx = 10, dy = 1, sprite = "trains_02_75" },
                { dx = 6, dy = 1, sprite = "fixtures_sinks_01_2", water = true },
                { dx = 6, dy = 3, sprite = "fixtures_bathroom_01_33", water = true },
                { dx = 6, dy = 4, sprite = "fixtures_bathroom_01_3", water = true },
            },
        },
        galley = {
            base = { W = "walls_interior_bathroom_01_16", N = "walls_interior_bathroom_01_17", doorW = "walls_interior_bathroom_01_26", doorN = "walls_interior_bathroom_01_27" },
            floor = { { "floors_interior_tilesandwood_01_1" } },
            aisle = { "floors_interior_tilesandwood_01_1" },
            wallN = { "trains_02_90", "trains_02_91", "trains_02_90", "trains_02_91", "", "trains_02_97", "trains_02_91", "trains_02_90", "trains_02_91", "trains_02_90", "trains_02_91", "trains_02_90" },
            wallW = { "", "", "trains_02_94", "", "" },
            power = { dx = 8, dy = 2 },
            lamps = { { dx = 3, dy = 2 }, { dx = 8, dy = 2 } },
            fittings = {
                { dx = 1, dy = 0, sprite = "trains_02_89", stock = "dry" },
                { dx = 2, dy = 0, sprite = "appliances_refrigeration_01_22", stock = "cold" },
                { dx = 3, dy = 0, sprite = "fixtures_sinks_01_5", water = true },
                { dx = 4, dy = 0, sprite = "fixtures_counters_01_37", stock = "wares" },
                { dx = 6, dy = 0, sprite = "appliances_cooking_01_21", stove = true, stock = "pots" },
                { dx = 7, dy = 0, sprite = "appliances_cooking_01_21", stove = true },
                { dx = 8, dy = 0, sprite = "trains_02_87" },
                { dx = 9, dy = 0, sprite = "trains_02_88" },
                { dx = 10, dy = 0, sprite = "trains_02_89", stock = "cans" },
                { dx = 1, dy = 4, sprite = "trains_02_85", stock = "tools" },
                { dx = 2, dy = 4, sprite = "trains_02_86" },
                { dx = 7, dy = 4, sprite = "trains_02_85", stock = "drinks" },
                { dx = 8, dy = 4, sprite = "trains_02_86" },
            },
        },
        coach = {
            base = { W = "walls_interior_house_04_16", N = "walls_interior_house_04_17", doorW = "walls_interior_house_04_26", doorN = "walls_interior_house_04_27" },
            floor = { { "floors_interior_tilesandwood_01_18" } },
            aisle = { "floors_interior_carpet_01_2" },
            wallN = { "trains_02_90", "trains_02_91", "trains_02_90", "trains_02_91", "", "trains_02_97", "trains_02_91", "trains_02_90", "trains_02_91", "trains_02_90", "trains_02_91", "trains_02_90" },
            wallW = { "", "", "trains_02_94", "", "" },
            fittings = {
                { dx = 1, dy = 0, sprite = "trains_02_14" },
                { dx = 1, dy = 1, sprite = "trains_02_15" },
                { dx = 3, dy = 0, sprite = "trains_02_16" },
                { dx = 3, dy = 1, sprite = "trains_02_17" },
                { dx = 4, dy = 0, sprite = "trains_02_14" },
                { dx = 4, dy = 1, sprite = "trains_02_15" },
                { dx = 6, dy = 0, sprite = "trains_02_16" },
                { dx = 6, dy = 1, sprite = "trains_02_17" },
                { dx = 7, dy = 0, sprite = "trains_02_14" },
                { dx = 7, dy = 1, sprite = "trains_02_15" },
                { dx = 9, dy = 0, sprite = "trains_02_16" },
                { dx = 9, dy = 1, sprite = "trains_02_17" },
                { dx = 10, dy = 0, sprite = "trains_02_14" },
                { dx = 10, dy = 1, sprite = "trains_02_15" },
                { dx = 1, dy = 3, sprite = "trains_02_14" },
                { dx = 1, dy = 4, sprite = "trains_02_15" },
                { dx = 3, dy = 3, sprite = "trains_02_16" },
                { dx = 3, dy = 4, sprite = "trains_02_17" },
                { dx = 4, dy = 3, sprite = "trains_02_14" },
                { dx = 4, dy = 4, sprite = "trains_02_15" },
                { dx = 6, dy = 3, sprite = "trains_02_16" },
                { dx = 6, dy = 4, sprite = "trains_02_17" },
                { dx = 7, dy = 3, sprite = "trains_02_14" },
                { dx = 7, dy = 4, sprite = "trains_02_15" },
                { dx = 9, dy = 3, sprite = "trains_02_16" },
                { dx = 9, dy = 4, sprite = "trains_02_17" },
                { dx = 10, dy = 3, sprite = "trains_02_14" },
                { dx = 10, dy = 4, sprite = "trains_02_15" },
                { dx = 0, dy = 0, sprite = "trains_02_18" },
                { dx = 1, dy = 0, sprite = "trains_02_19" },
                { dx = 2, dy = 0, sprite = "trains_02_18" },
                { dx = 3, dy = 0, sprite = "trains_02_19" },
                { dx = 6, dy = 0, sprite = "trains_02_18" },
                { dx = 7, dy = 0, sprite = "trains_02_19" },
                { dx = 8, dy = 0, sprite = "trains_02_18" },
                { dx = 9, dy = 0, sprite = "trains_02_19" },
                { dx = 10, dy = 0, sprite = "trains_02_18" },
                { dx = 11, dy = 0, sprite = "trains_02_19" },
            },
        },
        commuter = {
            base = { W = "walls_interior_house_01_16", N = "walls_interior_house_01_17", doorW = "walls_interior_house_01_26", doorN = "walls_interior_house_01_27" },
            floor = { { "floors_interior_tilesandwood_01_16" } },
            aisle = { "floors_interior_carpet_01_0" },
            wallN = { "trains_02_92", "trains_02_93", "trains_02_92", "trains_02_93", "", "trains_02_97", "trains_02_93", "trains_02_92", "trains_02_93", "trains_02_92", "trains_02_93", "trains_02_92" },
            wallW = { "", "", "trains_02_95", "", "" },
            fittings = {
                { dx = 1, dy = 0, sprite = "trains_02_34" },
                { dx = 1, dy = 1, sprite = "trains_02_35" },
                { dx = 3, dy = 0, sprite = "trains_02_36" },
                { dx = 3, dy = 1, sprite = "trains_02_37" },
                { dx = 4, dy = 0, sprite = "trains_02_34" },
                { dx = 4, dy = 1, sprite = "trains_02_35" },
                { dx = 6, dy = 0, sprite = "trains_02_36" },
                { dx = 6, dy = 1, sprite = "trains_02_37" },
                { dx = 7, dy = 0, sprite = "trains_02_34" },
                { dx = 7, dy = 1, sprite = "trains_02_35" },
                { dx = 9, dy = 0, sprite = "trains_02_36" },
                { dx = 9, dy = 1, sprite = "trains_02_37" },
                { dx = 10, dy = 0, sprite = "trains_02_34" },
                { dx = 10, dy = 1, sprite = "trains_02_35" },
                { dx = 1, dy = 3, sprite = "trains_02_34" },
                { dx = 1, dy = 4, sprite = "trains_02_35" },
                { dx = 3, dy = 3, sprite = "trains_02_36" },
                { dx = 3, dy = 4, sprite = "trains_02_37" },
                { dx = 4, dy = 3, sprite = "trains_02_34" },
                { dx = 4, dy = 4, sprite = "trains_02_35" },
                { dx = 6, dy = 3, sprite = "trains_02_36" },
                { dx = 6, dy = 4, sprite = "trains_02_37" },
                { dx = 7, dy = 3, sprite = "trains_02_34" },
                { dx = 7, dy = 4, sprite = "trains_02_35" },
                { dx = 9, dy = 3, sprite = "trains_02_36" },
                { dx = 9, dy = 4, sprite = "trains_02_37" },
                { dx = 10, dy = 3, sprite = "trains_02_34" },
                { dx = 10, dy = 4, sprite = "trains_02_35" },
                { dx = 0, dy = 0, sprite = "trains_02_18" },
                { dx = 1, dy = 0, sprite = "trains_02_19" },
                { dx = 2, dy = 0, sprite = "trains_02_18" },
                { dx = 3, dy = 0, sprite = "trains_02_19" },
                { dx = 6, dy = 0, sprite = "trains_02_18" },
                { dx = 7, dy = 0, sprite = "trains_02_19" },
                { dx = 8, dy = 0, sprite = "trains_02_18" },
                { dx = 9, dy = 0, sprite = "trains_02_19" },
                { dx = 10, dy = 0, sprite = "trains_02_18" },
                { dx = 11, dy = 0, sprite = "trains_02_19" },
            },
        },
        box = {
            base = { W = "industry_01_0", N = "industry_01_1", doorW = "industry_01_10", doorN = "industry_01_11" },
            floor = { { "trains_01_11" } },
            aisle = { "trains_01_11" },
            wallN = { "trains_01_12", "trains_01_12", "trains_01_12", "trains_01_12", "trains_01_12", "trains_01_15", "trains_01_12", "trains_01_12", "trains_01_12", "trains_01_12", "trains_01_12", "trains_01_12" },
            wallW = { "trains_01_13", "trains_01_13", "trains_01_14", "trains_01_13", "trains_01_13" },
            fittings = {},
        },
        loco = {
            base = { W = "industry_01_0", N = "industry_01_1", doorW = "industry_01_10", doorN = "industry_01_11" },
            floor = { { "floors_interior_tilesandwood_01_28" } },
            aisle = { "floors_interior_tilesandwood_01_28" },
            wallN = { "", "", "", "", "", "trains_02_97", "", "", "", "", "", "" },
            wallW = { "", "", "trains_02_96", "", "" },
            fittings = {
                { dx = 0, dy = 0, sprite = "trains_02_50" },
                { dx = 0, dy = 1, sprite = "trains_02_51" },
                { dx = 1, dy = 0, sprite = "trains_02_52" },
                { dx = 1, dy = 1, sprite = "trains_02_52" },
                { dx = 3, dy = 0, sprite = "trains_02_53" },
                { dx = 6, dy = 0, sprite = "trains_02_54" },
                { dx = 7, dy = 0, sprite = "trains_02_55" },
                { dx = 8, dy = 0, sprite = "trains_02_56" },
                { dx = 9, dy = 0, sprite = "trains_02_57" },
                { dx = 6, dy = 1, sprite = "trains_02_58" },
                { dx = 7, dy = 1, sprite = "trains_02_59" },
                { dx = 8, dy = 1, sprite = "trains_02_60" },
                { dx = 9, dy = 1, sprite = "trains_02_61" },
            },
        },
        warehouse = {
            base = { W = "industry_railroad_05_8", N = "industry_railroad_05_9", doorW = "industry_railroad_05_18", doorN = "industry_railroad_05_19" },
            floor = { { "industry_railroad_05_22" } },
            aisle = { "industry_railroad_05_22" },
            wallN = { "", "", "", "", "", "trains_02_97", "", "", "", "", "", "" },
            wallW = { "", "", "trains_02_96", "", "" },
            lamps = { { dx = 3, dy = 2 }, { dx = 8, dy = 2 } },
            fittings = {
                { dx = 1, dy = 0, sprite = "furniture_shelving_01_26", stock = "hardware" },
                { dx = 2, dy = 0, sprite = "furniture_shelving_01_27", stock = "mechanic" },
                { dx = 3, dy = 0, sprite = "furniture_shelving_01_26", stock = "cans" },
                { dx = 4, dy = 0, sprite = "furniture_shelving_01_27", stock = "dry" },
                { dx = 6, dy = 0, sprite = "furniture_shelving_01_26", stock = "gear" },
                { dx = 7, dy = 0, sprite = "furniture_shelving_01_27", stock = "electrics" },
                { dx = 8, dy = 0, sprite = "furniture_shelving_01_26", stock = "larder" },
                { dx = 9, dy = 0, sprite = "furniture_shelving_01_27", stock = "linen" },
                { dx = 10, dy = 0, sprite = "location_military_generic_01_0", stock = "cans" },
                { dx = 1, dy = 3, sprite = "carpentry_01_19", stock = "medicine" },
                { dx = 10, dy = 3, sprite = "industry_01_23" },
                { dx = 1, dy = 4, sprite = "carpentry_01_16", stock = "lumber" },
                { dx = 2, dy = 4, sprite = "carpentry_01_19", stock = "fabric" },
                { dx = 3, dy = 4, sprite = "carpentry_01_16", stock = "lumber" },
                { dx = 7, dy = 4, sprite = "constructedobjects_01_44", stock = "metalwork" },
                { dx = 8, dy = 4, sprite = "constructedobjects_01_44", stock = "fuel" },
                { dx = 9, dy = 4, sprite = "furniture_storage_02_16", stock = "clothes" },
                { dx = 10, dy = 4, sprite = "furniture_storage_02_17", stock = "drinks" },
            },
        },
        dining = {
            base = { W = "walls_interior_house_03_32", N = "walls_interior_house_03_33", doorW = "walls_interior_house_03_42", doorN = "walls_interior_house_03_43" },
            floor = { { "floors_interior_tilesandwood_01_44" } },
            aisle = { "floors_interior_carpet_01_9" },
            wallN = { "trains_02_92", "trains_02_93", "trains_02_92", "trains_02_93", "", "trains_02_97", "trains_02_93", "trains_02_92", "trains_02_93", "trains_02_92", "trains_02_93", "trains_02_92" },
            wallW = { "", "", "trains_02_95", "", "" },
            lamps = { { dx = 3, dy = 2 }, { dx = 8, dy = 2 } },
            fittings = {
                { dx = 1, dy = 0, sprite = "location_restaurant_diner_01_35" },
                { dx = 1, dy = 1, sprite = "location_restaurant_diner_01_34" },
                { dx = 2, dy = 0, sprite = "location_restaurant_diner_01_15" },
                { dx = 2, dy = 1, sprite = "location_restaurant_diner_01_14" },
                { dx = 3, dy = 0, sprite = "location_restaurant_diner_01_39" },
                { dx = 3, dy = 1, sprite = "location_restaurant_diner_01_38" },
                { dx = 4, dy = 0, sprite = "location_restaurant_diner_01_35" },
                { dx = 4, dy = 1, sprite = "location_restaurant_diner_01_34" },
                { dx = 5, dy = 0, sprite = "location_restaurant_diner_01_15" },
                { dx = 5, dy = 1, sprite = "location_restaurant_diner_01_14" },
                { dx = 6, dy = 0, sprite = "location_restaurant_diner_01_39" },
                { dx = 6, dy = 1, sprite = "location_restaurant_diner_01_38" },
                { dx = 8, dy = 0, sprite = "location_restaurant_diner_01_35" },
                { dx = 8, dy = 1, sprite = "location_restaurant_diner_01_34" },
                { dx = 9, dy = 0, sprite = "location_restaurant_diner_01_15" },
                { dx = 9, dy = 1, sprite = "location_restaurant_diner_01_14" },
                { dx = 10, dy = 0, sprite = "location_restaurant_diner_01_39" },
                { dx = 10, dy = 1, sprite = "location_restaurant_diner_01_38" },
                { dx = 1, dy = 3, sprite = "location_restaurant_diner_01_35" },
                { dx = 1, dy = 4, sprite = "location_restaurant_diner_01_34" },
                { dx = 2, dy = 3, sprite = "location_restaurant_diner_01_15" },
                { dx = 2, dy = 4, sprite = "location_restaurant_diner_01_14" },
                { dx = 3, dy = 3, sprite = "location_restaurant_diner_01_39" },
                { dx = 3, dy = 4, sprite = "location_restaurant_diner_01_38" },
                { dx = 7, dy = 3, sprite = "location_restaurant_diner_01_35" },
                { dx = 7, dy = 4, sprite = "location_restaurant_diner_01_34" },
                { dx = 8, dy = 3, sprite = "location_restaurant_diner_01_15" },
                { dx = 8, dy = 4, sprite = "location_restaurant_diner_01_14" },
                { dx = 9, dy = 3, sprite = "location_restaurant_diner_01_39" },
                { dx = 9, dy = 4, sprite = "location_restaurant_diner_01_38" },
                { dx = 10, dy = 4, sprite = "location_restaurant_seahorse_01_62", stock = "table" },
                { dx = 11, dy = 4, sprite = "location_restaurant_seahorse_01_63", stock = "sweets" },
            },
        },
        lounge = {
            base = { W = "location_restaurant_bar_01_44", N = "location_restaurant_bar_01_45", doorW = "location_restaurant_bar_01_54", doorN = "location_restaurant_bar_01_55" },
            floor = { { "location_restaurant_bar_01_24" } },
            aisle = { "location_restaurant_bar_01_24" },
            wallN = { "trains_02_92", "trains_02_93", "trains_02_92", "trains_02_93", "", "trains_02_97", "trains_02_93", "trains_02_92", "trains_02_93", "trains_02_92", "trains_02_93", "trains_02_92" },
            wallW = { "", "", "trains_02_95", "", "" },
            lamps = { { dx = 3, dy = 2 }, { dx = 8, dy = 2 } },
            fittings = {
                { dx = 1, dy = 0, sprite = "location_restaurant_bar_01_64", stock = "liquor" },
                { dx = 2, dy = 0, sprite = "location_restaurant_bar_01_65", stock = "liquor" },
                { dx = 3, dy = 0, sprite = "location_restaurant_bar_01_65", stock = "glasses" },
                { dx = 4, dy = 0, sprite = "location_restaurant_bar_01_66", stock = "liquor" },
                { dx = 1, dy = 1, sprite = "location_restaurant_bar_01_21", stock = "drinks" },
                { dx = 2, dy = 1, sprite = "location_restaurant_bar_01_21", stock = "snacks" },
                { dx = 3, dy = 1, sprite = "location_restaurant_bar_01_21", stock = "parlor" },
                { dx = 4, dy = 1, sprite = "location_restaurant_bar_01_21", stock = "wares" },
                { dx = 5, dy = 0, sprite = "recreational_01_1" },
                { dx = 6, dy = 1, sprite = "location_restaurant_bar_01_26" },
                { dx = 7, dy = 1, sprite = "furniture_tables_high_01_23" },
                { dx = 8, dy = 1, sprite = "location_restaurant_bar_01_26" },
                { dx = 8, dy = 0, sprite = "appliances_television_01_9", tv = "Base.TvAntique" },
                { dx = 9, dy = 0, sprite = "recreational_01_16" },
                { dx = 10, dy = 0, sprite = "recreational_01_25" },
                { dx = 10, dy = 1, sprite = "recreational_01_24" },
                { dx = 1, dy = 4, sprite = "location_restaurant_bar_01_8" },
                { dx = 2, dy = 4, sprite = "location_restaurant_bar_01_9" },
                { dx = 3, dy = 4, sprite = "lighting_indoor_02_68" },
                { dx = 7, dy = 3, sprite = "furniture_tables_low_01_8" },
                { dx = 8, dy = 3, sprite = "furniture_tables_low_01_9" },
                { dx = 7, dy = 4, sprite = "location_restaurant_bar_01_8" },
                { dx = 8, dy = 4, sprite = "location_restaurant_bar_01_9" },
                { dx = 6, dy = 3, sprite = "furniture_seating_indoor_03_40" },
                { dx = 9, dy = 3, sprite = "furniture_seating_indoor_03_42" },
                { dx = 10, dy = 4, sprite = "lighting_indoor_02_64" },
            },
        },
        dorm = {
            base = { W = "walls_interior_house_04_16", N = "walls_interior_house_04_17", doorW = "walls_interior_house_04_26", doorN = "walls_interior_house_04_27" },
            inner = { W = "walls_interior_house_03_32", N = "walls_interior_house_03_33", doorW = "walls_interior_house_03_42", doorN = "walls_interior_house_03_43" },
            floor = { { "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_tilesandwood_01_5", "floors_interior_tilesandwood_01_5" }, { "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_tilesandwood_01_5", "floors_interior_tilesandwood_01_5" }, { "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3" }, { "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3" }, { "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3", "floors_interior_carpet_01_3" } },
            aisle = { "floors_interior_carpet_01_2" },
            wallN = { "trains_02_90", "trains_02_91", "trains_02_90", "trains_02_91", "", "trains_02_97", "trains_02_91", "trains_02_90", "trains_02_91", "trains_02_90", "trains_02_91", "trains_02_90" },
            wallW = { "", "", "trains_02_94", "", "" },
            walls = {
                { dx = 10, dy = 0, side = "W", sprite = "" },
                { dx = 10, dy = 1, side = "W", sprite = "" },
                { dx = 10, dy = 2, side = "N", sprite = "", door = true },
                { dx = 11, dy = 2, side = "N", sprite = "" },
            },
            lamps = { { dx = 3, dy = 2 }, { dx = 8, dy = 2 }, { dx = 10, dy = 0 } },
            fittings = {
                { dx = 1, dy = 0, sprite = "furniture_bedding_01_85" },
                { dx = 1, dy = 1, sprite = "furniture_bedding_01_84" },
                { dx = 2, dy = 0, sprite = "furniture_storage_02_5", stock = "kit" },
                { dx = 3, dy = 0, sprite = "furniture_bedding_01_85" },
                { dx = 3, dy = 1, sprite = "furniture_bedding_01_84" },
                { dx = 4, dy = 0, sprite = "furniture_storage_02_5", stock = "clothes" },
                { dx = 5, dy = 0, sprite = "furniture_bedding_01_85" },
                { dx = 5, dy = 1, sprite = "furniture_bedding_01_84" },
                { dx = 6, dy = 0, sprite = "furniture_storage_02_5", stock = "kit" },
                { dx = 7, dy = 0, sprite = "furniture_bedding_01_85" },
                { dx = 7, dy = 1, sprite = "furniture_bedding_01_84" },
                { dx = 8, dy = 0, sprite = "furniture_storage_02_5", stock = "linen" },
                { dx = 1, dy = 4, sprite = "trains_02_73" },
                { dx = 2, dy = 4, sprite = "trains_02_74" },
                { dx = 3, dy = 4, sprite = "trains_02_73" },
                { dx = 4, dy = 4, sprite = "trains_02_74" },
                { dx = 6, dy = 4, sprite = "trains_02_73" },
                { dx = 7, dy = 4, sprite = "trains_02_74" },
                { dx = 8, dy = 4, sprite = "trains_02_73" },
                { dx = 9, dy = 4, sprite = "trains_02_74" },
                { dx = 10, dy = 4, sprite = "location_military_generic_01_0", stock = "gear" },
                { dx = 10, dy = 0, sprite = "fixtures_bathroom_01_0", water = true },
                { dx = 10, dy = 1, sprite = "fixtures_sinks_01_1", water = true },
                { dx = 11, dy = 0, sprite = "fixtures_bathroom_01_32", water = true },
            },
        },
        workshop = {
            base = { W = "industry_01_0", N = "industry_01_1", doorW = "industry_01_10", doorN = "industry_01_11" },
            floor = { { "floors_interior_tilesandwood_01_28" } },
            aisle = { "floors_interior_tilesandwood_01_28" },
            wallN = { "", "location_business_machinery_01_24", "location_business_machinery_01_25", "", "", "trains_02_97", "location_business_machinery_01_24", "location_business_machinery_01_25", "", "", "", "" },
            wallW = { "", "", "trains_02_96", "", "" },
            lamps = { { dx = 3, dy = 2 }, { dx = 8, dy = 2 } },
            fittings = {
                { dx = 1, dy = 0, sprite = "location_business_machinery_01_16" },
                { dx = 2, dy = 0, sprite = "location_business_machinery_01_17" },
                { dx = 3, dy = 0, sprite = "location_business_machinery_01_32", stock = "mechanic" },
                { dx = 4, dy = 0, sprite = "crafted_01_18" },
                { dx = 6, dy = 0, sprite = "location_business_machinery_01_16" },
                { dx = 7, dy = 0, sprite = "location_business_machinery_01_17" },
                { dx = 8, dy = 0, sprite = "location_business_machinery_01_32", stock = "gear" },
                { dx = 9, dy = 0, sprite = "furniture_shelving_01_26", stock = "hardware" },
                { dx = 10, dy = 0, sprite = "furniture_shelving_01_27", stock = "parts" },
                { dx = 1, dy = 4, sprite = "location_business_machinery_01_20" },
                { dx = 2, dy = 4, sprite = "location_business_machinery_01_21" },
                { dx = 3, dy = 4, sprite = "location_business_machinery_01_44" },
                { dx = 7, dy = 4, sprite = "constructedobjects_01_44", stock = "metalwork" },
                { dx = 8, dy = 4, sprite = "constructedobjects_01_44", stock = "lumber" },
                { dx = 9, dy = 4, sprite = "industry_01_22" },
                { dx = 10, dy = 4, sprite = "location_business_machinery_01_34", stock = "electrics" },
            },
        },
        armory = {
            base = { W = "industry_01_0", N = "industry_01_1", doorW = "industry_01_10", doorN = "industry_01_11" },
            inner = { W = "location_community_police_01_0", N = "location_community_police_01_1", doorW = "location_community_police_01_10", doorN = "location_community_police_01_11" },
            floor = { { "floors_interior_tilesandwood_01_28" } },
            aisle = { "floors_interior_tilesandwood_01_28" },
            wallN = { "", "", "", "", "", "trains_02_97", "", "", "", "", "", "" },
            wallW = { "", "", "trains_02_96", "", "" },
            walls = {
                { dx = 8, dy = 2, side = "N", sprite = "" },
                { dx = 9, dy = 2, side = "N", sprite = "", door = true },
                { dx = 10, dy = 2, side = "N", sprite = "" },
                { dx = 11, dy = 2, side = "N", sprite = "", door = true },
                { dx = 8, dy = 0, side = "W", sprite = "" },
                { dx = 8, dy = 1, side = "W", sprite = "" },
                { dx = 10, dy = 0, side = "W", sprite = "" },
                { dx = 10, dy = 1, side = "W", sprite = "" },
            },
            lamps = { { dx = 3, dy = 2 }, { dx = 8, dy = 3 }, { dx = 9, dy = 1 }, { dx = 11, dy = 1 } },
            fittings = {
                { dx = 1, dy = 0, sprite = "location_military_generic_01_22", stock = "rifles" },
                { dx = 2, dy = 0, sprite = "location_military_generic_01_22", stock = "sidearms" },
                { dx = 3, dy = 0, sprite = "location_military_generic_01_22", stock = "armor" },
                { dx = 4, dy = 0, sprite = "location_shop_generic_01_110" },
                { dx = 8, dy = 0, sprite = "location_community_police_01_25" },
                { dx = 8, dy = 1, sprite = "location_community_police_01_24" },
                { dx = 9, dy = 0, sprite = "fixtures_bathroom_01_4" },
                { dx = 10, dy = 0, sprite = "location_community_police_01_25" },
                { dx = 10, dy = 1, sprite = "location_community_police_01_24" },
                { dx = 11, dy = 0, sprite = "fixtures_bathroom_01_4" },
                { dx = 1, dy = 4, sprite = "location_military_generic_01_0", stock = "ammo" },
                { dx = 2, dy = 4, sprite = "location_military_generic_01_1", stock = "ammo" },
                { dx = 3, dy = 4, sprite = "location_military_generic_01_8", stock = "cans" },
                { dx = 7, dy = 4, sprite = "furniture_tables_high_01_30" },
                { dx = 8, dy = 4, sprite = "furniture_tables_high_01_31" },
                { dx = 7, dy = 3, sprite = "furniture_seating_indoor_02_0" },
                { dx = 10, dy = 4, sprite = "location_business_office_generic_01_24", stock = "stationery" },
            },
        },
        baggage = {
            base = { W = "industry_railroad_05_24", N = "industry_railroad_05_25", doorW = "industry_railroad_05_34", doorN = "industry_railroad_05_35" },
            floor = { { "industry_railroad_05_38" } },
            aisle = { "industry_railroad_05_38" },
            wallN = { "", "", "", "", "", "trains_02_97", "", "", "", "", "", "" },
            wallW = { "", "", "trains_02_96", "", "" },
            lamps = { { dx = 3, dy = 2 }, { dx = 8, dy = 2 } },
            fittings = {
                { dx = 1, dy = 0, sprite = "furniture_storage_02_16", stock = "parcels" },
                { dx = 2, dy = 0, sprite = "furniture_storage_02_17", stock = "travel" },
                { dx = 3, dy = 0, sprite = "carpentry_01_16", stock = "luggage" },
                { dx = 4, dy = 0, sprite = "carpentry_01_19", stock = "clothes" },
                { dx = 6, dy = 0, sprite = "furniture_storage_02_13", stock = "luggage" },
                { dx = 7, dy = 0, sprite = "furniture_storage_02_13", stock = "finery" },
                { dx = 8, dy = 0, sprite = "furniture_shelving_01_26", stock = "luggage" },
                { dx = 9, dy = 0, sprite = "furniture_shelving_01_27", stock = "travel" },
                { dx = 10, dy = 0, sprite = "furniture_storage_02_18", stock = "keepsakes" },
                { dx = 1, dy = 4, sprite = "carpentry_01_16", stock = "luggage" },
                { dx = 2, dy = 4, sprite = "furniture_storage_02_24", stock = "parlor" },
                { dx = 3, dy = 4, sprite = "furniture_storage_02_25", stock = "study" },
                { dx = 7, dy = 4, sprite = "carpentry_02_104", stock = "travel" },
                { dx = 8, dy = 4, sprite = "carpentry_01_19", stock = "clothes" },
                { dx = 9, dy = 4, sprite = "furniture_storage_02_26", stock = "parcels" },
                { dx = 10, dy = 4, sprite = "furniture_storage_02_27", stock = "keepsakes" },
            },
        },
        mail = {
            base = { W = "walls_interior_house_04_16", N = "walls_interior_house_04_17", doorW = "walls_interior_house_04_26", doorN = "walls_interior_house_04_27" },
            floor = { { "floors_interior_tilesandwood_01_18" } },
            aisle = { "floors_interior_tilesandwood_01_18" },
            wallN = { "trains_02_90", "trains_02_91", "trains_02_90", "trains_02_91", "", "trains_02_97", "trains_02_91", "trains_02_90", "trains_02_91", "trains_02_90", "trains_02_91", "trains_02_90" },
            wallW = { "", "", "trains_02_94", "", "" },
            lamps = { { dx = 3, dy = 2 }, { dx = 8, dy = 2 } },
            fittings = {
                { dx = 1, dy = 0, sprite = "furniture_shelving_01_16", stock = "mail" },
                { dx = 2, dy = 0, sprite = "furniture_shelving_01_17", stock = "mail" },
                { dx = 3, dy = 0, sprite = "furniture_shelving_01_18", stock = "stationery" },
                { dx = 4, dy = 0, sprite = "street_decoration_01_8", stock = "mail" },
                { dx = 6, dy = 0, sprite = "furniture_tables_high_01_52" },
                { dx = 7, dy = 0, sprite = "furniture_tables_high_01_53" },
                { dx = 6, dy = 1, sprite = "furniture_seating_indoor_02_2" },
                { dx = 8, dy = 0, sprite = "location_business_office_generic_01_16", stock = "stationery" },
                { dx = 9, dy = 0, sprite = "location_business_office_generic_01_16", stock = "study" },
                { dx = 10, dy = 0, sprite = "location_business_bank_01_69" },
                { dx = 1, dy = 4, sprite = "furniture_storage_02_24", stock = "parcels" },
                { dx = 2, dy = 4, sprite = "furniture_storage_02_25", stock = "parcels" },
                { dx = 3, dy = 4, sprite = "carpentry_01_16", stock = "parcels" },
                { dx = 7, dy = 4, sprite = "location_business_office_generic_01_24", stock = "mail" },
                { dx = 8, dy = 4, sprite = "location_business_office_generic_01_24", stock = "stationery" },
                { dx = 9, dy = 4, sprite = "furniture_storage_02_26", stock = "parcels" },
                { dx = 10, dy = 4, sprite = "location_business_bank_01_71" },
            },
        },
        caboose = {
            base = { W = "location_barn_01_0", N = "location_barn_01_1", doorW = "location_barn_01_10", doorN = "location_barn_01_11" },
            floor = { { "floors_interior_tilesandwood_01_42" } },
            aisle = { "floors_interior_tilesandwood_01_42" },
            wallN = { "trains_02_90", "trains_02_91", "trains_02_90", "trains_02_91", "", "trains_02_97", "trains_02_91", "trains_02_90", "trains_02_91", "trains_02_90", "trains_02_91", "trains_02_90" },
            wallW = { "", "", "trains_02_94", "", "" },
            lamps = { { dx = 3, dy = 2 }, { dx = 8, dy = 2 } },
            fittings = {
                { dx = 1, dy = 0, sprite = "appliances_cooking_01_17" },
                { dx = 3, dy = 0, sprite = "furniture_tables_high_01_26" },
                { dx = 4, dy = 0, sprite = "furniture_tables_high_01_27" },
                { dx = 3, dy = 1, sprite = "furniture_seating_indoor_02_2" },
                { dx = 6, dy = 0, sprite = "carpentry_01_16", stock = "crew" },
                { dx = 7, dy = 0, sprite = "furniture_bedding_01_85" },
                { dx = 7, dy = 1, sprite = "furniture_bedding_01_84" },
                { dx = 8, dy = 0, sprite = "furniture_storage_02_5", stock = "kit" },
                { dx = 9, dy = 0, sprite = "furniture_bedding_01_85" },
                { dx = 9, dy = 1, sprite = "furniture_bedding_01_84" },
                { dx = 10, dy = 0, sprite = "carpentry_01_19", stock = "larder" },
                { dx = 1, dy = 4, sprite = "carpentry_01_16", stock = "gear" },
                { dx = 2, dy = 4, sprite = "industry_01_22" },
                { dx = 7, dy = 3, sprite = "trains_02_14" },
                { dx = 7, dy = 4, sprite = "trains_02_15" },
                { dx = 8, dy = 4, sprite = "furniture_tables_high_01_14" },
                { dx = 9, dy = 3, sprite = "trains_02_16" },
                { dx = 9, dy = 4, sprite = "trains_02_17" },
            },
        },
        reefer = {
            base = { W = "walls_interior_bathroom_01_16", N = "walls_interior_bathroom_01_17", doorW = "walls_interior_bathroom_01_26", doorN = "walls_interior_bathroom_01_27" },
            floor = { { "floors_interior_tilesandwood_01_5" } },
            aisle = { "floors_interior_tilesandwood_01_5" },
            wallN = { "", "", "", "", "", "trains_02_97", "", "", "", "", "", "" },
            wallW = { "", "", "trains_02_94", "", "" },
            lamps = { { dx = 3, dy = 2 }, { dx = 8, dy = 2 } },
            fittings = {
                { dx = 1, dy = 0, sprite = "appliances_refrigeration_01_18", stock = "meat" },
                { dx = 2, dy = 0, sprite = "appliances_refrigeration_01_19", stock = "meat" },
                { dx = 3, dy = 0, sprite = "appliances_refrigeration_01_22", stock = "fish" },
                { dx = 4, dy = 0, sprite = "appliances_refrigeration_01_22", stock = "dairy" },
                { dx = 6, dy = 0, sprite = "appliances_refrigeration_01_40", stock = "frozen" },
                { dx = 7, dy = 0, sprite = "appliances_refrigeration_01_40", stock = "cold" },
                { dx = 8, dy = 0, sprite = "location_shop_generic_01_64", stock = "produce" },
                { dx = 9, dy = 0, sprite = "location_shop_generic_01_65", stock = "dairy" },
                { dx = 10, dy = 0, sprite = "location_shop_generic_01_66", stock = "drinks" },
                { dx = 1, dy = 4, sprite = "appliances_refrigeration_01_50" },
                { dx = 2, dy = 4, sprite = "appliances_refrigeration_01_50" },
                { dx = 7, dy = 4, sprite = "appliances_refrigeration_01_50" },
                { dx = 8, dy = 4, sprite = "appliances_refrigeration_01_50" },
                { dx = 9, dy = 4, sprite = "appliances_refrigeration_01_50" },
            },
        },
        greenhouse = {
            base = { W = "walls_interior_house_01_0", N = "walls_interior_house_01_1", doorW = "walls_interior_house_01_10", doorN = "walls_interior_house_01_11" },
            floor = { { "floors_interior_tilesandwood_01_42", "blends_natural_01_64", "blends_natural_01_64", "blends_natural_01_64", "blends_natural_01_64", "floors_interior_tilesandwood_01_42", "floors_interior_tilesandwood_01_42", "blends_natural_01_64", "blends_natural_01_64", "blends_natural_01_64", "blends_natural_01_64", "floors_interior_tilesandwood_01_42" }, { "floors_interior_tilesandwood_01_42", "blends_natural_01_64", "blends_natural_01_64", "blends_natural_01_64", "blends_natural_01_64", "floors_interior_tilesandwood_01_42", "floors_interior_tilesandwood_01_42", "blends_natural_01_64", "blends_natural_01_64", "blends_natural_01_64", "blends_natural_01_64", "floors_interior_tilesandwood_01_42" }, { "floors_interior_tilesandwood_01_42", "floors_interior_tilesandwood_01_42", "floors_interior_tilesandwood_01_42", "floors_interior_tilesandwood_01_42", "floors_interior_tilesandwood_01_42", "floors_interior_tilesandwood_01_42", "floors_interior_tilesandwood_01_42", "floors_interior_tilesandwood_01_42", "floors_interior_tilesandwood_01_42", "floors_interior_tilesandwood_01_42", "floors_interior_tilesandwood_01_42", "floors_interior_tilesandwood_01_42" }, { "floors_interior_tilesandwood_01_42", "floors_interior_tilesandwood_01_42", "floors_interior_tilesandwood_01_42", "floors_interior_tilesandwood_01_42", "floors_interior_tilesandwood_01_42", "floors_interior_tilesandwood_01_42", "floors_interior_tilesandwood_01_42", "floors_interior_tilesandwood_01_42", "floors_interior_tilesandwood_01_42", "floors_interior_tilesandwood_01_42", "floors_interior_tilesandwood_01_42", "floors_interior_tilesandwood_01_42" }, { "floors_interior_tilesandwood_01_42", "blends_natural_01_64", "blends_natural_01_64", "blends_natural_01_64", "floors_interior_tilesandwood_01_42", "floors_interior_tilesandwood_01_42", "floors_interior_tilesandwood_01_42", "blends_natural_01_64", "blends_natural_01_64", "floors_interior_tilesandwood_01_42", "floors_interior_tilesandwood_01_42", "floors_interior_tilesandwood_01_42" } },
            aisle = { "floors_interior_tilesandwood_01_42" },
            wallN = { "trains_02_92", "trains_02_93", "trains_02_92", "trains_02_93", "", "trains_02_97", "trains_02_93", "trains_02_92", "trains_02_93", "trains_02_92", "trains_02_93", "trains_02_92" },
            wallW = { "", "", "trains_02_95", "", "" },
            lamps = { { dx = 2, dy = 1 }, { dx = 8, dy = 1 }, { dx = 2, dy = 3 }, { dx = 8, dy = 3 } },
            fittings = {
                { dx = 6, dy = 0, sprite = "fixtures_sinks_01_5", water = true },
                { dx = 9, dy = 4, sprite = "carpentry_02_52", water = true },
                { dx = 10, dy = 4, sprite = "carpentry_02_52", water = true },
                { dx = 0, dy = 4, sprite = "carpentry_01_16", stock = "seeds" },
                { dx = 11, dy = 4, sprite = "carpentry_01_19", stock = "garden" },
                { dx = 0, dy = 0, sprite = "vegetation_indoor_01_11" },
                { dx = 11, dy = 0, sprite = "vegetation_indoor_01_10" },
            },
            soil = "blends_natural_01_64",
            was = { "vegetation_indoor_01_8", "vegetation_indoor_01_9", "vegetation_indoor_01_10", "vegetation_indoor_01_11", "vegetation_indoor_01_12" },
            crops = {
                { dx = 1, dy = 0, seed = "Tomato", stage = "ripe" },
                { dx = 2, dy = 0, seed = "Tomato", stage = "ripe" },
                { dx = 3, dy = 0, seed = "Tomato", stage = "young" },
                { dx = 4, dy = 0, seed = "Tomato", stage = "ripe" },
                { dx = 7, dy = 0, seed = "Potatoes", stage = "ripe" },
                { dx = 8, dy = 0, seed = "Potatoes", stage = "young" },
                { dx = 9, dy = 0, seed = "Carrots", stage = "ripe" },
                { dx = 10, dy = 0, seed = "Carrots", stage = "ripe" },
                { dx = 1, dy = 1, seed = "Cabbages", stage = "young" },
                { dx = 2, dy = 1, seed = "Cabbages", stage = "ripe" },
                { dx = 3, dy = 1, seed = "Broccoli", stage = "ripe" },
                { dx = 4, dy = 1, seed = "Broccoli", stage = "young" },
                { dx = 7, dy = 1, seed = "Strawberryplant", stage = "ripe" },
                { dx = 8, dy = 1, seed = "Strawberryplant", stage = "ripe" },
                { dx = 9, dy = 1, seed = "Lettuce", stage = "young" },
                { dx = 10, dy = 1, seed = "Lettuce", stage = "ripe" },
                { dx = 1, dy = 4, seed = "Radishes", stage = "ripe" },
                { dx = 2, dy = 4, seed = "Onion", stage = "young" },
                { dx = 3, dy = 4, seed = "BellPepper", stage = "ripe" },
                { dx = 7, dy = 4, seed = "Cucumber", stage = "ripe" },
                { dx = 8, dy = 4, seed = "Basil", stage = "young" },
            },
        },
        generator = {
            base = { W = "industry_01_0", N = "industry_01_1", doorW = "industry_01_10", doorN = "industry_01_11" },
            floor = { { "floors_interior_tilesandwood_01_28" } },
            aisle = { "industry_01_38" },
            wallN = { "", "", "", "", "", "trains_02_97", "", "", "", "", "", "" },
            wallW = { "", "", "trains_02_96", "", "" },
            lamps = { { dx = 3, dy = 2 }, { dx = 8, dy = 2 } },
            fittings = {
                { dx = 1, dy = 0, sprite = "industry_02_52" },
                { dx = 2, dy = 0, sprite = "industry_02_54" },
                { dx = 3, dy = 0, sprite = "industry_02_52" },
                { dx = 4, dy = 0, sprite = "industry_02_54" },
                { dx = 6, dy = 0, sprite = "industry_02_52" },
                { dx = 7, dy = 0, sprite = "industry_02_54" },
                { dx = 8, dy = 0, sprite = "industry_02_62" },
                { dx = 9, dy = 0, sprite = "furniture_shelving_01_26", stock = "fuel" },
                { dx = 10, dy = 0, sprite = "furniture_shelving_01_27", stock = "electrics" },
                { dx = 1, dy = 4, sprite = "industry_01_22" },
                { dx = 2, dy = 4, sprite = "industry_01_22" },
                { dx = 3, dy = 4, sprite = "location_military_generic_01_6" },
                { dx = 7, dy = 4, sprite = "location_military_generic_01_14" },
                { dx = 8, dy = 4, sprite = "industry_01_22" },
                { dx = 9, dy = 4, sprite = "constructedobjects_01_44", stock = "parts" },
                { dx = 10, dy = 4, sprite = "constructedobjects_01_44", stock = "mechanic" },
            },
        },
        livestock = {
            base = { W = "location_barn_01_0", N = "location_barn_01_1", doorW = "location_barn_01_10", doorN = "location_barn_01_11" },
            floor = { { "vegetation_farm_01_12", "vegetation_farm_01_13" } },
            aisle = { "floors_interior_tilesandwood_01_42" },
            wallN = { "", "", "", "", "", "trains_02_97", "", "", "", "", "", "" },
            wallW = { "", "", "trains_02_94", "", "" },
            lamps = { { dx = 3, dy = 2 }, { dx = 8, dy = 2 } },
            fittings = {
                { dx = 1, dy = 0, sprite = "vegetation_farm_01_10" },
                { dx = 2, dy = 0, sprite = "vegetation_farm_01_8" },
                { dx = 3, dy = 0, sprite = "vegetation_farm_01_9" },
                { dx = 4, dy = 0, sprite = "location_farm_accesories_01_12" },
                { dx = 7, dy = 0, sprite = "location_farm_accesories_01_18", trough = "feed" },
                { dx = 8, dy = 0, sprite = "location_farm_accesories_01_19", trough = "feed" },
                { dx = 7, dy = 1, sprite = "location_farm_accesories_01_16", trough = "feed" },
                { dx = 8, dy = 1, sprite = "location_farm_accesories_01_17", trough = "feed" },
                { dx = 10, dy = 0, sprite = "location_farm_accesories_01_9", stock = "feed" },
                { dx = 1, dy = 4, sprite = "vegetation_farm_01_16" },
                { dx = 2, dy = 4, sprite = "vegetation_farm_01_18" },
                { dx = 3, dy = 4, sprite = "vegetation_farm_01_17" },
                { dx = 7, dy = 4, sprite = "carpentry_02_52", water = true },
                { dx = 8, dy = 4, sprite = "carpentry_01_16", stock = "tack" },
                { dx = 9, dy = 4, sprite = "vegetation_farm_01_8" },
                { dx = 10, dy = 4, sprite = "vegetation_farm_01_11" },
                { dx = 5, dy = 0, sprite = "location_farm_accesories_01_15", trough = "feed" },
                { dx = 6, dy = 0, sprite = "location_farm_accesories_01_15", trough = "water" },
            },
            animals = {
                { dx = 2, dy = 1, animal = "hen", breed = "rhodeisland" },
                { dx = 3, dy = 1, animal = "hen", breed = "rhodeisland" },
                { dx = 2, dy = 3, animal = "hen", breed = "leghorn" },
                { dx = 3, dy = 3, animal = "cockerel", breed = "rhodeisland" },
                { dx = 9, dy = 1, animal = "ewe", breed = "suffolk" },
                { dx = 9, dy = 3, animal = "ram", breed = "suffolk" },
            },
        },
        library = {
            base = { W = "walls_interior_house_03_16", N = "walls_interior_house_03_17", doorW = "walls_interior_house_03_26", doorN = "walls_interior_house_03_27" },
            floor = { { "floors_interior_tilesandwood_01_44" } },
            aisle = { "floors_interior_carpet_01_8" },
            wallN = { "", "", "", "", "", "trains_02_97", "", "", "", "", "", "" },
            wallW = { "", "", "trains_02_95", "", "" },
            lamps = { { dx = 3, dy = 2 }, { dx = 8, dy = 2 } },
            fittings = {
                { dx = 1, dy = 0, sprite = "furniture_shelving_01_40", stock = "books" },
                { dx = 2, dy = 0, sprite = "furniture_shelving_01_40", stock = "books" },
                { dx = 3, dy = 0, sprite = "furniture_shelving_01_40", stock = "study" },
                { dx = 4, dy = 0, sprite = "furniture_shelving_01_40", stock = "books" },
                { dx = 5, dy = 0, sprite = "lighting_indoor_02_42" },
                { dx = 7, dy = 0, sprite = "location_community_school_01_19" },
                { dx = 8, dy = 0, sprite = "location_community_school_01_20" },
                { dx = 9, dy = 0, sprite = "location_community_school_01_21" },
                { dx = 10, dy = 0, sprite = "location_community_school_01_22" },
                { dx = 11, dy = 0, sprite = "location_community_school_01_23" },
                { dx = 7, dy = 1, sprite = "location_community_school_01_14", stock = "stationery" },
                { dx = 8, dy = 1, sprite = "location_community_school_01_14" },
                { dx = 9, dy = 1, sprite = "location_community_school_01_14" },
                { dx = 7, dy = 3, sprite = "location_community_school_01_14" },
                { dx = 8, dy = 3, sprite = "location_community_school_01_14" },
                { dx = 9, dy = 3, sprite = "location_community_school_01_14" },
                { dx = 1, dy = 3, sprite = "furniture_seating_indoor_02_1" },
                { dx = 2, dy = 3, sprite = "furniture_tables_high_01_6" },
                { dx = 3, dy = 3, sprite = "furniture_seating_indoor_02_3" },
                { dx = 1, dy = 4, sprite = "furniture_shelving_01_51", stock = "stationery" },
                { dx = 2, dy = 4, sprite = "furniture_shelving_01_51", stock = "books" },
                { dx = 3, dy = 4, sprite = "furniture_shelving_01_51", stock = "parlor" },
                { dx = 10, dy = 4, sprite = "location_business_office_generic_01_24", stock = "stationery" },
            },
        },
        chapel = {
            base = { W = "location_community_church_small_01_4", N = "location_community_church_small_01_5", doorW = "location_community_church_small_01_14", doorN = "location_community_church_small_01_15" },
            floor = { { "floors_interior_tilesandwood_01_44" } },
            aisle = { "floors_interior_carpet_01_9" },
            wallN = { "trains_02_92", "trains_02_93", "trains_02_92", "trains_02_93", "", "trains_02_97", "trains_02_93", "trains_02_92", "trains_02_93", "trains_02_92", "trains_02_93", "trains_02_92" },
            wallW = { "", "", "trains_02_95", "", "" },
            lamps = { { dx = 3, dy = 2 }, { dx = 8, dy = 2 } },
            fittings = {
                { dx = 1, dy = 0, sprite = "location_community_church_small_01_43" },
                { dx = 1, dy = 1, sprite = "location_community_church_small_01_42" },
                { dx = 1, dy = 3, sprite = "location_community_church_small_01_45" },
                { dx = 2, dy = 0, sprite = "furniture_shelving_01_19", stock = "chapel" },
                { dx = 2, dy = 4, sprite = "lighting_indoor_02_64" },
                { dx = 4, dy = 0, sprite = "location_community_church_small_01_61" },
                { dx = 4, dy = 1, sprite = "location_community_church_small_01_59" },
                { dx = 4, dy = 3, sprite = "location_community_church_small_01_61" },
                { dx = 4, dy = 4, sprite = "location_community_church_small_01_59" },
                { dx = 6, dy = 0, sprite = "location_community_church_small_01_61" },
                { dx = 6, dy = 1, sprite = "location_community_church_small_01_59" },
                { dx = 6, dy = 3, sprite = "location_community_church_small_01_61" },
                { dx = 6, dy = 4, sprite = "location_community_church_small_01_59" },
                { dx = 8, dy = 0, sprite = "location_community_church_small_01_61" },
                { dx = 8, dy = 1, sprite = "location_community_church_small_01_59" },
                { dx = 8, dy = 3, sprite = "location_community_church_small_01_61" },
                { dx = 8, dy = 4, sprite = "location_community_church_small_01_59" },
                { dx = 10, dy = 0, sprite = "location_community_church_small_01_61" },
                { dx = 10, dy = 1, sprite = "location_community_church_small_01_59" },
                { dx = 10, dy = 3, sprite = "location_community_church_small_01_61" },
                { dx = 10, dy = 4, sprite = "location_community_church_small_01_59" },
            },
        },
        observation = {
            base = { W = "walls_interior_house_01_16", N = "walls_interior_house_01_17", doorW = "walls_interior_house_01_26", doorN = "walls_interior_house_01_27" },
            floor = { { "floors_interior_carpet_01_0" } },
            aisle = { "floors_interior_tilesandwood_01_16" },
            wallN = { "trains_02_92", "trains_02_93", "trains_02_92", "trains_02_93", "", "trains_02_97", "trains_02_93", "trains_02_92", "trains_02_93", "trains_02_92", "trains_02_93", "trains_02_92" },
            wallW = { "", "", "trains_02_95", "", "" },
            lamps = { { dx = 3, dy = 2 }, { dx = 8, dy = 2 } },
            fittings = {
                { dx = 1, dy = 0, sprite = "furniture_seating_indoor_03_33" },
                { dx = 2, dy = 0, sprite = "furniture_seating_indoor_03_32" },
                { dx = 3, dy = 0, sprite = "vegetation_indoor_01_11" },
                { dx = 6, dy = 0, sprite = "furniture_seating_indoor_03_33" },
                { dx = 7, dy = 0, sprite = "furniture_seating_indoor_03_32" },
                { dx = 8, dy = 0, sprite = "lighting_indoor_02_68" },
                { dx = 9, dy = 0, sprite = "furniture_seating_indoor_03_33" },
                { dx = 10, dy = 0, sprite = "furniture_seating_indoor_03_32" },
                { dx = 1, dy = 1, sprite = "furniture_tables_low_01_8" },
                { dx = 2, dy = 1, sprite = "furniture_tables_low_01_9" },
                { dx = 9, dy = 1, sprite = "furniture_tables_low_01_8" },
                { dx = 10, dy = 1, sprite = "furniture_tables_low_01_9" },
                { dx = 1, dy = 4, sprite = "furniture_seating_indoor_03_7" },
                { dx = 2, dy = 4, sprite = "furniture_tables_low_01_13", stock = "parlor" },
                { dx = 3, dy = 4, sprite = "furniture_seating_indoor_03_7" },
                { dx = 7, dy = 4, sprite = "furniture_seating_indoor_03_7" },
                { dx = 8, dy = 4, sprite = "furniture_tables_low_01_13", stock = "parlor" },
                { dx = 9, dy = 4, sprite = "furniture_seating_indoor_03_7" },
                { dx = 10, dy = 4, sprite = "vegetation_indoor_01_10" },
            },
        },
    },
}

---------------------------------------------------------------------------
-- The plow (DESIGN.md 3.6)
---------------------------------------------------------------------------
C.Plow = {
    ahead     = 1.6,        -- the killing ground in front of the leading plow
    wide      = 1.8,        -- and half its width: a little more than the car behind it
    margin    = 0.9,        -- the train is this much wider to the dead than it looks
    throw     = 3.0,        -- a zombie in the train's way is thrown this far aside
    shove     = 0.6,        -- and shoved this far from a parked one
    moving    = 0.3,        -- under this speed a train is parked
    weapon    = "Base.Pistol",  -- what the engine's Hit is told did it
    damage    = 100,
    range     = 80,         -- a train further than this from every player hits nothing
    throwPlayer = 3.5,
    hurtPlayer  = 25,       -- general health, of 100
    againMs     = 1500,     -- a player is not hit twice in this long
}

---------------------------------------------------------------------------
-- The greenhouse car's crops, and any crop in any car (DESIGN.md 12)
---------------------------------------------------------------------------
-- Vanilla kills a crop that is indoors unless its room is one the map calls a greenhouse
-- (SFarmingSystem.changeHealth, sandbox KillInsideCrops). A room of ours is no room of the map's,
-- so the mod gives back what that rule takes, for every crop on the ground the cars' insides stand
-- on: **a crop in a car grows as in a greenhouse** (TRN_Garden).
--
-- And the greenhouse car's own beds are looked after, where the sandbox's Garden says so: watered
-- to what each crop wants, kept from failing, and a ripe crop left standing until somebody picks it.
C.Garden = {
    young     = 2,          -- a "young" crop is grown this many stages as it is sown
    most      = 12,         -- and a "ripe" one until there is something to pick, or this many
    health    = 80,         -- how well a crop is as it is sown, of 100
    keep      = 60,         -- a bed that is looked after is never less well than this
    hold      = 48,         -- hours: a ripe crop that is looked after does not go over for this long more, each time it is looked at
}

---------------------------------------------------------------------------
-- The livestock car's animals, and leading animals aboard (DESIGN.md 12)
---------------------------------------------------------------------------
C.Stable = {
    zone   = "Train stable ",   -- .. the room's key: the livestock zone laid over a room that has animals
    feed   = { { "Base.AnimalFeedBag", 4 }, { "Base.HayTuft", 8 } },    -- what a feed trough is given when it is empty
}
-- Animals on a rope go through a car's door with whoever leads them, while the train stands: in
-- from a platform, out by the side door. An animal is a thing of the world and a door is a move of
-- thousands of squares, so each is taken out of the world where it stands and made again where its
-- keeper comes out, as the engine does it for a trailer (BaseVehicle.removeAnimalFromTrailer).
C.Herd = {
    most    = 6,            -- animals one keeper takes through a door
    giveUp  = 600,          -- ticks: animals whose ground never comes are set down where their keeper is
    spread  = 1.0,          -- squares between one animal and the next where they are set down
}

---------------------------------------------------------------------------
-- The dev test line (DESIGN.md 9: the first spikes, in one build)
---------------------------------------------------------------------------
C.Dev = {
    consist = "all",        -- the train on the test line
    wearAll = "all",        -- the consist whose cars wear every outside in turn, to be looked at
    length  = 290,          -- of the line, end to end, at least
    inset   = 45,           -- from each end to its stop, at least: always more than half the train
    beside  = 4,            -- the line runs this far from whoever laid it
    dwell   = 30,           -- parked, on the test line
    skipTo  = 4,            -- "skip ahead" lands this long before the next change
    -- The line with a bend in it: east, a quarter turn to the right, south.
    bendBefore = 150,       -- straight, to where the turn begins
    bendRadius = 40,        -- of the turn, at the middle of the track
    bendAfter  = 150,       -- straight again, after it
    bendSteps  = 24,        -- the turn is this many short straights
}

-- A stop's marker on the ground (vanilla's ground markers; each client's own).
C.StopMarker = { texture = "circle_center", size = 1.6, r = 1.0, g = 0.8, b = 0.1, alpha = 0.8 }

-- What the speaker says, and when (DESIGN.md 5.4): seconds before.
C.Speaker = { arriving = 10, departing = 10 }

return C
