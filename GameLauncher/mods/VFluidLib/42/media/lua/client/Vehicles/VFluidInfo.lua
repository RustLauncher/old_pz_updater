-- The Fluid Info window: tank bars with per-fluid tooltips, the Tank Designation block
-- (service / mode / fluid, the padlock, Clean), mounted vessels, and the consumption panel.

require "ISUI/ISCollapsableWindow"
require "ISUI/ISToolTip"
require "ISUI/ISLayoutManager"

VFluidInfo = VFluidInfo or {}

local ROW_H    = 20
local PAD      = 6
local INDENT   = 20
local DESIG_ROW_H = 22
local COMBO_W     = 150
local LABEL_W     = 46
local BTN_W       = 24
local DESIG_ROWS  = 3
local DIV_GAP = 4
local DIV_H   = 9
local END_PAD = 5
local COMBO_H     = DESIG_ROW_H - 2
local ROW_GAP     = DESIG_ROW_H - COMBO_H
local BLOCK_H     = (DESIG_ROWS - 1) * DESIG_ROW_H + COMBO_H
local BTN_H       = math.floor((BLOCK_H - ROW_GAP) / 2)
local MIN_W    = 340

local FALLBACK = { r = 0.55, g = 0.58, b = 0.60 }

local tr = VFluid.tr

local function axisTint(axis)
	if axis == "fuel"    then return { r = 0.78, g = 0.55, b = 0.18 } end
	if axis == "potable" then return { r = 0.30, g = 0.55, b = 0.78 } end
	if axis == "propane" then return { r = 0.72, g = 0.35, b = 0.30 } end
	if axis == "beverage" then return { r = 0.62, g = 0.50, b = 0.72 } end
	return FALLBACK
end

--------------------------------------------------------------------------------
-- the window
--------------------------------------------------------------------------------

VFluidInfoWindow = ISCollapsableWindow:derive("VFluidInfoWindow")

function VFluidInfoWindow:createChildren()
	ISCollapsableWindow.createChildren(self)
	local th = self:titleBarHeight()
	self.body = ISPanel:new(0, th, self.width, self.height - th)
	self.body:initialise()
	self.body.background = false
	self.body.window = self
	self.body.render = VFluidInfoWindow.renderBody
	self:addView(self.body)
end

function VFluidInfoWindow:ensureFooter()
	if self.footer then return self.footer end
	local f = ISToolTip:new()
	f.followMouse = false
	f:initialise()
	self:addView(f)
	f:setVisible(false)
	self.footer = f
	return f
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local function serviceLabel(o)
	local a = VFluid.axes and VFluid.axes[o.axis]
	return (a and VFluid.axisLabel and VFluid.axisLabel(a)) or tostring(o.axis)
end

local function modeLabel(o)
	if o.mode == VFluid.MODE_SINGLE then return tr("IGUI_VFluid_ModeSingle", "Single Fluid") end
	return tr("IGUI_VFluid_ModeMulti", "Multi Fluid")
end

local function fluidLabel(o)
	if o.kind == "mixture" then return tr("IGUI_VFluid_FluidMixture", "Mixture") end
	if o.kind == "empty" then return tr("IGUI_VFluid_FluidEmpty", "(empty)") end
	if o.kind == "unit" then
		local a = VFluid.axes and VFluid.axes[o.axis]
		return (a and VFluid.axisLabel and VFluid.axisLabel(a)) or tostring(o.axis)
	end
	return (VFluid.fluidLabel and VFluid.fluidLabel(o.fluid)) or tostring(o.fluid)
end

local PENDING_TICKS = 120

local function vol(n)
	if n == math.floor(n) then return string.format("%d L", n) end
	return string.format("%.1f L", n)
end

local function cleanTip(plan)
	local toolName = (plan.tool and plan.tool.getDisplayName and plan.tool:getDisplayName()) or "Mop"
	local gearName = (plan.gear and plan.gear.getDisplayName and plan.gear:getDisplayName()) or "Rubber Gloves"
	local tip = tr("IGUI_VFluid_TipClean",
			"Clean the tank.\nRequires:\n1x %1\n1x %2\n%3 of Water\n%4 of Bleach")
		:gsub("%%1", toolName):gsub("%%2", gearName)
		:gsub("%%3", vol(plan.water)):gsub("%%4", vol(plan.bleach))
	if not plan.ok and plan.why then return tip .. "\n" .. plan.why end
	return tip
end

function VFluidInfoWindow:notePending(partId, fields)
	self.pending = self.pending or {}
	fields.tick = self.tick or 0
	self.pending[partId] = fields
	self:syncDesignation()
end

function VFluidInfoWindow:pendingFor(partId, d, axisId)
	local pend = self.pending and self.pending[partId]
	if not pend then return nil end
	local agreed = (pend.mode == nil or pend.mode == d.mode)
		and (pend.fluid == nil or pend.fluid == d.fluid)
		and (pend.locked == nil or pend.locked == d.userLocked)
		and (pend.axis == nil or pend.axis == axisId)
	if agreed then self.pending[partId] = nil; return nil end
	if ((self.tick or 0) - pend.tick) > PENDING_TICKS then
		self.pending[partId] = nil
		self.failed = self.failed or {}
		self.failed[partId] = (self.tick or 0)
		return nil
	end
	return pend
end

local FAILED_TICKS = 600

function VFluidInfoWindow:failedFor(partId)
	local at = self.failed and self.failed[partId]
	if not at then return false end
	if ((self.tick or 0) - at) > FAILED_TICKS then self.failed[partId] = nil return false end
	return true
end

function VFluidInfoWindow:applyChoice(combo, partId, send)
	local opt = combo.options and combo.options[combo.selected]
	local data = (type(opt) == "table") and opt.data or nil
	if not self.vehicle or not data or not partId then return end
	if data.current or not data.enabled then self:syncDesignation() return end
	send(data)
end

function VFluidInfoWindow:onServiceChanged(combo, partId)
	self:applyChoice(combo, partId, function(data)
		sendClientCommand(self.character, "vfluid", "setmode",
			{ vehicle = self.vehicle:getId(), part = partId, axis = data.axis })
		self:notePending(partId, { axis = data.axis })
	end)
end

function VFluidInfoWindow:onModeChanged(combo, partId)
	self:applyChoice(combo, partId, function(data)
		local fluid = nil
		if data.mode == VFluid.MODE_SINGLE then
			local part = self.vehicle.getPartById and self.vehicle:getPartById(partId)
			local axis = part and VFluid.axisFor(self.vehicle, part)
			fluid = part and axis and VFluid.designationDefaultFluid(self.vehicle, part, axis) or nil
			if not fluid then self:syncDesignation() return end
		end
		sendClientCommand(self.character, "vfluid", "setmode",
			{ vehicle = self.vehicle:getId(), part = partId, mode = data.mode, fluid = fluid })
		self:notePending(partId, { mode = data.mode, fluid = fluid })
	end)
end

function VFluidInfoWindow:onFluidChanged(combo, partId)
	self:applyChoice(combo, partId, function(data)
		sendClientCommand(self.character, "vfluid", "setmode",
			{ vehicle = self.vehicle:getId(), part = partId,
			  mode = VFluid.MODE_SINGLE, fluid = data.fluid })
		self:notePending(partId, { mode = VFluid.MODE_SINGLE, fluid = data.fluid })
	end)
end

function VFluidInfoWindow:onLockToggled(button, partId)
	if not self.vehicle or not partId then return end
	local want = not button.vfLocked
	sendClientCommand(self.character, "vfluid", "setmode",
		{ vehicle = self.vehicle:getId(), part = partId, lock = want })
	self:notePending(partId, { locked = want })
end

function VFluidInfoWindow:onCleanClicked(button, partId)
	if not self.vehicle or not partId then return end
	local part = self.vehicle:getPartById(partId)
	local axis = part and VFluid.axisFor(self.vehicle, part)
	if not axis then return end
	VFluidCleanAction.queue(self.character, self.vehicle, part, axis)
end

local function fillCombo(combo, opts, labelOf, prefer)
	local tips, sel, want = {}, 1, nil
	combo:clear()
	for i = 1, #opts do
		local o = opts[i]
		local label = labelOf(o)
		combo:addOptionWithData(label, o)
		if o.reason then tips[label] = o.reason end
		if o.current then sel = i end
		if prefer and prefer(o) then want = i end
	end
	combo.selected = want or sel
	combo:setToolTipMap(tips)
	return opts[combo.selected]
end

function VFluidInfoWindow:refreshDesignationRow(ui, r, v, part, axis)
	local d = VFluid.designationOf(v, part, axis)
	local pend = self:pendingFor(r.part, d, axis and axis.id)

	local services = VFluid.serviceOptions and VFluid.serviceOptions(v, part) or {}
	fillCombo(ui.service, services, serviceLabel,
		pend and pend.axis and function(o) return o.axis == pend.axis end or nil)
	local anySvc = false
	for _, o in ipairs(services) do if o.enabled and not o.current then anySvc = true end end
	ui.service.disabled = not anySvc

	local requiresClean = nil
	if not d.fixed and (d.locked or d.unserviceable) then
		requiresClean = (axis and axis.kind ~= "fluid")
			and tr("IGUI_VFluid_TipClosedSystem", "This is a closed system.")
			or tr("IGUI_VFluid_TipRequiresClean", "Requires drain and clean to switch.")
	end
	local function comboDefaultTip(combo, tip)
		local m = combo.tooltip
		if type(m) ~= "table" then m = {}; combo:setToolTipMap(m) end
		m.defaultTooltip = tip
	end
	if ui.service.disabled and not d.unserviceable then comboDefaultTip(ui.service, requiresClean) end

	if d.unserviceable then
		ui.service:clear()
		ui.service:addOptionWithData(tr("IGUI_VFluid_ServiceCompromised", "Compromised"),
			{ compromised = true })
		ui.service.selected = 1
		ui.service.disabled = true
		ui.service:setToolTipMap({ defaultTooltip = tr("IGUI_VFluid_TipCompromised",
			"This tank holds a mixture no service can carry and is disabled until it is "
			.. "drained and cleaned.") })
	end

	local svcPending = pend and pend.axis and VFluid.afterServiceModes ~= nil
	local modes = svcPending and VFluid.afterServiceModes()
		or VFluid.designationModes(v, part, axis)
	fillCombo(ui.mode, modes, modeLabel,
		(not svcPending) and pend and pend.mode and function(o) return o.mode == pend.mode end or nil)
	local anyMode = false
	for _, o in ipairs(modes) do if o.enabled and not o.current then anyMode = true end end
	ui.mode.disabled = not anyMode
	if ui.mode.disabled then comboDefaultTip(ui.mode, requiresClean) end

	local fluids = svcPending and VFluid.afterServiceFluids(pend.axis)
		or VFluid.designationFluids(v, part, axis, pend and pend.mode or nil)
	ui.fluid.vfCurrent = fillCombo(ui.fluid, fluids, fluidLabel,
		pend and pend.fluid and function(o) return o.fluid == pend.fluid end or nil)
	local anyFluid = false
	for _, o in ipairs(fluids) do if o.enabled and not o.current then anyFluid = true end end
	ui.fluid.disabled = not anyFluid
	if ui.fluid.disabled then comboDefaultTip(ui.fluid, requiresClean) end

	if pend and pend.locked ~= nil then
		ui.lock.vfLocked = pend.locked
	else
		ui.lock.vfLocked = (d.userLocked == true)
	end
	ui.lock:setImage(ui.lock.vfLocked and ui.lockClosed or ui.lockOpen)
	local lockDead = (d.fixed == true) or (d.unserviceable == true)
	ui.lock:setEnable(not lockDead)
	if lockDead then
		ui.lock.tooltip = nil
	elseif ui.lock.vfLocked then
		ui.lock.tooltip = tr("IGUI_VFluid_TipLocked",
			"Only allow fluids according to tank designation.")
	else
		ui.lock.tooltip = tr("IGUI_VFluid_TipUnlocked",
			"Allow any fluids that fit a possible tank designation.")
	end
	local failed = self:failedFor(r.part)
	local bc = failed and { r = 0.85, g = 0.25, b = 0.25, a = 1 } or nil
	ui.service.borderColor = bc or ui.service.vfBorder
	ui.mode.borderColor    = bc or ui.mode.vfBorder
	ui.fluid.borderColor   = bc or ui.fluid.vfBorder

	local plan = VFluid.cleaningPlan(self.character, v, part, axis)
	if plan.need == VFluid.NEED_NONE then
		ui.clean:setEnable(false)
		if not VFluid.cleaningEnabled() then
			ui.clean.tooltip = tr("IGUI_VFluid_TipCleanOff", "Switched off by sandbox settings.")
		else
			ui.clean.tooltip = tr("IGUI_VFluid_TipCleanNone", "Tank does not require cleaning.")
		end
	else
		ui.clean:setEnable(plan.ok == true)
		ui.clean.tooltip = cleanTip(plan)
	end
end

function VFluidInfoWindow:refreshModel()
	local v = self.vehicle
	self.model = v and VFluid.describe(v) or nil
	self:fitToContent()
	self:syncDesignation()
end

function VFluidInfoWindow:syncDesignation()
	self.desigUI = self.desigUI or {}
	for _, ui in pairs(self.desigUI) do
		ui.service:setVisible(false); ui.mode:setVisible(false); ui.fluid:setVisible(false)
		ui.lock:setVisible(false); ui.clean:setVisible(false)
	end
	local d, v = self.model, self.vehicle
	if not d or not v or not self.body then return end
	local g = self:geometry()
	local bw = self.body:getWidth()
	for i = 1, #d.tanks do
		local r, ry = d.tanks[i], g.rowY[i]
		if r.mode and ry then
			local part = v.getPartById and v:getPartById(r.part)
			local axis = part and VFluid.axisFor(v, part)
			if part and axis then
				local ui = self.desigUI[r.part]
				if not ui then
					ui = {}
					ui.lockClosed = getTexture("media/ui/lock.png")
					ui.lockOpen = getTexture("media/ui/lockOpen.png")
					ui.service = ISComboBox:new(0, 0, COMBO_W, COMBO_H, self,
						VFluidInfoWindow.onServiceChanged, r.part)
					ui.service:initialise(); self.body:addChild(ui.service)
					ui.service.vfBorder = ui.service.borderColor
					ui.mode = ISComboBox:new(0, 0, COMBO_W, COMBO_H, self,
						VFluidInfoWindow.onModeChanged, r.part)
					ui.mode:initialise(); self.body:addChild(ui.mode)
					ui.mode.vfBorder = ui.mode.borderColor
					ui.fluid = ISComboBox:new(0, 0, COMBO_W, COMBO_H, self,
						VFluidInfoWindow.onFluidChanged, r.part)
					ui.fluid:initialise(); self.body:addChild(ui.fluid)
					ui.fluid.vfBorder = ui.fluid.borderColor
					ui.clean = ISButton:new(0, 0, BTN_W, BTN_H, "", self,
						VFluidInfoWindow.onCleanClicked)
					ui.clean:initialise(); ui.clean.onClickArgs = { r.part }
					ui.clean.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
					ui.clean:setImage(getTexture("Item_Mop"))
					self.body:addChild(ui.clean)
					ui.lock = ISButton:new(0, 0, BTN_W, BTN_H, "", self,
						VFluidInfoWindow.onLockToggled)
					ui.lock:initialise(); ui.lock.onClickArgs = { r.part }
					ui.lock.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
					self.body:addChild(ui.lock)
					self.desigUI[r.part] = ui
				end
				self:refreshDesignationRow(ui, r, v, part, axis)
				local btnX = bw - 8 - BTN_W
				local comboX = INDENT + LABEL_W
				local comboW = btnX - 8 - comboX
				if comboW < 60 then comboW = 60 end
				local function place(c, n)
					c:setX(comboX); c:setY(ry + n * DESIG_ROW_H); c:setWidth(comboW)
					c:setVisible(true)
				end
				place(ui.service, 0); place(ui.mode, 1); place(ui.fluid, 2)
				ui.clean:setX(btnX); ui.clean:setY(ry)
				ui.lock:setX(btnX);  ui.lock:setY(ry + BTN_H + ROW_GAP)
				ui.clean:setVisible(true); ui.lock:setVisible(true)
			end
		end
	end
end

local BUSY_TICKS = 4
local IDLE_TICKS = 60

local VFluidBarTip = ISPanel:derive("VFluidBarTip")

local TIP_PAD, TIP_GAP = 8, 18

function VFluidBarTip:setRows(rows)
	self.rows = rows or {}
	local tm = getTextManager()
	local f = UIFont.Small
	local nameW, lW, pW = 0, 0, 0
	for i = 1, #self.rows do
		local r = self.rows[i]
		nameW = math.max(nameW, tm:MeasureStringX(f, r.label))
		lW    = math.max(lW,    tm:MeasureStringX(f, r.litres))
		pW    = math.max(pW,    tm:MeasureStringX(f, r.pct))
	end
	self.colL   = TIP_PAD + nameW + TIP_GAP + lW
	self.colPct = self.colL + TIP_GAP + pW
	self:setWidth(self.colPct + TIP_PAD)
	self:setHeight(TIP_PAD * 2 + #self.rows * (tm:getFontHeight(f) + 2))
end

function VFluidBarTip:render()
	local tm = getTextManager()
	local f = UIFont.Small
	local lh = tm:getFontHeight(f) + 2
	self:drawRect(0, 0, self.width, self.height, 0.9, 0.10, 0.10, 0.10)
	self:drawRectBorder(0, 0, self.width, self.height, 0.9, 0.40, 0.40, 0.40)
	local y = TIP_PAD
	for i = 1, #self.rows do
		local r = self.rows[i]
		local c = r.color
		self:drawText(r.label, TIP_PAD, y, c.r, c.g, c.b, 1, f)
		self:drawTextRight(r.litres, self.colL, y, r.tr, r.tg, r.tb, 1, f)
		self:drawTextRight(r.pct, self.colPct, y, r.tr, r.tg, r.tb, 1, f)
		y = y + lh
	end
end

local function barTipRows(r)
	local cap = r.capacity or 0
	if cap <= 0 then return nil end
	local rows, used = {}, 0
	local function push(col, label, amt, dim)
		rows[#rows + 1] = {
			label = tostring(label), color = col or { r = 0.85, g = 0.85, b = 0.85 },
			litres = string.format("%.1f L", amt),
			pct = string.format("%d%%", math.floor(amt / cap * 100 + 0.5)),
			tr = dim and 0.55 or 1, tg = dim and 0.58 or 1, tb = dim and 0.60 or 1,
		}
	end
	for i = 1, #(r.mixture or {}) do
		local m = r.mixture[i]
		if (m.amount or 0) > 0 then
			used = used + m.amount
			push(m.color, m.label or m.fluid, m.amount, false)
		end
	end
	if #rows == 0 and (r.amount or 0) > 0 then
		push(nil, r.tipName or r.contents or "?", r.amount, false)
		used = r.amount
	end
	push({ r = 0.55, g = 0.58, b = 0.60 }, tr("IGUI_VFluid_BarFree", "Free"),
		math.max(0, cap - used), true)
	return rows
end

function VFluidInfoWindow:showBarTooltip(rows)
	if not rows then
		if self.barTip and self.barTip:getIsVisible() then
			self.barTip:setVisible(false)
			self.barTip:removeFromUIManager()
		end
		return
	end
	if not self.barTip then
		self.barTip = VFluidBarTip:new(0, 0, 10, 10)
		self.barTip:initialise()
		self.barTip.background = false
		self.barTip:setAlwaysOnTop(true)
		self.barTip:setVisible(false)
	end
	self.barTip:setRows(rows)
	local mx, my = getMouseX() + 18, getMouseY() + 18
	local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
	if mx + self.barTip:getWidth() > sw then mx = sw - self.barTip:getWidth() - 4 end
	if my + self.barTip:getHeight() > sh then my = sh - self.barTip:getHeight() - 4 end
	self.barTip:setX(mx)
	self.barTip:setY(my)
	if not self.barTip:getIsVisible() then
		self.barTip:addToUIManager()
		self.barTip:setVisible(true)
	end
end

local function drawLevel(panel, x, y, w, h, pct, mixture, tint)
	panel:drawRect(x, y, w, h, 0.85, 0.12, 0.12, 0.12)
	local fillW = math.floor((w - 2) * math.max(0, math.min(100, pct)) / 100 + 0.5)
	if fillW > 0 then
		if mixture and #mixture > 0 then
			local cx, left = x + 1, fillW
			for i = 1, #mixture do
				local m = mixture[i]
				local segW = (i == #mixture) and left
					or math.floor(fillW * (m.pct or 0) / 100 + 0.5)
				if segW > left then segW = left end
				if segW > 0 then
					local c = m.color or FALLBACK
					panel:drawRect(cx, y + 1, segW, h - 2, 0.95, c.r, c.g, c.b)
					cx, left = cx + segW, left - segW
				end
			end
		else
			panel:drawRect(x + 1, y + 1, fillW, h - 2, 0.9, tint.r, tint.g, tint.b)
		end
	end
	panel:drawRectBorder(x, y, w, h, 0.8, 0.4, 0.4, 0.4)
end

local function fmtRate(rate, unit)
	if type(rate) ~= "number" then return rate and tostring(rate) or "" end
	local u = unit or "L/h"
	if rate == math.floor(rate) then return string.format("%d %s", rate, u) end
	return string.format("%.1f %s", rate, u)
end

local function fmtAmount(a, cap)
	return string.format("%d / %d", math.floor((a or 0) + 0.5), math.floor((cap or 0) + 0.5)) .. " L"
end

function VFluidInfoWindow.renderBody(panel)
	local self = panel.window
	local d = self.model
	if not d then return end
	local tm = getTextManager()
	local fh = tm:getFontHeight(UIFont.Small)
	local w = panel:getWidth()
	local y = PAD
	self.barHits = {}

	local function section(title)
		panel:drawText(title, 8, y, 0.75, 0.78, 0.80, 1, UIFont.Small)
		y = y + fh + 2
	end

	local function divider(dy)
		if dy then panel:drawRect(0, dy, w, 1, 0.55, 0.42, 0.45, 0.47) end
	end

	if #d.tanks == 0 and #d.mounted == 0 then
		panel:drawText(getText("IGUI_VFluid_NoTanks"), 8, y, 0.7, 0.7, 0.7, 1, UIFont.Small)
		return
	end

	if ISVehicleMenu and ISVehicleMenu.getVehicleDisplayName then
		local ok, vname = pcall(ISVehicleMenu.getVehicleDisplayName, self.vehicle)
		if ok and vname and vname ~= "" then
			panel:drawText(vname, 8, y, 1, 1, 1, 1, UIFont.Medium)
			y = y + tm:getFontHeight(UIFont.Medium) + 4
		end
	end

	local amountW = 0
	local function widest(r)
		local wmax = tm:MeasureStringX(UIFont.Small, fmtAmount(r.capacity, r.capacity))
		if wmax > amountW then amountW = wmax end
	end
	for i = 1, #d.tanks do widest(d.tanks[i]) end
	for i = 1, #d.mounted do widest(d.mounted[i]) end

	local function row(label, r)
		local tint = axisTint(r.axis)
		local amountTxt = fmtAmount(r.amount, r.capacity)
		local barX = INDENT + 130
		local barW = w - barX - amountW - 8 - 8
		if barW < 40 then barW = 40 end
		local ty = y + (ROW_H - fh) / 2 - 1
		panel:drawText(label, INDENT, ty, 1, 1, 1, 1, UIFont.Small)

		local px = INDENT + tm:MeasureStringX(UIFont.Small, label) + 6
		if r.tainted then
			local word = tr("IGUI_VFluid_TaintedWord", "Tainted")
			panel:drawText("(", px, ty, 0.62, 0.66, 0.68, 1, UIFont.Small)
			local wx = px + tm:MeasureStringX(UIFont.Small, "(")
			panel:drawText(word, wx, ty, 0.85, 0.55, 0.35, 1, UIFont.Small)
			panel:drawText(")", wx + tm:MeasureStringX(UIFont.Small, word), ty,
				0.62, 0.66, 0.68, 1, UIFont.Small)
		elseif r.contents then
			panel:drawText("(" .. r.contents .. ")", px, ty, 0.62, 0.66, 0.68, 1, UIFont.Small)
		end

		drawLevel(panel, barX, y + 4, barW, ROW_H - 8, r.pct or 0, r.mixture, tint)
		self.barHits[#self.barHits + 1] =
			{ x = barX, y = y + 4, w = barW, h = ROW_H - 8, row = r }
		panel:drawTextRight(amountTxt, w - 8, ty, 1, 1, 1, 1, UIFont.Small)
		y = y + ROW_H + 2
	end

	if #d.tanks > 0 then
		section(getText("IGUI_VFluid_SectionTanks"))
		for i = 1, #d.tanks do row(d.tanks[i].label or d.tanks[i].part, d.tanks[i]) end
	end
	if #d.mounted > 0 then
		y = y + 2
		section(getText("IGUI_VFluid_SectionMounted"))
		for i = 1, #d.mounted do row(d.mounted[i].label or d.mounted[i].part, d.mounted[i]) end
	end

	local g = self:geometry()
	for i = 1, #d.tanks do
		local ty, ry = g.titleY[i], g.rowY[i]
		if ty and ry then
			divider(g.divY[i])
			local nm = d.tanks[i].label or d.tanks[i].part
			local head = tr("IGUI_VFluid_SectionDesignation", "Tank Designation") .. " (" .. nm .. ")"
			panel:drawText(head, 8, ty, 0.75, 0.78, 0.80, 1, UIFont.Small)
			if self:failedFor(d.tanks[i].part) then
				panel:drawText("  " .. tr("IGUI_VFluid_NotPersisted", "SETTING NOT PERSISTED TO SERVER"),
					8 + getTextManager():MeasureStringX(UIFont.Small, head), ty,
					0.85, 0.25, 0.25, 1, UIFont.Small)
			end
			local function rowLabel(k, dflt, n)
				panel:drawText(tr(k, dflt), INDENT,
					ry + n * DESIG_ROW_H + (DESIG_ROW_H - fh) / 2, 0.82, 0.85, 0.87, 1, UIFont.Small)
			end
			rowLabel("IGUI_VFluid_RowService", "Service:", 0)
			rowLabel("IGUI_VFluid_RowMode",    "Mode:",    1)
			rowLabel("IGUI_VFluid_RowFluid",   "Fluid:",   2)
		end
	end

	local blocks = d.consumerBlocks or {}
	if #blocks > 0 and g.consY then
		divider(g.consDivY)
		local cy = g.consY
		for i = 1, #blocks do
			local b = blocks[i]
			local sup = ""
			for j = 1, #(b.supply or {}) do
				sup = (j == 1) and tostring(b.supply[j]) or (sup .. ", " .. tostring(b.supply[j]))
			end
			local head
			if b.kind == "use" then
				head = tr("IGUI_VFluid_SectionAppliances", "Piped Appliances")
			else
				local fl = (VFluid.fluidLabel and VFluid.fluidLabel(b.fluid)) or b.fluid
				head = tostring(fl) .. " " .. tr("IGUI_VFluid_Usage", "Usage")
			end
			local paren
			if sup == "" then
				paren = tr("IGUI_VFluid_NoUsableSupply", "No usable supply tank")
			elseif (b.available or 0) <= 0 then
				paren = tr("IGUI_VFluid_SupplyEmpty", "Empty")
			else
				paren = tr("IGUI_VFluid_Supply", "Supply") .. ": " .. sup
			end
			panel:drawText(head .. " (" .. paren .. ")",
				8, cy, 0.75, 0.78, 0.80, 1, UIFont.Small)
			cy = cy + fh + 2
			for j = 1, #b.rows do
				local r = b.rows[j]
				panel:drawText(tostring(r.label), INDENT, cy, 1, 1, 1, 1, UIFont.Small)
				local v = fmtRate(r.value, r.unit)
				if v ~= "" then
					panel:drawTextRight(v, w - 10, cy, 0.82, 0.85, 0.87, 1, UIFont.Small)
				end
				cy = cy + fh + 2
			end
			if b.kind == "rate" then
				local total = tr("IGUI_VFluid_Total", "Total")
				if b.runtimeHours then
					local rt = (b.runtimeHours >= 100)
						and string.format("~%.0f d", b.runtimeHours / 24)
						or  string.format("~%.0f h", b.runtimeHours)
					total = total .. " (" .. tr("IGUI_VFluid_Runtime", "Runtime") .. " " .. rt .. ")"
				end
				panel:drawText(total .. ":", 8, cy, 0.75, 0.78, 0.80, 1, UIFont.Small)
				panel:drawTextRight(fmtRate(b.totalRate, "L/h"), w - 10, cy,
					0.82, 0.85, 0.87, 1, UIFont.Small)
				cy = cy + fh + 2
			end
		end
	end

	divider(g.endDivY)

	local over = nil
	if panel:isMouseOver() then
		local mx, my = panel:getMouseX(), panel:getMouseY()
		for i = 1, #self.barHits do
			local b = self.barHits[i]
			if mx >= b.x and mx <= b.x + b.w and my >= b.y and my <= b.y + b.h then
				over = barTipRows(b.row)
				break
			end
		end
	end
	self:showBarTooltip(over)
end

function VFluidInfoWindow:geometry()
	local d = self.model
	local tm = getTextManager()
	local fh = tm:getFontHeight(UIFont.Small)
	local g = { fh = fh, rowY = {}, titleY = nil, total = ROW_H }
	if not d then return g end
	if #d.tanks == 0 and #d.mounted == 0 then
		g.total = PAD + fh + PAD
		return g
	end
	local y = PAD + tm:getFontHeight(UIFont.Medium) + 4
	local function block(n) y = y + fh + 2 + n * (ROW_H + 2) end
	if #d.tanks > 0 then block(#d.tanks) end
	if #d.mounted > 0 then y = y + 2; block(#d.mounted) end
	g.titleY, g.divY = {}, {}
	for i = 1, #d.tanks do
		if d.tanks[i].mode then
			g.divY[i] = y + DIV_GAP
			y = y + DIV_H
			g.titleY[i] = y
			y = y + fh + 2
			g.rowY[i] = y
			y = y + DESIG_ROW_H * DESIG_ROWS + 2
		end
	end
	local blocks = d.consumerBlocks or {}
	local consLines = 0
	for i = 1, #blocks do
		consLines = consLines + 1 + #blocks[i].rows
		if blocks[i].kind == "rate" then consLines = consLines + 1 end
	end
	if consLines > 0 then
		g.consDivY = y + DIV_GAP
		y = y + DIV_H
		g.consY = y
		y = y + consLines * (fh + 2)
	end
	g.endDivY = y + DIV_GAP
	g.total = g.endDivY + 1 + END_PAD
	return g
end

function VFluidInfoWindow:contentHeight()
	return self:geometry().total
end

function VFluidInfoWindow:footerText()
	return nil
end

function VFluidInfoWindow:fitToContent()
	if not self.model or not self.body then return end
	local th = self:titleBarHeight()
	local bodyH = self:contentHeight()
	self.body:setHeight(bodyH)
	self.body:setWidth(self:getWidth())

	local footH = 0
	local txt = self:footerText()
	if txt then
		local f = self:ensureFooter()
		f.description = " <SETX:" .. math.max(200, self:getWidth() - 30) .. "> <LINE> " .. txt
		f:setX(0)
		f:setY(th + bodyH)
		f:setWidth(self:getWidth())
		f:setVisible(true)
		footH = f:getHeight()
	elseif self.footer then
		self.footer:setVisible(false)
	end

	local want = th + bodyH + footH
	if math.abs(self:getHeight() - want) > 1 then self:setHeight(want) end
end

function VFluidInfoWindow:update()
	ISCollapsableWindow.update(self)
	local v = self.vehicle
	if not v or v:isRemovedFromWorld() then self:close() return end
	self.tick = (self.tick or 0) + 1
	local every = VFluid.isDrawing(v) and BUSY_TICKS or IDLE_TICKS
	if not self.model or (self.tick % every) == 0 then
		self:refreshModel()
	end
end

function VFluidInfoWindow:close()
	self:showBarTooltip(nil)
	self:setVisible(false)
	self:removeFromUIManager()
end

function VFluidInfoWindow:new(x, y, character, vehicle)
	local o = ISCollapsableWindow.new(self, x, y, MIN_W, 64)
	o.character = character
	o.vehicle = vehicle
	o:refreshModel()
	o:setResizable(false)
	o:setTitle(getText("IGUI_VFluid_InfoTitle"))
	o:setHeight(o:titleBarHeight() + o:contentHeight())
	return o
end

--------------------------------------------------------------------------------

VFluidInfoWindow.windows = VFluidInfoWindow.windows or {}

local function closeStrayPanels(keep)
	if not UIManager or not UIManager.getUI then return end
	local ok, list = pcall(function() return UIManager.getUI() end)
	if not ok or not list or not list.size then return end
	for i = list:size() - 1, 0, -1 do
		local okE, e = pcall(function() return list:get(i) end)
		if okE and e and e ~= keep then
			local okT, ours = pcall(function() return e.Type == "VFluidInfoWindow" end)
			if okT and ours then
				pcall(function() e:setVisible(false) end)
				pcall(function() e:removeFromUIManager() end)
			end
		end
	end
end

function VFluidInfo.open(playerObj, vehicle)
	if not playerObj or not vehicle or not VFluid then return end
	local w = VFluidInfoWindow.windows[playerObj]
	if w then
		w.vehicle = vehicle
	else
		local pn = playerObj:getPlayerNum()
		w = VFluidInfoWindow:new(getPlayerScreenLeft(pn) + 70, getPlayerScreenTop(pn) + 50,
			playerObj, vehicle)
		w:initialise()
		w:addToUIManager()
		VFluidInfoWindow.windows[playerObj] = w
		if pn == 0 and ISLayoutManager and ISLayoutManager.RegisterWindow then
			ISLayoutManager.RegisterWindow('vfluidinfo', ISCollapsableWindow, w)
		end
	end
	closeStrayPanels(w)
	w:setVisible(true)
	w:addToUIManager()
	w:refreshModel()
	return w
end

local function infoWhen(ctx)
	if not (VFluid and ctx and ctx.vehicle) then return false end
	local d = VFluid.describe(ctx.vehicle)
	return #d.tanks > 0 or #d.mounted > 0
end

if VRadial and VRadial.register then
	VRadial.register{
		id       = "vfluid.tank.info",
		order    = 110,
		surfaces = { "outside", "seated" },
		when     = infoWhen,
		build    = function(ctx, add)
			add{
				text = getText("ContextMenu_VFluid_Info"),
				icon = getTexture("media/ui/vfluid/fluid_info.png"),
				handler = VFluidInfo.open,
				args = { ctx.player, ctx.vehicle },
			}
		end,
	}
end
if VContext and VContext.register then
	VContext.register{
		id    = "vfluid.tank.info",
		order = 110,
		build = function(ctx, add)
			if not infoWhen(ctx) then return end
			add{
				text = getText("ContextMenu_VFluid_Info"),
				icon = getTexture("media/ui/vfluid/fluid_info.png"),
				handler = VFluidInfo.open,
				args = { ctx.player, ctx.vehicle },
			}
		end,
	}
end
