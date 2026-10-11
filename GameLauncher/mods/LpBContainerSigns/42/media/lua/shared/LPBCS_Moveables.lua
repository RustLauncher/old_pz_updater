--[[
    © 2026 Warlord-Fox3. Tous droits réservés / All Rights Reserved.

    Toute réutilisation, modification, redistribution ou inclusion dans un
    modpack sans autorisation écrite préalable est strictement interdite.

    Any reuse, modification, redistribution, or inclusion in a modpack
    without prior written permission is strictly prohibited.
]]

--[[
    LPBCS_Moveables -- l'écriteau suit le meuble quand on le déménage.

    Ce que le jeu de base fait, et ce qu'il ne fait pas.

    Au RAMASSAGE (pickUpMoveableInternal), il ne recopie sur l'item que la clé
    « <type>_customContainerName », et seulement si le conteneur a un nom local :

        for i = 0, _object:getContainerCount()-1 do
            if _object:getContainerByIndex(i):getCustomName() then
                item:getModData()[cont:getType() .. "_customContainerName"] = ...

    Le texte passe donc, mais le style, l'encre, la face épinglée et l'auteur
    restent sur une commode qui n'existe plus. Sauf pour un IsoThumpable, où
    saveThumpableParameters fait _table.modData = copyTable(getModData()) et
    emporte tout -- ce qui explique pourquoi le défaut ne se voyait que sur les
    meubles du monde, jamais sur ceux que le joueur avait construits.

    À la POSE (placeMoveableInternal), il restaure la clé et appelle
    obj:setName(value) avec -- mais JAMAIS container:setCustomName(value). Le
    meuble arrivait donc avec un nom sur l'objet, aucun sur son conteneur, et
    plus d'écriteau : le fameux troisième nom, celui que personne ne pouvait
    corriger parce que personne ne le lisait.

    Ce fichier ferme les deux bouts. Il vit dans shared/ et non client/, parce
    que ISMoveableSpriteProps est un fichier partagé : en multijoueur le serveur
    exécute réellement le déplacement (TransactionProcessor) pendant que le
    client le joue en optimiste, et les deux ont besoin de ces enveloppes.

    Ce qui reste perdu, et qu'on assume :

      - un meuble multi-tuiles ramassé en un seul item (pickUpMoveable jette les
        items intermédiaires et en fabrique un par instanceItem) ;
      - un meuble déplacé par un joueur qui n'a pas le mod.

    Dans les deux cas la clé vanilla survit seule, et c'est le repli de
    Label.read qui rattrape le texte. Le NOM, donc, et lui seul : le meuble
    arrive nommé -- barre de titre, infobulle -- mais sans planche. Un repli
    n'accroche plus rien sur le meuble (voir Label.signOn et le balayage de
    LPBCS_Scan) ; le joueur réécrit son écriteau s'il le veut, et le mod
    l'aurait de toute façon préservé en entier si le déménageur l'avait eu.
]]

require "LPBCS_Core"
require "LPBCS_Label"
require "Moveables/ISMoveableSpriteProps"

-- Guarded: file scope, so it runs at load. See the note on the same call in
-- ISLPBCSWriteLabel -- a diagnostic must not be able to stop the file loading.
if LPBCS and LPBCS.stamp then
    LPBCS.stamp("LPBCS_Moveables", LPBCS.PROTOCOL)
end

LPBCS.Moveables = LPBCS.Moveables or {}
local Moveables = LPBCS.Moveables
local Label = LPBCS.Label

--- Une copie de la table de l'écriteau, ou nil s'il n'y en a pas.
---
--- Copiée et non partagée : le jeu, lui, recopie la ModData de l'item sur
--- l'objet par référence, ce qui laisse deux propriétaires sur une même table.
--- L'item est consommé juste après, donc ça ne s'est jamais vu -- mais une table
--- qu'on croit à soi et qui bouge ailleurs est le genre de chose qu'on ne
--- diagnostique pas deux fois.
---
--- Passe par hasModData() : lire getModData() accrocherait une table vide à
--- chaque meuble ramassé, y compris ceux qui n'ont jamais porté d'écriteau.
local function signOf(holder)
    if not holder then return nil end
    if LPBCS.get(holder, "hasModData", false) ~= true then return nil end

    local data = LPBCS.get(holder, "getModData", nil)
    if type(data) ~= "table" then return nil end

    local stored = data[LPBCS.MODDATA_KEY]
    if type(stored) ~= "table" then return nil end

    if copyTable then
        local copy = LPBCS.attempt(copyTable, stored)
        if type(copy) == "table" then return copy end
    end
    return stored
end

local function putSign(holder, stored)
    if not holder or type(stored) ~= "table" then return end
    local data = LPBCS.get(holder, "getModData", nil)
    if type(data) ~= "table" then return end
    data[LPBCS.MODDATA_KEY] = stored
end

--- L'item parmi les arguments de la pose, où qu'il soit.
---
--- Cherché par son type et non par sa place : 42.21 a ajouté le personnage en
--- tête de placeMoveableInternal, et c'est la place qui a bougé, pas l'item.
--- instanceof passe par LPBCS.attempt -- s'il venait à manquer, l'écriteau ne
--- suivrait plus, mais le meuble se poserait encore.
local function itemAmong(...)
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        if value ~= nil
            and LPBCS.attempt(instanceof, value, "InventoryItem") == true then
            return value
        end
    end
    return nil
end

--- Redonne au conteneur le nom local que le jeu ne lui rend pas.
---
--- C'est la ligne qui manque à placeMoveableInternal : il fait obj:setName() et
--- s'arrête là. Sans elle, le meuble se repose avec son nom sur l'objet et rien
--- sur son conteneur -- et comme setCustomName est la seule surface par laquelle
--- les autres mods voient un nom de conteneur, il devenait anonyme pour eux.
local function remirror(obj)
    local count = LPBCS.get(obj, "getContainerCount", 0)
    for index = 0, count - 1 do
        local container = LPBCS.attempt(function()
            return obj:getContainerByIndex(index)
        end)
        if container and LPBCS.isSignableContainer(obj, container) then
            local label = Label.read(obj, container)
            if label then Label.mirror(obj, container, label.text) end
        end
    end
end

if ISMoveableSpriteProps
    and type(ISMoveableSpriteProps.pickUpMoveableInternal) == "function"
    and type(ISMoveableSpriteProps.placeMoveableInternal) == "function"
    and not ISMoveableSpriteProps.LPBCS_wrapped then

    -- Même sentinelle que dans LPBCS_Inventory : un rechargement du Lua rejoue
    -- ce fichier, et la capture ci-dessous prendrait sinon notre propre
    -- enveloppe pour base.
    ISMoveableSpriteProps.LPBCS_wrapped = true

    local basePickUp = ISMoveableSpriteProps.pickUpMoveableInternal
    local basePlace = ISMoveableSpriteProps.placeMoveableInternal

    --- L'écriteau monte sur l'item avec le meuble.
    ---
    --- LU AVANT l'appel, et l'ordre n'est pas négociable : la base retire
    --- l'objet de sa case en chemin (transmitRemoveItemFromSquare), donc sa
    --- ModData n'est plus là où on irait la chercher au retour.
    function ISMoveableSpriteProps:pickUpMoveableInternal(_character, _square,
            _object, _sprInstance, _spriteName, _createItem, _rotating)

        local stored = LPBCS.attempt(signOf, _object)

        local item = basePickUp(self, _character, _square, _object, _sprInstance,
            _spriteName, _createItem, _rotating)

        if item and stored then
            LPBCS.attempt(putSign, item, stored)
        end

        return item
    end

    --- Et il redescend avec lui.
    ---
    --- La base recopie déjà la ModData de l'item en bloc -- mais seulement quand
    --- movableData est absent, et par référence. On repose la table
    --- explicitement : elle arrive alors dans tous les cas, et elle nous
    --- appartient.
    ---
    --- Le transmit est APRÈS, et il le faut : la base fait son
    --- transmitCompleteItemToClients avant qu'on ait écrit quoi que ce soit, si
    --- bien qu'un écriteau posé sans cette ligne resterait invisible pour tous
    --- les autres clients jusqu'au prochain chargement de la case.
    ---
    --- Les arguments passent TELS QUELS, sans être nommés. 42.21 a ajouté le
    --- personnage en tête -- (_character, _square, _item, _spriteName) -- et
    --- l'enveloppe, restée à trois paramètres, jetait le quatrième : la base
    --- recevait un nom de sprite nil, levait sur getSprite(nil):getType(), et
    --- plus AUCUN meuble ne se posait, écriteau ou pas, serveur compris. Relayé
    --- ainsi, un prochain changement de signature coûtera au pire l'écriteau,
    --- jamais la pose.
    function ISMoveableSpriteProps:placeMoveableInternal(...)
        local obj = basePlace(self, ...)

        if obj then
            -- Hors de la closure : en 5.1, `...` n'y est pas visible.
            local item = itemAmong(...)
            LPBCS.attempt(function()
                local stored = signOf(item)
                if stored then putSign(obj, stored) end

                -- Appelé même sans table à nous : le meuble peut n'avoir que la
                -- clé vanilla -- ramassé par un joueur sans le mod, ou avant
                -- qu'il soit installé -- et c'est là que le repli de Label.read
                -- lui refait un écriteau.
                remirror(obj)

                if LPBCS.attempt(isServer) == true then Label.transmit(obj) end
            end)
        end

        return obj
    end

else

    -- Sans ces enveloppes, déménager un meuble non-thumpable lui coûte son
    -- écriteau et lui laisse un nom fantôme sur l'objet. C'est exactement le
    -- défaut d'origine, et il ne se signale pas tout seul.
    LPBCS.log("Moveables", "ISMoveableSpriteProps introuvable ou deja enveloppe "
        .. "-- l'ecriteau ne suivra pas un meuble deplace")

end

return Moveables
