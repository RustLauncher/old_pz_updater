require 'PepsiFridge/Core'
local M=PepsiFridge
local prepared={}

-- B42's cached renderer needs the same depth geometry for the body, glass and
-- stock. Texture-only overlays are created lazily, after initSprites(), so bind
-- them explicitly through the game's supported assignment manager as well.
function M.prepareDepth(name)
    if prepared[name] or not TileDepthTextureAssignmentManager then return end
    local sprite=getSprite(name)
    if not sprite then return end
    TileDepthTextureAssignmentManager.getInstance():assignDepthTextureToSprite('PepsiFridge',name)
    prepared[name]=true
end

Events.OnGameStart.Add(function()
    prepared={}
    for _,prefix in ipairs({'PepsiFridge_', 'PepsiFridgeWorn_'}) do
        for i=0,3 do M.prepareDepth(prefix..'01_'..i) end
        for _,direction in ipairs({40,41}) do
            for level=0,3 do
                M.prepareDepth(prefix..direction..'_stock_'..level)
                M.prepareDepth(prefix..direction..'_light_'..level)
            end
        end
    end
end)
