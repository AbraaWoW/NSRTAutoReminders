local ADDON_NAME, EP = ...
local L = setmetatable({}, { __index = function(_, k) return (EP.L or {})[k] or k end })

--[[----------------------------------------------------------------------
  NSRT AutoReminders — Bouton minimap

  Implémentation autonome : pas de LibDataBroker ni de LibDBIcon à
  embarquer. Le bouton se place sur le cercle de la minimap, se déplace
  par glisser-déposer et mémorise son angle dans les SavedVariables.

  Le bouton est optionnel : /autoreminders minimap pour l'afficher ou le
  masquer.
------------------------------------------------------------------------]]

local MEDIA = "Interface\\AddOns\\NSRTAutoReminders\\Media\\"
local RADIUS = 80          -- rayon du placement autour de la minimap
local DEFAULT_ANGLE = 205  -- en degrés, en bas à gauche : zone peu encombrée

local button

-- math.atan2 existe en Lua 5.1 (la version utilisée par WoW) mais a été
-- retiré des versions plus récentes : on prévoit le repli.
local atan2 = math.atan2 or function(y, x)
    if x > 0 then return math.atan(y / x) end
    if x < 0 then return math.atan(y / x) + (y >= 0 and math.pi or -math.pi) end
    return y >= 0 and (math.pi / 2) or -(math.pi / 2)
end

local function DB()
    NSRTAutoRemindersDB = NSRTAutoRemindersDB or {}
    NSRTAutoRemindersDB.minimap = NSRTAutoRemindersDB.minimap or {}
    return NSRTAutoRemindersDB.minimap
end

local function UpdatePosition()
    if not button then return end
    local angle = math.rad(DB().angle or DEFAULT_ANGLE)
    button:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(angle) * RADIUS, math.sin(angle) * RADIUS)
end

local function OnUpdateDragging(self)
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    px, py = px / scale, py / scale
    DB().angle = math.deg(atan2(py - my, px - mx)) % 360
    UpdatePosition()
end

local function CreateButton()
    local b = CreateFrame("Button", "NSRTAutoRemindersMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetMovable(true)

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT", 0, 0)

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(25, 25)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("CENTER", 0, 1)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(19, 19)
    icon:SetPoint("CENTER", 0, 1)
    -- Icône de l'addon si elle est présente, sinon une icône générique :
    -- SetTexture sur un fichier absent laisse GetTexture() à nil.
    icon:SetTexture(MEDIA .. "icon.tga")
    if not icon:GetTexture() then
        icon:SetTexture("Interface\\Icons\\Spell_Holy_BorrowedTime")
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    b.icon = icon

    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", OnUpdateDragging)
        GameTooltip:Hide()
    end)
    b:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    b:SetScript("OnClick", function()
        if EP.ToggleMainWindow then EP.ToggleMainWindow() end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cFF33CCFFNSRT|r AutoReminders")
        GameTooltip:AddLine("|cFF888888v" .. (EP.GetVersion and EP.GetVersion() or "?") .. "|r")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Left-click: open"], 1, 1, 1)
        GameTooltip:AddLine(L["Drag: move the button"], 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return b
end

function EP.UpdateMinimapButton()
    if DB().hide then
        if button then button:Hide() end
        return
    end
    if not button then
        button = CreateButton()
    end
    UpdatePosition()
    button:Show()
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    EP.UpdateMinimapButton()
end)
