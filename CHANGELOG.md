# Changelog

## 1.0.1 (Nov 20, 2026)

- Layout fixes (FrostSuite-1.0 r4, shared by the suite): a status too long to sit beside the title moves to its own line instead of running into it, and box heights fit their text.
- Low-level Mages (FrostSuite-1.0 r6, shared by the suite): until you have Frost Nova and Blizzard the box shows one calm line, e.g. `Learn Frost Nova at level 10`, with a small **Hide until I learn** button (saved per character). It steps aside in combat and comes back by itself as soon as you learn them (checked when you learn a spell, level up, change talents or leave combat).

## 1.0.0 (Nov 20, 2026)

First release, part of the Frost Suite.

- Flashes `HOLD THE WEATHER!` when you start channelling Blizzard while your own Frost Nova may still be holding (Blizzard
  breaks Frost Nova since the Nov 13, 2026 hotfix). The warning clears when you stop the channel or the Nova window ends.
- The Nova window comes from the Frost Nova root on your target when the game lets addons read it, otherwise from your own
  Frost Nova cast plus its 8-second duration from the game's data. Nova can break early from damage, so the box says
  "Nova up" (it may still be up), never a countdown.
- If the game hides your casts, the box says `can't see your casts here` and chat says it once; if only your Frost Nova is hidden, it says `can't see your Frost Nova here`. It never warns on a guess.
- `/frost weather test` shows the warning out of combat; `/frost weather sound on|off`; `/frost weather debug`.
- Docks with the other Frost Suite boxes (one column, one padlock, one glow at a time; this warning has top priority).
