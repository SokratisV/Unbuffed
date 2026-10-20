# Unbuffed

**Flags friendly player nameplates that are missing the buffs you track.**

[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
![Version](https://img.shields.io/badge/version-1.5.0-brightgreen)
![WoW](https://img.shields.io/badge/WoW-Forever%20%2F%20TBC%20Classic-f8b700)
![Interface](https://img.shields.io/badge/interface-16001%20%7C%2020505-555)

Pick the buffs you care about. Any friendly player whose nameplate is on screen and who
is **missing** one gets a small row of those buffs' icons beside their plate. A fully
buffed player shows nothing at all, so every icon you can see is something to cast.

> **Client support.** Runs on **WoW Forever** (interface `16001`) and on the
> **TBC Classic / Anniversary** client (interface `20505`) from the same files.

## Using it

- `/unbuffed` (or `/ub`) opens the settings window. Pick a class and tick the buffs to flag. It has
  four pages -- **Buffs**, **Look**, **Expiring** and **General** -- in the style of FlareUI: the
  pages on the left, the settings in the middle, and on the right what the setting you are pointing
  at does. Settings that don't apply to your choices (the ring color, once the style has no ring)
  are not shown. The entry under AddOns in the game's own settings just opens this window.
- `/ub add <name or spell ID>` adds anything the class lists don't have.
- `/ub remove <name>`, `/ub list`.
- `/ub test` runs the expiring-buff look for 20 seconds, so you can see it.

## Choosing buffs

The **Buffs** page has a **Class** choice with all nine classes. Pick one
and it lists every buff that class casts on other players: for example the Paladin's
blessings and auras, the Shaman's totem buffs, the Priest's Fortitude, Spirit and Shadow
Protection. The dropdown starts on your own class. Tick any number of buffs, and switch
class to add more: the choices accumulate.

Under the class list, **Active buffs** shows everything currently tracked, whichever
class it came from (or none, for a buff added by name), each with a button to drop it.
Unticking a buff in its class does the same.

Hover any buff, in the class list or the Active list, for its tooltip: the game's own
description of the spell, for the **rank that suits your character's level** -- the
highest rank you could have learned by now, so a level-25 character sees Blessing of Might
rank 3 and a level-60 one rank 6. A character below a buff's first rank sees that rank,
with a note saying at which level it is learned. The ranks come from the trainer data for
your client (Forever's or TBC's), so a TBC character sees the TBC-only higher ranks.
Buffs with no level-based rank have a plain tooltip instead, naming what they match:
Blessing of Sanctuary and Blood Pact (talent and pet spells, in no trainer list) and, on
TBC, Blessing of Kings (a talent there). A buff you added by spell ID shows exactly that
spell.

A Rogue has no buffs of that kind, so that class's list is empty; anything else can
always be added by name or spell ID. A few buffs exist only on the TBC clients
(Commanding Shout, Tranquil Air, Wrath of Air Totem) and are left out on Forever.

**Fortitude is tracked out of the box** on a fresh profile, so the addon does something
visible before you open the panel; untick it like any other buff if you don't want it.
It is seeded once per profile, not re-added on every load.

## Who gets an icon

Any friendly player whose nameplate is on screen. Two options in **General** narrow that:
**Skip my own nameplate**, and **Only show for party and raid members**, which limits the
icons to people in your group, so strangers in a city or a dungeon never get one. With the
second on and no group, nothing is shown. If the client won't say whether someone is in your
group, they are treated as not being in it, the same way an unreadable buff is never drawn
as missing.

## Where the icons go

The **Look** page's **Position** section chooses where the icon row attaches. Above the settings
on the Look and Expiring pages sits a live **preview** of a nameplate that stays put while the page
scrolls, so each choice shows what it does as you make it. The icon row can attach to:

- **Right of the level text** (the default): just past the level number.
- **Left of the health bar**: against the bar's left end.
- **Centered under the health bar**.
- **Custom**: measured from the centre of the plate. The horizontal and vertical
  offset sliders appear only while this is selected.

These follow the plate's own parts, so they work at any nameplate width. A part the
plate doesn't have falls back down a chain: level box, then health bar, then the plate
itself -- friendly plates often have no level box, in which case the icon sits at the
right end of the bar instead.

The **Look** page covers icon size, opacity, **layout**, spacing, a **cap** on how many icons are
drawn, the **icon style** with the options that belong to it, **icon zoom**, and the position.

**Icon zoom** crops into or out of the icon art. At 0% you see the whole texture,
including Blizzard's own border; higher values magnify the middle. It is separate from
icon size, which changes how big the icon is. The default is 0%, the whole icon.

The styles are:

- **Square**: the stock spell icon.
- **Round**: the icon clipped to a circle.
- **Gold ring** (the default): the round icon inside a gold ring.

The round styles use Blizzard's own circle art, so they ship nothing of their own, and
they are offered only on clients that have it; elsewhere the choice is just Square.

Each style shows its own options and hides the rest: the gold ring has a **ring color**; Square and
Round have a **black outline** with a **thickness**.

**Ring color** applies to the gold ring style: plain **Gold**, or **Class of the buff**, the
color of the class that casts it (white for a Priest's buff, orange for a Druid's, and so on), so
you can tell who to ask. A buff you added by name has no known class and keeps the gold ring.

**Layout** is how several missing buffs sit side by side: **Row**, or **Overlapped**, where each
icon covers the edge of the last (the spacing setting is ignored then).

**Most icons shown** caps the group. When more buffs are missing than the cap, the last slot
becomes a red **+N** chip standing for the rest. At the top of the slider there is no limit.

**Black outline** (Square and Round) lays a black edge along the icon's border, from 1 to 4 pixels
thick, laid over the icon's edge: the art keeps its size and only its outermost pixels are covered,
square or round. A small icon holds it to a quarter of its size. The gold ring has an edge of its
own, so it has no outline option.

**Reset position and look** (two clicks,
no popup) puts those back to their defaults and leaves the buffs you track alone.

Settings saved by an earlier version carry over: the old *right* and *left* become
*Right of the level text* and *Left of the health bar*, and *centered* becomes *Custom*
with its offsets unchanged.

## Buffs about to expire

With **Also flag buffs about to expire** on, a buff that has less than the warning
threshold left (5 minutes by default) is shown too, with the minutes remaining on it, so
it reads differently from a buff that was never cast at all. **Show them as** picks how:

- **Amber tint** (the default): the icon turns amber.
- **Faded icon**: the icon keeps its colour and becomes more transparent instead, by
  the **Faded opacity** you set (50% by default).
- **Countdown sweep**: the icon stays as it is, and a clock-style wedge darkens it as the time
  runs out. The wedge lies between the icon and its ring or outline, so the ring stays clean. The label turns amber, then orange under two minutes and red under one, and counts
  seconds in the last minute.

To see any of these without waiting for a real buff to run down, press **Test expiring look** (or
type `/ub test`). For 20 seconds the first buff you track counts down from a full warning window to
nothing, in the preview and on every friendly player's nameplate in view.

Only the icon fades: the minutes-left label stays fully opaque, so it is always
readable. The preview includes an expiring example, so you can
see the effect as you change it. A buff whose remaining time this client will not report is never flagged, for the
same reason an unreadable buff is never drawn as missing.

## Why buffs are matched by name

Every listed buff matches on its **name**, not a spell ID, and that is deliberate. On
Vanilla-era content a buff is a *family* of per-rank spell IDs — Power Word: Fortitude
alone is 1243, 1244, 1245, 2791, 10937 and 10938 — so a single ID would only ever match
one rank and would report everyone else as unbuffed.

Names also let an entry carry the group version, because somebody under **Prayer of
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

The usual reason is simply that **friendly player nameplates are switched off** — the
addon says so once at login if it detects that.

Another nameplate addon, or a UI suite's own nameplates, can also replace the default
plates in a way that hides the icons. Try with the other addon disabled.

## License

MIT. See [LICENSE](LICENSE).
