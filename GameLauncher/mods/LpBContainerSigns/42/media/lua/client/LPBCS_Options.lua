--[[
    © 2026 Warlord-Fox3. Tous droits réservés / All Rights Reserved.

    Toute réutilisation, modification, redistribution ou inclusion dans un
    modpack sans autorisation écrite préalable est strictement interdite.

    Any reuse, modification, redistribution, or inclusion in a modpack
    without prior written permission is strictly prohibited.
]]

--[[
    LPBCS_Options -- the per-player half of the mod.

    Sandbox options (LPBCS_Config) decide the rules: who may write, what it
    costs, how long a name may be. These decide only how the sign looks on
    this screen, so two players on the same server can disagree about the
    display radius without disagreeing about anything that matters.

    Built on PZAPI.ModOptions, which build 42 ships natively -- no dependency
    on the workshop Mod Options mod. Every read is guarded: if the API is
    missing the mod falls back to its defaults rather than going dark.
]]

require "LPBCS_Core"
require "LPBCS_Text"

LPBCS.Options = LPBCS.Options or {}
local Options = LPBCS.Options

local DEFAULTS = {
    enabled          = true,
    radius           = 8,
    opacity          = 80,
    hideWhenLootOpen = false,
}

--- Every name and tooltip handed to ModOptions is run back through getText()
--- by the vanilla options screen (MainOptions.lua:3025). Translator reads a
--- stray "%" in there as a format placeholder and throws, which kills the
--- whole panel -- our page and every other mod's with it. Our own strings
--- keep clear of the character; this is the net under future translations.
local function label(key, fallback, ...)
    return (tostring(LPBCS.text(key, fallback, ...)):gsub("%%", ""))
end

local function build()
    if not PZAPI or not PZAPI.ModOptions or not PZAPI.ModOptions.create then return nil end

    local page = LPBCS.attempt(function()
        return PZAPI.ModOptions:create(LPBCS.MOD_ID,
            label("UI_LPBCS_OptionsTitle", "LpB Container Signs"))
    end)
    if not page then return nil end

    page:addTickBox("enabled",
        label("UI_LPBCS_Opt_Enabled", "Show signs on containers"),
        DEFAULTS.enabled,
        label("UI_LPBCS_Opt_Enabled_tooltip",
            "Draw the name written on a crate or cabinet in the world. Turning this off hides every sign for you only; the names themselves are untouched."))

    page:addSlider("radius",
        label("UI_LPBCS_Opt_Radius", "Display radius (tiles)"),
        3, 20, 1, DEFAULTS.radius,
        label("UI_LPBCS_Opt_Radius_tooltip",
            "How far a sign stays readable. Signs fade out over the last two tiles instead of blinking away. Lower this in a dense base."))

    page:addSlider("opacity",
        label("UI_LPBCS_Opt_Opacity", "Sign opacity (percent)"),
        20, 100, 5, DEFAULTS.opacity,
        label("UI_LPBCS_Opt_Opacity_tooltip",
            "How solid the signs are drawn."))

    page:addTickBox("hideWhenLootOpen",
        label("UI_LPBCS_Opt_HideWhenLoot", "Hide while the loot window is open"),
        DEFAULTS.hideWhenLootOpen,
        label("UI_LPBCS_Opt_HideWhenLoot_tooltip",
            "Clears the signs off the screen while you are actually rummaging through a container, when you no longer need them."))

    return page
end

local page = build()

local function value(id)
    if not page then return DEFAULTS[id] end
    local option = LPBCS.attempt(function() return page:getOption(id) end)
    if not option then return DEFAULTS[id] end
    local stored = LPBCS.attempt(function() return option:getValue() end)
    if stored == nil then return DEFAULTS[id] end
    return stored
end

function Options.enabled()
    return value("enabled") == true
end

function Options.radius()
    return LPBCS.clampInt(value("radius"), 3, 20)
end

--- 0..1, the way every draw call wants it.
function Options.opacity()
    return LPBCS.clampInt(value("opacity"), 20, 100) / 100
end

function Options.hideWhenLootOpen()
    return value("hideWhenLootOpen") == true
end

-- ------------------------------------------------------------------- fade

--- Over how many tiles a sign fades out at the edge of the radius, and the
--- alpha below which it stops being worth drawing at all.
---
--- Here rather than in a renderer because BOTH have to agree on them: the sign
--- the engine draws in the world (LPBCS_Sprites, placed by the sweep) and the
--- overlay that picks up whatever the world path could not take
--- (LPBCS_Render). They used to live in the overlay alone, which is how the
--- radius tooltip came to promise a fade that the path players actually see
--- never performed -- and how a sign walked away from stayed nailed up behind
--- them at full strength, because nothing outside the overlay knew the radius
--- had an edge at all.
local FADE_TILES = 2
local MIN_ALPHA = 0.02

--- How solid a sign this far from the player should be drawn: their own
--- opacity, faded out linearly over the last FADE_TILES, and nothing past the
--- radius.
---
--- `radius` and `opacity` are handed in rather than read here, and that is not
--- an oversight: both callers walk a list -- every sign on screen, every
--- container in the sweep -- and every option read is a pcall into the options
--- page. Read the two once at the top of the walk and pass them down.
function Options.alphaAt(distance, radius, opacity)
    if type(distance) ~= "number" then return 0 end
    if distance > radius then return 0 end

    local fadeFrom = radius - FADE_TILES
    if distance <= fadeFrom then return opacity end
    return opacity * ((radius - distance) / FADE_TILES)
end

--- Invisible anyway: not worth the draw calls on the overlay, and not worth a
--- sprite in the world.
function Options.tooFaint(alpha)
    return type(alpha) ~= "number" or alpha <= MIN_ALPHA
end

--- Is this player rummaging through a container right now?
---
--- Asked by both renderers for hideWhenLootOpen, so it sits next to the option
--- rather than inside whichever of them happened to need it first.
function Options.lootWindowOpen(playerNum)
    local loot = LPBCS.attempt(getPlayerLoot, playerNum)
    if not loot then return false end
    return LPBCS.get(loot, "getIsVisible", false) == true
end

return Options
