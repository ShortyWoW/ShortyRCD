-- ui.lua
ShortyRCD = ShortyRCD or {}
ShortyRCD.UI = ShortyRCD.UI or {}

local UI = ShortyRCD.UI

local function ShortName(nameWithRealm)
  if type(nameWithRealm) ~= "string" then return nameWithRealm end
  if Ambiguate then return Ambiguate(nameWithRealm, "short") end
  return (nameWithRealm:gsub("%-.*$", ""))
end

local function FormatTime(sec)
  sec = math.max(0, math.floor(sec + 0.5))
  if sec >= 3600 then
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    return ("%dh%dm"):format(h, m)
  elseif sec >= 60 then
    local m = math.floor(sec / 60)
    local s = sec % 60
    return ("%dm%02ds"):format(m, s)
  else
    return ("%ds"):format(sec)
  end
end

function UI:Init()
  self.rows = {}
  self.classByName = {}
  self.rosterItems = {}

  self:CreateFrame()
  self:RestorePosition()
  self:ApplyLockState()
  self:RegisterRosterEvents()
  self:RefreshRoster()

  self.accum = 0
  self.frame:SetScript("OnUpdate", function(_, elapsed)
    self.accum = self.accum + elapsed
    if self.accum >= 0.10 then
      self.accum = 0
      self:UpdateBoard()
    end
  end)
end

function UI:RegisterRosterEvents()
  if not EventRegistry then return end
  EventRegistry:RegisterFrameEvent("GROUP_ROSTER_UPDATE")
  EventRegistry:RegisterCallback("GROUP_ROSTER_UPDATE", function() self:RefreshRoster() end, self)

  EventRegistry:RegisterFrameEvent("PLAYER_ENTERING_WORLD")
  EventRegistry:RegisterCallback("PLAYER_ENTERING_WORLD", function() self:RefreshRoster() end, self)
end

function UI:RefreshRoster()
  wipe(self.classByName)
  wipe(self.rosterItems)

  local function AddUnit(unit)
    if not UnitExists(unit) then return end
    local full = UnitName(unit)
    if not full then return end
    local short = ShortName(full)
    local _, classToken = UnitClass(unit)
    if not short or not classToken then return end

    self.classByName[short] = classToken

    local list = ShortyRCD.ClassLib and ShortyRCD.ClassLib[classToken]
    if type(list) ~= "table" then return end

    for _, e in ipairs(list) do
      if type(e) == "table" and type(e.spellID) == "number" then
        table.insert(self.rosterItems, {
          sender = short,
          classToken = classToken,
          spellID = e.spellID,
          spellName = e.name or ("Spell " .. tostring(e.spellID)),
          iconID = e.iconID,
          type = e.type,
          cd = tonumber(e.cd) or 0,
          ac = tonumber(e.ac) or 0,
        })
      end
    end
  end

  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      AddUnit("raid" .. i)
    end
  elseif IsInGroup() then
    -- In instance parties, party1..n excludes player; include player explicitly
    AddUnit("player")
    for i = 1, GetNumSubgroupMembers() do
      AddUnit("party" .. i)
    end
  else
    AddUnit("player")
  end

  -- Stable ordering: by sender then by type then by spell name
  table.sort(self.rosterItems, function(a, b)
    if a.sender ~= b.sender then return a.sender < b.sender end
    if (a.type or "") ~= (b.type or "") then return (a.type or "") < (b.type or "") end
    return (a.spellName or "") < (b.spellName or "")
  end)

  -- Force a layout refresh next update
  self.needsLayout = true
end

function UI:GetClassColorForSender(senderShort)
  local classToken = self.classByName[senderShort]
  if classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken] then
    local c = RAID_CLASS_COLORS[classToken]
    return c.r, c.g, c.b
  end
  return 0.32, 0.36, 0.42
end

function UI:CreateFrame()
  if self.frame then return end

  local f = CreateFrame("Frame", "ShortyRCD_Frame", UIParent, "BackdropTemplate")
  f:SetSize(320, 190)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")

  f:SetBackdrop({
    bgFile = "Interface/ChatFrame/ChatFrameBackground",
    edgeFile = "Interface/ChatFrame/ChatFrameBackground",
    tile = true, tileSize = 16, edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 }
  })
  f:SetBackdropColor(0.07, 0.08, 0.10, 0.92)
  f:SetBackdropBorderColor(0.12, 0.13, 0.16, 1.0)

  local header = CreateFrame("Frame", nil, f, "BackdropTemplate")
  header:SetPoint("TOPLEFT", 1, -1)
  header:SetPoint("TOPRIGHT", -1, -1)
  header:SetHeight(34)
  header:SetBackdrop({
    bgFile = "Interface/ChatFrame/ChatFrameBackground",
    edgeFile = "Interface/ChatFrame/ChatFrameBackground",
    tile = true, tileSize = 16, edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 }
  })
  header:SetBackdropColor(0.05, 0.06, 0.08, 0.98)
  header:SetBackdropBorderColor(0.12, 0.13, 0.16, 1.0)

  local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("LEFT", 10, 0)
  title:SetText("|cffffd000ShortyRCD|r")

  local sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 10, -6)
  sub:SetText("Raid cooldown tracker")

  f:SetScript("OnDragStart", function()
    if ShortyRCDDB.locked then return end
    f:StartMoving()
  end)
  f:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    UI:SavePosition()
  end)

  self.frame = f
  self.header = header
  self.sub = sub

  local list = CreateFrame("Frame", nil, f)
  list:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -8)
  list:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 10)
  list:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -60)
  self.list = list
end

function UI:EnsureRow(i)
  if self.rows[i] then return self.rows[i] end

  local parent = self.list
  local r = CreateFrame("Frame", nil, parent)
  r:SetSize(300, 22)

  local icon = r:CreateTexture(nil, "ARTWORK")
  icon:SetSize(18, 18)
  icon:SetPoint("LEFT", r, "LEFT", 0, 0)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  local barBG = CreateFrame("Frame", nil, r, "BackdropTemplate")
  barBG:SetPoint("LEFT", icon, "RIGHT", 8, 0)
  barBG:SetPoint("RIGHT", r, "RIGHT", 0, 0)
  barBG:SetHeight(18)
  barBG:SetBackdrop({
    bgFile = "Interface/ChatFrame/ChatFrameBackground",
    edgeFile = "Interface/ChatFrame/ChatFrameBackground",
    tile = true, tileSize = 16, edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 }
  })
  barBG:SetBackdropColor(0.03, 0.03, 0.04, 0.95)
  barBG:SetBackdropBorderColor(0.14, 0.15, 0.18, 1.0)

  local bar = CreateFrame("StatusBar", nil, barBG)
  bar:SetPoint("TOPLEFT", barBG, "TOPLEFT", 1, -1)
  bar:SetPoint("BOTTOMRIGHT", barBG, "BOTTOMRIGHT", -1, 1)
  bar:SetStatusBarTexture("Interface/TargetingFrame/UI-StatusBar")
  bar:SetMinMaxValues(0, 1)
  bar:SetValue(1)

  local timer = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  timer:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
  timer:SetJustifyH("RIGHT")
  timer:SetWidth(60)

  local label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  label:SetPoint("LEFT", bar, "LEFT", 6, 0)
  label:SetPoint("RIGHT", timer, "LEFT", -8, 0)
  label:SetJustifyH("LEFT")

  r.icon = icon
  r.bar = bar
  r.label = label
  r.timer = timer
  r.barBG = barBG

  self.rows[i] = r
  return r
end

function UI:HideExtraRows(fromIndex)
  for i = fromIndex, #self.rows do
    self.rows[i]:Hide()
  end
end

local function GetMaxScreenHeight()
  if UIParent and UIParent.GetHeight then
    return math.max(200, UIParent:GetHeight() - 140)
  end
  return 600
end

local function GetMaxScreenWidth()
  if UIParent and UIParent.GetWidth then
    return math.max(300, UIParent:GetWidth() - 80)
  end
  return 900
end

function UI:ComputeLayout(itemCount)
  -- No scrolling: choose columns so height fits on screen.
  local rowH = 22
  local gapY = 6
  local colW = 320
  local gapX = 14
  local topOverhead = 34 + 6 + 14 + 10  -- header + sub gap + list top + padding-ish
  local bottomPad = 18
  local maxH = GetMaxScreenHeight()
  local maxW = GetMaxScreenWidth()

  local maxCols = math.max(1, math.floor((maxW - 20) / (colW + gapX)))
  maxCols = math.min(maxCols, 5)

  local cols = 1
  local rowsPerCol = itemCount
  local height = topOverhead + bottomPad + rowsPerCol * rowH + math.max(0, rowsPerCol - 1) * gapY

  while height > maxH and cols < maxCols do
    cols = cols + 1
    rowsPerCol = math.ceil(itemCount / cols)
    height = topOverhead + bottomPad + rowsPerCol * rowH + math.max(0, rowsPerCol - 1) * gapY
  end

  local width = 20 + cols * colW + (cols - 1) * gapX
  width = math.min(width, maxW)

  return cols, rowsPerCol, width, math.min(height, maxH)
end

function UI:PositionRow(rowFrame, index, cols, rowsPerCol)
  local rowH = 22
  local gapY = 6
  local colW = 320
  local gapX = 14

  local col = math.floor((index - 1) / rowsPerCol)
  local row = (index - 1) % rowsPerCol

  local x = col * (colW + gapX)
  local y = -row * (rowH + gapY)

  rowFrame:ClearAllPoints()
  rowFrame:SetPoint("TOPLEFT", self.list, "TOPLEFT", x, y)
  rowFrame:SetSize(colW - 20, rowH)
end

function UI:UpdateBoard()
  if not self.frame then return end

  -- Build display items from roster (always), and overlay active/cd state if present.
  local items = self.rosterItems or {}
  local n = #items

  -- Auto-resize & multi-column to avoid scrolling
  local cols, rowsPerCol, w, h = self:ComputeLayout(n)
  if self.needsLayout or self.lastCols ~= cols or self.lastRowsPerCol ~= rowsPerCol then
    self.frame:SetSize(w, h)
    self.lastCols = cols
    self.lastRowsPerCol = rowsPerCol
    self.needsLayout = false
  end

  for i = 1, n do
    local d = items[i]
    local r = self:EnsureRow(i)
    self:PositionRow(r, i, cols, rowsPerCol)

    local sender = d.sender
    local cr, cg, cb = self:GetClassColorForSender(sender)

    -- Use tracker state if spell is currently active/cooling down
    local state = nil
    if ShortyRCD.Tracker and ShortyRCD.Tracker.GetState then
      state = ShortyRCD.Tracker:GetState(sender, d.spellID)
    end

    local labelText = ("%s - %s"):format(sender or "?", d.spellName or ("Spell " .. tostring(d.spellID)))
    r.label:SetText(labelText)

    if d.iconID then
      r.icon:SetTexture(d.iconID)
    else
      r.icon:SetTexture("Interface/Icons/INV_Misc_QuestionMark")
    end

    if state then
      local isActive = state.isActive
      local total = isActive and (state.ac > 0 and state.ac or 1) or (state.cd > 0 and state.cd or 1)
      local remaining = isActive and state.activeRemaining or state.cooldownRemaining
      local progress = 1.0
      if total > 0 then
        progress = math.max(0, math.min(1, remaining / total))
      end

      r.bar:SetMinMaxValues(0, 1)
      r.bar:SetValue(progress)

      if isActive then
        r.bar:SetStatusBarColor(cr, cg, cb, 0.90)
        r.timer:SetText(FormatTime(remaining))
        r.timer:SetTextColor(0.90, 0.92, 0.96, 1.0)
        r.label:SetTextColor(0.90, 0.92, 0.96, 1.0)
      else
        r.bar:SetStatusBarColor(cr * 0.35, cg * 0.35, cb * 0.35, 0.85)
        r.timer:SetText(FormatTime(remaining))
        r.timer:SetTextColor(0.70, 0.72, 0.76, 1.0)
        r.label:SetTextColor(0.70, 0.72, 0.76, 1.0)
      end
    else
      -- READY state (not currently on cooldown)
      r.bar:SetMinMaxValues(0, 1)
      r.bar:SetValue(1)
      r.bar:SetStatusBarColor(cr * 0.25, cg * 0.25, cb * 0.25, 0.85)
      r.timer:SetText("READY")
      r.timer:SetTextColor(0.60, 0.70, 0.60, 1.0)
      r.label:SetTextColor(0.80, 0.82, 0.86, 1.0)
    end

    r:Show()
  end

  if n == 0 and self.rows[1] then
    self:HideExtraRows(1)
  elseif n < #self.rows then
    self:HideExtraRows(n + 1)
  end
end

function UI:SavePosition()
  if not self.frame then return end
  local point, relTo, relPoint, x, y = self.frame:GetPoint(1)
  local relName = (relTo and relTo.GetName and relTo:GetName()) or "UIParent"
  ShortyRCDDB.frame.point = { point, relName, relPoint, x, y }
end

function UI:RestorePosition()
  if not self.frame then return end
  local p = ShortyRCDDB.frame.point
  if type(p) ~= "table" or #p < 5 then return end
  local rel = _G[p[2]] or UIParent
  self.frame:ClearAllPoints()
  self.frame:SetPoint(p[1], rel, p[3], p[4], p[5])
end

function UI:SetLocked(locked)
  ShortyRCDDB.locked = (locked == true)
  self:ApplyLockState()
end

function UI:ApplyLockState()
  if not self.frame then return end
  if ShortyRCDDB.locked then
    self.frame:EnableMouse(false)
  else
    self.frame:EnableMouse(true)
  end
end
