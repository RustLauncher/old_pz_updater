# Dr Pepper Fridge 1.0.7 — save-compatible poster update

Dr Pepper Fridge 1.0.7 for Project Zomboid 42.21. The local validation report records the completed checks and their scope.

The update separates the overlapping poster registrations: Dr Pepper posters use tile-definition number **4865**, More Damaged Objects keeps **4864**, and clean/worn Dr Pepper fridges keep **4863**. The Workshop item, mod ID and Dr Pepper inventory item types remain the same.

## Helper correction in 1.0.7

On Windows, singleplayer preparation reads the stored mode and world directory names before writing the index. Arguments with different capitalization now identify the same save correctly. Exact multiplayer configuration/history matching, backup verification and refusal to overwrite an existing index remain unchanged.

This correction does not rename or rewrite previously created indices. Do not manually rename an old index after adding a conflicting mod or changing the world's history. The 1.0.7 helper tests used isolated profiles only: 22 before/after identity scenarios and the existing 26 safety scenarios passed, with original fixture files unchanged and backups verified.

## Ordinary existing worlds

Normal existing worlds do **not** need an external preparation script to keep playing or saving. Missing preparation is not an error. Objects with an exact saved Dr Pepper sprite name or matching Dr Pepper identity metadata can be restored to the new poster registration. Unmarked objects are not converted merely because their numeric ID or current alias name resembles a poster.

When the old numeric slots are vacant and the migration state has not observed MDO, compatibility aliases can display older posters while retaining their original numeric IDs. This display bridge is not proof of a world's complete mod history. Another mod's registered sprites are never overwritten.

If MDO was previously observed and is now disabled, or stored migration history is invalid or incomplete, vacant old slots receive **inert placeholders**. These retain numeric identities so the game does not discard attached children during loading. They do not receive a Dr Pepper image, collectible name or pickup properties. Exact Dr Pepper identities can still be recovered. Unmarked old attachments retain their original data.

A missing required current Dr Pepper sprite, a conflicting registration, or an actual conversion error is an exceptional asset failure. The mod reports it and temporarily disables normal saving; in singleplayer it also pauses the world. Returning to the menu restores the prior saving setting before the next world loads. This protection is not triggered merely by an ordinary unprepared old world. It is not a replacement for a complete offline backup: native game loading can still touch other world files.

## Pickup, inventory, placement and rotation

Picking up an approved visible legacy poster produces a Dr Pepper item using the canonical poster sprite. Existing inventory items with an exact Dr Pepper item type and the matching legacy poster design are normalized before the furniture cursor looks up their placement sprite, including when MDO is enabled. Incorrect design/type pairings are not converted.

Normalization retains the same inventory object, condition, custom modData and actual pickup weight. Placement uses the final rotated canonical face and records explicit poster identity. Rotation also handles the original alias name retained by vanilla after pickup. The wall itself is not changed into a poster, and forced placement still checks that a suitable, unoccupied wall is available before consuming the item.

## Limit: already mixed, unmarked old objects

The original Dr Pepper and MDO registrations assigned the same numeric IDs to different images. Some old wall attachments stored only those numbers, with no independent name or owner. Their saved bytes cannot reveal which image was intended. Preserving raw IDs retains recovery data, but **cannot guarantee the original appearance** when the mods supplying those IDs change.

This update does not claim universal repair of a world already affected by both original mods. It leaves unknown numeric ownership intact and restores only independently identifiable Dr Pepper objects. Work on a copy for individual recovery, or restore a verified backup from before MDO was introduced. Never confirm Dr-Pepper-only history for a world that used MDO or whose history is uncertain. Removing MDO from today's mod list does not establish that history.

## Optional migration for a verified original Dr-Pepper-only save

The Windows helpers are included in the Workshop content at:

`steamapps/workshop/content/108600/3810693580/mods/DrPepperFridge/42/Tools`

They are designed for **Windows PowerShell 5.1**; PowerShell 7 is not required. Open PowerShell in this Tools folder. Close Project Zomboid and any dedicated/hosted server completely before running a helper. The helpers refuse a detected running game/server and also refuse when a Java process cannot be inspected sufficiently to verify that it is safe to make an offline backup.

`Prepare-LegacySave.ps1` requires an explicit confirmation that the world **never used More Damaged Objects**. It checks retained records, creates a dated backup, verifies the copied world files, and records the existing map chunks without editing binary save files. The user's confirmed history remains necessary; the current mod list alone is not historical proof.

Singleplayer example, using the actual profile folder, save folder name and mode:

```powershell
& './Prepare-LegacySave.ps1' -Profile "$env:USERPROFILE/Zomboid" -World 'YOUR SAVE NAME' -Mode Sandbox -ConfirmDrPepperOnlyHistory
```

A custom launch profile must use its actual profile path instead of the default `Zomboid` folder. The selected world must be under `<Profile>/Saves/<Mode>/<World>`.

Prepare the verified older source **before MDO is first loaded in that world**. Keep the backup until the migrated world has been checked. Do not regenerate or expand the index after MDO has been introduced. The helper refuses to overwrite an existing preparation index.

The prepared ownership boundary allows older numeric posters and the original mod's standard wall attachments to migrate as their areas load, including distant chunks. Standard attachments retain their face, exposed scale and alpha; the host wall stays unchanged. Custom tint, animation state, offsets or flip added by unrelated scripts are outside the certified original placement route. Detectably custom attachments are retained rather than rebuilt with lost state.

A per-square completion marker prevents MDO objects added later to the same area from being interpreted as old Dr Pepper posters. Validated nonempty or explicitly prepared saved ownership takes precedence over an external file. An earlier empty, unprepared identity-only state can accept a later valid preparation only while MDO has never been observed. Once MDO is observed, a new file cannot enlarge ownership. Invalid files or stored records cause identity-only handling, not an ownership guess or a blanket saving block.

`Prepare-FirstInstallation.ps1` is an optional backup/documentation helper for adding Dr Pepper to an existing world for the first time. Run it **before enabling Dr Pepper**. It refuses retained evidence of prior/current Dr Pepper use and incomplete retained history, and records zero Dr-owned legacy chunks:

```powershell
& './Prepare-FirstInstallation.ps1' -Profile "$env:USERPROFILE/Zomboid" -World 'YOUR SAVE NAME' -Mode Sandbox
```

Neither helper reconstructs indistinguishable objects in an already mixed world.

## Dedicated or hosted server preparation

Use **the server's profile**, not a player's client cache. Set `-Mode Multiplayer` and use the **exact server configuration/world name** for `-World`: the name used by `Server/<World>.ini` and `Saves/Multiplayer/<World>`. Do not supply an IP address, port, display title, path or launch argument. A renamed/mismatched world is refused when its retained world identity does not match.

Example for an original server world verified never to have used MDO:

```powershell
& './Prepare-LegacySave.ps1' -Profile 'C:/ZomboidServerProfile' -World 'MyServer' -Mode Multiplayer -ConfirmDrPepperOnlyHistory
```

For first installation, use the same profile/name/mode with `Prepare-FirstInstallation.ps1`, before adding Dr Pepper to the server configuration. The helpers require a complete server world and its matching configuration. In addition to the verified world backup, they copy the server's present configuration, sandbox/spawn files and account database files into a separate `-ServerFiles` backup. Keep both backups. Restore the matching world, configuration and account data together when returning to the source state.

## Multiplayer behavior

The server performs authoritative world migration. Clients do not reinterpret or stamp saved world objects. Before chunks arrive, a client without MDO registers only vacant inert legacy placeholders. A separate compact server decision containing schema, presentation permission and MDO history controls whether those same sprite instances receive Dr Pepper textures and interaction properties. The large persisted chunk map is not sent by this handshake.

Dedicated-server reloads in 42.21 can announce a new world even while loading existing saved data. The mod does not use that flag alone: saved history is retained, and a genuinely new world requires empty state and no native save files. The read-only check uses files in the current world's save directory. A failed or invalid check keeps identity-only handling, without accepting a new ownership index or blocking ordinary saving.

Dedicated servers validate registered IDs, sprite identity and properties without requiring rendering textures. Clients validate display textures.

## Poster-update validation (1.0.6)

The final candidate was tested on Windows with Project Zomboid 42.21. The focused Lua/Kahlua suites completed **55 registry/history/migration checks** and **40 pickup/inventory/cursor checks**. The Windows PowerShell 5.1 helpers completed **45 scenarios: 8 successful preparations and 37 expected refusals**. Their original fixture files remained unchanged and successful backups were verified against their sources.

A native server-copy backup check also verified **707 files, 576 indexed chunks and five server configuration/account files**, using Windows PowerShell 5.1 in a short isolated test profile. The closed original test source was preserved. This separates native backup evidence from the mocked process-inspection scenarios and does not claim arbitrary long-path support.

Native singleplayer completed all ten poster faces, real pickup/placement, condition and custom data preservation, incorrect-type rejection, rotation and inventory cursor lookup (**15 checks**). Saving and reopening with MDO enabled verified all ten stored items and subsequent placement (**10 checks**). World tests covered normal unprepared legacy saves, first installation, verified migration, distant areas and saved/reopened wall attachments.

Dedicated multiplayer covered **52 mixed-world fixtures plus ten actual client placements**, real cursor lookup, authoritative server/client reception, save/reload, MDO removal and another reload after removal. The original Dr-only dedicated-world upgrade preserved its **22 fixture objects** without mandatory preparation. A later verified preparation was accepted before MDO was observed and migrated the original standard attachments.

Repeated server PASS lines are repeated verification, not extra independent tests. The detailed local report identifies the source-associated runs and their logs. These tests cover the listed routes and fixtures; they do not establish compatibility with every third-party mod or reconstruct unknown historical ownership.

Test fixtures, profiles, launchers and research files are not release content. Nick's Moveable Workstations 1.1.0 has a separate 42.21 furniture-placement wrapper issue that omits a required native argument. It is distinct from this poster-ID collision and from Nick's Turn Off Fridges.
