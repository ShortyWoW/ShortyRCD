-- ShortyRCD_TestCombatLog.lua
-- PURPOSE: Prove self-cast success detection is viable in Midnight.
-- IMPORTANT: Does NOT use Frame:RegisterEvent().

local ADDON_TAG = "|cff00ff88[ShortyRCD TEST]|r "

-- Set true to only print spells that exist in your ClassLib
local ONLY_TRACKED_SPELLS = false

local function msg(text)
  DEFAULT_CHAT_FRAME:AddMessage(ADDON_TAG .. text)
end

local function IsTrackedSpell(spellID)
  if not ShortyRCD or not ShortyRCD.ClassLib then return false end
  for _, spells in pairs(ShortyRCD.ClassLib) do
    for _, s in ipairs(spells) do
      if s.spellID == spellID then
        return true
      end
    end
  end
  return false
end

-- Midnight-safe spell name lookup (GetSpellInfo may be gone)
local function GetSpellNameSafe(spellID)
  spellID = tonumber(spellID)
  if not spellID then return nil end

  -- Newer API patterns
  if C_Spell then
    if C_Spell.GetSpellName then
      local name = C_Spell.GetSpellName(spellID)
      if name then return name end
    end

    -- Some builds have GetSpellInfo returning a table
    if C_Spell.GetSpellInfo then
      local info = C_Spell.GetSpellInfo(spellID)
      if type(info) == "table" then
        return info.name or info.spellName
      end
    end
  end

  -- Absolute fallback: no name available
  return nil
end

local function OnSucceeded(_, unit, castGUID, spellID)
  if unit ~= "player" then return end
  spellID = tonumber(spellID)
  if not spellID then return end

  if ONLY_TRACKED_SPELLS and not IsTrackedSpell(spellID) then
    return
  end

  local spellName = GetSpellNameSafe(spellID) or "UNKNOWN_SPELL"
  msg(string.format(
    "UNIT_SPELLCAST_SUCCEEDED: %s (%d) castGUID=%s",
    spellName, spellID, tostring(castGUID)
  ))
end

-- Register via EventRegistry to avoid RegisterEvent() being protected/blocked
if EventRegistry and EventRegistry.RegisterFrameEventAndCallback then
  EventRegistry:RegisterFrameEventAndCallback(
    "UNIT_SPELLCAST_SUCCEEDED",
    OnSucceeded,
    "ShortyRCD_Test_Succeeded"
  )
  msg("Registered UNIT_SPELLCAST_SUCCEEDED via EventRegistry. Cast any spell to test.")
else
  msg("ERROR: EventRegistry not available. Cannot register test listener without RegisterEvent().")
end
