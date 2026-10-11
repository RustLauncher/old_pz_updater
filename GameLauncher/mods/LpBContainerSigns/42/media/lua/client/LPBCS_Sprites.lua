--[[
    © 2026 Warlord-Fox3. Tous droits réservés / All Rights Reserved.

    Toute réutilisation, modification, redistribution ou inclusion dans un
    modpack sans autorisation écrite préalable est strictement interdite.

    Any reuse, modification, redistribution, or inclusion in a modpack
    without prior written permission is strictly prohibited.
]]

--[[
    LPBCS_Sprites -- l'écriteau posé dans le monde, dessiné par le moteur.

    Le rendu interface (LPBCS_Render) reste en repli, mais c'est ici que se
    joue la version qui compte : au lieu de dessiner l'écriteau par-dessus le
    monde à chaque image, on accroche des sprites à l'objet une fois pour
    toutes et on laisse le moteur s'en occuper. Il est alors éclairé comme la
    caisse, trié en profondeur avec elle, et un personnage qui passe devant le
    masque -- ce qu'aucune astuce d'interface ne sait faire.

    Cinq choses ont dû être établies en jeu avant d'écrire ce fichier, parce
    qu'aucune n'est documentée :

      - Un sprite se positionne en PEIGNANT le décor à sa place dans le cadre
        de tuile (128x256 en 2x), pas en le décalant. La perspective
        isométrique fait partie de l'image : c'est pour ça que les glyphes et
        les planches sont pré-cisaillés, par tools/make_assets.py.
      - Les offsets d'AttachExistingAnim sont INVERSÉS : le bytecode fait
        soffX = -offX. Poser une image au point (x, y) du cadre demande donc
        l'offset (-x, -y).
      - La position et la teinte appartiennent au SPRITE, pas à l'attachement
        (IsoSprite.prepareToRenderSprite lit soffX, soffY et tintMod sur le
        sprite). Deux attachements du même sprite se superposent donc, et de la
        même couleur. C'est ce qui oblige à faire porter au nom du sprite sa
        position et son encre -- voir spriteFor.
      - Le moteur compose ces sprites en ALPHA PRÉMULTIPLIÉ. Une image dont le
        RGB ne porte pas déjà sa couverture voit sa couleur ajoutée à pleine
        force par-dessus un fond seulement partiellement effacé : le contour
        d'une lettre ressort alors plus clair et plus saturé que son cœur. En
        encre sombre ça ne se voit pas, en couleur ça bave. Mesuré sur une
        capture d'un « VHS » rouge : une composition juste fait descendre le
        vert quand le rouge monte, une composition prémultipliée les fait
        descendre ensemble -- corrélation rouge/vert de +0,94 en jeu, contre
        -0,95 pour le modèle juste et +0,99 pour le modèle prémultiplié. Les
        glyphes sont donc fabriqués prémultipliés (tools/make_assets.py), et la
        teinte passée ici l'est aussi -- voir Sprites.apply.
      - Le CONTOUR de sélection, lui, ignore soffX/soffY :
        FBORenderObjectOutline$Drawer2 ne retient qu'une position, celle de
        l'objet, et n'ajoute des sprites attachés que leur texture. Tout ce
        qu'on accroche se retrouve donc dessiné à l'origine de la tuile dès que
        la caisse est mise en surbrillance. Rien ne se règle ici -- voir
        LPBCS_Outline, qui retire l'écriteau de cette passe.

    Tout est en pixels du cadre de tuile 2x, l'échelle des textures du jeu.
]]

require "LPBCS_Core"
require "LPBCS_GlyphMetrics"
require "LPBCS_Options"

LPBCS.Sprites = LPBCS.Sprites or {}
local Sprites = LPBCS.Sprites
local Options = LPBCS.Options

--- Le repli quand l'objet ne déclare pas de hauteur de dessus. 0.62 étage,
--- soit à peu près le haut d'une commode.
local FALLBACK_SURFACE = 0.62

-- Les images vivent à plat dans media/textures/, pas dans un sous-dossier.
-- Ce n'est pas de la négligence : le seul chargement dont on ait la preuve en
-- jeu est celui-là, et un sous-dossier de mod non indexé donne un sprite sans
-- texture -- qui s'attache sans erreur et ne dessine rien.
local GLYPH_DIR = "media/textures/"

-- Le cadre de tuile et la géométrie isométrique, en 2x.
local FRAME_W, FRAME_H = 128, 256
local HALF_W, HALF_H = 64, 32
local STOREY = 192

-- Marges dans l'écriteau, le long de la face et vers le bas.
--
-- La marge horizontale est étroite, et c'est voulu : sur une face de cinquante
-- pixels, chaque pixel rendu à la marge est un pixel de nom qui n'a plus
-- besoin d'aller à la ligne. Trois est mesuré -- tools/check_fit.py compte les
-- pixels d'encre hors de la planche, et il n'y en a aucun jusqu'à deux.
--
-- PAD_V, lui, ne se règle plus ici : il est cuit dans la hauteur des fonds par
-- tools/make_assets.py. Le changer sans régénérer décalerait le texte.
local PAD_U, PAD_V = 3, 3.5

-- Ce que l'écriteau remonte au-dessus du milieu calculé de la face, en pixels
-- du cadre.
--
-- Le milieu calculé n'est pas le milieu vu, et le sprite de la caisse en bois
-- du jeu (carpentry_01_16, sorti de Tiles2x.pack) dit pourquoi : sa silhouette
-- fait 70 pixels de haut et s'arrête 3 pixels au-dessus du bas du cadre, quand
-- la géométrie d'ici prend les 64 pixels que déclare `Surface` -- 32 sur 96,
-- et c'est bien ce que le jeu répond -- et le sol au bas du cadre. Le dessin
-- déborde son gabarit par le haut et s'en retire par le bas : centré à la
-- stricte moitié, l'écriteau se lisait bas.
--
-- Six pixels rattraperaient cet écart en entier, et c'est trop : les pixels du
-- haut sont ceux du REBORD DU COUVERCLE, qui déborde la face et n'est pas du
-- panneau où on cloue une planche. Corriger la silhouette entière remonte donc
-- l'écriteau sur le couvercle. Trois est la moitié, et c'est ce qui se voit
-- juste en jeu -- la valeur est réglée à l'œil sur la caisse, la mesure ne
-- donne que la borne haute.
--
-- Trois pixels de cadre, donc, soit un pixel et demi d'écran au zoom 1. Réglés
-- sur la caisse parce que c'est ce que le mod vise par défaut
-- (Config.cratesOnly) ; sur un meuble plus haut ils passent inaperçus.
--
-- LPBCS_Render applique le même décalage, converti en étages : les deux rendus
-- doivent poser l'écriteau au même endroit.
local LIFT = 3

-- La planche ne descend pas sous cette largeur, même sur un meuble étroit.
--
-- LPBCS_Scan borne déjà l'emprise d'un sprite à 0.4 de demi-tuile, soit
-- vingt-cinq pixels de face : un budget de dix-neuf hacherait « Munitions » en
-- « Mu / niti / ons ». Sous quarante pixels on préfère un écriteau qui déborde
-- un peu à un écriteau que plus personne ne lit.
local SIGN_MIN = 40

-- Tout se mesure HORIZONTALEMENT, pas le long de la face.
--
-- C'est le piège de cette géométrie : une image est large de n pixels à
-- l'écran, pas le long du plan où on la pose. Avancer d'un pixel sur la face
-- avance d'un pixel en x et d'un demi en y, donc le pas est (1, -pente) et
-- non le vecteur unitaire de la face. Mesurer le long de la face donnait une
-- planche 12 pour cent trop longue, qui dépassait de la caisse.
local STEP_Y = HALF_H / HALF_W

-- ------------------------------------------------------------- le registre

--- Le sprite a-t-il vraiment une image ?
---
--- AddSprite réussit même quand la texture ne se charge pas : on obtient alors
--- un sprite qui s'attache sans erreur et ne dessine rien. C'est exactement le
--- silence qu'il faut éviter, donc on vérifie la texture, pas l'enregistrement.
---
--- La direction n'est pas optionnelle : getTextureForCurrentFrame(nil) ne rend
--- rien, et le contrôle échouait donc toujours -- ce qui faisait basculer tout
--- le mod sur son rendu de repli. Vanilla passe IsoDirections.N pour la même
--- question (DebugChunkStateUI), et nos sprites n'ont de toute façon qu'une
--- seule direction.
local function anyDirection()
    return IsoDirections and IsoDirections.N or nil
end

local function hasTexture(sprite)
    local texture = LPBCS.attempt(function()
        return sprite:getTextureForCurrentFrame(anyDirection())
    end)
    if not texture then return false end
    return (LPBCS.get(texture, "getWidth", 0) or 0) > 0
end

local registered = {}

--- Le sprite enregistré sous ce nom, créé à la demande depuis le PNG du mod.
---
--- `name` est l'identité du sprite, `texture` le fichier à y charger, et les
--- deux ne sont PAS la même chose. C'est le point le plus contre-intuitif de
--- tout ce fichier, et il est vérifié dans le bytecode :
--- IsoSprite.prepareToRenderSprite lit soffX, soffY et tintMod sur le SPRITE,
--- pas sur l'instance attachée. Deux attachements du même sprite s'affichent
--- donc au même endroit et de la même couleur -- le dernier posé gagne.
---
--- Une lettre à deux endroits, ou deux caisses écrites de deux couleurs, sont
--- donc deux sprites distincts qui partagent une texture. D'où un nom qui
--- porte la position et la teinte, et un jeu de sprites borné par le nombre de
--- mises en page réellement présentes dans le monde -- quelques centaines pour
--- une base entière, tous adossés aux mêmes 432 images.
---
--- Seuls les sprites qui ont VRAIMENT une image sont mémorisés, et un sprite
--- sans image est rechargé plutôt qu'abandonné.
---
--- C'est ce qui a mis le plus longtemps à se voir. Le premier appel a lieu au
--- tout début de la partie, avant que le moteur ne sache charger une texture :
--- AddSprite réussit, LoadFrames ne charge rien, et on se retrouve avec un
--- sprite creux. Mémorisé, il condamnait la session -- et vider le cache n'y
--- suffirait pas, puisque IsoSpriteManager garde lui aussi ce sprite sous ce
--- nom et le rendrait à nouveau. D'où le rechargement sur place, idempotent,
--- qui aboutit dès que le moteur est prêt.
local function spriteFor(name, texture)
    local cached = registered[name]
    if cached then return cached end

    local manager = IsoSpriteManager and LPBCS.attempt(function()
        return IsoSpriteManager.instance
    end)
    if not manager then return nil end

    local path = GLYPH_DIR .. (texture or name) .. ".png"

    local sprite = LPBCS.attempt(function() return manager:getSprite(name) end)
    if not sprite then
        sprite = LPBCS.attempt(function() return manager:AddSprite(name) end)
        if not sprite then return nil end
        LPBCS.invoke(sprite, "LoadFramesNoDirPageSimple", path)
    end

    if not hasTexture(sprite) then
        LPBCS.invoke(sprite, "LoadFramesNoDirPageSimple", path)
        if not hasTexture(sprite) then return nil end
    end

    registered[name] = sprite
    return sprite
end

--- La voie monde est-elle praticable sur ce build ? Le gestionnaire de sprites
--- répond-il, et le premier glyphe arrive-t-il vraiment avec son image.
function Sprites.available()
    local probe = LPBCS.GLYPHS and LPBCS.GLYPHS[65]
    if not probe or not probe.e then return false end

    local sprite = spriteFor(probe.e.sprite, probe.e.sprite)
    return sprite ~= nil and hasTexture(sprite)
end

--- Un état des lieux, écrit une seule fois dans la console au démarrage.
---
--- Ce chemin dépend de trois choses qui peuvent manquer sans rien dire : le
--- gestionnaire de sprites du moteur, la table de métriques générée, et les
--- images. Quand rien ne s'affiche, c'est la première chose à lire.
local reported = false
local firstAsked = nil

--- Combien de temps laisser au moteur avant de conclure à l'échec. Le premier
--- tick arrive avant que le jeu ne sache charger quoi que ce soit : conclure
--- là revenait à annoncer une panne à chaque démarrage.
local GRACE_MS = 10000

function Sprites.report()
    if reported then return end

    -- Rien à dire tant que ça peut encore réussir.
    local ready = Sprites.available()
    if not ready then
        firstAsked = firstAsked or LPBCS.nowMs()
        if (LPBCS.nowMs() - firstAsked) < GRACE_MS then return end
    end

    reported = true

    local manager = IsoSpriteManager and LPBCS.attempt(function()
        return IsoSpriteManager.instance
    end)

    local glyphs = 0
    if LPBCS.GLYPHS then
        for _ in pairs(LPBCS.GLYPHS) do glyphs = glyphs + 1 end
    end

    local planks = LPBCS.PLANKS and LPBCS.PLANKS.plank and LPBCS.PLANKS.plank.e
    local probe = LPBCS.GLYPHS and LPBCS.GLYPHS[65]
    local sprite = probe and probe.e and spriteFor(probe.e.sprite, probe.e.sprite)

    local size = "AUCUNE"
    if sprite then
        local texture = LPBCS.attempt(function()
            return sprite:getTextureForCurrentFrame(anyDirection())
        end)
        if texture then
            size = string.format("%sx%s", tostring(LPBCS.get(texture, "getWidth", 0)),
                tostring(LPBCS.get(texture, "getHeight", 0)))
        end
    end

    LPBCS.log("Sprites", "IsoSpriteManager=%s metriques=%d glyphes planches=%s "
        .. "sprite d'essai=%s texture=%s",
        manager and "oui" or "NON", glyphs, planks and "oui" or "NON",
        sprite and "oui" or "NON", size)

    if not manager or glyphs == 0 or not planks or not sprite or size == "AUCUNE" then
        LPBCS.log("Sprites", "voie monde INDISPONIBLE -- l'ancien rendu prend le relais")
    end
end

-- ------------------------------------------------------------- les replis

--- Le nom tel que l'atlas peut l'écrire.
---
--- Un caractère absent perd son accent, jamais sa place : « Łódź » s'écrit
--- « Lodz », et ce qui ne se replie sur rien -- cyrillique, grec, CJK -- prend
--- l'avance d'une espace. Les six langues du mod passent ici sans rien perdre ;
--- la table de replis est là pour la septième.
---
--- C'est un défaut de l'atlas, pas une correction de la saisie : ce que le
--- joueur a tapé reste intact dans le ModData et dans le nom du conteneur. Seul
--- le dessin se replie.
---
--- Sous Kahlua une chaîne est une chaîne Java, donc string.byte rend le POINT
--- DE CODE (ñ → 241) et non un octet UTF-8 : GLYPHS et FOLD s'indexent
--- directement dessus. Voir LPBCS_Render pour ce que ça implique ailleurs.
function Sprites.fold(text)
    local out, dirty = {}, false
    for index = 1, #text do
        local code = string.byte(text, index)
        if LPBCS.GLYPHS[code] then
            out[index] = string.sub(text, index, index)
        else
            -- L'espace de secours est ce qui distingue ce code de celui d'avant.
            -- Un caractère inconnu ne faisait pas avancer le curseur, donc il ne
            -- manquait pas : il se faisait recouvrir. « Cañón » s'écrivait
            -- « Can », et la planche était taillée sur cette largeur-là.
            out[index] = (LPBCS.FOLD and LPBCS.FOLD[code]) or " "
            dirty = true
        end
    end
    if not dirty then return text end
    return table.concat(out)
end

-- --------------------------------------------------------------- la mesure

--- Largeur du nom, en pixels du cadre.
---
--- La mesure replie d'abord, comme la pose : les deux doivent lire le MÊME
--- texte, sinon la planche est taillée pour un nom que personne ne voit. C'est
--- pour ça que fill() peut mesurer des sous-chaînes en toute confiance -- le
--- repli est caractère par caractère, donc la largeur d'un morceau reste la
--- somme des largeurs de ses lettres.
function Sprites.measure(text)
    local folded = Sprites.fold(text)
    local total = 0
    for index = 1, #folded do
        local glyph = LPBCS.GLYPHS[string.byte(folded, index)]
        if glyph then total = total + glyph.adv end
    end
    return total
end

--- La ligne la plus large du lot.
local function widest(rows)
    local most = 0
    for index = 1, #rows do
        local width = Sprites.measure(rows[index])
        if width > most then most = width end
    end
    return most
end

--- Les fonds et leur hauteur, par nombre de lignes. Rien n'est supposé
--- présent : un atlas régénéré avec --lines 2 doit continuer à tourner, avec
--- une ligne de moins.
local function familyFor(rows)
    if rows <= 1 then return LPBCS.PLANKS end
    return LPBCS["PLANKS" .. rows]
end

local function heightFor(rows)
    if rows <= 1 then return LPBCS.PLANK_HEIGHT end
    return LPBCS["PLANK_HEIGHT_" .. rows] or LPBCS.PLANK_HEIGHT
end

--- La planche la plus large que ce meuble puisse porter.
---
--- C'est ici que se joue tout le sujet : la coupe se mesure sur la CAISSE, et
--- non sur le plus grand fond qui existe. L'ancien budget valait PLANK_MAX
--- moins les marges -- soixante-seize pixels -- quand la face d'une caisse
--- vanilla en fait cinquante-cinq. Une ligne pleine obtenait donc une planche
--- de quatre-vingt-huit posée au milieu de cinquante-cinq de caisse, et
--- débordait de seize pixels de chaque côté avant même qu'un retour à la ligne
--- ne soit envisagé.
---
--- L'arrondi va vers le BAS, jamais au palier le plus proche. Un palier de
--- trop paraît anodin -- quatre pixels de cadre, deux à l'écran -- mais la
--- planche est un parallélogramme cisaillé : ce qui dépasse d'un pixel dépasse
--- sur toute la hauteur de l'écriteau, et tools/make_poster.py le compte en
--- dizaines de pixels dans le vide. Mieux vaut une lettre de moins par ligne.
local function capFor(extent)
    local cap = math.floor(HALF_W * (extent or 1) / LPBCS.PLANK_STEP)
        * LPBCS.PLANK_STEP
    if cap < SIGN_MIN then cap = SIGN_MIN end
    if cap > LPBCS.PLANK_MAX then cap = LPBCS.PLANK_MAX end
    return cap
end

--- Combien de lignes cet écriteau a le droit de porter.
---
--- Deux plafonds, et le plus bas gagne. Les images d'abord : sans fond à trois
--- lignes, la troisième tomberait à cheval sur le bord de la planche. La face
--- ensuite : une planche plus haute que le dessus du meuble pendrait sous lui.
local function maxLines(faceHeight, style, faceKey)
    local rows = 1
    while rows < (LPBCS.MAX_LINES or 1) do
        local family = familyFor(rows + 1)
        local planks = family and family[style]
        if not (planks and planks[faceKey]) then break end
        if heightFor(rows + 1) > faceHeight then break end
        rows = rows + 1
    end
    return rows
end

--- Les mots dans l'ordre, autant qu'il en tient par ligne.
---
--- `cut` dit quoi faire d'un mot plus large qu'une ligne entière : refuser la
--- mise en page (la coupe reste alors sur les espaces, mots entiers), ou
--- couper dans le mot au caractère près.
local function fill(text, width, cut)
    local rows, current = {}, nil

    -- La variable de boucle est copiée : la coupe dans le mot consomme ce
    -- qu'elle a posé, et une variable de boucle est constante à partir de
    -- Lua 5.4.
    for token in string.gmatch(text, "%S+") do
        local word = token
        local joined = current and (current .. " " .. word) or word
        if Sprites.measure(joined) <= width then
            current = joined
        else
            if current then rows[#rows + 1] = current end
            current = nil

            if Sprites.measure(word) <= width then
                current = word
            elseif not cut then
                return nil
            else
                -- Le mot ne tient sur aucune ligne. On prend le dernier
                -- caractère qui rentre encore, et on recommence avec le reste.
                while Sprites.measure(word) > width do
                    local taken = 0
                    for index = 1, #word do
                        if Sprites.measure(string.sub(word, 1, index)) > width then
                            break
                        end
                        taken = index
                    end
                    -- Une ligne trop étroite pour une seule lettre : en poser
                    -- une quand même, sinon la boucle ne finit jamais.
                    if taken < 1 then taken = 1 end
                    rows[#rows + 1] = string.sub(word, 1, taken)
                    word = string.sub(word, taken + 1)
                end
                if word ~= "" then current = word end
            end
        end
    end

    if current then rows[#rows + 1] = current end
    if #rows == 0 then rows[1] = text end
    return rows
end

--- Le nom découpé en lignes, et la largeur de la plus longue.
---
--- `cap` est la planche la plus large que le meuble accepte, `maxRows` le
--- nombre de lignes qu'il peut porter. Trois passes, et l'ordre fait tout le
--- résultat :
---
---   A. Mots entiers. Le moins de lignes possible d'abord, la planche la plus
---      étroite ensuite -- l'écriteau reste petit sans qu'un mot soit jamais
---      coupé pour rien.
---   B. Un mot seul plus large que la caisse. On le coupe, mais au budget
---      PLEIN et non au plus étroit, pour le couper le moins souvent
---      possible : « Electronique » donne « Electroniq / ue » et non
---      « Elect / roni / que ».
---   C. Même coupé, ça ne tient pas -- un nom au maximum, tout en capitales,
---      ou un meuble qui ne supporte qu'une ligne. On desserre la largeur
---      au-delà de la caisse plutôt que de perdre des caractères. C'est le
---      seul débordement qui subsiste, et il est choisi.
function Sprites.lines(text, cap, maxRows)
    cap = cap or LPBCS.PLANK_MAX
    maxRows = maxRows or 1

    local step = LPBCS.PLANK_STEP

    for rows = 1, maxRows do
        for plank = LPBCS.PLANK_MIN, cap, step do
            local packed = fill(text, plank - PAD_U * 2, false)
            if packed and #packed <= rows then return packed, widest(packed) end
        end
    end

    local packed = fill(text, cap - PAD_U * 2, true)
    if packed and #packed <= maxRows then return packed, widest(packed) end

    -- Au plus large, le texte entier tient sur une ligne : la boucle finit
    -- donc toujours par rendre quelque chose.
    local loose = Sprites.measure(text) + PAD_U * 2
    for plank = cap + step, loose, step do
        packed = fill(text, plank - PAD_U * 2, true)
        if packed and #packed <= maxRows then return packed, widest(packed) end
    end

    return { text }, Sprites.measure(text)
end

--- Le palier de planche qui accueille ce texte. Un sprite ne s'étire pas, donc
--- la largeur est prise dans un jeu fini d'images, et il en existe un jeu par
--- face : une planche cisaillée pour la droite est à l'envers sur la gauche.
--- Et un jeu par nombre de lignes, puisqu'une planche ne s'étire pas non plus
--- en hauteur.
---
--- Pas de plafond de caisse ici : c'est Sprites.lines qui a taillé le texte
--- pour la face, donc la planche qu'on en déduit y tient déjà. PLANK_MAX ne
--- reste que comme la borne de ce qui existe en image.
local function plankFor(style, faceKey, width, rows)
    rows = rows or 1

    local family = familyFor(rows)
    local styled = family and family[style]
    local planks = styled and styled[faceKey]
    if not planks then return nil, 0, 0 end

    local wanted = math.ceil(width / LPBCS.PLANK_STEP) * LPBCS.PLANK_STEP
    if wanted < LPBCS.PLANK_MIN then wanted = LPBCS.PLANK_MIN end
    if wanted > LPBCS.PLANK_MAX then wanted = LPBCS.PLANK_MAX end

    return planks[wanted], wanted, heightFor(rows)
end

-- ----------------------------------------------------------------- la pose

--- Accroche une image au point (x, y) du cadre, de cette couleur.
---
--- L'offset est inversé et entier : soffX/soffY sont des shorts. Et le sprite
--- est identifié par la texture ET par ce qu'on lui demande d'afficher, pour
--- la raison expliquée sur spriteFor.
local function put(obj, texture, x, y, ink, tint)
    local ox, oy = -math.floor(x + 0.5), -math.floor(y + 0.5)
    local name = string.format("%s@%d,%d#%s", texture, ox, oy, ink)

    local sprite = spriteFor(name, texture)
    if not sprite then return false end

    return LPBCS.invoke(obj, "AttachExistingAnim", sprite, ox, oy,
        false, 0, false, 0, tint)
end

--- À quelle hauteur est le dessus de l'objet, en étages, **par rapport à
--- l'objet lui-même**.
---
--- La nuance est tout le sujet. getSurfaceOffsetNoTable() ajoute
--- getRenderYOffset() -- le décalage d'empilement -- pour donner une hauteur
--- absolue au-dessus du sol. Or le moteur applique déjà ce même décalage aux
--- sprites attachés (IsoObject.renderAttachedSprites). S'en servir revenait à
--- compter l'empilement deux fois : sur une caisse posée sur une autre,
--- l'écriteau montait d'un cran de trop.
---
--- La propriété brute du sprite, elle, ne connaît que l'objet : 32 pour une
--- caisse en bois, empilée ou non, soit un tiers d'étage. C'est celle qu'il
--- faut, et vanilla la lit de la même façon (TileGeometryEditor).
function Sprites.surface(obj)
    local props = LPBCS.get(obj, "getProperties", nil)
    local raw = props and LPBCS.get(props, "getSurface", nil)

    -- Repli sur l'ancienne mesure si le sprite ne déclare rien : elle vaut
    -- mieux que rien, au décalage d'empilement près.
    if type(raw) ~= "number" or raw <= 0 then
        raw = LPBCS.get(obj, "getSurfaceOffsetNoTable", nil)
    end
    if type(raw) ~= "number" then return FALLBACK_SURFACE end

    local storeys = raw / 96
    if storeys <= 0.05 or storeys > 1.8 then return FALLBACK_SURFACE end
    return storeys
end

-- ------------------------------------------------------------ le cycle de vie

--- Ce qui est posé, et sous quelle forme. Sert à ne pas tout retirer et
--- reposer quatre fois par seconde pour rien, et à savoir quoi nettoyer quand
--- le joueur coupe l'affichage.
local applied = {}

--- Le pas auquel une opacité est arrondie avant d'atteindre un nom de sprite.
---
--- Ce n'est pas de la coquetterie. La teinte appartient au SPRITE et non à
--- l'attachement -- c'est tout le sujet de l'en-tête -- donc chaque opacité
--- distincte, à chaque position distincte, est un sprite de plus dans
--- `registered`, et rien n'y est jamais évincé. Un fondu pris au pied de la
--- lettre frapperait un jeu de glyphes neuf à chaque centième d'opacité
--- traversé par un joueur qui marche.
---
--- Cinq pour cent est déjà le pas du curseur d'opacité et la précision des
--- clés `%.2f` plus bas : rien de visible ne se perd, et le registre reste
--- borné par le nombre de mises en page du monde multiplié par une poignée de
--- paliers de fondu.
local ALPHA_STEP = 0.05

local function quantize(alpha)
    if type(alpha) ~= "number" or alpha <= 0 then return 0 end
    if alpha > 1 then alpha = 1 end
    return math.floor(alpha / ALPHA_STEP + 0.5) * ALPHA_STEP
end

--- L'encre d'un écriteau, et son repli -- un écriteau écrit avant que la
--- couleur existe n'en porte pas.
---
--- UNE SEULE LECTURE, et c'est tout l'intérêt de cette fonction de trois
--- lignes. Ces valeurs entrent dans le NOM du sprite (`inkKey`, plus bas) et
--- dans la SIGNATURE qui décide s'il faut le reposer ; les lire à deux endroits
--- les laisse libres de diverger, et la divergence est muette. Elle l'a été :
--- la signature ne portait pas l'encre du tout, donc `sync` se taisait quand
--- seule la couleur avait changé. La ModData disait rouge, l'écran montrait le
--- noir de la veille, et il fallait toucher au TEXTE -- ou marcher assez pour
--- changer de palier d'opacité -- pour que l'écriteau se reprenne.
local function inkOf(label)
    return label.r or 0.13, label.g or 0.13, label.b or 0.13
end

--- Tout ce qui, en changeant, change les sprites accrochés. Rien de plus :
--- chaque champ de trop est un écriteau reposé pour rien, quatre fois par
--- seconde. Rien de moins : chaque champ qui manque est un changement que le
--- joueur ne verra jamais arriver.
---
--- L'encre est arrondie au CENTIÈME, exactement comme `inkKey` l'arrondit dans
--- le nom du sprite. Plus fin serait une signature qui bouge pour deux couleurs
--- que le registre ne sait pas distinguer -- une repose sans rien à reposer ;
--- plus grossier serait deux jeux de sprites sous une seule signature, et le
--- silence d'où l'on vient.
local function signature(label, face, extent, surface, alpha)
    local r, g, b = inkOf(label)
    return string.format("%s|%s|%s|%.3f|%.3f|%.2f|%.2f,%.2f,%.2f", label.text,
        label.style or "plank", face or "east", extent or 1, surface, alpha,
        r, g, b)
end

--- Met l'objet en accord avec son écriteau, et ne fait rien s'il l'est déjà.
--- C'est le point d'entrée du balayage : appelé souvent, il doit être muet la
--- plupart du temps.
---
--- `alpha` est l'opacité voulue à cette distance, calculée par le balayage
--- (LPBCS_Options.alphaAt). Trop faible, l'écriteau part : c'est ce qui donne
--- au rayon un bord plutôt qu'une frontière que rien ne franchit jamais.
function Sprites.sync(obj, label, face, extent, alpha)
    if not obj then return end

    alpha = quantize(alpha)

    if not label or not Options.enabled() or Options.tooFaint(alpha) then
        if applied[obj] then
            Sprites.clear(obj)
            applied[obj] = nil
        end
        return
    end

    local surface = Sprites.surface(obj)
    local want = signature(label, face, extent, surface, alpha)
    if applied[obj] == want then return end

    if Sprites.apply(obj, label, face, extent, surface, alpha) then
        applied[obj] = want
    else
        applied[obj] = nil
    end
end

--- Cet objet porte-t-il un écriteau posé dans le monde ?
---
--- C'est la question que pose le rendu de repli avant de dessiner : les deux
--- chemins coexistent, et celui de l'interface ne s'occupe que de ce que
--- l'autre n'a pas réussi à prendre. Plus de décision unique au chargement,
--- donc plus de dépendance à l'instant où l'on demande.
function Sprites.isPlaced(obj)
    return obj ~= nil and applied[obj] ~= nil
end

--- Tout retirer : le joueur a coupé l'affichage, ou le mod s'efface.
function Sprites.clearAll()
    for obj in pairs(applied) do
        Sprites.clear(obj)
    end
    applied = {}
end

--- Retire les écriteaux de tout objet absent de `keep`.
---
--- Le balayage ne visite que la boîte du rayon autour du joueur : un objet
--- qu'on quitte n'est plus jamais synchronisé, donc rien ne lui disait jamais
--- de rendre son écriteau. Il restait accroché derrière soi, à pleine
--- opacité, jusqu'à ce que le joueur coupe l'affichage. C'est ici que la
--- sortie du rayon se paie, et c'est ce qui donne son sens au fondu du bord :
--- sans ça un écriteau s'estomperait sans jamais disparaître.
---
--- Mettre la clé courante à nil pendant un `pairs` est permis ; en poser une
--- autre ne l'est pas, et rien ici n'en pose.
function Sprites.retain(keep)
    for obj in pairs(applied) do
        if not (keep and keep[obj]) then
            Sprites.clear(obj)
            applied[obj] = nil
        end
    end
end

--- Retire les écriteaux posés sur cet objet.
---
--- Point ouvert, et il est délibérément laissé visible : une instance attachée
--- ne dit pas de quel sprite elle vient (getName et getParentSprite rendent
--- nil), donc on ne sait pas retirer les nôtres seulement. Sur une caisse rien
--- d'autre n'est attaché, mais ce n'est pas une garantie -- à régler avant de
--- publier.
function Sprites.clear(obj)
    if LPBCS.get(obj, "getAttachedAnimSpriteCount", 0) > 0 then
        LPBCS.invoke(obj, "RemoveAttachedAnims")
    end
end

--- Pose l'écriteau : la planche, puis le nom lettre par lettre le long de la
--- pente. `face` et `extent` viennent du balayage (LPBCS_Scan), `surface` de
--- la hauteur déclarée par le sprite de l'objet.
--- Un mot à l'écran, une seule fois, quand la pose échoue.
---
--- La console dit tout mais il faut aller la lire, et un joueur qui ne voit
--- rien n'a aucune raison de savoir où chercher. Ceci met la réponse là où le
--- problème se voit.
local warned = false

local function warnOnce(text)
    if warned then return end
    warned = true

    LPBCS.log("Sprites", "%s", text)
    local player = LPBCS.attempt(getSpecificPlayer, 0)
    if player and HaloTextHelper then
        LPBCS.attempt(function()
            HaloTextHelper.addText(player, "LpB: " .. text, 1.0, 0.5, 0.3)
        end)
    end
end

function Sprites.apply(obj, label, face, extent, surface, alpha)
    if not obj or not label then return false end

    -- Tant que l'atlas ne répond pas, on ne touche à rien : accrocher des
    -- sprites creux ferait croire à un écriteau posé, effacerait le rendu de
    -- repli, et ne dessinerait rien. Mieux vaut ne pas commencer.
    if not Sprites.available() then return false end

    Sprites.clear(obj)

    local faceHeight = surface * STOREY

    -- La largeur de la face, à l'horizontale : une demi-tuile, moins ce que le
    -- meuble n'occupe pas.
    local faceWidth = HALF_W * (extent or 1)

    -- Sens de lecture, et de quel côté du coin proche la face se développe.
    local ex, ey = 1, -STEP_Y
    local outward = 1
    if face == "south" then
        ey = STEP_Y
        outward = -1
    end

    local faceKey = (face == "south") and "s" or "e"
    local style = label.style or "plank"

    -- Le nom se taille sur le meuble, pas sur le plus grand fond disponible :
    -- c'est la caisse qui décide de la largeur d'une ligne, et sa hauteur du
    -- nombre de lignes.
    local lines, textWidth =
        Sprites.lines(label.text, capFor(extent), maxLines(faceHeight, style, faceKey))
    local name, plankWidth, height =
        plankFor(style, faceKey, textWidth + PAD_U * 2, #lines)
    if not name then return false end

    -- Le coin proche de la face, au niveau du dessus de l'objet, puis le
    -- milieu de la portion que l'objet occupe vraiment.
    local nearX, nearY = FRAME_W / 2, FRAME_H - faceHeight
    local midX = nearX + ex * outward * faceWidth / 2
    local midY = nearY + ey * outward * faceWidth / 2

    -- Le rattrapage cède devant le haut de l'objet : sur une face courte le
    -- centre est déjà tout en haut, et remonter encore décollerait l'écriteau
    -- du meuble. La borne à zéro qui suit s'en charge.
    local inset = (faceHeight - height) / 2 - LIFT
    if inset < 0 then inset = 0 end

    local tlx = midX - ex * plankWidth / 2
    local tly = midY - ey * plankWidth / 2 + inset

    -- La planche : son image est plus haute que le panneau de w * pente. Sur la
    -- face droite le panneau est en bas de l'image, donc l'ancrage remonte ;
    -- sur la face gauche il est en haut et l'image se pose telle quelle.
    -- L'opacité vient du balayage, déjà quantifiée : elle entre dans le nom du
    -- sprite, et un nom par centième d'opacité ne se rattrape pas.
    --
    -- Les deux teintes qui suivent sont PRÉMULTIPLIÉES : leurs canaux de couleur
    -- sont déjà multipliés par leur propre opacité. C'est ce que le moteur
    -- attend (voir le point 5 de l'en-tête), et ça ne se voit qu'au fondu :
    -- l'image, elle, est prémultipliée à la fabrication, mais le moteur la
    -- multiplie ENSUITE par ce ColorInfo. Une teinte laissée à pleine couleur
    -- avec une opacité de 0,5 rendrait donc une encre entière sur un fond à
    -- moitié effacé -- un écriteau qui se délave au lieu de s'effacer.
    -- Le blanc de la planche suit la même règle pour la même raison.
    local rise = (faceKey == "e") and (plankWidth * LPBCS.GLYPH_SLOPE) or 0
    alpha = quantize(alpha)
    local plainKey = string.format("%.2f", alpha)
    local white = LPBCS.attempt(function()
        return ColorInfo.new(alpha, alpha, alpha, alpha)
    end)
    put(obj, name, tlx, tly - rise, plainKey, white)

    -- Le nom, une lettre à la fois. Chaque glyphe est déjà cisaillé ; le pas
    -- le long de la pente fait le reste.
    local r, g, b = inkOf(label)
    local inkKey = string.format("%.2f,%.2f,%.2f,%.2f", r, g, b, alpha)
    local ink = LPBCS.attempt(function()
        return ColorInfo.new(r * alpha, g * alpha, b * alpha, alpha)
    end)

    local originX = tlx + ex * PAD_U
    local originY = tly + ey * PAD_U + PAD_V

    -- La deuxième ligne descend tout droit. Sur une face verticale la verticale
    -- du monde est la verticale de l'écran : seule la ligne de base est en
    -- pente, l'interligne ne l'est pas.
    local leading = LPBCS.GLYPH_LINE_HEIGHT or 12

    for row = 1, #lines do
        -- Le même repli que la mesure, sur le même texte. Après lui il ne reste
        -- que des codes connus, et le curseur avance à chaque tour.
        local line = Sprites.fold(lines[row])
        local lineY = originY + (row - 1) * leading
        local cursor = 0
        for index = 1, #line do
            local glyph = LPBCS.GLYPHS[string.byte(line, index)]
            if glyph then
                local variant = glyph[faceKey]
                if variant then
                    put(obj, variant.sprite,
                        originX + ex * cursor + glyph.ox,
                        lineY + ey * cursor + variant.oy,
                        inkKey, ink)
                end
                cursor = cursor + glyph.adv
            end
        end
    end

    -- On ne se déclare pas satisfait sur la foi de nos intentions : si rien ne
    -- s'est accroché, l'écriteau n'existe pas et le rendu de repli doit garder
    -- la main. Se dire posé sans l'être est ce qui a fait disparaître les deux
    -- affichages à la fois.
    local attached = LPBCS.get(obj, "getAttachedAnimSpriteCount", 0) or 0
    if attached <= 0 then
        warnOnce("aucun sprite accroche -- atlas illisible, repli sur l'ancien rendu")
        return false
    end

    return true
end

return Sprites
