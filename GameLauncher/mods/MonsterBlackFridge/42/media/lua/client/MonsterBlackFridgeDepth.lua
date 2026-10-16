require 'MonsterBlackFridge/Core'
local M=MonsterBlackFridge
local prepared={}

-- B42's cached renderer needs the same depth geometry for the body, glass and
-- stock. Texture-only overlays are created lazily, after initSprites(), so bind
-- them explicitly through the game's supported assignment manager as well.
function M.prepareDepth(name)
    if prepared[name] or not TileDepthTextureAssignmentManager then return end
    local sprite=getSprite(name)
    if not sprite then return end
    TileDepthTextureAssignmentManager.getInstance():assignDepthTextureToSprite('MonsterBlackFridge',name)
    prepared[name]=true
end

Events.OnGameStart.Add(function()
    prepared={}
    for i=0,3 do M.prepareDepth('MonsterBlackFridge_01_'..i) end
    for i=0,1 do M.prepareDepth('MonsterBlackFridge_01_on_'..i) end
    for _,direction in ipairs({22,23}) do
        for level=0,5 do
            M.prepareDepth('MonsterBlackFridge_'..direction..'_stock_'..level)
            M.prepareDepth('MonsterBlackFridge_'..direction..'_light_'..level)
        end
    end
end)
