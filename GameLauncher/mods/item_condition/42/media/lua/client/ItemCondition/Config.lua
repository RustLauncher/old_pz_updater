ItemCondition = ItemCondition or {}
ItemCondition.Config = ItemCondition.Config or {}

local Config = ItemCondition.Config
Config.Hotbar = Config.Hotbar or {}
Config.Equipped = Config.Equipped or {}

Config.Hotbar.ProgressBarMode = 3
Config.Hotbar.ProgressBarOpacity = 0.30

Config.Equipped.ProgressBarMode = 3
Config.Equipped.ProgressBarOpacity = 0.30

Config.TypeDefault = {
    Colors = {
        P100 = { r = 0.0, g = 0.7, b = 0.0 },
        P090 = { r = 0.0, g = 0.7, b = 0.0 },
        P080 = { r = 0.0, g = 0.7, b = 0.0 },
        P070 = { r = 0.0, g = 0.7, b = 0.0 },
        P060 = { r = 1.0, g = 1.0, b = 0.0 },
        P050 = { r = 1.0, g = 1.0, b = 0.0 },
        P040 = { r = 1.0, g = 1.0, b = 0.0 },
        P030 = { r = 1.0, g = 1.0, b = 0.0 },
        P020 = { r = 1.0, g = 0.2, b = 0.2 },
        P010 = { r = 1.0, g = 0.2, b = 0.2 },
        P000 = { r = 1.0, g = 0.2, b = 0.2 }
    }
}

Config.TypeWater = {
    Colors = {
        P100 = { r = 0.0, g = 0.0, b = 1.0 },
        P090 = { r = 0.0, g = 0.0, b = 1.0 },
        P080 = { r = 0.0, g = 0.0, b = 1.0 },
        P070 = { r = 0.0, g = 0.0, b = 1.0 },
        P060 = { r = 0.0, g = 0.0, b = 1.0 },
        P050 = { r = 0.0, g = 0.0, b = 1.0 },
        P040 = { r = 0.0, g = 0.0, b = 1.0 },
        P030 = { r = 0.0, g = 0.0, b = 1.0 },
        P020 = { r = 0.0, g = 0.0, b = 1.0 },
        P010 = { r = 0.0, g = 0.0, b = 1.0 },
        P000 = { r = 0.0, g = 0.0, b = 1.0 }
    }
}
