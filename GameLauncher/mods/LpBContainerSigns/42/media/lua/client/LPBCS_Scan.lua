--[[
    © 2026 Warlord-Fox3. Tous droits réservés / All Rights Reserved.

    Toute réutilisation, modification, redistribution ou inclusion dans un
    modpack sans autorisation écrite préalable est strictement interdite.

    Any reuse, modification, redistribution, or inclusion in a modpack
    without prior written permission is strictly prohibited.
]]

--[[
    LPBCS_Scan -- which signs are worth drawing right now.

    The renderer runs every frame; sweeping the tiles around the player every
    frame would be indefensible. So the sweep happens on a clock (four times a
    second) and immediately whenever the player steps onto a new tile, and the
    renderer only ever reads the resulting list.

    That makes this the right place for anything the renderer would otherwise
    recompute per sign per frame for an answer that only moves when the
    furniture does -- which is why the face a sign hangs on is decided here.

    Le balayage a longtemps ete aussi ce qui remettait le titre de la fenetre de
    butin en accord avec l'ecriteau, par Label.mirror. Il ne l'est plus, et ce
    fichier n'a plus a s'en soucier : LPBCS_Inventory derive le titre et
    l'infobulle de la ModData au moment ou ils s'affichent.

    C'est ce qui a repare trois defauts d'un coup, et ils venaient tous de ce
    couplage-ci : le titre etait faux hors du rayon de balayage, faux quand le
    joueur avait masque les ecriteaux pendant le butin, et fige tant qu'il ne
    changeait pas de case.

    Label.mirror reste appele ici, mais pour ce qu'il aurait toujours du etre :
    une commodite, pour que getCustomName() -- la seule surface par laquelle les
    autres mods voient un nom de conteneur -- dise la meme chose que nous.
]]

require "LPBCS_Core"
require "LPBCS_Label"
require "LPBCS_Options"
require "LPBCS_Sprites"

-- Guarded: file scope, so it runs at load. See the note on the same call in
-- ISLPBCSWriteLabel -- a diagnostic must not be able to stop the file loading.
if LPBCS and LPBCS.stamp then
    LPBCS.stamp("LPBCS_Scan", LPBCS.PROTOCOL)
end

LPBCS.Scan = LPBCS.Scan or {}
local Scan = LPBCS.Scan
local Label = LPBCS.Label
local Options = LPBCS.Options
local Sprites = LPBCS.Sprites

local REFRESH_MS = 250

Scan.cache = Scan.cache or {}

local function cacheFor(playerNum)
    local cache = Scan.cache[playerNum]
    if not cache then
        -- `placed` : les objets sur lesquels le dernier balayage a réellement
        -- posé un écriteau. Sert à la purge de sortie de rayon (Sprites.retain
        -- dans onTick), pas au rendu.
        cache = { entries = {}, placed = {}, at = 0,
                  x = nil, y = nil, z = nil, dirty = true }
        Scan.cache[playerNum] = cache
    end
    return cache
end

--- True when nothing on the neighbouring tile would bury a sign hung on that
--- face of the object: no wall between the two squares, and no other container
--- standing there.
---
--- Deliberately not LPBCS.eachContainerOnSquare, which filters by the
--- CratesOnly rule. What matters here is geometry: a fridge next door hides a
--- sign just as well as a crate does, whether or not it could carry one.
local function faceIsClear(cell, square, nx, ny, z)
    local neighbour = cell:getGridSquare(nx, ny, z)
    -- Edge of the loaded world: nothing out there to hide behind.
    if not neighbour then return true end
    if square:isWallTo(neighbour) then return false end

    local objects = neighbour:getObjects()
    if not objects then return true end

    for index = 0, objects:size() - 1 do
        local obj = objects:get(index)
        if obj and obj:getContainerCount() > 0 then return false end
    end
    return true
end

--- Which vertical face of the object the sign is nailed to. The east face
--- (x+1, the right-hand half of the tile on screen, text running up to the
--- right) reads best and is the default; the sign moves round to the south
--- face when something is standing against that one, which is what a wall of
--- crates looks like from here. Both blocked and it stays east -- there is no
--- third visible face to run to.
---
--- Decided here, at four sweeps a second, rather than in the renderer, which
--- would redo it for every sign on every frame for an answer that only changes
--- when the furniture does.
---
--- Only ever asked when the sign has not been pinned to a face by hand: a
--- player who moved it there meant it, and a crate turning up next door is no
--- reason to overrule them.
local function faceFor(cell, square, x, y, z)
    if faceIsClear(cell, square, x + 1, y, z) then return "east" end
    if faceIsClear(cell, square, x, y + 1, z) then return "south" end
    return "east"
end

--- How far the object's sprite actually reaches to each side of the near
--- corner, as a fraction of half a tile.
---
--- Furniture does not fill the square it stands on: the vanilla crate covers
--- 86 per cent of its tile, so a sign sized and centred on the tile hangs off
--- the crate on one side and leaves a gap on the other. The texture knows the
--- answer -- PZ trims the transparent margin off every sprite and remembers
--- what it cut, which is exactly the silhouette -- so this asks rather than
--- guesses, and works the same for a narrow shelf or an overhanging table.
---
--- Returns nil if the sprite will not say, and the caller falls back to the
--- whole tile.
local function spriteExtent(obj)
    local sprite = LPBCS.get(obj, "getSprite", nil)
    if not sprite then return nil end

    local dir = LPBCS.get(obj, "getDir", nil)
    if dir == nil then return nil end

    local texture = LPBCS.attempt(function()
        return sprite:getTextureForCurrentFrame(dir)
    end)
    if not texture then return nil end

    local frame = LPBCS.get(texture, "getWidthOrig", nil)
    local width = LPBCS.get(texture, "getWidth", nil)
    local offset = LPBCS.get(texture, "getOffsetX", nil)
    if type(frame) ~= "number" or type(width) ~= "number" or type(offset) ~= "number" then
        return nil
    end
    if frame <= 0 or width <= 0 then return nil end

    local half = frame / 2
    return (half - offset) / half, (offset + width - half) / half
end

--- The share of its tile face the sign has to work with, on the side it hangs.
--- Clamped: a sprite that reaches barely anywhere, or well past its tile,
--- should still get a sign of a sane size.
local function extentFor(obj, face)
    local left, right = spriteExtent(obj)
    local reach = (face == "south") and left or right
    if type(reach) ~= "number" then return 1 end
    return LPBCS.clampFloat(reach, 0.4, 1)
end

--- Forces the next read to sweep again. Called after this player writes or
--- erases a sign, so their own change shows up without waiting out the clock.
function Scan.invalidate(playerNum)
    if playerNum == nil then
        for _, cache in pairs(Scan.cache) do cache.dirty = true end
        return
    end
    cacheFor(playerNum).dirty = true
end

--- Combien d'écriteaux le dernier balayage a trouvés. Sert au diagnostic :
--- une console qui dit zéro quand on est devant une caisse nommée déplace la
--- recherche du côté du balayage plutôt que du côté des sprites.
---
--- Déclaré ICI et pas plus bas près de l'horloge : refresh() s'en sert, et un
--- local déclaré après lui n'est pas dans sa portée -- la fonction écrivait
--- alors dans un global du même nom pendant que le local restait à -1.
local lastSeen = -1

--- Combien de balayages ont vraiment eu lieu. onTick s'en sert pour ne purger
--- les écriteaux hors rayon qu'après un balayage, et non à chacun de ses
--- soixante battements par seconde.
local sweeps = 0

local function refresh(cache, px, py, pz)
    local entries = {}
    local placed = {}
    cache.entries = entries
    cache.placed = placed
    sweeps = sweeps + 1

    local cell = getCell()
    if not cell then return end

    local radius = Options.radius()
    -- Lus une fois pour tout le balayage et passés à Options.alphaAt : chaque
    -- lecture d'option est un pcall dans la page d'options.
    local opacity = Options.opacity()
    -- One container may be reachable from several tiles of a wide piece of
    -- furniture; the sign belongs to the container, not to the tile.
    local seen = {}

    for x = px - radius, px + radius do
        for y = py - radius, py + radius do
            local square = cell:getGridSquare(x, y, pz)
            if square then
                LPBCS.eachContainerOnSquare(square, function(obj, container)
                    if seen[container] then return end
                    seen[container] = true

                    local label = Label.read(obj, container)
                    if not label then
                        -- Plus d'écriteau : s'il en restait un de posé, il
                        -- part maintenant. C'est le chemin de l'effacement.
                        Sprites.sync(obj, nil)

                        -- Et le nom local s'en va avec lui. C'EST ICI que ce
                        -- client apprend qu'un écriteau effacé ailleurs est
                        -- parti : setCustomName ne voyage pas, donc le serveur
                        -- n'a nettoyé que le sien. Sans cette ligne, le repli
                        -- de Label.read relisait le nom que ce client s'était
                        -- écrit à lui-même au balayage précédent et raccrochait
                        -- l'écriteau -- indéfiniment.
                        --
                        -- Muet quand il n'y a rien à retirer, donc appelable à
                        -- chaque balayage : la sortie anticipée d'unmirror est
                        -- le cas courant, un conteneur sans nom.
                        Label.unmirror(container)
                        return
                    end

                    -- UN NOM N'EST PAS UN ÉCRITEAU, et c'est ici que ça se voit.
                    --
                    -- Label.read rend aussi le repli : ce que le « Renommer »
                    -- du jeu de base a laissé sur le conteneur, ou ce qu'une
                    -- clé vanilla a rapporté d'un déménagement. Ce repli est
                    -- fait pour être AFFICHÉ -- barre de titre, infobulle,
                    -- LPBCS_Inventory -- et le rendre ici accrochait une
                    -- planche sur une caisse que personne n'avait écrite : le
                    -- joueur demandait un nom et recevait un écriteau.
                    --
                    -- Rien à démiroiter au passage : le nom est légitime, il
                    -- reste, il n'y a que la planche qui n'a rien à faire là.
                    -- C'est toute la différence avec la sortie ci-dessus.
                    if label.fromName then
                        Sprites.sync(obj, nil)
                        return
                    end

                    -- Une commodité, et rien de plus : que getCustomName() --
                    -- la seule surface par laquelle les autres mods voient un
                    -- nom de conteneur -- dise la même chose que l'écriteau.
                    Label.mirror(obj, container, label.text)

                    -- Le côté choisi par le joueur passe devant le côté deviné,
                    -- y compris quand il met l'écriteau face à un mur : c'est
                    -- son affaire, pas la nôtre.
                    local face = label.side or faceFor(cell, square, x, y, pz)
                    local extent = extentFor(obj, face)

                    -- Le fondu du bord du rayon, la règle que le repli
                    -- applique aussi (Options.alphaAt). De centre de tuile à
                    -- centre de tuile : le balayage raisonne en cases, et
                    -- c'est ce qui arrondit en disque la boîte carrée
                    -- parcourue par les deux boucles.
                    local dx, dy = x - px, y - py
                    local alpha = Options.alphaAt(math.sqrt(dx * dx + dy * dy),
                        radius, opacity)

                    -- L'écriteau dans le monde. Muet tant que rien n'a changé,
                    -- donc appelable à chaque balayage : c'est lui qui rattrape
                    -- un chargement de chunk ou une écriture venue du réseau.
                    Sprites.sync(obj, label, face, extent, alpha)
                    if Sprites.isPlaced(obj) then placed[obj] = true end

                    entries[#entries + 1] = {
                        x = x,
                        y = y,
                        z = pz,
                        square = square,
                        -- The renderer needs the object itself to ask how tall
                        -- it is, the face to know which plane to draw in, and
                        -- the extent to know how much of that face the object
                        -- actually occupies.
                        object = obj,
                        face = face,
                        extent = extent,
                        label = label,
                    }
                end)
            end
        end
    end

    -- Back to front, so a sign on a crate nearer the camera covers the one
    -- behind it rather than the other way round. Depth in an isometric view
    -- runs along x + y: both axes come towards the screen, so the sum is what
    -- orders two tiles, not either coordinate on its own.
    table.sort(entries, function(a, b)
        local depthA, depthB = a.x + a.y, b.x + b.y
        if depthA ~= depthB then return depthA < depthB end
        return a.x < b.x
    end)

    if #entries ~= lastSeen then
        lastSeen = #entries
        LPBCS.log("Scan", "%d conteneur(s) nomme(s) dans le rayon", #entries)
    end
end

--- The signs around this player. Cheap to call every frame.
function Scan.entries(playerNum)
    local cache = cacheFor(playerNum)

    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj then
        -- Plus de joueur, plus rien de posé pour son compte : sans vider aussi
        -- `placed`, la purge de onTick garderait indéfiniment les écriteaux du
        -- dernier rayon qu'il a regardé.
        cache.entries = {}
        cache.placed = {}
        return cache.entries
    end

    local square = playerObj:getSquare()
    if not square then return cache.entries end

    local px, py, pz = square:getX(), square:getY(), square:getZ()
    local now = LPBCS.nowMs()
    local moved = (px ~= cache.x or py ~= cache.y or pz ~= cache.z)

    if cache.dirty or moved or (now - cache.at) >= REFRESH_MS then
        cache.dirty = false
        cache.at = now
        cache.x, cache.y, cache.z = px, py, pz
        refresh(cache, px, py, pz)
    end

    return cache.entries
end

--- Placing or removing furniture changes what is out there, and neither
--- event moves the player, so the clock alone would leave a stale sign
--- hanging in the air for a quarter of a second. Cheap to be exact.
local function onObjectChanged()
    Scan.invalidate(nil)
end

Events.OnObjectAdded.Add(onObjectChanged)
if Events.OnObjectAboutToBeRemoved then
    Events.OnObjectAboutToBeRemoved.Add(onObjectChanged)
end

-- ------------------------------------------------------------- l'horloge

--- Les écriteaux doivent-ils quitter l'écran ? Deux raisons : le joueur a
--- coupé l'affichage, ou il fouille une caisse et a demandé qu'ils s'écartent
--- le temps qu'il le fasse.
---
--- La question se pose pour tout le client et pas par joueur, et c'est une
--- limite à assumer : un sprite est accroché à l'objet du monde, pas à un
--- écran. En écran partagé, la fenêtre de butin de l'un masquera donc les
--- écriteaux des deux. Options.enabled() a déjà exactement cette propriété --
--- PZAPI.ModOptions est par client, pas par joueur -- donc rien ne se dégrade
--- ici ; ce n'est simplement pas réparable de ce côté-ci.
local function hidden(players)
    if not Options.enabled() then return true end
    if not Options.hideWhenLootOpen() then return false end

    for playerNum = 0, players - 1 do
        if Options.lootWindowOpen(playerNum) then return true end
    end
    return false
end

local wasHidden = nil

--- Ce qui fait tourner le balayage.
---
--- Il était autrefois entraîné par le rendu interface, qui appelait
--- Scan.entries() à chaque image. Depuis que l'écriteau est posé dans le monde
--- ce rendu ne s'installe plus, et sans ce battement plus rien n'appellerait le
--- balayage : aucun écriteau ne se poserait jamais. Le sweep lui-même reste
--- protégé par son horloge interne (quatre fois par seconde), donc taper ici à
--- chaque tick ne coûte que la comparaison.
local function onTick()
    Sprites.report()

    local players = LPBCS.attempt(getNumActivePlayers) or 1

    if hidden(players) then
        -- Un seul passage, puis plus rien : les écriteaux hors du rayon ne
        -- seront jamais balayés, il faut les retirer explicitement, et il ne
        -- sert à rien de recommencer à chaque battement.
        if wasHidden ~= true then Sprites.clearAll() end
        wasHidden = true
        return
    end

    if wasHidden == true then
        -- De retour. Le cache croit encore que tout est en place, alors que
        -- clearAll vient de tout décrocher : sans ça, sync trouverait sa
        -- signature inchangée et ne reposerait rien.
        Scan.invalidate(nil)
    end
    wasHidden = false

    local before = sweeps
    local keep = {}
    for playerNum = 0, players - 1 do
        Scan.entries(playerNum)
        local cache = Scan.cache[playerNum]
        if cache and cache.placed then
            for obj in pairs(cache.placed) do keep[obj] = true end
        end
    end

    -- L'union de tous les joueurs, jamais joueur par joueur : `applied` est
    -- global, donc purger sur le seul rayon de l'un décrocherait ce que
    -- l'autre a sous les yeux. Et seulement après un vrai balayage : sans ce
    -- garde-fou on repasserait sur tous les écriteaux posés soixante fois par
    -- seconde pour n'y rien changer.
    if sweeps ~= before then Sprites.retain(keep) end
end

Events.OnTick.Add(onTick)

return Scan
