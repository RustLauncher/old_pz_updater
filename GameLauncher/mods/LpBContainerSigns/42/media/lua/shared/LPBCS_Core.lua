--[[
    © 2026 Warlord-Fox3. Tous droits réservés / All Rights Reserved.

    Toute réutilisation, modification, redistribution ou inclusion dans un
    modpack sans autorisation écrite préalable est strictement interdite.

    Any reuse, modification, redistribution, or inclusion in a modpack
    without prior written permission is strictly prohibited.
]]

--[[
    LPBCS_Core -- identity, storage keys and the small helpers every other
    file leans on.

    The one thing worth knowing before reading anything else in this mod:
    ItemContainer:setCustomName() is NOT replicated in multiplayer. The class
    carries no packet for that field and the vanilla rename never sends one,
    so a name set on one client stays on that client. Every sign is therefore
    stored in the IsoObject's ModData, which IS replicated (ObjectModDataPacket
    via transmitModData), and the container's custom name is only ever a local
    mirror rebuilt from it -- see LPBCS_Label.

    Do not "simplify" this by reading getCustomName() as the source of truth.
]]

LPBCS = LPBCS or {}

LPBCS.MOD_ID = "LpBContainerSigns"

-- Single network module for the whole mod: one OnClientCommand listener
-- rather than several all string-matching their way through every packet.
LPBCS.MODULE = "LpBContainerSigns"

-- The shape of what travels over the wire, bumped whenever a command is added
-- or a field changes meaning. Client and server are updated separately -- the
-- server runs its own copy of the workshop item and restarts when its owner
-- says so -- so they WILL disagree, and the only question is whether the
-- disagreement is noticed or acted on.
--
-- Version 2 is the one that stopped inferring "erase this sign" from a request
-- that simply had no text in it. A version 1 server, handed a version 2 move,
-- wiped the sign and reported success.
--
-- Version 3 adds RenameSign, and with it the other half of the conversation.
-- The vanilla loot window's rename wrote straight into the container's local
-- name -- which does not travel -- and the display sweep put the old text back
-- a quarter of a second later, without a word. A rename is a request now, like
-- the other three, and it reaches the ModData every client actually reads.
--
-- Version 4 adds SetInk: the colour is one the player picked rather than one
-- the inventory walk stumbled on. It is the first request that names a PERSON
-- rather than a square, and it had to be, because the ink cannot travel on the
-- write. The engine rebuilds the action in the server's process through
-- :new(character, object, container, text, style), so on a dedicated server it
-- is the SERVER that calls Ink.requirement and decides the colour -- see
-- ISLPBCSWriteLabel. A choice carried on the action would be lost exactly the
-- way `intent` and `side` were.
--
-- This bump does NOT protect the write on a dedicated server, and that is worth
-- knowing here rather than discovering later: SetSign is never sent by the
-- client there, so permitted()'s `args.v > PROTOCOL` compares the server's own
-- version with itself and never fires. A version 3 server answers a version 4
-- SetInk with silence -- the unknown-command branch -- and would write in the
-- colour the dropdown did not show. That silence is why SetInk is acknowledged
-- with InkResult, and why LPBCS_Context says IGUI_LPBCS_VersionSkew when no
-- acknowledgement comes back.
--
-- Version 5 widens what SetInk's `id` may say. A four-colour pen is one item
-- carrying four inks, so an id may now name the ink inside it --
-- "Base.PenMultiColor#RED_PEN" -- and a version 4 server's hygiene refuses the
-- separator outright. It would answer BadRequest: "that request made no sense",
-- which is a diagnosis of the payload for what is really a disagreement about
-- age. That is the exact inference the build registry below exists to stop,
-- and the number is what stops it -- fromTheFuture fires first and says
-- IGUI_LPBCS_VersionSkew instead.
--
-- The cost is paid knowingly: against a version 4 server the whole feature
-- stands down, including the plain ids that would still have worked. A choice
-- honoured for some pens and refused for others, with no way to tell which from
-- the dropdown, would be worse than a choice that says out loud it is not
-- available here.
LPBCS.PROTOCOL = 5

-- Our own ModData key on the IsoObject. Holds the whole sign: text, ink,
-- style, the face the player pinned it to, author.
LPBCS.MODDATA_KEY = "LPBCS"

-- Our key on the IsoPlayer. Holds which pen and which paint that character
-- writes with -- see LPBCS_Ink.
--
-- Its own constant even though it spells the same four letters as MODDATA_KEY
-- above, and the duplication is deliberate. One namespaces an IsoObject, the
-- other an IsoPlayer; they name a sign and a person, and nothing but
-- coincidence makes them equal. Folding them into one constant would tie two
-- unrelated stores together, and the day one of them has to move the other
-- would move with it for no reason.
LPBCS.PLAYER_MODDATA_KEY = "LPBCS"

-- The vanilla key, written alongside ours. ISMoveableSpriteProps copies
-- "<containerType>_customContainerName" onto the item when furniture is
-- picked up and restores it on placement, which is the only reason a sign
-- survives a player moving a wardrobe across the room.
LPBCS.VANILLA_NAME_SUFFIX = "_customContainerName"

-- Hard ceiling; the sandbox option can lower it, never raise it. 28 is the
-- vanilla container rename limit, which lives as a file-local
-- MAXIMUM_RENAME_LENGTH in ISInventoryPage and so cannot be read from here.
-- A sign is a container name: letting it run longer than a name the game
-- itself accepts would only produce titles the loot window clips.
LPBCS.MAX_TEXT_LENGTH = 28

-- How far a player may be from a container and still write on it. Checked
-- again server-side, where it is the only thing standing between a modified
-- client and writing on someone else's crate from across the map.
LPBCS.MAX_WRITE_DISTANCE = 3

LPBCS.STYLES = { "plank", "paper", "painted" }
LPBCS.DEFAULT_STYLE = "plank"

-- Les deux faces verticales qu'on voit d'une caisse. "south" est la moitié
-- GAUCHE de la tuile à l'écran, "east" la droite -- c'est le sens que leur
-- donnent LPBCS_Scan, LPBCS_Sprites et LPBCS_Render.
LPBCS.FACES = { "east", "south" }

-- The two things a player can have a standing preference about. A pen writes
-- the plank and the paper styles; a can of paint writes the painted one. They
-- are kept apart because they are chosen from different lists and a player who
-- writes in red ink does not thereby paint in red.
LPBCS.INK_KINDS = { "pen", "paint" }

-- How long an item type may be before we refuse to remember it. A preference
-- is stored on a saved character, so an unbounded string off the wire would be
-- unbounded junk in a save file. Nothing vanilla comes close: the longest is
-- "Base.PenMultiColor#GREEN_PEN", an item and one of its inks, at 28.
LPBCS.MAX_INK_ID = 64

-- ---------------------------------------------------------------- logging

--- Silent unless the DebugLogging sandbox option is on, which it is not by
--- default. One gate for the whole mod: every call site stays a plain
--- LPBCS.log(...) and none of them has to know whether anyone is listening.
---
--- LPBCS.Config is reached through the global rather than required, because
--- Config requires this file -- the same reason isSignableContainer does it
--- further down. Config lives in media/lua/shared, which the game loads before
--- client and server, so by the time anything has something to say it has
--- answered; the nil guard is a belt, not a case.
function LPBCS.log(scope, fmt, ...)
    local config = LPBCS.Config
    if not config or not config.debugLogging() then return end

    local msg = fmt
    if select("#", ...) > 0 then
        local ok, formatted = pcall(string.format, fmt, ...)
        if ok then msg = formatted end
    end
    print("[LpBContainerSigns][" .. tostring(scope) .. "] " .. tostring(msg))
end

-- -------------------------------------------------------- build registry
--
-- Every file that has a say in what travels stamps itself as it loads. The
-- point is not to refuse anything -- nothing is ever refused on a version
-- number -- but to be able to ANSWER the question "which half of this install
-- is the old one?" at startup, instead of inferring it three rounds later from
-- the shape of a malformed packet.
--
-- That inference is the trap this exists to close. A request that arrives
-- missing a field says nothing whatsoever about anybody's install: it is just
-- as easily an action that lost its intent inside one process. Three separate
-- diagnoses read a missing field as evidence about the player's files, and all
-- three blamed an innocent.

local stamps = {}

--- Records that `file` loaded, announcing `version`.
function LPBCS.stamp(file, version)
    if file == nil then return end
    stamps[tostring(file)] = tonumber(version) or 0
end

--- Files that loaded but do not speak the same number as LPBCS_Core.
--- An array, sorted by name, of { file = , version = }.
function LPBCS.buildMismatches()
    local odd = {}
    for file, version in pairs(stamps) do
        if version ~= LPBCS.PROTOCOL then
            odd[#odd + 1] = { file = file, version = version }
        end
    end
    table.sort(odd, function(a, b) return a.file < b.file end)
    return odd
end

--- Files that were expected to stamp themselves and never did.
---
--- This is the case comparing numbers to each other can NEVER see: a file older
--- than the stamping itself does not register anywhere, so it has no number to
--- disagree with -- and it is precisely the file being looked for. Hence a list
--- of what is EXPECTED, not just a reading of what answered.
function LPBCS.missingFiles(expected)
    local missing = {}
    if type(expected) ~= "table" then return missing end
    for index = 1, #expected do
        local file = tostring(expected[index])
        if stamps[file] == nil then missing[#missing + 1] = file end
    end
    return missing
end

--- True when everything that answered agrees, and everything expected answered.
--- Says out loud what is wrong, once, so it is in the log before anyone has to
--- go looking for it.
---
--- Writes what is running, agreement or not, and that is the point. A registry
--- that only speaks up when it spots something wrong cannot be compared between
--- two machines -- and comparing the two halves is the whole question.
---
--- Read that comparison carefully now, because it rests on a condition it did
--- not use to have: this goes through LPBCS.log, so it says nothing at all
--- unless the DebugLogging sandbox option is on. Silence therefore only means
--- "this file is not running here" once the option is known to have been ON,
--- at startup, on BOTH machines being compared. Turning it on mid-session is
--- too late for this one -- checkBuild fires on OnGameStart and
--- OnServerStarted, and does not fire again.
function LPBCS.checkBuild(expected)
    local odd = LPBCS.buildMismatches()
    local missing = LPBCS.missingFiles(expected)

    local names = {}
    for file, version in pairs(stamps) do
        names[#names + 1] = string.format("%s=%d", file, version)
    end
    table.sort(names)
    LPBCS.log("Build", "protocole %d, %d fichier(s) : %s",
        LPBCS.PROTOCOL, #names, table.concat(names, " "))

    for index = 1, #odd do
        LPBCS.log("Build", "%s annonce le protocole %d, ce build parle le %d",
            odd[index].file, odd[index].version, LPBCS.PROTOCOL)
    end
    for index = 1, #missing do
        LPBCS.log("Build", "%s n'est pas charge, ou trop ancien pour s'annoncer",
            missing[index])
    end

    return #odd == 0 and #missing == 0
end

LPBCS.stamp("LPBCS_Core", LPBCS.PROTOCOL)

-- ------------------------------------------------------- safe Java access

--- Calls obj:methodName() and swallows anything that goes wrong.
--- Most of what this mod touches is Java, and a method that moved between
--- builds should degrade the feature, never break the file.
function LPBCS.get(obj, methodName, default)
    if obj == nil then return default end
    local method = obj[methodName]
    if type(method) ~= "function" then return default end
    local ok, value = pcall(method, obj)
    if not ok or value == nil then return default end
    return value
end

--- Calls obj:methodName(...) for its side effect. Returns true on success.
function LPBCS.invoke(obj, methodName, ...)
    if obj == nil then return false end
    local method = obj[methodName]
    if type(method) ~= "function" then return false end
    return (pcall(method, obj, ...))
end

--- Calls a plain function, returning nil instead of raising.
function LPBCS.attempt(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok then return nil end
    return value
end

-- ------------------------------------------------------------ text / misc

function LPBCS.trim(value)
    return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function LPBCS.isBlank(value)
    return LPBCS.trim(value) == ""
end

function LPBCS.clampInt(value, minimum, maximum)
    value = math.floor(tonumber(value) or 0)
    if minimum and value < minimum then value = minimum end
    if maximum and value > maximum then value = maximum end
    return value
end

function LPBCS.clampFloat(value, minimum, maximum)
    value = tonumber(value) or 0
    if minimum and value < minimum then value = minimum end
    if maximum and value > maximum then value = maximum end
    return value
end

function LPBCS.listContains(list, value)
    if type(list) ~= "table" then return false end
    for index = 1, #list do
        if list[index] == value then return true end
    end
    return false
end

function LPBCS.isStyle(value)
    return LPBCS.listContains(LPBCS.STYLES, value)
end

function LPBCS.isFace(value)
    return LPBCS.listContains(LPBCS.FACES, value)
end

function LPBCS.isInkKind(value)
    return LPBCS.listContains(LPBCS.INK_KINDS, value)
end

function LPBCS.nowMs()
    local value = LPBCS.attempt(getTimestampMs)
    if type(value) == "number" then return value end
    return os.time() * 1000
end

-- --------------------------------------------------------------- identity

function LPBCS.usernameOf(playerObj)
    if not playerObj then return nil end
    local username = LPBCS.get(playerObj, "getUsername", nil)
    if username == nil then return nil end
    return tostring(username)
end

function LPBCS.isAdmin(playerObj)
    if not playerObj then return false end
    if LPBCS.attempt(function() return playerObj:isAccessLevel("Admin") end) == true then
        return true
    end
    local level = LPBCS.get(playerObj, "getAccessLevel", nil)
    return level ~= nil and tostring(level):lower() == "admin"
end

-- ------------------------------------------------------------- containers

--- True for a container type that reads as a crate. The vanilla crate,
--- smallcrate, militarycrate and SurvivorCrate all carry "crate" in their
--- type, and so does every modded crate seen so far, so this matches the
--- substring rather than a fixed list: a mod's crate is covered without this
--- file having to know the mod exists.
---
--- Memoised because it runs in the display hot path and there are only ever
--- a couple of dozen distinct container types in a save.
local crateTypes = {}

function LPBCS.isCrateType(containerType)
    if containerType == nil then return false end

    local key = tostring(containerType)
    local known = crateTypes[key]
    if known == nil then
        known = string.find(key:lower(), "crate", 1, true) ~= nil
        crateTypes[key] = known
    end
    return known
end

--- True for the containers this mod is willing to sign: crates, cabinets,
--- lockers, anything standing in the world. Deliberately excludes the kinds
--- a sign makes no sense on -- the floor pile, worn inventories and vehicle
--- storage -- and anything belonging to a corpse.
---
--- The CratesOnly sandbox option narrows it further, down to crates alone.
--- That gate sits here rather than in the context menu so that it also takes
--- the signs off everything else: one rule, one place, display and writing
--- both. LPBCS.Config is reached through the global rather than required,
--- because Config requires this file.
---
--- This one sits in the display hot path (every container on every square
--- around the player, several times a second), so it calls straight into
--- Java rather than through the pcall helpers above. Everything it touches
--- is core API that has been there since build 41.
function LPBCS.isSignableContainer(obj, container)
    if not obj or not container then return false end

    local containerType = container:getType()
    if containerType == nil then return false end
    containerType = tostring(containerType)
    if containerType == "" or containerType == "floor" then return false end
    if containerType == "inventorymale" or containerType == "inventoryfemale" then
        return false
    end

    local config = LPBCS.Config
    if config and config.cratesOnly() and not LPBCS.isCrateType(containerType) then
        return false
    end

    if instanceof(obj, "IsoDeadBody") then return false end

    local parent = container:getParent()
    if parent and instanceof(parent, "BaseVehicle") then return false end

    return obj:getSquare() ~= nil
end

--- L'IsoObject d'un conteneur DU MONDE sur lequel on accepte d'ecrire, ou nil.
---
--- isSignableContainer ne suffit pas ici, et ce n'est pas un defaut de sa part :
--- il est ecrit pour le balayage, qui ne lui presente jamais que des objets
--- poses sur une case. La fenetre de butin, elle, construit un bouton pour TOUT
--- -- le sac sur le dos du joueur, le sol, le coffre d'une voiture -- et le
--- dernier test de isSignableContainer, obj:getSquare() ~= nil, est aussi vrai
--- d'un IsoPlayer que d'une commode. Sans ce garde, un sac a dos porte prendrait
--- le titre d'une caisse.
---
--- Le sac se reconnait a getContainingItem() : un conteneur porte appartient a
--- un InventoryItem, un meuble n'appartient a rien. C'est le test que le jeu
--- fait lui-meme avant d'offrir son propre « Renommer »
--- (ISInventoryPage:onBackpackRightMouseDown), et le reprendre ici, c'est nommer
--- exactement les memes conteneurs que lui.
function LPBCS.worldObjectOf(container)
    if not container then return nil end
    if LPBCS.get(container, "getContainingItem", nil) ~= nil then return nil end

    local parent = LPBCS.get(container, "getParent", nil)
    if not parent then return nil end
    if instanceof(parent, "BaseVehicle") then return nil end
    if not LPBCS.isSignableContainer(parent, container) then return nil end

    return parent
end

--- Every (object, container) pair on a square that could carry a sign. One
--- IsoObject may expose several containers, and a wide piece of furniture puts
--- one object on each tile it covers.
--- Returning false from `fn` stops the walk.
---
--- The indices this walks by are deliberately NOT handed out. They are only
--- valid for as long as nothing is built, broken or dropped on the tile, so a
--- caller that kept one would be holding a number that goes stale without
--- saying so. The one place they are needed -- addressing a container over the
--- network -- recomputes them at the moment it sends, in Label.locate.
function LPBCS.eachContainerOnSquare(square, fn)
    if not square then return end

    local objects = square:getObjects()
    if not objects then return end

    for index = 0, objects:size() - 1 do
        local obj = objects:get(index)
        if obj then
            for containerIndex = 0, obj:getContainerCount() - 1 do
                local container = obj:getContainerByIndex(containerIndex)
                if LPBCS.isSignableContainer(obj, container) then
                    if fn(obj, container) == false then return end
                end
            end
        end
    end
end

return LPBCS
