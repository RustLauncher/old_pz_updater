ItemCondition = ItemCondition or {}
ItemCondition.ModOptions = ItemCondition.ModOptions or {}

local Config = ItemCondition.Config
local OPTIONS_ID = "qdx_item_condition"

local function clamp(value, minimum, maximum)
    if value < minimum then
        return minimum
    end

    if value > maximum then
        return maximum
    end

    return value
end

local function getColor(color)
    return {
        r = color.r or 0,
        g = color.g or 0,
        b = color.b or 0
    }
end

local function setupOptions()
    if not PZAPI or not PZAPI.ModOptions then
        return
    end

    if PZAPI.ModOptions:getOptions(OPTIONS_ID) then
        return
    end

    local options = PZAPI.ModOptions:create(
        OPTIONS_ID,
        getText("UI_qdx_item_condition_mod_name_uppercase")
    )

    options:addTitle(
        getText("UI_qdx_item_condition_section_hotbar")
    )

    local hotbarMode = options:addComboBox(
        "hotbar_progressbar_mode",
        getText("UI_qdx_item_condition_option_hotbar_progressbar_mode_name"),
        getText("UI_qdx_item_condition_option_hotbar_progressbar_mode_hover")
    )

    hotbarMode:addItem(
        getText("UI_qdx_item_condition_option_progressbar_mode_none"),
        Config.Hotbar.ProgressBarMode == 1
    )

    hotbarMode:addItem(
        getText("UI_qdx_item_condition_option_progressbar_mode_vertical"),
        Config.Hotbar.ProgressBarMode == 2
    )

    hotbarMode:addItem(
        getText("UI_qdx_item_condition_option_progressbar_mode_vertical_multicolor"),
        Config.Hotbar.ProgressBarMode == 3
    )

    hotbarMode:addItem(
        getText("UI_qdx_item_condition_option_progressbar_mode_horizontal"),
        Config.Hotbar.ProgressBarMode == 4
    )

    hotbarMode:addItem(
        getText("UI_qdx_item_condition_option_progressbar_mode_horizontal_multicolor"),
        Config.Hotbar.ProgressBarMode == 5
    )

    local hotbarOpacity = options:addSlider(
        "hotbar_progressbar_opacity",
        getText("UI_qdx_item_condition_option_hotbar_progressbar_opacity_name"),
        0.1,
        1.0,
        0.01,
        Config.Hotbar.ProgressBarOpacity,
        getText("UI_qdx_item_condition_option_hotbar_progressbar_opacity_hover")
    )

    options:addSeparator()

    options:addTitle(
        getText("UI_qdx_item_condition_section_equipped")
    )

    local equippedMode = options:addComboBox(
        "equipped_progressbar_mode",
        getText("UI_qdx_item_condition_option_equipped_progressbar_mode_name"),
        getText("UI_qdx_item_condition_option_equipped_progressbar_mode_hover")
    )

    equippedMode:addItem(
        getText("UI_qdx_item_condition_option_progressbar_mode_none"),
        Config.Equipped.ProgressBarMode == 1
    )

    equippedMode:addItem(
        getText("UI_qdx_item_condition_option_progressbar_mode_vertical"),
        Config.Equipped.ProgressBarMode == 2
    )

    equippedMode:addItem(
        getText("UI_qdx_item_condition_option_progressbar_mode_vertical_multicolor"),
        Config.Equipped.ProgressBarMode == 3
    )

    equippedMode:addItem(
        getText("UI_qdx_item_condition_option_progressbar_mode_horizontal"),
        Config.Equipped.ProgressBarMode == 4
    )

    equippedMode:addItem(
        getText("UI_qdx_item_condition_option_progressbar_mode_horizontal_multicolor"),
        Config.Equipped.ProgressBarMode == 5
    )

    local equippedOpacity = options:addSlider(
        "equipped_progressbar_opacity",
        getText("UI_qdx_item_condition_option_equipped_progressbar_opacity_name"),
        0.1,
        1.0,
        0.01,
        Config.Equipped.ProgressBarOpacity,
        getText("UI_qdx_item_condition_option_equipped_progressbar_opacity_hover")
    )

    options:addSeparator()

    options:addTitle(
        getText("UI_qdx_item_condition_section_colors")
    )

    local defaultColors = Config.TypeDefault.Colors
    local waterColors = Config.TypeWater.Colors

    local colorOptions = {
        { "P100", "100" },
        { "P090", "090" },
        { "P080", "080" },
        { "P070", "070" },
        { "P060", "060" },
        { "P050", "050" },
        { "P040", "040" },
        { "P030", "030" },
        { "P020", "020" },
        { "P010", "010" },
        { "P000", "000" }
    }

    for _, entry in ipairs(colorOptions) do
        local key = entry[1]

        options:addColorPicker(
            "default_color_" .. key,
            getText(
                "UI_qdx_item_condition_option_default_color_" .. key
            ),
            defaultColors[key].r,
            defaultColors[key].g,
            defaultColors[key].b,
            1.0,
            getText(
                "UI_qdx_item_condition_option_default_color_" ..
                key ..
                "_hover"
            )
        )

        options:addColorPicker(
            "water_color_" .. key,
            getText(
                "UI_qdx_item_condition_option_water_color_" .. key
            ),
            waterColors[key].r,
            waterColors[key].g,
            waterColors[key].b,
            1.0,
            getText(
                "UI_qdx_item_condition_option_water_color_" ..
                key ..
                "_hover"
            )
        )

        if key ~= "P000" then
            options:addSeparator()
        end
    end

    ItemCondition.ModOptions.Options = options
    ItemCondition.ModOptions.HotbarMode = hotbarMode
    ItemCondition.ModOptions.HotbarOpacity = hotbarOpacity
    ItemCondition.ModOptions.EquippedMode = equippedMode
    ItemCondition.ModOptions.EquippedOpacity = equippedOpacity
end

local function readOptions()
    local options = ItemCondition.ModOptions.Options

    if not options then
        return
    end

    local hotbarMode = ItemCondition.ModOptions.HotbarMode:getValue()
    local hotbarOpacity = ItemCondition.ModOptions.HotbarOpacity:getValue()

    local equippedMode = ItemCondition.ModOptions.EquippedMode:getValue()
    local equippedOpacity = ItemCondition.ModOptions.EquippedOpacity:getValue()

    Config.Hotbar.ProgressBarMode =
        clamp(tonumber(hotbarMode) or 3, 1, 5)

    Config.Hotbar.ProgressBarOpacity =
        clamp(tonumber(hotbarOpacity) or 0.30, 0.1, 1.0)

    Config.Equipped.ProgressBarMode =
        clamp(tonumber(equippedMode) or 3, 1, 5)

    Config.Equipped.ProgressBarOpacity =
        clamp(tonumber(equippedOpacity) or 0.30, 0.1, 1.0)

    local defaultColors = Config.TypeDefault.Colors
    local waterColors = Config.TypeWater.Colors

    local colorKeys = {
        "P100",
        "P090",
        "P080",
        "P070",
        "P060",
        "P050",
        "P040",
        "P030",
        "P020",
        "P010",
        "P000"
    }

    for _, key in ipairs(colorKeys) do
        local defaultOption =
            options:getOption("default_color_" .. key)

        if defaultOption then
            local color = defaultOption:getValue()

            if color then
                defaultColors[key] = getColor(color)
            end
        end

        local waterOption =
            options:getOption("water_color_" .. key)

        if waterOption then
            local color = waterOption:getValue()

            if color then
                waterColors[key] = getColor(color)
            end
        end
    end
end

local function installColorPickerWidthHook()
    if not MainOptions or type(MainOptions.addModOptionsPanel) ~= "function" then
        return false
    end

    if ItemCondition.ModOptions.ColorWidthHookInstalled then
        return true
    end

    local originalAddModOptionsPanel = MainOptions.addModOptionsPanel

    MainOptions.addModOptionsPanel = function(self, ...)
        originalAddModOptionsPanel(self, ...)

        local options = PZAPI.ModOptions and PZAPI.ModOptions:getOptions(OPTIONS_ID)
        if not options then
            return
        end

        local comboWidth = 45 * (getCore():getOptionFontSizeReal() + 1) + 60
        local colorWidth = math.max(100, comboWidth - 15)

        for _, option in ipairs(options.data) do
            if option.type == "colorpicker" and option.element then
                option.element:setWidth(colorWidth)
            end
        end
    end

    ItemCondition.ModOptions.ColorWidthHookInstalled = true
    return true
end

setupOptions()

installColorPickerWidthHook()

if Events and Events.OnGameBoot then
    Events.OnGameBoot.Add(installColorPickerWidthHook)
end

if Events and Events.OnGameStart then
    Events.OnGameStart.Add(installColorPickerWidthHook)
end

Events.OnGameStart.Add(function()
    readOptions()
end)