--[[
    © 2026 Warlord-Fox3. Tous droits réservés / All Rights Reserved.

    Toute réutilisation, modification, redistribution ou inclusion dans un
    modpack sans autorisation écrite préalable est strictement interdite.

    Any reuse, modification, redistribution, or inclusion in a modpack
    without prior written permission is strictly prohibited.
]]

--[[
    LPBCS_InkBox -- la fenêtre d'écriture, avec le choix de l'encre.

    C'est l'ISTextBox du jeu, plus une ligne : une liste déroulante des encres
    que le joueur porte VRAIMENT, sous le champ du nom. Rien d'autre ne change.

    Pourquoi la dériver plutôt qu'en écrire une : ISTextBox ne transporte que
    param1..param4 jusqu'à son rappel, et LPBCS_Context les occupe déjà tous les
    quatre -- joueur, objet, conteneur, style. La couleur n'a donc AUCUNE place
    dans la signature, et se lit sur le modal lui-même : `button.parent`, très
    exactement comme le texte se lit déjà sur `button.parent.entry`. Ce contrat-là
    n'existe que parce que la boîte est une ISTextBox ; en écrire une autre
    obligerait à le réinventer à l'identique pour que le même gestionnaire tienne.

    Le jeu fait la même chose sur la même classe : ISTextBox:enableColorPicker
    rétrécit son propre champ pour poser un bouton à côté. On ne fouille pas dans
    des entrailles, on se sert de la place qu'elles laissent.

    LA GARDE AU NIVEAU FICHIER N'EST PAS DÉCORATIVE. check_menu.py bouchonne
    `ISTextBox = {}` avec un seul :new, et son require() charge ce fichier pour
    de vrai : un :derive appelé sur ce bouchon lèverait au chargement et
    emporterait tout le banc. C'est la forme que LPBCS_Inventory tient déjà pour
    la même raison, et l'estampille reste posée dans les deux cas -- « chargé
    mais inerte » doit se distinguer de « pas chargé du tout ».
]]

require "LPBCS_Core"
require "LPBCS_Text"
require "LPBCS_Ink"
require "ISUI/ISTextBox"
require "ISUI/ISComboBox"

if LPBCS and LPBCS.stamp then
    LPBCS.stamp("LPBCS_InkBox", LPBCS.PROTOCOL)
end

if ISTextBox and type(ISTextBox.derive) == "function"
    and ISComboBox and type(ISComboBox.new) == "function" then

ISLPBCSInkBox = ISTextBox:derive("ISLPBCSInkBox")

-- Les mêmes valeurs que le haut d'ISTextBox.lua, et pour la même raison :
-- reprendre ses espacements plutôt que d'en inventer d'autres, sinon la ligne
-- ajoutée se verrait comme une pièce rapportée.
--
-- À L'INTÉRIEUR DE LA GARDE, délibérément : getTextManager() n'existe pas hors
-- du jeu, et ces trois lignes à la portée du fichier feraient exactement ce que
-- la garde est là pour empêcher.
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local UI_BORDER_SPACING = 10
local COMBO_HGT = FONT_HGT_SMALL + 6

--- Les encres à proposer, et celle qui est déjà en vigueur. À appeler AVANT
--- initialise(), qui est le moment où la ligne se construit ou ne se construit
--- pas.
function ISLPBCSInkBox:setInkChoices(choices, current)
    self.inkChoices = choices
    self.inkCurrent = current
end

--- L'id de l'encre choisie, ou nil s'il n'y a pas de liste.
---
--- Passe par getOptionData(getSelected()) et JAMAIS par getSelectedData() :
--- celui-ci indexe self.options sans garde et lève sur une liste vide, où
--- `selected` vaut 0. Une fenêtre qui plante en validant est pire qu'une couleur
--- mal choisie.
function ISLPBCSInkBox:selectedInk()
    if not self.inkCombo then return nil end
    local id = LPBCS.attempt(function()
        return self.inkCombo:getOptionData(self.inkCombo:getSelected())
    end)
    if type(id) ~= "string" or id == "" then return nil end
    return id
end

function ISLPBCSInkBox:initialise()
    ISTextBox.initialise(self)

    -- Une seule encre n'est pas un choix, et aucune est le cas du joueur qui
    -- écrit les mains nues -- RequireWritingTool éteint. Dans les deux cas la
    -- boîte reste celle du jeu, au pixel près.
    local choices = self.inkChoices
    if type(choices) ~= "table" or #choices < 2 then return end

    local label = LPBCS.text("IGUI_LPBCS_InkLabel", "Written with")
    local labelWidth = getTextManager():MeasureStringX(UIFont.Small, label)

    local x = UI_BORDER_SPACING + 1 + labelWidth + UI_BORDER_SPACING
    local y = self.entry:getBottom() + UI_BORDER_SPACING

    self.inkLabel = label
    self.inkLabelX = UI_BORDER_SPACING + 1
    self.inkLabelY = y + (COMBO_HGT - FONT_HGT_SMALL) / 2

    local combo = ISComboBox:new(x, y, self:getWidth() - x - UI_BORDER_SPACING - 1,
        COMBO_HGT, self, nil)
    combo:initialise()
    combo:instantiate()
    self:addChild(combo)
    self.inkCombo = combo

    for _, choice in ipairs(choices) do
        combo:addOptionWithData(choice.label, choice.id)
    end

    -- La préférence en vigueur revient présélectionnée : c'est ce qui fait d'un
    -- choix une préférence plutôt qu'une question posée à chaque caisse. Si elle
    -- ne figure plus dans la liste -- le stylo a été posé depuis -- selectData ne
    -- fait rien et addOptionWithData a déjà laissé la première entrée choisie.
    if self.inkCurrent then
        LPBCS.attempt(function() combo:selectData(self.inkCurrent) end)
    end

    -- Tout ce qui était sous le champ descend d'une ligne, et la fenêtre grandit
    -- d'autant. La hauteur se recalcule par l'expression même d'ISTextBox plutôt
    -- que par un nombre de pixels : une version du jeu qui changerait ses
    -- métriques nous emmène avec elle.
    local shift = COMBO_HGT + UI_BORDER_SPACING
    self.yes:setY(self.yes:getY() + shift)
    self.no:setY(self.no:getY() + shift)
    self:setHeight(self.yes:getBottom() + UI_BORDER_SPACING + 1)
end

function ISLPBCSInkBox:prerender()
    ISTextBox.prerender(self)
    if self.inkLabel then
        self:drawText(self.inkLabel, self.inkLabelX, self.inkLabelY,
            1, 1, 1, 1, UIFont.Small)
    end
end

-- ---------------------------------------------------------------- manette

--- Trois lignes au lieu de deux.
---
--- ISTextBox n'en connaît que deux et les code en dur : joypadIndexY vaut 1 sur
--- le champ, 0 sur les boutons. La liste s'intercale entre les deux, donc les
--- trois crochets qui suivent remplacent ce va-et-vient par un compte.
---
--- Rien d'autre n'en dépend : sans manette, ces fonctions ne sont jamais
--- appelées, et un joueur à la manette qui aurait choisi une fois à la souris
--- continue d'écrire dans sa couleur -- parce que le choix est durable. C'est le
--- seul endroit du mod où la dégradation est aussi douce, et elle l'est
--- justement parce que ce n'est pas une question posée à chaque écriture.
function ISLPBCSInkBox:onGainJoypadFocus(joypadData)
    ISTextBox.onGainJoypadFocus(self, joypadData)
    if self.inkCombo then
        self:insertNewLineOfButtons(self.inkCombo)
        self.joypadIndexY = 2
    end
end

function ISLPBCSInkBox:setInkRow(row, joypadData)
    if not self.inkCombo then return end
    self.joypadIndexY = row
    self.entry:setJoypadFocused(row == 2, joypadData)
    LPBCS.attempt(function() self.inkCombo:setJoypadFocused(row == 1) end)
end

function ISLPBCSInkBox:onJoypadDirUp(joypadData)
    if not self.inkCombo then return ISTextBox.onJoypadDirUp(self, joypadData) end
    self:setInkRow(math.min(2, (self.joypadIndexY or 0) + 1), joypadData)
end

function ISLPBCSInkBox:onJoypadDirDown(joypadData)
    if not self.inkCombo then return ISTextBox.onJoypadDirDown(self, joypadData) end
    self:setInkRow(math.max(0, (self.joypadIndexY or 0) - 1), joypadData)
end

else

-- Sans ISTextBox ni ISComboBox -- un processus serveur, un banc, un build où
-- l'une des deux a bougé -- la classe n'existe pas, et LPBCS_Context s'en rend
-- compte en la lisant : il ouvre alors la boîte du jeu, sans liste. Le joueur
-- écrit comme avant, dans l'encre qu'on lui trouve. Dit ici parce qu'une absence
-- silencieuse ressemble trait pour trait à un fichier qui ne s'est pas chargé.
LPBCS.log("InkBox", "ISTextBox ou ISComboBox absente -- la fenetre d'ecriture "
    .. "restera celle du jeu, sans choix de couleur")

end

-- nil quand la garde n'est pas passee, et c'est la valeur que LPBCS_Context lit
-- pour decider d'ouvrir la boite du jeu a la place.
return ISLPBCSInkBox
