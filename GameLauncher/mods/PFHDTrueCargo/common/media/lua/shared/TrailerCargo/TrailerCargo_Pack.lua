-- TrailerCargo_Pack: WHERE trunk items sit on the bed. Pure Lua.
-- An entry is { m, x, z, yaw, ids }: one model or a pile of it, ids bottom
-- to top, x/z the model ORIGIN in part units.
-- Bottom-left fill in (x, u), u growing away from the hitch.
---@class (partial) TrailerCargo
---@field Pack TrailerCargo.Pack
TrailerCargo = rawget(_G, "TrailerCargo") or {}
TrailerCargo.Bed = TrailerCargo.Bed or {}

---@class TrailerCargo.Pack
local P = TrailerCargo.Pack or {}
TrailerCargo.Pack = P

local B = TrailerCargo.Bed
local abs, floor, HUGE = math.abs, math.floor, math.huge

-- y (lift, part units), rx, rz (lean, degrees) are the player's; the
-- packer never writes them.
---@class TrailerCargo.Entry
---@field m string
---@field x number
---@field z number
---@field yaw number
---@field ids number[]
---@field free boolean|nil  split from a pile by the player: nothing joins it
---@field y number|nil
---@field rx number|nil
---@field rz number|nil

---@class TrailerCargo.Layout
---@field v integer
---@field rev integer
---@field spilled boolean
---@field list TrailerCargo.Entry[]
---@field hidden table<number, boolean>|nil  ids the player hid from the bed (the trunk menu)
---@field shown table<number, boolean>|nil  ids the player showed, over the size classes
---@field parked table<number, TrailerCargo.Entry>|nil  where a hidden item was drawn, for its Show

---@class TrailerCargo.PackCtx
---@field bounds table<string, TrailerCargo.BoundsEntry>
---@field capOf fun(m: string): integer|nil  layer cap, nil when it never stacks
---@field ms number
---@field rng fun(): number
---@field maxNew integer
---@field floorFirst table<string, boolean>|nil  defaults to TrailerCargo.FloorFirst
---@field auto boolean|nil  false: Free mode, scatter instead of pack
---@field noRepack boolean|nil  skip the full-repack fallback (the caller knows it failed for this very trunk already)

-- The layout format; an older one is emptied by Trunk.layoutOf.
P.LAYOUT_V = 2

---@return TrailerCargo.Layout
function P.newLayout()
  return { v = P.LAYOUT_V, rev = 0, spilled = false, list = {} }
end

---@return TrailerCargo.Entry|nil, integer|nil
function P.entryOf(layout, id)
  local list = layout.list
  for i = 1, #list do
    local ids = list[i].ids
    for j = 1, #ids do
      if ids[j] == id then return list[i], i end
    end
  end
  return nil, nil
end

-- trunk: array of { id, m }. removed: ids in the layout that are gone or
-- changed model. added: trunk items not placed (a changed one re-enters).
---@param layout TrailerCargo.Layout
---@param trunk { id: number, m: string }[]
---@return table<number, boolean> removed, integer nRemoved, { id: number, m: string }[] added
function P.diff(layout, trunk)
  local inTrunk = {}
  for i = 1, #trunk do inTrunk[trunk[i].id] = trunk[i].m end
  local placed, removed, nRemoved = {}, {}, 0
  local list = layout.list
  for i = 1, #list do
    local e = list[i]
    for j = 1, #e.ids do
      local id = e.ids[j]
      placed[id] = true
      if inTrunk[id] ~= e.m then
        removed[id] = true
        nRemoved = nRemoved + 1
      end
    end
  end
  local added = {}
  for i = 1, #trunk do
    local t = trunk[i]
    if not placed[t.id] or removed[t.id] then added[#added + 1] = t end
  end
  return removed, nRemoved, added
end

---@param layout TrailerCargo.Layout
---@param removed table<number, boolean>
---@return boolean changed
function P.prune(layout, removed)
  local list, changed, w = layout.list, false, 0
  for i = 1, #list do
    local e = list[i]
    local kept, k = {}, 0
    for j = 1, #e.ids do
      if removed[e.ids[j]] then changed = true else k = k + 1; kept[k] = e.ids[j] end
    end
    e.ids = kept
    if k > 0 then w = w + 1; list[w] = e end
  end
  for i = #list, w + 1, -1 do list[i] = nil end
  return changed
end

-- Trims every packer pile to its model's current cap, off the top. Free
-- piles are left alone.
---@param layout TrailerCargo.Layout
---@param ctx TrailerCargo.PackCtx
---@return number[] ids  taken off, to be placed again
function P.trimPiles(layout, ctx)
  local out = {}
  local list = layout.list
  for i = 1, #list do
    local e = list[i]
    if not e.free then
      local cap = ctx.capOf(e.m)
      local limit = (cap and cap > 1) and cap or 1
      for j = #e.ids, limit + 1, -1 do
        out[#out + 1] = e.ids[j]
        e.ids[j] = nil
      end
    end
  end
  return out
end

local function rectOf(e, ctx)
  local hx, hz, ox, oz = B.footprint(ctx.bounds, e.m, ctx.ms)
  return B.rect(e.x, e.z, e.yaw, hx, hz, ox, oz)
end

---@param layout TrailerCargo.Layout
---@param ctx TrailerCargo.PackCtx
---@return TrailerCargo.Rect[]
function P.rects(layout, ctx)
  local out, list = {}, layout.list
  for i = 1, #list do out[i] = rectOf(list[i], ctx) end
  return out
end

-- (x, u) frame: u = 0 at the hitch end, growing away from it.
local function uOf(bed, z)
  if bed.hitch > 0 then return bed.z[2] - z end
  return z - bed.z[1]
end
local function zOf(bed, u)
  if bed.hitch > 0 then return bed.z[2] - u end
  return bed.z[1] + u
end

-- The origin that puts a model's AABB min corner at (cx, cu), or nil.
local function poseAt(bed, rects, hx, hz, ox, oz, yaw, cx, cu)
  local probe = B.rect(0, 0, yaw, hx, hz, ox, oz)
  local rx = (probe.maxx - probe.minx) / 2
  local rz = (probe.maxz - probe.minz) / 2
  local x = cx + rx - (probe.minx + rx)
  local z = zOf(bed, cu + rz) - (probe.minz + rz)
  local r = B.rect(x, z, yaw, hx, hz, ox, oz)
  if B.fits(bed, rects, r, nil) then return x, z, r end
  return nil
end

-- The gap between packed items in part units: the same on the ground
-- whatever the modelScale.
local function gapOf(ctx)
  return B.GAP_TILES / ctx.ms
end

-- Beside and beyond every placed rect or hump.
local function candidates(bed, rects, gap)
  local c = { { bed.x[1], 0 } }
  local function around(r)
    local u1, u2 = uOf(bed, r.minz), uOf(bed, r.maxz)
    if u1 > u2 then u1, u2 = u2, u1 end
    c[#c + 1] = { r.maxx + gap, u1 }
    c[#c + 1] = { math.max(r.minx, bed.x[1]), u2 + gap }
  end
  for i = 1, #rects do around(rects[i]) end
  local humps = B.humpRects(bed)
  for i = 1, #humps do around(humps[i]) end
  return c
end

-- Best spot for one footprint: lowest u, then lowest x.
---@return number|nil x, number|nil z, number|nil yaw, TrailerCargo.Rect|nil rect
local function place(bed, rects, hx, hz, ox, oz, yaws, gap)
  local cands = candidates(bed, rects, gap)
  local bx, bz, byaw, br
  local bu, bxx = HUGE, HUGE
  for i = 1, #cands do
    local cand = cands[i]
    for k = 1, #yaws do
      local x, z, r = poseAt(bed, rects, hx, hz, ox, oz, yaws[k], cand[1], cand[2])
      if x and z and r then
        local u = bed.hitch > 0 and uOf(bed, r.maxz) or uOf(bed, r.minz)
        if u < bu - 1e-6 or (abs(u - bu) <= 1e-6 and r.minx < bxx) then
          bx, bz, byaw, br, bu, bxx = x, z, yaws[k], r, u, r.minx
        end
      end
    end
  end
  return bx, bz, byaw, br
end

-- The jitter a packer entry's bottom layer is DRAWN with, from its id;
-- never stored in the layout. A free entry is drawn exactly where it is.
---@param id number
---@return number jx, number jz, number jyaw
function P.placeJitter(id)
  local a = id % 11 - 5
  local b = floor(id / 11) % 11 - 5
  local c = floor(id / 121) % 13 - 6
  return a * 0.004, b * 0.004, c * 1.0
end

local YAWS_ANY = { 0, 90 }

-- A pile of the model with room left, or nil; never a free one. `even`:
-- the pile with the fewest layers (floor-first models).
---@param list TrailerCargo.Entry[]
---@param m string
---@param cap integer
---@param even boolean
---@return TrailerCargo.Entry|nil
local function pileFor(list, m, cap, even)
  local best
  for j = 1, #list do
    local e = list[j]
    if e.m == m and not e.free and #e.ids < cap then
      if not even then return e end
      if not best or #e.ids < #best.ids then best = e end
    end
  end
  return best
end

-- Square tiles of footprint one kilogram stands for: weight is a size
-- proxy when a model has no bounds row.
P.WEIGHT_AREA = 0.05

-- An item's size for packing order and for judging a repack: the larger
-- of its footprint area (part units squared) and its weight's equivalent.
---@param m string
---@param w number|nil
---@param ctx TrailerCargo.PackCtx
---@return number
function P.sizeOf(m, w, ctx)
  local hx, hz = B.footprint(ctx.bounds, m, ctx.ms)
  return math.max(hx * hz, (w or 0) * P.WEIGHT_AREA / (ctx.ms * ctx.ms))
end

-- Size per item where a pile ranks as one footprint carrying all its
-- layers' weight. Items group by model in cap-sized runs.
---@param items { id: number, m: string, w: number|nil }[]
---@param ctx TrailerCargo.PackCtx
---@return number[] sizes  one per item, its group's size
---@return number[] groupSizes  one per group
function P.pileSizes(items, ctx)
  local sizes, groupSizes = {}, {}
  ---@type table<string, { m: string, members: integer[], w: number }>  the pile still taking members, per model
  local open = {}
  ---@type { m: string, members: integer[], w: number }[]
  local groups = {}
  for i = 1, #items do
    local it = items[i]
    local cap = ctx.capOf(it.m)
    if cap and cap > 1 then
      local g = open[it.m]
      if not g or #g.members >= cap then
        g = { m = it.m, members = {}, w = 0.0 }
        open[it.m] = g
        groups[#groups + 1] = g
      end
      g.members[#g.members + 1] = i
      g.w = g.w + (it.w or 0)
    else
      groups[#groups + 1] = { m = it.m, members = { i }, w = it.w or 0.0 }
    end
  end
  for k = 1, #groups do
    local g = groups[k]
    local v = P.sizeOf(g.m, g.w, ctx)
    groupSizes[k] = v
    for j = 1, #g.members do sizes[g.members[j]] = v end
  end
  return sizes, groupSizes
end

-- Largest first (P.pileSizes), ties to the heavier; floor-first models
-- last. Selection, up to maxNew.
---@param added { id: number, m: string, w: number|nil }[]
---@param ctx TrailerCargo.PackCtx
---@param ff table<string, boolean>
---@return { id: number, m: string }[]
local function ordered(added, ctx, ff)
  local n = #added
  local last, used = {}, {}
  local area = P.pileSizes(added, ctx)
  for i = 1, n do
    last[i] = ff[added[i].m] == true
  end
  local out = {}
  for _ = 1, math.min(n, ctx.maxNew) do
    local best = 0
    for i = 1, n do
      if not used[i] then
        if best == 0 then best = i
        elseif last[i] ~= last[best] then
          if not last[i] then best = i end
        elseif abs(area[i] - area[best]) > 1e-9 then
          if area[i] > area[best] then best = i end
        elseif (added[i].w or 0) > (added[best].w or 0) then best = i end
      end
    end
    if best == 0 then break end
    used[best] = true
    out[#out + 1] = added[best]
  end
  return out
end

-- Pack up to ctx.maxNew of `added` into the layout. Returns the number of
-- layers placed and the ids that fit nowhere.
---@param layout TrailerCargo.Layout
---@param added { id: number, m: string }[]
---@param ctx TrailerCargo.PackCtx
---@return integer packed, number[] unfit
function P.pack(bed, layout, added, ctx)
  local list = layout.list
  local rects = P.rects(layout, ctx)
  local packed, unfit = 0, {}
  local ff = ctx.floorFirst or TrailerCargo.FloorFirst or {}
  local items = ordered(added, ctx, ff)
  for i = 1, #items do
    local it = items[i]
    local cap = ctx.capOf(it.m)
    local first = ff[it.m] == true
    local joined = false
    -- a floor-first model piles only when the floor is full
    local pile = cap and not first and pileFor(list, it.m, cap, false)
    if pile then
      pile.ids[#pile.ids + 1] = it.id
      joined = true
    end
    if not joined then
      local hx, hz, ox, oz = B.footprint(ctx.bounds, it.m, ctx.ms)
      local isLong = B.isLong(hx, hz)
      local yaws = first and { B.acrossYaw(hx, hz) } or isLong and { B.lengthwiseYaw(hx, hz) } or YAWS_ANY
      local x, z, yaw, r = place(bed, rects, hx, hz, ox, oz, yaws, gapOf(ctx))
      if x and z and yaw and r then
        list[#list + 1] = { m = it.m, x = x, z = z, yaw = yaw, ids = { it.id } }
        rects[#rects + 1] = r
        joined = true
      else
        pile = cap and first and pileFor(list, it.m, cap, true)
        if pile then
          pile.ids[#pile.ids + 1] = it.id
          joined = true
        else
          unfit[#unfit + 1] = it.id
        end
      end
    end
    if joined then packed = packed + 1 end
  end
  return packed, unfit
end

-- Floor-first piles give their top layers back to the floor while it has
-- room, tallest first. Free or lifted piles never move.
---@param layout TrailerCargo.Layout
---@param ctx TrailerCargo.PackCtx
---@return boolean changed
function P.spread(bed, layout, ctx)
  local ff = ctx.floorFirst or TrailerCargo.FloorFirst or {}
  local rects, stuck, changed = P.rects(layout, ctx), {}, false
  while true do
    local best
    for _, e in ipairs(layout.list) do
      if ff[e.m] and not e.free and #e.ids > 1 and (e.y or 0) == 0 and not stuck[e.m]
        and (not best or #e.ids > #best.ids) then
        best = e
      end
    end
    if not best then return changed end
    local hx, hz, ox, oz = B.footprint(ctx.bounds, best.m, ctx.ms)
    local x, z, yaw, r = place(bed, rects, hx, hz, ox, oz, { B.acrossYaw(hx, hz) }, gapOf(ctx))
    if x and z and yaw and r then
      local id = table.remove(best.ids)
      layout.list[#layout.list + 1] = { m = best.m, x = x, z = z, yaw = yaw, ids = { id } }
      rects[#rects + 1] = r
      changed = true
    else
      -- no floor for this model; a smaller one may still find some
      stuck[best.m] = true
    end
  end
end

-- Free mode: a random spot and turn per item, never piled, each free.
-- After SCATTER_TRIES the last try stands, overlap included.
P.SCATTER_TRIES = 8

---@param layout TrailerCargo.Layout
---@param added { id: number, m: string }[]
---@param ctx TrailerCargo.PackCtx
---@return integer packed, number[] unfit
function P.scatter(bed, layout, added, ctx)
  local list = layout.list
  local rects = P.rects(layout, ctx)
  local packed, unfit = 0, {}
  local w, d = bed.x[2] - bed.x[1], bed.z[2] - bed.z[1]
  for i = 1, math.min(#added, ctx.maxNew) do
    local it = added[i]
    local hx, hz, ox, oz = B.footprint(ctx.bounds, it.m, ctx.ms)
    local x, z, yaw, r
    for _ = 1, P.SCATTER_TRIES do
      yaw = ctx.rng() * 360
      local probe = B.rect(0, 0, yaw, hx, hz, ox, oz)
      local rx, rz = (probe.maxx - probe.minx) / 2, (probe.maxz - probe.minz) / 2
      -- the footprint centre anywhere it keeps the whole footprint on the bed
      local cx = bed.x[1] + rx + ctx.rng() * math.max(0, w - 2 * rx)
      local cz = bed.z[1] + rz + ctx.rng() * math.max(0, d - 2 * rz)
      x, z = cx - probe.cx, cz - probe.cz
      r = B.rect(x, z, yaw, hx, hz, ox, oz)
      if B.fits(bed, rects, r, nil) then break end
    end
    if x and z and yaw and r and B.holds(bed, r) then
      -- a try that ended on a hump sits on it, not in it
      local g = B.groundAt(bed, r)
      list[#list + 1] = { m = it.m, x = x, z = z, yaw = yaw, ids = { it.id }, free = true, y = g > 0 and g or nil }
      rects[#rects + 1] = r
      packed = packed + 1
    else
      unfit[#unfit + 1] = it.id
    end
  end
  return packed, unfit
end

-- The group sizes of the ids that found no room, largest first.
---@param ids number[]
---@param trunk { id: number, m: string, w: number|nil }[]
---@param ctx TrailerCargo.PackCtx
---@return number[]
local function unfitSizes(ids, trunk, ctx)
  local byId = {}
  for i = 1, #trunk do byId[trunk[i].id] = trunk[i] end
  local items = {}
  for i = 1, #ids do
    local t = byId[ids[i]]
    if t then items[#items + 1] = t end
  end
  local _, groupSizes = P.pileSizes(items, ctx)
  local out = {}
  for i = 1, #groupSizes do
    local v = groupSizes[i]
    local j = #out
    while j >= 1 and out[j] < v do
      out[j + 1] = out[j]
      j = j - 1
    end
    out[j + 1] = v
  end
  return out
end

-- True when `a` leaves less out than `b`: compared biggest first, down
-- the list.
---@param a number[]  sizes, largest first
---@param b number[]
---@return boolean
function P.leavesLess(a, b)
  local n = math.max(#a, #b)
  for i = 1, n do
    local x, y = a[i] or 0, b[i] or 0
    if x < y - 1e-9 then return true end
    if x > y + 1e-9 then return false end
  end
  return false
end

-- Bring a layout in line with the trunk: drop what left, place what
-- arrived, entries that stay keep their place. Free mode scatters. `held`
-- ids are not tried singly again, only in the full repack. When something
-- does not fit, everything but free entries is repacked largest first,
-- adopted only if it leaves less out (P.leavesLess).
---@param layout TrailerCargo.Layout
---@param trunk { id: number, m: string }[]
---@param ctx TrailerCargo.PackCtx
---@param held table<number, boolean>|nil  ids rejected before, off the bed
---@return boolean changed, number[] unfit
function P.reconcile(bed, layout, trunk, ctx, held)
  local removed, nRemoved, added = P.diff(layout, trunk)
  local changed = false
  if nRemoved > 0 then
    P.prune(layout, removed)
    changed = true
  end
  -- requeued: layers over the cap, packer entries under free ones
  local requeue = P.trimPiles(layout, ctx)
  local evicted = P.evict(layout, bed, ctx)
  for i = 1, #evicted do requeue[#requeue + 1] = evicted[i] end
  if #requeue > 0 then
    changed = true
    local byId = {}
    for i = 1, #trunk do byId[trunk[i].id] = trunk[i] end
    for i = 1, #requeue do
      local t = byId[requeue[i]]
      if t then added[#added + 1] = t end
    end
  end
  local waiting = {}
  if held then
    local fresh = {}
    for i = 1, #added do
      if held[added[i].id] then waiting[#waiting + 1] = added[i].id else fresh[#fresh + 1] = added[i] end
    end
    added = fresh
  end
  local packed, unfit = 0, {}
  if ctx.auto == false then
    packed, unfit = P.scatter(bed, layout, added, ctx)
  else
    packed, unfit = P.pack(bed, layout, added, ctx)
  end
  if packed > 0 then changed = true end
  for i = 1, #waiting do unfit[#unfit + 1] = waiting[i] end
  if #unfit > 0 and ctx.auto ~= false and not ctx.noRepack then
    local all = {
      bounds = ctx.bounds, capOf = ctx.capOf, ms = ctx.ms, rng = ctx.rng,
      maxNew = #trunk, floorFirst = ctx.floorFirst,
    }
    -- free entries stay; only the packer's are packed again
    local fresh = P.newLayout()
    local pinned = {}
    for i = 1, #layout.list do
      local e = layout.list[i]
      if e.free then
        fresh.list[#fresh.list + 1] = e
        for j = 1, #e.ids do pinned[e.ids[j]] = true end
      end
    end
    local rest = {}
    for i = 1, #trunk do
      if not pinned[trunk[i].id] then rest[#rest + 1] = trunk[i] end
    end
    local _, freshUnfit = P.pack(bed, fresh, rest, all)
    if P.leavesLess(unfitSizes(freshUnfit, trunk, ctx), unfitSizes(unfit, trunk, ctx)) then
      layout.list = fresh.list
      unfit = freshUnfit
      changed = true
    end
  end
  if P.spread(bed, layout, ctx) then changed = true end
  return changed, unfit
end

---@param layout TrailerCargo.Layout
---@param ctx TrailerCargo.PackCtx
function P.fitsAt(layout, bed, ctx, id, x, z, yaw)
  local e, idx = P.entryOf(layout, id)
  if not e then return false end
  local hx, hz, ox, oz = B.footprint(ctx.bounds, e.m, ctx.ms)
  return B.fits(bed, P.rects(layout, ctx), B.rect(x, z, yaw, hx, hz, ox, oz), idx)
end

-- A player's move: the footprint centre must stay on the bed (B.holds);
-- overlaps are allowed. The entry becomes free.
---@param layout TrailerCargo.Layout
---@param ctx TrailerCargo.PackCtx
function P.move(layout, bed, ctx, id, x, z, yaw, y, rx, rz)
  local e = P.entryOf(layout, id)
  if not e then return false end
  local hx, hz, ox, oz = B.footprint(ctx.bounds, e.m, ctx.ms)
  local r = B.rect(x, z, yaw, hx, hz, ox, oz)
  if not B.holds(bed, r) then return false end
  e.x, e.z, e.yaw = x, z, yaw
  e.y = B.clampLift(bed, y or 0)
  e.rx, e.rz = (rx or 0) % 360, (rz or 0) % 360
  e.free = true
  return true
end

-- Where layer `li` of entry `e` is drawn, jitter included; unstack, hide
-- and the render agree on it.
---@param e TrailerCargo.Entry
---@param li integer
---@param ctx TrailerCargo.PackCtx
---@return number x, number z, number yaw, number y
function P.drawnPose(e, li, ctx)
  local jx, jz, jyaw = P.layerJitter(e.ids[li], li)
  if li == 1 and not e.free then jx, jz, jyaw = P.placeJitter(e.ids[1]) end
  return e.x + jx, e.z + jz, e.yaw + jyaw, (e.y or 0) + (li - 1) * B.pitch(ctx.bounds, e.m, ctx.ms)
end

-- A player's unstack: one free entry per layer, each where it was drawn.
-- False when `id` is not in a pile of two or more.
---@param layout TrailerCargo.Layout
---@param ctx TrailerCargo.PackCtx
---@return boolean
function P.unstack(layout, ctx, id)
  local e, idx = P.entryOf(layout, id)
  if not e or not idx or #e.ids < 2 then return false end
  local split = {}
  for li = 1, #e.ids do
    local x, z, yaw, y = P.drawnPose(e, li, ctx)
    split[li] = { m = e.m, x = x, z = z, yaw = yaw, ids = { e.ids[li] }, y = y, rx = e.rx or 0, rz = e.rz or 0, free = true }
  end
  local list, out = layout.list, {}
  for i = 1, #list do
    if i == idx then
      for k = 1, #split do out[#out + 1] = split[k] end
    else
      out[#out + 1] = list[i]
    end
  end
  layout.list = out
  return true
end

-- Hide or show one item. A show also marks it `shown` (over the size
-- classes) and always counts as a change.
---@param layout TrailerCargo.Layout
---@return boolean changed
function P.setHidden(layout, id, on)
  local h = layout.hidden
  if on then
    if layout.shown then layout.shown[id] = nil end
    if h and h[id] then return false end
    if not h then
      h = {}
      layout.hidden = h
    end
    h[id] = true
    return true
  end
  if h then h[id] = nil end
  if not layout.shown then layout.shown = {} end
  layout.shown[id] = true
  return true
end

-- "Hide from trailer": keeps where it was drawn (`parked`) for its Show.
---@param layout TrailerCargo.Layout
---@param ctx TrailerCargo.PackCtx
---@param id number
---@return boolean changed
function P.hide(layout, ctx, id)
  local e = P.entryOf(layout, id)
  if e then
    local li = 1
    for j = 1, #e.ids do
      if e.ids[j] == id then li = j end
    end
    local x, z, yaw, y = P.drawnPose(e, li, ctx)
    if not layout.parked then layout.parked = {} end
    layout.parked[id] = { m = e.m, x = x, z = z, yaw = yaw, ids = { id }, y = y, rx = e.rx or 0, rz = e.rz or 0, free = true }
  end
  return P.setHidden(layout, id, true)
end

-- "Show on trailer": the item lands free where it was parked, else in the
-- middle of the bed; marked shown.
---@param layout TrailerCargo.Layout
---@param ctx TrailerCargo.PackCtx
---@param id number
---@param m string  the item's model
---@return boolean
function P.show(layout, bed, ctx, id, m)
  P.prune(layout, { [id] = true })
  P.setHidden(layout, id, false)
  local parked = layout.parked and layout.parked[id]
  if parked and layout.parked and parked.m == m then
    layout.parked[id] = nil
    layout.list[#layout.list + 1] = parked
    return true
  end
  local cx, cz = (bed.x[1] + bed.x[2]) / 2, (bed.z[1] + bed.z[2]) / 2
  local hx, hz, ox, oz = B.footprint(ctx.bounds, m, ctx.ms)
  local y = B.groundAt(bed, B.rect(cx, cz, 0, hx, hz, ox, oz))
  local e = { m = m, x = cx, z = cz, yaw = 0, ids = { id }, free = true, y = y, rx = 0, rz = 0 }
  layout.list[#layout.list + 1] = e
  return true
end

-- Packer entries overlapping a free one leave the bed to be placed
-- again. Free entries never evict each other.
---@param layout TrailerCargo.Layout
---@param ctx TrailerCargo.PackCtx
---@return number[] ids  of the entries removed, in layout order
function P.evict(layout, bed, ctx)
  local list = layout.list
  local rects = P.rects(layout, ctx)
  local out, keep, w = {}, {}, 0
  for i = 1, #list do
    local e = list[i]
    local gone = false
    if not e.free then
      for j = 1, #list do
        if j ~= i and list[j].free and B.overlaps(rects[i], rects[j]) then
          gone = true
          break
        end
      end
    end
    if gone then
      for k = 1, #e.ids do out[#out + 1] = e.ids[k] end
    else
      w = w + 1
      keep[w] = e
    end
  end
  layout.list = keep
  return out
end

-- Forget hidden, shown and parked ids of items no longer `present`.
---@param layout TrailerCargo.Layout
---@param present table<number, boolean>
---@return boolean changed
function P.forget(layout, present)
  local changed = false
  for _, key in ipairs({ "hidden", "shown", "parked" }) do
    local t = layout[key]
    if t then
      local gone, n = {}, 0
      for id in pairs(t) do
        if not present[id] then
          n = n + 1
          gone[n] = id
        end
      end
      for i = 1, n do t[gone[i]] = nil end
      if n > 0 then changed = true end
    end
  end
  return changed
end

-- Height of an entry's top above the bed floor (Bed.pitch per lower layer).
---@param e TrailerCargo.Entry
---@param ctx TrailerCargo.PackCtx
function P.topOf(e, ctx)
  return (e.y or 0) + (#e.ids - 1) * B.pitch(ctx.bounds, e.m, ctx.ms) + B.height(ctx.bounds, e.m, ctx.ms)
end

-- The tops of the other entries whose footprint an entry at (x, z, yaw)
-- overlaps, above the floor. What a lift can snap onto.
---@param layout TrailerCargo.Layout
---@param ctx TrailerCargo.PackCtx
---@return number[]
function P.topsUnder(layout, ctx, id, x, z, yaw)
  local tops = {}
  local e, idx = P.entryOf(layout, id)
  if not e then return tops end
  local hx, hz, ox, oz = B.footprint(ctx.bounds, e.m, ctx.ms)
  local r = B.rect(x, z, yaw, hx, hz, ox, oz)
  local list = layout.list
  for i = 1, #list do
    if i ~= idx then
      local o = list[i]
      local ohx, ohz, oox, ooz = B.footprint(ctx.bounds, o.m, ctx.ms)
      if B.overlaps(B.rect(o.x, o.z, o.yaw, ohx, ohz, oox, ooz), r) then
        tops[#tops + 1] = P.topOf(o, ctx)
      end
    end
  end
  return tops
end

-- Within this of the floor or a top, a lift snaps onto it. Part units.
P.SNAP = 0.04

-- The lift after a drag: snaps to the floor or a top within SNAP.
---@param y number  the lift the drag asks for
---@param tops number[]  P.topsUnder at the new spot
function P.snapLift(y, tops)
  local best, bestD = 0.0, abs(y)
  for i = 1, #tops do
    local d = abs(y - tops[i])
    if d < bestD then best, bestD = tops[i], d end
  end
  if bestD <= P.SNAP then return best end
  return y
end

P.PICK_REACH = 0.15

-- The entry under a bed point (highest top wins), else the nearest
-- within reach.
---@param layout TrailerCargo.Layout
---@param ctx TrailerCargo.PackCtx
---@return TrailerCargo.Entry|nil
function P.pick(layout, bed, ctx, bx, bz)
  local rects = P.rects(layout, ctx)
  local point = B.rect(bx, bz, 0, 0, 0, 0, 0)
  local under, underTop
  for i = 1, #rects do
    if B.overlaps(rects[i], point) then
      local top = P.topOf(layout.list[i], ctx)
      if not underTop or top > underTop then under, underTop = layout.list[i], top end
    end
  end
  if under then return under end
  local best, bestD
  for i = 1, #rects do
    local r = rects[i]
    local dx = math.max(r.minx - bx, 0, bx - r.maxx)
    local dz = math.max(r.minz - bz, 0, bz - r.maxz)
    local d = dx * dx + dz * dz
    if d <= P.PICK_REACH * P.PICK_REACH and (not bestD or d < bestD) then best, bestD = layout.list[i], d end
  end
  return best
end

-- The entry nearest a bed point, however far: where a pad session starts.
-- Of several the point is on, the one with the highest top, as P.pick.
---@param layout TrailerCargo.Layout
---@param ctx TrailerCargo.PackCtx
---@return TrailerCargo.Entry|nil
function P.nearestEntry(layout, ctx, bx, bz)
  local rects = P.rects(layout, ctx)
  local best, bestD, bestTop
  for i = 1, #rects do
    local r = rects[i]
    local dx = math.max(r.minx - bx, 0, bx - r.maxx)
    local dz = math.max(r.minz - bz, 0, bz - r.maxz)
    local d = dx * dx + dz * dz
    local top = P.topOf(layout.list[i], ctx)
    if not bestD or d < bestD or (d == bestD and top > bestTop) then
      best, bestD, bestTop = layout.list[i], d, top
    end
  end
  return best
end

-- Millimetre grid for the pad's order, so a layer's jitter does not
-- shuffle a split pile in among its neighbours.
local function mm(v) return floor(v * 1000 + 0.5) end

-- The entry `step` (1 or -1) from `cur` in the pad's order: along z, then
-- across x, then up a pile, wrapping at either end. With no `cur`, or one
-- no longer on the bed, the first (or the last, stepping back).
---@param layout TrailerCargo.Layout
---@param ctx TrailerCargo.PackCtx
---@param cur TrailerCargo.Entry|nil
---@return TrailerCargo.Entry|nil
function P.stepEntry(layout, ctx, cur, step)
  ---@type { e: TrailerCargo.Entry, k: number[] }[]
  local rows = {}
  for i, e in ipairs(layout.list) do
    rows[i] = { e = e, k = { mm(e.z), mm(e.x), P.topOf(e, ctx), e.ids[1] or 0 } }
  end
  local n = #rows
  if n == 0 then return nil end
  table.sort(rows, function(a, b)
    for k = 1, 4 do
      if a.k[k] ~= b.k[k] then return a.k[k] < b.k[k] end
    end
    return false
  end)
  -- `+ n` keeps the operand positive: Kahlua's % keeps the left sign
  for i = 1, n do
    if rows[i].e == cur then return rows[(i - 1 + step + n) % n + 1].e end
  end
  return rows[step < 0 and n or 1].e
end

-- The resting height after `y` for a pad's Y + RB: the ground, then each
-- top under the item from low to high, back to the ground after the
-- highest. Heights within SNAP of each other are one.
---@param y number  the lift now
---@param tops number[]  P.topsUnder at the item's spot
---@param ground number  the floor there (a hump's top, else 0)
function P.nextRest(y, tops, ground)
  local rests = { ground }
  for i = 1, #tops do
    if tops[i] > ground + P.SNAP then rests[#rests + 1] = tops[i] end
  end
  table.sort(rests)
  local out = { rests[1] }
  for i = 2, #rests do
    if rests[i] - out[#out] > P.SNAP then out[#out + 1] = rests[i] end
  end
  for i = 1, #out do
    if out[i] > y + P.SNAP then return out[i] end
  end
  return out[1]
end

-- Per-layer jitter for a bundle, from the item id so every client agrees
-- without storing it. The bottom layer never moves.
function P.layerJitter(id, layer)
  if layer <= 1 then return 0, 0, 0 end
  local a = id % 7 - 3
  local b = floor(id / 7) % 7 - 3
  local c = floor(id / 49) % 5 - 2
  return a * 0.003, b * 0.003, c * 1.5
end
