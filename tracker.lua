-- tracker.lua
ShortyRCD = ShortyRCD or {}
ShortyRCD.Tracker = ShortyRCD.Tracker or {}

local Tracker = ShortyRCD.Tracker

local function ShortName(nameWithRealm)
  if type(nameWithRealm) ~= "string" then return nameWithRealm end
  -- Prefer Ambiguate if available (handles Name-Realm)
  if Ambiguate then
    return Ambiguate(nameWithRealm, "short")
  end
  return (nameWithRealm:gsub("%-.*$", ""))
end

function Tracker:Init()
  -- state[name][spellID] = { startedAt=, cd=, ac=, iconID=, name=, type=, roe= }
  self.state = self.state or {}
  self.capabilities = self.capabilities or {} -- sender -> set{spellID=true}
end

function Tracker:OnRemoteCast(sender, spellID, cdOverride)
  sender = ShortName(sender)
  spellID = tonumber(spellID)
  if not sender or not spellID then return end

  local entry = ShortyRCD.GetSpellEntry and ShortyRCD:GetSpellEntry(spellID) or nil
  if not entry then return end

  self.state[sender] = self.state[sender] or {}
  self.state[sender][spellID] = {
    startedAt = GetTime(),
    cd = (tonumber(cdOverride) or tonumber(entry.cd) or 0),
    ac = tonumber(entry.ac) or 0,
    iconID = entry.iconID,
    spellName = entry.name or ("Spell " .. tostring(spellID)),
    type = entry.type,
    roe = (entry.roe == true),
  }
end

function Tracker:OnEncounterEnd()
  if not self.state then return end
  for sender, bySpell in pairs(self.state) do
    for spellID, s in pairs(bySpell) do
      local entry = ShortyRCD.GetSpellEntry and ShortyRCD:GetSpellEntry(tonumber(spellID)) or nil
      if entry and entry.roe == true then
        bySpell[spellID] = nil
      end
    end
    if next(bySpell) == nil then
      self.state[sender] = nil
    end
  end
end

local function BuildRow(sender, spellID, st, now)
  local startedAt = st.startedAt or 0
  local cd = st.cd or 0
  local ac = st.ac or 0

  local activeEnd = startedAt + ac
  local cdEnd = startedAt + cd

  local activeRemaining = math.max(0, activeEnd - now)
  local cdRemaining = math.max(0, cdEnd - now)

  return {
    sender = sender,
    spellID = spellID,
    iconID = st.iconID,
    spellName = st.spellName,
    type = st.type,
    startedAt = startedAt,
    cd = cd,
    ac = ac,
    activeRemaining = activeRemaining,
    cooldownRemaining = cdRemaining,
    isActive = activeRemaining > 0,
    isCoolingDown = cdRemaining > 0,
  }
end

function Tracker:GetRows()
  local rows = {}
  local now = GetTime()

  if not self.state then return rows end

  for sender, bySpell in pairs(self.state) do
    for spellID, st in pairs(bySpell) do
      local row = BuildRow(sender, spellID, st, now)

      -- Auto-expire once fully ready again
      if row.cooldownRemaining <= 0 then
        bySpell[spellID] = nil
      else
        table.insert(rows, row)
      end
    end
    if next(bySpell) == nil then
      self.state[sender] = nil
    end
  end

  table.sort(rows, function(a, b)
    if a.isActive ~= b.isActive then return a.isActive end
    if a.cooldownRemaining ~= b.cooldownRemaining then return a.cooldownRemaining < b.cooldownRemaining end
    if a.sender ~= b.sender then return a.sender < b.sender end
    return (a.spellName or "") < (b.spellName or "")
  end)

  return rows
end


-- Added for roster board: query a specific sender+spell state
function Tracker:GetState(sender, spellID)
  if not self.state then return nil end
  sender = ShortName(sender)
  spellID = tonumber(spellID)
  if not sender or not spellID then return nil end

  local bySpell = self.state[sender]
  if not bySpell then return nil end
  local st = bySpell[spellID]
  if not st then return nil end

  local now = GetTime()

  local startedAt = st.startedAt or 0
  local cd = st.cd or 0
  local ac = st.ac or 0

  local activeEnd = startedAt + ac
  local cdEnd = startedAt + cd

  local activeRemaining = math.max(0, activeEnd - now)
  local cdRemaining = math.max(0, cdEnd - now)

  local row = {
    sender = sender,
    spellID = spellID,
    iconID = st.iconID,
    spellName = st.spellName,
    type = st.type,
    startedAt = startedAt,
    cd = cd,
    ac = ac,
    activeRemaining = activeRemaining,
    cooldownRemaining = cdRemaining,
    isActive = activeRemaining > 0,
    isCoolingDown = cdRemaining > 0,
  }

  if row.cooldownRemaining <= 0 then
    bySpell[spellID] = nil
    if next(bySpell) == nil then self.state[sender] = nil end
    return nil
  end

  return row
end



-- ---------- Capability tracking (what each sender can actually cast) ----------
function Tracker:SetCapabilities(sender, spellIDs)
  sender = ShortName(sender)
  if not sender then return end
  self.capabilities = self.capabilities or {}

  local set = {}
  if type(spellIDs) == "table" then
    for _, id in ipairs(spellIDs) do
      id = tonumber(id)
      if id then set[id] = true end
    end
  end

  self.capabilities[sender] = set

  -- If we have active timers for spells the sender no longer reports, drop them.
  if self.state and self.state[sender] then
    for spellID in pairs(self.state[sender]) do
      if not set[tonumber(spellID)] then
        self.state[sender][spellID] = nil
      end
    end
    if next(self.state[sender]) == nil then
      self.state[sender] = nil
    end
  end

  -- Let UI rebuild roster immediately.
  if ShortyRCD.UI and ShortyRCD.UI.RefreshRoster then
    ShortyRCD.UI:RefreshRoster()
  end
  if ShortyRCD.InterruptUI and ShortyRCD.InterruptUI.RefreshRoster then
    ShortyRCD.InterruptUI:RefreshRoster()
  end
end

function Tracker:OnRemoteCapabilities(sender, spellIDs)
  self:SetCapabilities(sender, spellIDs)
end

function Tracker:HasAnyCapabilities(sender)
  sender = ShortName(sender)
  if not sender or not self.capabilities then return false end
  local set = self.capabilities[sender]
  return type(set) == "table" and next(set) ~= nil
end

function Tracker:HasCapability(sender, spellID)
  sender = ShortName(sender)
  spellID = tonumber(spellID)
  if not sender or not spellID or not self.capabilities then return false end
  local set = self.capabilities[sender]
  if type(set) ~= "table" then return false end
  return set[spellID] == true
end