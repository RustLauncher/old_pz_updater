# True Cargo for vehicle modders

True Cargo draws the items in an open bed's trunk as 3D models on the bed.
It needs one row per vehicle saying where the bed is. You know your
vehicle's scripts and meshes, so you can ship that row with your mod. There
is no dependency: without True Cargo the row is an unused table.

## The row

Add one shared Lua file to your mod, for example
`media/lua/shared/MyTrailer_TrueCargo.lua`:

```lua
TrueCargoBeds = TrueCargoBeds or {}
TrueCargoBeds["Base.MyFlatbed"] = {
  part = "MyFlatbedTrunk",
  floor = -0.265, rail = 0.156,
  x = { -0.59, 0.59 }, z = { -1.12, 1.11 },
  hitch = 1,
}
```

Every number is in part units, the frame a part model's `offset` is
written in: x across the bed, y up, z along it.

Always write `TrueCargoBeds = TrueCargoBeds or {}`, never `= {}`: another
mod may have added its rows first. True Cargo reads the table once every
mod has loaded (at `OnGameBoot`, then again at `OnInitWorld`), so load
order does not matter. You may fill it from your own `OnGameBoot` handler.

| field | meaning |
|---|---|
| key | The vehicle's full script name, as `vehicle:getScriptName()` returns it: `Module.Name`. |
| `part` | The part that owns the bed's real container. The models ride this part. |
| `floor` | Part y of the floor that cargo rests on: the top of the floor panel. |
| `rail` | Part y of the top of the side walls. It must be above `floor`. The dump reports each item's top against it. |
| `x`, `z` | The usable floor rectangle `{ min, max }` in part units, inside the walls. |
| `hitch` | `1` to pack from the +z end (a trailer's hitch, a truck's cab), `-1` to pack from the -z end. |
| `humps` | Optional. A list of raised floor areas such as wheel arches: `{ x = {min, max}, z = {min, max}, top = y }`. Automatic packing keeps off them. An item placed by hand stays where the player puts it, even over one. `top` lies between `floor` and `rail`. `z` lies within the bed's `z`, while `x` may reach into the wall. |
| `covers` | Optional. A list of parts that hide the bed while installed: `{ part = "MyTarp" }`, or `{ part = "MyAddon", items = { "Mod.TallCanvas" } }` to hide it only while one of those item types is installed. Nothing is drawn under a cover. The layout is kept for when the cover comes off. A covered bed never spills its load. |
| `tarps` | Optional. Parts that hold the load in without hiding it, such as a flat tarp at the rail, written like `covers`. The cargo stays drawn, but a vehicle tipped over while one is installed keeps its load instead of spilling it. |
| `override` | Optional. `true` replaces a row that True Cargo ships for the same vehicle. Without it, True Cargo keeps its own row. |

Rows are used as they are. They are never copied or changed, so several
script names may share one row table.

## Three rules for the numbers

**1. From the script, part units are the value minus the body offset.**
Part units are what a part model's `offset` is written in. `Loaded()`
multiplies the physics shapes, areas and body offset by the same
`model { scale }`, so a physics box read from the script converts as
`part = value - model offset`. Do not divide by the model scale.

**2. From Blender, use the raw node coordinates times the model script's
`scale`.** The engine ignores the FBX `UnitScaleFactor` and applies only
the node transforms. Blender folds the unit into the object matrix, so a
reading taken through it can be off by 100 / UnitScaleFactor.

**3. Check it in game.** A new Lua file is only picked up at game
start, so restart after adding it (editing it later needs no restart).
Turn on the **Debug tools** mod option, put a few items in the trunk,
right-click the vehicle and choose **Log cargo here**. The log
(`console.txt`) prints the bed, every item's position, its gap to the
nearest edge and its top against the rail, plus the items that did not
fit. A bed that is too big shows items through the walls. A bed that is
too small leaves items unplaced while the floor looks empty.

## Traps

- **The real container.** Some vehicles carry a dummy bed container (for
  example `category = nodisplay` with no capacity) besides the real one.
  `part` must be the part whose container the player actually loads.
- **The rectangle is the usable floor, not the tub box.** True Cargo's
  own rows are inset from the inner walls by about 12% of the half-width
  (at most 0.09) at each side and end. Item models are not the neat boxes
  their sizes claim.
- **The floor is where cargo rests.** Measure the top of the floor panel,
  not its underside. True Cargo's KI5 rows sit 0.012 above the panel's
  lower face.
- **An asymmetric bed.** Cargo is drawn mirrored in x against the part
  frame. True Cargo handles that, so write the row in part units as your
  scripts are. If the bed is not symmetric across x, confirm the side in
  the dump.

## Worked example: KI5 Utility Trailer (Medium)

From `TrailerKI5utilityMedium.txt`, abridged:

```
model { scale = 0.9000, offset = 0.0000 0.5889 0.0000 }
physics box { offset = 0.0000 0.5222 0.0399, extents = 1.3333 0.4667 2.3556 }   -- the tub
attachment trailer { offset = 0.0000 -0.3778 2.3556 }
part KI5TRTrunk { container ... }
```

The tub box in part units (rule 1):

- x: 0 ± 1.3333 / 2 = **-0.667..0.667**
- y: (0.5222 - 0.5889) ± 0.4667 / 2 = **-0.300..0.167**
- z: (0.0399 - 0) ± 2.3556 / 2 = **-1.138..1.218**

The box is the rim, not the floor. The meshes give the exact tub (rule 2):
the tarp covers x -0.672..0.671, z -1.209..1.202; the tailgate runs
from y -0.277 to 0.156. So the floor panel's lower face is at -0.277 and
the rail is 0.156. Inset the rectangle and lift the floor to the panel top:

```lua
TrueCargoBeds["Base.TrailerKI5utilityMedium"] = {
  part = "KI5TRTrunk", floor = -0.2650, rail = 0.1558,
  x = { -0.5915, 0.5902 }, z = { -1.1194, 1.1117 },
  hitch = 1,   -- the trailer attachment is at +z
}
```

That is the row True Cargo ships for this trailer.

## What the log says

Each row is reported once, prefixed `[TrailerCargo] TrueCargoBeds:`:

- `bed added for Mod.Name`: the row is in use.
- `skipped Mod.Name: <reason>`: the row is malformed and nothing is drawn
  for that vehicle. The reason names the field.
- `skipped Name: key it by the full script name, Module.Name`
- `kept True Cargo's own row for Mod.Name; set override = true to replace it`

Once the vehicle is in the world, one more line can appear:

- `Mod.Name: bed row names part X but the vehicle has no such part; nothing drawn`
  (or `but it has no container`): the row was accepted, but `part` is not
  the id of a part with a container on that vehicle. Nothing is drawn and
  the right-click menu shows no cargo entries until the row is fixed.
