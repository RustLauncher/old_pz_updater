VAPES OF '93 - Build 42 (made for 42.21)

INSTALL
  Copy the "VapesOf93" folder (containing "42" and "common") into  Zomboid/mods/ and enable it.
  Safe to add to an existing save (see LOOT below).
  (Only saves where you tested the old "VapesAndCarts" build lose those old items - the item IDs changed.)

USING VAPES
  Right-click a vape -> Smoke. Same system and animation as vanilla cigarettes (stress relief,
  nicotine withdrawal, cough chance) but NO lighter, and it takes half the time (Eattime 230 vs 460).
  Nicotine vapes use the vanilla cigarette handler (RecipeCodeOnEat.consumeNicotine), so the Smoker trait
  is relieved exactly like with a cigarette.
  Every vape has at most 20 uses. About 1 hit in 4 (THC: 1 in 3) you'll say a line about the flavor.

THE VAPE (one model: the black vape)
  Refillable Vape Pen (Empty)  +  Vape Juice box  ->  Vape Pen (<flavor>), 20 hits.
  HOW TO REFILL: right-click the empty pen -> "Refill with Juice" -> pick a flavor
                 (or right-click a juice box -> "Refill an Empty Vape Pen").
                 The crafting menu also has a recipe for each flavor.
  The mouthpiece tip takes the colour of the juice you refill it with (Mango = orange, Strawberry = red...).
  Empty pens turn back into a Refillable Vape Pen. Refill only when empty (flavors don't mix).
  Vape Juice comes in a "VAPZ" box in each flavor colour with the flavor name on it.
  Each box has 3 refills and disappears after the third.
  Flavors: Mango, Strawberry, Kiwi Passion Fruit Guava, Banana, Blue Razz, Blueberry, Watermelon,
           Grape, Peach, Pineapple, Cotton Candy, Mint, Menthol, Classic Tobacco.
  Perks: fruit = small mood lift, mint/menthol = endurance boost, tobacco = extra stress relief.

THC (not refillable): Sativa, Indica, Hybrid - 20 hits each, same vape with a lime-green tip
  and a thin colour band on the body (yellow = Sativa, purple = Indica, cyan = Hybrid).
  When used up they become a Used THC Vape.
  Instant: big drop in stress, unhappiness, boredom and panic (applied by this mod's own Lua).
  Each hit adds ~20 game-minutes of high (stacks to 4h): keeps lowering unhappiness, stress and panic.
  Sativa: energetic, no tiredness.  Indica: sleepy, strongest pain relief.  Hybrid: balanced.
  Everyone gets hungry and thirsty. Stack past ~2.5h and you get sick.

LOOT  (edit the numbers at the top of 42/media/lua/server/VapesOf93/VapesOf93_Loot.lua)
  Same unit as the vanilla loot tables (the "chance" number next to an item, e.g. 8 for cigarettes in a desk).
  The chance applies to EACH of the four categories: empty refillable pens, pens already filled with juice,
  vape juice boxes and THC vapes. A category's chance is split between its items (13 juice flavours, 3 THC strains...).
    10  desks, kitchen counters, lockers (and wardrobes in mechanic shops / prison cells),
        crates in gas stations, shelves / counters / display cases in convenience stores and gas stations
     2  vehicle glove boxes
        (each place has its own line at the top of the Lua file, so they can be tuned separately)
  Gas stations and convenience stores: food shelves and magazine racks never get vapes (detected by list name
  and by content; console.txt lists what was skipped).
  Grocery stores / food markets and bars: no vapes at all (shelves, counters, crates, desks, everything).
  Only those places get vapes. SCALE_* lines scale one category up or down (1.0 = as written above).
  Zombies: 5% per kill, one item, rolled once per zombie.
  Existing saves: the mod can be added at any time. New loot appears in containers that have not been generated
  yet (unexplored areas, or areas that respawn loot); containers you already looted are not changed.
  console.txt shows "[VapesOf93] loot: added vapes to N places: ..." at game start and, when a game loads,
  "[VapesOf93] item check: all 33 items found" (or the list of items the game does not know).
  A line "[VapesOf93] loot: vehicle glove boxes patched: N" shows how many glove box lists were found.

3D MODELS
  Two GLB meshes in common/media/models_X/VapesOf93: Vape_Puff (the vape) and Vape_Pack (the juice box),
  each with a per-item texture. Smokable vapes use a flipped copy (Vape_Puff_Hand) for the in-hand/smoking model.
  If they look too big/small, change the "scale" values in 42/media/scripts/VapesOf93_models.txt.

ICONS
  Cut out from the supplied screenshots (icons are lifted slightly in brightness so the black vape stays visible).
  The original "PUFF" print was removed from the vape and renamed "VAPZ" on the box.

MOODLES
  No custom moodles. Everything nudges vanilla stats, so you only see the normal vanilla moodles
  (Stressed, Bored, Unhappy, Panic, Pain, Hungry, Thirsty, Tired, Sick).

TROUBLESHOOTING  (all messages are in console.txt, search for "[VapesOf93]")
  "smoke hooks: complete=true perform=true"  -> flavor perks / THC effects are hooked in.
  "hit <item>: stress A -> B"                -> printed after every hit; shows what the hit did to stress.
  "CharacterStat.X not found"                -> that stat name differs in your build (the old API is used instead).
  Debug spawn: debug mode > item list > search "Vape".
