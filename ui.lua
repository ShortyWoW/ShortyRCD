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

local function RGBToHex(r, g, b)
  r = math.max(0, math.min(1, tonumber(r) or 1))
  g = math.max(0, math.min(1, tonumber(g) or 1))
  b = math.max(0, math.min(1, tonumber(b) or 1))
  return string.format("%02x%02x%02x", math.floor(r*255 + 0.5), math.floor(g*255 + 0.5), math.floor(b*255 + 0.5))
end

-- Preferred UI font (Expressway). Place the file at:
-- Interface\AddOns\ShortyRCD\Media\Expressway.ttf
local PREFERRED_FONT = "Interface\\AddOns\\ShortyRCD\\Media\\Expressway.ttf"

local function GetFallbackFont()
  if GameFontNormal and GameFontNormal.GetFont then
    local f = GameFontNormal:GetFont()
    if f then return f end
  end
  return "Fonts\\FRIZQT__.TTF"
end

local function SetFontSafe(fontString, size, flags)
  if not fontString or not fontString.SetFont then return end
  size = size or 12
  flags = flags or ""
  local ok = fontString:SetFont(PREFERRED_FONT, size, flags)
  if not ok then
    fontString:SetFont(GetFallbackFont(), size, flags)
  end
end



-- Category order + display names
local CATEGORY_ORDER = { "DEFENSIVE", "HEALING", "UTILITY" }
local CATEGORY_LABEL = {
  DEFENSIVE = "Defensive CDs",
  HEALING   = "Healing CDs",
  UTILITY   = "Utility CDs",
}

-- Layout constants (compact, raid-friendly)
local ROW_H   = 18
local GAP_Y   = 3
local GAP_X   = 14
local COL_W   = 320
local PAD_L   = 10
local PAD_R   = 10
local PAD_B   = 10

local function GetMaxScreenHeight()
  if UIParent and UIParent.GetHeight then
    return math.max(240, UIParent:GetHeight() - 140)
  end
  return 650
end

local function GetMaxScreenWidth()
  if UIParent and UIParent.GetWidth then
    return math.max(360, UIParent:GetWidth() - 80)
  end
  return 1000
end

function UI:Init()
  self.rows = {}            -- pooled row frames (headers + items)
  self.classByName = {}     -- shortName -> classToken
  self.rosterItems = {}     -- raw items from roster
  self.displayLines = {}    -- flattened lines: {kind="header"/"item", ...}

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
        local tracked = true
        if ShortyRCD and ShortyRCD.IsTracked then
          tracked = ShortyRCD:IsTracked(classToken, e.spellID)
        end
        if tracked then
        table.insert(self.rosterItems, {
          sender = short,
          classToken = classToken,
          spellID = e.spellID,
          spellName = e.name or ("Spell " .. tostring(e.spellID)),
          iconID = e.iconID,
          type = (e.type and tostring(e.type):upper()) or "UTILITY",
          cd = tonumber(e.cd) or 0,
          ac = tonumber(e.ac) or 0,
        })
              end
      end
    end
  end

  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      AddUnit("raid" .. i)
    end
  elseif IsInGroup() then
    AddUnit("player")
    for i = 1, GetNumSubgroupMembers() do
      AddUnit("party" .. i)
    end
  else
    AddUnit("player")
  end

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
  f:SetSize(360, 260)
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
  self.title = title

  
  SetFontSafe(title, 16, "")
local sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 10, -6)
  sub:SetText("")
  sub:Hide()

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
  list:SetPoint("TOPLEFT", header, "BOTTOMLEFT", PAD_L, -10)
  list:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD_L, PAD_B)
  list:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD_R, -46)
  self.list = list
end

-- Row pool: header rows and item rows share the same frame type, but style differs.
function UI:EnsureRow(i)
  if self.rows[i] then return self.rows[i] end

  local parent = self.list
  local r = CreateFrame("Frame", nil, parent)
  r:SetSize(COL_W - 20, ROW_H)

  -- Background (for items)
  local bg = CreateFrame("Frame", nil, r, "BackdropTemplate")
  bg:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
  bg:SetBackdrop({
    bgFile = "Interface/ChatFrame/ChatFrameBackground",
    edgeFile = "Interface/ChatFrame/ChatFrameBackground",
    tile = true, tileSize = 16, edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 }
  })
  bg:SetBackdropColor(0.05, 0.06, 0.08, 0.55)
  bg:SetBackdropBorderColor(0.12, 0.13, 0.16, 0.9)

  -- Icon
  local icon = r:CreateTexture(nil, "ARTWORK")
  icon:SetSize(16, 16)
  icon:SetPoint("LEFT", r, "LEFT", 4, 0)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  -- Status bar background
  local barBG = CreateFrame("Frame", nil, r, "BackdropTemplate")
  barBG:SetPoint("LEFT", icon, "RIGHT", 6, 0)
  barBG:SetPoint("RIGHT", r, "RIGHT", -4, 0)
  barBG:SetHeight(16)
  barBG:SetBackdrop({
    bgFile = "Interface/ChatFrame/ChatFrameBackground",
    edgeFile = "Interface/ChatFrame/ChatFrameBackground",
    tile = true, tileSize = 16, edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 }
  })
  barBG:SetBackdropColor(0.03, 0.03, 0.04, 0.85)
  barBG:SetBackdropBorderColor(0.14, 0.15, 0.18, 1.0)

  local bar = CreateFrame("StatusBar", nil, barBG)
  bar:SetPoint("TOPLEFT", barBG, "TOPLEFT", 1, -1)
  bar:SetPoint("BOTTOMRIGHT", barBG, "BOTTOMRIGHT", -1, 1)
  bar:SetStatusBarTexture("Interface/TargetingFrame/UI-StatusBar")
  bar:SetMinMaxValues(0, 1)
  bar:SetValue(1)

  -- Timer text fixed width to prevent overlap
  local timer = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  timer:SetPoint("RIGHT", bar, "RIGHT", -5, 0)
  timer:SetJustifyH("RIGHT")
  timer:SetWidth(58)

  SetFontSafe(timer, 12, "")

  local label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  label:SetPoint("LEFT", bar, "LEFT", 5, 0)
  label:SetPoint("RIGHT", timer, "LEFT", -6, 0)
  label:SetJustifyH("LEFT")

  SetFontSafe(label, 12, "")

  -- Header label (for category headers)
  local headerText = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  headerText:SetPoint("LEFT", r, "LEFT", 0, 0)
  headerText:SetJustifyH("LEFT")

  SetFontSafe(headerText, 12, "OUTLINE")

  r.bg = bg
  r.icon = icon
  r.barBG = barBG
  r.bar = bar
  r.label = label
  r.timer = timer
  r.headerText = headerText

  self.rows[i] = r
  return r
end

function UI:HideExtraRows(fromIndex)
  for i = fromIndex, #self.rows do
    self.rows[i]:Hide()
  end
end

-- Build display lines grouped by category. If a category wraps to a new column,
-- we repeat the header with " (cont)".
function UI:BuildDisplayLines()
  wipe(self.displayLines)

  -- Group items by category
  local byCat = { DEFENSIVE = {}, HEALING = {}, UTILITY = {} }
  for _, it in ipairs(self.rosterItems or {}) do
    local cat = it.type or "UTILITY"
    if not byCat[cat] then byCat[cat] = {} end
    table.insert(byCat[cat], it)
  end

  -- Sort within each category: by player then by spell name
  for _, cat in pairs(byCat) do
    table.sort(cat, function(a, b)
      if a.sender ~= b.sender then return a.sender < b.sender end
      return (a.spellName or "") < (b.spellName or "")
    end)
  end

  for _, catKey in ipairs(CATEGORY_ORDER) do
    local list = byCat[catKey]
    if list and #list > 0 then
      table.insert(self.displayLines, { kind = "header", text = CATEGORY_LABEL[catKey] or catKey, cat = catKey })
      for _, it in ipairs(list) do
        table.insert(self.displayLines, { kind = "item", item = it, cat = catKey })
      end
      table.insert(self.displayLines, { kind = "spacer" })
    end
  end

  -- Remove trailing spacer
  if #self.displayLines > 0 and self.displayLines[#self.displayLines].kind == "spacer" then
    table.remove(self.displayLines, #self.displayLines)
  end
end

-- Compute how many columns are needed so that each column height <= maxH.
-- We flow line-by-line into columns (like text), repeating category headers when wrapping mid-category.
function UI:ComputeFlowColumns(lines)
  local maxH = GetMaxScreenHeight()

  -- Available vertical space inside list
  local topOverhead = 34 + 6 + 16 + 16
  local usableH = math.max(200, maxH - topOverhead)

  local function LineHeight(line)
    if line.kind == "header" then return ROW_H + 4 end
    if line.kind == "spacer" then return 8 end
    return ROW_H
  end

  local columns = { {} }
  local colIndex = 1
  local y = 0

  local lastHeader = nil

  for i = 1, #lines do
    local line = lines[i]
    local h = LineHeight(line)

    -- If this line won't fit, wrap to next column
    if y > 0 and (y + h) > usableH then
      colIndex = colIndex + 1
      columns[colIndex] = {}
      y = 0

      -- If we wrapped in the middle of a category (next line is item),
      -- repeat the last header as "(cont)" at top of new column.
      if lastHeader then
        table.insert(columns[colIndex], { kind="header", text=lastHeader.text .. " (cont)", cat=lastHeader.cat, cont=true })
        y = y + LineHeight({kind="header"}) + GAP_Y
      end
    end

    table.insert(columns[colIndex], line)
    if line.kind == "header" then
      lastHeader = line
      y = y + h + GAP_Y
    elseif line.kind == "spacer" then
      y = y + h
    else
      y = y + h + GAP_Y
    end

    -- If the next line is a header, reset lastHeader so we don't "cont" across categories.
    local nextLine = lines[i+1]
    if nextLine and nextLine.kind == "header" then
      lastHeader = nil
    end
  end

  -- Width constraints
  local maxW = GetMaxScreenWidth()
  local maxCols = math.max(1, math.floor((maxW - 20) / (COL_W + GAP_X)))
  maxCols = math.min(maxCols, 6)

  -- If we exceeded max columns, just clamp (will overflow vertically).
  if #columns > maxCols then
    columns = { lines } -- fallback to single stream
  end

  return columns, usableH
end

function UI:UpdateBoard()
  if not self.frame then return end

  self:BuildDisplayLines()
  local lines = self.displayLines
  local columns, usableH = self:ComputeFlowColumns(lines)

  local cols = #columns
  local width = (PAD_L + PAD_R) + cols * COL_W + (cols - 1) * GAP_X
  width = math.min(width, GetMaxScreenWidth())

  -- Compute height as min(max column used height + overhead, max screen height),
  -- but "no scrolling" means we prefer more columns rather than clipping.
  local maxUsed = 0
  local function LineHeight(line)
    if line.kind == "header" then return ROW_H + 4 end
    if line.kind == "spacer" then return 8 end
    return ROW_H
  end
  for _, colLines in ipairs(columns) do
    local y = 0
    for _, line in ipairs(colLines) do
      local h = LineHeight(line)
      if line.kind == "spacer" then
        y = y + h
      else
        y = y + h + GAP_Y
      end
    end
    if y > maxUsed then maxUsed = y end
  end

  local topOverhead = 34 + 6 + 16 + 22 + 18
  local height = math.min(GetMaxScreenHeight(), topOverhead + maxUsed)
  height = math.max(200, height)

  if self.needsLayout or self.lastW ~= width or self.lastH ~= height then
    self.frame:SetSize(width, height)
    self.lastW, self.lastH = width, height
    self.needsLayout = false
  end

  -- Render
  local rowIndex = 1
  local startX = 0

  for col = 1, cols do
    local colLines = columns[col]
    local y = 0

    for _, line in ipairs(colLines) do
      local r = self:EnsureRow(rowIndex)
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", self.list, "TOPLEFT", startX, -y)
      r:SetSize(COL_W - 20, ROW_H)

      if line.kind == "header" then
        -- Header styling: no icon/bar, just text
        r.bg:Hide()
        r.icon:Hide()
        r.barBG:Hide()
        r.headerText:Show()
        r.headerText:SetPoint("LEFT", r, "LEFT", 2, 0)
        r.headerText:SetText("|cff4fc3f7" .. (line.text or "") .. "|r")
        r.headerText:SetTextColor(0.31, 0.76, 0.97, 1.0)

        r.label:Hide()
        r.timer:Hide()
        r.bar:Hide()

        r:Show()
        y = y + (ROW_H + 4) + GAP_Y
        rowIndex = rowIndex + 1
      elseif line.kind == "spacer" then
        r:Hide()
        y = y + 8
      else
        -- Item row
        local d = line.item
        local sender = d.sender
        local cr, cg, cb = self:GetClassColorForSender(sender)

        r.headerText:Hide()
        r.bg:Show()
        r.icon:Show()
        r.barBG:Show()
        r.bar:Show()
        r.label:Show()
        r.timer:Show()

        local senderHex = RGBToHex(cr, cg, cb)
        local senderText = ("|cff%s%s|r"):format(senderHex, sender or "?")
        local labelText = ("%s - %s"):format(senderText, d.spellName or ("Spell " .. tostring(d.spellID)))
        r.label:SetText(labelText)

        if d.iconID then
          r.icon:SetTexture(d.iconID)
        else
          r.icon:SetTexture("Interface/Icons/INV_Misc_QuestionMark")
        end

        local state = nil
        if ShortyRCD.Tracker and ShortyRCD.Tracker.GetState then
          state = ShortyRCD.Tracker:GetState(sender, d.spellID)
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
            r.bar:SetStatusBarColor(cr * 0.30, cg * 0.30, cb * 0.30, 0.85)
            r.timer:SetText(FormatTime(remaining))
            r.timer:SetTextColor(0.92, 0.55, 0.55, 1.0) -- red-ish like raid addons
            r.label:SetTextColor(0.78, 0.80, 0.84, 1.0)
          end
        else
          -- READY state: no progression needed; keep subtle bar & green READY
          r.bar:SetMinMaxValues(0, 1)
          r.bar:SetValue(1)
          r.bar:SetStatusBarColor(cr * 0.22, cg * 0.22, cb * 0.22, 0.85)
          r.timer:SetText("READY")
          r.timer:SetTextColor(0.35, 0.90, 0.50, 1.0)
          r.label:SetTextColor(0.82, 0.84, 0.88, 1.0)
        end

        r:Show()
        y = y + ROW_H + GAP_Y
        rowIndex = rowIndex + 1
      end
    end

    startX = startX + COL_W + GAP_X
  end

  self:HideExtraRows(rowIndex)
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

  local locked = (ShortyRCDDB and ShortyRCDDB.locked) == true

  -- Movement interaction
  self.frame:EnableMouse(not locked)

  if locked then
    -- Transparent container/header/title. Keep categories + spell rows visible.
    self.frame:SetBackdropColor(0.07, 0.08, 0.10, 0.00)
    self.frame:SetBackdropBorderColor(0.12, 0.13, 0.16, 0.00)

    if self.header then
      self.header:SetBackdropColor(0.05, 0.06, 0.08, 0.00)
      self.header:SetBackdropBorderColor(0.12, 0.13, 0.16, 0.00)
    end

    if self.title then
      self.title:SetAlpha(0.0)
    end
  else
    self.frame:SetBackdropColor(0.07, 0.08, 0.10, 0.92)
    self.frame:SetBackdropBorderColor(0.12, 0.13, 0.16, 1.00)

    if self.header then
      self.header:SetBackdropColor(0.05, 0.06, 0.08, 0.98)
      self.header:SetBackdropBorderColor(0.12, 0.13, 0.16, 1.00)
    end

    if self.title then
      self.title:SetAlpha(1.0)
    end
  end
end