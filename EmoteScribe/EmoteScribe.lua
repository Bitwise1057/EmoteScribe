-------------------------------------------------------------------------------
-- Emote Scribe -- by VfX / Bitwise1057
-------------------------------------------------------------------------------
local AddonName, Me = ...

LibStub("AceAddon-3.0"):NewAddon( Me, "EmoteScribe", "AceHook-3.0",
                                                      "AceEvent-3.0" )

EmoteScribe = Me
local Enscriber = LibEnscriber

SlashCmdList["EMOTESCRIBE"] = function( msg )
	if msg == "" then
		Me.Options_Show()
		return
	end

	local args = msg:gmatch( "%S+" )
	local arg1 = args()
	local arg2 = args()

	if arg1:lower() == "debug" then
		Enscriber.Internal.debug_mode = not Enscriber.Internal.debug_mode
		if Enscriber.Internal.debug_mode then
			print( "|cff00a9ec<EmoteScribe>|r Debug logging ON." )
		else
			print( "|cff00a9ec<EmoteScribe>|r Debug logging OFF." )
		end
		return
	end

	if arg1:lower() == "maxlen" then
		local v = tonumber(arg2) or 0
		v = math.max( v, 40 )
		v = math.min( v, 255 )
		Enscriber.SetChunkSizeOverride( "OTHER", v )
		print( "Max message length set to " .. v .. "." )
		return
	end

	--[[ lockinfo — diagnostic command, uncomment to re-enable.
	if arg1:lower() == "lockinfo" then
		local combat = InCombatLockdown()
		local msgLock = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
		               and C_ChatInfo.InChatMessagingLockdown() or false
		local isLocked = Enscriber.Internal.IsLocked()

		local eb = LAST_ACTIVE_CHAT_EDIT_BOX or ACTIVE_CHAT_EDIT_BOX
		local maxBytes, maxLetters, visByteLimit = "N/A", "N/A", "N/A"
		if eb then
			maxBytes    = eb:GetMaxBytes()
			maxLetters  = eb:GetMaxLetters()
			if eb.GetVisibleTextByteLimit then
				visByteLimit = eb:GetVisibleTextByteLimit()
			end
		end

		print( "|cff00a9ec<EmoteScribe>|r Lock diagnostics:" )
		print( "  InCombatLockdown: " .. tostring(combat) )
		print( "  InChatMessagingLockdown: " .. tostring(msgLock) )
		print( "  IsLocked (composite): " .. tostring(isLocked) )
		print( "  Editbox MaxBytes: " .. tostring(maxBytes)
		       .. "  MaxLetters: " .. tostring(maxLetters)
		       .. "  VisByteLimit: " .. tostring(visByteLimit) )
		print( "  (0 = unlimited, 255 = locked)" )
		return
	end
	--]]
end

function Me:OnEnable()
	Me.Options_Init()
	SLASH_EMOTESCRIBE1 = "/scribe"

	Enscriber.Listen( "SEND_START",               Me.Enscriber_SEND_START               )
	Enscriber.Listen( "SEND_DONE",                Me.Enscriber_SEND_DONE                )
	Enscriber.Listen( "SEND_DEATH",               Me.Enscriber_SEND_DEATH               )
	Enscriber.Listen( "SEND_FAIL",                Me.Enscriber_SEND_FAIL                )
	Enscriber.Listen( "SEND_CONFIRMED",           Me.Enscriber_SEND_CONFIRMED           )
	Enscriber.Listen( "SEND_RECOVER",             Me.Enscriber_SEND_RECOVER             )
	Enscriber.Listen( "THROTTLER_START",          Me.Enscriber_THROTTLER_START          )
	Enscriber.Listen( "THROTTLER_STOP",           Me.Enscriber_THROTTLER_STOP           )
	Enscriber.Listen( "ENCOUNTER_LOCKDOWN_START", Me.Enscriber_ENCOUNTER_LOCKDOWN_START )
	Enscriber.Listen( "ENCOUNTER_LOCKDOWN_END",   Me.Enscriber_ENCOUNTER_LOCKDOWN_END   )

	-- BNet and Club messages support up to 4000 chars; we cap chunks at 400.
	Enscriber.Internal.default_chunk_sizes.BNET = 400
	Enscriber.Internal.default_chunk_sizes.CLUB = 400

	-- Track editbox defaults per-frame. During chat lockdown the limits are
	-- restored so oversized text can't reach SendText and cause an error.
	Me.editbox_defaults = Me.editbox_defaults or {}

	EventRegistry:RegisterCallback(
		"ChatFrame.OnEditBoxFocusGained",
		function( _, editBox )
			if not Me.editbox_defaults[editBox] then
				local visLimit = 0
				if editBox.GetVisibleTextByteLimit then
					visLimit = editBox:GetVisibleTextByteLimit()
				end
				Me.editbox_defaults[editBox] = {
					MaxLetters           = editBox:GetMaxLetters(),
					MaxBytes             = editBox:GetMaxBytes(),
					VisibleTextByteLimit = visLimit,
				}
			end

			if Enscriber.Internal.IsLocked() then
				local d = Me.editbox_defaults[editBox]
				editBox:SetMaxLetters( d.MaxLetters )
				editBox:SetMaxBytes( d.MaxBytes )
				if editBox.SetVisibleTextByteLimit then
					editBox:SetVisibleTextByteLimit( d.VisibleTextByteLimit )
				end
			else
				editBox:SetMaxLetters( 0 )
				editBox:SetMaxBytes( 0 )
				if editBox.SetVisibleTextByteLimit then
					editBox:SetVisibleTextByteLimit( 0 )
				end
			end
		end
	)

	Me.UnlockCommunitiesChat()

	local f = CreateFrame( "Frame", "EmoteScribeSending", UIParent )
	f:SetPoint( "BOTTOMLEFT", 3, 3 )
	f:SetSize( 200, 20 )
	f:EnableMouse( false )
	Me.sending_text = EmoteScribeSending

	-- Lockdown indicator — sits just above the sending indicator.
	local lf = CreateFrame( "Frame", "EmoteScribeLockdown", UIParent )
	lf:SetPoint( "BOTTOMLEFT", 3, 3 )
	lf:SetSize( 250, 20 )
	lf:EnableMouse( false )
	lf:SetFrameStrata( "DIALOG" )
	lf:Hide()
	lf.text = lf:CreateFontString( nil, "ARTWORK", "EmoteScribeSendingFont" )
	lf.text:SetPoint( "BOTTOMLEFT" )
	lf.text:SetTextColor( 0, 169/255, 236/255, 1 )
	lf.text:SetText( "Lockdown: Splitting Paused" )
	Me.lockdown_indicator = lf

	Me.EmoteProtection.Init()
end

function Me.SendingText_ShowSending()
	if not Me.db.global.showsending then return end
	local t = Me.sending_text
	if not t then return end
	t.text:SetTextColor( 0, 169/255, 236/255, 1 )
	t.text:SetText( "Sending... " )
	t:Show()
end

function Me.SendingText_ShowFailed()
	if not Me.db.global.showsending then return end
	local t = Me.sending_text
	if not t then return end
	t.text:SetTextColor( 239/255,19/255,19/255,1 )
	t.text:SetText( "Waiting..." )
	t:Show()
end

function Me.SendingText_Hide()
	if not Me.sending_text then return end
	Me.sending_text:Hide()
end

function Me.Enscriber_SEND_START()    Me.SendingText_ShowSending() end
function Me.Enscriber_SEND_DONE()     Me.SendingText_Hide() end
function Me.Enscriber_SEND_CONFIRMED() Me.SendingText_ShowSending() end
function Me.Enscriber_SEND_FAIL()     Me.SendingText_ShowFailed() end

function Me.Enscriber_SEND_DEATH()
	Me.SendingText_Hide()
	print( "|cffff0000<Chat failed!>|r" )
end

function Me.Enscriber_SEND_RECOVER()
	if not Me.db.global.hidefailed then
		print( "|cffff00ff<Resending...>" )
	end
	Me.SendingText_ShowSending()
end

function Me.Enscriber_THROTTLER_START() Me.SendingText_ShowSending() end

function Me.Enscriber_THROTTLER_STOP()
	if not Enscriber.AnyChannelsBusy() then
		Me.SendingText_Hide()
	end
end

-- 12.0: During boss/M+/PvP lockdown Enscriber steps aside entirely.
-- Messages over 255 chars are server-truncated, same as without the addon.
function Me.Enscriber_ENCOUNTER_LOCKDOWN_START()
	Me.in_lockdown = true
	if Me.db.global.showlockdown then
		print( "|cff00a9ec<EmoteScribe>|r Message splitting paused"
		       .. " (encounter lockdown). 255 character limit applies." )
	end
	if Me.lockdown_indicator and Me.db.global.showlockdown then
		Me.lockdown_indicator:Show()
	end
end

function Me.Enscriber_ENCOUNTER_LOCKDOWN_END()
	if not Me.in_lockdown then return end
	Me.in_lockdown = false
	if Me.db.global.showlockdown then
		print( "|cff00ff00<EmoteScribe>|r Message splitting resumed." )
	end
	if Me.lockdown_indicator then
		Me.lockdown_indicator:Hide()
	end
end

-- Unlock the Communities chatbox character limit.
function Me.UnlockCommunitiesChat()
	if not C_Club then return end
	if not CommunitiesFrame then
		Me:RegisterEvent( "ADDON_LOADED", function( event, addon )
			if addon == "Blizzard_Communities" then
				Me:UnregisterEvent( "ADDON_LOADED" )
				Me.UnlockCommunitiesChat()
			end
		end)
		return
	end
	CommunitiesFrame.ChatEditBox:SetMaxBytes( 0 )
	CommunitiesFrame.ChatEditBox:SetMaxLetters( 0 )
	CommunitiesFrame.ChatEditBox:SetVisibleTextByteLimit( 0 )
end

-- TRP3 NPC chat frame integration. Set EmoteScribe.disable_trp_npc_extension
-- to disable if TRP3 handles this internally.
function Me.ExtendTRPNPCChat()
	if not TRP3_API then return end
	if Me.disable_trp_npc_extension then return end

	local function SendChat()
		local name    = strtrim( TRP3_NPCTalk.name:GetText() )
		local channel = TRP3_NPCTalk.channelDropdown:GetSelectedValue()
		local msg     = TRP3_NPCTalk.messageText.scroll.text:GetText()
		if #msg == 0 or #name == 0 then return end

		local padding = ""
		if channel == "MONSTER_SAY" then
			padding = TRP3_API.loc.NPC_TALK_SAY_PATTERN .. " "
		elseif channel == "MONSTER_YELL" then
			padding = TRP3_API.loc.NPC_TALK_YELL_PATTERN .. " "
		elseif channel == "MONSTER_WHISPER" then
			padding = TRP3_API.loc.NPC_TALK_WHISPER_PATTERN .. " "
		end

		-- TRP NPC talk uses SendChatMessage directly, which goes through
		-- the editbox hook path. The padding is prepended to the message.
		SendChatMessage(
			TRP3_API.chat.configNPCTalkPrefix() .. name .. " " .. padding .. msg,
			"EMOTE" )
		TRP3_NPCTalk.messageText.scroll.text:SetText( "" )
	end

	local function OnTextChanged()
		local hasname = #strtrim(TRP3_NPCTalk.name:GetText()) > 0
		local hasmsg  = #strtrim(TRP3_NPCTalk.messageText.scroll.text:GetText()) > 0
		if hasname and hasmsg then
			TRP3_NPCTalk.send:Enable()
		else
			TRP3_NPCTalk.send:Disable()
		end
	end

	TRP3_API.events.listenToEvent( TRP3_API.events.WORKFLOW_ON_FINISH, function()
		local send_button      = TRP3_NPCTalk.send
		local message_text     = TRP3_NPCTalk.messageText.scroll.text
		local npc_name         = TRP3_NPCTalk.name

		send_button:SetScript( "OnClick", SendChat )
		message_text:SetScript( "OnEnterPressed", SendChat )
		TRP3_NPCTalk.channelDropdown.callback = OnTextChanged
		message_text:HookScript( "OnTextChanged", OnTextChanged )
		message_text:HookScript( "OnEditFocusGained", OnTextChanged )
		npc_name:HookScript( "OnTextChanged", OnTextChanged )
		npc_name:HookScript( "OnEditFocusGained", OnTextChanged )
		TRP3_NPCTalk.charactersCounter:Hide()
	end)
end
