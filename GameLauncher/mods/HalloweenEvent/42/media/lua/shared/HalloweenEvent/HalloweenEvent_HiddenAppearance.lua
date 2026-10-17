require "HalloweenEvent/HalloweenEvent_Shared"

-- Flat discovery fields keep hosted/dedicated command serialization identical.
-- This carries only clothing visuals; HAZ still owns sex, skin/hair seed and AI.
local Codec = {}
local MAX_ITEMS = 32

function Codec.encode(args, index, prepared)
    if type(prepared) ~= "table" or prepared.selected ~= true then return end
    local snapshot = prepared.snapshot
    local pieces = snapshot and type(snapshot.Items)=="table" and #snapshot.Items or 0
    if pieces > MAX_ITEMS then return end
    local prefix = "hweHidden" .. tostring(index)
    -- Count=0 is valid for native outfits: the client builds the preview from
    -- the registered native outfit, rather than receiving made-up ItemVisuals.
    args[prefix .. "Costume"] = prepared.costumeID
    args[prefix .. "Count"] = pieces
    args[prefix .. "Mode"] = prepared.visualMode or "replace"
    if pieces == 0 then return end
    for i, fullType in ipairs(snapshot.Items) do
        local key = prefix .. "Item" .. tostring(i)
        args[key] = fullType
        local appearance = snapshot.Appearance and snapshot.Appearance[i] or {}
        for _, field in ipairs({"Hue", "BaseTexture", "TextureChoice", "Decal"}) do
            args[key .. field] = appearance[field]
        end
        local tint = appearance.Tint
        if tint then
            args[key .. "R"], args[key .. "G"], args[key .. "B"] = tint[1], tint[2], tint[3]
        end
    end
end

function Codec.decode(args, index)
    local prefix = "hweHidden" .. tostring(index)
    local count = tonumber(args[prefix .. "Count"])
    local id = args[prefix .. "Costume"]
    if type(id) ~= "string" or not HalloweenEvent.getCostumeByID(id)
        or not count or count < 0 or count > MAX_ITEMS or count ~= math.floor(count) then return nil end
    local costume=HalloweenEvent.getCostumeByID(id)
    if count==0 then return {id=id, outfit=costume.outfit, nativeOnly=true} end
    local items, appearances = {}, {}
    for i = 1, count do
        local key = prefix .. "Item" .. tostring(i)
        if type(args[key]) ~= "string" or args[key] == "" then return nil end
        items[i] = args[key]
        local r, g, b = tonumber(args[key .. "R"]), tonumber(args[key .. "G"]), tonumber(args[key .. "B"])
        appearances[i] = {
            Tint = r and g and b and {r, g, b} or nil,
            Hue = tonumber(args[key .. "Hue"]),
            BaseTexture = tonumber(args[key .. "BaseTexture"]),
            TextureChoice = tonumber(args[key .. "TextureChoice"]),
            Decal = type(args[key .. "Decal"]) == "string" and args[key .. "Decal"] or nil,
        }
    end
    return {id=id, outfit=costume.outfit,
        visualMode=args[prefix .. "Mode"]=="append" and "append" or "replace",
        visualItems=items, visualAppearance=appearances}
end

return Codec
