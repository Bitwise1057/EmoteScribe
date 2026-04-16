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

	-- "General" sidebar tab button
	local tabGeneral = CreateFrame("Button", nil, sidebar)
	tabGeneral:SetPoint("TOPLEFT", 4, -8)
	tabGeneral:SetSize(SIDEBAR_W - 8, 24)
	tabGeneral:EnableMouse(true)

	local tabBg = tabGeneral:CreateTexture(nil, "BACKGROUND")
	tabBg:SetAllPoints()
	tabBg:SetColorTexture(0, 169/255, 236/255, 0.15)

	local tabHighlight = tabGeneral:CreateTexture(nil, "HIGHLIGHT")
	tabHighlight:SetAllPoints()
	tabHighlight:SetColorTexture(0, 169/255, 236/255, 0.1)

	-- Left accent bar on active tab
	local tabAccent = tabGeneral:CreateTexture(nil, "ARTWORK")
	tabAccent:SetPoint("TOPLEFT", 0, 0)
	tabAccent:SetPoint("BOTTOMLEFT", 0, 0)
	tabAccent:SetWidth(2)
	tabAccent:SetColorTexture(0, 169/255, 236/255, 1)

	local tabLabel = tabGeneral:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	tabLabel:SetPoint("LEFT", 10, 0)
	tabLabel:SetText("General")
	tabLabel:SetTextColor(0, 169/255, 236/255, 1)

	-------------------------------------------------------------------------------
	-- Content panel
	-------------------------------------------------------------------------------
	local PAD_L = SIDEBAR_W + 24
	local PAD_R = -18
	local y     = -54

	-- Split Markers
	MakeLabel(f, "Split Markers", PAD_L, y, 200, "GameFontNormalSmall")
	y = y - 20

	MakeLabel(f, "Postfix", PAD_L, y, 52)
	local postEB = MakeInput(f, PAD_L + 48, y + 2, 80, 10,
		function() return DB_Get("postmark") end,
		function(v) DB_Set("postmark", v); Me.Options_Apply() end)

	MakeLabel(f, "Prefix", PAD_L + 148, y, 52)
	local preEB = MakeInput(f, PAD_L + 196, y + 2, 80, 10,
		function() return DB_Get("premark") end,
		function(v) DB_Set("premark", v); Me.Options_Apply() end)

	y = y - 30

	MakeButton(f, "Reset Marks to Default", PAD_L, y, 180, function()
		DB_Set("premark",  "»")
		DB_Set("postmark", "»")
		preEB:SetText("»")
		postEB:SetText("»")
		Me.Options_Apply()
	end)

	y = y - 40

	-- Divider
	local div2 = f:CreateTexture(nil, "OVERLAY")
	div2:SetColorTexture(0.3, 0.3, 0.3, 0.5)
	div2:SetPoint("TOPLEFT", PAD_L, y + 6)
	div2:SetPoint("TOPRIGHT", PAD_R, y + 6)
	div2:SetHeight(1)

	y = y - 8

	-- Notification/display toggles
	MakeCheckbox(f, "Show Lockdown Notifications",
		"Show chat messages and an indicator when encounter lockdown pauses message splitting.",
		PAD_L, y,
		function() return DB_Get("showlockdown") end,
		function(v) DB_Set("showlockdown", v) end)
	y = y - 28

	MakeCheckbox(f, "Show Sending Indicator",
		"Show a small indicator at the bottom-left while messages are being sent.",
		PAD_L, y,
		function() return DB_Get("showsending") end,
		function(v) DB_Set("showsending", v) end)
	y = y - 28

	MakeCheckbox(f, "Hide Failure Messages",
		"Suppress the system message shown when your chat is throttled.",
		PAD_L, y,
		function() return DB_Get("hidefailed") end,
		function(v) DB_Set("hidefailed", v); Me.Options_Apply() end)

	y = y - 40

	-- Advanced Formatting section
	local divAdv = f:CreateTexture(nil, "OVERLAY")
	divAdv:SetColorTexture(0.3, 0.3, 0.3, 0.5)
	divAdv:SetPoint("TOPLEFT", PAD_L, y + 6)
	divAdv:SetPoint("TOPRIGHT", PAD_R, y + 6)
	divAdv:SetHeight(1)

	y = y - 4

	local advLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	advLabel:SetPoint("TOPLEFT", PAD_L, y)
	advLabel:SetText("Advanced Formatting")
	advLabel:SetTextColor(0, 169/255, 236/255, 0.8)

	y = y - 20

	MakeCheckbox(f, "RP Syntax Continuity",
		"When a message splits mid-delimiter (e.g. inside \" quotes or *emote* asterisks), automatically closes the delimiter on the outgoing chunk and reopens it on the next.",
		PAD_L, y,
		function() return DB_Get("rpsyntax") end,
		function(v) DB_Set("rpsyntax", v); Me.Options_Apply() end)
	y = y - 28

	MakeCheckbox(f, "Undo / Emote Protection  (Ctrl-Z / Ctrl-Y)",
		"Adds Ctrl-Z and Ctrl-Y undo/redo to chat editboxes. Useful for recovering long emotes after accidental closes or disconnects.",
		PAD_L, y,
		function() return DB_Get("emoteprotection") end,
		function(v)
			DB_Set("emoteprotection", v)
			Me.EmoteProtection.OptionsChanged()
		end)

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
