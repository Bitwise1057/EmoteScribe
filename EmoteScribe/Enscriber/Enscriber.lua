-------------------------------------------------------------------------------
-- Enscriber -- by VfX / Bitwise1057
-------------------------------------------------------------------------------
-- Allows SendChatMessage and related APIs to accept messages larger than 255
-- characters, splitting them automatically. Provides a robust queue system
-- that verifies delivery and retries on server throttle errors.
-------------------------------------------------------------------------------

local VERSION = 16

if IsLoggedIn() then
   error( "Enscriber can't be loaded on demand!" )
end

local Me

if LibEnscriber then
   Me = LibEnscriber.Internal
   if Me.VERSION >= VERSION then
      Me.load = false
      return
   end
else
   LibEnscriber = { Internal = {} }
   Me = LibEnscriber.Internal
end

Me.VERSION = VERSION
Me.load    = true

-------------------------------------------------------------------------------
-- Queue internals
-- Queue 1: SAY, EMOTE, YELL, BNET  (confirmed via chat echo)
-- Queue 2: GUILD, OFFICER, CLUB    (confirmed via club events)
-- Queue 3: CLUBEDIT, CLUBDELETE    (confirmed via CLUB_MESSAGE_UPDATED)
Me.chat_queue    = {}
Me.channels_busy = {}
Me.message_id    = 1
Me.NUM_CHANNELS  = 3

local QUEUED_TYPES = {
   SAY        = 1;
   EMOTE      = 1;
   YELL       = 1;
   BNET       = 1;
   GUILD      = 2;
   OFFICER    = 2;
   CLUB       = 2;
   CLUBEDIT   = 3;
   CLUBDELETE = 3;
}

if not C_Club then
   QUEUED_TYPES.GUILD   = nil
   QUEUED_TYPES.OFFICER = nil
end

-------------------------------------------------------------------------------
-- Event system — simplified flat listener table.
-- Internal code calls Me.FireEvent(name, ...) which iterates listeners.
-- External addons use Listen/StopListening via api.lua.
Me.event_hooks = {
   SEND_START     = {};  -- Queue became active.
   SEND_FAIL      = {};  -- Server throttle detected, will retry.
   SEND_RECOVER   = {};  -- Retrying after failure.
   SEND_DEATH     = {};  -- Queue timed out, hard reset.
   SEND_CONFIRMED = {};  -- Server echo confirmed a queued message.
   SEND_DONE      = {};  -- Queue emptied, back to idle.
   THROTTLER_START = {}; -- Throttler inserted a bandwidth delay.
   THROTTLER_STOP  = {}; -- Throttler finished all delayed sends.
   ENCOUNTER_LOCKDOWN_START = {};
   ENCOUNTER_LOCKDOWN_END   = {};
}

Me.channel_failures = {}
Me.FAILURE_LIMIT    = 5

Me.CHAT_TIMEOUT       = 10.0
Me.CHAT_THROTTLE_WAIT = 3.0

Me.default_chunk_sizes = { OTHER = 255 }
Me.chunk_size_overrides = {}

Me.latency           = 0.1
Me.latency_recording = nil

Me.hide_failure_messages = true

Me.splitmark_start = "»"
Me.splitmark_end   = "»"

Me.chat_replacement_patterns = {
   -- Protect chat links from being split mid-link.
   -- Supports |cff (hex), |cn (named), and |cnIQ (item quality) color codes.
   "(|c[fn][^|]*|H[^|]+|h(.-)|h|r)";
}

-------------------------------------------------------------------------------
Me.frame = Me.frame or CreateFrame( "Frame" )
Me.frame:UnregisterAllEvents()
Me.frame:RegisterEvent( "PLAYER_LOGIN" )

Me.continue_frame_label = "Press enter to continue."

-------------------------------------------------------------------------------
function Me.OnLogin()
   C_Timer.After( 0.01, Me.AddCompatibilityLayers )
   Me.PLAYER_GUID = UnitGUID("player")
   Me.SetupContinueFrame()

   Me.frame:RegisterEvent( "CHAT_MSG_SAY"   )
   Me.frame:RegisterEvent( "CHAT_MSG_EMOTE" )
   Me.frame:RegisterEvent( "CHAT_MSG_YELL"  )

   if C_Club then
      Me.frame:RegisterEvent( "CLUB_MESSAGE_ADDED"          )
      Me.frame:RegisterEvent( "CHAT_MSG_COMMUNITIES_CHANNEL")
      Me.frame:RegisterEvent( "CHAT_MSG_GUILD"              )
      Me.frame:RegisterEvent( "CHAT_MSG_OFFICER"            )
      Me.frame:RegisterEvent( "CLUB_ERROR"                  )
      Me.frame:RegisterEvent( "CLUB_MESSAGE_UPDATED"        )
   end

   Me.frame:RegisterEvent( "CHAT_MSG_BN_WHISPER_INFORM"          )
   Me.frame:RegisterEvent( "CHAT_MSG_BN_WHISPER_PLAYER_OFFLINE"  )
   Me.frame:RegisterEvent( "CHAT_MSG_SYSTEM"                     )
   Me.frame:RegisterEvent( "ADDON_ACTION_BLOCKED"                )
   Me.frame:RegisterEvent( "ENCOUNTER_START"                     )
   Me.frame:RegisterEvent( "ENCOUNTER_END"                       )

   local AddFilter = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter
                     or ChatFrame_AddMessageEventFilter
   AddFilter( "CHAT_MSG_SYSTEM", function( _, _, msg, sender )
      if Me.hide_failure_messages and msg == ERR_CHAT_THROTTLED then
         return true
      end
   end)

   Me.DebugLog( "Initialized." )
end

-------------------------------------------------------------------------------
-- Continue-prompt frame. Overlays the editbox with "Press enter to continue."
-- when the throttler needs a hardware event to dispatch chunk[2+] of
-- SAY/EMOTE/YELL messages.
function Me.SetupContinueFrame()
   Me.continue_frame = Me.continue_frame or CreateFrame( "Frame", nil, UIParent )
   Me.continue_frame:Hide()
   Me.continue_frame:SetScript( "OnUpdate", function( self )
      if LAST_ACTIVE_CHAT_EDIT_BOX then
         self:SetAllPoints( LAST_ACTIVE_CHAT_EDIT_BOX )
      end
   end)
   Me.continue_frame.text = Me.continue_frame.text
                            or Me.continue_frame:CreateFontString()
   local text = Me.continue_frame.text
   text:SetFontObject( GameFontNormal )
   text:SetAllPoints()
end

function Me.ShowContinueFrame()
   Me.continue_frame:Show()
   Me.continue_frame.text:SetText( Me.continue_frame_label )
end

function Me.HideContinueFrame()
   Me.continue_frame:Hide()
end

function Me.OnOpenChat( ... )
   if Me.TryContinuePrompt() then
      if ACTIVE_CHAT_EDIT_BOX and ACTIVE_CHAT_EDIT_BOX.text ~= "/" then
         ACTIVE_CHAT_EDIT_BOX:Hide()
      end
      if CHAT_FOCUS_OVERRIDE then
         CHAT_FOCUS_OVERRIDE:ClearFocus()
      end
   end
end

function Me.TryContinuePrompt()
   if Me.prompt_continue and Me.ThrottlerHealth() > 30 then
      Me.prompt_continue = false
      Me.HideContinueFrame()
      Me.PipeThrottlerKeystroke()
      return true
   end
end

function Me.PromptForContinue()
   Me.prompt_continue = true
   Me.ShowContinueFrame()
end

-------------------------------------------------------------------------------
function Me.OnGameEvent( frame, event, ... )
   if event == "CHAT_MSG_SAY" or event == "CHAT_MSG_EMOTE"
                                             or event == "CHAT_MSG_YELL" then
      Me.TryConfirm( event:sub( 10 ) )
   elseif event == "CLUB_MESSAGE_ADDED" then
      Me.OnClubMessageAdded( event, ... )
   elseif event == "CHAT_MSG_GUILD" or event == "CHAT_MSG_OFFICER" then
      Me.OnChatMsgGuildOfficer( event, ... )
   elseif event == "CHAT_MSG_COMMUNITIES_CHANNEL" then
      Me.OnChatMsgCommunitiesChannel( event, ... )
   elseif event == "CHAT_MSG_BN_WHISPER_INFORM" then
      Me.TryConfirm( "BNET", Me.PLAYER_GUID )
   elseif event == "CLUB_ERROR" then
      Me.OnClubError( event, ... )
   elseif event == "CLUB_MESSAGE_UPDATED" then
      Me.OnClubMessageUpdated( event, ... )
   elseif event == "CHAT_MSG_BN_WHISPER_PLAYER_OFFLINE" then
      Me.OnChatMsgBnOffline( event, ... )
   elseif event == "CHAT_MSG_SYSTEM" then
      Me.OnChatMsgSystem( event, ... )
   elseif event == "ADDON_ACTION_BLOCKED" then
      Me.addon_action_blocked = true
   elseif event == "ENCOUNTER_START" then
      Me.FireEvent( "ENCOUNTER_LOCKDOWN_START" )
   elseif event == "ENCOUNTER_END" then
      Me.FireEvent( "ENCOUNTER_LOCKDOWN_END" )
   elseif event == "PLAYER_LOGIN" then
      Me.OnLogin()
   end
end

Me.frame:SetScript( "OnEvent", Me.OnGameEvent )

function Me.HideFailureMessages( hide )
   Me.hide_failure_messages = hide
end

-------------------------------------------------------------------------------
-- Event system — flat listener model.
local function FindTableValue( table, value )
   for k, v in pairs( table ) do
      if v == value then return k end
   end
end

function Me.Listen( event, func )
   if not Me.event_hooks[event] then error( "Invalid event." ) end
   if FindTableValue( Me.event_hooks[event], func ) then return false end
   table.insert( Me.event_hooks[event], func )
   return true
end

function Me.StopListening( event, func )
   if not Me.event_hooks[event] then error( "Invalid event." ) end
   local index = FindTableValue( Me.event_hooks[event], func )
   if index then
      table.remove( Me.event_hooks[event], index )
      return true
   end
   return false
end

function Me.GetEventHooks( event )
   return Me.event_hooks[event]
end

function Me.FireEvent( event, ... )
   local hooks = Me.event_hooks[event]
   if not hooks then return end
   for i = 1, #hooks do
      local ok, err = pcall( hooks[i], event, ... )
      if not ok then
         Me.DebugLog( "Listener error:", err )
      end
   end
end

-------------------------------------------------------------------------------
function Me.SetChunkSizeOverride( chat_type, chunk_size )
   Me.chunk_size_overrides[chat_type] = chunk_size
end

local function FalseIsNil( value )
   if value == false then return nil else return value end
end

function Me.SetSplitmarks( pre, post, sticky )
   local key_pre, key_post = "splitmark_start", "splitmark_end"
   if not sticky then
      key_pre  = key_pre  .. "_temp"
      key_post = key_post .. "_temp"
   end
   if pre  ~= nil then Me[key_pre]  = FalseIsNil( pre  ) end
   if post ~= nil then Me[key_post] = FalseIsNil( post ) end
end

function Me.GetSplitmarks( sticky )
   if sticky then
      return Me.splitmark_start, Me.splitmark_end
   else
      return Me.splitmark_start_temp, Me.splitmark_end_temp
   end
end

-------------------------------------------------------------------------------
-- Split text on newlines and literal "\n" sequences.
function Me.SplitLines( text )
   text = text:gsub( "\\n", "\n" )
   local lines = {}
   for line in text:gmatch( "[^\n]+" ) do
      table.insert( lines, line )
   end
   if #lines == 0 then lines[1] = "" end
   return lines
end

-------------------------------------------------------------------------------
-- BNet and Club hook functions (these globals are still replaced because they
-- are not subject to the same taint restrictions as SendChatMessage).
function Me.BNSendWhisperHook( presence_id, message_text )
   Me.inside_hook = "BNET"
   Me.AddChat( message_text, "BNET", nil, presence_id )
   Me.inside_hook = nil
end

function Me.ClubSendMessageHook( club_id, stream_id, message )
   Me.inside_hook = "CLUB"
   Me.AddChat( message, "CLUB", club_id, stream_id )
   Me.inside_hook = nil
end

local function GetGuildClub()
   for _, club in pairs( C_Club.GetSubscribedClubs() ) do
      if club.clubType == Enum.ClubType.Guild then return club.clubId end
   end
end

-------------------------------------------------------------------------------
function Me.ResetState()
   Me.splitmark_end_temp   = nil
   Me.splitmark_start_temp = nil
end

-------------------------------------------------------------------------------
-- Main message processing entry point. Splits the message into chunks and
-- queues each chunk for delivery.
function Me.AddChat( msg, chat_type, arg3, target )
   msg = tostring( msg or "" )
   msg = Me.SplitLines( msg )
   chat_type = chat_type:upper()

   local chunk_size = Me.chunk_size_overrides[chat_type]
                      or Me.default_chunk_sizes[chat_type]
                      or Me.chunk_size_overrides.OTHER
                      or Me.default_chunk_sizes.OTHER

   -- Reroute CHANNEL messages linked to community streams.
   if chat_type == "CHANNEL" then
      local _, channel_name,_, is_club = GetChannelName( target )
      if channel_name and is_club then
         local club_id, stream_id = channel_name:match( "Community:(%d+):(%d+)" )
         chat_type  = "CLUB"
         arg3       = tonumber(club_id)
         target     = tonumber(stream_id)
         chunk_size = Me.chunk_size_overrides.CLUB
                      or Me.default_chunk_sizes.CLUB
                      or Me.chunk_size_overrides.OTHER
                      or Me.default_chunk_sizes.OTHER
      end
   end

   for _, line in ipairs( msg ) do
      local chunks = Me.SplitMessage( line, chunk_size )
      for i = 1, #chunks do
         Me.QueueChat( chunks[i], chat_type, arg3, target )
      end
   end

   Me.ResetState()
end

-------------------------------------------------------------------------------
-- Split a message into chunks of chunk_size, preserving chat links and words.
function Me.SplitMessage( text, chunk_size, splitmark_start, splitmark_end )
   chunk_size      = chunk_size or Me.default_chunk_sizes.OTHER
   splitmark_start = splitmark_start or Me.splitmark_start_temp
                                                   or Me.splitmark_start or ""
   splitmark_end   = splitmark_end or Me.splitmark_end_temp
                                                     or Me.splitmark_end or ""

   if Me.debug_mode then
      Me.DebugLog( "SplitMessage called: text_len=", text:len(),
                   "chunk_size=", chunk_size )
      if text:find("|H") then
         Me.DebugLog( "Text contains item link!" )
         Me.DebugLog( "Raw text: " .. text:gsub("|", "||") )
      end
   end

   -- Replace chat links with fixed-width placeholders so splitting respects
   -- visible length rather than raw byte length (links can be very long).
   local replaced_links = {}
   for index, pattern in ipairs( Me.chat_replacement_patterns ) do
      text = text:gsub( pattern, function( link, textpart )
         if Me.debug_mode then
            Me.DebugLog( "Link matched: len=", link:len(),
                         "textpart_len=", textpart:len() )
            Me.DebugLog( "Link: " .. link:gsub("|", "||") )
         end
         replaced_links[index] = replaced_links[index] or {}
         table.insert( replaced_links[index], link )
         return "\001\002" .. index
                .. ("\002"):rep( textpart:len() - 4 ) .. "\003"
      end)
   end

   if splitmark_start ~= "" then splitmark_start = splitmark_start .. " " end
   if splitmark_end   ~= "" then splitmark_end   = " " .. splitmark_end   end

   local chunks = {}
   while( text:len() > chunk_size ) do
      for i = chunk_size+1 - splitmark_end:len(), 1, -1 do
         local ch = string.byte( text, i )
         if ch == 32 or ch == 1 then
            local offset = 0
            if ch == 32 then offset = 1 end
            table.insert( chunks, text:sub( 1, i-1 ) .. splitmark_end )
            text = splitmark_start .. text:sub( i+offset )
            break
         end
         if i <= 16 then
            for i = chunk_size+1 - splitmark_end:len(), 1, -1 do
               local ch = text:byte(i)
               if (ch >= 32 and ch < 128) or (ch >= 192) then
                  table.insert( chunks, text:sub( 1, i-1 ) .. splitmark_end )
                  text = splitmark_start .. text:sub( i )
                  break
               end
               if i <= 128 then return {""} end
            end
            break
         end
      end
   end

   table.insert( chunks, text )

   local counters = {1,1,1, 1,1,1, 1,1,1}
   for i = 1, #chunks do
      chunks[i] = chunks[i]:gsub("\001\002(%d)\002*\003", function(index)
         index = index:byte(1) - 48
         local text = replaced_links[index][counters[index]]
         counters[index] = counters[index] + 1
         return text or ""
      end)
   end

   return chunks
end

-------------------------------------------------------------------------------
-- Queue a single message chunk for sending.
local function ChatQueueInsert( entry )
   local insert_index = #Me.chat_queue + 1
   for k, v in ipairs( Me.chat_queue ) do
      if v.prio > entry.prio then insert_index = k; break end
   end
   table.insert( Me.chat_queue, insert_index, entry )
end

function Me.QueueChat( msg, type, arg3, target )
   type = type:upper()

   -- During editbox pre-send interception, the first chunk is captured here
   -- and delivered by setting the editbox text instead of being queued.
   -- We also mark channels_busy so the queue waits for chunk[1] to be
   -- confirmed before dispatching chunk[2], preserving send order.
   if Me.capturing_first_chunk and Me.editbox_first_chunk == nil then
      Me.editbox_first_chunk    = msg
      Me.capturing_first_chunk  = false
      -- Only block the queue if the message splits into 2+ chunks.
      -- Single-chunk messages don't need ordering protection.
      if Me.editbox_needs_placeholder then
         local channel = QUEUED_TYPES[type]
         if channel and not Me.channels_busy[channel] then
            Me.channels_busy[channel] = {
               msg    = msg;
               type   = type;
               arg3   = arg3;
               target = target;
               id     = Me.message_id;
               prio   = 1;
               _editbox_placeholder = true;
            }
            Me.message_id = Me.message_id + 1
            if not Me.sending_active then
               Me.sending_active = true
               Me.FireEvent( "SEND_START" )
            end
            -- For channels 2/3 (GUILD/CLUB), the placeholder won't be
            -- released by the deferred timer it waits for a server echo.
            -- Set a timeout so the queue doesn't stall forever if the echo
            -- never arrives.
            if channel >= 2 then
               Me.Timer_Start( "enscriber_placeholder_"..channel, "push",
                  Me.CHAT_TIMEOUT, function()
                     if Me.channels_busy[channel]
                        and Me.channels_busy[channel]._editbox_placeholder then
                        Me.DebugLog( "Placeholder timeout, channel=", channel )
                        Me.channels_busy[channel] = nil
                        Me.ChatQueueNext()
                     end
                  end)
            end
         end
      end
      return
   end

   local msg_pack = {
      msg    = msg;
      type   = type;
      arg3   = arg3;
      target = target;
      id     = Me.message_id;
      prio   = 1;
   }
   Me.message_id = Me.message_id + 1

   local queue_index = QUEUED_TYPES[type]

   if queue_index then
      if msg == "" then return end
      if msg:find( "卍" ) or msg:find( "卐" ) then return end
      if UnitIsDeadOrGhost( "player" ) and (type == "SAY"
                                        or type == "EMOTE"
                                        or type == "YELL") then
         UIErrorsFrame:AddMessage( ERR_CHAT_WHILE_DEAD, 1.0, 0.1, 0.1, 1.0 )
         return
      end
      ChatQueueInsert( msg_pack )
      Me.ChatQueueNext()
   else
      -- Non-queued types (PARTY, RAID, WHISPER etc.) go straight to the
      -- throttler without waiting for a server confirmation echo.
      -- During editbox capture, chunk[1] hasn't been staged yet. Defer
      -- subsequent chunks so the throttler doesn't send them before chunk[1].
      if Me.capturing_first_chunk == false and Me.editbox_first_chunk ~= nil then
         Me.DebugLog( "Deferring non-queued chunk, type=", type )
         Me.editbox_deferred_commits = Me.editbox_deferred_commits or {}
         table.insert( Me.editbox_deferred_commits, msg_pack )
      else
         Me.DebugLog( "CommitChat non-queued chunk, type=", type,
                      "capturing=", tostring(Me.capturing_first_chunk),
                      "first_chunk=", tostring(Me.editbox_first_chunk ~= nil) )
         Me.CommitChat( msg_pack )
      end
   end
end

function Me.AnyChannelsBusy()
   for i = 1, Me.NUM_CHANNELS do
      if Me.channels_busy[i] then return true end
   end
end

function Me.SendingActive()
   return Me.sending_active
end

-------------------------------------------------------------------------------
-- Queue dispatcher. Sends queued messages when their channel is free.
function Me.ChatQueueNext()
   if #Me.chat_queue == 0 then
      if not Me.AnyChannelsBusy() and Me.sending_active then
         Me.FireEvent( "SEND_DONE" )
         Me.failures       = 0
         Me.sending_active = false
      end
      return
   end

   if not Me.sending_active then
      Me.sending_active = true
      Me.FireEvent( "SEND_START" )
   end

   local all_busy = true
   local i = 1
   while i <= #Me.chat_queue do
      local q = Me.chat_queue[i]
      local channel = QUEUED_TYPES[q.type]
      if not Me.channels_busy[channel] then
         Me.channels_busy[channel]  = q
         Me.inside_chat_queue       = true
         Me.CommitChat( q )
         Me.inside_chat_queue       = false
         -- Check if all channels are now occupied.
         all_busy = true
         for c = 1, Me.NUM_CHANNELS do
            if not Me.channels_busy[c] then all_busy = false; break end
         end
         if all_busy then break end
      end
      i = i + 1
   end

   if not Me.AnyChannelsBusy() and Me.sending_active then
      Me.FireEvent( "SEND_DONE" )
      Me.failures       = 0
      Me.sending_active = false
   end
end

-------------------------------------------------------------------------------
function Me.OnChatSent( msg )
   local channel = QUEUED_TYPES[ msg.type ]
   if not channel then return end
   if msg._editbox_placeholder then return end

   Me.Timer_Start( "enscriber_channel_"..channel, "push",
                          Me.CHAT_TIMEOUT, Me.ChatDeath, channel )

   -- If channels_busy was already cleared before we got here (e.g. an echo
   -- from a prior chunk confirmed this one prematurely), cancel immediately.
   if not Me.channels_busy[channel] then
      Me.Timer_Cancel( "enscriber_channel_"..channel )
      return
   end

   if channel == 1 then
      local delay = math.min( Me.GetLatency() * 2 + 0.5, 3.0 )
      Me.Timer_Start( "enscriber_autoconfirm_"..channel, "push",
                      delay, function()
         if Me.channels_busy[channel] then
            Me.RemoveFromTable( Me.chat_queue, Me.channels_busy[channel] )
            Me.ChatConfirmed( channel )
         end
      end)
   end
end

function Me.ChatDeath( channel )
   Me.FireEvent( "SEND_DEATH", Me.chat_queue )
   if Me.debug_mode then
      Me.DebugLog( "Chat death! channel=", channel )
      print( "  Channels busy:", not not Me.channels_busy[1],
                                not not Me.channels_busy[2] )
      print( "  Copying chat queue to ENSCRIBER_DUMP_CHATQUEUE." )
      ENSCRIBER_DUMP_CHATQUEUE = {}
      for _, v in ipairs( Me.chat_queue ) do
         table.insert( ENSCRIBER_DUMP_CHATQUEUE, v )
      end
   end
   wipe( Me.chat_queue )
   Me.sending_active = false
   for i = 1, Me.NUM_CHANNELS do
      Me.channels_busy[i] = nil
      Me.Timer_Cancel( "enscriber_autoconfirm_"..i )
      Me.Timer_Cancel( "enscriber_placeholder_"..i )
   end
end

function Me.ChatConfirmed( channel, skip_event )
   Me.StopLatencyRecording()
   Me.channel_failures[channel] = nil
   if not skip_event then
      Me.FireEvent( "SEND_CONFIRMED", Me.channels_busy[channel] )
   end
   Me.channels_busy[channel] = nil
   Me.Timer_Cancel( "enscriber_channel_"..channel     )
   Me.Timer_Cancel( "enscriber_autoconfirm_"..channel )
   Me.Timer_Cancel( "enscriber_placeholder_"..channel )
   if not Me.inside_chat_queue then
      Me.ChatQueueNext()
   end
end

function Me.ChatFailed( channel )
   Me.channel_failures[channel] = (Me.channel_failures[channel] or 0) + 1
   if Me.channel_failures[channel] >= Me.FAILURE_LIMIT then
      Me.ChatDeath( channel )
      return
   end
   Me.FireEvent( "SEND_FAIL", Me.channels_busy[channel] )
   local wait_time
   if channel == 2 then
      wait_time = Me.CHAT_THROTTLE_WAIT
   else
      wait_time = math.min( 10, math.max( 1.5 + Me.GetLatency(),
                                          Me.CHAT_THROTTLE_WAIT ))
   end
   Me.Timer_Start( "enscriber_channel_"..channel, "push", wait_time,
                                                 Me.ChatFailedRetry, channel )
end

function Me.ChatFailedRetry( channel )
   Me.FireEvent( "SEND_RECOVER", Me.channels_busy[channel] )
   Me.channels_busy[channel] = nil
   Me.ChatQueueNext()
end

local function RemoveFromTable( target, value )
   for k, v in ipairs( target ) do
      if v == value then table.remove( target, k ); return end
   end
end
Me.RemoveFromTable = RemoveFromTable

-- 12.0: CHAT_MSG_SAY/EMOTE/YELL sender values arrive tainted and cannot be
-- compared against secure strings. We confirm on type match alone; the
-- auto-confirm timer handles cases where the echo never arrives.
function Me.TryConfirm( kind )
   local channel = QUEUED_TYPES[kind]
   if not channel then return end
   if Me.channels_busy[channel] and kind == Me.channels_busy[channel].type then
      RemoveFromTable( Me.chat_queue, Me.channels_busy[channel] )
      Me.ChatConfirmed( channel )
   end
end

-------------------------------------------------------------------------------
-- Latency tracking
function Me.StartLatencyRecording()
   Me.latency_recording = GetTime()
end

function Me.StopLatencyRecording()
   if not Me.latency_recording then return end
   local time = GetTime() - Me.latency_recording
   if time <= 0.001 then Me.latency_recording = nil; return end
   time = math.min( time, 10 )
   if time > Me.latency then
      Me.latency = time
   else
      Me.latency = Me.latency * 0.80 + time * 0.20
   end
   Me.latency_recording = nil
end

function Me.GetLatency()
   local _, _, latency_home = GetNetStats()
   local latency = math.max( Me.latency, latency_home/1000 )
   return math.min( latency, 10.0 )
end

-------------------------------------------------------------------------------
-- Channel 2/3 confirmation handlers (GUILD/OFFICER/CLUB/CLUBEDIT/CLUBDELETE)
function Me.OnChatMsgSystem( event, message, sender )
   if not Me.channels_busy[1] then return end
   if message == ERR_CHAT_THROTTLED and sender == "" then
      Me.StopLatencyRecording()
      Me.ChatFailed( 1 )
   end
end

function Me.OnChatMsgBnOffline( event, ... )
   local c = Me.channels_busy[1]
   if not c then return end
   local senderID = select( 13, ... )
   if c.type == "BNET" and c.target == senderID then
      local i = 1
      while Me.chat_queue[i] do
         local c = Me.chat_queue[i]
         if c.type == "BNET" and c.target == senderID then
            table.remove( Me.chat_queue, i )
         else
            i = i + 1
         end
      end
      Me.ChatConfirmed( 1, true )
   end
end

function Me.OnChatMsgGuildOfficer( event, _,_,_,_,_,_,_,_,_,_,_, guid )
   local cq = Me.channels_busy[2]
   if cq and guid == Me.PLAYER_GUID then
      event = event:sub( 10 )
      if (cq.type == event) or (cq.type == "CLUB" and cq.arg3 == GetGuildClub()) then
         RemoveFromTable( Me.chat_queue, cq )
         Me.ChatConfirmed( 2 )
      end
   end
end

function Me.OnChatMsgCommunitiesChannel( event, _,_,_,_,_,_,_,_,_,_,_,
                                         guid, bn_sender_id )
   local cq = Me.channels_busy[2]
   if not cq then return end
   if (guid and guid == Me.PLAYER_GUID)
      or (bn_sender_id and bn_sender_id ~= 0 and BNIsSelf(bn_sender_id)) then
      RemoveFromTable( Me.chat_queue, cq )
      Me.ChatConfirmed( 2 )
   end
end

function Me.OnClubMessageAdded( event, club_id, stream_id, message_id )
   local cq = Me.channels_busy[2]
   if not cq then return end
   local message = C_Club.GetMessageInfo( club_id, stream_id, message_id )
   if cq.type == "CLUB" and cq.arg3 == club_id and cq.target == stream_id
                                                and message.author.isSelf then
      RemoveFromTable( Me.chat_queue, cq )
      Me.ChatConfirmed( 2 )
   end
end

function Me.OnClubMessageUpdated( event, club, stream, message_id )
   local c = Me.channels_busy[3]
   if not c then return end
   if club == c.arg3 and stream == c.target then
      local info = C_Club.GetMessageInfo( club, stream, message_id )
      if info.author.isSelf then
         RemoveFromTable( Me.chat_queue, Me.channels_busy[3] )
         Me.ChatConfirmed( 3 )
      end
   end
end

function Me.OnClubError( event, action, error, club_type )
   Me.DebugLog( "Club error.", action, error, club_type )
   if Me.channels_busy[2]
           and action == Enum.ClubActionType.ErrorClubActionCreateMessage then
      Me.ChatFailed( 2 )
      return
   end
   local c = Me.channels_busy[3]
   if not c then return end
   if (c.type == "CLUBEDIT"
           and action == Enum.ClubActionType.ErrorClubActionEditMessage)
      or (c.type == "CLUBDELETE"
           and action == Enum.ClubActionType.ErrorClubActionDestroyMessage) then
      Me.ChatFailed( 3 )
   end
end

-------------------------------------------------------------------------------
-- Hooks
-- SendChatMessage is NOT replaced here. It is intercepted via the editbox
-- ChatFrame.OnEditBoxPreSendText callback, which runs inside the secure
-- hardware-event chain so it never taints C_ChatInfo.SendChatMessage.
-- BNSendWhisper and C_Club.SendMessage are still replaced because they don't
-- share the same taint restrictions.
Me.hooks = Me.hooks or {}

-- Returns true when a chat messaging lockdown is active (boss, M+, PvP).
-- Enscriber steps aside entirely during lockdown.
function Me.IsLocked()
   if InCombatLockdown() then return true end
   if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
      if C_ChatInfo.InChatMessagingLockdown() then return true end
   end
   return false
end

-- Pre-send editbox callback. Intercepts before Blizzard calls SendText,
-- replaces editbox text with chunk[1], queues remaining chunks.
Me.editbox_hooked = Me.editbox_hooked or false
if not Me.editbox_hooked then
   Me.editbox_hooked = true
   EventRegistry:RegisterCallback(
      "ChatFrame.OnEditBoxPreSendText",
      function( _, editBox )
         if Me.IsLocked() then return end

         local msg = editBox:GetText()
         if not msg or msg == "" then return end

         local chat_type = ChatFrameUtil.GetActiveChatType()
         chat_type = chat_type and chat_type:upper() or "SAY"

         local chunk_size = Me.chunk_size_overrides[chat_type]
                            or Me.default_chunk_sizes[chat_type]
                            or Me.chunk_size_overrides.OTHER
                            or Me.default_chunk_sizes.OTHER

         local needs_split = msg:len() > chunk_size
                             or msg:find( "\n" ) or msg:find( "\\n" )

         local language = editBox.languageID
         local target   = editBox:GetTellTarget() or editBox:GetChannelTarget()
         if target == 0 then target = nil end

         Me.editbox_first_chunk       = nil
         Me.capturing_first_chunk     = true
         Me.editbox_needs_placeholder = needs_split
         Me.inside_hook               = "CHAT"
         Me.AddChat( msg, chat_type, language, target )
         Me.inside_hook               = nil
         Me.capturing_first_chunk     = false
         Me.editbox_needs_placeholder = false

         -- Set chunk[1] into the editbox FIRST, before releasing the
         -- placeholder. Blizzard's SendText will fire immediately after this
         -- hook returns, sending chunk[1]. Only then do we release the
         -- placeholder and allow chunk[2+] to be dispatched, so the server
         -- always receives them in order.
         if Me.editbox_first_chunk then
            editBox:SetText( Me.editbox_first_chunk )
            Me.editbox_first_chunk = nil
         end

         -- Defer all chunk[2+] dispatch to the next frame. By then
         -- Blizzard's SendText will have fired and sent chunk[1],
         -- guaranteeing server order.
         local channel = QUEUED_TYPES[chat_type]
         local deferred = Me.editbox_deferred_commits
         Me.editbox_deferred_commits = nil

         C_Timer.After( 0, function()
            -- Release placeholder for channel 1 (SAY/EMOTE/YELL/BNET).
            -- These have an autoconfirm timer as a fallback, so releasing
            -- the placeholder here is safe — the queue still waits for
            -- confirmation before advancing.
            --
            -- For channels 2/3 (GUILD/OFFICER/CLUB), do NOT release here.
            -- Those channels confirm via server echo events (CHAT_MSG_GUILD,
            -- CLUB_MESSAGE_ADDED, etc.). Releasing early would dispatch
            -- chunk[2] before the server confirms chunk[1], causing the
            -- Club API to deliver them out of order.
            if channel and channel == 1
                       and Me.channels_busy[channel]
                       and Me.channels_busy[channel]._editbox_placeholder then
               Me.channels_busy[channel] = nil
               Me.ChatQueueNext()
            end

            -- Flush deferred commits for non-queued types
            -- (PARTY/RAID/WHISPER etc.)
            if deferred then
               Me.DebugLog( "Flushing deferred commits: count=", #deferred )
               for _, pack in ipairs( deferred ) do
                  Me.CommitChat( pack )
               end
            end
         end)
      end
   )
end

if not Me.hooks.BNSendWhisper then
   Me.hooks.BNSendWhisper = BNSendWhisper
   function BNSendWhisper( ... )
      return Me.BNSendWhisperHook( ... )
   end
end

if not Me.hooks.ChatFrame_OpenChat then
   Me.hooks.ChatFrame_OpenChat = true
   hooksecurefunc(ChatFrameUtil, "OpenChat", function( ... )
      Me.OnOpenChat( ... )
   end)
end

if C_Club then
   if not Me.hooks.ClubSendMessage then
      Me.hooks.ClubSendMessage = C_Club.SendMessage
      C_Club.SendMessage = function( ... )
         return Me.ClubSendMessageHook( ... )
      end
   end
end

-------------------------------------------------------------------------------
-- Timer API
-------------------------------------------------------------------------------
Me.timers = {}
Me.last_triggered = {}

function Me.Timer_Start( slot, mode, period, func, ... )
   if mode == "cooldown" and not Me.timers[slot] then
      local time_to_next = (Me.last_triggered[slot] or (-period))
                           + period - GetTime()
      if time_to_next <= 0 then
         Me.last_triggered[slot] = GetTime()
         func()
         return
      end
      mode   = "ignore"
      period = time_to_next
   end
   if Me.timers[slot] then
      if mode == "push" then
         Me.timers[slot].cancel = true
      elseif mode == "duplicate" then
         -- intentionally left empty
      else
         return
      end
   end
   local this_timer = { cancel = false }
   local args = {...}
   Me.timers[slot] = this_timer
   C_Timer.After( period, function()
      if this_timer.cancel then return end
      Me.timers[slot] = nil
      Me.last_triggered[slot] = GetTime()
      func( unpack( args ))
   end)
end

function Me.Timer_Cancel( slot )
   if Me.timers[slot] then
      Me.timers[slot].cancel = true
      Me.timers[slot] = nil
   end
end

function Me.DebugLog( ... )
   if not Me.debug_mode then return end
   print( "[Enscriber-Debug]", ... )
end
