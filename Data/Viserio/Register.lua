local ADDON_NAME, EP = ...
EP.RegisterSource({
    id = "viserio",
    label = "Viserio CD Raid",
    GeneratedAt = "2026-11-05",
    CurrentSeason = 2,
    Raid = EP.ViserioRaid,
    EncounterNames = EP.ViserioEncounterNames,
    Plans = {},
    FullNotes = EP.ViserioFullNotes,
    fullRaid = true,
})
