-- options.lua
ShortyRCD = ShortyRCD or {}
ShortyRCD.Options = ShortyRCD.Options or {}

-- Font cache (computed once)
ShortyRCD.Options._fontPath = nil


-- -------------------------------------------------
-- Helpers
-- -------------------------------------------------

-- -------------------------------------------------
-- Font Handling
-- -------------------------------------------------

function ShortyRCD.Options:GetFontPath()
  -- Return cached result if we already tested it
  if self._fontPath then
    return self._fontPath
  end

  local customPath = "Fonts\\Expressway.ttf"

  -- Test if WoW can load it (no direct file-exists API, so we probe SetFont)
  local testFrame = CreateFrame("Frame")
  local fs = testFrame:CreateFontString(nil, "OVERLAY")
  local ok = fs:SetFont(customPath, 12)

  if ok then
    self._fontPath = customPath
  else
    self._fontPath = STANDARD_TEXT_FONT
  end

  return self._fontPath
end



local CLASS_ICON_TEX = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"

-- Spell row indentation (px)
local SPELL_INDENT = 10

local function ClassColorText(classToken, text)
  local c = (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]) or nil
  if c then
    return string.format("|cFF%02X%02X%02X%s|r", c.r * 255, c.g * 255, c.b * 255, text)
  end
  return text
end

local function PrettyType(t)
  t = tostring(t or ""):upper()
  if t == "DEFENSIVE" then return "Defensive" end
  if t == "HEALING"   then return "Healing" end
  if t == "UTILITY"   then return "Utility" end
  return "Other"
end

-- Subtle type colors (not neon)
local function TypeColorCode(t)
  t = tostring(t or ""):upper()
  if t == "HEALING" then   return "FF7BD88F" end -- soft green
  if t == "UTILITY" then   return "FF7FB7FF" end -- soft blue
  if t == "DEFENSIVE" then return "FFFFD36A" end -- soft gold
  return "FFCCCCCC"
end

local function ColorizeType(t)
  local pretty = PrettyType(t)
  local hex = TypeColorCode(t)
  return string.format("|c%s%s|r", hex, pretty)
end

local function FormatCooldownSeconds(sec)
  sec = tonumber(sec) or 0
  if sec <= 0 then return "" end

  if sec < 60 then
    return string.format("%ds", sec)
  end

  if (sec % 60) == 0 then
    return string.format("%dm", sec / 60)
  end

  if (sec % 30) == 0 then
    return string.format("%.1fm", sec / 60)
  end

  return string.format("%ds", sec)
end

local function SetClassIcon(tex, classToken)
  if not tex then return end
  tex:SetTexture(CLASS_ICON_TEX)

  if CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classToken] then
    local coords = CLASS_ICON_TCOORDS[classToken]
    tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
  else
    tex:SetTexCoord(0, 1, 0, 1)
  end
end

local function CreateSpellIcon(parent, iconID)
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetSize(18, 18)
  -- AFTER checkbox, plus indent for hierarchy
  t:SetPoint("LEFT", parent, "LEFT", 24 + SPELL_INDENT, 0)
  if iconID then t:SetTexture(iconID) end
  t:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  return t
end

local function CreateLeftLabel(parent, text)
  local fs = parent:CreateFontString(nil, "ARTWORK")
  local fontPath = ShortyRCD.Options:GetFontPath()
  fs:SetFont(fontPath, 13)
  fs:SetTextColor(1, 1, 1)

  fs:SetPoint("LEFT", parent, "LEFT", 46 + SPELL_INDENT, 0)
  fs:SetJustifyH("LEFT")
  fs:SetText(text or "")
  return fs
end

local function CreateRightTag(parent, text)
  local fs = parent:CreateFontString(nil, "ARTWORK")
  local fontPath = ShortyRCD.Options:GetFontPath()
  fs:SetFont(fontPath, 12)
  fs:SetTextColor(0.85, 0.85, 0.85)

  fs:SetPoint("RIGHT", parent, "RIGHT", -10, 0)
  fs:SetJustifyH("RIGHT")
  fs:SetText(text or "")
  return fs
end

local function CreateCheckboxRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(22)

  local cb = CreateFrame("CheckButton", nil, row, "InterfaceOptionsCheckButtonTemplate")
  cb:SetPoint("LEFT", SPELL_INDENT, 0) -- indent the checkbox for hierarchy
  cb.Text:SetText("")
  row.checkbox = cb

  return row
end

local function NukeChildren(frame)
  if not frame or not frame.GetNumChildren then return end
  local children = { frame:GetChildren() }
  for _, child in ipairs(children) do
    child:Hide()
    child:SetParent(nil)
  end
end

local function GetClassOrder()
  if ShortyRCD.ClassOrder and #ShortyRCD.ClassOrder > 0 then
    return ShortyRCD.ClassOrder
  end
  local order = {}
  if ShortyRCD.ClassDisplay then
    for k in pairs(ShortyRCD.ClassDisplay) do
      table.insert(order, k)
    end
    table.sort(order)
  end
  return order
end

-- -------------------------------------------------
-- Options Panel
-- -------------------------------------------------

function ShortyRCD.Options:Init()
  self:CreatePanel()
  self:RegisterPanel()
end

function ShortyRCD.Options:Open()
  if not self.panel then return end

  if Settings and Settings.OpenToCategory and self.category then
    Settings.OpenToCategory(self.category:GetID())
    return
  end

  if InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory(self.panel)
    InterfaceOptionsFrame_OpenToCategory(self.panel) -- quirk
    return
  end

  ShortyRCD:Print("Could not open options in this client build.")
end

function ShortyRCD.Options:CreatePanel()
  if self.panel then return end

  local p = CreateFrame("Frame", "ShortyRCDOptionsPanel", UIParent)
  local panel = p -- alias for legacy code paths
  p.name = "ShortyRCD"

  local title = p:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("ShortyRCD")

  local subtitle = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  subtitle:SetText("Configure raid cooldown tracking. Use /srcd to open this page.")

  -- Frame controls
  local lockCB = CreateFrame("CheckButton", nil, p, "InterfaceOptionsCheckButtonTemplate")
  lockCB.Text:SetText("Lock display frame")
  lockCB:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", -2, -16)
  lockCB:SetChecked(ShortyRCDDB.locked)

  lockCB:SetScript("OnClick", function(self)
    ShortyRCDDB.locked = self:GetChecked()
    if ShortyRCD.UI then ShortyRCD.UI:ApplyLockState() end
  end)

  local moveBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  moveBtn:SetSize(120, 22)
  moveBtn:SetPoint("LEFT", lockCB.Text, "RIGHT", 14, 0)
  moveBtn:SetText("Move Frame")
  moveBtn:SetScript("OnClick", function()
    ShortyRCDDB.locked = false
    lockCB:SetChecked(false)
    if ShortyRCD.UI then ShortyRCD.UI:ApplyLockState() end
    ShortyRCD:Print("Frame unlocked. Drag it, then re-lock here.")
  end)

  -- Spell name display mode: Full | Short | None
  ShortyRCDDB.ui = ShortyRCDDB.ui or {}
  if not ShortyRCDDB.ui.spellNames then ShortyRCDDB.ui.spellNames = "full" end
  if not ShortyRCDDB.ui.grouping then ShortyRCDDB.ui.grouping = "spell" end

  local snLabel = p:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  snLabel:SetPoint("TOPLEFT", moveBtn, "BOTTOMLEFT", 0, -14)
  snLabel:SetText("Spell Names:")

  local fullCB = CreateFrame("CheckButton", nil, p, "InterfaceOptionsCheckButtonTemplate")
  fullCB.Text:SetText("Full")
  fullCB:SetPoint("TOPLEFT", snLabel, "BOTTOMLEFT", -2, -6)

  local shortCB = CreateFrame("CheckButton", nil, p, "InterfaceOptionsCheckButtonTemplate")
  shortCB.Text:SetText("Short")
  shortCB:SetPoint("LEFT", fullCB.Text, "RIGHT", 26, 0)

  local noneCB = CreateFrame("CheckButton", nil, p, "InterfaceOptionsCheckButtonTemplate")
  noneCB.Text:SetText("None")
  noneCB:SetPoint("LEFT", shortCB.Text, "RIGHT", 26, 0)

  local function ApplySpellNameMode(mode)
    ShortyRCDDB.ui.spellNames = mode
    fullCB:SetChecked(mode == "full")
    shortCB:SetChecked(mode == "short")
    noneCB:SetChecked(mode == "none")

    if ShortyRCD and ShortyRCD.UI and ShortyRCD.UI.RefreshRoster then
      ShortyRCD.UI:RefreshRoster()
    elseif ShortyRCD and ShortyRCD.UI and ShortyRCD.UI.UpdateBoard then
      ShortyRCD.UI:UpdateBoard()
    end
  end

  fullCB:SetScript("OnClick", function() ApplySpellNameMode("full") end)
  shortCB:SetScript("OnClick", function() ApplySpellNameMode("short") end)
  noneCB:SetScript("OnClick", function() ApplySpellNameMode("none") end)

  -- Grouping mode: By Spell | By Class
  local grpLabel = p:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  grpLabel:SetPoint("TOPLEFT", fullCB, "BOTTOMLEFT", 2, -14)
  grpLabel:SetText("Grouping:")

  local bySpellCB = CreateFrame("CheckButton", nil, p, "InterfaceOptionsCheckButtonTemplate")
  bySpellCB.Text:SetText("By Spell")
  bySpellCB:SetPoint("TOPLEFT", grpLabel, "BOTTOMLEFT", -2, -6)

  local byClassCB = CreateFrame("CheckButton", nil, p, "InterfaceOptionsCheckButtonTemplate")
  byClassCB.Text:SetText("By Class")
  byClassCB:SetPoint("LEFT", bySpellCB.Text, "RIGHT", 26, 0)

  local byMinCB = CreateFrame("CheckButton", nil, p, "InterfaceOptionsCheckButtonTemplate")
  byMinCB.Text:SetText("Minimalist")
  byMinCB:SetPoint("LEFT", byClassCB.Text, "RIGHT", 26, 0)

  local function ApplyGrouping(mode)
    ShortyRCDDB.ui.grouping = mode
    bySpellCB:SetChecked(mode == "spell")
    byClassCB:SetChecked(mode == "class")
    byMinCB:SetChecked(mode == "minimal")

    if ShortyRCD and ShortyRCD.UI and ShortyRCD.UI.UpdateBoard then
      ShortyRCD.UI:UpdateBoard()
    elseif ShortyRCD and ShortyRCD.UI and ShortyRCD.UI.RefreshRoster then
      ShortyRCD.UI:RefreshRoster()
    end
  end

  bySpellCB:SetScript("OnClick", function() ApplyGrouping("spell") end)
  byClassCB:SetScript("OnClick", function() ApplyGrouping("class") end)
  byMinCB:SetScript("OnClick", function() ApplyGrouping("minimal") end)

  -- Initialize checks
  ApplyGrouping(ShortyRCDDB.ui.grouping or "spell")

  ApplySpellNameMode(ShortyRCDDB.ui.spellNames)


  -- Tracking header
  local trackingHeader = p:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  trackingHeader:SetPoint("TOPLEFT", fullCB, "BOTTOMLEFT", 2, -18)
  trackingHeader:SetText("Tracking")

  -- Fix layout: ensure Tracking section starts below Grouping options (avoid overlap)
  trackingHeader:ClearAllPoints()
  trackingHeader:SetPoint("TOPLEFT", bySpellCB, "BOTTOMLEFT", 2, -18)

  -- Scroll container
  local scrollFrame = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
  scrollFrame:SetPoint("TOPLEFT", trackingHeader, "BOTTOMLEFT", 0, -10)
  scrollFrame:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -30, 12)

  local scrollChild = CreateFrame("Frame", nil, scrollFrame)
  scrollChild:SetSize(1, 1)
  scrollFrame:SetScrollChild(scrollChild)

  self.panel = p
  self.scrollFrame = scrollFrame
  self.scrollChild = scrollChild

  -- Rebuild list when panel is shown (ensures sizes are real)
  p:SetScript("OnShow", function()
    ShortyRCD.Options:RebuildTrackingList()
  end)

  -- Keep width correct if resized
  scrollFrame:SetScript("OnSizeChanged", function()
    ShortyRCD.Options:UpdateScrollChildWidth()
  end)
end

function ShortyRCD.Options:UpdateScrollChildWidth()
  if not self.scrollFrame or not self.scrollChild then return end
  local w = self.scrollFrame:GetWidth()
  if not w or w <= 0 then return end
  -- scrollbar/padding
  self.scrollChild:SetWidth(math.max(1, w - 28))
end

function ShortyRCD.Options:RebuildTrackingList()
  if not self.scrollChild then return end
  self._fontPath = nil

  self:UpdateScrollChildWidth()
  NukeChildren(self.scrollChild)

  local child = self.scrollChild
  local y = -4

  -- Store checkbox refs by class so Enable/Disable All updates UI
  local classCheckboxes = {}

  local classOrder = GetClassOrder()
  local classLib = ShortyRCD.ClassLib or {}

  local function AddClassBlock(classToken)
    local className = (ShortyRCD.ClassDisplay and ShortyRCD.ClassDisplay[classToken]) or classToken
    local spells = classLib[classToken] or {}

    -- Class header row
    local header = CreateFrame("Frame", nil, child)
    header:SetHeight(20)
    header:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
    header:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, y)

    local icon = header:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", 0, 0)
    SetClassIcon(icon, classToken)

    local headerText = header:CreateFontString(nil, "ARTWORK")
    local fontPath = ShortyRCD.Options:GetFontPath()
    headerText:SetFont(fontPath, 14)
    headerText:SetTextColor(1, 0.82, 0)

    headerText:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    headerText:SetText(ClassColorText(classToken, className))

    -- Enable/Disable All buttons (right side)
    local disableBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    disableBtn:SetSize(90, 18)
    disableBtn:SetPoint("RIGHT", header, "RIGHT", 0, 0)
    disableBtn:SetText("Disable All")

    local enableBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    enableBtn:SetSize(80, 18)
    enableBtn:SetPoint("RIGHT", disableBtn, "LEFT", -6, 0)
    enableBtn:SetText("Enable All")

    y = y - 22

    classCheckboxes[classToken] = classCheckboxes[classToken] or {}

    if #spells == 0 then
      enableBtn:Disable()
      disableBtn:Disable()

      local none = child:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
      none:SetPoint("TOPLEFT", child, "TOPLEFT", 24, y)
      none:SetText("(no raid cooldowns)")
      y = y - 18
      y = y - 8
      return
    end

    enableBtn:SetScript("OnClick", function()
      for _, s in ipairs(spells) do
        ShortyRCD:SetTracked(classToken, s.spellID, true)
      end
      for _, cb in ipairs(classCheckboxes[classToken]) do
        cb:SetChecked(true)
      end
    end)

    disableBtn:SetScript("OnClick", function()
      for _, s in ipairs(spells) do
        ShortyRCD:SetTracked(classToken, s.spellID, false)
      end
      for _, cb in ipairs(classCheckboxes[classToken]) do
        cb:SetChecked(false)
      end
    end)

    for _, s in ipairs(spells) do
      local row = CreateCheckboxRow(child)
      row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
      row:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, y)

      local tracked = ShortyRCD:IsTracked(classToken, s.spellID)
      row.checkbox:SetChecked(tracked)

      row.checkbox:SetScript("OnClick", function(self)
        ShortyRCD:SetTracked(classToken, s.spellID, self:GetChecked())
      end)

      table.insert(classCheckboxes[classToken], row.checkbox)

      row.icon  = CreateSpellIcon(row, s.iconID)
      row.label = CreateLeftLabel(row, s.name or "Unknown Spell")

      -- Colored type + cooldown (from class library source of truth)
      local typeColored = ColorizeType(s.type)
      local cdText = FormatCooldownSeconds(s.cd)

      local tag = typeColored
      if cdText ~= "" then
        tag = string.format("%s \226\128\162 %s", typeColored, cdText) -- " • "
      end

      row.tag = CreateRightTag(row, tag)

      y = y - 24
    end

    y = y - 10
  end

  for _, classToken in ipairs(classOrder) do
    AddClassBlock(classToken)
  end

  child:SetHeight(math.abs(y) + 40)
end

function ShortyRCD.Options:RegisterPanel()
  if not self.panel then return end

  if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(self.panel, self.panel.name)
    Settings.RegisterAddOnCategory(category)
    self.category = category
    return
  end

  if InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(self.panel)
  end
end