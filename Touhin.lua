--------------------------------------------------------------------------------
-- Touhin!
--

local _, Touhin = ...
LibStub("AceAddon-3.0"):NewAddon(Touhin, "Touhin", "AceEvent-3.0", "AceTimer-3.0")

local L = LibStub("AceLocale-3.0"):GetLocale("Touhin")
Touhin.L = L

-- Debug
_G.Touhin = Touhin

function Touhin:Print(...)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Touhin|r: " .. string.join(" ", tostringall(...)))
end

--------------------------------------------------------------------------------
-- Locals
--

-- luacheck: globals GameTooltip C_LootHistory LibStub UIParent AlertFrame LootHistoryFrame
-- luacheck: globals GameTooltip_ShowCompareItem LootHistoryFrame_OpenToRoll InterfaceOptionsFrame_OpenToCategory
-- luacheck: globals STANDARD_TEXT_FONT ITEM_QUALITY_COLORS

local media = LibStub("LibSharedMedia-3.0", true)
if media then
	media:Register("statusbar", "TouhinDark", [[Interface\AddOns\Touhin\TouhinDark]])
end

local db
local pName = UnitName("player")
local pClass = select(2, UnitClass("player"))

local CLASS_COLORS = {}

local rollTextures = {
	[LOOT_ROLL_TYPE_PASS] = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
	[LOOT_ROLL_TYPE_NEED] = "Interface\\Buttons\\UI-GroupLoot-Dice-Up",
	[LOOT_ROLL_TYPE_GREED] = "Interface\\Buttons\\UI-GroupLoot-Coin-Up",
	[LOOT_ROLL_TYPE_DISENCHANT] = "Interface\\Buttons\\UI-GroupLoot-DE-Up",
}


--------------------------------------------------------------------------------
-- LibDeformat-3.0 replacement
-- This is Jerry's GetPattern function from LibItemBonus-2.0.
--
-- This is very much a ripoff of Deformat, simplified in that it does not
-- handle merged patterns

local Deformat
do

	local next, ipairs, assert, loadstring = next, ipairs, assert, loadstring
	local tconcat = table.concat
	local function donothing() end

	local cache = {}
	local sequences = {
		["%d*d"] = "%%-?%%d+",
		["s"] = ".+",
		["[fg]"] = "%%-?%%d+%%.?%%d*",
		["%%%.%d[fg]"] = "%%-?%%d+%%.?%%d*",
		["c"] = ".",
	}

	local function get_first_pattern(s)
		local first_pos, first_pattern
		for pattern in next, sequences do
			local pos = s:find("%%%%"..pattern)
			if pos and (not first_pos or pos < first_pos) then
				first_pos, first_pattern = pos, pattern
			end
		end
		return first_pattern
	end

	local function get_indexed_pattern(s, i)
		for pattern in next, sequences do
			if s:find("%%%%" .. i .. "%%%$" .. pattern) then
				return pattern
			end
		end
	end

	local function unpattern_unordered(unpattern, f)
		local i = 1
		while true do
			local pattern = get_first_pattern(unpattern)
			if not pattern then return unpattern, i > 1 end

			unpattern = unpattern:gsub("%%%%" .. pattern, "(" .. sequences[pattern] .. ")", 1)
			f[i] = (pattern ~= "c" and pattern ~= "s")
			i = i + 1
		end
	end

	local function unpattern_ordered(unpattern, f)
		local i = 1
		while true do
			local pattern = get_indexed_pattern(unpattern, i)
			if not pattern then return unpattern, i > 1 end

			unpattern = unpattern:gsub("%%%%" .. i .. "%%%$" .. pattern, "(" .. sequences[pattern] .. ")", 1)
			f[i] = (pattern ~= "c" and pattern ~= "s")
			i = i + 1
		end
	end

	local function GetPattern(pattern)
		local unpattern, f, matched = '^' .. pattern:gsub("([%(%)%.%*%+%-%[%]%?%^%$%%])", "%%%1") .. '$', {}
		if not pattern:find("%1$", nil, true) then
			unpattern, matched = unpattern_unordered(unpattern, f)
			if not matched then
				return donothing
			else
				local locals, returns = {}, {}
				for index, number in ipairs(f) do
					local l = ("v%d"):format(index)
					locals[index] = l
					if number then
						returns[#returns + 1] = "n("..l..")"
					else
						returns[#returns + 1] = l
					end
				end
				locals = tconcat(locals, ",")
				returns = tconcat(returns, ",")
				local code = ("local m, n = string.match, tonumber return function(s) local %s = m(s, %q) return %s end"):format(locals, unpattern, returns)
				return assert(loadstring(code))()
			end
		else
			unpattern, matched = unpattern_ordered(unpattern, f)
			if not matched then
				return donothing
			else
				local i, o = 1, {}
				pattern:gsub("%%(%d)%$", function(w) o[i] = tonumber(w); i = i + 1; end)
				local sorted_locals, returns = {}, {}
				for index, number in ipairs(f) do
					local l = ("v%d"):format(index)
					sorted_locals[index] = ("v%d"):format(o[index])
					if number then
						returns[#returns + 1] = "n("..l..")"
					else
						returns[#returns + 1] = l
					end
				end
				sorted_locals = tconcat(sorted_locals, ",")
				returns = tconcat(returns, ",")
				local code =("local m, n = string.match, tonumber return function(s) local %s = m(s, %q) return %s end"):format(sorted_locals, unpattern, returns)
				return assert(loadstring(code))()
			end
		end
	end

	function Deformat(text, pattern)
		local func = cache[pattern]
		if not func then
			func = GetPattern(pattern)
			cache[pattern] = func
		end
		return func(text)
	end
end


--------------------------------------------------------------------------------
-- Anchor
--

local anchor = nil

local function CreateAnchor()
	local f = CreateFrame("Frame", "TouhinAnchor", UIParent)
	f:SetWidth(220)
	f:SetHeight(18)
	f:ClearAllPoints()
	f:SetPoint(db.anchor_point or "CENTER", db.anchor_x or 0, db.anchor_y or 0)

	local texture = f:CreateTexture(nil, "BACKGROUND")
	texture:SetAllPoints(f)
	texture:SetBlendMode("BLEND")
	texture:SetColorTexture(0, 0, 0, 0.3)

	local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	text:SetAllPoints(f)
	text:SetText("Touhin")

	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" then
			local point, _, _, x, y = self:GetPoint(1)
			db.anchor_point = point
			db.anchor_x = x
			db.anchor_y = y
			self:Hide()
		elseif button == "LeftButton" and IsShiftKeyDown() then
			Touhin:AddLootTest()
		elseif button == "MiddleButton" then
			Touhin:OpenOptions()
		end
	end)

	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, _, x, y = self:GetPoint(1)
		db.anchor_point = point
		db.anchor_x = x
		db.anchor_y = y
	end)

	f:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
		GameTooltip:ClearLines()
		GameTooltip:AddLine("Touhin")
		GameTooltip:AddLine(L.ANCHOR_TOOLTIP, 0.2, 1, 0.2, 1)
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
	end)

	f:Hide()

	anchor = f
end

local function ShowAnchor()
	if not anchor then CreateAnchor() end
	anchor:Show()
end

local function HideAnchor()
	if not anchor then return end
	anchor:Hide()
end

local function UpdateAnchor()
	if not anchor then return end
	anchor:ClearAllPoints()
	anchor:SetPoint(db.anchor_point or "CENTER", db.anchor_x or 0, db.anchor_y or 0)
end

local function ResetAnchor()
	if anchor then
		anchor:ClearAllPoints()
		anchor:SetPoint("CENTER")
	end
	db.anchor_point = nil
	db.anchor_x = nil
	db.anchor_y = nil

	ShowAnchor()
end

local function ToggleAnchor()
	if not anchor or not anchor:IsShown() then
		ShowAnchor()
	else
		HideAnchor()
	end
end


--------------------------------------------------------------------------------
-- Frame stacking
--

local UpdateRows, AddRow, RemoveRow, GetRows, UpdateRowOrdering
do
	local function sorter(a, b)
		return a.time < b.time and true or false
	end

	local rows = {}
	local tmp = {}

	local point, relativePoint, yOffset
	function UpdateRowOrdering()
		point = (db.growDown and "TOP" or "BOTTOM") .. (db.alignLeft and "LEFT" or "RIGHT")
		relativePoint = (db.growDown and "BOTTOM" or "TOP") .. (db.alignLeft and "LEFT" or "RIGHT")
		yOffset = db.rowSpacing * (db.growDown and -1 or 1)
	end

	function UpdateRows(refix)
		wipe(tmp)
		for row in next, rows do
			row:Hide()
			tmp[#tmp + 1] = row
		end
		table.sort(tmp, sorter)

		if not point then UpdateRowOrdering() end

		local last = anchor
		for i=1, db.shownLimit do
			local row = tmp[i]
			if not row then break end
			row:ClearAllPoints()
			row:SetScale(db.scale)
			row:SetPoint(point, last, relativePoint, 0, yOffset)
			row:SetWidth(db.insets + (db.showIcon and db.iconSize or 0) + db.iconGap + row.text:GetStringWidth() + 4 + db.insets)
			row:SetHeight(math.max(22, row.text:GetStringHeight() + db.insets * 2))
			if refix then
				row:Refresh()
			end
			row:Show()
			last = row
		end
	end

	function AddRow(row)
		if not anchor then CreateAnchor() end
		rows[row] = true
		UpdateRows()
	end

	function RemoveRow(row)
		rows[row] = nil
		row:Hide()
		UpdateRows()
	end

	function GetRows()
		return rows
	end
end


--------------------------------------------------------------------------------
-- Frame creation
--

local GetFrame, ReleaseFrame, UpdateFrameBackdrop, UpdateFrameFont
do
	local frameHeap = {}

	-- scripts
	local function fader_OnFinished(self, requested)
		RemoveRow(self.object)
		ReleaseFrame(self.object)
	end

	local function frame_OnShow(self)
		if db.fadeDelay > 0 then
			self.fader:GetParent():Play()
		end
	end

	local function frame_OnEnter(self)
		if not self.link then return end
		GameTooltip:SetOwner(self, "ANCHOR_" .. (db.alignLeft and "RIGHT" or "LEFT"), 0, -self:GetHeight())
		GameTooltip:SetHyperlink(self.link)

		if self.rollId then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(LOOT_ROLLS, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
			GameTooltip:AddTexture([[Interface\Minimap\Tracking\Banker]])
			for itemIdx=1, C_LootHistory.GetNumItems() do
				local rollId, _, numPlayers, _, winnerIdx, isMasterLoot = C_LootHistory.GetItem(itemIdx)
				if self.rollId == rollId then
					if winnerIdx or isMasterLoot then
						for playerIdx=1, numPlayers do
							local name, class, rollType, roll, isWinner, isMe = C_LootHistory.GetPlayerInfo(itemIdx, playerIdx)
							if isMe or roll or isMasterLoot then -- should show
								local line = string.format("%s%s|r", CLASS_COLORS[class], name)
								if roll and roll > 0 then
									line = line .. " - " .. roll
								end
								GameTooltip:AddLine(line, 1, 1, 1)
								GameTooltip:AddTexture(rollTextures[rollType])
							end
						end
					else -- everyone passed
						GameTooltip:AddLine(LOOT_HISTORY_ALL_PASSED, 1, 1, 1)
						GameTooltip:AddTexture(rollTextures[LOOT_ROLL_TYPE_PASS])
					end
					break
				end
			end
			GameTooltip:Show()
		end

		if IsModifiedClick("COMPAREITEMS") or (C_CVar.GetCVarBool("alwaysCompareItems") and not GameTooltip:IsEquippedItem()) then
			GameTooltip_ShowCompareItem()
		end
		if IsModifiedClick("DRESSUP") then
			ShowInspectCursor()
		else
			ResetCursor()
		end

		if db.fadeDelay > 0 then
			self.fader:GetParent():Pause()
		end
	end

	local function frame_OnLeave(self)
		if not self.link then return end
		GameTooltip:Hide()
		ResetCursor()
		frame_OnShow(self)
	end

	local function frame_OnClick(self, button)
		if button == "LeftButton" then
			if IsModifiedClick() then
				HandleModifiedItemClick(self.link)
			elseif self.rollId then
				LootHistoryFrame_OpenToRoll(LootHistoryFrame, self.rollId)
			end
		elseif button == "RightButton" then
			if db.fadeDelay > 0 then
				self.fader:GetParent():Stop()
			else
				fader_OnFinished(self.fader, true)
			end
		end
	end


	-- media
	local fontObject = CreateFont("TouhinItem")
	fontObject:SetFont(STANDARD_TEXT_FONT, 12, "")
	fontObject:SetTextColor(1, 1, 1, 1)
	fontObject:SetShadowOffset(0.8, -0.8)
	fontObject:SetShadowColor(0, 0, 0, 1)
	fontObject:SetJustifyH("LEFT")
	fontObject:SetJustifyV("MIDDLE")

	local background = "Interface\\AddOns\\Touhin\\TouhinDark"
	local backdrop = {
		bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
		tile = true, tileSize = 16,
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16,
		insets = {left = 4, right = 4, top = 4, bottom = 4},
	}

	function UpdateFrameBackdrop()
		if not media then return end

		local bgFile = media:Fetch("statusbar", db.bgFile, true)
		if bgFile then
			background = bgFile
		end

		-- local changed = nil

		local edgeFile = media:Fetch("border", db.edgeFile, true)
		if backdrop.edgeFile ~= edgeFile then
			backdrop.edgeFile = edgeFile
			-- changed = true
		end
		if backdrop.edgeSize ~= db.edgeSize then
			backdrop.edgeSize = db.edgeSize
			-- changed = true
		end
		if backdrop.insets.left ~= db.insets then
			backdrop.insets.left = db.insets
			backdrop.insets.right = db.insets
			backdrop.insets.top = db.insets
			backdrop.insets.bottom = db.insets
			-- changed = true
		end

		--[[
		if changed then
			border glitches occasionally on reused frames, clean our heap if the backdrop changes
			for k in next, GetRows() do
				k.dirty = true
			end
			for i = 1, #frameHeap do
				frameHeap[i]:SetParent(nil)
				frameHeap[i] = nil
			end
		end
		--]]
	end

	function UpdateFrameFont()
		local font = media and media:Fetch("font", db.font, true)
		fontObject:SetFont(font or STANDARD_TEXT_FONT, db.fontSize, "")
	end


	-- prototype
	local function SetRow(self, icon, color, text, hightlightColor)
		self.text:SetText(text)

		self.color = color
		self.borderColor = hightlightColor or color

		if not db.colorBackground then
			color = db.bgColor
		end
		local borderColor = self.borderColor

		self:SetBackdropBorderColor(borderColor.r, borderColor.g, borderColor.b)
		self.background:SetVertexColor(color.r, color.g, color.b, .7)
		self.iconFrame:SetBackdropBorderColor(color.r, color.g, color.b)
		self.icon:SetTexture(icon)

		if self.rollType then
			self.rollIcon:SetNormalTexture(rollTextures[self.rollType])
			self.rollIcon:Show()
		end
	end

	local function Refresh(self)

		self:SetFrameStrata(db.strata)

		self.iconFrame:SetPoint("LEFT", db.insets, 0)
		self.iconFrame:SetSize(db.iconSize, db.iconSize)
		self.iconFrame:SetBackdrop(backdrop)
		if self.color then
			self.iconFrame:SetBackdropBorderColor(self.color.r, self.color.g, self.color.b)
		end

		self.icon:SetPoint("TOPLEFT", self.iconFrame, "TOPLEFT", db.insets, -db.insets)
		self.icon:SetPoint("BOTTOMRIGHT", self.iconFrame, "BOTTOMRIGHT", -db.insets, db.insets)

		self.rollIcon:SetSize(db.iconSize, db.iconSize)
		self.rollIcon:SetScale(db.rollIconScale)

		if db.showIcon then
			self.iconFrame:Show()
			self.text:SetPoint("LEFT", self.iconFrame, "RIGHT", db.iconGap, 0)
		else
			self.iconFrame:Hide()
			self.text:SetPoint("LEFT", self.iconFrame, db.iconGap, 0)
		end

		self:SetBackdrop(backdrop)
		self:SetBackdropColor(db.bgColor.r, db.bgColor.g, db.bgColor.b, db.bgColor.a)
		if self.borderColor then
			self:SetBackdropBorderColor(self.borderColor.r, self.borderColor.g, self.borderColor.b)
		end

		self.background:SetPoint("TOPLEFT", self, "TOPLEFT", db.insets, -db.insets)
		self.background:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -db.insets, db.insets)
		self.background:SetTexture(background)
		if not db.colorBackground then
			self.background:SetVertexColor(db.bgColor.r, db.bgColor.g, db.bgColor.b, .7)
		elseif self.color then
			self.background:SetVertexColor(self.color.r, self.color.g, self.color.b, .7)
		else
			self.background:SetVertexColor(1, 1, 1, 1, .7)
		end
	end


	-- creation/recycling
	function GetFrame()
		local frame = tremove(frameHeap)
		if not frame then
			-- shiney new frame
			frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
			frame:SetHeight(22)
			frame:SetBackdrop(backdrop)
			frame:SetBackdropColor(db.bgColor.r, db.bgColor.g, db.bgColor.b, db.bgColor.a)
			-- frame:SetBackdropBorderColor(1, 1, 1, 1)
			frame:SetFrameStrata(db.strata)

			local texture = frame:CreateTexture(nil, "BORDER")
			texture:SetPoint("TOPLEFT", frame, "TOPLEFT", db.insets, -db.insets)
			texture:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -db.insets, db.insets)
			texture:SetTexture(background)
			frame.background = texture

			local iconFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
			iconFrame:SetPoint("LEFT", db.insets, 0)
			iconFrame:SetSize(db.iconSize, db.iconSize)
			iconFrame:SetBackdrop(backdrop)
			iconFrame:SetBackdropColor(1, 1, 1, 0)
			-- iconFrame:SetBackdropBorderColor(1, 1, 1, 1)
			frame.iconFrame = iconFrame

			local icon = iconFrame:CreateTexture(nil, "OVERLAY")
			icon:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", db.insets, -db.insets)
			icon:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -db.insets, db.insets)
			icon:SetTexCoord(.07, .93, .07, .93) -- 0.1, 0.9, 0.1, 0.9
			frame.icon = icon

			local rollIcon = CreateFrame("Button", nil, iconFrame)
			rollIcon:SetPoint("BOTTOMRIGHT")
			rollIcon:SetSize(db.iconSize, db.iconSize)
			rollIcon:SetScale(db.rollIconScale)
			frame.rollIcon = rollIcon

			local text = frame:CreateFontString(nil, "OVERLAY")
			text:SetPoint("LEFT", iconFrame, "RIGHT", db.iconGap, 0)
			text:SetFontObject(fontObject)
			frame.text = text

			-- a timer and fancy fading in one, pretty neat
			local ag = frame:CreateAnimationGroup()
			ag:SetLooping("NONE")

			local fader = ag:CreateAnimation("Alpha")
			fader:SetFromAlpha(1)
			fader:SetToAlpha(db.fadeTime > 0 and 0 or 1)
			fader:SetStartDelay(db.fadeDelay)
			fader:SetDuration(db.fadeTime > 0 and db.fadeTime or 0.1)
			fader:SetSmoothing("IN")
			fader:SetScript("OnStop", fader_OnFinished)
			fader:SetScript("OnFinished", fader_OnFinished)
			fader.object = frame
			frame.fader = fader


			frame:SetScript("OnShow", frame_OnShow)
			frame:SetScript("OnEnter", frame_OnEnter)
			frame:SetScript("OnLeave", frame_OnLeave) -- GameTooltip_HideResetCursor
			frame:SetScript("OnMouseUp", frame_OnClick)

			frame.SetRow = SetRow
			frame.Refresh = Refresh
		else
			frame.fader:SetStartDelay(db.fadeDelay)
			frame.fader:SetFromAlpha(1)
			frame.fader:SetToAlpha(db.fadeTime > 0 and 0 or 1)
			frame.fader:SetDuration(db.fadeTime > 0 and db.fadeTime or 0.1)

			frame.item = nil
			frame.amount = nil
			frame.link = nil
			frame.unit = nil
			frame.time = nil
			frame.rollId = nil
			frame.rollType = nil
			frame.color = nil
			frame.borderColor = nil

			frame:Refresh()
		end

		frame.rollIcon:Hide()
		if db.showIcon then
			frame.iconFrame:Show()
		else
			frame.text:SetPoint("LEFT", frame.iconFrame, db.iconGap, 0)
			frame.iconFrame:Hide()
		end

		return frame
	end

	function ReleaseFrame(frame)
		frame:Hide()
		frame:ClearAllPoints()

		--[[
		if frame.dirty then
			frame:SetParent(nil)
			return
		end
		--]]

		tinsert(frameHeap, frame)
	end
end


--------------------------------------------------------------------------------
-- Parse chat messages
--

--[[
CURRENCY_GAINED = "You receive currency: %s.";
CURRENCY_GAINED_MULTIPLE = "You receive currency: %s x%d.";
--]]
local function ParseCurrencyMessage(msg)
	local item, quantity = Deformat(msg, CURRENCY_GAINED_MULTIPLE)
	if quantity then
		return item, tonumber(quantity)
	end

	item = Deformat(msg, CURRENCY_GAINED)
	if item then
		return item, 1
	end
end

-- /run Touhin:CHAT_MSG_CURRENCY(nil, "You receive currency: |cff00aa00|Hcurrency:416|h[Mark of the World Tree]|h|r x1.")
function Touhin:CHAT_MSG_CURRENCY(_, msg)
	local item, quantity = ParseCurrencyMessage(msg)
	if quantity then
		self:ScheduleTimer("AddCurrency", 0.3, item, quantity)
	end
end

local GetItemRoll
do
	local rolls = {}
	--[[
	LOOT_ITEM = "%s receives loot: %s.";
	LOOT_ITEM_MULTIPLE = "%s receives loot: %sx%d.";
	LOOT_ITEM_PUSHED_SELF = "You receive item: %s.";
	LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d.";
	LOOT_ITEM_SELF = "You receive loot: %s.";
	LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d.";
	LOOT_ITEM_CREATED_SELF = "You create: %s.";
	LOOT_ITEM_CREATED_SELF_MULTIPLE = "You create: %sx%d.";
	LOOT_DISENCHANT_CREDIT = "%s was disenchanted for loot by %s.";
	LOOT_ITEM_REFUND = "You are refunded: %s.";
	LOOT_ITEM_REFUND_MULTIPLE = "You are refunded: %sx%d.";

	LOOT_ROLL_ALL_PASSED = "|HlootHistory:%d|h[Loot]|h: Everyone passed on: %s";
	LOOT_ROLL_STARTED = "|HlootHistory:%d|h[Loot]|h: %s";
	--]]
	local function ParseLootMessage(msg)
		local player = pName
		local item, quantity = Deformat(msg, LOOT_ITEM_SELF_MULTIPLE)
		if quantity then
			return player, item, tonumber(quantity)
		end

		item = Deformat(msg, LOOT_ITEM_SELF)
		if item then
			return player, item, 1
		end

		item, quantity = Deformat(msg, LOOT_ITEM_PUSHED_SELF_MULTIPLE)
		if quantity then
			return player, item, tonumber(quantity)
		end

		item = Deformat(msg, LOOT_ITEM_PUSHED_SELF)
		if item then
			return player, item, 1
		end

		item, quantity = Deformat(msg, LOOT_ITEM_CREATED_SELF_MULTIPLE)
		if quantity then
			return player, item, tonumber(quantity), 1
		end

		item = Deformat(msg, LOOT_ITEM_CREATED_SELF)
		if item then
			return player, item, 1, 1
		end

		item, quantity = Deformat(msg, LOOT_ITEM_REFUND_MULTIPLE)
		if quantity then
			return player, item, tonumber(quantity), 1
		end

		item = Deformat(msg, LOOT_ITEM_REFUND)
		if item then
			return player, item, 1, 1
		end

		player, item, quantity = Deformat(msg, LOOT_ITEM_MULTIPLE)
		if quantity then
			return player, item, tonumber(quantity)
		end

		player, item = Deformat(msg, LOOT_ITEM)
		if item then
			return player, item, 1
		end

		item = select(2, Deformat(msg, LOOT_ROLL_ALL_PASSED))
		if item then
			rolls[item] = nil
			return LOOT_HISTORY_ALL_PASSED, item, 0
		end
	end

	--[[
	function Touhin:START_LOOT_ROLL(_, rollId)
		for i=1, C_LootHistory.GetNumItems() do
			local id, itemLink = C_LootHistory.GetItem(i)
			if id == rollId then
				rolls[itemLink] = rollId
				break
			end
		end
	end
	--]]

	local function ParseRollMessage(msg)
		local rollId, item = Deformat(msg, LOOT_ROLL_STARTED)
		if item then
			rolls[item] = rollId
			return true
		end
	end

	local L_ENCHANTING = GetItemSubClassInfo(7, 12)
	function GetItemRoll(item, name)
		local rollId = rolls[item]
		if not rollId and select(3, GetItemInfoInstant(item)) ~= L_ENCHANTING then return end -- no id, not enchanting mats
		rolls[item] = nil

		for i=1, C_LootHistory.GetNumItems() do
			local id, itemLink, _, _, winnerIndex = C_LootHistory.GetItem(i)
			if winnerIndex then
				local winner, _, rollType = C_LootHistory.GetPlayerInfo(i, winnerIndex)
				if id == rollId then
					return rollType, id
				elseif not rollId and rollType == 3 and name == winner:gsub("%-.+", "") then
					-- no rollId (de result) check if we can match a rollId to the actual item
					rolls[itemLink] = nil
					return rollType, id, itemLink
				end
			end
		end
	end

	-- /run GetItemInfo(88296)
	-- /run Touhin:CHAT_MSG_LOOT(nil, LOOT_ROLL_STARTED:format(2, select(2, GetItemInfo(88296))))
	-- /run Touhin:CHAT_MSG_LOOT(nil, LOOT_ITEM:format("Neb", select(2, GetItemInfo(88296))))
	function Touhin:CHAT_MSG_LOOT(_, msg)
		if IsInGroup() and ParseRollMessage(msg) then return end -- save the item link and roll id

		local player, item, quantity, crafted = ParseLootMessage(msg)
		if item then
			self:ScheduleTimer("AddLoot", 0.5, player, item, quantity, crafted)
		end
	end
end


--[[
LOOT_MONEY = "%s loots %s.";x
LOOT_MONEY_SPLIT = "Your share of the loot is %s.";
LOOT_MONEY_SPLIT_GUILD = "Your share of the loot is %s. (%s deposited to guild bank)";
LOOT_MONEY_REFUND = "You are refunded %s.";
YOU_LOOT_MONEY = "You loot %s";
YOU_LOOT_MONEY_GUILD = "You loot %s (%s deposited to guild bank)";
--]]
local ParseMoneyMessage
do
	-- Parse coin strings (code from SpecialEventsEmbed-Loot)
	local cg = GOLD_AMOUNT:gsub("%%d", "(%1+)")
	local cs = SILVER_AMOUNT:gsub("%%d", "(%1+)")
	local cc = COPPER_AMOUNT:gsub("%%d", "(%1+)")

	local function parseCoinString(str)
		local g = string.match(str, cg) or 0
		local s = string.match(str, cs) or 0
		local c = string.match(str, cc) or 0
		return g * 10000 + s * 100 + c
	end

	local strings = {
		LOOT_MONEY_SPLIT,
		LOOT_MONEY_SPLIT_GUILD,
		YOU_LOOT_MONEY,
		YOU_LOOT_MONEY_GUILD,
		LOOT_MONEY_REFUND,
	}

	function ParseMoneyMessage(msg)
		for _,moneyString in ipairs(strings) do
			local money = Deformat(msg, moneyString)
			if money then
				return pName, parseCoinString(money)
			end
		end

		local player, money = Deformat(msg, LOOT_MONEY)
		if money then
			return player, parseCoinString(money)
		end
	end
end

function Touhin:CHAT_MSG_MONEY(_, msg)
	local player, quantity = ParseMoneyMessage(msg)
	if quantity then
		self:AddCoin(quantity)
	end
end


--------------------------------------------------------------------------------
-- Show Loot!
--

function Touhin:AddLootTest()
	if db.showMoney and math.random() > .8 then
		self:AddCoin(math.random(1, 50000))
	else
		local item
		repeat
			item = GetContainerItemLink(math.random(0, 4), math.random(1, 22))
		until item
		self:AddLoot(pName, item, 0)
	end
end

do
	local function getCoinString(amount)
		local s = GetCoinText(amount, " ")
		s = string.gsub(s, "(%d+) Gold", "|cffffffff%1|r|cffffd700g|r")
		s = string.gsub(s, "(%d+) Silver", "|cffffffff%1|r|cffc7c7cfs|r")
		s = string.gsub(s, "(%d+) Copper", "|cffffffff%1|r|cffeda55fc|r")
		return s
	end

	function Touhin:AddCoin(amount)
		local row
		for k in next, GetRows() do
			if k.item == "coin" then
				if not k.dirty then
					row = k
				else
					-- XXX update for the proper text width when toggling the icon
					RemoveRow(k)
					ReleaseFrame(k)
				end
				break
			end
		end
		if not row then
			row = GetFrame()
			row.time = 0 -- always on top (giggity)
			row.item = "coin"
		end

		local text
		if row.amount then
			row.amount = row.amount + amount
			text = string.format("%s (|cff20ff20+|r%s)", getCoinString(row.amount), getCoinString(amount))
		else
			row.amount = amount
			text = getCoinString(amount)
		end

		row:SetRow(GetCoinIcon(row.amount), ITEM_QUALITY_COLORS[0], text)
		AddRow(row)
	end
end

do
	local blacklist = {
		[1585] = true, -- Honor
		[1586] = true, -- Honor Level
	}
	function Touhin:AddCurrency(item, amount)
		local id = C_CurrencyInfo.GetCurrencyIDFromLink(item)
		if not id or blacklist[id] then return end

		local info = C_CurrencyInfo.GetCurrencyInfo(id)
		local itemColor = ITEM_QUALITY_COLORS[info.quality] or ITEM_QUALITY_COLORS[1]
		local classColor = CLASS_COLORS[pClass]
		local text = string.format("%s%s|r %s[%s]|r|cffffffffx%d|r%s", classColor, pName, itemColor.hex, info.name, amount, db.showTotalCount and string.format(" |cffaaaaaa%d|r", info.quantity) or "")

		local row = GetFrame()
		row.unit = pName
		row.time = GetTime()
		row.link = item

		row:SetRow(info.iconFileID, ITEM_QUALITY_COLORS[0], text)
		AddRow(row)
	end
end

do
	local L_QUEST = GetItemClassInfo(LE_ITEM_CLASS_QUEST)
	local QUEST_COLOR = { hex = "|cffffff00", r = 1, g = 1, b = 0 }

	function Touhin:AddLoot(unitName, item, quantity, isCrafted)
		local rollType, rollId, deItem
		if not isCrafted then
			rollType, rollId, deItem = GetItemRoll(item, unitName)
			if deItem then
				quantity = 1
			end
		end

		local itemName, itemLink, itemQuality, _, _, itemType, itemSubType, _, _, itemTexture = GetItemInfo(deItem or item)
		if not itemName then return end

		local isQuestItem = itemType == L_QUEST
		local isMine = UnitIsUnit("player", unitName)

		-- threshold tests
		if not (isQuestItem and db.showQuestItems) and ( (isMine and itemQuality < db.qualitySelfThreshold) or (not isMine and itemQuality < db.qualityThreshold) ) then
			return
		end

		local totalText = ""
		if isMine and db.showTotalCount then
			local total = GetItemCount(itemLink) or 0
			if total > quantity and total > 1 then -- extra check for test loot
				totalText = string.format(" |cffaaaaaa%d|r", total)
			end
		end

		if unitName == LOOT_HISTORY_ALL_PASSED then
			itemTexture = rollTextures[LOOT_ROLL_TYPE_PASS]
		end

		-- TODO should probably move the item name to its own fontstring and make the option control row width, but ugh.
		if string.len(itemName) > db.displayLength then
			itemName = string.sub(itemName, 1, db.displayLength) .. ".."
		end
		local _, class = UnitClass(unitName)
		local classColor = CLASS_COLORS[class] or "|cffcccccc"
		local qualityColor = isQuestItem and QUEST_COLOR or ITEM_QUALITY_COLORS[itemQuality]

		local rowText
		if quantity > 1 then
			rowText = string.format("%s%s|r %s[%s]|r|cffffffffx%d|r%s", classColor, unitName, qualityColor.hex, itemName, quantity, totalText)
		else
			rowText = string.format("%s%s|r %s[%s]|r%s", classColor, unitName, qualityColor.hex, itemName, totalText)
		end

		local highlight = db.highlightWon and isMine and rollType and QUEST_COLOR
		if highlight then
			PlaySound(31578)
		end

		local row = GetFrame()
		row.link = itemLink
		row.unit = unitName
		row.time = GetTime()

		if rollType then
			row.rollId = rollId
			row.rollType = rollType
		end

		row:SetRow(itemTexture, qualityColor, rowText, highlight)
		AddRow(row)
	end
end


--------------------------------------------------------------------------------
-- Options
--

local defaults = {
	profile = {
		scale = 1,
		showMoney = true,
		showAltCurrency = true,
		showLoot = true,
		showTotalCount = true,
		showRollWinner = true,
		showRollChoices = true,
		showQuestItems = true,
		highlightWon = true,
		disableLootAlert = false,
		qualityThreshold = 3,
		qualitySelfThreshold = 0,
		displayLength = 100,
		growDown = true,
		alignLeft = true,
		shownLimit = 10,
		fadeDelay = 8,
		fadeTime = 0.4,
		strata = "LOW",
		font = "Friz Quadrata TT",
		fontSize = 12,
		bgFile = "TouhinDark",
		edgeFile = "Blizzard Tooltip",
		edgeSize = 16,
		insets = 4,
		iconGap = 2,
		rowSpacing = 2,
		bgColor = { r = 0, b = 0, g = 0, a = 0.9 },
		borderAlpha = 1,
		colorBackground =  true,
		showIcon = true,
		iconSize = 26,
		rollIconScale = 0.6,
	},
}

local GetOptions
do
	local qualityValues = {}
	for i = 0, 5 do qualityValues[i] = format("%s%s|r", _G["ITEM_QUALITY_COLORS"][i].hex, _G["ITEM_QUALITY"..i.."_DESC"]) end
	local strataValues = {[1] = "BACKGROUND", [2] = "LOW", [3] = "MEDIUM", [4] = "HIGH", [5] = "DIALOG", [6] = "TOOLTIP"}
	local fontValues, barValues, borderValues
	if media then
		fontValues = media:List("font")
		barValues = media:List("statusbar")
		borderValues = media:List("border")
	else
		fontValues, barValues, borderValues = {}, {}, {}
	end

	local function set_with_update(info, value)
		db[info[#info]] = value
		UpdateRowOrdering()
		UpdateRows()
	end

	local function set_with_refresh(info, value)
		db[info[#info]] = value
		UpdateFrameFont()
		UpdateFrameBackdrop()
		UpdateRows(true)
	end

	function GetOptions()
		local options = {
			name = "Touhin",
			type = "group",
			get = function(info) return db[info[#info]] end,
			set = function(info, value) db[info[#info]] = value end,
			args = {
				header = {
					name = GetAddOnMetadata("Touhin", "Notes").."\n",
					type = "description",
					order = 1,
					width = "full",
				},
				toggleAnchor = {
					name = L["Toggle Anchor"],
					desc = L["Toggle showing the anchor."],
					type = "execute",
					func = ToggleAnchor,
					order = 2,
				},
				resetAnchor = {
					name = L["Reset Position"],
					desc = L["Reset the anchor position to the center of your screen."],
					type = "execute",
					func = ResetAnchor,
					order = 3,
				},
				growDown = {
					name = L["Grow Down"],
					desc = L["New items are added below shown items instead of above."],
					type = "toggle",
					set = set_with_update,
					order = 4,
				},
				alignLeft = {
					name = L["Align Left"],
					desc = L["Items are aligned to the left edge of the anchor instead of the right."],
					type = "toggle",
					set = set_with_update,
					order = 5,
				},
				scale = {
					name = L["Scale"],
					desc = L["Set the overall scale of the display."],
					type = "range", isPercent = true, min = 0, softMin = .5, softMax = 1.5, max = 3, step = .01,
					set = set_with_update,
					order = 6,
				},
				shownLimit = {
					name = L["Shown Limit"],
					desc = L["Maximum number of items to show at once."],
					type = "range", min = 1, max = 25, step = 1,
					set = set_with_update,
					order = 7,
				},
				showMoney = {
					name = L["Show Money"],
					desc = L["Toggle showing looted money received by you in the display."],
					type = "toggle",
					order = 10,
					set = function(info, value)
						db[info[#info]] = value
						if value then
							Touhin:RegisterEvent("CHAT_MSG_MONEY")
						else
							Touhin:UnregisterEvent("CHAT_MSG_MONEY")
						end
					end,
				},
				showAltCurrency = {
					name = L["Show Currency"],
					desc = L["Toggle showing currency (tokens, points, etc.) received by you in the display."],
					type = "toggle",
					order = 11,
					set = function(info, value)
						db[info[#info]] = value
						if value then
							Touhin:RegisterEvent("CHAT_MSG_CURRENCY")
						else
							Touhin:UnregisterEvent("CHAT_MSG_CURRENCY")
						end
					end,
				},
				showTotalCount = {
					name = L["Show Item Total"],
					desc = L["Toggle showing the total number of items in your inventory."],
					type = "toggle",
					order = 12,
				},
				showQuestItems = {
					name = L["Show Quest Items"],
					desc = L["Ignore loot thresholds and always show looted quest items."],
					type = "toggle",
					order = 13,
				},
				highlightWon = {
					name = L["Highlight Won"],
					desc = L["Toggle highlighting items won while in a group."],
					type = "toggle",
					order = 13.1,
				},
				disableLootAlert = {
					name = L["Hide Loot Alert"],
					desc = L["Disable showing the loot won frame."],
					type = "toggle",
					set = function(info, value)
						db[info[#info]] = value
						if value then
							AlertFrame:UnregisterEvent("LOOT_ITEM_ROLL_WON")
							AlertFrame:UnregisterEvent("SHOW_LOOT_TOAST")
						else
							AlertFrame:RegisterEvent("LOOT_ITEM_ROLL_WON")
							AlertFrame:RegisterEvent("SHOW_LOOT_TOAST")
						end
					end,
					order = 13.2,
				},
				qualitySelfThreshold = {
					name = L["Self Quality Threshold"],
					desc = L["Set the minimum quality of items looted by you to show."],
					type = "select",
					values = qualityValues,
					order = 14,
				},
				qualityThreshold = {
					name = L["Group Quality Threshold"],
					desc = L["Set the minimum quality of items looted by group members to show."],
					type = "select",
					values = qualityValues,
					order = 15,
				},
				display = {
					name = L["Item Display"],
					type = "group",
					inline = true,
					order = 20,
					args = {
						font = {
							name = L["Font"],
							desc = L["Set the font face."],
							type = "select",
							itemControl = "DDI-Font",
							values = fontValues,
							get = function()
								for i, v in next, fontValues do
									if v == db.font then return i end
								end
							end,
							set = function(info, value)
								set_with_refresh(info, fontValues[value])
							end,
							order = 1,
							disabled = function() return not media end,
						},
						fontSize = {
							name = L["Font Size"],
							desc = L["Set the font size."],
							type = "range", min = 8, max = 30, step = 1,
							set = set_with_refresh,
							order = 2,
						},
						displayLength = {
							name = L["Item Text Length"],
							desc = L["Number of characters to show before truncating the item name."],
							type = "range", min = 1, softMax = 100, max = 300, step = 1,
							order = 3,
						},
						fadeDelay = {
							name = L["Fade Delay"],
							desc = L["Set the number of seconds to wait before fading the item."],
							type = "range", min = 0, max = 30, step = 1,
							order = 5,
						},
						fadeTime = {
							name = L["Fade Duration"],
							desc = L["Set the duration of the fade animation."],
							type = "range", min = 0, max = 1, step = .1,
							order = 6,
						},
						advancedDivider = {
							name = L["Advanced"],
							type = "header",
							order = 20,
						},
						showIcon = {
							name = L["Show Icon"],
							desc = L["Toggle showing the item icon."],
							type = "toggle",
							set = set_with_refresh,
							order = 20.1,
						},
						iconSize = {
							name = L["Icon Size"],
							desc = L["Set the icon size."],
							type = "range", min = 8, max = 48, step = 1,
							set = set_with_refresh,
							order = 20.2,
							disabled = function() return not db.showIcon end,
						},
						rollIconScale = {
							name = L["Roll Icon Scale"],
							desc = L["Set the roll icon scale relative to the icon size."],
							type = "range", isPercent = true, min = 0, softMin = .1, softMax = 1, max = 3, step = .01,
							set = set_with_refresh,
							order = 20.3,
							disabled = function() return not db.showIcon end,
						},
						iconGap = {
							name = L["Text Offset"],
							desc = L["Set the spacing between the item icon and text."],
							type = "range", min = -100, softMin = -30, softMax = 30, max = 100, step = 1,
							set = set_with_refresh,
							order = 21,
						},
						rowSpacing = {
							name = L["Row Spacing"],
							desc = L["Set the spacing between rows."],
							type = "range", min = -100, softMin = -30, softMax = 30, max = 100, step = 1,
							set = set_with_update,
							order = 22,
						},
						strata = {
							name = L["Strata"],
							desc = L["Set the frame strata of items."],
							type = "select",
							values = strataValues,
							-- why you sort my tables by key ;[
							get = function(info)
								local key = db[info[#info]]
								for i,v in ipairs(strataValues) do
									if v == key then
										return i
									end
								end
							end,
							set = function(info, value)
								db[info[#info]] = strataValues[value]
								UpdateRows(true)
							end,
							order = 23,
						},
					},
				}, -- display
				background = {
					name = L["Background"],
					type = "group",
					inline = true,
					order = 30,
					set = set_with_refresh,
					disabled = function() return not media end,
					args = {
						bgFile = {
							name = L["Background"],
							desc = L["Set the background texture."],
							type = "select",
							itemControl = "DDI-Statusbar",
							values = barValues,
							get = function()
								for i, v in next, barValues do
									if v == db.bgFile then return i end
								end
							end,
							set = function(info, value)
								set_with_refresh(info, barValues[value])
							end,
							order = 1,
						},
						bgColor = {
							name = L["Backdrop Color"],
							desc = L["Set the backdrop color and opacity."],
							type = "color", hasAlpha = true,
							get = function(info)
								local color = db.bgColor
								return color.r, color.g, color.b, color.a
							end,
							set = function(info, r, g, b, a)
								local color = db.bgColor
								color.r, color.g, color.b, color.a = r, g, b, a
								UpdateRows(true)
							end,
							order = 2,
						},
						colorBackground = {
							name = L["Color Background"],
							desc = L["Toggle tinting the background and border with the item quality color, otherwise, use the backdrop color."],
							type = "toggle",
							order = 2.1,
						},
						edgeFile = {
							name = L["Border"],
							desc = L["Set the border texture."],
							type = "select",
							values = borderValues,
							get = function()
								for i, v in next, borderValues do
									if v == db.edgeFile then return i end
								end
							end,
							set = function(info, value)
								set_with_refresh(info, borderValues[value])
							end,
							order = 3,
						},
						edgeSize = {
							name = L["Border Size"],
							desc = L["Set the thickness of border segments and square size of the corners."],
							type = "range", min = 1, softMax = 16, max = 30, step = 1,
							order = 5,
						},
						insets = {
							name = L["Background Inset"],
							desc = L["Set distance from the edges of the frame to the edges of the background texture."],
							type = "range", min = 1, max = 16, step = 1,
							order = 6,
						},
					},
				}, -- background
				sharedMediaMessage = {
					name = "** "..L["Some options are disabled because LibSharedMedia-3.0 is not available."],
					type = "description",
					fontSize = "medium",
					order = 100,
					hidden = function() return media end,
				},
			},
		}
		return options
	end
end

function Touhin:OpenOptions()
	InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
end


--------------------------------------------------------------------------------
-- Initialization
--

function Touhin:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("TouhinDB", defaults, true)
	db = self.db.profile

	local function OnProfileChanged()
		db = self.db.profile
		UpdateAnchor()
	end
	self.db.RegisterCallback(self, "OnProfileChanged", OnProfileChanged)
	self.db.RegisterCallback(self, "OnProfileCopied", OnProfileChanged)
	self.db.RegisterCallback(self, "OnProfileReset", OnProfileChanged)

	LibStub("AceConfig-3.0"):RegisterOptionsTable("Touhin", GetOptions)
	self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("Touhin")
	LibStub("AceConfigRegistry-3.0"):RegisterOptionsTable("Touhin Profile", LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db))
	LibStub("AceConfigDialog-3.0"):AddToBlizOptions("Touhin Profile", "Profiles", "Touhin")
end

function Touhin:OnEnable()
	if not db.anchor_point then
		ShowAnchor()
	end
	UpdateFrameBackdrop()
	UpdateFrameFont()

	self:RegisterEvent("CHAT_MSG_LOOT")
	if db.showMoney then self:RegisterEvent("CHAT_MSG_MONEY") end
	if db.showAltCurrency then self:RegisterEvent("CHAT_MSG_CURRENCY") end
	if db.disableLootAlert then
		AlertFrame:UnregisterEvent("LOOT_ITEM_ROLL_WON")
		AlertFrame:UnregisterEvent("SHOW_LOOT_TOAST")
	end

	local function updateClassColors()
		wipe(CLASS_COLORS)
		for class, color in pairs(CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS) do
			CLASS_COLORS[class] = ("|cff%02x%02x%02x"):format(color.r * 255, color.g * 255, color.b * 255)
		end
	end
	updateClassColors()

	--!ClassColors support
	if CUSTOM_CLASS_COLORS then
		CUSTOM_CLASS_COLORS:RegisterCallback(updateClassColors)
	end
end

SLASH_TOUHIN1 = "/touhin"
SlashCmdList["TOUHIN"] = function(input)
	if input == "config" then
		Touhin:OpenOptions()
	else
		ToggleAnchor()
	end
end
