-- comms.lua
ShortyRCD = ShortyRCD or {}
ShortyRCD.Comms = ShortyRCD.Comms or {}

ShortyRCD.Comms.PREFIX = "ShortyRCD" -- <= 16 chars

-- Allowed channels (hard lock per your requirement)
local ALLOWED_SEND = {
  RAID = true,
  INSTANCE_CHAT = true,
}

local ALLOWED_RECV = {
  RAID = true,
  INSTANCE_CHAT = true,
}

function ShortyRCD.Comms:Init()
  self:RegisterPrefix()
  self:RegisterEvents()
end

function ShortyRCD.Comms:RegisterPrefix()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(self.PREFIX)
  end
end

-- Only function in RAID and INSTANCE (Mythic+/LFG) groups.
function ShortyRCD.Comms:GetBestChannel()
  -- Instance groups (M+/LFG) should use INSTANCE_CHAT
  if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
    return "INSTANCE_CHAT"
  end

  -- Non-instance raids use RAID
  if IsInRaid() then
    return "RAID"
  end

  -- Not allowed: open-world party, solo, etc.
  return nil
end

function ShortyRCD.Comms:Send(msg)
  local ch = self:GetBestChannel()
  if not ch then
    ShortyRCD:Debug("TX blocked (not in RAID/INSTANCE)")
    return
  end
  if not ALLOWED_SEND[ch] then
    ShortyRCD:Debug("TX blocked (channel not allowed): " .. tostring(ch))
    return
  end

  C_ChatInfo.SendAddonMessage(self.PREFIX, msg, ch)
end

-- Convenience wrapper for our single message type.
function ShortyRCD.Comms:BroadcastCast(spellID)
  if type(spellID) ~= "number" then return end
  self:Send("C|" .. tostring(spellID))
end

function ShortyRCD.Comms:OnAddonMessage(prefix, msg, channel, sender)
  if prefix ~= self.PREFIX then return end
  if not ALLOWED_RECV[channel] then
    -- Ignore any other delivery channel.
    return
  end

  -- Format: "C|<spellID>"
  local kind, spellIDStr = strsplit("|", msg or "", 2)
  if kind ~= "C" then return end

  local spellID = tonumber(spellIDStr)
  local entry = ShortyRCD.GetSpellEntry and ShortyRCD:GetSpellEntry(spellID) or nil
  if not entry then
    ShortyRCD:Debug(("RX ignored (unknown spellID): %s from %s"):format(tostring(spellIDStr), tostring(sender)))
    return
  end

  -- Phase 1 print verification (keep for now)
  ShortyRCD:Print(("RX %s cast %s (%d)"):format(tostring(sender), entry.name or "?", spellID))

  -- Phase 2 hook (we’ll wire this next)
  -- if ShortyRCD.Tracker and ShortyRCD.Tracker.OnRemoteCast then
  --   ShortyRCD.Tracker:OnRemoteCast(sender, spellID)
  -- end
end

-- Dev helper: simulate receiving a cast message locally without needing a second client.
-- Does NOT send anything to chat channels; it directly calls the same handler used by CHAT_MSG_ADDON.
function ShortyRCD.Comms:DevInjectCast(spellID, senderOverride)
  spellID = tonumber(spellID)
  if not spellID then
    ShortyRCD:Print("Inject usage: /srcd inject <spellID>")
    return
  end

  local sender = senderOverride
  if not sender then
    local name, realm = UnitFullName("player")
    if realm and realm ~= "" then
      sender = name .. "-" .. realm
    else
      sender = name
    end
  end

  -- channel "DEV_INJECT" would be blocked by ALLOWED_RECV, so pass "RAID" here
  -- to exercise the real receive path logic.
  self:OnAddonMessage(self.PREFIX, "C|" .. tostring(spellID), "RAID", sender)
end

function ShortyRCD.Comms:RegisterEvents()
  if not EventRegistry then
    ShortyRCD:Print("EventRegistry unavailable; comms disabled")
    return
  end

  EventRegistry:RegisterFrameEvent("CHAT_MSG_ADDON")
  EventRegistry:RegisterCallback("CHAT_MSG_ADDON", function(_, ...)
    self:OnAddonMessage(...)
  end, self)
end