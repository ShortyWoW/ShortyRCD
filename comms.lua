-- comms.lua
ShortyRCD = ShortyRCD or {}
ShortyRCD.Comms = ShortyRCD.Comms or {}

local Comms = ShortyRCD.Comms
Comms.PREFIX = "ShortyRCD" -- <= 16 chars

local function AllowedChannel()
  -- Instance groups (LFG/Mythic+/LFR) use INSTANCE_CHAT. Raids use RAID.
  if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
  if IsInRaid() then return "RAID" end
  if IsInGroup() then return "PARTY" end
  return nil
end

local function GetCooldownDurationSeconds(spellID)
  -- Best effort: after a successful cast, the spell cooldown API usually reflects
  -- talent-modified cooldown durations.
  local startTime, duration

  if C_Spell and C_Spell.GetSpellCooldown then
    local cd = C_Spell.GetSpellCooldown(spellID)
    if cd then
      startTime = cd.startTime
      duration = cd.duration
    end
  end

  if not duration then
    -- Legacy fallback
    startTime, duration = GetSpellCooldown(spellID)
  end

  if type(duration) ~= "number" or duration <= 0 then
    return nil
  end

  -- Round to nearest whole second (addon messages should stay small)
  return math.floor(duration + 0.5)
end

-- Try to obtain the current cooldown duration for a spell (in seconds).
-- This reflects talent modifiers *after* the cooldown has been started.
local function GetCooldownDurationSeconds(spellID)
  -- Prefer modern API if available.
  if C_Spell and C_Spell.GetSpellCooldown then
    local cd = C_Spell.GetSpellCooldown(spellID)
    if cd and cd.duration and cd.duration > 0 then
      return cd.duration
    end
  end

  -- Fallback.
  local startTime, duration = GetSpellCooldown(spellID)
  if duration and duration > 0 then
    return duration
  end

  return nil
end

-- Try to obtain the current cooldown duration for a spell (in seconds).
-- This reflects talent modifiers *after* the cooldown has been started.
local function GetCooldownDurationSeconds(spellID)
  -- Prefer modern API if available.
  if C_Spell and C_Spell.GetSpellCooldown then
    local cd = C_Spell.GetSpellCooldown(spellID)
    if cd and cd.duration and cd.duration > 0 then
      return cd.duration
    end
  end

  -- Fallback to legacy API.
  if GetSpellCooldown then
    local startTime, duration, enabled = GetSpellCooldown(spellID)
    if type(duration) == "number" and duration > 0 then
      return duration
    end
  end

  return nil
end

function Comms:Init()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(self.PREFIX)
  end

  if not EventRegistry then
    ShortyRCD:Print("EventRegistry unavailable; comms disabled")
    return
  end

  EventRegistry:RegisterFrameEvent("CHAT_MSG_ADDON")
  EventRegistry:RegisterCallback("CHAT_MSG_ADDON", function(_, ...)
    self:OnAddonMessage(...)
  end, self)
end

function Comms:Send(msg)
  local ch = AllowedChannel()
  if not ch then
    ShortyRCD:Debug("TX blocked (not in RAID/INSTANCE/PARTY)")
    return false
  end

  if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then
    ShortyRCD:Debug("TX blocked (C_ChatInfo.SendAddonMessage unavailable)")
    return false
  end

  -- Prefer ChatThrottleLib if present.
  if ChatThrottleLib and ChatThrottleLib.SendAddonMessage then
    ChatThrottleLib:SendAddonMessage("NORMAL", self.PREFIX, msg, ch)
  else
    C_ChatInfo.SendAddonMessage(self.PREFIX, msg, ch)
  end

  return true
end

-- Broadcast a cast event.
-- If cdOverrideSec is nil, we will try to query the spell's cooldown duration (talents included)
-- and include it.
function Comms:BroadcastCast(spellID, cdOverrideSec)
  if type(spellID) ~= "number" then return end

  local cdSec = tonumber(cdOverrideSec)
  if not cdSec or cdSec <= 0 then
    cdSec = GetCooldownDurationSeconds(spellID)
  else
    cdSec = math.floor(cdSec + 0.5)
  end

  local payload
  if cdSec and cdSec > 0 then
    payload = "C|" .. tostring(spellID) .. "|" .. tostring(cdSec)
    ShortyRCD:Debug(("TX C|%d cd=%ss"):format(spellID, tostring(cdSec)))
  else
    payload = "C|" .. tostring(spellID)
    ShortyRCD:Debug(("TX C|%d (no cd in msg)"):format(spellID))
  end

  self:Send(payload)
end


-- Broadcast capabilities list (what spells I can currently cast).
-- spells: array of spellIDs (numbers) sorted or unsorted.
function Comms:BroadcastCapabilities(spells)
  if type(spells) ~= "table" then return end
  if #spells == 0 then return end

  -- Payload stays compact: "L|740,98008,108280"
  local parts = {}
  for i = 1, #spells do
    local id = tonumber(spells[i])
    if id then
      parts[#parts+1] = tostring(id)
    end
  end
  if #parts == 0 then return end
  table.sort(parts)

  local payload = "L|" .. table.concat(parts, ",")
  ShortyRCD:Debug(("TX %s"):format(payload))
  self:Send(payload)
end


-- Request that everyone rebroadcast their capability list (L|...).
-- Sent by newcomers on join/reload so the roster converges quickly.
function Comms:RequestCapabilities()
  local payload = "R|"
  ShortyRCD:Debug(("TX %s"):format(payload))
  self:Send(payload)
end

function Comms:OnAddonMessage(prefix, msg, channel, sender)
  if prefix ~= self.PREFIX then return end
  if channel ~= "RAID" and channel ~= "INSTANCE_CHAT" and channel ~= "PARTY" then return end

  local kind, a, b = strsplit("|", msg or "", 3)

  -- Capability request: R|  (ask everyone to send L|...)
  if kind == "R" then
    ShortyRCD:Debug(("RX %s requested caps"):format(tostring(sender)))
    if ShortyRCD.BroadcastMyCapabilities then
      -- BroadcastMyCapabilities already throttles to avoid spam.
      ShortyRCD:BroadcastMyCapabilities("CAPS_REQUEST")
    end
    return
  end


  -- Capability list: L|740,98008,108280
  if kind == "L" then
    local spellIDs = {}
    if type(a) == "string" and a ~= "" then
      for idStr in string.gmatch(a, "([^,]+)") do
        local id = tonumber(idStr)
        if id then
          spellIDs[#spellIDs+1] = id
        end
      end
    end

    ShortyRCD:Debug(("RX %s caps %d spells"):format(tostring(sender), #spellIDs))

    if ShortyRCD.Tracker and ShortyRCD.Tracker.OnRemoteCapabilities then
      ShortyRCD.Tracker:OnRemoteCapabilities(sender, spellIDs)
    end

    return
  end

  -- Cast events: C|spellID|cdSec(optional)
  if kind ~= "C" then return end

  local spellID = tonumber(a)
  if not spellID then return end

  local cdSec = tonumber(b)
  if cdSec and cdSec > 0 then
    cdSec = math.floor(cdSec + 0.5)
  else
    cdSec = nil
  end

  local entry = ShortyRCD.GetSpellEntry and ShortyRCD:GetSpellEntry(spellID) or nil
  if not entry then
    ShortyRCD:Debug(("RX ignored unknown spellID %s from %s"):format(tostring(a), tostring(sender)))
    return
  end

  if cdSec then
    ShortyRCD:Debug(("RX %s cast %s (%d) cd=%ss"):format(tostring(sender), entry.name or "?", spellID, tostring(cdSec)))
  else
    ShortyRCD:Debug(("RX %s cast %s (%d) (no cd)"):format(tostring(sender), entry.name or "?", spellID))
  end

  if ShortyRCD.Tracker and ShortyRCD.Tracker.OnRemoteCast then
    -- Tracker can accept the 3rd arg; if it doesn't, Lua will ignore extras safely.
    ShortyRCD.Tracker:OnRemoteCast(sender, spellID, cdSec)
  end
end

-- Dev helper: simulate receiving a cast locally (no network).
-- Usage: /srcd inject <spellID>
function Comms:DevInjectCast(spellID, senderOverride)
  spellID = tonumber(spellID)
  if not spellID then
    ShortyRCD:Print("Inject usage: /srcd inject <spellID>")
    return
  end

  local sender = senderOverride
  if not sender then
    local name, realm = UnitFullName("player")
    if realm and realm ~= "" then sender = name .. "-" .. realm else sender = name end
  end

  -- Use RAID as a valid receive channel to exercise the real receive path.
  self:OnAddonMessage(self.PREFIX, "C|" .. tostring(spellID), "RAID", sender)
end 