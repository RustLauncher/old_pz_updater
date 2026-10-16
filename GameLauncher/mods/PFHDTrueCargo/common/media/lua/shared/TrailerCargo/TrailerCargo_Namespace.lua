-- TrailerCargo_Namespace: the mod's global. Files reuse sub-tables, so load
-- order does not matter. Other globals: `TrueCargoBeds` (the modder hook)
-- and `TrailerCargoArrangeUI`. Every file declares the class `(partial)`.
---@class (partial) TrailerCargo
TrailerCargo = rawget(_G, "TrailerCargo") or {}
