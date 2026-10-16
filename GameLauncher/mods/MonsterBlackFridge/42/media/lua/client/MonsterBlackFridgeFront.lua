require 'MonsterBlackFridge/Core'
local M=MonsterBlackFridge
M.front=M.front or {}
local F=M.front
local fronts={MonsterBlackFridge_01_0=true,MonsterBlackFridge_01_1=true}

-- B42's animated-light pass draws _on_ glass AND redraws the ordinary stock
-- overlay. A zero-scale blocker alone still schedules that second pass. Our
-- independent sprites already have complete powered/unpowered stock fronts;
-- disable only THEIR automatic pass, never the vanilla or other mods' sprites.
function F.prepare(sprite)
    if sprite and fronts[sprite:getName()] then
        sprite:getProperties():unset(IsoFlagType.HasLightOnSprite)
    end
end

function F.refresh(object)
    F.prepare(object:getSprite())
    local existing=object:getOnOverlay()
    -- Nick owns hidden instances while unplugged. Leave its marker untouched.
    if existing and existing:getScaleX()==0 then return end
    if existing then object:clearOnOverlay() end
end

Events.OnGameStart.Add(function()
    for name in pairs(fronts) do F.prepare(getSprite(name)) end
end)
