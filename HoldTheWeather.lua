-- Hold the Weather: a Frost Mage warning for WoW: Forever. Written from scratch (MIT).
--
-- Why: the official Nov 13, 2026 hotfix says "Frost Nova is now correctly broken by damage from procs and damage from
-- Blizzard." Channelling your own Blizzard into your own Frost Nova breaks it. This addon flashes one warning when you
-- start that channel while your Nova may still be holding, and stays quiet otherwise. It never casts, targets or moves.
--
-- What it can see (picked at runtime, never guessed; /frost weather debug prints all of it):
--   Blizzard channel: the player's own UNIT_SPELLCAST_CHANNEL_START / _STOP. The docs flag these
--     SecretWhenUnitSpellCastRestricted. If the client hides the spell ID (or flags Blizzard's casts always secret via
--     C_Secrets.GetSpellCastSecrecy), the box says "can't see your casts here" instead of warning.
--   Frost Nova window:
--     "aura": the Frost Nova root on your target can be read (the spell is never-secret, or restrictions are off). Its
--             presence and expiry are used; when it leaves your target the window ends.
--     "cast": otherwise, the window starts at your own Frost Nova UNIT_SPELLCAST_SUCCEEDED and lasts the spell's full
--             duration from client data (SpellMisc DurationIndex 31 = 8000 ms for all four ranks, build 1.60.1.70862).
--             Nova is "up to 8 sec": damage can end it early, so the box says "may still be up", never a countdown.
--     "none": neither is visible: the box says so.
-- Spell IDs: SpellName + SkillLineAbility (Mage, SkillLine 6 Frost), builds 1.60.1.70862 and 70888.
local ADDON, ns = ...
local C, Core, FS = ns.Compat, ns.Core, ns.FrostSuite
local L = Core.L

local HW = {}
KennyHoldTheWeather = HW
ns.HW = HW
local KEY = "HoldTheWeather"
local SCHEMA = 1

HW.NOVA = { [122] = 1, [865] = 2, [6131] = 3, [10230] = 4 }
HW.BLIZZARD = { [10] = 1, [6141] = 2, [8427] = 3, [10185] = 4, [10186] = 5, [10187] = 6 }
-- Trainer levels: SpellLevels.BaseLevel, build 1.60.1.71037 (Frost Nova 122 = 10, Blizzard 10 = 20).
HW.NEEDS = { { name = L["Frost Nova"], level = 10, spells = HW.NOVA }, { name = L["Blizzard"], level = 20, spells = HW.BLIZZARD } }
HW.NOVA_SECONDS = 8
HW.PREVIEW_SECONDS = 4
HW.DEFAULTS = {}

local db, settings, row
local migrations = {} -- schema 1 is the first release

-- state
HW.novaUntil = nil      -- GetTime() when the Nova window ends (cast timer or aura expiry)
HW.novaSource = nil     -- "cast" or "aura": what set novaUntil
HW.auraOnTarget = false -- the Nova root was seen on the current target
HW.channeling = false   -- the player is channelling Blizzard (from the player's own channel events)
HW.warning = false
HW.preview = false
HW.hiddenEvents = 0     -- player cast/channel events whose spell ID came back secret
HW.plainBlizzard = 0    -- Blizzard channel starts seen with a plain spell ID
HW.known = true
HW.secrecy = {}         -- aura secrecy per Nova rank
HW.castSecrecy = {}     -- cast secrecy per spell
HW.modes = { nova = "cast", blizzard = "cast" }
HW.restricted = nil
local gen = 0

local function now() return C.Clock() end
local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, ...)
  if not ok or C.IsSecret(v) then return nil end
  return v
end

function HW.DB() return db end
function HW.Settings() return settings end

-- ---------- detection ----------
function HW.EvaluateModes()
  local S = C_Secrets
  HW.restricted = S and call(S.HasSecretRestrictions)
  if HW.restricted == nil and type(S) ~= "table" and issecretvalue == nil then HW.restricted = false end
  local auraOK = false
  local canRead = C_UnitAuras ~= nil and type(C_UnitAuras.GetUnitAuraBySpellID) == "function"
  for id in pairs(HW.NOVA) do
    local lvl = S and call(S.GetSpellAuraSecrecy, id)
    HW.secrecy[id] = type(lvl) == "number" and lvl or nil
    if canRead and (HW.restricted == false or HW.secrecy[id] == 0) then auraOK = true end
    local c = S and call(S.GetSpellCastSecrecy, id)
    HW.castSecrecy[id] = type(c) == "number" and c or nil
  end
  local novaCastOK = false
  for id in pairs(HW.NOVA) do if HW.castSecrecy[id] ~= 1 then novaCastOK = true end end
  local blizzOK = false
  for id in pairs(HW.BLIZZARD) do
    local c = S and call(S.GetSpellCastSecrecy, id)
    HW.castSecrecy[id] = type(c) == "number" and c or nil
    if HW.castSecrecy[id] ~= 1 then blizzOK = true end
  end
  -- hidden events this session and no plain Blizzard channel since: the client is hiding the player's casts
  if HW.hiddenEvents > 0 and HW.plainBlizzard == 0 then blizzOK = false end
  HW.modes.blizzard = blizzOK and "cast" or "none"
  HW.modes.nova = auraOK and "aura" or ((novaCastOK and not (HW.hiddenEvents > 0 and HW.plainBlizzard == 0)) and "cast" or "none")
  return HW.modes
end

function HW.CanWarn() return HW.modes.blizzard ~= "none" and HW.modes.nova ~= "none" end

-- Not a Mage: hidden. A Mage without Frost Nova or Blizzard yet: HW.need names the first one missing (the box says when
-- to learn it). The client can't say (no C_SpellBook.IsSpellKnown): assumed known, debug says so.
function HW.CheckKnown()
  if C.InCombat() then return HW.known end -- spellbook only re-read out of combat
  HW.need = FS.IsMage() and FS.Missing(HW.NEEDS) or nil
  HW.known = FS.IsMage() and HW.need == nil
  if HW.known then FS.Learned(KEY) end
  return HW.known
end

-- ---------- Nova window ----------
local function schedule(t)
  gen = gen + 1
  local mine = gen
  local wait = t - now()
  if wait < 0 then wait = 0 end
  C_Timer.After(wait + 0.05, function() if mine == gen then HW.Update() end end)
end

function HW.NovaUp()
  return HW.novaUntil ~= nil and now() < HW.novaUntil
end

-- Read the Nova root on the target, only when the client lets us (mode "aura"). Returns true if the read was usable.
function HW.ReadTargetAura()
  if HW.modes.nova ~= "aura" then return false end
  if UnitExists and not UnitExists("target") then return false end
  local found
  for id in pairs(HW.NOVA) do
    local ok, a = pcall(C_UnitAuras.GetUnitAuraBySpellID, "target", id)
    if ok and not C.IsSecret(a) and type(a) == "table" then found = a; break end
  end
  if found then
    local okE, exp = pcall(function() return found.expirationTime end)
    exp = okE and C.SafeNumber(exp) or nil
    HW.auraOnTarget = true
    if exp and exp > 0 then HW.novaUntil, HW.novaSource = exp, "aura"; schedule(exp) end
  elseif HW.auraOnTarget then
    -- the root was on the target and is gone (ran out or broke): the window is over
    HW.auraOnTarget = false
    HW.novaUntil, HW.novaSource = now(), "aura"
  end
  return true
end

function HW.OnNova()
  HW.novaUntil, HW.novaSource = now() + HW.NOVA_SECONDS, "cast"
  HW.auraOnTarget = false
  schedule(HW.novaUntil)
  HW.ReadTargetAura()
end

-- ---------- events ----------
local function hidden()
  HW.hiddenEvents = HW.hiddenEvents + 1
  local before = HW.CanWarn()
  HW.EvaluateModes()
  if before and not HW.CanWarn() and not HW.toldHidden then
    HW.toldHidden = true
    Core.Print(L["The client is hiding your casts here, so Hold the Weather can't warn you. /frost weather debug shows why."])
  end
  HW.Update()
end

function HW.OnSpellcast(unit, _, spellID)
  if unit ~= "player" then return end
  if C.IsSecret(spellID) then return hidden() end
  if HW.NOVA[spellID] then HW.OnNova(); HW.Update() end
end

function HW.OnChannelStart(unit, _, spellID)
  if unit ~= "player" then return end
  if C.IsSecret(spellID) then return hidden() end
  if HW.BLIZZARD[spellID] then
    HW.plainBlizzard = HW.plainBlizzard + 1
    if HW.modes.blizzard == "none" or HW.modes.nova == "none" then HW.EvaluateModes() end
    HW.channeling = true
    HW.ReadTargetAura()
    HW.Update()
  end
end

function HW.OnChannelStop(unit, _, spellID)
  if unit ~= "player" then return end
  -- any stop of the player's channel ends it, even with a hidden spell ID: a stop can only end a channel
  if C.IsSecret(spellID) or HW.BLIZZARD[spellID] then HW.channeling = false; HW.Update() end
end

function HW.OnAura(unit)
  if unit ~= "target" then return end
  if HW.ReadTargetAura() then HW.Update() end
end

function HW.OnTargetChanged()
  HW.auraOnTarget = false
  if HW.ReadTargetAura() then HW.Update() end
end

-- ---------- the one warning ----------
function HW.ShouldWarn()
  if HW.preview then return true end
  return HW.known and HW.CanWarn() and HW.channeling and HW.NovaUp()
end

function HW.Update()
  local warn = HW.ShouldWarn() and true or false
  if warn and not HW.warning then
    HW.warning = true
    if FS.RequestFlash(KEY, "HOLD") then FS.PlaySound(KEY) end
  elseif not warn and HW.warning then
    HW.warning = false
    FS.EndFlash(KEY)
  end
  if row then HW.Paint() end
  return warn
end

-- Names what is actually missing: your casts (Blizzard channel hidden) or only the Frost Nova window.
function HW.StatusText()
  if HW.modes.blizzard == "none" then return L["can't see your casts here"], "Mist" end
  if HW.modes.nova == "none" then return L["can't see your Frost Nova here"], "Mist" end
  if HW.NovaUp() then return L["Nova up"], "Snow" end
  return L["clear"], "Mist"
end

function HW.Paint()
  if not HW.known and not HW.preview then
    if HW.need then FS.NotYet(KEY, HW.need) else FS.State(KEY, "hidden") end
    return
  end
  local text, color = HW.StatusText()
  FS.Status(KEY, text, color)
  if HW.warning then
    FS.Headline(KEY, L["HOLD THE WEATHER!"], "StopPink")
    FS.State(KEY, "active")
  else
    FS.Headline(KEY, "", "Mist")
    FS.State(KEY, "idle")
  end
end

-- Out of combat preview of the warning (and its sound), then back to normal.
function HW.Test()
  if C.InCombat() then Core.Print(L["The preview only runs out of combat."]); return false end
  HW.preview = true
  HW.Update()
  C_Timer.After(HW.PREVIEW_SECONDS, function() HW.preview = false; HW.Update() end)
  return true
end

function HW.DetectionLines()
  HW.EvaluateModes()
  local S = C_Secrets
  local out = {
    ("Frost Nova window: %s  (aura = root on your target read, cast = %d s timer from your Nova, none = can't see)"):format(HW.modes.nova, HW.NOVA_SECONDS),
    ("Blizzard channel: %s  (cast = your channel start/stop seen, none = hidden by the client)"):format(HW.modes.blizzard),
    ("secret restrictions: %s, auras secret now: %s, in combat: %s"):format(tostring(HW.restricted),
      tostring(S and call(S.ShouldAurasBeSecret)), tostring(C.InCombat())),
    ("knows Frost Nova and Blizzard (Mage): %s%s%s"):format(tostring(HW.known), HW.need and (", not yet: " .. HW.need.name) or "",
      (C_SpellBook and C_SpellBook.IsSpellKnown) and "" or " (C_SpellBook.IsSpellKnown missing: assumed)"),
    ("events: %d hidden, %d plain Blizzard channel starts; channelling now: %s; Nova window: %s"):format(HW.hiddenEvents,
      HW.plainBlizzard, tostring(HW.channeling), HW.NovaUp() and (tostring(HW.novaSource) .. ", may still be up") or "closed"),
    "procs and other damage can also break Frost Nova (official Nov 13 hotfix); this addon can't see those.",
  }
  local ids = {}
  for id in pairs(HW.NOVA) do ids[#ids + 1] = id end
  for id in pairs(HW.BLIZZARD) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    out[#out + 1] = ("  %d %s %d: aura secrecy %s, cast secrecy %s (0 = never secret)"):format(id,
      HW.NOVA[id] and "Frost Nova" or "Blizzard", HW.NOVA[id] or HW.BLIZZARD[id],
      tostring(HW.NOVA[id] and HW.secrecy[id] or "-"), tostring(HW.castSecrecy[id]))
  end
  return out
end

function HW.Slash(msg)
  local cmd, a = (msg or ""):lower():match("^(%S*)%s*(.-)$")
  if cmd == "test" then HW.Test()
  elseif cmd == "sound" and (a == "on" or a == "off") then
    db.sound = a == "on"; Core.Print(L["sound:"] .. " " .. a)
  elseif cmd == "debug" then for _, l in ipairs(HW.DetectionLines()) do Core.Print(l) end
  else
    Core.Print("/frost weather test | sound on|off | debug")
  end
end

-- ---------- wiring ----------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
for _, e in ipairs({ "PLAYER_LOGIN", "SPELLS_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED" }) do ev:RegisterEvent(e) end
ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
ev:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
ev:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
ev:RegisterUnitEvent("UNIT_AURA", "target")

local function refresh() HW.CheckKnown(); HW.EvaluateModes(); HW.Update() end
local handlers = {
  PLAYER_LOGIN = refresh,
  SPELLS_CHANGED = refresh,
  PLAYER_REGEN_DISABLED = function() HW.EvaluateModes(); HW.Update() end,
  PLAYER_REGEN_ENABLED = refresh,
  PLAYER_TARGET_CHANGED = HW.OnTargetChanged,
  UNIT_SPELLCAST_SUCCEEDED = HW.OnSpellcast,
  UNIT_SPELLCAST_CHANNEL_START = HW.OnChannelStart,
  UNIT_SPELLCAST_CHANNEL_STOP = HW.OnChannelStop,
  UNIT_AURA = HW.OnAura,
}

ev:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= ADDON then return end
    db = Core.Migrate(KennyHoldTheWeatherDB, migrations, SCHEMA)
    KennyHoldTheWeatherDB = db
    settings = Core.Settings(db.settings, HW.DEFAULTS)
    row = FS.Register(KEY, db, { title = L["Hold the Weather"], slash = HW.Slash, help = "test | sound on|off | debug",
      debug = Core.PrintDebug, refresh = refresh })
    HW.row = row
    Core.SafeCall("refresh", refresh)
    return
  end
  local h = handlers[event]
  if h and db then Core.SafeCall(event, h, ...) end
end)

Core.Setup({ cmd = "/frost weather",
  required = { "C_Timer.After", "PlaySoundFile" },
  optional = { "C_UnitAuras.GetUnitAuraBySpellID", "C_Secrets.HasSecretRestrictions", "C_Secrets.GetSpellAuraSecrecy",
    "C_Secrets.GetSpellCastSecrecy", "C_Secrets.ShouldAurasBeSecret", "C_SpellBook.IsSpellKnown" },
  db = function() return db end,
  firstRun = { L["Hold the Weather is ready: it warns when your Blizzard would break your own Frost Nova. /frost weather test shows it."] },
  debugLines = function() return HW.DetectionLines() end })
