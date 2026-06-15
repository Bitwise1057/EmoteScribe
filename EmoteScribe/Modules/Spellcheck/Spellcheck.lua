-------------------------------------------------------------------------------
-- EmoteScribe -- Spellcheck Module
-- by VfX / Bitwise1057
--
-- Provides live spellchecking of chat editbox text. Misspelled words are
-- highlighted with native WoW color escape sequences so the chat editbox keeps
-- its own insertion cursor. Highlight tags are stripped before sending and
-- before Enscriber splits outgoing messages.
--
-- Dictionary engine written independently; dictionary data (Dic_enUS.lua)
-- is based on Kevin Atkinson's wordlist (LGPL) with affix data derived from
-- Geoff Kuenning's Ispell (BSD), as documented in that file's header.
--
-- Phonetic suggestion engine implements the Metaphone algorithm
-- (Lawrence Philips, 1990 — public domain).
-------------------------------------------------------------------------------
local _, Me = ...

Me.Spellcheck = Me.Spellcheck or {}
local SC = Me.Spellcheck

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------
SC.baseWords        = {}
SC.phoneticIndex    = {}
SC.tryChars         = "esianrtolcdugmphbyfvkwz'"
SC.wordCache        = {}
SC.wordCacheCount   = 0
SC.WORD_CACHE_MAX   = 5000
SC.hookedEditboxes  = {}       -- editbox → true
SC.wordLocations    = {}       -- editbox name → { word, startPos, endPos }
SC.enabled          = false
SC.dictionaryLoaded = false
SC.liveEditboxHooks = true
SC.skipTextChanged  = false
SC.highlightPrefixes = {}
SC.suspendedEditboxes = {}
SC.oldLineLengths = {}
SC.underlineColor   = "00a9ec"
SC.ignoreCaps       = true
SC.ignoreNumbers    = true
SC.whitelist        = {}       -- lowercase-keyed hash; account-wide custom words

SC.MAX_UNDERLINES   = 12
SC.MAX_SUGGESTIONS  = 5

-------------------------------------------------------------------------------
-- Metaphone phonetic encoder
-- Implements the original Metaphone algorithm (Lawrence Philips, 1990).
-- Written independently from the public-domain algorithm specification.
-------------------------------------------------------------------------------
local function IsVowel(c)
    return c=="A" or c=="E" or c=="I" or c=="O" or c=="U"
end

function SC.Metaphone(word)
    if not word or #word == 0 then return "" end

    word = word:upper()
    local len  = #word
    local code = {}
    local i    = 1

    local two = word:sub(1, 2)
    if two=="AE" or two=="GN" or two=="KN" or two=="PN" or two=="WR" then
        i = 2
    end

    if i <= len and IsVowel(word:sub(i,i)) then
        table.insert(code, "E")
        i = i + 1
    end

    local function ch(p)   return word:sub(p, p)   end
    local function ch2(p)  return word:sub(p, p+1)  end
    local function ch3(p)  return word:sub(p, p+2)  end
    local function prev(p) return p > 1 and word:sub(p-1, p-1) or "" end

    while i <= len do
        local c    = ch(i)
        local skip = false

        if c ~= "C" and c == prev(i) then
            skip = true
        elseif IsVowel(c) then
            skip = true
        elseif c == "B" then
            if not (i == len and prev(i) == "M") then
                table.insert(code, "B")
            end
        elseif c == "C" then
            if ch2(i)=="CI" or ch2(i)=="CE" or ch2(i)=="CY" then
                table.insert(code, "S")
                if ch2(i)=="CI" then i = i+1 end
            elseif ch2(i)=="CH" then
                table.insert(code, "X"); i = i+1
            elseif ch2(i)=="CK" then
                table.insert(code, "K"); i = i+1
            else
                table.insert(code, "K")
            end
        elseif c == "D" then
            if ch2(i)=="DG" and (ch(i+2)=="E" or ch(i+2)=="I" or ch(i+2)=="Y") then
                table.insert(code, "J"); i = i+2
            else
                table.insert(code, "T")
            end
        elseif c == "F" then
            table.insert(code, "F")
        elseif c == "G" then
            local gskip = false
            if ch2(i)=="GH" then
                if i+2 > len or not IsVowel(ch(i+2)) then
                    gskip = true; i = i+1
                else
                    table.insert(code, "K"); i = i+1
                end
            elseif ch2(i)=="GN" then
                if i+1==len or (ch2(i+1)=="ED" and i+2==len) then gskip = true end
            elseif i > 1 and prev(i)=="G" then
                gskip = true
            end
            if not gskip then
                local n = ch(i+1)
                if n=="E" or n=="I" or n=="Y" then
                    table.insert(code, "J")
                else
                    table.insert(code, "K")
                end
            end
        elseif c == "H" then
            if IsVowel(ch(i+1)) and not IsVowel(prev(i)) then
                table.insert(code, "H")
            end
        elseif c == "J" then
            table.insert(code, "J")
        elseif c == "K" then
            if prev(i) ~= "C" then table.insert(code, "K") end
        elseif c == "L" then
            table.insert(code, "L")
        elseif c == "M" then
            table.insert(code, "M")
        elseif c == "N" then
            table.insert(code, "N")
        elseif c == "P" then
            if ch(i+1)=="H" then
                table.insert(code, "F"); i = i+1
            else
                table.insert(code, "P")
            end
        elseif c == "Q" then
            table.insert(code, "K")
        elseif c == "R" then
            table.insert(code, "R")
        elseif c == "S" then
            if ch2(i)=="SH" or ch3(i)=="SIO" or ch3(i)=="SIA" then
                table.insert(code, "X")
                if ch2(i)=="SH" then i = i+1 end
            elseif ch3(i)=="SCH" then
                table.insert(code, "SK"); i = i+2
            else
                table.insert(code, "S")
            end
        elseif c == "T" then
            if ch2(i)=="TH" then
                table.insert(code, "0"); i = i+1
            elseif ch3(i)=="TIA" or ch3(i)=="TIO" then
                table.insert(code, "X")
            else
                table.insert(code, "T")
            end
        elseif c == "V" then
            table.insert(code, "F")
        elseif c == "W" then
            if IsVowel(ch(i+1)) then table.insert(code, "W") end
        elseif c == "X" then
            table.insert(code, "KS")
        elseif c == "Y" then
            if IsVowel(ch(i+1)) then table.insert(code, "Y") end
        elseif c == "Z" then
            table.insert(code, "S")
        end

        i = i + 1
    end

    return table.concat(code)
end

-------------------------------------------------------------------------------
-- Edit distance (Levenshtein)
-------------------------------------------------------------------------------
function SC.EditDistance(a, b)
    local la, lb = #a, #b
    if la == 0 then return lb end
    if lb == 0 then return la end

    local prev, curr = {}, {}
    for j = 0, lb do prev[j] = j end

    for i = 1, la do
        curr[0] = i
        for j = 1, lb do
            local cost = (a:sub(i,i) == b:sub(j,j)) and 0 or 1
            curr[j] = math.min(curr[j-1]+1, prev[j]+1, prev[j-1]+cost)
        end
        prev, curr = curr, prev
    end

    return prev[lb]
end

-------------------------------------------------------------------------------
-- Dictionary loading
-------------------------------------------------------------------------------
function SC.LoadDictionary()
    if not WordDict_GetDictionary_enUS then return false end

    local dict = WordDict_GetDictionary_enUS()
    if not dict or not dict.Words then return false end

    if dict.Try and dict.Try[1] then
        SC.tryChars = dict.Try[1]
    end

    local words   = dict.Words
    local base    = SC.baseWords
    local phonIdx = SC.phoneticIndex
    local lower   = string.lower
    local find    = string.find
    local sub     = string.sub

    for i = 1, #words do
        local entry = words[i]
        local s1    = find(entry, "/", 1, true)
        local word  = s1 and sub(entry, 1, s1-1) or entry

        if word ~= "" then
            local lword = lower(word)
            base[lword] = true

            if s1 then
                local s2 = find(entry, "/", s1+1, true)
                if s2 then
                    local pcode = sub(entry, s2+1)
                    if pcode:sub(1,1) == "*" then pcode = pcode:sub(2) end
                    if pcode ~= "" then
                        if not phonIdx[pcode] then phonIdx[pcode] = {} end
                        table.insert(phonIdx[pcode], lword)
                    end
                end
            end
        end
    end

    WordDict_GetDictionary_enUS = nil
    collectgarbage("collect")
    return true
end

-------------------------------------------------------------------------------
-- Word lookup — cached, lowercase hash.
--
-- TryVariants handles two common false-positive cases:
--
--   1. Contractions / possessives — "it's", "what's", "dragon's", "they're":
--      Split on the apostrophe and accept if the pre-apostrophe stem is in
--      the dictionary.  Single-char stems (e.g. the lone "I" in "I'll") are
--      let through by the #word <= 1 guard in Contains, so we only need to
--      worry about len >= 2 stems.
--
--   2. Inflected forms — plurals ("cats"), past tense ("played"), progressive
--      ("running"), comparatives ("faster"), etc.: Strip the most common
--      English suffixes in specificity order and accept if any stripped form
--      is in the dictionary.  Minimal stemming only — we stop at the first
--      hit to avoid over-stripping (e.g. "ies→y" before "s").
-------------------------------------------------------------------------------
local SUFFIXES = {
    -- longer / more specific first
    { "iest",  ""  },   -- happiest → happy (via iest→y path below)
    { "iest",  "y" },
    { "ier",   "y" },
    { "ying",  "ie"},   -- dying → die (ying→ie)
    { "ying",  "y" },
    { "ying",  ""  },
    { "ping",  "p" },   -- stopping → stop
    { "ting",  "t" },   -- hitting → hit
    { "ning",  "n" },   -- running → run
    { "ring",  "r" },   -- starring → star
    { "ding",  "d" },
    { "king",  "k" },
    { "bing",  "b" },
    { "ming",  "m" },
    { "sing",  "s" },
    { "ging",  "g" },
    { "fing",  "f" },
    { "zing",  "z" },
    { "ling",  "l" },
    { "xing",  "x" },
    { "ing",   "e" },   -- taking → take
    { "ing",   ""  },   -- talking → talk
    { "pped",  "p" },   -- stopped → stop
    { "tted",  "t" },   -- batted → bat
    { "nned",  "n" },
    { "rred",  "r" },
    { "dded",  "d" },
    { "ied",   "y" },   -- carried → carry
    { "ied",   ""  },
    { "ed",    "e" },   -- liked → like
    { "ed",    ""  },   -- walked → walk
    { "ies",   "y" },   -- flies → fly
    { "ves",   "f" },   -- wolves → wolf
    { "ves",   "fe"},   -- knives → knife
    { "ses",   "s" },   -- classes → class
    { "zes",   "z" },   -- fizzes → fizz
    { "xes",   "x" },   -- boxes → box
    { "hes",   "h" },   -- wishes → wish
    { "es",    "e" },   -- fades → fade
    { "es",    ""  },   -- boxes already handled, remaining -es
    { "s",     ""  },   -- cats → cat  (kept last — most ambiguous)
    { "er",    "e" },   -- nicer → nice
    { "er",    ""  },   -- faster → fast
    { "est",   "e" },
    { "est",   ""  },
    { "ly",    ""  },   -- quickly → quick
    { "ness",  ""  },   -- darkness → dark
    { "less",  ""  },   -- useless → use  (rough)
    { "ful",   ""  },   -- helpful → help
}

local function InBase(w)
    return #w >= 2 and (SC.baseWords[w] == true or SC.whitelist[w] == true)
end

-- Prefixes defined in Dic_enUS.lua: re-, in-, un-, de-, dis-, con-, pro-.
-- Stripped in longest-first order so "dis" is tried before "de".
local PREFIXES = { "dis", "con", "pro", "re", "in", "un", "de" }

local function StripSuffix(word)
    local len = #word
    for _, pair in ipairs(SUFFIXES) do
        local suf, repl = pair[1], pair[2]
        local slen = #suf
        if len > slen + 1 and word:sub(-slen) == suf then
            local stem = word:sub(1, len - slen) .. repl
            if InBase(stem) then return true end
        end
    end
    return false
end

local function TryVariants(lword)
    -- 1. Contraction / possessive split: accept on pre-apostrophe stem.
    local apos = lword:find("'", 1, true)
    if apos then
        local stem = lword:sub(1, apos - 1)
        if InBase(stem) then return true end
        -- bare possessive like "dragon's" — stem already checked above
        return false  -- don't stem contractions further; too noisy
    end

    -- 2. Suffix stripping.
    if StripSuffix(lword) then return true end

    -- 3. Prefix stripping — then base lookup, then suffix stripping on remainder.
    --    Covers: remind → mind, undo → do, disconnect → connect,
    --            reminded → mind (prefix strip → suffix strip), etc.
    for _, pfx in ipairs(PREFIXES) do
        local plen = #pfx
        if #lword > plen + 1 and lword:sub(1, plen) == pfx then
            local stem = lword:sub(plen + 1)
            if InBase(stem) then return true end
            -- prefix + suffix combined (e.g. reminded → re+mind+ed)
            if StripSuffix(stem) then return true end
        end
    end

    return false
end

function SC.Contains(word)
    if #word <= 1 then return true end

    local cached = SC.wordCache[word]
    if cached ~= nil then return cached end

    SC.wordCacheCount = SC.wordCacheCount + 1
    if SC.wordCacheCount > SC.WORD_CACHE_MAX then
        SC.wordCache = {}; SC.wordCacheCount = 1
    end

    local lword  = string.lower(word)
    local result = InBase(lword)
                   or TryVariants(lword)
    SC.wordCache[word] = result
    return result
end

-------------------------------------------------------------------------------
-- Whitelist (custom words)
-- Account-wide, user-maintained set of words that are never flagged. Stored in
-- EmoteScribeSaved.global.spellcheck_whitelist as a lowercase-keyed hash and
-- mirrored into SC.whitelist. Consulted through InBase, so affix variants
-- (plurals, possessives) of a whitelisted word are accepted automatically.
-- The suggestion engine is intentionally NOT whitelist-aware.
-------------------------------------------------------------------------------
local WHITELIST_WORD_PATTERN = "^[A-Za-z'%-]+$"

-- Returns a normalized (trimmed, lowercased) word, or nil + reason on failure.
function SC.NormalizeWhitelistWord(word)
    if type(word) ~= "string" then return nil, "empty" end
    word = word:gsub("^%s+", ""):gsub("%s+$", "")
    if word == "" then return nil, "empty" end
    if #word < 2 then return nil, "tooshort" end
    if not word:match(WHITELIST_WORD_PATTERN) then return nil, "badchars" end
    return word:lower()
end

local function ClearWordCache()
    SC.wordCache      = {}
    SC.wordCacheCount = 0
end

local function GetWhitelistStore()
    local db = EmoteScribeSaved and EmoteScribeSaved.global
    if not db then return nil end
    if type(db.spellcheck_whitelist) ~= "table" then
        db.spellcheck_whitelist = {}
    end
    return db.spellcheck_whitelist
end

-- Re-run spellcheck on any currently-visible hooked editbox so highlights
-- update immediately after a whitelist change. SpellCheckChat self-gates on
-- the enabled flag and on lockdown, so this is safe to call unconditionally.
function SC.RefreshOpenEditboxes()
    for editbox in pairs(SC.hookedEditboxes) do
        if editbox.IsVisible and editbox:IsVisible() then
            SC.SpellCheckChat(editbox)
        end
    end
end

function SC.AddWhitelistWord(word)
    local norm, reason = SC.NormalizeWhitelistWord(word)
    if not norm then return false, reason end

    local store = GetWhitelistStore()
    if not store then return false, "nodb" end
    if store[norm] then return false, "exists" end

    store[norm]  = true
    SC.whitelist = store
    ClearWordCache()
    SC.RefreshOpenEditboxes()
    return true
end

function SC.RemoveWhitelistWord(word)
    local norm = SC.NormalizeWhitelistWord(word)
    if not norm then return false, "invalid" end

    local store = GetWhitelistStore()
    if store then store[norm] = nil end
    SC.whitelist = store or SC.whitelist
    SC.whitelist[norm] = nil
    ClearWordCache()
    SC.RefreshOpenEditboxes()
    return true
end

function SC.GetWhitelistWords()
    -- Re-sync the in-memory mirror from the persisted store before reading, so
    -- the list is correct even when queried before ApplySettings has run — e.g.
    -- the options UI builds its initial list during load, ahead of ApplySettings.
    local store = GetWhitelistStore()
    if store then SC.whitelist = store end

    local list = {}
    for w in pairs(SC.whitelist) do list[#list + 1] = w end
    table.sort(list)
    return list
end

-------------------------------------------------------------------------------
-- Suggestion generator — multi-pass mutation engine.
-------------------------------------------------------------------------------
function SC.Suggest(word)
    local lword = string.lower(word)
    local len   = #lword
    local seen  = { [lword] = true }
    local pool  = {}
    local try   = SC.tryChars

    local function addWord(w)
        if seen[w] then return end
        seen[w] = true
        if SC.baseWords[w] then
            table.insert(pool, { word=w, dist=SC.EditDistance(lword, w) })
        end
    end

    -- Pass 1: Phonetic seed.
    local code = SC.Metaphone(lword)
    local function addPhonetic(pcode)
        local bucket = SC.phoneticIndex[pcode]
        if not bucket then return end
        for _, w in ipairs(bucket) do addWord(w) end
    end
    addPhonetic(code)
    if len > 1 then
        local rest = lword:sub(2)
        for _, v in ipairs({"a","e","i","o","u"}) do
            addPhonetic(SC.Metaphone(v .. rest))
        end
        addPhonetic(SC.Metaphone(rest))
    end

    -- Pass 2: SwapChar.
    if len > 1 then
        local chars = {}
        for i = 1, len do chars[i] = lword:sub(i,i) end
        for i = 1, len - 1 do
            chars[i], chars[i+1] = chars[i+1], chars[i]
            addWord(table.concat(chars))
            chars[i], chars[i+1] = chars[i+1], chars[i]
        end
    end

    -- Pass 3: ExtraChar.
    if len > 1 then
        for i = 1, len do
            addWord(lword:sub(1, i-1) .. lword:sub(i+1))
        end
    end

    -- Pass 4: ForgotChar.
    for i = 0, len do
        for j = 1, #try do
            addWord(lword:sub(1, i) .. try:sub(j,j) .. lword:sub(i+1))
        end
    end

    -- Pass 5: BadChar.
    local chars = {}
    for i = 1, len do chars[i] = lword:sub(i,i) end
    for i = 1, len do
        local orig = chars[i]
        for j = 1, #try do
            local c = try:sub(j,j)
            if c ~= orig then
                chars[i] = c
                addWord(table.concat(chars))
            end
        end
        chars[i] = orig
    end

    if #pool == 0 then return {} end

    table.sort(pool, function(a, b)
        if a.dist ~= b.dist then return a.dist < b.dist end
        return a.word < b.word
    end)

    local results = {}
    for i = 1, math.min(SC.MAX_SUGGESTIONS, #pool) do
        table.insert(results, pool[i].word)
    end
    return results
end

-------------------------------------------------------------------------------
-- WoW UI escape sequence masking
-- Used by CheckLine to skip over item links and other escape sequences when
-- scanning for word tokens. The editbox text is never modified.
-------------------------------------------------------------------------------
local PLACEHOLDER_CHAR = "\001"

local ESCAPE_PATTERNS = {
    "(|cn[^:]+:.-|r)",
    "(|cnIQ%d:.-|r)",
    "(|[Cc]%x+|H.-|h.-|h|r)",
    "(|H.-|h)",
    "(|T.-|t)",
    "(|A.-|a)",
    "({.-})",
    "(|n)",
}

local function MaskEscapes(text)
    local placeholders, index = {}, 0
    for _, patt in ipairs(ESCAPE_PATTERNS) do
        text = text:gsub(patt, function(match)
            index = index + 1
            local token = PLACEHOLDER_CHAR .. index .. PLACEHOLDER_CHAR
            local pad   = #match - #token
            if pad > 0 then token = token .. string.rep(" ", pad) end
            placeholders[index] = match
            return token
        end)
    end
    return text, placeholders
end

-------------------------------------------------------------------------------
-- Line scanning
-- Returns { word, startPos, endPos } for each misspelled word in text.
-- Positions are byte offsets into the raw editbox text.
-------------------------------------------------------------------------------
local WORD_PATTERN = "[A-Za-z'%-]+"

function SC.CheckLine(text)
    local results = {}
    if not text or #text < 2 then return results end

    local masked = MaskEscapes(text)
    if masked:sub(1,1) == "/" then return results end

    local find  = string.find
    local match = string.match
    local upper = string.upper
    local s, e  = find(masked, WORD_PATTERN)

    while s do
        local word = masked:sub(s, e)
        local skip = false

        if SC.ignoreCaps   and word == upper(word) then skip = true end
        if not skip and SC.ignoreNumbers and match(word, "%d") then skip = true end
        if not skip and not SC.Contains(word) then
            table.insert(results, { word=word, startPos=s, endPos=e })
        end

        s, e = find(masked, WORD_PATTERN, e+1)
    end

    return results
end

-------------------------------------------------------------------------------
-- Native color-highlight system
-------------------------------------------------------------------------------

local HIGHLIGHT_SUFFIX = "|r"
SC.highlightPrefixes["|cff00a9ec"] = true

local function HighlightPrefix()
    local hex = (SC.underlineColor or "00a9ec"):gsub("[^%x]", ""):sub(1, 6)
    if #hex ~= 6 then hex = "00a9ec" end
    local prefix = "|cff" .. hex
    SC.highlightPrefixes[prefix] = true
    return prefix
end

function SC.RemoveHighlighting(text, cursorPos)
    local newText = tostring(text or "")
    local cpos = cursorPos or 0

    for prefix in pairs(SC.highlightPrefixes) do
        local patt = prefix .. "([A-Za-z'%-]+)" .. HIGHLIGHT_SUFFIX
        local startPos, endPos, word = newText:find(patt)

        while startPos do
            local wordStart = startPos + #prefix
            local wordEnd   = endPos - #HIGHLIGHT_SUFFIX
            local before    = newText:sub(1, startPos - 1)
            local after     = newText:sub(endPos + 1)

            if cursorPos then
                if cpos >= endPos then
                    cpos = cpos - #prefix - #HIGHLIGHT_SUFFIX
                elseif cpos >= wordStart and cpos <= wordEnd then
                    cpos = cpos - #prefix
                elseif cpos >= startPos then
                    cpos = startPos - 1
                end
            end

            newText = before .. word .. after
            startPos, endPos, word = newText:find(patt)
        end

        -- If editing damaged the leading tag, remove the orphaned prefix.
        startPos, endPos = newText:find(prefix, 1, true)
        while startPos do
            if cursorPos and cpos >= startPos then
                cpos = math.max(startPos - 1, cpos - #prefix)
            end
            newText = newText:sub(1, startPos - 1) .. newText:sub(endPos + 1)
            startPos, endPos = newText:find(prefix, 1, true)
        end
    end

    return newText, cpos
end

local function SetEditboxText(editbox, text, cursorPos)
    SC.skipTextChanged = true
    editbox:SetText(text)
    if cursorPos then
        editbox:SetCursorPosition(math.max(0, cursorPos))
    end
    if editbox.GetName then
        SC.oldLineLengths[editbox:GetName()] = #(editbox:GetText() or "")
    end
end

local function CleanEditboxText(editbox)
    if not editbox or not editbox.GetText then return end

    local text = editbox:GetText() or ""
    local cursor = editbox.GetCursorPosition and editbox:GetCursorPosition() or nil
    local cleanText, cleanCursor = SC.RemoveHighlighting(text, cursor)

    if cleanText ~= text then
        SetEditboxText(editbox, cleanText, cleanCursor)
    end

    local ebName = editbox:GetName()
    if ebName then SC.wordLocations[ebName] = {} end
end

local function SuspendEditbox(editbox)
    if not editbox or not editbox.GetName then return end

    local ebName = editbox:GetName()
    SC.suspendedEditboxes[ebName] = true

    C_Timer.After(0, function()
        SC.suspendedEditboxes[ebName] = nil
    end)
end

-------------------------------------------------------------------------------
-- Spellcheck pass
-- Reads the editbox text, strips old highlight tags, and reapplies native
-- color tags around misspelled words.
-------------------------------------------------------------------------------
function SC.SpellCheckChat(editbox)
    if not SC.enabled then return end
    if LibEnscriber and LibEnscriber.Internal.IsLocked() then return end

    local ebName = editbox:GetName()
    local text   = editbox:GetText() or ""
    local cursor = editbox:GetCursorPosition() or 0
    local cleanText, cleanCursor = SC.RemoveHighlighting(text, cursor)

    SC.wordLocations[ebName] = {}

    if SC.suspendedEditboxes[ebName] then
        if cleanText ~= text then
            SetEditboxText(editbox, cleanText, cleanCursor)
        end
        return
    end

    if #cleanText < 2 then
        if cleanText ~= text then
            SetEditboxText(editbox, cleanText, cleanCursor)
        end
        return
    end

    if cleanText:sub(1, 1) == "/" then
        if cleanText ~= text then
            SetEditboxText(editbox, cleanText, cleanCursor)
        end
        return
    end

    local misspelled = SC.CheckLine(cleanText)

    if #misspelled == 0 then
        if cleanText ~= text then
            SetEditboxText(editbox, cleanText, cleanCursor)
        end
        return
    end

    local prefix = HighlightPrefix()
    local suffix = HIGHLIGHT_SUFFIX
    local newText = cleanText
    local newCursor = cleanCursor
    local highlighted = {}
    local count = 0

    for i = #misspelled, 1, -1 do
        if count >= SC.MAX_UNDERLINES then break end

        local w = misspelled[i]
        highlighted[i] = true
        count = count + 1

        newText = newText:sub(1, w.startPos - 1)
               .. prefix
               .. newText:sub(w.startPos, w.endPos)
               .. suffix
               .. newText:sub(w.endPos + 1)

        if newCursor >= w.endPos then
            newCursor = newCursor + #prefix + #suffix
        elseif newCursor >= w.startPos then
            newCursor = newCursor + #prefix
        end
    end

    local added = 0
    for i, w in ipairs(misspelled) do
        if highlighted[i] then
            table.insert(SC.wordLocations[ebName], {
                word       = w.word,
                startPos   = w.startPos + added + #prefix,
                endPos     = w.endPos + added + #prefix,
                cleanStart = w.startPos,
                cleanEnd   = w.endPos,
            })
            added = added + #prefix + #suffix
        end
    end

    if newText ~= text then
        SetEditboxText(editbox, newText, newCursor)
    end
end

-------------------------------------------------------------------------------
-- Explicit spellcheck report
-- Safe path: reads the active chat editbox only when requested and does not
-- hook, render inside, or mutate the Blizzard chat editbox.
-------------------------------------------------------------------------------
local function AddonPrint(msg)
    local line = "|cff00a9ec<EmoteScribe>|r " .. msg
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(line)
    else
        print(line)
    end
end

function SC.ReportActiveChat()
    if not SC.dictionaryLoaded then
        AddonPrint("Spellcheck dictionary is not loaded.")
        return
    end

    local editbox = ACTIVE_CHAT_EDIT_BOX or LAST_ACTIVE_CHAT_EDIT_BOX
    if not editbox or not editbox.GetText then
        AddonPrint("Open a chat editbox first.")
        return
    end

    local text = SC.RemoveHighlighting(editbox:GetText() or "")
    if text == "" then
        AddonPrint("No chat text to check.")
        return
    end

    local misspelled = SC.CheckLine(text)
    if #misspelled == 0 then
        AddonPrint("No misspellings found.")
        return
    end

    AddonPrint("Possible misspellings:")

    local seen = {}
    local shown = 0
    for _, entry in ipairs(misspelled) do
        local word = entry.word
        local key = string.lower(word)
        if not seen[key] then
            seen[key] = true
            shown = shown + 1

            local suggestions = SC.Suggest(word)
            local suffix = " -> (no suggestions)"
            if #suggestions > 0 then
                suffix = " -> " .. table.concat(suggestions, ", ")
            end

            AddonPrint("  " .. word .. suffix)

            if shown >= 8 then
                AddonPrint("  More misspellings omitted.")
                break
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Right-click suggestion dropdown
-------------------------------------------------------------------------------
local SC_DropDown = CreateFrame("Frame", "EmoteScribeSCDropDown", UIParent,
                                "UIDropDownMenuTemplate")

local SC_ActiveEditbox = nil
local SC_ActiveWord    = nil
local SC_ActiveStart   = nil
local SC_ActiveEnd     = nil

local function ApplySuggestion(suggestion, editbox, cleanStart, cleanEnd)
    local text = SC.RemoveHighlighting(editbox:GetText())

    -- Preserve capitalization of the original word's first letter.
    local orig = text:sub(cleanStart, cleanEnd)
    if orig:sub(1,1) == orig:sub(1,1):upper()
    and orig:sub(1,1) ~= orig:sub(1,1):lower() then
        suggestion = suggestion:sub(1,1):upper() .. suggestion:sub(2)
    end

    local newText = text:sub(1, cleanStart-1) .. suggestion .. text:sub(cleanEnd+1)
    local newCPos = cleanStart - 1 + #suggestion

    SetEditboxText(editbox, newText, newCPos)

    -- Re-run spellcheck next frame after the SetText OnTextChanged fires.
    C_Timer.After(0, function() SC.SpellCheckChat(editbox) end)
end

local function InitDropDown(self, level)
    if not SC_ActiveWord then return end

    local info = UIDropDownMenu_CreateInfo()
    info.text         = "Suggestions: " .. SC_ActiveWord
    info.isTitle      = true
    info.notCheckable = true
    UIDropDownMenu_AddButton(info, level)

    local suggestions = SC.Suggest(SC_ActiveWord)

    if #suggestions == 0 then
        info              = UIDropDownMenu_CreateInfo()
        info.text         = "(no suggestions)"
        info.disabled     = true
        info.notCheckable = true
        UIDropDownMenu_AddButton(info, level)
    else
        for _, sug in ipairs(suggestions) do
            local capSug = sug
            local eb     = SC_ActiveEditbox
            local cs     = SC_ActiveStart
            local ce     = SC_ActiveEnd
            info              = UIDropDownMenu_CreateInfo()
            info.text         = sug
            info.notCheckable = true
            info.func         = function() ApplySuggestion(capSug, eb, cs, ce) end
            UIDropDownMenu_AddButton(info, level)
        end
    end

    info              = UIDropDownMenu_CreateInfo()
    info.text         = ""
    info.notClickable = true
    info.notCheckable = true
    UIDropDownMenu_AddButton(info, level)

    info              = UIDropDownMenu_CreateInfo()
    info.text         = "Cancel"
    info.notCheckable = true
    info.func         = function() CloseDropDownMenus() end
    UIDropDownMenu_AddButton(info, level)
end

UIDropDownMenu_Initialize(SC_DropDown, InitDropDown, "MENU")

-------------------------------------------------------------------------------
-- EditBox event handlers
-------------------------------------------------------------------------------
local WORD_TERMINATOR_PATTERN = "[ %(%);,%.!%?:\"]"

local function OnTextChanged(editbox)
    local ebName = editbox:GetName()

    if SC.skipTextChanged then
        SC.skipTextChanged = false
        return
    end

    local text = editbox:GetText() or ""
    local pos = editbox:GetCursorPosition() or 0
    local oldLength = SC.oldLineLengths[ebName] or 0
    local newLength = #text

    if newLength == 0 then
        SC.wordCache      = {}
        SC.wordCacheCount = 0
        SC.wordLocations[ebName] = {}
        SC.oldLineLengths[ebName] = 0
        return
    end

    if text:sub(1, 1) == "/" then
        CleanEditboxText(editbox)
        SC.oldLineLengths[ebName] = #(editbox:GetText() or "")
        return
    end

    if pos == newLength and newLength - 1 == oldLength then
        local lastChar = text:sub(-1)
        if lastChar:match(WORD_TERMINATOR_PATTERN) then
            SC.SpellCheckChat(editbox)
        end
    elseif pos ~= newLength then
        SC.SpellCheckChat(editbox)
    end

    SC.oldLineLengths[ebName] = #(editbox:GetText() or "")
end

local function OnEnterPressed(editbox)
    CleanEditboxText(editbox)
    SC.oldLineLengths[editbox:GetName()] = #(editbox:GetText() or "")
end

local function OnEscapePressed(editbox)
    CleanEditboxText(editbox)
    SC.oldLineLengths[editbox:GetName()] = #(editbox:GetText() or "")
end

local function OnMouseUp(editbox, button)
    if button ~= "RightButton" then return end
    if not SC.enabled then return end

    local locs = SC.wordLocations[editbox:GetName()]
    if not locs or #locs == 0 then return end

    local pos = editbox:GetCursorPosition()

    for _, w in ipairs(locs) do
        if pos >= w.startPos and pos <= w.endPos then
            CloseDropDownMenus()
            SC_ActiveEditbox = editbox
            SC_ActiveWord    = w.word
            SC_ActiveStart   = w.cleanStart
            SC_ActiveEnd     = w.cleanEnd
            ToggleDropDownMenu(1, nil, SC_DropDown, "cursor", 0, 0)
            return
        end
    end
end

-------------------------------------------------------------------------------
-- Hook and editbox setup
-------------------------------------------------------------------------------
local function HookEditbox(editbox)
    if SC.hookedEditboxes[editbox] then return end
    SC.hookedEditboxes[editbox] = true

    local ebName = editbox:GetName()
    SC.wordLocations[ebName] = {}
    SC.oldLineLengths[ebName] = #(editbox:GetText() or "")

    editbox:HookScript("OnShow", function()
        SC.oldLineLengths[ebName] = #(editbox:GetText() or "")
    end)
    editbox:HookScript("OnEditFocusGained", function()
        SC.oldLineLengths[ebName] = #(editbox:GetText() or "")
    end)
    editbox:HookScript("OnHide", function()
        CleanEditboxText(editbox)
        SC.oldLineLengths[ebName] = #(editbox:GetText() or "")
    end)
    editbox:HookScript("OnEditFocusLost", function()
        CleanEditboxText(editbox)
        SC.oldLineLengths[ebName] = #(editbox:GetText() or "")
    end)

    editbox:HookScript("OnTextChanged",   OnTextChanged)
    editbox:HookScript("OnEnterPressed",  OnEnterPressed)
    editbox:HookScript("OnEscapePressed", OnEscapePressed)
    editbox:HookScript("OnMouseUp",       OnMouseUp)
end

local function WireEditboxes()
    local n = _G.NUM_CHAT_WINDOWS or 10
    for i = 1, n do
        local eb = _G["ChatFrame" .. i .. "EditBox"]
        if eb then HookEditbox(eb) end
    end
end

-------------------------------------------------------------------------------
-- Settings application
-------------------------------------------------------------------------------
function SC.ApplySettings()
    local db = EmoteScribeSaved and EmoteScribeSaved.global

    local wasEnabled = SC.enabled

    SC.enabled       = db and db.spellcheck_enabled        or false
    SC.underlineColor = (db and db.spellcheck_color)       or "00a9ec"
    HighlightPrefix()
    SC.ignoreCaps    = db and db.spellcheck_ignore_caps    ~= false
    SC.ignoreNumbers = db and db.spellcheck_ignore_numbers ~= false
    SC.whitelist     = GetWhitelistStore() or {}

    SC.wordCache      = {}
    SC.wordCacheCount = 0

    if wasEnabled and not SC.enabled then
        for editbox in pairs(SC.hookedEditboxes) do
            CleanEditboxText(editbox)
        end
        for ebName, _ in pairs(SC.wordLocations) do
            SC.wordLocations[ebName] = {}
        end
    end
end

local function WrapEnscriber()
    if SC.enscriberWrapped then return end
    if not LibEnscriber or not LibEnscriber.Internal then return end
    if not LibEnscriber.Internal.AddChat then return end

    local original_AddChat = LibEnscriber.Internal.AddChat
    LibEnscriber.Internal.AddChat = function(msg, chatType, ...)
        msg = SC.RemoveHighlighting(tostring(msg or ""))
        return original_AddChat(msg, chatType, ...)
    end

    SC.enscriberWrapped = true
end

local function WrapEmoteProtection()
    if SC.emoteProtectionWrapped then return end
    local ep = Me.EmoteProtection
    if not ep then return end

    local function GetEditBox(index)
        return _G["ChatFrame" .. index .. "EditBox"]
    end

    if ep.db then
        for _, data in pairs(ep.db) do
            if data.history then
                for _, entry in ipairs(data.history) do
                    entry.text, entry.cursor =
                        SC.RemoveHighlighting(entry.text, entry.cursor)
                end
            end
        end
    end

    local original_AddUndoHistory = ep.AddUndoHistory
    if original_AddUndoHistory then
        ep.AddUndoHistory = function(index, force, customText, customPos)
            local text, pos = customText, customPos

            if text == nil then
                local editbox = GetEditBox(index)
                if editbox then
                    text = editbox:GetText()
                    pos = editbox:GetCursorPosition()
                end
            end

            if text ~= nil then
                text, pos = SC.RemoveHighlighting(text, pos)
                return original_AddUndoHistory(index, force, text, pos)
            end

            return original_AddUndoHistory(index, force, customText, customPos)
        end
    end

    local original_MyTextChanged = ep.MyTextChanged
    if original_MyTextChanged then
        ep.MyTextChanged = function(index, text, position, force)
            local cleanText, cleanPos = SC.RemoveHighlighting(text, position)
            return original_MyTextChanged(index, cleanText, cleanPos, force)
        end
    end

    local function WrapUndoRedo(name)
        local original = ep[name]
        if not original then return end

        ep[name] = function(index, ...)
            local editbox = GetEditBox(index)
            SuspendEditbox(editbox)
            CleanEditboxText(editbox)

            local result = original(index, ...)

            CleanEditboxText(editbox)
            return result
        end
    end

    WrapUndoRedo("Undo")
    WrapUndoRedo("Redo")

    SC.emoteProtectionWrapped = true
end

-------------------------------------------------------------------------------
-- Initialization
-------------------------------------------------------------------------------
function SC.Init()
    local loaded = SC.LoadDictionary()
    if not loaded then return end

    SC.dictionaryLoaded = true
    WrapEnscriber()
    -- WrapEmoteProtection()
    if SC.liveEditboxHooks then
        C_Timer.After(0.1, WireEditboxes)
    end

    -- SpellCheckChat is gated on IsLocked() so no new highlights are applied
    -- during lockdown. We do not strip existing highlights on lockdown start —
    -- calling SetText on the editbox during lockdown taints it, which causes
    -- SendChatMessage to be blocked as a protected function. The WrapEnscriber
    -- path strips highlights before the message pipeline, so any visible
    -- highlights during lockdown are cosmetic only and do not affect sending.
end
