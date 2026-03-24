-------------------------------------------------------------------------------
-- Emote Splitter -- Undo / Emote Protection
-------------------------------------------------------------------------------
local _, Me = ...

local HISTORY_SIZE = 20

local This = {
	hooked    = false;
	last_text = {};
	last_pos  = {};
}

Me.EmoteProtection = This

local function GetEditBox( index )
	return _G["ChatFrame" .. index .. "EditBox"]
end

function This.Init()
	This.db = Me.db.char.undo_history
	for i = 1, NUM_CHAT_WINDOWS do
		if not This.db[i] then
			This.db[i] = {
				position = 1;
				history  = { { text=""; cursor=0; } };
			}
		end
	end
	This.OptionsChanged()
end

local function LoadUndo( index )
	local data    = This.db[index]
	local editbox = GetEditBox( index )
	editbox:SetText( data.history[data.position].text )
	editbox:SetCursorPosition( data.history[data.position].cursor )
end

function This.Undo( index )
	local data = This.db[index]
	if data.position == 1 then return end
	This.AddUndoHistory( index, true )
	if data.position == 1 then return end
	data.position = data.position - 1
	LoadUndo( index )
end

function This.Redo( index )
	local data = This.db[index]
	if data.position == #data.history then return end
	This.AddUndoHistory( index, true )
	if data.position == #data.history then return end
	data.position = data.position + 1
	LoadUndo( index )
end

-- Add a history entry. force=true always adds; false only adds when the text
-- has changed by 20+ chars, preventing an entry per keystroke.
function This.AddUndoHistory( index, force, custom_text, custom_pos )
	local data    = This.db[index]
	local editbox = GetEditBox( index )
	local text    = custom_text or editbox:GetText()

	if text == data.history[data.position].text then return end

	if not force and
	     (math.abs(text:len() - data.history[data.position].text:len()) < 20
	      and text ~= "") then
		return
	end

	data.position = data.position + 1
	data.history[data.position] = {
		text   = text;
		cursor = custom_pos or editbox:GetCursorPosition();
	}

	for i = data.position+1, #data.history do
		data.history[i] = nil
	end

	while #data.history > HISTORY_SIZE do
		table.remove( data.history, 1 )
		data.position = data.position - 1
	end
end

-- Track editbox text changes for the undo buffer.
-- When text is empty (box closed), saves the last known text first so the
-- finished emote is preserved before the box clears it.
function This.MyTextChanged( index, text, position, force )
	if text == "" then
		if This.last_text[index] then
			This.AddUndoHistory( index, true,
			                     This.last_text[index], This.last_pos[index] )
		end
	end
	This.last_text[index] = text
	This.last_pos[index]  = position
	This.AddUndoHistory( index, force, text, position )
end

This.EditboxHooks = {
	OnTextChanged = function( self, index, user_input )
		if not user_input then return end
		local editbox = GetEditBox(index)
		This.MyTextChanged( index, editbox:GetText(),
		                    editbox:GetCursorPosition(), false )
	end;
	OnKeyDown = function( self, index, key )
		if IsControlKeyDown() then
			if key == "Z" then
				This.Undo( index )
			elseif key == "Y" then
				This.Redo( index )
			end
		end
	end;
	OnShow = function( self, index )
		This.MyTextChanged( index, "", 0, true )
	end;
	OnHide = function( self, index )
		This.MyTextChanged( index, "", 0, true )
	end;
}

function This.Hook()
	if This.hooked then return end
	This.hooked = true
	for i = 1, NUM_CHAT_WINDOWS do
		for script, handler in pairs( This.EditboxHooks ) do
			_G["ChatFrame" .. i .. "EditBox"]:HookScript( script,
				function( editbox, ... )
					if not Me.db.global.emoteprotection then return end
					handler( editbox, i, ... )
				end)
		end
	end
end

function This.OptionsChanged()
	if Me.db.global.emoteprotection then
		This.Hook()
	end
end
