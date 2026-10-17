local Codec = require "HalloweenEvent/HalloweenEvent_HiddenAppearance"
local HWE = HalloweenEvent

local function install()
    if not HideAnywhereZombies or not HidingMod then return end
    require "DHCS/DiscoveryPanel"
    local Panel = DHCSDiscoveryPanel
    if not Panel or Panel._hweHiddenCompatInstalled or type(Panel.updateModel) ~= "function" then return end
    Panel._hweHiddenCompatInstalled = true
    local update = Panel.updateModel
    Panel.updateModel = function(self, ...)
        local result = update(self, ...)
        if not self.args or self.args.occupantType ~= "zombie" or not self.paperDollZombies then return result end
        self._hweHiddenApplied = self._hweHiddenApplied or {}
        for index, preview in ipairs(self.paperDollZombies) do
            if self._hweHiddenApplied[index] ~= preview then
                -- One attempt per off-world actor prevents repeated dressing,
                -- model rebuilding or error retries during UI rendering.
                self._hweHiddenApplied[index] = preview
                local recipe = Codec.decode(self.args, index)
                if recipe then
                    local costume=HWE.getCostumeByID(recipe.id)
                    local ok,err=false,nil
                    -- Native outfits need the same named-outfit dressing used
                    -- for live zombies. Extra visualItems are applied on top.
                    if costume and (recipe.nativeOnly or recipe.visualMode=="append") then
                        local visuals=HWE.safeCall(preview,"getItemVisuals")
                        local human=HWE.safeCall(preview,"getHumanVisual")
                        local nativeOK = HWE.tryCall(human,"dressInNamedOutfit",costume.outfit,visuals)
                        if not nativeOK then nativeOK=HWE.tryCall(preview,"dressInNamedOutfit",costume.outfit) end
                        ok = nativeOK and (tonumber(HWE.safeCall(visuals,"size")) or 0)>0
                        if not ok then err="native outfit preview unavailable" end
                    end
                    if recipe.visualItems and #recipe.visualItems>0 then
                        if recipe.visualMode~="append" or ok then
                            local called, applied, reason=pcall(HWE.applyCostumeVisuals,preview,recipe,"client_hidden_preview")
                            if not called then ok,err=false,applied else ok,err=applied,reason end
                        end
                    end
                    if ok then
                        HWE.tryCall(preview, "onWornItemsChanged")
                        local model = (self.models or {self.model})[index]
                        if model then
                            HWE.tryCall(model, "setCharacter", preview)
                            HWE.tryCall(model, "setState", tostring(self.args.modelState or "idle"))
                            if IsoDirections then HWE.tryCall(model, "setDirection", IsoDirections.S) end
                            if index == 1 and self.args.playSurprise == true then
                                HWE.tryCall(model, "reportEvent", "EventSurprised")
                            end
                        end
                    else HWE.log("HIDDEN_PREVIEW_APPLY_FAIL error=" .. tostring(err)) end
                end
            end
        end
        return result
    end
end

install()
if Events and Events.OnGameStart then Events.OnGameStart.Add(install) end
