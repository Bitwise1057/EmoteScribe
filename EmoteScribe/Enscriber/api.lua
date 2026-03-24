-------------------------------------------------------------------------------
-- Enscriber -- by VfX / Bitwise1057
-------------------------------------------------------------------------------
local Internal = LibEnscriber.Internal
if not Internal.load then return end
local Enscriber = LibEnscriber

function Enscriber.GetVersion()
	return Internal.VERSION
end

-- Register a callback for an Enscriber event. Returns true on success, false
-- if already registered. See Enscriber.lua for the full event list.
Enscriber.Listen         = Internal.Listen
Enscriber.StopListening  = Internal.StopListening
Enscriber.GetEventListeners = Internal.GetEventHooks

-- Override the chunk size for a given chat type. Pass nil to remove.
-- Use "OTHER" to override the default for all types.
-- Resolution order: overrides[type] > defaults[type] > overrides.OTHER > defaults.OTHER
Enscriber.SetChunkSizeOverride = Internal.SetChunkSizeOverride

-- Set the split markers added at the end/start of continued message chunks.
-- sticky=true persists for all future messages; false applies once only.
-- Pass nil to leave a value unchanged, false to clear it.
Enscriber.SetSplitmarks = Internal.SetSplitmarks
Enscriber.GetSplitmarks = Internal.GetSplitmarks

-- Queue state queries.
Enscriber.AnyChannelsBusy = Internal.AnyChannelsBusy
Enscriber.SendingActive   = Internal.SendingActive

-- Returns Enscriber's measured latency in seconds.
Enscriber.GetLatency = Internal.GetLatency

-- Returns available bandwidth as a percentage (max 50 during combat lockdown).
Enscriber.ThrottlerHealth = Internal.ThrottlerHealth

-- Returns true if the throttler is currently waiting through a delay.
Enscriber.ThrottlerActive = Internal.ThrottlerActive

-- Hide/show the system throttle error message in chat.
Enscriber.HideFailureMessages = Internal.HideFailureMessages

-- Timer helpers with slot-based management.
-- mode: "push" (reset), "ignore" (skip if running), "duplicate", "cooldown"
Enscriber.Timer_Start  = Internal.Timer_Start
Enscriber.Timer_Cancel = Internal.Timer_Cancel

-- Enable or disable debug logging to chat.
function Enscriber.Debug( setting )
	if setting == nil then setting = true end
	if setting == false then setting = nil end
	Enscriber.Internal.debug_mode = setting
end
