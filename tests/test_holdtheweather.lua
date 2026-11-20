-- Hold the Weather: the warning, the Nova window and honest failure, against realistic secret-value rules.
package.path = "tests/?.lua;" .. package.path
local W = require("mock_wow"); W.install()
local S = W.S
local check = W.check
local ns = W.loadAddon(".", "HoldTheWeather")
W.fire("PLAYER_LOGIN")
local HW, FS = ns.HW, _G.FrostSuite_1_0
local row = FS.rows.HoldTheWeather
local NOVA, BLIZZ = 10230, 10187

local function reset()
  W.combat = false; W.fire("PLAYER_REGEN_ENABLED"); W.advance(30)
  S.install(W); W.sounds = {}; W.prints = {}
  HW.hiddenEvents, HW.plainBlizzard, HW.channeling, HW.novaUntil, HW.toldHidden = 0, 0, false, nil, nil
  FS.lastSound = -100; FS.EndFlash("HoldTheWeather")
  W.fire("PLAYER_LOGIN")
end
local function fight() W.combat = true; W.fire("PLAYER_REGEN_DISABLED") end

-- Static data: every rank, Nova duration from client data.
local n, b = 0, 0
for _ in pairs(HW.NOVA) do n = n + 1 end
for _ in pairs(HW.BLIZZARD) do b = b + 1 end
check(n == 4 and b == 6 and HW.NOVA_SECONDS == 8, "4 Nova ranks, 6 Blizzard ranks, 8 s Nova")
check(row.statusText == "clear" and row.state == "idle", "idle strip says clear")

-- 1. Strict client (auras secret in combat, casts plain): cast mode, the warning works from the timer.
reset(); fight()
check(HW.modes.nova == "cast" and HW.modes.blizzard == "cast", "strict client: Nova by cast timer, Blizzard by cast")
S.cast(NOVA)
check(HW.NovaUp() and row.statusText == "Nova up", "Nova cast opens the window")
check(not HW.warning, "no warning without Blizzard")
S.channelStart(BLIZZ)
check(HW.warning and row.headText == "HOLD THE WEATHER!" and FS.Glowing() == "HoldTheWeather", "Blizzard into Nova: warning + glow")
check(#W.sounds == 1 and W.sounds[1][1] == 569310, "one in-game sound (frostnovastateend)")
S.channelStop(BLIZZ)
check(not HW.warning and FS.Glowing() == nil, "stopping the channel clears it")
S.channelStart(BLIZZ)
check(HW.warning, "a new channel inside the window warns again")
check(#W.sounds == 1, "no second sound within 4 s")
W.advance(8.1)
check(not HW.warning and not HW.NovaUp() and row.statusText == "clear", "the window closes after 8 s, even mid-channel")
S.channelStop(BLIZZ)
-- Blizzard first, then Nova: still a self-break.
S.channelStart(BLIZZ); S.cast(NOVA)
check(HW.warning, "Nova cast during a Blizzard channel warns too")
S.channelStop(BLIZZ)
check(S.reads == 0, "strict client: no aura reads at all (cast mode never asks)")
-- Other units and other spells are ignored.
W.advance(10)
S.cast(NOVA, "party1"); S.channelStart(BLIZZ, "party1")
check(not HW.warning and not HW.NovaUp(), "other units' casts ignored")
S.cast(116); S.channelStart(5143)
check(not HW.warning and not HW.NovaUp() and not HW.channeling, "other spells ignored")
S.channelStop(5143)

-- 2. Never-secret Nova aura: aura mode; the root leaving the target ends the window early.
reset()
S.never[NOVA] = true; W.target = "mob"
W.fire("PLAYER_LOGIN"); fight()
check(HW.modes.nova == "aura", "never-secret Nova aura: aura mode")
S.cast(NOVA); S.unitGain("target", NOVA, 0, 6)
check(HW.novaSource == "aura" and math.abs(HW.novaUntil - (W.clock + 6)) < 0.01, "aura expiry replaces the 8 s timer")
S.channelStart(BLIZZ)
check(HW.warning, "warning in aura mode")
S.unitDrop("target", NOVA)
check(not HW.warning and not HW.NovaUp(), "root broke on the target: window over, warning gone")
S.channelStop(BLIZZ)

-- 3. Secret auras do not leak: with the aura on the target but secret, the addon uses the timer and never reads values.
reset(); W.target = "mob"; fight()
S.cast(NOVA); S.unitGain("target", NOVA, 0, 3)
check(HW.modes.nova == "cast" and HW.novaSource == "cast", "secret aura: stays on the cast timer")
check(math.abs(HW.novaUntil - (W.clock + 8)) < 0.01, "secret aura: the 3 s aura did not leak into the timer")

-- 4. Client hides the player's casts in combat: fail visibly, never warn on a guess.
reset(); S.castSecretInCombat = true; fight()
S.cast(NOVA); S.channelStart(BLIZZ)
check(not HW.warning, "no warning from hidden casts")
check(HW.modes.blizzard == "none" and row.statusText == "can't see your casts here", "box says it can't see casts")
check(W.printed("can't warn you"), "chat says so once")
local p = #W.prints
S.cast(NOVA)
check(#W.prints == p, "said only once")
local dbg = table.concat(HW.DetectionLines(), "\n")
check(dbg:find("Blizzard channel: none", 1, true) and dbg:find("procs and other damage", 1, true), "debug explains")
-- Always-secret cast flag on Blizzard: mode none from the start.
reset(); for id in pairs(HW.BLIZZARD) do S.castAlways[id] = true end
W.fire("PLAYER_LOGIN")
check(HW.modes.blizzard == "none" and not HW.CanWarn(), "always-secret Blizzard casts: none from login")
check(FS.rows.HoldTheWeather.statusText == "can't see your casts here", "status names the hidden casts")
-- Only the Nova window is missing (Nova casts always secret, Nova aura secret): the status says that, not "casts".
reset(); for id in pairs(HW.NOVA) do S.castAlways[id] = true end
W.fire("PLAYER_LOGIN")
check(HW.modes.nova == "none" and HW.modes.blizzard == "cast", "Nova hidden, Blizzard visible")
check(FS.rows.HoldTheWeather.statusText == "can't see your Frost Nova here", "status names the missing Nova window")

-- 5. Not a Mage: the row takes no slot. Spells not known: one calm line (tests/test_lowlevel.lua has the details).
reset(); W.class = "WARRIOR"; W.fire("SPELLS_CHANGED")
check(row.state == "hidden" and not HW.known, "non-Mage: row hidden")
W.class = nil; W.known = { [122] = true }; W.fire("SPELLS_CHANGED")
check(row.state == "learn" and row.learnText.text_ == "Learn Blizzard from your trainer", "Nova known but no Blizzard: says to learn it (r5)")
W.known = nil; W.fire("SPELLS_CHANGED")
check(row.state ~= "hidden", "both known: shown")

-- 6. /frost weather test: preview out of combat only; never casts anything.
reset()
SlashCmdList.FROSTSUITE("weather test")
check(HW.warning and row.headText == "HOLD THE WEATHER!", "preview shows the warning")
W.advance(4.1)
check(not HW.warning, "preview ends")
fight(); W.prints = {}
SlashCmdList.FROSTSUITE("weather test")
check(not HW.warning and W.printed("out of combat"), "no preview in combat")
reset()
SlashCmdList.FROSTSUITE("weather sound off")
check(HW.DB().sound == false, "/frost weather sound off")
SlashCmdList.FROSTSUITE("weather sound on")
-- 7. Flash rule: a higher-priority glow can't exist; Hold the Weather takes the glow from any other row.
reset()
FS.Register("BarrierReef", {}, { title = "Reef" })
W.advance(5)
FS.RequestFlash("BarrierReef", "PULSE")
fight(); S.cast(NOVA); S.channelStart(BLIZZ)
check(FS.Glowing() == "HoldTheWeather", "Hold the Weather takes the glow from Barrier Reef")
S.channelStop(BLIZZ)
-- Nothing in the addon casts, targets or moves.
local src = io.open("HoldTheWeather.lua"):read("*a")
check(not src:find("CastSpell") and not src:find("TargetUnit") and not src:find("MoveForward") and not src:find("SpellStopCasting"),
  "no cast, target or movement calls")
W.done("HoldTheWeather")
