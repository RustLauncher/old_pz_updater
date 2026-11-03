--[[
    © 2026 Warlord-Fox3. Tous droits réservés / All Rights Reserved.

    Toute réutilisation, modification, redistribution ou inclusion dans un
    modpack sans autorisation écrite préalable est strictement interdite.

    Any reuse, modification, redistribution, or inclusion in a modpack
    without prior written permission is strictly prohibited.
]]

--[[
    LPBCS_Ink -- which tool lets you write, and what colour it writes in.

    The palettes are copied from vanilla on purpose. A red pen writes the same
    red on a crate as it does on a map (ISMapSymbolDialog), and a can of blue
    paint paints the same blue as a painted wall (ISPaintCursor). Picking new
    colours here would have made the mod look bolted on.

    THE COLOUR IS CHOSEN, and this file is the only place it is chosen.

    It did not use to be. findPen took the first WRITE-tagged item the recursive
    inventory walk happened to reach, and that order follows the history of what
    went into which bag: a player carrying a black pen and a red one got
    whichever, and got a different whichever after tidying up. Nothing was
    random -- there is no random in this mod -- but nothing was a choice either.

    A choice has to survive the trip to where the sign is actually written, and
    that is the whole reason it is shaped the way it is. The engine rebuilds the
    timed action in the server's process through
    :new(character, object, container, text, style), so on a dedicated server it
    is the SERVER that reaches :complete(), calls Ink.requirement and settles the
    colour. A choice carried on the action would be dropped in the rebuild,
    exactly the way `intent` and `side` were -- see ISLPBCSWriteLabel.

    So it is not carried on the action. It is a PREFERENCE on the character --
    "I write in red" -- kept in the player's ModData, which both processes can
    read, and put on the server's copy by its own request, SetInk. That is also
    why it is remembered between signs: a preference that had to be restated
    every time would be an intention wearing a preference's clothes, and would
    have to travel with every write.

    Two rules fall out, and both are load-bearing:

      * A PREFERENCE IS A HINT, NEVER AN AUTHORITY. Everything about it is
        re-checked at the moment of writing -- the item is still carried, still
        usable, still carries the tag -- and anything that fails falls back to
        the first-found walk. A forged id can therefore not produce a colour the
        player does not own, because the colour is never sent: only a name for an
        item, whose colour is then read off the item that name resolves to.

      * THE CAN IS RESOLVED ONCE, HERE, AND NEVER RE-DERIVED. Ink.consume spends
        `requirement.paint`, which is the same table whose colour was written. A
        stray Ink.findPaint(playerObj) added to consume later would look
        innocent and would spend the FIRST-FOUND can while the sign shows the
        CHOSEN colour. tools/check_encre.py fails on exactly that mutation.

    ONE ITEM CAN BE SEVERAL INKS, and the four-colour pen is the reason this
    file no longer pretends otherwise. PenMultiColor declares base:redpen,
    base:bluepen, base:greenpen AND base:pen at once -- the game saying "this
    writes in any of these" -- and Crayons adds base:pencil to the same list.
    They matched the first palette entry and nothing else, so a player carrying
    nothing but a four-colour pen wrote red, forever, and the dropdown offered
    them that single line to prove it.

    So an id may now name an ink INSIDE an item -- "Base.PenMultiColor#RED_PEN"
    -- and that separator is the whole of the change on the wire. "#" because a
    full type is module.Type and both halves are [A-Za-z0-9_]: nothing vanilla
    or modded can put one in a type name, so an id splits exactly once, and an
    id without one still means precisely what it always meant. Preferences
    saved by an older build read back unchanged.

    It weakens neither rule above, and hanging it off a TAG rather than a colour
    is why. Only the tag travels; the colour is still read off the palette entry
    the carried item is re-checked against at writing time, with THE SAME
    PREDICATE THAT BUILT THE LIST. A forged "Base.Pen#GREEN_PEN" therefore
    resolves to nothing, because that pen carries no green. Two predicates free
    to disagree would be worse than none: the list would offer an ink the
    resolver refuses, the refusal falls back to first-found, and the player
    picks green and gets black without a word -- the exact silence this whole
    file exists to end.

    The colour WORDS are vanilla's too, ContextMenu_Red and its neighbours, the
    ones ISPaintMenu names its cans with. Four entries have to be told apart by
    something and item:getName() says "Multi-Color Pen" four times; borrowing
    the game's own vocabulary is what keeps this mod from owning a single colour
    name in six translation files.
]]

require "LPBCS_Core"
require "LPBCS_Config"
require "LPBCS_Text"

LPBCS.Ink = LPBCS.Ink or {}
local Ink = LPBCS.Ink
local Config = LPBCS.Config

Ink.DEFAULT = { r = 0.13, g = 0.13, b = 0.13 }
Ink.DEFAULT_PAINT = { r = 0.92, g = 0.92, b = 0.92 }

-- Same five inks the vanilla map annotation dialog offers, matched first by
-- item tag (so modded pens that declare base:redpen work) and then by type.
--
-- `word` names the ink when the item cannot: a four-colour pen is four of these
-- entries and item:getName() answers the same string for all four. The keys are
-- ISPaintMenu's own -- vanilla ships them translated everywhere the game is --
-- and the English beside each is the fallback LPBCS.text needs, not a second
-- copy of a translation.
local PEN_PALETTE = {
    { tag = "RED_PEN",   type = "RedPen",   r = 0.65,  g = 0.054, b = 0.054,
      word = "ContextMenu_Red",   plain = "Red"   },
    { tag = "BLUE_PEN",  type = "BluePen",  r = 0.156, g = 0.188, b = 0.49,
      word = "ContextMenu_Blue",  plain = "Blue"  },
    { tag = "GREEN_PEN", type = "GreenPen", r = 0.06,  g = 0.39,  b = 0.17,
      word = "ContextMenu_Green", plain = "Green" },
    { tag = "PENCIL",    type = "Pencil",   r = 0.2,   g = 0.2,   b = 0.2,
      word = "ContextMenu_Grey",  plain = "Gray"  },
    { tag = "PEN",       type = "Pen",      r = 0.129, g = 0.129, b = 0.129,
      word = "ContextMenu_Black", plain = "Black" },
}

-- ISPaintCursor's colours, in ISPaintMenu's order.
--
-- An ARRAY, and it has to be one now. This was a table keyed by item type, and
-- "ISPaintCursor's table, verbatim" was only ever true of the VALUES: a Lua
-- constructor's key order is not an order, so pairs() over it comes out however
-- the hash falls. That cost nothing while the only question asked of it was
-- "what colour is this can", and it would have shuffled a dropdown on every
-- open. The order is ISPaintMenu.PaintMenuItems', which is vanilla's own
-- presentation order for this identical list of fifteen -- the same argument
-- the header makes about the colours themselves.
local PAINT_PALETTE = {
    { type = "PaintBlue",       r = 0.35, g = 0.35, b = 0.80 },
    { type = "PaintGreen",      r = 0.41, g = 0.80, b = 0.41 },
    { type = "PaintLightBrown", r = 0.59, g = 0.44, b = 0.21 },
    { type = "PaintLightBlue",  r = 0.55, g = 0.55, b = 0.87 },
    { type = "PaintBrown",      r = 0.45, g = 0.23, b = 0.11 },
    { type = "PaintOrange",     r = 0.79, g = 0.44, b = 0.19 },
    { type = "PaintCyan",       r = 0.50, g = 0.80, b = 0.80 },
    { type = "PaintPink",       r = 0.81, g = 0.60, b = 0.60 },
    { type = "PaintGrey",       r = 0.50, g = 0.50, b = 0.50 },
    { type = "PaintTurquoise",  r = 0.49, g = 0.70, b = 0.80 },
    { type = "PaintPurple",     r = 0.61, g = 0.40, b = 0.63 },
    { type = "PaintYellow",     r = 0.84, g = 0.78, b = 0.30 },
    { type = "PaintWhite",      r = 0.92, g = 0.92, b = 0.92 },
    { type = "PaintRed",        r = 0.63, g = 0.10, b = 0.10 },
    { type = "PaintBlack",      r = 0.20, g = 0.20, b = 0.20 },
}

-- Built once, so colorOfPaint stays the single table read it always was.
local PAINT_BY_TYPE = {}
for index, entry in ipairs(PAINT_PALETTE) do
    entry.rank = index
    PAINT_BY_TYPE[entry.type] = entry
end

for index, entry in ipairs(PEN_PALETTE) do
    entry.rank = index
end

-- ------------------------------------------------------------------- tags

--- ItemTag entries are Java constants that have moved around between builds.
--- A missing one degrades to "this tool is not recognised", never to a crash.
local function tag(name)
    if type(ItemTag) ~= "table" and type(ItemTag) ~= "userdata" then return nil end
    local ok, value = pcall(function() return ItemTag[name] end)
    if not ok then return nil end
    return value
end

local function hasTag(item, name)
    local itemTag = tag(name)
    if item == nil or itemTag == nil then return false end
    return LPBCS.attempt(function() return item:hasTag(itemTag) end) == true
end

local function isUsable(item)
    if item == nil then return false end
    return LPBCS.get(item, "isBroken", false) ~= true
end

local function firstWithTag(inventory, name)
    local itemTag = tag(name)
    if inventory == nil or itemTag == nil then return nil end

    local item = LPBCS.attempt(function()
        return inventory:getFirstTagEvalRecurse(itemTag, isUsable)
    end)
    if item ~= nil then return item end

    item = LPBCS.attempt(function() return inventory:getFirstTagRecurse(itemTag) end)
    if isUsable(item) then return item end
    return nil
end

local function typeOf(item)
    local value = LPBCS.get(item, "getType", nil)
    if value == nil then return "" end
    return tostring(value)
end

--- Every item carrying this tag, not just the first one. What the dropdown is
--- built from.
---
--- Three tiers, because only the getFirst* forms were ever used here and the
--- enumerating ones are a wider bet. The last tier is today's behaviour exactly,
--- so the worst case is a dropdown with one entry rather than no dropdown and no
--- writing:
---
---   1. getAllTagEvalRecurse(tag, eval, list) -- the eval runs in Java.
---   2. getAllTagRecurse(tag, list), filtered here.
---   3. firstWithTag, wrapped in a one-element list.
---
--- Read from OUR OWN reference to the list rather than from the return value:
--- ISWorldObjectContextMenu discards what these return, so what they hand back
--- is not something to rely on. Java lists are indexed from 0.
---
--- ArrayList is guarded like ItemTag above, and for a reason that has already
--- bitten elsewhere in this mod: this is a shared/ file, loaded for real by
--- check_wire.py and check_nom.py under a Lua that has no Java at all. A missing
--- ArrayList has to mean "fall to tier 3", never "raise on load".
local function allWithTag(inventory, name)
    local itemTag = tag(name)
    local found = {}
    if inventory == nil or itemTag == nil then return found end

    local list = nil
    if type(ArrayList) == "table" or type(ArrayList) == "userdata" then
        list = LPBCS.attempt(function() return ArrayList.new() end)
    end

    local function drain(filter)
        local size = LPBCS.get(list, "size", nil)
        if type(size) ~= "number" then return false end
        for index = 0, size - 1 do
            local item = LPBCS.attempt(function() return list:get(index) end)
            if item ~= nil and (not filter or isUsable(item)) then
                found[#found + 1] = item
            end
        end
        return true
    end

    -- These APPEND to the list they are handed; they do not replace its
    -- contents. A first tier that raised halfway would otherwise leave its
    -- findings behind for the second to count twice.
    local function gather(fill, filter)
        found = {}
        LPBCS.invoke(list, "clear")
        if LPBCS.attempt(fill) ~= true then return false end
        return drain(filter) and #found > 0
    end

    if list ~= nil then
        -- The eval already ran in Java, so nothing is filtered again here.
        if gather(function()
            inventory:getAllTagEvalRecurse(itemTag, isUsable, list)
            return true
        end, false) then return found end

        if gather(function()
            inventory:getAllTagRecurse(itemTag, list)
            return true
        end, true) then return found end

        found = {}
    end

    local item = firstWithTag(inventory, name)
    if item ~= nil then found[1] = item end
    return found
end

-- --------------------------------------------------------------- palettes

--- EVERY palette entry this item matches, in palette order. One for a red pen,
--- four for PenMultiColor, five for Crayons.
---
--- THE ONE PREDICATE, and it has to stay one. Ink.available builds the dropdown
--- from it and resolveChoice re-checks the returned id against it, so a list
--- that offers an ink is by construction a list whose ink resolves. Two copies
--- would be free to drift, and the drift would be invisible: the resolver
--- refuses, the refusal falls back to first-found, and the player who picked
--- green gets black with nothing said.
local function penEntries(item)
    local found = {}
    if item == nil then return found end
    local itemType = typeOf(item)
    for _, entry in ipairs(PEN_PALETTE) do
        if hasTag(item, entry.tag) or itemType == entry.type then
            found[#found + 1] = entry
        end
    end
    return found
end

local function paintEntry(item)
    if item == nil then return nil end
    return PAINT_BY_TYPE[typeOf(item)]
end

--- The palette entry this item matches FIRST, or nil. What an unchosen ink
--- falls back to, and what colorOfPen has always answered. Split out of
--- colorOfPen so that there is one answer to "which palette slot is this"
--- rather than two that can disagree.
local function penEntry(item)
    return penEntries(item)[1]
end

--- Both palettes behind one question, so that everything downstream stops
--- caring which one it is asking. A can is one colour by construction: there is
--- no multi-colour paint, and PAINT_PALETTE carries no tags for one to be
--- several by. Only a pen ever comes back as more than one entry.
local function entriesOf(item, painted)
    if painted then
        local entry = paintEntry(item)
        if entry == nil then return {} end
        return { entry }
    end
    return penEntries(item)
end

function Ink.colorOfPen(item)
    if item == nil then return Ink.DEFAULT end
    local entry = penEntry(item)
    if entry then return { r = entry.r, g = entry.g, b = entry.b } end
    return Ink.DEFAULT
end

function Ink.colorOfPaint(item)
    if item == nil then return Ink.DEFAULT_PAINT end
    local entry = paintEntry(item)
    if entry then return { r = entry.r, g = entry.g, b = entry.b } end
    return Ink.DEFAULT_PAINT
end

-- ------------------------------------------------------------------ tools

function Ink.findPen(playerObj)
    local inventory = LPBCS.get(playerObj, "getInventory", nil)
    return firstWithTag(inventory, "WRITE")
end

function Ink.findBrush(playerObj)
    local inventory = LPBCS.get(playerObj, "getInventory", nil)
    return firstWithTag(inventory, "PAINTBRUSH")
end

function Ink.findPaint(playerObj)
    local inventory = LPBCS.get(playerObj, "getInventory", nil)
    return firstWithTag(inventory, "PAINT")
end

-- ----------------------------------------------------------------- choices

-- Between an item and which of its inks. See the header: a full type is
-- module.Type and both halves are [A-Za-z0-9_], so nothing that names an item
-- can contain one, an id splits exactly once, and an id with no separator is
-- the id this mod has always written.
Ink.ID_SEPARATOR = "#"

--- Takes an id apart: the item it names, and the ink inside it or nil.
--- Never raises, and hands back the whole string as the item name when there is
--- nothing to split -- which is what every id saved before this existed is.
local function splitId(id)
    if type(id) ~= "string" or id == "" then return nil, nil end
    local itemId, inkTag = id:match("^([^#]+)#([^#]+)$")
    if itemId ~= nil then return itemId, inkTag end
    return id, nil
end

--- Which kind of preference this style reads. A pen writes the plank and the
--- paper; a can writes the painted one.
function Ink.kindOf(style)
    if style == "painted" then return "paint" end
    return "pen"
end

--- The item's name on the wire. The full type, so that a modded "CrimsonPen"
--- declaring base:redpen and vanilla's RedPen stay two entries with two names
--- rather than collapsing into one -- they are the same COLOUR, not the same
--- thing, and the player owns them separately.
---
--- This is vanilla's own shape for the same problem: ISPaintCursor remembers a
--- paint TYPE chosen earlier and resolves it to a concrete can at use time with
--- getFirstTypeRecurse.
local function idOf(item)
    local value = LPBCS.get(item, "getFullType", nil)
    if value == nil then value = LPBCS.get(item, "getType", nil) end
    if value == nil then return nil end
    value = tostring(value)
    if value == "" then return nil end
    return value
end

--- What to call it in the dropdown: the item's own name, which the game has
--- already translated. That is the whole reason there is not one colour-name
--- key in this mod's six languages -- and it is also why a modded pen matched
--- by tag arrives correctly labelled without knowing anything about us. The
--- label is a property of the item, not of our palette.
local function labelOf(item, id)
    local value = LPBCS.get(item, "getName", nil)
    if value == nil then value = LPBCS.get(item, "getDisplayName", nil) end
    if value == nil then return id end
    value = tostring(value)
    if value == "" then return id end
    return value
end

--- The same, plus which ink -- but ONLY for an item carrying several. A red pen
--- is already called "Red Pen" by the game, and "Red Pen (Red)" would be this
--- mod explaining an item to itself.
---
--- The item still names itself and vanilla still names the colour; the only
--- string of ours on the line is the shape holding the two together, which is
--- why IGUI_LPBCS_InkOf is a key rather than a hard-coded "%1 (%2)": a language
--- that wants the colour first can have it.
local function labelFor(item, id, entry, several)
    local name = labelOf(item, id)
    if not several or entry == nil then return name end
    return LPBCS.text("IGUI_LPBCS_InkOf", "%1 (%2)", name,
        LPBCS.text(entry.word, entry.plain))
end

--- Every ink this player could write this style in, deduplicated by id and in
--- an order that does not move: palette order first, then anything the palettes
--- do not know, by id.
---
--- ONE ENTRY PER INK, NOT PER ITEM, which is what makes a four-colour pen four
--- lines instead of one. Deduplication follows: it is by the composite id, so
--- two red pens are still one line, and a red pen beside a four-colour pen is
--- two -- they are the same colour but not the same thing, and the player owns
--- them separately.
---
--- By ID and not by label for the tail, deliberately. Sorting on what is shown
--- would reorder the list when the player changes language, and a dropdown whose
--- entries move is a dropdown nobody trusts.
---
--- Never nil. An empty inventory gives an empty table, which is what the caller
--- has to handle anyway.
---
--- `item` rides along for the caller's convenience -- the write path uses it to
--- move the right can into the main inventory -- and NEVER goes on the wire.
--- Only `id` travels.
function Ink.available(playerObj, style)
    local inventory = LPBCS.get(playerObj, "getInventory", nil)
    local painted = (style == "painted")
    local items = allWithTag(inventory, painted and "PAINT" or "WRITE")

    local fallback = painted and Ink.DEFAULT_PAINT or Ink.DEFAULT

    local out, seen = {}, {}
    for rank, item in ipairs(items) do
        local base = idOf(item)
        if base ~= nil then
            local entries = entriesOf(item, painted)
            local several = #entries > 1
            -- math.max, because an item NO palette knows is still one line: it
            -- writes in the default ink, which beats not being offered at all.
            -- That is the modded-pen case, and it has not moved.
            for slot = 1, math.max(#entries, 1) do
                local entry = entries[slot]
                local id = base
                if several then id = base .. Ink.ID_SEPARATOR .. entry.tag end
                if not seen[id] then
                    seen[id] = true
                    local ink = entry or fallback
                    out[#out + 1] = {
                        id = id,
                        label = labelFor(item, base, entry, several),
                        r = ink.r, g = ink.g, b = ink.b,
                        item = item,
                        -- Sort keys only. Unknown types go after every known
                        -- one, and the discovery rank is the tiebreak:
                        -- table.sort is not stable, so without it two cans of
                        -- the same rank could swap places between two openings
                        -- of the same menu. Same trick, same reason, as the
                        -- container stack in LPBCS_Context. Two inks of the
                        -- same ITEM share a discovery rank and never tie,
                        -- because they differ by palette rank first.
                        palette = entry and entry.rank or nil,
                        found = rank,
                    }
                end
            end
        end
    end

    table.sort(out, function(a, b)
        if (a.palette ~= nil) ~= (b.palette ~= nil) then return a.palette ~= nil end
        if a.palette ~= nil and a.palette ~= b.palette then return a.palette < b.palette end
        if a.palette == nil and a.id ~= b.id then return a.id < b.id end
        return a.found < b.found
    end)

    return out
end

-- -------------------------------------------------------------- preference

local function playerStore(playerObj, create)
    local modData = LPBCS.get(playerObj, "getModData", nil)
    if type(modData) ~= "table" then return nil end

    local mine = modData[LPBCS.PLAYER_MODDATA_KEY]
    if type(mine) ~= "table" then
        if not create then return nil end
        mine = {}
        modData[LPBCS.PLAYER_MODDATA_KEY] = mine
    end

    if type(mine.ink) ~= "table" then
        if not create then return nil end
        mine.ink = {}
    end
    return mine.ink
end

--- What this character writes with, or nil when they have never said.
function Ink.preference(playerObj, kind)
    if not LPBCS.isInkKind(kind) then return nil end
    local store = playerStore(playerObj, false)
    if store == nil then return nil end
    local id = store[kind]
    if type(id) ~= "string" or id == "" then return nil end
    return id
end

--- Remembers it. Returns true when something was stored.
---
--- THE ONLY COPY OF THIS VALIDATION, and that is the point of it living here
--- rather than in the two callers. The client stores the choice locally and the
--- server stores the same choice off the wire; two copies of the rule would be
--- free to drift, and the one that drifted would be the server's.
---
--- It is hygiene, not authority: the question here is only "is this a string
--- worth writing into a saved character", never "does this player own it".
--- Ownership is re-asked at writing time, in Ink.requirement, where a wrong
--- answer still has somewhere to fall back to. Refusing here instead would
--- leave a player who put the pen down between choosing and the packet landing
--- with a stale preference and no way to see why.
function Ink.setPreference(playerObj, kind, id)
    if not LPBCS.isInkKind(kind) then return false end

    local store = playerStore(playerObj, true)
    if store == nil then return false end

    if id == nil then
        store[kind] = nil
        return true
    end

    if type(id) ~= "string" then return false end
    if id == "" or #id > LPBCS.MAX_INK_ID then return false end

    -- Each half on its own terms, rather than one pattern widened to let "#"
    -- through anywhere: that would have accepted "#", "a#b#c" and "Base.Pen#"
    -- as things worth writing into a saved character.
    local itemId, inkTag = splitId(id)
    if itemId == nil or itemId:match("^[%w_%.]+$") == nil then return false end
    if inkTag ~= nil and inkTag:match("^[%w_]+$") == nil then return false end

    store[kind] = id
    return true
end

--- The carried, usable, correctly tagged item this id names, and which of its
--- inks was asked for -- or nil, twice, when anything fails.
---
--- The tag re-check is the one that matters. getFirstTypeRecurse will happily
--- resolve "Base.Katana" for a client that asked for it; without the tag the
--- katana would become the writing tool, the colour would fall to DEFAULT, and
--- a forged request would have quietly changed the sign. With it, a forged id
--- resolves to nothing and the write falls back to first-found.
---
--- The ink half is re-checked the same way and for the same reason: it must be
--- an ink THIS item carries, asked through entriesOf, the predicate that built
--- the list. "Base.Pen#GREEN_PEN" is a plain pen and a colour it does not have,
--- so it resolves to nothing rather than to a green plain pen.
local function resolveChoice(inventory, id, tagName, painted)
    if inventory == nil then return nil end

    local itemId, inkTag = splitId(id)
    if itemId == nil then return nil end

    local item = LPBCS.attempt(function()
        return inventory:getFirstTypeRecurse(itemId)
    end)
    if item == nil then return nil end
    if not isUsable(item) then return nil end
    if not hasTag(item, tagName) then return nil end

    if inkTag == nil then return item, nil end

    for _, entry in ipairs(entriesOf(item, painted)) do
        if entry.tag == inkTag then return item, entry end
    end
    return nil
end

--- What this player would need to write in this style, and whether they have
--- it. Always returns a table; `ok` says whether the write may proceed and
--- `message` describes the gap when it may not.
---
--- The requirement is a server rule, so this is called on both sides: the
--- client to grey the menu entry out, the server to refuse a forged request.
---
--- `choiceId` is optional and overrides the stored preference; nil reads the
--- store. The first two parameters have not moved, so all five callers -- two in
--- ISLPBCSWriteLabel, one in LPBCS_Server, two in LPBCS_Context -- keep working
--- untouched, and `result` only ever gains a field.
---
--- ONE TARGETED WALK, not an enumeration. This is called once per style per
--- container every time the world menu is built, so a stack of four crates asks
--- it twelve times per right click; Ink.available's full walk belongs where it
--- runs once, at the moment the dropdown is filled.
function Ink.requirement(playerObj, style, choiceId)
    local painted = (style == "painted")
    local result = { style = style, painted = painted }

    local inventory = LPBCS.get(playerObj, "getInventory", nil)
    local wanted = choiceId or Ink.preference(playerObj, Ink.kindOf(style))

    -- `chosen` is the palette entry the id named, and it is the ONLY thing
    -- that can tell a four-colour pen's green from its red: both are the same
    -- item, so colorOf* would answer the same first match for either. It stays
    -- nil for a plain id, where the item alone is the whole answer.
    if painted then
        result.tool = Ink.findBrush(playerObj)
        local can, chosen = resolveChoice(inventory, wanted, "PAINT", true)
        if can ~= nil then
            result.paint = can
            result.choice = wanted
            result.ink = chosen and { r = chosen.r, g = chosen.g, b = chosen.b }
                or Ink.colorOfPaint(can)
        else
            result.paint = Ink.findPaint(playerObj)
            result.ink = Ink.colorOfPaint(result.paint)
        end
    else
        local tool, chosen = resolveChoice(inventory, wanted, "WRITE", false)
        if tool ~= nil then
            result.tool = tool
            result.choice = wanted
            result.ink = chosen and { r = chosen.r, g = chosen.g, b = chosen.b }
                or Ink.colorOfPen(tool)
        else
            result.tool = Ink.findPen(playerObj)
            result.ink = Ink.colorOfPen(result.tool)
        end
    end

    if not Config.requireWritingTool() then
        result.ok = true
        return result
    end

    if painted then
        if not result.tool then
            result.ok = false
            result.message = {
                key = "IGUI_LPBCS_NeedBrush",
                fallback = "You need a paintbrush to paint a name on this.",
            }
            return result
        end
        if not result.paint then
            result.ok = false
            result.message = {
                key = "IGUI_LPBCS_NeedPaint",
                fallback = "You need a can of paint to paint a name on this.",
            }
            return result
        end
    elseif not result.tool then
        result.ok = false
        result.message = {
            key = "IGUI_LPBCS_NeedPen",
            fallback = "You need a pen or a pencil to write on this.",
        }
        return result
    end

    result.ok = true
    return result
end

--- Spends the tool, if spending it means anything. A paint can loses a use;
--- a pen does not, which is exactly how vanilla treats a pen used to annotate
--- a map. ConsumeToolUse therefore only ever bites on drainables.
---
--- IT SPENDS THE TABLE IT IS HANDED, and never goes looking for a can itself.
--- The can was resolved once, in Ink.requirement, and ISLPBCSWriteLabel passes
--- that same table here -- so the can that loses a charge is by construction the
--- one whose colour was written. An Ink.findPaint(playerObj) added here later
--- would read as a harmless tidy-up and would spend the FIRST-FOUND can while
--- the sign shows the CHOSEN colour: two cans, one emptied, the other painted
--- with. tools/check_encre.py fails on exactly that mutation.
---
--- The preference names a colour-bearing TYPE, not one physical can. Two cans of
--- PaintRed are one entry in the dropdown, and when the first runs out the next
--- takes over without a word -- which is what "I paint in red" means.
function Ink.consume(requirement)
    if type(requirement) ~= "table" then return end
    if not Config.consumeToolUse() then return end

    local item = requirement.paint or requirement.tool
    if item == nil then return end
    if LPBCS.get(item, "IsDrainable", false) ~= true then return end

    if LPBCS.invoke(item, "UseAndSync") then return end
    LPBCS.invoke(item, "Use")
end

return Ink
