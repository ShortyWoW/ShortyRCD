-- ShortyRCD.lua (core/glue)

local ADDON_NAME = ...
ShortyRCD = ShortyRCD or {}
ShortyRCD.ADDON_NAME = ADDON_NAME
local version = C_AddOns.GetAddOnMetadata(ShortyRCD.ADDON_NAME, "Version")
ShortyRCD.VERSION = version or "DEV"

ShortyRCDDB = ShortyRCDDB or nil

ShortyRCD.DEFAULTS = {
  debug = false,
  locked = false,
  frame = {
    point = { "CENTER", "UIParent", "CENTER", 0, 0 },
  },
  tracking = {
    -- Populated lazily: tracking[classToken][spellID] = true/false
  }
}

-- ---------- Utils ----------
local function DeepCopy(src)
  if type(src) ~= "table" then return src end
  local dst = {}
  for k, v in pairs(src) do dst[k] = DeepCopy(v) end
  return dst
end

local function ApplyDefaults(dst, defaults)
  for k, v in pairs(defaults) do
    if type(v) == "table" then
      dst[k] = dst[k] or {}
      ApplyDefaults(dst[k], v)
    else
      if dst[k] == nil then dst[k] = v end
    end
  end
end

function ShortyRCD:Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ShortyRCD|r " .. tostring(msg))
end

function ShortyRCD:Debug(msg)
  if ShortyRCDDB and ShortyRCDDB.debug then
    self:Print("|cff999999" .. tostring(msg) .. "|r")
  end

end

-- ---------- Capability broadcast (my currently available spells from ClassLib) ----------
function ShortyRCD:GetMyCapabilities()
  local spells = {}

  local _, classToken = UnitClass("player")
  if not classToken then return spells end

  local list = self.ClassLib and self.ClassLib[classToken] or nil
  if type(list) ~= "table" then return spells end

  for _, e in ipairs(list) do
    local spellID = tonumber(e.spellID)
    if spellID and self:IsTracked(classToken, spellID) then
      -- IsPlayerSpell includes talented spells (true only if currently known).
      if IsPlayerSpell and IsPlayerSpell(spellID) then
        spells[#spells+1] = spellID
      elseif IsSpellKnown and IsSpellKnown(spellID) then
        spells[#spells+1] = spellID
      end
    end
  end

  table.sort(spells)
  return spells
end

function ShortyRCD:BroadcastMyCapabilities(reason)
  if not (self.Comms and self.Comms.BroadcastCapabilities) then return end

  -- Soft throttle to avoid spamming on rapid talent/spec updates.
  self._lastCapsAt = self._lastCapsAt or 0
  local now = GetTime and GetTime() or 0
  if now - self._lastCapsAt < 1.0 and reason ~= "ENCOUNTER_END" then
    return
  end
  self._lastCapsAt = now

  local spells = self:GetMyCapabilities()
  if #spells == 0 then
    self:Debug("Caps TX skipped (none)")
    return
  end

  self.Comms:BroadcastCapabilities(spells)
  self:Debug(("TX L|%d spells (%s)"):format(#spells, tostring(reason or "?")))
end


function ShortyRCD:RequestCapabilities(reason)
  if not (self.Comms and self.Comms.RequestCapabilities) then return end
  if not IsInGroup or not IsInGroup() then return end

  -- Throttle capability requests (e.g., multiple roster updates on login/reload).
  self._lastCapsReqAt = self._lastCapsReqAt or 0
  local now = GetTime and GetTime() or 0
  if now - self._lastCapsReqAt < 2.0 then return end
  self._lastCapsReqAt = now

  self.Comms:RequestCapabilities()
  self:Debug(("TX R| (%s)"):format(tostring(reason or "?")))
end



-- ---------- DB helpers ----------
function ShortyRCD:InitDB()
  if type(ShortyRCDDB) ~= "table" then
    ShortyRCDDB = DeepCopy(self.DEFAULTS)
  else
    ApplyDefaults(ShortyRCDDB, self.DEFAULTS)
  end
end

function ShortyRCD:IsTracked(classToken, spellID)
  if not ShortyRCDDB or not ShortyRCDDB.tracking then return true end
  if not classToken or not spellID then return false end

  -- Default behavior: tracked unless explicitly disabled
  local classTbl = ShortyRCDDB.tracking[classToken]
  if not classTbl then return true end
  local v = classTbl[spellID]
  if v == nil then return true end
  return v == true
end

function ShortyRCD:SetTracked(classToken, spellID, isTracked)
  ShortyRCDDB.tracking[classToken] = ShortyRCDDB.tracking[classToken] or {}
  ShortyRCDDB.tracking[classToken][spellID] = (isTracked == true)

  -- Live-update roster board without requiring /reload
  if ShortyRCD.UI and ShortyRCD.UI.RefreshRoster then
    ShortyRCD.UI:RefreshRoster()
  end
end


-- ---------- Slash ----------
local function OpenOptions()
  if ShortyRCD and ShortyRCD.Options and ShortyRCD.Options.Open then
    ShortyRCD.Options:Open()
  else
    ShortyRCD:Print("Options module not ready yet.")
  end
end

local function SlashHandler(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if msg == "" or msg == "options" then
    OpenOptions()
    return
  end
  if msg == "debug" then
    ShortyRCDDB.debug = not ShortyRCDDB.debug
    ShortyRCD:Print("Debug: " .. tostring(ShortyRCDDB.debug))
    return
  end

  -- Dev helper: simulate receiving a cast from addon comms.
  -- Usage: /srcd inject <spellID>
  local cmd, rest = strsplit(" ", msg, 2)
  if cmd == "inject" then
    local spellID = tonumber(rest)
    if not spellID then
      ShortyRCD:Print("Inject usage: /srcd inject <spellID>")
      return
    end
    if ShortyRCD.Comms and ShortyRCD.Comms.DevInjectCast then
      ShortyRCD.Comms:DevInjectCast(spellID)
      return
    end
    ShortyRCD:Print("Comms module not ready; cannot inject.")
    return
  end

  ShortyRCD:Print("Usage: /srcd  (options) | /srcd debug | /srcd inject <spellID>")
end

-- ---------- Init ----------
function ShortyRCD:OnLogin()
  self:InitDB()

  -- Initialize subsystems (each module attaches itself if loaded)
  if self.Tracker and self.Tracker.Init then self.Tracker:Init() end
  if self.Comms and self.Comms.Init then self.Comms:Init() end
  if self.UI and self.UI.Init then self.UI:Init() end
  if self.Options and self.Options.Init then self.Options:Init() end

  -- Slash command
  SLASH_SHORTYRCD1 = "/srcd"
  SlashCmdList["SHORTYRCD"] = SlashHandler

  -- Announce my current available spells (talents/spec filtered)
  self:BroadcastMyCapabilities("LOGIN")

  self:Print("Loaded v" .. self.VERSION .. ". Type /srcd")
end


-- ---------- Cooldown query (local, for CD override) ----------
function ShortyRCD:GetEffectiveCooldownSeconds(spellID)
  spellID = tonumber(spellID)
  if not spellID then return nil end

  local startTime, duration = nil, nil

  -- Prefer modern API if available.
  if C_Spell and C_Spell.GetSpellCooldown then
    local info = C_Spell.GetSpellCooldown(spellID)
    if info then
      startTime = info.startTime
      duration = info.duration
    end
-- Delayed broadcast: cooldown APIs can report 0/1s on the same frame as UNIT_SPELLCAST_SUCCEEDED.
-- We retry for a few frames to capture the real (talent-modified) cooldown before broadcasting.
ShortyRCD._pendingCastBroadcast = ShortyRCD._pendingCastBroadcast or {}

function ShortyRCD:ScheduleCastBroadcast(spellID, castGUID)
  if type(spellID) ~= "number" then return end
  castGUID = castGUID or ("spell:" .. tostring(spellID) .. ":" .. tostring(GetTimePreciseSec and GetTimePreciseSec() or GetTime()))

  local pending = self._pendingCastBroadcast
  if pending[castGUID] then return end

  pending[castGUID] = { spellID = spellID, tries = 0 }

  local function attempt()
    local p = pending[castGUID]
    if not p then return end
    p.tries = (p.tries or 0) + 1

    local entry = self.GetSpellEntry and self:GetSpellEntry(spellID) or nil
    local base = entry and entry.cd or nil
    local cdSec = self.GetEffectiveCooldownSeconds and self:GetEffectiveCooldownSeconds(spellID, base) or nil

    -- Many spells will return 0/1s for a frame or two after the cast event.
    -- If it looks bogus, retry a couple times.
    if cdSec and cdSec <= 1.5 and p.tries < 4 then
      ShortyRCD:Debug(("CD sample too low (%s) for %d, retry %d"):format(tostring(cdSec), spellID, p.tries))
      C_Timer.After(0.08, attempt)
      return
    end

    pending[castGUID] = nil

    if self.Comms and self.Comms.BroadcastCast then
      -- -- self.Comms:BroadcastCast(spellID, cdSec)  -- replaced by delayed broadcast
  self:ScheduleCastBroadcast(spellID, castGUID)  -- replaced by delayed broadcast
  self:ScheduleCastBroadcast(spellID, castGUID)
    end
  end

  C_Timer.After(0.05, attempt)
end
  elseif GetSpellCooldown then
    startTime, duration = GetSpellCooldown(spellID)
  end

  duration = tonumber(duration) or 0

  -- Ignore GCD-ish durations; we only want real cooldowns.
  if duration <= 1.6 then
    return nil
  end

  return duration
end


-- ---------- Spell detection (self only) ----------
function ShortyRCD:OnSpellcastSucceeded(unit, castGUID, spellID)
  if unit ~= "player" then return end
  if type(spellID) ~= "number" then return end

  -- Only act on spells we track.
  local entry = self.GetSpellEntry and self:GetSpellEntry(spellID) or nil
  if not entry then return end

  -- Channeled spells are announced on UNIT_SPELLCAST_CHANNEL_START.
  if entry.ch == true then return end

  local _, classToken = UnitClass("player")
  if not self:IsTracked(classToken, spellID) then return end

  if self.Comms and self.Comms.BroadcastCast then
    self.Comms:BroadcastCast(spellID, self:GetEffectiveCooldownSeconds(spellID))
    self:Debug(("TX C|%d (%s)"):format(spellID, entry.name or "?"))
  end
end

function ShortyRCD:OnSpellcastChannelStart(unit, castGUID, spellID)
  if unit ~= "player" then return end
  if type(spellID) ~= "number" then return end

  -- Only act on spells we track.
  local entry = self.GetSpellEntry and self:GetSpellEntry(spellID) or nil
  if not entry then return end

  -- Only channeled spells are announced here.
  if entry.ch ~= true then return end

  local _, classToken = UnitClass("player")
  if not self:IsTracked(classToken, spellID) then return end

  if self.Comms and self.Comms.BroadcastCast then
    self.Comms:BroadcastCast(spellID, self:GetEffectiveCooldownSeconds(spellID))
    self:Debug(("TX C|%d (%s) [channel]"):format(spellID, entry.name or "?"))
  end
end

-- Encounter end: clear any timers flagged as reset-on-encounter-end (roe == true).
function ShortyRCD:OnEncounterEnd(encounterID, encounterName, difficultyID, groupSize, success)
  if self.Tracker and self.Tracker.OnEncounterEnd then
    self.Tracker:OnEncounterEnd(encounterID, encounterName, difficultyID, groupSize, success)
  end
end



function ShortyRCD:OnGroupRosterUpdate()
  -- Always re-broadcast my current capability list.
  self:BroadcastMyCapabilities("GROUP_ROSTER_UPDATE")

  -- Newcomer behavior: if I just joined a group (or /reload while grouped),
  -- request that everyone rebroadcast so my roster is immediately accurate.
  local inGroup = IsInGroup and IsInGroup() or false
  local wasInGroup = self._wasInGroup or false

  if inGroup and not wasInGroup then
    self:RequestCapabilities("JOINED_GROUP")
  end

  self._wasInGroup = inGroup
end

function ShortyRCD:RegisterEvents()
  if not EventRegistry then
    self:Print("EventRegistry unavailable; events disabled")
    return
  end

  EventRegistry:RegisterFrameEvent("PLAYER_LOGIN")
  EventRegistry:RegisterCallback("PLAYER_LOGIN", function()
    ShortyRCD:OnLogin()
  end, self)

  -- Self casts only (architecture: each client detects their own casts).
  EventRegistry:RegisterFrameEvent("UNIT_SPELLCAST_SUCCEEDED")
  EventRegistry:RegisterCallback("UNIT_SPELLCAST_SUCCEEDED", function(_, ...)
    ShortyRCD:OnSpellcastSucceeded(...)
  end, self)

  -- Channeled spells announce at channel start so AC bars are meaningful.
  EventRegistry:RegisterFrameEvent("UNIT_SPELLCAST_CHANNEL_START")
  EventRegistry:RegisterCallback("UNIT_SPELLCAST_CHANNEL_START", function(_, ...)
    ShortyRCD:OnSpellcastChannelStart(...)
  end, self)

  -- Reset-on-encounter-end cooldowns (roe=true in ClassLib).
  EventRegistry:RegisterFrameEvent("ENCOUNTER_END")
  EventRegistry:RegisterCallback("ENCOUNTER_END", function(_, ...)
    ShortyRCD:OnEncounterEnd(...)
  end, self)


  -- Group changes: join/leave/convert party<->raid etc.
  EventRegistry:RegisterFrameEvent("GROUP_ROSTER_UPDATE")
  EventRegistry:RegisterCallback("GROUP_ROSTER_UPDATE", function()
    ShortyRCD:OnGroupRosterUpdate()
  end, self)
  -- Zoning / instance transitions (dungeons/raids/world).
  EventRegistry:RegisterFrameEvent("PLAYER_ENTERING_WORLD")
  EventRegistry:RegisterCallback("PLAYER_ENTERING_WORLD", function()
    ShortyRCD:BroadcastMyCapabilities("PLAYER_ENTERING_WORLD")
  end, self)

  EventRegistry:RegisterFrameEvent("ZONE_CHANGED_NEW_AREA")
  EventRegistry:RegisterCallback("ZONE_CHANGED_NEW_AREA", function()
    ShortyRCD:BroadcastMyCapabilities("ZONE_CHANGED_NEW_AREA")
  end, self)

  -- Talent system updates (Dragonflight+)
  EventRegistry:RegisterFrameEvent("TRAIT_CONFIG_UPDATED")
  EventRegistry:RegisterCallback("TRAIT_CONFIG_UPDATED", function()
    ShortyRCD:BroadcastMyCapabilities("TRAIT_CONFIG_UPDATED")
  end, self)

  -- Legacy talent updates (harmless if never fires)
  EventRegistry:RegisterFrameEvent("PLAYER_TALENT_UPDATE")
  EventRegistry:RegisterCallback("PLAYER_TALENT_UPDATE", function()
    ShortyRCD:BroadcastMyCapabilities("PLAYER_TALENT_UPDATE")
  end, self)

  EventRegistry:RegisterFrameEvent("ACTIVE_TALENT_GROUP_CHANGED")
  EventRegistry:RegisterCallback("ACTIVE_TALENT_GROUP_CHANGED", function()
    ShortyRCD:BroadcastMyCapabilities("ACTIVE_TALENT_GROUP_CHANGED")
  end, self)


  -- Spec change (covers swapping between heal/dps and many talent swaps that change known spells).
  EventRegistry:RegisterFrameEvent("PLAYER_SPECIALIZATION_CHANGED")
  EventRegistry:RegisterCallback("PLAYER_SPECIALIZATION_CHANGED", function(_, unit)
    if unit == "player" then
      ShortyRCD:BroadcastMyCapabilities("PLAYER_SPECIALIZATION_CHANGED")
    end
  end, self)

end

-- ---------- Bootstrap ----------
ShortyRCD:RegisterEvents()

-- ============================================================================
-- CD override reliability patch (add-only)
--
-- Problem: immediate cooldown queries often return the GCD (~1s) right after a
-- successful cast, especially in instances. For accurate per-player cooldown
-- broadcast (talent-modified), we retry a few frames and ignore GCD-like
-- results.
--
-- NOTE: This is intentionally add-only: we *override* methods by re-defining
-- them here (Lua uses the latest definition).
-- ============================================================================

do
  local function CooldownSampleSeconds(spellID)
    spellID = tonumber(spellID)
    if not spellID then return nil end

    -- Prefer modern API if available.
    if C_Spell and C_Spell.GetSpellCooldown then
      local cd = C_Spell.GetSpellCooldown(spellID)
      if cd and cd.startTime and cd.duration then
        if cd.startTime > 0 and cd.duration and cd.duration > 0 then
          return cd.duration
        end
      end
    end

    -- Fallback.
    if GetSpellCooldown then
      local start, duration, enabled = GetSpellCooldown(spellID)
      if enabled == 1 and start and start > 0 and duration and duration > 0 then
        return duration
      end
    end

    return nil
  end

  local function IsLikelyGCD(seconds)
    if not seconds then return true end
    -- Treat anything <= 1.6s as GCD/no-cooldown noise.
    return seconds <= 1.6
  end

  -- Override: return a *usable* cooldown duration in seconds, or nil.
  function ShortyRCD:GetEffectiveCooldownSeconds(spellID)
    local entry = self.GetSpellEntry and self:GetSpellEntry(spellID) or nil
    local baseCd = entry and tonumber(entry.cd) or nil

    local s = CooldownSampleSeconds(spellID)
    if IsLikelyGCD(s) then return nil end

    -- If we know the base cooldown, reject obviously-wrong tiny values.
    if baseCd and baseCd >= 20 then
      local minOk = math.max(5, baseCd * 0.25) -- accepts 120s vs 180s, rejects 1s.
      if s < minOk then
        return nil
      end
    end

    return s
  end

  -- Override: schedule reliable broadcast (and local tracking) with retry.
  function ShortyRCD:ScheduleCastBroadcast(spellID, sender)
    spellID = tonumber(spellID)
    if not spellID then return end

    local entry = self.GetSpellEntry and self:GetSpellEntry(spellID) or nil
    if not entry then return end

    local attempts = 0
    local maxAttempts = 8

    local function finish(cdSec)
      cdSec = tonumber(cdSec) or tonumber(entry.cd) or 0

      -- Local start (guarantees your own bars even if comms get throttled)
      if self.Tracker and self.Tracker.OnRemoteCast then
        self.Tracker:OnRemoteCast(sender or (UnitName("player") or "player"), spellID, cdSec)
      end

      -- Network broadcast
      if self.Comms and self.Comms.BroadcastCast then
        self.Comms:BroadcastCast(spellID, cdSec)
      end

      if self.Debug then
        self:Debug(("CD sample for %s (%d): %ss (base %ss)"):format(entry.name or "?", spellID, tostring(cdSec), tostring(entry.cd)))
      end
    end

    local function try()
      attempts = attempts + 1
      local cdSec = self:GetEffectiveCooldownSeconds(spellID)
      if cdSec then
        finish(cdSec)
        return
      end

      if attempts >= maxAttempts then
        finish(nil) -- fallback to base
        return
      end

      -- Retry a few frames later; small delay is negligible to humans.
      local delay = 0.05
      if attempts >= 3 then delay = 0.10 end
      if attempts >= 5 then delay = 0.20 end
      if attempts >= 7 then delay = 0.35 end
      if C_Timer and C_Timer.After then
        C_Timer.After(delay, try)
      else
        -- Worst-case: no timer API; just fall back.
        finish(nil)
      end
    end

    try()
  end

  -- Override: hook spellcast success to the scheduler.
  local _origSucceeded = ShortyRCD.OnSpellcastSucceeded
  function ShortyRCD:OnSpellcastSucceeded(unit, castGUID, spellID)
    if unit ~= "player" then return end
    spellID = tonumber(spellID)
    if not spellID then return end

    local entry = self.GetSpellEntry and self:GetSpellEntry(spellID) or nil
    if not entry then
      -- Preserve any prior debug/behavior.
      if _origSucceeded then
        return _origSucceeded(self, unit, castGUID, spellID)
      end
      return
    end

    -- Use reliable broadcast (handles talent-modified CDs)
    self:ScheduleCastBroadcast(spellID, UnitName("player"))
  end
end