require "HalloweenEvent/HalloweenEvent_Text"
-- EVHalloween Item Pack 13: 25 rewards, plus the saved legacy coffin alias.
require "HalloweenEvent/HalloweenEvent_Shared"
local HWE = HalloweenEvent
HWE.Items = HWE.Items or {}
local Items = HWE.Items
Items.VERSION = "items-13"
Items.coffinType = "HalloweenEvent.Mov_EVHalloweenCoffin"
Items.legacyCoffinType = "HalloweenEvent.EVHalloween_Decor_CoffinProp"
Items.typeAliases = {[Items.legacyCoffinType]=Items.coffinType}
-- Visual sizing revised from the supplied Items3 screenshots.
Items.MODEL_SCALE = 0.005
Items.lanternType = "HalloweenEvent.EVHalloween_Decor_HangingLantern"
Items.bucketVariants = {{name="Original",index=0},{name="Orange",index=1},{name="Charcoal",index=2},{name="Mint",index=3}}
Items.doormatVariants = {{name="Happy Halloween", index=0}, {name="Trick or Treat", index=1}}
Items.catalog = {
    {fullType="HalloweenEvent.EVHalloween_PumpkinTreatPail", name="Cat Treat Pail", group="Functional", kind="base:container"},
    {fullType="HalloweenEvent.EVHalloween_PumpkinTreatBucket", name="Ghost Treat Bucket", group="Functional", kind="base:container"},
    {fullType="HalloweenEvent.EVHalloween_WitchCauldron", name="Witch Treat Cauldron", group="Functional", kind="base:container"},
    {fullType="HalloweenEvent.EVHalloween_Decor_PumpkinOrange", name="Sage Heirloom Halloween Pumpkin", group="Decorations", kind="base:normal"},
    {fullType="HalloweenEvent.EVHalloween_Decor_PumpkinWhite", name="White Halloween Pumpkin", group="Decorations", kind="base:normal"},
    {fullType="HalloweenEvent.EVHalloween_Decor_JackOLanternGrin", name="Grinning Jack-o-Lantern", group="Functional", kind="base:normal"},
    {fullType="HalloweenEvent.EVHalloween_Decor_JackOLanternCat", name="Cat Jack-o-Lantern", group="Functional", kind="base:normal"},
    {fullType="HalloweenEvent.EVHalloween_Decor_GhostYardFigure", name="Little Ghost Yard Figure", group="Decorations", kind="base:normal"},
    {fullType="HalloweenEvent.EVHalloween_Decor_TombstonePlain", name="Cross Tombstone Prop", group="Decorations", kind="base:normal"},
    {fullType="HalloweenEvent.EVHalloween_Decor_TombstoneRIP", name="R.I.P. Tombstone Prop", group="Decorations", kind="base:normal"},
    {fullType="HalloweenEvent.EVHalloween_Decor_TombstoneCracked", name="Halloween Doormat", group="Decorations", kind="base:normal"},
    {fullType="HalloweenEvent.EVHalloween_Decor_WoodenCross", name="Wooden Grave Cross", group="Decorations", kind="base:normal"},
    {fullType="HalloweenEvent.EVHalloween_Decor_BatBanner", name="Bat Yard Ornament", group="Decorations", kind="base:normal"},
    {fullType="HalloweenEvent.EVHalloween_Decor_SkullPile", name="Plastic Skull Pile", group="Decorations", kind="base:normal"},
    {fullType="HalloweenEvent.EVHalloween_Decor_BonePile", name="Halloween Ouija Board", group="Decorations", kind="base:normal"},
    {fullType="HalloweenEvent.EVHalloween_Decor_WitchesCauldron", name="Bubbling Cauldron Prop", group="Decorations", kind="base:normal"},
    {fullType="HalloweenEvent.EVHalloween_Decor_WitchBroom", name="Witch Broom", group="Functional", kind="base:weapon"},
    {fullType="HalloweenEvent.EVHalloween_Decor_WitchHatProp", name="Witch Cat Figurine", group="Decorations", kind="base:normal"},
    {fullType="HalloweenEvent.EVHalloween_Decor_HangingLantern", name="Halloween Battery Lantern", group="Functional", kind="base:drainable"},
    {fullType="HalloweenEvent.EVHalloween_Decor_CandleCluster", name="Wax Candle Cluster", group="Decorations", kind="base:normal"},
    {fullType="HalloweenEvent.EVHalloween_Decor_HalloweenPennant", name="Halloween Pennant Stand", group="Decorations", kind="base:normal"},
    {fullType=Items.coffinType, name="Coffin Storage Chest", group="Functional", kind="base:moveable", modelShort="Decor_CoffinProp"},
    {fullType="HalloweenEvent.EVHalloween_Decor_HauntedMirror", name="Haunted Mirror Prop", group="Decorations", kind="base:normal"},
    {fullType="HalloweenEvent.EVHalloween_Decor_PumpkinSmash", name="Spiderweb Yard Stand", group="Decorations", kind="base:normal"},
    {fullType="HalloweenEvent.EVHalloween_Decor_HalloweenCandyBowl", name="Trick-or-Treat Candy Bowl", group="Functional", kind="base:container"},
}
Items.byType = {}
Items.treatContainers = {}
Items.rewards = {}
for _, entry in ipairs(Items.catalog) do
    local short = entry.modelShort or entry.fullType:gsub("^HalloweenEvent.EVHalloween_", "")
    entry.worldModel = "HalloweenEvent.EVHItems_" .. short .. "_Ground"
    entry.handModel = (entry.kind ~= "base:normal" or short=="Decor_JackOLanternGrin" or short=="Decor_JackOLanternCat") and ("HalloweenEvent.EVHItems_" .. short .. "_Hand") or nil
    entry.handMesh = entry.handModel and ("EVHalloween/EVHalloween_" .. short .. "_Held") or nil
    entry.modelScale = short == "PumpkinTreatBucket" and 0.0035
        or (short == "WitchCauldron" and 0.004 or Items.MODEL_SCALE)
    entry.role = "decoration"
    if entry.kind == "base:weapon" then entry.role = "weapon"
    elseif entry.kind == "base:drainable" then entry.role = "handheld_light"
    elseif entry.kind == "base:container" then entry.role = "placeable_storage_container" end
    if entry.kind=="base:moveable" then entry.role="furniture_storage" end
    if short=="Decor_JackOLanternGrin" or short=="Decor_JackOLanternCat" then entry.role="candle_light" end
    Items.byType[entry.fullType] = entry
    if entry.fullType == "HalloweenEvent.EVHalloween_PumpkinTreatPail"
        or entry.fullType == "HalloweenEvent.EVHalloween_PumpkinTreatBucket"
        or entry.fullType == "HalloweenEvent.EVHalloween_WitchCauldron" then
        entry.role = "handled_carry_container"
        Items.treatContainers[#Items.treatContainers + 1] = entry.fullType
    else
        Items.rewards[#Items.rewards + 1] = entry.fullType
    end
end
-- Existing bags keep their class and contents until the player converts an
-- empty one. Their meshes still resolve, but they are not another reward roll.
Items.byType[Items.legacyCoffinType] = Items.byType[Items.coffinType]

function EVHalloweenCreateCoffin(item)
    item:ReadFromWorldSprite("evh_coffins_01_0")
    item:setActualWeight(7.5)
    item:setWeight(7.5)
end

local function reportedScale(model)
    if not model then return nil end
    -- ModelScript.scale is public in B42. Keep audits usable if a runtime exposes
    -- methods but not fields; expectedScale is then logged alongside unavailable.
    local ok, value = pcall(function() return model.scale end)
    if ok and type(value) == "number" then return value end
    return nil
end

local function auditBucketReference(manager)
    for _, fullType in ipairs({"Base.HalloweenCandyBucket","Base.Lantern_Hurricane","Base.Broom_Twig"}) do
        local ok, err = pcall(function()
            local item = manager:getItem(fullType)
            if not item then HWE.log("ITEMS VANILLA_REFERENCE type="..fullType.." missing=true");return end
            for _, role in ipairs({"ground", "hand"}) do
                local name = role=="ground" and item:getWorldStaticModel() or item:getStaticModel()
                local model = name and manager:getModelScript(name)
                HWE.log("ITEMS VANILLA_REFERENCE type="..fullType.." role="..role
                    .." model="..tostring(name).." mesh="..tostring(model and model:getMeshName())
                    .." texture="..tostring(model and model:getTextureName()))
                if model then for i=0,model:getAttachmentCount()-1 do
                    local a=model:getAttachment(i)
                    HWE.log("ITEMS VANILLA_GRIP type="..fullType.." role="..role.." id="..tostring(a:getId())
                        .." offset="..tostring(a:getOffset()).." rotation="..tostring(a:getRotate()))
                end end
            end
        end)
        if not ok then HWE.log("ITEMS VANILLA_REFERENCE type="..fullType.." unavailable="..tostring(err)) end
    end
end

local function gripInfo(model)
    local ok, result = pcall(function()
        local a = model and model:getAttachmentById("hand")
        if not a then return "missing" end
        return tostring(a:getOffset()) .. " rotate=" .. tostring(a:getRotate())
    end)
    return ok and result or "unavailable"
end

function Items.audit()
    local side = isServer() and "server" or (isClient() and "client" or "singleplayer")
    HalloweenEvent.log("ITEMS AUDIT_BEGIN version=" .. Items.VERSION
        .. " side=" .. side .. " expected=" .. #Items.catalog)
    local manager = type(getScriptManager) == "function" and getScriptManager()
        or (ScriptManager and ScriptManager.instance)
    if not manager then
        HalloweenEvent.log("ITEMS AUDIT_UNAVAILABLE version=" .. Items.VERSION .. " manager=false")
        return false
    end
    auditBucketReference(manager)
    if Items.Functions and Items.Functions.auditFuelReferences then Items.Functions.auditFuelReferences(manager) end
    local failed = 0
    local registered, models, handModels, scaleMismatches, meshMismatches = 0, 0, 0, 0, 0
    for _, entry in ipairs(Items.catalog) do
        local script = manager:getItem(entry.fullType)
        local model = script and script:getWorldStaticModel()
        local resolved = model and manager:getModelScript(model)
        local hand = script and script:getStaticModel()
        local resolvedHand = hand and manager:getModelScript(hand)
        local handMesh = resolvedHand and resolvedHand:getMeshName()
        local meshMismatch = entry.handMesh and resolvedHand and handMesh ~= entry.handMesh
        local worldScale, handScale = reportedScale(resolved), reportedScale(resolvedHand)
        local scaleMismatch = (worldScale and math.abs(worldScale - entry.modelScale) > 0.000001)
            or (handScale and math.abs(handScale - entry.modelScale) > 0.000001)
        if script then registered = registered + 1 end
        if resolved then models = models + 1 end
        if resolvedHand then handModels = handModels + 1 end
        if scaleMismatch then scaleMismatches = scaleMismatches + 1 end
        if meshMismatch then meshMismatches = meshMismatches + 1 end
        if not script or not resolved or (entry.handModel and not resolvedHand) or scaleMismatch or meshMismatch then
            failed = failed + 1
        end
        HalloweenEvent.log("ITEMS AUDIT type=" .. entry.fullType
            .. " script=" .. tostring(script ~= nil) .. " worldModel=" .. tostring(model)
            .. " model=" .. tostring(resolved ~= nil)
            .. " mesh=" .. tostring(resolved and resolved:getMeshName())
            .. " texture=" .. tostring(resolved and resolved:getTextureName())
            .. " role=" .. entry.role .. " expectedScale=" .. tostring(entry.modelScale)
            .. " reportedWorldScale=" .. tostring(worldScale or "unavailable")
            .. " handModel=" .. tostring(hand) .. " handResolved=" .. tostring(resolvedHand ~= nil)
            .. " handMesh=" .. tostring(handMesh) .. " expectedHandMesh=" .. tostring(entry.handMesh)
            .. " handGrip=" .. gripInfo(resolvedHand)
            .. " reportedHandScale=" .. tostring(handScale or "unavailable")
            .. " visualSizeVerified=false gripBake=true holdingPoseNeedsGameCheck=" .. tostring(entry.handModel ~= nil))
    end
    HalloweenEvent.log("ITEMS AUDIT_RESULT defined=" .. #Items.catalog .. " failed=" .. failed
        .. " registered=" .. registered .. " models=" .. models .. " version=" .. Items.VERSION
        .. " handModels=" .. handModels .. " expectedHandModels=9 scaleMismatches=" .. scaleMismatches
        .. " meshMismatches=" .. meshMismatches .. " visualSizeVerified=false")
    if registered == 0 then
        HalloweenEvent.log("ITEMS REGISTRATION_FAILED check=42/media/scripts/HalloweenEvent_Items.txt"
            .. " action=replace_item_scripts_and_fully_restart_client_and_server")
    end
    return failed == 0
end

if Events and Events.OnGameStart then Events.OnGameStart.Add(Items.audit) end
if Events and Events.OnServerStarted then Events.OnServerStarted.Add(Items.audit) end
return Items
