--[[
    © 2026 Warlord-Fox3. Tous droits réservés / All Rights Reserved.

    Toute réutilisation, modification, redistribution ou inclusion dans un
    modpack sans autorisation écrite préalable est strictement interdite.

    Any reuse, modification, redistribution, or inclusion in a modpack
    without prior written permission is strictly prohibited.
]]

--[[
    LPBCS_Render -- l'ancien rendu, gardé en repli.

    L'écriteau du mod est maintenant posé dans le monde par LPBCS_Sprites, et
    dessiné par le moteur : éclairé, trié en profondeur, masqué par ce qui
    passe devant. Ce fichier-ci dessine par-dessus le monde, ce qu'aucune de
    ces trois choses ne permet -- il ne sert plus que là où l'autre chemin ne
    peut pas fonctionner. Voir la note au-dessus de onCreatePlayer.

    Ce qui suit décrit ce rendu de repli.

    One zero-sized, click-through UI element per player, drawing every nearby
    sign in a single render pass over the whole screen. One element per sign
    would have been the obvious shape and the wrong one: a base with thirty
    named crates would put thirty UI elements through the manager every frame.

    Zero-sized is not a typo and the mouse handlers below are not filler --
    both are load-bearing, and the note above them says why.

    The sign is nailed to a vertical face of the container, in the isometric
    plane. It is not hung in the air facing the camera, and three things are
    what make the difference:

      - The projection is measured, not guessed. isoToScreenX/Y is affine in
        (x, y, z) -- the camera only ever translates it -- so a handful of
        calls at one tile give the screen vector of one world unit along X,
        along Y and along Z. That basis stands for every tile on screen, costs
        one measurement per frame, and stays correct at every zoom level and
        on any build with no magic pixel constant. The rest is arithmetic.
      - Nothing asks for the zoom, and nothing is sized in screen pixels. One
        measured storey is the yardstick every part of a sign is cut from, so
        a sign is the same size *relative to the crate* at any zoom and at any
        interface scale -- including the writing, which is scaled to a world
        height rather than drawn at whatever size the font atlas happens to be.
      - The plate is a quad with four independent corners, so it shears into
        the plane of the face instead of staying a screen rectangle. Its
        vertical edges stay vertical -- that is what a vertical face does in
        this projection -- while its top and bottom slope.
      - The board holds its shape in whole pixels, stepped off its own corner,
        so the writing never shifts about on the plank even though the plank
        itself moves smoothly with the world.

    Text is the one thing that cannot follow the shear: DrawText only takes a
    uniform zoom, so a glyph cannot be slanted. They are drawn one at a time
    along the sloping baseline instead, which gets the line of the text right
    and leaves each glyph upright. On a vertical face that is exactly right for
    the vertical strokes and half a glyph out for the horizontal ones, and at
    this size it reads as paint on wood.
]]

require "ISUI/ISUIElement"
require "LPBCS_Core"
require "LPBCS_Options"
require "LPBCS_Scan"

LPBCSSignOverlay = ISUIElement:derive("LPBCSSignOverlay")

local Options = LPBCS.Options
local Scan = LPBCS.Scan

--- Where the top of the sign sits when the object will not say how tall it
--- is, as a fraction of one storey above the floor. 0.62 is roughly the top
--- of a crate or a chest of drawers, which is where you would actually nail
--- a board.
local SIGN_HEIGHT = 0.62

--- Screen pixels for one storey at zoom 1. Used to read a surface height back
--- out of the sprite properties, and as the fallback when the z+1 measurement
--- comes back nonsense (the top floor of the world, say).
local FALLBACK_STOREY = 96

--- How tall a line of writing stands in the world, as a fraction of one
--- storey. This is the one number that sets how big a sign is, and it is
--- deliberately expressed in world units rather than in pixels of font: the
--- atlas the game hands back grows with the player's interface scale, so
--- anything derived from the font height alone would nail a poster to the
--- crate at 2x and a stamp at 1x. 0.2 is what UIFont.Small measures at a 1x
--- interface, so nobody's sign changes size when this arrives.
local TEXT_STOREYS = 19 / 96

--- How wide a sign may be, as a fraction of the face it is nailed to. A face
--- is only 36 pixels across at zoom 1 -- one tile edge seen side-on -- while a
--- name is 37 to 86 of them, so without this every sign would straddle the
--- corner onto the next face and stop looking nailed to anything. The face in
--- question is the object's own, not its tile's -- LPBCS_Scan measures how
--- much of the square the sprite really covers -- so this is a plain margin:
--- a little bare wood showing at each end is what reads as a board nailed on
--- rather than as cladding.
local MAX_SIGN_FACES = 0.88

--- How much of the object's own height a sign may cover. A crate face is 32
--- pixels tall and an unshrunk sign is 27 of them, so without this the board
--- claddings the whole face instead of sitting on it -- and a board as tall as
--- the crate reads as a billboard standing behind it, not a label.
local MAX_SIGN_COVERAGE = 0.5

--- ...and how tall it may be outright, as a fraction of one storey. Half of a
--- wardrobe would be a poster. Between the two, a sign ends up the size of a
--- thing someone nailed on, whatever it is nailed to.
local MAX_SIGN_STOREYS = 0.22

--- How far above the computed middle of the face the sign rides, as a fraction
--- of one storey. The computed middle is not the middle one sees: on the game's
--- wooden crate the silhouette is 70 frame pixels tall and stops 3 pixels short
--- of the bottom of the frame, while the geometry here works off the 64 that
--- `Surface` declares and off a floor at the frame's edge, so a board hung at
--- the strict half reads low. Only half of that gap is worth taking back --
--- the pixels at the top belong to the lid rim, which overhangs the face --
--- and the rest is settled by eye in the game. This is the three frame pixels
--- of LPBCS_Sprites in the units of this file: both renderers have to put the
--- sign in the same place.
local LIFT_STOREYS = 3 / 192

--- The floor on the shrinking those ask for. Below this the writing stops
--- being worth drawing at all, so a very long name is allowed to overhang the
--- face a little instead of becoming a smudge.
---
--- Low on purpose. Set at 0.45 it was the floor, not the face, that decided
--- the width of any name past eight characters, and the board hung off the
--- side of the crate. It can afford to be this low because the sign scales
--- with the world: this is seven pixels only at full zoom-out, where nothing
--- else is legible either, and it grows with the crate as you walk up to it.
local MIN_SHRINK = 0.38

--- What is left of a sign when somebody is standing in front of it. The
--- overlay is drawn after the world and cannot be hidden behind a character,
--- so the next best thing is to stop pretending: fade it down to a ghost and
--- the character reads as being in front, which is what is actually happening.
local OCCLUDED_ALPHA = 0.18

--- Roughly how much screen a character takes up, in tiles across and storeys
--- tall, for that test. It only has to be close: it decides a fade, not a
--- collision.
local BODY_TILES = 0.34
local BODY_STOREYS = 1.15

-- How far a sign fades at the edge of the radius, and how faint is too faint,
-- both live in LPBCS_Options now: this file is no longer the only thing that
-- draws a sign, and the two renderers have to agree about when one stops being
-- visible. See Options.alphaAt.

local TEXTURE_PATH = {
    plank   = "media/textures/LPBCS_SignPlank.png",
    paper   = "media/textures/LPBCS_SignPaper.png",
    painted = "media/textures/LPBCS_SignPainted.png",
}

-- Padding inside the sign, in pixels at zoom 1. The painted style is a wash
-- straight on the wood rather than a board, so it needs less room around it.
local PADDING = {
    plank   = { x = 7, y = 4 },
    paper   = { x = 6, y = 4 },
    painted = { x = 5, y = 2 },
}

local textures = {}

--- Cached both ways: a texture that failed to load is remembered as `false`
--- so a missing file costs one lookup, not one per sign per frame.
local function textureFor(style)
    local cached = textures[style]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end

    local path = TEXTURE_PATH[style]
    local texture = path and LPBCS.attempt(getTexture, path) or nil
    textures[style] = texture or false
    return texture
end

-- ------------------------------------------------------------- text metrics

--- Width of one character, memoised. The text is laid out a glyph at a time
--- (see the header), so the renderer asks for this a couple of dozen times per
--- sign per frame -- more calls into MeasureStringX than into the drawing
--- itself. The alphabet a base actually uses is a few dozen glyphs that never
--- change their metrics, so the cache never needs clearing.
---
--- Kahlua strings are Java strings: sub(i, i) is one character, not one byte,
--- and an accented letter survives the trip. Nothing here is safe for the
--- astral planes, and nothing in the fonts would draw them anyway.
local charWidths = {}

local function widthOf(font, char)
    local widths = charWidths[font]
    if not widths then
        widths = {}
        charWidths[font] = widths
    end

    local width = widths[char]
    if width == nil then
        local textManager = getTextManager()
        if char == " " then
            -- A lone space can measure 0: the string is trimmed before it is
            -- measured, which is what vanilla's DrawTextUntrimmed exists to
            -- work around. Ask for the difference between two words instead.
            width = textManager:MeasureStringX(font, "a a")
                - textManager:MeasureStringX(font, "aa")
            if width <= 0 then width = textManager:MeasureStringX(font, "n") end
        else
            width = textManager:MeasureStringX(font, char)
        end
        widths[char] = width
    end
    return width
end

--- Nearest whole pixel.
---
--- Load-bearing, not tidiness, and used for the sign's shape rather than for
--- where it sits. Text laid out a glyph at a time is fragile: each letter is
--- rounded where it lands, so at fractional spacings they cross their rounding
--- boundaries at different moments and the word visibly reflows as the camera
--- moves. Measuring every step in whole pixels from one corner makes the board
--- and its writing a rigid thing that can only translate.
---
--- The corner itself is deliberately NOT snapped, and that is checked rather
--- than assumed: IsoUtils.XToScreen is (x - y) * (32 * Core.tileScale) with no
--- rounding anywhere in it, and the camera offset its callers subtract is a
--- float. World positions are continuous, so a sign pinned to the pixel grid
--- would step against a crate that glides. Snap the shape, not the place.
local function snap(value)
    return math.floor(value + 0.5)
end

--- The sum of the per-character advances, which is not quite MeasureStringX of
--- the whole string. It is the sum that matters: the glyphs are placed one by
--- one from it, and a plate measured any other way would drift off what it is
--- supposed to be holding. (The shipped fonts carry no kerning pairs, so the
--- two agree in practice -- this is about staying agreed under a font that
--- does.)
local function measure(font, text)
    local total = 0
    for index = 1, #text do
        total = total + widthOf(font, text:sub(index, index))
    end
    return total
end

-- ------------------------------------------------------------------- draw

function LPBCSSignOverlay:viewport()
    if getNumActivePlayers() > 1 then
        local left = getPlayerScreenLeft(self.player)
        local top = getPlayerScreenTop(self.player)
        return left, top,
            left + getPlayerScreenWidth(self.player),
            top + getPlayerScreenHeight(self.player)
    end
    return 0, 0, getCore():getScreenWidth(), getCore():getScreenHeight()
end

-- There is deliberately no prerender(). This element is never resized to the
-- screen: :render() works in absolute screen coordinates and :viewport() gets
-- the screen bounds from getCore(), so the element's own rect is only ever the
-- mouse hit-box -- and it has to stay empty. See the note above the mouse
-- handlers.

--- The screen vectors of one world unit along each axis, measured at the
--- player's own tile and good for every tile on screen -- isoToScreenX/Y is
--- affine in (x, y, z), the camera only translates it. Filled into a table
--- owned by the element rather than a fresh one, because this runs every
--- frame and the contents live no longer than the pass that reads them.
---
--- Returns nil when there is nothing to measure against, which is the caller's
--- cue to draw nothing at all.
function LPBCSSignOverlay:measureIso(playerObj)
    local square = playerObj:getSquare()
    if not square then return nil end

    local bx, by, bz = square:getX(), square:getY(), square:getZ()
    local x0 = isoToScreenX(self.player, bx, by, bz)
    local y0 = isoToScreenY(self.player, bx, by, bz)

    local storey = y0 - isoToScreenY(self.player, bx, by, bz + 1)
    if storey <= 1 then
        -- Top floor of the world: there is no z+1 to project. The only place
        -- left where the zoom has to be asked for instead of measured.
        local zoom = getCore():getZoom(self.player)
        if type(zoom) ~= "number" or zoom <= 0 then zoom = 1 end
        storey = FALLBACK_STOREY / zoom
    end

    -- Snapped, and for the same reason the corners are: these are measured
    -- fresh every frame from wherever the player happens to be standing, and
    -- a projection that quantises can hand back a value a pixel either side of
    -- the truth. Left raw, that pixel would travel into the scale, and from
    -- there into the size of every sign on screen, several times a second.
    -- Rounded, they change only when the zoom does.
    local iso = self.iso
    iso.ux = snap(isoToScreenX(self.player, bx + 1, by, bz) - x0)
    iso.uy = snap(isoToScreenY(self.player, bx + 1, by, bz) - y0)
    iso.vx = snap(isoToScreenX(self.player, bx, by + 1, bz) - x0)
    iso.vy = snap(isoToScreenY(self.player, bx, by + 1, bz) - y0)
    -- Screen pixels per storey: the yardstick every size in a sign is cut
    -- from, and the zoom in disguise -- measured, never asked for. Rounded for
    -- the reason just above, and it matters most here: this one number sets
    -- how big every sign on screen is.
    iso.storey = snap(storey)
    return iso
end

--- How high up the object the sign is nailed, in storeys.
--- getSurfaceOffsetNoTable() is the height the game itself drops items at when
--- you put something down on top of the furniture -- in pixels at zoom 1,
--- which vanilla divides by 96 the same way (ISPlace3DItemCursor). So the sign
--- lands on the lid of a crate and near the top of a wardrobe without this
--- file knowing what either of them is. Anything that will not answer, or
--- answers absurdly, falls back to crate height.
local function topOf(object)
    local offset = LPBCS.get(object, "getSurfaceOffsetNoTable", nil)
    if type(offset) ~= "number" then return SIGN_HEIGHT end

    local storeys = offset / FALLBACK_STOREY
    if storeys <= 0.05 or storeys > 1.8 then return SIGN_HEIGHT end
    return storeys
end

--- The face a sign hangs on: the screen vector of one whole tile along its
--- reading direction, the share of that the object actually occupies, and the
--- world point at the middle of the part it occupies.
---
---   east  (x+1): the right-hand half of the tile on screen. Reading runs
---                against +Y, which is up and to the right.
---   south (y+1): the left-hand half. Reading runs along +X, down and right.
---
--- Both faces are measured out from the near corner of the tile, (x+1, y+1) --
--- the one nearest the camera -- because that is the corner the furniture is
--- built out from. An extent of one is the whole tile; the crate is 0.84 of
--- it, and half of the difference is what stops the board hanging off the
--- side. Which face it is, and how far the sprite reaches, were both settled
--- by the sweep in LPBCS_Scan, not here.
local function faceOf(entry, iso)
    local extent = entry.extent or 1
    if entry.face == "south" then
        return iso.ux, iso.uy, extent, entry.x + 1 - extent / 2, entry.y + 1
    end
    return -iso.vx, -iso.vy, extent, entry.x + 1, entry.y + 1 - extent / 2
end

--- Whether the four-corner texture draw is available. Everything else this
--- file calls has been in the API since build 41; drawTextureAllPoint reaches
--- a twelve-argument Java overload that has not. Probing it once and
--- remembering costs nothing and keeps a missing overload from throwing once
--- per sign per frame for as long as the game is running -- the sign loses its
--- plank and keeps its shape, which is the same bargain textureFor strikes for
--- a missing file.
local quadDraw = true

function LPBCSSignOverlay:drawPlate(texture, tlx, tly, trx, try, brx, bry, blx, bly, alpha)
    if texture and quadDraw then
        -- Corners go top-left, top-right, bottom-right, bottom-left, and the
        -- colour comes r, g, b, a -- drawTextureScaled takes a, r, g, b.
        if LPBCS.invoke(self, "drawTextureAllPoint", texture,
            tlx, tly, trx, try, brx, bry, blx, bly, 1, 1, 1, alpha) then
            return
        end

        quadDraw = false
        LPBCS.log("Render", "drawTextureAllPoint refused; signs fall back to plain plates")
    end

    -- No artwork, or no way to put it on screen: a plain plate still beats
    -- text floating unreadably over a lit wall. drawPolygon takes a nil
    -- texture for exactly this, and takes the same four corners.
    self:drawPolygon(nil, tlx, tly, trx, try, brx, bry, blx, bly,
        0.07, 0.06, 0.05, alpha * 0.75)
end

function LPBCSSignOverlay:drawSign(entry, iso, font, lineHeight, alpha, left, top, right, bottom,
                                   bodyX, bodyY, bodyHalf, bodyTall, bodyDepth)
    local label = entry.label
    local pad = PADDING[label.style] or PADDING.plank

    local faceX, faceY, extent, worldX, worldY = faceOf(entry, iso)
    local tileFace = math.sqrt(faceX * faceX + faceY * faceY)
    if tileFace <= 0 then return end

    -- Unit vector of the reading direction: every horizontal step, in the
    -- plate and in the writing, is taken along this. It comes off the whole
    -- tile, since the direction of a face does not change with how much of it
    -- the furniture uses -- only the length available does.
    local ex, ey = faceX / tileFace, faceY / tileFace
    local faceLength = tileFace * extent

    -- Not named `top`: that is the viewport edge this function is handed.
    local surface = topOf(entry.object)

    local storeyPx = iso.storey
    local faceHeight = surface * storeyPx

    -- Pixels of font to pixels of screen, chosen so that a line of writing
    -- comes out TEXT_STOREYS of a storey tall whatever the interface scale
    -- handed us for a font.
    local scale = TEXT_STOREYS * storeyPx / lineHeight
    local width = (measure(font, label.text) + pad.x * 2) * scale
    local height = (lineHeight + pad.y * 2) * scale
    if width <= 0 or height <= 0 then return end

    -- Every way a sign can outgrow what it is nailed to, settled in one go so
    -- that shrinking for one never breaks another: wider than the face, taller
    -- than a fraction of the object, or taller than a board has any business
    -- being. The writing goes down with the board -- a name has to stay inside
    -- its plank -- and MIN_SHRINK is where that stops, because a name too small
    -- to read helps nobody.
    local shrink = math.min(1,
        faceLength * MAX_SIGN_FACES / width,
        faceHeight * MAX_SIGN_COVERAGE / height,
        storeyPx * MAX_SIGN_STOREYS / height)

    if shrink < 1 then
        if shrink < MIN_SHRINK then shrink = MIN_SHRINK end
        scale, width, height = scale * shrink, width * shrink, height * shrink
    end

    local anchorX = isoToScreenX(self.player, worldX, worldY, entry.z + surface)
    local anchorY = isoToScreenY(self.player, worldX, worldY, entry.z + surface)

    -- Centred on the face rather than hung off the top edge of it. Flush with
    -- the lid looks like the board is holding the crate shut; centred looks
    -- like someone put a label where a label goes, and it puts the sign at
    -- chest height on a wardrobe instead of up by the ceiling.
    --
    -- LIFT_STOREYS then takes it a touch higher still, and the clamp below is
    -- what keeps that honest: on a short face the centre is already at the top
    -- edge, and rising further would lift the board clear of the furniture.
    local inset = (faceHeight - height) / 2 - LIFT_STOREYS * storeyPx
    if inset < 0 then inset = 0 end
    anchorY = anchorY + inset

    -- The world Z axis projects straight down the screen, so the bottom
    -- corners sit directly under the top ones whichever way the face turns.
    -- That is the whole shear: the top edge slopes, the sides stay upright.
    --
    -- The three other corners are whole-pixel steps from the first, rather
    -- than each being rounded on its own: the board then keeps its exact shape
    -- from frame to frame and only ever translates. The first corner is left
    -- exactly where it falls, because the world moves smoothly between ticks
    -- and a sign rounded to the pixel grid would step against it -- the shape
    -- is what has to be stable, not the position.
    local runX, runY = snap(ex * width), snap(ey * width)
    local rise = snap(height)

    local tlx, tly = anchorX - ex * width / 2, anchorY - ey * width / 2
    local trx, try = tlx + runX, tly + runY
    local blx, bly = tlx, tly + rise
    local brx, bry = trx, try + rise

    if math.max(tlx, trx) < left or math.min(tlx, trx) > right then return end
    if math.max(bly, bry) < top or math.min(tly, try) > bottom then return end

    -- Somebody standing between the camera and the board. Depth in this
    -- projection runs along x + y, so a character with a larger sum is in
    -- front of the sign and the world would have drawn them over it; this
    -- overlay cannot be drawn over, so it gets out of the way instead.
    if bodyDepth and bodyDepth > worldX + worldY then
        if bodyX + bodyHalf > math.min(tlx, trx) and bodyX - bodyHalf < math.max(tlx, trx)
            and bodyY > math.min(tly, try) and bodyY - bodyTall < math.max(bly, bry) then
            alpha = alpha * OCCLUDED_ALPHA
            if Options.tooFaint(alpha) then return end
        end
    end

    self:drawPlate(textureFor(label.style),
        tlx, tly, trx, try, brx, bry, blx, bly, alpha)

    -- Inside the padding, then one glyph at a time along the slope. The
    -- horizontal inset runs along the face; the vertical one is straight down,
    -- like the sides of the plate. Every step is a whole pixel measured from
    -- the board's own corner, so the letters hold their places on the plank
    -- rather than each crossing its own rounding boundary as the camera moves.
    local originX = tlx + snap(ex * pad.x * scale)
    local originY = tly + snap(ey * pad.x * scale) + snap(pad.y * scale)

    local cursor = 0
    for index = 1, #label.text do
        local char = label.text:sub(index, index)
        if char ~= " " then
            local along = cursor * scale
            self:drawTextZoomed(char,
                originX + snap(ex * along), originY + snap(ey * along),
                scale, label.r, label.g, label.b, alpha, font)
        end
        cursor = cursor + widthOf(font, char)
    end
end

function LPBCSSignOverlay:render()
    if not Options.enabled() then return end

    local playerObj = getSpecificPlayer(self.player)
    if not playerObj or playerObj:isDead() then return end
    if Options.hideWhenLootOpen() and Options.lootWindowOpen(self.player) then return end

    local entries = Scan.entries(self.player)
    if #entries == 0 then return end

    local iso = self:measureIso(playerObj)
    if not iso then return end

    local font = UIFont.Small
    local lineHeight = getTextManager():getFontHeight(font)

    -- Read once for the whole pass and handed to Options.alphaAt per sign:
    -- each of these is a pcall into the options page.
    local opacity = Options.opacity()
    local radius = Options.radius()
    local px, py = playerObj:getX(), playerObj:getY()
    local left, top, right, bottom = self:viewport()

    -- Where the player is standing on screen, for the test that fades a sign
    -- they are standing in front of. Their feet, and how far the body reaches
    -- from there.
    local bodyX = isoToScreenX(self.player, px, py, playerObj:getZ())
    local bodyY = isoToScreenY(self.player, px, py, playerObj:getZ())
    local bodyHalf = math.abs(iso.ux - iso.vx) * BODY_TILES
    local bodyTall = iso.storey * BODY_STOREYS
    local bodyDepth = px + py

    for index = 1, #entries do
        local entry = entries[index]
        local centreX, centreY = entry.x + 0.5, entry.y + 0.5

        local dx, dy = centreX - px, centreY - py
        local distance = math.sqrt(dx * dx + dy * dy)

        -- Cheapest test first, then the one that needs no Java call, then the
        -- line of sight. The alpha is zero past the radius, so the distance
        -- check the loop used to make is folded into it.
        local inWorld = LPBCS.Sprites ~= nil and LPBCS.Sprites.isPlaced(entry.object)
        local alpha = Options.alphaAt(distance, radius, opacity)

        if not inWorld and not Options.tooFaint(alpha)
            and entry.square:isCanSee(self.player) then
            self:drawSign(entry, iso, font, lineHeight, alpha,
                left, top, right, bottom,
                bodyX, bodyY, bodyHalf, bodyTall, bodyDepth)
        end
    end
end

-- ------------------------------------------------------------------ mouse

--[[
    This overlay must be invisible to the mouse, and the engine gives it three
    separate ways to fail at that. Two of them are answered here, the third by
    the element being zero-sized -- see :new().

    1. setConsumeMouseEvents(false), which is what :new() asks for. It covers
       left click, wheel and move: UIElement.onMouseDown/onMouseUp/onMouseWheel
       /onMouseMove treat a nil return from Lua as "consumed" only when the
       flag is set.

    2. Right click, which that flag does NOT cover. UIElement.onRightMouseDown
       and onRightMouseUp never read it: a nil return from Lua means
       "consumed", full stop. ISUIElement's own onRightMouseUp is an empty
       function, so a screen-sized element silently eats every right-click in
       the world and no context menu ever opens -- with no error anywhere,
       because as far as the game is concerned a UI element handled the click.
       Hence the explicit `return false` below, which is exactly what vanilla's
       own click-through overlay does (ISToolTip:onRightMouseUp).

    3. UIElement.isPointOver, which no amount of returning false can reach: it
       is Java-only, never dispatched to the Lua table, so it cannot be
       overridden from here. For a root element it answers "is this point in
       my rect, and is no element ABOVE me in UIManager.UI over it too?" --
       and it never looks at consumeMouseEvents on that path. A screen-sized
       root element therefore makes isPointOver return false for every root
       element beneath it, and UIManager's wheel loop skips any element whose
       isPointOver is false. That is a scroll wheel that stops working in the
       inventory and zooms the world instead. The only way out is for the
       element not to contain the point, so it has no size at all.

    Do not delete these handlers because the element "obviously" has no mouse
    behaviour: having none is exactly the problem.
]]

function LPBCSSignOverlay:onMouseDown(x, y)
    return false
end

function LPBCSSignOverlay:onMouseUp(x, y)
    return false
end

function LPBCSSignOverlay:onRightMouseDown(x, y)
    return false
end

function LPBCSSignOverlay:onRightMouseUp(x, y)
    return false
end

function LPBCSSignOverlay:onMouseWheel(del)
    return false
end

-- ------------------------------------------------------------- lifecycle

function LPBCSSignOverlay:new(playerNum)
    -- Zero-sized on purpose -- point 3 of the note above the mouse handlers.
    -- Drawing is unaffected: UIElement's draw calls offset by the element's
    -- absolute position, which is 0,0 here, and clip to nothing, so the whole
    -- screen stays reachable from a rect that covers none of it. A root
    -- element is also rendered without any size check, so there is nothing
    -- else holding this together.
    local o = ISUIElement:new(0, 0, 0, 0)
    setmetatable(o, self)
    self.__index = self
    o.player = playerNum
    o.anchorLeft = true
    o.anchorTop = true

    -- The isometric basis, remeasured at the top of every render pass. It
    -- lives here so that measuring it does not allocate a table per frame.
    o.iso = { ux = 0, uy = 0, vx = 0, vy = 0, storey = FALLBACK_STOREY }

    -- anchorRight and anchorBottom stay false. UIElement.resize() would
    -- otherwise stretch the element back across the screen on a resolution
    -- change and quietly reintroduce the whole problem.
    o.anchorRight = false
    o.anchorBottom = false

    -- ISUIElement:new defaults this to true; instantiate() copies it onto the
    -- Java object. Setting it here is the supported way in, and it has to be
    -- done before instantiate() to take effect.
    o.wantMouseEvents = false

    return o
end

LPBCSSignOverlay.instances = LPBCSSignOverlay.instances or {}

local function removeOverlay(playerNum)
    local overlay = LPBCSSignOverlay.instances[playerNum]
    if not overlay then return end
    LPBCS.invoke(overlay, "removeFromUIManager")
    LPBCSSignOverlay.instances[playerNum] = nil
end

local function createOverlay(playerNum)
    removeOverlay(playerNum)

    local overlay = LPBCSSignOverlay:new(playerNum)
    overlay:initialise()
    overlay:instantiate()

    -- Belt and braces: :new() asks instantiate() for this, and the mouse
    -- handlers above cover the right-click path the flag does not reach.
    if overlay.javaObject then
        LPBCS.invoke(overlay.javaObject, "setConsumeMouseEvents", false)
    end

    overlay:addToUIManager()
    LPBCSSignOverlay.instances[playerNum] = overlay
end

--- Ce fichier n'est plus le rendu du mod, c'est son repli.
---
--- L'écriteau est maintenant posé dans le monde par LPBCS_Sprites : le moteur
--- l'éclaire, le trie en profondeur, et un personnage qui passe devant le
--- masque. Rien de tout cela n'est possible depuis l'interface, qui est
--- dessinée après le monde et ne peut donc qu'être par-dessus.
---
--- Le calque est néanmoins toujours installé, et c'est délibéré : il ne
--- dessine que les écriteaux que la voie monde n'a PAS pris (voir le test sur
--- Sprites.isPlaced dans render). Décider une fois pour toutes au chargement
--- du joueur ne marchait pas -- à cet instant le jeu ne sait pas encore
--- charger une texture, la voie monde se déclarait indisponible et le mod
--- restait sur ce repli pour toute la session. Ici, chaque écriteau bascule
--- de lui-même dès que l'autre chemin réussit à le prendre.
local function onCreatePlayer(playerNum)
    createOverlay(playerNum)
    Scan.invalidate(playerNum)
end

local function onPlayerDeath(playerObj)
    if not playerObj then return end
    local playerNum = LPBCS.get(playerObj, "getPlayerNum", nil)
    if playerNum ~= nil then removeOverlay(playerNum) end
end

Events.OnCreatePlayer.Add(onCreatePlayer)
Events.OnPlayerDeath.Add(onPlayerDeath)

return LPBCSSignOverlay
