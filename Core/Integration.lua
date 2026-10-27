local ADDON_NAME, EP = ...
local L = setmetatable({}, { __index = function(_, k) return (EP.L or {})[k] or k end })

--[[----------------------------------------------------------------------
  NSRT AutoReminders — Onglet dans la fenêtre de Northern Sky Raid Tools

  On s'accroche à des éléments INTERNES de NSRT (NSUI, MenuFrame,
  NSUIHeaderBtn_PersonalNotes). Ces noms peuvent changer d'une version de
  NSRT à l'autre : en cas d'échec, on prévient le joueur une seule fois au
  lieu de disparaître silencieusement. L'addon reste utilisable via
  /autoreminders et le bouton minimap.
------------------------------------------------------------------------]]

local TAB_NAME = "AutoReminders"
local installed = false
local attempts = 0
local MAX_ATTEMPTS = 6
local failureReported = false

-- Depuis NSRT 12.1, l'UI (et donc le système d'onglets) vit dans l'addon
-- séparé NorthernSkyRaidTools_UI, exposé via _G.NorthernSkyRaidTools.UI.
-- Core.NSUI — plus un simple global _G.NSUI comme avant. On garde l'ancien
-- chemin en repli au cas où une version plus ancienne de NSRT tourne
-- encore chez certains joueurs.
local function GetNSUI()
    local NSI = _G["NorthernSkyRaidTools"]
    local viaCore = NSI and NSI.UI and NSI.UI.Core and NSI.UI.Core.NSUI
    if viaCore then return viaCore end
    return _G["NSUI"]
end

-- Bouton d'en-tête auquel s'ancrer : celui des notes personnelles en
-- priorité, sinon le dernier bouton connu du système d'onglets.
local function FindAnchor(tabSystem)
    local anchor = _G["NSUIHeaderBtn_PersonalNotes"]
    if anchor then return anchor end
    local buttons = tabSystem and tabSystem.AllButtons
    if buttons then
        for i = #buttons, 1, -1 do
            local b = buttons[i]
            if b and b.GetFrameLevel and b:GetName() ~= ("NSUIHeaderBtn_" .. TAB_NAME) then
                return b
            end
        end
    end
end

local function FindReferenceFrame(tabSystem)
    local byName = tabSystem and tabSystem.AllFramesByName
    if not byName then return nil end
    return byName["PersonalNotes"] or byName["Reminders"]
        or (tabSystem.AllFrames and tabSystem.AllFrames[1])
end

local function CreateHeaderButton(NSUI, anchorBtn, tabSystem)
    local btn = CreateFrame("Button", "NSUIHeaderBtn_" .. TAB_NAME, NSUI, "BackdropTemplate")
    btn:SetSize(190, 26)
    btn:SetPoint("TOPLEFT", anchorBtn, "TOPRIGHT", 6, 0)
    btn:SetFrameLevel(anchorBtn:GetFrameLevel())
    btn:SetBackdrop({ bgFile = [[Interface\Tooltips\UI-Tooltip-Background]], tile = true, tileSize = 64 })
    btn:SetBackdropColor(0.1, 0.1, 0.1, 0.9)

    local selectedTex = btn:CreateTexture(nil, "BACKGROUND")
    selectedTex:SetAllPoints(); selectedTex:SetColorTexture(0, 1, 1, 0.18); selectedTex:Hide()
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetAllPoints(); label:SetText("|cFF33CCFFAuto|r Reminders")

    function btn:Select()
        selectedTex:Show(); self._selected = true
        C_Timer.After(0, function()
            EP.ShowMainWindow()
            -- L'onglet sert uniquement de lanceur : NSRT peut rester ouvert derrière.
        end)
    end
    function btn:Deselect() selectedTex:Hide(); self._selected = false end
    function btn:IsSelected() return self._selected end

    btn:SetScript("OnClick", function()
        tabSystem:SelectTabByName(TAB_NAME)
        EP.ShowMainWindow()
    end)
    return btn
end

local function TryInstall()
    if installed then return true end
    local NSUI = GetNSUI()
    local tabSystem = NSUI and NSUI.MenuFrame
    local anchorBtn = FindAnchor(tabSystem)
    local refFrame = FindReferenceFrame(tabSystem)
    if not (NSUI and tabSystem and tabSystem.AllFramesByName and tabSystem.AllFrames
            and tabSystem.AllButtons and anchorBtn and refFrame) then
        return false
    end

    -- Frame minimal requis par le système d'onglets NSRT.
    local tabFrame = CreateFrame("Frame", "NSUI_TabFrame_" .. TAB_NAME, NSUI)
    tabFrame:SetPoint("TOPLEFT", refFrame, "TOPLEFT", 0, 0)
    tabFrame:SetPoint("BOTTOMRIGHT", refFrame, "BOTTOMRIGHT", 0, 0)
    tabFrame:Hide()

    local text = tabFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("CENTER", 0, 18)
    text:SetText((L["%s opens in its own window."]):format("|cFF33CCFFNSRT AutoReminders|r"))
    local open = CreateFrame("Button", nil, tabFrame, "UIPanelButtonTemplate")
    open:SetSize(210, 28); open:SetPoint("TOP", text, "BOTTOM", 0, -14)
    open:SetText(L["Open AutoReminders"])
    open:SetScript("OnClick", EP.ShowMainWindow)
    tabFrame:HookScript("OnShow", function() C_Timer.After(0, EP.ShowMainWindow) end)

    tabSystem.AllFramesByName[TAB_NAME] = tabFrame
    table.insert(tabSystem.AllFrames, tabFrame)
    local btn = CreateHeaderButton(NSUI, anchorBtn, tabSystem)
    tabSystem.AllButtonsByName = tabSystem.AllButtonsByName or {}
    tabSystem.AllButtonsByName[TAB_NAME] = btn
    table.insert(tabSystem.AllButtons, btn)
    installed = true
    return true
end

-- Nouvelles tentatives espacées : NSRT construit son système d'onglets
-- de façon paresseuse (NSUI:Init() ne tourne qu'à la toute première
-- ouverture de sa fenêtre par le joueur, pas au login) — donc ces
-- tentatives échouent souvent tant que NSRT n'a pas encore été ouvert
-- une fois. Le message qui suit ne doit donc PAS dire que ça a
-- définitivement échoué : le hook OnShow posé dans TryInstall/f:SetScript
-- ci-dessus prendra le relais dès la première ouverture de NSRT.
local function Retry()
    if TryInstall() then return end
    attempts = attempts + 1
    if attempts < MAX_ATTEMPTS then
        C_Timer.After(2, Retry)
    elseif not failureReported then
        failureReported = true
        print("|cFF33CCFFAutoReminders|r: |cFFFFB347"
            .. L["The NSRT tab isn't ready yet — it will appear automatically the first time you open NSRT this session. Meanwhile, use the minimap button or /autoreminders to open the window."] .. "|r")
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    C_Timer.After(3, function()
        if not TryInstall() then
            local NSUI = GetNSUI()
            if NSUI then NSUI:HookScript("OnShow", TryInstall) end
            Retry()
        end
    end)
end)

--[[----------------------------------------------------------------------
  Confirmation d'activation réelle des notes partagées

  Une note Shared Notes ne devient réellement active que quand le joueur
  clique dessus dans l'onglet Shared Notes de NSRT — jusque-là, on ne
  peut que deviner si ça a marché. NSRT annonce ce changement via son
  propre évènement public (NSRT_REMINDER_CHANGED, voir NSAPI.RegisterCallback
  dans Functions.lua). On s'y abonne pour confirmer une fois pour de bon,
  au lieu de laisser le joueur deviner ou de sonder en boucle.

  Les arguments passés par l'évènement ne sont volontairement pas utilisés
  ici : on relit directement NSRT.ActiveReminder à chaque déclenchement,
  ce qui reste correct même si le format des arguments changeait un jour.
------------------------------------------------------------------------]]

local function OnNSRTReminderChanged()
    if EP.pendingConfirm and NSRT and NSRT.ActiveReminder == EP.pendingConfirm.noteName then
        print("|cFF33CCFFAutoReminders|r: " ..
            (L["\"%s\" is now active in NSRT."]):format(EP.pendingConfirm.planName))
        EP.pendingConfirm = nil
    end
    if EP.RefreshUI then EP.RefreshUI() end
end

local function TryRegisterReminderCallback()
    local NSAPIRef = _G["NSAPI"]
    if NSAPIRef and NSAPIRef.RegisterCallback then
        local ok = pcall(NSAPIRef.RegisterCallback, EP, "NSRT_REMINDER_CHANGED", OnNSRTReminderChanged)
        return ok
    end
    return false
end

-- NorthernSkyRaidTools est une dépendance déclarée (## Dependencies dans
-- le .toc), donc ses fichiers ont fini de charger avant les nôtres —
-- l'essai direct devrait suffire. Un repli existe quand même au cas où.
if not TryRegisterReminderCallback() then
    C_Timer.After(3, TryRegisterReminderCallback)
end
