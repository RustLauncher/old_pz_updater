--[[
    © 2026 Warlord-Fox3. Tous droits réservés / All Rights Reserved.

    Toute réutilisation, modification, redistribution ou inclusion dans un
    modpack sans autorisation écrite préalable est strictement interdite.

    Any reuse, modification, redistribution, or inclusion in a modpack
    without prior written permission is strictly prohibited.
]]

--[[
    LPBCS_Inventory -- la fenêtre de butin dit la même chose que l'écriteau.

    Ce fichier existe parce que le jeu de base prend un INSTANTANÉ du nom d'un
    conteneur et le garde. Dans refreshBackpacks :

        local title = getTextOrNull("IGUI_ContainerTitle_" .. type) or ...
        if container:getCustomName() then title = container:getCustomName() end
        containerButton = self:addContainerButton(container, nil, title, title)

    ce titre part dans button.name ET dans button.tooltip, puis plus bas dans
    self.title. Trois affichages, une seule lecture -- et cette lecture ne se
    refait que lorsque refreshBackpacks se refait, c'est-à-dire quand le joueur
    change de case ou de direction. Debout devant sa caisse, il ne la refait
    jamais.

    D'où venaient les noms différents :

      - l'écriteau lisait la ModData, quatre fois par seconde ;
      - le titre et l'infobulle lisaient setCustomName, une fois pour toutes ;
      - et setCustomName ne voyage pas, donc chaque client se l'écrivait à
        lui-même depuis son propre balayage -- dans son rayon d'affichage
        seulement, et pas du tout quand les écriteaux étaient masqués.

    La réparation n'est pas de forcer des refreshBackpacks : c'est de rendre le
    nom AU MOMENT OÙ IL S'AFFICHE. Deux accroches, et il en faut bien deux :

      1. OnRefreshInventoryWindowContainers, phase "buttonsAdded". Elle part
         toujours -- elle est hors du `if not self.onCharacter` qui se ferme
         juste au-dessus -- et AVANT la boucle qui fait
         self.title = containerButton.name. Corriger button.name là, c'est
         laisser le jeu poser sa barre de titre lui-même, gratuitement.

      2. Une enveloppe de :prerender(), cadencée au quart de seconde. Elle seule
         couvre le cas qui n'a aucun événement : un écriteau écrit par un AUTRE
         joueur arrive par ObjectModDataPacket, et rien côté Lua ne l'annonce --
         il n'existe pas d'événement de réception de ModData. Sans elle, une
         fenêtre restée ouverte garderait l'ancien nom indéfiniment.

    L'infobulle suit sans rien de plus : ISButton:updateTooltip relit self.tooltip
    à chaque image tant que la souris est dessus.

    Et l'autre moitié de la conversation, celle que le mod n'avait jamais eue :
    le « Renommer » du jeu de base écrivait dans setCustomName, que personne
    d'autre ne lit, et le balayage remettait l'ancien texte par-dessus au quart
    de seconde suivant. Il passe désormais par RenameSign -- MAIS seulement quand
    il y a un écriteau à renommer.

    Ce « seulement » est tout le sujet. Renommer une caisse est un geste du jeu de
    base, et sur une caisse vierge il n'a rien demandé au mod : le capter quand
    même y faisait naître un écriteau complet -- planche, encre par défaut, auteur
    -- sauvegardé et répliqué, que le joueur ne pouvait plus retirer par là où il
    l'avait obtenu, la boîte du jeu refusant le texte vide et gratter un écriteau
    ne se demandant que par le menu du mod. Sans écriteau, les deux enveloppes
    rendent donc la main entière au jeu de base ; le nom continue de s'afficher
    par le repli de Label.read, comme il l'a toujours fait, mais il reste un nom.
]]

require "LPBCS_Core"
require "LPBCS_Config"
require "LPBCS_Text"
require "LPBCS_Label"
require "LPBCS_Scan"
require "ISUI/ISInventoryPage"
require "ISUI/ISTextBox"

-- Guarded: file scope, so it runs at load. See the note on the same call in
-- ISLPBCSWriteLabel -- a diagnostic must not be able to stop the file loading.
if LPBCS and LPBCS.stamp then
    LPBCS.stamp("LPBCS_Inventory", LPBCS.PROTOCOL)
end

LPBCS.Inventory = LPBCS.Inventory or {}
local Inventory = LPBCS.Inventory
local Config = LPBCS.Config
local Label = LPBCS.Label

-- Le même quart de seconde que le balayage, et pour la même raison : c'est la
-- cadence à laquelle un changement venu du réseau doit se voir, pas celle à
-- laquelle une fenêtre se redessine.
local REFRESH_MS = 250

-- Combien de temps un renommage tout juste envoyé s'affiche avant que la vérité
-- reprenne la main d'elle-même. Volontairement court : c'est un filet contre un
-- paquet perdu, pas une seconde source de vérité.
local PENDING_MS = 3000

-- -------------------------------------------------------------- le verrou
--
-- Le nom que ce joueur vient de taper, tant que la vérité ne l'a pas rattrapé.
--
-- Sans lui, le renommage clignote : le clic envoie la demande, le jeu rafraîchit
-- ses boutons dans la foulée, et l'affichage -- qui lit maintenant la ModData --
-- rend encore l'ANCIEN texte le temps d'un aller-retour serveur. Le joueur tape
-- « Outils », voit « Clous » revenir, puis « Outils ». C'est très exactement le
-- symptôme qu'on est en train de faire disparaître.
--
-- Ce n'est PAS un verrou sur Label.mirror. Le miroir est devenu inoffensif : du
-- jour où toute écriture passe d'abord par la ModData, il ne recopie plus qu'une
-- valeur que la vérité vient de produire, et il ne peut plus contredire
-- personne.

local pending = {}

local function holdRename(container, text)
    if not container then return end
    pending[container] = { text = text, at = LPBCS.nowMs() }
end

--- Lâche tout : le refus du serveur est arrivé, la vérité est celle qu'on avait
--- déjà sous les yeux avant de taper.
---
--- Appelé sur un refus qui ne dit pas de quel conteneur il parle -- et n'a pas à
--- le dire : les demandes sont sérialisées par le limiteur de débit de
--- permitted(), donc celle qu'on vient de refuser est la dernière partie.
---
--- Rien d'autre à défaire. Ce chemin ne s'emprunte que sur un conteneur qui porte
--- DÉJÀ un écriteau -- c'est le garde des deux enveloppes plus bas -- et le texte
--- de la ModData l'emporte sur tout dans Label.read. L'affichage était donc resté
--- juste pendant tout l'aller-retour, sauf ici, où le verrou lui mettait le nom
--- demandé par-dessus ; l'oublier suffit à le rendre.
local function releaseAll()
    pending = {}
end

--- Le nom à afficher pour ce conteneur, verrou compris. Rend le verrou de
--- lui-même dès que la vérité l'a rattrapé : c'est la sortie normale, et elle
--- n'a besoin d'aucun accusé de réception.
local function displayNameFor(obj, container)
    local truth = Label.displayName(obj, container)

    local held = pending[container]
    if not held then return truth end

    if truth == held.text or (LPBCS.nowMs() - held.at) > PENDING_MS then
        pending[container] = nil
        return truth
    end

    return held.text
end

-- ------------------------------------------------------------ l'affichage

--- Remet les boutons d'une fenêtre en accord avec les écriteaux.
---
--- Muet sur tout ce qui n'est pas un conteneur du monde signable : un sac porté,
--- le sol, un coffre de voiture et l'inventaire du joueur gardent exactement le
--- titre et l'infobulle du jeu de base. C'est LPBCS.worldObjectOf qui tranche,
--- et son test sur getContainingItem() est ce qui écarte les sacs -- le même que
--- le jeu fait lui-même avant d'offrir son « Renommer ».
local function applyTo(page)
    local buttons = page and page.backpacks
    if type(buttons) ~= "table" then return end

    for index = 1, #buttons do
        local button = buttons[index]
        local container = button and button.inventory
        local obj = container and LPBCS.worldObjectOf(container)

        if obj then
            local name = displayNameFor(obj, container)
            if name ~= nil and name ~= "" then
                button.name = name

                -- L'infobulle du sol est nil et doit le rester : le jeu s'en
                -- sert pour dire « ce bouton-là n'en a pas ». On remplace celles
                -- qui existent, on n'en invente pas.
                if button.tooltip ~= nil then button.tooltip = name end

                -- La barre de titre. Inutile depuis "buttonsAdded" -- le jeu la
                -- repose lui-même quelques lignes plus bas, à partir du
                -- button.name qu'on vient de corriger -- mais indispensable
                -- depuis prerender, où plus personne ne la recalculera.
                if page.inventory ~= nil and container == page.inventory then
                    page.title = name
                end
            end
        end
    end
end

--- Enveloppé pour de bon, et ce n'est pas de la prudence de principe : ceci
--- tourne dans le rendu de la fenêtre d'inventaire. Une erreur Lua qui
--- remonterait d'ici emporterait refreshBackpacks au milieu de sa
--- reconstruction. Un écriteau qui ne s'affiche pas est un défaut ; une fenêtre
--- d'inventaire qui disparaît en est un autre, sans commune mesure.
function Inventory.refresh(page)
    LPBCS.attempt(applyTo, page)
end

-- -------------------------------------------------------------- l'horloge

local appliedAt = {}

local function throttled(page)
    local now = LPBCS.nowMs()
    if (now - (appliedAt[page] or 0)) < REFRESH_MS then return end
    appliedAt[page] = now
    Inventory.refresh(page)
end

-- ----------------------------------------------------------------- le nom

--- Envoie le renommage là où tout le monde le lira. Rend true si la demande est
--- bien partie.
local function submitRename(playerObj, obj, container, text)
    local location = Label.locate(obj, container)
    if not location then
        LPBCS.log("Inventory", "renommage : conteneur introuvable sur sa case")
        return false
    end

    local args = {
        v = LPBCS.PROTOCOL,
        x = location.x,
        y = location.y,
        z = location.z,
        index = location.index,
        containerIndex = location.containerIndex,
        text = text,
    }

    -- Pas de nom local optimiste, et c'est le garde des enveloppes qui le rend
    -- inutile : on n'arrive ici QUE sur un conteneur qui porte déjà un écriteau,
    -- dont le texte l'emporte sur le nom dans Label.read. Écrire le nom
    -- n'afficherait donc rien, et le balayage le réécrirait au quart de seconde
    -- suivant. Le verrou ci-dessous est ce qui tient l'affichage, et lui seul.
    --
    -- Conséquence assumée : sur un serveur resté en protocole 2, qui ne connaît
    -- pas le mot « RenameSign » et ne répond rien du tout, le renommage d'un
    -- écriteau existant se voit pendant PENDING_MS puis s'efface. C'était déjà
    -- le sort que lui réservait le balayage.
    if LPBCS.attempt(isClient) == true then
        LPBCS.attempt(sendClientCommand, playerObj, LPBCS.MODULE, "RenameSign", args)
    elseif LPBCS.Server and LPBCS.Server.rename then
        -- Solo et hôte coop : media/lua/server est chargé ici aussi, donc la
        -- moitié autoritaire tourne dans le même processus. Même motif que
        -- ISLPBCSWriteLabel, qui sert les trois autres commandes de cette façon.
        LPBCS.Server.rename(playerObj, args)
    else
        LPBCS.log("Inventory", "renommage : ni client ni serveur -- rien n'est envoye")
        return false
    end

    holdRename(container, text)
    if LPBCS.Scan and LPBCS.Scan.invalidate then LPBCS.Scan.invalidate(nil) end
    return true
end

-- ------------------------------------------------------------- enveloppes

if ISInventoryPage and type(ISInventoryPage.prerender) == "function"
    and not ISInventoryPage.LPBCS_wrapped then

    -- La sentinelle. Un rechargement du Lua -- le bouton de la console de debug,
    -- un retour au menu principal -- rejoue ce fichier, et sans elle la capture
    -- ci-dessous prendrait NOTRE enveloppe pour base : récursion infinie, dès la
    -- première image, sur la fenêtre d'inventaire.
    ISInventoryPage.LPBCS_wrapped = true

    local basePrerender = ISInventoryPage.prerender
    local baseOnRenameContainer = ISInventoryPage.onRenameContainer
    local baseOnRenameContainerClick = ISInventoryPage.onRenameContainerClick

    function ISInventoryPage:prerender()
        throttled(self)
        return basePrerender(self)
    end

    --- La boîte de saisie du jeu de base, pré-remplie avec ce que le joueur voit.
    ---
    --- Réécrite plutôt qu'enveloppée : le pré-remplissage est un argument de
    --- ISTextBox:new, et rien ne permet de le changer après coup. Le corps est
    --- celui du jeu, au titre près -- qui annonce NOTRE limite de longueur,
    --- comme le fait déjà la boîte du menu du mod.
    ---
    --- `container` peut être n'importe quoi : un sac, le sol, un coffre de
    --- voiture. Tout ce que le mod ne revendique pas repart chez le jeu de base
    --- -- et un conteneur SANS écriteau en fait partie, voir le garde ci-dessous.
    ISInventoryPage.onRenameContainer = function(container, player)
        local obj = LPBCS.worldObjectOf(container)
        if not obj or not Config.writingEnabled()
            or not Label.signOn(obj, container) then
            return baseOnRenameContainer(container, player)
        end

        local modal = ISTextBox:new(0, 0, 280, 180,
            LPBCS.text("IGUI_LPBCS_PromptTitle",
                "What goes on this container? (%1 characters at most)",
                Config.maxTextLength()),
            Label.displayName(obj, container), nil,
            ISInventoryPage.onRenameContainerClick,
            player, getSpecificPlayer(player), container)
        modal:initialise()
        modal:addToUIManager()

        if JoypadState.players[player + 1] then
            setJoypadFocus(player, modal)
        end
    end

    --- Le clic sur « OK ».
    ---
    --- Attention à la signature. Elle est déclarée avec `:` dans le jeu, mais
    --- ISTextBox appelle onclick(target, button, param1, param2, ...) et
    --- onRenameContainer passe target = nil : à l'exécution `self` est donc
    --- TOUJOURS nil, et `player` est un IsoPlayer, pas un numéro. On relaie tel
    --- quel, sans chercher à corriger ce que le jeu fait exprès.
    ---
    --- Le jeu de base ferait container:setCustomName(texte) puis deux
    --- refreshBackpacks. On ne l'appelle pas sur NOS conteneurs : son écriture
    --- se poserait en concurrente de la vérité, et c'est cette concurrence-là
    --- qu'on démonte.
    function ISInventoryPage:onRenameContainerClick(button, player, container)
        local obj = container and LPBCS.worldObjectOf(container)

        -- Pas à nous, ou l'écriture est coupée sur ce serveur : le jeu de base
        -- reprend la main entière. Un serveur qui a désactivé l'écriture ne doit
        -- pas se retrouver avec un « Renommer » cassé -- le mod s'efface, il ne
        -- confisque pas une fonction du jeu.
        --
        -- Et le troisième cas, qui est le sens même de ce garde : PAS D'ÉCRITEAU.
        -- Renommer une caisse vierge est un geste du jeu de base, qui n'a rien
        -- demandé au mod ; le capter y faisait naître un écriteau complet que le
        -- joueur ne pouvait plus retirer par là où il l'avait obtenu. Le nom
        -- s'affiche toujours -- c'est le repli de Label.read, inchangé -- mais il
        -- reste un nom.
        --
        -- Le même test qu'à l'ouverture de la boîte, et il est relu ici plutôt
        -- que retenu : entre les deux, un autre joueur a pu gratter l'écriteau.
        -- La bascule retombe proprement des deux côtés -- le jeu de base fait
        -- setCustomName, ce qui est exactement ce qu'on veut d'un conteneur sans
        -- écriteau -- donc rien à mémoriser.
        if not obj or not Config.writingEnabled()
            or not Label.signOn(obj, container) then
            return baseOnRenameContainerClick(self, button, player, container)
        end

        if button and button.internal == "OK" then
            local entry = button.parent and button.parent.entry
            local text = Label.sanitize(entry and entry:getText() or "")

            -- Vide : le jeu de base n'en fait rien non plus, et surtout ce n'est
            -- pas un effacement. Gratter un écriteau se demande par le menu du
            -- mod, à voix haute -- voir la note en tête de LPBCS_Server.
            if text ~= "" then
                submitRename(player, obj, container, text)
                LPBCS.attempt(ISInventoryPage.dirtyUI)
            end
        end

        -- Le focus manette revient à l'inventaire, comme dans le jeu de base.
        local playerNum = LPBCS.get(player, "getPlayerNum", nil)
        if playerNum ~= nil and JoypadState.players[playerNum + 1] then
            setJoypadFocus(playerNum, getPlayerInventory(playerNum))
        end
    end

    -- L'accroche qui ne coûte rien : le jeu annonce lui-même qu'il vient de
    -- reconstruire ses boutons, et il l'annonce avant de poser sa barre de
    -- titre. Testée avant d'être posée, comme OnObjectAboutToBeRemoved dans
    -- LPBCS_Scan : un événement que ce build n'aurait pas ne doit pas empêcher
    -- le reste du fichier de s'installer.
    if Events.OnRefreshInventoryWindowContainers then
        Events.OnRefreshInventoryWindowContainers.Add(function(page, phase)
            if phase == "buttonsAdded" then Inventory.refresh(page) end
        end)
    end

    --- Un refus du serveur lâche le verrou. Le gestionnaire de LPBCS_Context
    --- reste où il est et dit au joueur ce qui n'a pas marché ; celui-ci ne
    --- s'occupe que de ce qui est affiché.
    Events.OnServerCommand.Add(function(module, command, args)
        if module ~= LPBCS.MODULE or command ~= "SignResult" then return end
        if type(args) ~= "table" or args.ok then return end
        releaseAll()
    end)

else

    -- Sans ce fichier, le titre et l'infobulle redeviennent des instantanés et
    -- le « Renommer » du jeu redevient local. Rien ne le dirait : le seul
    -- symptôme est un nom qui ne bouge pas, que personne ne rapprochera d'un
    -- fichier d'interface manquant.
    LPBCS.log("Inventory", "ISInventoryPage introuvable ou deja enveloppe -- "
        .. "le titre de la fenetre de butin restera un instantane")

end

return Inventory
