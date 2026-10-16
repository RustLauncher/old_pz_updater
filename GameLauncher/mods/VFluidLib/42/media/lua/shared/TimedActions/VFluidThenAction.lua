-- A zero-length action that runs one function when the queue reaches it - lets a walk
-- finish before a vanilla handler fires.
-- Sorts before VFluidWashAction.lua; a file defining a global must load before the file
-- calling it. DO NOT RENAME.

require "TimedActions/ISBaseTimedAction"

VFluidThenAction = ISBaseTimedAction:derive("VFluidThenAction")

function VFluidThenAction:isValid() return true end
function VFluidThenAction:waitToStart() return false end
function VFluidThenAction:update() end
function VFluidThenAction:start() end
function VFluidThenAction:stop() ISBaseTimedAction.stop(self) end
function VFluidThenAction:getDuration() return 1 end

function VFluidThenAction:perform()
	if self.fn then pcall(self.fn) end
	ISBaseTimedAction.perform(self)
end

function VFluidThenAction:new(character, fn)
	local o = ISBaseTimedAction.new(self, character)
	o.character = character
	o.fn = fn
	o.maxTime = 1
	o.stopOnWalk = false
	o.stopOnRun = false
	return o
end
