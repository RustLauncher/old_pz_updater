# Optional Project Viewpoint models

Redbull Freezer 1.1.0 adds a lightweight 3D model pack for Project Viewpoint.
Project Viewpoint and its dependencies are optional. Enable Redbull Freezer as
usual for ordinary isometric play; no extra installation step is needed.

Only Redbull's own sprites are bound to this pack. Vanilla small freezers and
other mods' sprite mappings are not replaced. The existing four orientations,
three decorative stock levels and powered/unpowered appearances are retained.
The normal freezer scripts continue to control stock thresholds, electricity,
blue lighting, Nick's Turn Off Fridges integration, sounds and movement.
Decorative cans do not add items or change storage capacity.

The client registers the model pack only when Project Viewpoint is active and
its model-pack API is available, including client-only Viewpoint in multiplayer.
An inactive API left in memory or a Java mod marked as banned is not sufficient.
No new Java addon is installed. No saved tile IDs, physical sprite names,
containers, inventory items, Sandbox values or movableData are changed.

To use the 3D models, install and enable Project Viewpoint and its dependencies
according to their authors' instructions, then fully restart the game after
Steam finishes downloading. Open Viewpoint settings with Delete (default):

- Graphics > General > 3D model packs: enabled.
- World > Model packs > Redbull Freezer [B42]: enabled.
- World > Levels of detail > Model packs' models within (chunks): above 0.

Viewpoint's Low graphics preset sets the model-pack range to 0 and uses sprite
art instead. Farther chunks also use sprite art. Disabling Viewpoint's camera
returns to normal isometric rendering; disabling Viewpoint itself leaves the
original Redbull mod working normally.

The models are built from the mod's original sprite artwork. The glass opening
has the same size in all stock states. It does not rely on unsupported MTL
glass transparency or a second light source. Existing in-game blue lighting
remains owned by Redbull Freezer.

If first registration fails because files were not ready, restart the game:
Viewpoint currently remembers a failed first attempt for that process. This
adapter never clears another mod's registry or changes Viewpoint preferences.

Project Viewpoint:
https://steamcommunity.com/sharedfiles/filedetails/?id=3809306528

Report bugs in the Redbull Workshop comments with a screenshot, game/Viewpoint
versions, singleplayer or multiplayer, and relevant console.txt errors.

Validation details and limits are recorded in the candidate's verification
report. Native CPU tests are not a substitute for an in-game GPU visual check.
