-------------------------------------------------------------------------------
-- Enscriber -- by VfX / Bitwise1057
-------------------------------------------------------------------------------
-- Outgoing chat throttler. Manages bandwidth so we don't flood the server.
-- Separate from ChatThrottleLib: supports BNet/Club, gives chat traffic full
-- bandwidth priority, and avoids CTL re-entry issues.
-------------------------------------------------------------------------------
local Me = LibEnscriber.Internal
if not Me.load then return end

local THROTTLE_BPS   = 1000
local THROTTLE_BURST = 2000
local TIMER_PERIOD   = 0.25
local MSG_OVERHEAD   = 25

Me.bandwidth      = 0
Me.bandwidth_time = GetTime()
Me.out_chat_buffer = {}
Me.send_queue_started = false
Me.throttler_started  = false

local function MaxBandwidth()
	return InCombatLockdown() and THROTTLE_BURST/2 or THROTTLE_BURST
end

local function UpdateBandwidth()
	local time = GetTime()
	if time == Me.bandwidth_time then return end
	local bps, burst = THROTTLE_BPS, THROTTLE_BURST
	if InCombatLockdown() then
		bps   = bps / 2
		burst = burst / 2
	end
	Me.bandwidth = math.min( Me.bandwidth + bps * (time - Me.bandwidth_time),
	                         burst )
	Me.bandwidth_time = time
end

-- pcall wrapper. Swallows errors so a bad send can't corrupt throttler state.
local function SafeCall( api, ... )
	local result, a = pcall( api, ... )
	if Me.debug_mode and not result then
		Me.DebugLog( "Send API error.", a )
	end
	if result then return a end
end

local function TryDispatchMessage( msg )
	local size = (#msg.msg + MSG_OVERHEAD)
	if size > Me.bandwidth and Me.bandwidth < (MaxBandwidth() - 50) then
		return "WAIT"
	end

	local hardware = Me.inside_hook or Me.triggered_from_keystroke
	local msgtype  = msg.type
	Me.bandwidth   = Me.bandwidth - size

	if msgtype == "BNET" then
		SafeCall( Me.hooks.BNSendWhisper, msg.target, msg.msg )
	elseif msgtype == "CLUB" then
		if not hardware then return "PROMPT" end
		Me.addon_action_blocked = false
		SafeCall( Me.hooks.ClubSendMessage, msg.arg3, msg.target, msg.msg )
		if Me.addon_action_blocked then return "PROMPT" end
	elseif msgtype == "CLUBDELETE" then
		SafeCall( C_Club.DestroyMessage, msg.arg3, msg.target, msg.cmid )
	elseif msgtype == "CLUBEDIT" then
		SafeCall( C_Club.EditMessage, msg.arg3, msg.target, msg.cmid, msg.msg )
	else
		-- Standard SendChatMessage types. Hardware event required for
		-- SAY/YELL/CHANNEL without a keystroke trigger.
		-- EMOTE is intentionally excluded: it does not enforce the hardware
		-- event requirement outside of encounter lockdown. The IsLocked() guard
		-- in the editbox hook ensures no chunks enter the queue during boss/M+
		-- fights, so timer-dispatched EMOTE chunks are safe without a prompt.
		if not hardware then
			if msg.type == "CHANNEL"
			   or msg.type == "SAY"
			   or msg.type == "YELL" then
				return "PROMPT"
			end
		end

		-- Call C_ChatInfo.SendChatMessage directly. We no longer hook this
		-- global, so it remains clean and untainted.
		Me.addon_action_blocked = false
		SafeCall( C_ChatInfo.SendChatMessage, msg.msg, msgtype,
		                                               msg.arg3, msg.target )
		if Me.addon_action_blocked then return "PROMPT" end

		if msgtype == "SAY" or msgtype == "EMOTE" or msgtype == "YELL" then
			Me.StartLatencyRecording()
		end
	end

	Me.OnChatSent( msg )
	return "PASSED"
end

local ScheduleSendQueue

local function RunSendQueue()
	UpdateBandwidth()
	while #Me.out_chat_buffer > 0 do
		local msg    = Me.out_chat_buffer[1]
		local status = TryDispatchMessage( msg )
		if status == "PASSED" then
			table.remove( Me.out_chat_buffer, 1 )
		elseif status == "WAIT" then
			ScheduleSendQueue()
			return
		elseif status == "PROMPT" then
			Me.PromptForContinue()
			return
		end
	end

	if Me.throttler_started then
		Me.throttler_started = false
		Me.FireEvent( "THROTTLER_STOP" )
	end
	Me.send_queue_started = false
end

ScheduleSendQueue = function()
	if not Me.throttler_started then
		Me.throttler_started = true
		Me.FireEvent( "THROTTLER_START" )
	end
	C_Timer.After( TIMER_PERIOD, RunSendQueue )
end

function Me.PipeThrottlerKeystroke()
	Me.triggered_from_keystroke = true
	RunSendQueue()
	Me.triggered_from_keystroke = false
end

local function StartSendQueue()
	if Me.send_queue_started then return end
	Me.send_queue_started = true
	RunSendQueue()
end

function Me.ThrottlerActive()
	return Me.throttler_started
end

function Me.CommitChat( msg )
	table.insert( Me.out_chat_buffer, msg )
	StartSendQueue()
end

-- Returns available bandwidth as a percentage (max 50 in combat).
function Me.ThrottlerHealth()
	UpdateBandwidth()
	return math.ceil(Me.bandwidth / THROTTLE_BURST * 100)
end
