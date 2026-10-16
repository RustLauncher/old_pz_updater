require "OptionScreens/ServerSettingsScreen"

-- Use the game's existing section headings on our single sandbox page.
-- Option IDs and saved values stay the same in new games and server settings.
if not ServerSettingsScreen.DrPepperSectionsInstalled then
    ServerSettingsScreen.DrPepperSectionsInstalled = true
    local original = ServerSettingsScreen.getSandboxSettingsTable
    local titles = {
        ["DrPepperFridge.Chance"] = "DrPepperFridge_Fridges",
        ["DrPepperFridge.DrinkThirst"] = "DrPepperFridge_Drinks",
        ["DrPepperFridge.PostersEnabled"] = "DrPepperFridge_Posters",
    }

    function ServerSettingsScreen.getSandboxSettingsTable(...)
        local settings = original(...)
        local pages = settings
        for _, page in ipairs(pages or {}) do
            for _, setting in ipairs(page.settings or {}) do
                local title = titles[setting.name]
                if title then setting.title = title end
            end
        end
        return settings
    end
end
