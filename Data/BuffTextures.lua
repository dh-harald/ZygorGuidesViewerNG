-- Buff reference -> icon key lookup for the havebuff/nobuff goals (Goal.lua), resolved on
-- Wowhead. A guide names a buff by its icon's FileDataID or as "spell:ID"; 1.12.1's
-- UnitBuff/UnitDebuff return only the icon path, so both are matched by icon: the lowercase
-- file name without directory, extension or "_TEX" suffix (Unreal Azeroth returns
-- /Game/Interface/Icons/Name_TEX, the vanilla client Interface\Icons\Name).
ZGV.BuffTextures = {
  [132092] = "ability_cheapshot",
  [132288] = "ability_rogue_disguise",
  [132331] = "ability_vanish",
  [133440] = "inv_jewelry_talisman_07",
  [134297] = "inv_misc_monsterclaw_04",
  [135859] = "spell_frost_manarecharge",
  [135880] = "spell_holy_blessingofprotection",
  [136230] = "spell_shadow_unsummonbuilding",
  ["spell:25678"] = "ability_suffocate",  -- Siren's Song
  ["spell:25688"] = "inv_misc_head_gnome_01",  -- Narain!
}
