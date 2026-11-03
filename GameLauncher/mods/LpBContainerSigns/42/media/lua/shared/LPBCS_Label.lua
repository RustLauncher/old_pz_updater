--[[
    © 2026 Warlord-Fox3. Tous droits réservés / All Rights Reserved.

    Toute réutilisation, modification, redistribution ou inclusion dans un
    modpack sans autorisation écrite préalable est strictement interdite.

    Any reuse, modification, redistribution, or inclusion in a modpack
    without prior written permission is strictly prohibited.
]]

--[[
    LPBCS_Label -- the only file that knows how a sign is stored.

    Storage is deliberately in three places, and they are not redundant:

      1. obj:getModData().LPBCS          the source of truth. Replicated to
                                         every client by transmitModData().
      2. container:setCustomName(text)   a local mirror, so the loot window
                                         title says the same thing as the sign
                                         hanging on the crate. Never read back
                                         as truth: it does not travel over the
                                         network.
      3. obj:getModData()[type.."_customContainerName"]
                                         the vanilla key. ISMoveableSpriteProps
                                         copies it onto the item when furniture
                                         is picked up and restores it on
                                         placement -- and Label.read reads it
                                         back, which is what makes that work. It
                                         was written here and read by NOBODY, so
                                         a wardrobe arrived at the far end of the
                                         room carrying its name in ModData, none
                                         on its container, and no sign at all.

    Reading falls back to container:getCustomName(), and then to that key, so a
    container someone renamed through the vanilla loot window -- or carried
    across the room -- still SHOWS the name it carries, without anyone having to
    write on it again.

    It shows it. It does not grow a sign out of it, and that difference is the
    whole of Label.signOn just below Label.read. A fallback has no ink, no
    chosen style and no author, and it goes the day the name goes; everything
    that WRITES, MOVES or DRAWS asks signOn, never read -- Label.rename,
    Label.setSide, the world menu in LPBCS_Context and the sweep in LPBCS_Scan.

    Confusing the two grew a full, saved, replicated sign out of a plain rename:
    a plank appeared on a crate nobody had written on, the menu then offered to
    "rewrite" it and to choose which face it hung from, and the player could not
    take it off through the box they had got it from -- the vanilla box refuses
    an empty text, and scraping a sign off is something only the mod's own menu
    asks for.

    Label.read stays the one that ANSWERS for the display: the loot window title
    and its tooltip, through LPBCS_Inventory. A name is a name everywhere the
    game shows names -- it is simply not a board nailed to the front.

    Both fallbacks are sanitised, and that is not tidiness. The vanilla rename
    accepts 28 characters where the mod may be set to fewer, so an unsanitised
    fallback displayed a name the mod would silently shorten the first time it
    passed through Label.write. The name changed on its own, and nobody had
    touched it.

    That fallback is also why erasing leaves a TOMBSTONE -- { erased = true,
    was = <the text> } under the same key -- rather than removing the key:

      * mirror (2) is per-process. A server that scrapes a sign off clears its
        own copy of the name and nobody else's, so every client is left holding
        one that the fallback would read straight back as a sign. Erasing
        therefore worked in single player and was IMPOSSIBLE online.
      * a key that has stopped existing is not an entry, so transmitModData has
        nothing to carry. A key holding a value does travel.

    The mark outranks the name, and `was` is what keeps that from condemning the
    container: a name that still matches it is somebody's stale mirror, while a
    DIFFERENT one is a genuine vanilla rename since the erase, which must still
    grow a sign. Clients take their own mirror down through Label.unmirror, from
    the sweep in LPBCS_Scan.
]]

require "LPBCS_Core"
require "LPBCS_Config"

-- Guarded: file scope, so it runs at load. See the note on the same call in
-- ISLPBCSWriteLabel -- a diagnostic must not be able to stop the file loading.
if LPBCS and LPBCS.stamp then
    LPBCS.stamp("LPBCS_Label", LPBCS.PROTOCOL)
end

LPBCS.Label = LPBCS.Label or {}
local Label = LPBCS.Label
local Config = LPBCS.Config

local DEFAULT_INK = { r = 0.13, g = 0.13, b = 0.13 }

-- ------------------------------------------------------------- validation

--- Trims, collapses whitespace and caps the length. Returns "" for anything
--- that is not worth putting on a sign, which callers treat as "erase".
function Label.sanitize(text)
    local out = LPBCS.trim(text)
    if out == "" then return "" end

    -- A sign is one line. Newlines and tabs would draw as blanks or boxes.
    out = out:gsub("[%c]", " "):gsub("%s+", " ")
    out = LPBCS.trim(out)

    local limit = Config.maxTextLength()
    if #out > limit then out = out:sub(1, limit) end
    return out
end

local function normaliseStyle(style)
    if LPBCS.isStyle(style) and Config.styleAllowed(style) then return style end
    return Config.defaultStyle()
end

--- The face the player pinned this sign to, or nil for "let the mod choose".
--- Unlike the style there is no fallback value: having made no choice IS the
--- default state, and LPBCS_Scan reads nil as "work it out from the furniture".
local function normaliseSide(side)
    if LPBCS.isFace(side) then return side end
    return nil
end

-- ---------------------------------------------------------------- reading

--- Read-only access. getModData() CREATES the table on first call, and the
--- display sweep looks at every container around the player several times a
--- second: going through getModData() here would hang an empty ModData table
--- off every crate, shelf and fridge the player ever walks past, and then
--- write them all to the save. hasModData() first, always.
local function readModData(obj)
    if not obj then return nil end
    if LPBCS.get(obj, "hasModData", false) ~= true then return nil end
    local data = LPBCS.get(obj, "getModData", nil)
    if type(data) ~= "table" then return nil end
    return data
end

--- Write access, which is allowed to create the table. Only ever called on
--- the path where a sign really is being stored.
local function writeModData(obj)
    if not obj then return nil end
    local data = LPBCS.get(obj, "getModData", nil)
    if type(data) ~= "table" then return nil end
    return data
end

--- La cle sous laquelle le jeu de base range le nom d'un conteneur. Declaree
--- ICI, dans la section de lecture, et non plus au-dessus des ecritures : depuis
--- que Label.read s'en sert, un local declare plus bas ne serait pas dans sa
--- portee et la lecture retomberait silencieusement sur nil.
local function vanillaKey(container)
    local containerType = LPBCS.get(container, "getType", nil)
    if containerType == nil then return nil end
    return tostring(containerType) .. LPBCS.VANILLA_NAME_SUFFIX
end

--- Le titre que le jeu de base donnerait a ce conteneur s'il n'avait pas de nom.
---
--- Le jeu ecrit cette meme ligne a quatre endroits (ISInventoryPage l.1714,
--- l.1739, l.1906, et LPBCS_Context de notre cote) ; elle vit ici parce que
--- Label.displayName en a besoin, et parce qu'un titre par defaut est encore une
--- reponse a « comment s'appelle ce conteneur ».
function Label.typeTitle(container)
    local containerType = LPBCS.get(container, "getType", nil)
    if containerType == nil then return "" end
    containerType = tostring(containerType)

    if getTextOrNull then
        local title = LPBCS.attempt(getTextOrNull,
            "IGUI_ContainerTitle_" .. containerType)
        if title and title ~= "" then return tostring(title) end
    end
    return containerType
end

--- Comment ce conteneur s'appelle, pour qui doit l'AFFICHER. Jamais nil, jamais
--- vide : l'ecriteau s'il y en a un, le titre de type sinon.
---
--- C'est la fonction que l'interface appelle, et elle rend le titre par defaut
--- au lieu de se contenter de surcharger, pour une raison qui ne se voit pas :
--- setCustomName est SERIALISE dans la sauvegarde, et "" est ce que
--- Label.unmirror laisse derriere lui -- faute de pouvoir laisser nil, que le
--- pont Lua->Java ne sait pas transmettre. Or le jeu teste
--- `if container:getCustomName() then`, vrai pour "". Une accroche qui se
--- contenterait de surcharger quand il y a un ecriteau laisserait donc la barre
--- de titre vide sur toute caisse dont on a gratte l'ecriteau ; celle-ci
--- reconstruit « Caisse ». C'est ce qui rend "" tenable la-bas.
function Label.displayName(obj, container)
    local label = Label.read(obj, container)
    if label and not LPBCS.isBlank(label.text) then return label.text end
    return Label.typeTitle(container)
end

--- The sign on this container, or nil. Never returns a table with blank
--- text: an empty sign is no sign.
function Label.read(obj, container)
    if not LPBCS.isSignableContainer(obj, container) then return nil end

    local data = readModData(obj)
    local stored = data and data[LPBCS.MODDATA_KEY]
    if type(stored) == "table" and not LPBCS.isBlank(stored.text) then
        return {
            text   = tostring(stored.text),
            r      = LPBCS.clampFloat(stored.r or DEFAULT_INK.r, 0, 1),
            g      = LPBCS.clampFloat(stored.g or DEFAULT_INK.g, 0, 1),
            b      = LPBCS.clampFloat(stored.b or DEFAULT_INK.b, 0, 1),
            style  = normaliseStyle(stored.style),
            side   = normaliseSide(stored.side),
            author = stored.author and tostring(stored.author) or nil,
        }
    end

    local customName = LPBCS.get(container, "getCustomName", nil)

    -- Ce que le jeu de base a laisse derriere lui, s'il y a quelque chose. Deux
    -- endroits, et le second est celui qui manquait.
    --
    -- ISMoveableSpriteProps recopie « <type>_customContainerName » sur l'item
    -- quand on ramasse un meuble, la restaure dans la ModData de l'objet pose,
    -- et appelle obj:setName() avec -- mais JAMAIS container:setCustomName().
    -- Une commode deplacee de trois cases arrivait donc sans nom sur son
    -- conteneur, sans table a nous si elle n'est pas un IsoThumpable, et sans
    -- ecriteau : le nom etait bien la, dans une cle que ce fichier ecrivait et
    -- que personne ne relisait.
    local fallback = customName
    if LPBCS.isBlank(fallback) then
        local key = vanillaKey(container)
        if key and data then fallback = data[key] end
    end

    -- The tombstone, and the reason it has to exist at all.
    --
    -- setCustomName() does not travel (see LPBCS_Core). Every client writes it
    -- for itself from replicated ModData, several times a second, in the display
    -- sweep. So when a sign is scraped off on a server, the server clears its own
    -- copy of the name -- and every OTHER client is still holding one that
    -- nobody will ever clear. The fallback below would read it back as a sign
    -- and hang the name straight back on the crate, forever, which is what made
    -- erasing impossible online while working perfectly in single player.
    --
    -- An erased sign therefore leaves a mark that DOES travel, and the mark
    -- outranks the name. `was` is what the sign said when it was scraped off:
    -- a name that still matches it is this client's own stale mirror and means
    -- nothing, while a DIFFERENT one is somebody genuinely renaming the
    -- container afterwards through the vanilla loot window -- which must still
    -- be SHOWN, as it always has. Shown, and no more: a name grows no plank
    -- (see Label.signOn and the sweep in LPBCS_Scan), so what comes back here
    -- is a title, not a resurrected sign.
    -- La marque s'applique aux DEUX replis. Label.erase laisse la cle vanilla a
    -- blanc pour cette raison meme, donc en pratique elle n'a rien a dire ici --
    -- mais une cle rapportee par un demenagement en aurait, et elle ne doit pas
    -- plus qu'un miroir rance rendre un ecriteau qu'on a gratte.
    if type(stored) == "table" and stored.erased == true then
        if LPBCS.isBlank(fallback) then return nil end
        if tostring(fallback) == tostring(stored.was or "") then return nil end

        -- Le rattrapage des sauvegardes que la version d'avant a empoisonnees.
        --
        -- « null » n'est pas un nom : c'est ce que le pont Lua->Java a ecrit a
        -- la place de rien (voir Label.unmirror). Sous une marque d'effacement,
        -- il ne peut venir que de la, et sans cette ligne les caisses deja
        -- grattees une fois resteraient bloquees dessus : le balayage ne retire
        -- le miroir que quand cette fonction rend nil, ce qu'elle ne faisait
        -- jamais tant qu'elle rendait « null ».
        --
        -- Le prix, et il se dit : un joueur qui renommerait deliberement
        -- « null » une caisse dont l'ecriteau a ete gratte perdrait ce nom-la.
        if tostring(fallback) == "null" then return nil end
    end

    -- Nothing of ours: fall back to whatever the vanilla rename left behind.
    --
    -- Assaini, comme le serait une ecriture. Voir la note en tete de fichier :
    -- sans ce passage, un nom vanilla de 28 caracteres s'affichait entier ici et
    -- se faisait tronquer a MaxLabelLength des qu'il repassait par Label.write.
    fallback = Label.sanitize(fallback)
    if fallback ~= "" then
        return {
            text     = fallback,
            r        = DEFAULT_INK.r,
            g        = DEFAULT_INK.g,
            b        = DEFAULT_INK.b,
            style    = Config.defaultStyle(),
            fromName = true,
        }
    end

    return nil
end

--- L'ecriteau REEL sur ce conteneur, ou nil. Un nom vanilla n'en est pas un.
---
--- La distinction que rend cette fonction est la seule qui compte pour qui
--- s'apprete a ECRIRE : Label.read dit ce qu'il faut afficher, et il le dit aussi
--- pour un conteneur qui n'a qu'un nom -- un repli, marque `fromName`, qui n'a ni
--- encre, ni style choisi, ni auteur, et qui disparait le jour ou le nom
--- disparait. Confondre les deux, c'est ce qui faisait naitre un ecriteau
--- complet, sauvegarde et repliqué, d'un simple renommage dans la fenetre de
--- butin -- et un ecriteau ne se gratte que par le menu du mod, donc le joueur
--- n'avait plus aucun moyen de defaire ce qu'il n'avait jamais demande.
---
--- Le nom reste affiche par le repli, comme il l'a toujours ete. Il n'est
--- simplement plus ecrit.
function Label.signOn(obj, container)
    local label = Label.read(obj, container)
    if not label or label.fromName then return nil end
    return label
end

-- ---------------------------------------------------------------- writing

--- Pushes the authoritative text down into the two mirrors. Safe to call on
--- every client: it is what keeps the loot window title honest for a sign
--- that arrived over the network rather than being written here.
---
--- Both writes are guarded by an equality check, because this runs several
--- times a second from the display sweep and rewriting identical values
--- would keep flagging the object's ModData as changed for nothing.
function Label.mirror(obj, container, text)
    if not obj or not container then return end

    local current = LPBCS.get(container, "getCustomName", nil)
    if current == nil or tostring(current) ~= text then
        LPBCS.invoke(container, "setCustomName", text)
    end

    local data = readModData(obj)
    local key = vanillaKey(container)
    if data and key and data[key] ~= text then data[key] = text end
end

--- Writes the sign and returns the stored table, or nil when there was nothing
--- worth writing -- in which case NOTHING happens: the sign already there is
--- left exactly as it was.
--- Does NOT transmit: the caller decides, because the server transmits once
--- after a write and the client must never transmit at all.
---
--- Writing does not erase. It used to: an empty text called Label.erase and
--- the two intentions shared one entry point, so any caller that reached here
--- without a text -- a request of another kind, a payload from a client of
--- another version -- destroyed the sign instead of being refused. Erasing is
--- Label.erase, said out loud, by a caller that means it.
---
--- `side` is optional and, left out, is inherited from whatever is already
--- there. The table below is rebuilt from scratch on every write, so without
--- that carry-over fixing a typo would unpin a sign the player had moved.
function Label.write(obj, container, text, ink, style, author, side)
    if not LPBCS.isSignableContainer(obj, container) then return nil end

    text = Label.sanitize(text)
    if text == "" then return nil end

    local data = writeModData(obj)
    if not data then return nil end

    local previous = data[LPBCS.MODDATA_KEY]
    -- The side says where the sign hangs, not what it says. Rewriting the text
    -- does not take it off the wall.
    side = normaliseSide(side)
    if side == nil and type(previous) == "table" then
        side = normaliseSide(previous.side)
    end

    ink = type(ink) == "table" and ink or DEFAULT_INK
    local stored = {
        text   = text,
        r      = LPBCS.clampFloat(ink.r or DEFAULT_INK.r, 0, 1),
        g      = LPBCS.clampFloat(ink.g or DEFAULT_INK.g, 0, 1),
        b      = LPBCS.clampFloat(ink.b or DEFAULT_INK.b, 0, 1),
        style  = normaliseStyle(style),
        side   = side,
        author = author and tostring(author) or nil,
    }

    data[LPBCS.MODDATA_KEY] = stored
    Label.mirror(obj, container, text)
    return stored
end

--- Le renommage venu de la fenetre de butin du jeu de base, ecrit la ou tout le
--- monde le lira. Rend la table stockee, ou nil s'il n'y avait rien a ecrire.
---
--- Le jeu de base fait container:setCustomName(texte) et rien d'autre
--- (ISInventoryPage:onRenameContainerClick). Ce nom-la ne voyage pas, et le
--- balayage remettait le texte de la ModData par-dessus au quart de seconde
--- suivant : le joueur regardait son renommage disparaitre sans un mot, et
--- aucun autre client ne l'avait jamais vu. Passer par ici, c'est le porter
--- jusqu'a la seule ecriture que les autres liront.
---
--- Ce qui est CONSERVE : l'encre, le style et la face. Renommer une caisse ne
--- repeint pas son ecriteau et ne le decroche pas de sa paroi -- meme scrupule
--- que Label.setSide, qui deplace sans jamais toucher au texte.
---
--- Ce qui CHANGE : l'auteur, qui est celui dont c'est le renommage.
---
--- RENOMME, et ne cree jamais. C'est la regle de fond, et elle a coute assez
--- cher pour etre dite : sans le garde ci-dessous, renommer une caisse vierge y
--- faisait naitre un ecriteau complet -- encre par defaut, style par defaut, un
--- auteur -- sauvegarde et repliqué a tout le monde. Le joueur avait demande un
--- nom et recevait un ecriteau, qu'il ne pouvait plus retirer par la ou il
--- l'avait obtenu : la boite du jeu de base refuse le texte vide, et gratter un
--- ecriteau ne se demande que par le menu du mod.
---
--- Le client s'arrete deja avant d'envoyer (voir LPBCS_Inventory, qui rend la
--- main au « Renommer » du jeu de base des qu'il n'y a pas d'ecriteau). Ce
--- garde-ci est celui qui compte quand meme : Server.rename est l'autorite, et
--- un client modifie ne se prive pas d'envoyer ce qu'il veut.
---
--- La pierre tombale n'est donc plus levee ici, et il n'y a rien a rattraper :
--- une caisse grattee n'a plus d'ecriteau, son renommage repart chez le jeu de
--- base, et le repli de Label.read laisse deja passer un texte DIFFERENT de
--- `was` -- ce a quoi sert `was`.
function Label.rename(obj, container, text, author)
    if not LPBCS.isSignableContainer(obj, container) then return nil end

    text = Label.sanitize(text)
    if text == "" then return nil end

    local previous = Label.signOn(obj, container)
    if not previous then return nil end

    return Label.write(obj, container, text,
        { r = previous.r, g = previous.g, b = previous.b },
        previous.style, author, previous.side)
end

--- Moves the sign to a given face, or back to nil for "let the mod choose".
--- Returns true when something actually changed.
---
--- The one thing this must not do is rewrite the sign: the text, the ink and
--- the style are untouched, which is why moving a sign costs no pen and no
--- paint. Does NOT transmit, same contract as Label.write.
function Label.setSide(obj, container, side)
    -- DEPLACE, et ne cree jamais -- meme regle que Label.rename, et pour la
    -- meme raison. Un nom du jeu de base ne pend a aucune face : il n'est ecrit
    -- nulle part, il s'affiche. Deplacer ce qui n'existe pas faisait naitre ici
    -- un ecriteau complet -- encre par defaut, style par defaut, sauvegarde et
    -- replique -- d'un simple renommage, ce que le menu ne propose plus et que
    -- le serveur n'a pas a servir davantage : Server.setSide est l'autorite, et
    -- un menu bati avant un effacement, ou un client modifie, ne se privent pas
    -- de demander une face sur une caisse qui n'a qu'un nom.
    local label = Label.signOn(obj, container)
    if not label then return false, false end

    side = normaliseSide(side)

    local data = writeModData(obj)
    if not data then return false, false end

    -- signOn a deja garanti la table : ni pierre tombale, ni repli, ni rien.
    local stored = data[LPBCS.MODDATA_KEY]
    if type(stored) ~= "table" then return false, false end

    -- Two return values, saying two different things: `changed` is whether the
    -- ModData moved, `ok` whether the sign is on the face that was asked for.
    -- Confounding them is what put "the sign could not be moved" in front of a
    -- player looking at their sign hanging exactly where they wanted it --
    -- asking again for the face it already carries changes nothing, and is not
    -- a failure.
    if normaliseSide(stored.side) == side then return false, true end
    stored.side = side

    -- Put the table back under its key rather than leaving the change buried a
    -- level down. Label.mirror's guard says something on the Java side notices
    -- when ModData is written to; a nested field would not look like a write.
    data[LPBCS.MODDATA_KEY] = stored
    return true, true
end

--- Takes the sign off for good. The ONLY thing in the mod that destroys one,
--- and it is meant to stay that way: nothing else should be able to lose a
--- sign as a side effect of doing something different.
--- Clears this process's local copy of the name.
---
--- Split out of Label.erase because the two happen in different places on a
--- server: erasing is the server's business, but the mirror is per-process, so
--- every client has to take its own down. LPBCS_Scan calls this when the sweep
--- finds a tombstone -- that is where a client learns the sign is gone.
---
--- setCustomName(nil) NE REMET PAS le nom a nil, et il faut le dire dans ce
--- sens-la : ce n'est pas un appel qui « pourrait etre refuse », c'est un appel
--- qui echoue toujours et qui laisse quelque chose derriere lui.
---
--- Le pont Lua->Java de PZ ne sait pas transmettre un String nul : il ecrit la
--- chaine « null ». Le jeu ne passe d'ailleurs jamais nil a ce setter -- le seul
--- appel vanilla est ISInventoryPage.onRenameContainerClick, toujours avec un
--- texte non vide -- donc ce chemin n'appartient qu'a nous et personne n'avait
--- verifie ce qui s'y range vraiment.
---
--- Ce qu'il en coutait : le repli de Label.read relisait « null » comme un nom
--- vanilla, la marque d'effacement ne le condamnait pas -- elle ne condamne que
--- le texte qu'on vient de gratter -- et le conteneur repartait avec un ecriteau
--- qui disait « null ». Il fallait gratter une SECONDE fois, laquelle inscrivait
--- « null » dans la marque et fermait enfin la boucle. Un geste sur deux ne
--- servait qu'a reparer le precedent.
---
--- "" est donc le plancher : ce qu'on peut atteindre, faute de nil. Tout le mod
--- le lit deja comme « pas de nom » (LPBCS.isBlank), il est identique dans
--- toutes les langues et sur tous les clients -- ce qui compte, le repli devant
--- se taire aussi bien chez celui qui efface que chez son voisin -- et
--- Label.displayName reconstruit « Caisse » par-dessus.
---
--- Ce que ca coute, et c'est assume : le jeu teste `if container:getCustomName()
--- then`, vrai pour "". Ce qui ne passe pas par Label.displayName -- les autres
--- mods -- lit du vide la ou il aurait lu « Caisse ». Il y lisait « null ».
function Label.unmirror(container)
    if not container then return end

    -- Rien a retirer, et c'est le cas courant -- un conteneur sans nom, vu
    -- quatre fois par seconde par le balayage. La sortie est ici pour lui.
    --
    -- "" sort par la MEME porte depuis qu'on sait que nil est hors d'atteinte :
    -- il n'y a plus rien a tenter sur un nom deja vide, et le tenter quand meme
    -- serait deux appels Java par balayage et par conteneur efface, pour
    -- reecrire ce qui est deja la.
    local current = LPBCS.get(container, "getCustomName", nil)
    if LPBCS.isBlank(current) then return end

    LPBCS.invoke(container, "setCustomName", nil)

    local remaining = LPBCS.get(container, "getCustomName", nil)
    if not LPBCS.isBlank(remaining) then
        -- Le pont a stringifie le null. On repasse derriere lui.
        LPBCS.invoke(container, "setCustomName", "")
        remaining = LPBCS.get(container, "getCustomName", nil)
    end

    if not LPBCS.isBlank(remaining) then
        LPBCS.log("Label", "le nom local de '%s' resiste a nil ET a \"\" (reste "
            .. "'%s') -- l'affichage passe par la ModData",
            tostring(LPBCS.get(container, "getType", "?")), tostring(remaining))
    end
end

function Label.erase(obj, container)
    local previous = Label.read(obj, container)

    -- A tombstone, not a removed key. Two reasons, and the second is the one
    -- that made erasing impossible on a server:
    --
    --   1. transmitModData replicates the entries a table HAS. A key that has
    --      simply stopped existing is not an entry, so its removal is not
    --      something the packet can carry; a key holding a value is.
    --   2. Label.read falls back to the container's local name, which no client
    --      but this one will ever clear. The mark is what outranks it -- see the
    --      long note in Label.read.
    --
    -- `was` records what it said, so that a LATER vanilla rename is still
    -- allowed to grow a new sign instead of being condemned by the mark.
    local data = (previous ~= nil) and writeModData(obj) or readModData(obj)
    if data then
        local stored = data[LPBCS.MODDATA_KEY]
        local marked = type(stored) == "table" and stored.erased == true
        local key = vanillaKey(container)

        if previous ~= nil then
            data[LPBCS.MODDATA_KEY] = { erased = true, was = previous.text }
            -- Blank rather than nil, for reason 1 above: this key is what
            -- ISMoveableSpriteProps copies onto the item when the furniture is
            -- picked up, so a stale one would nail the name back on at the far
            -- end of a house move.
            if key then data[key] = "" end
        elseif not marked then
            -- Nothing to erase and no mark to keep: leave no litter behind on a
            -- container that never carried a sign.
            data[LPBCS.MODDATA_KEY] = nil
            if key then data[key] = nil end
        end

        -- A mark already there is left EXACTLY as it is. Erasing twice -- two
        -- players at one crate, or one stale menu -- must not lift it: it is the
        -- only thing standing between the other clients' stale mirrors and the
        -- sign going straight back up.
    end

    Label.unmirror(container)
end

--- Sends the object's ModData to every client that has the chunk loaded.
--- Server-side only; on a client this would be a no-op at best.
function Label.transmit(obj)
    LPBCS.invoke(obj, "transmitModData")
end

-- --------------------------------------------------------- wire addressing

--- The coordinates a client sends so the server can find the same container
--- again. Same shape the vanilla Commands.object.* handlers use: square plus
--- an index into getObjects(), plus which container of that object.
function Label.locate(obj, container)
    local square = LPBCS.get(obj, "getSquare", nil)
    if not square then return nil end

    local objects = LPBCS.get(square, "getObjects", nil)
    local count = objects and LPBCS.get(objects, "size", 0) or 0
    local objectIndex = -1
    for index = 0, count - 1 do
        if LPBCS.attempt(function() return objects:get(index) end) == obj then
            objectIndex = index
            break
        end
    end
    if objectIndex < 0 then return nil end

    local containerIndex = -1
    local containerCount = LPBCS.get(obj, "getContainerCount", 0)
    for index = 0, containerCount - 1 do
        if LPBCS.attempt(function() return obj:getContainerByIndex(index) end) == container then
            containerIndex = index
            break
        end
    end
    if containerIndex < 0 then return nil end

    return {
        x = LPBCS.get(square, "getX", 0),
        y = LPBCS.get(square, "getY", 0),
        z = LPBCS.get(square, "getZ", 0),
        index = objectIndex,
        containerIndex = containerIndex,
    }
end

--- The reverse, run on the server against coordinates a client sent. Every
--- index is bounds-checked: these numbers come off the wire and nothing else
--- is going to check them.
function Label.resolve(args)
    if type(args) ~= "table" then return nil end
    if type(args.x) ~= "number" or type(args.y) ~= "number" or type(args.z) ~= "number" then
        return nil
    end
    if type(args.index) ~= "number" or type(args.containerIndex) ~= "number" then
        return nil
    end

    local cell = LPBCS.attempt(getCell)
    if not cell then
        cell = LPBCS.attempt(function() return getWorld():getCell() end)
    end
    if not cell then return nil end

    local square = LPBCS.attempt(function()
        return cell:getGridSquare(args.x, args.y, args.z)
    end)
    if not square then return nil end

    local objects = LPBCS.get(square, "getObjects", nil)
    local count = objects and LPBCS.get(objects, "size", 0) or 0
    if args.index < 0 or args.index >= count then return nil end

    local obj = LPBCS.attempt(function() return objects:get(args.index) end)
    if not obj then return nil end

    local containerCount = LPBCS.get(obj, "getContainerCount", 0)
    if args.containerIndex < 0 or args.containerIndex >= containerCount then return nil end

    local container = LPBCS.attempt(function()
        return obj:getContainerByIndex(args.containerIndex)
    end)
    if not LPBCS.isSignableContainer(obj, container) then return nil end

    return obj, container, square
end

return Label
