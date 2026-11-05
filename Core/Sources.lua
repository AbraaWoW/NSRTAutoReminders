local ADDON_NAME, EP = ...

--[[----------------------------------------------------------------------
  NSRT AutoReminders — Registre des sources de données

  Chaque fichier Data_<Source>.lua (ou Data/<Source>/Register.lua pour les
  sources multi-fichiers) s'enregistre ici avec ses propres raids, boss et
  plans. L'ordre d'enregistrement (= l'ordre du .toc) définit l'ordre
  d'affichage dans le sélecteur de source.

  Une seule source est active à la fois : la sélection est exclusive
  (voir EP.SelectSource dans Core.lua).

  Deux modèles de données possibles selon la source :

  1. Spé-filtrée (WoW Timeline) : `Plans` contient une variante par spé du joueur.
     EP.RegisterSource({
         id = "wowtimeline",
         label = "WoW Timeline (Top Logs)",
         GeneratedAt = "2026-07-23",
         CurrentSeason = 1,
         Raid = { { name, season, current, encounters = {...} }, ... },
         EncounterNames = { [encID] = "Nom", ... },
         Plans = { [encID] = { [difficulty] = { [specID] = { variantes } } } },
     })

  2. Note complète (Viserio) : `fullRaid = true`, `FullNotes` contient des
     notes couvrant tout le raid (toutes les spés d'un coup, comme publiées
     sur Viserio) — pas de filtrage par spé du joueur, elles se partagent
     au groupe entier plutôt que de se charger en note personnelle.
     EP.RegisterSource({
         id = "viserio",
         label = "Viserio CD Raid",
         GeneratedAt = "2026-07-23",
         CurrentSeason = 1,
         Raid = { { name, season, current, encounters = {...} }, ... },
         EncounterNames = { [encID] = "Nom", ... },
         Plans = {},
         FullNotes = { [encID] = { { name, author, difficulty, duration,
                                      specs = { [specID] = { rappels } } }, ... } },
         fullRaid = true,
     })
------------------------------------------------------------------------]]

EP.PlanNamePrefix = "[AR] "

EP.Sources = {}
EP.SourceOrder = {}

local function DecodeReminders(s)
    local out = {}
    for t, ph, id in s:gmatch("([^,;]+),([^,;]+),([^,;]+)") do
        out[#out + 1] = { time = tonumber(t), ph = tonumber(ph), spellid = tonumber(id) }
    end
    return out
end

local LazyVariant = {
    __index = function(variant, key)
        if key ~= "reminders" then return nil end
        local packed = rawget(variant, "r")
        if type(packed) ~= "string" then return nil end
        local list = DecodeReminders(packed)
        rawset(variant, "reminders", list)
        rawset(variant, "r", nil)
        return list
    end,
}

local function AttachLazyReminders(plans)
    for _, byDiff in pairs(plans) do
        for _, bySpec in pairs(byDiff) do
            for _, variants in pairs(bySpec) do
                for _, variant in ipairs(variants) do
                    if type(rawget(variant, "r")) == "string" then
                        setmetatable(variant, LazyVariant)
                    end
                end
            end
        end
    end
end

function EP.ForEachVariantSpell(variant, fn)
    local list = rawget(variant, "reminders")
    if list then
        for _, r in ipairs(list) do
            if r.spellid then fn(r.spellid) end
        end
        return
    end
    local packed = rawget(variant, "r")
    if type(packed) == "string" then
        for id in packed:gmatch("[^,;]+,[^,;]+,([^,;]+)") do
            id = tonumber(id)
            if id then fn(id) end
        end
    end
end

function EP.RegisterSource(def)
    if not (def and def.id) or EP.Sources[def.id] then return end
    def.Raid = def.Raid or {}
    def.EncounterNames = def.EncounterNames or {}
    def.Plans = def.Plans or {}
    AttachLazyReminders(def.Plans)
    def.FullNotes = def.FullNotes or {}
    def.fullRaid = def.fullRaid or false
    EP.Sources[def.id] = def
    table.insert(EP.SourceOrder, def.id)
    -- Les fichiers de données sont chargés avant Core.lua : à ce moment le
    -- cache n'existe pas encore, d'où le test.
    if EP.InvalidateCache then EP.InvalidateCache() end
end
