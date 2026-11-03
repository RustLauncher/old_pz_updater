ProjectALife = ProjectALife or {}

local Blueprints = { byId = {}, order = {}, problems = {}, cache = {} }
ProjectALife.Blueprints = Blueprints

Blueprints.formatVersion = 1

Blueprints.rowOps = { tile = true, floor = true, container = true, light = true, items = true,
    radio = true, generator = true, vehicle = true, stairs = true }

Blueprints.spriteOps = { tile = true, floor = true, container = true, light = true, radio = true,
    stairs = true }

Blueprints.terrainSheets = { "blends_natural_", "blends_street_", "floors_exterior_natural_",
    "floors_exterior_street_" }

Blueprints.floorSheets = { "floors_" }

Blueprints.decorSheets = { "d_", "blends_", "boulders", "floors_", "industry_railroad", "trash_",
    "street_" }

Blueprints.solidSheets = { "furniture_", "location_military_generic", "location_military_knox",
    "boulders", "construction_01", "industry_01", "location_business", "location_community_medical",
    "location_community_school", "appliances_" }

Blueprints.barriers = { fencing_01_100 = true, fencing_01_101 = true }

Blueprints.solidOps = { container = true, generator = true, radio = true, vehicle = true }

Blueprints.vehicleReach = { x = 1, y = 2 }

Blueprints.campfire = "camping_01_4"

Blueprints.postOrder = { guard = 1, sniper = 2, radio = 3, sit = 4 }

Blueprints.maxProblems = 20

function Blueprints.starts(text, prefixes)
    if type(text) ~= "string" or type(prefixes) ~= "table" then return false end
    for _, prefix in ipairs(prefixes) do
        if string.sub(text, 1, #prefix) == prefix then return true end
    end
    return false
end

function Blueprints.validate(def)
    local problems = {}
    local function fail(what)
        if #problems < Blueprints.maxProblems then problems[#problems + 1] = what end
    end
    if type(def) ~= "table" then return false, { "blueprint is not a table" } end
    if def.format ~= Blueprints.formatVersion then fail("unknown format") end
    if type(def.id) ~= "string" or def.id == "" then fail("no id") end
    local anchor = def.anchor
    if type(anchor) ~= "table" or type(anchor.x) ~= "number" or type(anchor.y) ~= "number"
            or type(anchor.z) ~= "number" then
        fail("bad anchor")
    end
    if type(def.rows) ~= "table" or #def.rows == 0 then
        fail("no rows")
    else
        for index, row in ipairs(def.rows) do
            local where = "row " .. tostring(index) .. ": "
            if type(row) ~= "table" or not Blueprints.rowOps[row.op] then
                fail(where .. "unknown op")
            elseif type(row.dx) ~= "number" or type(row.dy) ~= "number" or type(row.dz) ~= "number" then
                fail(where .. "no offset")
            elseif Blueprints.spriteOps[row.op] and type(row.sprite) ~= "string" then
                fail(where .. "no sprite")
            elseif row.op == "items" and type(row.item) ~= "string" then
                fail(where .. "no item")
            elseif row.op == "vehicle" and type(row.script) ~= "string" then
                fail(where .. "no vehicle script")
            end
        end
    end
    return #problems == 0, problems
end

function Blueprints.add(def)
    local ok, problems = Blueprints.validate(def)
    if not ok then
        Blueprints.problems[#Blueprints.problems + 1] = {
            id = type(def) == "table" and tostring(def.id) or "?", problems = problems }
        return nil, problems
    end
    if Blueprints.byId[def.id] == nil then Blueprints.order[#Blueprints.order + 1] = def.id end
    Blueprints.byId[def.id] = def
    Blueprints.cache[def.id] = nil
    return def
end

function Blueprints.get(id)
    return Blueprints.byId[tostring(id or "")]
end

function Blueprints.anchorOf(id)
    local def = Blueprints.get(id)
    if def == nil then return nil end
    return { x = math.floor(def.anchor.x), y = math.floor(def.anchor.y), z = math.floor(def.anchor.z) }
end

function Blueprints.solidRow(row)
    if Blueprints.solidOps[row.op] then return true end
    if row.op ~= "tile" then return false end
    if Blueprints.barriers[row.sprite] then return true end
    if row.edge ~= nil then return false end
    return Blueprints.starts(row.sprite, Blueprints.solidSheets)
end

function Blueprints.cellKey(x, y, z)
    return math.floor(x) .. ":" .. math.floor(y) .. ":" .. math.floor(z)
end

function Blueprints.blocked(def)
    local cached = Blueprints.cache[def.id]
    if cached ~= nil then return cached end
    local set = {}
    local reach = Blueprints.vehicleReach
    for _, row in ipairs(def.rows) do
        if Blueprints.solidRow(row) then
            set[Blueprints.cellKey(row.dx, row.dy, row.dz)] = true
            if row.op == "vehicle" then
                for ox = -reach.x, reach.x do
                    for oy = -reach.y, reach.y do
                        set[Blueprints.cellKey(row.dx + ox, row.dy + oy, row.dz)] = true
                    end
                end
            end
        end
    end
    Blueprints.cache[def.id] = set
    return set
end

function Blueprints.contents(text)
    local list = {}
    if type(text) ~= "string" or text == "" then return list end
    for part in string.gmatch(text, "[^;]+") do
        local name, count = string.match(part, "^(.-)%*(%d+)$")
        if name ~= nil and name ~= "" then list[#list + 1] = { name, tonumber(count) or 1 } end
    end
    return list
end

function Blueprints.lootIndex(def, rules)
    local index = {}
    for _, rule in ipairs(type(rules) == "table" and rules or {}) do
        index[Blueprints.cellKey(def.anchor.x + rule.x, def.anchor.y + rule.y,
            def.anchor.z + (rule.z or 0))] = rule
    end
    return index
end

function Blueprints.tileOp(row, x, y, z)
    local floorLike = Blueprints.starts(row.sprite, Blueprints.floorSheets)
        and not Blueprints.starts(row.sprite, Blueprints.terrainSheets)
    local op = { op = floorLike and "floor" or "tile", x = x, y = y, z = z, sprite = row.sprite,
        keep = true }
    if not floorLike and Blueprints.starts(row.sprite, Blueprints.decorSheets) then op.decor = true end
    return op
end

function Blueprints.ops(def, options)
    options = options or {}
    local anchor = def.anchor
    local ops, seen, boxes = {}, {}, {}
    local loot = Blueprints.lootIndex(def, options.loot)
    for _, row in ipairs(def.rows) do
        local x, y, z = anchor.x + row.dx, anchor.y + row.dy, anchor.z + row.dz
        local kind = row.op
        local key = Blueprints.cellKey(x, y, z) .. ":" .. tostring(row.sprite or row.item or "")
        if kind == "tile" then
            if not seen[key] then
                seen[key] = true
                ops[#ops + 1] = Blueprints.tileOp(row, x, y, z)
            end
        elseif kind == "floor" then
            local terrain = z == 0 and Blueprints.starts(row.sprite, Blueprints.terrainSheets)
            if not terrain and not seen[key] then
                seen[key] = true
                ops[#ops + 1] = { op = "floor", x = x, y = y, z = z, sprite = row.sprite, keep = true }
            end
        elseif kind == "container" then
            local box = boxes[key]
            if box == nil then
                if row.ctype == "campfire" then
                    box = { op = "campfire", x = x, y = y, z = z, sprite = Blueprints.campfire }
                else
                    box = { op = "container", x = x, y = y, z = z, sprite = row.sprite, contents = {} }
                    local rule = loot[Blueprints.cellKey(x, y, z)]
                    if rule ~= nil then box.loot, box.draws = rule.store, rule.draws end
                end
                boxes[key] = box
                ops[#ops + 1] = box
            end
            if box.contents ~= nil then
                for _, entry in ipairs(Blueprints.contents(row.contents)) do
                    box.contents[#box.contents + 1] = entry
                end
            end
        elseif kind == "light" or kind == "radio" then
            ops[#ops + 1] = { op = kind, x = x, y = y, z = z, sprite = row.sprite }
        elseif kind == "generator" then
            ops[#ops + 1] = { op = kind, x = x, y = y, z = z, fuel = row.fuel, condition = row.condition }
        elseif kind == "vehicle" then
            ops[#ops + 1] = { op = kind, x = x, y = y, z = z, script = row.script,
                facing = row.facing, fuel = 0 }
        elseif kind == "items" then
            ops[#ops + 1] = { op = kind, x = x, y = y, z = z, item = row.item, quantity = row.quantity }
        elseif kind == "stairs" then
            ops[#ops + 1] = { op = kind, x = x, y = y, z = z, sprite = row.sprite, north = row.north,
                level = row.level }
        end
    end
    return ops
end

function Blueprints.postBefore(a, b)
    local order = Blueprints.postOrder
    local ra, rb = order[a.role] or 9, order[b.role] or 9
    if ra ~= rb then return ra < rb end
    if (a.conduct == "gunner") ~= (b.conduct == "gunner") then return a.conduct == "gunner" end
    if a.y ~= b.y then return a.y < b.y end
    return a.x < b.x
end

function Blueprints.posts(def, specs)
    local blocked = Blueprints.blocked(def)
    local anchor = def.anchor
    local result, refused = {}, {}
    for _, spec in ipairs(type(specs) == "table" and specs or {}) do
        local dz = spec.z or 0
        if blocked[Blueprints.cellKey(spec.x, spec.y, dz)] then
            refused[#refused + 1] = "post at " .. Blueprints.cellKey(spec.x, spec.y, dz)
        else
            local post = { x = anchor.x + spec.x + 0.5, y = anchor.y + spec.y + 0.5, z = anchor.z + dz,
                role = spec.role, conduct = spec.conduct }
            if type(spec.face) == "table" then
                post.face = { x = anchor.x + spec.face.x, y = anchor.y + spec.face.y }
            end
            result[#result + 1] = post
        end
    end
    table.sort(result, Blueprints.postBefore)
    return result, refused
end

function Blueprints.plan(id, options)
    local def = Blueprints.get(id)
    if def == nil then return nil, "blueprint_unknown" end
    options = options or {}
    local posts, refused = Blueprints.posts(def, options.posts)
    return { ops = Blueprints.ops(def, options), posts = posts, conflicts = #refused,
        refusals = refused, anchor = Blueprints.anchorOf(id) }
end

return Blueprints
