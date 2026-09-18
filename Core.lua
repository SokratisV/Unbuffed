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
-- Matched by NAME, not spell id, and that is deliberate: on Vanilla-era content a
-- buff is a family of per-rank spell ids (Power Word: Fortitude alone is 1243,
-- 1244, 1245, 2791, 10937, 10938), so one id would only ever match one rank.
-- `names` also carries the group version, because someone under Prayer of
-- Fortitude is not missing Fortitude.
--
-- Icons are literal paths so a preset still draws for a class that can't cast it
-- (a warrior wants to see who lacks Fortitude); a spell id look-up would come back
-- empty there.
ns.PRESETS = {
    { key = "fortitude", label = "Fortitude",          icon = "Interface\\Icons\\Spell_Holy_WordFortitude",
      names = { "Power Word: Fortitude", "Prayer of Fortitude" } },
    { key = "intellect", label = "Arcane Intellect",   icon = "Interface\\Icons\\Spell_Holy_MagicalSentry",
      names = { "Arcane Intellect", "Arcane Brilliance" } },
    { key = "motw",      label = "Mark of the Wild",   icon = "Interface\\Icons\\Spell_Nature_Regeneration",
      names = { "Mark of the Wild", "Gift of the Wild" } },
    { key = "spirit",    label = "Divine Spirit",      icon = "Interface\\Icons\\Spell_Holy_DivineSpirit",
      names = { "Divine Spirit", "Prayer of Spirit" } },
    { key = "thorns",    label = "Thorns",             icon = "Interface\\Icons\\Spell_Nature_Thorns",
      names = { "Thorns" } },
    { key = "bshout",    label = "Battle Shout",       icon = "Interface\\Icons\\Ability_Warrior_BattleShout",
      names = { "Battle Shout" } },
    { key = "might",     label = "Blessing of Might",  icon = "Interface\\Icons\\Spell_Holy_FistOfJustice",
      names = { "Blessing of Might", "Greater Blessing of Might" } },
    { key = "wisdom",    label = "Blessing of Wisdom", icon = "Interface\\Icons\\Spell_Holy_SealOfWisdom",
      names = { "Blessing of Wisdom", "Greater Blessing of Wisdom" } },
    { key = "kings",     label = "Blessing of Kings",  icon = "Interface\\Icons\\Spell_Magic_MageArmor",
      names = { "Blessing of Kings", "Greater Blessing of Kings" } },
}

ns.FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

--------------------------------------------------------------------------
-- Saved variables
--------------------------------------------------------------------------
ns.defaults = {
    enabled   = true,
    tracked   = {},     -- ordered list of entries; see AddTracked
    iconSize  = 18,
    spacing   = 2,
    side      = "RIGHT",
    xOffset   = 4,
    yOffset   = 0,
    alpha     = 1,
    hideSelf  = true,   -- your own nameplate (the personal resource display)
    refresh   = 0.5,    -- seconds between re-checks of every visible plate
    greeted   = false,
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
ns.On("ADDON_LOADED", function(_, name)
    if name ~= ADDON then return end
    UnbuffedDB = copyDefaults(ns.defaults, UnbuffedDB)
    ns.db = UnbuffedDB
end)

ns.On("PLAYER_LOGIN", function()
    if not ns.db.greeted and #ns.db.tracked == 0 then
        ns.db.greeted = true
        ns.Print("nothing is being tracked yet -- open |cffffd100/unbuffed|r and tick the buffs you want flagged.")
    end
    -- The addon draws on friendly player nameplates, so it is invisible while the
    -- client isn't showing any. Worth saying once rather than looking broken.
    ns.CheckNameplateCVar()
end)

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
