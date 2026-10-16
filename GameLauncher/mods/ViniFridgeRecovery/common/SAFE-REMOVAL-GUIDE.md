# Safe removal of VINI fridge and freezer appearances

This guide applies to Coca-Cola ICE, Monster, Redbull, Pepsi and Dr Pepper in Project Zomboid 42.21. The optional support mod is named **VINI Furniture Recovery [B42]**, with Mod ID `ViniFridgeRecovery`.

1. Close the game or server. Back up the complete save. For a server, keep its matching settings and player/account files with that backup.
2. Update the original VINI fridge/freezer packages and keep them enabled for this preparation. Each of the five updated packages supplies the same optional recovery mod. Keep at least one supplying package installed.
3. Enable **VINI Furniture Recovery [B42]** in the world's mod list **while the original appearance mods are still enabled**. In multiplayer, the server and players must receive the same updated files.
4. For a normal, undamaged world, load it, let loading finish, save, and close the game/server. The updated originals record exact furniture identities as objects load; Recovery leaves active appearance families unchanged. This step does not claim that every distant area has been visited or converted.
5. Disable the original fridge/freezer appearances you want to remove, leaving **VINI Furniture Recovery [B42]** enabled.
6. Load the world again. Supported old furniture uses the game's original appearance and its storage remains available.
7. Keep the recovery support enabled while unseen areas or stored furniture still reference the disabled appearance mods. **It must also remain enabled for as long as the save contains any Dr Pepper cans, custom Dr Pepper fluids, Dr Pepper poster items, or old poster aliases attached to walls.**

Do not unsubscribe from every package supplying Recovery unless a standalone copy has already been installed. Do not remove Recovery simply because the room around the player looks correct: that does not prove the entire world and all stored items have been converted.

Loading or visiting an area does not convert retained Dr Pepper item/fluid types or every wall-poster attachment to ordinary game types. Current wall posters can remain supported aliases. Keep Recovery enabled while any of these references remain, even after the fridges use their original game appearance.

## Standalone local copy before unsubscribing

1. Close Project Zomboid or the server.
2. Locate the complete `ViniFridgeRecovery` folder inside any updated installed VINI Workshop package. Its usual location is `steamapps/workshop/content/108600/<Workshop ID>/mods/ViniFridgeRecovery` in the Steam library. For example, Coca-Cola ICE uses Workshop ID `3796500904`.
3. Copy that **entire folder** into the local `mods` directory of the game's actual cache/profile folder. On a default Windows installation, the final path is `%USERPROFILE%\Zomboid\mods\ViniFridgeRecovery`. Keep both `42` and `common` directly inside that folder, including all their files. If the game or server uses a custom `-cachedir`, use `<that cache folder>/mods/ViniFridgeRecovery` instead.
4. Start the game/server and keep Mod ID `ViniFridgeRecovery` enabled for the affected world. For a multiplayer server, also keep it in the server's `Mods` setting and provide the same standalone files to players before removing every Workshop provider.

Only cancel all supplying Workshop subscriptions **after** this complete local copy is present and enabled. Copying just `42` or a few Lua files is insufficient. Keep the local support mod enabled while unvisited areas or stored furniture may still reference the removed appearances, and while any retained Dr Pepper cans, fluids, poster items or wall-poster aliases remain.

If a world was already loaded and saved after disabling the originals, work on a copy first. The preparation sequence above does not require you to reactivate originals in an already damaged or conflicting world. Recovery can use surviving original IDs or an exact saved identity. If both the original ID and every independent record of orientation were lost, restore the backup rather than guessing or destroying the furniture.

Recovery retains the current Dr Pepper can, fluid and poster item types so those saved items are not discarded. It uses native placeholder appearances while the original mod is disabled. It does not reinterpret the ambiguous old poster IDs shared with More Damaged Objects.

Recovery is optional for ordinary play with the original appearance mods enabled. After disabling an original, it is required for the remaining references described above. Recovery does not replace the graphics of families that are still active.
