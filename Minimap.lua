-- Minimap.lua - Minimap button

DeltaChess.Minimap = {}

local minimapButton
local STATUS = {
    ACTIVE = DeltaChess.Constants.STATUS_ACTIVE,
}

-- Detect WoW version for compatibility (with nil checks for older clients)
local isRetail = WOW_PROJECT_ID and WOW_PROJECT_MAINLINE and (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)

-- Initialize minimap button
function DeltaChess.Minimap:Initialize()
    if minimapButton then return end
    
    if not DeltaChess.db.minimap then
        DeltaChess.db.minimap = {
            hide = not DeltaChess.db.settings.showMinimapButton,
            angle = 220
        }
    end
    
    -- Create minimap button
    minimapButton = CreateFrame("Button", "DeltaChessMinimapButton", Minimap)
    minimapButton:SetSize(31, 31)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetFrameLevel(8)
    
    -- RegisterForClicks: Use explicit button types for Classic compatibility
    if isRetail then
        minimapButton:RegisterForClicks("AnyUp")
    else
        minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end
    minimapButton:RegisterForDrag("LeftButton")
    minimapButton:SetMovable(true)
    
    -- Icon (use .tga extension explicitly for Classic compatibility)
    local icon = minimapButton:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture("Interface\\AddOns\\DeltaChess\\Textures\\logo_small.tga")
    minimapButton.icon = icon
    
    -- Border
    local overlay = minimapButton:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")
    minimapButton.overlay = overlay
    
    -- Highlight
    minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- Click handler
    minimapButton:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            DeltaChess:ShowMainMenu()
        elseif button == "RightButton" then
            -- Resume most recent active game
            local mostRecentId, mostRecentTime = nil, 0
            if DeltaChess.db and DeltaChess.db.games then
                for gameId, board in pairs(DeltaChess.db.games) do
                    local status = board:GetGameStatus()
                    local startTime = board:GetStartTime() or 0
                    if status == STATUS.ACTIVE and startTime > mostRecentTime then
                        mostRecentId = gameId
                        mostRecentTime = startTime
                    end
                end
            end
            if mostRecentId then
                DeltaChess:ShowChessBoard(mostRecentId)
            else
                DeltaChess:ShowMainMenu()
            end
        end
    end)
    
    -- Tooltip
    minimapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cFF33FF99DeltaChess|r")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cFFFFFFFFLeft-click:|r Open menu", 1, 1, 1)
        GameTooltip:AddLine("|cFFFFFFFFRight-click:|r Resume most recent game", 1, 1, 1)
        GameTooltip:AddLine(" ")
        
        -- Show active games
        local activeCount = 0
        if DeltaChess.db and DeltaChess.db.games then
            for _ in pairs(DeltaChess.db.games) do
                activeCount = activeCount + 1
            end
        end
        
        if activeCount > 0 then
            GameTooltip:AddLine(string.format("|cFF00FF00Active Games:|r %d", activeCount), 1, 1, 1)
        end
        if DeltaChess:IsMyTurnInAnyGame() then
            GameTooltip:AddLine("|cFF00FF00Your turn!|r", 1, 1, 1)
        end
        if DeltaChess.db and DeltaChess.db.settings and DeltaChess.db.settings.dnd then
            GameTooltip:AddLine("|cFFFF0000Do Not Disturb|r", 1, 1, 1)
        end
        
        GameTooltip:Show()
    end)
    
    minimapButton:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    -- Drag handler
    minimapButton:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        self.isMouseDown = true
        self:SetScript("OnUpdate", function(self)
            local mx, my = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            mx = mx / scale
            my = my / scale
            
            local cx, cy = Minimap:GetCenter()
            local angle = math.atan2(my - cy, mx - cx)
            DeltaChess.db.minimap.angle = angle
            DeltaChess.Minimap:UpdatePosition()
        end)
    end)
    
    minimapButton:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self.isMouseDown = false
        self:UnlockHighlight()
    end)
    
    self:UpdatePosition()
    
    if DeltaChess.db.settings.showMinimapButton then
        minimapButton:Show()
    else
        minimapButton:Hide()
    end
    
    self:UpdateDNDHighlight()

    -- Periodically update "your turn" highlight (with fallback for Classic compatibility)
    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(2, function()
            DeltaChess.Minimap:UpdateYourTurnHighlight()
        end)
    else
        -- Fallback: create a separate frame for updates (avoids conflicts with drag OnUpdate)
        local updateFrame = CreateFrame("Frame")
        local elapsed = 0
        updateFrame:SetScript("OnUpdate", function(self, delta)
            elapsed = elapsed + delta
            if elapsed >= 2 then
                elapsed = 0
                DeltaChess.Minimap:UpdateYourTurnHighlight()
            end
        end)
    end
end

-- Use .tga extension explicitly for Classic compatibility
local ICON_NORMAL = "Interface\\AddOns\\DeltaChess\\Textures\\logo_small.tga"
local ICON_GREEN  = "Interface\\AddOns\\DeltaChess\\Textures\\logo_green.tga"
local ICON_RED    = "Interface\\AddOns\\DeltaChess\\Textures\\logo_red.tga"

-- Update minimap icon texture (green = your turn has priority over red = DND)
function DeltaChess.Minimap:UpdateYourTurnHighlight()
    if not minimapButton or not minimapButton.icon then return end
    if not minimapButton:IsShown() then return end
    local myTurn = DeltaChess:IsMyTurnInAnyGame()
    local dnd = DeltaChess.db and DeltaChess.db.settings and DeltaChess.db.settings.dnd
    local tex
    if myTurn then
        tex = ICON_GREEN
    elseif dnd then
        tex = ICON_RED
    else
        tex = ICON_NORMAL
    end
    minimapButton.icon:SetTexture(tex)
end

-- Update minimap highlight (DND); green (your turn) always has priority
function DeltaChess.Minimap:UpdateDNDHighlight()
    self:UpdateYourTurnHighlight()
end

-- Update button position
function DeltaChess.Minimap:UpdatePosition()
    if not minimapButton then return end
    
    local angle = DeltaChess.db.minimap.angle or 220
    local x = math.cos(angle)
    local y = math.sin(angle)
    
    -- Use larger radius for Retail, smaller for Classic (minimap is smaller)
    local radius = isRetail and 105 or 80
    x = x * radius
    y = y * radius
    
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Show minimap button
function DeltaChess.Minimap:Show()
    if minimapButton then
        DeltaChess.db.minimap.hide = false
        minimapButton:Show()
    end
end

-- Hide minimap button
function DeltaChess.Minimap:Hide()
    if minimapButton then
        DeltaChess.db.minimap.hide = true
        minimapButton:Hide()
    end
end

-- Toggle minimap button
function DeltaChess.Minimap:Toggle()
    if DeltaChess.db.minimap.hide then
        self:Show()
    else
        self:Hide()
    end
end
