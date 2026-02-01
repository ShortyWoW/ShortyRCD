-- ShortyRCD.lua (core/glue)

local ADDON_NAME = ...
ShortyRCD = ShortyRCD or {}
ShortyRCD.ADDON_NAME = ADDON_NAME
ShortyRCD.VERSION = "0.1.0"

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

  self:Print("Loaded v" .. self.VERSION .. ". Type /srcd")
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
    self.Comms:BroadcastCast(spellID)
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
    self.Comms:BroadcastCast(spellID)
    self:Debug(("TX C|%d (%s) [channel]"):format(spellID, entry.name or "?"))
  end
end

-- Encounter end: clear any timers flagged as reset-on-encounter-end (roe == true).
function ShortyRCD:OnEncounterEnd(encounterID, encounterName, difficultyID, groupSize, success)
  if self.Tracker and self.Tracker.OnEncounterEnd then
    self.Tracker:OnEncounterEnd(encounterID, encounterName, difficultyID, groupSize, success)
  end
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

end

-- ---------- Bootstrap ----------
ShortyRCD:RegisterEvents()
