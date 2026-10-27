local ADDON_NAME, EP = ...
local L = setmetatable({}, { __index = function(_, k) return (EP.L or {})[k] or k end })

--[[----------------------------------------------------------------------
  NSRT AutoReminders — Interface

  Palette et mécanique de survol/sélection reprises du code source réel
  de NSRT (Components.lua, AnchorWindow.lua) plutôt que d'une estimation
  visuelle — voir les commentaires sur P.bg/P.accent plus bas pour le détail.

  Coins arrondis : SetBackdrop ne sait dessiner que des rectangles droits,
  et recouvrir ses angles d'images de la même couleur ne découpe rien. Les
  surfaces arrondies sont donc composées de pièces : RoundedFill pour un
  aplat, RoundedBox pour un aplat bordé (deux aplats superposés, la
  bordure naissant de leur différence), SelectionRing pour un contour seul.
  (Une tentative via DetailsFramework a été essayée puis retirée : elle ne
  rendait pas non plus les coins en jeu et laissait un cadre fantôme à
  l'écran après fermeture de la fenêtre.)
------------------------------------------------------------------------]]

local MEDIA = "Interface\\AddOns\\NSRTAutoReminders\\Media\\"

-- Palette -----------------------------------------------------------------
-- Palette derivee de l'echelle Radix Slate (12 niveaux), relevee dans
-- ExwindTools : chaque teinte y est annotee de sa clarte CIE L* et de son
-- contraste WCAG. Les niveaux 1-2 sont les fonds, 3-5 les trois etats d'un
-- controle, 6-8 les bordures, 9-10 les aplats pleins, 11-12 le texte.
--
-- Le bleu plein est #2870bd et non le #0090ff plus vif : le texte blanc y
-- passe AA (5.07 contre 3.26), ce qui compte sur un bouton principal.
local function Hex(h, a)
    return { tonumber(h:sub(1, 2), 16) / 255,
             tonumber(h:sub(3, 4), 16) / 255,
             tonumber(h:sub(5, 6), 16) / 255, a }
end

-- Regroupees dans UNE table et non en locaux separes : Lua limite une
-- fonction a 60 upvalues, et CreateMainWindow en capturait 66. Une table
-- compte pour une seule, quel que soit le nombre de teintes.
local P = {
    accent      = Hex("70b8ff"),   -- aFg : accent de premier plan
    accentSolid = Hex("2870bd", 1), -- aSolid : aplat plein (texte blanc AA)
    menuHover   = Hex("96989b", 0.10), -- survol d'une ligne de menu
    hoverLift   = Hex("96989b", 0.14), -- survol d'un bouton ou d'un champ
    hover       = Hex("2870bd", 0.08), -- survol d'une ligne de liste
    success     = Hex("4cc38a"),   -- okFg
    warning     = Hex("ffb224"),
    -- Textes eclaircis (13.0.3) : sur le fond #1c1f24, l'ancien gris
    -- #6a6d71 des titres BOSS / MES RAPPELS, des temps et de la legende ne
    -- se lisait presque plus en jeu.
    info        = Hex("c3c6ca"),   -- dim
    spec        = Hex("c3c6ca"),   -- badge spécialisation : neutre
    source      = Hex("c3c6ca"),   -- badge source : repli si source inconnue
    count       = Hex("4cc38a"),   -- badge nombre de rappels : vert
    heroic      = Hex("70b8ff"),   -- badge héroïque : bleu clair
    mythic      = Hex("ff9d4d"),   -- badge mythique : orange adouci
    -- Lignes de deroulement du boss : en retrait, pour qu'elles se lisent
    -- comme un decor et non comme des rappels a executer.
    bossLine    = Hex("bfb0e6"),

    bg          = Hex("131619", 0.98),  -- canvas : fenêtre
    bar         = Hex("171a1f", 0.98),  -- panel  : barres haute et basse
    panel       = Hex("1c1f24", 1),     -- card   : panneaux et cartes
    pop         = Hex("23272c", 0.97), -- pop    : menu deroulant ouvert
    panelHead   = Hex("1f2328", 1),     -- head   : en-tête de carte
    field       = Hex("14171c", 1),     -- ctrl   : champs, boutons secondaires
    border      = Hex("3b3f44", 1),     -- bDef
    borderSoft  = Hex("292d31", 1),     -- bSubtle : séparateurs
    rowAlt      = Hex("202328", 1),     -- cardAlt : ligne alternée
    selected    = Hex("1d2530", 1),     -- ccSelected : ligne sélectionnée

    danger       = Hex("ff9592"),   -- danger : libelle d'une action destructrice
    dangerBorder = Hex("7a363b"),   -- dangerSoft : son contour au repos

    thumb       = Hex("c2c6cc"),   -- pastille du curseur, au repos
    thumbDown   = Hex("adb2b8"),   -- pendant le glissement
    text        = Hex("eef0f2"),
    textDim     = Hex("c3c6ca"),
    textFaint   = Hex("a2a6ab"),        -- ph : texte de remplacement
}

-- Métriques -----------------------------------------------------------------
local HEADER_H, CTRL_H, ACTION_H, ROW_H, ROW_STEP, COL_HEAD, PAD = 52, 40, 56, 60, 64, 32, 14
-- Hauteur de l'en-tete de boss : vignette de 52 plus ses marges.
local DETAILS_HEAD_H = 84
-- Meme raison que la palette : une table plutot que six locaux.
-- minW/minH : plancher mesure sur le contenu — colonne de gauche (240) plus
-- marges, plus la rangee de controles d'un rappel (temps, icone, libelle,
-- cible 150, sort 190, suppression). En dessous le texte se chevauche, donc
-- on l'interdit plutot que de laisser produire une fenetre illisible.
local WIN = { w = 1180, h = 760, minW = 1100, minH = 660, maxW = 2400, maxH = 1500 }
-- Rayons des surfaces arrondies, repris d'ExwindTools : 4 pour un controle,
-- 6 pour une fenetre surgissante, 8 pour une boite de dialogue, 10 pour une
-- carte. La fenetre elle-meme reste a 14, son cadre etant plus epais.
local MENU_R, CARD_R, FIELD_R, CTRL_R, WINDOW_R = 6, 10, 6, 4, 14

-- Hauteur de controle UNIQUE, comme ExwindTools (GUIMetrics : CONTROL_HEIGHT
-- = 30 pour bouton, champ, liste deroulante, pastille, ligne d'arbre et ligne
-- de menu). C'est de la que vient leur regularite : nos 26 / 28 / 32 choisis
-- au cas par cas donnaient une rangee de controles qui ne s'alignait jamais.
local CTRL_SIZE = 30
-- PISTES. Une ligne par capacite, ses occurrences posees sur l'axe du temps,
-- au lieu d'une ligne par occurrence. Sur Vashnik, 31 capacites du boss
-- tiennent ainsi sur 3 pistes, et la liste editable plus bas ne contient plus
-- que les rappels du joueur : 10 lignes manipulables au lieu de 41 melangees.
--
-- TOUT DANS UNE SEULE TABLE, et ce n'est pas qu'une question de rangement :
-- Lua 5.1 n'autorise que 60 upvalues par fonction, et la fonction qui
-- construit la fenetre en comptait deja 62 avec ces reglages declares un par
-- un. Une table = un seul upvalue.
local LANE = {
    LABEL   = 210,  -- largeur reservee au nom de la capacite, a gauche de l'axe
    H       = 24,   -- hauteur d'une piste
    ICON    = 16,   -- cote de l'icone posee a l'instant du lancer
    -- En dessous de ce nombre de pixels par seconde, deux icones se
    -- chevauchent et la piste devient illisible. On ne compresse donc pas
    -- indefiniment : au-dela, la timeline depasse la largeur disponible et un
    -- curseur horizontal apparait pour la parcourir.
    MIN_PPS = 2.6,
    HEAD    = 19,   -- hauteur de l'en-tete d'un panneau
    PAD     = 6,    -- marge basse d'un panneau
    GAP     = 10,   -- espace entre deux panneaux
    RULER   = 20,   -- hauteur de la regle de temps
    CAPTION = 18,   -- hauteur d'un intertitre
    LINE_W  = 306,  -- largeur d'une ligne de rappel en mode colonnes
    GUTTER  = 40,   -- gouttiere entre deux colonnes de rappels
}
-- Marges, memes sources : rowPaddingX 20, columnGap 20, cardBodyPadding 12,
-- sectionGroupGap 16, contentPaddingX 18.
local GAP = { rowX = 20, col = 20, cardBody = 12, group = 16, contentX = 18 }

--[[ Polices -----------------------------------------------------------------

La police du jeu n'a pas de graisse : FRIZQT__.TTF n'existe qu'en un poids.
ExwindTools compose donc toute sa hierarchie avec la seule taille — son
ExwindGUI.lua reprend GameFontHighlight:GetFont() et ne change que le corps.

On embarque Noto Sans en deux graisses (SIL OFL, voir Media/Fonts/OFL.txt)
pour retrouver le demi-gras de la maquette, plus un Noto Sans Mono reduit aux
chiffres pour que la colonne des temps s'aligne vraiment.

Les locales CJK gardent la police du jeu : couvrir le coreen et les deux
chinois demanderait plusieurs megaoctets de glyphes. La hierarchie y repose
alors sur la taille seule, exactement comme chez ExwindTools.

Regroupe dans un do...end : seul `Typeset` sort, donc une seule upvalue pour
les fonctions qui s'en servent (CreateMainWindow en frole deja la limite).
]]
local Typeset, ReText
do
    local CJK = { koKR = true, zhCN = true, zhTW = true }
    local game = GameFontHighlight:GetFont()
    local dir = MEDIA .. "Fonts\\"
    local file = { reg = game, semi = game, mono = game }

    if not CJK[GetLocale()] then
        local want = {
            reg  = dir .. "NotoSans-Regular.ttf",
            semi = dir .. "NotoSans-SemiBold.ttf",
            mono = dir .. "NotoSansMono-Regular.ttf",
        }
        -- SetFont renvoie false quand le fichier manque ou n'est pas lisible.
        -- On teste une fois sur une chaine jetable, plutot que de decouvrir le
        -- probleme libelle par libelle avec une fenetre vide a l'ecran.
        local probe = UIParent:CreateFontString(nil, "BACKGROUND")
        for key, path in pairs(want) do
            if probe:SetFont(path, 13, "") then file[key] = path end
        end
        probe:Hide()
    end

    -- Roles typographiques de la maquette V2.
    local role = {
        bossTitle = { 21, "semi" },
        brand     = { 15, "semi" },
        section   = { 15, "semi" },
        strong    = { 13, "semi" },
        text      = { 13, "reg"  },
        time      = { 13, "mono" },
        hint      = { 11, "reg"  },
        chip      = { 10, "semi" },
    }

    function Typeset(region, name)
        region.arRole = name
        local r = role[name] or role.text
        region:SetFont(file[r[2]], r[1], "")
        return region
    end

    -- Un caractere absent de la police embarquee se dessine en carre vide.
    -- Le cas courant est un nom de joueur : "Top #4 : 五月" sortait en
    -- "Top #4 : 口口" sur un client francais, alors que la police du jeu,
    -- elle, couvre ces glyphes.
    --
    -- Le test porte sur les OCTETS et non sur les codes : en UTF-8 un octet
    -- >= 0xE0 ouvre un caractere >= U+0800, donc hors latin, grec et
    -- cyrillique — exactement ce que contient le sous-ensemble embarque.
    local function Exotic(text)
        if type(text) ~= "string" then return false end
        for i = 1, #text do
            if text:byte(i) >= 0xE0 then return true end
        end
        return false
    end

    -- A utiliser partout ou la chaine vient du jeu ou du joueur : nom de
    -- boss, de sort, de personnage. Le corps ne change pas, seule la fonte.
    function ReText(region, text)
        local r = role[region.arRole] or role.text
        region:SetFont(Exotic(text) and game or file[r[2]], r[1], "")
        region:SetText(text)
    end
end

-- Une teinte par source, pour reconnaitre d'ou vient une note sans lire le
-- libelle. Choisies hors des couleurs deja porteuses de sens dans la rangee
-- de pastilles — orange/bleu clair pour la difficulte a gauche, vert pour le
-- nombre de rappels a droite. Une source absente de cette table retombe sur
-- P.source ; `def.color` d'une source l'emporte si elle en declare une.
local SOURCE_COLORS = {
    wowtimeline = Hex("a78bfa"),   -- violet
    viserio = Hex("f472b6"),   -- rose
}
local MIN_SCALE, MAX_SCALE, SCALE_STEP = 0.60, 1.60, 0.05
local MIN_SCALE_TICK, MAX_SCALE_TICK = 0, 20
local BOSS_PLACEHOLDER = "Interface\\Icons\\Achievement_Boss_Archimonde"

local UI

--[[ État persistant -------------------------------------------------------]]

local function DB()
    NSRTAutoRemindersDB = NSRTAutoRemindersDB or {}
    NSRTAutoRemindersDB.ui = NSRTAutoRemindersDB.ui or {}
    return NSRTAutoRemindersDB.ui
end

-- Sélection courante (saison / raid / boss / timeline) : PAR PERSONNAGE.
local function SEL()
    local ui = DB()
    ui.sel = ui.sel or {}
    local key = EP.GetCharKey() or "?"
    ui.sel[key] = ui.sel[key] or {}
    return ui.sel[key]
end

--[[ Utilitaires ------------------------------------------------------------]]

local function FormatTime(t)
    t = t or 0
    local sign = t < 0 and "-" or ""
    t = math.abs(t)
    return ("%s%d:%02d"):format(sign, math.floor(t / 60), t % 60)
end

-- Le curseur avance par crans entiers plutôt que par valeurs décimales :
-- ça garantit exactement 0.05 par cran et évite toute dérive flottante ou
-- position intermédiaire du curseur selon le client.
-- Echelle maximale REELLEMENT utilisable : au-dela, la fenetre deborde de
-- l'ecran et ses bords deviennent inatteignables. 1.60 sur une fenetre de
-- 1180 fait 1888 pixels de large, soit plus que bien des resolutions.
-- On borne donc par la place disponible, en gardant une marge de 2 %.
local function MaxUsableScale()
    local parent = UIParent
    if not (parent and parent.GetWidth) then return MAX_SCALE end
    local sw, sh = parent:GetWidth(), parent:GetHeight()
    local win = _G.NSRTAutoRemindersMainWindow
    local w = (win and win.GetWidth and win:GetWidth()) or WIN.w
    local h = (win and win.GetHeight and win:GetHeight()) or WIN.h
    if not (sw and sh) or sw <= 0 or sh <= 0 or w <= 0 or h <= 0 then
        return MAX_SCALE
    end
    return math.max(MIN_SCALE, math.min(MAX_SCALE, (sw * 0.98) / w, (sh * 0.98) / h))
end

local function ClampScale(value)
    value = tonumber(value) or 1
    local usable = MaxUsableScale()
    value = math.min(value, usable)
    local tick = math.floor(((value - MIN_SCALE) / SCALE_STEP) + 0.5)
    tick = math.max(MIN_SCALE_TICK, math.min(MAX_SCALE_TICK, tick))
    -- L'arrondi au cran le plus proche peut repasser au-dessus de la limite :
    -- on redescend d'un cran plutot que de deborder, meme de peu.
    while tick > MIN_SCALE_TICK and MIN_SCALE + (tick * SCALE_STEP) > usable do
        tick = tick - 1
    end
    return MIN_SCALE + (tick * SCALE_STEP)
end
local function ScaleToTick(value)
    value = ClampScale(value)
    return math.floor(((value - MIN_SCALE) / SCALE_STEP) + 0.5)
end
local function TickToScale(tick)
    tick = math.floor((tonumber(tick) or 0) + 0.5)
    tick = math.max(MIN_SCALE_TICK, math.min(MAX_SCALE_TICK, tick))
    -- Meme borne que ClampScale : le curseur ne doit pas pouvoir amener la
    -- fenetre au-dela du bord de l'ecran.
    return math.min(MIN_SCALE + (tick * SCALE_STEP), MaxUsableScale())
end

local function Backdrop(frame, color, border)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(unpack(color or P.panel))
    frame:SetBackdropBorderColor(unpack(border or P.border))
end

-- Lisere de selection : un contour arrondi, et non un simple aplat.
--
-- Quatre arcs (textures blanches, teintees a l'execution pour pouvoir servir
-- a n'importe quelle couleur) relies par quatre segments d'1 px. Le tout vit
-- dans un cadre qu'on montre ou cache d'un bloc.
-- 5 px : accorde au rayon des textures de bouton (4), le lisere etant
-- pose 1 px en retrait.
local SELECTION_RING_R = 5
local function SelectionRing(parent, inset, color)
    local r = SELECTION_RING_R
    local ring = CreateFrame("Frame", nil, parent)
    ring:SetPoint("TOPLEFT", inset, -inset)
    ring:SetPoint("BOTTOMRIGHT", -inset, inset)
    ring:EnableMouse(false)
    ring:SetFrameLevel((parent:GetFrameLevel() or 1) + 3)

    local function Line()
        local t = ring:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(color[1], color[2], color[3], 1)
        return t
    end
    local top = Line()
    top:SetPoint("TOPLEFT", r, 0); top:SetPoint("TOPRIGHT", -r, 0); top:SetHeight(1)
    local bottom = Line()
    bottom:SetPoint("BOTTOMLEFT", r, 0); bottom:SetPoint("BOTTOMRIGHT", -r, 0); bottom:SetHeight(1)
    local left = Line()
    left:SetPoint("TOPLEFT", 0, -r); left:SetPoint("BOTTOMLEFT", 0, r); left:SetWidth(1)
    local right = Line()
    right:SetPoint("TOPRIGHT", 0, -r); right:SetPoint("BOTTOMRIGHT", 0, r); right:SetWidth(1)

    for _, spec in ipairs({
        { point = "TOPLEFT", file = "topleft" },
        { point = "TOPRIGHT", file = "topright" },
        { point = "BOTTOMLEFT", file = "bottomleft" },
        { point = "BOTTOMRIGHT", file = "bottomright" },
    }) do
        local tex = ring:CreateTexture(nil, "OVERLAY")
        tex:SetSize(r, r)
        tex:SetPoint(spec.point, 0, 0)
        tex:SetTexture(MEDIA .. "UI\\ring_" .. spec.file)
        tex:SetVertexColor(color[1], color[2], color[3], 1)
    end

    ring:Hide()
    return ring
end

-- Aplat arrondi, pendant plein du lisere ci-dessus : trois blocs unis et
-- quatre quarts de disque blancs, teintes a l'execution.
--
-- Les fill_* sont traces sur le meme cercle que les arcs du lisere, a ceci
-- pres qu'ils font 32 px : un quart de disque se reduit proprement a
-- n'importe quel rayon, alors qu'une piece de 5 px agrandie baverait. Le
-- meme jeu d'images sert donc aussi bien a une ligne de menu (rayon 5) qu'a
-- une tuile de logo (rayon 8) ou a un panneau (rayon 10).
--
-- Les textures sont posees DIRECTEMENT sur le cadre, et non dans un
-- sous-cadre : un sous-cadre vit a un niveau superieur et passerait donc
-- devant le texte de la ligne, qu'il masquerait.
local function RoundedFill(frame, layer, color, radius, inset, sub)
    local r = radius or SELECTION_RING_R
    -- `inset` vaut un nombre pour un retrait uniforme, ou { x, y } quand les
    -- deux different : le rail du curseur d'echelle doit toucher les bords en
    -- largeur tout en ne faisant que 4 px de haut dans un cadre de 12.
    local ix, iy
    if type(inset) == "table" then ix, iy = inset[1] or 0, inset[2] or 0
    else ix = inset or 0; iy = ix end
    local a = color[4] or 1
    local parts = {}

    local function Piece(file)
        local t = frame:CreateTexture(nil, layer, nil, sub)
        -- Les quarts de disque sont des images blanches qu'on teinte ; les
        -- blocs unis, eux, sont des aplats de couleur. Ils ne se recolorent
        -- donc pas de la meme facon : on retient lesquels sont lesquels.
        t.isArc = file and true or false
        if file then
            t:SetSize(r, r)
            t:SetTexture(MEDIA .. "UI\\fill_" .. file)
        end
        table.insert(parts, t)
        return t
    end

    local mid = Piece()
    mid:SetPoint("TOPLEFT", ix + r, -iy); mid:SetPoint("BOTTOMRIGHT", -ix - r, iy)
    local left = Piece()
    left:SetPoint("TOPLEFT", ix, -iy - r); left:SetPoint("BOTTOMLEFT", ix, iy + r); left:SetWidth(r)
    local right = Piece()
    right:SetPoint("TOPRIGHT", -ix, -iy - r); right:SetPoint("BOTTOMRIGHT", -ix, iy + r); right:SetWidth(r)
    for _, spec in ipairs({
        { point = "TOPLEFT", x = ix, y = -iy, file = "topleft" },
        { point = "TOPRIGHT", x = -ix, y = -iy, file = "topright" },
        { point = "BOTTOMLEFT", x = ix, y = iy, file = "bottomleft" },
        { point = "BOTTOMRIGHT", x = -ix, y = iy, file = "bottomright" },
    }) do
        Piece(spec.file):SetPoint(spec.point, spec.x, spec.y)
    end

    local fill = {}
    function fill:SetShown(on)
        for _, t in ipairs(parts) do t:SetShown(on and true or false) end
    end
    function fill:SetColor(c)
        local al = c[4] or 1
        for _, t in ipairs(parts) do
            if t.isArc then t:SetVertexColor(c[1], c[2], c[3], al)
            else t:SetColorTexture(c[1], c[2], c[3], al) end
        end
    end
    fill:SetColor(color)
    fill:SetShown(false)
    return fill
end

-- Decoupe : l'exact complement de RoundedFill, a partir des cut_<coin>.
--
-- Sert a poser une IMAGE dans une surface arrondie. Une texture est toujours
-- un rectangle droit ; on lui repeint donc les angles a la couleur de ce qui
-- se trouve derriere, et la forme arrondie reapparait. C'est la seule methode
-- qui tienne ici : un masque unique etire sur un en-tete de 1000 x 84
-- rendrait les coins elliptiques.
local function RoundedClip(frame, layer, color, radius, inset, sub)
    local r = radius or SELECTION_RING_R
    local i = inset or 0
    local a = color[4] or 1
    for _, spec in ipairs({
        { point = "TOPLEFT", x = i, y = -i, file = "topleft" },
        { point = "TOPRIGHT", x = -i, y = -i, file = "topright" },
        { point = "BOTTOMLEFT", x = i, y = i, file = "bottomleft" },
        { point = "BOTTOMRIGHT", x = -i, y = i, file = "bottomright" },
    }) do
        local t = frame:CreateTexture(nil, layer, nil, sub)
        t:SetSize(r, r)
        t:SetPoint(spec.point, spec.x, spec.y)
        t:SetTexture(MEDIA .. "UI\\cut_" .. spec.file)
        t:SetVertexColor(color[1], color[2], color[3], a)
    end
end

-- Un carre a coins arrondis, borde : deux aplats superposes plutot qu'un
-- aplat plus un contour. L'exterieur porte la couleur de bordure, l'interieur
-- est pose 1 px en retrait avec un rayon reduit d'autant.
--
-- Pourquoi pas SelectionRing : son trait d'1 px est grave dans l'image, donc
-- un jeu d'arcs ne vaut que pour SON rayon. Ici la bordure naît de la
-- difference entre deux aplats, et marche a n'importe quel rayon.
local function RoundedBox(frame, layer, fill, border, radius)
    local r = radius or SELECTION_RING_R
    -- Remplacant de Backdrop : on retire le rectangle a angles droits, sans
    -- quoi il resterait visible derriere les coins decoupes.
    if frame.SetBackdrop then frame:SetBackdrop(nil) end
    local outer, inner
    if border then
        outer = RoundedFill(frame, layer, border, r, 0, 0)
        inner = RoundedFill(frame, layer, fill, math.max(1, r - 1), 1, 1)
        outer:SetShown(true)
    else
        inner = RoundedFill(frame, layer, fill, r, 0, 0)
    end
    inner:SetShown(true)
    -- Rendus pour les surfaces qui changent de couleur apres coup (un badge
    -- prend la teinte de ce qu'il annonce).
    return inner, outer
end

-- Contraste WCAG, pour que le libelle d'une pastille reste lisible quelle
-- que soit la couleur qu'elle porte.
--
-- Une pastille se peint dans la teinte de ce qu'elle annonce, et certaines
-- couleurs de classe sont trop sombres pour servir de texte sur leur propre
-- fond : chevalier de la mort 3,31, chasseur de demons 3,48, chaman 3,93 —
-- sous le seuil AA de 4,5. On les eclaircit vers le blanc par petits pas
-- jusqu'a passer le seuil ; la teinte reste reconnaissable (#C41E3A devient
-- #D15166, toujours le rouge du chevalier). Les dix autres classes sont
-- deja au-dessus et ressortent inchangees.
local function Luminance(c)
    local function ch(v)
        if v <= 0.03928 then return v / 12.92 end
        return ((v + 0.055) / 1.055) ^ 2.4
    end
    return 0.2126 * ch(c[1]) + 0.7152 * ch(c[2]) + 0.0722 * ch(c[3])
end

local function Readable(c, bg, target)
    local lb = Luminance(bg)
    local out = { c[1], c[2], c[3] }
    for _ = 1, 24 do
        local lf = Luminance(out)
        local hi = math.max(lf, lb)
        local lo = math.min(lf, lb)
        if (hi + 0.05) / (lo + 0.05) >= (target or 4.5) then break end
        out[1] = math.min(1, out[1] + (1 - out[1]) * 0.12)
        out[2] = math.min(1, out[2] + (1 - out[2]) * 0.12)
        out[3] = math.min(1, out[3] + (1 - out[3]) * 0.12)
    end
    return out
end

local function Tint(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end
local function TintTex(tex, c) tex:SetVertexColor(c[1], c[2], c[3]) end

-- Champ de recherche des menus deroulants.
--
-- InputBoxTemplate arrive avec son liptique dore de Blizzard, qui jure avec
-- le reste : on masque ses trois pieces et on repeint un champ plat a coins
-- arrondis. Au repos il porte un contour sobre ; des qu'il a le focus, le
-- lisere bleu s'allume, exactement comme un element selectionne.
local function StyleSearchBox(box)
    for _, key in ipairs({ "Left", "Right", "Middle" }) do
        local piece = box[key]
        if piece then piece:Hide() end
    end
    box:SetTextInsets(8, 8, 0, 0)
    RoundedFill(box, "BACKGROUND", P.field):SetShown(true)
    local rest = SelectionRing(box, 0, P.borderSoft)
    rest:Show()
    local focus = SelectionRing(box, 0, P.accent)
    box:HookScript("OnEditFocusGained", function() rest:Hide(); focus:Show() end)
    box:HookScript("OnEditFocusLost", function() focus:Hide(); rest:Show() end)
    return box
end

-- Texte coloré inline (codes couleur WoW) : utile dans les libellés de
-- menu déroulant, où une seule ligne doit porter à la fois le nom et un
-- statut coloré (pas de sous-titre séparé possible dans ce widget).
local function ColorText(text, c)
    return ("|cff%02x%02x%02x%s|r"):format(
        math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5), text)
end

-- Rappelle systématiquement le survol "de base" du widget (fondu cyan de
-- Button/Dropdown/etc.) avant d'afficher l'infobulle, au lieu de
-- l'écraser — sinon tout bouton avec une infobulle perdait son effet de
-- survol, contrairement aux autres. On lit `self.baseOnEnter/baseOnLeave`
-- (posés une fois à la création du widget) plutôt que le script actuel,
-- pour rester rappelable sans imbrication même si appelé à chaque refresh.
--
-- `text` est la CLE anglaise : elle est traduite au moment du survol, dans
-- la langue active a cet instant. Traduite a la creation, l'infobulle
-- restait dans la langue du premier affichage apres un changement de
-- langue (zoom, curseur, poignee de redimensionnement...). Un texte deja
-- traduit passe aussi : L[] renvoie tel quel ce qui n'est pas une cle.
local function Tooltip(frame, text)
    frame:SetScript("OnEnter", function(self)
        if self.baseOnEnter then self.baseOnEnter(self) end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L[text], 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function(self)
        if self.baseOnLeave then self.baseOnLeave(self) end
        GameTooltip:Hide()
    end)
end

local function SlugFromName(name)
    local s = (name or "unknown"):lower()
    s = s:gsub("[’'`]", ""):gsub("&", "and"):gsub("[^a-z0-9]+", "-"):gsub("^-", ""):gsub("-$", "")
    return s
end

-- Essaie chaque chemin dans l'ordre et garde le premier fichier existant.
local function ApplyFirst(texture, paths, placeholder)
    for _, path in ipairs(paths) do
        texture:SetTexture(path)
        if texture:GetTexture() then
            texture:SetDesaturated(false)
            texture:SetVertexColor(1, 1, 1, 1)
            return true
        end
    end
    if placeholder then
        texture:SetTexture(placeholder)
        texture:SetDesaturated(true)
        texture:SetVertexColor(0.55, 0.55, 0.55, 1)
    end
    return false
end

local function ApplyRaidTexture(texture, name)
    return ApplyFirst(texture, { MEDIA .. "Raid\\" .. SlugFromName(name) .. ".tga" }, BOSS_PLACEHOLDER)
end

local function ApplyBossTexture(texture, encID)
    return ApplyFirst(texture, {
        MEDIA .. "Boss\\" .. tostring(encID) .. ".tga",
        MEDIA .. "Boss\\" .. SlugFromName(EP.GetEncounterName(encID)) .. ".tga",
    }, BOSS_PLACEHOLDER)
end

--[[ Composants -------------------------------------------------------------]]

-- Mécanique reprise du CreateButton de NSRT (Components.lua) : pas de
-- bordure au repos, juste un fond plein ; un voile cyan à opacité fixe
-- apparaît en fondu au survol (hover_color) et reste affiché fixe pour
-- l'état "primary"/actif (selected_color) ; le texte reste blanc pur en
-- permanence, posé au-dessus des voiles pour ne jamais être assombri.
-- Case a cocher de la liste des rappels : deux pastilles superposees (le
-- contour, puis le fond) et la coche. Un seul upvalue pour la fonction qui
-- construit la fenetre, comme les autres widgets.
local function CheckBox(parent, size)
    local c = CreateFrame("Button", nil, parent)
    c:SetSize(size or 16, size or 16)
    c.edge = c:CreateTexture(nil, "ARTWORK", nil, 1)
    c.edge:SetAllPoints()
    c.edge:SetTexture(MEDIA .. "UI\\swatch")
    c.fill = c:CreateTexture(nil, "ARTWORK", nil, 2)
    c.fill:SetPoint("TOPLEFT", 1.5, -1.5)
    c.fill:SetPoint("BOTTOMRIGHT", -1.5, 1.5)
    c.fill:SetTexture(MEDIA .. "UI\\swatch")
    c.mark = c:CreateTexture(nil, "OVERLAY")
    c.mark:SetPoint("TOPLEFT", 1, -1)
    c.mark:SetPoint("BOTTOMRIGHT", -1, 1)
    c.mark:SetTexture(MEDIA .. "UI\\check")
    function c:SetChecked(on)
        self.checked = on and true or false
        TintTex(self.edge, on and P.accent or P.textDim)
        TintTex(self.fill, on and P.accentSolid or P.panel)
        self.mark:SetShown(self.checked)
    end
    c:SetChecked(false)
    return c
end

local function Button(parent, text, w, h, primary, icon)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b.minWidth = w or 120
    local height = h or 28
    b:SetSize(b.minWidth, height)
    b.primary = primary

    -- Fond en 3 morceaux pré-fabriqués (coin gauche arrondi + milieu
    -- extensible + coin droit arrondi), voir Media/UI/btn_*.tga et
    -- btnprimary_*.tga — de simples images fixes affichées telles
    -- quelles, comme les icônes (qui, elles, s'affichaient déjà
    -- correctement) : plus de composition de coins à la volée, qui ne
    -- se rendait pas correctement en jeu.
    local prefix = primary and "btnprimary" or "btn"
    b.bgLeft = b:CreateTexture(nil, "BACKGROUND")
    b.bgLeft:SetSize(16, height)
    b.bgLeft:SetPoint("TOPLEFT", 0, 0)
    b.bgLeft:SetPoint("BOTTOMLEFT", 0, 0)
    b.bgLeft:SetTexture(MEDIA .. "UI\\" .. prefix .. "_left")

    b.bgRight = b:CreateTexture(nil, "BACKGROUND")
    b.bgRight:SetSize(16, height)
    b.bgRight:SetPoint("TOPRIGHT", 0, 0)
    b.bgRight:SetPoint("BOTTOMRIGHT", 0, 0)
    b.bgRight:SetTexture(MEDIA .. "UI\\" .. prefix .. "_right")

    -- Ancré des deux côtés (au coin gauche ET au coin droit) : WoW
    -- étire automatiquement cette texture pour combler l'espace entre
    -- les deux, quelle que soit la largeur du bouton — aucun recalcul
    -- manuel nécessaire quand le texte (et donc la largeur) change.
    b.bgMid = b:CreateTexture(nil, "BACKGROUND")
    b.bgMid:SetPoint("TOPLEFT", b.bgLeft, "TOPRIGHT", 0, 0)
    b.bgMid:SetPoint("BOTTOMRIGHT", b.bgRight, "BOTTOMLEFT", 0, 0)
    b.bgMid:SetTexture(MEDIA .. "UI\\" .. prefix .. "_mid")

    b.hoverBg = CreateFrame("Frame", nil, b)
    b.hoverBg:SetPoint("TOPLEFT", 3, -3)
    b.hoverBg:SetPoint("BOTTOMRIGHT", -3, 3)
    b.hoverBg:EnableMouse(false)
    b.hoverBg.tex = b.hoverBg:CreateTexture(nil, "ARTWORK")
    b.hoverBg.tex:SetAllPoints()
    b.hoverBg.tex:SetColorTexture(P.hoverLift[1], P.hoverLift[2], P.hoverLift[3], P.hoverLift[4])
    b.hoverBg:SetAlpha(0)

    b.selectedBg = CreateFrame("Frame", nil, b)
    b.selectedBg:SetPoint("TOPLEFT", 3, -3)
    b.selectedBg:SetPoint("BOTTOMRIGHT", -3, 3)
    b.selectedBg:EnableMouse(false)
    b.selectedBg.tex = b.selectedBg:CreateTexture(nil, "ARTWORK")
    b.selectedBg.tex:SetAllPoints()
    -- Teinte discrete : c'est le lisere qui porte la selection, le fond ne
    -- fait que la souligner. A 0.55 les deux se disputaient le regard.
    b.selectedBg.tex:SetColorTexture(0.157, 0.439, 0.741, 0.18)
    -- Plus de voile permanent sur un bouton principal : son aspect vient
    -- desormais de ses propres textures (degrade + bordure). Le voile ne sert
    -- plus qu'a l'etat selectionne, via SetSelected.
    b.selectedBg:SetAlpha(0)

    -- Texte BLANC sur les boutons principaux. Le noir se justifiait tant que
    -- le fond etait un cyan clair ; sur le bleu #2870bd il devient illisible.
    -- Cette teinte a precisement ete retenue parce que le blanc y atteint un
    -- contraste de 5.07, donc le niveau AA — ce que le cyan ne permettait pas.
    local textColor = primary and { 1, 1, 1 } or P.text

    if icon then
        b.icon = b:CreateTexture(nil, "OVERLAY")
        b.icon:SetSize(14, 14)
        b.icon:SetTexture(icon)
        TintTex(b.icon, textColor)
    end

    b.label = Typeset(b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), "text")
    b.label:SetDrawLayer("OVERLAY", 2)
    Tint(b.label, textColor)
    if primary then
        -- Legere ombre portee : elle detache le blanc du bleu sans l'assombrir.
        b.label:SetShadowOffset(1, -1)
        b.label:SetShadowColor(0, 0, 0, 0.45)
    end

    b.baseOnEnter = function(self) UIFrameFadeIn(self.hoverBg, 0.12, self.hoverBg:GetAlpha(), 1) end
    b.baseOnLeave = function(self) UIFrameFadeOut(self.hoverBg, 0.20, self.hoverBg:GetAlpha(), 0) end
    b:SetScript("OnEnter", b.baseOnEnter)
    b:SetScript("OnLeave", b.baseOnLeave)

    b.ring = SelectionRing(b, 1, P.accent)

    function b:SetSelected(on)
        self.selected = on
        if self.ring then self.ring:SetShown(on and true or false) end
        if on then
            UIFrameFadeIn(self.selectedBg, 0.10, self.selectedBg:GetAlpha(), 1)
        else
            UIFrameFadeOut(self.selectedBg, 0.15, self.selectedBg:GetAlpha(), 0)
        end
    end

    -- Variante destructrice : meme gabarit, mais fond sombre a contour rouge
    -- et libelle rouge clair. On ne teinte pas le bouton ordinaire en rouge —
    -- la teinte s'appliquerait aussi au remplissage et donnerait un bouton
    -- entierement rouge, qui crierait plus fort que l'action ne le merite.
    function b:SetDanger()
        self.bgLeft:SetTexture(MEDIA .. "UI\\btndanger_left")
        self.bgMid:SetTexture(MEDIA .. "UI\\btndanger_mid")
        self.bgRight:SetTexture(MEDIA .. "UI\\btndanger_right")
        self.dangerStyle = true
        Tint(self.label, P.danger)
        if self.icon then TintTex(self.icon, P.danger) end
        -- Survol rouge et non bleu, sinon les deux couleurs se contredisent.
        self.hoverBg.tex:SetColorTexture(0.898, 0.282, 0.302, 0.22)
    end

    function b:SetEnabledState(on)
        self:SetEnabled(on)
        -- On attenue le FOND, pas le cadre entier. Avant, 0.35 sur le libelle
        -- et 0.6 sur le bouton se multipliaient : le texte tombait a 0.21
        -- d'opacite, illisible. Ici le remplissage s'efface, le libelle reste
        -- lisible, et le bouton se lit quand meme comme indisponible.
        local fill = on and 1 or 0.4
        self.bgLeft:SetAlpha(fill)
        self.bgMid:SetAlpha(fill)
        self.bgRight:SetAlpha(fill)
        self.label:SetAlpha(on and 1 or 0.8)
        if self.icon then self.icon:SetAlpha(on and 1 or 0.8) end
        self:SetAlpha(1)
    end
    -- Largeur mini passée en paramètre, jamais fixe au-delà : la traduction
    -- la plus longue (souvent le français ou l'allemand) doit rester
    -- entièrement lisible, quelle que soit la langue active. Les autres
    -- éléments de la barre d'action sont ancrés les uns aux autres (RIGHT
    -- de l'un = LEFT de l'autre), donc tout se redécale automatiquement
    -- quand un bouton change de largeur.
    -- Icône + texte gardés comme un GROUPE centré, l'icône toujours à
    -- gauche du texte avec un espace fixe : aucun chevauchement possible,
    -- quelle que soit la largeur du bouton ou la langue active.
    function b:SetText(newText)
        self.label:SetText(newText or "")
        local textW = self.label:GetStringWidth()
        local iconW = self.icon and 14 or 0
        local gap = self.icon and 6 or 0
        self:SetWidth(math.max(self.minWidth, textW + iconW + gap + 28))
        self.label:ClearAllPoints()
        if self.icon then
            self.label:SetPoint("CENTER", (iconW + gap) / 2, 0)
            self.icon:ClearAllPoints()
            self.icon:SetPoint("RIGHT", self.label, "LEFT", -gap, 0)
        else
            self.label:SetPoint("CENTER")
        end
    end
    b:SetText(text)
    return b
end

-- Un seul menu ouvert à la fois, tous widgets confondus (Dropdown,
-- SpellPicker, TargetPicker) : sans ça, ouvrir le menu Raid puis cliquer
-- sur Boss sans fermer le premier laissait les deux menus ouverts en même
-- temps, superposés l'un sur l'autre.
local activePickerMenu = nil

-- Champ déroulant compact (source, saison).
local function Dropdown(parent, root, w, withIcon)
    local d = CreateFrame("Button", nil, parent, "BackdropTemplate")
    d:SetSize(w, CTRL_SIZE)
    d.bgLeft = d:CreateTexture(nil, "BACKGROUND")
    d.bgLeft:SetSize(16, CTRL_SIZE)
    d.bgLeft:SetPoint("TOPLEFT", 0, 0)
    d.bgLeft:SetPoint("BOTTOMLEFT", 0, 0)
    d.bgLeft:SetTexture(MEDIA .. "UI\\btn_left")
    d.bgRight = d:CreateTexture(nil, "BACKGROUND")
    d.bgRight:SetSize(16, CTRL_SIZE)
    d.bgRight:SetPoint("TOPRIGHT", 0, 0)
    d.bgRight:SetPoint("BOTTOMRIGHT", 0, 0)
    d.bgRight:SetTexture(MEDIA .. "UI\\btn_right")
    d.bgMid = d:CreateTexture(nil, "BACKGROUND")
    d.bgMid:SetPoint("TOPLEFT", d.bgLeft, "TOPRIGHT", 0, 0)
    d.bgMid:SetPoint("BOTTOMRIGHT", d.bgRight, "BOTTOMLEFT", 0, 0)
    d.bgMid:SetTexture(MEDIA .. "UI\\btn_mid")

    if withIcon then
        d.icon = d:CreateTexture(nil, "OVERLAY")
        d.icon:SetSize(15, 15)
        d.icon:SetPoint("LEFT", 6, 0)
    end

    d.text = Typeset(d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), "text")
    d.text:SetPoint("LEFT", withIcon and d.icon or d, withIcon and "RIGHT" or "LEFT", withIcon and 6 or 9, 0)
    -- Volontairement PAS d'ancrage a droite : avec deux ancrages opposes, la
    -- largeur du texte est imposee par le cadre et SetWidth est ignore, donc
    -- AutoSize ne pourrait plus mesurer le libelle ni ajuster quoi que ce soit.
    d.text:SetJustifyH("LEFT")
    Tint(d.text, { 1, 1, 1 })

    d.arrow = d:CreateTexture(nil, "OVERLAY")
    d.arrow:SetSize(12, 12)
    d.arrow:SetPoint("RIGHT", -5, 0)
    d.arrow:SetTexture(MEDIA .. "UI\\chevron")
    d.arrow:SetVertexColor(P.textDim[1], P.textDim[2], P.textDim[3], 1)

    -- Ajuste le champ a son libelle, en largeur d'abord puis en hauteur.
    --
    -- Les libelles n'ont pas la meme longueur d'une langue a l'autre :
    -- "Automatic (client language)" tient sur une ligne, sa traduction
    -- francaise en occupe trois. A largeur fixe, le texte passait a la ligne
    -- et debordait d'un cadre reste haut de 26 px.
    --
    -- On elargit donc jusqu'a autoMax ; si le libelle ne tient toujours pas,
    -- on le laisse revenir a la ligne et c'est le CADRE qui grandit.
    d.autoMin, d.autoMax = w, math.floor(w * 2.2)
    function d:AutoSize()
        local textLeft = self.icon and 27 or 9   -- 6 + 15 (icone) + 6
        local textRight = 18                     -- place de la fleche
        self.text:SetWidth(0)
        self.text:SetWordWrap(false)
        local needed = textLeft + math.ceil(self.text:GetStringWidth()) + textRight
        if needed <= self.autoMax then
            self:SetWidth(math.max(self.autoMin, needed))
            self:SetHeight(CTRL_SIZE)
        elseif self.truncate then
            -- Champ d'une seule ligne (en-tete de la note) : au-dela de
            -- autoMax, le libelle est coupe par "..." DANS le bouton, et le
            -- nom complet s'affiche au survol. Il ne deborde jamais.
            self:SetWidth(self.autoMax)
            self.text:SetWidth(self.autoMax - textLeft - textRight)
            self:SetHeight(CTRL_SIZE)
        else
            self:SetWidth(self.autoMax)
            self.text:SetWordWrap(true)
            self.text:SetWidth(self.autoMax - textLeft - textRight)
            self:SetHeight(math.max(CTRL_SIZE, math.ceil(self.text:GetStringHeight()) + 10))
        end
        self.cut = self.truncate and needed > self.autoMax
        if self.menu then
            self.menu:SetWidth(math.max(self:GetWidth(), self.menuNeed or 0))
        end
    end

    -- Voile cyan en fondu au survol, comme les boutons de NSRT — plus de
    -- changement de couleur de bordure.
    d.hoverBg = CreateFrame("Frame", nil, d)
    d.hoverBg:SetPoint("TOPLEFT", 3, -3)
    d.hoverBg:SetPoint("BOTTOMRIGHT", -3, 3)
    d.hoverBg:EnableMouse(false)
    d.hoverBg.tex = d.hoverBg:CreateTexture(nil, "ARTWORK")
    d.hoverBg.tex:SetAllPoints()
    d.hoverBg.tex:SetColorTexture(P.hoverLift[1], P.hoverLift[2], P.hoverLift[3], P.hoverLift[4])
    d.hoverBg:SetAlpha(0)

    -- Menu ouvert = champ selectionne : meme lisere bleu que partout
    -- ailleurs. Branche sur OnShow/OnHide du menu plutot que sur le clic,
    -- pour suivre AUSSI les fermetures qu'on ne declenche pas nous-memes
    -- (ouverture d'un autre menu, clic en dehors, Echap).
    d.ring = SelectionRing(d, 1, P.accent)

    d.menu = CreateFrame("Frame", nil, root, "BackdropTemplate")
    d.menu:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -3)
    d.menu:SetWidth(w)
    d.menu:SetFrameStrata("TOOLTIP")
    d.menu:SetClampedToScreen(true)
    RoundedBox(d.menu, "BACKGROUND", P.pop, P.border, MENU_R)
    d.menu:Hide()
    d.menu.buttons = {}
    d.menu:HookScript("OnShow", function() d.ring:Show() end)
    d.menu:HookScript("OnHide", function() d.ring:Hide() end)

    d.baseOnEnter = function(self)
        UIFrameFadeIn(self.hoverBg, 0.12, self.hoverBg:GetAlpha(), 1)
        if self.cut then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(self.text:GetText() or "", 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end
    d.baseOnLeave = function(self)
        UIFrameFadeOut(self.hoverBg, 0.20, self.hoverBg:GetAlpha(), 0)
        if self.cut and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end
    d:SetScript("OnEnter", d.baseOnEnter)
    d:SetScript("OnLeave", d.baseOnLeave)
    d:SetScript("OnClick", function(self)
        if self.menu:IsShown() then
            self.menu:Hide()
            activePickerMenu = nil
        else
            if activePickerMenu and activePickerMenu ~= self.menu then
                activePickerMenu:Hide()
            end
            self.menu:Show()
            activePickerMenu = self.menu
        end
    end)

    function d:SetItems(items)
        for _, b in ipairs(self.menu.buttons) do b:Hide() end
        local step = CTRL_SIZE
        for i, item in ipairs(items) do
            local b = self.menu.buttons[i]
            if not b then
                b = CreateFrame("Button", nil, self.menu)
                b:SetHeight(step)
                -- Element selectionne : aplat bleu plein a coins arrondis.
                -- Opaque et non translucide, pour que le libelle blanc garde
                -- son contraste (5,07 sur #2870bd, soit le niveau AA ; a 55 %
                -- d'alpha sur le fond du menu il tombait sous le seuil).
                b.sel = RoundedFill(b, "BACKGROUND", P.accentSolid)
                b.icon = b:CreateTexture(nil, "OVERLAY")
                b.icon:SetSize(14, 14)
                b.icon:SetPoint("LEFT", 6, 0)
                b.text = Typeset(b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), "text")
                b.text:SetPoint("LEFT", 26, 0)
                b.text:SetPoint("RIGHT", -8, 0)
                b.text:SetJustifyH("LEFT")
                -- Une ligne par element : un libelle trop long finit par
                -- "..." dans sa ligne au lieu de deborder sur la suivante.
                b.text:SetWordWrap(false)
                -- Survol arrondi lui aussi : pose sur la couche HIGHLIGHT,
                -- ou le client montre et cache seul TOUTES les pieces.
                -- Carre, il aurait depasse aux angles de la ligne selectionnee.
                RoundedFill(b, "HIGHLIGHT", P.menuHover):SetShown(true)
                self.menu.buttons[i] = b
            end
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 3, -3 - (i - 1) * step)
            b:SetPoint("TOPRIGHT", -3, -3 - (i - 1) * step)
            ReText(b.text, item.text)
            b.sel:SetShown(item.selected)
            Tint(b.text, { 1, 1, 1 })
            if item.icon then
                b.icon:SetTexture(item.icon)
                -- `iconColor` sert aux pastilles unies (swatch.tga, blanche et
                -- teintee a l'execution). Sans couleur, on remet du blanc :
                -- la teinte precedente resterait sinon collee a la ligne,
                -- qui est recyclee d'un menu a l'autre.
                TintTex(b.icon, item.iconColor or { 1, 1, 1 })
                b.icon:Show()
            else
                b.icon:Hide()
            end
            b.text:SetPoint("LEFT", item.icon and 26 or 9, 0)
            b:SetScript("OnClick", function() self.menu:Hide(); item.onClick() end)
            b:Show()
        end
        self.menu:SetHeight(math.max(6, 6 + #items * step))
        -- Le menu s'elargit pour montrer les libelles en entier (jusqu'a
        -- autoMax), sans jamais etre plus etroit que le bouton ; au-dela,
        -- chaque ligne se coupe par "...".
        local widest = 0
        for i = 1, #items do
            local t = self.menu.buttons[i].text
            local tw = t.GetUnboundedStringWidth and t:GetUnboundedStringWidth()
                or t:GetStringWidth()
            widest = math.max(widest, math.ceil(tw))
        end
        self.menuNeed = math.min(widest + 26 + 8 + 6, self.autoMax)
        self.menu:SetWidth(math.max(self:GetWidth(), self.menuNeed))
    end

    return d
end

-- Comme Dropdown, mais avec un champ de recherche qui filtre la liste au
-- fur et à mesure — nécessaire ici car la base de sorts (voir
-- EP.GetKnownSpells) peut être bien plus grande que la liste des spés :
-- tout afficher d'un coup serait imbuvable, donc on ne montre jamais
-- plus de MAX_RESULTS correspondances à la fois.

local function SpellPicker(parent, root, w)
    local MAX_RESULTS = 10
    local ROW_H = CTRL_SIZE

    local d = CreateFrame("Button", nil, parent, "BackdropTemplate")
    d:SetSize(w, CTRL_SIZE)
    d.bgLeft = d:CreateTexture(nil, "BACKGROUND")
    d.bgLeft:SetSize(16, CTRL_SIZE)
    d.bgLeft:SetPoint("TOPLEFT", 0, 0)
    d.bgLeft:SetPoint("BOTTOMLEFT", 0, 0)
    d.bgLeft:SetTexture(MEDIA .. "UI\\btn_left")
    d.bgRight = d:CreateTexture(nil, "BACKGROUND")
    d.bgRight:SetSize(16, CTRL_SIZE)
    d.bgRight:SetPoint("TOPRIGHT", 0, 0)
    d.bgRight:SetPoint("BOTTOMRIGHT", 0, 0)
    d.bgRight:SetTexture(MEDIA .. "UI\\btn_right")
    d.bgMid = d:CreateTexture(nil, "BACKGROUND")
    d.bgMid:SetPoint("TOPLEFT", d.bgLeft, "TOPRIGHT", 0, 0)
    d.bgMid:SetPoint("BOTTOMRIGHT", d.bgRight, "BOTTOMLEFT", 0, 0)
    d.bgMid:SetTexture(MEDIA .. "UI\\btn_mid")

    d.icon = d:CreateTexture(nil, "OVERLAY")
    d.icon:SetSize(15, 15)
    d.icon:SetPoint("LEFT", 6, 0)

    d.text = Typeset(d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), "text")
    d.text:SetPoint("LEFT", d.icon, "RIGHT", 6, 0)
    d.text:SetJustifyH("LEFT")
    d.text:SetWordWrap(false)
    Tint(d.text, { 1, 1, 1 })

    -- Le cadre suit le libelle, sur UNE ligne. Borne haute pour qu'un nom
    -- interminable ne pousse pas la colonne des noms hors de la fenetre : au
    -- dela, le texte est tronque et l'infobulle le donne en entier.
    d.autoMin, d.autoMax = w, math.floor(w * 1.9)
    d.padLeft, d.padRight, d.menuMin = 27, 18, 230

    -- Largeur qu'il FAUDRAIT a ce cadre pour montrer son libelle en entier.
    -- La liste s'en sert pour aligner toute une colonne sur le plus long.
    function d:NeededWidth()
        return self.padLeft + math.ceil(self.text:GetStringWidth()) + self.padRight
    end

    -- Largeur IMPOSEE, bornee comme AutoSize. Au-dela de autoMax le libelle
    -- est tronque plutot que de pousser la colonne hors de la fenetre.
    function d:SetColumnWidth(width)
        width = math.max(self.autoMin, math.min(self.autoMax, width))
        self:SetWidth(width)
        self.text:SetWidth(width - self.padLeft - self.padRight)
        if self.menu then self.menu:SetWidth(math.max(width, self.menuMin)) end
    end

    -- Hors liste (un cadre isole), chacun se suffit a lui-meme.
    function d:AutoSize() self:SetColumnWidth(self:NeededWidth()) end

    d.arrow = d:CreateTexture(nil, "OVERLAY")
    d.arrow:SetSize(12, 12)
    d.arrow:SetPoint("RIGHT", -5, 0)
    d.arrow:SetTexture(MEDIA .. "UI\\chevron")
    d.arrow:SetVertexColor(P.textDim[1], P.textDim[2], P.textDim[3], 1)

    d.hoverBg = CreateFrame("Frame", nil, d)
    d.hoverBg:SetPoint("TOPLEFT", 3, -3)
    d.hoverBg:SetPoint("BOTTOMRIGHT", -3, 3)
    d.hoverBg:EnableMouse(false)
    d.hoverBg.tex = d.hoverBg:CreateTexture(nil, "ARTWORK")
    d.hoverBg.tex:SetAllPoints()
    d.hoverBg.tex:SetColorTexture(P.hoverLift[1], P.hoverLift[2], P.hoverLift[3], P.hoverLift[4])
    d.hoverBg:SetAlpha(0)

    -- Menu ouvert = champ selectionne (voir Dropdown).
    d.ring = SelectionRing(d, 1, P.accent)

    local menuW = math.max(w, 230)
    d.menu = CreateFrame("Frame", nil, root, "BackdropTemplate")
    d.menu:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -3)
    d.menu:SetWidth(menuW)
    d.menu:SetFrameStrata("TOOLTIP")
    d.menu:SetClampedToScreen(true)
    RoundedBox(d.menu, "BACKGROUND", P.pop, P.border, MENU_R)
    d.menu:Hide()
    d.menu.buttons = {}
    d.allItems = {}
    d.menu:HookScript("OnShow", function() d.ring:Show() end)
    d.menu:HookScript("OnHide", function() d.ring:Hide() end)

    d.menu.search = CreateFrame("EditBox", nil, d.menu, "InputBoxTemplate")
    d.menu.search:SetSize(menuW - 20, 20)
    d.menu.search:SetPoint("TOP", 0, -8)
    d.menu.search:SetAutoFocus(false)
    d.menu.search:SetFontObject("GameFontHighlightSmall")
    StyleSearchBox(d.menu.search)

    local function RenderMatches(query)
        query = (query or ""):lower()
        local matches = {}
        for _, item in ipairs(d.allItems) do
            if query == "" or item.text:lower():find(query, 1, true) then
                table.insert(matches, item)
                if #matches >= MAX_RESULTS then break end
            end
        end
        for _, b in ipairs(d.menu.buttons) do b:Hide() end
        for i, item in ipairs(matches) do
            local b = d.menu.buttons[i]
            if not b then
                b = CreateFrame("Button", nil, d.menu)
                b:SetHeight(ROW_H)
                b.icon = b:CreateTexture(nil, "OVERLAY")
                b.icon:SetSize(14, 14)
                b.icon:SetPoint("LEFT", 6, 0)
                b.text = Typeset(b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), "text")
                b.text:SetPoint("LEFT", 24, 0)
                b.text:SetPoint("RIGHT", -6, 0)
                b.text:SetJustifyH("LEFT")
                Tint(b.text, { 1, 1, 1 })
                -- Survol arrondi lui aussi : pose sur la couche HIGHLIGHT,
                -- ou le client montre et cache seul TOUTES les pieces.
                -- Carre, il aurait depasse aux angles de la ligne selectionnee.
                RoundedFill(b, "HIGHLIGHT", P.menuHover):SetShown(true)
                d.menu.buttons[i] = b
            end
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 3, -34 - (i - 1) * ROW_H)
            b:SetPoint("TOPRIGHT", -3, -34 - (i - 1) * ROW_H)
            ReText(b.text, item.text)
            if item.icon then b.icon:SetTexture(item.icon) end
            b:SetScript("OnClick", function()
                d.menu:Hide()
                if d.onSelect then d.onSelect(item) end
            end)
            b:Show()
        end
        d.menu:SetHeight(34 + math.max(#matches, 1) * ROW_H + 6)
    end

    d.menu.search:SetScript("OnTextChanged", function(self) RenderMatches(self:GetText()) end)
    d.menu.search:SetScript("OnEscapePressed", function(self) self:ClearFocus(); d.menu:Hide() end)

    d.baseOnEnter = function(self) UIFrameFadeIn(self.hoverBg, 0.12, self.hoverBg:GetAlpha(), 1) end
    d.baseOnLeave = function(self) UIFrameFadeOut(self.hoverBg, 0.20, self.hoverBg:GetAlpha(), 0) end
    d:SetScript("OnEnter", d.baseOnEnter)
    d:SetScript("OnLeave", d.baseOnLeave)
    d:SetScript("OnClick", function(self)
        if self.menu:IsShown() then
            self.menu:Hide()
            activePickerMenu = nil
        else
            if activePickerMenu and activePickerMenu ~= self.menu then
                activePickerMenu:Hide()
            end
            self.menu.search:SetText("")
            RenderMatches("")
            self.menu:Show()
            self.menu.search:SetFocus()
            activePickerMenu = self.menu
        end
    end)

    function d:SetSourceItems(items)
        self.allItems = items
    end

    return d
end

-- Comme SpellPicker, mais pour choisir QUI reçoit l'alerte d'un rappel :
-- soit toute une spé (réglage par défaut, "Reset"), soit un joueur précis
-- du raid actuel — utile quand deux joueurs partagent la même spé et
-- qu'un seul doit vraiment agir. La liste vient du groupe en jeu
-- (EP.GetRaidRosterOptions), jamais mémorisée : elle change avec la
-- composition du raid.
local function TargetPicker(parent, root, w)
    local MAX_RESULTS = 10
    local ROW_H = CTRL_SIZE

    local d = CreateFrame("Button", nil, parent, "BackdropTemplate")
    d:SetSize(w, CTRL_SIZE)
    d.bgLeft = d:CreateTexture(nil, "BACKGROUND")
    d.bgLeft:SetSize(16, CTRL_SIZE)
    d.bgLeft:SetPoint("TOPLEFT", 0, 0)
    d.bgLeft:SetPoint("BOTTOMLEFT", 0, 0)
    d.bgLeft:SetTexture(MEDIA .. "UI\\btn_left")
    d.bgRight = d:CreateTexture(nil, "BACKGROUND")
    d.bgRight:SetSize(16, CTRL_SIZE)
    d.bgRight:SetPoint("TOPRIGHT", 0, 0)
    d.bgRight:SetPoint("BOTTOMRIGHT", 0, 0)
    d.bgRight:SetTexture(MEDIA .. "UI\\btn_right")
    d.bgMid = d:CreateTexture(nil, "BACKGROUND")
    d.bgMid:SetPoint("TOPLEFT", d.bgLeft, "TOPRIGHT", 0, 0)
    d.bgMid:SetPoint("BOTTOMRIGHT", d.bgRight, "BOTTOMLEFT", 0, 0)
    d.bgMid:SetTexture(MEDIA .. "UI\\btn_mid")

    d.text = Typeset(d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), "text")
    d.text:SetPoint("LEFT", 8, 0)
    d.text:SetJustifyH("LEFT")
    d.text:SetWordWrap(false)
    Tint(d.text, { 1, 1, 1 })

    d.autoMin, d.autoMax = w, math.floor(w * 1.9)
    d.padLeft, d.padRight, d.menuMin = 8, 18, 200

    function d:NeededWidth()
        return self.padLeft + math.ceil(self.text:GetStringWidth()) + self.padRight
    end

    function d:SetColumnWidth(width)
        width = math.max(self.autoMin, math.min(self.autoMax, width))
        self:SetWidth(width)
        self.text:SetWidth(width - self.padLeft - self.padRight)
        if self.menu then self.menu:SetWidth(math.max(width, self.menuMin)) end
    end

    function d:AutoSize() self:SetColumnWidth(self:NeededWidth()) end

    d.arrow = d:CreateTexture(nil, "OVERLAY")
    d.arrow:SetSize(12, 12)
    d.arrow:SetPoint("RIGHT", -5, 0)
    d.arrow:SetTexture(MEDIA .. "UI\\chevron")
    d.arrow:SetVertexColor(P.textDim[1], P.textDim[2], P.textDim[3], 1)

    d.hoverBg = CreateFrame("Frame", nil, d)
    d.hoverBg:SetPoint("TOPLEFT", 3, -3)
    d.hoverBg:SetPoint("BOTTOMRIGHT", -3, 3)
    d.hoverBg:EnableMouse(false)
    d.hoverBg.tex = d.hoverBg:CreateTexture(nil, "ARTWORK")
    d.hoverBg.tex:SetAllPoints()
    d.hoverBg.tex:SetColorTexture(P.hoverLift[1], P.hoverLift[2], P.hoverLift[3], P.hoverLift[4])
    d.hoverBg:SetAlpha(0)

    -- Menu ouvert = champ selectionne (voir Dropdown).
    d.ring = SelectionRing(d, 1, P.accent)

    local menuW = math.max(w, 200)
    d.menu = CreateFrame("Frame", nil, root, "BackdropTemplate")
    d.menu:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -3)
    d.menu:SetWidth(menuW)
    d.menu:SetFrameStrata("TOOLTIP")
    d.menu:SetClampedToScreen(true)
    RoundedBox(d.menu, "BACKGROUND", P.pop, P.border, MENU_R)
    d.menu:Hide()
    d.menu.buttons = {}
    d.rosterItems = {}
    d.resetItem = nil
    d.menu:HookScript("OnShow", function() d.ring:Show() end)
    d.menu:HookScript("OnHide", function() d.ring:Hide() end)

    d.menu.search = CreateFrame("EditBox", nil, d.menu, "InputBoxTemplate")
    d.menu.search:SetSize(menuW - 20, 20)
    d.menu.search:SetPoint("TOP", 0, -8)
    d.menu.search:SetAutoFocus(false)
    d.menu.search:SetFontObject("GameFontHighlightSmall")
    StyleSearchBox(d.menu.search)

    d.menu.empty = Typeset(d.menu:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"), "hint")
    d.menu.empty:SetPoint("TOP", d.menu.search, "BOTTOM", 0, -10)
    d.menu.empty:SetPoint("LEFT", 8, 0)
    d.menu.empty:SetPoint("RIGHT", -8, 0)
    d.menu.empty:SetJustifyH("CENTER")
    d.menu.empty:SetWordWrap(true)
    d.menu.empty:Hide()

    local function GetRow(i)
        local b = d.menu.buttons[i]
        if not b then
            b = CreateFrame("Button", nil, d.menu)
            b:SetHeight(ROW_H)
            b.text = Typeset(b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), "text")
            b.text:SetPoint("LEFT", 8, 0)
            b.text:SetPoint("RIGHT", -6, 0)
            b.text:SetJustifyH("LEFT")
            RoundedFill(b, "HIGHLIGHT", P.menuHover):SetShown(true)
            d.menu.buttons[i] = b
        end
        return b
    end

    local function RenderMatches(rawQuery)
        rawQuery = rawQuery or ""
        local trimmed = rawQuery:match("^%s*(.-)%s*$")
        local query = trimmed:lower()
        local rows = {}
        if d.resetItem and (query == "" or d.resetItem.text:lower():find(query, 1, true)) then
            table.insert(rows, d.resetItem)
        end
        -- Saisie manuelle : utile hors raid, ou pour un joueur non listé
        -- (hors ligne, autre groupe...). Proposée dès qu'un texte est tapé
        -- et ne correspond exactement à personne du roster.
        local exactMatch = false
        for _, item in ipairs(d.rosterItems) do
            if item.value and item.value:lower() == query then exactMatch = true end
        end
        if trimmed ~= "" and not exactMatch then
            table.insert(rows, {
                text = trimmed,
                value = trimmed,
                display = (L["Use \"%s\""]):format(trimmed),
                isManual = true,
            })
        end
        for _, item in ipairs(d.rosterItems) do
            if query == "" or item.text:lower():find(query, 1, true) then
                table.insert(rows, item)
                if #rows >= MAX_RESULTS then break end
            end
        end
        for _, b in ipairs(d.menu.buttons) do b:Hide() end
        if #d.rosterItems == 0 then
            d.menu.empty:SetText(L["Not in a raid group — join one to pick from the roster, or type a name manually below."])
            d.menu.empty:Show()
        else
            d.menu.empty:Hide()
        end
        local top = d.menu.empty:IsShown() and 60 or 34
        for i, item in ipairs(rows) do
            local b = GetRow(i)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 3, -(top + (i - 1) * ROW_H))
            b:SetPoint("TOPRIGHT", -3, -(top + (i - 1) * ROW_H))
            ReText(b.text, item.display or item.text)
            b:SetScript("OnClick", function()
                d.menu:Hide()
                activePickerMenu = nil
                if d.onSelect then d.onSelect(item) end
            end)
            b:Show()
        end
        local extra = d.menu.empty:IsShown() and 34 or 0
        d.menu:SetHeight(34 + extra + math.max(#rows, 1) * ROW_H + 6)
    end

    d.menu.search:SetScript("OnTextChanged", function(self) RenderMatches(self:GetText()) end)
    d.menu.search:SetScript("OnEscapePressed", function(self) self:ClearFocus(); d.menu:Hide() end)
    d.menu.search:SetScript("OnEnterPressed", function(self)
        local trimmed = self:GetText():match("^%s*(.-)%s*$")
        if trimmed == "" then return end
        d.menu:Hide()
        activePickerMenu = nil
        self:ClearFocus()
        if d.onSelect then d.onSelect({ text = trimmed, value = trimmed, isManual = true }) end
    end)

    d.baseOnEnter = function(self) UIFrameFadeIn(self.hoverBg, 0.12, self.hoverBg:GetAlpha(), 1) end
    d.baseOnLeave = function(self) UIFrameFadeOut(self.hoverBg, 0.20, self.hoverBg:GetAlpha(), 0) end
    d:SetScript("OnEnter", d.baseOnEnter)
    d:SetScript("OnLeave", d.baseOnLeave)
    d:SetScript("OnClick", function(self)
        if self.menu:IsShown() then
            self.menu:Hide()
            activePickerMenu = nil
        else
            if activePickerMenu and activePickerMenu ~= self.menu then
                activePickerMenu:Hide()
            end
            self.rosterItems = {}
            for _, m in ipairs(EP.GetRaidRosterOptions()) do
                local color = m.colorHex and ("|c" .. m.colorHex) or ""
                local suffix = color ~= "" and "|r" or ""
                table.insert(self.rosterItems, { text = m.name, value = m.name, display = color .. m.name .. suffix })
            end
            self.menu.search:SetText("")
            RenderMatches("")
            self.menu:Show()
            self.menu.search:SetFocus()
            activePickerMenu = self.menu
        end
    end)

    -- resetItem.text est utilisé pour la recherche/l'affichage ; resetItem
    -- lui-même est renvoyé tel quel à onSelect quand on le choisit.
    function d:SetResetItem(item)
        self.resetItem = item
    end

    return d
end

local function Badge(parent)
    local b = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    b:SetHeight(18)
    b.text = Typeset(b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), "chip")
    b.text:SetPoint("CENTER", 0, 0)
    -- Une pastille arrondie, construite une fois et recoloree a chaque Set :
    -- un badge prend la teinte de ce qu'il annonce (vert pour un nombre,
    -- orange pour le mythique...), d'ou SetColor plutot qu'un jeu d'images
    -- par couleur.
    b.fill, b.edge = RoundedBox(b, "BACKGROUND", P.panel, P.border, CTRL_R)
    function b:Set(text, color)
        local c = color or P.textDim
        local bg = { c[1] * 0.16, c[2] * 0.16, c[3] * 0.16, 1 }
        self.text:SetText(text)
        Tint(self.text, Readable(c, bg))
        self.fill:SetColor(bg)
        self.edge:SetColor({ c[1] * 0.5, c[2] * 0.5, c[3] * 0.5, 1 })
        self:SetWidth(self.text:GetStringWidth() + 16)
        self:Show()
    end
    return b
end

--[[ Colonne à liste ---------------------------------------------------------]]

--[[ Divers ------------------------------------------------------------------]]

local function GetSeasons()
    local found, list = {}, {}
    for _, raid in ipairs(EP.GetRaid()) do
        local s = raid.season or 0
        if not found[s] then found[s] = true; table.insert(list, s) end
    end
    table.sort(list, function(a, b) return a > b end)
    return list
end

local function ActiveSourceId()
    for _, id in ipairs(EP.SourceOrder or {}) do
        if EP.IsSourceEnabled(id) then return id end
    end
end

local function EntrySourceLabel(entry)
    local def = entry and entry.sourceId and EP.Sources[entry.sourceId]
    return def and def.label or (entry and entry.sourceId) or "?"
end

-- Teinte de la source d'une entree : celle qu'elle declare, sinon la table
-- ci-dessus, sinon le gris neutre.
local function SourceColor(entry)
    local id = entry and entry.sourceId
    local def = id and EP.Sources[id]
    return (def and def.color) or (id and SOURCE_COLORS[id]) or P.source
end

-- Bornes de la piste, en secondes absolues depuis le debut du combat.
-- Depuis 8.3.0 tous les `time` manipules par l'interface sont absolus : le
-- decoupage en phases NSRT n'a lieu qu'a l'ecriture de la note
-- (EP.SplitPhase), donc plus rien ici n'a besoin de connaitre les phases.
local function TimeBounds(reminders)
    local lo, hi
    for _, r in ipairs(reminders or {}) do
        local t = r.time or 0
        if not lo or t < lo then lo = t end
        if not hi or t > hi then hi = t end
    end
    return lo or 0, hi or 0
end

-- EP.GetKnownSpells() renvoie des entrées {spellID=, name=, icon=} ;
-- SpellPicker (comme Dropdown) attend {text=, icon=, ...}. Sans cette
-- adaptation, chaque ligne s'affichait avec une icône mais sans aucun nom
-- (item.text valait nil). Mémorisé : la liste source ne change pas en
-- cours de session.
local knownSpellItemsCache
local function GetKnownSpellItems()
    if knownSpellItemsCache then return knownSpellItemsCache end
    local list = {}
    for _, s in ipairs(EP.GetKnownSpells()) do
        table.insert(list, { text = s.name, icon = s.icon, spellID = s.spellID })
    end
    knownSpellItemsCache = list
    return list
end

-- Affichage du nom d'une spé pour le libellé par défaut du sélecteur de
-- cible (pas de liste à maintenir : appel direct à l'API native).
local function GetSpecDisplay(specID)
    local _, name = GetSpecializationInfoByID(specID)
    return name or ("#" .. tostring(specID))
end

--[[ Fenêtre principale -------------------------------------------------------]]

local function CreateMainWindow()
    -- Couleur d'accent fixe de la charte graphique : la même pour tout le
    -- monde, quelle que soit la classe. (Auparavant dérivée de
    -- RAID_CLASS_COLORS — retiré à la demande : l'accent doit correspondre
    -- à la maquette, pas varier d'un joueur à l'autre.) Bleu clair depuis la
    -- 9.0.0 : c'est l'accent de premier plan de la palette (aFg), lisible sur
    -- les fonds sombres là où le cyan pur vibrait.

    local f = CreateFrame("Frame", "NSRTAutoRemindersMainWindow", UIParent, "BackdropTemplate")
    local db = DB()
    -- Taille memorisee, bornee : en dessous de WIN.minW la colonne de
    -- gauche et le panneau de details ne tiennent plus cote a cote, au-dessus
    -- de WIN.maxW la fenetre deborde des ecrans courants.
    f:SetSize(math.min(math.max(tonumber(db.width) or WIN.w, WIN.minW), WIN.maxW),
              math.min(math.max(tonumber(db.height) or WIN.h, WIN.minH), WIN.maxH))
    db.scale = ClampScale(db.scale)
    f:SetScale(db.scale)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint(1)
        local d = DB(); d.point, d.relPoint, d.x, d.y = point, relPoint, x, y
    end)

    -- Redimensionnement. SetResizeBounds remplace l'ancien couple
    -- SetMinResize/SetMaxResize, retire par Blizzard : on garde un repli pour
    -- les clients qui n'ont que l'ancienne API.
    f:SetResizable(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(WIN.minW, WIN.minH, WIN.maxW, WIN.maxH)
    elseif f.SetMinResize then
        f:SetMinResize(WIN.minW, WIN.minH)
        f:SetMaxResize(WIN.maxW, WIN.maxH)
    end

    f.sizer = CreateFrame("Button", nil, f)
    f.sizer:SetSize(16, 16)
    f.sizer:SetPoint("BOTTOMRIGHT", -3, 3)
    f.sizer:EnableMouse(true)
    f.sizer:RegisterForDrag("LeftButton")
    f.sizer.tex = f.sizer:CreateTexture(nil, "OVERLAY")
    f.sizer.tex:SetAllPoints()
    f.sizer.tex:SetTexture(MEDIA .. "UI\\sizer")
    TintTex(f.sizer.tex, P.textFaint)
    f.sizer:SetScript("OnEnter", function(self) TintTex(self.tex, P.accent) end)
    f.sizer:SetScript("OnLeave", function(self) TintTex(self.tex, P.textFaint) end)
    f.sizer:SetScript("OnDragStart", function()
        f:StartSizing("BOTTOMRIGHT")
    end)
    f.sizer:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local d = DB()
        d.width, d.height = math.floor(f:GetWidth() + 0.5), math.floor(f:GetHeight() + 0.5)
        -- La fenetre a bouge son ancrage pendant le redimensionnement.
        local point, _, relPoint, x, y = f:GetPoint(1)
        d.point, d.relPoint, d.x, d.y = point, relPoint, x, y
        if f.UpdateColumnLayout then f:UpdateColumnLayout() end
        if f.Refresh then f:Refresh() end
    end)
    -- Pendant le glissement, la disposition suit en direct : sans ca les
    -- colonnes ne se recalculaient qu'au relachement et la fenetre paraissait
    -- cassee tout le temps du redimensionnement.
    f:SetScript("OnSizeChanged", function(self)
        if self.UpdateColumnLayout then self:UpdateColumnLayout() end
    end)
    Tooltip(f.sizer, "Drag to resize the window.")
    RoundedBox(f, "BACKGROUND", P.bg, P.border, WINDOW_R)
    if db.point then
        f:ClearAllPoints()
        f:SetPoint(db.point, UIParent, db.relPoint or db.point, db.x or 0, db.y or 0)
    end

    if UISpecialFrames then
        local registered = false
        for _, name in ipairs(UISpecialFrames) do if name == f:GetName() then registered = true break end end
        if not registered then table.insert(UISpecialFrames, f:GetName()) end
    end

    ------------------------------------------------------------------ en-tête
    f.header = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.header:SetPoint("TOPLEFT", 1, -1)
    f.header:SetPoint("TOPRIGHT", -1, -1)
    f.header:SetHeight(HEADER_H)
    Backdrop(f.header, P.bar, { 0, 0, 0, 0 })
    f.headerLine = f.header:CreateTexture(nil, "OVERLAY")
    f.headerLine:SetPoint("BOTTOMLEFT", 0, 0)
    f.headerLine:SetPoint("BOTTOMRIGHT", 0, 0)
    f.headerLine:SetHeight(1)
    f.headerLine:SetColorTexture(unpack(P.border))

    -- Pas de tuile de marque : le nom suffit a dire quelle fenetre c'est, et
    -- l'icone de l'addon reste celle de la liste du client (icon.tga, via le
    -- .toc). Media/UI/logo.tga n'a plus d'emploi et a ete retire.
    f.title = Typeset(f.header:CreateFontString(nil, "OVERLAY", "GameFontNormal"), "brand")
    f.title:SetPoint("LEFT", PAD, 0)
    -- Nom de marque a l'accent de la palette, et non au cyan #00ffff herite
    -- de NSRT : c'etait la derniere couleur en dehors de l'echelle.
    f.title:SetText("AutoReminders")
    Tint(f.title, P.accent)

    f.version = Typeset(f.header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"), "hint")
    f.version:SetPoint("LEFT", f.title, "RIGHT", 8, -1)
    f.version:SetText("v" .. (EP.GetVersion and EP.GetVersion() or "?") .. "   |   By Abraa")
    Tint(f.version, P.textFaint)

    f.close = CreateFrame("Button", nil, f.header, "UIPanelCloseButton")
    f.close:SetSize(13, 13)
    f.close:SetPoint("RIGHT", -6, 0)
    f.close:SetScript("OnClick", function() f:Hide() end)

    -- En haut à droite, comme le sélecteur "Langue:" de NSRT lui-même.
    f.language = Dropdown(f.header, f, 140, true)
    f.language.icon:SetTexture(MEDIA .. "UI\\globe")
    TintTex(f.language.icon, P.accent)
    f.language:SetPoint("RIGHT", f.close, "LEFT", -14, 0)

    -- Curseur d'échelle, centré dans le bandeau du haut.
    f.scaleControl = CreateFrame("Frame", nil, f.header)
    f.scaleControl:SetSize(220, HEADER_H)
    f.scaleControl:SetPoint("CENTER", f.header, "CENTER", 0, 0)

    f.scaleLabel = Typeset(f.scaleControl:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"), "hint")
    f.scaleLabel:SetPoint("LEFT", 0, 0)
    f.scaleLabel:SetText(L["Scale:"])
    Tint(f.scaleLabel, P.textDim)

    f.scaleSlider = CreateFrame("Slider", nil, f.scaleControl, "BackdropTemplate")
    f.scaleSlider:SetOrientation("HORIZONTAL")
    f.scaleSlider:SetMinMaxValues(MIN_SCALE_TICK, MAX_SCALE_TICK)
    f.scaleSlider:SetValueStep(1)
    if f.scaleSlider.SetObeyStepOnDrag then f.scaleSlider:SetObeyStepOnDrag(true) end
    -- Le cadre reste haut de 12 pour que la pastille ait de quoi vivre ; la
    -- piste, elle, ne fait que 4 px et se dessine au centre.
    f.scaleSlider:SetSize(120, 12)
    f.scaleSlider:SetPoint("LEFT", f.scaleLabel, "RIGHT", 9, 0)

    -- Le rail se pose en textures SUR le curseur, et non dans un cadre
    -- enfant : un enfant vit a un niveau superieur, donc son rail passait
    -- par-dessus la pastille et la barrait en deux.
    -- Cadre de 12 px, rail de 4 : un retrait vertical de 4 le centre.
    RoundedFill(f.scaleSlider, "BACKGROUND", P.borderSoft, 2, { 0, 4 }):SetShown(true)

    f.scaleSlider:SetThumbTexture(MEDIA .. "UI\\thumb")
    local thumb = f.scaleSlider:GetThumbTexture()
    thumb:SetSize(26, 12)
    TintTex(thumb, P.thumb)

    f.scaleValue = Typeset(f.scaleControl:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), "time")
    f.scaleValue:SetPoint("LEFT", f.scaleSlider, "RIGHT", 10, 0)
    f.scaleValue:SetWidth(36)
    f.scaleValue:SetJustifyH("RIGHT")
    Tint(f.scaleValue, P.textDim)

    -- Même logique que le curseur d'échelle de NSRT lui-même : on retarde
    -- l'application de SetScale tant que le bouton de la souris est
    -- maintenu, car changer l'échelle pendant le glisser modifie le
    -- système de coordonnées sous le curseur et peut le faire sauter à
    -- une extrémité.
    local function ApplyScaleTick(slider, tick)
        tick = math.floor((tonumber(tick) or 0) + 0.5)
        tick = math.max(MIN_SCALE_TICK, math.min(MAX_SCALE_TICK, tick))
        if math.abs((slider:GetValue() or tick) - tick) > 0.001 then
            slider:SetValue(tick)
            return
        end
        local value = TickToScale(tick)
        f.scaleValue:SetText(("%.2f"):format(value))
        slider.pendingTick = tick
    end
    local function CommitScale(slider)
        local tick = slider.pendingTick
        if tick == nil then tick = math.floor((tonumber(slider:GetValue()) or 0) + 0.5) end
        local value = TickToScale(tick)
        DB().scale = value
        f:SetScale(value)
        slider.pendingTick = nil
    end
    f.scaleSlider:SetScript("OnMouseDown", function(slider)
        slider.isInteracting = true
        TintTex(slider:GetThumbTexture(), P.thumbDown)
    end)
    f.scaleSlider:SetScript("OnMouseUp", function(slider)
        TintTex(slider:GetThumbTexture(), P.thumb)
        slider.isInteracting = false
        ApplyScaleTick(slider, slider:GetValue())
        CommitScale(slider)
    end)
    f.scaleSlider:SetScript("OnValueChanged", function(slider, tick)
        ApplyScaleTick(slider, tick)
        if not slider.isInteracting
            and not (IsMouseButtonDown and IsMouseButtonDown("LeftButton")) then
            CommitScale(slider)
        end
    end)
    f.scaleSlider:SetValue(ScaleToTick(db.scale))
    f.scaleSlider:EnableMouseWheel(true)
    f.scaleSlider:SetScript("OnMouseWheel", function(slider, delta)
        local tick = math.floor((tonumber(slider:GetValue()) or 0) + 0.5)
        slider:SetValue(math.max(MIN_SCALE_TICK, math.min(MAX_SCALE_TICK, tick + (delta > 0 and 1 or -1))))
    end)
    Tooltip(f.scaleSlider, "Adjust window scale")

    -------------------------------------------------------------- contrôles
    f.controls = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.controls:SetPoint("TOPLEFT", f.header, "BOTTOMLEFT", 0, 0)
    f.controls:SetPoint("TOPRIGHT", f.header, "BOTTOMRIGHT", 0, 0)
    f.controls:SetHeight(CTRL_H)
    Backdrop(f.controls, P.bar, { 0, 0, 0, 0 })
    f.controlsLine = f.controls:CreateTexture(nil, "OVERLAY")
    f.controlsLine:SetPoint("BOTTOMLEFT", 0, 0)
    f.controlsLine:SetPoint("BOTTOMRIGHT", 0, 0)
    f.controlsLine:SetHeight(1)
    f.controlsLine:SetColorTexture(unpack(P.border))

    -- Coche maison plutot que UICheckButtonTemplate : celui de Blizzard
    -- arrive avec son cadre et sa coche doree, hors de la palette. On garde
    -- le CheckButton pour la mecanique du clic et on repeint tout.
    f.enabled = CreateFrame("CheckButton", nil, f.controls)
    f.enabled:SetSize(16, 16)
    f.enabled:SetPoint("LEFT", PAD, 0)
    f.enabled.mark = f.enabled:CreateTexture(nil, "OVERLAY")
    f.enabled.mark:SetAllPoints()
    f.enabled.mark:SetTexture(MEDIA .. "UI\\check")
    f.enabled:SetScript("OnClick", function(btn)
        EP.SetEnabled(btn:GetChecked() and true or false)
    end)

    f.enabledText = Typeset(f.controls:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), "text")
    f.enabledText:SetPoint("LEFT", f.enabled, "RIGHT", 6, 0)
    f.enabledText:SetText(L["Enabled"])

    -- Vert quand c'est actif, gris sinon : l'etat se lit sans avoir a
    -- comparer deux coches.
    function f.enabled:Paint()
        local on = self:GetChecked() and true or false
        local c = on and P.success or P.textFaint
        TintTex(self.mark, c)
        self.mark:SetAlpha(on and 1 or 0.55)
        Tint(f.enabledText, c)
    end

    -- Separateur vertical, comme sur la maquette : il detache l'interrupteur
    -- des deux selecteurs, qui eux vont ensemble.
    f.controlsSep = f.controls:CreateTexture(nil, "ARTWORK")
    f.controlsSep:SetSize(1, 20)
    f.controlsSep:SetPoint("LEFT", f.enabledText, "RIGHT", 14, 0)
    f.controlsSep:SetColorTexture(unpack(P.borderSoft))

    f.source = Dropdown(f.controls, f, 170, true)
    f.source:SetPoint("LEFT", f.controlsSep, "RIGHT", 14, 0)
    -- Pastille de couleur a la place du logo de la source : c'est la meme
    -- teinte que sa pastille dans l'en-tete de boss, donc l'oeil fait le
    -- lien. Un logo de 15 px, lui, n'etait lisible pour personne.
    f.source.icon:SetTexture(MEDIA .. "UI\\swatch")
    f.source.icon:SetSize(14, 14)

    f.season = Dropdown(f.controls, f, 150, false)
    f.season:SetPoint("LEFT", f.source, "RIGHT", 8, 0)

    f.dataDate = Typeset(f.controls:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"), "hint")
    f.dataDate:SetPoint("RIGHT", -PAD, 0)
    f.dataDate:SetJustifyH("RIGHT")
    Tint(f.dataDate, P.textFaint)

    ---------------------------------------------------------------- alertes
    f.notice = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.notice:SetPoint("TOPLEFT", f.controls, "BOTTOMLEFT", 0, 0)
    f.notice:SetPoint("TOPRIGHT", f.controls, "BOTTOMRIGHT", 0, 0)
    f.notice:SetHeight(1)
    RoundedBox(f.notice, "BACKGROUND", { 0.140, 0.100, 0.050, 1 }, nil, FIELD_R)
    f.notice:Hide()
    f.notice.text = Typeset(f.notice:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), "text")
    f.notice.text:SetPoint("LEFT", PAD, 0)
    f.notice.text:SetPoint("RIGHT", -PAD, 0)
    f.notice.text:SetJustifyH("LEFT")
    Tint(f.notice.text, P.warning)

    function f:SetNotice(text)
        if text and text ~= "" then
            self.notice.text:SetText(text)
            self.notice:SetHeight(22)
            self.notice:Show()
        else
            self.notice:SetHeight(1)
            self.notice:Hide()
        end
        self:UpdateColumnLayout()
    end

    ---------------------------------------------------------------- colonnes
    f.anchor = CreateFrame("Frame", nil, f)
    f.anchor:SetPoint("TOPLEFT", f.controls, "BOTTOMLEFT", 0, 0)
    f.anchor:SetPoint("TOPRIGHT", f.controls, "BOTTOMRIGHT", 0, 0)
    f.anchor:SetHeight(1)

    -- Colonne de gauche : un arbre raid -> boss, et non deux listes
    -- deroulantes empilees. Les deux selecteurs cachaient le contenu du raid
    -- derriere un clic, alors que la liste des boss tient largement dans la
    -- colonne et dit d'un coup d'oeil ou en est chacun.
    f.tree = CreateFrame("Frame", nil, f, "BackdropTemplate")
    RoundedBox(f.tree, "BACKGROUND", P.bar, P.borderSoft, CARD_R)

    f.tree.caption = Typeset(f.tree:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"), "hint")
    f.tree.caption:SetPoint("TOPLEFT", 14, -12)
    f.tree.caption:SetText(L["RAIDS"])
    Tint(f.tree.caption, P.textDim)

    f.tree.scroll = CreateFrame("ScrollFrame", nil, f.tree, "UIPanelScrollFrameTemplate")
    f.tree.scroll:SetPoint("TOPLEFT", f.tree.caption, "BOTTOMLEFT", -6, -8)
    f.tree.scroll:SetPoint("BOTTOMRIGHT", -22, 8)
    f.tree.content = CreateFrame("Frame", nil, f.tree.scroll)
    f.tree.content:SetSize(1, 1)
    f.tree.scroll:SetScrollChild(f.tree.content)
    f.tree.rows = {}

    -- Une rangee sert indifferemment a un raid ou a un boss : meme hauteur,
    -- memes pieces, seuls le retrait et ce qu'on montre changent.
    function f.tree:Row(i)
        local r = self.rows[i]
        if r then return r end
        r = CreateFrame("Button", nil, self.content)
        r:SetHeight(CTRL_SIZE)
        r.hover = RoundedFill(r, "BACKGROUND", P.hoverLift, CTRL_R)
        r.fill = RoundedFill(r, "BACKGROUND", P.selected, CTRL_R)
        r.ring = SelectionRing(r, 1, P.accent)
        r.twist = r:CreateTexture(nil, "OVERLAY")
        r.twist:SetSize(10, 10)
        r.twist:SetPoint("LEFT", 8, 0)
        r.twist:SetTexture(MEDIA .. "UI\\chevron")
        r.icon = r:CreateTexture(nil, "OVERLAY")
        r.icon:SetSize(16, 16)
        r.label = Typeset(r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), "text")
        r.label:SetJustifyH("LEFT")
        r.label:SetWordWrap(false)
        r.pill = Typeset(r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"), "hint")
        r.pill:SetPoint("RIGHT", -10, 0)
        r.baseOnEnter = function(self) self.hover:SetShown(true) end
        r.baseOnLeave = function(self) self.hover:SetShown(false) end
        r:SetScript("OnEnter", r.baseOnEnter)
        r:SetScript("OnLeave", r.baseOnLeave)
        self.rows[i] = r
        return r
    end

    -- Remplit l'arbre a partir d'une liste a plat deja ordonnee : chaque
    -- entree dit si c'est un raid ou un boss, et l'affichage en decoule.
    function f.tree:Fill(entries)
        for _, r in ipairs(self.rows) do r:Hide() end
        local y = 0
        for i, e in ipairs(entries) do
            local r = self:Row(i)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, -y)
            r:SetPoint("RIGHT", 0, 0)

            r.twist:SetShown(e.kind == "raid")
            if e.kind == "raid" then
                -- Le chevron pointe vers le bas par defaut ; un quart de tour
                -- dans le sens trigonometrique le met a droite.
                r.twist:SetRotation(e.open and 0 or (math.pi / 2))
                TintTex(r.twist, e.open and P.accent or P.textDim)
            end

            r.icon:ClearAllPoints()
            r.icon:SetPoint("LEFT", e.kind == "raid" and 24 or 30, 0)
            if e.apply then
                e.apply(r.icon)
                -- Un boss sans timeline reste visible mais s'efface, au lieu
                -- de disparaitre de la liste : on sait qu'il existe.
                if e.dim then r.icon:SetDesaturated(true) end
            end

            r.label:ClearAllPoints()
            r.label:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
            r.label:SetPoint("RIGHT", r.pill, "LEFT", -8, 0)
            ReText(r.label, e.label)
            Tint(r.label, e.selected and { 1, 1, 1 } or (e.dim and P.textFaint or P.text))

            r.pill:SetText(e.pill or "")
            Tint(r.pill, e.pillColor or P.textFaint)

            if e.tip then
                Tooltip(r, e.tip)
            else
                r:SetScript("OnEnter", r.baseOnEnter)
                r:SetScript("OnLeave", r.baseOnLeave)
            end
            r.fill:SetShown(e.selected and e.kind == "boss")
            r.ring:SetShown(e.selected and e.kind == "raid")
            r:SetScript("OnClick", e.onClick)
            r:Show()
            y = y + CTRL_SIZE + 2
        end
        self.content:SetHeight(math.max(y, 1))
        self.content:SetWidth(math.max(self.scroll:GetWidth(), 1))
    end

    f.details = CreateFrame("Frame", nil, f, "BackdropTemplate")
    -- Fond explicite a la couleur de page. Le panneau etait transparent et
    -- laissait les coins arrondis de ses cartes reveler ce qui se trouvait
    -- dessous, donc dependre de la pile de la fenetre. Avec cet aplat, un
    -- angle de carte decouvre toujours exactement la meme teinte.
    Backdrop(f.details, P.bg, { 0, 0, 0, 0 })

    -- En-tete de boss : le bandeau devient le FOND d'une carte compacte, au
    -- lieu d'une bande decorative de 160 px qui ne portait aucune information
    -- et repoussait la liste d'autant. Tout ce qui identifie la timeline —
    -- nom, difficulte, spe, source, nombre de rappels, variante choisie —
    -- tient desormais dans ces 84 px.
    f.details.head = CreateFrame("Frame", nil, f.details, "BackdropTemplate")
    f.details.head:SetPoint("TOPLEFT", 0, 0)
    f.details.head:SetPoint("TOPRIGHT", 0, 0)
    f.details.head:SetHeight(DETAILS_HEAD_H)

    -- Une carte ordinaire, comme celle de la liste et celle de l'arbre.
    --
    -- Elle etait auparavant composee a la main en cinq couches — disque de
    -- bordure, image, voile, deux decoupes — parce que le bandeau large
    -- devait aller jusqu'au bord arrondi. Ce bandeau n'existe plus, et cet
    -- empilement laissait voir sa couche de bordure sur une quinzaine de
    -- pixels tout autour de la carte. RoundedBox fait le meme travail en une
    -- ligne, et c'est le chemin deja eprouve partout ailleurs.
    RoundedBox(f.details.head, "BACKGROUND", P.panel, P.borderSoft, CARD_R)

    -- Vignette du boss, meme traitement que la tuile de marque.
    f.details.portrait = CreateFrame("Frame", nil, f.details.head)
    f.details.portrait:SetSize(52, 52)
    f.details.portrait:SetPoint("LEFT", 14, 0)
    RoundedBox(f.details.portrait, "BACKGROUND", P.field, P.border, 8)
    f.details.portraitTex = f.details.portrait:CreateTexture(nil, "ARTWORK")
    f.details.portraitTex:SetPoint("TOPLEFT", 1, -1)
    f.details.portraitTex:SetPoint("BOTTOMRIGHT", -1, 1)
    -- La vignette est une image carree : on lui redecoupe les angles a la
    -- couleur de la carte qui la porte.
    RoundedClip(f.details.portrait, "ARTWORK", P.panel, 8, 0, 1)

    f.details.title = Typeset(f.details.head:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"), "bossTitle")
    f.details.title:SetPoint("TOPLEFT", f.details.portrait, "TOPRIGHT", 14, -2)
    f.details.title:SetJustifyH("LEFT")
    Tint(f.details.title, { 1, 1, 1 })

    f.details.badges = {}
    for i = 1, 4 do
        local b = Badge(f.details.head)
        if i == 1 then b:SetPoint("TOPLEFT", f.details.title, "BOTTOMLEFT", 0, -7)
        else b:SetPoint("LEFT", f.details.badges[i - 1], "RIGHT", 6, 0) end
        b:Hide()
        f.details.badges[i] = b
    end

    -- Choix de la variante : a droite de l'en-tete, sans libelle "TIMELINE" —
    -- l'icone d'horloge le dit, et la rangee y gagne une ligne.
    f.timelineSelect = Dropdown(f.details.head, f, 260, true)
    f.timelineSelect.icon:SetTexture(MEDIA .. "UI\\clock")
    TintTex(f.timelineSelect.icon, P.accent)
    f.timelineSelect:SetPoint("RIGHT", -14, 0)
    f.timelineSelect.truncate = true
    f.timelineSelect.autoMax = 380

    -- Barre d'outils : les actions qui portent sur la liste, pas sur la note.
    f.details.toolbar = CreateFrame("Frame", nil, f.details)
    f.details.toolbar:SetPoint("TOPLEFT", f.details.head, "BOTTOMLEFT", 0, -GAP.cardBody)
    f.details.toolbar:SetPoint("TOPRIGHT", f.details.head, "BOTTOMRIGHT", 0, -GAP.cardBody)
    f.details.toolbar:SetHeight(CTRL_SIZE)
    -- La rangee se replie quand elle n'a rien a montrer : sur une note
    -- WoW Timeline le bouton « Ajouter un rappel » est cache, et 30 px de vide
    -- restaient sous le bandeau.
    function f.details.toolbar:Reflow()
        self:SetHeight((self.addLine and self.addLine:IsShown()) and CTRL_SIZE or 1)
    end

    f.addLineButton = Button(f.details.toolbar, L["Add reminder"], 150, CTRL_SIZE, false, MEDIA .. "UI\\plus")
    f.addLineButton:SetPoint("LEFT", 0, 0)
    f.addLineButton:Hide()
    f.details.toolbar.addLine = f.addLineButton
    f.details.toolbar:Reflow()
    f.addLineButton:SetScript("OnClick", function()
        if not (f.selectedBoss and f.selectedEntry) then return end
        local modKey = EP.GetModKeyForSelection(f.selectedBoss, f.selectedEntry)
        if not modKey then return end
        EP.AddCustomLine(modKey, EP.GetCurrentSpecID())
        f:Refresh()
    end)

    f.details.track = CreateFrame("Frame", nil, f.details, "BackdropTemplate")
    f.details.track:SetPoint("TOPLEFT", f.details.toolbar, "BOTTOMLEFT", 0, 0)
    f.details.track:SetPoint("RIGHT", f.details.toolbar, "RIGHT", 0, 0)
    f.details.track:SetHeight(1)
    f.details.track:Hide()
    RoundedBox(f.details.track, "BACKGROUND", P.field, P.border, FIELD_R)
    f.details.track.marks = {}
    f.details.track.pre = f.details.track:CreateTexture(nil, "BACKGROUND")
    f.details.track.pre:SetPoint("TOPLEFT", 1, -1)
    f.details.track.pre:SetPoint("BOTTOMLEFT", 1, 1)
    f.details.track.pre:SetColorTexture(0.16, 0.16, 0.16, 1)
    f.details.track.pre:Hide()

    f.details.trackStart = Typeset(f.details:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"), "hint")
    f.details.trackStart:SetPoint("TOPLEFT", f.details.track, "BOTTOMLEFT", 1, -3)
    f.details.trackStart:Hide()
    Tint(f.details.trackStart, P.textFaint)
    f.details.trackEnd = Typeset(f.details:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"), "hint")
    f.details.trackEnd:SetPoint("TOPRIGHT", f.details.track, "BOTTOMRIGHT", -1, -3)
    f.details.trackEnd:Hide()
    Tint(f.details.trackEnd, P.textFaint)

    -- DEUX CARTES DISTINCTES. La timeline a la sienne, avec son propre
    -- defilement vertical : elle ne partage plus la zone de la liste. Sur une
    -- note Viserio elle est masquee, et la liste reprend toute la hauteur.
    f.details.timeCard = CreateFrame("Frame", nil, f.details, "BackdropTemplate")
    f.details.timeCard:SetPoint("TOPLEFT", f.details.toolbar, "BOTTOMLEFT", 0, -GAP.cardBody)
    f.details.timeCard:SetPoint("RIGHT", f.details, "RIGHT", 0, 0)
    f.details.timeCard:SetHeight(1)
    RoundedBox(f.details.timeCard, "BACKGROUND", P.panel, P.borderSoft, CARD_R)
    f.details.timeScroll = CreateFrame("ScrollFrame", nil, f.details.timeCard,
        "UIPanelScrollFrameTemplate")
    f.details.timeScroll:SetFrameLevel(f.details.timeCard:GetFrameLevel() + 1)
    f.details.timeScroll:SetPoint("TOPLEFT", 6, -6)
    f.details.timeScroll:SetPoint("BOTTOMRIGHT", -22, 6)
    f.details.timeContent = CreateFrame("Frame", nil, f.details.timeScroll)
    f.details.timeContent:SetSize(1, 1)
    f.details.timeScroll:SetScrollChild(f.details.timeContent)
    f.details.timeCard:Hide()

    -- POIGNEE entre la timeline et « Mes rappels » : on la tire vers le bas
    -- pour agrandir la timeline, vers le haut pour agrandir la liste. Elle
    -- occupe exactement l'espace entre les deux cartes ; la liste etant
    -- ancree sous la timeline, elle suit d'elle-meme. Part de la hauteur
    -- enregistree dans DB().timelineSplit ; double-clic = partage d'origine.
    local split = CreateFrame("Button", nil, f.details)
    split:SetPoint("TOPLEFT", f.details.timeCard, "BOTTOMLEFT", 0, 0)
    split:SetPoint("TOPRIGHT", f.details.timeCard, "BOTTOMRIGHT", 0, 0)
    split:SetHeight(GAP.cardBody)
    split:RegisterForClicks("LeftButtonUp")
    split.grip = {}
    for k = 1, 3 do
        local g = split:CreateTexture(nil, "OVERLAY")
        g:SetSize(26, 1.5)
        g:SetPoint("CENTER", 0, (k - 2) * 3)
        g:SetColorTexture(P.textFaint[1], P.textFaint[2], P.textFaint[3], 0.9)
        split.grip[k] = g
    end
    local function PaintGrip(c)
        for _, g in ipairs(split.grip) do g:SetColorTexture(c[1], c[2], c[3], 0.95) end
    end
    split:SetScript("OnEnter", function(btn)
        PaintGrip(P.accent)
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        GameTooltip:SetText(L["Drag to resize the timeline and the list — double-click to reset."], 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    split:SetScript("OnLeave", function(btn)
        if not btn.dragging then PaintGrip(P.textFaint) end
        GameTooltip:Hide()
    end)
    split:SetScript("OnMouseDown", function(btn, button)
        if button ~= "LeftButton" then return end
        local _, cy = GetCursorPosition()
        btn.fromY = cy / (btn:GetEffectiveScale() or 1)
        btn.fromH = f.details.timeCard:GetHeight() or 0
        btn.dragging = true
        GameTooltip:Hide()
    end)
    split:SetScript("OnUpdate", function(btn)
        if not btn.dragging then return end
        local _, cy = GetCursorPosition()
        local y = cy / (btn:GetEffectiveScale() or 1)
        -- Vers le bas (y diminue) : la timeline grandit.
        local h = math.min(math.max(btn.fromH + (btn.fromY - y), btn.minH or 80),
            btn.maxH or 400)
        f.details.timeCard:SetHeight(h)
    end)
    split:SetScript("OnMouseUp", function(btn)
        if not btn.dragging then return end
        btn.dragging = nil
        PaintGrip(btn:IsMouseOver() and P.accent or P.textFaint)
        local total = f.details:GetHeight() or 0
        if total > 0 then
            DB().timelineSplit = (f.details.timeCard:GetHeight() or 0) / total
        end
        -- La liste repart en colonnes selon sa nouvelle hauteur.
        f:Refresh()
    end)
    split:SetScript("OnDoubleClick", function()
        DB().timelineSplit = nil
        f:Refresh()
    end)
    split:Hide()
    f.details.splitter = split

    f.details.scroll = CreateFrame("ScrollFrame", nil, f.details, "UIPanelScrollFrameTemplate")
    f.details.listCard = CreateFrame("Frame", nil, f.details, "BackdropTemplate")
    f.details.listCard:SetPoint("TOPLEFT", f.details.toolbar, "BOTTOMLEFT", 0, -GAP.cardBody)
    f.details.listCard:SetPoint("BOTTOMRIGHT", f.details, "BOTTOMRIGHT", 0, 0)
    RoundedBox(f.details.listCard, "BACKGROUND", P.panel, P.borderSoft, CARD_R)
    -- La carte est creee APRES le cadre de defilement, donc a un niveau
    -- superieur : sans ca son fond passerait devant la liste et la masquerait
    -- entierement. On remonte la liste d'un cran plutot que de descendre la
    -- carte, qui pourrait tomber sous le panneau.
    f.details.scroll:SetFrameLevel(f.details.listCard:GetFrameLevel() + 1)

    f.details.scroll:SetPoint("TOPLEFT", f.details.listCard, "TOPLEFT", 6, -6)
    f.details.scroll:SetPoint("BOTTOMRIGHT", f.details.listCard, "BOTTOMRIGHT", -22, 6)
    f.details.content = CreateFrame("Frame", nil, f.details.scroll)
    f.details.content:SetSize(1, 1)
    f.details.scroll:SetScrollChild(f.details.content)
    f.details.lines = {}
    f.details.lanes = {}
    f.details.blocks = {}

    f.details.hint = Typeset(f.details:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"), "hint")
    f.details.hint:SetPoint("CENTER", f.details.listCard, "CENTER", 0, 0)
    Tint(f.details.hint, P.textFaint)
    f.details.hint:Hide()

    -------------------------------------------------------------- barre d'action
    f.actionBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.actionBar:SetPoint("BOTTOMLEFT", 1, 1)
    f.actionBar:SetPoint("BOTTOMRIGHT", -1, 1)
    f.actionBar:SetHeight(ACTION_H)
    Backdrop(f.actionBar, P.bar, { 0, 0, 0, 0 })
    f.actionLine = f.actionBar:CreateTexture(nil, "OVERLAY")
    f.actionLine:SetPoint("TOPLEFT", 0, 0)
    f.actionLine:SetPoint("TOPRIGHT", 0, 0)
    f.actionLine:SetHeight(1)
    f.actionLine:SetColorTexture(unpack(P.border))

    f.load = Button(f.actionBar, L["Send to Personal Notes"], 170, CTRL_SIZE, true, MEDIA .. "UI\\send")
    f.load:SetPoint("RIGHT", -PAD, 0)

    f.resetMods = Button(f.actionBar, L["Reset all"], 104, CTRL_SIZE, false, MEDIA .. "UI\\reset")
    f.resetMods:SetPoint("RIGHT", f.load, "LEFT", -14, 0)
    Tooltip(f.resetMods, "Clear every time/spec/spell change for this timeline.")
    f.resetMods:SetScript("OnClick", function()
        if not (f.selectedBoss and f.selectedEntry) then return end
        local key = EP.GetModKeyForSelection(f.selectedBoss, f.selectedEntry)
        if key then EP.ResetModifiers(key) end
        f:Refresh()
    end)

    f.removeNotes = Button(f.actionBar, L["Remove imported notes"], 190, CTRL_SIZE, false, MEDIA .. "UI\\trash")
    f.removeNotes:SetDanger()
    f.removeNotes:SetPoint("LEFT", PAD, 0)
    Tooltip(f.removeNotes, "Remove only notes created by AutoReminders from NSRT — both Personal Notes and Shared Notes.")

    -- Tag des rappels WoW Timeline : spe (defaut) ou nom du personnage.
    -- Un clic bascule ; la note change donc et se reimporte (« mise a jour
    -- disponible »). Masque sur Viserio, ou chaque ligne a deja sa cible.
    f.tagMode = Button(f.actionBar, "", 150, CTRL_SIZE, false)
    f.tagMode:SetPoint("RIGHT", f.resetMods, "LEFT", -14, 0)
    Tooltip(f.tagMode, "Tag of your reminders in the NSRT note. Specialization: the note works on every character of that spec. Character name: NSRT's timeline lists the reminders on your line, so you can edit them there — but the note only works for this character.")
    f.tagMode:SetScript("OnClick", function()
        EP.SetTagMode(EP.GetTagMode() == "name" and "spec" or "name")
        f:Refresh()
    end)

    f.status = Typeset(f.actionBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), "text")
    f.status:SetPoint("LEFT", f.removeNotes, "RIGHT", 16, 0)
    f.status:SetPoint("RIGHT", f.tagMode, "LEFT", -16, 0)
    f.status:SetJustifyH("LEFT")

    StaticPopupDialogs["NSRTAUTOREMINDERS_REMOVE_NOTES"] = {
        text = L["Remove every note created by AutoReminders from NSRT — both Personal Notes and Shared Notes?\n\nThis cannot be undone."],
        button1 = L["Remove"],
        button2 = L["Cancel"],
        OnAccept = function() EP.RemoveAllOwnNotes() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    f.removeNotes:SetScript("OnClick", function()
        if InCombatLockdown() then
            print("|cFF33CCFFAutoReminders|r: |cFFFFB347" .. L["Not available during combat."] .. "|r")
            return
        end
        StaticPopup_Show("NSRTAUTOREMINDERS_REMOVE_NOTES")
    end)

    -- Édition du temps d'un rappel précis (notes complètes Viserio
    -- uniquement) : nombre entier de secondes, négatif accepté
    -- (avant-pull). Rien n'est sauvegardé, comme pour le sort.
    local function ApplyTimeChange(popup)
        local data = popup.data
        local box = popup.EditBox or popup.editBox
        local text = box:GetText()
        local seconds = tonumber(text)
        if not seconds then
            print("|cFF33CCFFAutoReminders|r: |cFFFFB347" ..
                (L["Not a number: %s"]):format(text) .. "|r")
            return
        end
        local rounded = math.floor(seconds + 0.5)
        if data.isCustom then
            EP.SetCustomLineField(data.modKey, data.lineKey, "time", rounded)
        else
            EP.SetLineTime(data.modKey, data.lineKey, data.origTime, rounded)
        end
        if data.refresh then data.refresh() end
    end
    StaticPopupDialogs["NSRTAUTOREMINDERS_CHANGE_TIME"] = {
        text = L["Set the exact time (in seconds) for this reminder. Negative values are before the pull. This only affects the note you're about to create — nothing is saved."],
        button1 = L["Apply"],
        button2 = L["Cancel"],
        hasEditBox = true,
        OnShow = function(self)
            -- Le champ s'appelle EditBox (majuscule) dans les versions
            -- récentes du client, editBox (minuscule) dans les anciennes ;
            -- on gère les deux pour ne pas dépendre d'une version précise.
            local box = self.EditBox or self.editBox
            box:SetText(self.data and tostring(self.data.currentTime) or "")
            box:HighlightText()
        end,
        OnAccept = function(self) ApplyTimeChange(self) end,
        EditBoxOnEnterPressed = function(self)
            local popup = self:GetParent()
            ApplyTimeChange(popup)
            popup:Hide()
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }

    f.load:SetScript("OnClick", function()
        if not (f.selectedBoss and f.selectedEntryIndex) then return end
        if EP.IsFullRaidActive() then
            EP.ShareFullNote(f.selectedBoss, f.selectedEntryIndex)
        else
            EP.LoadVariant(f.selectedBoss, f.selectedEntryIndex)
        end
        f:Refresh()
    end)

    ---------------------------------------------------------------- layout
    function f:UpdateColumnLayout()
        local top = self.notice:IsShown() and self.notice or self.anchor
        local w1 = 240 -- colonne étroite fixe (raid + boss empilés) : le reste de la largeur va au panneau de détails.

        self.tree:ClearAllPoints()
        self.tree:SetPoint("TOPLEFT", top, "BOTTOMLEFT", PAD, -GAP.contentX)
        self.tree:SetPoint("BOTTOM", self.actionBar, "TOP", 0, GAP.contentX)
        self.tree:SetWidth(w1)

        self.details:ClearAllPoints()
        self.details:SetPoint("TOPLEFT", top, "BOTTOMLEFT", PAD + w1 + GAP.group, -GAP.contentX)
        self.details:SetPoint("BOTTOMRIGHT", self.actionBar, "TOPRIGHT", -GAP.contentX, GAP.contentX)

        -- Hauteur fixe (et non dépendante de la largeur de fenêtre) pour que
        -- la dimension d'image recommandée reste stable : voir
        -- GRAPHIC_CHARTER.md / Media/README.txt pour la taille exacte.
        self.details.head:SetHeight(DETAILS_HEAD_H)

        self.details.content:SetWidth(math.max(self.details.scroll:GetWidth(), 1))
        self.tree.content:SetWidth(math.max(self.tree.scroll:GetWidth(), 1))
    end

    f:SetScript("OnSizeChanged", function(self) self:UpdateColumnLayout() end)

    --[[ Rafraîchissements -----------------------------------------------]]

    function f:RefreshSource()
        local activeId = ActiveSourceId()
        local def = activeId and EP.Sources[activeId]
        self.source.text:SetText((def and def.label) or activeId or L["Select source"])
        if self.source.AutoSize then self.source:AutoSize() end
        TintTex(self.source.icon,
            (def and def.color) or (activeId and SOURCE_COLORS[activeId]) or P.source)
        local items = {}
        for _, id in ipairs(EP.SourceOrder or {}) do
            local d = EP.Sources[id]
            table.insert(items, {
                text = (d and d.label) or id,
                -- Meme pastille de couleur que sur le bouton ferme (voir
                -- f.source.icon) plutot que le logo de la source : a 14 px
                -- un logo n'est pas lisible, et la couleur est deja le
                -- repere utilise partout ailleurs pour designer la source.
                icon = MEDIA .. "UI\\swatch",
                iconColor = SourceColor({ sourceId = id }),
                selected = (id == activeId),
                onClick = function()
                    EP.SelectSource(id)
                    local s = SEL(); s.raidName, s.encID, s.entryIndex = nil, nil, nil
                    self:Refresh()
                end,
            })
        end
        self.source:SetItems(items)
    end

    function f:RefreshSeason()
        local seasons = GetSeasons()
        local selected = SEL().season
        local valid = false
        for _, s in ipairs(seasons) do if s == selected then valid = true end end
        if not valid then selected = EP.GetCurrentSeason(); SEL().season = selected end

        local current = EP.GetCurrentSeason()
        local function Label(s)
            if s == 0 then return L["Others"] end
            local t = (L["Season %d"]):format(s)
            if s == current then t = t .. " " .. L["(current)"] end
            return t
        end
        self.season.text:SetText(Label(selected))
        if self.season.AutoSize then self.season:AutoSize() end
        local items = {}
        for _, s in ipairs(seasons) do
            table.insert(items, {
                text = Label(s), selected = (s == selected),
                onClick = function()
                    local sel = SEL()
                    sel.season, sel.raidName, sel.encID, sel.entryIndex = s, nil, nil, nil
                    self:Refresh()
                end,
            })
        end
        self.season:SetItems(items)
    end

    function f:RefreshLanguage()
        local choice = EP.GetLanguageChoice()
        local function Label(c)
            if c.id == "Auto" then return (L["Automatic (client language)"]) end
            return c.label
        end
        for _, c in ipairs(EP.LanguageChoices) do
            if c.id == choice then
                self.language.text:SetText(Label(c))
                if self.language.AutoSize then self.language:AutoSize() end
            end
        end
        local items = {}
        for _, c in ipairs(EP.LanguageChoices) do
            table.insert(items, {
                text = Label(c),
                selected = (c.id == choice),
                onClick = function()
                    EP.SetLanguage(c.id)
                    self:Refresh()
                end,
            })
        end
        self.language:SetItems(items)
    end

    -- Certains libellés (boutons fixes, en-têtes...) n'étaient posés
    -- qu'une seule fois à la création de la fenêtre — changer de langue
    -- ensuite ne les touchait jamais. Tout reposer ici, appelé à chaque
    -- Refresh(), corrige ça pour de bon plutôt que de traquer chaque
    -- widget au cas par cas.
    function f:RefreshStaticText()
        self.scaleLabel:SetText(L["Scale:"])
        Tooltip(self.scaleSlider, "Adjust window scale")
        self.enabledText:SetText(L["Enabled"])
        self.addLineButton:SetText(L["Add reminder"])
        self.resetMods:SetText(L["Reset all"])
        Tooltip(self.resetMods, "Clear every time/spec/spell change for this timeline.")
        self.removeNotes:SetText(L["Remove imported notes"])
        self.tagMode:SetText(EP.GetTagMode() == "name" and L["Tag: character name"]
            or L["Tag: specialization"])
        Tooltip(self.removeNotes, "Remove only notes created by AutoReminders from NSRT — both Personal Notes and Shared Notes.")
    end

    function f:RefreshRaid()
        local specID = EP.GetCurrentSpecID()
        local fullRaid = EP.IsFullRaidActive()
        local list = {}
        for _, raid in ipairs(EP.GetRaid()) do
            if (raid.season or 0) == (SEL().season or EP.GetCurrentSeason()) then
                local count = 0
                for _, enc in ipairs(raid.encounters) do
                    local has = fullRaid and EP.GetFullNotesForBoss(enc) or EP.GetVariantsAll(enc, specID)
                    if has then count = count + 1 end
                end
                table.insert(list, { raid = raid, count = count, total = #raid.encounters })
            end
        end

        local selectedName = SEL().raidName
        local exists = false
        for _, item in ipairs(list) do if item.raid.name == selectedName then exists = true end end
        if not exists then
            selectedName = list[1] and list[1].raid.name or nil
            SEL().raidName = selectedName
        end

        -- Conserve pour l'arbre, qui est rempli une fois les deux niveaux
        -- connus (voir RefreshBoss, qui appelle FillTree).
        self.raidList = list
        self.selectedRaid = selectedName
    end

    -- Depliage : un etat par raid, garde dans les variables sauvegardees.
    -- A defaut, seul le raid selectionne s'ouvre — sinon la premiere
    -- ouverture deroulerait toute la saison d'un coup.
    function f:IsRaidOpen(name)
        local saved = DB().treeOpen
        if saved and saved[name] ~= nil then return saved[name] end
        return name == self.selectedRaid
    end

    function f:ToggleRaid(name)
        local db = DB()
        db.treeOpen = db.treeOpen or {}
        db.treeOpen[name] = not self:IsRaidOpen(name)
        self:RefreshBoss()
    end

    function f:RefreshBoss()
        local specID = EP.GetCurrentSpecID()
        local fullRaid = EP.IsFullRaidActive()
        local all = {}
        for _, raid in ipairs(EP.GetRaid()) do
            if raid.name == self.selectedRaid then
                for _, enc in ipairs(raid.encounters) do table.insert(all, enc) end
                break
            end
        end

        local selected = SEL().encID
        local exists = false
        for _, enc in ipairs(all) do if enc == selected then exists = true end end
        if not exists then selected = all[1]; SEL().encID = selected end

        -- Le meme calcul servait au seul raid selectionne ; il sert
        -- maintenant a chaque raid deplie.
        local function BossStates(encounters)
        local items = {}
        for _, enc in ipairs(encounters) do
            local statusText, statusColor
            local available = 0
            if fullRaid then
                local notes = EP.GetFullNotesForBoss(enc)
                available = notes and #notes or 0
                if not notes then
                    statusText, statusColor = L["No complete note for this boss"], P.textFaint
                else
                    statusText, statusColor = ("%d"):format(#notes), P.success
                end
            else
                local variants = EP.GetVariantsAll(enc, specID)
                available = variants and #variants or 0
                local hasTimeline = variants ~= nil
                local status = hasTimeline and EP.GetBossImportState(enc) or "none"
                if not hasTimeline then
                    statusText, statusColor = L["No timeline for current specialization"], P.textFaint
                elseif not EP.IsBossEnabled(enc) then
                    statusText, statusColor = L["Disabled for this boss"], P.textFaint
                elseif status == "up_to_date" then
                    statusText, statusColor = L["Up to date — ready for next pull"], P.success
                elseif status == "update" then
                    statusText, statusColor = L["Update available"], P.warning
                elseif status == "imported" then
                    statusText, statusColor = L["Imported — select for next pull"], P.info
                else
                    statusText, statusColor = L["Not imported"], P.textFaint
                end
            end
            table.insert(items, {
                enc = enc,
                status = statusText,
                color = statusColor,
                count = available,
                ready = statusColor ~= P.textFaint,
            })
        end
        return items
        end

        self.selectedBoss = selected

        -- L'arbre : chaque raid de la saison se deplie independamment, et
        -- plusieurs peuvent l'etre en meme temps. Cliquer un raid ouvre ou
        -- ferme SA branche sans rien selectionner ; c'est le clic sur un boss
        -- qui choisit, et qui amene la selection sur son raid au passage.
        local entries = {}
        for _, item in ipairs(self.raidList or {}) do
            local raid = item.raid
            local name = raid.name
            local open = self:IsRaidOpen(name)
            table.insert(entries, {
                kind = "raid", label = EP.GetRaidDisplayName(raid), open = open,
                selected = (name == self.selectedRaid),
                apply = function(tex) ApplyRaidTexture(tex, name) end,
                pill = ("%d/%d"):format(item.count, item.total),
                pillColor = item.count > 0 and P.success or P.textFaint,
                onClick = function() self:ToggleRaid(name) end,
            })
            if open then
                for _, b in ipairs(BossStates(raid.encounters)) do
                    table.insert(entries, {
                        kind = "boss", label = EP.GetEncounterDisplayName(b.enc),
                        selected = (name == self.selectedRaid and b.enc == selected),
                        dim = not b.ready,
                        apply = function(tex) ApplyBossTexture(tex, b.enc) end,
                        -- Le statut tient dans la couleur de la pastille ; la
                        -- phrase complete reste dans l'infobulle, pour ne rien
                        -- perdre de ce que disait l'ancienne liste.
                        pill = b.count > 0 and tostring(b.count) or "—",
                        pillColor = b.color,
                        tip = b.status,
                        onClick = function()
                            local st = SEL()
                            st.raidName, st.encID, st.entryIndex = name, b.enc, nil
                            self:Refresh()
                        end,
                    })
                end
            end
        end
        self.tree:Fill(entries)
    end

    local function LayoutTrack(track, reminders, lo, hi)
        for _, m in ipairs(track.marks) do m:Hide() end
        local width = math.max(track:GetWidth() - 2, 1)
        local span = math.max(hi - lo, 1)
        if lo < 0 then
            track.pre:SetWidth(math.max(width * (-lo) / span, 1))
            track.pre:Show()
        else
            track.pre:Hide()
        end
        for i, r in ipairs(reminders) do
            local m = track.marks[i]
            if not m then
                m = track:CreateTexture(nil, "OVERLAY")
                m:SetPoint("TOP", track, "TOPLEFT", 0, -3)
                m:SetSize(2, 16)
                track.marks[i] = m
            end
            local x = 1 + width * (((r.time or 0) - lo) / span)
            m:ClearAllPoints()
            m:SetPoint("TOP", track, "TOPLEFT", math.min(x, width), -3)
            m:SetColorTexture(P.accent[1], P.accent[2], P.accent[3], 0.9)
            m:Show()
        end
    end

    function f:RefreshDetails()
        local encID = self.selectedBoss
        local fullRaid = EP.IsFullRaidActive()
        local specID = EP.GetCurrentSpecID()
        local entries = encID and (fullRaid and EP.GetFullNotesForBoss(encID) or EP.GetVariantsAll(encID, specID)) or nil

        -- Important : on teste SEL().entryIndex (la valeur persistée, mise à
        -- jour par les clics de ligne) et non self.selectedEntryIndex (un
        -- champ mis en cache par l'appel précédent). Tester le champ en
        -- cache ici laissait le panneau vide après un changement de boss :
        -- l'ancien index restait "valide" pour le nouveau boss par
        -- coïncidence, empêchant la réinitialisation vers la 1re variante.
        local sel = SEL()
        if not sel.entryIndex or not (entries and entries[sel.entryIndex]) then
            sel.entryIndex = entries and entries[1] and 1 or nil
        end
        self.selectedEntryIndex = sel.entryIndex
        local entry = entries and self.selectedEntryIndex and entries[self.selectedEntryIndex]
        self.selectedEntry = entry

        -- Certaines timelines (Viserio) intègrent déjà "M "/"HC " en clair
        -- dans leur nom ; d'autres (WoW Timeline) ne l'ont pas. Dans les deux
        -- cas on retire un éventuel préfixe brut existant puis on remet un
        -- préfixe COLORÉ uniforme (mêmes couleurs que les badges :
        -- P.mythic/P.heroic), pour repérer la difficulté d'un coup
        -- d'œil dans le menu déroulant sans avoir à lire le nom en entier.
        local function ColoredDifficultyPrefix(difficulty)
            local isMythic = difficulty == "Mythic"
            local prefix = isMythic and "M" or "HC"
            return ColorText(prefix, isMythic and P.mythic or P.heroic)
        end

        local function StripRawPrefix(name, rawPrefix)
            if name:sub(1, #rawPrefix + 1) == (rawPrefix .. " ") then
                return name:sub(#rawPrefix + 2)
            end
            return name
        end

        local function DifficultyLabel(e)
            local rawPrefix = e.difficulty == "Mythic" and "M" or "HC"
            local name = StripRawPrefix(e.variant.name or "", rawPrefix)
            -- Nom genere en anglais par le script : traduit a l'affichage.
            local top = name:match("^Plan consensus %(top (%d+)%)$")
            if top then name = L["Consensus plan (top %d)"]:format(tonumber(top)) end
            name = ColoredDifficultyPrefix(e.difficulty) .. "  " .. name
            -- La durée vient du champ `duration` (généré par le script pour
            -- les données récentes) ou, à défaut, du dernier rappel de la
            -- timeline — ça reste compatible avec d'anciens fichiers de
            -- données générés avant l'ajout de ce champ.
            local duration = e.variant.duration
            if not duration then
                local _, hi = TimeBounds(e.variant.reminders)
                duration = hi
            end
            return name .. "  (" .. FormatTime(duration) .. ")"
        end

        -- Équivalent pour une note complète (toutes spés) : le nom de la
        -- note et sa durée totale, sans notion de spé du joueur.
        local function FullNoteLabel(e)
            local rawPrefix = e.note.difficulty == "Mythic" and "M" or "HC"
            local name = StripRawPrefix(e.note.name or "", rawPrefix)
            name = ColoredDifficultyPrefix(e.note.difficulty) .. "  " .. name
            return name .. "  (" .. FormatTime(e.note.duration or 0) .. ")"
        end

        local ItemLabel = fullRaid and FullNoteLabel or DifficultyLabel
        local items = {}
        if entries then
            for i, e in ipairs(entries) do
                table.insert(items, {
                    text = ItemLabel(e),
                    selected = (i == self.selectedEntryIndex),
                    onClick = function()
                        SEL().entryIndex = i
                        self:Refresh()
                    end,
                })
            end
        end
        self.timelineSelect:SetItems(items)
        ReText(self.timelineSelect.text, entry and ItemLabel(entry) or L["Select a timeline"])
        self.timelineSelect:AutoSize()

        if not entry then
            for _, b in ipairs(self.details.badges) do b:Hide() end
            self.details.portraitTex:SetTexture(nil)
            self.details.title:SetText("")
            self.details.trackStart:SetText("")
            self.details.trackEnd:SetText("")
            self.details.track:Hide()
            self.details.hint:SetText(encID and L["Select a timeline"] or L["Select a boss"])
            self.details.hint:Show()
            for _, line in ipairs(self.details.lines) do line:Hide() end
            if self.details.listHead then self.details.listHead:Hide() end
            if self.details.selBar then self.details.selBar:Hide() end
            for _, chip in ipairs(self.details.spellChips or {}) do chip:Hide() end
            self.details.content:SetHeight(1)
            self.status:SetText("")
            self.load:SetEnabledState(false)
            self.resetMods:Hide()
            self.tagMode:Hide()
            self.addLineButton:Hide()
            self.details.toolbar:Reflow()
            return
        end

        self.details.hint:Hide()

        ApplyBossTexture(self.details.portraitTex, encID)

        -- Normalise les deux modèles vers un jeu commun de variables avant
        -- le rendu (identique dans les deux cas à partir d'ici) : une note
        -- complète fusionne les rappels de toutes ses spés, triés par temps.
        -- Le temps affiché est déjà celui éventuellement modifié rappel
        -- par rappel (EP.GetLineTime), donc l'aperçu correspond exactement
        -- à ce qui sera importé/partagé.
        local modKey = EP.GetModKeyForSelection(encID, entry)
        local reminders, difficulty, titleText, authorText
        -- Duree REELLE du combat : la piste va jusqu'a la fin du pull, pas
        -- jusqu'au dernier rappel. `bounds` ne sert qu'a recoller les donnees
        -- WoW Timeline (stockees par phase) en temps absolu.
        local noteDuration, bounds
        if fullRaid then
            local note = entry.note
            titleText = note.name
            difficulty = note.difficulty
            authorText = note.author
            noteDuration = note.duration
            reminders = {}
            -- Une note Viserio peut contenir DEUX joueurs de la meme spe.
            -- On n'affiche (et on n'exporte) que celui qui est selectionne,
            -- sinon le joueur recevrait aussi le plan de son homologue.
            -- Une note Viserio peut contenir DEUX joueurs de la meme spe.
            -- On affiche les deux (une note de raid couvre tout le monde),
            -- mais chaque bloc devra recevoir un pseudo avant l'envoi.
            for specID, block in pairs(note.specs) do
                local actors = EP.SpecActors(block)
                local actorCount = #actors
                for actorIdx, actorCasts in ipairs(actors) do
                    for idx, r in ipairs(actorCasts) do
                        local lineKey = EP.LineKey(specID, idx, actorIdx)
                        if not EP.IsLineDeleted(modKey, lineKey) then
                            table.insert(reminders, {
                                -- Temps ABSOLU depuis le debut du combat : les
                                -- pages Viserio ne portent aucune phase.
                                time = EP.GetLineTime(modKey, lineKey, r.time),
                                spellid = r.spellid, bossSpell = r.bossSpell,
                                origSpecID = specID, lineKey = lineKey,
                                actorIndex = actorIdx, actorCount = actorCount,
                            })
                        end
                    end
                end
            end
            -- Rappels ajoutés à la main (voir bouton "+ Ajouter un
            -- rappel" plus bas) : mêmes contrôles que les autres lignes,
            -- mais temps/sort/cible stockés directement dessus (pas de
            -- valeur d'origine à écraser).
            for _, custom in ipairs(EP.GetCustomLines(modKey)) do
                if not EP.IsLineDeleted(modKey, custom.lineKey) then
                    table.insert(reminders, {
                        time = custom.time,
                        spellid = custom.spellid,
                        origSpecID = nil, lineKey = custom.lineKey, isCustom = true,
                    })
                end
            end
            -- Une seule piste continue, du debut a la fin du combat.
            table.sort(reminders, function(a, b)
                return (a.time or 0) < (b.time or 0)
            end)
        else
            titleText = entry.variant.name
            difficulty = entry.difficulty
            noteDuration = entry.variant.duration
            -- Bornes de phase DE CE pull : servent a recoller les temps
            -- relatifs stockes en une timeline absolue continue.
            bounds = EP.PhaseBoundaries(encID, difficulty, entry.variant)
            -- Même mécanisme que la branche Viserio ci-dessus (lineKey +
            -- EP.GetLineTime/IsLineDeleted). Seule différence : pas de
            -- notion de spé par ligne — une variante WoW Timeline est déjà
            -- mono-spé — donc pas de remap vers un joueur précis, qui n'a
            -- de sens que sur une note partagée au raid.
            reminders = {}
            for idx, r in ipairs(entry.variant.reminders or {}) do
                local lineKey = EP.LineKey("toplogs", idx)
                if not EP.IsLineDeleted(modKey, lineKey) then
                    table.insert(reminders, {
                        time = EP.GetLineTime(modKey, lineKey,
                            EP.JoinPhase(r.ph, r.time, bounds)),
                        spellid = r.spellid, bossSpell = r.bossSpell,
                        lineKey = lineKey,
                    })
                end
            end
            -- Rappels ajoutes a la main. Ils n'etaient rendus que dans la
            -- branche Viserio, et BuildNoteString ne les ecrivait pas : le
            -- bouton etait donc masque ici. Les deux sont corriges.
            for _, custom in ipairs(EP.GetCustomLines(modKey)) do
                if not EP.IsLineDeleted(modKey, custom.lineKey) then
                    table.insert(reminders, {
                        time = custom.time,
                        spellid = custom.spellid,
                        lineKey = custom.lineKey, isCustom = true,
                    })
                end
            end
            -- Une seule piste continue, du debut a la fin du combat.
            table.sort(reminders, function(a, b)
                return (a.time or 0) < (b.time or 0)
            end)
        end
        -- Deroulement du boss intercale dans la liste : voir a quelle capacite
        -- repond chaque rappel, et pouvoir placer le sien en face. Les lignes
        -- de boss sont purement indicatives — elles ne partent jamais dans la
        -- note envoyee a NSRT (voir BuildNoteString / BuildFullNoteString, qui
        -- n'iterent que sur les rappels).
        --
        -- SOURCES SPE-FILTREES UNIQUEMENT (WoW Timeline). Sur une note Viserio, le
        -- deroulement n'a rien a quoi se raccrocher : les rappels n'y portent
        -- pas de champ bossSpell (Viserio est du HTML scrape, pas un log), et
        -- on a decide de ne pas le deduire. Les lignes de boss n'y etaient
        -- donc qu'un deuxieme jeu de lignes melange au plan, sans lien avec
        -- lui — sur Nek'zali, 169 rappels auxquels s'ajoutaient les capacites.
        -- Le deroulement reste affiche sur WoW Timeline, ou il vient du meme log que
        -- les rappels et se lit donc avec eux.
        local bossRows = 0
        local lanes, laneView = {}, false
        -- Frise du boss : mesuree sur les top logs pour WoW Timeline, celle
        -- de Viserio (Data/Viserio/BossTimeline.lua) pour une note Viserio.
        local timeline
        if fullRaid then
            local byDiff = EP.ViserioBossTimeline and EP.ViserioBossTimeline[encID]
            timeline = byDiff and byDiff[difficulty]
            if timeline and #timeline == 0 then timeline = nil end
        else
            timeline = EP.GetBossTimeline and EP.GetBossTimeline(encID, difficulty)
        end
        if timeline and EP.ShowBossTimeline() then
            -- Borne : on ne montre pas des capacites au-dela de ce que dure
            -- la note, sinon la piste s'etire sur un combat plus long que le
            -- plan affiche.
            local cutoff = noteDuration or 0
            for _, r in ipairs(reminders) do
                if (r.time or 0) > cutoff then cutoff = r.time end
            end
            -- Une meme capacite porte parfois PLUSIEURS identifiants de sort
            -- (composante d'incantation, composante de degats, un id par
            -- unite qui la lance). Ils ont chacun leur propre compteur
            -- d'occurrence, d'ou trois lignes "Collision puissante (4)" a la
            -- meme seconde, qui n'apportent rien au lecteur.
            --
            -- On ne garde donc qu'une ligne par (seconde, NOM affiche). Le
            -- regroupement se fait ici et pas dans le script, qui ne connait
            -- que des identifiants : seul le client sait quels ids portent le
            -- meme nom. Un id sans nom (absent du client) garde son id comme
            -- cle, donc il reste affiche.
            -- Une piste par NOM affiche, ses occurrences dedans. Le
            -- regroupement par seconde entiere reste indispensable : une meme
            -- capacite porte parfois plusieurs identifiants (incantation,
            -- degats, un par unite qui la lance), qui produiraient autant de
            -- marques superposees au meme instant.
            local byLabel = {}
            for _, cast in ipairs(timeline) do
                if cast.t <= cutoff then
                    local label = C_Spell.GetSpellName(cast.id) or tostring(cast.id)
                    local group = byLabel[label]
                    if not group then
                        group = { label = label, spellid = cast.id,
                                  times = {}, seen = {} }
                        byLabel[label] = group
                        table.insert(lanes, group)
                    end
                    local key = math.floor(cast.t)
                    if not group.seen[key] then
                        group.seen[key] = true
                        table.insert(group.times, cast.t)
                    end
                end
            end
            laneView = #lanes > 0
        end

        -- Mes cooldowns prennent leurs propres pistes, sous celles du boss et
        -- sur le MEME axe : c'est ce qui montre d'un coup d'oeil qu'un sort
        -- reste en recharge pendant trois minutes.
        -- Mise en page compacte de la liste (colonnes, menu fusionne, bouton
        -- dans la carte) : WoW Timeline seulement. Une ligne Viserio porte un
        -- menu de cible en plus et garde sa mise en page.
        local listView = laneView and not fullRaid

        if laneView and not fullRaid then
            local byID, mine = {}, {}
            for _, r in ipairs(reminders) do
                local sid = r.spellid
                if sid then
                    local group = byID[sid]
                    if not group then
                        group = { label = C_Spell.GetSpellName(sid) or tostring(sid),
                                  spellid = sid, times = {}, mine = true }
                        byID[sid] = group
                        table.insert(mine, group)
                    end
                    table.insert(group.times, r.time or 0)
                end
            end
            local function ByFirst(a, b)
                return (a.times[1] or 0) < (b.times[1] or 0)
            end
            table.sort(lanes, ByFirst)
            table.sort(mine, ByFirst)
            for _, group in ipairs(mine) do table.insert(lanes, group) end
        end

        -- Le nom du BOSS, pas celui de la variante : celle-ci se lit deja
        -- dans le selecteur a droite de l'en-tete. `titleText` reste utilise
        -- plus bas pour la pastille d'auteur des notes Viserio.
        ReText(self.details.title, encID and EP.GetEncounterDisplayName(encID) or titleText)
        self.resetMods:Show()
        self.tagMode:SetShown(not fullRaid)
        -- Visible sur les deux sources depuis que BuildNoteString ecrit
        -- lui aussi les lignes ajoutees.
        self.addLineButton:SetShown(true)
        -- Le bouton vit DANS la carte des rappels : c'est ce qu'il remplit.
        -- Il tient sur la ligne du titre, a droite, au-dessus de la premiere
        -- rangee — et la barre d'outils se replie, ce qui rend 30 px a la
        -- timeline.
        if listView then
            self.addLineButton:SetParent(self.details.listCard)
            self.addLineButton:ClearAllPoints()
            self.addLineButton:SetPoint("TOPRIGHT", self.details.listCard,
                "TOPRIGHT", -26, -3)
            self.addLineButton:SetFrameLevel(
                self.details.scroll:GetFrameLevel() + 2)
            self.details.toolbar.addLine = nil
        else
            self.addLineButton:SetParent(self.details.toolbar)
            self.addLineButton:ClearAllPoints()
            self.addLineButton:SetPoint("LEFT", 0, 0)
            self.details.toolbar.addLine = self.addLineButton
        end
        self.details.toolbar:Reflow()

        local lo, hi = TimeBounds(reminders)
        -- Les pistes peuvent aller plus loin que le dernier rappel : sans ca,
        -- les marques de fin de combat sortiraient de l'axe.
        for _, group in ipairs(lanes) do
            for _, t in ipairs(group.times) do
                if t > hi then hi = t end
            end
        end
        -- La piste va jusqu'a la fin du combat, pas jusqu'au dernier rappel :
        -- sinon elle contredisait la duree annoncee dans le menu deroulant.
        hi = math.max(hi, noteDuration or 0)
        local badges = {
            { difficulty == "Mythic" and L["Mythic"] or L["Heroic"],
              difficulty == "Mythic" and P.mythic or P.heroic },
            -- Note Viserio : la pastille porte l'auteur, dont on ignore la
            -- classe, donc teinte neutre. Note WoW Timeline : c'est NOTRE spe, on
            -- la peint a la couleur de classe.
            fullRaid and { authorText or "?", P.spec }
                or { EP.GetSpecLabel(), EP.GetClassColor() or P.spec },
            fullRaid and { L["Full raid"], SourceColor(entry) }
                or { EntrySourceLabel(entry), SourceColor(entry) },
            { (L["%d reminders"]):format(#reminders - bossRows), P.count },
        }
        for i, b in ipairs(badges) do self.details.badges[i]:Set(b[1], b[2]) end

        LayoutTrack(self.details.track, reminders, math.min(lo, 0), math.max(hi, 1))
        self.details.trackStart:SetText(lo < 0 and (FormatTime(lo) .. "  " .. L["pre-pull"]) or "0:00")
        self.details.trackEnd:SetText(FormatTime(hi))

        -- Calcule une seule fois par rafraichissement : une note Viserio
        -- depasse la centaine de lignes, reconstruire le roster a chaque
        -- ligne serait du gaspillage.
        local raidNames = fullRaid and EP.BuildRaidNameSet() or nil

        local y = 0

        -- ---------------------------------------------------------------
        -- PISTES
        -- ---------------------------------------------------------------
        -- Chaque piste porte le nom de la capacite a gauche, puis ses
        -- occurrences placees sur l'axe du temps. Les marques sont des
        -- textures reutilisees d'un rafraichissement a l'autre, comme les
        -- lignes : une note longue en compte plusieurs centaines.
        local hasCompo = fullRaid and entry.note and entry.note.composition
            and #entry.note.composition > 0
        -- Carte du haut d'une note Viserio : composition (joueurs ayant au
        -- moins un sort), rangee par role. Renvoie sa hauteur.
        local function RenderCompo()
                local compo = self.details.compo
                if not compo then
                    compo = CreateFrame("Frame", nil, self.details.timeContent)
                    compo.title = Typeset(compo:CreateFontString(
                        nil, "OVERLAY", "GameFontHighlightSmall"), "time")
                    compo.heads, compo.chips = {}, {}
                    self.details.compo = compo
                end
                local width = math.max(self.details.timeScroll:GetWidth() or 0, 200)
                compo:Show(); compo:ClearAllPoints()
                compo:SetPoint("TOPLEFT", 0, 0)
                compo:SetWidth(width)
                compo.title:ClearAllPoints()
                compo.title:SetPoint("TOPLEFT", 6, -4)
                ReText(compo.title, L["COMPOSITION"])
                Tint(compo.title, P.text)

                -- Regroupement : role (API du jeu) puis spe, avec le compte.
                local order, byRole = { "TANK", "HEALER", "DAMAGER" }, {}
                for _, specID in ipairs(entry.note.composition) do
                    local _, specName, _, _, role, classFile = GetSpecializationInfoByID(specID)
                    if specName and role then
                        byRole[role] = byRole[role] or { list = {}, index = {} }
                        local group = byRole[role]
                        local item = group.index[specID]
                        if not item then
                            item = { name = specName, classFile = classFile, n = 0 }
                            group.index[specID] = item
                            table.insert(group.list, item)
                        end
                        item.n = item.n + 1
                    end
                end
                local labels = { TANK = L["TANKS"], HEALER = L["HEALERS"], DAMAGER = L["DPS"] }

                local cy, chipIndex, headIndex = 24, 0, 0
                for _, role in ipairs(order) do
                    local group = byRole[role]
                    if group then
                        headIndex = headIndex + 1
                        local head = compo.heads[headIndex]
                        if not head then
                            head = Typeset(compo:CreateFontString(
                                nil, "OVERLAY", "GameFontHighlightSmall"), "time")
                            compo.heads[headIndex] = head
                        end
                        local total = 0
                        for _, item in ipairs(group.list) do total = total + item.n end
                        head:Show(); head:ClearAllPoints()
                        head:SetPoint("TOPLEFT", 6, -cy)
                        head:SetText(labels[role] .. "  " .. total)
                        Tint(head, P.textDim)
                        cy = cy + 18

                        local cx = 6
                        for _, item in ipairs(group.list) do
                            chipIndex = chipIndex + 1
                            local chip = compo.chips[chipIndex]
                            if not chip then
                                chip = CreateFrame("Frame", nil, compo)
                                chip:SetHeight(20)
                                chip.fill = RoundedFill(chip, "BACKGROUND", P.panelHead, CTRL_R)
                                chip.text = Typeset(chip:CreateFontString(
                                    nil, "OVERLAY", "GameFontHighlightSmall"), "text")
                                chip.text:SetPoint("LEFT", 8, 0)
                                compo.chips[chipIndex] = chip
                            end
                            local cc = (C_ClassColor and C_ClassColor.GetClassColor(item.classFile))
                                or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[item.classFile])
                            local r, g, b = 0.85, 0.85, 0.85
                            if cc then r, g, b = cc.r, cc.g, cc.b end
                            chip.text:SetText(item.n > 1
                                and (item.name .. "  |cff96989bx" .. item.n .. "|r") or item.name)
                            chip.text:SetTextColor(r, g, b)
                            chip.fill:SetColor({ r, g, b, 0.14 })
                            chip.fill:SetShown(true)
                            local w = (chip.text:GetStringWidth() or 40) + 16
                            -- Retour a la ligne quand la pastille ne tient plus.
                            if cx > 6 and cx + w > width - 6 then
                                cx = 6
                                cy = cy + 24
                            end
                            chip:Show(); chip:ClearAllPoints()
                            chip:SetPoint("TOPLEFT", cx, -cy)
                            chip:SetWidth(w)
                            cx = cx + w + 6
                        end
                        cy = cy + 30
                    end
                end
                for j = headIndex + 1, #compo.heads do compo.heads[j]:Hide() end
                for j = chipIndex + 1, #compo.chips do compo.chips[j]:Hide() end
                compo:SetHeight(cy)
            return cy
        end

        local ly = 0
        if laneView and hasCompo then ly = RenderCompo() + 6 end
        if laneView then
            -- Largeur utile de l'axe. Calculee ici et pas lue sur la frame :
            -- GetWidth() d'une piste ancree a gauche ET a droite ne vaut rien
            -- tant que WoW n'a pas repasse une frame, et les marques seraient
            -- alors toutes empilees sur le bord gauche au premier affichage.
            local trackW = math.max(
                (self.details.timeScroll:GetWidth() or 0) - LANE.LABEL - 28, 60)
            local base = math.min(lo, 0)
            local span = math.max(hi - base, 1)

            -- Echelle et fenetre visible. `laneOffset` est en SECONDES, pas en
            -- pixels : il survit ainsi a un redimensionnement de la fenetre.
            -- Zoom : 1 = tout le combat tient dans la largeur. Au-dela, la
            -- timeline s'etire et se parcourt au curseur ou a la souris.
            local zoom = math.min(math.max(self.details.laneZoom or 1, 1), 8)
            self.details.laneZoom = zoom
            local pxPerSec = math.max(trackW / span, LANE.MIN_PPS) * zoom
            local maxOffset = math.max(span - trackW / pxPerSec, 0)
            local offset = math.min(math.max(self.details.laneOffset or 0, 0),
                maxOffset)
            self.details.laneOffset = offset
            local function X(t) return LANE.LABEL + (t - base - offset) * pxPerSec end
            local function OnScreen(x)
                return x >= LANE.LABEL - 1 and x <= LANE.LABEL + trackW + 1
            end

            local contentLevel = self.details.timeContent:GetFrameLevel()
            local bossCount, mineCount = 0, 0
            for _, group in ipairs(lanes) do
                if group.mine then mineCount = mineCount + 1
                else bossCount = bossCount + 1 end
            end
            local blockH = (bossCount > 0 and (LANE.HEAD + bossCount * LANE.H + LANE.PAD + LANE.GAP) or 0)
                + (mineCount > 0 and (LANE.HEAD + mineCount * LANE.H + LANE.PAD) or 0)

            -- ----- REGLE DE TEMPS -----
            local ruler = self.details.ruler
            if not ruler then
                ruler = CreateFrame("Frame", nil, self.details.timeContent)
                ruler:SetHeight(LANE.RULER)
                ruler.ticks = {}
                ruler.phases = {}
                self.details.ruler = ruler
            end
            ruler:Show(); ruler:ClearAllPoints()
            ruler:SetPoint("TOPLEFT", 0, -ly)
            ruler:SetPoint("RIGHT", 0, 0)
            -- Au-dessus des panneaux : les traits verticaux doivent se voir
            -- par-dessus leur fond, sinon ils disparaissent dans le bloc.
            ruler:SetFrameLevel(contentLevel + 4)

            -- Pas de graduation choisi sur la duree VISIBLE, pas sur le combat
            -- entier : en vue resserree, des reperes toutes les deux minutes
            -- laisseraient un ecran sans aucun repere.
            local visible = math.min(trackW / pxPerSec, span)
            local step = 120
            if visible <= 150 then step = 15
            elseif visible <= 300 then step = 30
            elseif visible <= 600 then step = 60 end

            local tickCount = 0
            for t = math.floor(offset / step) * step, hi, step do
                local x = X(t)
                if OnScreen(x) then
                    tickCount = tickCount + 1
                    local tick = ruler.ticks[tickCount]
                    if not tick then
                        tick = {}
                        tick.label = Typeset(ruler:CreateFontString(
                            nil, "OVERLAY", "GameFontHighlightSmall"), "time")
                        tick.line = ruler:CreateTexture(nil, "ARTWORK")
                        tick.line:SetWidth(1)
                        ruler.ticks[tickCount] = tick
                    end
                    tick.label:Show(); tick.label:ClearAllPoints()
                    tick.label:SetPoint("BOTTOM", ruler, "BOTTOMLEFT", x, 3)
                    tick.label:SetText(FormatTime(t))
                    Tint(tick.label, P.textFaint)
                    tick.line:Show(); tick.line:ClearAllPoints()
                    tick.line:SetPoint("TOP", ruler, "BOTTOMLEFT", x, 0)
                    tick.line:SetHeight(blockH)
                    tick.line:SetColorTexture(P.border[1], P.border[2],
                        P.border[3], 0.35)
                end
            end
            for j = tickCount + 1, #ruler.ticks do
                ruler.ticks[j].label:Hide()
                ruler.ticks[j].line:Hide()
            end

            -- Bornes de phase : le seul repere qui explique un trou dans un
            -- plan. Teinte accent, nettement plus marquee qu'une graduation.
            local phaseCount = 0
            for _, b in ipairs(bounds or {}) do
                local at = tonumber(b.start)
                local x = at and X(at) or nil
                if at and at > 0 and at <= hi and x and OnScreen(x) then
                    phaseCount = phaseCount + 1
                    local ph = ruler.phases[phaseCount]
                    if not ph then
                        ph = {}
                        ph.line = ruler:CreateTexture(nil, "OVERLAY")
                        ph.line:SetWidth(1)
                        ph.label = Typeset(ruler:CreateFontString(
                            nil, "OVERLAY", "GameFontHighlightSmall"), "time")
                        ruler.phases[phaseCount] = ph
                    end
                    ph.line:Show(); ph.line:ClearAllPoints()
                    ph.line:SetPoint("TOP", ruler, "BOTTOMLEFT", x, 0)
                    ph.line:SetHeight(blockH)
                    ph.line:SetColorTexture(P.accent[1], P.accent[2],
                        P.accent[3], 0.45)
                    ph.label:Show(); ph.label:ClearAllPoints()
                    ph.label:SetPoint("BOTTOMLEFT", ruler, "BOTTOMLEFT", x + 3, 3)
                    -- 1.5 doit s'ecrire "1.5", ni "2" ni "1,5".
                    local pn = tonumber(b.phase) or 1
                    ph.label:SetText("P" .. (pn % 1 == 0
                        and tostring(math.floor(pn)) or ("%g"):format(pn)))
                    Tint(ph.label, P.accent)
                end
            end
            for j = phaseCount + 1, #ruler.phases do
                ruler.phases[j].line:Hide()
                ruler.phases[j].label:Hide()
            end
            ly = ly + LANE.RULER

            -- ----- PANNEAUX -----
            -- Chaque bloc est une VRAIE carte : fond, en-tete, marge. Les
            -- intertitres en simple texte ne separaient rien, les pistes du
            -- boss et les miennes se suivaient sur le meme fond.
            local blockIndex = 0
            local function OpenBlock(title, laneCount)
                blockIndex = blockIndex + 1
                local block = self.details.blocks[blockIndex]
                if not block then
                    block = CreateFrame("Frame", nil, self.details.timeContent)
                    block.fill = RoundedFill(block, "BACKGROUND", P.panel, CTRL_R)
                    block.head = block:CreateTexture(nil, "BORDER")
                    block.head:SetPoint("TOPLEFT", 2, -2)
                    block.head:SetPoint("TOPRIGHT", -2, -2)
                    block.head:SetHeight(LANE.HEAD - 2)
                    block.title = Typeset(block:CreateFontString(
                        nil, "OVERLAY", "GameFontHighlightSmall"), "time")
                    block.title:SetPoint("TOPLEFT", 10, -5)
                    self.details.blocks[blockIndex] = block
                end
                block:Show(); block:ClearAllPoints()
                block:SetPoint("TOPLEFT", 0, -ly)
                block:SetPoint("RIGHT", 0, 0)
                block:SetHeight(LANE.HEAD + laneCount * LANE.H + LANE.PAD)
                block:SetFrameLevel(contentLevel + 1)
                block.fill:SetShown(true)
                block.head:SetColorTexture(P.panelHead[1], P.panelHead[2],
                    P.panelHead[3], 1)
                ReText(block.title, title)
                Tint(block.title, P.text)
                ly = ly + LANE.HEAD
            end

            local index, openedMine = 0, false
            -- Marques survolables : position de chaque icone affichee, pour
            -- l'infobulle du sort (voir le cadre de glissement plus bas, qui
            -- recouvre les pistes et recoit donc seul la souris).
            local hits = {}
            if bossCount > 0 then OpenBlock(L["BOSS"], bossCount) end
            for _, group in ipairs(lanes) do
                if group.mine and not openedMine then
                    openedMine = true
                    ly = ly + LANE.PAD + LANE.GAP
                    OpenBlock(L["MY COOLDOWNS"], mineCount)
                end
                index = index + 1
                local lane = self.details.lanes[index]
                if not lane then
                    lane = CreateFrame("Frame", nil, self.details.timeContent)
                    lane:SetHeight(LANE.H)
                    lane.icon = lane:CreateTexture(nil, "ARTWORK")
                    lane.icon:SetSize(14, 14)
                    lane.icon:SetPoint("LEFT", 10, 0)
                    lane.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    lane.text = Typeset(lane:CreateFontString(
                        nil, "OVERLAY", "GameFontHighlightSmall"), "text")
                    lane.text:SetPoint("LEFT", lane.icon, "RIGHT", 6, 0)
                    lane.text:SetWidth(LANE.LABEL - 64)
                    lane.text:SetJustifyH("LEFT")
                    -- Une seule ligne, quoi qu'il arrive : "Grace du marcheur
                    -- des esprits" passait sinon sur deux lignes et cassait
                    -- l'alignement de toute la colonne.
                    if lane.text.SetWordWrap then lane.text:SetWordWrap(false) end
                    lane.count = Typeset(lane:CreateFontString(
                        nil, "OVERLAY", "GameFontHighlightSmall"), "time")
                    lane.count:SetPoint("LEFT", LANE.LABEL - 30, 0)
                    lane.count:SetWidth(24)
                    lane.count:SetJustifyH("RIGHT")
                    lane.marks = {}
                    -- Infobulle du sort au survol du NOM de la piste.
                    -- EnableMouseMotion : survol sans capter clics ni molette.
                    if lane.EnableMouseMotion then
                        lane:EnableMouseMotion(true)
                    else
                        lane:EnableMouse(true)
                    end
                    lane:SetScript("OnEnter", function(fr)
                        if not fr.spellid then return end
                        GameTooltip:SetOwner(fr, "ANCHOR_NONE")
                        GameTooltip:SetPoint("BOTTOMLEFT", fr, "TOPLEFT", 8, 2)
                        if C_Spell.GetSpellName(fr.spellid) then
                            GameTooltip:SetSpellByID(fr.spellid)
                        else
                            GameTooltip:SetText(tostring(fr.spellid), 1, 1, 1)
                        end
                        GameTooltip:Show()
                    end)
                    lane:SetScript("OnLeave", function(fr)
                        if GameTooltip:IsOwned(fr) then GameTooltip:Hide() end
                    end)
                    self.details.lanes[index] = lane
                end
                lane.spellid = group.spellid
                lane:Show(); lane:ClearAllPoints()
                lane:SetPoint("TOPLEFT", 0, -ly)
                lane:SetPoint("RIGHT", 0, 0)
                lane:SetFrameLevel(contentLevel + 2)

                local texture = C_Spell.GetSpellTexture(group.spellid) or 134400
                lane.icon:SetTexture(texture)
                local count = #group.times
                ReText(lane.text, group.label)
                Tint(lane.text, group.mine and P.text or P.bossLine)
                lane.count:SetText(count > 1 and ("x" .. count) or "")
                Tint(lane.count, P.textFaint)

                -- Recharge et duree d'effet du sort, telles que le catalogue
                -- de WoW Timeline les donne (Data/Spells.lua). Absentes : on
                -- s'en tient a l'icone, sans barre — rien n'est devine.
                local info = group.mine and EP.SpellTable
                    and EP.SpellTable[group.spellid] or nil

                local shown = 0
                local laneTop = ly
                for _, t in ipairs(group.times) do
                    local x = X(t)
                    local cd = info and (tonumber(info.cd) or 0) or 0
                    local dur = info and (tonumber(info.dur) or 0) or 0
                    -- Une barre reste pertinente meme si son lancer est sorti
                    -- de l'ecran par la gauche : c'est tout l'interet de voir
                    -- qu'un sort est encore en recharge.
                    if OnScreen(x) or (cd > 0 and OnScreen(X(t + cd))) then
                        shown = shown + 1
                        local mark = lane.marks[shown]
                        if not mark then
                            mark = {}
                            mark.cd = lane:CreateTexture(nil, "BACKGROUND")
                            mark.cd:SetHeight(8)
                            mark.dur = lane:CreateTexture(nil, "BORDER")
                            mark.dur:SetHeight(8)
                            mark.icon = lane:CreateTexture(nil, "OVERLAY")
                            mark.icon:SetSize(LANE.ICON, LANE.ICON)
                            mark.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                            mark.at = Typeset(lane:CreateFontString(
                                nil, "OVERLAY", "GameFontHighlightSmall"), "time")
                            lane.marks[shown] = mark
                        end

                        -- Les barres sont rognees aux deux bords de la fenetre
                        -- visible, sinon une recharge de trois minutes
                        -- deborderait sur la colonne des noms.
                        local function Bar(tex, from, to, alpha)
                            local x1 = math.max(X(from), LANE.LABEL)
                            local x2 = math.min(X(to), LANE.LABEL + trackW)
                            if to > from and x2 > x1 then
                                tex:Show(); tex:ClearAllPoints()
                                tex:SetPoint("LEFT", lane, "LEFT", x1, 0)
                                tex:SetWidth(math.max(x2 - x1, 1))
                                tex:SetColorTexture(P.accent[1], P.accent[2],
                                    P.accent[3], alpha)
                            else
                                tex:Hide()
                            end
                        end
                        Bar(mark.cd, t, math.min(t + cd, hi), 0.16)
                        Bar(mark.dur, t, math.min(t + dur, hi), 0.55)

                        if OnScreen(x) then
                            mark.icon:Show(); mark.icon:ClearAllPoints()
                            mark.icon:SetPoint("CENTER", lane, "LEFT", x, 0)
                            mark.icon:SetTexture(texture)
                            table.insert(hits, { x = x - LANE.LABEL, y = laneTop,
                                id = group.spellid, t = t })
                        else
                            mark.icon:Hide()
                        end

                        -- L'instant du lancer, a droite de l'icone. Seulement
                        -- sur mes pistes : sur une capacite lancee onze fois,
                        -- onze horodatages feraient une ligne illisible.
                        if group.mine and OnScreen(x) then
                            mark.at:Show(); mark.at:ClearAllPoints()
                            mark.at:SetPoint("LEFT", mark.icon, "RIGHT", 3, 0)
                            mark.at:SetText(FormatTime(t))
                            Tint(mark.at, P.textDim)
                        else
                            mark.at:Hide()
                        end
                    end
                end
                for j = shown + 1, #lane.marks do
                    lane.marks[j].icon:Hide()
                    lane.marks[j].cd:Hide()
                    lane.marks[j].dur:Hide()
                    lane.marks[j].at:Hide()
                end
                ly = ly + LANE.H
            end
            for j = index + 1, #self.details.lanes do
                self.details.lanes[j]:Hide()
            end
            ly = ly + LANE.PAD + 6

            -- ----- GLISSER-DEPLACER SUR LES PISTES -----
            -- Un cadre transparent couvre la zone des pistes et capte le
            -- glissement horizontal : c'est le geste naturel sur une
            -- timeline, le curseur plus bas n'en est que le rappel visible.
            local panner = self.details.lanePanner
            if not panner then
                panner = CreateFrame("Frame", nil, self.details.timeContent)
                panner:EnableMouse(true)
                panner:SetScript("OnMouseDown", function(fr, button)
                    if button ~= "LeftButton" or (fr.maxOffset or 0) <= 0 then
                        return
                    end
                    local cx = GetCursorPosition()
                    fr.fromX = cx / (fr:GetEffectiveScale() or 1)
                    fr.fromOffset = fr.owner.details.laneOffset or 0
                    fr.dragging = true
                end)
                local function StopDrag(fr) fr.dragging = nil end
                panner:SetScript("OnMouseUp", StopDrag)
                panner:SetScript("OnHide", StopDrag)
                panner:SetScript("OnLeave", function(fr)
                    fr.tip = nil
                    if GameTooltip:IsOwned(fr) then GameTooltip:Hide() end
                end)
                panner:SetScript("OnUpdate", function(fr)
                    if not fr.dragging then
                        -- Infobulle de la capacite sous la souris : on cherche
                        -- l'icone la plus proche sur la piste survolee.
                        if not fr:IsMouseOver() then return end
                        local sc = fr:GetEffectiveScale() or 1
                        local cx, cy = GetCursorPosition()
                        local mx = cx / sc - (fr:GetLeft() or 0)
                        local my = (fr:GetTop() or 0) - cy / sc
                        local best, bestD = nil, LANE.ICON / 2 + 3
                        for _, h in ipairs(fr.hits or {}) do
                            local top = h.y - (fr.panTop or 0)
                            if my >= top and my <= top + LANE.H then
                                local d = math.abs(mx - h.x)
                                if d <= bestD then best, bestD = h, d end
                            end
                        end
                        if best ~= fr.tip then
                            fr.tip = best
                            if best then
                                GameTooltip:SetOwner(fr, "ANCHOR_NONE")
                                GameTooltip:SetPoint("BOTTOM", fr, "TOPLEFT",
                                    best.x, -(best.y - (fr.panTop or 0)) + 2)
                                if C_Spell.GetSpellName(best.id) then
                                    GameTooltip:SetSpellByID(best.id)
                                else
                                    GameTooltip:SetText(tostring(best.id), 1, 1, 1)
                                end
                                GameTooltip:AddLine(" ")
                                GameTooltip:AddLine(string.format(L["Cast at %s"],
                                    FormatTime(best.t)), P.accent[1], P.accent[2], P.accent[3])
                                GameTooltip:Show()
                            elseif GameTooltip:IsOwned(fr) then
                                GameTooltip:Hide()
                            end
                        end
                        return
                    end
                    if fr.tip then
                        fr.tip = nil
                        if GameTooltip:IsOwned(fr) then GameTooltip:Hide() end
                    end
                    local cx = GetCursorPosition()
                    local x = cx / (fr:GetEffectiveScale() or 1)
                    local moved = (x - (fr.fromX or x)) / (fr.pxPerSec or 1)
                    local want = math.min(math.max(
                        (fr.fromOffset or 0) - moved, 0), fr.maxOffset or 0)
                    -- Seuil d'un demi-second : sans lui, chaque image
                    -- declencherait un rafraichissement complet de la vue.
                    if math.abs(want - (fr.owner.details.laneOffset or 0)) >= 0.5 then
                        fr.owner.details.laneOffset = want
                        fr.owner:Refresh()
                    end
                end)
                self.details.lanePanner = panner
            end
            panner.owner = self
            panner.pxPerSec = pxPerSec
            panner.maxOffset = maxOffset
            panner.hits = hits
            panner.panTop = ly - blockH
            -- La vue a change (zoom, defilement) : l'infobulle sera recalculee.
            panner.tip = nil
            panner:Show(); panner:ClearAllPoints()
            panner:SetPoint("TOPLEFT", LANE.LABEL, -(ly - blockH))
            panner:SetPoint("RIGHT", -14, 0)
            panner:SetHeight(math.max(blockH, 1))
            panner:SetFrameLevel(contentLevel + 6)

            -- ----- CURSEUR HORIZONTAL -----
            -- N'apparait que si la timeline depasse la largeur disponible.
            local slider = self.details.laneSlider
            if not slider then
                slider = CreateFrame("Slider", nil, self.details.timeContent,
                    "BackdropTemplate")
                slider:SetOrientation("HORIZONTAL")
                slider:SetHeight(12)
                RoundedFill(slider, "BACKGROUND", P.borderSoft, 2, { 0, 4 })
                    :SetShown(true)
                slider:SetThumbTexture(MEDIA .. "UI\\thumb")
                local thumb = slider:GetThumbTexture()
                thumb:SetSize(40, 12)
                TintTex(thumb, P.thumb)
                slider:SetScript("OnValueChanged", function(sl, value)
                    local owner = sl.owner
                    if not owner or sl.updating then return end
                    owner.details.laneOffset = value
                    owner:Refresh()
                end)
                slider:EnableMouseWheel(true)
                slider:SetScript("OnMouseWheel", function(sl, delta)
                    sl:SetValue((sl:GetValue() or 0) - delta * (sl.pageStep or 10))
                end)
                self.details.laneSlider = slider
            end
            slider.owner = self

            local zoomOut = self.details.laneZoomOut
            local zoomIn = self.details.laneZoomIn
            if not zoomOut then
                local function ZoomBy(factor)
                    local before = trackW / pxPerSec
                    local centre = (self.details.laneOffset or 0) + before / 2
                    self.details.laneZoom = math.min(math.max(
                        (self.details.laneZoom or 1) * factor, 1), 8)
                    -- On garde le MILIEU de la vue sous les yeux : zoomer sur
                    -- un bord renverrait sans cesse au debut du combat.
                    local after = trackW / (math.max(trackW / span, LANE.MIN_PPS)
                        * self.details.laneZoom)
                    self.details.laneOffset = math.max(centre - after / 2, 0)
                    self:Refresh()
                end
                zoomOut = Button(self.details.timeContent, "-", 22, 16)
                zoomOut:SetScript("OnClick", function() ZoomBy(1 / 1.6) end)
                Tooltip(zoomOut, "Zoom out")
                zoomIn = Button(self.details.timeContent, "+", 22, 16)
                zoomIn:SetScript("OnClick", function() ZoomBy(1.6) end)
                Tooltip(zoomIn, "Zoom in")
                self.details.laneZoomOut, self.details.laneZoomIn = zoomOut, zoomIn
            end
            -- Les deux boutons vont en HAUT A GAUCHE, sur la ligne de la
            -- regle, au-dessus de la colonne des noms : c'est la seule zone
            -- vraiment vide de la carte. En bas ils chevauchaient la derniere
            -- piste et se perdaient a cote du curseur.
            zoomOut:Show(); zoomOut:ClearAllPoints()
            zoomOut:SetPoint("LEFT", ruler, "LEFT", 6, 0)
            zoomIn:Show(); zoomIn:ClearAllPoints()
            zoomIn:SetPoint("LEFT", zoomOut, "RIGHT", 4, 0)

            if maxOffset > 0 then
                slider:Show(); slider:ClearAllPoints()
                slider:SetPoint("TOPLEFT", LANE.LABEL, -ly)
                slider:SetPoint("RIGHT", -14, 0)
                slider.pageStep = math.max(trackW / pxPerSec / 4, 1)
                slider.updating = true
                slider:SetMinMaxValues(0, maxOffset)
                slider:SetValue(offset)
                slider.updating = nil
                Tooltip(slider, "Scroll the timeline")
            else
                slider:Hide()
            end
            ly = ly + 16

            -- Legende. Sans elle, deux bleus de densites differentes et un
            -- trait vertical ne veulent rien dire pour qui ouvre l'addon
            -- pour la premiere fois.
            local legend = self.details.legend
            if not legend then
                legend = CreateFrame("Frame", nil, self.details.timeContent)
                legend:SetHeight(LANE.CAPTION)
                legend.items = {}
                local at = 10
                for k, def in ipairs({
                    { key = "Effect duration", alpha = 0.55 },
                    { key = "On cooldown", alpha = 0.16 },
                    { key = "Phase change", phase = true },
                }) do
                    local item = { def = def }
                    item.swatch = legend:CreateTexture(nil, "ARTWORK")
                    item.swatch:SetSize(def.phase and 2 or 14, 8)
                    item.swatch:SetPoint("LEFT", at, 0)
                    item.text = Typeset(legend:CreateFontString(
                        nil, "OVERLAY", "GameFontHighlightSmall"), "time")
                    item.text:SetPoint("LEFT", item.swatch, "RIGHT", 5, 0)
                    legend.items[k] = item
                end
                self.details.legend = legend
            end
            legend:Show(); legend:ClearAllPoints()
            legend:SetPoint("TOPLEFT", 0, -ly)
            legend:SetPoint("RIGHT", 0, 0)
            -- Libelles et espacement recalcules a chaque affichage : poses
            -- une seule fois, ils restaient dans la langue du premier
            -- affichage, avec des ecarts mesures sur cette langue.
            local at = 10
            for _, item in ipairs(legend.items) do
                local w = item.def.phase and 2 or 14
                item.swatch:ClearAllPoints()
                item.swatch:SetPoint("LEFT", at, 0)
                item.swatch:SetColorTexture(P.accent[1], P.accent[2], P.accent[3],
                    item.def.phase and 0.6 or item.def.alpha)
                ReText(item.text, L[item.def.key])
                Tint(item.text, P.textFaint)
                at = at + w + 9 + math.max(item.text:GetStringWidth(), 50) + 16
            end
            ly = ly + LANE.CAPTION + LANE.GAP

            for j = blockIndex + 1, #self.details.blocks do
                self.details.blocks[j]:Hide()
            end
        else
            if self.details.ruler then self.details.ruler:Hide() end
            if self.details.legend then self.details.legend:Hide() end
            if self.details.laneSlider then self.details.laneSlider:Hide() end
            if self.details.lanePanner then self.details.lanePanner:Hide() end
            if self.details.laneZoomOut then
                self.details.laneZoomOut:Hide()
                self.details.laneZoomIn:Hide()
            end
            for j = 1, #self.details.lanes do self.details.lanes[j]:Hide() end
            for j = 1, #self.details.blocks do self.details.blocks[j]:Hide() end
        end


        -- Hauteur de la carte timeline : son contenu, plafonne a 55 % du
        -- panneau pour que la liste garde de quoi vivre. Au-dela, c'est le
        -- defilement vertical de la carte qui prend le relais.
        if laneView then
            self.details.timeContent:SetWidth(
                math.max(self.details.timeScroll:GetWidth(), 1))
            self.details.timeContent:SetHeight(math.max(ly, 1))
            local total = self.details:GetHeight() or 400
            local roomy = math.max(total * 0.55, 120)
            -- Bornes de la poignee : chaque carte garde au moins de quoi
            -- afficher quelques lignes, aucune ne disparait.
            local minH, maxH = 80, math.max(total * 0.80, 120)
            local share = DB().timelineSplit
            local h
            if type(share) == "number" and share > 0 then
                h = math.min(math.max(share * total, minH), maxH)
            else
                h = math.min(ly + 12, roomy)
            end
            self.details.timeCard:SetHeight(h)
            self.details.timeCard:Show()
            self.details.splitter.minH, self.details.splitter.maxH = minH, maxH
            self.details.splitter:Show()
            self.details.listCard:ClearAllPoints()
            self.details.listCard:SetPoint("TOPLEFT", self.details.timeCard,
                "BOTTOMLEFT", 0, -GAP.cardBody)
            self.details.listCard:SetPoint("BOTTOMRIGHT", self.details,
                "BOTTOMRIGHT", 0, 0)
        elseif fullRaid and entry.note and entry.note.composition
                and #entry.note.composition > 0 then
            self.details.splitter:Hide()
            -- COMPOSITION d'une note Viserio, dans la carte du haut : les
            -- joueurs qui ont au moins un sort dans la note, ranges par role,
            -- une pastille par spe a la couleur de sa classe, ×n si la spe est
            -- en double. C'est la seule information de la note reprise ici.
            local cy = RenderCompo()

            self.details.timeContent:SetWidth(
                math.max(self.details.timeScroll:GetWidth() or 0, 200))
            self.details.timeContent:SetHeight(cy)
            local roomy = math.max((self.details:GetHeight() or 400) * 0.40, 100)
            self.details.timeCard:SetHeight(math.min(cy + 12, roomy))
            self.details.timeCard:Show()
            self.details.listCard:ClearAllPoints()
            self.details.listCard:SetPoint("TOPLEFT", self.details.timeCard,
                "BOTTOMLEFT", 0, -GAP.cardBody)
            self.details.listCard:SetPoint("BOTTOMRIGHT", self.details,
                "BOTTOMRIGHT", 0, 0)
        else
            self.details.splitter:Hide()
            self.details.timeCard:Hide()
            self.details.listCard:ClearAllPoints()
            self.details.listCard:SetPoint("TOPLEFT", self.details.toolbar,
                "BOTTOMLEFT", 0, -GAP.cardBody)
            self.details.listCard:SetPoint("BOTTOMRIGHT", self.details,
                "BOTTOMRIGHT", 0, 0)
        end
        -- La composition ne vit que sur une note Viserio qui en porte une.
        if self.details.compo and not (fullRaid and entry.note
                and entry.note.composition and #entry.note.composition > 0) then
            self.details.compo:Hide()
        end

        -- Titre de la carte des rappels. La carte etant maintenant separee,
        -- il tient lieu d'en-tete et dit combien de lignes partiront dans la
        -- note.
        -- SELECTION (vue liste WoW Timeline) : des lignes cochees, a
        -- supprimer d'un coup. Propre a la note affichee : changer de note
        -- vide la selection. On ne garde que des lignes encore presentes.
        local sel = self.details.selection
        if not sel or sel.key ~= modKey then
            sel = { key = modKey, set = {} }
            self.details.selection = sel
        end
        local selectable, bySpell, spellOrder = {}, {}, {}
        if listView then
            for _, r in ipairs(reminders) do
                if r.lineKey and not r.isBoss then
                    local sid = r.spellid
                    if not r.isCustom then
                        sid = EP.GetLineSpell(modKey, r.lineKey, r.spellid)
                    end
                    selectable[r.lineKey] = r.isCustom and "custom" or "orig"
                    if sid then
                        if not bySpell[sid] then
                            bySpell[sid] = {}
                            table.insert(spellOrder, sid)
                        end
                        table.insert(bySpell[sid], r.lineKey)
                    end
                end
            end
        end
        local nsel = 0
        for k in pairs(sel.set) do
            if selectable[k] then nsel = nsel + 1 else sel.set[k] = nil end
        end
        local nselectable = 0
        for _ in pairs(selectable) do nselectable = nselectable + 1 end

        if listView then
            local head = self.details.listHead
            if not head then
                head = CreateFrame("Frame", nil, self.details.content)
                head:SetHeight(LANE.CAPTION)
                head.text = Typeset(head:CreateFontString(
                    nil, "OVERLAY", "GameFontHighlightSmall"), "time")
                head.text:SetPoint("LEFT", 4, 0)
                -- Nombre de rappels dans une pastille bleue, lisible d'un
                -- coup d'oeil (il etait dans le meme gris que le titre).
                head.badge = CreateFrame("Frame", nil, head)
                head.badge:SetHeight(16)
                head.badge:SetPoint("LEFT", head.text, "RIGHT", 8, 0)
                RoundedFill(head.badge, "BACKGROUND", P.accentSolid, 8):SetShown(true)
                head.count = Typeset(head.badge:CreateFontString(
                    nil, "OVERLAY", "GameFontHighlightSmall"), "time")
                head.count:SetPoint("CENTER")
                Tint(head.count, { 1, 1, 1 })
                head.all = CheckBox(head, 14)
                head.all:SetPoint("LEFT", head.badge, "RIGHT", 18, 0)
                head.allText = Typeset(head:CreateFontString(
                    nil, "OVERLAY", "GameFontHighlightSmall"), "text")
                head.allText:SetPoint("LEFT", head.all, "RIGHT", 6, 0)
                self.details.listHead = head
            end
            head:Show(); head:ClearAllPoints()
            head:SetPoint("TOPLEFT", 0, -y)
            head:SetPoint("RIGHT", 0, 0)
            ReText(head.text, L["MY REMINDERS"])
            Tint(head.text, P.text)
            head.count:SetText(tostring(#reminders))
            head.badge:SetWidth(math.max(head.count:GetStringWidth() + 14, 22))
            local allOn = nselectable > 0 and nsel == nselectable
            head.all:SetChecked(allOn)
            head.all:SetShown(nselectable > 0)
            ReText(head.allText, L["Select all"])
            Tint(head.allText, P.textDim)
            head.allText:SetShown(nselectable > 0)
            head.all:SetScript("OnClick", function()
                for k in pairs(selectable) do sel.set[k] = (not allOn) or nil end
                self:Refresh()
            end)
            y = y + LANE.CAPTION + 10

            -- Une puce par sort : un clic coche (ou decoche) toutes ses lignes.
            self.details.spellChips = self.details.spellChips or {}
            local chips = self.details.spellChips
            local avail = math.max((self.details.scroll:GetWidth() or 0) - 20, 200)
            local cx, rowH = 4, 24
            for ci, sid in ipairs(spellOrder) do
                local chip = chips[ci]
                if not chip then
                    chip = Button(self.details.content, "", 40, rowH, false, 134400)
                    chips[ci] = chip
                end
                local keys = bySpell[sid]
                local all = true
                for _, k in ipairs(keys) do
                    if not sel.set[k] then all = false end
                end
                chip.icon:SetTexture(C_Spell.GetSpellTexture(sid) or 134400)
                TintTex(chip.icon, { 1, 1, 1 })
                chip.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                chip:SetText((C_Spell.GetSpellName(sid) or (L["Spell"] .. " " .. sid))
                    .. "   " .. #keys)
                chip:SetSelected(all)
                local w = chip:GetWidth()
                if cx > 4 and cx + w > avail then
                    cx = 4
                    y = y + rowH + 6
                end
                chip:Show(); chip:ClearAllPoints()
                chip:SetPoint("TOPLEFT", self.details.content, "TOPLEFT", cx, -y)
                cx = cx + w + 6
                chip:SetScript("OnClick", function()
                    for _, k in ipairs(keys) do sel.set[k] = (not all) or nil end
                    self:Refresh()
                end)
            end
            for ci = #spellOrder + 1, #chips do chips[ci]:Hide() end
            if #spellOrder > 0 then y = y + rowH + 8 end

            -- Barre de selection : seulement quand quelque chose est coche.
            local bar = self.details.selBar
            if not bar then
                bar = CreateFrame("Frame", nil, self.details.content)
                bar:SetHeight(CTRL_SIZE + 6)
                RoundedFill(bar, "BACKGROUND", { 0.157, 0.439, 0.741, 0.20 }, CTRL_R):SetShown(true)
                bar.text = Typeset(bar:CreateFontString(
                    nil, "OVERLAY", "GameFontHighlightSmall"), "text")
                bar.text:SetPoint("LEFT", 10, 0)
                bar.cancel = Button(bar, L["Cancel"], 90, CTRL_SIZE - 4)
                bar.cancel:SetPoint("RIGHT", -6, 0)
                bar.delete = Button(bar, "", 120, CTRL_SIZE - 4, false, MEDIA .. "UI\\trash")
                bar.delete:SetDanger()
                bar.delete:SetPoint("RIGHT", bar.cancel, "LEFT", -8, 0)
                self.details.selBar = bar
            end
            if nsel > 0 then
                bar:Show(); bar:ClearAllPoints()
                bar:SetPoint("TOPLEFT", 0, -y)
                bar:SetPoint("RIGHT", -6, 0)
                ReText(bar.text, L["%d reminder(s) selected"]:format(nsel))
                Tint(bar.text, P.text)
                bar.cancel:SetText(L["Cancel"])
                bar.delete:SetText(L["Delete %d"]:format(nsel))
                bar.cancel:SetScript("OnClick", function()
                    sel.set = {}
                    self:Refresh()
                end)
                bar.delete:SetScript("OnClick", function()
                    -- Meme effet que le x de chaque ligne, en une fois : un
                    -- rappel d'origine est marque supprime (« Tout
                    -- reinitialiser » le fait revenir), un rappel ajoute a
                    -- la main est retire.
                    for k in pairs(sel.set) do
                        if selectable[k] == "custom" then
                            EP.RemoveCustomLine(modKey, k)
                        elseif selectable[k] then
                            EP.SetLineDeleted(modKey, k, true)
                        end
                    end
                    sel.set = {}
                    self:Refresh()
                end)
                y = y + CTRL_SIZE + 6 + 10
            else
                bar:Hide()
                y = y + 8
            end
        else
            if self.details.listHead then self.details.listHead:Hide() end
            if self.details.selBar then self.details.selBar:Hide() end
            for _, chip in ipairs(self.details.spellChips or {}) do chip:Hide() end
        end

        -- COLONNES. Une ligne de rappel fait environ 300 px de large dans la
        -- vue en pistes ; au-dela, la carte n'est que du vide a droite pendant
        -- qu'on fait defiler. On remplit donc colonne par colonne, de haut en
        -- bas, et on n'en ouvre une nouvelle que lorsque la precedente est
        -- pleine : avec dix rappels qui tiennent a l'ecran, rien ne change.
        local listTop = y
        local listCols, listRows, listColW = 1, #reminders, 0
        if listView and #reminders > 0 then
            -- Largeur d'une ligne, plus une gouttiere franche. A 316 px tout
            -- compris, le temps d'une colonne venait toucher le bouton de
            -- suppression de la precedente.
            listColW = LANE.LINE_W + LANE.GUTTER
            local avail = math.max(self.details.scroll:GetWidth() or 0, listColW)
            local maxCols = math.max(math.floor(avail / listColW), 1)
            local fits = math.max(math.floor(
                ((self.details.scroll:GetHeight() or 0) - listTop) / CTRL_SIZE), 1)
            listCols = math.min(math.max(math.ceil(#reminders / fits), 1), maxCols)
            listRows = math.ceil(#reminders / listCols)
        end

        for i, reminder in ipairs(reminders) do
            local line = self.details.lines[i]

            if not line then
                line = CreateFrame("Frame", nil, self.details.content)
                line:SetHeight(CTRL_SIZE)
                line.bg = line:CreateTexture(nil, "BACKGROUND")
                line.bg:SetAllPoints()

                -- Survol de la ligne. Il n'en existait aucun : seule la
                -- rayure alternee distinguait les lignes, donc rien ne disait
                -- ou se trouvait la souris sur soixante lignes identiques.
                --
                -- EnableMouseMotion et non EnableMouse : la premiere donne
                -- OnEnter/OnLeave sans capter les clics ni la molette, qui
                -- doivent continuer d'aller aux boutons de la ligne et au
                -- cadre de defilement.
                line.hover = RoundedFill(line, "BORDER", P.hoverLift, CTRL_R)
                if line.EnableMouseMotion then
                    line:EnableMouseMotion(true)
                else
                    line:EnableMouse(true)
                end
                line:SetScript("OnEnter", function(self) self.hover:SetShown(true) end)
                line:SetScript("OnLeave", function(self) self.hover:SetShown(false) end)
                -- Le temps est cliquable (notes complètes Viserio
                -- uniquement) : bouton invisible superposé au texte, seul
                -- moyen de capter un clic sur un FontString.
                line.check = CheckBox(line, 14)
                line.check:SetPoint("LEFT", 6, 0)
                line.check:Hide()
                line.timeButton = CreateFrame("Button", nil, line)
                line.timeButton:SetPoint("LEFT", 4, 0)
                line.timeButton:SetSize(52, 26)
                line.timeButton.hl = line.timeButton:CreateTexture(nil, "HIGHLIGHT")
                line.timeButton.hl:SetAllPoints()
                line.timeButton.hl:SetColorTexture(0.157, 0.439, 0.741, 0.25)
                line.time = Typeset(line.timeButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), "time")
                line.time:SetPoint("LEFT", 4, 0)
                line.time:SetWidth(44)
                Tint(line.time, P.accent)
                line.icon = line:CreateTexture(nil, "ARTWORK")
                line.icon:SetSize(18, 18)
                line.icon:SetPoint("LEFT", line.timeButton, "RIGHT", 4, 0)
                line.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                line.text = Typeset(line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), "text")
                line.text:SetPoint("LEFT", line.icon, "RIGHT", 8, 0)
                line.text:SetJustifyH("LEFT")
                Tint(line.text, P.text)
                -- Suppression rappel par rappel : disparaît de l'aperçu et
                -- de la note générée, sans toucher aux autres rappels.
                line.deleteButton = Button(line, "x", 22, 22)
                line.deleteButton:SetPoint("RIGHT", -6, 0)
                line.deleteButton:Hide()
                -- Remplacement de sort rappel par rappel (notes complètes
                -- Viserio uniquement) : la note dit "Spirale temporelle"
                -- mais chez nous c'est un autre sort qui couvre ce
                -- créneau — recherche filtrée, pas une liste à parcourir.
                -- Rien n'est sauvegardé (voir EP.SetLineSpell).
                line.spellControl = SpellPicker(line, self.details, 190)
                line.spellControl:SetPoint("RIGHT", line.deleteButton, "LEFT", -6, 0)
                line.spellControl:Hide()
                -- Qui reçoit l'alerte pour ce rappel : toute une spé (par
                -- défaut) ou un joueur précis du raid actuel — utile
                -- quand deux joueurs partagent la même spé et qu'un seul
                -- doit vraiment agir. Rien n'est sauvegardé non plus.
                line.targetControl = TargetPicker(line, self.details, 150)
                line.targetControl:SetPoint("RIGHT", line.spellControl, "LEFT", -6, 0)
                line.targetControl:Hide()
                self.details.lines[i] = line
            end
            line:Show(); line:ClearAllPoints()
            if listCols > 1 then
                local col = math.floor((i - 1) / listRows)
                local row = (i - 1) % listRows
                line:SetPoint("TOPLEFT", col * listColW,
                    -(listTop + row * CTRL_SIZE))
                line:SetWidth(LANE.LINE_W)
            else
                line:SetPoint("TOPLEFT", 0, -y)
                line:SetPoint("RIGHT", 0, 0)
            end
            -- Pas de rayure alternee : la maquette n'en a pas. Les lignes
            -- reposent toutes sur la carte, et ce sont le survol et la
            -- selection qui les distinguent — pas une couleur permanente.
            line.bg:SetColorTexture(0, 0, 0, 0)
            -- Temps ABSOLU depuis le debut du combat, sur une seule piste
            -- continue : la phase NSRT est deduite a l'ecriture de la note
            -- (EP.SplitPhase) et n'a plus a etre geree ici.
            line.time:SetText(FormatTime(reminder.time))

            local isCustom = reminder.isCustom
            local lineKey = reminder.lineKey

            -- Case de selection (vue liste) : le temps se decale pour lui
            -- laisser la place.
            local checkable = listView and lineKey and selectable[lineKey]
            line.timeButton:ClearAllPoints()
            if checkable then
                line.check:Show()
                line.check:SetChecked(sel.set[lineKey])
                line.check:SetScript("OnClick", function()
                    sel.set[lineKey] = (not sel.set[lineKey]) or nil
                    self:Refresh()
                end)
                line.timeButton:SetPoint("LEFT", 24, 0)
            else
                line.check:Hide()
                line.timeButton:SetPoint("LEFT", 4, 0)
            end
            line.hover:SetShown(false)
            if checkable and sel.set[lineKey] then
                line.bg:SetColorTexture(P.accentSolid[1], P.accentSolid[2],
                    P.accentSolid[3], 0.22)
            end

            if reminder.isBoss then
                -- Ligne de boss : informative. Pas de cible, pas de sort a
                -- changer, pas de suppression — mais cliquable pour creer un
                -- rappel en face (notes completes uniquement, seules a
                -- supporter les lignes ajoutees a la main).
                line.deleteButton:Hide()
                line.spellControl:Hide()
                line.targetControl:Hide()
                line.timeButton:SetScript("OnEnter", nil)
                line.timeButton:SetScript("OnLeave", nil)
                if modKey then
                    local atTime = reminder.time
                    line.timeButton:EnableMouse(true)
                    line.timeButton:SetScript("OnClick", function()
                        EP.AddCustomLine(modKey, nil, math.floor(atTime))
                        self:Refresh()
                    end)
                    Tooltip(line.timeButton, "Click to add one of your own reminders at this boss ability.")
                else
                    line.timeButton:EnableMouse(false)
                    line.timeButton:SetScript("OnClick", nil)
                end
            elseif lineKey then
                line.timeButton:EnableMouse(true)
                local origTime = reminder.time
                line.timeButton:SetScript("OnClick", function()
                    StaticPopup_Show("NSRTAUTOREMINDERS_CHANGE_TIME", nil, nil, {
                        isCustom = isCustom, modKey = modKey, lineKey = lineKey, origTime = origTime,
                        currentTime = reminder.time,
                        refresh = function() self:Refresh() end,
                    })
                end)
                -- Volontairement AUCUNE mention de phase ici. La timeline
                -- est une piste continue en secondes depuis le debut du
                -- combat, d'un bout a l'autre du fight ; le decoupage en
                -- phases NSRT est un detail d'implementation de l'export
                -- (EP.SplitPhase) qui ne doit jamais remonter a l'ecran.
                Tooltip(line.timeButton, "Click to set an exact time (in seconds) for this reminder — only for this note, nothing is saved.")

                line.deleteButton:Show()
                line.deleteButton:SetScript("OnClick", function()
                    if isCustom then
                        EP.RemoveCustomLine(modKey, lineKey)
                    else
                        EP.SetLineDeleted(modKey, lineKey, true)
                    end
                    self:Refresh()
                end)
                Tooltip(line.deleteButton, "Remove this reminder from the note — only for this note, nothing is saved.")
            else
                line.timeButton:EnableMouse(false)
                line.timeButton:SetScript("OnClick", nil)
                line.timeButton:SetScript("OnEnter", nil)
                line.timeButton:SetScript("OnLeave", nil)
                line.deleteButton:Hide()
            end

            -- Rappel ajouté sans sort choisi pour l'instant : espace
            -- réservé plutôt que d'appeler l'API sur un spellid nil.
            local displaySpellID = reminder.spellid
            if not isCustom and lineKey then
                displaySpellID = EP.GetLineSpell(modKey, lineKey, reminder.spellid)
            end
            local displayName
            if displaySpellID then
                displayName = C_Spell.GetSpellName(displaySpellID)
                    or (L["Spell"] .. " " .. tostring(displaySpellID))
                line.icon:SetTexture(C_Spell.GetSpellTexture(displaySpellID) or 134400)
                line.icon:Show()
            else
                displayName = L["Choose a spell..."]
                line.icon:Hide()
            end
            if reminder.isBoss then
                -- "(3)" : la 3e fois que le boss lance cette capacite. Sans
                -- ce numero, cinq lignes identiques se suivent sans qu'on
                -- sache laquelle est laquelle.
                if reminder.occurrence and reminder.occurrence > 1 then
                    displayName = displayName .. " (" .. reminder.occurrence .. ")"
                end
                ReText(line.text, displayName)
                -- Teinte dediee, distincte du gris des libelles : la colonne
                -- de gauche se lit comme un decor, pas comme une consigne.
                Tint(line.text, P.bossLine)
                Tint(line.time, P.textFaint)
            else
                ReText(line.text, displayName)
                Tint(line.text, P.text)
                local touched = displaySpellID ~= reminder.spellid or not displaySpellID
                Tint(line.time, touched and P.accent or P.textDim)
            end

            -- Les capacites du boss sont dans les pistes, pas dans la liste :
            -- l'icone reprend donc sa place normale, juste apres le temps.
            line.icon:ClearAllPoints()
            line.icon:SetPoint("LEFT", line.timeButton, "RIGHT", 4, 0)

            line.text:ClearAllPoints()
            line.text:SetPoint("LEFT", line.icon:IsShown() and line.icon or line.timeButton, "RIGHT", 8, 0)

            -- Édition du sort : dispo dès qu'il y a un lineKey (Viserio ET
            -- WoW Timeline désormais). Le remap vers un joueur précis reste
            -- Viserio-only (origSpecID par ligne n'existe pas pour une
            -- variante WoW Timeline, déjà mono-spé — voir plus haut).
            local canEditSpell = lineKey ~= nil and not reminder.isBoss
            local canEditTarget = fullRaid and lineKey ~= nil and not reminder.isBoss

            -- COLONNE DE DROITE : le menu de sort EST la ligne.
            -- Avant, le nom s'ecrivait a gauche de la colonne ET se repetait a
            -- l'identique dans le menu colle au bord droit, avec plusieurs
            -- centaines de pixels de vide entre les deux. Le menu porte deja
            -- l'icone et le nom, et c'est lui qu'on manipule : on le pose donc
            -- en tete de colonne, le bouton de suppression juste apres, et le
            -- libelle en double disparait.
            --
            -- Seulement en mode deux colonnes (source WoW Timeline). Une note
            -- Viserio garde sa mise en page : son libelle n'est pas un doublon,
            -- il n'y a pas de colonne de boss pour l'adosser, et son menu de
            -- cible occupe la droite de la ligne.
            local mergedControl = listView and canEditSpell
            line.spellControl:ClearAllPoints()
            line.deleteButton:ClearAllPoints()
            if mergedControl then
                line.spellControl:SetPoint("LEFT", line.timeButton, "RIGHT", 4, 0)
                line.deleteButton:SetPoint("LEFT", line.spellControl, "RIGHT", 6, 0)
                line.icon:Hide()
            else
                line.deleteButton:SetPoint("RIGHT", -6, 0)
                line.spellControl:SetPoint("RIGHT", line.deleteButton, "LEFT", -6, 0)
            end
            line.text:SetShown(not mergedControl)

            if canEditSpell then
                line.text:SetPoint("RIGHT",
                    canEditTarget and line.targetControl or line.spellControl,
                    "LEFT", -8, 0)
                line.spellControl:Show()
                ReText(line.spellControl.text, displayName)
                if displaySpellID then
                    line.spellControl.icon:SetTexture(C_Spell.GetSpellTexture(displaySpellID) or 134400)
                end
                line.spellControl:SetSourceItems(GetKnownSpellItems())

                local origSpellID = reminder.spellid
                line.spellControl.onSelect = function(item)
                    if isCustom then
                        EP.SetCustomLineField(modKey, lineKey, "spellid", item.spellID)
                    else
                        EP.SetLineSpell(modKey, lineKey, origSpellID, item.spellID)
                    end
                    self:Refresh()
                end
                Tooltip(line.spellControl, "Click to replace this reminder's spell — only for this note, nothing is saved.")
            else
                line.text:SetPoint("RIGHT", -8, 0)
                line.spellControl:Hide()
            end

            if canEditTarget then
                line.targetControl:Show()
                local origSpecID = reminder.origSpecID
                local target
                if isCustom then
                    -- Cible stockée directement sur la ligne perso (pas de
                    -- valeur d'origine à comparer/écraser).
                    for _, custom in ipairs(EP.GetCustomLines(modKey)) do
                        if custom.lineKey == lineKey then target = custom.target end
                    end
                else
                    target = EP.GetLineRemapTarget(modKey, lineKey, origSpecID)
                end
                -- Plusieurs joueurs de cette spe : chaque bloc doit porter
                -- un pseudo, sinon ses lignes partiraient avec tag:<specID>
                -- et s'afficheraient chez les deux joueurs a la fois.
                -- Chaque bloc doit porter un pseudo avant l'envoi : une
                -- ligne marquee par spe s'afficherait chez TOUS les joueurs
                -- de cette spe dans le raid qui recoit la note.
                local actorCount = reminder.actorCount or 1
                local actorIdx = reminder.actorIndex or 1
                local actorName = not isCustom
                    and EP.GetActorName(modKey, origSpecID, actorIdx) or nil
                local actorSuffix = actorCount > 1
                    and ("  (%d/%d)"):format(actorIdx, actorCount) or ""
                if type(target) == "string" then
                    ReText(line.targetControl.text, target)
                    Tint(line.targetControl.text, P.accent)
                elseif actorName then
                    ReText(line.targetControl.text, actorName .. actorSuffix)
                    -- Pseudo assigne mais absent du raid : signale en
                    -- orange, sans bloquer (le joueur peut arriver apres).
                    Tint(line.targetControl.text,
                        EP.IsNameInRaid(raidNames, actorName) and P.accent or P.warning)
                else
                    ReText(line.targetControl.text,
                        L["Name needed"] .. actorSuffix)
                    Tint(line.targetControl.text, P.warning)
                end
                line.targetControl:SetResetItem(not isCustom and {
                    text = L["Clear this player's name"],
                    isReset = true,
                } or nil)
                line.targetControl.onSelect = function(item)
                    -- Choisir un pseudo nomme TOUT le bloc de ce joueur, pas
                    -- seulement la ligne : une note Viserio compte plus de
                    -- cent rappels, les assigner un par un serait
                    -- inutilisable.
                    if not isCustom then
                        EP.SetActorName(modKey, origSpecID, actorIdx,
                            (not item.isReset) and item.value or nil)
                        self:Refresh()
                        return
                    end
                    if isCustom then
                        EP.SetCustomLineField(modKey, lineKey, "target", item.value)
                    elseif item.isReset then
                        EP.SetLineRemap(modKey, lineKey, origSpecID, nil)
                    else
                        EP.SetLineRemap(modKey, lineKey, origSpecID, item.value)
                    end
                    self:Refresh()
                end
                Tooltip(line.targetControl, "Choose exactly who should see this reminder — a specific raid member instead of the whole spec. Only for this note, nothing is saved.")
            else
                line.targetControl:Hide()
            end
            if listCols > 1 then
                y = listTop + listRows * CTRL_SIZE
            else
                y = y + CTRL_SIZE
            end
        end

        -- Alignement des deux colonnes de droite.
        --
        -- Chaque cadre connait la largeur qu'il lui faudrait ; on prend la
        -- PLUS GRANDE et on la donne a tous. Les colonnes deviennent droites
        -- et restent assez larges pour le libelle le plus long de la note.
        --
        -- Mesure apres coup et non pendant la boucle : la largeur voulue
        -- d'une ligne depend d'un libelle qu'on ne connait qu'une fois tous
        -- les autres poses.
        local function AlignColumn(get)
            local want = 0
            for j = 1, #reminders do
                local line = self.details.lines[j]
                local ctrl = line and get(line)
                if ctrl and ctrl:IsShown() and ctrl.NeededWidth then
                    want = math.max(want, ctrl:NeededWidth())
                end
            end
            if want <= 0 then return end
            for j = 1, #reminders do
                local line = self.details.lines[j]
                local ctrl = line and get(line)
                if ctrl and ctrl.SetColumnWidth then ctrl:SetColumnWidth(want) end
            end
        end
        AlignColumn(function(line) return line.spellControl end)
        AlignColumn(function(line) return line.targetControl end)

        -- COLONNES, deuxieme passe. La premiere supposait une ligne de largeur
        -- fixe ; mais AlignColumn vient d'elargir TOUS les menus au nom le plus
        -- long (« Potion de soins concentree de Lune-d'Argent »). La ligne
        -- debordait alors de sa colonne, et le bouton de suppression passait
        -- sous le temps de la colonne suivante. On mesure donc le menu tel
        -- qu'il est maintenant, et on refait la grille avec cette largeur.
        if listView and #reminders > 0 then
            local ctrlW = 0
            for j = 1, #reminders do
                local ctrl = self.details.lines[j] and self.details.lines[j].spellControl
                if ctrl and ctrl:IsShown() then
                    ctrlW = math.max(ctrlW, ctrl:GetWidth() or 0)
                end
            end
            -- case 20, temps (4 + 52) + 4, le menu, 6 + suppression 22, 6 de marge
            local lineW = 20 + 60 + ctrlW + 6 + 22 + 6
            local colW = lineW + LANE.GUTTER
            local avail = math.max(self.details.scroll:GetWidth() or 0, colW)
            local maxCols = math.max(math.floor((avail + LANE.GUTTER) / colW), 1)
            local fits = math.max(math.floor(
                ((self.details.scroll:GetHeight() or 0) - listTop) / CTRL_SIZE), 1)
            listCols = math.min(math.max(math.ceil(#reminders / fits), 1), maxCols)
            listRows = math.ceil(#reminders / listCols)
            for j = 1, #reminders do
                local line = self.details.lines[j]
                line:ClearAllPoints()
                if listCols > 1 then
                    local col = math.floor((j - 1) / listRows)
                    local row = (j - 1) % listRows
                    line:SetPoint("TOPLEFT", col * colW, -(listTop + row * CTRL_SIZE))
                    line:SetWidth(lineW)
                else
                    line:SetPoint("TOPLEFT", 0, -(listTop + (j - 1) * CTRL_SIZE))
                    line:SetPoint("RIGHT", 0, 0)
                end
            end
            y = listTop + listRows * CTRL_SIZE

            -- Filet vertical au milieu de chaque gouttiere.
            self.details.listSeps = self.details.listSeps or {}
            for c = 1, listCols - 1 do
                local sep = self.details.listSeps[c]
                if not sep then
                    sep = self.details.content:CreateTexture(nil, "ARTWORK")
                    sep:SetWidth(1)
                    self.details.listSeps[c] = sep
                end
                sep:Show(); sep:ClearAllPoints()
                sep:SetPoint("TOPLEFT", self.details.content, "TOPLEFT",
                    c * colW - LANE.GUTTER / 2, -listTop)
                sep:SetHeight(math.max(listRows * CTRL_SIZE, 1))
                sep:SetColorTexture(P.borderSoft[1], P.borderSoft[2],
                    P.borderSoft[3], 1)
            end
            for c = listCols, #self.details.listSeps do
                self.details.listSeps[c]:Hide()
            end
        elseif self.details.listSeps then
            for c = 1, #self.details.listSeps do self.details.listSeps[c]:Hide() end
        end

        -- Les lignes sont des widgets réutilisés d'un rafraîchissement à
        -- l'autre : sans ça, passer d'une note à 116 rappels (Viserio) à
        -- une note à 8 rappels (WoW Timeline) laissait les lignes 9 à 116
        -- affichées avec leur ancien contenu (spé, sort, contrôles...).
        for j = #reminders + 1, #self.details.lines do
            self.details.lines[j]:Hide()
        end
        self.details.content:SetHeight(math.max(y, 1))

        if fullRaid then
            local specCount = 0
            for _ in pairs(entry.note.specs) do specCount = specCount + 1 end
            local compatible = EP.GetNSRTCompatibility()
            local canShare = EP.IsEnabled() and compatible and EP.IsBossEnabled(encID)
            -- Blocs encore anonymes : l'envoi reste bloque, sinon leurs
            -- lignes partiraient avec tag:<specID> et s'afficheraient chez
            -- tous les joueurs de la spe concernee.
            local missing = #EP.GetUnnamedActors(entry.note, modKey)
                            + EP.GetUnnamedCustomLines(modKey)
            if missing > 0 then
                self.status:SetText((L["%d block(s) still need a player name — click their target column to assign one."]):format(missing))
                Tint(self.status, P.warning)
                self.load:SetText(L["Send to Shared Notes"])
                self.load:SetEnabledState(false)
                return
            end
            local absent = EP.GetAbsentActorNames(entry.note, modKey)
            if #absent > 0 then
                local shown = table.concat(absent, ", ", 1, math.min(#absent, 3))
                if #absent > 3 then shown = shown .. "..." end
                self.status:SetText(
                    (L["%d assigned player(s) are not in the raid right now: %s"])
                        :format(#absent, shown))
                Tint(self.status, P.warning)
                self.load:SetText(L["Send to Shared Notes"])
                self.load:SetEnabledState(canShare)
                return
            end
            local isActive, trackedName = EP.GetSharedNoteActivation(encID, entry)
            if isActive == false then
                self.status:SetText((L["Sent as %s, but that's not the note currently active in NSRT — open Shared Notes and click it (or check if your NSRT profile changed)."]):format(trackedName))
                Tint(self.status, P.warning)
            else
                self.status:SetText((L["Complete note covering %d specializations — anyone can share it to the group."]):format(specCount))
                Tint(self.status, P.info)
            end
            self.load:SetText(L["Send to Shared Notes"])
            self.load:SetEnabledState(canShare)
            return
        end

        local state = EP.GetRowState(encID, self.selectedEntryIndex)
        local compatible = EP.GetNSRTCompatibility()
        local canImport = EP.IsEnabled() and compatible and EP.IsBossEnabled(encID)

        if state == "up_to_date" then
            local isActive, trackedName = EP.GetPersonalNoteActivation(encID, entry)
            if isActive == false then
                self.status:SetText((L["Imported as %s, but it isn't set to load in NSRT right now (check if your NSRT profile changed)."]):format(trackedName))
                Tint(self.status, P.warning)
            else
                self.status:SetText(L["Up to date — ready for next pull"]); Tint(self.status, P.success)
            end
            self.load:SetText(L["Up to date"]); self.load:SetEnabledState(false)
        elseif state == "update" then
            self.status:SetText(L["A newer timeline is available."]); Tint(self.status, P.warning)
            self.load:SetText(L["Update in NSRT"]); self.load:SetEnabledState(canImport)
        elseif state == "imported" then
            self.status:SetText(L["Imported — another note is currently selected for the next pull."]); Tint(self.status, P.info)
            self.load:SetText(L["Select for next pull"]); self.load:SetEnabledState(canImport)
        else
            self.status:SetText(L["Not imported"]); Tint(self.status, P.textFaint)
            self.load:SetText(L["Send to Personal Notes"]); self.load:SetEnabledState(canImport)
        end
    end

    function f:Refresh()
        local on = EP.IsEnabled()
        self.enabled:SetChecked(on)
        self.enabled:Paint()

        local compatible, compatibilityIssue = EP.GetNSRTCompatibility()
        local issues = EP.GetNSRTDisplayIssues and EP.GetNSRTDisplayIssues() or {}
        if not on then
            self:SetNotice(L["AutoReminders is disabled. Existing imported notes are kept in NSRT."])
        elseif not compatible then
            self:SetNotice((L["NSRT compatibility issue: %s"]):format(compatibilityIssue or "?"))
        elseif #issues > 0 then
            self:SetNotice(table.concat(issues, "  /  ") .. "  —  "
                .. L["Enable them in NSRT's settings (/ns) for the reminders to show."])
        else
            self:SetNotice(nil)
        end

        local date = EP.GetDataDate and EP.GetDataDate()
        self.dataDate:SetText(date and (L["Data from %s"]):format(date) or "")

        self:RefreshSource()
        self:RefreshSeason()
        self:RefreshLanguage()
        self:RefreshStaticText()
        self:RefreshRaid()
        self:RefreshBoss()
        self:RefreshDetails()
    end

    f:SetScript("OnShow", function(self)
        self:UpdateColumnLayout()
        self:Refresh()
    end)
    f:SetScript("OnHide", function(self)
        self.source.menu:Hide()
        self.season.menu:Hide()
        self.language.menu:Hide()
        self.timelineSelect.menu:Hide()
    end)

    f:UpdateColumnLayout()
    f:Hide()
    return f
end

--[[ API publique --------------------------------------------------------]]

function EP.GetMainWindow()
    if not UI then UI = CreateMainWindow() end
    return UI
end

function EP.ShowMainWindow()
    local f = EP.GetMainWindow()
    f:Show(); f:Raise(); f:Refresh()
end

function EP.ToggleMainWindow()
    local f = EP.GetMainWindow()
    if f:IsShown() then f:Hide() else EP.ShowMainWindow() end
end

function EP.RefreshUI()
    if UI and UI:IsShown() then UI:Refresh() end
end

function EP.RefreshStates()
    EP.RefreshUI()
end
