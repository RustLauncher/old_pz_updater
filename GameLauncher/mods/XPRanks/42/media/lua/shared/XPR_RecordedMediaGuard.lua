XPR_RecordedMediaGuard = XPR_RecordedMediaGuard or {}
XPR_RecordedMediaGuard.active = false

local function installGuardWrapper()
	if XPR_RecordedMediaGuard._installed then return end
	if ISRadioInteractions and ISRadioInteractions.getInstance then
		local inst = ISRadioInteractions:getInstance()
		if inst and inst.checkPlayer then
			XPR_RecordedMediaGuard._installed = true
			local origCheckPlayer = inst.checkPlayer
			inst.checkPlayer = function(...)
				XPR_RecordedMediaGuard.active = true
				origCheckPlayer(...)
				XPR_RecordedMediaGuard.active = false
			end
			XPR_dprint("[XPR] XPR_RecordedMediaGuard: wrapped ISRadioInteractions checkPlayer")
		else
			XPR_ErrorPrint("XPR_RecordedMediaGuard: ISRadioInteractions instance has no checkPlayer, guard NOT installed")
		end
	else
		XPR_ErrorPrint("XPR_RecordedMediaGuard: ISRadioInteractions not found, guard NOT installed")
	end
end

if Events then
	Events.OnConnected.Add(function() installGuardWrapper() end)
	Events.OnConnectFailed.Add(function() installGuardWrapper() end)
	Events.OnTick.Add(function() installGuardWrapper() end)
else
	installGuardWrapper()
end

return XPR_RecordedMediaGuard
