-------------------------------------------------------------------------------
-- Enscriber -- by VfX / Bitwise1057
-------------------------------------------------------------------------------
local Me = LibEnscriber.Internal
if not Me.load then return end

-- Called one frame after PLAYER_LOGIN so other addons are initialised.
function Me.AddCompatibilityLayers()
	Me.UCMCompatibility()
	Me.EmoteSplitterCompatibility()
	Me.MisspelledCompatibility()
end

-- UnlimitedChatMessage: warn the user and offer to disable it.
StaticPopupDialogs["EMOTESCRIBE_UCM_CONFLICT"] = {
	text        = "|cff00a9ecEmoteScribe|r has detected that |cffff4400UnlimitedChatMessage|r"
	              .. " is enabled.\n\nBoth addons manage chat splitting and will"
	              .. " conflict with each other.\n\nPlease disable UnlimitedChatMessage.",
	button1     = "Disable & Reload",
	button2     = "Ignore",
	OnAccept    = function()
		C_AddOns.DisableAddOn( "UnlimitedChatMessage" )
		ReloadUI()
	end,
	OnCancel    = function()
		Me.ucm_conflict_ignored = true
	end,
	timeout     = 0,
	whileDead   = true,
	hideOnEscape = true,
}

function Me.UCMCompatibility()
	if Me.ucm_conflict_ignored then return end
	if not C_AddOns.IsAddOnLoaded( "UnlimitedChatMessage" ) then return end
	StaticPopup_Show( "EMOTESCRIBE_UCM_CONFLICT" )
end

-- EmoteSplitter: warn the user and offer to disable it.
StaticPopupDialogs["EMOTESCRIBE_EMOTESPLITTER_CONFLICT"] = {
	text        = "|cff00a9ecEmoteScribe|r has detected that |cffff4400EmoteSplitter|r"
	              .. " is enabled.\n\nBoth addons manage chat splitting and will"
	              .. " conflict with each other.\n\nPlease disable EmoteSplitter.",
	button1     = "Disable & Reload",
	button2     = "Ignore",
	OnAccept    = function()
		C_AddOns.DisableAddOn( "EmoteSplitter" )
		ReloadUI()
	end,
	OnCancel    = function()
		Me.emotesplitter_conflict_ignored = true
	end,
	timeout     = 0,
	whileDead   = true,
	hideOnEscape = true,
}

function Me.EmoteSplitterCompatibility()
	if Me.emotesplitter_conflict_ignored then return end
	if not C_AddOns.IsAddOnLoaded( "EmoteSplitter" ) then return end
	StaticPopup_Show( "EMOTESCRIBE_EMOTESPLITTER_CONFLICT" )
end

-- Misspelled: warn the user and offer to disable it.
StaticPopupDialogs["EMOTESCRIBE_MISSPELLED_CONFLICT"] = {
	text        = "|cff00a9ecEmoteScribe|r has detected that |cffff4400Misspelled|r"
	              .. " is enabled.\n\nBoth addons manage chat splitting and will"
	              .. " conflict with each other.\n\nPlease disable Misspelled.",
	button1     = "Disable & Reload",
	button2     = "Ignore",
	OnAccept    = function()
		C_AddOns.DisableAddOn( "Misspelled" )
		ReloadUI()
	end,
	OnCancel    = function()
		Me.misspelled_conflict_ignored = true
	end,
	timeout     = 0,
	whileDead   = true,
	hideOnEscape = true,
}

function Me.MisspelledCompatibility()
	if Me.misspelled_conflict_ignored then return end
	if not C_AddOns.IsAddOnLoaded( "Misspelled" ) then return end
	StaticPopup_Show( "EMOTESCRIBE_MISSPELLED_CONFLICT" )
end
