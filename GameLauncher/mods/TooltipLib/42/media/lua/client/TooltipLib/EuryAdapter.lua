-- ============================================================================
-- TooltipLib EuryAdapter — native integration with EuryTooltipController
-- ============================================================================
-- EuryTooltipController ships in Better Item Info (Workshop 3758971325, id
-- EURY_ITEMINFO) and Better Clothing Info (3604080281, EURY_CLOTHINGINFO).
-- Its model, read from EuryTooltipController.lua (BII 42.19):
--
--   * install() REPLACES ISToolTipInv.render with controller:render(panel)
--     and never chains the render it found (it only falls back to the render
--     captured at ITS file load, and only when no provider has anything to
--     say). BII's Guns of Marz patch re-asserts that replacement again on
--     OnGameStart, so whether TooltipLib's render wrapper is even in the
--     chain depends on load order.
--   * The card is drawn by one OWNER provider (BII's "Layout" owner claims
--     every InventoryItem and builds the vanilla rows through
--     DoTooltipEmbedded — never item:DoTooltip, so TooltipLib's per-render
--     DoTooltip swap never fires) plus ROW providers:
--     controller:registerProvider(id, p) with p:getRows(ctx) (or getLines)
--     returning text rows { label, value, labelR/G/B, valueR/G/B,
--     valueParts } (BII/Utils.lua row/note shapes). No bars, no textures.
--   * renderControlled measures the owner, then measures every row group,
--     sizes the panel to both, and only then draws. Anything drawn after
--     that (TooltipLib's deferred staple) lands outside the box — measured
--     2026-10-07 in the SousVide tooltip gauntlet: VPS's rows at y 145..193
--     on a 150-tall panel. With StarlitLibrary also present, TooltipLib
--     stood down waiting for Starlit's onFillItemTooltip, which BII's render
--     never fires: VPS's rows never appeared at all.
--
-- The adapter: when the controller is present with the pieces we need,
-- TooltipLib registers ONE Eury row provider (id "TooltipLib"). Its getRows
-- runs TooltipLib's active item providers for ctx.item against a RECORDING
-- layout (a Lua table shaped like ObjectTooltip.Layout — addItem() returns an
-- item that records setLabel / setValue / setValueRight / setProgress), so
-- every ctx:add* method runs its real code (separators, headers, sections,
-- wrapping) unchanged, and the recorded items convert to Eury rows:
--
--   label only        -> note row  (label + its colour)
--   label + value     -> value row (label, value, both colours)
--   setValueRight(n)  -> value row ("+n", green/red per highGood)
--   progress bar      -> value row ("Label  62%", value in the bar colour)
--   rules / dividers  -> dropped   (no rule primitive in Eury rows)
--   blank spacers     -> " " row   (a "" row draws nothing and takes no
--                                   height in Eury; " " keeps the gap)
--
-- BII then measures and draws those rows itself, inside the box it sizes.
-- Providers change nothing on their side. While the controller owns the
-- render, Hook.lua's item surface passes straight through (no DoTooltip
-- swap, no dress, no deferred staple, no Starlit wait), and only falls back
-- to its old paths for an item whose render provably bypassed the controller
-- (getRows never ran: TooltipLib._euryFired stays false).
--
-- Doctrine (docs/COMPATIBILITY.md §2.4): they own the card, we are a
-- well-behaved data provider in it. Scope matches the Starlit adapter, plus
-- the provider's own state phases: preTooltip -> callback -> cleanup run per
-- provider (cleanup always), postRender / textures / accent do not (Eury
-- rows have no drawing surface for them). replacesVanilla providers stand
-- down (the owner already drew the vanilla rows).
--
-- Guards: controller absent, or missing registerProvider / providers /
-- render / the row collection it calls getRows from -> nothing installs and
-- TooltipLib behaves exactly as before. Install is idempotent and runs on
-- OnGameStart, when both mods' files have loaded whatever their order.
-- ============================================================================

require "TooltipLib/Core"
require "TooltipLib/Helpers"

-- BII's item card lays a provider's rows out in its own ALIGNED layout (label
-- and value columns, like its weapon stats) only for providers whose id starts
-- "BetterItemInfo" (BII/TooltipItem.lua consumesRows); every other provider's
-- rows go to drawLineTooltipText, which puts each value 6 px after its label,
-- so two-column content (VPS's stats, the Stir) came out ragged. BII uses the
-- same route for another mod's rows itself (BII/Compatibility/GunsOfMarz.lua:
-- "BetterItemInfoGunsOfMarz", sectionGapBefore 9). An owner that does not
-- consume (Better Clothing Info) still draws them as lines.
local PROVIDER_ID = "BetterItemInfoTooltipLib"
-- After every BII row provider (theirs run 0..100; Guns of Marz is 90).
local PROVIDER_PRIORITY = 200
-- A floor for ctx:addText's wrap width: Eury measures the owner first, and a
-- 150px owner card would otherwise wrap lore at ~130px. Eury widens the card
-- to the widest row, so wrapping wider than the owner is safe.
local WRAP_FLOOR = 280

-- ----------------------------------------------------------------------------
-- Recording layout
-- ----------------------------------------------------------------------------
-- Fields live in a separate `rec` table so the catch-all __index (a no-op for
-- any LayoutItem method we don't model) can never answer for our own data.

local noop = function() end

local ItemMethods = {}
function ItemMethods:setLabel(text, r, g, b, a)
    local rec = rawget(self, "_rec")
    rec.label = text
    rec.lr, rec.lg, rec.lb, rec.la = r, g, b, a
    return self
end
function ItemMethods:setValue(text, r, g, b, a)
    local rec = rawget(self, "_rec")
    rec.value = text
    rec.vr, rec.vg, rec.vb, rec.va = r, g, b, a
    return self
end
function ItemMethods:setValueRight(n, highGood)
    local rec = rawget(self, "_rec")
    rec.right = n
    rec.highGood = highGood
    return self
end
function ItemMethods:setValueRightNoPlus(n)
    local rec = rawget(self, "_rec")
    rec.right = n
    rec.noPlus = true
    return self
end
function ItemMethods:setProgress(fraction, r, g, b, a)
    local rec = rawget(self, "_rec")
    rec.progress = fraction
    rec.br, rec.bg, rec.bb, rec.ba = r, g, b, a
    return self
end

local ItemMT = {
    __index = function(_, key)
        local m = ItemMethods[key]
        if m then return m end
        return noop
    end,
}

local function newRecordingLayout()
    local L = { records = {} }
    function L.addItem(self)
        local rec = {}
        self.records[#self.records + 1] = rec
        return setmetatable({ _rec = rec }, ItemMT)
    end
    -- Layout methods a provider might call on ctx.layout directly
    L.setMinLabelWidth = noop
    L.setMinValueWidth = noop
    L.render = function() return 0 end
    return L
end

-- ----------------------------------------------------------------------------
-- Record -> Eury row conversion
-- ----------------------------------------------------------------------------

local function num(v, default)
    if type(v) == "number" then return v end
    return default
end

local function isBlank(s)
    return s == nil or s == "" or (type(s) == "string" and not s:find("%S"))
end

local function pctText(fraction)
    local f = num(fraction, 0)
    return tostring(math.floor(f * 100 + 0.5)) .. "%"
end

--- Convert recorded layout items to Eury rows (appended to `out`).
--- Exposed as TooltipLib._euryRowsFromRecords for tests.
---@param records table[]
---@param out table[]? rows array to append to (created when nil)
---@return table[] out
local function rowsFromRecords(records, out)
    out = out or {}
    local C = TooltipLib.Colors
    for i = 1, #records do
        local rec = records[i]
        local label = rec.label ~= nil and tostring(rec.label) or ""
        local lr, lg, lb = num(rec.lr, 1), num(rec.lg, 1), num(rec.lb, 1)
        if rec.progress ~= nil then
            if isBlank(label) then
                -- divider / section rule: no rule primitive in Eury rows
            else
                -- the bar becomes its percentage, unless the label already
                -- spells it out ("  Power  25%": VPS writes it into the label)
                local pct = pctText(rec.progress)
                if label:find(pct, 1, true) then pct = "" end
                out[#out + 1] = {
                    label = label, value = pct,
                    labelR = lr, labelG = lg, labelB = lb,
                    valueR = num(rec.br, C.PROGRESS[1]), valueG = num(rec.bg, C.PROGRESS[2]),
                    valueB = num(rec.bb, C.PROGRESS[3]),
                }
            end
        elseif rec.value ~= nil and not isBlank(tostring(rec.value)) then
            out[#out + 1] = {
                label = label, value = tostring(rec.value),
                labelR = lr, labelG = lg, labelB = lb,
                valueR = num(rec.vr, 1), valueG = num(rec.vg, 1), valueB = num(rec.vb, 1),
            }
        elseif type(rec.right) == "number" then
            local n = rec.right
            local text = ((n > 0 and not rec.noPlus) and "+" or "") .. tostring(n)
            local good = (n >= 0) == (rec.highGood ~= false)
            local vc = (n == 0 and C.WHITE) or (good and C.GREEN) or C.RED
            out[#out + 1] = {
                label = label, value = text,
                labelR = lr, labelG = lg, labelB = lb,
                valueR = vc[1], valueG = vc[2], valueB = vc[3],
            }
        elseif isBlank(label) then
            -- spacer: Eury draws nothing for an empty row and gives it no
            -- height, so a single space keeps the gap. Never two in a row.
            local prev = out[#out]
            if prev and not prev._spacer then
                out[#out + 1] = { label = " ", value = "", _spacer = true }
            end
        elseif label:find("\n", 1, true) then
            -- one layout item spanning lines: one Eury row per line (Eury
            -- counts the lines for height, but DrawText draws only one)
            for line in (label .. "\n"):gmatch("([^\n]*)\n") do
                out[#out + 1] = {
                    label = line ~= "" and line or " ", value = "",
                    labelR = lr, labelG = lg, labelB = lb,
                }
            end
        else
            out[#out + 1] = {
                label = label, value = "",
                labelR = lr, labelG = lg, labelB = lb,
            }
        end
    end
    return out
end

local function trimSpacers(rows)
    while #rows > 0 and rows[#rows]._spacer do rows[#rows] = nil end
    while #rows > 0 and rows[1]._spacer do table.remove(rows, 1) end
    return rows
end

-- ----------------------------------------------------------------------------
-- The Eury row provider
-- ----------------------------------------------------------------------------

local function freshSectionState()
    return { list = {}, meta = {}, dressed = false }
end

--- getRows(ctx) for the Eury controller: TooltipLib's active item providers
--- for ctx.item, as Eury rows. nil when there is nothing to add (the
--- controller then falls back to its original render if no one else has rows).
local function collectRows(_, ectx)
    -- Evidence for Hook.lua: the controller dispatched to us this render.
    TooltipLib._euryFired = true
    local item = ectx and ectx.item
    if not item then return nil end
    if instanceof and not instanceof(item, "InventoryItem") then return nil end

    local providers = TooltipLib._getProvidersForTarget("item")
    if not providers or #providers == 0 then return nil end

    local detailHeld = false
    pcall(function() detailHeld = TooltipLib._readDetailKey() end)
    local active, hasHiddenDetail = TooltipLib._evaluateProviders(providers, detailHeld, item)
    if not active then return nil end

    local tooltip = ectx.tooltip
    local wrapHint = WRAP_FLOOR
    pcall(function()
        local w = tooltip and tooltip:getWidth()
        if type(w) == "number" and w > wrapHint then wrapHint = w end
    end)
    for i = 1, #active do
        local mw = active[i].minWidth
        if type(mw) == "number" and mw > wrapHint then wrapHint = mw end
    end

    local rows = {}
    local accentState = { color = nil }
    local prevAddedContent = false
    local ran = 0
    for i = 1, #active do
        local p = active[i]
        if not p.replacesVanilla and type(p.callback) == "function" then
            ran = ran + 1
            local layout = newRecordingLayout()
            local ctx = setmetatable({
                item = item,
                tooltip = tooltip,
                detail = detailHeld,
                surface = "item",
                layout = layout,
                helpers = TooltipLib.Helpers,
                _accentState = accentState,
                _sectionState = freshSectionState(),
                _wrapWidthHint = wrapHint,
                _needsSeparator = prevAddedContent and p.separator ~= false,
                _itemCount = 0,
                ornamented = false,
            }, TooltipLib._ContextMT)
            if p.preTooltip then
                local okP, errP = pcall(p.preTooltip, ctx)
                if not okP then
                    TooltipLib._log("Provider '" .. tostring(p.id) ..
                        "' preTooltip error under Eury adapter: " .. tostring(errP))
                end
            end
            local ok, err = pcall(p.callback, ctx)
            if not ok then
                TooltipLib._log("Provider '" .. tostring(p.id) ..
                    "' callback error under Eury adapter: " .. tostring(err))
                TooltipLib._recordError(p.id)
            else
                -- every dispatch path that records errors records successes
                -- too (the v1.5.2 cumulative-latch lesson)
                TooltipLib._recordSuccess(p.id)
                rowsFromRecords(layout.records, rows)
            end
            if p.cleanup then
                local okC, errC = pcall(p.cleanup, ctx)
                if not okC then
                    TooltipLib._log("Provider '" .. tostring(p.id) ..
                        "' cleanup error under Eury adapter: " .. tostring(errC))
                end
            end
            if (ctx._itemCount or 0) > 0 then prevAddedContent = true end
        end
    end
    if ran == 0 then return nil end

    trimSpacers(rows)
    if hasHiddenDetail and not detailHeld and #rows > 0 then
        local keyName = "Shift"
        pcall(function() keyName = getKeyName(TooltipLib._getDetailKeyCode()) or "Shift" end)
        rows[#rows + 1] = { label = "[" .. keyName .. "] Details", value = "",
            labelR = 0.55, labelG = 0.55, labelB = 0.55 }
    end
    if #rows == 0 then return nil end
    TooltipLib._diagBump("euryFills")
    return rows
end

local euryProvider = {
    priority = PROVIDER_PRIORITY,
    -- a section of its own inside BII's layout, spaced like its Guns of Marz section
    sectionGapBefore = 9,
    getRows = collectRows,
    -- same insets BII's own row providers use (BII/Utils.lua newProvider)
    getTextX = function(_, ctx)
        if ctx and ctx.ownerProvider and ctx.ownerProvider.id == "BetterClothingInfo" then return 5 end
        return 12
    end,
    getLinePadLeft = function(_, ctx)
        if ctx and ctx.ownerProvider and ctx.ownerProvider.id == "BetterClothingInfo" then return 5 end
        return 10
    end,
    getLinePadRight = function(_, ctx)
        if ctx and ctx.ownerProvider and ctx.ownerProvider.id == "BetterClothingInfo" then return 5 end
        return 10
    end,
}

--- The controller, when it has every piece the adapter relies on; else nil.
local function usableController()
    local C = rawget(_G, "EuryTooltipController")
    if type(C) ~= "table" then return nil end
    if type(C.registerProvider) ~= "function" then return nil end
    if type(C.providers) ~= "table" then return nil end
    if type(C.render) ~= "function" then return nil end
    -- the calls that reach getRows: without them our rows would never draw
    if type(C.collectRowGroups) ~= "function" and type(C.getProviderRows) ~= "function" then
        return nil
    end
    return C
end

--- Install: register our row provider with the controller. Idempotent; a
--- no-op (today's behaviour) when the controller is absent or incomplete.
local function installEuryAdapter()
    if TooltipLib._euryAdapter then return true end
    local C = usableController()
    if not C then return false end
    local ok, err = pcall(C.registerProvider, C, PROVIDER_ID, euryProvider)
    if not ok or C.providers[PROVIDER_ID] ~= euryProvider then
        TooltipLib._warn("EuryTooltipController found but registering with it failed (" ..
            tostring(err) .. ") — staying on the standard tooltip path.")
        return false
    end
    TooltipLib._euryAdapter = true
    TooltipLib._log("EuryTooltipController detected (Better Item Info / Better Clothing " ..
        "Info) — native tooltip integration active (provider content flows into its " ..
        "card as rows; load order no longer matters for it).")
    return true
end

Events.OnGameStart.Add(installEuryAdapter)

TooltipLib._installEuryAdapter = installEuryAdapter
TooltipLib._euryProvider = euryProvider              -- exposed for tests
TooltipLib._euryRowsFromRecords = rowsFromRecords    -- exposed for tests
TooltipLib._euryRecordingLayout = newRecordingLayout -- exposed for tests
TooltipLib._log("EuryAdapter module loaded")
