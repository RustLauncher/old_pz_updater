require "ISUI/ISPanel"
require "HalloweenEvent/EVHalloween_ItemFunctions"
local Items,F=HalloweenEvent.Items,HalloweenEvent.Items.Functions
local FX={time=0,drawn={},warned=false}
Items.PotionEffects=FX
-- A drawing helper, never added to the UI manager: no mouse capture, inventory
-- objects, world objects, network packets or saved particle state are created.
function FX.draw(painter,texture,playerNum,item,world,square,phase)
    if not square:isCanSee(playerNum) then return 0 end
    local zoom=getCore():getZoom(playerNum)
    local left,top=getPlayerScreenLeft(playerNum),getPlayerScreenTop(playerNum)
    local width,height=getPlayerScreenWidth(playerNum),getPlayerScreenHeight(playerNum)
    local ox,oy=IsoCamera.getOffX(playerNum),IsoCamera.getOffY(playerNum)
    local x,y,z=square:getX()+world:getOffX(),square:getY()+world:getOffY(),square:getZ()+world:getOffZ()
    local drawn=0
    for j=0,4 do
        local t=(phase+j*.197)%1
        -- World-height units match the item placement cursor; rise, grow then
        -- fade and pop above the liquid. Independent phases avoid a single blob.
        local px=x+math.sin(j*2.3)*.043+math.sin(t*5+j)*.008
        local py=y+math.cos(j*2.3)*.043
        local pz=z+.127+t*.055
        local sx=(IsoUtils.XToScreen(px,py,pz,0)-ox)/zoom+left
        local sy=(IsoUtils.YToScreen(px,py,pz,0)-oy)/zoom+top
        local size=(5+4*math.sin(t*math.pi))/zoom
        local alpha=.65*math.sin(t*math.pi)
        if sx-size>=left and sx+size<left+width and sy-size>=top and sy+size<top+height then
            painter:drawTextureScaled(texture,sx-size/2,sy-size/2,size,size,alpha,1,1,1);drawn=drawn+1
        end
    end
    return drawn
end
function FX.render()
    local V=Items.Visuals;if not V or not getSpecificPlayer(0) then return end
    if not FX.texture then FX.texture=getTexture("media/textures/EVHalloween_PotionBubble.png") end
    if not FX.texture then return end
    if not FX.painter then
        FX.painter=ISPanel:new(0,0,getCore():getScreenWidth(),getCore():getScreenHeight())
        FX.painter:initialise();FX.painter:instantiate();FX.painter:noBackground()
    end
    -- UI pass uses screen pixels; explicit player camera offsets avoid the
    -- world render pass applying a second zoom/viewport transform.
    local playerNum=0
    for id in pairs(FX.drawn) do if not V.world[id] then FX.drawn[id]=nil end end
    for id,item in pairs(V.world) do
        if item:getFullType()==F.potionType then
            local world=item:getWorldItem();local square=world and world:getSquare()
            if square then
                local count=FX.draw(FX.painter,FX.texture,playerNum,item,world,square,(FX.time+id%23*.071)%1)
                if count>0 and not FX.drawn[id] then
                    FX.drawn[id]=true
                    HalloweenEvent.log("ITEMS POTION_FX_DRAW id="..tostring(id).." particles="..count.." renderer=ui_world_projected_sprites")
                end
            else FX.drawn[id]=nil end
        end
    end
end
if Events.OnTick then Events.OnTick.Add(function()
    -- Real animation time rather than game-hour time; pause stops motion.
    local delta=getGameTime():getRealworldSecondsSinceLastUpdate()
    FX.time=(FX.time+math.min(.1,delta)*.55)%1
end) end
if Events.OnPreUIDraw then Events.OnPreUIDraw.Add(function()
    local ok,err=pcall(FX.render)
    if not ok and not FX.warned then FX.warned=true;HalloweenEvent.log("ITEMS POTION_FX_UNAVAILABLE reason="..tostring(err)) end
end) end
if Events.OnGameStart then Events.OnGameStart.Add(function()
    HalloweenEvent.log("ITEMS POTION_FX_READY renderer=ui_world_projected_sprites particlesPerProp=5 explicitCamera=true")
end) end
return FX
