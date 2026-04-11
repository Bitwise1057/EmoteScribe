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
-- Lightweight saved-variable handler replacing AceDB.
-- Reads EmoteScribeSaved.global on load, writes back on change.
-- Falls back to DEFAULTS for any missing key.
-------------------------------------------------------------------------------
local function DB_Get( key )
	return EmoteScribeSaved.global[key]
end

local function DB_Set( key, val )
	EmoteScribeSaved.global[key] = val
end

function Me.Options_Init()
	-- Initialise saved variable table if missing or incomplete.
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

	-- Provide Me.db shim so emoteprotection.lua can keep using Me.db.char
	-- and Me.db.global without changes.
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
local WINDOW_W = 380
local WINDOW_H = 366

local function MakeLabel( parent, text, x, y, width )
	local f = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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

	-- Title bar
	local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	title:SetPoint("TOP", 0, -16)
	title:SetText("EmoteScribe")
	title:SetTextColor( 0, 169/255, 236/255, 1 )

	local ver = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	ver:SetPoint("TOP", 0, -30)
	ver:SetText("v" .. (C_AddOns.GetAddOnMetadata("EmoteScribe", "Version") or "?") .. "  |  VfX / Bitwise1057")

	-- Divider
	local div = f:CreateTexture(nil, "OVERLAY")
	div:SetTexture("Interface\\Tooltips\\UI-Tooltip-Border")
	div:SetPoint("TOPLEFT", 14, -44)
	div:SetPoint("TOPRIGHT", -14, -44)
	div:SetHeight(1)
	div:SetVertexColor(0.4, 0.4, 0.4, 0.6)

	local PAD_L = 20
	local y     = -54

	-- Split markers section
	MakeLabel(f, "Split Markers", PAD_L, y, 200)
	y = y - 18

	MakeLabel(f, "Postfix", PAD_L, y, 60)
	local postEB = MakeInput(f, PAD_L + 56, y + 2, 80, 10,
		function() return DB_Get("postmark") end,
		function(v)
			DB_Set("postmark", v)
			Me.Options_Apply()
		end)

	MakeLabel(f, "Prefix", PAD_L + 158, y, 60)
	local preEB = MakeInput(f, PAD_L + 214, y + 2, 80, 10,
		function() return DB_Get("premark") end,
		function(v)
			DB_Set("premark", v)
			Me.Options_Apply()
		end)

	y = y - 30

	MakeButton(f, "Reset Marks to Default", PAD_L, y, 180, function()
		DB_Set("premark",  "»")
		DB_Set("postmark", "»")
		preEB:SetText("»")
		postEB:SetText("»")
		Me.Options_Apply()
	end)

	y = y - 36

	-- Divider
	local div2 = f:CreateTexture(nil, "OVERLAY")
	div2:SetTexture("Interface\\Tooltips\\UI-Tooltip-Border")
	div2:SetPoint("TOPLEFT", 14, y + 8)
	div2:SetPoint("TOPRIGHT", -14, y + 8)
	div2:SetHeight(1)
	div2:SetVertexColor(0.4, 0.4, 0.4, 0.6)

	-- Checkboxes
	MakeCheckbox(f, "Hide Failure Messages",
		"Suppress the system message shown when your chat is throttled.",
		PAD_L, y - 4,
		function() return DB_Get("hidefailed") end,
		function(v)
			DB_Set("hidefailed", v)
			Me.Options_Apply()
		end)
	y = y - 28

	MakeCheckbox(f, "Show Sending Indicator",
		"Show a small indicator at the bottom-left while messages are being sent.",
		PAD_L, y,
		function() return DB_Get("showsending") end,
		function(v) DB_Set("showsending", v) end)
	y = y - 28

	MakeCheckbox(f, "Show Lockdown Notifications",
		"Show chat messages and an indicator when encounter lockdown pauses message splitting.",
		PAD_L, y,
		function() return DB_Get("showlockdown") end,
		function(v) DB_Set("showlockdown", v) end)
	y = y - 28

	MakeCheckbox(f, "Undo / Emote Protection  (Ctrl-Z / Ctrl-Y)",
		"Adds Ctrl-Z and Ctrl-Y undo/redo to chat editboxes. Useful for recovering long emotes after accidental closes or disconnects.",
		PAD_L, y,
		function() return DB_Get("emoteprotection") end,
		function(v)
			DB_Set("emoteprotection", v)
			Me.EmoteProtection.OptionsChanged()
		end)
	y = y - 28

	MakeCheckbox(f, "RP Syntax Continuity",
		"When a message splits mid-delimiter (e.g. inside \" quotes or *emote* asterisks), automatically closes the delimiter on the outgoing chunk and reopens it on the next chunk.",
		PAD_L, y,
		function() return DB_Get("rpsyntax") end,
		function(v)
			DB_Set("rpsyntax", v)
			Me.Options_Apply()
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
