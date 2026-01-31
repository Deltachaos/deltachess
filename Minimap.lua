-- Minimap.lua - Minimap button

DeltaChess.Minimap = {}

local minimapButton

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
    minimapButton:RegisterForClicks("AnyUp")
    minimapButton:RegisterForDrag("LeftButton")
    
    -- Icon
    local icon = minimapButton:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Toy_07")
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
            if UnitExists("target") and UnitIsPlayer("target") then
                local targetName = DeltaChess:GetFullPlayerName(UnitName("target"))
                DeltaChess:ShowChallengeWindow(targetName)
            else
                DeltaChess:Print("Right-click: Challenge your current target")
            end
        end
    end)
    
    -- Tooltip
    minimapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cFF33FF99DeltaChess|r")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cFFFFFFFFLeft-click:|r Open menu", 1, 1, 1)
        GameTooltip:AddLine("|cFFFFFFFFRight-click:|r Challenge target", 1, 1, 1)
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
        
        -- Show statistics
        if DeltaChess.db and DeltaChess.db.statistics then
            local stats = DeltaChess.db.statistics
            local winRate = stats.totalGames > 0 and (stats.wins / stats.totalGames * 100) or 0
            GameTooltip:AddLine(string.format("Games: %d | Win Rate: %.0f%%", stats.totalGames, winRate), 0.7, 0.7, 0.7)
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
end

-- Update button position
function DeltaChess.Minimap:UpdatePosition()
    if not minimapButton then return end
    
    local angle = DeltaChess.db.minimap.angle or 220
    local x = math.cos(angle)
    local y = math.sin(angle)
    
    x = x * 80
    y = y * 80
    
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
