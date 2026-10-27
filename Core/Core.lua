local ADDON_NAME, EP = ...
local L = setmetatable({}, { __index = function(_, k) return (EP.L or {})[k] or k end })

--[[----------------------------------------------------------------------
  NSRT AutoReminders — Core

  Ce que fait l'addon : il expose les plans de cooldowns publiés (Library
  Viserio, Warcraft Logs via WoW Timeline) pour le boss et la spécialisation
  courants, et écrit celui que le joueur choisit dans les notes
  personnelles de Northern Sky Raid Tools.

  IMPORTANT — l'import est MANUEL. Rien n'est injecté tout seul :
  une note n'est écrite que sur action explicite du joueur (bouton
  « Import to NSRT »). Les événements de connexion et de
  changement de spé ne servent qu'à rafraîchir l'affichage.

  Règles de politesse envers NSRT :
  1. Nos notes portent toujours le préfixe EP.PlanNamePrefix.
  2. On ne touche jamais à une note qui n'est pas la nôtre.
  3. On ne force jamais un réglage de NSRT : on prévient le joueur.
------------------------------------------------------------------------]]

local f = CreateFrame("Frame")

local CHAT_PREFIX = "|cFF33CCFFAutoReminders|r: "
local function Say(msg) print(CHAT_PREFIX .. msg) end
local function Warn(msg) print(CHAT_PREFIX .. "|cFFFFB347" .. msg .. "|r") end

local function DB()
    NSRTAutoRemindersDB = NSRTAutoRemindersDB or {}
    return NSRTAutoRemindersDB
end

function EP.GetVersion()
    local get = C_AddOns and C_AddOns.GetAddOnMetadata or _G.GetAddOnMetadata
    return (get and get(ADDON_NAME, "Version")) or "?"
end


--[[ Cache ---------------------------------------------------------------
  La fusion des sources et la recherche de variantes étaient recalculées
  à chaque rafraîchissement (GetRaid() était appelé 3 fois par Refresh).
  On mémorise le résultat et on l'invalide au changement de source.
------------------------------------------------------------------------]]

local cache = { defs = nil, raid = nil, variants = {} }

function EP.InvalidateCache()
    cache.defs, cache.raid = nil, nil
    if wipe then wipe(cache.variants) else cache.variants = {} end
end


--[[ Sélection de source -------------------------------------------------]]

-- Migration des identifiants de source enregistres.
--
-- La source des top logs s'appelait "lorrgs" ; Lorrgs a ete remplace par
-- WoW Timeline et l'identifiant devient "wowtimeline". Sans cette reprise,
-- un joueur qui avait choisi WoW Timeline se retrouverait avec une source
-- desactivee et verrait son addon vide au premier lancement.
--
-- Seul `db.sources` est concerne : les autres reglages sauvegardes sont
-- indexes par personnage ou par rencontre, jamais par source. Les
-- modificateurs ligne par ligne ne sont pas sauvegardes du tout (voir le
-- bloc Modificateurs plus bas), donc rien a reprendre de ce cote.
local SOURCE_ID_MIGRATION = { lorrgs = "wowtimeline" }

local function MigrateSourceIds(db)
    if db.sourceIdsMigrated then return end
    db.sourceIdsMigrated = true
    if type(db.sources) ~= "table" then return end
    for old, new in pairs(SOURCE_ID_MIGRATION) do
        local kept = db.sources[old]
        if kept ~= nil then
            -- On n'ecrase pas un choix deja exprime sous le nouveau nom.
            if db.sources[new] == nil then db.sources[new] = kept end
            db.sources[old] = nil
        end
    end
end

function EP.IsSourceEnabled(id)
    local db = DB()
    db.sources = db.sources or {}
    MigrateSourceIds(db)
    return db.sources[id] ~= false
end

-- Sélection EXCLUSIVE : cliquer sur une source désactive les autres.
function EP.SelectSource(id)
    local db = DB()
    db.sources = db.sources or {}
    MigrateSourceIds(db)
    for _, sid in ipairs(EP.SourceOrder) do
        db.sources[sid] = (sid == id)
    end
    EP.InvalidateCache()
    if EP.RefreshUI then EP.RefreshUI() end
end

-- Garantit qu'exactement une source est active (défaut : la première).
function EP.NormalizeSourceSelection()
    local db = DB()
    db.sources = db.sources or {}
    local firstEnabled
    for _, sid in ipairs(EP.SourceOrder) do
        if EP.IsSourceEnabled(sid) then
            if not firstEnabled then
                firstEnabled = sid
            else
                db.sources[sid] = false
            end
        end
    end
    if not firstEnabled and EP.SourceOrder[1] then
        db.sources[EP.SourceOrder[1]] = true
    end
end

local function EnabledDefs()
    if cache.defs then return cache.defs end
    if #EP.SourceOrder > 1 then EP.NormalizeSourceSelection() end
    local defs = {}
    for _, id in ipairs(EP.SourceOrder) do
        if EP.IsSourceEnabled(id) then
            local def = EP.Sources[id]
            if def then table.insert(defs, def) end
        end
    end
    cache.defs = defs
    return defs
end

-- La source active d'abord ; en dernier recours on interroge les autres,
-- pour qu'un boss chargé sous une source garde son nom après une bascule.
function EP.GetEncounterName(encID)
    for _, def in ipairs(EnabledDefs()) do
        local n = def.EncounterNames[encID]
        if n then return n end
    end
    for _, id in ipairs(EP.SourceOrder) do
        local def = EP.Sources[id]
        local n = def and def.EncounterNames[encID]
        if n then return n end
    end
    return "Encounter " .. tostring(encID)
end

--[[ Noms localises (AFFICHAGE seulement) --------------------------------
  Les donnees generees portent les noms anglais. Ils restent la reference
  pour tout ce qui sort de l'addon (nom de note NSRT, plan, texture) : une
  note partagee doit etre identique d'un client a l'autre.

  A l'ecran, on prend le nom dans le journal d'aventure du jeu, donc dans
  la langue du client. Le journal est indexe par ses propres IDs : on le
  parcourt une fois pour relier chaque ID de rencontre (celui des donnees
  et de NSRT, 7e retour d'EJ_GetEncounterInfo) a son nom et a son instance.
  Boss absent du journal : nom anglais des donnees.
------------------------------------------------------------------------]]
local ejBoss, ejInstance
local function ScanJournal()
    if ejBoss then return end
    ejBoss, ejInstance = {}, {}
    if not EJ_GetEncounterInfo then return end
    for jid = 1, 5000 do
        local name, _, _, _, _, instID, dungeonEncID = EJ_GetEncounterInfo(jid)
        if name and dungeonEncID and dungeonEncID > 0 then
            ejBoss[dungeonEncID] = name
            ejInstance[dungeonEncID] = instID
        end
    end
end

function EP.GetEncounterDisplayName(encID)
    ScanJournal()
    return ejBoss[encID] or EP.GetEncounterName(encID)
end

-- Nom du raid dans la langue du client : celui de l'instance du journal qui
-- contient TOUS ses boss. Si une autre entree de la meme saison tombe sur
-- la meme instance (raids que Warcraft Logs regroupe), le nom du journal va
-- a celle qui a le plus de boss ; l'autre garde le nom des donnees, pour
-- que deux raids n'affichent jamais le meme nom.
function EP.GetRaidDisplayName(raid)
    ScanJournal()
    local encs = raid.encounters or {}
    local instID = encs[1] and ejInstance[encs[1]]
    if not instID or not EJ_GetInstanceInfo then return raid.name end
    for _, enc in ipairs(encs) do
        if ejInstance[enc] ~= instID then return raid.name end
    end
    for _, other in ipairs(EP.GetRaid and EP.GetRaid() or {}) do
        if other ~= raid and other.name ~= raid.name
            and (other.season or 0) == (raid.season or 0) then
            local shared = false
            for _, enc in ipairs(other.encounters or {}) do
                if ejInstance[enc] == instID then shared = true end
            end
            if shared and #(other.encounters or {}) >= #encs then
                return raid.name
            end
        end
    end
    return EJ_GetInstanceInfo(instID) or raid.name
end

-- Pour /ar check : combien de boss des donnees ont un nom dans le journal.
function EP.GetJournalStats()
    ScanJournal()
    local found, total, seen = 0, 0, {}
    for _, id in ipairs(EP.SourceOrder or {}) do
        local def = EP.Sources[id]
        for enc in pairs(def and def.EncounterNames or {}) do
            if not seen[enc] then
                seen[enc] = true
                total = total + 1
                if ejBoss[enc] then found = found + 1 end
            end
        end
    end
    return found, total
end

-- Date de génération la plus ancienne parmi les sources activées
function EP.GetDataDate()
    local oldest
    for _, def in ipairs(EnabledDefs()) do
        local d = def.GeneratedAt
        if d and (not oldest or d < oldest) then oldest = d end
    end
    return oldest
end

-- Saison courante sur TOUTES les sources, comme EP.GetRaid : elle decide
-- quelle branche de l'arbre est affichee, et l'arbre ne doit pas changer
-- quand on bascule de source.
function EP.GetCurrentSeason()
    local s = 0
    for _, id in ipairs(EP.SourceOrder) do
        local def = EP.Sources[id]
        s = math.max(s, (def and def.CurrentSeason) or 0)
    end
    return s
end

-- Ordre de KILL (pas l'EncounterID) pour trier les listes deroulantes dans
-- l'ordre de progression du raid plutot que dans l'ordre numerique des
-- EncounterID (qui n'a aucun rapport avec l'ordre des boss en jeu). DOIT
-- rester synchronise avec BOSS_KILL_ORDER dans NSRTAutoReminders-build.py.
-- Un boss absent d'ici est simplement trie par son EncounterID en dernier
-- recours (comportement identique a l'ancien tri numerique).
local ENCOUNTER_KILL_ORDER = {
    -- The Venomous Abyss (saison 2)
    [3470] = 1,   -- Nek'zali the Soulcoiler
    [3445] = 2,   -- Entombed Sentinels
    [3497] = 3,   -- The Lost Explorers
    [3455] = 4,   -- Vashnik the Malignant
    [3420] = 5,   -- Sszorak
    [3421] = 6,   -- The Twin Fangs
    [3429] = 7,   -- The Coiled Altar
    [3492] = 8,   -- Ula'tek
    -- The Unbinding of Kith'ix (saison 2) : un seul boss, donc premier
    -- de SON raid. Le tri porte sur la liste d'un raid a la fois, il n'y
    -- a donc pas de conflit avec le 1 de Nek'zali.
    [3513] = 1,   -- Kith'ix
}

local function SortEncountersByKillOrder(encounters)
    table.sort(encounters, function(a, b)
        local oa, ob = ENCOUNTER_KILL_ORDER[a], ENCOUNTER_KILL_ORDER[b]
        if oa and ob then return oa < ob end
        if oa and not ob then return true end
        if ob and not oa then return false end
        return a < b
    end)
end

-- Arborescence raid -> boss, construite sur TOUTES les sources enregistrees
-- et non sur la seule source active.
--
-- C'est volontaire : le menu doit etre identique sous Viserio et sous
-- WoW Timeline. Seules les DONNEES dependent de la source (nombre de notes, etat
-- d'import, disponibilite pour la spe) ; un boss qu'elle ne couvre pas
-- reste visible, grise, avec son libelle "aucune timeline". Avant, chaque
-- bascule de source redessinait l'arbre — un raid pouvait disparaitre, et
-- la selection sautait ailleurs.
--
-- Conflit : si deux sources rangent un meme boss dans des raids differents
-- (typiquement l'index de l'une est perime), c'est la source generee le
-- plus RECEMMENT qui tranche, jamais un ordre arbitraire. GeneratedAt est
-- au format ISO AAAA-MM-JJ, donc comparable tel quel. A egalite de date,
-- l'ordre de declaration du .toc departage.
function EP.GetRaid()
    if cache.raid then return cache.raid end

    local claim = {}    -- encID -> { raid = nom, at = date }
    local meta = {}     -- nom de raid -> { season, current, at, idx }
    local order = {}

    for _, id in ipairs(EP.SourceOrder) do
        local def = EP.Sources[id]
        local at = (def and def.GeneratedAt) or ""
        for _, raid in ipairs((def and def.Raid) or {}) do
            local m = meta[raid.name]
            if not m then
                table.insert(order, raid.name)
                meta[raid.name] = {
                    season = raid.season, current = raid.current,
                    at = at, idx = #order,
                }
            elseif at > m.at then
                m.season, m.current, m.at = raid.season, raid.current, at
            end
            for _, e in ipairs(raid.encounters) do
                local c = claim[e]
                if not c or at > c.at then
                    claim[e] = { raid = raid.name, at = at }
                end
            end
        end
    end

    local byName, built = {}, {}
    for _, name in ipairs(order) do
        local m = meta[name]
        local r = { name = name, season = m.season, current = m.current,
                    idx = m.idx, encSet = {}, encounters = {} }
        byName[name] = r
        table.insert(built, r)
    end
    for enc, c in pairs(claim) do
        local r = byName[c.raid]
        if r and not r.encSet[enc] then
            r.encSet[enc] = true
            table.insert(r.encounters, enc)
        end
    end

    -- Un raid dont tous les boss ont ete repris par une source plus recente
    -- n'a plus de contenu : il ne doit pas rester comme branche vide.
    local kept = {}
    for _, r in ipairs(built) do
        if #r.encounters > 0 then
            SortEncountersByKillOrder(r.encounters)
            table.insert(kept, r)
        end
    end
    -- table.sort n'est pas stable : sans l'index de declaration en second
    -- critere, l'ordre de deux raids d'une meme saison serait indefini et
    -- pourrait changer d'une ouverture a l'autre.
    table.sort(kept, function(a, b)
        local sa, sb = a.season or 0, b.season or 0
        if sa ~= sb then return sa > sb end
        return a.idx < b.idx
    end)
    cache.raid = kept
    return kept
end


--[[ Personnage et spécialisation ----------------------------------------]]

function EP.GetCharKey()
    local name, realm = UnitFullName("player")
    if not realm then realm = GetNormalizedRealmName() end
    return realm and (name .. "-" .. realm) or nil
end

function EP.GetCurrentSpecID()
    local specIndex = GetSpecialization()
    return specIndex and GetSpecializationInfo(specIndex)
end

function EP.GetClassName()
    local className = UnitClass("player")
    return className or "?"
end

function EP.GetSpecName()
    local specIndex = GetSpecialization()
    if not specIndex then return "?" end
    -- Important : l'opérateur `and` de Lua ne propage pas toutes les valeurs
    -- de retour de GetSpecializationInfo(). On appelle donc explicitement la
    -- fonction pour récupérer son 2e résultat : le nom localisé de la spé.
    local _, specName = GetSpecializationInfo(specIndex)
    return specName or "?"
end

-- Couleur de classe du joueur, en {r, g, b}.
--
-- C_ClassColor est la source moderne ; RAID_CLASS_COLORS reste le repli, et
-- CUSTOM_CLASS_COLORS est consulte en premier car plusieurs addons de raid
-- le redefinissent (les joueurs s'attendent alors a LEUR teinte).
function EP.GetClassColor()
    local _, fileName = UnitClass("player")
    if not fileName then return nil end
    local c = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[fileName])
        or (C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(fileName))
        or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[fileName])
    if not (c and c.r) then return nil end
    return { c.r, c.g, c.b }
end

function EP.GetSpecLabel()
    local className = EP.GetClassName()
    local specName = EP.GetSpecName()
    if className ~= "?" and specName ~= "?" then
        return className .. " " .. specName
    end
    return className ~= "?" and className or specName
end


--[[ Base de sorts connus -------------------------------------------------
  Pour le remplacement de sort (voir plus bas) : plutôt qu'une liste codée
  en dur à maintenir, on scanne une fois tous les sorts qui apparaissent
  réellement dans les données chargées (WoW Timeline + Viserio, toutes sources,
  pas seulement celle active) et on résout nom/icône via l'API native.
  Ça donne naturellement une liste pertinente (des cooldowns de raid, pas
  n'importe quel sort du jeu) sans entretien manuel.
------------------------------------------------------------------------]]

local knownSpellsCache

local function CollectSpellIDs(seen)
    for _, id in ipairs(EP.SourceOrder) do
        local def = EP.Sources[id]
        if def then
            for _, byDiff in pairs(def.Plans or {}) do
                for _, bySpec in pairs(byDiff) do
                    for _, variants in pairs(bySpec) do
                        for _, variant in ipairs(variants) do
                            for _, r in ipairs(variant.reminders or {}) do
                                if r.spellid then seen[r.spellid] = true end
                            end
                        end
                    end
                end
            end
            for _, notes in pairs(def.FullNotes or {}) do
                for _, note in ipairs(notes) do
                    -- note.specs[specID] contient une liste PAR JOUEUR
                    -- depuis 8.2.0 (EP.SpecActors gere aussi l'ancien
                    -- format plat) : parcourir a plat perdrait tous les
                    -- sorts des notes Viserio dans le selecteur.
                    for _, block in pairs(note.specs or {}) do
                        for _, casts in ipairs(EP.SpecActors(block)) do
                            for _, r in ipairs(casts) do
                                if r.spellid then seen[r.spellid] = true end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Liste { {spellID=, name=, icon=}, ... } triée par nom. Mémorisée : les
-- données chargées ne changent pas en cours de session.
function EP.GetKnownSpells()
    if knownSpellsCache then return knownSpellsCache end
    local seen, list = {}, {}
    CollectSpellIDs(seen)
    for spellID in pairs(seen) do
        local name = C_Spell.GetSpellName(spellID)
        if name then
            table.insert(list, { spellID = spellID, name = name, icon = C_Spell.GetSpellTexture(spellID) })
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    knownSpellsCache = list
    return list
end

-- Membres du groupe de raid actuel, quelle que soit sa taille ou son type
-- (LFR, Normal/Héroïque 10-30, Mythique) — l'API de groupe est la même
-- dans tous les cas, rien à distinguer. Jamais mémorisé : la composition
-- change (arrivées/départs), donc recalculé à chaque ouverture du menu.
function EP.GetRaidRosterOptions()
    local list = {}
    if not IsInRaid() then return list end
    for i = 1, GetNumGroupMembers() do
        local name, _, _, _, _, fileName = GetRaidRosterInfo(i)
        if name and name ~= "" then
            local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[fileName]
            table.insert(list, {
                name = name,
                classFile = fileName,
                colorHex = color and color.colorStr,
            })
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end


-- Variantes disponibles pour un boss et la spé courante, toutes difficultés
-- confondues (ordre fixe : Mythique puis Héroïque).
-- Chaque entrée = { variant = <table>, difficulty = "Mythic"|"Heroic", sourceId }
local DIFF_ORDER = { "Mythic", "Heroic" }

function EP.GetVariantsAll(encID, specID)
    if not (encID and specID) then return nil end
    local key = encID .. ":" .. specID
    local hit = cache.variants[key]
    if hit ~= nil then
        if hit == false then return nil end
        return hit
    end
    local merged = {}
    for _, def in ipairs(EnabledDefs()) do
        local difficulties = def.Plans[encID]
        if difficulties then
            for _, diff in ipairs(DIFF_ORDER) do
                local specs = difficulties[diff]
                local variants = specs and specs[specID]
                if variants then
                    for _, v in ipairs(variants) do
                        table.insert(merged, { variant = v, difficulty = diff, sourceId = def.id })
                    end
                end
            end
        end
    end
    if #merged > 0 then
        cache.variants[key] = merged
        return merged
    end
    cache.variants[key] = false
    return nil
end

local function VariantKey(entry)
    return (entry.sourceId or "?") .. "|" .. entry.difficulty .. "|" .. entry.variant.name
end

function EP.GetVariantModKey(entry)
    if not entry then return nil end
    return "variant|" .. VariantKey(entry)
end


--[[ Modificateurs (rappel par rappel : temps, spé, sort) ----------------
  Réglages appliqués par le joueur avant import/partage. VOLONTAIREMENT
  NON SAUVEGARDÉS : une simple table Lua en mémoire, jamais écrite dans
  NSRTAutoRemindersDB ni dans NSRT. Ils ne survivent pas à une
  déconnexion/relog — seule la note générée avec ces changements (une
  fois importée/partagée) persiste, dans NSRT, comme n'importe quelle
  autre note.

  Tout se fait RAPPEL PAR RAPPEL, jamais globalement ni par bloc de spé :
  chaque rappel garde son propre temps, sa propre spé cible et son propre
  sort, indépendamment des autres rappels de la même note.
------------------------------------------------------------------------]]

local sessionMods = {}

local function GetModifiers()
    return sessionMods
end

local function GetModEntry(key, create)
    local mods = GetModifiers()
    local entry = mods[key]
    if not entry and create then
        entry = { timeMap = {}, specMap = {}, spellMap = {}, actorNames = {}, deletedLines = {}, customLines = {} }
        mods[key] = entry
    end
    return entry
end

-- Temps (en secondes, peut être négatif = avant le pull) d'un rappel
-- précis. `lineKey` identifie ce rappel dans la note (voir EP.LineKey).
function EP.GetLineTime(key, lineKey, origTime)
    local entry = key and GetModEntry(key, false)
    local map = entry and entry.timeMap
    local t = map and lineKey and map[lineKey]
    if t == nil then return origTime end
    return t
end

function EP.SetLineTime(key, lineKey, origTime, newTime)
    if not (key and lineKey) then return end
    if newTime == nil or newTime == origTime then
        local entry = GetModEntry(key, false)
        if entry and entry.timeMap then entry.timeMap[lineKey] = nil end
        return
    end
    GetModEntry(key, true).timeMap[lineKey] = newTime
end

-- Réassignation d'un rappel (notes complètes Viserio uniquement), RAPPEL
-- PAR RAPPEL — pas par bloc de spé entier. `lineKey` identifie un rappel
-- précis dans la note (voir EP.LineKey plus bas). Le "target" peut être
-- soit un SpecID (nombre, toute la spé reçoit l'alerte) soit un nom de
-- joueur exact (texte, un seul joueur précis — utile quand deux joueurs
-- partagent la même spé). table[lineKey] = target.
function EP.GetSpecRemap(key)
    local entry = key and GetModEntry(key, false)
    return (entry and entry.specMap) or nil
end

function EP.GetLineRemapTarget(key, lineKey, origSpecID)
    local map = EP.GetSpecRemap(key)
    return (map and lineKey and map[lineKey]) or origSpecID
end

-- target == nil ou == origSpecID -> supprime la réassignation de ce rappel
-- précis (retour à sa spé d'origine, tout le monde de cette spé). Les
-- autres rappels de la même spé d'origine, eux, ne sont pas affectés.
function EP.SetLineRemap(key, lineKey, origSpecID, target)
    if not (key and lineKey) then return end
    if not target or target == origSpecID then
        local entry = GetModEntry(key, false)
        if entry and entry.specMap then entry.specMap[lineKey] = nil end
        return
    end
    GetModEntry(key, true).specMap[lineKey] = target
end

-- Remplacement du SORT lui-même pour un rappel précis (ex. la note dit
-- "Spirale temporelle" mais chez nous, c'est un autre sort qui couvre ce
-- créneau) — indépendant de la réassignation de spé ci-dessus. Les deux
-- peuvent être utilisés ensemble ou séparément sur un même rappel.
function EP.GetLineSpell(key, lineKey, origSpellID)
    local entry = key and GetModEntry(key, false)
    local map = entry and entry.spellMap
    return (map and lineKey and map[lineKey]) or origSpellID
end

function EP.SetLineSpell(key, lineKey, origSpellID, newSpellID)
    if not (key and lineKey) then return end
    if not newSpellID or newSpellID == origSpellID then
        local entry = GetModEntry(key, false)
        if entry and entry.spellMap then entry.spellMap[lineKey] = nil end
        return
    end
    GetModEntry(key, true).spellMap[lineKey] = newSpellID
end

function EP.GetLineSpellMap(key)
    local entry = key and GetModEntry(key, false)
    return (entry and entry.spellMap) or nil
end

function EP.GetLineTimeMap(key)
    local entry = key and GetModEntry(key, false)
    return (entry and entry.timeMap) or nil
end

-- Suppression d'un rappel précis (notes complètes Viserio uniquement) :
-- il disparaît de l'aperçu et de la note générée, sans affecter les
-- autres rappels de la même note. Réversible tant que la note n'a pas
-- été partagée (rien n'est sauvegardé, comme le reste des modificateurs).
function EP.IsLineDeleted(key, lineKey)
    local entry = key and GetModEntry(key, false)
    return (entry and entry.deletedLines and entry.deletedLines[lineKey]) or false
end

function EP.SetLineDeleted(key, lineKey, deleted)
    if not (key and lineKey) then return end
    if not deleted then
        local entry = GetModEntry(key, false)
        if entry and entry.deletedLines then entry.deletedLines[lineKey] = nil end
        return
    end
    GetModEntry(key, true).deletedLines[lineKey] = true
end

function EP.GetDeletedLines(key)
    local entry = key and GetModEntry(key, false)
    return (entry and entry.deletedLines) or nil
end

-- Ajout d'un rappel personnalisé (notes complètes Viserio uniquement) :
-- contrairement aux rappels d'origine, il n'a pas de "valeur de base" à
-- écraser — temps, sort et cible sont stockés directement sur l'objet,
-- modifiables ensuite avec les mêmes contrôles que les autres lignes.
-- spellid reste nil tant qu'aucun sort n'a été choisi ; une ligne sans
-- sort n'est jamais incluse dans la note générée.
function EP.GetCustomLines(key)
    local entry = key and GetModEntry(key, false)
    return (entry and entry.customLines) or {}
end

-- `atTime` : position de depart du rappel, en secondes depuis le pull. Sert
-- quand on cree le rappel depuis une capacite du boss, pour qu'il arrive deja
-- en face d'elle au lieu de repartir de 0:00.
function EP.AddCustomLine(key, defaultTarget, atTime)
    local entry = GetModEntry(key, true)
    entry.customLineSeq = (entry.customLineSeq or 0) + 1
    local line = {
        lineKey = "new:" .. entry.customLineSeq,
        time = tonumber(atTime) or 0,
        ph = 1,
        spellid = nil,
        target = defaultTarget,
    }
    table.insert(entry.customLines, line)
    return line
end

function EP.RemoveCustomLine(key, lineKey)
    local entry = key and GetModEntry(key, false)
    if not (entry and entry.customLines) then return end
    for i, line in ipairs(entry.customLines) do
        if line.lineKey == lineKey then
            table.remove(entry.customLines, i)
            return
        end
    end
end

function EP.SetCustomLineField(key, lineKey, field, value)
    local entry = key and GetModEntry(key, false)
    if not (entry and entry.customLines) then return end
    for _, line in ipairs(entry.customLines) do
        if line.lineKey == lineKey then
            line[field] = value
            return
        end
    end
end

-- Clé stable pour un rappel précis à l'intérieur d'une note complète :
-- spé d'origine + position dans la liste de cette spé. Utilisée à la fois
-- pour l'affichage (UI.lua) et pour la génération de la note (ci-dessous) —
-- les deux parcourent note.specs[specID] dans le même ordre (ipairs sur des
-- données statiques), donc la clé reste stable d'un rafraîchissement à l'autre.
-- `actorIndex` distingue deux joueurs de la MEME spe dans une note Viserio.
-- Le joueur 1 garde l'ancienne forme de cle, pour que les modificateurs
-- poses sur une note mono-joueur restent valides.
function EP.LineKey(origSpecID, indexInSpec, actorIndex)
    if actorIndex and actorIndex > 1 then
        return origSpecID .. "#" .. actorIndex .. ":" .. indexInSpec
    end
    return origSpecID .. ":" .. indexInSpec
end

--[[ Joueurs multiples d'une meme spe (notes Viserio) -------------------
  Viserio publie une section par JOUEUR. Une note de raid peut donc
  contenir deux Paladins Sacres, deux Chasseurs BM, etc. Jusqu'en 8.1.10
  ces sections etaient fusionnees en une seule timeline par spe : chacun
  recevait aussi les assignations de son homologue, d'ou des cooldowns de
  plusieurs minutes reclames a une seconde d'intervalle.

  Les donnees conservent desormais un bloc par joueur, et TOUS les blocs
  partent dans la note — une note de raid doit couvrir tout le monde. Mais
  NSRT marque par defaut chaque ligne avec la SPE (tag:<specID>), ce qui
  la ferait afficher chez les deux joueurs a la fois. Chaque bloc doit
  donc etre nomme (tag:<Pseudo>) avant l'envoi : voir EP.GetUnnamedActors,
  qui bloque le partage tant que ce n'est pas fait.
------------------------------------------------------------------------]]

-- Accepte les deux formes : ancienne (liste de rappels) et nouvelle
-- (liste de listes, une par joueur). Renvoie toujours une liste de blocs.
function EP.SpecActors(block)
    if type(block) ~= "table" or block[1] == nil then return {} end
    if block[1].spellid ~= nil or block[1].time ~= nil then
        return { block }          -- ancien format : un seul joueur
    end
    return block
end

function EP.GetSpecActorCount(note, specID)
    if not (note and note.specs and note.specs[specID]) then return 0 end
    return #EP.SpecActors(note.specs[specID])
end

local function ActorKey(specID, actorIndex)
    return specID .. "#" .. (actorIndex or 1)
end

function EP.GetActorName(key, specID, actorIndex)
    local entry = key and GetModEntry(key, false)
    local map = entry and entry.actorNames
    return map and map[ActorKey(specID, actorIndex)] or nil
end

function EP.SetActorName(key, specID, actorIndex, name)
    if not (key and specID) then return end
    if not name or name == "" then
        local entry = GetModEntry(key, false)
        if entry and entry.actorNames then
            entry.actorNames[ActorKey(specID, actorIndex)] = nil
        end
        return
    end
    GetModEntry(key, true).actorNames[ActorKey(specID, actorIndex)] = name
end

-- Un bloc "vivant" est un bloc dont au moins une ligne subsiste : un bloc
-- entierement supprime (joueur absent du raid ce soir) ne part pas dans la
-- note et n'a donc pas a etre nomme.
local function ActorHasLiveLines(key, specID, actorIndex, casts)
    for idx = 1, #casts do
        if not EP.IsLineDeleted(key, EP.LineKey(specID, idx, actorIndex)) then
            return true
        end
    end
    return false
end

-- Blocs qui partiraient encore avec tag:<specID>. TOUS les blocs sont
-- concernes, pas seulement ceux des spes en double : la composition d'une
-- note Viserio est celle du raid de son AUTEUR. Meme si la note ne contient
-- qu'un seul Paladin Sacre, TON raid peut en aligner deux — le marquage par
-- spe afficherait alors la ligne chez les deux. Seul un pseudo leve
-- l'ambiguite, d'ou l'obligation pour le RL de nommer chaque bloc.
function EP.GetUnnamedActors(note, key)
    local missing = {}
    if not (note and note.specs) then return missing end
    for specID, block in pairs(note.specs) do
        local actors = EP.SpecActors(block)
        for i = 1, #actors do
            if not EP.GetActorName(key, specID, i)
               and ActorHasLiveLines(key, specID, i, actors[i]) then
                missing[#missing + 1] =
                    { specID = specID, actorIndex = i, count = #actors }
            end
        end
    end
    return missing
end

-- Le roster renvoie "Nom-Royaume" pour un joueur d'un autre royaume, alors
-- que le RL saisit souvent le nom court : on compare les deux formes pour
-- ne pas signaler a tort un pseudo parfaitement valide.
local function ShortName(name)
    return name and (name:match("^([^-]+)") or name) or nil
end

-- Ensemble des noms presents dans le raid, ou nil quand on n'est pas en
-- raid : dans ce cas on ne signale RIEN (le RL prepare souvent sa note
-- seul, hors groupe — avertir la serait du bruit permanent).
function EP.BuildRaidNameSet()
    if not IsInRaid() then return nil end
    local set, any = {}, false
    for _, m in ipairs(EP.GetRaidRosterOptions()) do
        set[m.name] = true
        set[ShortName(m.name)] = true
        any = true
    end
    return any and set or nil
end

function EP.IsNameInRaid(set, name)
    if not (set and name) then return true end   -- inconnu : on ne signale pas
    return (set[name] or set[ShortName(name)]) and true or false
end

-- Pseudos assignes a un bloc vivant mais absents du raid actuel : joueur
-- parti, remplace, ou faute de frappe lors d'une saisie manuelle. Ne
-- bloque pas l'envoi — le joueur peut se connecter apres — mais le RL doit
-- le voir.
function EP.GetAbsentActorNames(note, key)
    local absent, set = {}, EP.BuildRaidNameSet()
    if not (set and note and note.specs) then return absent end
    local seen = {}
    for specID, block in pairs(note.specs) do
        local actors = EP.SpecActors(block)
        for i = 1, #actors do
            local name = EP.GetActorName(key, specID, i)
            if name and not seen[name]
               and not EP.IsNameInRaid(set, name)
               and ActorHasLiveLines(key, specID, i, actors[i]) then
                seen[name] = true
                absent[#absent + 1] = name
            end
        end
    end
    for _, custom in ipairs(EP.GetCustomLines(key)) do
        local name = custom.target
        if custom.spellid and type(name) == "string" and not seen[name]
           and not EP.IsNameInRaid(set, name)
           and not EP.IsLineDeleted(key, custom.lineKey) then
            seen[name] = true
            absent[#absent + 1] = name
        end
    end
    table.sort(absent)
    return absent
end

-- Meme exigence pour les rappels ajoutes a la main : sans pseudo ils
-- partiraient eux aussi marques par spe. Seuls comptent ceux qui finiront
-- reellement dans la note (un sort choisi, non supprimes).
function EP.GetUnnamedCustomLines(key)
    local n = 0
    for _, custom in ipairs(EP.GetCustomLines(key)) do
        if custom.spellid and type(custom.target) ~= "string"
           and not EP.IsLineDeleted(key, custom.lineKey) then
            n = n + 1
        end
    end
    return n
end

function EP.ResetModifiers(key)
    if not key then return end
    GetModifiers()[key] = nil
end


--[[ Notes complètes (Viserio) --------------------------------------------
  Contrairement à `Plans` (filtré par spé du joueur), `FullNotes` couvre
  tout le raid d'un coup : on les liste sans tenir compte de la spé du
  joueur, et on les partage au groupe plutôt que de les charger en note
  personnelle (voir EP.ShareFullNote plus bas).
------------------------------------------------------------------------]]

-- Sources qui exposent le modèle "note complète" (fullRaid = true).
local function FullRaidDefs()
    local list = {}
    for _, def in ipairs(EnabledDefs()) do
        if def.fullRaid then table.insert(list, def) end
    end
    return list
end

-- Vrai quand la (les) source(s) actives sont toutes en modèle "note
-- complète" (Viserio) — la sélection étant exclusive, ça revient en
-- pratique à savoir si Viserio ou WoW Timeline est actif.
function EP.IsFullRaidActive()
    local defs = EnabledDefs()
    if #defs == 0 then return false end
    for _, def in ipairs(defs) do
        if not def.fullRaid then return false end
    end
    return true
end

-- Notes complètes pour un boss, toutes sources fullRaid confondues.
-- Chaque entrée = { note = <table>, sourceId }
function EP.GetFullNotesForBoss(encID)
    if not encID then return nil end
    local merged = {}
    for _, def in ipairs(FullRaidDefs()) do
        local notes = def.FullNotes[encID]
        if notes then
            for _, note in ipairs(notes) do
                table.insert(merged, { note = note, sourceId = def.id })
            end
        end
    end
    if #merged == 0 then return nil end
    return merged
end


--[[ Écriture des notes NSRT ---------------------------------------------]]

-- NSRT accepte des phases FRACTIONNAIRES (1.5, 1.75, 2.5) et son parseur
-- les lit bien : ph:(%d*%.?%d+). Un "%d" ici tronquerait 1.5 en 1 et
-- rangerait le rappel dans la mauvaise phase — donc silencieusement jamais
-- declenche. On formate en entier quand c'est possible, sinon en decimal.
local function FormatPhase(ph)
    ph = tonumber(ph) or 1
    if ph == math.floor(ph) then return ("%d"):format(ph) end
    return (("%.2f"):format(ph):gsub("0+$", ""):gsub("%.$", ""))
end

-- ---------------------------------------------------------------------------
-- TIMELINE ABSOLUE <-> PHASES NSRT
--
-- Tout ce que l'utilisateur voit et edite est en temps ABSOLU depuis le debut
-- du combat, sur une seule piste continue : c'est comme ca qu'on lit un plan
-- de raid, et c'est ce qu'on affiche. Mais NSRT, lui, ne sait pas lire ca.
-- Verifie dans son code (Reminders.lua) :
--   * le parseur fait `phase = phase and tonumber(phase) or 1` — il n'existe
--     aucune valeur "toutes phases", et omettre ph: revient a ecrire ph:1 ;
--   * StartReminders(phase) appelle HideAllReminders(), qui fait `v:Cancel()`
--     sur CHAQUE timer en attente, puis remet `self.ReminderTimer = {}` et ne
--     replanifie que les rappels de la phase qui commence.
-- Autrement dit `time:` est relatif au debut de sa phase, et un rappel laisse
-- en ph:1 avec un temps posterieur au premier changement de phase est detruit
-- avant d'avoir tire — silencieusement, sans aucune erreur en jeu.
--
-- D'ou ce decoupage, fait au tout dernier moment (a l'ecriture de la note) :
-- l'utilisateur n'a jamais a penser aux phases, et la note reste valide.
-- ---------------------------------------------------------------------------

-- Bornes de phase utilisables pour ce boss, en secondes absolues, triees.
-- `variant` (timeline WoW Timeline) a la priorite absolue : ses `phaseStarts` sont
-- les vraies bornes DE CE pull, alors que EP.PhaseTable est une reference
-- figee dont la borne bouge d'un groupe a l'autre (sur Nek'zali Mythique
-- l'intermission demarre entre 155 s et 205 s selon le pull).
function EP.PhaseBoundaries(encID, difficulty, variant)
    local function Sorted(src)
        if type(src) ~= "table" then return nil end
        local out = {}
        for ph, start in pairs(src) do
            local p, s = tonumber(ph), tonumber(start)
            if p and s then out[#out + 1] = { phase = p, start = s } end
        end
        if #out == 0 then return nil end
        table.sort(out, function(a, b)
            if a.start ~= b.start then return a.start < b.start end
            return a.phase < b.phase
        end)
        -- La phase 1 demarre toujours a 0. Une variante dont le premier cast
        -- tombe apres un changement de phase n'a pas d'entree pour elle : sans
        -- cette sentinelle, un rappel ramene en debut de combat par l'utilisateur
        -- serait range dans la premiere phase connue au lieu de la phase 1.
        if out[1].start > 0 then
            table.insert(out, 1, { phase = 1, start = 0 })
        end
        return out
    end

    local fromLog = variant and Sorted(variant.phaseStarts)
    if fromLog then return fromLog end

    local byDiff = EP.PhaseTable and EP.PhaseTable[encID]
    if not byDiff then return nil end
    return Sorted(byDiff[difficulty] or byDiff.Mythic or byDiff.Heroic)
end

-- Deroulement des capacites du boss (Data/BossTimelines.lua), trie par temps.
-- Purement informatif : ces lignes ne sortent jamais dans la note envoyee a
-- NSRT, elles servent a voir a quoi repond chaque rappel et a en placer un.
function EP.GetBossTimeline(encID, difficulty)
    local byDiff = EP.BossTimeline and EP.BossTimeline[encID]
    if not byDiff then return nil end
    -- AUCUN repli sur l'autre difficulte : les deroulements different
    -- vraiment. Sur Ula'tek, le Mythique ouvre sur 1304012 a 4,9 s alors que
    -- l'Heroique ouvre sur 1298367 a 15 s et ne lance 1304012 qu'a 75,9 s.
    -- Afficher le mauvais deroulement serait pire que n'en afficher aucun :
    -- on s'en servirait pour placer des rappels au mauvais moment.
    local t = byDiff[difficulty]
    if not t or #t == 0 then return nil end
    return t
end

-- Affichage du deroulement du boss : activable, parce qu'il double facilement
-- le nombre de lignes et que tout le monde ne veut pas ca en permanence.
function EP.ShowBossTimeline()
    local db = NSRTAutoRemindersDB
    if not db or db.showBossTimeline == nil then return true end
    return db.showBossTimeline and true or false
end

function EP.SetShowBossTimeline(v)
    NSRTAutoRemindersDB = NSRTAutoRemindersDB or {}
    NSRTAutoRemindersDB.showBossTimeline = v and true or false
end

-- Tag des notes WoW Timeline : "spec" (defaut, ID de spe) ou "name" (nom du
-- personnage). Le nom permet de retrouver et de modifier les rappels dans
-- la timeline de NSRT, qui les range par joueur ; en contrepartie, la note
-- ne vaut plus que pour CE personnage. Les notes Viserio ne sont pas
-- concernees : chaque ligne y porte deja sa propre cible.
function EP.GetTagMode()
    local db = NSRTAutoRemindersDB
    return (db and db.tagMode == "name") and "name" or "spec"
end

function EP.SetTagMode(mode)
    NSRTAutoRemindersDB = NSRTAutoRemindersDB or {}
    NSRTAutoRemindersDB.tagMode = (mode == "name") and "name" or "spec"
end

-- Temps absolu -> (phase NSRT, temps relatif au debut de cette phase).
-- Sans bornes connues, on reste en phase 1 avec le temps absolu : c'est le
-- comportement d'avant 8.1.0, qui ne peut produire aucun rappel inatteignable.
function EP.SplitPhase(absTime, bounds)
    absTime = tonumber(absTime) or 0
    if absTime < 0 then absTime = 0 end
    if not bounds or #bounds == 0 then return 1, absTime end
    local phase, start = 1, 0
    for _, b in ipairs(bounds) do
        if absTime >= b.start then
            phase, start = b.phase, b.start
        else
            break
        end
    end
    return phase, absTime - start
end

-- (phase, temps relatif) -> temps absolu. Utilise a la lecture des donnees
-- WoW Timeline, qui sont stockees decoupees par phase.
function EP.JoinPhase(phase, relTime, bounds)
    local rel = tonumber(relTime) or 0
    phase = tonumber(phase) or 1
    if not bounds or #bounds == 0 then return rel end
    local fallback
    for _, b in ipairs(bounds) do
        if b.phase == phase then return b.start + rel end
        -- Phase inconnue de la table : on retient le dernier debut connu
        -- qui la precede. Ca arrive sur des donnees generees avant 8.3.0,
        -- ou le modele `increment` n'etait pas borne et pouvait ecrire
        -- jusqu'a ph:7 sur The Lost Explorers alors que NSRT s'arrete a 5.
        -- Sans ce repli, ces rappels revenaient a t=0 et tassaient toute
        -- la piste au debut du combat.
        if b.phase < phase then fallback = b.start end
    end
    return (fallback or 0) + rel
end

-- `reminders` porte des temps ABSOLUS (voir EP.SplitPhase) ; le decoupage en
-- phases NSRT se fait ici, au dernier moment.
local function BuildNoteString(encID, difficulty, reminders, bounds, specID, modKey)
    -- Le `tag:` decide A QUI s'adresse un rappel. NSRT le compare, dans
    -- TagMatchesPlayer, au nom du joueur, a son surnom, a son role, a sa
    -- classe, a son groupe... et a tostring(specID). Un rappel dont le tag
    -- ne correspond a rien n'est tout simplement pas arme.
    --
    -- On y mettait le NOM du joueur : la note se declenchait donc quelle que
    -- soit la spe, et une timeline Paladin Heal continuait de parler en
    -- Protection. On y met desormais l'ID DE SPE pour laquelle la variante a
    -- ete choisie. La note etant personnelle, « quiconque joue cette spe »
    -- revient a « moi, quand je joue cette spe ».
    --
    -- Repli sur le nom si la spe est inconnue : un tag vide vaudrait
    -- « tout le monde » et ferait reapparaitre le probleme a l'envers.
    --
    -- Option « nom du joueur » (EP.GetTagMode) : le tag devient le nom du
    -- personnage, pour que la timeline de NSRT range les rappels sur sa
    -- ligne et permette de les modifier. Changer l'option change la note :
    -- elle repasse en « mise a jour disponible » et se reimporte.
    local tag
    if EP.GetTagMode() == "name" or not (specID and specID ~= 0) then
        tag = UnitName("player")
    else
        tag = tostring(specID)
    end
    local bossName = EP.GetEncounterName(encID)
    local lines = {
        ("EncounterID:%d;Difficulty:%s;Name:%s"):format(encID, difficulty, bossName)
    }
    for _, r in ipairs(reminders) do
        local ph, rel = EP.SplitPhase(r.time, bounds)
        local parts = { ("time:%d"):format(rel), "ph:" .. FormatPhase(ph) }
        if r.bossSpell then
            parts[#parts + 1] = ("bossSpell:%d"):format(r.bossSpell)
        end
        parts[#parts + 1] = ("tag:%s"):format(tag)
        parts[#parts + 1] = ("spellid:%d"):format(r.spellid)
        lines[#lines + 1] = table.concat(parts, ";") .. ";"
    end

    -- Rappels ajoutes a la main sur une timeline WoW Timeline.
    --
    -- Seul BuildFullNoteString (Viserio) les ecrivait : le bouton etait donc
    -- masque ici, sans quoi on aurait pu ajouter des lignes qui
    -- disparaissaient silencieusement a l'import.
    --
    -- Pas de cible, contrairement a Viserio : une note WoW Timeline est
    -- PERSONNELLE et porte deja le tag de la spe. Une ligne qu'on y ajoute
    -- est donc forcement pour soi — il n'y a personne d'autre a designer.
    -- On exige seulement un sort : une ligne sans sort n'est pas ecrite.
    for _, custom in ipairs(EP.GetCustomLines(modKey)) do
        if custom.spellid and not EP.IsLineDeleted(modKey, custom.lineKey) then
            local ph, rel = EP.SplitPhase(custom.time or 0, bounds)
            lines[#lines + 1] = table.concat({
                ("time:%d"):format(rel),
                "ph:" .. FormatPhase(ph),
                ("tag:%s"):format(tag),
                ("spellid:%d"):format(custom.spellid),
            }, ";") .. ";"
        end
    end

    -- NSRT découpe le texte avec le motif `str:gmatch('([^\n]*)\n')`, qui
    -- exige un \n après CHAQUE ligne, y compris la dernière — sans ce \n
    -- final, le tout dernier rappel de la note n'était jamais reconnu par
    -- NSRT (silencieusement ignoré, pas d'erreur visible).
    return table.concat(lines, "\n") .. "\n"
end

local function CleanupOwnNotes(charKey)
    if not (NSRT and NSRT.PersonalReminders) then return 0 end
    local removed = 0
    local active = NSRT.ActivePersonalReminder and NSRT.ActivePersonalReminder[charKey]
    for name in pairs(NSRT.PersonalReminders) do
        if name:find(EP.PlanNamePrefix, 1, true) == 1 then
            NSRT.PersonalReminders[name] = nil
            removed = removed + 1
            if active then
                for encID, activeName in pairs(active) do
                    if activeName == name then active[encID] = nil end
                end
            end
        end
    end
    return removed
end

-- Shared Notes : notes complètes Viserio partagées au groupe (voir
-- EP.ShareFullNote). Pas de scope par personnage — une note partagée
-- n'appartient à personne en particulier.
local function CleanupOwnSharedNotes()
    if not (NSRT and NSRT.Reminders) then return 0 end
    local removed = 0
    for name in pairs(NSRT.Reminders) do
        if name:find(EP.PlanNamePrefix, 1, true) == 1 then
            NSRT.Reminders[name] = nil
            if NSRT.InviteList then NSRT.InviteList[name] = nil end
            if NSRT.ActiveReminder == name then NSRT.ActiveReminder = nil end
            removed = removed + 1
        end
    end
    -- Notre table de correspondance (note d'origine -> nom de note NSRT) ne
    -- contient que des entrées créées par nous : on la vide entièrement,
    -- sinon un futur partage réutiliserait un nom qui vient d'être
    -- supprimé de NSRT sans jamais le recréer.
    if NSRTAutoRemindersDB and NSRTAutoRemindersDB.sharedMap then
        NSRTAutoRemindersDB.sharedMap = {}
    end
    return removed
end

-- Table des notes chargées : DB.loaded[charKey][encID][cléVariante] = nom de note
local function GetLoadedMap(encID)
    local db = DB()
    db.loaded = db.loaded or {}
    local charKey = EP.GetCharKey()
    if not charKey then return nil end
    db.loaded[charKey] = db.loaded[charKey] or {}
    db.loaded[charKey][encID] = db.loaded[charKey][encID] or {}
    return db.loaded[charKey][encID]
end

-- Nettoie les références devenues invalides lorsque les notes sont supprimées
-- directement depuis Northern Sky Raid Tools (Unload / Delete All).
function EP.PruneStaleNoteState(encID)
    local charKey = EP.GetCharKey()
    if not (charKey and NSRT and NSRT.PersonalReminders) then return end

    local loadedByChar = NSRTAutoRemindersDB
        and NSRTAutoRemindersDB.loaded
        and NSRTAutoRemindersDB.loaded[charKey]
    local map = loadedByChar and loadedByChar[encID]

    if map then
        for key, noteName in pairs(map) do
            if type(noteName) ~= "string" or not NSRT.PersonalReminders[noteName] then
                map[key] = nil
            end
        end
        if not next(map) then
            loadedByChar[encID] = nil
        end
    end

    local active = NSRT.ActivePersonalReminder and NSRT.ActivePersonalReminder[charKey]
    local activeName = active and active[encID]
    if activeName and not NSRT.PersonalReminders[activeName] then
        active[encID] = nil
    end
end

-- Retire toutes NOS notes de NSRT (action explicite du joueur uniquement) —
-- Personal Notes ET Shared Notes.
function EP.RemoveAllOwnNotes()
    local charKey = EP.GetCharKey()
    local removedPersonal = charKey and CleanupOwnNotes(charKey) or 0
    local removedShared = CleanupOwnSharedNotes()
    if NSRTAutoRemindersDB and NSRTAutoRemindersDB.loaded and charKey then
        NSRTAutoRemindersDB.loaded[charKey] = nil
    end
    if EP.RefreshUI then EP.RefreshUI() end
    Say((L["%d imported note(s) removed from NSRT."]):format(removedPersonal + removedShared))
    return removedPersonal + removedShared
end

-- Calcule la liste finale des rappels d'une variante WoW Timeline, en appliquant
-- les modifications de session (temps/sort) et en retirant les rappels
-- supprimés — mêmes règles que l'aperçu (UI.lua, Refresh()) et que
-- BuildFullNoteString pour les notes complètes Viserio. Utilisée à la fois
-- pour générer la note réellement importée (EP.LoadVariant) et pour
-- détecter si une note déjà importée est à jour (EP.GetRowState) : les
-- deux DOIVENT produire exactement le même résultat, sinon une note
-- modifiée par le joueur semblerait éternellement "à mettre à jour" (ou,
-- avant ce correctif, le bouton "Importer" écrivait carrément les
-- rappels d'ORIGINE dans NSRT en ignorant les modifications faites dans
-- l'aperçu — l'aperçu avait l'air correct, mais la note réellement créée
-- ne l'était pas).
-- Renvoie les rappels de la variante en temps ABSOLU. Les donnees generees
-- sont stockees decoupees par phase (`time` relatif + `ph`) parce que c'est
-- ce que NSRT consomme ; on les recolle ici pour que tout le reste de
-- l'addon — apercu, edition, export — ne manipule qu'une seule timeline
-- continue. Le decoupage inverse a lieu dans BuildNoteString.
local function ResolveVariantReminders(entry, bounds)
    local modKey = EP.GetVariantModKey(entry)
    local out = {}
    for idx, r in ipairs(entry.variant.reminders or {}) do
        local lineKey = EP.LineKey("toplogs", idx)
        if not EP.IsLineDeleted(modKey, lineKey) then
            -- L'eventuelle correction de l'utilisateur est elle aussi
            -- absolue : c'est ce qu'il a saisi dans la piste.
            local absolute = EP.JoinPhase(r.ph, r.time, bounds)
            out[#out + 1] = {
                time = EP.GetLineTime(modKey, lineKey, absolute),
                bossSpell = r.bossSpell,
                spellid = EP.GetLineSpell(modKey, lineKey, r.spellid),
            }
        end
    end
    table.sort(out, function(a, b) return (a.time or 0) < (b.time or 0) end)
    return out
end

-- État d'une timeline :
--   "none"       : jamais importée
--   "update"     : note présente mais contenu différent
--   "imported"   : contenu à jour, mais une autre note est prévue au pull
--   "up_to_date" : contenu à jour et note prévue pour le prochain pull
function EP.GetRowState(encID, i)
    EP.PruneStaleNoteState(encID)
    local specID = EP.GetCurrentSpecID()
    local entries = specID and EP.GetVariantsAll(encID, specID)
    local entry = entries and entries[i]
    local map = GetLoadedMap(encID)
    local charKey = EP.GetCharKey()
    if not (entry and map and charKey and NSRT and type(NSRT.PersonalReminders) == "table") then
        return "none"
    end
    local noteName = map[VariantKey(entry)]
    if not (noteName and NSRT.PersonalReminders[noteName]) then
        return "none"
    end
    local bounds = EP.PhaseBoundaries(encID, entry.difficulty, entry.variant)
    local expected = BuildNoteString(
        encID, entry.difficulty, ResolveVariantReminders(entry, bounds), bounds, specID,
        EP.GetVariantModKey(entry))
    if NSRT.PersonalReminders[noteName] ~= expected then
        return "update", noteName
    end
    local active = NSRT.ActivePersonalReminder and NSRT.ActivePersonalReminder[charKey]
    if active and active[encID] == noteName then return "up_to_date", noteName end
    return "imported", noteName
end

function EP.GetBossImportState(encID)
    local entries = EP.GetVariantsAll(encID, EP.GetCurrentSpecID())
    local foundImported, foundUpdate
    for i = 1, #(entries or {}) do
        local state = EP.GetRowState(encID, i)
        if state == "up_to_date" then return "up_to_date" end
        if state == "update" then foundUpdate = true end
        if state == "imported" then foundImported = true end
    end
    if foundUpdate then return "update" end
    if foundImported then return "imported" end
    return "none"
end


--[[ Diagnostic ----------------------------------------------------------]]

-- Contrôle minimal des API internes de NSRT utilisées par l'addon. Le but
-- est de refuser proprement une écriture si NSRT change sa structure au lieu
-- de provoquer une erreur Lua ou de laisser croire que l'import a réussi.
function EP.GetNSRTCompatibility()
    if type(NSRT) ~= "table" then
        return false, L["Northern Sky Raid Tools is not available."]
    end
    if type(NSRT.PersonalReminders) ~= "table" then
        return false, L["This version of NSRT does not expose Personal Notes in the expected format."]
    end
    if NSRT.ActivePersonalReminder ~= nil and type(NSRT.ActivePersonalReminder) ~= "table" then
        return false, L["This version of NSRT uses an unsupported active-note format."]
    end
    if NSRT.Reminders ~= nil and type(NSRT.Reminders) ~= "table" then
        return false, L["This version of NSRT uses an unsupported shared-note format."]
    end
    return true
end

-- Réglages NSRT qui empêcheraient nos rappels de s'afficher.
-- On ne force jamais les réglages du joueur, on l'informe clairement.
function EP.GetNSRTDisplayIssues()
    local issues = {}
    local rs = NSRT and NSRT.ReminderSettings
    if not rs then return issues end
    if rs.enabled == false then
        table.insert(issues, L["Reminders are disabled in NSRT"])
    end
    if rs.PersNote == false then
        table.insert(issues, L["Personal notes are disabled in NSRT"])
    end
    local frame = rs.PersonalReminderFrame
    if frame and frame.enabled == false then
        table.insert(issues, L["The Personal Reminder frame is hidden in NSRT"])
    end
    return issues
end

local displayWarningChecked
local function WarnIfHidden()
    if displayWarningChecked then return end
    displayWarningChecked = true
    local issues = EP.GetNSRTDisplayIssues()
    if #issues > 0 then
        Warn(table.concat(issues, " / ") .. " — "
            .. L["Enable them in NSRT's settings (/ns) for the reminders to show."])
    end
end

-- Garde-fou : aucune écriture de note ni aperçu pendant un combat.
local function BlockedInCombat()
    if InCombatLockdown() then
        Warn(L["Not available during combat."])
        return true
    end
    return false
end


--[[ Import des notes ----------------------------------------------------]]

-- Nom de base d'une note : « [AR] <Boss> - <Classe Spé> ».
-- Le nom du boss est inclus pour que la liste de NSRT reste lisible
-- quand une dizaine de notes sont chargées.
local function NoteBase(encID)
    return EP.PlanNamePrefix .. EP.GetEncounterName(encID) .. " - " .. EP.GetSpecLabel()
end

local function NextNoteName(base)
    local n = 1
    while NSRT.PersonalReminders[base .. " #" .. n] do
        n = n + 1
    end
    return base .. " #" .. n
end

-- Renomme une note héritée d'un ancien schéma de nommage (« [AR] Classe Spé
-- #1 ») vers le schéma courant, en conservant son contenu et son activation.
local function MigrateMappedNoteName(charKey, encID, map, key, noteName)
    if not (noteName and NSRT.PersonalReminders[noteName]) then return noteName end
    local expectedPrefix = NoteBase(encID) .. " #"
    if noteName:sub(1, #expectedPrefix) == expectedPrefix then return noteName end

    local newName = NextNoteName(NoteBase(encID))
    NSRT.PersonalReminders[newName] = NSRT.PersonalReminders[noteName]
    NSRT.PersonalReminders[noteName] = nil
    map[key] = newName

    local active = NSRT.ActivePersonalReminder and NSRT.ActivePersonalReminder[charKey]
    if active and active[encID] == noteName then
        active[encID] = newName
    end
    return newName
end

-- Statut d'activation pour une variante WoW Timeline déjà importée : contrairement
-- aux notes partagées, on écrit nous-mêmes le pointeur d'activation
-- (ActivePersonalReminder), donc c'est fiable dès l'import — pas besoin
-- d'attendre une confirmation de NSRT ici.
function EP.GetPersonalNoteActivation(encID, entry)
    local map = GetLoadedMap(encID)
    local charKey = EP.GetCharKey()
    if not (map and charKey and entry) then return nil end
    local noteName = map[VariantKey(entry)]
    if not noteName then return nil end
    local active = NSRT and NSRT.ActivePersonalReminder
        and NSRT.ActivePersonalReminder[charKey] and NSRT.ActivePersonalReminder[charKey][encID]
    return active == noteName, noteName
end

--[[ Note active selon la difficulte --------------------------------------
  NSRT ne choisit pas la note personnelle d'apres la difficulte : il charge,
  au ready check et au pull, NSRT.ActivePersonalReminder[perso][encID] — une
  seule note par boss (verifie dans Reminders.lua, NSI:LoadPersReminder).
  Importer la note HM apres la MM faisait donc partir la HM en Mythique.

  On retient ici, a chaque import, quelle note a ete choisie pour CETTE
  difficulte et CETTE spe. Quand la difficulte du raid change (ou en entrant
  dans l'instance, ou en changeant de spe), on remet comme note active celle
  qui correspond — seulement parmi les notes que le joueur a deja importees.
  Rien n'est cree ni renvoye : on change le meme champ que le bouton
  « Charger ». Les notes partagees (Viserio) ne sont pas touchees : c'est le
  meneur qui choisit la note active du raid.
------------------------------------------------------------------------]]
local DIFFICULTY_BY_ID = { [16] = "Mythic", [15] = "Heroic" }

local function DifficultySlot(specID, difficulty)
    return tostring(specID or 0) .. ":" .. tostring(difficulty)
end

local function RememberDifficultyNote(charKey, encID, specID, difficulty, noteName)
    local db = DB()
    db.activeByDiff = db.activeByDiff or {}
    db.activeByDiff[charKey] = db.activeByDiff[charKey] or {}
    db.activeByDiff[charKey][encID] = db.activeByDiff[charKey][encID] or {}
    db.activeByDiff[charKey][encID][DifficultySlot(specID, difficulty)] = noteName
end

-- Difficulte du raid : celle de l'instance si on y est, sinon celle choisie
-- pour le groupe (menu du portrait). Normal, LFR, donjons : nil, on ne
-- touche a rien.
function EP.GetCurrentDifficulty()
    local _, instanceType, difficultyID = GetInstanceInfo()
    if instanceType ~= "raid" then
        difficultyID = GetRaidDifficultyID and GetRaidDifficultyID()
    end
    return DIFFICULTY_BY_ID[difficultyID]
end

function EP.IsAutoDifficulty()
    return DB().autoDifficulty ~= false
end

function EP.SetAutoDifficulty(on)
    DB().autoDifficulty = on and true or false
end

local difficultyPending = false

-- Renvoie le nombre de boss dont la note active a change.
function EP.ApplyDifficulty()
    if not EP.IsAutoDifficulty() then return 0 end
    if InCombatLockdown() then
        difficultyPending = true            -- refait a la sortie du combat
        return 0
    end
    difficultyPending = false
    local difficulty = EP.GetCurrentDifficulty()
    local charKey, specID = EP.GetCharKey(), EP.GetCurrentSpecID()
    if not (difficulty and charKey and EP.GetNSRTCompatibility()) then return 0 end
    local byEnc = DB().activeByDiff and DB().activeByDiff[charKey]
    if not byEnc then return 0 end
    NSRT.ActivePersonalReminder = NSRT.ActivePersonalReminder or {}
    NSRT.ActivePersonalReminder[charKey] = NSRT.ActivePersonalReminder[charKey] or {}
    local active = NSRT.ActivePersonalReminder[charKey]
    local switched = 0
    for encID, slots in pairs(byEnc) do
        local name = slots[DifficultySlot(specID, difficulty)]
        if name and not NSRT.PersonalReminders[name] then
            slots[DifficultySlot(specID, difficulty)] = nil   -- supprimee dans NSRT
        elseif name and active[encID] ~= name then
            active[encID] = name
            switched = switched + 1
        end
    end
    if switched > 0 then
        Say(L["%s: your notes for %d boss(es) now follow this difficulty in NSRT."]:format(
            L[difficulty], switched))
        if EP.RefreshStates then EP.RefreshStates() end
    end
    return switched
end

function EP.IsDifficultyPending() return difficultyPending end

-- Bouton « Charger » : crée (ou met à jour) une note indexée pour ce boss
-- et la sélectionne pour le chargement automatique au pull. Les notes déjà
-- importées restent : elles s'accumulent.
function EP.LoadVariant(encID, i)
    if BlockedInCombat() then return false end
    local compatible, reason = EP.GetNSRTCompatibility()
    if not compatible then
        Warn(reason)
        return false
    end
    if not EP.IsEnabled() or not EP.IsBossEnabled(encID) then return false end
    local specID = EP.GetCurrentSpecID()
    local entries = specID and EP.GetVariantsAll(encID, specID)
    local entry = entries and entries[i]
    local map = GetLoadedMap(encID)
    local charKey = EP.GetCharKey()
    if not (entry and map and charKey) then return false end

    local key = VariantKey(entry)
    local noteName = map[key]
    noteName = MigrateMappedNoteName(charKey, encID, map, key, noteName)
    if not (noteName and NSRT.PersonalReminders[noteName]) then
        noteName = NextNoteName(NoteBase(encID))
        map[key] = noteName
    end
    local bounds = EP.PhaseBoundaries(encID, entry.difficulty, entry.variant)
    NSRT.PersonalReminders[noteName] = BuildNoteString(
        encID, entry.difficulty, ResolveVariantReminders(entry, bounds), bounds, specID,
        EP.GetVariantModKey(entry))

    NSRT.ActivePersonalReminder = NSRT.ActivePersonalReminder or {}
    NSRT.ActivePersonalReminder[charKey] = NSRT.ActivePersonalReminder[charKey] or {}
    NSRT.ActivePersonalReminder[charKey][encID] = noteName
    RememberDifficultyNote(charKey, encID, specID, entry.difficulty, noteName)

    Say((L["\"%s\" imported as %s and set to load on your next pull."]):format(
        entry.variant.name, noteName))
    WarnIfHidden()
    if EP.RefreshStates then EP.RefreshStates() end
    return true
end


--[[ Notes complètes -> Shared Notes NSRT --------------------------------
  Une note Viserio couvre tout le raid : on la pousse telle quelle dans
  NSRT.Reminders (les « Shared Notes » de NSRT, onglet séparé des notes
  personnelles), avec chaque rappel étiqueté par SpecID (tag:<specID>).
  C'est le mécanisme natif de NSRT (NSI:EvaluateLoad / TagMatchesPlayer)
  qui redistribue ensuite automatiquement à chaque joueur du raid ses
  propres rappels selon sa spé — exactement comme s'partager manuellement
  une note Viserio "Copy -> From NSRT" puis Shared Notes -> Import.

  On ne l'active PAS automatiquement (NSRT.ActiveReminder) : ça reste au
  meneur de raid de choisir/synchroniser la note active depuis NSRT
  lui-même (onglet Shared Notes), exactement comme pour une note collée
  à la main. On se contente de la rendre disponible dans cette liste.
------------------------------------------------------------------------]]

local function BuildFullNoteString(encID, note, modKey)
    local timeMap = EP.GetLineTimeMap(modKey)
    local specMap = EP.GetSpecRemap(modKey)
    local spellMap = EP.GetLineSpellMap(modKey)
    local deletedLines = EP.GetDeletedLines(modKey)
    -- Les pages Viserio ne portent aucune phase : leurs temps sont absolus
    -- depuis le debut du combat. Jusqu'ici tout partait donc en ph:1, et sur
    -- un boss a phases NSRT detruisait tout ce qui tombait apres le premier
    -- changement de phase. On decoupe maintenant avec la table de reference
    -- (Data/Phases.lua), deja filtree des phases que NSRT n'atteint jamais.
    -- Une note lue par l'API Viserio porte ses propres debuts de phase
    -- (`phaseStarts`, mesures dans le plan de l'auteur) : PhaseBoundaries les
    -- prend en priorite. Sans eux (note lue par le HTML), repli sur la table.
    local bounds = EP.PhaseBoundaries(encID, note.difficulty, note)

    local bossName = EP.GetEncounterName(encID)
    local lines = {
        ("EncounterID:%d;Difficulty:%s;Name:%s"):format(encID, note.difficulty, bossName)
    }

    -- `time` est ABSOLU ; la phase est deduite ici, jamais choisie a la main.
    local function EmitLine(time, bossSpell, target, spellID)
        local ph, rel = EP.SplitPhase(time, bounds)
        local parts = { ("time:%d"):format(rel), "ph:" .. FormatPhase(ph) }
        if bossSpell then
            parts[#parts + 1] = ("bossSpell:%d"):format(bossSpell)
        end
        -- NSRT reconnaît tag:<SpecID> (toute la spé) aussi bien que
        -- tag:<NomDuJoueur> (un joueur précis) — utile quand deux joueurs
        -- partagent la même spé et qu'un seul doit vraiment lancer ce
        -- sort précis.
        parts[#parts + 1] = "tag:" .. (type(target) == "string" and target or tostring(target))
        parts[#parts + 1] = ("spellid:%d"):format(spellID)
        lines[#lines + 1] = table.concat(parts, ";") .. ";"
    end

    -- Ordre de spé stable (tri par SpecID d'origine) pour un diff propre
    -- d'un export à l'autre, même quand certains rappels sont réassignés.
    local specIDs = {}
    for specID in pairs(note.specs) do table.insert(specIDs, specID) end
    table.sort(specIDs)
    for _, specID in ipairs(specIDs) do
        -- Un seul joueur par spe est inclus dans la note generee (voir
        -- EP.SpecActors) : sinon les deux series partiraient chez les deux
        -- joueurs de cette spe, dont celle qui ne les concerne pas.
        local actors = EP.SpecActors(note.specs[specID])
        for actorIdx, actorCasts in ipairs(actors) do
          -- Cible du bloc : le pseudo assigne par le RL. Le repli sur la
          -- spe ne sert que de filet — l'envoi est bloque tant qu'un bloc
          -- vivant n'est pas nomme (voir EP.GetUnnamedActors).
          local actorTarget = EP.GetActorName(modKey, specID, actorIdx) or specID
          for idx, r in ipairs(actorCasts) do
            -- Modifications RAPPEL PAR RAPPEL, toutes indépendantes les
            -- unes des autres et de celles des autres rappels de la même
            -- spé d'origine : quand ça a lieu (time), qui reçoit l'alerte
            -- (tag), quel sort est réellement concerné (spellid), et si
            -- le rappel est supprimé de cette note — jamais globalement.
            local lineKey = EP.LineKey(specID, idx, actorIdx)
            if not (deletedLines and deletedLines[lineKey]) then
                local targetTime = (timeMap and timeMap[lineKey])
                if targetTime == nil then targetTime = r.time end
                local target = (specMap and specMap[lineKey]) or actorTarget
                local targetSpellID = (spellMap and spellMap[lineKey]) or r.spellid
                EmitLine(targetTime, r.bossSpell, target, targetSpellID)
            end
          end
        end
    end

    -- Rappels ajoutés à la main (voir EP.AddCustomLine) : ignorés tant
    -- qu'aucun sort n'a été choisi, pour ne jamais écrire une ligne
    -- invalide dans la note.
    for _, custom in ipairs(EP.GetCustomLines(modKey)) do
        if custom.spellid and custom.target and not (deletedLines and deletedLines[custom.lineKey]) then
            EmitLine(custom.time, nil, custom.target, custom.spellid)
        end
    end

    -- Même exigence que BuildNoteString ci-dessus : \n final obligatoire,
    -- sinon le dernier rappel de la note (d'origine ou ajouté à la main)
    -- disparaît silencieusement côté NSRT.
    return table.concat(lines, "\n") .. "\n"
end

local function SharedNoteBase(encID, note)
    return EP.PlanNamePrefix .. EP.GetEncounterName(encID) .. " - " .. note.name
end

local function NextSharedNoteName(base)
    local n = 1
    while NSRT.Reminders[base .. " #" .. n] do
        n = n + 1
    end
    return base .. " #" .. n
end

local function SharedNoteKey(encID, entry)
    local note = entry.note
    return (entry.sourceId or "?") .. "|" .. encID .. "|" .. note.difficulty
        .. "|" .. note.name .. "|" .. note.author
end

function EP.GetFullNoteModKey(encID, entry)
    return "full|" .. SharedNoteKey(encID, entry)
end

-- Point d'entrée unique pour l'UI : calcule la bonne clé de modificateurs
-- selon le modèle actif (note complète Viserio ou variante perso WoW Timeline),
-- sans que UI.lua ait à connaître la distinction.
function EP.GetModKeyForSelection(encID, entry)
    if not entry then return nil end
    if EP.IsFullRaidActive() then
        return EP.GetFullNoteModKey(encID, entry)
    end
    return EP.GetVariantModKey(entry)
end

local function GetSharedMap()
    local db = DB()
    db.sharedMap = db.sharedMap or {}
    return db.sharedMap
end

-- Bouton « Partager au groupe » : pousse la note complète (toutes spés)
-- dans les Shared Notes de NSRT. N'importe quel joueur peut le faire, pas
-- seulement celui qui a la spé concernée — la note couvre tout le raid.
-- Statut d'activation réel côté NSRT pour une note complète Viserio déjà
-- partagée : true si NSRT.ActiveReminder pointe bien vers NOTRE note pour
-- CE plan précis. nil si on n'a jamais partagé ce plan (pas encore de nom
-- suivi), donc pas d'avertissement à afficher dans ce cas — juste "pas
-- encore envoyée".
function EP.GetSharedNoteActivation(encID, entry)
    local sharedMap = GetSharedMap()
    local key = SharedNoteKey(encID, entry)
    local noteName = sharedMap[key]
    if not noteName then return nil end
    return NSRT and NSRT.ActiveReminder == noteName, noteName
end

function EP.ShareFullNote(encID, i)
    if BlockedInCombat() then return false end
    local compatible, reason = EP.GetNSRTCompatibility()
    if not compatible then
        Warn(reason)
        return false
    end
    if type(NSRT.Reminders) ~= "table" then
        Warn(L["This version of NSRT does not expose Shared Notes in the expected format."])
        return false
    end
    if not EP.IsEnabled() or not EP.IsBossEnabled(encID) then return false end
    local entries = EP.GetFullNotesForBoss(encID)
    local entry = entries and entries[i]
    if not entry then return false end
    local note = entry.note

    -- Refus tant qu'un bloc reste anonyme : sans pseudo, ses lignes
    -- partiraient avec tag:<specID> et s'afficheraient chez TOUS les
    -- joueurs de cette spe, y compris celui qu'elles ne concernent pas.
    local shareModKey = EP.GetFullNoteModKey(encID, entry)
    local unnamed = #EP.GetUnnamedActors(note, shareModKey)
                    + EP.GetUnnamedCustomLines(shareModKey)
    if unnamed > 0 then
        Warn((L["%d block(s) still need a player name before this note can be shared — reminders tagged by specialization would fire for everyone playing it."]):format(unnamed))
        return false
    end

    local sharedMap = GetSharedMap()
    local key = SharedNoteKey(encID, entry)
    local noteName = sharedMap[key]
    if not (noteName and NSRT.Reminders[noteName]) then
        noteName = NextSharedNoteName(SharedNoteBase(encID, note))
        sharedMap[key] = noteName
    end
    local modKey = EP.GetFullNoteModKey(encID, entry)
    NSRT.Reminders[noteName] = BuildFullNoteString(encID, note, modKey)
    -- Pas de ligne `invitelist:` dans nos notes générées : on aligne le
    -- comportement sur celui de NSI:InviteListFromReminder pour ce cas
    -- (retourne false quand aucune ligne invitelist n'est trouvée).
    NSRT.InviteList = NSRT.InviteList or {}
    NSRT.InviteList[noteName] = false

    Say((L["\"%s\" shared to NSRT's Shared Notes as %s. Open NSRT's Shared Notes tab and click it to activate/sync it to the raid — click it again after every re-send, even if it was already selected, or NSRT won't pick up your changes."]):format(
        note.name, noteName))
    -- On attend ici la confirmation réelle (voir NSRT_REMINDER_CHANGED plus
    -- bas) plutôt que de simplement espérer que le joueur a bien cliqué
    -- dans NSRT.
    EP.pendingConfirm = { noteName = noteName, planName = note.name }
    if NSRT and NSRT.ActiveReminder == noteName then
        EP.pendingConfirm = nil
        Say((L["\"%s\" is already active in NSRT."]):format(note.name))
    end
    if EP.RefreshStates then EP.RefreshStates() end
    return true
end


--[[ Activation par boss / globale ---------------------------------------]]

-- Activation par boss (par personnage). Désactivé = la note de ce boss est
-- retirée de NSRT, le reste continue de fonctionner.
local function GetBossDisabledTable()
    local db = DB()
    db.disabledBoss = db.disabledBoss or {}
    local charKey = EP.GetCharKey()
    if not charKey then return nil end
    db.disabledBoss[charKey] = db.disabledBoss[charKey] or {}
    return db.disabledBoss[charKey]
end

function EP.IsBossEnabled(encID)
    local t = GetBossDisabledTable()
    return not (t and t[encID])
end

-- Interrupteur général (compte entier). Désactiver suspend seulement les
-- imports et aperçus ; les notes existantes restent intactes dans NSRT.
function EP.IsEnabled()
    return DB().enabled ~= false
end

function EP.SetEnabled(on)
    DB().enabled = on and true or false
    if on then
        Say(L["AutoReminders enabled."])
    else
        Say(L["AutoReminders disabled. Imported notes were kept in NSRT."])
    end
    if EP.RefreshUI then EP.RefreshUI() end
end


--[[ Événements ----------------------------------------------------------]]

f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_SPECIALIZATION_CHANGED" and unit ~= "player" then return end
    -- Note active selon la difficulte (et la spe) : voir EP.ApplyDifficulty.
    -- Une seconde de delai : GetInstanceInfo n'est pas toujours a jour a
    -- l'instant meme de l'evenement.
    if event == "PLAYER_REGEN_ENABLED" then
        if EP.IsDifficultyPending() then C_Timer.After(1, EP.ApplyDifficulty) end
        return
    end
    if event ~= "PLAYER_LOGIN" then
        C_Timer.After(1, EP.ApplyDifficulty)
    end
    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_DIFFICULTY_CHANGED" then
        return
    end
    if event == "PLAYER_LOGIN" then
        C_Timer.After(3, function()
            local compatible, reason = EP.GetNSRTCompatibility()
            if not compatible then Warn((L["NSRT compatibility issue: %s"]):format(reason or "?")) end
            -- Aucune source enregistree = aucun fichier de donnees charge.
            -- L'archive de l'addon n'en livre plus (ils appartiennent a ton
            -- dossier et sont regeneres par le script) : sans ce message, la
            -- fenetre s'ouvrait vide sans rien expliquer.
            if #(EP.SourceOrder or {}) == 0 then
                Warn(L["No data loaded. Run NSRTAutoReminders-build.py to generate it."])
            end
        end)
    end
    -- Aucune écriture automatique : les notes ne se créent que via le bouton
    -- Charger. On rafraîchit juste l'affichage.
    C_Timer.After(2, function() if EP.RefreshUI then EP.RefreshUI() end end)
end)


--[[ Commandes -----------------------------------------------------------]]

-- /ar check : tout ce qu'il faut pour un rapport de bug, en une fois.
-- Lecture seule : ne modifie ni NSRT ni les reglages.
function EP.PrintDiagnostic()
    local get = C_AddOns and C_AddOns.GetAddOnMetadata or _G.GetAddOnMetadata
    local function Meta(addon)
        if not get then return "?" end
        local ok, v = pcall(get, addon, "Version")
        return (ok and v) or "?"
    end
    local function Count(t)
        local n = 0
        for _ in pairs(t or {}) do n = n + 1 end
        return n
    end
    Say(L["Diagnostic — copy these lines into a bug report:"])
    Say(("AutoReminders %s — " .. L["Language: %s"]):format(
        EP.GetVersion(), tostring(EP.GetLanguage())))
    local ok, reason = EP.GetNSRTCompatibility()
    if ok then
        Say(L["NSRT %s: compatible"]:format(Meta("NorthernSkyRaidTools")))
    else
        Warn(("NSRT %s: %s"):format(Meta("NorthernSkyRaidTools"), tostring(reason)))
    end
    for _, id in ipairs(EP.SourceOrder or {}) do
        local def = EP.Sources[id]
        local tbl = def.fullRaid and def.FullNotes or def.Plans
        local notes = 0
        for _, v in pairs(tbl or {}) do
            if def.fullRaid then
                notes = notes + #v
            else
                for _, bySpec in pairs(v) do
                    for _, list in pairs(bySpec) do notes = notes + #list end
                end
            end
        end
        Say(L["%s: data of %s, %d boss(es), %d note(s)"]:format(
            def.label or id, tostring(def.GeneratedAt or "?"), Count(tbl), notes))
    end
    Say(L["Phase table: %d boss(es); boss timelines: %d (WoW Timeline), %d (Viserio)"]:format(
        Count(EP.PhaseTable), Count(EP.BossTimeline), Count(EP.ViserioBossTimeline)))
    Say(L["Boss names from the Adventure Guide: %d/%d"]:format(EP.GetJournalStats()))
    local difficulty = EP.GetCurrentDifficulty()
    Say(L["Difficulty: %s — automatic note switch: %s"]:format(
        difficulty and L[difficulty] or "-",
        EP.IsAutoDifficulty() and L["on"] or L["off"]))
    local specID = EP.GetCurrentSpecID()
    local specName = specID and GetSpecializationInfoByID
        and select(2, GetSpecializationInfoByID(specID))
    Say(L["Specialization: %s — %s"]:format(
        specName and (specName .. " (" .. specID .. ")") or tostring(specID),
        EP.GetTagMode() == "name" and L["Tag: character name"] or L["Tag: specialization"]))
end

SLASH_NSRTAUTOREMINDERS1 = "/autoreminders"
SLASH_NSRTAUTOREMINDERS2 = "/ar"
SlashCmdList["NSRTAUTOREMINDERS"] = function(msg)
    local cmd = (msg:match("^(%S*)") or ""):lower()
    if cmd == "version" then
        Say(("|cFFFFFFFFv%s|r"):format(EP.GetVersion()))
    elseif cmd == "check" then
        EP.PrintDiagnostic()
    elseif cmd == "diff" then
        -- /ar diff : active/desactive le changement de note selon la difficulte.
        local on = not EP.IsAutoDifficulty()
        EP.SetAutoDifficulty(on)
        Say(on and L["Automatic note switch by difficulty enabled."]
            or L["Automatic note switch by difficulty disabled."])
        if on then EP.ApplyDifficulty() end
    elseif cmd == "tag" then
        -- /ar tag : bascule le tag des notes WoW Timeline (spe <-> nom).
        local mode = EP.GetTagMode() == "name" and "spec" or "name"
        EP.SetTagMode(mode)
        Say(mode == "name" and L["Reminders are now tagged with your character name."]
            or L["Reminders are now tagged with your specialization."])
        if EP.RefreshUI then EP.RefreshUI() end
    elseif cmd == "boss" then
        -- Le deroulement du boss double facilement le nombre de lignes :
        -- affiche par defaut, mais debrayable.
        --
        -- N'a d'effet visible que sur les sources spe-filtrees (WoW Timeline) :
        -- une note Viserio n'affiche plus le deroulement du tout, ses
        -- rappels n'ayant aucun lien avec les capacites (voir le bloc
        -- `local timeline = (not fullRaid) ...` dans UI.lua).
        local on = not EP.ShowBossTimeline()
        EP.SetShowBossTimeline(on)
        Say(on and L["Boss timeline shown."] or L["Boss timeline hidden."])
        if EP.RefreshUI then EP.RefreshUI() end
    else
        -- Repli utilisé quand l'onglet n'a pas encore pu s'accrocher à
        -- NSRT (voir Integration.lua) : doit vraiment ouvrir la fenêtre,
        -- pas juste exister sur le papier.
        if EP.ToggleMainWindow then EP.ToggleMainWindow() end
    end
end
