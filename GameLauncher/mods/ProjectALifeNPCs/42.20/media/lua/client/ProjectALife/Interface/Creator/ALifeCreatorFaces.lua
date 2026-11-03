require "ProjectALife/Interface/Creator/ALifeCreatorCore"

local Creator = ProjectALife.CreatorScreen

function Creator.buildFacesPage(window, formW)
    local px = Creator.px
    local faces = window.profilePages.faces
    Creator.addLabel(faces, px(12), 0, "FACES", Creator.palette.TEXT, UIFont.Medium)
    local facesCard = Creator.addSectionCard(faces, px(4), px(28), formW - px(8), px(158),
        "MODDED FACE OVERLAYS", "Optional compatibility layer")
    Creator.addLabel(facesCard, px(12), px(52),
        "Compatible overlays appear here only when their source mod is enabled.", Creator.palette.MUTED)
    window.faceCombo = Creator.addCombo(facesCard, 0, 0, 1, Creator.clothingChoices.Faces)
    window.faceCombo:setVisible(false)
    window.faceTile = Creator.addPickerTile(facesCard, px(12), px(78), facesCard.width - px(24), px(62),
        "FACE OVERLAY", window.faceCombo, function()
            window.selectedClothingSlot = "Faces"
            Creator.openItemPicker(window, "clothing", "Faces", window.faceCombo, "Face overlays")
        end, "Choose a compatible modded face overlay. This does not replace the vanilla face model.")
    Creator.setPickerTileClear(window.faceTile, function() return Creator.clearClothingSlot(window, "Faces") end)
end

return Creator
