--[[
    Fletcher: Archery VHS tapes (Retail-VHS, spawning 2 like vanilla's instructional tapes, so they
    turn up among the store-bought tapes). Watching a line with the code ARC+N gives Archery XP.
    Vanilla's media codes live in a local table in RadioCom/ISRadioInteractions.lua, so a new code
    can't be added there: F.wrapMediaInteractions wraps the instance's checkPlayer and, for each line
    vanilla accepted (it marks the line known), applies our codes the way vanilla's doSkill does
    (50 XP per point, nothing past the sandbox LevelForMediaXPCutoff; through F.awardXp, see
    MultiplierConfig.Archery in sandbox-options.txt). Text: Recorded_Media.json.
    Translation keys are uuid5s (any unique RM_ key works); new lines need a new key.
]]
require "Fletcher/Skill"
require "RadioCom/ISRadioInteractions"
local F = Fletcher

RecMedia = RecMedia or {}

-- VHS: Bowhunting Basics with Ray Dunbar
RecMedia["dd73c9e6-d608-5be8-9289-0b2149b1ff4f"] = {
    itemDisplayName = "RM_ae4129f5-0c7a-55e1-b437-ec23d6167234",
    title = "RM_1ec9d11c-c010-59ac-b4e7-af16ee135dca",
    extra = "RM_2e23d41a-ed5c-5dd2-bedb-20e388002493",
    subtitle = nil,
    author = nil,
    spawning = 2,
    category = "Retail-VHS",
    lines = {
        { text = "RM_3e708c44-4b99-5e40-8e1c-c87561ae4f12", r = 0.85, g = 0.65, b = 0.25, codes = "BOR-1" },
        { text = "RM_c15199a8-2685-5b97-9439-fd475814dbf3", r = 0.85, g = 0.65, b = 0.25, codes = "BOR-1" },
        { text = "RM_a51fa50b-01c5-56dc-80d0-5e8d33ad2915", r = 0.85, g = 0.65, b = 0.25, codes = "ARC+1" },
        { text = "RM_128baba8-01c8-5311-8750-e3c4dd948cd6", r = 0.85, g = 0.65, b = 0.25, codes = "BOR-1" },
        { text = "RM_5de18836-5184-50e8-a61f-dbff975e7f9e", r = 0.85, g = 0.65, b = 0.25, codes = "ARC+1" },
        { text = "RM_303febd3-f89c-5c57-8929-8125c0fecc71", r = 0.85, g = 0.65, b = 0.25, codes = "BOR-1" },
        { text = "RM_d82f0d7e-40a5-53b4-a554-82665aad98ab", r = 0.85, g = 0.65, b = 0.25, codes = "ARC+1" },
        { text = "RM_da4db67f-7fbf-5053-b250-99640abd6130", r = 0.85, g = 0.65, b = 0.25, codes = "BOR-1" },
        { text = "RM_1d0037f8-562f-5470-9696-199c8210b0fa", r = 0.85, g = 0.65, b = 0.25, codes = "ARC+1" },
        { text = "RM_de32ae67-e268-5b0d-a541-caebcb4a8d71", r = 0.85, g = 0.65, b = 0.25, codes = "BOR-1" },
        { text = "RM_a06b47a4-1103-5a8c-b614-f690b43c63cf", r = 0.85, g = 0.65, b = 0.25, codes = "BOR-1" },
        { text = "RM_3af55764-e6d1-5d45-9b98-b80ab1249bb2", r = 0.85, g = 0.65, b = 0.25, codes = "BOR-1" },
        { text = "RM_17a5d2c7-165f-5247-bd79-01165f8600cf", r = 0.85, g = 0.65, b = 0.25, codes = "BOR-1" },
    },
}

-- VHS: Traditional Archery: Form and Release
RecMedia["14a800b2-6617-5515-9470-be2627b55b4f"] = {
    itemDisplayName = "RM_4f4178ad-6338-5819-985e-f30ec44cc5da",
    title = "RM_72fc59da-71f5-5d4e-be83-c57ee154d7c7",
    extra = "RM_d5668edd-5cdf-5076-af30-cebdd0d12fe1",
    subtitle = nil,
    author = nil,
    spawning = 2,
    category = "Retail-VHS",
    lines = {
        { text = "RM_c61e05ed-2ac8-5918-b515-245aeb2dfbb4", r = 0.40, g = 0.70, b = 0.90, codes = "BOR-1" },
        { text = "RM_1d8ac2dd-5c90-5ca1-8cdd-ee4166a23347", r = 0.40, g = 0.70, b = 0.90, codes = "ARC+1" },
        { text = "RM_79f4faeb-eda7-5ae2-824d-2936b370ab5d", r = 0.40, g = 0.70, b = 0.90, codes = "BOR-1" },
        { text = "RM_bded21b4-ddf5-5c06-af4e-68e6837156f5", r = 0.40, g = 0.70, b = 0.90, codes = "ARC+1" },
        { text = "RM_d2d894de-ae94-5144-b36e-1e5e4b2b414f", r = 0.40, g = 0.70, b = 0.90, codes = "BOR-1" },
        { text = "RM_bef77899-cb28-512f-9c21-03168b1c2553", r = 0.40, g = 0.70, b = 0.90, codes = "ARC+1" },
        { text = "RM_df71a872-fb3c-5ea8-9656-83d73006e343", r = 0.40, g = 0.70, b = 0.90, codes = "BOR-1" },
        { text = "RM_b23aa2c3-9ac9-5d9d-9105-5d6eac61abdb", r = 0.40, g = 0.70, b = 0.90, codes = "ARC+2" },
        { text = "RM_a60de3ac-b570-53d0-9a3a-f2e572fc2bd9", r = 0.40, g = 0.70, b = 0.90, codes = "BOR-1" },
        { text = "RM_a11e06de-fb3f-5efd-860a-fd4f9172c53e", r = 1.00, g = 1.00, b = 1.00, codes = "BOR-1" },
        { text = "RM_19839b9f-e800-5842-acad-2f7b1534e0a3", r = 0.40, g = 0.70, b = 0.90, codes = "BOR-1" },
        { text = "RM_0b36334f-37d0-52d9-abb4-fde08b45c591", r = 0.40, g = 0.70, b = 0.90, codes = "BOR-1" },
    },
}

-- VHS: The Silent Hunter: Advanced Bowhunting
RecMedia["dcb0267a-c9c9-53a7-9fa8-e5f642544338"] = {
    itemDisplayName = "RM_e0c9acbb-a64a-5720-bc6a-bbdcf74f46ac",
    title = "RM_b7a7ff08-45e8-5df3-a58b-30fde4ed1f77",
    extra = "RM_31a4e33d-e774-58e7-91c5-db5783b200e7",
    subtitle = nil,
    author = nil,
    spawning = 2,
    category = "Retail-VHS",
    lines = {
        { text = "RM_863fd89e-30b9-58a4-9770-fbf57eda7be9", r = 0.85, g = 0.65, b = 0.25, codes = "BOR-1" },
        { text = "RM_ecc4e436-7e07-5ef9-9667-376113535e13", r = 0.85, g = 0.65, b = 0.25, codes = "ARC+2" },
        { text = "RM_8fa4fc3a-2637-503c-beaa-3d634d49caa4", r = 0.85, g = 0.65, b = 0.25, codes = "BOR-1" },
        { text = "RM_af26cf52-a5c8-50c7-a8ad-c40ead958944", r = 0.85, g = 0.65, b = 0.25, codes = "ARC+1" },
        { text = "RM_2aa4042c-2c32-5c89-8855-1251eab6a5fb", r = 0.85, g = 0.65, b = 0.25, codes = "BOR-1" },
        { text = "RM_dc081a76-97db-514e-922e-004c3e83d055", r = 0.85, g = 0.65, b = 0.25, codes = "BOR-1" },
        { text = "RM_5d06a0dd-80dd-56b0-b46c-aabb23019bb1", r = 0.85, g = 0.65, b = 0.25, codes = "ARC+2" },
        { text = "RM_9be1e731-d2d9-50c7-9540-05eccc0d1174", r = 0.85, g = 0.65, b = 0.25, codes = "BOR-1" },
        { text = "RM_bdd42d3c-371b-52a2-8e03-027aff399a1e", r = 0.85, g = 0.65, b = 0.25, codes = "ARC+1" },
        { text = "RM_c1794482-d618-5a32-846a-48c54cd200ba", r = 0.85, g = 0.65, b = 0.25, codes = "BOR-1" },
        { text = "RM_04d026ab-634c-51ae-b0e0-68175887f2d6", r = 0.85, g = 0.65, b = 0.25, codes = "BOR-1" },
    },
}

F.MEDIA_TAPES = {"dd73c9e6-d608-5be8-9289-0b2149b1ff4f", "14a800b2-6617-5515-9470-be2627b55b4f", "dcb0267a-c9c9-53a7-9fa8-e5f642544338"}

--- Our media codes for one line a player just took in (vanilla accepted it): ARC+N = Archery XP.
function F.mediaCodes(player, codes)
    for c in string.gmatch(codes or "", "[^,]+") do
        local code, op, n = string.sub(c, 1, 3), string.sub(c, 4, 4), tonumber(string.sub(c, 5))
        if code == "ARC" and op == "+" and n and n > 0 then
            local perk = F.perk()
            local cutoff = SandboxVars and SandboxVars.LevelForMediaXPCutoff
            if not cutoff or player:getPerkLevel(perk) < cutoff then
                local before = player:getXp():getXP(perk)
                F.awardXp(player, 50 * n)
                local gained = player:getXp():getXP(perk) - before
                if gained ~= 0 and ISRadioInteractions then
                    ISRadioInteractions:getInstance().addHalo(getText("IGUI_perks_Archery"), gained, true)
                end
            end
        end
    end
end

function F.wrapMediaInteractions()
    local inst = ISRadioInteractions and ISRadioInteractions:getInstance()
    if not inst or inst.fl_wrapped then return end
    inst.fl_wrapped = true
    local checkPlayer = inst.checkPlayer
    inst.checkPlayer = function(player, guid, codes, x, y, z, line, source)
        local fresh = guid ~= nil and guid ~= "" and not player:isKnownMediaLine(guid)
        checkPlayer(player, guid, codes, x, y, z, line, source)
        if fresh and codes and string.find(codes, "ARC", 1, true) and player:isKnownMediaLine(guid) then
            F.mediaCodes(player, codes)
        end
    end
end

F.wrapMediaInteractions()
