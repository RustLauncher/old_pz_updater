--[[
    © 2026 Warlord-Fox3. Tous droits réservés / All Rights Reserved.

    Toute réutilisation, modification, redistribution ou inclusion dans un
    modpack sans autorisation écrite préalable est strictement interdite.

    Any reuse, modification, redistribution, or inclusion in a modpack
    without prior written permission is strictly prohibited.
]]

--[[
    LPBCS_Outline -- retire l'écriteau du contour de sélection.

    Quand la fenêtre de butin met une caisse en surbrillance, le contour orange
    se dédoublait : la caisse était bien entourée, mais un parallélogramme
    fantôme flottait en l'air au-dessus et à gauche d'elle, avec un petit
    contour à côté qui ne correspondait à rien. C'étaient la planche et les
    lettres, toutes empilées à l'origine de la tuile.

    Le contour est construit par FBORenderObjectOutline$Drawer2, et deux choses
    y sont vraies, lues dans le bytecode :

      - init() ne calcule QU'UNE position d'écran, celle de l'objet. Pour
        chaque sprite attaché il ne retient ensuite que la texture --
        initTexture() fait un textures.add() et rien d'autre. Aucune position
        n'est conservée.
      - render() dessine chaque texture de cette liste à renderX +
        texture.getOffsetX(). Le soffX/soffY du sprite, seul endroit où vit la
        position d'un écriteau, n'est jamais lu.

    Il n'y a donc pas moyen de placer ce contour correctement : la position que
    le moteur devrait utiliser, il ne la regarde pas. Ce qui reste, c'est de ne
    pas y participer -- isOutlineHlAttached commande exactement ça, et il est
    testé APRÈS que le sprite propre à l'objet a été ajouté. La caisse garde
    donc son contour ; seul l'écriteau en sort.

    Reste à savoir où se placer. Le mod ne touche jamais ce drapeau : c'est le
    jeu qui le pose, et ISInventoryPage:update() le repose à CHAQUE IMAGE. Un
    nettoyage dans notre propre tick ne tiendrait pas -- il gagnerait ou
    perdrait selon l'ordre des mises à jour dans l'image. D'où ces enveloppes,
    posées juste après chaque poseur, où l'ordre est acquis.
]]

require "LPBCS_Core"
require "LPBCS_Sprites"

--- Retire nos sprites du contour de sélection de cet objet.
---
--- Muet sur tout ce que le mod n'a pas écrit : une caisse sans écriteau garde
--- le comportement du jeu de base, drapeau compris.
---
--- L'appel passe par LPBCS.invoke plutôt qu'en direct parce que
--- setOutlineHlAttached(int, boolean) est une méthode Java comme une autre :
--- si elle bouge d'un build à l'autre, le contour redevient faux mais le
--- fichier ne casse pas.
local function detach(obj, playerNum)
    if not obj or not LPBCS.Sprites.isPlaced(obj) then return end
    LPBCS.invoke(obj, "setOutlineHlAttached", playerNum, false)
end

if ISInventoryPage then

    -- La fenêtre de butin, ses deux chemins.
    --
    -- updateContainerHighlight allume le drapeau sur le conteneur affiché, et
    -- comme :update() l'appelle à chaque image, c'est aussi notre battement.
    -- On en profite pour nettoyer le conteneur survolé : il est allumé
    -- ailleurs (onMouseOverButton) et cette fonction-ci ne l'éteint jamais
    -- d'elle-même.
    local baseUpdateContainerHighlight = ISInventoryPage.updateContainerHighlight

    function ISInventoryPage:updateContainerHighlight()
        baseUpdateContainerHighlight(self)

        detach(self:getContainerParent(self.inventory), self.player)
        detach(self:getContainerParent(self.coloredInv), self.player)
        detach(self.mouseOverColoredContainer, self.player)
    end

    -- Le menu de démontage.
    --
    -- Son option.onHighlight allume le drapeau puis appelle ceci. C'est le
    -- seul point saisissable de ce chemin : le onHighlight lui-même est une
    -- fermeture anonyme, construite à l'ouverture du menu.
    local baseOnObjectHighlighted = ISInventoryPage.OnObjectHighlighted

    function ISInventoryPage.OnObjectHighlighted(playerNum, object, isHighlighted)
        baseOnObjectHighlighted(playerNum, object, isHighlighted)

        if isHighlighted then
            detach(object, playerNum)
        end
    end

else

    -- Ce fichier ne fait rien d'autre que d'envelopper ISInventoryPage. S'il
    -- n'est pas là, l'écriteau revient hanter le contour, et rien dans le jeu
    -- ne le dirait : le seul symptôme est un contour de travers, que personne
    -- ne rapprochera d'un fichier d'interface manquant.
    LPBCS.log("Outline", "ISInventoryPage introuvable -- l'écriteau restera "
        .. "dans le contour de sélection")

end
