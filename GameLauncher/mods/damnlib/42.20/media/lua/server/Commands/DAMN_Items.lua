--[[
    This file is part of that DAMN Library (Workshop ID 3171167894) authored by KI5 / bikinihorst.
    No permission is given for redistribution, repacking or modifying this or other files contained within the named
    workshop item, regardless of visibility or target community size, except if explicitly allowed by the author.
    TIS / Steam modding policy: https://projectzomboid.com/blog/modding-policy/
    This mod is "On Lockdown": https://theindiestone.com/forums/index.php?/topic/2530-mod-permissions/#findComment-36479
]]--

DAMN = DAMN or {};
DAMN.ServerHandlers = DAMN.ServerHandlers or {};

-- helpers

function DAMN:spawnAndSendItem(playerObj, config)
    if config["fullType"]
    then
        config["amount"] = config["amount"] or 1;
        config["source"] = config["source"] or "unknown source";
        config["modData"] = config["modData"] or {};

        DAMN:appendLineToFile("that_damn_item_spawn.log", string.format("[%s] [%s] %s x %s (%s)",
            tostring(Calendar.getInstance():getTime()),
            tostring(playerObj),
            tostring(config["amount"]),
            tostring(config["fullType"]),
            tostring(config["source"])
        ));

        local inventory = playerObj:getInventory();

        for i = 1, config["amount"]
        do
            local item = instanceItem(config["fullType"]);

            if item
            then
                local itemData = item:getModData();

                for k, v in pairs(config["modData"])
                do
                    itemData[k] = v;
                end

                if config["condition"] and item["setCondition"]
                then
                    item:setCondition(tonumber(config["condition"]));
                end

                if config["name"] and item["setName"]
                then
                    item:setName(tostring(config["name"]));
                end

                inventory:AddItem(item);
                sendAddItemToContainer(inventory, item);
            end
        end
    end
end

-- handlers

function DAMN.ServerHandlers.addItemsToPlayerInventory(playerObj, args)
    args["items"] = args["items"] or {};

    if args["items"]["itemId"]
    then
        DAMN:spawnAndSendItem(playerObj, {
            fullType = args["items"]["itemId"],
            amount = args["items"]["amount"],
            modData = args["items"]["modData"],
            source = args["source"],
            condition = args["items"]["condition"],
            name = args["items"]["name"],
        });
    elseif args["items"][1] and type(args["items"][1]) == "string"
    then
        for i, itemId in ipairs(args["items"])
        do
            DAMN:spawnAndSendItem(playerObj, {
                fullType = itemId,
                amount = 1,
                modData = args["modData"],
                source = args["source"],
                condition = args["condition"],
                name = args["name"],
            });
        end
    else
        for k, spawnDef in pairs(args["items"])
        do
            DAMN:spawnAndSendItem(playerObj, {
                fullType = spawnDef["itemId"],
                amount = spawnDef["amount"],
                modData = spawnDef["modData"],
                source = args["source"],
                condition = spawnDef["condition"],
                name = args["name"],
            });
        end
    end
end