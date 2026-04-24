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
--   Sets splitterBypassing to suppress Speaketh's own editbox hook for this
--   send cycle, then falls through to original_AddChat unmodified. Chunk
--   sizing is left at the standard 255-byte boundary; Speaketh's internal
--   binary-search overflow handling fits the translation into the budget.
--
--   Me.QueueChat wrapper — runs once per chunk, after splitting.
--   Calls Speaketh:TranslateChunk, which translates the chunk, caches its
--   original locally, and broadcasts it on group/OOB channels — the full
--   originals contract, handled correctly per chunk.
--
-- Requires Speaketh 1.1.0+ (splitter API: WouldTranslate, TranslateChunk,
-- splitterBypassing).
-------------------------------------------------------------------------------
local Me = LibEnscriber.Internal
if not Me.load then return end

function Me.SpeakethCompatibility()
	-- Presence checks: addon loaded and splitter API available.
	if not C_AddOns.IsAddOnLoaded( "Speaketh" ) then return end
	if not Speaketh then return end
	if not Speaketh.WouldTranslate then return end
	if not Speaketh.TranslateChunk then return end

	local original_AddChat   = Me.AddChat
	local original_QueueChat = Me.QueueChat

	-- AddChat wrapper: runs once per send, before splitting.
	-- Suppresses Speaketh's editbox hook for this send cycle so it does not
	-- re-translate chunk[1] after QueueChat has already handled it.
	Me.AddChat = function( msg, chat_type, arg3, target )
		if Speaketh:WouldTranslate( tostring( chat_type ):upper() ) then
			-- Suppress Speaketh's editbox hook. It fires after EmoteScribe's
			-- callback in the same EventRegistry chain and would otherwise
			-- re-translate chunk[1] which QueueChat has already handled.
			-- Clear next frame after the full callback chain has completed.
			Speaketh.splitterBypassing = true
			C_Timer.After( 0, function() Speaketh.splitterBypassing = false end )
		end
		return original_AddChat( msg, chat_type, arg3, target )
	end

	-- QueueChat wrapper: runs once per chunk, after splitting.
	-- TranslateChunk handles translation, local cache, and group broadcast.
	-- Speaketh's binary-search overflow handling fits the translation into
	-- 255 bytes without falling back to untranslated text.
	Me.QueueChat = function( msg, chat_type, arg3, target )
		if Speaketh:WouldTranslate( chat_type ) then
			msg = Speaketh:TranslateChunk( msg, chat_type, target )
		end
		return original_QueueChat( msg, chat_type, arg3, target )
	end

	Me.DebugLog( "Speaketh compatibility active." )
end
