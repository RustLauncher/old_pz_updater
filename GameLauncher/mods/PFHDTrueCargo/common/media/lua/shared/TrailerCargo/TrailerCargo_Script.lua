-- TrailerCargo_Script: the text of a private vehicle script, one model block
-- per cargo layer. ScriptParser splits values on ',': every value ends in one.
---@class (partial) TrailerCargo
---@field Script TrailerCargo.Script
TrailerCargo = rawget(_G, "TrailerCargo") or {}

---@class TrailerCargo.Script
local Sc = TrailerCargo.Script or {}
TrailerCargo.Script = Sc

Sc.PART_ID = "TCargo"

-- The runtime clone's name for a model drawn with an item's texture: a legal
-- script name whatever the path holds.
---@param bare string
---@param tex string
---@return string
function Sc.texturedName(bare, tex)
  return bare .. "__" .. string.gsub(tex, "[^%w_]", "_")
end

-- The model script a cargo layer is drawn from: the `shader = trailercargo`
-- clone (gen_shaded.py) when one exists, which lights it like a dropped item.
-- A sub-model takes its texture from its script alone, so an item texture on
-- an untextured model needs a runtime clone (Render ensureTextured).
---@param m string  model script name as the trunk item gave it, "Base.X" or bare "X"
---@param tex string|nil  the item's texture, or nil
---@return string
function Sc.fileOf(m, tex)
  local shaded = TrailerCargo.Shaded
  if not shaded then return m end
  local dot = string.find(m, ".", 1, true)
  local key = dot and string.sub(m, dot + 1) or m
  if not shaded[key] then return m end
  if tex and TrailerCargo.Untextured and TrailerCargo.Untextured[key] then
    return "TrailerCargo." .. Sc.texturedName(key, tex)
  end
  return "TrailerCargo." .. key
end

-- The one block ModelScript:Load parses for a textured clone.
---@param name string  bare clone name
---@param u { mesh: string, scale: number, static: boolean }
---@param tex string
---@return string
function Sc.modelText(name, u, tex)
  return string.format("model %s { mesh = %s, scale = %s, static = %s, texture = %s, shader = trailercargo, }",
    name, u.mesh, tostring(u.scale), tostring(u.static), tex)
end

---@class TrailerCargo.ScriptLayer
---@field key number   item id; the model id is "c<key>"
---@field file string  model script name
---@field x number
---@field y number
---@field z number
---@field yaw number
---@field scale number
---@field rx number|nil  model-space tilt from TrailerCargo_Fixups
---@field rz number|nil

-- Reused across calls.
local buf = {}

---@param name string
---@param layers TrailerCargo.ScriptLayer[]
---@return string
function Sc.text(name, layers)
  local n = 1
  buf[1] = "vehicle " .. name .. " {\n\tpart " .. Sc.PART_ID .. " {\n"
  for i = 1, #layers do
    local l = layers[i]
    n = n + 1
    buf[n] = string.format(
      "\t\tmodel c%d { file = %s, offset = %.4f %.4f %.4f, rotate = %.2f %.2f %.2f, scale = %.5f, }\n",
      l.key, l.file, l.x, l.y, l.z, l.rx or 0, l.yaw, l.rz or 0, l.scale)
  end
  n = n + 1
  buf[n] = "\t}\n}\n"
  -- concat only this call's part; a longer build's tail stays unused
  return table.concat(buf, "", 1, n)
end
