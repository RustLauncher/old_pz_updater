--[[
    © 2026 Warlord-Fox3. Tous droits réservés / All Rights Reserved.

    Toute réutilisation, modification, redistribution ou inclusion dans un
    modpack sans autorisation écrite préalable est strictement interdite.

    Any reuse, modification, redistribution, or inclusion in a modpack
    without prior written permission is strictly prohibited.
]]

--[[
    LPBCS_Server -- the authoritative half of writing on a container.

    Nothing the client sends is trusted. The square is re-resolved from the
    coordinates, every index is bounds-checked, the distance is re-measured,
    the safehouse rule is re-applied and the tool is looked for again in the
    player's real inventory. A modified client that asks to write on a crate
    on the other side of the map, or inside someone else's safehouse, is
    refused here and told why.

    This file is also what runs in single player: media/lua/server is loaded
    there too, and ISLPBCSWriteLabel calls the matching function here directly
    rather than sending a command that nothing would receive.

    Four requests, four functions, four names on the wire -- Server.apply,
    Server.rename, Server.erase, Server.setSide. They are deliberately NOT
    variations on one another with a field left out. That is what they used to
    be: erasing was a write whose text happened to be empty, so a request
    carrying no text at all -- a move, arriving at a server that did not yet
    know the word "SetSide" -- was read as an order to destroy the sign, and
    answered with a success. Anything added here should be a request that says
    what it is.

    Server.rename is the newest, and it is the half of the conversation this
    mod never had. The loot window's own rename wrote into a name that does not
    travel, so it reached nobody and was overwritten locally a quarter of a
    second later. It is a request now.
]]

require "LPBCS_Core"
require "LPBCS_Config"
require "LPBCS_Text"
require "LPBCS_Label"
require "LPBCS_Ink"

-- Guarded: file scope, so it runs at load. See the note on the same call in
-- ISLPBCSWriteLabel -- a diagnostic must not be able to stop the file loading.
if LPBCS and LPBCS.stamp then
    LPBCS.stamp("LPBCS_Server", LPBCS.PROTOCOL)
end

LPBCS.Server = LPBCS.Server or {}
local Server = LPBCS.Server
local Config = LPBCS.Config
local Label = LPBCS.Label
local Ink = LPBCS.Ink

local REQUEST_COOLDOWN_MS = 400
local lastRequestAt = {}

local function rateLimited(playerObj)
    local key = LPBCS.usernameOf(playerObj) or "singleplayer"
    local now = LPBCS.nowMs()
    if now - (lastRequestAt[key] or 0) < REQUEST_COOLDOWN_MS then return true end
    lastRequestAt[key] = now
    return false
end

local function answer(playerObj, command, ok, message)
    if not isServer() or not sendServerCommand or not playerObj then
        -- Single player: no round trip, so the refusal is said on the spot.
        if not ok and message then
            LPBCS.sayBad(playerObj, LPBCS.text(message.key, message.fallback))
        end
        return
    end

    local payload = { ok = ok == true }
    if message then
        payload.key = message.key
        payload.fallback = message.fallback
    end
    LPBCS.attempt(sendServerCommand, playerObj, LPBCS.MODULE, command, payload)
end

local function reply(playerObj, ok, message)
    answer(playerObj, "SignResult", ok, message)
end

--- The answer to SetInk, and it must NOT be SignResult.
---
--- SignResult means "your write, rename, erase or move was answered", and
--- LPBCS_Inventory listens for it: any ok = false there releases the rename
--- lock. An ink refusal borrowing that name would silently undo a rename that
--- is still in flight and has nothing to do with it.
---
--- Its other job is to exist at all. A version 3 server does not know the word
--- SetInk and answers nothing -- see the unknown-command branch at the bottom of
--- this file -- so the client reads SILENCE as "this server cannot honour a
--- colour" and says so. Nothing else can tell it: on a dedicated server the
--- write is never sent by the client, so permitted()'s version guard compares
--- the server's own protocol with itself and never fires.
local function replyInk(playerObj, ok, message)
    answer(playerObj, "InkResult", ok, message)
end

--- A client newer than this server is speaking a language this file may not
--- know all the words of. Refuse rather than guess: guessing is exactly how a
--- move request came to be read as an erase.
---
--- Only ever refuses a client from the FUTURE. An older one sends no version at
--- all, and is served as before -- there is nothing it can ask for that was not
--- already understood.
---
--- Its own function since SetInk needs it too, and SetInk cannot go through
--- permitted(): it names a person, not a square.
local function fromTheFuture(args)
    return type(args) == "table" and type(args.v) == "number"
        and args.v > LPBCS.PROTOCOL
end

-- ------------------------------------------------------------------ rules

--- Safehouse permission, with the same helper the vanilla loot window uses
--- before it offers its own rename. Admins are exempt so a moderator can
--- clean up a griefed sign without joining the safehouse first.
local function mayWriteHere(playerObj, square)
    if not Config.restrictToSafehouse() then return true end
    if LPBCS.isAdmin(playerObj) then return true end
    if not SafeHouse or not SafeHouse.isSafehouseAllowInteract then return true end

    local allowed = LPBCS.attempt(function()
        return SafeHouse.isSafehouseAllowInteract(square, playerObj)
    end)
    -- A nil answer means the check could not run; refusing on that would lock
    -- the feature out entirely on builds where the helper moved.
    if allowed == nil then return true end
    return allowed == true
end

local function withinReach(playerObj, square)
    local distance = LPBCS.attempt(function()
        return playerObj:DistTo(square:getX(), square:getY())
    end)
    if type(distance) ~= "number" then return true end
    return distance <= LPBCS.MAX_WRITE_DISTANCE + 1
end

-- ----------------------------------------------------------------- apply

--- Everything that has to be true before this player may touch that sign, in
--- one place: the rule is on, the container is really there, they are standing
--- next to it, and it is not in somebody else's safehouse.
---
--- Returns the object and its container, or nil having already told the player
--- why not. Shared by both requests, so a client cannot get round a check by
--- asking to MOVE a sign rather than to write one.
local function permitted(playerObj, args)
    if not playerObj or type(args) ~= "table" then return nil end

    -- Refused OUT LOUD. This used to `return nil` on the spot: the request
    -- evaporated, nothing was written and nothing was said, which is the last
    -- way a sign could refuse to move or to come off without a word. Two clicks
    -- in a row, or two players at the same crate, and one of them simply did
    -- not happen.
    if rateLimited(playerObj) then
        reply(playerObj, false, {
            key = "IGUI_LPBCS_TooQuick",
            fallback = "Give it a moment before asking again.",
        })
        return nil
    end

    -- Same guard for everyone, in the same position it has always been in --
    -- after the rate limiter, before the rules. Only its body moved out, so
    -- that SetInk could share it without sharing the rest of this function.
    if fromTheFuture(args) then
        reply(playerObj, false, {
            key = "IGUI_LPBCS_VersionSkew",
            fallback = "This server is running an older version of this mod.",
        })
        LPBCS.log("Server", "requete en protocole %d, ce serveur parle le %d",
            args.v, LPBCS.PROTOCOL)
        return nil
    end

    if not Config.writingEnabled() then
        reply(playerObj, false, {
            key = "IGUI_LPBCS_Disabled",
            fallback = "Writing on containers is disabled on this server.",
        })
        return nil
    end

    local obj, container, square = Label.resolve(args)
    if not obj or not container or not square then
        reply(playerObj, false, {
            key = "IGUI_LPBCS_NoContainer",
            fallback = "That container is no longer there.",
        })
        return nil
    end

    if not withinReach(playerObj, square) then
        reply(playerObj, false, {
            key = "IGUI_LPBCS_TooFar",
            fallback = "You are too far from that container.",
        })
        return nil
    end

    if not mayWriteHere(playerObj, square) then
        reply(playerObj, false, {
            key = "IGUI_LPBCS_NotYourSafehouse",
            fallback = "This container is inside a safehouse you do not belong to.",
        })
        return nil
    end

    return obj, container
end

--- Writes one sign. Returns true when the world changed.
---
--- Never erases, and the refusal below is the whole point of this file's
--- second version. It used to read a blank text as "scrape this one off",
--- which meant the ABSENCE of a text was an order to destroy -- and a request
--- that is not a write at all has no text in it. A move sent to a server whose
--- dispatcher did not yet know the word "SetSide" landed here, sanitised nil
--- into "", wiped the sign and answered ok. Erasing is EraseSign now, asked
--- for by name, and a write that arrives without something to write is
--- malformed rather than fatal.
function Server.apply(playerObj, args)
    -- A request carrying a FACE is a move, whatever door it came through, and
    -- it is served rather than refused. This is the mis-routing that started
    -- all of it: a move landing here was read as "erase this" by the first
    -- version and as "that made no sense" by the second, which left the player
    -- with no way to move a sign at all. Asking for the left-hand face now
    -- succeeds, whatever happens on the way.
    --
    -- The test is a field that is PRESENT and valid. An absent text still means
    -- nothing but "malformed" -- an invented face routes nowhere -- and blank
    -- counts as absent, because a packet built in-process has no `text` field
    -- while the same packet off the wire has one holding "".
    --
    -- Routed BEFORE permitted(), deliberately: setSide runs its own permitted(),
    -- and the rate limiter would otherwise refuse that second call as a repeat
    -- of this one -- turning a served request back into a silent no-op.
    if type(args) == "table" and LPBCS.isFace(args.side)
        and LPBCS.isBlank(args.text) then
        LPBCS.log("Server", "SetSign porteur d'une face de '%s' -- route vers SetSide",
            tostring(LPBCS.usernameOf(playerObj) or "singleplayer"))
        return Server.setSide(playerObj, args)
    end

    local obj, container = permitted(playerObj, args)
    if not obj then return false end

    local text = args.text ~= nil and Label.sanitize(args.text) or ""
    if text == "" then
        reply(playerObj, false, {
            key = "IGUI_LPBCS_BadRequest",
            fallback = "That request made no sense and was ignored.",
        })
        LPBCS.log("Server", "SetSign sans texte de '%s' -- ignore",
            tostring(LPBCS.usernameOf(playerObj) or "singleplayer"))
        return false
    end

    local style = args.style
    if not LPBCS.isStyle(style) or not Config.styleAllowed(style) then
        style = Config.defaultStyle()
    end

    local requirement = Ink.requirement(playerObj, style)
    if requirement.ok ~= true then
        reply(playerObj, false, requirement.message)
        return false
    end

    -- The ink colour is the one the client reported. It is cosmetic, it is
    -- clamped, and recomputing it here would only disagree with the pen the
    -- player actually picked up.
    local ink = {
        r = LPBCS.clampFloat(args.r ~= nil and args.r or requirement.ink.r, 0, 1),
        g = LPBCS.clampFloat(args.g ~= nil and args.g or requirement.ink.g, 0, 1),
        b = LPBCS.clampFloat(args.b ~= nil and args.b or requirement.ink.b, 0, 1),
    }

    -- The side is not validated here: Label normalises it, the same way it
    -- owns normaliseStyle. Left out of the request, the sign keeps the face it
    -- is already on.
    local written = Label.write(obj, container, text, ink, style,
        LPBCS.usernameOf(playerObj), args.side)
    if not written then
        reply(playerObj, false, {
            key = "IGUI_LPBCS_WriteFailed",
            fallback = "The name could not be written.",
        })
        return false
    end

    Label.transmit(obj)
    reply(playerObj, true)

    LPBCS.log("Sign", "'%s' wrote \"%s\" at %d,%d,%d",
        tostring(LPBCS.usernameOf(playerObj) or "singleplayer"),
        text, args.x, args.y, args.z)

    return true
end

-- ---------------------------------------------------------------- rename

--- Le renommage venu de la fenetre de butin du jeu de base. Rend true quand le
--- monde a change.
---
--- Sa propre commande, comme les trois autres. Un renommage n'est pas une
--- ecriture -- il ne coute rien -- et n'est pas un effacement -- il ne detruit
--- rien : le deguiser en SetSign sans encre aurait rendu SetSign ambigu, qui est
--- exactement la pente sur laquelle un deplacement a fini par etre lu comme un
--- ordre de destruction.
---
--- Ne consulte PAS Ink.requirement, et c'est le choix de fond de cette commande.
--- Renommer un conteneur est gratuit dans le jeu de base ; le mod capte ce
--- geste, il ne le taxe pas. Un joueur sans stylo garde le droit de nommer ses
--- caisses comme il l'a toujours eu -- il ne choisit simplement ni le style ni
--- la couleur, que seul le menu du mod propose.
---
--- Tout le RESTE des regles s'applique : permitted() est le meme que pour une
--- ecriture, donc la portee, le safehouse, le limiteur de debit et la resolution
--- du conteneur sont ceux de toujours. Le client refuse deja de partir quand
--- l'ecriture est desactivee sur le serveur, mais un client modifie ne s'en
--- prive pas, et c'est ici que ca se decide.
---
--- Un texte vide n'est PAS un effacement. Le jeu de base l'ecarte avant meme
--- d'arriver jusqu'ici, donc le cas ne devrait pas se presenter -- et s'il se
--- presente, il est refuse plutot que devine. Voir Server.apply : l'absence d'un
--- champ n'a jamais valu un ordre.
---
--- Et une caisse SANS ecriteau n'est pas un ordre non plus. Renommer, c'est
--- changer un texte qui existe ; sur un conteneur vierge le geste appartient au
--- jeu de base, qui le fait tres bien tout seul, et le capter y faisait naitre un
--- ecriteau complet que personne n'avait demande. Le client s'arrete deja avant
--- d'envoyer (voir LPBCS_Inventory) : ce qui arrive ici malgre tout vient d'un
--- client modifie, ou d'un ecriteau gratte pendant que le paquet volait. Label
--- tranche dans les deux cas, et c'est lui l'autorite -- pas l'expediteur.
function Server.rename(playerObj, args)
    local obj, container = permitted(playerObj, args)
    if not obj then return false end

    local text = type(args) == "table" and args.text ~= nil
        and Label.sanitize(args.text) or ""
    if text == "" then
        reply(playerObj, false, {
            key = "IGUI_LPBCS_BadRequest",
            fallback = "That request made no sense and was ignored.",
        })
        LPBCS.log("Server", "RenameSign sans texte de '%s' -- ignore",
            tostring(LPBCS.usernameOf(playerObj) or "singleplayer"))
        return false
    end

    -- Refuse quand il n'y a pas d'ecriteau -- la raison de loin la plus probable,
    -- l'ecriture elle-meme ne pouvant echouer que sur un conteneur que permitted()
    -- vient pourtant de valider. D'ou BadRequest et non WriteFailed : rien n'a
    -- rate, c'est la demande qui n'avait pas lieu d'etre.
    local written = Label.rename(obj, container, text,
        LPBCS.usernameOf(playerObj))
    if not written then
        reply(playerObj, false, {
            key = "IGUI_LPBCS_BadRequest",
            fallback = "That request made no sense and was ignored.",
        })
        LPBCS.log("Server", "RenameSign de '%s' sur un conteneur sans ecriteau "
            .. "en %d,%d,%d -- ignore",
            tostring(LPBCS.usernameOf(playerObj) or "singleplayer"),
            args.x, args.y, args.z)
        return false
    end

    Label.transmit(obj)
    reply(playerObj, true)

    LPBCS.log("Sign", "'%s' renamed the container at %d,%d,%d to \"%s\"",
        tostring(LPBCS.usernameOf(playerObj) or "singleplayer"),
        args.x, args.y, args.z, text)

    return true
end

-- ----------------------------------------------------------------- erase

--- Scrapes one sign off. Returns true when the world changed.
---
--- Its own command rather than a write with nothing in it, for the reason
--- spelled out on Server.apply: destroying a sign has to be something a client
--- ASKS for, never something inferred from what a request is missing. Costs
--- nothing and asks for no tool, same as before.
function Server.erase(playerObj, args)
    local obj, container = permitted(playerObj, args)
    if not obj then return false end

    Label.erase(obj, container)
    Label.transmit(obj)
    reply(playerObj, true)

    LPBCS.log("Sign", "'%s' erased the sign at %d,%d,%d",
        tostring(LPBCS.usernameOf(playerObj) or "singleplayer"),
        args.x, args.y, args.z)

    return true
end

-- --------------------------------------------------------------- setSide

--- Moves one sign to the other face of its container, or hands the choice back
--- to the mod. Returns true when the world changed.
---
--- Deliberately not a write: the text, the ink and the style are left alone,
--- and Ink.requirement is never consulted. Prying a board off and nailing it to
--- the next face along asks nothing of the player's pockets, the same way
--- scraping a name off does not.
function Server.setSide(playerObj, args)
    local obj, container = permitted(playerObj, args)
    if not obj then return false end

    local changed, ok = Label.setSide(obj, container, args.side)
    if not ok then
        reply(playerObj, false, {
            key = "IGUI_LPBCS_MoveFailed",
            fallback = "The sign could not be moved.",
        })
        return false
    end

    -- Already on the face it was asked for. In multiplayer the menu is built on
    -- the LOCAL replicated copy, so two clicks before the first transmitModData
    -- comes back -- or two players at the same crate -- name a face the server
    -- is already holding. Nothing to write and nothing to replicate, but above
    -- all nothing to REFUSE: the sign is where the player wanted it, which is
    -- the outcome they asked for.
    if not changed then
        reply(playerObj, true)
        return false
    end

    Label.transmit(obj)
    reply(playerObj, true)

    LPBCS.log("Sign", "'%s' moved the sign at %d,%d,%d to %s",
        tostring(LPBCS.usernameOf(playerObj) or "singleplayer"),
        args.x, args.y, args.z, tostring(args.side or "auto"))

    return true
end

-- ----------------------------------------------------------------- setInk

--- Remembers which pen or which can this player writes with. Returns true when
--- the preference changed hands.
---
--- THE ONLY REQUEST IN THIS FILE THAT NAMES A PERSON RATHER THAN A SQUARE, and
--- everything odd about it follows from that.
---
--- It exists because the colour cannot travel on the write. The engine rebuilds
--- the timed action in this process through
--- :new(character, object, container, text, style), so on a dedicated server it
--- is the server that reaches :complete() and calls Ink.requirement -- a choice
--- carried on the action would be dropped there, the way `intent` and `side`
--- were. The choice is therefore a preference on the character, and this puts it
--- on the copy of that character which will actually be asked.
---
--- It does NOT go through permitted(), and the two reasons are worth keeping
--- apart:
---
---   * permitted() calls Label.resolve, which wants coordinates this request
---     does not have. Inventing a square to make it fit would be the same
---     disguising that made a move readable as an erase.
---
---   * the RATE LIMITER would break it outright. permitted() already documents
---     this hazard for the SetSide re-route just above; here the sequence is
---     SetInk then SetSign, and the gap between them is ONE FRAME for a player
---     whose actions are instant -- getDuration() returns 1 for them. Sharing
---     lastRequestAt would refuse the write with "give it a moment". And a
---     dropped SetInk is a silently wrong colour: a limiter that can drop it
---     manufactures the very bug this feature exists to remove. The bound is on
---     the payload -- MAX_INK_ID and the character class, both checked inside
---     Ink.setPreference -- not on the cadence. Nothing here touches the world.
---
--- Membership of Ink.available is deliberately NOT required. It looks like a
--- stronger check and is a weaker one: a player who puts the pen down between
--- choosing and the packet landing would have their choice refused, and would
--- keep writing in the old colour with no way to see why. Ownership is asked at
--- writing time instead, in Ink.requirement, where a wrong answer still has
--- somewhere to fall back to.
function Server.setInk(playerObj, args)
    if not playerObj or type(args) ~= "table" then return false end

    if fromTheFuture(args) then
        replyInk(playerObj, false, {
            key = "IGUI_LPBCS_VersionSkew",
            fallback = "This server is running an older version of this mod.",
        })
        LPBCS.log("Server", "SetInk en protocole %d, ce serveur parle le %d",
            args.v, LPBCS.PROTOCOL)
        return false
    end

    -- Reachable only from a modified client -- the menu does not open when
    -- writing is off -- and refused for the same reason as the other four.
    if not Config.writingEnabled() then
        replyInk(playerObj, false, {
            key = "IGUI_LPBCS_Disabled",
            fallback = "Writing on containers is disabled on this server.",
        })
        return false
    end

    if not Ink.setPreference(playerObj, args.kind, args.id) then
        replyInk(playerObj, false, {
            key = "IGUI_LPBCS_BadRequest",
            fallback = "That request made no sense and was ignored.",
        })
        LPBCS.log("Server", "SetInk illisible de '%s' (kind=%s id=%s) -- ignore",
            tostring(LPBCS.usernameOf(playerObj) or "singleplayer"),
            tostring(args.kind), tostring(args.id))
        return false
    end

    replyInk(playerObj, true)

    LPBCS.log("Ink", "'%s' ecrit desormais avec %s (%s)",
        tostring(LPBCS.usernameOf(playerObj) or "singleplayer"),
        tostring(args.id), tostring(args.kind))

    return true
end

-- --------------------------------------------------------------- commands

--- One handler, one command each, and a word in the console for anything else.
---
--- The silent `return` this replaces is how a version gap used to look from
--- here: nothing in the log, nothing on screen, and -- before Server.apply
--- stopped inferring erases -- a sign gone. A command this file does not know
--- means the client is newer than the server, which is worth saying once.
local unknownReported = {}

local function onClientCommand(module, command, playerObj, args)
    if module ~= LPBCS.MODULE then return end

    -- What actually came off the wire, said once per request. The two version
    -- stamps are here and nowhere else: `v` is LPBCS_Core's, `av` the action
    -- file's, and a request that arrives malformed can now at least say how old
    -- the thing that built it was. Nothing is refused on either -- reading a
    -- missing field as evidence about somebody's install is exactly the mistake
    -- that sent three diagnoses after the wrong culprit.
    LPBCS.log("Server", "recu '%s' de '%s' : text=%s side=%s kind=%s id=%s v=%s av=%s",
        tostring(command),
        tostring(LPBCS.usernameOf(playerObj) or "singleplayer"),
        type(args) == "table" and tostring(args.text) or "?",
        type(args) == "table" and tostring(args.side) or "?",
        type(args) == "table" and tostring(args.kind) or "?",
        type(args) == "table" and tostring(args.id) or "?",
        type(args) == "table" and tostring(args.v) or "?",
        type(args) == "table" and tostring(args.av) or "?")

    if command == "SetSign" then
        Server.apply(playerObj, args)
    elseif command == "RenameSign" then
        Server.rename(playerObj, args)
    elseif command == "EraseSign" then
        Server.erase(playerObj, args)
    elseif command == "SetSide" then
        Server.setSide(playerObj, args)
    elseif command == "SetInk" then
        Server.setInk(playerObj, args)
    elseif not unknownReported[command] then
        unknownReported[command] = true
        LPBCS.log("Server", "commande inconnue '%s' -- client plus recent que "
            .. "le serveur ? Ce serveur parle le protocole %d",
            tostring(command), LPBCS.PROTOCOL)
    end
end

Events.OnClientCommand.Add(onClientCommand)

--- Read the registry out once, when the server is up.
---
--- On the event rather than at load time, because this file may well be the one
--- that loaded first and the others would not have stamped themselves yet.
--- The expected list is what a SERVER process should be holding: LPBCS_Context
--- and LPBCS_Scan are client-only and their absence here is not a fault.
Events.OnServerStarted.Add(function()
    LPBCS.checkBuild({
        "LPBCS_Core", "LPBCS_Label", "ISLPBCSWriteLabel", "LPBCS_Server",
        "LPBCS_Moveables",
    })
end)

return Server
