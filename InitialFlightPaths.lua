-- The flight point each race knows from character creation (its capital; Rut'theran Village
-- for night elves, as Darnassus has no flight master), by LibTaxi position tag, as
-- ZygorGuidesViewerClassic seeds them.
local INITIAL_FLIGHT_PATHS = {
    Human = { ["432:672"] = true },     -- Stormwind
    Dwarf = { ["507:488"] = true },     -- Ironforge
    Gnome = { ["507:488"] = true },     -- Ironforge
    NightElf = { ["416:157"] = true },  -- Rut'theran Village
    Orc = { ["628:443"] = true },       -- Orgrimmar
    Troll = { ["628:443"] = true },     -- Orgrimmar
    Scourge = { ["442:194"] = true },   -- Undercity
    Tauren = { ["449:561"] = true },    -- Thunder Bluff
}

-- Runs once per character. A table without the flag is either new or holds keys LibTaxi does
-- not write, so it is replaced rather than merged.
function ZGV:SeedInitialFlightPaths()
    local char = ZGV.db.char
    if char.initialFlightPathsLoaded then return end
    char.taxis = {}
    local _, race = UnitRace("player")
    for tag in pairs(INITIAL_FLIGHT_PATHS[race] or {}) do
        char.taxis[tag] = true
    end
    char.initialFlightPathsLoaded = true
end
