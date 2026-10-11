ISMoodlesInLua = ISUIElement:derive("ISMoodlesInLua")

function ISMoodlesInLua:new()
    local o = ISUIElement:new(x, y, moodleSize, moodleSize)
    setmetatable(o, self)
    self.__index = self

    o.defaultMoodleSize = 48
    o.moodleSizes = {[1] = 32,[2] = 48,[3] = 64,[4] = 80,[5] = 96,[6] = 128}

    o.iconPaths = {
        ["Endurance"]     = "Status_DifficultyBreathing",
        ["Bleeding"]      = "Status_Bleeding",
        ["Angry"]         = "Mood_Angry",
        ["Stress"]        = "Mood_Stressed",
        ["Thirst"]        = "Status_Thirst",
        ["Panic"]         = "Mood_Panicked",
        ["Hungry"]        = "Status_Hunger",
        ["Injured"]       = "Status_InjuredMinor",
        ["Pain"]          = "Mood_Pained",
        ["Sick"]          = "Mood_Nauseous",
        ["Bored"]         = "Mood_Bored",
        ["Unhappy"]       = "Mood_Sad",
        ["Tired"]         = "Mood_Sleepy",
        ["HeavyLoad"]     = "Status_HeavyLoad",
        ["Drunk"]         = "Mood_Drunk",
        ["Wet"]           = "Status_Wet",
        ["HasACold"]      = "Mood_Ill",
        ["Dead"]          = "Mood_Dead",
        ["Zombie"]        = "Mood_Zombified",
        ["Windchill"]     = "Status_Windchill",
        ["CantSprint"]    = "Status_MovementRestricted",
        ["Uncomfortable"] = "Mood_Discomfort",
        ["NoxiousSmell"]  = "Mood_NoxiousSmell",
        ["FoodEaten"]     = "Status_Hunger",
        ["Hyperthermia"]  = "Status_TemperatureHot",
        ["Hypothermia"]   = "Status_TemperatureLow",
    }

    -- Set options to defaults
    o.defaultOptions = {
        moodleOffsetX = 0,
        moodleOffsetY = 0,
        iconOffsetX = 0,
        iconOffsetY = 0,
        moodleAlpha = 1.0,
        moodlesDistance = 10,
        tooltipPadding = 1,
        tooltipOffsetX = 5,
    }

    -- Instance options that will be applied
    o.options = {}

    -- Set initial state for options to defaults
    o:applyOptions()

    o.previousMoodleLevels = {}
    o.moodleAnimations = {}
    o.moodleOscillations =  {}
    o.moodleOscillationsSteps = {}

    o.OscilatorScalar = 15.6;
    o.OscilatorDecelerator = 0.16; -- 0.84 (in java is 0.96) = 0.16
    o.OscilatorRate = 0.8;
    o.OscilatorStep = 0;

    o.useCharacter = nil
    o.playerNum = 0

    if o.useCharacter and o.useCharacter.getPlayerNum then
        o.playerNum = o.useCharacter:getPlayerNum()
    end

    o.active = false

    o.borderTextureSets = {}
    o.iconTextureSets = {}
    o.textureCache = {}
    return o
end

function ISMoodlesInLua:start()
    self.active = true
end
function ISMoodlesInLua:stop()
    self.active = false
end

function ISMoodlesInLua:setCharacter(character)
    self.useCharacter = character
end

function ISMoodlesInLua:applyOptions(options)
    -- Apply options by overwriting defaults with custom values if they exist
    for key, defaultValue in pairs(self.defaultOptions) do
        self.options[key] = (options and options[key]) or defaultValue
    end
end

--[[REGISTER BORDERS]]--

function ISMoodlesInLua:registerBorderTextureSet(name, path, options)
    -- Error Handling: Ensure texture set contains name and path
    if not name or not path then
        error("MIL [registerBorderTextureSet]: ERROR - Texture set registration requires both a name and a path.")
        return
    end

    -- Error Handling: Prevent duplicate entries
    for _, set in ipairs(self.borderTextureSets) do
        if set.name == name then
            print("MIL [registerBorderTextureSet]: ERROR - Texture set '" .. name .. "' is already registered.")
            return
        end
    end

    -- Cache texture set name and path
    table.insert(self.borderTextureSets, { name = name, path = path, options = options or {} })

    -- Add to dropdown menu and options
    local MILModOptions = PZAPI.ModOptions:getOptions("MoodlesInLua")
    local BorderTextureDropdown = MILModOptions and MILModOptions:getOption("MoodleBorderSet")

    if BorderTextureDropdown then
        BorderTextureDropdown:addItem(name, false)
    else
        print("MIL [registerBorderTextureSet]: ERROR - Moodle Background dropdown menu has not been initialized.")
    end

    table.insert(BorderTextureOptions, name)
end

function ISMoodlesInLua:getBorderTexturePath(goodBadNeutralId, moodleLevel)
    local defaultPath = "media/ui/MIL/Default"

    -- Find the registered texture set
    for _, set in ipairs(self.borderTextureSets) do
        if set.name == self.currentMoodleBorderSet then
            defaultPath = set.path
            break
        end
    end

    return string.format("%s/%s_%d.png", defaultPath, goodBadNeutralId == 1 and "Good" or goodBadNeutralId == 2 and "Bad" or "Neutral", moodleLevel)
end

function ISMoodlesInLua:getBorderTextureOptions()
    for _, set in ipairs(self.borderTextureSets) do
        if set.name == self.currentMoodleBorderSet then
            return set.options  -- Return the options associated with the current texture set
        end
    end
end

function ISMoodlesInLua:updateMoodleBorderType(newBorderType)
    self.currentMoodleBorderSet = newBorderType
end

--[[END OF REGISTER BORDERS]]--



--[[REGISTER ICONS]]--

function ISMoodlesInLua:registerIconTextureSet(name, path)
    -- Error Handling: Ensure texture set contains name and path
    if not name or not path then
        error("MIL [registerIconTextureSet]: ERROR - Texture set registration requires both a name and a path.")
        return
    end

    -- Error Handling: Prevent duplicate entries
    for _, set in ipairs(self.iconTextureSets) do
        if set.name == name then
            print("MIL [registerIconTextureSet]: ERROR - Texture set '" .. name .. "' is already registered.")
            return
        end
    end

    -- Cache texture set name and path
    table.insert(self.iconTextureSets, { name = name, path = path })

    -- Add to dropdown menu and options
    local MILModOptions = PZAPI.ModOptions:getOptions("MoodlesInLua")
    local IconTextureDropdown = MILModOptions and MILModOptions:getOption("MoodleIconSet")

    if IconTextureDropdown then
        IconTextureDropdown:addItem(name, false)
    else
        print("MIL [registerIconTextureSet]: ERROR - Moodle Background dropdown menu has not been initialized.")
    end

    table.insert(IconTextureOptions, name)
end

function ISMoodlesInLua:getIconTexturePath(moodleType)
    local defaultPath = "media/ui/MIL/Default"
    local iconName = self.iconPaths[tostring(moodleType)]

    -- Find the registered texture set
    for _, set in ipairs(self.iconTextureSets) do
        if set.name == self.currentMoodleIconSet then
            defaultPath = set.path
            break
        end
    end

    local path = (self.currentMoodleIconSet == "Disabled") and "media/ui/Moodles/128" or defaultPath
    return string.format("%s/%s.png", path, iconName)
end

function ISMoodlesInLua:updateMoodleIconType(newIconType)
    self.currentMoodleIconSet = newIconType
end

--[[END OF REGISTER ICONS]]--



function ISMoodlesInLua:getTexture(path)
    -- Check if the texture is already cached
    if not self.textureCache[path] then
        print("Loading texture: " .. path)
        -- Attempt to load the texture
        local texture = getTexture(path)

        -- Error handling: Check if texture loading was successful
        if texture == nil then
            print("Error: Texture not found for path: " .. path)
            return nil -- Skip drawing if texture is not found
        end

        -- Cache the texture if it's loaded
        self.textureCache[path] = texture
    end

    return self.textureCache[path]
end

function ISMoodlesInLua:clearTextureCache()
    if self.textureCache then
        for path, _ in pairs(self.textureCache) do
            print("Releasing texture: " .. path)
        end
        self.textureCache = {} -- Clear all cached textures
    end
end

function ISMoodlesInLua:getMoodleSize()
    -- Get Preset
    local moodleSize = getCore():getOptionMoodleSize()

     -- Auto size
    if moodleSize == 7 then
        local fontEnum = UIFont.Small
        return getTextManager():getFontFromEnum(fontEnum):getLineHeight()*3
    end

    -- Preset size
    return self.moodleSizes[moodleSize] or self.defaultMoodleSize
end


function ISMoodlesInLua:drawMoodleTooltip(moodles, moodleId, moodleX, moodleY)
    local moodleSize = self:getMoodleSize()

    local title = moodles:getMoodleDisplayString(moodleId)
    local description = moodles:getMoodleDescriptionString(moodleId)

    local textPadding = 10
    local titleLength = getTextManager():MeasureStringX(UIFont.Small, title) + textPadding
    local descriptionLength = getTextManager():MeasureStringX(UIFont.Small, description) + textPadding
    local textLength = math.max(titleLength, descriptionLength)

    local titleHeight = getTextManager():MeasureStringY(UIFont.Small, title)
    local descriptionHeight = getTextManager():MeasureStringY(UIFont.Small, description)
    local rectHeight = titleHeight + descriptionHeight + self.options.tooltipPadding * 4
    --local anchorTooltipOnMoodle =
    local anchorTooltipOnMoodle = math.floor((moodleSize - rectHeight) / 2)
    -- Draw Tooltip Rectangle
    self:drawRect(moodleX - textLength - textPadding - self.options.tooltipOffsetX, moodleY + anchorTooltipOnMoodle, textLength + textPadding, rectHeight, 0.6, 0, 0, 0)
    -- Draw Tooltip Text & Description (not necessary when using moodlesUI:setVisible() state)
    self:drawTextRight(title, moodleX - textPadding - self.options.tooltipOffsetX, moodleY + self.options.tooltipPadding + anchorTooltipOnMoodle, 1, 1, 1, 1)
    self:drawTextRight(description, moodleX - textPadding - self.options.tooltipOffsetX, moodleY + titleHeight + self.options.tooltipPadding * 2 + anchorTooltipOnMoodle, 1, 1, 1, 0.7)
end

function ISMoodlesInLua:render()

    local moodlesUI = MoodlesUI.getInstance()

    --Ensures ISMoodlesInLua and MoodlesUI are active
    if not self.active or not moodlesUI then return end

    --Disables vanilla moodle system
    moodlesUI:setDefaultDraw(false)

    local player = self.useCharacter

    if player and player:getMoodles() then
        local moodles = player:getMoodles()

        local moodleSize = self:getMoodleSize()
        local x = getPlayerScreenLeft(self.playerNum) + getPlayerScreenWidth(self.playerNum) - 10 - moodleSize
        local y = getPlayerScreenTop(self.playerNum) + 120

        -- Add offsets
        x = x + self.options.moodleOffsetX
        y = y + self.options.moodleOffsetY

        for moodleId = 0, moodles:getNumMoodles() - 1 do
            local moodleType = MoodleType.FromIndex(moodleId)
            local moodleLevel = moodles:getMoodleLevel(moodleType)
            local goodBadNeutralId = moodles:getGoodBadNeutral(moodleId)

            local prevLevel = self.previousMoodleLevels[tostring(moodleType)] or 0
            self.previousMoodleLevels[tostring(moodleType)] = moodleLevel

            local baseY = y -- Save the starting Y for this moodle
            local animY = baseY -- Default to base Y if no animation

            if moodleLevel > 0 then

                -- Get frame time to use in animations
                local deltaTime = UIManager.getMillisSinceLastUpdate() / 1000 -- Convert ms to seconds

                -- Detect when to apply oscillations
                if moodleLevel ~= prevLevel and moodleLevel >= 1 then
                    self.moodleOscillations[tostring(moodleType)] = 1
                end

                local oscillationOffset = 0

                local oscillationDeltaTime = deltaTime * 33.3333
                if not oscillationDeltaTime or oscillationDeltaTime <= 0 then
                    oscillationDeltaTime = 1  -- to prevent issues with very low frame rates
                end

                local moodleOscillation = self.moodleOscillations[tostring(moodleType)] or 0

                if moodleOscillation > 0 then
                    -- Decay the oscillation
                    self.moodleOscillations[tostring(moodleType)] = moodleOscillation - moodleOscillation * (self.OscilatorDecelerator) / oscillationDeltaTime

                    -- Saturate the oscillation
                    if self.moodleOscillations[tostring(moodleType)] <= 0.015 then
                        self.moodleOscillations[tostring(moodleType)] = 0
                    end

                    if self.moodleOscillations[tostring(moodleType)] > 0 then
                        -- Each moodleType gets its own OscilatorStep
                        local OscilatorStep = self.moodleOscillationsSteps[tostring(moodleType)] or 0

                        -- Update the OscilatorStep and store it for the specific moodleType
                        OscilatorStep = OscilatorStep + self.OscilatorRate / oscillationDeltaTime
                        self.moodleOscillationsSteps[tostring(moodleType)] = OscilatorStep

                        -- Apply the oscillation offset
                        local Oscilator = math.sin(OscilatorStep)
                        oscillationOffset = Oscilator * self.OscilatorScalar * self.moodleOscillations[tostring(moodleType)] * 2
                    else
                        oscillationOffset = 0
                    end
                end



                -- Detect when apply start animation
                if prevLevel == 0 and moodleLevel == 1 then
                    self.moodleAnimations[tostring(moodleType)] = {
                        progress = 0,
                        startY = baseY,
                        targetY = 10000
                    }
                end

                -- Handle Start animation
                local anim = self.moodleAnimations[tostring(moodleType)]
                if anim then
                    -- Update and clamp progress using time since last frame
                    anim.progress = math.min(anim.progress + (deltaTime * 0.5), 1)

                    -- Smooth cubic ease-out interpolation
                    local t = 1 - math.pow(1 - anim.progress, 3)
                    local animY = anim.targetY + (anim.startY - anim.targetY) * t

                    -- Auto-remove and reset animation
                    if anim.progress >= 1 then
                        self.moodleAnimations[tostring(moodleType)] = nil
                        animY = baseY
                    end

                    -- Apply animation to y position
                    y = animY
                end

                -- Moodles / borders logic
                local borderTexturePath = self:getBorderTexturePath(goodBadNeutralId, moodleLevel)
                local borderTexture = self:getTexture(borderTexturePath)

                local iconTexturePath = self:getIconTexturePath(moodleType)
                local iconTexture = self:getTexture(iconTexturePath)

                -- Get the original dimensions of the Border texture
                local realBorderWidth = borderTexture:getWidth()
                local realBorderHeight = borderTexture:getHeight()

                local scaleFactor = moodleSize / 128 -- FIXME may need to rely on user defined parameters but textures in the game are 128x128, so it's better to use 128 as a default

                -- Calculate the scaled dimensions
                local scaledBorderWidth = realBorderWidth * scaleFactor
                local scaledBorderHeight = realBorderHeight * scaleFactor

                -- Calculate distance with scaling
                local iconOffsetX = math.floor(self.options.iconOffsetX * scaleFactor)
                local iconOffsetY = math.floor(self.options.iconOffsetY * scaleFactor)

                if borderTexture then -- TODO add later support for custom color background
                    UIManager.DrawTexture(borderTexture, x + oscillationOffset, y, scaledBorderWidth, scaledBorderHeight, self.options.moodleAlpha) -- border
                    UIManager.DrawTexture(iconTexture, x + iconOffsetX + oscillationOffset, y + iconOffsetY, moodleSize, moodleSize, self.options.moodleAlpha) -- moodle icon
                end

                -- Draw moodle tooltip on mouse hover
                local mouseX, mouseY = getMouseX(), getMouseY()
                if mouseX >= x and mouseX <= x + moodleSize and mouseY >= y and mouseY <= y + moodleSize then
                    self:drawMoodleTooltip(moodles, moodleId, x, y)
                end

                -- Increment position for the next moodle
                y = baseY + self.options.moodlesDistance + moodleSize
            end
        end
    end
end




--[[HANDLER]]--

ISMoodlesInLuaHandle = ISMoodlesInLua:new()

-- Initialize the framework and add it to the UIManager
local function initializeMIL()
    ISMoodlesInLuaHandle:initialise()
    ISMoodlesInLuaHandle:addToUIManager()
    ISMoodlesInLuaHandle:start()
end
Events.OnGameStart.Add(initializeMIL)

-- Update player character
local function updateCharacter(id,player)
    ISMoodlesInLuaHandle:setCharacter(player)
end
Events.OnCreatePlayer.Add(updateCharacter)




--[[MOD OPTIONS]]--

local MILOptions = PZAPI.ModOptions:create("MoodlesInLua", getText("Moodles In Lua"))

local borderKey = "MoodleBorderSet"
local borderName = getText("Border texture pack:")

local iconKey = "MoodleIconSet"
local iconName = getText("Moodle texture pack:")

BorderTextureOptions = {
    [1] = "Default",
}

IconTextureOptions = {
    [1] = "Disabled",
    [2] = "Default",
}

MILOptions:addDescription("Select custom textures for moodles")

local MoodleBorderSetDropdown = MILOptions:addComboBox(borderKey, borderName, "tooltip")
MoodleBorderSetDropdown:addItem("Default", true)

local MoodleIconSetDropdown = MILOptions:addComboBox(iconKey, iconName, "tooltip")
MoodleIconSetDropdown:addItem("Disabled", false)
MoodleIconSetDropdown:addItem("Default", true)

MILOptions:addDescription("If new packs do not appear in the list, check if they are listed under the Moodles In Lua mod in Mod Order menu")

function MILOptions:apply()
    -- Release textures from the previous texture set
    if ISMoodlesInLuaHandle.currentMoodleBorderSet or ISMoodlesInLuaHandle.currentMoodleIconSet then
        ISMoodlesInLuaHandle:clearTextureCache()
    end

    -- Update to the new border set
    local selectedBorderIndex = self:getOption("MoodleBorderSet"):getValue()
    local newBorderType = BorderTextureOptions[selectedBorderIndex]
    ISMoodlesInLuaHandle:updateMoodleBorderType(newBorderType)

    -- Retrieve options for the current texture set
    local options = ISMoodlesInLuaHandle:getBorderTextureOptions()

    -- Update to the new icon set
    local selectedIconIndex = self:getOption("MoodleIconSet"):getValue()
    local newIconType = IconTextureOptions[selectedIconIndex]
    ISMoodlesInLuaHandle:updateMoodleIconType(newIconType)

    -- Update options
    ISMoodlesInLuaHandle:applyOptions(options)

    -- Update textures for all MF.ISMoodle instances
    if MF ~= nil then
        MF.ISMoodle.updateTextures()
    end

    ISMoodlesInLuaHandle:update()
end

local og_load = PZAPI.ModOptions.load
PZAPI.ModOptions.load = function(self)
    og_load(self)
    pcall(function ()
        MILOptions:apply()
    end)
end



--[[LIFESTYLE COMPATIBILITY]]--

require "LSMoodleManager"

if LSMoodleManager ~= nil then

local alignmentTable = { Good = 1, Bad = 2, }

  function LSgetMoodleBkg(player, moodleLevel, moodleName)
      local alignment = player:getModData().LSMoodles[moodleName].Alignment
      local g = alignmentTable[alignment] or 0
      local texturePath = ISMoodlesInLuaHandle:getBorderTexturePath(g, moodleLevel)
      return texturePath
  end

end

--[[MOODLE FRAMEWORK COMPATIBILITY]]--

require "MF_ISMoodle"

if MF ~= nil then

    local oldNew = MF.ISMoodle.new
    MF.ISMoodle.instances = {} -- Table to store instances

    local function loadTextures(instance)
        for g = 1, 2 do
            for l = 1, 4 do
                local MFtexturePath = ISMoodlesInLuaHandle:getBorderTexturePath(g, l)
                local MFtexture = ISMoodlesInLuaHandle:getTexture(MFtexturePath)

                if MFtexture then
                    instance:setBackground(g, l, MFtexture)  -- Set the background texture
                else
                    print("MIL: Texture not found for MF, path: " .. MFtexturePath)
                end
            end
        end
    end

    -- I added this function because moodles in lua can show FoodEaten on all levels, so it's just copying the code and removing one condition :p
    function MF.ISMoodle:getXYPosition()
        local size = MF.getSize()
        if size ~= self.width then
            self:setWidth(size);
            self:updateTextures(size)
        end

        local x = getPlayerScreenLeft(self.playerNum) + getPlayerScreenWidth(self.playerNum) - MF.xOffset - self:getWidth()
        local y = getPlayerScreenTop(self.playerNum) + MF.yOffset
        local distY = 10 + MF.defaultWidth * MF.scale
        local numMoodles = self.char:getMoodles():getNumMoodles();

        if self.disable then
            if MF.verbose then print("MF.ISMoodle:getXYPosition while disabled. "..self.name) end;
            return x,y;
        end

        if self:getLevel() ~= 0 then--bypass when not displayed (this is bad design)
            for i = 0, numMoodles-1 do--vanilla moodles first
                local moodleType = MoodleType.FromIndex(i)
                local moodleLevel = self.char:getMoodles():getMoodleLevel(moodleType)
                if moodleLevel ~= 0 then
                    y = y + distY;
                end
            end

            local aiteronMM = self.char:getModData().MoodleManager;--aiteron moodles second
            if aiteronMM and aiteronMM.moodles then
                local nbMoodlesAiteron = 0
                for _, moodleObj in pairs(aiteronMM.moodles) do
                    --print("MF.ISMoodle:AiteronCompatibility MoodleManager "..tostring(_ or 'nil').." "..tostring(moodleObj or 'nil'));
                    if moodleObj.getLevel then--there is a fake item (_ == 1) in moodles that has no getLevel
                        local lvl = moodleObj:getLevel()
                        if lvl > 0 then
                            nbMoodlesAiteron = nbMoodlesAiteron + 1
                            y = y + distY;
                        end
                    end
                end
                --print("MF.ISMoodle:AiteronCompatibility MoodleManager "..nbMoodlesAiteron.." moodles");
            else
                --print("MF.ISMoodle:AiteronCompatibility no MoodleManager");
            end

            for k, v in pairs(self.char:getModData().Moodles) do--modded moodles then
                if k == self.name then
                    break--found
                else
                    if v.Level ~= 0 then--this is why we need to share level in player mod data
                        y = y + distY;
                    end
                end
            end
        end

        return x, y
    end
    -- end of MF.ISMoodle:getXYPosition

    function MF.ISMoodle.new(self, moodleName, character)
        local o = oldNew(self, moodleName, character)
        table.insert(MF.ISMoodle.instances, o) -- Store the instance

        -- Load textures for the new instance
        loadTextures(o)

        return o
    end

    -- Function to update textures for all instances
    function MF.ISMoodle.updateTextures()
        for _, instance in ipairs(MF.ISMoodle.instances) do
            loadTextures(instance) -- Update the background textures
        end
    end
end
