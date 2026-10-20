local ADDON, ns = ...

-- Sharing your buff list with another player, in the way Thumber (same author) shares its marks:
-- a whisper transfer over addon messages. The other player is asked first (Accept / Decline),
-- and the list then goes across in small, paced chunks.
--
-- Only which buffs you track is sent -- not your look, and no icons. A listed buff goes as its key and
-- is looked up in the receiver's own tables, so it comes with the receiver's own names, icon and
-- availability; one added by name goes as that name; one added by spell id as the id. Everything
-- that arrives is treated as untrusted: validated, stripped of escape codes, size-capped, and only
-- ever ADDED to the list, never allowed to remove or change anything.

local PREFIX        = "UNBUFFED"
local VERSION       = 1
local CHUNK         = 200    -- characters of payload per addon message (the limit is 255)
local STEP          = 0.3    -- seconds between chunks, well under the server's rate limit
local MAX_ENTRIES   = 200
local MAX_CHUNKS    = 60
local OFFER_WAIT    = 60     -- how long a sender waits for Accept
local OFFER_SHOWN   = 45     -- how long the prompt stays up before it declines for you
local RETRY_RESULTS = { [3] = true, [8] = true, [11] = true }   -- throttled / locked down

local IsSecret = function(v) return ns.IsSecret(v) end

--------------------------------------------------------------------------
-- Encoding: base64 (so the text survives the addon channel) over a small tab-separated format
--------------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local ENC, DEC = {}, {}
for i = 1, 64 do
    local c = B64:sub(i, i)
    ENC[i - 1], DEC[c] = c, i - 1
end

local function B64Encode(data)
    local out = {}
    for i = 1, #data, 3 do
        local a, b, c = data:byte(i, i + 2)
        local v = a * 65536 + (b or 0) * 256 + (c or 0)
        out[#out + 1] = ENC[math.floor(v / 262144)] .. ENC[math.floor(v / 4096) % 64]
            .. (b and ENC[math.floor(v / 64) % 64] or "=") .. (c and ENC[v % 64] or "=")
    end
    return table.concat(out)
end

-- The decoded string, or nil if the text is not valid base64.
local function B64Decode(text)
    text = text:gsub("=+$", "")
    if text:find("[^A-Za-z0-9+/]") or #text % 4 == 1 then return nil end
    local out = {}
    for i = 1, #text, 4 do
        local s = text:sub(i, i + 3)
        local d1, d2, d3, d4 = DEC[s:sub(1, 1)], DEC[s:sub(2, 2)], DEC[s:sub(3, 3)], DEC[s:sub(4, 4)]
        local v = d1 * 262144 + d2 * 4096 + (d3 or 0) * 64 + (d4 or 0)
        out[#out + 1] = string.char(math.floor(v / 65536))
        if d3 then out[#out + 1] = string.char(math.floor(v / 256) % 256) end
        if d4 then out[#out + 1] = string.char(v % 256) end
    end
    return table.concat(out)
end

local ESC = { ["\\"] = "\\\\", ["\t"] = "\\t", ["\n"] = "\\n", ["\r"] = "" }
local function Esc(s) return (tostring(s or ""):gsub("[\\\t\n\r]", ESC)) end
local function Unesc(s)
    return (s:gsub("\\(.)", function(c) return c == "t" and "\t" or c == "n" and "\n" or c end))
end

local function Split(s, sep)
    local parts, from = {}, 1
    while true do
        local i = s:find(sep, from, true)
        if not i then parts[#parts + 1] = s:sub(from) break end
        parts[#parts + 1] = s:sub(from, i - 1)
        from = i + #sep
    end
    return parts
end

-- Cut to `max` bytes without leaving half a UTF-8 character at the end.
local function Cut(s, max)
    if #s <= max then return s end
    s = s:sub(1, max)
    local p = #s
    while p > 1 and s:byte(p) >= 0x80 and s:byte(p) < 0xC0 do p = p - 1 end
    local lead = s:byte(p)
    local len = lead >= 0xF0 and 4 or lead >= 0xE0 and 3 or lead >= 0xC0 and 2 or 1
    if p + len - 1 > #s then s = s:sub(1, p - 1) end
    return s
end

-- Text from outside: no escape codes (colours, textures, links), no control characters,
-- trimmed, and cut to length.
local function Clean(s, max)
    s = s:gsub("|", ""):gsub("%c", " ")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return Cut(s, max)
end

--------------------------------------------------------------------------
-- What goes across
--------------------------------------------------------------------------
-- The enabled buffs as one text block, and how many there are. Listed buffs go by key; the rest by
-- the id or the name they were added with. Anything else is left out.
local function Serialize()
    local lines, n = { "UNBUFFED" .. VERSION }, 0
    for _, e in ipairs(ns.db.tracked) do
        if e.enabled and n < MAX_ENTRIES and type(e.key) == "string" then
            local line
            if ns.FindPreset(e.key) then
                line = "p\t" .. Esc(e.key)
            elseif e.key:find("^spell:") and e.ids and tonumber(e.ids[1]) then
                line = "i\t" .. math.floor(tonumber(e.ids[1]))
            elseif e.key:find("^name:") and e.names and type(e.names[1]) == "string" then
                line = "n\t" .. Esc(e.names[1])
            end
            if line then
                n = n + 1
                lines[#lines + 1] = line
            end
        end
    end
    return table.concat(lines, "\n"), n
end

-- A text block back into a validated list of { kind, value }, or nil and a reason.
local function ParsePayload(raw)
    local lines = Split(raw, "\n")
    if lines[1] ~= "UNBUFFED" .. VERSION then return nil, "that was made by a different version of Unbuffed" end
    local entries, seen = {}, {}
    for i = 2, #lines do
        if lines[i] ~= "" and #entries < MAX_ENTRIES then
            local f = Split(lines[i], "\t")
            local kind, value = f[1], Unesc(f[2] or "")
            local ok = false
            if kind == "p" then
                value = Clean(value, 32)
                ok = value:match("^[%w_]+$") ~= nil
            elseif kind == "i" then
                local id = tonumber(value)
                if id and id >= 1 and id <= 9999999 and id == math.floor(id) then value, ok = id, true end
            elseif kind == "n" then
                value = Clean(value, 64)
                ok = value ~= "" and tonumber(value) == nil
            end
            local id = kind .. ":" .. tostring(value)
            if ok and not seen[id] then
                seen[id] = true
                entries[#entries + 1] = { kind = kind, value = value }
            end
        end
    end
    return entries
end

-- Add what the list does not have, and nothing else. Returns how many were added, how many were
-- already tracked, and how many this client cannot use (a TBC-only buff on Forever, a spell id it
-- does not know). An existing entry is never touched, even if it is switched off.
local function Apply(entries)
    local added, had, skipped = 0, 0, 0
    for _, ent in ipairs(entries) do
        local built
        if ent.kind == "p" then
            local preset = ns.FindPreset(ent.value)
            if preset and ns.PresetAvailable(preset) then built = ns.PresetEntry(preset) end
        else
            built = ns.EntryFromInput(ent.kind == "i" and tostring(ent.value) or ent.value)
        end
        if not built then
            skipped = skipped + 1
        elseif ns.FindTracked(built.key) then
            had = had + 1
        else
            ns.AddTracked(built)
            added = added + 1
        end
    end
    ns.RefreshAll()
    ns.RefreshOptions()
    return added, had, skipped
end

ns.Share = { B64Encode = B64Encode, B64Decode = B64Decode, Serialize = Serialize, Parse = ParsePayload, Apply = Apply }

--------------------------------------------------------------------------
-- Naming a player, as the game wants it
--------------------------------------------------------------------------
-- WoW Forever gives every character a first name and a surname, and UnitName answers (first name,
-- surname) where Classic answers (name, realm); so there the second value is part of the name.
local function UniqueNames()
    return RegionalUniqueNamesEnabled ~= nil and RegionalUniqueNamesEnabled() == true
end
local function SurnameSeparator()
    local consts = Constants and Constants.CharacterNameSeparatorConsts
    return consts and consts.CHARACTERNAME_SURNAME_SEPARATOR or " "
end

-- A unit's full name in the form a whisper takes, or nothing if it cannot be read.
local function UnitKey(unit)
    if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then return end
    local getName = (unit == "player" and UnitNameUnmodified) or UnitName
    local name, second = getName(unit)
    if not name or IsSecret(name) or name == "" then return end
    if second and IsSecret(second) then return end
    local hasSecond = second and second ~= ""
    if UniqueNames() then
        local sep = SurnameSeparator()
        if hasSecond and not name:find(sep, 1, true) then return name .. sep .. second end
        return name
    end
    return hasSecond and (name .. "-" .. second) or name
end

-- A typed name, tidied the way the game would: trimmed, the first letter capitalised, and on Forever
-- the surname too, with the old "First-Surname" spelling accepted.
local function NormalizeName(text)
    local key = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if UniqueNames() then
        local sep = SurnameSeparator()
        key = key:gsub("^([^%-%s]+)%-([^%-%s]+)$", "%1" .. sep:gsub("%%", "%%%%") .. "%2")
        local first, rest = key:find(sep, 1, true)
        if first then
            local surname = key:sub(rest + 1):gsub("^%l", string.upper)
            key = key:sub(1, rest) .. surname
        end
    end
    return (key:gsub("^%l", string.upper))
end

-- The friendly player you are targeting (or pointing at), as a name to send to.
function ns.ShareTargetName()
    return UnitKey("target") or UnitKey("mouseover")
end

--------------------------------------------------------------------------
-- Status line, shown wherever the options window put one
--------------------------------------------------------------------------
ns.shareStatus = ""
local function Status(text)
    ns.shareStatus = text or ""
    if ns.ShareSink then ns.ShareSink(ns.shareStatus) end
end
local function Print(msg) ns.Print(msg) end

--------------------------------------------------------------------------
-- Sending to a player
--------------------------------------------------------------------------
local out        -- the transfer we are sending
local inc        -- the transfer we are receiving
local offer      -- an offer waiting for Accept / Decline
local lastOffer = {}

local function SendMsg(msg, target)
    local send = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or _G.SendAddonMessage
    if not send then return false end
    local ok, res = pcall(send, PREFIX, msg, "WHISPER", target)
    if not ok then return false end
    if res == nil or res == true or res == 0 then return true end
    return false, res
end

local function SameName(a, b)
    local function norm(n)
        n = Ambiguate and Ambiguate(n, "short") or n
        return n:lower()
    end
    return norm(a) == norm(b)
end

local function Pump(o)
    if out ~= o then return end
    local chunk = o.chunks[o.idx + 1]
    if not chunk then
        Status(("Sent %d buffs to %s."):format(o.count, o.target))
        Print(("sent %d buffs to %s."):format(o.count, o.target))
        out = nil
        return
    end
    local ok, res = SendMsg(("C:%s:%d:%s"):format(o.id, o.idx + 1, chunk), o.target)
    if ok then
        o.idx, o.tries = o.idx + 1, 0
        Status(("Sending to %s... %d / %d"):format(o.target, o.idx, #o.chunks))
    else
        o.tries = (o.tries or 0) + 1
        if not (res and RETRY_RESULTS[res]) or o.tries > 5 then
            Status("Sending stopped: the game wouldn't take the messages. Try again in a moment.")
            out = nil
            return
        end
    end
    C_Timer.After(ok and STEP or 1, function() Pump(o) end)
end

-- Offer your buffs to `target`; the transfer starts when they accept. Returns true, or false and why.
function ns.SendBuffs(target)
    target = NormalizeName(target or "")
    if target == "" then return false, "Type a player's name first." end
    local me = UnitKey("player")
    if me and SameName(me, target) then return false, "That's you." end
    local payload, count = Serialize()
    if count == 0 then return false, "You aren't tracking any buffs to share." end
    if out then return false, "A transfer is already under way." end
    local data = B64Encode(payload)
    local chunks = {}
    for i = 1, #data, CHUNK do chunks[#chunks + 1] = data:sub(i, i + CHUNK - 1) end
    if #chunks > MAX_CHUNKS then return false, "That's too many buffs to send." end

    local id = ("%06x"):format(math.random(0, 0xFFFFFF))
    local ok = SendMsg(("O:%s:%d:%d"):format(id, #chunks, count), target)
    if not ok then return false, "Couldn't send anything to " .. target .. "." end
    local o = { id = id, target = target, chunks = chunks, idx = 0, count = count }
    out = o
    Status(("Waiting for %s to accept %d buffs..."):format(target, count))
    C_Timer.After(OFFER_WAIT, function()
        if out == o and not o.sending then
            out = nil
            Status(("No answer from %s. They may be offline, not have Unbuffed, or have said no."):format(target))
        end
    end)
    return true
end

--------------------------------------------------------------------------
-- Receiving
--------------------------------------------------------------------------
local function Watch(i)
    C_Timer.After(10, function()
        if inc ~= i then return end
        if GetTime() - i.last > 40 then
            Print(("the transfer from %s timed out."):format(i.sender))
            inc = nil
        else
            Watch(i)
        end
    end)
end

local function Finish(i)
    inc = nil
    local parts = {}
    for n = 1, i.total do parts[n] = i.got[n] end
    local raw = B64Decode(table.concat(parts))
    local entries, err
    if raw then entries, err = ParsePayload(raw) else err = "the data was damaged" end
    if not entries then
        Print(("what %s sent couldn't be read: %s."):format(i.sender, err or "damaged data"))
        return
    end
    local added, had, skipped = Apply(entries)
    local msg = ("received %d buffs from %s: %d new"):format(#entries, i.sender, added)
    if had > 0 then msg = msg .. (", %d you already track"):format(had) end
    if skipped > 0 then msg = msg .. (", %d this client can't use"):format(skipped) end
    Print(msg .. ".")
end

local function Decline(o, reason)
    if offer == o then offer = nil end
    SendMsg(("D:%s:%s"):format(o.id, reason or "no"), o.sender)
end

local function Accept(o)
    if offer ~= o then return end
    offer = nil
    local i = { id = o.id, sender = o.sender, total = o.total, count = o.count, got = {}, n = 0, last = GetTime() }
    inc = i
    SendMsg("A:" .. o.id, o.sender)
    Print(("receiving %d buffs from %s..."):format(o.count, o.sender))
    Watch(i)
end

-- The Accept / Decline prompt is our own frame. It deliberately does not use Blizzard's StaticPopup
-- system: registering a dialog writes to Blizzard's StaticPopupDialogs global, and that taint is
-- read by the game menu's Escape handling, which then blocks the menu.
local offerFrame
local function ShowOffer(o)
    local f = offerFrame
    if not f then
        f = CreateFrame("Frame", "UnbuffedOffer", UIParent, "BackdropTemplate")
        f:SetSize(380, 104)
        f:SetPoint("TOP", UIParent, "TOP", 0, -160)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetClampedToScreen(true)
        f:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        f:SetBackdropColor(0.08, 0.067, 0.043, 0.97)
        f:SetBackdropBorderColor(0.80, 0.60, 0.34, 1)
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.text:SetPoint("TOPLEFT", 16, -14)
        f.text:SetPoint("TOPRIGHT", -16, -14)
        f.text:SetJustifyH("CENTER")
        local function button(text, x, onClick)
            local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
            b:SetSize(110, 22)
            b:SetPoint("TOPLEFT", x, -68)
            b:SetText(text)
            b:SetScript("OnClick", onClick)
            return b
        end
        f.accept = button("Accept", 70, function()
            local cur = f.offer
            f:Hide()
            if cur then Accept(cur) end
        end)
        f.decline = button("Decline", 200, function()
            local cur = f.offer
            f:Hide()
            if cur and offer == cur then Decline(cur) end
        end)
        offerFrame = f
    end
    f.offer = o
    f.text:SetText(("|cffffd100%s|r wants to share %d Unbuffed buffs with you.\nYour own list is kept; only new buffs are added."):format(o.sender, o.count))
    f:Show()
    C_Timer.After(OFFER_SHOWN, function()
        if f.offer == o and offer == o then
            f:Hide()
            Decline(o)
        end
    end)
end

local function OnOffer(sender, rest)
    local id, total, count = rest:match("^(%x+):(%d+):(%d+)$")
    if not id then return end
    total, count = tonumber(total), tonumber(count)
    local o = { id = id, sender = sender, total = total, count = count }
    local now = GetTime()
    if lastOffer[sender] and now - lastOffer[sender] < 15 then return end   -- no popup spam
    lastOffer[sender] = now
    if not ns.db.shareReceive then return Decline(o, "off") end
    if inc or offer then return Decline(o, "busy") end
    if total < 1 or total > MAX_CHUNKS or count > MAX_ENTRIES then return Decline(o, "size") end
    offer = o
    ShowOffer(o)
end

local DECLINED = {
    busy = "is busy with another transfer", off = "isn't accepting shared buffs",
    size = "can't take that many buffs",
}

local function OnMessage(prefix, text, _, sender)
    if prefix ~= PREFIX or type(text) ~= "string" or type(sender) ~= "string" then return end
    if IsSecret(text) or IsSecret(sender) then return end
    local kind, rest = text:match("^(%a):(.*)$")
    if kind == "O" then
        OnOffer(sender, rest)
    elseif kind == "A" then
        if out and out.id == rest and not out.sending and SameName(sender, out.target) then
            out.sending = true
            Status(("%s accepted. Sending..."):format(out.target))
            Pump(out)
        end
    elseif kind == "D" then
        local id, reason = rest:match("^(%x+):(%a*)$")
        if out and out.id == id and SameName(sender, out.target) then
            Status(("%s %s."):format(out.target, DECLINED[reason] or "said no"))
            out = nil
        end
    elseif kind == "C" then
        local id, n, data = rest:match("^(%x+):(%d+):(.*)$")
        n = tonumber(n)
        if inc and inc.id == id and SameName(sender, inc.sender) and n and n >= 1 and n <= inc.total
            and not inc.got[n] and #data <= CHUNK + 8 and not data:find("[^A-Za-z0-9+/=]") then
            inc.got[n], inc.n, inc.last = data, inc.n + 1, GetTime()
            if inc.n == inc.total then Finish(inc) end
        end
    end
end

ns.On("PLAYER_LOGIN", function()
    local register = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or _G.RegisterAddonMessagePrefix
    if register then pcall(register, PREFIX) end
end)
ns.On("CHAT_MSG_ADDON", function(_, ...) OnMessage(...) end)
