-- Frost Suite: the shared FrostSuite-1.0 dock, flash rule, saved position and /frost router (identical in every addon).
package.path = "tests/?.lua;" .. package.path
local W = require("mock_wow"); W.install()
local check = W.check
local toc = io.popen("ls *.toc"):read("*l")
local name = toc:gsub("%.toc$", "")
W.loadAddon(".", name)
W.fire("PLAYER_LOGIN")
local FS = _G.FrostSuite_1_0
check(type(FS) == "table" and FS.minor == 1, "library installed as FrostSuite_1_0 r1")
check(FS.rows[name] ~= nil, "the addon registered its own row")
check(SLASH_FROSTSUITE1 == "/frost" and SlashCmdList.FROSTSUITE ~= nil, "/frost registered")

-- Same-version copy loads again (a second addon): returns early and keeps every row.
local before = FS.rows[name]
assert(loadfile("Libs/FrostSuite/FrostSuite.lua"))("Other", {})
check(_G.FrostSuite_1_0 == FS and FS.rows[name] == before, "equal MINOR copy keeps the table and rows")
-- An older copy never downgrades; a newer one replaces functions but keeps state.
FS.minor = 99
local oldLayout = FS.Layout
assert(loadfile("Libs/FrostSuite/FrostSuite.lua"))("Older", {})
check(FS.Layout == oldLayout and FS.minor == 99, "older copy does not replace a newer one")
FS.minor = 0
assert(loadfile("Libs/FrostSuite/FrostSuite.lua"))("Newer", {})
check(FS.minor == 1 and FS.rows[name] == before, "newer copy upgrades in place and keeps rows")

-- Fake the other six rows so the dock and flash rule can be checked with the whole suite loaded.
local dbs = {}
for key in pairs(FS.ADDONS) do
  if not FS.rows[key] then dbs[key] = {}; FS.Register(key, dbs[key], { title = key }) end
end
for _, key in ipairs(FS.order) do FS.rows[key].state = "idle" end
FS.Layout()
check(#FS.order == 7, "seven rows docked")
check(FS.order[1] == "HoldTheWeather" and FS.order[7] == "ScrollCall", "dock order follows FS.ADDONS order")
check(FS.rows.HoldTheWeather.after == "anchor" and FS.rows.EightSecondArgument.after == "HoldTheWeather", "rows chain top to bottom")
check(FS.rows.HoldTheWeather.h == 28 and FS.rows.ShatterHappens.h == 96, "idle heights: strip 28, Shatter 96")
check(FS.lock.owner == "HoldTheWeather", "padlock on the top row")
-- A hidden row takes no slot; the next one moves up and takes the padlock.
FS.rows.HoldTheWeather.state = "hidden"; FS.Layout()
check(FS.rows.EightSecondArgument.after == "anchor" and FS.lock.owner == "EightSecondArgument", "hidden row leaves no gap")
FS.rows.HoldTheWeather.state = "idle"; FS.Layout()

-- Combat: five combat rows go to active height, utility rows hide; heights frozen until 2 s after combat.
W.combat = true
W.fire("PLAYER_REGEN_DISABLED")
check(FS.rows.HoldTheWeather.h == 50 and FS.rows.BarrierReef.h == 64 and FS.rows.ShatterHappens.h == 78, "combat heights")
check(FS.rows.WaterBill.after == nil and FS.rows.ScrollCall.after == nil, "utility rows hidden in combat")
FS.State("BarrierReef", "active")
check(FS.layoutPending == nil, "no relayout in combat")
W.combat = false
W.fire("PLAYER_REGEN_ENABLED")
check(FS.rows.WaterBill.after == nil, "utility rows still hidden right after combat")
W.advance(2.1)
check(FS.rows.WaterBill.after ~= nil and FS.rows.HoldTheWeather.h == 28, "relayout 2 s after combat")

-- Flash rule: one glow, highest priority wins, lower is denied (no queue), utility rows never flash.
W.advance(10)
check(FS.RequestFlash("ShatterHappens", "PULSE") == true, "Shatter pulse wins when nothing glows")
check(FS.RequestFlash("BarrierReef", "PULSE") == true and FS.Glowing() == "BarrierReef", "Reef outranks Shatter")
check(FS.rows.ShatterHappens.glow.alpha == 0, "outranked glow drops to 0 at once")
check(FS.RequestFlash("ShatterHappens", "PULSE") == false, "lower priority denied")
check(FS.RequestFlash("HoldTheWeather", "HOLD") == true and FS.rows.BarrierReef.glow.alpha == 0, "Hold the Weather outranks all")
check(FS.RequestFlash("ConeOfPlenty", "PULSE") == false, "Cone denied while Hold glows")
check(FS.RequestFlash("WaterBill") == false and FS.RequestFlash("ScrollCall") == false, "utility rows never flash")
check(FS.RequestFlash("EightSecondArgument", "TEXT") == false, "TEXT style never glows")
FS.EndFlash("HoldTheWeather")
check(FS.Glowing() == nil and FS.rows.HoldTheWeather.glow.alpha == 0, "EndFlash clears the HOLD glow")
check(FS.RequestFlash("BarrierReef", "PULSE") == false, "same row may not pulse twice within 3 s")
W.advance(3.1)
check(FS.RequestFlash("BarrierReef", "PULSE") == true, "pulse allowed again after 3 s")
local r = FS.rows.BarrierReef
W.clock = W.clock + 0.6; r.scripts.OnUpdate(r)
check(FS.Glowing() == nil and r.glow.alpha == 0, "pulse fades out after 0.5 s and frees the glow")
-- Sounds: only the winner, one per 4 s, own switch.
W.sounds = {}
FS.RequestFlash("HoldTheWeather", "HOLD")
check(FS.PlaySound("HoldTheWeather") == true and W.sounds[1][1] == 569310, "winner plays its in-game sound")
check(FS.PlaySound("BarrierReef") == false, "a row without the glow is silent")
FS.EndFlash("HoldTheWeather"); W.advance(1)
FS.RequestFlash("HoldTheWeather", "HOLD")
check(FS.PlaySound("HoldTheWeather") == false, "one suite sound per 4 s")
FS.EndFlash("HoldTheWeather")
W.advance(5)
FS.rows.HoldTheWeather.db.sound = false
FS.RequestFlash("HoldTheWeather", "HOLD")
check(FS.PlaySound("HoldTheWeather") == false, "per-addon sound switch honoured")
FS.rows.HoldTheWeather.db.sound = true
FS.EndFlash("HoldTheWeather")
check(dbs.ConeOfPlenty and dbs.ConeOfPlenty.sound == false, "Cone sound off by default")

-- Saved position, lock and scale: written to every addon's db.suite, newest stamp wins.
W.now = W.now + 100
FS.SetLocked(true)
local all = true
for _, key in ipairs(FS.order) do local s = FS.rows[key].db.suite; all = all and s.locked == true end
check(all and FS.IsLocked(), "lock written to every row's db.suite")
check(FS.SetScale(2) == 1.4 and FS.SetScale(0.5) == 0.8 and FS.SetScale("1.13") == 1.1, "scale clamped 0.8-1.4, step 0.1")
dbs.ScrollCall.suite = { point = "TOP", relPoint = "TOP", x = 1, y = 2, locked = false, scale = 1.2, stamp = W.now + 50 }
check(FS.Suite().scale == 1.2 and FS.IsLocked() == false, "newest db.suite wins")
FS.ResetPosition()
local s = FS.Suite()
check(s.point == "TOPLEFT" and s.relPoint == "CENTER" and s.x == 220 and s.y == 160, "reset to the default spot")

-- /frost router.
W.prints = {}
SlashCmdList.FROSTSUITE("lock")
check(FS.IsLocked() and W.printed("locked"), "/frost lock")
SlashCmdList.FROSTSUITE("unlock")
check(not FS.IsLocked(), "/frost unlock")
W.prints = {}
SlashCmdList.FROSTSUITE("")
check(W.printed("/frost " .. FS.ADDONS[name].cmd), "/frost lists the addon's subcommand")
W.prints = {}
SlashCmdList.FROSTSUITE("debug")
check(W.printed("FrostSuite-1.0 r1"), "/frost debug prints the dock state")
W.done(name .. " frostsuite")
