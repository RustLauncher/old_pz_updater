-- Renames the mechanics window's storage lines to the tank's designated service.

VFluidMechanics = VFluidMechanics or {}

local tr = VFluid.tr

local function suffixOf(self, part)
	local ok, contents = pcall(function()
		return self:roundContainerContentAmount(part) .. " / " .. part:getContainerCapacity()
	end)
	if not ok or not contents then return nil end
	return ": " .. contents
end

function VFluidMechanics.serviceWord(vehicle, part)
	if not (VFluid and VFluid.axisFor) then return nil end
	if VFluid.vanillaRules and VFluid.vanillaRules() then return nil end
	local axis = VFluid.axisFor(vehicle, part)
	if not axis or axis.kind ~= "fluid" then return nil end
	if VFluid.designationOf then
		local d = VFluid.designationOf(vehicle, part, axis)
		if d and d.unserviceable then
			return tr("IGUI_VFluid_ServiceCompromised", "Compromised")
		end
	end
	return VFluid.axisLabel and VFluid.axisLabel(axis) or nil
end

function VFluidMechanics.install()
	if not ISVehicleMechanics then return end
	if ISVehicleMechanics.renderPartDetail == VFluidMechanics._detailWrapper then return end

	local prev = ISVehicleMechanics.renderPartDetail
	VFluidMechanics._detailWrapper = function(self, part)
		local word = nil
		local ok = pcall(function()
			word = VFluidMechanics.serviceWord(self.vehicle, part)
		end)
		local suffix = (ok and word) and suffixOf(self, part) or nil
		if not suffix then return prev(self, part) end

		local storage = tr("IGUI_VFluid_StorageSuffix", "Storage")
		local own, draw = rawget(self, "drawText"), self.drawText
		self.drawText = function(s, text, x, y, r, g, b, a, font)
			if type(text) == "string" then
				local at = string.find(text, suffix, 1, true)
				if at and at + string.len(suffix) - 1 == string.len(text) then
					text = word .. " " .. storage .. suffix
				end
			end
			return draw(s, text, x, y, r, g, b, a, font)
		end
		local drew, err = pcall(prev, self, part)
		self.drawText = own
		if not drew then error(err) end
	end
	ISVehicleMechanics.renderPartDetail = VFluidMechanics._detailWrapper
end

Events.OnGameStart.Add(VFluidMechanics.install)
Events.OnGameBoot.Add(VFluidMechanics.install)
