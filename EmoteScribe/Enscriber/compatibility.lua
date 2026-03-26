-------------------------------------------------------------------------------
-- Enscriber -- by VfX / Bitwise1057
-------------------------------------------------------------------------------
local Me = LibEnscriber.Internal
if not Me.load then return end

-- Called one frame after PLAYER_LOGIN so other addons are initialised.
function Me.AddCompatibilityLayers()
	Me.UCMCompatibility()
	-- Me.MisspelledCompatibility()
end

-- UnlimitedChatMessage: remove its SendChatMessage hook, keep its editbox work.
function Me.UCMCompatibility()
	if Me.compatibility_ucm then return end
	if not UCM then return end
	if UCM.core.hooks.SendChatMessage then
		Me.compatibility_ucm = true
		UCM.core:Unhook( "SendChatMessage" )
	end
end

--[[ Misspelled: unhook its SendChatMessage and run its highlight removal via
-- a listener instead, so it doesn't shrink already-split chunks.
function Me.MisspelledCompatibility()
	if Me.compatibility_misspelled then return end
	if not Misspelled then return end
	if not Misspelled.hooks or not Misspelled.hooks.SendChatMessage then return end

	Me.compatibility_misspelled = true
	Misspelled:Unhook( "SendChatMessage" )

	-- Misspelled highlight removal is hooked into the editbox pre-send path
	-- by the main addon (EmoteScribe.lua) rather than as an Enscriber event
	-- listener, since CHAT_NEW no longer exists. The unhook above is still
	-- needed to prevent Misspelled from interfering with SendChatMessage.
end
--]]
