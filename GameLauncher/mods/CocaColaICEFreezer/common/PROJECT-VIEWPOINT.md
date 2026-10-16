# Optional Project Viewpoint models

Version 1.4.2 adds models for the existing Coca-Cola ICE and original
vanilla ICE freezer. Project Viewpoint is optional. It is not a required item or
a hard dependency of this mod.

For ordinary isometric play, enable Coca-Cola ICE as usual. The original sprites,
inventories, capacity, cooling, sounds, appearance chance, lighting, movement and
recovery support continue to work. This integration introduces no new saved tile
IDs or additional furniture objects.

For Viewpoint play, enable and install Project Viewpoint and its own dependencies
according to their authors' instructions. The client registers the model pack
only while Viewpoint is active. Viewpoint's model-pack/LOD controls must also be
enabled. Turning off its 3D camera returns to the original isometric appearance.

The Coke models have the original empty, partial and full decorative stock
levels, with powered/unpowered versions. The vanilla ICE retains its original
frosted lids and lettering. Both physical halves and the original two cabinet
orientations are mapped separately. No decorative can is added to the inventory.

This mod loads after Viewpoint and the optional PZVoxelStudioViewpoint and
ViewpointFurnitureFix packs when those are present, so these specific ICE models
can replace their generic ICE mapping. No such pack is needed. An unrelated pack
that also binds the same vanilla sprites may need its load order adjusted.

Models use a single diffuse atlas based on the original sprites. Clear Coke lids
are represented without an opaque surface obscuring the contents; this does not
depend on unsupported transparent/multi-material MTL behavior. Existing red
game lights remain owned by Coca-Cola ICE, not by a second renderer addon.

Patch 1.4.4 fixes the final native rotation of both freezer halves, so the
closed outer sides and printed front face the intended directions. It also
registers the pack when Viewpoint is active only as a Java client mod and the
game's multiplayer mod list contains only the server's gameplay mods.

After Steam finishes downloading, fully restart Project Zomboid. Open Viewpoint's
settings with Delete (default key): enable Graphics > General > 3D model packs,
enable Coca-Cola Freezer ICE under World > Model packs, and set World > Levels of
detail > Model packs' models within (chunks) above 0. Viewpoint's Low preset sets
this range to 0 and uses sprite art instead. Farther chunks also use sprite art.

The Sketchfab gallery model is a separate, more detailed promotional
reconstruction. This optional in-game pack uses lighter models and the original
sprite-based texture atlas; it does not import the Sketchfab model.

Validation status, 16 October 2026: original Viewpoint 0.1.6.1 native CPU tests
passed for full OBJ/MTL/PNG loading, all 32 bindings in four range/readiness
conditions, and final transforms of 16 complete freezer pairs (80 assertions).
Nine Lua/native activation cases passed, including the reproduced client-only
multiplayer registration gap, its correction, ordinary absent-Viewpoint play,
and rejecting an inactive cached API or a known banned Java record.

Full in-game Viewpoint GPU rendering and a live multiplayer session have not
been visually verified. CPU tests do not establish GPU upload, camera visibility
or the exact cause on another player's computer. The integration changes no
saved tile IDs, inventories, spawn options or ordinary isometric scripts.

If you encounter bugs or errors, please report them in the Workshop comments
with a screenshot, SP/MP, game/Viewpoint versions, active mod list and relevant
console errors. If an initial registration fails after files become available,
restart the game; the current Viewpoint version remembers failed first attempts
for the process. The adapter never clears other mods' registry entries.
