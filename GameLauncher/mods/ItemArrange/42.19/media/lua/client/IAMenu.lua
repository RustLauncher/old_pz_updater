local function arrangeItems(player, square)
    IA.ArrangeItems(square)
end

local function onPreFillWorldObjectContextMenu(playerId, context, worldobjects, test)
    local fetch = ISWorldObjectContextMenu.fetchVars
    local square = fetch.clickedSquare
    if not square then return end

    local player = getSpecificPlayer(playerId)

    -- local optionArrange = context:addOption("Arrange", player, arrangeItems, square)
end

Events.OnPreFillWorldObjectContextMenu.Add(onPreFillWorldObjectContextMenu)
