--[[
    © 2026 Warlord-Fox3. Tous droits réservés / All Rights Reserved.

    Toute réutilisation, modification, redistribution ou inclusion dans un
    modpack sans autorisation écrite préalable est strictement interdite.

    Any reuse, modification, redistribution, or inclusion in a modpack
    without prior written permission is strictly prohibited.
]]

--[[
    ISLPBCSWriteLabel -- standing in front of the crate and writing on it.

    Structured after ISPaintSignAction, which is the closest thing vanilla has
    to "mark this piece of furniture": same anim, same hand model override,
    same habit of spending the paint only once the action actually completes.

    The action never writes the sign itself. It sends the request and lets the
    server decide, so that a client which lies about its coordinates, its
    distance or its pen gets refused rather than obeyed.
]]

require "TimedActions/ISBaseTimedAction"
require "LPBCS_Core"
require "LPBCS_Label"
require "LPBCS_Ink"

ISLPBCSWriteLabel = ISBaseTimedAction:derive("ISLPBCSWriteLabel")

local Label = LPBCS.Label
local Ink = LPBCS.Ink

-- The age of THIS file, sent as `av` beside LPBCS.PROTOCOL's `v`. The two are
-- separate on purpose: `v` vouches for LPBCS_Core, `av` for the file that
-- actually built the request. Nothing is ever refused on `av` -- it exists so
-- that the server's log says how old the thing that spoke to it was, which is
-- the one question a malformed packet could never answer before.
--
-- CODE EN DUR, et c'est tout son intérêt : ce nombre est la seule chose qui
-- donne encore des dents à LPBCS.buildMismatches(). Les sept autres fichiers du
-- mod s'estampillent avec LPBCS.PROTOCOL, donc ils relisent la valeur du Core
-- chargé et sont d'accord PAR CONSTRUCTION -- même venus d'une installation
-- vieille de deux versions. Seul un numéro écrit ici peut trahir son âge.
--
-- Il suit donc les générations du protocole, et se bump avec lui. Sur une
-- installation saine `av` et `v` sont égaux ; ils ne divergent que sur une
-- panachée, ce qui est précisément le diagnostic qu'ils servent à poser. L'avoir
-- laissé à 2 quand le protocole est passé à 3 a fait accuser au registre un
-- fichier qui n'avait pas bougé -- très exactement ce qu'il existe pour éviter.
local ACTION_VERSION = 5

-- Guarded, and the guard is not paranoia. This call sits at FILE SCOPE, so it
-- runs the moment the loader reaches this file -- unlike everything else here,
-- which is deferred inside a function. This file's name starts with I and
-- LPBCS_Core's with L, so a loader that walks its directories in name order can
-- get here first. An unguarded call would then raise on a nil, and the whole
-- file would fail to load: no ISLPBCSWriteLabel at all, and writing, erasing and
-- moving would ALL stop working together.
--
-- A registry that exists to diagnose problems must never be able to cause one.
if LPBCS and LPBCS.stamp then
    LPBCS.stamp("ISLPBCSWriteLabel", ACTION_VERSION)
end

-- What this action means to do. Spelled out and carried on the action itself
-- rather than inferred from which flags happen to be set: an action that lost
-- its flags used to fall through to the WRITE branch, which then posted a write
-- with nothing to write and got itself refused at the far end.
local INTENTS = { write = true, erase = true, move = true }

--- What this action is for, or nil when that did not survive.
---
--- `erasing` and `moving` are still read, so an action built by an older caller
--- still says what it is. Note what is NOT derived: "write". Inferring a write
--- from the absence of everything else is the exact mistake this file is being
--- rebuilt to stop making -- a write is only ever a write because :new said so.
function ISLPBCSWriteLabel:resolveIntent()
    if INTENTS[self.intent] then return self.intent end
    if self.moving then return "move" end
    if self.erasing then return "erase" end
    return nil
end

function ISLPBCSWriteLabel:isValid()
    if not self.object or not self.container then return false end
    if not LPBCS.isSignableContainer(self.object, self.container) then return false end

    local square = LPBCS.get(self.object, "getSquare", nil)
    if not square then return false end

    local distance = LPBCS.attempt(function()
        return self.character:DistTo(square:getX(), square:getY())
    end)
    if type(distance) == "number" and distance > LPBCS.MAX_WRITE_DISTANCE then
        return false
    end

    local intent = self:resolveIntent()

    -- An action whose intent did not survive must still be let through, which
    -- reads backwards until you follow what the queue does with a refusal: it
    -- DROPS the action. :complete would never run, so the explanation below
    -- would never be said, and the player would click "Scrape the name off" and
    -- get nothing at all -- no effect, no error, nothing to report.
    -- isValid refuses what is IMPOSSIBLE; what is merely malformed goes all the
    -- way and explains itself.
    if intent == nil then return true end

    -- Erasing needs no tool: you can always scratch a name off.
    if intent == "erase" then return true end

    -- Nor does moving one. It is the same board with the same name on it, and
    -- there has to be a board to move.
    if intent == "move" then
        return Label.read(self.object, self.container) ~= nil
    end

    return Ink.requirement(self.character, self.style).ok == true
end

function ISLPBCSWriteLabel:update()
    self.character:setMetabolicTarget(Metabolics.LightDomestic)
end

function ISLPBCSWriteLabel:start()
    -- Le rattrapage de l'envoi que le menu n'a PAS fait.
    --
    -- LPBCS_Context ne dispatche plus au clic quand il vient de mettre une
    -- marche en file : LPBCS_Server re-verifie la distance et aurait refuse en
    -- « vous etes trop loin » une demande partie d'un joueur encore en chemin.
    -- Le voici arrive -- c'est ce que veut dire l'action qui demarre.
    --
    -- Ici et pas plus tard parce que c'est le PREMIER crochet de l'action :
    -- StartAction l'appelle avant que le moteur ne commence a interroger
    -- isValid(), donc il est atteint dans des cas ou :perform() et :complete()
    -- ne le sont pas. Dans son propre attempt() pour que Label.locate, qui parle
    -- a la case, ne puisse pas emporter l'animation avec lui.
    --
    -- Rien ne part deux fois : `dispatched` garde les trois points d'envoi, et
    -- la copie que le serveur dedie rejoue s'arrete sur isClient().
    LPBCS.attempt(function() self:dispatchFromClient() end)

    -- All presentation, and every global it reaches for -- CharacterActionAnims,
    -- the sound system -- exists only where there is a screen. The engine also
    -- runs this action in the dedicated server's process, where they are nil, so
    -- this degrades instead of raising. Raising here would take the action down
    -- with it, and on a server that run is the one that reaches the world.
    LPBCS.attempt(function()
        self:setActionAnim(CharacterActionAnims.Paint)
        if self.style == "painted" then
            self:setOverrideHandModels("PaintBrush", nil)
            self.sound = self.character:playSound("Painting")
        end
        self.character:faceThisObject(self.object)
    end)
end

function ISLPBCSWriteLabel:stop()
    if self.sound then self.character:stopOrTriggerSound(self.sound) end
    ISBaseTimedAction.stop(self)
end

--- Sends the requests that :complete() cannot carry, from the side that still
--- knows what they are.
---
--- The engine rebuilds this action in the server's process through
--- :new(character, object, container, text, style), so by the time :complete()
--- runs there, everything newErase and newMove set is gone and every rebuilt
--- action looks like a write. A write survives that trip -- its text is one of
--- the rebuilt parameters -- but an erase and a move do not, and no amount of
--- care inside :complete() can recover what was never handed to it.
---
--- So they go out from the client, where the player's choice is still known.
--- Called from the context menu handler -- the only place proven to run on the
--- client, which queues the action and then reaches none of its later hooks:
--- not :complete(), not :perform(). The cost is that the sign goes the moment
--- the entry is clicked rather than when the character has finished scraping.
---
--- Guarded by `dispatched` because it is called from more than one place and the
--- same request must never go twice.
function ISLPBCSWriteLabel:dispatchFromClient()
    if self.dispatched then return false end
    if LPBCS.attempt(isClient) ~= true then return false end

    local intent = self:resolveIntent()
    if intent ~= "erase" and intent ~= "move" then return false end

    local location = Label.locate(self.object, self.container)
    if not location then return false end

    local args = {
        v = LPBCS.PROTOCOL,
        av = ACTION_VERSION,
        x = location.x,
        y = location.y,
        z = location.z,
        index = location.index,
        containerIndex = location.containerIndex,
    }

    local command = "EraseSign"
    if intent == "move" then
        command = "SetSide"
        args.side = self.side
    end

    self.dispatched = true
    LPBCS.log("Action", "%s envoye depuis le client (intent=%s side=%s)",
        command, tostring(intent), tostring(self.side))
    LPBCS.attempt(sendClientCommand, self.character, LPBCS.MODULE, command, args)
    return true
end

function ISLPBCSWriteLabel:perform()
    if self.sound then self.character:stopOrTriggerSound(self.sound) end

    -- A belt to the braces in LPBCS_Context, and normally a no-op: the menu
    -- handler has already sent this one and `dispatched` says so. Kept because
    -- it costs nothing and would pick up the request on any build where this
    -- hook does run on the client -- on the one this was traced against, it does
    -- not run there at all.
    self:dispatchFromClient()

    -- needed to remove from queue / start next.
    ISBaseTimedAction.perform(self)
end

function ISLPBCSWriteLabel:complete()
    -- The dedicated server's process has no menu -- LPBCS_Context is client-only
    -- -- so nothing here was ever built by a player choosing something. An action
    -- reaching this point on that side carries no text, no intent and no face,
    -- and serving it would mean the server answering a question nobody asked.
    --
    -- The player's real request is already on its way as a client command; this
    -- side's only job is to stay out of its way. Said out loud rather than left
    -- to the isClient() test further down, because that test only decides HOW to
    -- deliver a request -- it does not decide whether there is one.
    local intent = self:resolveIntent()

    -- BEFORE any decision, including the server guard below. Said on every side
    -- that reaches here, so that the two logs can be laid side by side and the
    -- question "who ran this, and what was in it?" has an answer rather than a
    -- theory. An earlier version of this file returned from the guard first and
    -- so never said what the server's copy contained -- which is precisely the
    -- thing worth knowing.
    LPBCS.log("Action", "complete : intent=%s text=%s style=%s side=%s "
        .. "(client=%s serveur=%s coop=%s)",
        tostring(intent), tostring(self.text), tostring(self.style),
        tostring(self.side), tostring(LPBCS.attempt(isClient)),
        tostring(LPBCS.attempt(isServer)), tostring(LPBCS.attempt(isCoopHost)))

    -- No default branch, and that is the whole repair. An action that has lost
    -- its intent used to land in the WRITE arm below, post a write with nothing
    -- to write, and be refused at the far end with "that request made no sense"
    -- -- a refusal aimed at the player for something no player did. It stops
    -- here instead, before the wire and before the ink.
    if intent == nil then
        LPBCS.log("Action", "action sans intention lisible -- rien n'est envoye, "
            .. "aucune encre depensee")
        return false
    end

    -- Addressing is recomputed here rather than at queue time: the object's
    -- index on its square is only stable while nothing else is built, broken
    -- or dropped on that tile in the meantime.
    local location = Label.locate(self.object, self.container)
    if not location then return false end

    local args = {
        -- Which language this is written in. A server that predates the field
        -- ignores it; one that is older than the number refuses the request
        -- instead of doing its best with it.
        v = LPBCS.PROTOCOL,
        -- And how old the file that built the request is. Never refused on,
        -- only logged: `v` can agree while this file is the one that is behind.
        av = ACTION_VERSION,
        x = location.x,
        y = location.y,
        z = location.z,
        index = location.index,
        containerIndex = location.containerIndex,
    }

    -- Each intention gets its own command, and none of them is spelled as
    -- another one with a field left out. Erasing used to be "a write with an
    -- empty text", which made the absence of a text an order to destroy -- and
    -- a move, which carries no text at all, was one mis-routed packet away
    -- from being read as exactly that.
    local command
    if intent == "move" then
        -- The server must not go looking for a pen, and must not touch what the
        -- sign says. Everything else about the action -- the anim, the reach,
        -- the refusal path -- is shared.
        command = "SetSide"
        args.side = self.side
    elseif intent == "erase" then
        command = "EraseSign"
    else
        -- Checked before Ink, not after: consuming the paint first meant every
        -- write that turned out to have nothing to write still cost a charge.
        local text = Label.sanitize(self.text)
        if text == "" then
            -- Expected, not alarming: this is what an erase or a move looks like
            -- after the server rebuilt it through :new. Its real request already
            -- went out from the client. Nothing to do here, and above all
            -- nothing to infer -- reading an absent text as "erase this" is the
            -- shortcut that used to delete signs on a move.
            LPBCS.log("Action", "action rejouee sans texte utilisable -- rien "
                .. "n'est fait ici, aucune encre depensee")
            return false
        end

        local requirement = Ink.requirement(self.character, self.style)
        if requirement.ok ~= true then return false end

        command = "SetSign"
        args.text = text
        args.style = self.style
        args.r = requirement.ink and requirement.ink.r or nil
        args.g = requirement.ink and requirement.ink.g or nil
        args.b = requirement.ink and requirement.ink.b or nil

        Ink.consume(requirement)
    end

    local serve = LPBCS.Server and ({
        SetSign = LPBCS.Server.apply,
        EraseSign = LPBCS.Server.erase,
        SetSide = LPBCS.Server.setSide,
    })[command]

    -- THIS is where a sign actually gets written, and it is not where the file
    -- used to claim it was.
    --
    -- The engine re-runs this action in the dedicated server's process, and it
    -- is the server's run that carries the player's typed text -- the client
    -- never reaches :complete() at all. So the in-process branch below is not a
    -- single-player convenience: on a server it is the ONLY path that arrives.
    -- Gating it on isDedicatedServer(), as a previous version did, stopped
    -- writing, erasing and moving all at once.
    --
    -- What that server-side run canNOT do is say what it is FOR. The engine
    -- rebuilds it through :new(character, object, container, text, style), so
    -- everything newErase and newMove set -- intent, erasing, moving, side -- is
    -- gone by the time it lands here, and every rebuilt action looks like a
    -- write. Erasing and moving therefore travel by client command instead, sent
    -- from LPBCS_Context where the player's choice is still known.
    if isClient() then
        -- :perform() may already have sent this one -- see dispatchFromClient.
        -- A client that runs both hooks must not ask twice.
        if not self.dispatched then
            self.dispatched = true
            LPBCS.attempt(sendClientCommand, self.character, LPBCS.MODULE, command, args)
        end
    elseif serve then
        serve(self.character, args)
    end

    -- Single player has no reply to wait for, so the display has to be told
    -- here. On a server this only shortens the wait: the sign still arrives
    -- as replicated ModData, and the sweep would have caught it anyway.
    if LPBCS.Scan and LPBCS.Scan.invalidate then LPBCS.Scan.invalidate(nil) end

    return true
end

function ISLPBCSWriteLabel:getDuration()
    if self.character:isTimedActionInstant() then return 1 end

    local intent = self:resolveIntent()
    if intent == "move" then return 30 end
    if intent == "erase" then return 40 end
    if self.style == "painted" then return 100 end
    return 60
end

--- Writing a name on a container. Needs something to write with.
function ISLPBCSWriteLabel:new(character, object, container, text, style)
    local o = ISBaseTimedAction.new(self, character)
    o.object = object
    o.container = container
    o.text = text
    o.style = style or LPBCS.DEFAULT_STYLE
    o.intent = "write"
    o.erasing = false
    o.moving = false
    o.maxTime = o:getDuration()
    o.caloriesModifier = 2
    return o
end

--- Scraping the name off. Its own constructor for the same reason the move has
--- one: it is not a write with the text left blank, and nothing about it should
--- be able to reach the writing path by accident. Costs no tool -- you can
--- always scratch a name off -- so the style stays nil and :start leaves the
--- character's hands empty.
function ISLPBCSWriteLabel:newErase(character, object, container)
    local o = ISBaseTimedAction.new(self, character)
    o.object = object
    o.container = container
    o.intent = "erase"
    o.erasing = true
    o.moving = false
    o.maxTime = o:getDuration()
    o.caloriesModifier = 2
    return o
end

--- Taking the sign off one face of the container and putting it on the other.
--- `side` is a face name, or nil to hand the choice back to the mod.
---
--- Its own constructor rather than a seventh argument to :new, because it
--- carries none of what a write carries: no text, no style, and so no pen. The
--- style is left nil on purpose, which is also what keeps :start from putting a
--- paintbrush in the character's hand.
function ISLPBCSWriteLabel:newMove(character, object, container, side)
    local o = ISBaseTimedAction.new(self, character)
    o.object = object
    o.container = container
    o.side = side
    o.intent = "move"
    o.erasing = false
    o.moving = true
    o.maxTime = o:getDuration()
    o.caloriesModifier = 2
    return o
end

return ISLPBCSWriteLabel
