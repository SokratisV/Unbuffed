local ADDON, ns = ...
local L = ns.L

-- Exporting and importing a whole setup as one string you can copy: every setting, and the current
-- character's buff list. Paste it on another character or another install to get the same setup.
--
--   UNBUFFEDP1:<base64 of the text below>
--
--   UNBUFFEDPROFILE1
--   v<TAB><addon version>
--   s<TAB><setting><TAB><value>          one per setting
--   ---
--   UNBUFFED1                            the buff list, in the format Share.lua sends over a whisper,
--   p<TAB>fortitude<TAB>1                with a third column saying whether the buff is switched on
--   n<TAB>Power Infusion<TAB>0
--
-- What comes in is untrusted: the tag and version must match, the text must decode, every value is
-- checked against what the setting allows (a number is clamped, a choice must be one that exists), and
-- anything unknown or invalid is dropped, never an error. A setting the string does not mention takes
-- its default, so an export from an older version still leaves a complete setup.

local TAG, VERSION = "UNBUFFEDP", 1
local MAX_TEXT = 40000

-- Every setting a profile carries, and what each may be. A test insists that every setting in
-- ns.defaults is either here or deliberately not (see ns.PROFILE_SKIPPED), so a new setting cannot
-- be forgotten.
local SPECS = {
    { key = "anchor",          enum = ns.ANCHORS },
    { key = "xOffset",         min = -200, max = 200 },
    { key = "yOffset",         min = -100, max = 100 },
    { key = "iconSize",        min = 8,    max = 40 },
    { key = "iconStyle",       enum = ns.ICON_STYLES },
    { key = "iconZoom",        min = 0,    max = ns.MAX_ZOOM },
    { key = "spacing",         min = 0,    max = 12 },
    { key = "alpha",           min = 0.2,  max = 1, float = true },
    { key = "ringColor",       enum = ns.RING_COLORS },
    { key = "layout",          enum = ns.LAYOUTS },
    { key = "maxIcons",        min = ns.MIN_ICON_LIMIT, max = ns.NO_ICON_LIMIT },
    { key = "outline",         bool = true },
    { key = "outlineSize",     min = 1,    max = 4 },
    { key = "hideSelf",        bool = true },
    { key = "groupOnly",       bool = true },
    { key = "flagExpiring",    bool = true },
    { key = "expiringMinutes", min = 1,    max = 30 },
    { key = "expireStyle",     enum = ns.EXPIRE_STYLES },
    { key = "expireAlpha",     min = 10,   max = 100 },
    { key = "shareReceive",    bool = true },
    { key = "refresh",         min = 0.1,  max = 5, float = true },
}
ns.PROFILE_SPECS = SPECS

-- Settings that are not part of a profile, and why: the buff lists are carried separately (and only the
-- current character's), `chars` and `legacyTracked` are other characters' data, and the rest is state.
ns.PROFILE_SKIPPED = {
    tracked = "the buff list, carried as its own section",
    chars = "every character's own data; a profile carries only the current character's list",
    legacyTracked = "the old shared list, kept only to seed new characters",
    optionsPage = "which page the window was last on",
    greeted = "a flag that has not been used since lists became per-character",
}

local function encode(spec, v)
    if spec.bool then return v and "1" or "0" end
    return tostring(v)
end

-- The value a profile's text means for a setting, or nil if it is not one the setting allows.
local function decode(spec, text)
    if spec.bool then
        if text == "1" then return true elseif text == "0" then return false end
        return nil
    end
    if spec.enum then
        for _, o in ipairs(spec.enum) do if o.key == text then return text end end
        return nil
    end
    local n = tonumber(text)
    if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
    n = math.max(spec.min, math.min(spec.max, n))
    if not spec.float then n = math.floor(n + 0.5) end
    return n
end

local function addonVersion()
    local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
    local ok, v = pcall(function() return meta and meta(ADDON, "Version") end)
    return (ok and v) or "?"
end

--------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------
-- The whole setup as one string, and how many buffs it holds.
function ns.ExportProfile()
    local S = ns.Share
    local lines = { "UNBUFFEDPROFILE" .. VERSION, "v\t" .. S.Esc(addonVersion()) }
    for _, spec in ipairs(SPECS) do
        local v = ns.db[spec.key]
        if v == nil then v = ns.defaults[spec.key] end
        lines[#lines + 1] = "s\t" .. spec.key .. "\t" .. S.Esc(encode(spec, v))
    end
    lines[#lines + 1] = "---"
    local block, n = S.Serialize(true)
    lines[#lines + 1] = block
    return TAG .. VERSION .. ":" .. S.B64Encode(table.concat(lines, "\n")), n
end

--------------------------------------------------------------------------
-- Import
--------------------------------------------------------------------------
local function parse(text)
    local S = ns.Share
    if type(text) ~= "string" then return nil, L["Paste a profile first."] end
    text = text:gsub("%s+", "")
    if text == "" then return nil, L["Paste a profile first."] end
    if #text > MAX_TEXT then return nil, L["That is too long to be an Unbuffed profile."] end
    local ver, body = text:match("^" .. TAG .. "(%d+):(.+)$")
    if not ver then return nil, L["That doesn't look like an Unbuffed profile."] end
    if tonumber(ver) ~= VERSION then return nil, L["That profile was made by a different version of Unbuffed."] end
    local raw = S.B64Decode(body)
    if not raw then return nil, L["The text is damaged. Copy the whole string again."] end

    local lines = S.Split(raw, "\n")
    if lines[1] ~= "UNBUFFEDPROFILE" .. VERSION then return nil, L["The text is damaged. Copy the whole string again."] end
    local profile = { settings = {}, ignored = 0, invalid = 0 }
    local specByKey = {}
    for _, spec in ipairs(SPECS) do specByKey[spec.key] = spec end
    local cut
    for i = 2, #lines do
        if lines[i] == "---" then cut = i break end
        local f = S.Split(lines[i], "\t")
        if f[1] == "v" then
            profile.version = S.Clean(S.Unesc(f[2] or ""), 16)
        elseif f[1] == "s" then
            local spec = specByKey[f[2] or ""]
            if not spec then
                profile.ignored = profile.ignored + 1
            else
                local v = decode(spec, S.Unesc(f[3] or ""))
                if v == nil then profile.invalid = profile.invalid + 1 else profile.settings[spec.key] = v end
            end
        end
    end
    if cut then
        local entries, err = S.Parse(table.concat(lines, "\n", cut + 1))
        if not entries then return nil, L["The buff list in that profile couldn't be read."] .. " " .. (err or L["The data was damaged."]) end
        profile.buffs = entries
    end
    return profile
end

-- A parsed profile, or nil and a reason; never an error, whatever the text.
function ns.ParseProfile(text)
    local ok, profile, err = pcall(parse, text)
    if not ok then return nil, L["The text is damaged. Copy the whole string again."] end
    return profile, err
end

-- How an import would land: how many settings differ from yours, and how many buffs the profile carries.
function ns.CompareProfile(profile)
    local differ = 0
    for _, spec in ipairs(SPECS) do
        local v = profile.settings[spec.key]
        if v == nil then v = ns.defaults[spec.key] end
        local cur = ns.db[spec.key]
        if cur == nil then cur = ns.defaults[spec.key] end
        if cur ~= v then differ = differ + 1 end
    end
    local buffs, on = 0, 0
    for _, e in ipairs(profile.buffs or {}) do
        buffs = buffs + 1
        if e.enabled then on = on + 1 end
    end
    return differ, buffs, on
end

-- Put a profile's settings, and with `withBuffs` its buff list, in place of the current ones, and redraw
-- everything now. The buff list replaces this character's in the same table, so nothing that holds it
-- is left looking at an old one; a buff this client doesn't have (a TBC-only one on Forever, a spell id
-- it doesn't know) is skipped. Returns how many settings changed, how many buffs were set, how many
-- were skipped.
function ns.ApplyProfile(profile, withBuffs)
    local changed = 0
    for _, spec in ipairs(SPECS) do
        local v = profile.settings[spec.key]
        if v == nil then v = ns.defaults[spec.key] end
        if ns.db[spec.key] ~= v then changed = changed + 1 end
        ns.db[spec.key] = v
    end
    local set, skipped = 0, 0
    if withBuffs and profile.buffs then
        local list = ns.db.tracked
        for i = #list, 1, -1 do table.remove(list, i) end
        for _, ent in ipairs(profile.buffs) do
            local built = ns.Share.BuildEntry(ent)
            if not built or ns.FindTracked(built.key) then
                skipped = skipped + 1
            else
                built.enabled = ent.enabled and true or false
                list[#list + 1] = built
                set = set + 1
            end
        end
        -- an import is a choice about the list: the class's mains are not ticked again behind it
        for _, key in ipairs(ns.MAIN_BUFFS[ns.PlayerClass() or ""] or {}) do ns.char.auto[key] = true end
    end
    ns.RefreshAll()
    ns.RefreshOptions()
    return changed, set, skipped
end
