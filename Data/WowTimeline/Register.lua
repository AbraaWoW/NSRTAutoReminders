local ADDON_NAME, EP = ...
EP.RegisterSource({
    id = "wowtimeline",
    label = "WoW Timeline (Top Logs)",
    GeneratedAt = "2026-10-27",
    CurrentSeason = 2,
    Raid = EP.WowTimelineRaid,
    EncounterNames = EP.WowTimelineEncounterNames,
    Plans = EP.WowTimelinePlans,
})
