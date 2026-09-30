-- Stat weights for the Gear Advisor. Keys are LibItemBonusLib's bonus names, plus ARMOR (its
-- bonus armor and the base armor line together) and DPS (weapon damage over speed), which
-- ReadLoadedTooltip adds.
--
-- ZGV.GearWeightsBySpec: per class and spec, ZygorGuidesViewerClassic's weights
-- (Data-Classic/Item-Statweights.lua) with its stat names mapped to the keys above; Haste,
-- Expertise and Armor Penetration, which 1.12 items don't have, are left out, and so are
-- Classic's item type lists. The spec is the selected talent build's gearspec (see
-- ZGV:GetGearWeights).
--
-- ZGV.GearWeights: the fallback without a build, one table per class. Hand-picked,
-- leveling-appropriate heuristics, directionally sensible rather than theorycrafted.
-- Every class needs a non-zero ARMOR weight: an item whose only gain is armor would
-- otherwise score exactly 0 and could never register as an upgrade, since
-- CheckItemForUpgrade requires newscore > equippedscore.
ZGV.GearWeights = {
    WARRIOR = { STR = 2.2, AGI = 1.2, STA = 1.5, ATTACKPOWER = 1, CRIT = 1, TOHIT = 1.2, ARMOR = 0.3, DEFENSE = 0.5, DPS = 2 },
    PALADIN = { STR = 2, STA = 1.5, ATTACKPOWER = 1, CRIT = 0.8, TOHIT = 1.2, INT = 0.5, SPI = 0.5, HEAL = 0.5, ARMOR = 0.3, DPS = 1.8 },
    DRUID   = { AGI = 1.5, STR = 1, INT = 1.2, SPI = 1, STA = 1.3, ATTACKPOWER = 0.8, HEAL = 0.8, DMG = 0.8, CRIT = 0.8, ARMOR = 0.15, DPS = 1.5 },
    PRIEST  = { INT = 2, SPI = 2, STA = 1, HEAL = 1.5, DMG = 1.5, SPELLTOHIT = 1, SPELLCRIT = 0.6, MANAREG = 0.8, ARMOR = 0.05 },
    SHAMAN  = { AGI = 1.3, STR = 1.3, INT = 1.3, SPI = 1, STA = 1.3, ATTACKPOWER = 0.8, HEAL = 0.6, DMG = 0.6, CRIT = 0.8, TOHIT = 1, ARMOR = 0.15, DPS = 1.5 },
    HUNTER  = { AGI = 2.5, ATTACKPOWER = 1, RANGEDATTACKPOWER = 1, CRIT = 1.3, TOHIT = 1.3, STA = 1, INT = 0.5, ARMOR = 0.15, DPS = 2 },
    ROGUE   = { AGI = 2.5, STR = 1, ATTACKPOWER = 1, CRIT = 1.3, TOHIT = 1.4, STA = 1, ARMOR = 0.15, DPS = 2 },
    MAGE    = { INT = 2.2, SPI = 0.8, DMG = 2.2, STA = 1, SPELLTOHIT = 1.2, SPELLCRIT = 1, MANAREG = 0.5, ARMOR = 0.05 },
    WARLOCK = { INT = 2, SPI = 1, DMG = 2.2, STA = 1, SPELLTOHIT = 1.2, SPELLCRIT = 1, MANAREG = 0.4, ARMOR = 0.05 },
}

ZGV.GearWeightsBySpec = {
    WARRIOR = {
        arms = { STR = 1, AGI = 0.69, DPS = 5.31, ATTACKPOWER = 0.45, TOHIT = 1, CRIT = 0.85, SPI = 0.05, MANAREG = 0, STA = 0.5, HEALTH = 0.05, HEALTHREG = 1, ARMOR = 0.005, DEFENSE = 0.05, DODGE = 0.05, PARRY = 0.05, FIRERES = 0.04, FROSTRES = 0.04, ARCANERES = 0.04, SHADOWRES = 0.04, NATURERES = 0.04 },
        fury = { STR = 1, AGI = 0.57, DPS = 5.22, ATTACKPOWER = 0.54, TOHIT = 0.57, CRIT = 0.7, SPI = 0.05, MANAREG = 0, STA = 0.5, HEALTH = 0.05, HEALTHREG = 1, ARMOR = 0.005, DEFENSE = 0.05, DODGE = 0.05, PARRY = 0.12, FIRERES = 0.04, FROSTRES = 0.04, ARCANERES = 0.04, SHADOWRES = 0.04, NATURERES = 0.04 },
        protection = { STR = 0.33, AGI = 0.59, DPS = 3.13, ATTACKPOWER = 0.06, TOHIT = 0.67, CRIT = 0.28, SPI = 0.05, MANAREG = 0, STA = 1, HEALTH = 0.09, HEALTHREG = 2, ARMOR = 0.02, DEFENSE = 0.81, DODGE = 0.7, PARRY = 0.58, BLOCK = 0.59, BLOCKVALUE = 0.35, FIRERES = 0.2, FROSTRES = 0.2, ARCANERES = 0.2, SHADOWRES = 0.2, NATURERES = 0.2 },
    },
    PALADIN = {
        holy = { AGI = 0.05, INT = 1, MANA = 0.009, SPI = 0.28, MANAREG = 1.24, HEAL = 0.54, SPELLCRIT = 0.46, STA = 0.5, HEALTH = 0.05, HEALTHREG = 1, ARMOR = 0.005, DEFENSE = 0.05, DODGE = 0.05, PARRY = 0.05, BLOCK = 0.01, FIRERES = 0.04, FROSTRES = 0.04, ARCANERES = 0.04, SHADOWRES = 0.04, NATURERES = 0.04 },
        protection = { STR = 0.2, AGI = 0.6, DPS = 1.77, ATTACKPOWER = 0.06, TOHIT = 0.16, CRIT = 0.15, INT = 0.5, MANA = 0.045, SPI = 0.05, MANAREG = 1, DMG = 0.44, HOLYDMG = 0.44, SPELLTOHIT = 0.78, SPELLCRIT = 0.6, SPELLPEN = 0.03, STA = 1, HEALTH = 0.09, HEALTHREG = 2, ARMOR = 0.02, DEFENSE = 0.7, DODGE = 0.7, PARRY = 0.6, BLOCK = 0.6, BLOCKVALUE = 0.15, FIRERES = 0.2, FROSTRES = 0.2, ARCANERES = 0.2, SHADOWRES = 0.2, NATURERES = 0.2 },
        retribution = { STR = 1, AGI = 0.64, DPS = 5.4, ATTACKPOWER = 0.41, TOHIT = 0.84, CRIT = 0.66, INT = 0.34, MANA = 0.032, SPI = 0.05, MANAREG = 1, DMG = 0.33, HOLYDMG = 0.33, SPELLTOHIT = 0.21, SPELLCRIT = 0.12, SPELLPEN = 0.015, STA = 0.5, HEALTH = 0.05, HEALTHREG = 1, ARMOR = 0.005, DEFENSE = 0.05, DODGE = 0.05, PARRY = 0.05, FIRERES = 0.04, FROSTRES = 0.04, ARCANERES = 0.04, SHADOWRES = 0.04, NATURERES = 0.04 },
    },
    HUNTER = {
        ["beast-mastery"] = { STR = 0.05, AGI = 1, DPS = 2.4, ATTACKPOWER = 0.43, RANGEDATTACKPOWER = 0.43, TOHIT = 1, CRIT = 0.8, INT = 0.8, MANA = 0.075, SPI = 0.05, MANAREG = 2.4, STA = 0.5, HEALTH = 0.05, HEALTHREG = 1, ARMOR = 0.005, DEFENSE = 0.05, DODGE = 0.05, PARRY = 0.05, FIRERES = 0.04, FROSTRES = 0.04, ARCANERES = 0.04, SHADOWRES = 0.04, NATURERES = 0.04 },
        marksmanship = { STR = 0.05, AGI = 1, DPS = 2.6, ATTACKPOWER = 0.55, RANGEDATTACKPOWER = 0.55, TOHIT = 1, CRIT = 0.6, INT = 0.9, MANA = 0.085, SPI = 0.05, MANAREG = 2.4, STA = 0.5, HEALTH = 0.05, HEALTHREG = 1, ARMOR = 0.005, DEFENSE = 0.05, DODGE = 0.05, PARRY = 0.05, FIRERES = 0.04, FROSTRES = 0.04, ARCANERES = 0.04, SHADOWRES = 0.04, NATURERES = 0.04 },
        survival = { STR = 0.05, AGI = 1, DPS = 2.4, ATTACKPOWER = 0.55, RANGEDATTACKPOWER = 0.55, TOHIT = 1, CRIT = 0.65, INT = 0.8, MANA = 0.075, SPI = 0.05, MANAREG = 2.4, STA = 0.5, HEALTH = 0.05, HEALTHREG = 1, ARMOR = 0.005, DEFENSE = 0.05, DODGE = 0.05, PARRY = 0.05, FIRERES = 0.04, FROSTRES = 0.04, ARCANERES = 0.04, SHADOWRES = 0.04, NATURERES = 0.04 },
    },
    ROGUE = {
        assassination = { STR = 0.5, AGI = 1, DPS = 3, ATTACKPOWER = 0.45, TOHIT = 1, CRIT = 0.81, SPI = 0.05, MANAREG = 0, STA = 0.5, HEALTH = 0.05, HEALTHREG = 1, ARMOR = 0.005, DEFENSE = 0.05, DODGE = 0.05, PARRY = 0.12, FIRERES = 0.04, FROSTRES = 0.04, ARCANERES = 0.04, SHADOWRES = 0.04, NATURERES = 0.04 },
        combat = { STR = 0.5, AGI = 1, DPS = 3, ATTACKPOWER = 0.45, TOHIT = 1, CRIT = 0.81, SPI = 0.05, MANAREG = 0, STA = 0.5, HEALTH = 0.05, HEALTHREG = 1, ARMOR = 0.005, DEFENSE = 0.05, DODGE = 0.05, PARRY = 0.12, FIRERES = 0.04, FROSTRES = 0.04, ARCANERES = 0.04, SHADOWRES = 0.04, NATURERES = 0.04 },
        subtlety = { STR = 0.5, AGI = 1, DPS = 3, ATTACKPOWER = 0.45, TOHIT = 1, CRIT = 0.81, SPI = 0.05, MANAREG = 0, STA = 0.5, HEALTH = 0.05, HEALTHREG = 1, ARMOR = 0.005, DEFENSE = 0.05, DODGE = 0.05, PARRY = 0.12, FIRERES = 0.04, FROSTRES = 0.04, ARCANERES = 0.04, SHADOWRES = 0.04, NATURERES = 0.04 },
    },
    PRIEST = {
        discipline = { AGI = 0.05, INT = 1, MANA = 0.09, SPI = 0.48, MANAREG = 1.19, HEAL = 0.72, SPELLCRIT = 0.32, STA = 0.5, HEALTH = 0.05, HEALTHREG = 1, ARMOR = 0.005, DEFENSE = 0.05, DODGE = 0.05, PARRY = 0.05, FIRERES = 0.04, FROSTRES = 0.04, ARCANERES = 0.04, SHADOWRES = 0.04, NATURERES = 0.04 },
        holy = { AGI = 0.05, INT = 1, MANA = 0.09, SPI = 0.73, MANAREG = 1.35, HEAL = 0.81, SPELLCRIT = 0.24, STA = 0.5, HEALTH = 0.05, HEALTHREG = 1, ARMOR = 0.005, DEFENSE = 0.05, DODGE = 0.05, PARRY = 0.05, FIRERES = 0.04, FROSTRES = 0.04, ARCANERES = 0.04, SHADOWRES = 0.04, NATURERES = 0.04 },
        shadow = { AGI = 0.05, INT = 0.19, MANA = 0.017, SPI = 0.21, MANAREG = 1, DMG = 1, SHADOWDMG = 1, SPELLTOHIT = 1.12, SPELLCRIT = 0.76, SPELLPEN = 0.08, STA = 0.5, HEALTH = 0.05, HEALTHREG = 1, ARMOR = 0.005, DEFENSE = 0.05, DODGE = 0.05, PARRY = 0.05, FIRERES = 0.04, FROSTRES = 0.04, ARCANERES = 0.04, SHADOWRES = 0.04, NATURERES = 0.04 },
    },
    SHAMAN = {
        elemental = { AGI = 0.05, INT = 0.31, MANA = 0.024, SPI = 0.09, MANAREG = 1.14, DMG = 1, NATUREDMG = 1, SPELLTOHIT = 0.9, SPELLCRIT = 1.05, SPELLPEN = 0.38, STA = 0.5, HEALTH = 0.05, HEALTHREG = 1, ARMOR = 0.005, DEFENSE = 0.05, DODGE = 0.05, PARRY = 0.12, BLOCK = 0.01, FIRERES = 0.04, FROSTRES = 0.04, ARCANERES = 0.04, SHADOWRES = 0.04, NATURERES = 0.04 },
        enhancement = { STR = 1, AGI = 0.87, DPS = 3, ATTACKPOWER = 0.5, TOHIT = 0.67, CRIT = 0.98, INT = 0.34, MANA = 0.032, SPI = 0.05, MANAREG = 1, DMG = 0.3, NATUREDMG = 0.3, SPELLTOHIT = 0.223, SPELLCRIT = 0.326, SPELLPEN = 0.11, STA = 0.5, HEALTH = 0.05, HEALTHREG = 1, ARMOR = 0.005, DEFENSE = 0.05, DODGE = 0.05, PARRY = 0.05, FIRERES = 0.04, FROSTRES = 0.04, ARCANERES = 0.04, SHADOWRES = 0.04, NATURERES = 0.04 },
        restoration = { AGI = 0.05, INT = 1, MANA = 0.009, SPI = 0.61, MANAREG = 1.33, HEAL = 0.9, SPELLCRIT = 0.48, STA = 0.5, HEALTH = 0.05, HEALTHREG = 1, ARMOR = 0.005, DEFENSE = 0.05, DODGE = 0.05, PARRY = 0.05, BLOCK = 0.01, FIRERES = 0.04, FROSTRES = 0.04, ARCANERES = 0.04, SHADOWRES = 0.04, NATURERES = 0.04 },
    },
    MAGE = {
        arcane = { AGI = 0.05, INT = 0.46, MANA = 0.038, SPI = 0.59, MANAREG = 1.13, DMG = 1, FIREDMG = 0.064, FROSTDMG = 0.52, ARCANEDMG = 0.88, SPELLTOHIT = 0.87, SPELLCRIT = 0.6, SPELLPEN = 0.09, STA = 0.5, HEALTH = 0.05, HEALTHREG = 1, ARMOR = 0.005, DEFENSE = 0.05, DODGE = 0.05, PARRY = 0.05, FIRERES = 0.04, FROSTRES = 0.04, ARCANERES = 0.04, SHADOWRES = 0.04, NATURERES = 0.04 },
        fire = { SPELLPEN = 0.34, MANAREG = 0.333, DMG = 0.158, FIREDMG = 0.158, SPELLTOHIT = 1.07, TOHIT = 1.07, INT = 0.099, SPELLCRIT = 0.74, SPI = 0.055, FROSTDMG = 0.041, ARCANEDMG = 0.041, DPS = 0.012 },
        frost = { AGI = 0.05, INT = 0.37, MANA = 0.032, SPI = 0.06, MANAREG = 0.8, DMG = 1, FIREDMG = 0.05, FROSTDMG = 0.95, ARCANEDMG = 0.13, SPELLTOHIT = 1.22, SPELLCRIT = 0.58, SPELLPEN = 0.07, STA = 0.5, HEALTH = 0.05, HEALTHREG = 1, ARMOR = 0.005, DEFENSE = 0.05, DODGE = 0.05, PARRY = 0.05, FIRERES = 0.04, FROSTRES = 0.04, ARCANERES = 0.04, SHADOWRES = 0.04, NATURERES = 0.04 },
    },
    WARLOCK = {
        affliction = { AGI = 0.05, INT = 0.4, MANA = 0.03, SPI = 0.1, MANAREG = 1, DMG = 1, FIREDMG = 0.35, SHADOWDMG = 0.91, SPELLTOHIT = 1.2, SPELLCRIT = 0.39, SPELLPEN = 0.08, STA = 0.5, HEALTH = 0.05, HEALTHREG = 1, ARMOR = 0.005, DEFENSE = 0.05, DODGE = 0.05, PARRY = 0.05, FIRERES = 0.04, FROSTRES = 0.04, ARCANERES = 0.04, SHADOWRES = 0.04, NATURERES = 0.04 },
        demonology = { AGI = 0.05, INT = 0.4, MANA = 0.03, SPI = 0.5, MANAREG = 1, DMG = 1, FIREDMG = 0.8, SHADOWDMG = 0.8, SPELLTOHIT = 1.2, SPELLCRIT = 0.66, SPELLPEN = 0.08, STA = 0.5, HEALTH = 0.05, HEALTHREG = 1, ARMOR = 0.005, DEFENSE = 0.05, DODGE = 0.05, PARRY = 0.05, FIRERES = 0.04, FROSTRES = 0.04, ARCANERES = 0.04, SHADOWRES = 0.04, NATURERES = 0.04 },
        destruction = { AGI = 0.05, INT = 0.34, MANA = 0.028, SPI = 0.25, MANAREG = 0.65, DMG = 1, FIREDMG = 0.23, SHADOWDMG = 0.95, SPELLTOHIT = 1.6, SPELLCRIT = 0.87, SPELLPEN = 0.08, STA = 0.5, HEALTH = 0.05, HEALTHREG = 1, ARMOR = 0.005, DEFENSE = 0.05, DODGE = 0.05, PARRY = 0.05, FIRERES = 0.04, FROSTRES = 0.04, ARCANERES = 0.04, SHADOWRES = 0.04, NATURERES = 0.04 },
    },
    DRUID = {
        balance = { AGI = 0.05, INT = 0.38, MANA = 0.032, SPI = 0.34, MANAREG = 0.58, DMG = 1, ARCANEDMG = 0.64, NATUREDMG = 0.43, SPELLTOHIT = 1.21, SPELLCRIT = 0.62, SPELLPEN = 0.21, STA = 0.5, HEALTH = 0.05, HEALTHREG = 1, ARMOR = 0.005, DEFENSE = 0.05, DODGE = 0.05, PARRY = 0.05, FIRERES = 0.04, FROSTRES = 0.04, ARCANERES = 0.04, SHADOWRES = 0.04, NATURERES = 0.04 },
        feral = { STR = 1.48, AGI = 1, ATTACKPOWER = 0.59, ATTACKPOWERFERAL = 0.59, TOHIT = 0.61, CRIT = 0.59, INT = 0.1, MANA = 0.009, SPI = 0.05, MANAREG = 0.3, HEAL = 0.025, STA = 0.5, HEALTH = 0.05, HEALTHREG = 1, ARMOR = 0.02, DEFENSE = 0.05, DODGE = 0.05, PARRY = 0.05, FIRERES = 0.04, FROSTRES = 0.04, ARCANERES = 0.04, SHADOWRES = 0.04, NATURERES = 0.04 },
        ["feral-tank"] = { STR = 0.2, AGI = 0.48, ATTACKPOWER = 0.34, ATTACKPOWERFERAL = 0.34, TOHIT = 0.16, CRIT = 0.15, INT = 0.1, MANA = 0.009, SPI = 0.05, MANAREG = 0.3, HEAL = 0.025, NATUREDMG = 0.025, STA = 1, HEALTH = 0.08, HEALTHREG = 2, ARMOR = 0.1, DEFENSE = 0.26, DODGE = 0.38, FIRERES = 0.2, FROSTRES = 0.2, ARCANERES = 0.2, SHADOWRES = 0.2, NATURERES = 0.2 },
        restoration = { AGI = 0.05, INT = 1, MANA = 0.09, SPI = 0.87, MANAREG = 1.7, HEAL = 1.21, SPELLCRIT = 0.35, STA = 0.5, HEALTH = 0.05, HEALTHREG = 1, ARMOR = 0.005, DEFENSE = 0.05, DODGE = 0.05, PARRY = 0.05, FIRERES = 0.04, FROSTRES = 0.04, ARCANERES = 0.04, SHADOWRES = 0.04, NATURERES = 0.04 },
    },
}

-- Per class and spec, the name the Gear Advisor options show.
ZGV.GearSpecNames = {
    WARRIOR = {
        arms = "Arms",
        fury = "Fury",
        protection = "Protection",
    },
    PALADIN = {
        holy = "Holy",
        protection = "Protection",
        retribution = "Retribution",
    },
    HUNTER = {
        ["beast-mastery"] = "Beast Mastery",
        marksmanship = "Marksmanship",
        survival = "Survival",
    },
    ROGUE = {
        assassination = "Assassination",
        combat = "Combat",
        subtlety = "Subtlety",
    },
    PRIEST = {
        discipline = "Discipline",
        holy = "Holy",
        shadow = "Shadow",
    },
    SHAMAN = {
        elemental = "Elemental",
        enhancement = "Enhancement",
        restoration = "Restoration",
    },
    MAGE = {
        arcane = "Arcane",
        fire = "Fire",
        frost = "Frost",
    },
    WARLOCK = {
        affliction = "Affliction",
        demonology = "Demonology",
        destruction = "Destruction",
    },
    DRUID = {
        balance = "Balance",
        feral = "Feral DPS",
        ["feral-tank"] = "Feral Tank",
        restoration = "Restoration",
    },
}

-- Per class and spec, the stats whose weight counts half once the equipped total passes the
-- cap, and always below the level cap (Classic's rule; see ZGV:GetItemScore).
ZGV.GearCapsBySpec = {
    WARRIOR = {
        arms = { TOHIT = 5 },
        fury = { TOHIT = 5 },
        protection = { TOHIT = 5 },
    },
    PALADIN = {
        holy = { SPELLTOHIT = 4 },
        protection = { TOHIT = 5 },
        retribution = { TOHIT = 5 },
    },
    HUNTER = {
        ["beast-mastery"] = { TOHIT = 5 },
        marksmanship = { TOHIT = 5 },
        survival = { TOHIT = 5 },
    },
    ROGUE = {
        assassination = { TOHIT = 24 },
        combat = { TOHIT = 24 },
        subtlety = { TOHIT = 24 },
    },
    PRIEST = {
        discipline = { SPELLTOHIT = 4 },
        holy = { SPELLTOHIT = 4 },
        shadow = { SPELLTOHIT = 4 },
    },
    SHAMAN = {
        elemental = { SPELLTOHIT = 4 },
        enhancement = { TOHIT = 24 },
        restoration = { SPELLTOHIT = 4 },
    },
    MAGE = {
        arcane = { SPELLTOHIT = 4 },
        fire = { SPELLTOHIT = 4 },
        frost = { SPELLTOHIT = 4 },
    },
    WARLOCK = {
        affliction = { SPELLTOHIT = 4 },
        demonology = { SPELLTOHIT = 4 },
        destruction = { SPELLTOHIT = 4 },
    },
    DRUID = {
        balance = { SPELLTOHIT = 4 },
        feral = { TOHIT = 5 },
        ["feral-tank"] = { TOHIT = 5 },
        restoration = { SPELLTOHIT = 4 },
    },
}
