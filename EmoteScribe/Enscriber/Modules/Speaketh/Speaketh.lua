-------------------------------------------------------------------------------
-- Enscriber -- by VfX / Bitwise1057
-------------------------------------------------------------------------------
-- Speaketh compatibility module.
--
-- Speaketh is a roleplay language addon that translates outgoing chat into
-- constructed languages (Orcish, Thalassian, etc.) and applies dialect
-- effects (Troll accent, Drunk slurring, etc.). It hooks the same
-- ChatFrame.OnEditBoxPreSendText event that EmoteScribe uses to intercept
-- outgoing messages.
--
-- Without this module, Speaketh would only see chunk[1] of a split message
-- — the text EmoteScribe leaves in the editbox — and chunks 2+ would be
-- dispatched untranslated. Additionally, other Speaketh users would only
-- receive a decode payload for chunk[1], leaving the rest unreadable.
--
-- Architecture:
--
--   Me.AddChat wrapper — runs once per send, before splitting.
--   Queries GetTagOverhead to tighten the chunk size so each chunk has
--   room for the [Language] prefix after translation. Sets splitterBypassing
--   to suppress Speaketh's own editbox hook for this send cycle. Saves and
--   restores any pre-existing chunk size override.
--
--   Me.QueueChat wrapper — runs once per chunk, after splitting.
--   Calls Speaketh:TranslateChunk, which translates the chunk, caches its
--   original locally, and broadcasts it on group/OOB channels — the full
--   originals contract, handled correctly per chunk.
--
-- Requires Speaketh 1.1.0+ (splitter API: WouldTranslate, GetTagOverhead,
-- TranslateChunk, splitterBypassing).
-------------------------------------------------------------------------------
local Me = LibEnscriber.Internal
if not Me.load then return end

function Me.SpeakethCompatibility()
	-- Presence checks: addon loaded and full splitter API available.
	if not C_AddOns.IsAddOnLoaded( "Speaketh" ) then return end
	if not Speaketh then return end
	if not Speaketh.WouldTranslate  then return end
	if not Speaketh.GetTagOverhead  then return end
	if not Speaketh.TranslateChunk  then return end

	local original_AddChat   = Me.AddChat
	local original_QueueChat = Me.QueueChat

	-- AddChat wrapper: runs once per send, before splitting.
	-- Tightens the chunk size to leave room for the [Language] tag, sets the
	-- bypass flag, then falls through to original_AddChat unmodified.
	Me.AddChat = function( msg, chat_type, arg3, target )
		local type_upper     = tostring( chat_type ):upper()
		local will_translate = Speaketh:WouldTranslate( type_upper )
		local prev_override  = nil

		if will_translate then
			local overhead = Speaketh:GetTagOverhead( type_upper )
			if overhead > 0 then
				local base_size = Me.chunk_size_overrides[type_upper]
				                  or Me.default_chunk_sizes[type_upper]
				                  or Me.chunk_size_overrides.OTHER
				                  or Me.default_chunk_sizes.OTHER
				prev_override = Me.chunk_size_overrides[type_upper]
				Me.chunk_size_overrides[type_upper] = base_size - overhead
			end

			-- Suppress Speaketh's editbox hook. It fires after EmoteScribe's
			-- callback in the same EventRegistry chain and would otherwise
			-- re-translate chunk[1] which QueueChat has already handled.
			-- Clear next frame after the full callback chain has completed.
			Speaketh.splitterBypassing = true
			C_Timer.After( 0, function() Speaketh.splitterBypassing = false end )
		end

		local ok, err = pcall( original_AddChat, msg, chat_type, arg3, target )

		-- Restore chunk size override regardless of outcome.
		-- Only needed if we actually set one (overhead > 0 path).
		if will_translate and Me.chunk_size_overrides[type_upper] ~= prev_override then
			Me.chunk_size_overrides[type_upper] = prev_override
		end

		if not ok then
			Me.DebugLog( "SpeakethCompatibility: AddChat error:", err )
		end
	end

	-- QueueChat wrapper: runs once per chunk, after splitting.
	-- TranslateChunk handles translation, local cache, and group broadcast.
	Me.QueueChat = function( msg, chat_type, arg3, target )
		if Speaketh:WouldTranslate( chat_type ) then
			msg = Speaketh:TranslateChunk( msg, chat_type, target )
		end
		return original_QueueChat( msg, chat_type, arg3, target )
	end

	Me.DebugLog( "Speaketh compatibility active." )
end
