require "Hotbar/ISHotbarAttachDefinition"
require "Hotbar/ISHotbar"

-- 1. YUVA VE OMUZ KAYIŞI KISAYOLLARINI ANINDA KAYDET (ÇIK-GIR YAPILDIĞINDA UNUTMAYI ENGELLEYEN BOOT SİSTEMİ)
local function setupTwoWeaponsOnBackHotbar()
    if not ISHotbarAttachDefinition then return end

    local hasBack2 = false
    for _, slot in ipairs(ISHotbarAttachDefinition) do
        if slot.type == "Back2" or slot.type == "Sling" then
            hasBack2 = true
            break
        end
    end

    if not hasBack2 then
        table.insert(ISHotbarAttachDefinition, {
            type = "Back2",
            name = "Back 2",
            animset = "back",
            attachments = {
                Rifle = "Back2",
                Shotgun = "Back2",
                BigWeapon = "Back2",
                HandWeapon = "Back2",
                Spear = "Back2",
                Sword = "Back2",
                Shovel = "Back2",
                BigBlade = "Back2",
                Guitar = "Back2",
                GuitarAcoustic = "Back2",
                Racket = "Back2",
            },
        })
    end

    if ISHotbarAttachDefinition.replacements then
        local hasSlingRep = false
        for _, rep in ipairs(ISHotbarAttachDefinition.replacements) do
            if rep.type == "SheetRopeSling" then
                hasSlingRep = true
                break
            end
        end

        if not hasSlingRep then
            table.insert(ISHotbarAttachDefinition.replacements, {
                type = "SheetRopeSling",
                slot = "Back2",
            })
            table.insert(ISHotbarAttachDefinition.replacements, {
                type = "LeatherSling",
                slot = "Back2",
            })
            table.insert(ISHotbarAttachDefinition.replacements, {
                type = "Bag",
                name = "Back 2",
                animset = "back",
                replacement = {
                    Rifle = "Back2WithBag",
                    Shotgun = "Back2WithBag",
                    BigWeapon = "Back2WithBag",
                    HandWeapon = "Back2WithBag",
                    Spear = "Back2WithBag",
                    Sword = "Back2WithBag",
                    Shovel = "Back2WithBag",
                    BigBlade = "Back2WithBag",
                    Guitar = "Back2WithBag",
                    GuitarAcoustic = "Back2WithBag",
                    Racket = "Back2WithBag",
                }
            })
        end
    end
end

-- Dosya yüklendiği saniye ve tüm boot evrelerinde çalışarak çık-gir yapınca kaybolma bugını sıfırlıyor
setupTwoWeaponsOnBackHotbar()
Events.OnGameBoot.Add(setupTwoWeaponsOnBackHotbar)
Events.OnCreatePlayer.Add(setupTwoWeaponsOnBackHotbar)
Events.OnGameStart.Add(setupTwoWeaponsOnBackHotbar)


-- 2. ÇANTA TAKILINCA VEYA ÇIKARILINCA SOLA KAYMA SISTEMI (B42 ISHOTBAR GÜVENLİ HOOK YAMASI)
if ISHotbar then
    local original_ISHotbar_attachItem = ISHotbar.attachItem
    function ISHotbar:attachItem(item, slot, slotIndex, slotDef, doAnim)
        if slotDef and (slotDef.type == "Back2" or slotDef.type == "Sling" or slotDef.name == "Back 2") then
            local hasBag = false
            if self.replacements and (self.replacements["Rifle"] or self.replacements["BigWeapon"] or self.replacements["Shotgun"]) then
                hasBag = true
            end
            if not hasBag and self.chr and self.chr:getWornItems() then
                for i = 0, self.chr:getWornItems():size() - 1 do
                    local worn = self.chr:getWornItems():getItemByIndex(i)
                    if worn and worn:getAttachmentReplacement() == "Bag" then
                        hasBag = true
                        break
                    end
                end
            end

            if hasBag then
                -- Büyük sırt çantası var: Tam sola (-97 derece sol omuz kenarına) harika biçimde kaydır!
                slot = "Back2WithBag"
            else
                -- Çanta yok: Normal sırt X çapraz konumunda kal!
                slot = "Back2"
            end
        end

        return original_ISHotbar_attachItem(self, item, slot, slotIndex, slotDef, doAnim)
    end

    local original_ISHotbar_refresh = ISHotbar.refresh
    function ISHotbar:refresh(...)
        original_ISHotbar_refresh(self, ...)
        
        if not self.availableSlot or not self.chr then return end

        local hasBag = false
        if self.replacements and (self.replacements["Rifle"] or self.replacements["BigWeapon"] or self.replacements["Shotgun"]) then
            hasBag = true
        end
        if not hasBag and self.chr and self.chr:getWornItems() then
            for i = 0, self.chr:getWornItems():size() - 1 do
                local worn = self.chr:getWornItems():getItemByIndex(i)
                if worn and worn:getAttachmentReplacement() == "Bag" then
                    hasBag = true
                    break
                end
            end
        end

        for slotIndex, slot in pairs(self.availableSlot) do
            local slotDef = slot.def
            if slotDef and (slotDef.type == "Back2" or slotDef.type == "Sling" or slotDef.name == "Back 2") then
                local attachedItem = self.attachedItems[slotIndex]
                if attachedItem and not self.chr:isHandItem(attachedItem) then
                    local targetSlot = hasBag and "Back2WithBag" or "Back2"
                    if attachedItem:getAttachedToModel() ~= targetSlot then
                        self.chr:removeAttachedItem(attachedItem)
                        self.chr:setAttachedItem(targetSlot, attachedItem)
                        attachedItem:setAttachedToModel(targetSlot)
                    end
                end
            end
        end
    end
end

print("MOD: Two Weapons on Back Loaded Flawlessly and Safely!")
