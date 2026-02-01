-- class_library.lua
-- ShortyRCD raid cooldown catalog (Midnight).
-- This file is the ONLY place we maintain the spell list.

ShortyRCD = ShortyRCD or {}

ShortyRCD.ClassDisplay = {
  DEATHKNIGHT = "Death Knight",
  DEMONHUNTER = "Demon Hunter",
  DRUID       = "Druid",
  EVOKER      = "Evoker",
  HUNTER      = "Hunter",
  MAGE        = "Mage",
  MONK        = "Monk",
  PALADIN     = "Paladin",
  PRIEST      = "Priest",
  ROGUE       = "Rogue",
  SHAMAN      = "Shaman",
  WARLOCK     = "Warlock",
  WARRIOR     = "Warrior",
}

ShortyRCD.ClassOrder = {
  "DEATHKNIGHT","DEMONHUNTER","DRUID","EVOKER","HUNTER","MAGE","MONK",
  "PALADIN","PRIEST","ROGUE","SHAMAN","WARLOCK","WARRIOR"
}

-- Spell entry format:
-- {
--   spellID = 123,
--   name    = "Spell",
--   iconID  = 456,
--   cd      = 120,  -- cooldown seconds
--   ac      = 10,   -- active seconds (0 allowed)
--   ch      = false,-- channel? true/false
--   type    = "DEFENSIVE" | "HEALING" | "UTILITY"
-- }

ShortyRCD.ClassLib = {

  DEATHKNIGHT = {
    { name = "Anti-Magic Zone",           abbr = "AMZ", spellID = 51052,  iconID = 237510,  cd = 240, ac = 6,  ch = false, roe = true, type = "DEFENSIVE" },
    { name = "Mind Freeze",               abbr = "Kick", spellID = 47528,  iconID = 237527,  cd = 15, ac = 0,  ch = false, roe = false, type = "INTERRUPT" },
  },

  DEMONHUNTER = {
    { name = "Darkness",                  abbr = "Darkness", spellID = 196718, iconID = 1305154, cd = 300, ac = 8,  ch = false, roe = true, type = "DEFENSIVE" },
    { name = "Disrupt",                   abbr = "Kick", spellID = 183752, iconID = 1305153, cd = 15, ac = 0,  ch = false, roe = false, type = "INTERRUPT" },
  },

  DRUID = {
    { name = "Tranquility",               abbr = "Tranq", spellID = 740,    iconID = 136107, cd = 180, ac = 6,  ch = true, roe = true,  role = "Healer", type = "HEALING"   },
    { name = "Incarnation: Tree of Life", abbr = "Tree", spellID = 33891,  iconID = 236157, cd = 180, ac = 30, ch = false, roe = true, type = "HEALING"   },
    { name = "Ironbark",                  abbr = "Ironbark", spellID = 102342, iconID = 572025, cd = 90,  ac = 12, ch = false, roe = false, type = "DEFENSIVE" },
    { name = "Stampeding Roar",           abbr = "Roar", spellID = 77761,  iconID = 463283, cd = 120, ac = 8,  ch = false, roe = false, type = "UTILITY"   },
    { name = "Innervate",                 abbr = "Innervate", spellID = 29166,  iconID = 136048, cd = 180, ac = 8,  ch = false, roe = true, type = "UTILITY"   },
    { name = "Ursol's Vortex",            abbr = "Ursol's", spellID = 102793, iconID = 571588, cd = 60,  ac = 10, ch = false, roe = false, type = "UTILITY"   },
    { name = "Skull Bash",                abbr = "Kick", spellID = 106839, iconID = 236946, cd = 15, ac = 0,  ch = false, roe = false, type = "INTERRUPT" },
  },

  EVOKER = {
    { name = "Zephyr",                    abbr = "Zephyr", spellID = 374227, iconID = 4630449, cd = 120, ac = 8,  ch = false, roe = true, type = "UTILITY"   },
    { name = "Rewind",                    abbr = "Rewind", spellID = 363534, iconID = 4622474, cd = 240, ac = 5,  ch = false, roe = true, type = "HEALING"   },
    { name = "Dream Flight",              abbr = "Dream Flight", spellID = 359816, iconID = 4622455, cd = 120, ac = 15, ch = true, roe = true,  type = "HEALING"   },
    { name = "Time Spiral",               abbr = "Time Spiral", spellID = 374968, iconID = 4622479, cd = 120, ac = 10, ch = false, roe = true, type = "UTILITY"   },
    { name = "Time Dilation",             abbr = "Time Dilation", spellID = 357170, iconID = 4622478, cd = 60,  ac = 8,  ch = false, roe = false, type = "DEFENSIVE" },
    { name = "Quell",                     abbr = "Kick", spellID = 351338, iconID = 4622469, cd = 15, ac = 0,  ch = false, roe = false, type = "INTERRUPT" },
  },

  HUNTER = {
    { name = "Counter Shot",              abbr = "Kick", spellID = 147362, iconID = 249170, cd = 24, ac = 0,  ch = false, roe = false, type = "INTERRUPT" },
    { name = "Muzzle",                    abbr = "Kick", spellID = 187707, iconID = 1376045, cd = 15, ac = 0,  ch = false, roe = false, type = "INTERRUPT" },
  },

  MAGE = {
    { name = "Counterspell",              abbr = "Kick", spellID = 2139, iconID = 135856, cd = 25, ac = 0,  ch = false, roe = false, type = "INTERRUPT" },
  },

  MONK = {
    { name = "Revival",                   abbr = "Revival", spellID = 115310, iconID = 1020466, cd = 180, ac = 0,  ch = false, roe = true, role = "Healer", type = "HEALING" },
    { name = "Life Cocoon",               abbr = "Cocoon", spellID = 116849, iconID = 627485,  cd = 120, ac = 12, ch = false, roe = true, type = "HEALING" },
    { name = "Ring of Peace",             abbr = "Ring", spellID = 116844, iconID = 839107,  cd = 120, ac = 5,  ch = false, roe = false, type = "UTILITY" },
    { name = "Spear Hand Strike",         abbr = "Kick", spellID = 116705, iconID = 608940, cd = 15, ac = 0,  ch = false, roe = false, type = "INTERRUPT" },
  },

  PALADIN = {
    { name = "Aura Mastery",              abbr = "Mastery", spellID = 31821, iconID = 135872, cd = 180, ac = 8,  ch = false, roe = true, type = "DEFENSIVE" },
    { name = "Blessing of Protection",    abbr = "BoP", spellID = 1022,  iconID = 135964, cd = 300, ac = 10, ch = false, roe = true, type = "DEFENSIVE" },
    { name = "Blessing of Sacrifice",     abbr = "Sac", spellID = 6940,  iconID = 135966, cd = 120, ac = 12, ch = false, roe = false, type = "DEFENSIVE" },
    { name = "Blessing of Freedom",       abbr = "Freedom", spellID = 1044,  iconID = 135968, cd = 25,  ac = 8,  ch = false, roe = false, type = "UTILITY"   },
    { name = "Rebuke",                    abbr = "Kick", spellID = 96231, iconID = 523893, cd = 15, ac = 0,  ch = false, roe = false, type = "INTERRUPT" },
  },

  PRIEST = {
    { name = "Power Infusion",            abbr = "PI", spellID = 10060, iconID = 135939, cd = 120, ac = 15, ch = false, roe = true, type = "UTILITY"   },
    { name = "Power Word: Barrier",       abbr = "Barrier", spellID = 62618, iconID = 253400, cd = 180, ac = 10, ch = false, roe = true, type = "DEFENSIVE" },
    { name = "Divine Hymn",               abbr = "Hymn", spellID = 64843, iconID = 237540, cd = 180, ac = 5,  ch = true, roe = true,  type = "HEALING"   },
    { name = "Symbol of Hope",            abbr = "Hope", spellID = 64901, iconID = 135982, cd = 180, ac = 4,  ch = true, roe = true,  type = "UTILITY"   },
    { name = "Guardian Spirit",           abbr = "GS", spellID = 47788, iconID = 237542, cd = 180, ac = 10, ch = false, roe = true, type = "DEFENSIVE" },
    { name = "Silence",                   abbr = "Kick", spellID = 15487, iconID = 458230, cd = 30, ac = 0,  ch = false, roe = false, type = "INTERRUPT" },
  },

  ROGUE = {
    { name = "Kick",                      abbr = "Kick", spellID = 1766, iconID = 132219, cd = 15, ac = 0,  ch = false, roe = false, type = "INTERRUPT" },
  },

  SHAMAN = {
    { name = "Spirit Link Totem",         abbr = "SLT", spellID = 98008,  iconID = 237586, cd = 180, ac = 6,  ch = false, roe = true, type = "HEALING" },
    { name = "Healing Tide Totem",        abbr = "HTT", spellID = 108280, iconID = 538569, cd = 180, ac = 10, ch = false, roe = true, type = "HEALING" },
    { name = "Wind Rush Totem",           abbr = "Wind Rush", spellID = 192077, iconID = 538576, cd = 120, ac = 15, ch = false, roe = true, type = "UTILITY" },
    { name = "Earthbind Totem",           abbr = "Earthbind", spellID = 2484,   iconID = 136102, cd = 30,  ac = 20, ch = false, roe = false, type = "UTILITY" },
    { name = "Earthgrab Totem",           abbr = "Earthgrab", spellID = 51485,  iconID = 136100, cd = 30,  ac = 20, ch = false, roe = false, type = "UTILITY" },
    { name = "Tremor Totem",              abbr = "Tremor", spellID = 8143,   iconID = 136108, cd = 60,  ac = 10, ch = false, roe = false, type = "UTILITY" },
    { name = "Poison Cleansing Totem",    abbr = "Poison Totem", spellID = 383013, iconID = 136070, cd = 120, ac = 6,  ch = false, roe = false, type = "UTILITY" },
    { name = "Capacitor Totem",           abbr = "Cap Totem", spellID = 192058, iconID = 136013, cd = 60,  ac = 2,  ch = false, roe = false, type = "UTILITY" },
    { name = "Wind Shear",                abbr = "Kick", spellID = 57994, iconID = 136018, cd = 12, ac = 0,  ch = false, roe = false, type = "INTERRUPT" },
  },

  WARLOCK = {
    -- No raid CDs in your current Midnight list (keep empty on purpose)
  },

  WARRIOR = {
    { name = "Rallying Cry",              abbr = "Rally", spellID = 97462, iconID = 132351, cd = 180, ac = 10, ch = false, roe = true, type = "DEFENSIVE" },
    { name = "Pummel",                    abbr = "Kick", spellID = 6552, iconID = 132938, cd = 15, ac = 0,  ch = false, roe = false, type = "INTERRUPT" },
  },
}

-- -----------------------------------------------------------------------------
-- Lookup helpers (read-only index)
--
-- These helpers do NOT change the spell catalog; they just provide fast lookups
-- for other modules.

local _spellIndex = nil -- spellID -> entry
local _spellClass = nil -- spellID -> classToken

local function BuildIndex()
  if _spellIndex then return end
  _spellIndex = {}
  _spellClass = {}

  for classToken, list in pairs(ShortyRCD.ClassLib or {}) do
    if type(list) == "table" then
      for _, e in ipairs(list) do
        if type(e) == "table" and type(e.spellID) == "number" then
          _spellIndex[e.spellID] = e
          _spellClass[e.spellID] = classToken
        end
      end
    end
  end
end

-- Returns: entryTableOrNil, classTokenOrNil
function ShortyRCD:GetSpellEntry(spellID)
  if type(spellID) ~= "number" then return nil end
  BuildIndex()
  return _spellIndex[spellID], _spellClass[spellID]
end