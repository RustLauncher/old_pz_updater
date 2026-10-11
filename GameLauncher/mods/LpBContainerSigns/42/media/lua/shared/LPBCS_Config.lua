--[[
    © 2026 Warlord-Fox3. Tous droits réservés / All Rights Reserved.

    Toute réutilisation, modification, redistribution ou inclusion dans un
    modpack sans autorisation écrite préalable est strictement interdite.

    Any reuse, modification, redistribution, or inclusion in a modpack
    without prior written permission is strictly prohibited.
]]

--[[
    LPBCS_Config -- the only place sandbox options are read.

    Lookup order for a key:
        SandboxVars.LpBContainerSigns[key]
        getSandboxOptions():getOptionByName("LpBContainerSigns."..key)
        hard-coded default

    Sandbox options are the server's half of the mod: they decide what the
    rules are. How a sign LOOKS is a per-player choice and lives in
    LPBCS_Options instead, so two players on the same server can disagree
    about the display radius without disagreeing about who may write.
]]

require "LPBCS_Core"

LPBCS.Config = LPBCS.Config or {}
local Config = LPBCS.Config

local function fromSandboxVars(key)
    if not SandboxVars then return nil end
    local group = SandboxVars[LPBCS.MOD_ID]
    if type(group) ~= "table" then return nil end
    return group[key]
end

local function fromSandboxOptions(key)
    if not getSandboxOptions then return nil end
    local options = LPBCS.attempt(getSandboxOptions)
    if not options or not options.getOptionByName then return nil end
    local option = LPBCS.attempt(function()
        return options:getOptionByName(LPBCS.MOD_ID .. "." .. key)
    end)
    if not option then return nil end
    return LPBCS.get(option, "getValue", nil)
end

--- Walks the lookup chain and returns the first value that exists.
local function resolve(key)
    local value = fromSandboxVars(key)
    if value ~= nil then return value end
    return fromSandboxOptions(key)
end

function Config.getInt(key, default)
    local value = resolve(key)
    if type(value) == "number" then return math.floor(value) end
    return math.floor(default or 0)
end

function Config.getBool(key, default)
    local value = resolve(key)
    if value ~= nil then return value == true end
    return default == true
end

-- ------------------------------------------------------------------ rules

function Config.writingEnabled()
    return Config.getBool("WritingEnabled", true)
end

--- Crates only, which is what a base tends to want: the storage a player
--- built and filled deliberately, not every fridge and bedside table of the
--- neighbourhood. Off, any container in the world can carry a sign.
---
--- Unlike every other rule here this one is remembered, because it is read
--- from LPBCS.isSignableContainer -- once per container per square per sweep,
--- four sweeps a second. The lookup itself is two table reads, but a save
--- whose SandboxVars predate this option would fall through to
--- getSandboxOptions() on every single one of those calls, and that is a
--- pcall around a Java call. Sandbox values are fixed for a session, so
--- resolving once costs nothing in accuracy.
---
--- Nothing is remembered until the sandbox actually answers: the first call
--- could in principle land before the server's options have arrived, and a
--- default cached from that moment would outlive its excuse.
local cratesOnly = nil

function Config.cratesOnly()
    if cratesOnly ~= nil then return cratesOnly end

    local value = resolve("CratesOnly")
    if value == nil then return true end

    cratesOnly = value == true
    return cratesOnly
end

function Config.requireWritingTool()
    return Config.getBool("RequireWritingTool", true)
end

--- Only ever spends a drainable tool: a paint can loses a use, a pen does
--- not, exactly like the vanilla map annotations that ask for a pen and
--- never wear it out.
function Config.consumeToolUse()
    return Config.getBool("ConsumeToolUse", true)
end

function Config.restrictToSafehouse()
    return Config.getBool("RestrictToSafehouse", true)
end

--- Bounded by LPBCS.MAX_TEXT_LENGTH, which is the vanilla rename limit.
function Config.maxTextLength()
    return LPBCS.clampInt(Config.getInt("MaxLabelLength", 24), 4, LPBCS.MAX_TEXT_LENGTH)
end

--- Whether LPBCS.log says anything at all. Off, the mod is silent -- see the
--- gate in LPBCS_Core.
---
--- Read live from SandboxVars on every call rather than memoised like
--- cratesOnly, because a debug switch that needs a restart is a debug switch
--- nobody reaches for. SandboxVars is a plain Lua table the engine refreshes
--- when an admin edits the options, so two table reads buy a live toggle.
---
--- Only the fallback tier is remembered, and it does not go through getBool for
--- that reason. A save whose SandboxVars predate this option never answers on
--- the first tier, and falling through to getSandboxOptions() -- a pcall around
--- a Java call -- on every single log line is the one cost worth avoiding here.
--- Remembering a premature `false` is harmless, unlike in cratesOnly above:
--- SandboxVars stays the primary tier and is still read on every call, so a
--- value arriving late is still seen.
local debugFallback = nil

function Config.debugLogging()
    local value = fromSandboxVars("DebugLogging")
    if value ~= nil then return value == true end

    if debugFallback == nil then
        debugFallback = fromSandboxOptions("DebugLogging") == true
    end
    return debugFallback
end

-- ----------------------------------------------------------------- styles

local STYLE_OPTIONS = {
    plank   = "AllowPlankSign",
    paper   = "AllowPaperSign",
    painted = "AllowPaintedSign",
}

function Config.styleAllowed(style)
    local key = STYLE_OPTIONS[style]
    if not key then return false end
    return Config.getBool(key, true)
end

--- Styles this server accepts, in the mod's own order. Never empty: a server
--- that switched every style off would otherwise make writing impossible in
--- a way no message explains, so the first style stays available.
function Config.allowedStyles()
    local out = {}
    for _, style in ipairs(LPBCS.STYLES) do
        if Config.styleAllowed(style) then out[#out + 1] = style end
    end
    if #out == 0 then out[1] = LPBCS.DEFAULT_STYLE end
    return out
end

function Config.defaultStyle()
    local allowed = Config.allowedStyles()
    if LPBCS.listContains(allowed, LPBCS.DEFAULT_STYLE) then return LPBCS.DEFAULT_STYLE end
    return allowed[1]
end

return Config
