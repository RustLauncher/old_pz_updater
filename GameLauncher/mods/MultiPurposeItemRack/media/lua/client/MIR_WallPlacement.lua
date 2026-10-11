if isServer() then return end

require "MIR_Core"

local MIR = MultiPurposeItemRack
local CursorClass = nil

local function ensureCursorClass()
    if CursorClass then return CursorClass end
    if not ISBuildingObject then return nil end

    local WallRackCursor = ISBuildingObject:derive("MIRWallRackCursor")

    function WallRackCursor:getSprite()
        return nil
    end

    function WallRackCursor:selectedSide(square)
        return MIR.wallSide(square, self.nSprite)
    end

    function WallRackCursor:isValid(square)
        if not square or not self.item or not self.item:getContainer() then return false end
        if not self:selectedSide(square) then return false end
        if not square:isCouldSee(self.player) then return false end
        local playerSquare = self.character and self.character:getSquare()
        return playerSquare and MIR.distanceSquared(playerSquare, square) <= 16
    end

    function WallRackCursor:render(x, y, z, square)
        local valid = self:isValid(square)
        local r, g, b = valid and 1.0 or 0.75, valid and 1.0 or 0.15,
            valid and 1.0 or 0.15
        self:getFloorCursorSprite():RenderGhostTileColor(x, y, z, r, g, b, 0.22)
    end

    function WallRackCursor:renderOpaqueObjectsInWorld(x, y, z, square)
        if not square or not self:isValid(square) then return end
        local side = self:selectedSide(square)
        local pose = MIR.wallPose(square, side)
        if not pose then return end
        local preview = self.previewItem or self.item
        if preview and preview.setWorldStaticModel then
            preview:setWorldStaticModel(MIR.rackModel)
        end
        if preview and preview.setStaticModel then
            preview:setStaticModel(MIR.rackModel)
        end
        Render3DItem(preview, square, pose.x, pose.y, pose.z,
            ({ north = 0, west = 90, south = 180, east = 270 })[side] or 0)
    end

    function WallRackCursor:create(x, y, z, north, sprite)
        local square = getCell():getGridSquare(x, y, z)
        local side = self:selectedSide(square)
        if not side then return end
        local args = {
            x = x, y = y, z = z, side = side,
            rackItemId = MIR.itemId(self.item),
        }
        if isClient() then
            sendClientCommand(self.character, MIR.module, "install", args)
        elseif MIR.Server and MIR.Server.handle then
            MIR.Server.handle("install", self.character, args)
            if MIR.cacheSinglePlayerRackSquare then
                MIR.cacheSinglePlayerRackSquare(square)
            end
        end
    end

    function WallRackCursor:walkTo(x, y, z)
        return true
    end

    function WallRackCursor:new(character, item)
        local o = {}
        setmetatable(o, self)
        self.__index = self
        o:init()
        o.character = character
        o.chr = character
        o.player = character:getPlayerNum()
        o.item = item
        o.previewItem = instanceItem(MIR.boardRenderItemType)
        o.nSprite = 2
        o.skipBuildAction = true
        o.dragNilAfterPlace = true
        o.noNeedHammer = true
        o.isWallLike = true
        return o
    end

    CursorClass = WallRackCursor
    MIRWallRackCursor = WallRackCursor
    return CursorClass
end

function MIR.createWallRackCursor(character, item)
    local class = ensureCursorClass()
    return class and class:new(character, item) or nil
end

Events.OnGameStart.Add(ensureCursorClass)

return MIR
