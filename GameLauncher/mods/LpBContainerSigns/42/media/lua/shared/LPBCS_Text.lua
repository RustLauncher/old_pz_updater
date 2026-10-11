--[[
    © 2026 Warlord-Fox3. Tous droits réservés / All Rights Reserved.

    Toute réutilisation, modification, redistribution ou inclusion dans un
    modpack sans autorisation écrite préalable est strictement interdite.

    Any reuse, modification, redistribution, or inclusion in a modpack
    without prior written permission is strictly prohibited.
]]

--[[
    LPBCS_Text -- translation lookup that never shows a raw key to a player.

    getText() returns the key itself when a translation is missing, which in
    practice means a player sees "IGUI_LPBCS_NoWritingTool" floating over
    their head. Every user-facing string in this mod goes through here with an
    English fallback baked in at the call site.
]]

require "LPBCS_Core"

--- Substitutes %1, %2, ... in a fallback string. getText does this for real
--- translations; the fallback has to do it itself or a player would be shown
--- a literal "You need %1 to write on this.".
local function substitute(template, ...)
    local count = select("#", ...)
    if count == 0 then return template end

    local out = template
    for index = 1, count do
        local value = tostring(select(index, ...))
        -- gsub treats % specially in the replacement, so escape it there.
        out = out:gsub("%%" .. index, (value:gsub("%%", "%%%%")))
    end
    return out
end

--- Translated text for `key`, or `fallback` when the key is untranslated.
--- Extra arguments are substituted into %1, %2, ... either way.
function LPBCS.text(key, fallback, ...)
    if getText and key ~= nil then
        local ok, value = pcall(getText, key, ...)
        if ok and value ~= nil and value ~= key and value ~= "" then
            return value
        end
    end

    if fallback == nil then return tostring(key) end
    return substitute(fallback, ...)
end

function LPBCS.sayBad(playerObj, message)
    if not playerObj or message == nil then return end
    if HaloTextHelper and HaloTextHelper.addBadText then
        if LPBCS.attempt(HaloTextHelper.addBadText, playerObj, tostring(message)) ~= nil then
            return
        end
    end
    LPBCS.invoke(playerObj, "Say", tostring(message))
end

--- Resolves a {key, fallback, args} triple sent by the server. Server code
--- never sends prose over the wire, only keys, so each client renders the
--- refusal in its own language.
function LPBCS.resolveMessage(payload)
    if type(payload) ~= "table" then return nil end
    local args = payload.args
    if type(args) == "table" and #args > 0 then
        return LPBCS.text(payload.key, payload.fallback, unpack(args))
    end
    return LPBCS.text(payload.key, payload.fallback)
end

return LPBCS
