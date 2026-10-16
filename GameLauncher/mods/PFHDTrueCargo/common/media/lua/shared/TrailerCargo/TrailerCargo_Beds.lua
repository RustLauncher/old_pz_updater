-- TrailerCargo_Beds: the bed of every supported vehicle, in part units.
-- part: the trunk part that owns the container. floor: part y of the floor.
-- x, z: the inner rectangle. hitch: +1 when the coupling is at +z. rail:
-- part y of the rail top. Every rectangle is inset from the inner faces by
-- 12% of the half-span capped at 0.09; the floor gets +0.003 (cargo rests
-- on the panel). More inset does not stop wide models showing through.
---@class (partial) TrailerCargo
---@field Beds table<string, TrailerCargo.BedEntry>
TrailerCargo = rawget(_G, "TrailerCargo") or {}

---@class TrailerCargo.BedEntry
---@field part string
---@field floor number
---@field x [number, number]  min, max
---@field z [number, number]  min, max
---@field hitch integer
---@field rail number
---@field humps TrailerCargo.Hump[]|nil  raised parts of the floor: the packer keeps off them, a hand-placed item rests on them
---@field covers TrailerCargo.Cover[]|nil  parts that, installed, hide the bed (Bed.covered)
---@field tarps TrailerCargo.Cover[]|nil  parts that, installed, hold the load in without hiding it: no spill (Bed.sealed)
---@field override boolean|nil  a TrueCargoBeds row only: replace the row this file ships for the same vehicle

---@class TrailerCargo.Hump
---@field x [number, number]
---@field z [number, number]
---@field top number  part y of its top

---@class TrailerCargo.Cover
---@field part string
---@field items string[]|nil  only these installed items cover; nil: any

-- KI5 utility tarp: flat at the rail, the load stays drawn but cannot spill.
local KI5_TARP = { { part = "KI5TRTarp" } }

TrailerCargo.Beds = {
  ["Base.TrailerKI5utilitySmall"] = { part = "KI5TRTrunk", floor = -0.2650, x = { -0.5915, 0.5902 }, z = { -1.1194, 0.5109 }, hitch = 1, rail = 0.1558, tarps = KI5_TARP },
  ["Base.TrailerKI5utilityMedium"] = { part = "KI5TRTrunk", floor = -0.2650, x = { -0.5915, 0.5902 }, z = { -1.1194, 1.1117 }, hitch = 1, rail = 0.1558, tarps = KI5_TARP },
  ["Base.TrailerKI5utilityLarge"] = { part = "KI5TRTrunk", floor = -0.2650, x = { -0.5915, 0.5902 }, z = { -1.1194, 1.7661 }, hitch = 1, rail = 0.1558, tarps = KI5_TARP },
  -- vanilla trailer: the tub physics box minus the script body offset
  ["Base.Trailer"] = { part = "TrailerTrunk", floor = -0.0620, x = { -0.2770, 0.2770 }, z = { -0.7270, 0.0950 }, hitch = 1, rail = 0.1402 },
}

-- Vanilla pickups: ASCII FBX, read from raw vertices at scale 0.008. The
-- Lights mesh has the same bed.
local PICKUP = { part = "TruckBedOpen", floor = -0.1180, x = { -0.2966, 0.2910 }, z = { -1.0009, -0.1695 }, hitch = 1, rail = 0.0736 }
for _, name in ipairs({
  "Base.PickUpTruck", "Base.PickUpTruck_Camo", "Base.PickUpTruckJPLandscaping", "Base.PickUpTruckMccoy",
  "Base.PickUpTruckLightsAirport", "Base.PickUpTruckLightsAirportSecurity", "Base.PickUpTruckLightsFire",
  "Base.PickUpTruckLightsFossoil", "Base.PickUpTruckLightsRanger",
  -- PZK VLC's Public Works pickup: the vanilla Lights body at the vanilla scale
  "Base.pzkPickUpTruckPublicWorks",
}) do
  TrailerCargo.Beds[name] = PICKUP
end

-- KI5 M101A3 / M101A2 share one tub: floor -0.234, walls +-0.807, rail
-- 0.269, a wheel hump against each wall. The A3 cover and the A2's canvas
-- item cover; the flat tarps hold the load in. The A2's tarp part names an
-- area the trailer lacks, so it can never be removed in play.
local function m101(part, humpX, humpTop, cover, tarp)
  return {
    part = part, floor = -0.2310, x = { -0.7170, 0.7170 }, z = { -1.1030, 1.0270 }, hitch = 1, rail = 0.2690,
    humps = {
      { x = { -0.8070, -humpX }, z = { -0.6640, 0.3670 }, top = humpTop },
      { x = { humpX, 0.8070 }, z = { -0.6640, 0.3670 }, top = humpTop },
    },
    covers = { cover }, tarps = { tarp },
  }
end
TrailerCargo.Beds["Base.TrailerM101A3cargo"] = m101("M101A3Trunk", 0.5670, 0.0470, { part = "M101A3Cover" },
  { part = "M101A3Tarp" })
TrailerCargo.Beds["Base.TrailerM101A2cargo"] = m101("M101A2Trunk", 0.5970, 0.1440,
  { part = "M101A2Tarp", items = { "Base.86chevyCUCVBedTarp2" } }, { part = "M101A2Tarp" })

-- CUCV pack (Workshop 3428008364), beds on GloveBox. M1028: flat deck,
-- low sides topped 0.420. M1008: the K10 bed family, wheel arches; its
-- tall tarp covers, the plank stakes do not.
TrailerCargo.Beds["Base.86chevyM1028"] = {
  part = "M1028Trunk", floor = 0.0730, x = { -0.9870, 0.9870 }, z = { -2.3010, -0.3170 }, hitch = 1, rail = 0.4200,
}
TrailerCargo.Beds["Base.86chevyM1008"] = {
  part = "M1008Trunk", floor = -0.0680, x = { -0.7580, 0.7580 }, z = { -2.2850, -0.2870 }, hitch = 1, rail = 0.3950,
  humps = {
    { x = { -0.8480, -0.5760 }, z = { -1.9130, -0.9150 }, top = 0.1880 },
    { x = { 0.5760, 0.8480 }, z = { -1.9130, -0.9150 }, top = 0.1880 },
  },
  covers = { { part = "CUCV86BedAddons", items = { "Base.86chevyCUCVBedTarp2" } } },
}

-- KI5 pickups: the bed is a model on GloveBox placed per cab by a
-- part-model z offset, so one bed serves every cab through `shifted`.
-- Only caps and hard covers cover; flat tarps at the rail leave the load
-- drawn. Optional parts inside a bed (toolboxes, spares) are not modelled.

-- A copy of `row` moved `dz` along the bed; the row itself is untouched.
local function shifted(row, dz)
  local out = {
    part = row.part, floor = row.floor, x = row.x, z = { row.z[1] + dz, row.z[2] + dz },
    hitch = row.hitch, rail = row.rail, covers = row.covers, tarps = row.tarps,
  }
  if row.humps then
    out.humps = {}
    for i, h in ipairs(row.humps) do
      out.humps[i] = { x = h.x, z = { h.z[1] + dz, h.z[2] + dz }, top = h.top }
    end
  end
  return out
end

-- Two wells, one against each wall, from |x| `foot` to the wall.
local function wells(foot, wall, z1, z2, top)
  return {
    { x = { -wall, -foot }, z = { z1, z2 }, top = top },
    { x = { foot, wall }, z = { z1, z2 }, top = top },
  }
end

local function assign(names, row)
  for _, name in ipairs(names) do TrailerCargo.Beds[name] = row end
end

-- '93 Silverado: part-model z 0 (CC), 0.28 (XC), 0.91 (SC). The flat bed
-- tarp holds the load in; the stakes are open.
local SIL_TARP = { { part = "SIL93Tarp" } }
local SIL_LONG = {
  part = "SIL93Trunk3", floor = -0.1880, x = { -0.7290, 0.7290 }, z = { -3.5130, -1.2440 }, hitch = 1, rail = 0.3480,
  humps = wells(0.6370, 0.8190, -2.7820, -2.1240, 0.0910), tarps = SIL_TARP,
}
local SIL_SHORT = {
  part = "SIL93Trunk3", floor = -0.1880, x = { -0.7290, 0.7290 }, z = { -3.0450, -1.2440 }, hitch = 1, rail = 0.3480,
  humps = wells(0.6370, 0.8190, -2.4340, -1.7760, 0.0910), tarps = SIL_TARP,
}
assign({ "Base.93chevySilveradoCC" }, SIL_SHORT)
assign({ "Base.93chevySilveradoXC", "Base.93chevySilveradoVoltMojo" }, shifted(SIL_SHORT, 0.28))
assign({ "Base.93chevySilveradoSC", "Base.93chevySilveradoAirport" }, shifted(SIL_SHORT, 0.91))
assign({
  "Base.93chevySilveradoCCdually", "Base.93chevySilveradoCClong", "Base.93chevySilveradoPennSham",
  "Base.93chevySilveradoPoliceBCS", "Base.93chevySilveradoPoliceMCS",
}, SIL_LONG)
assign({
  "Base.93chevySilveradoXCdually", "Base.93chevySilveradoXClong", "Base.93chevySilveradoXClongMcCoy",
  "Base.93chevySilveradoXClongRanger", "Base.93chevySilveradoMcCoyWoodworking",
  "Base.93chevySilveradoRiversideFab", "Base.93chevySilveradoWpCarpentry",
}, shifted(SIL_LONG, 0.28))
assign({
  "Base.93chevySilveradoSCdually", "Base.93chevySilveradoSClong", "Base.93chevySilveradoSClongFossoil",
  "Base.93chevySilveradoStoneworksMasonry",
}, shifted(SIL_LONG, 0.91))

-- K3500 flatbed (+ Expanded lvLandscaping): deck 0.100, rails 0.431,
-- tailgate face -2.911, headache rack face -0.240.
assign({ "Base.93chevySilveradoK3500flatbed", "Base.93chevySilveradoK3500lvLandscaping" }, {
  part = "SIL93Trunk4", floor = 0.1030, x = { -0.9900, 0.9900 }, z = { -2.8210, -0.3300 }, hitch = 1, rail = 0.4310,
})

-- '91 Ranger: part-model z 0.4169 on the single cabs. The bed cap covers.
local RNG_CAP = { { part = "RNG91TruckBedExtras", items = { "Base.91fordRangerBedCap2" } } }
local RNG_LONG = {
  part = "RNG91Trunk", floor = -0.1310, x = { -0.6180, 0.6180 }, z = { -2.5450, -0.6360 }, hitch = 1, rail = 0.3310,
  humps = wells(0.5310, 0.7020, -1.9190, -1.2650, 0.0840), covers = RNG_CAP,
}
local RNG_SHORT = {
  part = "RNG91Trunk", floor = -0.1310, x = { -0.6180, 0.6180 }, z = { -2.2390, -0.6360 }, hitch = 1, rail = 0.3310,
  humps = wells(0.5310, 0.7020, -1.7340, -1.0800, 0.0840), covers = RNG_CAP,
}
assign({ "Base.91fordRangerXC", "Base.91fordRangerPD", "Base.91fordRangerRanger" }, RNG_SHORT)
assign({ "Base.91fordRangerXClong" }, RNG_LONG)
assign({ "Base.91fordRangerSC" }, shifted(RNG_SHORT, 0.4169))
assign({ "Base.91fordRangerSClong" }, shifted(RNG_LONG, 0.4169))

-- '88 Hilux: part-model z 0.4047 on the single cab. The bed cap covers.
local HLX = {
  part = "HLX88Trunk", floor = 0.0300, x = { -0.6110, 0.6110 }, z = { -2.5170, -0.8700 }, hitch = 1, rail = 0.4300,
  humps = wells(0.5440, 0.6940, -1.9910, -1.2560, 0.2710),
  covers = { { part = "HLX88TruckBedExtras", items = { "Base.88toyotaHiluxBedCap2" } } },
}
assign({ "Base.88toyotaHiluxXC", "Base.88toyotaHiluxXCS" }, HLX)
assign({ "Base.88toyotaHiluxSC" }, shifted(HLX, 0.4047))

-- '70 El Camino: the bed is inside the body mesh; wells good to about 0.05.
assign({ "Base.70elCamino", "Base.70elCaminoSS" }, {
  part = "CHE70TrunkE", floor = -0.0770, x = { -0.6160, 0.6160 }, z = { -2.3540, -0.7900 }, hitch = 1, rail = 0.3190,
  humps = wells(0.5390, 0.7000, -1.7000, -1.0000, 0.2500),
})

-- '82 J10: floor from j10_interior (the body reads lower). The cap covers.
assign({ "Base.82jeepJ10", "Base.82jeepJ10pd", "Base.82jeepJ10ranger" }, {
  part = "JP82Trunk", floor = -0.1660, x = { -0.6920, 0.6920 }, z = { -2.3850, -0.5210 }, hitch = 1, rail = 0.3130,
  humps = wells(0.6140, 0.7820, -1.8550, -1.0750, 0.1000),
  covers = { { part = "JP82BedCover" } },
})

-- '49 Power Wagon: no wells (wheels outside the bed); the PA shares it.
assign({ "Base.49powerWagon", "Base.49powerWagonMP", "Base.49powerWagonPD", "Base.49powerWagonPA" }, {
  part = "PWRTrunk", floor = -0.2120, x = { -0.5910, 0.5910 }, z = { -2.6980, -1.1760 }, hitch = 1, rail = 0.3360,
})

-- '93 F-Series: three beds (the F250 is the F350 bed moved 0.861). The
-- tonneau covers.
local F_COVER = { { part = "F3502TruckbedCover" } }
assign({ "Base.93fordF150", "Base.93fordF150S" }, {
  part = "F3502Trunk", floor = -0.1170, x = { -0.7680, 0.7680 }, z = { -1.8510, 0.0210 }, hitch = 1, rail = 0.4090,
  humps = wells(0.6490, 0.8580, -1.1400, -0.4820, 0.1820), covers = F_COVER,
})
assign({ "Base.93fordF250" }, {
  part = "F3502Trunk", floor = -0.1300, x = { -0.7680, 0.7680 }, z = { -2.2710, 0.0210 }, hitch = 1, rail = 0.3950,
  humps = wells(0.6490, 0.8580, -1.5600, -0.9020, 0.1690), covers = F_COVER,
})
assign({ "Base.93fordF350", "Base.93fordF350dually", "Base.93fordF350fd", "Base.93fordF350pd", "Base.93fordF350so" }, {
  part = "F3502Trunk", floor = -0.1170, x = { -0.7680, 0.7680 }, z = { -3.1320, -0.8400 }, hitch = 1, rail = 0.4090,
  humps = wells(0.6490, 0.8580, -2.4210, -1.7630, 0.1820), covers = F_COVER,
})

-- '88 S10. The cap covers.
assign({ "Base.88chevyS10" }, {
  part = "CH88Trunk", floor = -0.1450, x = { -0.6350, 0.6350 }, z = { -2.4400, -0.5780 }, hitch = 1, rail = 0.3200,
  humps = wells(0.5340, 0.7220, -1.9010, -1.0970, 0.1530),
  covers = { { part = "CH88BedCover" } },
})

-- '89 Defender 130 and its trailer share one bed. The hard cover and the
-- tarp cover cover; the rollbar toolbox does not.
assign({ "Base.89defender130", "Base.Trailer89defender" }, {
  part = "DEF89Trunk130", floor = -0.0500, x = { -0.7040, 0.7040 }, z = { -2.7140, -1.2830 }, hitch = 1, rail = 0.5310,
  humps = wells(0.5990, 0.7940, -2.1400, -1.3800, 0.2110),
  covers = { { part = "DEF89TruckBedAddon", items = { "Base.89defenderHardCover2", "Base.89defenderTarpCover2" } } },
})

-- '76 K series: K20 is 0.313 longer at the rear; the K30 crew cab is the
-- K20 bed at -0.7995. Only the closed caps cover.
local K_CAP = { { part = "CH76TruckBedCover", items = { "Base.76chevyK10BedCap2", "Base.76chevyK20BedCap2" } } }
local K20 = {
  part = "CH76Trunk", floor = -0.0680, x = { -0.7580, 0.7580 }, z = { -2.4970, -0.1890 }, hitch = 1, rail = 0.3950,
  humps = wells(0.5760, 0.8480, -2.1250, -1.1270, 0.1880), covers = K_CAP,
}
assign({ "Base.76chevyK10", "Base.76chevyK10fd", "Base.76chevyK10spirit", "Base.76chevyK10mccoy" }, {
  part = "CH76Trunk", floor = -0.0680, x = { -0.7580, 0.7580 }, z = { -2.1840, -0.1890 }, hitch = 1, rail = 0.3950,
  humps = wells(0.5760, 0.8480, -1.8120, -0.8140, 0.1880), covers = K_CAP,
})
assign({
  "Base.76chevyK20", "Base.76chevyK20BigRed", "Base.76chevyK30SCdually", "Base.76chevyK20brickingIt",
  "Base.76chevyK20callowayLandscaping", "Base.76chevyK20fossoil", "Base.76chevyK20helton",
  "Base.76chevyK20kimblesCon", "Base.76chevyK20kyLumber", "Base.76chevyK20marchRidgeCon",
  "Base.76chevyK20weldingCamille", "Base.76chevyK20yingsWood",
}, K20)
assign({ "Base.76chevyK30CC", "Base.76chevyK30CCdually" }, shifted(K20, -0.7995))

-- KI5 military. The body mesh is drawn mirrored in x: an asymmetric
-- feature takes part x = -raw x.

-- P19A trailers M1082 / M1095: `TruckBed` is the real container. The
-- tarp is a tall canvas: any installed item covers.
local P19A_TARP = { { part = "M10XXTarp" } }
TrailerCargo.Beds["Base.TrailerM1082"] = {
  part = "TruckBed", floor = 0.6110, x = { -1.0260, 1.0260 }, z = { -1.4310, 2.0510 }, hitch = 1, rail = 1.0800,
  covers = P19A_TARP,
}
TrailerCargo.Beds["Base.TrailerM1095"] = {
  part = "TruckBed", floor = 0.6110, x = { -1.0260, 1.0260 }, z = { -1.4310, 2.6950 }, hitch = 1, rail = 1.0800,
  covers = P19A_TARP,
}

-- M35A2: bed on GloveBox. Only the canvas (M35A2Tarp2) covers; the bows
-- and stake sides are open. The bed spare tyre is not modelled.
TrailerCargo.Beds["Base.78amgeneralM35A2"] = {
  part = "M35A2Trunk", floor = 0.4520, x = { -1.1150, 1.1150 }, z = { -3.8520, -0.4440 }, hitch = 1, rail = 0.8500,
  covers = { { part = "M35A2Tarp", items = { "Base.M35A2Tarp2" } } },
}

-- M923: rail is the side walls' top. Humps at the two bench seats. The
-- gun truck armour covers; the stakes are open.
TrailerCargo.Beds["Base.83amgeneralM923"] = {
  part = "M923Trunk", floor = 0.1960, x = { -1.1340, 1.1340 }, z = { -4.6900, -0.4880 }, hitch = 1, rail = 0.5610,
  humps = {
    { x = { 0.5690, 1.0190 }, z = { -1.7890, -1.4090 }, top = 0.5500 },
    { x = { 0.4710, 0.9210 }, z = { -2.7950, -2.4160 }, top = 0.5500 },
  },
  covers = { { part = "M923GuntruckArmor" } },
}

-- '80 MAN KAT1: MAN_flatbed on GloveBox. The canvas tarp covers.
TrailerCargo.Beds["Base.80manKat1"] = {
  part = "MAN80Trunk", floor = 0.2490, x = { -1.1030, 1.1030 }, z = { -4.1730, 0.5430 }, hitch = 1, rail = 0.9410,
  covers = { { part = "MAN80Tarp" } },
}

-- Papa_Chad M548: its model has rotate 0 180 0, so part z = file z. Deck
-- 0.959, walls 1.767, back door face -2.549, cab wall +0.61. The canvas
-- covers. The M113 is left out (closed hull).
assign({ "Base.M548", "Base.M548_Camo" }, {
  part = "TruckBed", floor = 0.9620, x = { -1.1550, 1.1550 }, z = { -2.4590, 0.5200 }, hitch = 1, rail = 1.7670,
  covers = { { part = "Back_Cage_Protection" } },
})

-- PZK VLC (Workshop 3217685049) and Motorious Zone (2791656602): beds baked
-- into the body mesh, measured with build/probe_beds.py. A hump taller
-- than the rail is capped just under it. A deck with no sides takes a
-- notional rail 0.25 above it. The PZK tarp is a tall canvas: a cover.
-- BRAT: arches; the rear-facing jump seats (cushion 0.255, backs to 0.51 against the cab end the bed)
assign({ "Base.fhq78BRAT_DL", "Base.fhq78BRAT_GL" }, {
  part = "TruckBedOpen", floor = 0.1940, x = { -0.2684, 0.2684 }, z = { -0.9098, -0.3202 }, hitch = 1, rail = 0.3800,
  humps = {
    { x = { -0.3050, -0.1950 }, z = { -0.7450, -0.4750 }, top = 0.2440 },
    { x = { 0.1950, 0.3050 }, z = { -0.7450, -0.4750 }, top = 0.2440 },
    { x = { -0.2300, -0.0300 }, z = { -0.4750, -0.3202 }, top = 0.2550 },
    { x = { 0.0300, 0.2300 }, z = { -0.4750, -0.3202 }, top = 0.2550 },
  },
})
-- RANGER: tub physics boxes agree: tailgate -0.967 top 0.310, walls 0.346
assign({ "Base.fhq93Ranger" }, {
  part = "TruckBedOpen", floor = 0.1340, x = { -0.3080, 0.3080 }, z = { -0.9180, -0.1700 }, hitch = 1, rail = 0.3090,
  humps = {
    { x = { -0.3500, -0.2100 }, z = { -0.6990, -0.3790 }, top = 0.2040 },
    { x = { 0.2100, 0.3500 }, z = { -0.6990, -0.3790 }, top = 0.2040 },
  },
})
-- RANGER_L
assign({ "Base.fhq93RangerLBed" }, {
  part = "TruckBedOpen", floor = 0.1340, x = { -0.3080, 0.3080 }, z = { -1.0590, -0.1790 }, hitch = 1, rail = 0.3090,
  humps = {
    { x = { -0.3500, -0.2100 }, z = { -0.7690, -0.4490 }, top = 0.2040 },
    { x = { 0.2100, 0.3500 }, z = { -0.7690, -0.4490 }, top = 0.2040 },
  },
})
-- RANGER_S
assign({ "Base.fhq93RangerSCab" }, {
  part = "TruckBedOpen", floor = 0.1340, x = { -0.3080, 0.3080 }, z = { -1.1286, -0.3894 }, hitch = 1, rail = 0.3090,
  humps = {
    { x = { -0.3500, -0.2100 }, z = { -0.9090, -0.5890 }, top = 0.2040 },
    { x = { 0.2100, 0.3500 }, z = { -0.9090, -0.5890 }, top = 0.2040 },
  },
})
-- BRONCO: fender ledges along both walls
assign({ "Base.fhqBroncoHalfCab" }, {
  part = "TruckBedOpen", floor = -0.1390, x = { -0.2772, 0.2772 }, z = { -0.7480, -0.3080 }, hitch = 1, rail = 0.0790,
  humps = {
    { x = { -0.3150, -0.2200 }, z = { -0.6880, -0.3080 }, top = -0.0350 },
    { x = { 0.2200, 0.3150 }, z = { -0.6880, -0.3080 }, top = -0.0350 },
  },
})
-- BRONCO_OR: the roll bar's legs stand on the ledges, its crossbar ends the bed
assign({ "Base.fhqBroncoHalfCabOffroad" }, {
  part = "TruckBedOpen", floor = -0.1390, x = { -0.2772, 0.2772 }, z = { -0.7560, -0.3600 }, hitch = 1, rail = 0.0790,
  humps = {
    { x = { -0.3150, -0.2200 }, z = { -0.7030, -0.3600 }, top = 0.0780 },
    { x = { 0.2200, 0.3150 }, z = { -0.7030, -0.3600 }, top = 0.0780 },
  },
})
-- H1: bed physics box z -1.104..-0.544 top 0.392
assign({ "Base.fhqH1Pickup", "Base.fhqH1Pickup_Offroad" }, {
  part = "TruckBedOpen", floor = 0.2360, x = { -0.2728, 0.2728 }, z = { -1.0552, -0.5888 }, hitch = 1, rail = 0.3950,
})
-- HQ: arches; buttresses at the cab corners
assign({ "Base.fhqHQUte", "Base.fhqHQSandmanUte" }, {
  part = "TruckBedOpen", floor = 0.0685, x = { -0.3036, 0.3036 }, z = { -1.0074, -0.2066 }, hitch = 1, rail = 0.2530,
  humps = {
    { x = { -0.3450, -0.2470 }, z = { -0.7420, -0.4520 }, top = 0.1600 },
    { x = { 0.2470, 0.3450 }, z = { -0.7420, -0.4520 }, top = 0.1600 },
    { x = { -0.3450, -0.2800 }, z = { -0.2320, -0.2066 }, top = 0.2520 },
    { x = { 0.2800, 0.3450 }, z = { -0.2320, -0.2066 }, top = 0.2520 },
  },
})
-- LOYALE
assign({ "Base.fhqLoyaleWagPickup" }, {
  part = "TruckBedOpen", floor = -0.0360, x = { -0.2772, 0.2772 }, z = { -0.9616, -0.6184 }, hitch = 1, rail = 0.1640,
  humps = {
    { x = { -0.3150, -0.2400 }, z = { -0.7450, -0.6184 }, top = 0.0440 },
    { x = { 0.2400, 0.3150 }, z = { -0.7450, -0.6184 }, top = 0.0440 },
  },
})
-- M715: the MZ side racks stand outside the walls
assign({ "Base.fhqM715MZ", "Base.fhqM715hardtopMZ", "Base.fhqM715CivMZ", "Base.fhqM715hardtopCivMZ" }, {
  part = "TruckBedOpen", floor = 0.3785, x = { -0.3476, 0.3476 }, z = { -1.3504, -0.3296 }, hitch = 1, rail = 0.5660,
  humps = {
    { x = { -0.3950, -0.2950 }, z = { -1.1100, -0.6800 }, top = 0.4860 },
    { x = { 0.2950, 0.3950 }, z = { -1.1100, -0.6800 }, top = 0.4860 },
  },
})
-- VW_T1: drop-side deck over the rear engine; modelScale 0.70
assign({ "Base.fhqVWT2T1Truck" }, {
  part = "TruckBedOpen", floor = 0.1190, x = { -0.8300, 0.8300 }, z = { -2.4210, 0.8180 }, hitch = 1, rail = 0.6670,
})
-- VW_T1_CREW
assign({ "Base.fhqVWT2T1CrewCab" }, {
  part = "TruckBedOpen", floor = 0.1190, x = { -0.8300, 0.8300 }, z = { -2.4340, -0.4690 }, hitch = 1, rail = 0.6670,
})
-- LM002: modelScale 0.66; the full-width step against the cab (0.63) ends the bed
assign({ "Base.fhqLM002" }, {
  part = "TruckBedOpen", floor = -0.0260, x = { -0.5984, 0.5984 }, z = { -2.5521, -1.8199 }, hitch = 1, rail = 0.3340,
})
-- SUB_LONG
assign({ "Base.pzkChevalierPickupCrewLong", "Base.pzkChevalierPickupCrewLongRail", "Base.pzkFranklin350FPickupCrewLong" }, {
  part = "TruckBedOpen", floor = -0.0520, x = { -0.3344, 0.3344 }, z = { -1.4014, -0.4686 }, hitch = 1, rail = 0.1280,
})
-- SUB_LONG2
assign({ "Base.pzkFranklin250FPickupCrewLong", "Base.pzkDashIntruder250PickupLong" }, {
  part = "TruckBedOpen", floor = -0.0520, x = { -0.3344, 0.3344 }, z = { -1.3966, -0.3934 }, hitch = 1, rail = 0.1280,
})
-- SUB_MED
assign({ "Base.pzkChevalierPickupCrewMedium", "Base.pzkChevalierPickupCrewMediumRail", "Base.pzkFranklin150FPickupMedium" }, {
  part = "TruckBedOpen", floor = -0.0520, x = { -0.3344, 0.3344 }, z = { -1.2086, -0.3814 }, hitch = 1, rail = 0.1280,
})
-- SUB_REG
assign({ "Base.pzkChevalierE6", "Base.pzkChevalierE6Rail", "Base.pzkChevalierF6", "Base.pzkChevalierF6Rail", "Base.pzkFranklin150FPickupReg", "Base.pzkPickUpTruck93" }, {
  part = "TruckBedOpen", floor = -0.1320, x = { -0.3344, 0.3344 }, z = { -0.9746, -0.1914 }, hitch = 1, rail = 0.0480,
})
-- HILLBILLY: the vanilla pickup's bed at modelScale 1.88
assign({ "Base.pzkPickUpTruckWoodboarded" }, {
  part = "TruckBedOpen", floor = -0.1230, x = { -0.2992, 0.2992 }, z = { -1.0204, -0.1756 }, hitch = 1, rail = 0.0740,
})
-- D100: stepside: fender ledges outside the tub
assign({ "Base.pzkChevalierD100Pickup", "Base.pzkChevalierD100PickupCustom" }, {
  part = "TruckBedOpen", floor = -0.1230, x = { -0.2420, 0.2420 }, z = { -1.0016, -0.1744 }, hitch = 1, rail = 0.0740,
})
-- NAVAJO
assign({ "Base.pzkDashNavajoP" }, {
  part = "TruckBedOpen", floor = -0.1280, x = { -0.3520, 0.3520 }, z = { -1.0741, -0.1949 }, hitch = 1, rail = 0.0700,
  humps = {
    { x = { -0.4000, -0.2500 }, z = { -0.7800, -0.4200 }, top = -0.0280 },
    { x = { 0.2500, 0.4000 }, z = { -0.7800, -0.4200 }, top = -0.0280 },
  },
})
-- RAIDER
assign({ "Base.pzkPickupFranklin", "Base.pzkPickupFranklinFire", "Base.pzkPickupFranklinRanger" }, {
  part = "TruckBedOpen", floor = -0.1420, x = { -0.3388, 0.3388 }, z = { -1.0106, -0.1834 }, hitch = 1, rail = 0.0750,
  humps = {
    { x = { -0.3850, -0.2500 }, z = { -0.7570, -0.3770 }, top = -0.0820 },
    { x = { 0.2500, 0.3850 }, z = { -0.7570, -0.3770 }, top = -0.0820 },
  },
})
-- IBERIA
assign({ "Base.pzkMastersonIberiaPickup" }, {
  part = "TruckBedOpen", floor = -0.1830, x = { -0.2684, 0.2684 }, z = { -0.9328, -0.1672 }, hitch = 1, rail = 0.0470,
  humps = {
    { x = { -0.3050, -0.2050 }, z = { -0.6350, -0.3250 }, top = -0.1300 },
    { x = { 0.2050, 0.3050 }, z = { -0.6350, -0.3250 }, top = -0.1300 },
  },
})
-- APEX: arches; the sport bar's legs stand on them
assign({ "Base.pzkMastersonApex4D" }, {
  part = "TruckBedOpen", floor = -0.1490, x = { -0.3124, 0.3124 }, z = { -1.0687, -0.5223 }, hitch = 1, rail = 0.0800,
  humps = {
    { x = { -0.3550, -0.2350 }, z = { -0.7700, -0.5223 }, top = -0.0290 },
    { x = { 0.2350, 0.3550 }, z = { -0.7700, -0.5223 }, top = -0.0290 },
    { x = { -0.3250, -0.2650 }, z = { -0.6000, -0.5223 }, top = 0.0790 },
    { x = { 0.2650, 0.3250 }, z = { -0.6000, -0.5223 }, top = 0.0790 },
  },
})
-- ROADRUNNER: arches; sail buttresses at the cab corners; sides -0.008, tailgate 0.032
assign({ "Base.pzkChevalierRoadrunner" }, {
  part = "TruckBedOpen", floor = -0.0880, x = { -0.3256, 0.3256 }, z = { -1.2262, -0.3638 }, hitch = 1, rail = 0.0300,
  humps = {
    { x = { -0.3700, -0.2150 }, z = { -0.8900, -0.5550 }, top = -0.0430 },
    { x = { 0.2150, 0.3700 }, z = { -0.8900, -0.5550 }, top = -0.0430 },
    { x = { -0.3700, -0.3000 }, z = { -0.4600, -0.3638 }, top = 0.0290 },
    { x = { 0.3000, 0.3700 }, z = { -0.4600, -0.3638 }, top = 0.0290 },
  },
})
-- HMMV3: storage boxes along both walls; the spare wheel (part pzkSpareWheel) stands on the left one
assign({ "Base.pzkHMMV3", "Base.pzkHMMV3Mil" }, {
  part = "TruckBedOpen", floor = -0.1850, x = { -0.4752, 0.4752 }, z = { -1.0131, -0.4859 }, hitch = 1, rail = 0.0750,
  humps = {
    { x = { -0.5400, -0.3250 }, z = { -1.0131, -0.4859 }, top = -0.0150 },
    { x = { 0.3250, 0.5400 }, z = { -1.0131, -0.4859 }, top = -0.0150 },
    { x = { -0.4460, -0.2640 }, z = { -0.8600, -0.4859 }, top = 0.0740 },
  },
})
-- HMMV4
assign({ "Base.pzkHMMV4Mil", "Base.pzkHMMV6Mil" }, {
  part = "TruckBed", floor = -0.1850, x = { -0.4752, 0.4752 }, z = { -0.9864, -0.0676 }, hitch = 1, rail = 0.0750,
  humps = {
    { x = { -0.5400, -0.3250 }, z = { -0.9864, -0.3000 }, top = -0.0150 },
    { x = { 0.3250, 0.5400 }, z = { -0.9864, -0.3000 }, top = -0.0150 },
  },
  covers = { { part = "pzkFranklinTruckMil_Tarp" } },
})
-- BRIG
assign({ "Base.pzkVanBrig" }, {
  part = "TruckBedOpen", floor = -0.1370, x = { -0.3828, 0.3828 }, z = { -1.2924, -0.2276 }, hitch = 1, rail = 0.0730,
  covers = { { part = "pzkFranklinTruckMil_Tarp" } },
})
-- UTIL150: service body: the centre well between the compartments (0.130)
assign({ "Base.pzkChevalier150Utility", "Base.pzkChevalier150UtilityMoore", "Base.pzkChevalier150UtilityNewCoalfieldMechanic", "Base.pzkDash150Utility", "Base.pzkDash150UtilityMoore", "Base.pzkDash150UtilityNewCoalfieldMechanic", "Base.pzkF150Utility", "Base.pzkF150UtilityMoore", "Base.pzkF150UtilityNewCoalfieldMechanic", "Base.pzkChevalier150UtilityAirport", "Base.pzkChevalier150UtilityBulletinPD", "Base.pzkChevalier150UtilityFire", "Base.pzkChevalier150UtilityIrvingtonSpeedway", "Base.pzkChevalier150UtilityKSTPD", "Base.pzkChevalier150UtilityLVPD", "Base.pzkChevalier150UtilityMuldPD", "Base.pzkChevalier150UtilityPublicWorks", "Base.pzkChevalier150UtilityRanger", "Base.pzkDash150UtilityAirport", "Base.pzkDash150UtilityBulletinPD", "Base.pzkDash150UtilityFire", "Base.pzkDash150UtilityIrvingtonSpeedway", "Base.pzkDash150UtilityKSTPD", "Base.pzkDash150UtilityLVPD", "Base.pzkDash150UtilityMuldPD", "Base.pzkDash150UtilityPublicWorks", "Base.pzkDash150UtilityRanger", "Base.pzkF150UtilityAirport", "Base.pzkF150UtilityBulletinPD", "Base.pzkF150UtilityFire", "Base.pzkF150UtilityIrvingtonSpeedway", "Base.pzkF150UtilityKSTPD", "Base.pzkF150UtilityLVPD", "Base.pzkF150UtilityMuldPD", "Base.pzkF150UtilityPublicWorks", "Base.pzkF150UtilityRanger", "Base.pzkChevalier150UtilityRail" }, {
  part = "TruckBedOpen", floor = -0.2200, x = { -0.2288, 0.2288 }, z = { -1.5434, -0.3026 }, hitch = 1, rail = 0.1300,
})
-- FLAT150: no sides; deck physics box z -1.704..-0.199 top -0.118
assign({ "Base.pzkF150BoxFlatbed", "Base.pzkChevalier150BoxFlatbed", "Base.pzkDash150BoxFlatbed", "Base.pzkF150BoxFlatbedPublicWorks", "Base.pzkChevalier150BoxFlatbedPublicWorks", "Base.pzkDash150BoxFlatbedPublicWorks" }, {
  part = "TruckBedOpen", floor = -0.1153, x = { -0.3960, 0.3960 }, z = { -1.6180, -0.2980 }, hitch = 1, rail = 0.1347,
})
-- FT_BED
assign({ "Base.pzkFranklinTruckBed" }, {
  part = "TruckBedOpen", floor = 0.1145, x = { -0.4752, 0.4752 }, z = { -1.8740, 0.2960 }, hitch = 1, rail = 0.3310,
})
-- FT_CAB
assign({ "Base.pzkFranklinTruckCab" }, {
  part = "TruckBedOpen", floor = 0.1145, x = { -0.4752, 0.4752 }, z = { -1.8740, -0.0840 }, hitch = 1, rail = 0.3310,
})
-- FT_SHORT
assign({ "Base.pzkFranklinTruckShort" }, {
  part = "TruckBedOpen", floor = 0.1145, x = { -0.4752, 0.4752 }, z = { -1.5040, 0.2960 }, hitch = 1, rail = 0.3310,
})
-- FT_FLAT: no sides
assign({ "Base.pzkFranklinTruckFlatbed", "Base.pzkFranklinTruckFlatbedPublicWorks" }, {
  part = "TruckBedOpen", floor = 0.1154, x = { -0.5016, 0.5016 }, z = { -1.8940, 0.2160 }, hitch = 1, rail = 0.3654,
})
-- FT_UTIL: the aisle between the compartments
assign({ "Base.pzkFranklinTruckUtility" }, {
  part = "TruckBedOpen", floor = 0.1090, x = { -0.3388, 0.3388 }, z = { -1.5300, -0.0940 }, hitch = 1, rail = 0.3490,
})
-- FT_MIL: bows over the bed to 0.84
assign({ "Base.pzkFranklinTruckMil" }, {
  part = "TruckBed", floor = 0.1140, x = { -0.4752, 0.4752 }, z = { -1.8400, 0.2600 }, hitch = 1, rail = 0.5040,
  covers = { { part = "pzkFranklinTruckMil_Tarp" } },
})
-- W35: the spare wheel hangs under the deck
assign({ "Base.pzkTruckDashW35CabrioMil" }, {
  part = "TruckBedOpen", floor = 0.0540, x = { -0.4752, 0.4752 }, z = { -1.2380, 0.2520 }, hitch = 1, rail = 0.2610,
  covers = { { part = "pzkFranklinTruckMil_Tarp" } },
})
-- W35_BED
assign({ "Base.pzkTruckDashW35BedMil" }, {
  part = "TruckBed", floor = 0.0540, x = { -0.4752, 0.4752 }, z = { -1.2300, 0.3300 }, hitch = 1, rail = 0.5240,
  covers = { { part = "pzkFranklinTruckMil_Tarp" } },
})
-- DUAL: open front; the tailgate top is 0.051
assign({ "Base.pzkDualTrailer" }, {
  part = "TruckBed", floor = -0.0490, x = { -0.2552, 0.2552 }, z = { -1.0916, 0.0436 }, hitch = 1, rail = 0.1420,
})
-- SEMI: deck falls 0.549 (rear) to 0.520 (front); modelScale 0.65
assign({ "Base.pzkTrailerRegularFlatbed" }, {
  part = "TruckBed", floor = 0.5350, x = { -1.5290, 1.5290 }, z = { -6.1100, 9.8760 }, hitch = 1, rail = 0.7850,
})

-- Daihatsu Hijet Truck (Workshop 3583266047), all three on one body: a flat
-- deck (0.141) walled by the drop sides, one skinned model on TrunkDoor
-- (inner faces x -0.704 / 0.706, tailgate -1.800, top 0.471); the cab's back
-- is the headboard (0.209). The tarp (ATA2VisualSpoilerRear, a canopy to
-- 1.35) covers. The roof rack's corner posts stand inside the sides.
assign({ "Base.hijet100p", "Base.hijet100pJDM", "Base.hijet100pJDMTurbo" }, {
  part = "TruckBed", floor = 0.1437, x = { -0.6194, 0.6214 }, z = { -1.7100, 0.1190 }, hitch = 1, rail = 0.4713,
  covers = { { part = "ATA2VisualSpoilerRear" } },
})

-- The modder hook (docs/modders.md): other mods put rows in the
-- TrueCargoBeds global, keyed by script name. A separate global because
-- this file assigns TrailerCargo.Beds. Merged at OnGameBoot and again at
-- OnInitWorld; our rows win unless theirs says `override = true`. Rows
-- are taken by reference, never changed.

local function isNum(v)
  return type(v) == "number" and v == v
end

local function isPair(p)
  return type(p) == "table" and isNum(p[1]) and isNum(p[2]) and p[1] < p[2]
end

-- What is wrong with a row's covers or tarps list, or nil when it is fine.
---@return string|nil
local function partsProblem(cs, field, what)
  if cs == nil then return nil end
  if type(cs) ~= "table" then return field .. " must be a list" end
  for i = 1, #cs do
    local c = cs[i]
    if type(c) ~= "table" or type(c.part) ~= "string" or c.part == "" then
      return what .. " " .. i .. ": part must be a part id"
    end
    if c.items ~= nil then
      if type(c.items) ~= "table" then return what .. " " .. i .. ": items must be a list" end
      for k = 1, #c.items do
        if type(c.items[k]) ~= "string" then return what .. " " .. i .. ": items must be full item types" end
      end
    end
  end
  return nil
end

-- What is wrong with a bed row, or nil when it is fine.
---@return string|nil
function TrailerCargo.bedProblem(b)
  if type(b) ~= "table" then return "not a table" end
  if type(b.part) ~= "string" or b.part == "" then return "part must be the trunk part's id" end
  if not isNum(b.floor) then return "floor must be a number" end
  if not isNum(b.rail) or b.rail <= b.floor then return "rail must be a number above floor" end
  if not isPair(b.x) then return "x must be { min, max } with min < max" end
  if not isPair(b.z) then return "z must be { min, max } with min < max" end
  if b.hitch ~= 1 and b.hitch ~= -1 then return "hitch must be 1 or -1" end
  if b.humps ~= nil then
    if type(b.humps) ~= "table" then return "humps must be a list" end
    for i = 1, #b.humps do
      local h = b.humps[i]
      if type(h) ~= "table" or not isPair(h.x) or not isPair(h.z) then
        return "hump " .. i .. ": x and z must be { min, max }"
      end
      if not isNum(h.top) or h.top <= b.floor or h.top >= b.rail then
        return "hump " .. i .. ": top must lie between floor and rail"
      end
      if h.z[1] < b.z[1] or h.z[2] > b.z[2] then return "hump " .. i .. ": z must lie within the bed's z" end
    end
  end
  return partsProblem(b.covers, "covers", "cover") or partsProblem(b.tarps, "tarps", "tarp")
end

-- Merge rows from src into st.beds; st.shipped names our own rows, st.done
-- the row last seen per name, so a repeat event neither adds nor logs.
-- Returns how many rows went in.
---@param st { beds: table, shipped: table<string, boolean>, done: table }
---@param src table
---@param log fun(msg: string)
---@return integer
function TrailerCargo.mergeBeds(st, src, log)
  local n = 0
  for name, b in pairs(src) do
    if st.done[name] ~= b then
      st.done[name] = b
      local problem = TrailerCargo.bedProblem(b)
      if type(name) ~= "string" or not string.find(name, ".", 1, true) then
        log("TrueCargoBeds: skipped " .. tostring(name) .. ": key it by the full script name, Module.Name")
      elseif problem then
        log("TrueCargoBeds: skipped " .. name .. ": " .. problem)
      elseif st.shipped[name] and b.override ~= true then
        log("TrueCargoBeds: kept True Cargo's own row for " .. name .. "; set override = true to replace it")
      else
        st.beds[name] = b
        n = n + 1
        log("TrueCargoBeds: bed added for " .. name)
      end
    end
  end
  return n
end

local shipped = {}
for name in pairs(TrailerCargo.Beds) do shipped[name] = true end
local hookState = { beds = TrailerCargo.Beds, shipped = shipped, done = {} }

function TrailerCargo.mergeModBeds()
  local src = rawget(_G, "TrueCargoBeds")
  if type(src) ~= "table" then return end
  TrailerCargo.mergeBeds(hookState, src, function(msg) print("[TrailerCargo] " .. msg) end)
end

if Events then
  Events.OnGameBoot.Add(TrailerCargo.mergeModBeds)
  Events.OnInitWorld.Add(TrailerCargo.mergeModBeds)
end
