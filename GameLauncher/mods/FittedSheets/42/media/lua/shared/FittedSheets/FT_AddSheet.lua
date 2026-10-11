-- ISAddSheetAction:complete() is the choke point every player add-sheet
-- path funnels through - in SP, and in MP both the client-side action
-- and the server's NetTimedAction re-run of it.
--
-- The vanilla complete runs FIRST and untouched - IsoWindow.addSheet
-- does its own side pick, occupancy guard, sheet consumption and MP
-- transmit, exactly as without the mod. Only afterwards, if the window
-- is big, is the freshly hung half-tile sheet swapped for the fitted one
-- in whichever slot vanilla chose (FT_Core.reskinWindowSheets).
-- Placement rules therefore always match the running game's, not a
-- mirror of them. Doors pass through untouched: their vanilla sheet is
-- private door state (hasCurtain), which also gates the Java-built "Add
-- Sheet" menu option - only vanilla setting it keeps the menu honest.
--
-- Server/SP only: on an MP client the swap is left to the server's
-- re-run (whose remove + place transmits bring every client along); the
-- acting client sees the fitted sheet after the server round trip.
--
-- The add paths this cannot see are Java's own: the randomized
-- buildings (safehouse, gunstore siege, ...) and stash houses hang
-- sheets as a building first generates. Those are caught by the
-- LoadGridsquare / LoadChunk sweeps in FT_Server.lua instead.

require "TimedActions/ISAddSheetAction"
require "FittedSheets/FT_Core"

local vanillaComplete = ISAddSheetAction.complete

function ISAddSheetAction:complete()
	local item = self.item
	local done = vanillaComplete(self)
	if not isClient() and item and instanceof(item, "IsoWindow") then
		FittedSheets.reskinWindowSheets(item)
	end
	return done
end
