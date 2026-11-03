--[[
    © 2026 Warlord-Fox3. Tous droits réservés / All Rights Reserved.

    Toute réutilisation, modification, redistribution ou inclusion dans un
    modpack sans autorisation écrite préalable est strictement interdite.

    Any reuse, modification, redistribution, or inclusion in a modpack
    without prior written permission is strictly prohibited.
]]

--[[
    LPBCS_Context -- "Write a name on this" in the world right-click menu.

    Worth knowing before touching this file: OnFillWorldObjectContextMenu is
    not always fired. ISWorldObjectContextMenu.doMenu bails out early when the
    Java pass has already claimed the menu, and it only triggers the event at
    all when fetch.safehouseAllowInteract is true:

        if ISWorldObjectContextMenuLogic.createMenuEntries(...) then return true end
        if fetch.safehouseAllowInteract then
            triggerEvent("OnFillWorldObjectContextMenu", ...)
        end

    That second condition is doing the mod a favour: inside a safehouse the
    player has no business in, the entry simply never appears. It is not a
    permission check though, only a menu that stops being built, so
    LPBCS_Server re-applies the rule against a request that arrives anyway.
]]

require "LPBCS_Core"
require "LPBCS_Config"
require "LPBCS_Text"
require "LPBCS_Label"
require "LPBCS_Ink"
require "LPBCS_Scan"
require "TimedActions/ISLPBCSWriteLabel"
require "TimedActions/ISTimedActionQueue"
require "luautils"
require "ISUI/ISWorldObjectContextMenu"
require "ISUI/ISContextMenu"
require "ISUI/ISTextBox"
require "LPBCS_InkBox"

-- Guarded: file scope, so it runs at load. See the note on the same call in
-- ISLPBCSWriteLabel -- a diagnostic must not be able to stop the file loading.
if LPBCS and LPBCS.stamp then
    LPBCS.stamp("LPBCS_Context", LPBCS.PROTOCOL)
end

LPBCS.Context = LPBCS.Context or {}
local Context = LPBCS.Context
local Config = LPBCS.Config
local Label = LPBCS.Label
local Ink = LPBCS.Ink

local STYLE_TEXT = {
    plank = {
        key = "ContextMenu_LPBCS_StylePlank",
        fallback = "On a nailed board",
        tip = "A slat of wood nailed to the front. Reads from across the room.",
        tipKey = "Tooltip_LPBCS_StylePlank",
    },
    paper = {
        key = "ContextMenu_LPBCS_StylePaper",
        fallback = "On a taped note",
        tip = "A sheet stuck to the front. Quick and unfussy.",
        tipKey = "Tooltip_LPBCS_StylePaper",
    },
    painted = {
        key = "ContextMenu_LPBCS_StylePainted",
        fallback = "Painted straight on",
        tip = "Painted onto the wood itself, in the colour of the can you use. Needs a paintbrush and paint.",
        tipKey = "Tooltip_LPBCS_StylePainted",
    },
}

--- The three states of the side, in the order they are offered.
---
--- This used to be one entry that swapped sense -- "move it to the left" on a
--- sign that was not there yet, "let it pick its own side" on one that was --
--- on the reading that there were only two states to move between. There are
--- three: automatic, and each of the two faces pinned by hand. A toggle
--- between two of them could never reach the third, so nothing in the mod
--- could ask for the RIGHT-hand face and be sure of keeping it: automatic
--- gives that face by default, then takes it away again the moment a wall or a
--- crate comes to block it. The state existed in the ModData, in the server
--- and in the renderer, and only the menu could not name it.
---
--- Laid out together, with a tick against the one in force, they read as what
--- they are: one choice, made once, out of three.
---
--- `side` is what the option asks for, so nil on the automatic one -- and nil
--- is exactly the value it has to arrive with at the far end.
local SIDE_TEXT = {
    {
        side = nil,
        key = "ContextMenu_LPBCS_SideAuto",
        fallback = "Auto",
        tip = "Leaves the choice to the mod: the right-hand face, unless a wall or a crate blocks it -- the sign then moves round on its own.",
        tipKey = "Tooltip_LPBCS_SideAuto",
    },
    {
        side = "south",
        key = "ContextMenu_LPBCS_SideLeft",
        fallback = "On the left",
        tip = "Nails the sign to the left-hand face and leaves it there, even if the right one clears.",
        tipKey = "Tooltip_LPBCS_SideLeft",
    },
    {
        side = "east",
        key = "ContextMenu_LPBCS_SideRight",
        fallback = "On the right",
        tip = "Nails the sign to the right-hand face and leaves it there, even if something comes to stand against it.",
        tipKey = "Tooltip_LPBCS_SideRight",
    },
}

-- ------------------------------------------------------------------ menu

local function describe(option, title, description)
    local tooltip = ISWorldObjectContextMenu.addToolTip()
    tooltip:setVisible(false)
    tooltip:setName(title)
    tooltip.description = description
    option.toolTip = tooltip
end

--- Le titre de TYPE, et rien d'autre : « Caisse », « Commode », « Frigo ».
---
--- A NE PAS remplacer par le nom de l'ecriteau, si tentant que ce soit. Il ne
--- sert qu'a departager plusieurs conteneurs sur une meme tuile, et l'entree du
--- menu porte deja « Sign: "Outils" » juste apres : on lirait « Outils --
--- Sign: "Outils" ». Pire, qualify() regroupe sur ce titre pour poser
--- « (en haut) / (en bas) », et deux caisses portant deux ecriteaux differents
--- cesseraient d'etre qualifiees -- au moment precis ou on en a le plus besoin.
---
--- Delegue a Label.typeTitle, qui est le seul endroit du mod ou se fabrique un
--- titre par defaut. L'affichage de la fenetre de butin en a besoin aussi.
local function containerTitle(container)
    return Label.typeTitle(container)
end

--- Every signable container reachable from the clicked tile, deduplicated,
--- ordered top of the stack first.
--- Reads the whole square rather than just the clicked objects: a player
--- aiming at a crate usually clicks the floor tile under it.
---
--- The order is ours, not the square's. eachContainerOnSquare walks
--- square:getObjects() by index, and that index follows the history of what
--- was put down when -- the game stacks with AddSpecialObject(obj,
--- objects:size()), so the order reflects placement, not height, and a
--- reloaded square may not even agree with itself. Two crates one on top of
--- the other came out in whichever order the square happened to hold them.
---
--- So the stacking offset decides instead: getRenderYOffset is 0 for the crate
--- on the floor and the surface height of whatever carries it for the one
--- above -- the same value LPBCS_Sprites has to subtract out when it places a
--- sign. Sorted descending, the menu reads the way the stack looks.
---
--- The sort has to be stable: a wide dresser puts several containers at the
--- same height, and there the discovery order is the only sensible tiebreak.
--- table.sort is not stable, hence the recorded rank.
local function candidates(worldobjects)
    local found, seenContainer, seenSquare = {}, {}, {}

    for _, worldObject in ipairs(worldobjects) do
        local square = LPBCS.get(worldObject, "getSquare", nil)
        if square and not seenSquare[square] then
            seenSquare[square] = true
            LPBCS.eachContainerOnSquare(square, function(obj, container)
                if not seenContainer[container] then
                    seenContainer[container] = true
                    found[#found + 1] = {
                        object = obj,
                        container = container,
                        height = tonumber(LPBCS.get(obj, "getRenderYOffset", 0)) or 0,
                        rank = #found + 1,
                    }
                end
            end)
        end
    end

    table.sort(found, function(a, b)
        if a.height ~= b.height then return a.height > b.height end
        return a.rank < b.rank
    end)

    return found
end

-- ---------------------------------------------------------------- marche

--- Amène le personnage devant la caisse. Rend `atteignable, enMarche`.
---
--- Le menu proposait son entrée à n'importe quelle distance, et au-delà de
--- LPBCS.MAX_WRITE_DISTANCE rien de bon n'en sortait : une écriture mise en
--- file que le moteur abandonnait sans un mot au premier isValid(), un
--- effacement dont la demande partait quand même et revenait en « vous êtes
--- trop loin ». Le joueur devait deviner qu'il fallait s'approcher à la main --
--- ce qu'aucune interaction vanilla ne demande.
---
--- L'ORDRE COMPTE : walkAdj vide la file d'actions avant d'y poser sa marche.
--- Tout ce qui doit suivre -- les transferts d'inventaire de transferIfNeeded
--- compris -- se met en file APRÈS cet appel, jamais avant, sinon la marche
--- l'emporte avec le reste. C'est l'ordre que le menu vanilla tient partout.
---
--- Le second retour existe pour l'effacement et le déplacement : leur demande
--- part au clic, et elle ne le peut plus si le personnage est encore en chemin.
--- Il se lit dans la file elle-même plutôt qu'il ne se redevine : walkAdj a son
--- propre seuil -- environ une case et demie, ET un canReachTo qui refuse la
--- caisse d'en face à travers un mur -- et le recopier ici serait une seconde
--- vérité, libre de dériver de la première.
local function approach(playerObj, object)
    local square = LPBCS.get(object, "getSquare", nil)
    if not square then return false, false end

    local reachable = LPBCS.attempt(function()
        return luautils.walkAdj(playerObj, square)
    end)

    -- nil : luautils n'a pas répondu -- absent d'un build, ou en erreur. On ne
    -- refuse pas l'action pour autant. Sans marche, elle vaut exactement ce
    -- qu'elle valait la veille : jouable de près, perdue de loin.
    if reachable == nil then return true, false end
    if reachable ~= true then return false, false end

    -- « ISWalkToTimedAction » est le nom que ISBaseTimedAction:derive pose en
    -- .Type sur l'action de marche du jeu, et sur lequel hasActionType compare.
    local walking = LPBCS.attempt(function()
        return ISTimedActionQueue.hasActionType(playerObj, "ISWalkToTimedAction")
    end) == true

    return true, walking
end

--- Dit ce que « walkAdj a rendu false » veut dire pour le joueur : la caisse
--- est là, elle se voit, et aucun chemin n'y mène. À ne pas confondre avec le
--- IGUI_LPBCS_TooFar du serveur, qui reste ce qu'il était -- le refus opposé à
--- un client qui aurait menti sur sa position.
local function cannotReach(playerObj)
    LPBCS.sayBad(playerObj, LPBCS.text("IGUI_LPBCS_NoWay",
        "There is no way to get to that container."))
end

-- -------------------------------------------------------------- text box

--- Deux encres sont-elles la meme ? A un millieme pres, parce qu'elles ont fait
--- l'aller-retour par le ModData et par clampFloat, et qu'une egalite stricte
--- sur des flottants qui ont voyage ne veut rien dire.
local function sameInk(existing, wanted)
    if type(existing) ~= "table" or type(wanted) ~= "table" then return true end
    for _, channel in ipairs({ "r", "g", "b" }) do
        local here = tonumber(existing[channel])
        local there = tonumber(wanted[channel])
        if here == nil or there == nil then return true end
        if math.abs(here - there) > 0.001 then return false end
    end
    return true
end

--- L'ACCUSE DE RECEPTION DE SETINK, et le seul filet contre un serveur muet.
---
--- Un serveur en protocole 3 ne connait pas le mot SetInk : il l'enregistre
--- comme commande inconnue et ne repond rien. Le joueur choisirait alors le
--- rouge dans la liste et verrait arriver du noir, sans un mot.
---
--- Et le garde de version ne peut PAS le dire a sa place, ce qui surprend assez
--- pour etre ecrit : sur un serveur dedie, l'ecriture n'est jamais envoyee par le
--- client -- c'est le serveur qui rejoue l'action et sert la sienne en direct --
--- donc permitted() compare le protocole du serveur avec lui-meme et ne se
--- declenche jamais. Le silence est la seule information disponible, alors on la
--- lit.
---
--- Dit UNE FOIS par session. C'est un desaccord d'installation : le repeter a
--- chaque caisse serait du bruit, et l'avoir dit une fois suffit a expliquer
--- toutes les suivantes.
---
--- A L'OUVERTURE DE LA FENETRE, jamais au clic qui vient d'envoyer la demande.
--- La reponse ne peut pas etre arrivee dans la meme image que l'envoi : appele
--- la, ce garde accuserait CHAQUE premiere ecriture d'une partie en ligne, y
--- compris contre un serveur parfaitement a jour. Il faut lui laisser un
--- aller-retour, et la prochaine caisse est le premier moment ou l'on sait.
local inkAsked, inkAnswered, inkWarned = false, false, false

local function warnIfUnanswered(playerObj)
    if inkWarned or inkAnswered or not inkAsked then return end
    inkWarned = true
    LPBCS.sayBad(playerObj, LPBCS.text("IGUI_LPBCS_VersionSkew",
        "This server is running an older version of this mod."))
end

--- Range le choix d'encre, ici et sur la copie serveur du joueur.
---
--- LE LOCAL D'ABORD ET TOUJOURS : en solo et chez un hote coop il n'y a qu'une
--- copie du personnage, et l'ecrire est tout le travail. La commande ne part que
--- d'un vrai client, ou la copie qui servira l'ecriture est dans un autre
--- processus -- c'est la meme distinction que submitRename tient dans
--- LPBCS_Inventory.
---
--- ET AVANT TOUT LE RESTE, parce que c'est une course : sur un serveur dedie
--- c'est le SERVEUR qui reconstruit l'action et decide la couleur, et il ne peut
--- le faire correctement que si ce paquet est arrive. Il a le temps de
--- l'ecriture pour cela -- soixante ticks, cent en peinture -- sauf pour un
--- joueur aux actions instantanees, ou getDuration() rend 1. Le pire cas reste
--- borne : la preference PRECEDENTE, jamais une couleur que le joueur ne porte
--- pas, puisque le serveur reverifie ce qu'il resout.
local function submitInk(playerObj, style, choice)
    if choice == nil then return end

    local kind = Ink.kindOf(style)
    if not Ink.setPreference(playerObj, kind, choice) then return end
    if LPBCS.attempt(isClient) ~= true then return end

    inkAsked = true
    LPBCS.attempt(sendClientCommand, playerObj, LPBCS.MODULE, "SetInk", {
        v = LPBCS.PROTOCOL,
        kind = kind,
        id = choice,
    })
end

local function onTextEntered(_target, button, playerObj, object, container, style)
    if not button or button.internal ~= "OK" then return end
    if not playerObj or not object or not container then return end

    local modal = button.parent
    local entry = modal and modal.entry
    local text = entry and entry:getText() or ""
    text = Label.sanitize(text)
    if text == "" then return end

    -- nil quand la boite est celle du jeu : une seule encre, ou aucune.
    local choice = nil
    if modal and modal.selectedInk then
        choice = LPBCS.attempt(function() return modal:selectedInk() end)
    end

    submitInk(playerObj, style, choice)

    -- APRES submitInk, et c'est ce qui rend juste tout ce qui suit : la
    -- preference vient d'etre posee, donc l'encre lue ici est celle que le
    -- joueur vient de choisir, et transferIfNeeded plus bas deplace LE POT
    -- CHOISI plutot que le premier venu.
    local requirement = Ink.requirement(playerObj, style)

    -- L'ECRITEAU, pas le nom. Un conteneur que le jeu de base a nomme
    -- « GARAGE » n'a rien d'ecrit dessus : ecrire « GARAGE » dessus est une
    -- premiere ecriture, pas une redite, et ce garde-la l'avalait en silence --
    -- le joueur payait son encre du regard et ne voyait aucune planche venir.
    --
    -- LA COULEUR EN FAIT PARTIE. Sans elle, repeindre en rouge un ecriteau qui
    -- dit deja la meme chose en bleu serait avale de la meme facon : le joueur
    -- choisit une couleur, valide, et rien ne bouge ni ne s'explique.
    local existing = Label.signOn(object, container)
    if existing and existing.text == text and existing.style == style
        and sameInk(existing, requirement.ink) then
        return
    end

    if requirement.ok ~= true then
        LPBCS.sayBad(playerObj, LPBCS.resolveMessage(requirement.message))
        return
    end

    -- AVANT les transferts, et l'ordre n'est pas négociable : approach() vide
    -- la file d'actions pour y poser sa marche, donc un transfert mis en file
    -- plus tôt partirait avec. Le personnage arriverait devant la caisse les
    -- mains vides et l'écriture s'arrêterait là.
    if not approach(playerObj, object) then
        cannotReach(playerObj)
        return
    end

    -- Both hands-worth of kit has to be on the player, not in a bag in a bag,
    -- or the action would play out with nothing to write with.
    if ISWorldObjectContextMenu.transferIfNeeded then
        if requirement.tool then
            ISWorldObjectContextMenu.transferIfNeeded(playerObj, requirement.tool)
        end
        if requirement.paint then
            ISWorldObjectContextMenu.transferIfNeeded(playerObj, requirement.paint)
        end
    end

    ISTimedActionQueue.add(
        ISLPBCSWriteLabel:new(playerObj, object, container, text, style))
end

function Context.promptFor(playerObj, object, container, style)
    if not playerObj or not object or not container then return end

    local existing = Label.read(object, container)
    local current = existing and existing.text or ""

    -- Ici, et pas au clic qui vient d'envoyer la demande : voir sa note.
    warnIfUnanswered(playerObj)

    -- Une seule encre n'est pas un choix, et zero est le joueur qui ecrit les
    -- mains nues -- RequireWritingTool eteint, ou Ink.requirement rend ok sans
    -- rien tenir. Dans les deux cas la boite reste celle du jeu : une liste
    -- deroulante a une entree n'apprend rien et coute une ligne d'ecran.
    local choices = Ink.available(playerObj, style)

    -- LU A L'APPEL, jamais capture a la portee du fichier. Le jeu charge
    -- media/lua/client par ordre de nom, donc LPBCS_Context (C) passe avant
    -- LPBCS_InkBox (I) et un local pris en tete de fichier vaudrait nil pour
    -- toujours. Meme piege que celui documente en tete d'ISLPBCSWriteLabel.
    local class = ISTextBox
    local withInk = (#choices > 1) and ISLPBCSInkBox ~= nil
    if withInk then class = ISLPBCSInkBox end

    local playerNum = playerObj:getPlayerNum()
    local modal = class:new(0, 0, 300, 190,
        LPBCS.text("IGUI_LPBCS_PromptTitle",
            "What goes on this container? (%1 characters at most)", Config.maxTextLength()),
        current, nil, onTextEntered, playerNum, playerObj, object, container, style)

    -- AVANT initialise(), qui est le moment ou la ligne se construit.
    if withInk then
        modal:setInkChoices(choices, Ink.preference(playerObj, Ink.kindOf(style)))
    end

    modal:initialise()
    modal:addToUIManager()

    if JoypadState.players[playerNum + 1] then
        setJoypadFocus(playerNum, modal)
    end
end

local function onErase(playerObj, object, container)
    if not playerObj or not object or not container then
        LPBCS.log("Menu", "effacer : clic ignore (joueur/objet/conteneur absent)")
        return
    end

    -- Said at QUEUE time, not at :complete. The two are worth telling apart:
    -- an entry that never fires and an action the queue accepted and then
    -- dropped look identical from the far end -- nothing happens, nothing is
    -- said -- and they are fixed in completely different places.
    --
    -- Built through attempt() so that a constructor that is not there raises
    -- into the log instead of into the menu handler, where it would take the
    -- click down with it and leave nothing at all behind: no action, no
    -- message, no clue.
    local action = LPBCS.attempt(function()
        return ISLPBCSWriteLabel:newErase(playerObj, object, container)
    end)
    if not action then
        LPBCS.log("Menu", "effacer : l'action n'a pas pu etre construite "
            .. "(ISLPBCSWriteLabel.newErase absent ou en erreur)")
        return
    end

    local reachable, walking = approach(playerObj, object)
    if not reachable then
        LPBCS.log("Menu", "effacer : aucun chemin jusqu'a la caisse")
        cannotReach(playerObj)
        return
    end

    -- `marche` est le troisieme mot, et il est la pour que le deuxieme ne mente
    -- plus. Une action posee derriere une marche est INVALIDE au moment du clic
    -- -- le personnage est encore loin -- et le sera jusqu'a son arrivee. Sans
    -- ce mot, le journal accuserait d'un defaut ce qui est le cours normal.
    LPBCS.log("Menu", "effacer : mise en file (intent=%s, valide=%s, marche=%s)",
        tostring(action.intent),
        tostring(LPBCS.attempt(function() return action:isValid() end)),
        tostring(walking))

    -- Sent from HERE, and this is the only place on a client where it can be.
    --
    -- On a dedicated server the engine replays the action in its own process --
    -- that run is the one that reaches the world -- and rebuilds it through
    -- :new(character, object, container, text, style). Everything newErase sets
    -- is gone by then, so the server's copy cannot tell an erase from a write
    -- with nothing to write. And the client reaches none of the action's later
    -- hooks: not :complete(), not :perform() -- the logs show it queues and
    -- stops there. This handler is the last point at which the player's choice
    -- both exists and is running on the client.
    --
    -- No-op in single player, where isClient() is false: there the queued action
    -- runs in this same process with its intent intact, and serves itself.
    --
    -- Sauf si le personnage marche encore : LPBCS_Server re-verifie la distance
    -- (withinReach) et repondrait « vous etes trop loin » a une demande partie
    -- d'un joueur en chemin -- le refus qu'on est precisement en train de faire
    -- disparaitre. :start() la reprendra, une fois arrive.
    if not walking then action:dispatchFromClient() end

    ISTimedActionQueue.add(action)
end

--- `side` is a face name, or nil to hand the choice back to the mod. Nil
--- travels here as the missing fourth parameter of the menu option, which is
--- exactly the value it has to arrive with.
local function onSide(playerObj, object, container, side)
    if not playerObj or not object or not container then return end

    -- The multiplayer race, in miniature. This menu was built on the LOCAL
    -- replicated copy: the entry offering "move it to the left" was written when
    -- the sign had no side, and the face may have arrived over the network
    -- between the menu opening and the click. The entry then asks for the face
    -- the sign already carries.
    --
    -- Nothing should go: thirty ticks of animation to change nothing, and a
    -- round trip that came back as "the sign could not be moved" in front of a
    -- player looking at their sign hanging exactly where they wanted it.
    --
    -- L'ECRITEAU, pas le nom : un repli n'a pas de face, donc son `side` nil
    -- repondait « deja en place » a la demande automatique, et l'entree se
    -- taisait au lieu de partir se faire refuser proprement par le serveur.
    local existing = Label.signOn(object, container)
    if existing and existing.side == side then return end

    local action = LPBCS.attempt(function()
        return ISLPBCSWriteLabel:newMove(playerObj, object, container, side)
    end)
    if not action then
        LPBCS.log("Menu", "deplacer : l'action n'a pas pu etre construite "
            .. "(ISLPBCSWriteLabel.newMove absent ou en erreur)")
        return
    end

    local reachable, walking = approach(playerObj, object)
    if not reachable then
        LPBCS.log("Menu", "deplacer : aucun chemin jusqu'a la caisse")
        cannotReach(playerObj)
        return
    end

    LPBCS.log("Menu", "deplacer : mise en file (intent=%s, side=%s, marche=%s)",
        tostring(action.intent), tostring(side), tostring(walking))

    -- Same reason as the erase above: a move carries no text either, so nothing
    -- of what it is survives the server's rebuild of the action. Et la meme
    -- reserve : rien ne part tant que le personnage marche, sinon le serveur
    -- refuse la demande pour la distance qu'elle est en train de combler.
    if not walking then action:dispatchFromClient() end

    ISTimedActionQueue.add(action)
end

-- ------------------------------------------------------------ menu build

--- Fait entourer la caisse dans le monde quand cette entrée est survolée.
---
--- C'est la seule réponse qui ne dépende ni de l'ordre ni du libellé : on
--- montre la caisse elle-même. Le jeu sait déjà le faire -- son menu de
--- ramassage s'en sert pour exactement le même problème -- et le gestionnaire
--- vanilla se charge aussi de tout éteindre quand le survol s'en va.
---
--- À poser aussi sur les options de style : ISContextMenu:prerender ne retient
--- d'option surlignée que si la souris est sur ce menu-là, donc entrer dans le
--- sous-menu éteindrait la caisse au moment précis où on choisit quoi écrire
--- dessus. Les sous-menus héritent du .player dont le gestionnaire a besoin.
local function pointAt(option, entry)
    if not ISWorldObjectContextMenu.initWorldItemHighlightOption then return end
    LPBCS.attempt(ISWorldObjectContextMenu.initWorldItemHighlightOption,
        option, entry.object)
end

--- The "Position" branch: the three states of the side, with a tick against
--- the one the sign is in.
---
--- The ticked entry stays clickable, and does not have to be defended against
--- here: onSide already drops a request for the face the sign is on. That
--- guard was written for the multiplayer race -- a menu built before the face
--- arrived over the network -- and it covers this too, which is a click on the
--- side that is already in force.
local function addSideMenu(subMenu, playerObj, entry, existing)
    local title = LPBCS.text("ContextMenu_LPBCS_Side", "Position")
    local option = subMenu:addOption(title)
    pointAt(option, entry)
    describe(option, title,
        LPBCS.text("Tooltip_LPBCS_Side",
            "Which face of the container the sign hangs on."))

    -- Third level, and getNew has to be handed the menu the branch hangs off
    -- rather than the root: that is where it reads the .player the vanilla
    -- highlight handler needs. Vanilla nests this deep in the same way -- see
    -- the call in ISWorldObjectContextMenu.
    local sideMenu = ISContextMenu:getNew(subMenu)
    subMenu:addSubMenu(option, sideMenu)

    for _, wording in ipairs(SIDE_TEXT) do
        local label = LPBCS.text(wording.key, wording.fallback)
        local sideOption = sideMenu:addOption(
            label, playerObj, onSide, entry.object, entry.container, wording.side)
        pointAt(sideOption, entry)
        describe(sideOption, label, LPBCS.text(wording.tipKey, wording.tip))

        -- nil == nil is what marks the automatic entry, so it needs no case of
        -- its own. Guarded like the highlight above: a tick is worth nothing
        -- next to a menu that fails to build.
        if existing.side == wording.side and sideMenu.setOptionChecked then
            LPBCS.attempt(sideMenu.setOptionChecked, sideMenu, sideOption, true)
        end
    end
end

--- Les deux arguments disent deux choses differentes, et les confondre est le
--- defaut que ce menu portait :
---
---   `sign`     l'ecriteau REEL, ou nil. Lui seul a une face a choisir.
---   `anything` ce qu'il y a a retirer -- un ecriteau, ou un simple nom du jeu
---              de base. « Gratter » est le seul moyen d'enlever un nom pose
---              par le « Renommer » vanilla : sa boite refuse le texte vide,
---              donc sans cette entree-la un nom serait definitif.
local function addStyleOptions(subMenu, playerObj, entry, sign, anything)
    for _, style in ipairs(Config.allowedStyles()) do
        local wording = STYLE_TEXT[style] or STYLE_TEXT.plank
        local option = subMenu:addOption(
            LPBCS.text(wording.key, wording.fallback),
            playerObj, Context.promptFor, entry.object, entry.container, style)
        pointAt(option, entry)

        local requirement = Ink.requirement(playerObj, style)
        if requirement.ok ~= true then
            option.notAvailable = true
            describe(option,
                LPBCS.text(wording.key, wording.fallback),
                LPBCS.resolveMessage(requirement.message))
        else
            describe(option,
                LPBCS.text(wording.key, wording.fallback),
                LPBCS.text(wording.tipKey, wording.tip))
        end
    end

    -- Only ever offered on a sign that is already there: there is no side to
    -- choose for a name nobody has written yet -- et un nom du jeu de base ne
    -- pend a aucune face, il n'est ecrit nulle part.
    if sign then
        addSideMenu(subMenu, playerObj, entry, sign)
    end

    if anything then
        local option = subMenu:addOption(
            LPBCS.text("ContextMenu_LPBCS_Erase", "Scrape the name off"),
            playerObj, onErase, entry.object, entry.container)
        pointAt(option, entry)
    end
end

--- Où cette entrée se trouve dans une pile de `count`, en toutes lettres.
--- Les entrées sont déjà triées de haut en bas.
local function stackWord(position, count)
    if position == 1 then
        return LPBCS.text("ContextMenu_LPBCS_StackTop", "on top")
    elseif position == count then
        return LPBCS.text("ContextMenu_LPBCS_StackBottom", "at the bottom")
    end
    return LPBCS.text("ContextMenu_LPBCS_StackMiddle", "in the middle")
end

--- Ajoute « (en haut) », « (en bas) » aux entrées qui se liraient pareil.
---
--- Seulement à celles-là : une caisse et un frigo portent déjà deux noms
--- différents, les qualifier serait du bruit. Deux caisses empilées, elles,
--- donnent deux fois le même mot et rien ne dit laquelle est laquelle.
---
--- Le regroupement se fait sur le titre, pas sur le type, parce que c'est le
--- titre que le joueur lit.
local function qualify(titles)
    local counts, seen = {}, {}
    for _, title in ipairs(titles) do
        counts[title] = (counts[title] or 0) + 1
    end

    local out = {}
    for index, title in ipairs(titles) do
        if counts[title] < 2 then
            out[index] = title
        else
            seen[title] = (seen[title] or 0) + 1
            out[index] = title .. " (" .. stackWord(seen[title], counts[title]) .. ")"
        end
    end
    return out
end

local function onFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    if not Config.writingEnabled() then return end

    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj or playerObj:isDead() then return end

    local found = candidates(worldobjects)
    if #found == 0 then return end

    if test then return ISWorldObjectContextMenu.setTest() end

    local several = #found > 1

    -- Les titres d'abord, tous ensemble : on ne peut pas savoir si « Caisse »
    -- a besoin d'être précisé avant d'avoir vu les autres entrées.
    local titles = {}
    if several then
        for index, entry in ipairs(found) do
            titles[index] = containerTitle(entry.container)
        end
        titles = qualify(titles)
    end

    for index, entry in ipairs(found) do
        -- Ce que le menu ANNONCE suit l'ecriteau, pas le nom : une caisse que
        -- le « Renommer » du jeu de base a nommee n'a rien d'ecrit dessus, et
        -- l'annoncer comme un ecriteau proposait de « reecrire » ce que
        -- personne n'avait ecrit.
        local sign = Label.signOn(entry.object, entry.container)
        local existing = Label.read(entry.object, entry.container)

        local name
        if sign then
            name = LPBCS.text("ContextMenu_LPBCS_Rewrite", "Sign: \"%1\"", sign.text)
        else
            name = LPBCS.text("ContextMenu_LPBCS_Write", "Write a name on this")
        end
        if several then
            name = titles[index] .. " -- " .. name
        end

        local option = context:addOption(name)
        pointAt(option, entry)

        local subMenu = ISContextMenu:getNew(context)
        context:addSubMenu(option, subMenu)
        addStyleOptions(subMenu, playerObj, entry, sign, existing)
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)

-- ------------------------------------------------------------- server say

--- The server answers every write, successful or not. A refusal is shown to
--- the player; a success only has to nudge the display, because the sign
--- itself arrives as replicated ModData a moment later.
local function onServerCommand(module, command, args)
    if module ~= LPBCS.MODULE then return end
    if type(args) ~= "table" then return end

    -- La reponse a SetInk, sous SON PROPRE NOM. Elle n'a pas voulu de
    -- SignResult, que LPBCS_Inventory ecoute pour relacher le verrou du
    -- renommage : un refus d'encre emprunte a ce nom-la deferait un renommage
    -- en cours qui n'a rien a voir avec lui.
    --
    -- Sa reception vaut surtout pour ce qu'elle prouve -- que ce serveur connait
    -- le mot. Voir warnIfUnanswered : c'est son silence qui parle.
    if command == "InkResult" then
        inkAnswered = true
        if not args.ok then
            local refusal = LPBCS.resolveMessage(args)
            if refusal then LPBCS.sayBad(getPlayer(), refusal) end
        end
        return
    end

    if command ~= "SignResult" then return end

    local playerObj = getPlayer()
    if args.ok then
        LPBCS.Scan.invalidate(nil)
        return
    end

    local message = LPBCS.resolveMessage(args)
    if message then LPBCS.sayBad(playerObj, message) end
end

Events.OnServerCommand.Add(onServerCommand)

--- Read the registry out once the game is up, on the client's own list.
---
--- This is what would have named the file at fault at startup, instead of
--- leaving it to be guessed from the shape of a malformed packet three rounds
--- later. It NAMES; it refuses nothing.
Events.OnGameStart.Add(function()
    LPBCS.checkBuild({
        "LPBCS_Core", "LPBCS_Label", "ISLPBCSWriteLabel",
        "LPBCS_Context", "LPBCS_Scan", "LPBCS_Inventory", "LPBCS_Moveables",
        "LPBCS_InkBox",
    })
end)

return Context
