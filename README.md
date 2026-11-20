# Hold the Weather

A tiny Frost Mage warning for **WoW: Forever** (Interface 16001). Version 1.0.0. Part of Kenny's Frost Suite, and it works alone.

Since the official **Nov 13, 2026 hotfix**, "Frost Nova is now correctly broken by damage from procs and damage from Blizzard."
Channelling your own Blizzard into your own Frost Nova lets the pack go. Hold the Weather stays quiet until you do that, then
shows one line:

> **HOLD THE WEATHER!**

It clears as soon as you stop the channel or the Nova window ends. It never casts, targets or moves anything. You press every
button.

## What the game lets it see

WoW: Forever hides some combat data from addons. Hold the Weather picks what it can use when you log in and at the start of
each fight, and tells you when it can't see something:

| Thing | How it's read | When the game hides it |
| --- | --- | --- |
| Your Blizzard channel | your own channel start and stop events | the box says `can't see your casts here` and chat says it once; no warning |
| Frost Nova window | the Nova root on your target, if the game lets addons read it in combat | it uses your Nova cast plus the spell's full 8 seconds (from the game's data); if your Nova casts are hidden too, the box says `can't see your Frost Nova here` |

Frost Nova lasts **up to** 8 seconds, and damage can end it sooner. So with the timer the box says `Nova up` (it may still be
up) and never shows a countdown. Procs and other damage can also break Nova. The addon can't see those, because the game
doesn't give addons a combat log.

## Commands

The Frost Suite has no per-addon slash commands, only `/frost <sub>`. That keeps the risk of clashing with other addons low.

- `/frost weather test`: preview the warning (out of combat)
- `/frost weather sound on|off`: the warning sound (the game's own Frost Nova fade sound)
- `/frost weather debug`: what the game lets the addon see right now, rank by rank
- `/frost lock | unlock | scale 0.8-1.4 | reset | debug`: the shared dock

## Frost Suite

With other Frost Suite addons loaded, the boxes stack in one column under one anchor, with one padlock, one scale and only
one glow at a time. Hold the Weather has the top priority, because it is the only "stop doing that now" prompt.

## Files and checks

- `tests/run.sh <wow-ui-source>`: syntax, luacheck, locale, mock-client tests (with the game's secret-value rules) and checks
  against Blizzard's API docs
- `tools/verify_unit_events.py <wow-ui-source>`: unit events exist in the docs
- `tools/check_suite_lib.sh`: this copy of FrostSuite-1.0 matches the suite's canonical copy
- `tools/verify_media.sh`: every built-in sound and texture exists in the game client

Spell IDs come from the game's own data tables (SpellName, SkillLineAbility, SpellMisc) for builds 1.60.1.70862 and 70888.

MIT licence. Uses the game's own sounds and textures only.
