require "NPCs/AttachedLocations"

local function initTwoWeaponsOnBackLocations()
    local humanLocations = AttachedLocations.getGroup("Human")
    if humanLocations then
        -- ÇANTASIZ DURUM (Sol Çapraz Asma - Sling Modu'nun 4 numaralı ve X'li attachment'ları)
        humanLocations:getOrCreateLocation("Back2"):setAttachmentName("rifle_sling4")
        humanLocations:getOrCreateLocation("Sling"):setAttachmentName("rifle_sling4")
        
        humanLocations:getOrCreateLocation("Back2_Rifle"):setAttachmentName("rifle_sling4")
        humanLocations:getOrCreateLocation("Back2_Shotgun"):setAttachmentName("rifle_sling4")
        humanLocations:getOrCreateLocation("Back2_Spear"):setAttachmentName("rifle_sling4")
        humanLocations:getOrCreateLocation("Back2_Sword"):setAttachmentName("rifle_sling4")
        
        humanLocations:getOrCreateLocation("Back2_BigWeapon"):setAttachmentName("rifle_axeX")
        humanLocations:getOrCreateLocation("Back2_Shovel"):setAttachmentName("rifle_axeX")
        
        humanLocations:getOrCreateLocation("Back2_BigBlade"):setAttachmentName("rifle_katana")

        -- BÜYÜK ÇANTALI DURUM (Sol Dik Asma - Sling Modu'nun 2 numaralı attachment'ları)
        humanLocations:getOrCreateLocation("Back2WithBag"):setAttachmentName("rifle_sling2")
        humanLocations:getOrCreateLocation("SlingWithBag"):setAttachmentName("rifle_sling2")
        
        humanLocations:getOrCreateLocation("Back2WithBag_Rifle"):setAttachmentName("rifle_sling2")
        humanLocations:getOrCreateLocation("Back2WithBag_Shotgun"):setAttachmentName("rifle_sling2")
        humanLocations:getOrCreateLocation("Back2WithBag_Spear"):setAttachmentName("rifle_sling2")
        humanLocations:getOrCreateLocation("Back2WithBag_Sword"):setAttachmentName("rifle_sling2")
        
        humanLocations:getOrCreateLocation("Back2WithBag_BigWeapon"):setAttachmentName("rifle_axe")
        humanLocations:getOrCreateLocation("Back2WithBag_Shovel"):setAttachmentName("rifle_axe")
        
        humanLocations:getOrCreateLocation("Back2WithBag_BigBlade"):setAttachmentName("rifle_katana2")
    end
end

Events.OnLoadedTileDefinitions.Add(initTwoWeaponsOnBackLocations)
if AttachedLocations then
    initTwoWeaponsOnBackLocations()
end

print("MOD: Two Weapons on Back Locations initialized successfully!")
