# Unbuffed

**Flags friendly player nameplates that are missing the buffs you track.**

[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
![Version](https://img.shields.io/badge/version-1.0.0-brightgreen)
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

Appearance is configurable: icon size, opacity, horizontal and vertical offset, and
whether the row sits to the right or the left of the nameplate.

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
