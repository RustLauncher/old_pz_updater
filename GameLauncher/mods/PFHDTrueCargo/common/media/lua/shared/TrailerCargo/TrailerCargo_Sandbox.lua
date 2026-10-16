-- TrailerCargo_Sandbox: the server's switches (media/sandbox-options.txt),
-- read as SandboxVars.TrailerCargo.<Key>. The server enforces them; the
-- client reads them only to skip a request the server would refuse. A
-- missing page (offline, main menu, a save from before it) means defaults.
---@class (partial) TrailerCargo
TrailerCargo = rawget(_G, "TrailerCargo") or {}

---@class TrailerCargo.Sandbox
local Sb = TrailerCargo.Sandbox or {}
TrailerCargo.Sandbox = Sb

Sb.DAMAGE_MAX = 4

---@return table|nil
function Sb.vars()
  local sv = rawget(_G, "SandboxVars")
  if type(sv) ~= "table" then return nil end
  local page = sv.TrailerCargo
  if type(page) ~= "table" then return nil end
  return page
end

local function flag(key)
  local page = Sb.vars()
  local v = page and page[key]
  if type(v) == "boolean" then return v end
  return true
end

-- A tipped trailer or pickup drops its items.
function Sb.itemSpill() return flag("ItemSpill") end

-- A rolled car trailer throws its cars.
function Sb.carSpill() return flag("CarSpill") end

-- What a spilled car's damage is multiplied by: 0 none, 1 as built.
---@return number
function Sb.carDamage()
  local page = Sb.vars()
  local v = page and tonumber(page.CarSpillDamage)
  if not v then return 1 end
  return math.max(0, math.min(Sb.DAMAGE_MAX, v))
end
