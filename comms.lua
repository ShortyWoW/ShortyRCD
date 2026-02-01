-- comms.lua
ShortyRCD = ShortyRCD or {}
ShortyRCD.Comms = ShortyRCD.Comms or {}

local Comms = ShortyRCD.Comms
Comms.PREFIX = "ShortyRCD" -- <= 16 chars

local function AllowedChannel()
  -- Only function inside group content (RAID / PARTY / INSTANCE).
  -- Mythic+ premades are usually PARTY; LFG instances are INSTANCE_CHAT.
  if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
  if IsInRaid() then return "RAID" end
  if IsInGroup() then return "PARTY" end
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
    ShortyRCD:Debug("TX blocked (not in group content)")
    return
  end

  -- Prefer ChatThrottleLib if present (recommended by Blizzard docs).
  if ChatThrottleLib and ChatThrottleLib.SendAddonMessage then
    -- Prio can be "BULK"/"NORMAL"/"ALERT". NORMAL is fine for our traffic.
    ChatThrottleLib:SendAddonMessage("NORMAL", self.PREFIX, msg, ch)
    return
  end

  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    C_ChatInfo.SendAddonMessage(self.PREFIX, msg, ch)
  end
end


function Comms:BroadcastCast(spellID)
  if type(spellID) ~= "number" then return end
  self:Send("C|" .. tostring(spellID))
end


-- Broadcast a capability list (spells the sender can actually cast right now).
-- Payload: "L|<id1>,<id2>,<id3>"
function Comms:BroadcastCapabilities(spellIDs)
  if type(spellIDs) ~= "table" then return end
  local out = {}
  for _, id in ipairs(spellIDs) do
    id = tonumber(id)
    if id then out[#out+1] = tostring(id) end
  end
  if #out == 0 then return end
  self:Send("L|" .. table.concat(out, ","))
end


function Comms:OnAddonMessage(prefix, msg, channel, sender)
  if prefix ~= self.PREFIX then return end
  if channel ~= "RAID" and channel ~= "INSTANCE_CHAT" and channel ~= "PARTY" then return end

  local kind, payload = strsplit("|", msg or "", 2)

  if kind == "C" then
    local spellID = tonumber(payload)
    if not spellID then return end

    local entry = ShortyRCD.GetSpellEntry and ShortyRCD:GetSpellEntry(spellID) or nil
    if not entry then
      ShortyRCD:Debug(("RX ignored unknown spellID %s from %s"):format(tostring(payload), tostring(sender)))
      return
    end

    if ShortyRCD.Tracker and ShortyRCD.Tracker.OnRemoteCast then
      ShortyRCD.Tracker:OnRemoteCast(sender, spellID)
    end

    ShortyRCD:Debug(("RX %s cast %s (%d)"):format(tostring(sender), entry.name or "?", spellID))
    return
  end

  if kind == "L" then
    -- Capability list: "L|id1,id2,id3"
    local list = {}
    if payload and payload ~= "" then
      for idStr in string.gmatch(payload, "[^,]+") do
        local id = tonumber(idStr)
        if id then
          local entry = ShortyRCD.GetSpellEntry and ShortyRCD:GetSpellEntry(id) or nil
          if entry then
            list[#list+1] = id
          end
        end
      end
    end

    if ShortyRCD.Tracker and ShortyRCD.Tracker.OnRemoteCapabilities then
      ShortyRCD.Tracker:OnRemoteCapabilities(sender, list)
    elseif ShortyRCD.Tracker and ShortyRCD.Tracker.SetCapabilities then
      ShortyRCD.Tracker:SetCapabilities(sender, list)
    end

    ShortyRCD:Debug(("RX %s caps [%d]"):format(tostring(sender), #list))
    return
  end

  return
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