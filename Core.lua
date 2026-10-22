local ADDON, ns = ...

-- Unbuffed -- flags friendly player nameplates that are MISSING the buffs you track.
-- A player who has everything shows nothing; one who is missing something gets a
-- small row of the missing buffs' icons beside their nameplate.
--
-- WoW Forever (Interface 16001, Midnight 12.x API) and TBC Classic / Anniversary
-- (Interface 20505). Self-contained: no library deps.

-- Expose for console poking: /run Unbuffed.RefreshAll()
_G.Unbuffed = ns

--------------------------------------------------------------------------
-- Client / API compatibility
--------------------------------------------------------------------------
-- WoW Forever serves Classic content from the Midnight (12.x) client: it reports a
-- Classic WOW_PROJECT_ID but exposes the modern API. Detect it by interface number
-- (Forever is the 160xx range); everything else here feature-detects.
local INTERFACE = select(4, GetBuildInfo()) or 0
ns.IsForever  = INTERFACE >= 16000 and INTERFACE < 20000

-- Midnight hands addon-tainted code "secret" values for some unit and aura info.
-- A secret can be stored and passed to a widget setter, but comparing one throws
-- and arithmetic on one yields another secret. Older Classic clients have neither
-- secrets nor issecretvalue.
local issecret = _G.issecretvalue
function ns.IsSecret(v)
    return issecret ~= nil and issecret(v)
end

-- Restricted APIs refuse by returning *nothing* rather than by erroring, and a
-- secret boolean still reports as "boolean" to type(). So the only safe reading of
-- a predicate is: a real, non-secret boolean is an answer, and anything else means
-- "the client won't say" -- which is never the same as "no".
function ns.Truth(v)
    if ns.IsSecret(v) then return nil end
    if type(v) ~= "boolean" then return nil end
    return v
end

--------------------------------------------------------------------------
-- Event dispatcher
--------------------------------------------------------------------------
local dispatcher = CreateFrame("Frame")
local handlers = {}
function ns.On(event, fn)
    if not handlers[event] then
        -- RegisterEvent throws on events this client doesn't have; skip those so a
        -- single bad name can't abort the rest of a file's load.
        if not pcall(dispatcher.RegisterEvent, dispatcher, event) then return end
        handlers[event] = {}
    end
    handlers[event][#handlers[event] + 1] = fn
end
dispatcher:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for _, fn in ipairs(list) do fn(event, ...) end
end)

--------------------------------------------------------------------------
-- Presets
--------------------------------------------------------------------------
-- The buffs on offer, by class, live in Buffs.lua.

ns.FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

--------------------------------------------------------------------------
-- Saved variables
--------------------------------------------------------------------------
ns.defaults = {
    -- Stays empty here on purpose. The starting buffs are seeded by key, once, on a
    -- brand-new profile (see seedTracked): copyDefaults merges tables by index, so a
    -- default entry sitting at tracked[1] would be folded field-by-field into
    -- whatever the user happens to have first, and would grow back after removal.
    tracked   = {},     -- ordered list of entries; see AddTracked
    iconSize  = 18,
    iconStyle = "RING",     -- one of the keys in ns.ICON_STYLES below
    iconZoom  = 0,          -- percent of the icon art cropped from each edge; 0 shows all of it
    spacing   = 2,
    -- Where the icon row goes: one of the keys in ns.ANCHORS below. The first three
    -- follow a part of the nameplate; CUSTOM measures from the plate's centre by the
    -- two offsets, which mean nothing for the others.
    anchor    = "LEVEL_RIGHT",
    xOffset   = 0,
    yOffset   = 0,
    alpha     = 1,
    hideSelf  = true,   -- your own nameplate (the personal resource display)
    groupOnly = false,  -- only flag players who are in your party or raid
    flagExpiring    = true,  -- also flag buffs that are about to run out
    expiringMinutes = 5,     -- ...with this much left or less
    expireStyle = "TINT",    -- how such an icon differs: a key in ns.EXPIRE_STYLES
    expireAlpha = 50,        -- FADE only: percent opacity (of the icon opacity setting)
    ringColor = "GOLD",      -- RING style only: a key in ns.RING_COLORS
    layout    = "ROW",       -- how several icons sit: a key in ns.LAYOUTS
    maxIcons  = 9,           -- most things drawn at once, "+N" chip included; 9 or more means no limit
    outline   = false,       -- SQUARE and ROUND styles: a black edge round the icon
    outlineSize = 1,         -- ...this many pixels thick (1 to 4)
    optionsPage = "buffs",   -- the page the settings window was last on
    shareReceive = true,     -- let other players offer you their buff list (you still get asked)
    refresh   = 0.5,    -- seconds between re-checks of every visible plate
    greeted   = false,
    -- One entry per character, keyed "Name-Realm": that character's own tracked list, which class it
    -- last browsed, and which of its class's main buffs have already been ticked for it. The
    -- tracked list at the top is the current character's (the same table), and the account's
    -- old shared list is kept as legacyTracked until every character has been given its own.
    chars     = {},
}

-- How each icon is drawn, in the order the panel lists them. SQUARE is the stock
-- spell icon; RING, the default, is a round icon in a gold ring.
ns.ICON_STYLES = {
    { key = "SQUARE", label = "Square" },
    { key = "ROUND",  label = "Round" },
    { key = "RING",   label = "Gold ring" },
}

-- How an icon about to expire is told apart from one that was never cast. Only the
-- icon changes; the minutes-left label beside it always stays fully opaque.
ns.EXPIRE_STYLES = {
    { key = "TINT",  label = "Amber tint" },
    { key = "FADE",  label = "Faded icon" },
    { key = "SWEEP", label = "Countdown sweep" },
}

-- The most the icon art can be zoomed in, in percent cropped from each edge. Past this the icon is
-- magnified into a blur; the slider stops here and drawing holds any saved value to it.
ns.MAX_ZOOM = 15

-- Marks "no limit" on the icon cap: the slider's top value. A cap of N means at most N things
-- are drawn, so when more are missing the last slot becomes a "+N" chip for the rest.
ns.NO_ICON_LIMIT = 9
ns.MIN_ICON_LIMIT = 2

-- How several missing buffs sit side by side. OVERLAP ignores the spacing setting.
ns.LAYOUTS = {
    { key = "ROW",     label = "Row" },
    { key = "OVERLAP", label = "Overlapped" },
}

-- What colour the ring of the RING style is.
ns.RING_COLORS = {
    { key = "GOLD",  label = "Gold" },
    { key = "CLASS", label = "Class of the buff" },
}

-- The anchor choices, in the order the panel lists them. `help` is the line the panel
-- shows under the dropdown; nothing else reads it.
ns.ANCHORS = {
    { key = "LEVEL_RIGHT", label = "Right of the level text",
      help = "Just past the level number. A plate with no level box falls back to the right end of its health bar." },
    { key = "BAR_LEFT",    label = "Left of the health bar",
      help = "Against the left end of the health bar." },
    { key = "BAR_BELOW",   label = "Centered under the health bar",
      help = "Centered beneath the health bar." },
    { key = "CUSTOM",      label = "Custom",
      help = "Measured from the centre of the nameplate. Set the offsets below." },
}

local function copyDefaults(src, dst)
    if type(dst) ~= "table" then dst = {} end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = copyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

-- Stand-in database so nothing can index a nil ns.db between load and
-- ADDON_LOADED, which is when the real SavedVariables arrive and replace it.
-- The options panel no longer relies on this -- it builds itself on first show,
-- by which time the loaded values are in place -- but anything that runs early
-- still gets a real table rather than a crash.
ns.db = copyDefaults(ns.defaults, {})

--------------------------------------------------------------------------
-- Tracked-buff list
--------------------------------------------------------------------------
function ns.FindTracked(key)
    for i, e in ipairs(ns.db.tracked) do
        if e.key == key then return e, i end
    end
end

-- entry = { key, label, icon, names = {...}, ids = {...}, enabled }
function ns.AddTracked(entry)
    local existing = ns.FindTracked(entry.key)
    if existing then
        existing.enabled = true
        return existing
    end
    entry.enabled = true
    ns.db.tracked[#ns.db.tracked + 1] = entry
    return entry
end

function ns.RemoveTracked(key)
    local _, i = ns.FindTracked(key)
    if i then table.remove(ns.db.tracked, i) end
end

-- Build an entry from whatever the user typed: a spell id, or a buff name.
-- A spell id resolves to its name and icon, and we keep the id too -- the id path
-- is the one that survives combat on Midnight, while the name path is the one that
-- matches every rank. Wanting both is why an entry carries both.
function ns.EntryFromInput(input)
    if not input or input == "" then return nil, "nothing to add" end

    local id = tonumber(input)
    if id then
        local name, icon = ns.SpellNameAndIcon(id)
        if not name then
            return nil, ("no spell with id %d on this client"):format(id)
        end
        return { key = "spell:" .. id, label = name, icon = icon, names = { name }, ids = { id } }
    end

    -- A bare name. No id, so matching is name-only -- which is rank-proof anyway.
    -- The icon only resolves if this character knows the spell; a question mark is
    -- a fine stand-in otherwise, since the row is identified by position and tooltip.
    return {
        key = "name:" .. input:lower(), label = input,
        icon = ns.IconForSpellName(input) or ns.FALLBACK_ICON,
        names = { input },
    }
end

-- Best-effort icon for a spell the player may or may not know.
function ns.IconForSpellName(name)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, name)
        if ok and tex then return tex end
    end
    if _G.GetSpellTexture then
        local ok, tex = pcall(_G.GetSpellTexture, name)
        if ok and tex then return tex end
    end
    return nil
end

-- Spell name + icon, via whichever API this client has.
function ns.SpellNameAndIcon(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and type(info) == "table" and info.name then
            return info.name, info.iconID or ns.FALLBACK_ICON
        end
    end
    if _G.GetSpellInfo then
        local ok, name, _, icon = pcall(_G.GetSpellInfo, spellID)
        if ok and name then return name, icon or ns.FALLBACK_ICON end
    end
    return nil
end

--------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------
local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = deepCopy(x) end
    return out
end

-- The character's key in ns.db.chars: "Name-Realm", with Forever's surname standing in for the realm.
local function charKey()
    local getName = _G.UnitNameUnmodified or UnitName
    local name, second = getName("player")
    if not name or name == "" or ns.IsSecret(name) then return "unknown" end
    if not second or second == "" or ns.IsSecret(second) then second = _G.GetRealmName and GetRealmName() or "" end
    return name .. "-" .. second
end

-- Give the character logging in its own tracked list, the first time it is seen. The account's old
-- shared list is carried over where it fits: a buff of the character's own class stays, one that
-- belongs to another class (a Priest's Fortitude on a new Paladin) does not, and anything added by
-- name or id comes along. Then ns.db.tracked is pointed at the character's list, so everything
-- that reads it reads the right one. Safe to run more than once.
function ns.AttachCharacter()
    local key = charKey()
    local c = ns.db.chars[key]
    if not c then
        c = { tracked = {}, auto = {} }
        ns.db.chars[key] = c
        local mine = ns.PlayerClass()
        for _, e in ipairs(ns.db.legacyTracked or {}) do
            local owner = type(e.key) == "string" and ns.FindPreset(e.key) and ns.ClassOfBuff(e.key)
            if not owner or owner == mine then c.tracked[#c.tracked + 1] = deepCopy(e) end
        end
    end
    c.tracked = c.tracked or {}
    c.auto = c.auto or {}
    ns.char = c
    ns.db.tracked = c.tracked
    ns.attached = true
    ns.ApplyMains()
end

-- Tick the class's main buffs (ns.MAIN_BUFFS) for this character, each once, the first time it knows
-- the spell: a level 1 Paladin gets Might at level 4, and a buff unticked afterwards stays unticked.
function ns.ApplyMains()
    local mains = ns.MAIN_BUFFS[ns.PlayerClass() or ""]
    if not mains or not ns.char then return end
    for _, key in ipairs(mains) do
        if not ns.char.auto[key] then
            local preset = ns.FindPreset(key)
            if preset and ns.PresetAvailable(preset) and ns.KnowsBuff(preset) then
                ns.char.auto[key] = true
                if not ns.FindTracked(key) then ns.AddTracked(ns.PresetEntry(preset)) end
            end
        end
    end
end

-- SavedVariables are populated just before ADDON_LOADED fires for this addon, and
-- not a moment earlier, so this is the one place the saved table can be adopted.
ns.On("ADDON_LOADED", function(_, name)
    if name ~= ADDON then return end
    local fresh = type(UnbuffedDB) ~= "table"
    -- Originally the position was a `side` of RIGHT, LEFT or CENTER plus an offset.
    -- Carry that over to the nearest anchor, rather than letting the new default
    -- override a choice someone made; CENTER maps exactly, since CUSTOM measures the
    -- same way it did. Must run before copyDefaults, which would fill `anchor` in.
    if type(UnbuffedDB) == "table" and UnbuffedDB.anchor == nil then
        local legacy = { RIGHT = "LEVEL_RIGHT", LEFT = "BAR_LEFT", CENTER = "CUSTOM" }
        UnbuffedDB.anchor = legacy[UnbuffedDB.side]
    end
    -- A column layout and pop-in animation were offered briefly and then removed.
    if type(UnbuffedDB) == "table" then
        if UnbuffedDB.layout == "COLUMN" then UnbuffedDB.layout = "ROW" end
        UnbuffedDB.popIn = nil
    end
    UnbuffedDB = copyDefaults(ns.defaults, UnbuffedDB)
    ns.db = UnbuffedDB
    -- Nothing may read or write settings before this point. The options panel in
    -- particular must not build itself against the stand-in table.
    ns.dbReady = true
    -- Before this version the tracked list belonged to the account. Keep it, once, for the
    -- characters that have not been given their own yet.
    if not fresh and next(ns.db.chars) == nil and ns.db.legacyTracked == nil and #ns.db.tracked > 0 then
        ns.db.legacyTracked = deepCopy(ns.db.tracked)
    end
end)

ns.On("PLAYER_LOGIN", function()
    ns.AttachCharacter()
    if not ns.char.greeted and #ns.db.tracked == 0 then
        ns.char.greeted = true
        ns.Print("nothing is being tracked yet -- open |cffffd100/unbuffed|r and tick the buffs you want flagged.")
    end
    -- The addon draws on friendly player nameplates, so it is invisible while the
    -- client isn't showing any. Worth saying once rather than looking broken.
    ns.CheckNameplateCVar()
end)

-- Learning a spell (or levelling up, or a talent change) can make a main buff known.
local function spellsChanged()
    if not ns.attached then return end
    ns.ResetKnown()
    ns.ApplyMains()
    if ns.RefreshAll then ns.RefreshAll() end
    if ns.RefreshOptions then ns.RefreshOptions() end
end
ns.On("SPELLS_CHANGED", spellsChanged)
ns.On("PLAYER_LEVEL_UP", spellsChanged)

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffUnbuffed|r: " .. msg)
end

-- Friendly player nameplates are behind a CVar, and its name has moved around
-- between flavors, so try each spelling and only complain if one answers "off".
function ns.CheckNameplateCVar()
    local get = (C_CVar and C_CVar.GetCVarBool) or _G.GetCVarBool
    if not get then return end
    for _, cvar in ipairs({ "nameplateShowFriendlyPlayers", "nameplateShowFriends" }) do
        local ok, on = pcall(get, cvar)
        if ok and type(on) == "boolean" then
            if not on then
                ns.Print("friendly player nameplates are turned off, so nothing will show. Enable them in Interface options, or run |cffffd100/run C_CVar.SetCVar(\"" .. cvar .. "\", \"1\")|r")
            end
            return
        end
    end
end
