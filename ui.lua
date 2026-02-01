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
local GAP_Y   = 6
local GAP_X   = 14
local COL_W   = 320
local PAD_L   = 10
local PAD_R   = 10
local PAD_B   = 8

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
  self:RestoreSize()
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
          abbr = e.abbr, -- optional abbreviated label
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


  -- Resizing (Details-style bottom-right grip). Only visible/active when unlocked.
  f:SetResizable(true)
  if f.SetResizeBounds then
    f:SetResizeBounds(260, 180)
  end

  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:Hide()

  grip:SetScript("OnMouseDown", function(_, button)
    if button ~= "LeftButton" then return end
    if ShortyRCDDB.locked then return end
    f:StartSizing("BOTTOMRIGHT")
  end)

  grip:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    UI:SaveSize()
    UI.needsLayout = true
  end)

  f:HookScript("OnSizeChanged", function()
    if not (ShortyRCDDB and ShortyRCDDB.frame and ShortyRCDDB.frame.userSized) then return end

    -- Mark that a relayout is needed, but debounce the expensive rebuild so resizing feels smooth.
    UI.needsLayout = true
    UI._resizePending = true

    if UI._resizeScheduled then return end
    UI._resizeScheduled = true

    -- Debounce: run at most ~30fps during active resizing.
    C_Timer.After(0.03, function()
      UI._resizeScheduled = false
      if UI._resizePending then
        UI._resizePending = false
        UI:UpdateBoard()
      end
    end)
  end)

  self.sizeGrip = grip

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

  -- Display grouping: spell-first (default) or class-first (Option A: Category -> Class -> Spell -> Players)
  local grouping = (ShortyRCDDB and ShortyRCDDB.ui and ShortyRCDDB.ui.grouping) or "spell"
  if grouping == "class" and self.BuildDisplayLinesByClass then
    self:BuildDisplayLinesByClass()
    return
  end

  -- Default to raid-leader optimized grouping (spell -> players).
  -- Original flat layout is kept below as fallback.
  if self.BuildDisplayLinesGrouped then
    self:BuildDisplayLinesGrouped()
    return
  end

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


-- Raid-leader optimized layout: group by spell within each category.
function UI:BuildDisplayLinesGrouped()
  wipe(self.displayLines)

  -- category -> spellID -> bundle
  local byCatSpell = { DEFENSIVE = {}, HEALING = {}, UTILITY = {} }

  for _, it in ipairs(self.rosterItems or {}) do
    local cat = it.type or "UTILITY"
    if not byCatSpell[cat] then byCatSpell[cat] = {} end
    local sid = it.spellID
    if sid then
      local b = byCatSpell[cat][sid]
      if not b then
        b = { spellID = sid, spellName = it.spellName, abbr = it.abbr, iconID = it.iconID, items = {} }
        byCatSpell[cat][sid] = b
      end
      table.insert(b.items, it)
    end
  end

  local function SpellDisplayText(bundle)
    local mode = (ShortyRCDDB and ShortyRCDDB.ui and ShortyRCDDB.ui.spellNames) or "full"
    if mode == "short" then
      return bundle.abbr or bundle.spellName or ("Spell " .. tostring(bundle.spellID))
    elseif mode == "none" then
       -- Group headers must still identify the spell; "none" only applies to player rows
      return bundle.abbr or bundle.spellName or ("Spell " .. tostring(bundle.spellID))
    else
      return bundle.spellName or ("Spell " .. tostring(bundle.spellID))
    end
  end

  for _, catKey in ipairs(CATEGORY_ORDER) do
    local bucket = byCatSpell[catKey]
    if bucket then
      local spells = {}
      for _, b in pairs(bucket) do table.insert(spells, b) end

      table.sort(spells, function(a, b)
        return (SpellDisplayText(a) or "") < (SpellDisplayText(b) or "")
      end)

      if #spells > 0 then
        table.insert(self.displayLines, { kind = "header", text = CATEGORY_LABEL[catKey] or catKey, cat = catKey })

        for _, b in ipairs(spells) do
          table.insert(self.displayLines, {
            kind = "spell",
            cat = catKey,
            spellID = b.spellID,
            iconID = b.iconID,
            text = SpellDisplayText(b),
            count = #b.items,
          })

          table.sort(b.items, function(x, y) return (x.sender or "") < (y.sender or "") end)

          for _, it in ipairs(b.items) do
            it.onlySender = true
            table.insert(self.displayLines, { kind = "item", item = it, cat = catKey, indent = 1 })
          end

          table.insert(self.displayLines, { kind = "spacerSmall" })
        end
        table.insert(self.displayLines, { kind = "spacer" })
      end
    end
  end

  -- Trim trailing spacers
  while #self.displayLines > 0 and (self.displayLines[#self.displayLines].kind == "spacer" or self.displayLines[#self.displayLines].kind == "spacerSmall") do
    table.remove(self.displayLines, #self.displayLines)
  end
end


-- -------------------------------------------------
-- Grouping Mode: Category -> Class -> Spell -> Players
-- -------------------------------------------------
function UI:BuildDisplayLinesByClass()
  wipe(self.displayLines)

  -- category -> classToken -> spellID -> bundle
  local byCatClass = { DEFENSIVE = {}, HEALING = {}, UTILITY = {} }

  for _, it in ipairs(self.rosterItems or {}) do
    local cat = it.type or "UTILITY"
    if not byCatClass[cat] then byCatClass[cat] = {} end
    local ct = it.classToken or (self.classByName and self.classByName[it.sender]) or "UNKNOWN"
    local classBucket = byCatClass[cat][ct]
    if not classBucket then
      classBucket = {}
      byCatClass[cat][ct] = classBucket
    end

    local sid = it.spellID
    if sid then
      local b = classBucket[sid]
      if not b then
        b = { spellID = sid, spellName = it.spellName, abbr = it.abbr, iconID = it.iconID, items = {}, classToken = ct }
        classBucket[sid] = b
      end
      table.insert(b.items, it)
    end
  end

  local function SpellDisplayText(bundle)
    local mode = (ShortyRCDDB and ShortyRCDDB.ui and ShortyRCDDB.ui.spellNames) or "full"
    if mode == "short" then
      return bundle.abbr or bundle.spellName or ("Spell " .. tostring(bundle.spellID))
    elseif mode == "none" then
      -- Group headers must still identify the spell; "none" only applies to player rows
      return bundle.abbr or bundle.spellName or ("Spell " .. tostring(bundle.spellID))
    else
      return bundle.spellName or ("Spell " .. tostring(bundle.spellID))
    end
  end

  local function ClassDisplayText(classToken)
    -- Prefer WoW's localized class names if available
    local name = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classToken]) or (LOCALIZED_CLASS_NAMES_FEMALE and LOCALIZED_CLASS_NAMES_FEMALE[classToken]) or classToken
    return name or tostring(classToken or "UNKNOWN")
  end

  for _, catKey in ipairs(CATEGORY_ORDER) do
    local catBucket = byCatClass[catKey]
    if catBucket then
      -- collect classes present in this category
      local classes = {}
      for classToken, _ in pairs(catBucket) do
        -- Only include if the class has at least one spell bundle
        local hasAny = false
        for _sid, _b in pairs(catBucket[classToken]) do hasAny = true; break end
        if hasAny then
          table.insert(classes, classToken)
        end
      end

      table.sort(classes, function(a, b)
        return (ClassDisplayText(a) or "") < (ClassDisplayText(b) or "")
      end)

      local anyLines = false
      for _, classToken in ipairs(classes) do
        local spellMap = catBucket[classToken]
        local spells = {}
        for _, b in pairs(spellMap) do table.insert(spells, b) end

        table.sort(spells, function(a, b)
          return (SpellDisplayText(a) or "") < (SpellDisplayText(b) or "")
        end)

        if #spells > 0 then
          if not anyLines then
            table.insert(self.displayLines, { kind = "header", text = CATEGORY_LABEL[catKey] or catKey, cat = catKey })
            anyLines = true
          end

          table.insert(self.displayLines, { kind = "class", cat = catKey, classToken = classToken, text = ClassDisplayText(classToken) })

          for _, b in ipairs(spells) do
            table.insert(self.displayLines, {
              kind = "spell",
              cat = catKey,
              spellID = b.spellID,
              iconID = b.iconID,
              text = SpellDisplayText(b),
              count = #b.items,
            })

            table.sort(b.items, function(x, y) return (x.sender or "") < (y.sender or "") end)
            for _, it in ipairs(b.items) do
              it.onlySender = true
              table.insert(self.displayLines, { kind = "item", item = it, cat = catKey, indent = 1 })
            end
          end

          -- space between classes (not between spells)
          table.insert(self.displayLines, { kind = "spacerSmall" })
        end
      end

      if anyLines then
        table.insert(self.displayLines, { kind = "spacer" })
      end
    end
  end

  -- Trim trailing spacers
  while #self.displayLines > 0 and (self.displayLines[#self.displayLines].kind == "spacer" or self.displayLines[#self.displayLines].kind == "spacerSmall") do
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
    if line.kind == "header" then return ROW_H + 2 end
    if line.kind == "class" then return ROW_H - 4 end
    if line.kind == "class" then return ROW_H - 4 end
    if line.kind == "class" then return ROW_H - 4 end
    if line.kind == "spell" then return ROW_H - 4 end
    if line.kind == "spacer" then return 4 end
    if line.kind == "spacerSmall" then return 0 end
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
  local userSized = (ShortyRCDDB and ShortyRCDDB.frame and ShortyRCDDB.frame.userSized) == true
  local frameW = self.frame:GetWidth() or 360
  local colW = COL_W
  if userSized and cols > 0 then
    colW = math.floor((frameW - (PAD_L + PAD_R) - (cols - 1) * GAP_X) / cols)
    colW = math.max(240, colW)
  end
  local width = (PAD_L + PAD_R) + cols * colW + (cols - 1) * GAP_X
  width = math.min(width, GetMaxScreenWidth())

  -- Compute height as min(max column used height + overhead, max screen height),
  -- but "no scrolling" means we prefer more columns rather than clipping.
  local maxUsed = 0
  local function LineHeight(line)
    if line.kind == "header" then return ROW_H + 2 end
    if line.kind == "class" then return ROW_H - 4 end
    if line.kind == "class" then return ROW_H - 4 end
    if line.kind == "spell" then return ROW_H - 4 end
    if line.kind == "spacer" then return 4 end
    if line.kind == "spacerSmall" then return 2 end
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

  if (not userSized) and (self.needsLayout or self.lastW ~= width or self.lastH ~= height) then
    self.frame:SetSize(width, height)
    self.lastW, self.lastH = width, height
    self.needsLayout = false
  else
    -- If the user manually sized the frame, do not override it.
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
      r:SetSize(colW - 20, ROW_H)

      local indentPx = 0 -- default (spell headers should not indent)

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
        y = y + (ROW_H + 2) + GAP_Y
        rowIndex = rowIndex + 1
      elseif line.kind == "class" then
        -- Class sub-header: class name (colored)
        local classToken = line.classToken
        local classText = line.text or tostring(classToken or "")
        local c = (RAID_CLASS_COLORS and classToken and RAID_CLASS_COLORS[classToken])
        r.bg:Hide()
        r.barBG:Hide()
        r.bar:Hide()
        r.timer:Hide()
        r.label:Hide()
        r.icon:Hide()
        r.headerText:Show()
        r.headerText:ClearAllPoints()
        -- Indent class header slightly under category
        r.headerText:SetPoint("LEFT", r, "LEFT", 8, 0)
        if c then
          local rr = math.floor((c.r or 1)*255 + 0.5)
          local gg = math.floor((c.g or 1)*255 + 0.5)
          local bb = math.floor((c.b or 1)*255 + 0.5)
          r.headerText:SetText(string.format("|cff%02x%02x%02x%s|r", rr, gg, bb, classText))
        else
          r.headerText:SetText("|cffffffff" .. classText .. "|r")
        end
        r:Show()
        y = y + (ROW_H - 4) + GAP_Y
        rowIndex = rowIndex + 1
      elseif line.kind == "spell" then
        -- Spell sub-header: icon + name + count (no progress bar)
        local iconID = line.iconID
        local spellText = line.text or ""
        local count = tonumber(line.count) or 0

        r.bg:Hide()
        r.barBG:Hide()
        r.bar:Hide()
        r.timer:Hide()
        r.label:Hide()

        r.icon:Show()
        r.icon:ClearAllPoints()
        r.icon:SetPoint("LEFT", r, "LEFT", 2 + indentPx, 0)
        r.headerText:Show()
        r.icon:ClearAllPoints()
        r.icon:SetPoint("LEFT", r, "LEFT", 2, 0)

        if iconID then
          r.icon:SetTexture(iconID)
        else
          r.icon:SetTexture("Interface/Icons/INV_Misc_QuestionMark")
        end

        local catTint = "|cffb0bec5"
        if line.cat == "HEALING" then catTint = "|cff66bb6a" end
        if line.cat == "DEFENSIVE" then catTint = "|cff42a5f5" end
        if line.cat == "UTILITY" then catTint = "|cffffca28" end

        local label = ""
        if spellText ~= "" then
          label = spellText .. " "
        end
        label = label .. catTint .. "(" .. tostring(count) .. ")" .. "|r"

        r.headerText:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
        r.headerText:SetText("|cffcfd8dc" .. label .. "|r")

        r:Show()
        y = y + (ROW_H - 4) + GAP_Y
        rowIndex = rowIndex + 1
      elseif line.kind == "spacer" then
        r:Hide()
        y = y + 2
      elseif line.kind == "spacerSmall" then
        r:Hide()
        y = y + 0
      else
        -- Item row
        local d = line.item
        local sender = d.sender
        local cr, cg, cb = self:GetClassColorForSender(sender)

        r.headerText:Hide()

        local indentPx = (line.indent == 1) and 14 or 0
        r.bg:Show()
        r.icon:Show()
        r.barBG:Show()
        r.bar:Show()
        r.label:Show()
        r.timer:Show()

        local senderHex = RGBToHex(cr, cg, cb)
        local senderText = ("|cff%s%s|r"):format(senderHex, sender or "?")
        local onlySender = (d.onlySender == true)
        local bullet = (line.indent == 1) and "|cff90a4ae> |r" or ""

        local mode = (ShortyRCDDB and ShortyRCDDB.ui and ShortyRCDDB.ui.spellNames) or "full"
        local spellText = ""
        if mode == "full" then
          spellText = d.spellName or ("Spell " .. tostring(d.spellID))
        elseif mode == "short" then
          spellText = d.abbr or d.spellName or ("Spell " .. tostring(d.spellID))
        elseif mode == "none" then
          spellText = ""
        else
          spellText = d.spellName or ("Spell " .. tostring(d.spellID))
        end

        if onlySender then
          spellText = ""
        end

        local labelText
        if spellText ~= "" then
          labelText = bullet .. ("%s - %s"):format(senderText, spellText)
        else
          labelText = bullet .. senderText
        end
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

    startX = startX + colW + GAP_X
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

function UI:SaveSize()
  if not self.frame then return end
  ShortyRCDDB.frame.size = ShortyRCDDB.frame.size or {}
  ShortyRCDDB.frame.size.w = self.frame:GetWidth()
  ShortyRCDDB.frame.size.h = self.frame:GetHeight()
  ShortyRCDDB.frame.userSized = true
end

function UI:RestoreSize()
  if not self.frame then return end
  local s = ShortyRCDDB.frame.size
  if type(s) ~= "table" then return end
  local w = tonumber(s.w)
  local h = tonumber(s.h)
  if w and h and w > 0 and h > 0 then
    self.frame:SetSize(w, h)
    self.lastW, self.lastH = w, h
    ShortyRCDDB.frame.userSized = true
  end
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
    if self.sizeGrip then self.sizeGrip:Hide() end
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
    if self.sizeGrip then self.sizeGrip:Show() end
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