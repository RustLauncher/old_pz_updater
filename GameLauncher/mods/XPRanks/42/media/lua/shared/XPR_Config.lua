XPR_Config = XPR_Config or {}

--! DO NOT SET XPR_Config.DEBUG = true IN PRODUCTION IT WILL FLOOD YOUR SERVER AND CLIENTS WITH PRINTS !--

XPR_Config.DEBUG = false

XPR_Config.DEBUG_AUTHOR_USERNAME = "ObnoxiouslyNoxious"

XPR_Config.MAX_XP_PER_AWARD = 100000

XPR_Config.MAX_REWARD_BOXES_PER_AWARD = 50

XPR_Config.NOTIFICATION_QUIET_MS = 3000

function XPR_dprint(...)
	if XPR_Config.DEBUG then print(...) end
end

function XPR_ErrorPrint(...)
	print("[XPR][ERROR] ", ...)
end

return XPR_Config
