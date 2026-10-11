-- ============================================================================
-- TooltipLib Diagnostics — user-facing compatibility check
-- ============================================================================
-- Turns the runtime evidence the hooks already collect (TooltipLib._diag
-- counters, slot-ownership probe, circuit-breaker state) plus the user's
-- actual load order (getActivatedMods) into a three-level verdict:
--
--   OK        — healthy; nothing to do
--   MITIGATED — a conflict pattern was detected and contained automatically;
--               tooltips keep working, optional improvements listed
--   ACTION    — something needs the USER (fix load order / disable a mod) or
--               needs to be REPORTED (to TooltipLib or another mod's author);
--               the report says which, per finding
--
-- Surfaces:
--   TooltipLib.diagnose()        — full report -> debug log/console + returned
--   Mod Options > TooltipLib > "Run compatibility check" (button, Options.lua)
--   Automatic one-shot nudge ~2 min into a session when verdict is ACTION
--
-- The pattern taxonomy behind the rules is documented in
-- docs/COMPATIBILITY.md — each finding here corresponds to a class there.
-- ============================================================================

require "TooltipLib/Core"

-- Known tooltip-touching mods, by verified mod ID. class values:
--   bypasser  — replaces the render, never chains (TooltipLib must load AFTER)
--   ownpanel  — draws its own panel; TooltipLib stands down for its items
--   host      — layout framework TooltipLib integrates with natively
--   reclaimer — re-takes the render slot; contained by the cycle breaker
local KNOWN_MODS = {
    -- IDS MUST BE THE mod.info `id=`, NOT the containing folder name.
    -- getActivatedMods() returns ids, so a folder name here silently never
    -- matches and the mod goes unrecognised. That happened: this table carried
    -- "ExtensiveHealthReworkB42" (the folder) for the mod whose real id is
    -- "ExtensiveHealthReworkEvolved" — so the class-3 own-panel renderer that
    -- caused the v1.4.2 unbounded-growth incident was never once reported by
    -- diagnose(). scripts/tooltip-interop-audit.py now checks this table
    -- against ids read off disk.
    { id = "Tempo_PerfKit", name = "Tempo - PZ Performance Toolkit", class = "bypasser" },
    { id = "showweaponstatsplus4213", name = "Show Weapon Stats Plus (4213 fork)", class = "bypasser" },
    { id = "showweaponstatsplus", name = "Show Weapon Stats Plus (base)", class = "bypasser",
      note = "the BASE variant also throws on 42.20+ (swsp_main.lua initStats passes a " ..
          "String where PZ now wants the WeaponCategory enum) — the error surfaces inside " ..
          "TooltipLib's render path because SWSP draws through the hosted tooltip, but it " ..
          "is SWSP's; the 4213 fork or SauceTooltips' weapon-stats provider replaces it" },
    { id = "ExtensiveHealthReworkEvolved", name = "Extensive Health Rework Evolved", class = "ownpanel" },
    { id = "StarlitLibrary", name = "StarlitLibrary", class = "host" },
    { id = "EURY_CLOTHINGINFO", name = "Better Clothing Info (EuryTooltipController)", class = "host",
      eury = true,
      note = "installs its controller at file load, so TooltipLib always wraps outside it — " ..
          "safe in any load order on its own (but see Better Item Info + Guns of Marz below, " ..
          "which shares this controller). Non-clothing items compose natively (its default " ..
          "owner dispatches item:DoTooltip); clothing cards are BCI-owned, TooltipLib appends below" },
    -- Verified from source 2026-10-02 (Better Item Info 42.19, Workshop 3758971325,
    -- BII/Compatibility/GunsOfMarz.lua:35-41): when Guns of Marz is active it
    -- REPLACES ISToolTipInv.render with the Eury controller -- immediately AND
    -- again on OnGameStart -- without chaining the previous render. TooltipLib
    -- also installs on OnGameStart, and those handlers run in mod load order,
    -- so whichever loads LATER owns the hook. Field case (Django77): adding
    -- Timber Chainsaw (require=TooltipLib) pulled TooltipLib from #195 up to
    -- #160, above Better Item Info at #188, and every TooltipLib row vanished.
    -- Reproduced: tests/test_tooltiplib_eury_order_*.lua.
    { id = "EURY_ITEMINFO", name = "Better Item Info (EuryTooltipController)", class = "host",
      eury = true,
      bypassesWith = "GunsOfMarz",
      note = "same controller as Better Clothing Info. With Guns of Marz active, its Guns of " ..
          "Marz patch re-takes the tooltip on game start WITHOUT passing it on, so TooltipLib " ..
          "must load BELOW it" },
    { id = "MagicAccessories", name = "Magic Accessories", class = "reclaimer" },
    { id = "altredux", name = "Alternative Inventory Rendering", class = "reclaimer",
      note = "installs TWO independent render wrappers (cl_itrk_collection, cl_itrk_freshness), " ..
          "each capturing ISToolTipInv.render from inside a deferred OnTick install — the same " ..
          "late-capture shape that produced the v1.6.0 mutual-recursion overflow. The " ..
          "boot-render cycle breaker contains it; expect render_cycle lines on a fresh boot" },
    { id = "GunsOfMarz", name = "Guns of Marz", class = "chaining",
      note = "verified from source 2026-09: captures the previous render and chains on BOTH " ..
          "surfaces (item + itemSlot, the slot install guarded by an idempotence flag). " ..
          "Well-behaved in any order, and it contains NO TooltipLib code at all — the " ..
          "'MarzGuns_Info' provider in the 2026-08-31 half-empty-tooltip report is a THIRD " ..
          "PARTY bridge provider written by the reporter, not shipped by Guns of Marz" },
    { id = "ArmorMakesSense", name = "Armor Makes Sense", class = "reclaimer",
      note = "its Burden/Breathing tooltip rows CANNOT show while StarlitLibrary owns the " ..
          "card (AMS only integrates with EuryTooltipController; Starlit builds the card " ..
          "without dispatching AMS's hook) — no load order fixes that; the AMS author " ..
          "would need to register a TooltipLib or Starlit provider" },
}

local OWN_MOD_ID = "TooltipLib"

local LEVEL_RANK = { OK = 1, MITIGATED = 2, ACTION = 3 }

--- Active mod IDs in load order -> { map = id->position(1-based), list }.
--- nil map when the API is unavailable (test harness, weird contexts).
local function readLoadOrder()
    local map, list = {}, {}
    local ok = pcall(function()
        local mods = getActivatedMods()
        for i = 0, mods:size() - 1 do
            local id = mods:get(i)
            map[id] = i + 1
            list[#list + 1] = id
        end
    end)
    if not ok then return nil, nil end
    return map, list
end

--- Build the report. Returns (reportString, level, summaryLine).
--- silent=true skips printing (used by the automatic nudge).
--- WHERE a Lua function was defined, as "<mod> (<file>:<line>)". Names the mod
--- holding ISToolTipInv.render when it isn't TooltipLib -- the one fact a
--- player needs and could not get: "another mod took the hook" without a name
--- left them guessing through a 200-mod list (Django77, 2026-10-02).
--- getFilenameOfClosure / getFirstLineOfClosure are plain globals
--- (LuaManager.java:6349, no debug gate). The mod is read off the path:
--- .../108600/<workshopId>/mods/<Folder>/... or .../mods/<Folder>/...
---@param fn any
---@return string
function TooltipLib._describeClosure(fn)
    if type(fn) ~= "function" then return "none (" .. type(fn) .. ")" end
    if not getFilenameOfClosure then return "unknown (getFilenameOfClosure unavailable)" end
    local okF, file = pcall(getFilenameOfClosure, fn)
    if not okF or type(file) ~= "string" or file == "" then
        return "unknown (not a Lua closure)"
    end
    local okL, line = pcall(getFirstLineOfClosure, fn)
    local path = file:gsub("\\", "/")
    local wsId, folder = path:match("/108600/(%d+)/mods/([^/]+)/")
    if not folder then folder = path:match("/mods/([^/]+)/") end
    local short = path:match("(media/lua/.+)$") or path
    local where = short .. ((okL and type(line) == "number" and line > 0) and (":" .. line) or "")
    if folder then
        return "mod folder '" .. folder .. "'" .. (wsId and (" (Workshop " .. wsId .. ")") or "") ..
            " -- " .. where
    end
    if path:find("/media/lua/client/ISUI/", 1, true) then
        return "vanilla (" .. where .. ")"
    end
    return where
end

function TooltipLib.diagnose(silent)
    local d = TooltipLib._diag or {}
    local n = function(key) return d[key] or 0 end
    local lines = {}
    local advice = {}
    local level = "OK"

    local function raise(to)
        if LEVEL_RANK[to] > LEVEL_RANK[level] then level = to end
    end
    local function addAdvice(lvl, text)
        raise(lvl)
        advice[#advice + 1] = { lvl = lvl, text = text }
    end

    -- ── Hooks installed? ────────────────────────────────────────────────
    local hs = TooltipLib._hookStatus or {}
    local hooksLine = {}
    for _, surface in ipairs({ "item", "itemSlot", "object", "skill", "vehicle", "recipe" }) do
        local s = hs[surface]
        if s == true then
            hooksLine[#hooksLine + 1] = surface .. ": ok"
        elseif s ~= nil then
            hooksLine[#hooksLine + 1] = surface .. ": FAILED (" .. tostring(s) .. ")"
            addAdvice("ACTION", "The " .. surface .. " hook failed to install: " .. tostring(s) ..
                ". This is a TooltipLib/PZ-build problem, not a load-order problem — " ..
                "REPORT it on the TooltipLib Workshop page with this whole check.")
        end
    end

    local installed = TooltipLib._installedRender or {}
    if not installed.item then
        -- Pre-OnGameStart (main menu) — most evidence doesn't exist yet.
        local report =
            "=== TooltipLib Compatibility Check (v" .. tostring(TooltipLib.VERSION) .. ") ===\n" ..
            "Hooks are not installed yet — load a game, hover a few inventory items, then run this again."
        if not silent then TooltipLib._log(report) end
        return report, "OK", "Not in-game yet — run again after loading a save."
    end

    -- ── Render-slot ownership (item surface is the load-bearing one) ────
    local ownership
    local cur = ISToolTipInv and ISToolTipInv.render
    local contentFlowing = n("ownedRenders") > 0 or n("starlitFills") > 0 or n("deferredRenders") > 0
        or n("euryFills") > 0
    -- EuryTooltipController (Better Item Info / Better Clothing Info) owns the
    -- card through its row-provider API (EuryAdapter.lua). Whether our render
    -- wrapper is outside it or was replaced by it does not matter: content
    -- reaches the card through getRows either way, so no load-order advice.
    local euryNative = TooltipLib._euryAdapter and n("euryFills") > 0
    if euryNative then
        ownership = "Better Item Info / Better Clothing Info (EuryTooltipController) draws the " ..
            "tooltip card; TooltipLib's content flows into it through its provider API " ..
            "(native adapter, " .. n("euryFills") .. " fills). Load order does not matter for it."
    elseif cur == installed.item then
        ownership = "TooltipLib holds the tooltip hook (outermost). Ideal."
    elseif n("ownedRenders") > 0 or n("starlitFills") > 0 then
        ownership = "Another mod wrapped the hook after TooltipLib, but content is flowing through " ..
            "the chain — coexisting correctly."
    elseif n("deferredRenders") > 0 then
        ownership = "A foreign tooltip framework owns the tooltip card; TooltipLib appends its " ..
            "content below it (deferred mode)."
        addAdvice("MITIGATED", "Deferred mode is active: content shows but alignment is approximate. " ..
            "For native integration, move TooltipLib AFTER (below) the other tooltip framework in the load order.")
    elseif TooltipLib._euryAdapter then
        ownership = "Better Item Info / Better Clothing Info (EuryTooltipController) holds the " ..
            "tooltip hook; TooltipLib is registered with it as a row provider (native adapter). " ..
            "No item with TooltipLib content has been hovered yet."
    else
        ownership = "Another mod took the tooltip hook and NO TooltipLib content has rendered yet."
        addAdvice("ACTION", "Either no item has been hovered yet this session, or a mod is BYPASSING " ..
            "TooltipLib entirely. Hover a few inventory items and run this check again — if these " ..
            "counters stay at zero, the mod holding the hook is: " .. TooltipLib._describeClosure(cur) ..
            ". Move TooltipLib LOWER (later) than that mod in the Mods load order: whatever " ..
            "loads last wins the hook, and TooltipLib knows how to share it; bypassing mods don't. " ..
            "If that mod installs its hook late in the session, load order can't help: report it " ..
            "to its author with this check (it replaces the tooltip render without calling the one it captured).")
    end

    -- ── Counter-driven findings ─────────────────────────────────────────
    if n("cycleBreaks") > 0 then
        addAdvice("MITIGATED", "A render-slot loop was detected and broken " .. n("cycleBreaks") ..
            " time(s): a mod keeps re-taking the tooltip hook and chained back into TooltipLib. " ..
            "Tooltips keep working. If this happens on every fresh start, that mod's author should " ..
            "apply the boot-render fix from TooltipLib's compatibility notes (docs/COMPATIBILITY.md §6).")
    end
    if n("euryBypasses") > 0 then
        addAdvice("MITIGATED", "EuryTooltipController (Better Item Info / Better Clothing Info) is " ..
            "present, but another mod replaced the tooltip render after it for " .. n("euryBypasses") ..
            " item(s); TooltipLib routed those items through its standard path. The mod holding the " ..
            "render now is: " .. TooltipLib._describeClosure(cur) .. ".")
    end
    if n("starlitBypasses") > 0 and TooltipLib._euryAdapter then
        addAdvice("MITIGATED", "StarlitLibrary is present but Better Item Info's controller owns " ..
            "the tooltip render, so Starlit's card is not used for " .. n("starlitBypasses") ..
            " item(s). TooltipLib's content goes through the controller instead; load order " ..
            "does not change this.")
    elseif n("starlitBypasses") > 0 then
        addAdvice("ACTION", "StarlitLibrary is present but another mod bypassed it for " ..
            n("starlitBypasses") .. " item(s) — their content shows one frame late via the fallback " ..
            "path. Fix: move TooltipLib to the BOTTOM of the load order.")
    end
    if n("thrashRetires") > 0 then
        addAdvice("MITIGATED", n("thrashRetires") .. " item(s) had multiple mods fighting over their " ..
            "tooltip size; TooltipLib retired them to plain vanilla for stability. If content is " ..
            "missing on those items, reduce the number of tooltip-replacing mods.")
    end
    if n("chainErrors") > 0 then
        addAdvice("MITIGATED", "Another tooltip mod threw " .. n("chainErrors") .. " error(s) during " ..
            "rendering (contained by TooltipLib). Find the 'Render chain error' line in the debug log " ..
            "and report it to THAT mod's author.")
    end

    -- ── Load-order analysis against known tooltip mods ──────────────────
    local orderMap, orderList = readLoadOrder()
    local knownLines = {}
    if orderMap and orderMap[OWN_MOD_ID] then
        local tlPos = orderMap[OWN_MOD_ID]
        -- PZ loads a required mod immediately before the FIRST mod that requires
        -- it, so the mod right after TooltipLib is usually what put it there.
        -- Moving TooltipLib's own entry does nothing in that case -- the
        -- requirer has to move. Named so the advice can say which one.
        -- Only trusted when that mod's require= really lists TooltipLib
        -- (getModInfoByID / Mod.getRequire; ChooseGameInfo.java:225 strips the
        -- backslashes, not the spaces) -- otherwise the player put TooltipLib
        -- there themselves and naming the neighbour would be wrong advice.
        local puller = orderList and orderList[tlPos + 1]
        if puller then
            local requires = false
            pcall(function()
                local info = getModInfoByID(puller)
                local req = info and info:getRequire()
                if req then
                    for i = 0, req:size() - 1 do
                        local r = tostring(req:get(i)):gsub("^%s+", ""):gsub("%s+$", "")
                        if r == OWN_MOD_ID then requires = true end
                    end
                end
            end)
            if not requires then puller = nil end
        end
        for _, mod in ipairs(KNOWN_MODS) do
            local pos = orderMap[mod.id]
            if pos then
                local class = mod.class
                -- The Eury adapter feeds the controller's own rows, so its
                -- conditional render takeover no longer needs a load order.
                local native = mod.eury and TooltipLib._euryAdapter
                if mod.bypassesWith and orderMap[mod.bypassesWith] and not native then
                    class = "bypasser"
                end
                local line = mod.name .. " [" .. class .. "] at #" .. pos ..
                    " (TooltipLib at #" .. tlPos .. ")"
                if class == "bypasser" and mod.bypassesWith then
                    -- Conditional bypasser: installs on OnGameStart, so it is the
                    -- OnGameStart handler order (= load order) that decides.
                    if tlPos < pos then
                        line = line .. " — WRONG ORDER (" .. mod.bypassesWith .. " is active)"
                        local move = "Move TooltipLib BELOW " .. mod.name .. " in the Mods load order"
                        if puller and puller ~= mod.id then
                            move = move .. ". TooltipLib is at #" .. tlPos .. " because " .. puller ..
                                " (right after it) requires it, and the game loads a required mod just " ..
                                "before the first mod that needs it — so move " .. puller ..
                                " (and any other mod that requires TooltipLib) below " .. mod.name ..
                                "; moving TooltipLib's own entry will not stick"
                        end
                        addAdvice("ACTION", move .. ". With " .. mod.bypassesWith .. " active, " ..
                            mod.name .. " takes the tooltip over on game start without passing it on, " ..
                            "so TooltipLib's content only shows when TooltipLib loads after it.")
                    else
                        line = line .. " — ordered correctly"
                    end
                elseif class == "bypasser" and euryNative and n("euryBypasses") == 0 then
                    -- Evidence beats the table: the Eury controller drew every
                    -- card this session and none bypassed it, so this mod's
                    -- render replacement is not the one that ran. Moving
                    -- TooltipLib around it would change nothing.
                    line = line .. " — not in the way this session: Better Item Info's controller " ..
                        "draws the card and carries TooltipLib's content, so load order is moot"
                elseif class == "bypasser" then
                    if tlPos < pos then
                        line = line .. " — WRONG ORDER"
                        addAdvice("ACTION", "Move TooltipLib BELOW " .. mod.name .. " in the Mods " ..
                            "load order. It replaces the tooltip renderer without sharing; only mods " ..
                            "that load after it stay visible. TooltipLib currently loads before it.")
                    else
                        line = line .. " — ordered correctly"
                    end
                elseif class == "host" and native then
                    line = line .. " — native adapter active (TooltipLib content flows into its " ..
                        "card as rows); any load order works"
                elseif class == "host" then
                    if pos > tlPos then
                        line = line .. " — works; loading it ABOVE TooltipLib is cleanest"
                    else
                        line = line .. " — ideal (host above, TooltipLib below)"
                    end
                elseif class == "reclaimer" then
                    line = line .. " — re-takes the hook by design; contained automatically" ..
                        (n("cycleBreaks") > 0 and (" (" .. n("cycleBreaks") .. " loop-breaks this session)") or "")
                elseif class == "ownpanel" then
                    line = line .. " — draws its own tooltips for its items; TooltipLib stands down there by design"
                elseif class == "chaining" then
                    line = line .. " — chains the previous renderer; composes in any order"
                end
                if mod.note and not native then
                    line = line .. ". NOTE: " .. mod.note
                end
                knownLines[#knownLines + 1] = "  " .. line
            end
        end
    end

    -- ── Circuit-breaker state ────────────────────────────────────────────
    local disabled = {}
    for id, state in pairs(TooltipLib._errorCounts or {}) do
        if state and state.disabled then disabled[#disabled + 1] = id end
    end
    if #disabled > 0 then
        addAdvice("ACTION", "Provider(s) disabled after repeated errors: " .. table.concat(disabled, ", ") ..
            ". Their tooltips are hidden for this session. Report to the mod that registers them; " ..
            "TooltipLib.resetProvider(\"<id>\") re-enables one for testing.")
    end

    -- ── Assemble ─────────────────────────────────────────────────────────
    local summary
    if level == "OK" then
        summary = "Everything healthy — no conflicts detected."
    elseif level == "MITIGATED" then
        summary = "Conflicts detected and contained automatically — tooltips are working; see advice for optional improvements."
    else
        summary = "Action needed — see the numbered advice (load order fix or a report to a mod author)."
    end

    lines[#lines + 1] = "=== TooltipLib Compatibility Check (v" .. tostring(TooltipLib.VERSION) .. ") ==="
    lines[#lines + 1] = "VERDICT: " .. level .. " — " .. summary
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Hooks: " .. table.concat(hooksLine, " | ")
    lines[#lines + 1] = "Ownership: " .. ownership
    if cur ~= installed.item then
        lines[#lines + 1] = "Tooltip hook owner: " .. TooltipLib._describeClosure(cur)
    end
    lines[#lines + 1] = "Session evidence: owned=" .. n("ownedRenders") ..
        " starlit=" .. n("starlitFills") ..
        " deferred=" .. n("deferredRenders") ..
        " standdowns=" .. n("standDowns") ..
        " cycles-broken=" .. n("cycleBreaks") ..
        " thrash-retired=" .. n("thrashRetires") ..
        " starlit-bypassed=" .. n("starlitBypasses") ..
        " chain-errors=" .. n("chainErrors") ..
        " eury=" .. n("euryFills") ..
        " eury-bypassed=" .. n("euryBypasses")
    lines[#lines + 1] = "Providers: " .. tostring(TooltipLib.getProviderCount()) .. " registered" ..
        (#disabled > 0 and (", DISABLED: " .. table.concat(disabled, ", ")) or ", none disabled")
    if #knownLines > 0 then
        lines[#lines + 1] = "Known tooltip mods in this load order:"
        for _, l in ipairs(knownLines) do lines[#lines + 1] = l end
    elseif not orderMap then
        lines[#lines + 1] = "Load order: unavailable in this context."
    end
    if #advice > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Advice:"
        for i, a in ipairs(advice) do
            lines[#lines + 1] = "  " .. i .. ". [" .. a.lvl .. "] " .. a.text
        end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "If a problem isn't covered above, copy this whole check into a report on the TooltipLib Workshop page."

    local report = table.concat(lines, "\n")
    if not silent then TooltipLib._log(report) end
    return report, level, summary
end

-- ── Automatic one-shot nudge ─────────────────────────────────────────────
-- ~2 minutes into a session (enough hovering for the counters to mean
-- something), run silently; if the verdict is ACTION, print ONE always-on
-- warning pointing at the check. Never a modal, never repeated.
if Events and Events.EveryOneMinute then
    local minuteTicks = 0
    local autoCheck
    autoCheck = function()
        minuteTicks = minuteTicks + 1
        if minuteTicks < 2 then return end
        Events.EveryOneMinute.Remove(autoCheck)
        pcall(function()
            local _, level, summary = TooltipLib.diagnose(true)
            if level == "ACTION" then
                TooltipLib._warn("Compatibility check: " .. summary ..
                    " Run TooltipLib.diagnose() in the Lua console, or Mod Options > TooltipLib > " ..
                    "Run compatibility check.")
            end
        end)
    end
    Events.EveryOneMinute.Add(autoCheck)
end

TooltipLib._log("Diagnostics loaded (TooltipLib.diagnose())")
