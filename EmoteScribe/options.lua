-------------------------------------------------------------------------------
-- Emote Scribe -- Options
-- by VfX / Bitwise1057
-------------------------------------------------------------------------------
local _, Me = ...
local Enscriber = LibEnscriber

local DEFAULTS = {
	premark         = "»";
	postmark        = "»";
	hidefailed      = true;
	showsending     = true;
	showlockdown    = true;
	emoteprotection = true;
	rpsyntax        = true;
	spellcheck_enabled       = false;
	spellcheck_color         = "00a9ec";
	spellcheck_ignore_caps   = true;
	spellcheck_ignore_numbers = true;
}

-------------------------------------------------------------------------------
local function DB_Get( key )
	return EmoteScribeSaved.global[key]
end

local function DB_Set( key, val )
	EmoteScribeSaved.global[key] = val
end

function Me.Options_Init()
	if type(EmoteScribeSaved) ~= "table" then
		EmoteScribeSaved = {}
	end
	if type(EmoteScribeSaved.global) ~= "table" then
		EmoteScribeSaved.global = {}
	end
	if type(EmoteScribeSaved.char) ~= "table" then
		EmoteScribeSaved.char = {}
	end
	if type(EmoteScribeSaved.char.undo_history) ~= "table" then
		EmoteScribeSaved.char.undo_history = {}
	end
	for k, v in pairs(DEFAULTS) do
		if EmoteScribeSaved.global[k] == nil then
			EmoteScribeSaved.global[k] = v
		end
	end

	Me.db = {
		global = EmoteScribeSaved.global;
		char   = EmoteScribeSaved.char;
	}

	Me.Options_Build()
	Me.Options_Apply()
end

function Me.Options_Apply()
	Enscriber.HideFailureMessages( DB_Get("hidefailed") )
	Enscriber.SetSplitmarks( DB_Get("premark"), DB_Get("postmark"), true )
	LibEnscriber.Internal.handle_rp_syntax = DB_Get("rpsyntax")
	if Me.Spellcheck and Me.Spellcheck.ApplySettings then
		Me.Spellcheck.ApplySettings()
	end
end

-------------------------------------------------------------------------------
-- Native settings window
-------------------------------------------------------------------------------
local WINDOW_W  = 480
local WINDOW_H  = 380
local SIDEBAR_W = 120

local function MakeLabel( parent, text, x, y, width, font )
	local f = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
	f:SetPoint("TOPLEFT", x, y)
	f:SetWidth(width or 200)
	f:SetJustifyH("LEFT")
	f:SetText(text)
	return f
end

local function MakeCheckbox( parent, label, tooltip, x, y, getVal, setVal )
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetPoint("TOPLEFT", x, y)
	cb:SetSize(24, 24)
	cb:SetChecked( getVal() )

	local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
	lbl:SetText(label)

	if tooltip then
		cb:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(tooltip, nil, nil, nil, nil, true)
			GameTooltip:Show()
		end)
		cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end

	cb:SetScript("OnClick", function(self)
		setVal( self:GetChecked() and true or false )
	end)

	return cb
end

local function MakeInput( parent, x, y, width, maxlen, getVal, setVal )
	local bg = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	bg:SetPoint("TOPLEFT", x, y)
	bg:SetSize(width, 22)
	bg:SetBackdrop({
		bgFile   = "Interface\\ChatFrame\\ChatFrameBackground";
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border";
		edgeSize = 8;
		insets   = { left=3, right=3, top=3, bottom=3 };
	})
	bg:SetBackdropColor(0, 0, 0, 0.5)
	bg:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

	local eb = CreateFrame("EditBox", nil, bg)
	eb:SetPoint("TOPLEFT", 5, -3)
	eb:SetPoint("BOTTOMRIGHT", -5, 3)
	eb:SetFontObject(ChatFontNormal)
	eb:SetMaxLetters(maxlen or 10)
	eb:SetAutoFocus(false)
	eb:SetText( getVal() )
	eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	eb:SetScript("OnEnterPressed", function(self)
		setVal( self:GetText():sub(1, maxlen or 10) )
		self:ClearFocus()
	end)
	eb:SetScript("OnEditFocusLost", function(self)
		setVal( self:GetText():sub(1, maxlen or 10) )
	end)

	return eb, bg
end

local function MakeButton( parent, label, x, y, width, onClick )
	local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	btn:SetPoint("TOPLEFT", x, y)
	btn:SetSize(width or 160, 22)
	btn:SetText(label)
	btn:SetScript("OnClick", onClick)
	return btn
end

-------------------------------------------------------------------------------
-- Status tab refresh helpers
-------------------------------------------------------------------------------
local COMPAT_ADDONS = {
	{ name = "EmoteSplitter",        label = "EmoteSplitter"         };
	{ name = "UnlimitedChatMessage", label = "UnlimitedChatMessage"  };
	{ name = "Misspelled",           label = "Misspelled"            };
}

local statusRows   = {}   -- { nameLabel, statusLabel } per addon
local moduleRows   = {}   -- same structure for registered modules
local healthLabel  = nil  -- FontString for "Status Health: Good/Bad"

local function RefreshStatusTab()
	-- Registered modules
	local speakethLoaded = C_AddOns.IsAddOnLoaded("Speaketh")
	if moduleRows[1] then
		if speakethLoaded then
			moduleRows[1]:SetText("Loaded")
			moduleRows[1]:SetTextColor(0.2, 0.9, 0.2, 1)
		else
			moduleRows[1]:SetText("Not Loaded")
			moduleRows[1]:SetTextColor(0.9, 0.2, 0.2, 1)
		end
	end

	if moduleRows[2] then
		local sc = Me.Spellcheck
		if sc and sc.dictionaryLoaded then
			if sc.enabled then
				moduleRows[2]:SetText("Loaded")
				moduleRows[2]:SetTextColor(0.2, 0.9, 0.2, 1)
			else
				moduleRows[2]:SetText("Disabled")
				moduleRows[2]:SetTextColor(0.7, 0.7, 0.2, 1)
			end
		else
			moduleRows[2]:SetText("Not Loaded")
			moduleRows[2]:SetTextColor(0.9, 0.2, 0.2, 1)
		end
	end

	-- Compatibility checks
	local anyBad = false
	for i, entry in ipairs(COMPAT_ADDONS) do
		local loaded = C_AddOns.IsAddOnLoaded(entry.name)
		if loaded then anyBad = true end
		if statusRows[i] then
			if loaded then
				statusRows[i]:SetText("Present")
				statusRows[i]:SetTextColor(0.9, 0.2, 0.2, 1)
			else
				statusRows[i]:SetText("Not Present")
				statusRows[i]:SetTextColor(0.2, 0.9, 0.2, 1)
			end
		end
	end

	-- Overall health
	if healthLabel then
		if anyBad then
			healthLabel:SetText("|cffff4444Bad|r")
		else
			healthLabel:SetText("|cff44cc44Good|r")
		end
	end
end

-------------------------------------------------------------------------------
-- Tab management
-------------------------------------------------------------------------------
local function MakeSidebarTab( sidebar, label, yOffset )
	local btn = CreateFrame("Button", nil, sidebar)
	btn:SetPoint("TOPLEFT", 4, yOffset)
	btn:SetSize(SIDEBAR_W - 8, 24)
	btn:EnableMouse(true)

	-- Background: only shown when this tab is active
	local bg = btn:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 169/255, 236/255, 0.15)
	bg:Hide()

	-- Hover highlight: only shown on inactive tabs (active tab already has bg)
	local hl = btn:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.05)

	local accent = btn:CreateTexture(nil, "ARTWORK")
	accent:SetPoint("TOPLEFT", 0, 0)
	accent:SetPoint("BOTTOMLEFT", 0, 0)
	accent:SetWidth(2)
	accent:SetColorTexture(0, 169/255, 236/255, 1)
	accent:Hide()

	local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	lbl:SetPoint("LEFT", 10, 0)
	lbl:SetText(label)
	lbl:SetTextColor(0.5, 0.5, 0.5, 1)   -- start inactive

	btn.bg     = bg
	btn.accent = accent
	btn.lbl    = lbl
	return btn
end

function Me.Options_Build()
	if Me.options_frame then return end

	-- Main window
	local f = CreateFrame("Frame", "EmoteScribeOptions", UIParent, "BackdropTemplate")
	f:SetSize(WINDOW_W, WINDOW_H)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop",  f.StopMovingOrSizing)
	f:SetBackdrop({
		bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background";
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border";
		edgeSize = 32;
		insets   = { left=11, right=11, top=11, bottom=11 };
	})
	f:Hide()

	-- Title
	local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	title:SetPoint("TOP", 0, -16)
	title:SetText("EmoteScribe")
	title:SetTextColor( 0, 169/255, 236/255, 1 )

	local ver = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	ver:SetPoint("TOP", 0, -30)
	ver:SetText("v" .. (C_AddOns.GetAddOnMetadata("EmoteScribe", "Version") or "?") .. "  |  VfX / Bitwise1057")

	-- Horizontal divider below title
	local divTop = f:CreateTexture(nil, "OVERLAY")
	divTop:SetColorTexture(0.3, 0.3, 0.3, 0.6)
	divTop:SetPoint("TOPLEFT", 14, -44)
	divTop:SetPoint("TOPRIGHT", -14, -44)
	divTop:SetHeight(1)

	-------------------------------------------------------------------------------
	-- Sidebar
	-------------------------------------------------------------------------------
	local sidebar = CreateFrame("Frame", nil, f, "BackdropTemplate")
	sidebar:SetPoint("TOPLEFT", 14, -45)
	sidebar:SetPoint("BOTTOMLEFT", 14, 14)
	sidebar:SetWidth(SIDEBAR_W)
	sidebar:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark";
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border";
		edgeSize = 16;
		insets   = { left=4, right=4, top=4, bottom=4 };
	})
	sidebar:SetBackdropColor(0, 0, 0, 0.4)

	-- Vertical divider between sidebar and content
	local divSide = f:CreateTexture(nil, "OVERLAY")
	divSide:SetColorTexture(0.3, 0.3, 0.3, 0.6)
	divSide:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 0, 0)
	divSide:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMRIGHT", 0, 0)
	divSide:SetWidth(1)

	-- Sidebar tabs: Status (top), General (below), Spellcheck (below General)
	local tabStatus     = MakeSidebarTab(sidebar, "Status",     -8)
	local tabGeneral    = MakeSidebarTab(sidebar, "General",   -36)
	local tabSpellcheck = MakeSidebarTab(sidebar, "Spellcheck", -64)

	-------------------------------------------------------------------------------
	-- Content area clip frame (shared)
	-------------------------------------------------------------------------------
	local PAD_L = SIDEBAR_W + 24
	local PAD_R = -18
	local CONTENT_TOP = -46
	local CONTENT_BOT = 14

	-------------------------------------------------------------------------------
	-- Status panel (ScrollFrame)
	-------------------------------------------------------------------------------
	local statusScroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
	statusScroll:SetPoint("TOPLEFT",     PAD_L - 4, CONTENT_TOP)
	statusScroll:SetPoint("BOTTOMRIGHT", PAD_R - 20, CONTENT_BOT)

	local statusContent = CreateFrame("Frame", nil, statusScroll)
	statusContent:SetSize(WINDOW_W - PAD_L - 32, 400)
	statusScroll:SetScrollChild(statusContent)

	local sy = -8   -- y cursor inside statusContent

	-- Helper: section header inside statusContent
	local function StatusSectionLabel( text )
		local lbl = statusContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		lbl:SetPoint("TOPLEFT", 0, sy)
		lbl:SetText(text)
		sy = sy - 18
	end

	-- Helper: divider inside statusContent
	local function StatusDivider()
		local d = statusContent:CreateTexture(nil, "OVERLAY")
		d:SetColorTexture(0.3, 0.3, 0.3, 0.5)
		d:SetPoint("TOPLEFT",  0, sy + 2)
		d:SetPoint("TOPRIGHT", 0, sy + 2)
		d:SetHeight(1)
		sy = sy - 10
	end

	-- Helper: addon status row inside statusContent
	-- Returns the status FontString so we can update it later
	local function StatusRow( addonLabel )
		local nameLbl = statusContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		nameLbl:SetPoint("TOPLEFT", 0, sy)
		nameLbl:SetText(addonLabel)

		local statusLbl = statusContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		statusLbl:SetPoint("TOPLEFT", 160, sy)
		statusLbl:SetText("—")

		sy = sy - 22
		return statusLbl
	end

	-- Registered Modules section
	StatusSectionLabel("Registered Modules")

	moduleRows[1] = StatusRow("Speaketh")
	moduleRows[2] = StatusRow("Spellcheck")

	sy = sy - 6
	StatusDivider()

	-- Compatibility section
	StatusSectionLabel("Compatibility")

	for i, entry in ipairs(COMPAT_ADDONS) do
		statusRows[i] = StatusRow(entry.label)
	end

	sy = sy - 6
	StatusDivider()

	-- Status Health row
	local healthRowLabel = statusContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	healthRowLabel:SetPoint("TOPLEFT", 0, sy)
	healthRowLabel:SetText("Status Health:")

	healthLabel = statusContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	healthLabel:SetPoint("TOPLEFT", 160, sy)
	healthLabel:SetText("—")

	-- Resize content to actual used height
	statusContent:SetHeight(math.abs(sy) + 20)

	-------------------------------------------------------------------------------
	-- General panel (plain frame, no scroll needed)
	-------------------------------------------------------------------------------
	local generalPanel = CreateFrame("Frame", nil, f)
	generalPanel:SetPoint("TOPLEFT",     PAD_L, CONTENT_TOP)
	generalPanel:SetPoint("BOTTOMRIGHT", PAD_R, CONTENT_BOT)

	local y = -8   -- y cursor inside generalPanel

	-- Split Markers
	MakeLabel(generalPanel, "Split Markers", 0, y, 200, "GameFontNormalSmall")
	y = y - 20

	MakeLabel(generalPanel, "Postfix", 0, y, 52)
	local postEB = MakeInput(generalPanel, 48, y + 2, 80, 10,
		function() return DB_Get("postmark") end,
		function(v) DB_Set("postmark", v); Me.Options_Apply() end)

	MakeLabel(generalPanel, "Prefix", 148, y, 52)
	local preEB = MakeInput(generalPanel, 196, y + 2, 80, 10,
		function() return DB_Get("premark") end,
		function(v) DB_Set("premark", v); Me.Options_Apply() end)

	y = y - 30

	MakeButton(generalPanel, "Reset Marks to Default", 0, y, 180, function()
		DB_Set("premark",  "»")
		DB_Set("postmark", "»")
		preEB:SetText("»")
		postEB:SetText("»")
		Me.Options_Apply()
	end)

	y = y - 40

	-- Divider
	local div2 = generalPanel:CreateTexture(nil, "OVERLAY")
	div2:SetColorTexture(0.3, 0.3, 0.3, 0.5)
	div2:SetPoint("TOPLEFT",  0, y + 6)
	div2:SetPoint("TOPRIGHT", 0, y + 6)
	div2:SetHeight(1)

	y = y - 8

	-- Notification/display toggles
	MakeCheckbox(generalPanel, "Show Lockdown Notifications",
		"Show chat messages and an indicator when encounter lockdown pauses message splitting.",
		0, y,
		function() return DB_Get("showlockdown") end,
		function(v) DB_Set("showlockdown", v) end)
	y = y - 28

	MakeCheckbox(generalPanel, "Show Sending Indicator",
		"Show a small indicator at the bottom-left while messages are being sent.",
		0, y,
		function() return DB_Get("showsending") end,
		function(v) DB_Set("showsending", v) end)
	y = y - 28

	MakeCheckbox(generalPanel, "Hide Failure Messages",
		"Suppress the system message shown when your chat is throttled.",
		0, y,
		function() return DB_Get("hidefailed") end,
		function(v) DB_Set("hidefailed", v); Me.Options_Apply() end)

	y = y - 40

	-- Advanced Formatting section
	local divAdv = generalPanel:CreateTexture(nil, "OVERLAY")
	divAdv:SetColorTexture(0.3, 0.3, 0.3, 0.5)
	divAdv:SetPoint("TOPLEFT",  0, y + 6)
	divAdv:SetPoint("TOPRIGHT", 0, y + 6)
	divAdv:SetHeight(1)

	y = y - 4

	local advLabel = generalPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	advLabel:SetPoint("TOPLEFT", 0, y)
	advLabel:SetText("Advanced Formatting")
	advLabel:SetTextColor(0, 169/255, 236/255, 0.8)

	y = y - 20

	MakeCheckbox(generalPanel, "RP Syntax Continuity",
		"When a message splits mid-delimiter (e.g. inside \" quotes or *emote* asterisks), automatically closes the delimiter on the outgoing chunk and reopens it on the next.",
		0, y,
		function() return DB_Get("rpsyntax") end,
		function(v) DB_Set("rpsyntax", v); Me.Options_Apply() end)
	y = y - 28

	MakeCheckbox(generalPanel, "Emote Protection  (Ctrl-Z / Ctrl-Y)",
		"Adds Ctrl-Z and Ctrl-Y undo/redo to chat editboxes. Useful for recovering long emotes after accidental closes or disconnects.",
		0, y,
		function() return DB_Get("emoteprotection") end,
		function(v)
			DB_Set("emoteprotection", v)
			Me.EmoteProtection.OptionsChanged()
		end)

	-------------------------------------------------------------------------------
	-- Spellcheck panel
	-------------------------------------------------------------------------------
	local spellcheckPanel = CreateFrame("Frame", nil, f)
	spellcheckPanel:SetPoint("TOPLEFT",     PAD_L, CONTENT_TOP)
	spellcheckPanel:SetPoint("BOTTOMRIGHT", PAD_R, CONTENT_BOT)

	local sy2 = -8

	local scEnableCB = MakeCheckbox(spellcheckPanel, "Enable Spellcheck",
		"Highlight misspelled words in the chat editbox as you type.",
		0, sy2,
		function() return DB_Get("spellcheck_enabled") end,
		function(v)
			DB_Set("spellcheck_enabled", v)
			Me.Options_Apply()
		end)

	-- Alert triangle: warns about rare taint errors in combat encounters.
	local scAlert = spellcheckPanel:CreateTexture(nil, "OVERLAY")
	scAlert:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
	scAlert:SetSize(16, 16)
	scAlert:SetPoint("LEFT", scEnableCB, "RIGHT", 140, 0)

	local scAlertBtn = CreateFrame("Frame", nil, spellcheckPanel)
	scAlertBtn:SetAllPoints(scAlert)
	scAlertBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Compatibility Warning", 1, 0.82, 0)
		GameTooltip:AddLine("When enabled, spellcheck highlighting may cause rare errors if a message containing highlighted text is sent during an encounter or instance lockdown.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	scAlertBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

	sy2 = sy2 - 28

	MakeCheckbox(spellcheckPanel, "Ignore ALL CAPS Words",
		"Words written entirely in capitals (e.g. NPC names, acronyms) are not flagged.",
		0, sy2,
		function() return DB_Get("spellcheck_ignore_caps") end,
		function(v)
			DB_Set("spellcheck_ignore_caps", v)
			Me.Options_Apply()
		end)
	sy2 = sy2 - 28

	MakeCheckbox(spellcheckPanel, "Ignore Words with Numbers",
		"Words containing digits (e.g. item names, coordinates) are not flagged.",
		0, sy2,
		function() return DB_Get("spellcheck_ignore_numbers") end,
		function(v)
			DB_Set("spellcheck_ignore_numbers", v)
			Me.Options_Apply()
		end)
	sy2 = sy2 - 36

	local divSC = spellcheckPanel:CreateTexture(nil, "OVERLAY")
	divSC:SetColorTexture(0.3, 0.3, 0.3, 0.5)
	divSC:SetPoint("TOPLEFT",  0, sy2 + 6)
	divSC:SetPoint("TOPRIGHT", 0, sy2 + 6)
	divSC:SetHeight(1)
	sy2 = sy2 - 12

	-- "Highlight Color" label — same style as "Advanced Formatting"
	local scColorLabel = spellcheckPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	scColorLabel:SetPoint("TOPLEFT", 0, sy2)
	scColorLabel:SetText("Highlight Color")
	scColorLabel:SetTextColor(0, 169/255, 236/255, 0.8)
	sy2 = sy2 - 22

	-- Helper: parse a 6-char hex string to r,g,b in [0,1]
	local function HexToRGB(hex)
		hex = hex or "00a9ec"
		local r = tonumber(hex:sub(1,2), 16) / 255
		local g = tonumber(hex:sub(3,4), 16) / 255
		local b = tonumber(hex:sub(5,6), 16) / 255
		return r, g, b
	end

	-- Helper: convert r,g,b in [0,1] to 6-char uppercase hex string
	local function RGBToHex(r, g, b)
		return string.format("%02X%02X%02X",
			math.floor(r * 255 + 0.5),
			math.floor(g * 255 + 0.5),
			math.floor(b * 255 + 0.5))
	end

	-- Color swatch button — shows current color, opens picker on click
	local scSwatch = CreateFrame("Button", nil, spellcheckPanel, "BackdropTemplate")
	scSwatch:SetPoint("TOPLEFT", 0, sy2)
	scSwatch:SetSize(36, 22)
	scSwatch:SetBackdrop({
		bgFile   = "Interface\\ChatFrame\\ChatFrameBackground";
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border";
		edgeSize = 8;
		insets   = { left=3, right=3, top=3, bottom=3 };
	})
	scSwatch:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

	local scSwatchColor = scSwatch:CreateTexture(nil, "ARTWORK")
	scSwatchColor:SetPoint("TOPLEFT",     3, -3)
	scSwatchColor:SetPoint("BOTTOMRIGHT", -3, 3)

	local function UpdateSwatch()
		local r, g, b = HexToRGB(DB_Get("spellcheck_color"))
		scSwatchColor:SetColorTexture(r, g, b, 1)
	end
	UpdateSwatch()

	scSwatch:SetScript("OnClick", function()
		local r, g, b = HexToRGB(DB_Get("spellcheck_color"))

		local function OnColorChanged()
			local nr, ng, nb = ColorPickerFrame:GetColorRGB()
			DB_Set("spellcheck_color", RGBToHex(nr, ng, nb))
			UpdateSwatch()
			Me.Options_Apply()
		end

		local function OnColorCancelled(prevValues)
			DB_Set("spellcheck_color", RGBToHex(prevValues.r, prevValues.g, prevValues.b))
			UpdateSwatch()
			Me.Options_Apply()
		end

		OpenColorPicker({
			r           = r,
			g           = g,
			b           = b,
			hasOpacity  = false,
			swatchFunc  = OnColorChanged,
			opacityFunc = nil,
			cancelFunc  = OnColorCancelled,
		})
	end)

	scSwatch:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Click to choose a highlight color.", nil, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	scSwatch:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- Reset to Default button — placed to the right of the swatch
	local scResetBtn = MakeButton(spellcheckPanel, "Reset to Default", 44, sy2, 130, function()
		DB_Set("spellcheck_color", "00a9ec")
		UpdateSwatch()
		Me.Options_Apply()
	end)

	sy2 = sy2 - 36

	local divSC2 = spellcheckPanel:CreateTexture(nil, "OVERLAY")
	divSC2:SetColorTexture(0.3, 0.3, 0.3, 0.5)
	divSC2:SetPoint("TOPLEFT",  0, sy2 + 6)
	divSC2:SetPoint("TOPRIGHT", 0, sy2 + 6)
	divSC2:SetHeight(1)
	sy2 = sy2 - 12

	-------------------------------------------------------------------------------
	-- Tab switching
	-------------------------------------------------------------------------------
	local function SetActiveTab( activePanel, activBtn, ... )
		-- Hide all panels, deactivate all buttons.
		local allPanels = { statusScroll, generalPanel, spellcheckPanel }
		local allBtns   = { tabStatus, tabGeneral, tabSpellcheck }
		for _, p in ipairs(allPanels) do p:Hide() end
		for _, b in ipairs(allBtns) do
			b.bg:Hide()
			b.accent:Hide()
			b.lbl:SetTextColor(0.5, 0.5, 0.5, 1)
		end
		-- Activate selected.
		activePanel:Show()
		activBtn.bg:Show()
		activBtn.accent:Show()
		activBtn.lbl:SetTextColor(0, 169/255, 236/255, 1)
	end

	tabStatus:SetScript("OnClick", function()
		SetActiveTab(statusScroll, tabStatus)
		RefreshStatusTab()
	end)

	tabGeneral:SetScript("OnClick", function()
		SetActiveTab(generalPanel, tabGeneral)
	end)

	tabSpellcheck:SetScript("OnClick", function()
		SetActiveTab(spellcheckPanel, tabSpellcheck)
	end)

	-- Default: General tab active
	SetActiveTab(generalPanel, tabGeneral)

	-- Close button
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)

	tinsert(UISpecialFrames, "EmoteScribeOptions")
	Me.options_frame = f
end

function Me.Options_Show()
	if not Me.options_frame then return end
	if Me.options_frame:IsShown() then
		Me.options_frame:Hide()
	else
		Me.options_frame:Show()
	end
end
