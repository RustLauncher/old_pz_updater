if isServer() and not isClient() then return end

require "XPR_PatchNotes"
require "ObNoxPatchNotes"

local function resolveEntries(entries)
	local resolved = {}
	for _, entry in ipairs(entries or {}) do
		local copy = {}
		for key, value in pairs(entry) do copy[key] = value end
		if copy.header then copy.header = getText(copy.header) end
		if copy.line then copy.line = getText(copy.line) end
		resolved[#resolved + 1] = copy
	end
	return resolved
end

local function resolveHistory(history)
	local resolved = {}
	for _, versionEntry in ipairs(history or {}) do
		resolved[#resolved + 1] = {
			version = versionEntry.version,
			date = versionEntry.date,
			notes = resolveEntries(versionEntry.notes),
		}
	end
	return resolved
end

local registered = false
local function registerPatchNotes()
	if registered then return end
	if not (ObNoxPatchNotes and ObNoxPatchNotes.register) then return end
	registered = true
	ObNoxPatchNotes.register("XPR", "XP Ranks", XPR_PatchNotes.CURRENT_VERSION,
		resolveHistory(XPR_PatchNotes.History), {}, "[B42]XPRanks", nil, "3799796873")
end

if Events then
	Events.OnFETick.Add(registerPatchNotes)
	Events.OnGameStart.Add(registerPatchNotes)
	Events.OnCreatePlayer.Add(registerPatchNotes)
end
