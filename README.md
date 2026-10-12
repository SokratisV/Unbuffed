# Unbuffed

**Flags friendly player nameplates that are missing the buffs you track.**

[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
![Version](https://img.shields.io/badge/version-1.1.0-brightgreen)
![WoW](https://img.shields.io/badge/WoW-Forever%20%2F%20TBC%20Classic-f8b700)
![Interface](https://img.shields.io/badge/interface-16001%20%7C%2020505-555)

Pick the buffs you care about. Any friendly player whose nameplate is on screen and who
is **missing** one gets a small row of those buffs' icons beside their plate. A fully
buffed player shows nothing at all, so every icon you can see is something to cast.

> **Client support.** Runs on **WoW Forever** (interface `16001`) and on the
> **TBC Classic / Anniversary** client (interface `20505`) from the same files.

## Using it

- `/unbuffed` (or `/ub`) opens the settings panel. Tick the buffs to flag.
- `/ub add <name or spell ID>` adds anything not in the preset list.
- `/ub remove <name>`, `/ub list`, `/ub on`, `/ub off`.
- `/ub check` prints diagnostics — see **When icons don't appear** below.

Presets cover the long-term raid buffs: Fortitude, Arcane Intellect, Mark of the Wild,
Divine Spirit, Thorns, Battle Shout, and Blessings of Might / Wisdom / Kings.
**Fortitude is tracked out of the box**, so the addon does something visible before
you open the panel; untick it like any other preset if you don't want it. It is
seeded once per profile, not re-added on every load.

## Where the icons go

The **Position** section of the settings panel has a live preview of a nameplate, so
each choice shows what it does as you pick it. The icon row can attach to:

- **Right of the level text** (the default): just past the level number.
- **Left of the health bar**: against the bar's left end.
- **Centered under the health bar**.
- **Custom**: measured from the centre of the plate. The horizontal and vertical
  offset sliders appear only while this is selected.

These follow the plate's own parts, so they work at any nameplate width. A part the
plate doesn't have falls back down a chain: level box, then health bar, then the plate
itself -- friendly plates often have no level box, in which case the icon sits at the
right end of the bar instead.

**Look** covers icon size, opacity, spacing, **icon zoom** and the **icon style**.

**Icon zoom** crops into or out of the icon art. At 0% you see the whole texture,
including Blizzard's own border; higher values magnify the middle. It is separate from
icon size, which changes how big the icon is. The default, 7%, is the crop the addon
has always used, so nothing changes until you move it.

The styles are:

- **Square**: the stock spell icon (the default).
- **Round**: the icon clipped to a circle.
- **Gold ring**: the round icon inside a gold ring.

The round styles use Blizzard's own circle art, so they ship nothing of their own, and
they are offered only on clients that have it; elsewhere the choice is just Square.
The preview in the Position section shows the style you pick.

**Reset position and look** (two clicks,
no popup) puts those back to their defaults and leaves the buffs you track alone.

Settings saved by an earlier version carry over: the old *right* and *left* become
*Right of the level text* and *Left of the health bar*, and *centered* becomes *Custom*
with its offsets unchanged.

## Buffs about to expire

With **Also flag buffs about to expire** on, a buff that has less than the warning
threshold left (5 minutes by default) is shown too -- the same icon, tinted amber with
the minutes remaining on it, so it reads differently from a buff that was never cast at
all. A buff whose remaining time this client will not report is never flagged, for the
same reason an unreadable buff is never drawn as missing.

## Why buffs are matched by name

A preset matches on the buff's **name**, not a spell ID, and that is deliberate. On
Vanilla-era content a buff is a *family* of per-rank spell IDs — Power Word: Fortitude
alone is 1243, 1244, 1245, 2791, 10937 and 10938 — so a single ID would only ever match
one rank and would report everyone else as unbuffed.

Names also let a preset carry the group version, because somebody under **Prayer of
Fortitude** is not missing Fortitude.

Adding a buff by spell ID stores the ID *and* its name. The ID is the form that keeps
working during combat (see below); the name is what makes it rank-proof. A spell ID is
only ever used to prove a buff is **present** — never that it is absent.

## What the client will and won't tell an addon

Midnight (and so WoW Forever) restricts reading other players' auras:

- Aura **iteration** (`C_UnitAuras.GetAuraDataByIndex`) throws outright while auras are
  secret.
- `C_UnitAuras.GetUnitAuraBySpellID` keeps answering during combat, but only for spell
  IDs Blizzard whitelisted — which includes the long-term raid buffs this addon is for.
- A refusal looks like *"returned nothing"*, not like an error, so `C_Secrets` is used to
  ask permission first and tell a genuine "not buffed" apart from "won't say".

Unbuffed therefore treats a buff check as three-valued: **has it**, **definitely
missing**, or **no answer**. Only a definite *missing* draws an icon. Guessing on a
refusal would paint a "needs buff" icon on every player in sight the moment the client
clamped down, which is worse than drawing nothing.

### When icons don't appear

Run `/ub check` with a friendly player targeted. It prints, per tracked buff, whether
this client answered and what it said, plus whether auras are restricted right now and
whether unit identity is readable. That turns "it isn't working" into a specific cause.

The other common reason is simply that **friendly player nameplates are switched off** —
the addon says so once at login if it detects that.

## License

MIT. See [LICENSE](LICENSE).
