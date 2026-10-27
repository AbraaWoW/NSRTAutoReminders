local ADDON_NAME, EP = ...

--[[----------------------------------------------------------------------
  NSRT AutoReminders — Localisation (index)

  Un fichier par langue dans ce dossier (Locales/<code>.lua), plus ce
  fichier Index.lua chargé en premier (il crée EP.Locales / EP.L avant
  que les fichiers de langue ne s'enregistrent dedans).

  L'anglais est la langue par défaut : toute clé absente d'une table de
  langue est affichée telle quelle (c'est directement le texte anglais
  utilisé comme clé). Chaque langue ne redéfinit donc que ce qu'elle
  traduit.

  Convention : les libellés déjà en majuscules dans l'interface (RAID,
  BOSS...) sont stockés en majuscules ici. On n'appelle jamais :upper()
  sur une chaîne traduite, car le upper() de Lua ne gère pas les accents.

  Pour ajouter une langue : copiez un fichier existant, changez le code
  IETF dans EP.Locales["xxYY"] et traduisez les valeurs, puis ajoutez le
  fichier au .toc (dans le bloc Locales, avant Core.lua).
------------------------------------------------------------------------]]

EP.Locales = {}

-- Choix proposés dans le sélecteur de langue de l'addon. "Auto" suit la
-- langue du client WoW ; les autres forcent une langue précise quel que
-- soit le client. Chaque nom reste dans sa propre langue (on ne traduit
-- jamais "Français" en "French").
EP.LanguageChoices = {
    { id = "Auto", label = nil }, -- libellé résolu dynamiquement (voir UI.lua), dépend de la langue active
    { id = "enUS", label = "English" },
    { id = "frFR", label = "Français" },
    { id = "deDE", label = "Deutsch" },
    { id = "esES", label = "Español (España)" },
    { id = "esMX", label = "Español (Latinoamérica)" },
    { id = "itIT", label = "Italiano" },
    { id = "ptBR", label = "Português (Brasil)" },
    { id = "ruRU", label = "Русский" },
    { id = "koKR", label = "한국어" },
    { id = "zhCN", label = "简体中文" },
    { id = "zhTW", label = "繁體中文" },
}

-- Langue effective : par défaut, UNIQUEMENT la langue du client WoW
-- (GetLocale), enGB assimilé à enUS. Ne dépend plus des réglages de NSRT
-- (ça posait problème — la langue de l'addon changeait avec celle de NSRT,
-- de façon peu prévisible). Un choix explicite fait dans NOTRE sélecteur
-- (EP.SetLanguage) prend le dessus tant qu'il n'est pas remis sur "Auto".
function EP.GetLanguage()
    local languageId = NSRTAutoRemindersDB and NSRTAutoRemindersDB.language
    if not languageId or languageId == "Auto" then
        languageId = GetLocale()
    end
    if languageId == "enGB" then
        languageId = "enUS"
    end
    return languageId
end

-- Choix brut tel que réglé par le joueur ("Auto" si jamais touché) —
-- utilisé par le sélecteur pour savoir quelle entrée cocher.
function EP.GetLanguageChoice()
    return (NSRTAutoRemindersDB and NSRTAutoRemindersDB.language) or "Auto"
end

function EP.SetLanguage(id)
    NSRTAutoRemindersDB = NSRTAutoRemindersDB or {}
    NSRTAutoRemindersDB.language = id or "Auto"
    if EP.RefreshUI then EP.RefreshUI() end
end

-- Résolution dynamique : chaque texte est traduit au moment de son
-- affichage, dans la langue choisie ce jour-là. Clé absente ou langue
-- non traduite -> anglais (la clé elle-même).
EP.L = setmetatable({}, { __index = function(_, key)
    local t = EP.Locales[EP.GetLanguage()]
    return (t and t[key]) or key
end })
