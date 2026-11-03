-- TrailerCargo_LayDown: models tipped a quarter turn about model X to stay
-- under a low rail (Bed.laidDown), the one exception to lying as on the
-- ground. Curated on the player's call.
---@class (partial) TrailerCargo
---@field LayDown table<string, boolean>
TrailerCargo = rawget(_G, "TrailerCargo") or {}

TrailerCargo.LayDown = {
  ["Base.TirePump"] = true,
  ["Base.Extinguisher"] = true,
}
