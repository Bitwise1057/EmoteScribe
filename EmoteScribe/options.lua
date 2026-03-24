-------------------------------------------------------------------------------
-- Emote Scribe -- Options
-------------------------------------------------------------------------------
local _, Me = ...
local AceConfig       = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local Enscriber       = LibEnscriber

local DB_DEFAULTS = {
	global = {
		premark         = "»";
		postmark        = "»";
		hidefailed      = true;
		showsending     = true;
		emoteprotection = true;
	};
	char = {
		undo_history = {};
	};
}

local OPTIONS_TABLE = {
	type = "group";
	name = "Emote Scribe";
	args = {
		desc = {
			order = 10;
			name  = "Version: " .. (C_AddOns.GetAddOnMetadata("EmoteScribe", "Version") or "?")
			       .. "|nby VfX / Bitwise1057";
			type  = "description";
		};
		postmark = {
			name  = "Postfix Mark";
			desc  = "Text appended to a message chunk to indicate it continues in the next. Leave blank to disable.";
			order = 20;
			type  = "input";
			set   = function( info, val )
				Me.db.global.postmark = val:sub( 1, 10 )
				Me.Options_Apply()
			end;
			get   = function( info ) return Me.db.global.postmark end;
		};
		desc1 = { name=""; type="description"; order=21; };
		premark = {
			name  = "Prefix Mark";
			desc  = "Text prepended to a message chunk to indicate it continues from the previous. Leave blank to disable.";
			order = 22;
			type  = "input";
			set   = function( info, val )
				Me.db.global.premark = val:sub( 1, 10 )
				Me.Options_Apply()
			end;
			get   = function( info ) return Me.db.global.premark end;
		};
		desc2 = { name=""; type="description"; order=23; };
		resetmarks = {
			name  = "Reset Marks to Default";
			desc  = "Resets both the Prefix and Postfix marks back to the default » character.";
			order = 24;
			type  = "execute";
			func  = function()
				Me.db.global.premark  = "»"
				Me.db.global.postmark = "»"
				Me.Options_Apply()
			end;
		};
		desc3 = { name=""; type="description"; order=25; };
		hidefailed = {
			name  = "Hide Failure Messages";
			desc  = "Suppress the system message shown when your chat is throttled.";
			order = 40;
			type  = "toggle";
			width = "full";
			set   = function( info, val )
				Me.db.global.hidefailed = val
				Me.Options_Apply()
			end;
			get   = function( info ) return Me.db.global.hidefailed end;
		};
		showsending = {
			name  = "Show Sending Indicator";
			desc  = "Show a small indicator at the bottom-left of the screen while messages are being sent.";
			order = 50;
			type  = "toggle";
			width = "full";
			set   = function( info, val ) Me.db.global.showsending = val end;
			get   = function( info ) return Me.db.global.showsending end;
		};
		emoteprotection = {
			name  = "Undo / Emote Protection";
			desc  = "Adds |cffffff00Ctrl-Z|r and |cffffff00Ctrl-Y|r to chat editboxes for undo/redo. Useful for recovering long emotes lost to accidental closes or disconnects.";
			order = 60;
			type  = "toggle";
			width = "full";
			set   = function( info, val )
				Me.db.global.emoteprotection = val
				Me.EmoteProtection.OptionsChanged()
			end;
			get   = function( info ) return Me.db.global.emoteprotection end;
		};
	};
}

function Me.Options_Init()
	Me.db = LibStub("AceDB-3.0"):New("EmoteScribeSaved", DB_DEFAULTS, true)
	AceConfig:RegisterOptionsTable("EmoteScribe", OPTIONS_TABLE)

	-- Wrap RegisterCanvasLayoutCategory briefly to capture the category object,
	-- which is required by Settings.OpenToCategory in 12.0+.
	if Settings and Settings.RegisterCanvasLayoutCategory then
		local original = Settings.RegisterCanvasLayoutCategory
		Settings.RegisterCanvasLayoutCategory = function( frame, name, ... )
			local cat = original( frame, name, ... )
			if name == "Emote Scribe" then
				Me.options_category = cat
			end
			return cat
		end
		AceConfigDialog:AddToBlizOptions("EmoteScribe", "Emote Scribe")
		Settings.RegisterCanvasLayoutCategory = original
	else
		AceConfigDialog:AddToBlizOptions("EmoteScribe", "Emote Scribe")
	end

	Me.Options_Apply()
end

function Me.Options_Apply()
	Enscriber.HideFailureMessages( Me.db.global.hidefailed )
	Enscriber.SetSplitmarks( Me.db.global.premark, Me.db.global.postmark, true )
end

function Me.Options_Show()
	if Me.options_category then
		Settings.OpenToCategory( Me.options_category.ID )
	end
end
