-- Core.lua - Main addon initialization and slash commands

DeltaChess = DeltaChess or {}
DeltaChess.version = "1.0.0"

-- Local reference for constants (set after Constants loads)
local COLOR
local STATUS

-- Helper: create a repeating timer with Classic compatibility fallback
-- Returns the ticker handle (C_Timer ticker or a Frame for the OnUpdate fallback)
function DeltaChess.CreateTicker(intervalSeconds, callback)
    if C_Timer and C_Timer.NewTicker then
        return C_Timer.NewTicker(intervalSeconds, callback)
    end
    -- Classic fallback: use an OnUpdate frame
    local frame = CreateFrame("Frame")
    local elapsed = 0
    frame:SetScript("OnUpdate", function(self, delta)
        elapsed = elapsed + delta
        if elapsed >= intervalSeconds then
            elapsed = 0
            callback()
        end
    end)
    return frame
end

-- Frame for events
local eventFrame = CreateFrame("Frame")

-- UI Frames storage
DeltaChess.frames = {}

-- Initialize the addon
local function Initialize()
    -- Set local reference to constants now that all files are loaded
    COLOR = DeltaChess.Constants.COLOR
    STATUS = {
        ACTIVE = DeltaChess.Constants.STATUS_ACTIVE,
        PAUSED = DeltaChess.Constants.STATUS_PAUSED,
        ENDED = DeltaChess.Constants.STATUS_ENDED,
    }
    
    -- Initialize saved variables
    if not ChessDB then
        ChessDB = {
            games = {},
            history = {},
            settings = {
                showMinimapButton = true,
                dnd = false,
                boardMinimized = false,
                boardPosition = nil  -- { point, relativePoint, x, y } from GetPoint(1), relative to UIParent
            }
        }
    end
    if ChessDB.settings.dnd == nil then
        ChessDB.settings.dnd = false
    end
    if ChessDB.settings.boardMinimized == nil then
        ChessDB.settings.boardMinimized = false
    end
    
    -- Version check: if no version exists, clear games and history (old database format)
    if not ChessDB.version then
        ChessDB.games = {}
        ChessDB.history = {}
    end
    
    -- Save current addon version
    ChessDB.version = DeltaChess.version
    
    DeltaChess.db = ChessDB

    -- Register slash commands (slash names unchanged)
    SLASH_CHESS1 = "/chess"
    SlashCmdList["CHESS"] = function(msg)
        DeltaChess:SlashCommand(msg)
    end
    
    -- Register addon messages
    C_ChatInfo.RegisterAddonMessagePrefix("ChessChallenge")
    C_ChatInfo.RegisterAddonMessagePrefix("ChessMove")
    C_ChatInfo.RegisterAddonMessagePrefix("ChessResponse")
    C_ChatInfo.RegisterAddonMessagePrefix("ChessResign")
    C_ChatInfo.RegisterAddonMessagePrefix("ChessDraw")
    C_ChatInfo.RegisterAddonMessagePrefix("ChessAck")
    C_ChatInfo.RegisterAddonMessagePrefix("ChessPing")
    C_ChatInfo.RegisterAddonMessagePrefix("ChessPause")
    C_ChatInfo.RegisterAddonMessagePrefix("ChessUnpause")
    
    -- Register for addon messages
    eventFrame:RegisterEvent("CHAT_MSG_ADDON")
    eventFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "CHAT_MSG_ADDON" then
            DeltaChess:OnCommReceived(...)
        end
    end)
    
    -- Restore metatables for saved games
    DeltaChess:RestoreSavedGames()
    
    DeltaChess:Print("DeltaChess addon loaded! Use /chess to challenge a player or /chess menu to open settings.")
    
    -- Initialize minimap button after a short delay
    C_Timer.After(1, function()
        if DeltaChess.Minimap then
            DeltaChess.Minimap:Initialize()
        end
    end)

    -- Periodic ticker: archive ended games and update minimap highlight
    DeltaChess.CreateTicker(2, function()
        -- Move ended games from db.games to history
        if DeltaChess.db and DeltaChess.db.games then
            for gameId, board in pairs(DeltaChess.db.games) do
                if board:IsEnded() then
                    -- Update the frame before saving (which removes the board)
                    if DeltaChess.UI and DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId then
                        DeltaChess.UI:UpdateBoard(DeltaChess.UI.activeFrame)
                    end
                    DeltaChess:SaveGameToHistory(board)
                end
            end
        end

        -- Update minimap your-turn highlight
        if DeltaChess.Minimap and DeltaChess.Minimap.UpdateYourTurnHighlight then
            DeltaChess.Minimap:UpdateYourTurnHighlight()
        end
    end)
end

-- Restore board metatables for saved games after addon reload
function DeltaChess:RestoreSavedGames()
    if not self.db or not self.db.games then return end
    
    for gameId, board in pairs(self.db.games) do
        -- Board IS the game - restore metatable directly
        if board and not getmetatable(board) then
            -- Restore the board metatable using the Board prototype
            setmetatable(board, DeltaChess.Board.Prototype)
            
            -- Ensure the board has all required data structures
            if not board.moves then
                board.moves = {}
            end
            if not board.gameMeta then
                board.gameMeta = {}
            end
            -- Ensure board has started (for old saved games)
            if not board:GetStartTime() then
                board:StartGame()
            end
            -- Ensure board has its ID stored
            if not board:GetGameMeta("id") then
                board:SetGameMeta("id", gameId)
            end
        end
    end
end

-- Print function
function DeltaChess:Print(msg)
    print("|cFF33FF99DeltaChess:|r " .. tostring(msg))
end

-- Load on player login
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        Initialize()
    end
end)

-- Slash command handler
function DeltaChess:SlashCommand(input)
    local command = strtrim(input or "")
    
    if command == "" then
        -- Challenge target
        if UnitExists("target") and UnitIsPlayer("target") then
            local targetName = self:GetFullPlayerName(UnitName("target"))
            self:ShowChallengeWindow(targetName)
        else
            self:ShowMainMenu()
        end
    elseif command == "menu" or command == "help" then
        self:ShowMainMenu()
    elseif command == "games" or command == STATUS.ACTIVE then
        self:ShowActiveGames()
    elseif command == "history" then
        self:ShowGameHistory()
    elseif command == "settings" then
        self:ShowSettings()
    elseif command == "minimap" then
        self.db.settings.showMinimapButton = not self.db.settings.showMinimapButton
        if self.db.settings.showMinimapButton then
            DeltaChess.Minimap:Show()
            self:Print("Minimap button enabled")
        else
            DeltaChess.Minimap:Hide()
            self:Print("Minimap button disabled")
        end
    elseif command == "computer" or command == "ai" or command == "cpu" then
        self:ShowComputerGameWindow()
    elseif command:find("-") then
        -- Player-realm notation
        self:ShowChallengeWindow(command)
    else
        -- Try to find player on same realm
        local playerName = command .. "-" .. GetRealmName()
        self:ShowChallengeWindow(playerName)
    end
end

-- Get full player name with realm
function DeltaChess:GetFullPlayerName(name)
    if not name:find("-") then
        return name .. "-" .. GetRealmName()
    end
    return name
end

-- Check if it's the player's turn in any active game
function DeltaChess:IsMyTurnInAnyGame()
    if not self.db or not self.db.games then return false end
    local playerName = self:GetFullPlayerName(UnitName("player"))
    for _, board in pairs(self.db.games) do
        if board:IsActive() then
            local currentTurn = board:GetCurrentTurn()
            local isPlayerTurn
            local isVsComputer = board:OneOpponentIsEngine()
            if isVsComputer then
                local playerColor = board:GetPlayerColor() or COLOR.WHITE
                isPlayerTurn = (currentTurn == playerColor)
            else
                local white = board:GetWhitePlayerName()
                local black = board:GetBlackPlayerName()
                isPlayerTurn = (white == playerName and currentTurn == COLOR.WHITE) or
                              (black == playerName and currentTurn == COLOR.BLACK)
            end
            if isPlayerTurn then return true end
        end
    end
    return false
end

-- Common: notify user that opponent moved and it's their turn (human or computer)
function DeltaChess:NotifyItIsYourTurn(gameId, opponentDisplayName)
    local board = DeltaChess.GetBoard(gameId)
    if not board then return end
    if not board:IsActive() then return end
    
    local lastMove = board:GetLastMove()
    local moveNotation = lastMove and DeltaChess.UI:FormatMoveAlgebraic(lastMove) or ""
    if moveNotation ~= "" then
        self:Print(opponentDisplayName .. " played " .. moveNotation .. " - it's your turn!")
    else
        self:Print(opponentDisplayName .. " made their move - it's your turn!")
    end
    
    if DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId then
        -- Animate the opponent's move
        DeltaChess.UI:UpdateBoardAnimated(DeltaChess.UI.activeFrame, true)
    end
    
    if DeltaChess.Minimap and DeltaChess.Minimap.UpdateYourTurnHighlight then
        DeltaChess.Minimap:UpdateYourTurnHighlight()
    end
    
    -- Sound is now handled by the Sound module in HandleOpponentMove/ChessAI
end

--------------------------------------------------------------------------------
-- MAIN MENU WINDOW
--------------------------------------------------------------------------------
function DeltaChess:ShowMainMenu()
    -- Close existing menu if open
    if self.frames.mainMenu and self.frames.mainMenu:IsShown() then
        self.frames.mainMenu:Hide()
        return
    end
    
    -- Create main menu frame if it doesn't exist
    if not self.frames.mainMenu then
        local frame = CreateFrame("Frame", "ChessMainMenu", UIParent, "BasicFrameTemplateWithInset")
        frame:SetSize(460, 560)
        frame:SetPoint("CENTER")
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        frame:SetFrameStrata("DIALOG")
        frame:SetFrameLevel(100)
        frame.TitleText:SetText("DeltaChess (by Deltachaos)")
        
        -- Game History title
        local historyTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        historyTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -35)
        historyTitle:SetText("Game History")
        
        -- Support & License button (aligned right)
        local supportBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        supportBtn:SetSize(120, 22)
        supportBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -15, -32)
        supportBtn:SetText("Support & License")
        supportBtn:SetScript("OnClick", function()
            DeltaChess:ShowSupportDialog()
        end)
        
        -- History scroll frame
        local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", historyTitle, "BOTTOMLEFT", 0, -10)
        scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -40, 110)
        
        local scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetSize(400, 1)
        scrollFrame:SetScrollChild(scrollChild)
        frame.scrollChild = scrollChild
        
        -- DND checkbox (above bottom buttons)
        local dndCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        dndCheck:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 75)
        dndCheck.text:SetText("Do Not Disturb (no challenge popups)")
        dndCheck:SetChecked(DeltaChess.db.settings.dnd)
        dndCheck:SetScript("OnClick", function(self)
            DeltaChess.db.settings.dnd = self:GetChecked()
            if DeltaChess.Minimap and DeltaChess.Minimap.UpdateDNDHighlight then
                DeltaChess.Minimap:UpdateDNDHighlight()
            end
        end)
        frame.dndCheck = dndCheck
        
        -- Challenge Player button (above blingtron ad)
        local challengeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        challengeBtn:SetSize(211, 28)
        challengeBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 15, 42)
        challengeBtn:SetText("Challenge Player")
        challengeBtn:SetScript("OnClick", function()
            frame:Hide()
            DeltaChess:ShowChallengeWindow()
        end)
        
        -- Play vs Computer button
        local computerBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        computerBtn:SetSize(211, 28)
        computerBtn:SetPoint("LEFT", challengeBtn, "RIGHT", 8, 0)
        computerBtn:SetText("Play vs Computer")
        computerBtn:SetScript("OnClick", function()
            frame:Hide()
            DeltaChess:ShowComputerGameWindow()
        end)
        
        -- Blingtron.app advertisement (very bottom, below buttons)
        local blingtronBg = frame:CreateTexture(nil, "BACKGROUND")
        blingtronBg:SetColorTexture(0.1, 0.15, 0.2, 0.8)
        blingtronBg:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 10)
        blingtronBg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 10)
        blingtronBg:SetHeight(36)
        
        local blingtronText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        blingtronText:SetPoint("CENTER", blingtronBg, "CENTER", 0, 0)
        blingtronText:SetText("|cFF00BFFFSponsored by: |r|cFFFFFFFFhttps://blingtron.app|r - Discord bot for weekly vault & raid reminders")
        blingtronText:SetJustifyH("CENTER")
        blingtronText:SetWidth(430)
        
        self.frames.mainMenu = frame
    end
    
    -- Refresh the content
    self:RefreshMainMenuContent()
    
    self.frames.mainMenu:Show()
end

-- Support dialog with copyable links
function DeltaChess:ShowSupportDialog()
    if not self.frames.supportDialog then
        local PATREON_URL = "https://patreon.com/c/blingtronapp"
        local GITHUB_URL = "https://github.com/Deltachaos/deltachess"
        
        local frame = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
        frame:SetSize(440, 500)
        frame:SetPoint("CENTER")
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        frame:SetFrameStrata("DIALOG")
        frame:SetFrameLevel(200)
        frame.TitleText:SetText("DeltaChess - Support & License")
        
        local thankYou = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        thankYou:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -40)
        thankYou:SetText("Thank you for playing DeltaChess! Your support is greatly appreciated.")
        thankYou:SetWidth(400)
        
        local desc = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        desc:SetPoint("TOPLEFT", thankYou, "BOTTOMLEFT", 0, -10)
        desc:SetText("Support me on Patreon or check out my other wow project:")
        desc:SetWidth(400)

        local blingtron = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        blingtron:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -10)
        blingtron:SetText("|r|cFF00BFFFhttps://blingtron.app|r - Discord bot for weekly vault & raid reminders")
        blingtron:SetWidth(400)
        
        -- Patreon label
        local patreonLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        patreonLabel:SetPoint("TOPLEFT", blingtron, "BOTTOMLEFT", 0, -10)
        patreonLabel:SetText("|cFF00BFFFPatreon:|r")
        
        -- Patreon EditBox (read-only, selectable for copy)
        local patreonEdit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
        patreonEdit:SetSize(360, 22)
        patreonEdit:SetPoint("TOPLEFT", patreonLabel, "BOTTOMLEFT", 0, -4)
        patreonEdit:SetAutoFocus(false)
        patreonEdit:SetText(PATREON_URL)
        patreonEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        patreonEdit:SetScript("OnEditFocusLost", function(self) self:SetText(PATREON_URL) end)
        patreonEdit:SetScript("OnChar", function(self) self:SetText(PATREON_URL) end)
        
        -- GitHub label
        local githubLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        githubLabel:SetPoint("TOPLEFT", patreonEdit, "BOTTOMLEFT", 0, -15)
        githubLabel:SetText("|cFF00BFFFGitHub:|r")
        
        -- GitHub EditBox
        local githubEdit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
        githubEdit:SetSize(360, 22)
        githubEdit:SetPoint("TOPLEFT", githubLabel, "BOTTOMLEFT", 0, -4)
        githubEdit:SetAutoFocus(false)
        githubEdit:SetText(GITHUB_URL)
        githubEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        githubEdit:SetScript("OnEditFocusLost", function(self) self:SetText(GITHUB_URL) end)
        githubEdit:SetScript("OnChar", function(self) self:SetText(GITHUB_URL) end)
        
        -- Chess Engines credits
        local enginesTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        enginesTitle:SetPoint("TOPLEFT", githubEdit, "BOTTOMLEFT", 0, -15)
        enginesTitle:SetText("|cFF00BFFFChess Engines:|r")
        
        local enginesCredits = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        enginesCredits:SetPoint("TOPLEFT", enginesTitle, "BOTTOMLEFT", 0, -5)
        enginesCredits:SetWidth(400)
        enginesCredits:SetJustifyH("LEFT")
        
        -- Build engine credits from registered engines
        local creditLines = {}
        for _, engine in pairs(DeltaChess.Engines.Registry or {}) do
            local line = engine.name or engine.id
            if engine.author then
                line = line .. " by " .. engine.author
            end
            if engine.portedBy then
                line = line .. " (Lua port: " .. engine.portedBy .. ")"
            end
            if engine.license then
                line = line .. " - " .. engine.license
            end
            if engine.url then
                line = line .. "\n    " .. engine.url .. "\n"
            end
            table.insert(creditLines, line)
        end
        table.sort(creditLines)
        enginesCredits:SetText(table.concat(creditLines, "\n"))
        
        -- Chess piece artwork (below engines list)
        local artworkLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        artworkLabel:SetPoint("TOPLEFT", enginesCredits, "BOTTOMLEFT", 0, -15)
        artworkLabel:SetText("|cFF00BFFFChess piece artwork:|r By Cburnett (Wikimedia Commons), CC BY-SA 3.0.")
        artworkLabel:SetJustifyH("LEFT")

        -- License (below artwork)
        local licenseLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        licenseLabel:SetPoint("TOPLEFT", artworkLabel, "BOTTOMLEFT", 0, -5)
        licenseLabel:SetText("|cFF00BFFFLicense:|r GNU GPL v3.0.")
        licenseLabel:SetJustifyH("LEFT")

        -- OK button
        local okBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        okBtn:SetSize(100, 28)
        okBtn:SetPoint("BOTTOM", frame, "BOTTOM", 0, 15)
        okBtn:SetText("OK")
        okBtn:SetScript("OnClick", function()
            frame:Hide()
        end)
        
        frame:SetScript("OnHide", function()
            patreonEdit:ClearFocus()
            githubEdit:ClearFocus()
        end)
        frame:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                self:Hide()
            end
        end)
        frame:EnableKeyboard(true)
        
        self.frames.supportDialog = frame
    end
    
    self.frames.supportDialog:Show()
end

-- Refresh just the main menu content (without showing/hiding window)
function DeltaChess:RefreshMainMenuContent()
    if not self.frames.mainMenu then return end
    
    if self.frames.mainMenu.dndCheck then
        self.frames.mainMenu.dndCheck:SetChecked(self.db.settings.dnd)
    end
    
    -- Update history
    local scrollChild = self.frames.mainMenu.scrollChild
    
    -- Clear old entries (frames)
    for _, child in ipairs({scrollChild:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    
    -- Clear old FontStrings/textures (regions)
    for _, region in ipairs({scrollChild:GetRegions()}) do
        region:Hide()
        region:SetParent(nil)
    end
    
    -- Collect all boards (active + history deserialized)
    local allBoards = {}
    
    -- Add active game boards
    for _, board in pairs(self.db.games) do
        table.insert(allBoards, board)
    end
    
    -- Add history boards (deserialized; already have _endTime from serialization)
    for _, entry in pairs(self.db.history) do
        local board = self:DeserializeHistoryEntry(entry)
        if board then
            table.insert(allBoards, board)
        end
    end
    
    -- Sort by start time (newest first)
    table.sort(allBoards, function(a, b)
        return (a:GetStartTime() or 0) > (b:GetStartTime() or 0)
    end)
    
    -- Helper to compute player color and turn status
    local playerName = self:GetFullPlayerName(UnitName("player"))
    local function getPlayerInfo(board)
        local isVsComputer = board:OneOpponentIsEngine()
        local white = board:GetWhitePlayerName()
        local black = board:GetBlackPlayerName()
        local storedPlayerColor = board:GetPlayerColor()
        local currentTurn = board:GetCurrentTurn()
        local playerColor
        
        if isVsComputer then
            playerColor = storedPlayerColor
        else
            if white == playerName then
                playerColor = COLOR.WHITE
            elseif black == playerName then
                playerColor = COLOR.BLACK
            end
        end
        
        local isPlayerTurn = (currentTurn == playerColor)
        return playerColor, isPlayerTurn, currentTurn
    end
    
    -- Add entries
    local yOffset = 0
    if #allBoards == 0 then
        local noHistory = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        noHistory:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
        noHistory:SetText("No games played yet")
        noHistory:SetTextColor(0.5, 0.5, 0.5)
    else
        local displayCount = math.min(#allBoards, 30)
        for i = 1, displayCount do
            local board = allBoards[i]
            local gameId = board:GetGameMeta("id")
            local isActive = board:IsActive()
            local isPaused = board:IsPaused()
            local isVsComputer = board:OneOpponentIsEngine()
            local white = board:GetWhitePlayerName()
            local black = board:GetBlackPlayerName()
            local settings = board:GetGameMeta("settings")
            local computerEngine = board:GetEngineId()
            local computerDifficulty = board:GetEngineElo()
            local moveCount = board:GetHalfMoveCount()
            local result = board:GetGameResult()
            local gameDate = board:GetStartDateString()
            
            local playerColor, isPlayerTurn, _ = getPlayerInfo(board)
            local windowShown = DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId and DeltaChess.UI.activeFrame:IsShown()
            
            local entry = CreateFrame("Button", nil, scrollChild)
            entry:SetSize(400, 72)
            entry:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
            
            -- Background
            local bg = entry:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            if isActive or isPaused then
                if isPaused then
                    bg:SetColorTexture(0.2, 0.2, 0.0, 0.7) -- Yellow tint - paused
                elseif isPlayerTurn then
                    bg:SetColorTexture(0.0, 0.3, 0.0, 0.7) -- Bright green - your turn
                else
                    bg:SetColorTexture(0.1, 0.15, 0.1, 0.6) -- Dim green - waiting
                end
            elseif i % 2 == 0 then
                bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)
            else
                bg:SetColorTexture(0.15, 0.15, 0.15, 0.5)
            end
            
            -- Game info (opponents with class colors)
            local info = entry:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            info:SetPoint("TOPLEFT", entry, "TOPLEFT", 5, -4)
            info:SetText(DeltaChess.UI:FormatGameTitle(board))
            
            -- Date line
            local dateText = entry:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            dateText:SetPoint("TOPLEFT", info, "BOTTOMLEFT", 0, -1)
            dateText:SetText("|cFFAAAAAADate: " .. (gameDate or "Unknown") .. "|r")
            
            -- Settings line (color, clock, difficulty)
            local settingsText = entry:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            settingsText:SetPoint("TOPLEFT", dateText, "BOTTOMLEFT", 0, -1)
            
            local settingsParts = {}
            if playerColor then
                table.insert(settingsParts, "You: " .. playerColor)
            end
            if isVsComputer and computerDifficulty then
                local d = computerDifficulty
                local diffStr = type(d) == "number" and (tostring(d) .. " ELO") or "~1200 ELO"
                table.insert(settingsParts, "AI: " .. diffStr)
            end
            if settings then
                if settings.useClock then
                    table.insert(settingsParts, string.format("Clock: %dm +%ds", 
                        settings.timeMinutes or 10, 
                        settings.incrementSeconds or 0))
                else
                    table.insert(settingsParts, "No clock")
                end
            end
            settingsText:SetText("|cFFAAAAAA" .. table.concat(settingsParts, " | ") .. "|r")
            
            -- Status/Result line
            local statusText = entry:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            statusText:SetPoint("TOPLEFT", settingsText, "BOTTOMLEFT", 0, -1)
            local resultStr = DeltaChess.UI:GetGameStatusText(board, playerColor)
            statusText:SetText(string.format("%s - %d moves", resultStr, moveCount))
            
            -- Buttons
            if isActive or isPaused then
                local isHumanWindowHidden = not isVsComputer and not windowShown
                local btnText, btnAction
                if isPaused and not isVsComputer then
                    btnText = "Resume"
                    btnAction = function()
                        self.frames.mainMenu:Hide()
                        DeltaChess:RequestUnpause(gameId)
                        DeltaChess:ShowChessBoard(gameId)
                    end
                elseif isHumanWindowHidden and not isPaused then
                    btnText = "Open"
                    btnAction = function()
                        self.frames.mainMenu:Hide()
                        DeltaChess:ShowChessBoard(gameId)
                    end
                else
                    btnText = "Resume"
                    btnAction = function()
                        self.frames.mainMenu:Hide()
                        DeltaChess:ShowChessBoard(gameId)
                    end
                end
                local resumeBtn = CreateFrame("Button", nil, entry, "UIPanelButtonTemplate")
                resumeBtn:SetSize(60, 22)
                resumeBtn:SetPoint("RIGHT", entry, "RIGHT", -5, 0)
                resumeBtn:SetText(btnText)
                resumeBtn:SetScript("OnClick", btnAction)
                
                local resignBtn = CreateFrame("Button", nil, entry, "UIPanelButtonTemplate")
                resignBtn:SetSize(55, 22)
                resignBtn:SetPoint("RIGHT", resumeBtn, "LEFT", -3, 0)
                resignBtn:SetText("Resign")
                resignBtn:SetScript("OnClick", function()
                    DeltaChess._resignConfirmGameId = gameId
                    DeltaChess.UI:ShowGamePopup(gameId, "CHESS_RESIGN_CONFIRM", nil, gameId)
                    DeltaChess:RefreshMainMenuContent()
                end)
                
                -- PGN button for active/paused games
                local pgnBtn = CreateFrame("Button", nil, entry, "UIPanelButtonTemplate")
                pgnBtn:SetSize(40, 22)
                pgnBtn:SetPoint("RIGHT", resignBtn, "LEFT", -3, 0)
                pgnBtn:SetText("PGN")
                pgnBtn:SetScript("OnClick", function()
                    DeltaChess:ShowPGNWindow(board)
                end)
            else
                -- Delete button for completed games
                local deleteBtn = CreateFrame("Button", nil, entry, "UIPanelButtonTemplate")
                deleteBtn:SetSize(22, 22)
                deleteBtn:SetPoint("RIGHT", entry, "RIGHT", -5, 0)
                deleteBtn:SetText("X")
                deleteBtn:SetScript("OnClick", function()
                    DeltaChess:DeleteFromHistory(gameId)
                    DeltaChess:RefreshMainMenuContent() -- Refresh without closing
                end)
                
                -- Replay button for completed games
                local replayBtn = CreateFrame("Button", nil, entry, "UIPanelButtonTemplate")
                replayBtn:SetSize(55, 22)
                replayBtn:SetPoint("RIGHT", deleteBtn, "LEFT", -3, 0)
                replayBtn:SetText("Replay")
                replayBtn:SetScript("OnClick", function()
                    self.frames.mainMenu:Hide()
                    DeltaChess:ShowReplayWindow(board)
                end)
                
                -- PGN button for completed games
                local pgnBtn = CreateFrame("Button", nil, entry, "UIPanelButtonTemplate")
                pgnBtn:SetSize(40, 22)
                pgnBtn:SetPoint("RIGHT", replayBtn, "LEFT", -3, 0)
                pgnBtn:SetText("PGN")
                pgnBtn:SetScript("OnClick", function()
                    DeltaChess:ShowPGNWindow(board)
                end)
            end
            
            yOffset = yOffset + 74
        end
    end
    
    scrollChild:SetHeight(math.max(yOffset, 100))
end

--------------------------------------------------------------------------------
-- REPLAY WINDOW
--------------------------------------------------------------------------------
function DeltaChess:ShowReplayWindow(board)
    -- Close existing replay window
    if self.frames.replayWindow then
        self.frames.replayWindow:Hide()
    end
    
    local SQUARE_SIZE = 50
    local BOARD_SIZE = SQUARE_SIZE * 8
    local LABEL_SIZE = 20
    local PLAYER_BAR_HEIGHT = 45
    local RIGHT_PANEL_WIDTH = 220
    local CAPTURED_PIECE_SIZE = 18
    
    -- Get participant info using shared helper
    local participants = DeltaChess.UI:GetBoardParticipants(board)
    local myName = participants.myName
    local opponentName = participants.opponentName
    local myChessColor = participants.myChessColor
    local opponentChessColor = participants.opponentChessColor
    local myClass = participants.myClass
    local opponentClass = participants.opponentClass
    local flipBoard = participants.flipBoard
    -- Replay always shows time per side: clock if that side has one, else thinking time
    
    -- Create replay frame
    local totalWidth = LABEL_SIZE + BOARD_SIZE + 15 + RIGHT_PANEL_WIDTH + 15
    local totalHeight = 30 + PLAYER_BAR_HEIGHT + BOARD_SIZE + LABEL_SIZE + PLAYER_BAR_HEIGHT + 10
    
    local frame = CreateFrame("Frame", "ChessReplayFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(totalWidth, totalHeight)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(250)
    frame.TitleText:SetText("Replay")
    
    -- Flip board button in title bar (to the left of close button)
    local titleFlipBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    titleFlipBtn:SetSize(35, 22)
    titleFlipBtn:SetPoint("TOPRIGHT", frame.CloseButton, "TOPLEFT", 0, 0)
    titleFlipBtn:SetText("Flip")
    titleFlipBtn:SetScript("OnClick", function()
        frame.flipBoard = not frame.flipBoard
        DeltaChess.UI:RecreateBoardSquares(frame, false)
        DeltaChess.UI:UpdatePlayerBarLabels(frame)
        if frame.RefreshReplayDisplay then
            frame.RefreshReplayDisplay()
        end
    end)
    
    self.frames.replayWindow = frame
    
    -- Store replay state: full board (for GetBoardAtIndex) and move list for history/animation
    frame.replayBoard = board
    frame.moves = {}
    for i, moveData in ipairs(board:GetMoveHistory() or {}) do
        frame.moves[i] = DeltaChess.BoardMove.Wrap(moveData, nil, i)
    end
    frame.currentMoveIndex = 0
    frame.myChessColor = myChessColor
    frame.opponentChessColor = opponentChessColor
    
    local leftMargin = 10
    local topOffset = -30
    
    -- ==================== OPPONENT BAR (TOP) ====================
    local opponentBarInfo = DeltaChess.UI:CreatePlayerBar({
        parent = frame,
        anchorFrame = frame,
        anchorPoint = "TOPLEFT",
        anchorRelPoint = "TOPLEFT",
        offsetX = leftMargin,
        offsetY = topOffset,
        playerName = opponentName,
        playerClass = opponentClass,
        board = board,
        showClock = true,
        chessColor = opponentChessColor,
    })
    local opponentBar = opponentBarInfo.bar
    frame.topBarNameText = opponentBarInfo.nameText
    frame.topBarClock = opponentBarInfo.timeDisplay
    frame.topBarCapturedContainer = opponentBarInfo.capturedContainer
    frame.opponentCapturedContainer = opponentBarInfo.capturedContainer
    frame.opponentCapturedColor = myChessColor
    frame.opponentClock = opponentBarInfo.timeDisplay
    frame.opponentClockColor = opponentChessColor
    
    -- ==================== BOARD ====================
    local boardContainer = CreateFrame("Frame", nil, frame)
    boardContainer:SetSize(BOARD_SIZE + LABEL_SIZE, BOARD_SIZE + LABEL_SIZE)
    boardContainer:SetPoint("TOPLEFT", opponentBar, "BOTTOMLEFT", 0, 0)
    frame.boardContainer = boardContainer
    frame.flipBoard = flipBoard
    
    -- Create squares using shared function (non-interactive)
    frame.squares = DeltaChess.UI:CreateBoardSquares(boardContainer, SQUARE_SIZE, LABEL_SIZE, flipBoard, false)
    
    -- ==================== PLAYER BAR (BOTTOM) ====================
    local playerBarInfo = DeltaChess.UI:CreatePlayerBar({
        parent = frame,
        anchorFrame = boardContainer,
        anchorPoint = "TOPLEFT",
        anchorRelPoint = "BOTTOMLEFT",
        offsetX = 0,
        offsetY = 0,
        playerName = myName,
        playerClass = myClass,
        board = board,
        showClock = true,
        chessColor = myChessColor,
    })
    local playerBar = playerBarInfo.bar
    frame.bottomBarNameText = playerBarInfo.nameText
    frame.bottomBarClock = playerBarInfo.timeDisplay
    frame.bottomBarCapturedContainer = playerBarInfo.capturedContainer
    frame.playerCapturedContainer = playerBarInfo.capturedContainer
    frame.playerCapturedColor = opponentChessColor
    frame.playerClock = playerBarInfo.timeDisplay
    frame.playerClockColor = myChessColor
    
    -- ==================== RIGHT PANEL ====================
    local rightPanel = CreateFrame("Frame", nil, frame)
    rightPanel:SetSize(RIGHT_PANEL_WIDTH, PLAYER_BAR_HEIGHT + BOARD_SIZE + LABEL_SIZE + PLAYER_BAR_HEIGHT)
    rightPanel:SetPoint("TOPLEFT", opponentBar, "TOPRIGHT", 10, 0)
    
    -- Move history scroll frame
    local historyHeight = rightPanel:GetHeight() - 100
    local historyInfo = DeltaChess.UI:CreateMoveHistoryScroller({
        parent = rightPanel,
        width = RIGHT_PANEL_WIDTH,
        height = historyHeight,
        includeLabel = true,
    })
    frame.historyText = historyInfo.historyText
    
    -- Move counter / position label
    local moveLabel = rightPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    moveLabel:SetPoint("BOTTOMLEFT", rightPanel, "BOTTOMLEFT", 0, 60)
    moveLabel:SetText("Move: 0 / " .. #frame.moves)
    frame.moveLabel = moveLabel
    
    -- Navigation buttons row
    local buttonWidth = 50
    local buttonSpacing = 3
    
    local firstBtn = CreateFrame("Button", nil, rightPanel, "UIPanelButtonTemplate")
    firstBtn:SetSize(buttonWidth, 25)
    firstBtn:SetPoint("BOTTOMLEFT", rightPanel, "BOTTOMLEFT", 0, 30)
    firstBtn:SetText("|<<")
    
    local prevBtn = CreateFrame("Button", nil, rightPanel, "UIPanelButtonTemplate")
    prevBtn:SetSize(buttonWidth, 25)
    prevBtn:SetPoint("LEFT", firstBtn, "RIGHT", buttonSpacing, 0)
    prevBtn:SetText("<")
    
    local nextBtn = CreateFrame("Button", nil, rightPanel, "UIPanelButtonTemplate")
    nextBtn:SetSize(buttonWidth, 25)
    nextBtn:SetPoint("LEFT", prevBtn, "RIGHT", buttonSpacing, 0)
    nextBtn:SetText(">")
    
    local lastBtn = CreateFrame("Button", nil, rightPanel, "UIPanelButtonTemplate")
    lastBtn:SetSize(buttonWidth, 25)
    lastBtn:SetPoint("LEFT", nextBtn, "RIGHT", buttonSpacing, 0)
    lastBtn:SetText(">>|")
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, rightPanel, "UIPanelButtonTemplate")
    closeBtn:SetSize(RIGHT_PANEL_WIDTH, 25)
    closeBtn:SetPoint("BOTTOMLEFT", rightPanel, "BOTTOMLEFT", 0, 0)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function()
        frame:Hide()
    end)
    
    -- Update display function (animateMove: optional move to animate after rendering)
    local function UpdateReplayBoard(animateMove)
        -- Get board state at current move index (paused snapshot with same opponents/startTime/moves up to index)
        local snapshotBoard = frame.replayBoard:GetBoardAtIndex(frame.currentMoveIndex)
        
        -- Render the field using the snapshot board like the normal board (same rendering path)
        local lastMove = snapshotBoard:GetLastMove()
        DeltaChess.UI:RenderPieces(frame.squares, snapshotBoard, lastMove)
        
        -- Update move counter
        frame.moveLabel:SetText(string.format("Move: %d / %d", frame.currentMoveIndex, #frame.moves))
        
        -- Update move history with highlighting for current move
        local historyStr = DeltaChess.UI:FormatMoveHistoryText(frame.moves, frame.currentMoveIndex)
        frame.historyText:SetText(historyStr)
        
        -- Update captured pieces display from snapshot board
        local myAdvantage = snapshotBoard:CalculateMaterialAdvantage(myChessColor)
        local capturedByWhite = snapshotBoard:GetCapturedPiecesWhite()
        local capturedByBlack = snapshotBoard:GetCapturedPiecesBlack()
        local myCaptured = myChessColor == COLOR.WHITE and capturedByWhite or capturedByBlack
        local opponentCaptured = opponentChessColor == COLOR.WHITE and capturedByWhite or capturedByBlack
        DeltaChess.UI:UpdateCapturedPieces(frame.playerCapturedContainer, myCaptured,
            frame.playerCapturedColor, myAdvantage > 0 and myAdvantage or nil)
        DeltaChess.UI:UpdateCapturedPieces(frame.opponentCapturedContainer, opponentCaptured,
            frame.opponentCapturedColor, (-myAdvantage) > 0 and (-myAdvantage) or nil)
        
        -- Update time per side: remaining clock if that side has a clock, else thinking time
        if frame.playerClock or frame.opponentClock then
            local snapshotTime = (frame.currentMoveIndex == 0) and snapshotBoard:GetStartTime()
                or (frame.moves[frame.currentMoveIndex] and frame.moves[frame.currentMoveIndex]:GetTimestamp())
                or snapshotBoard:GetStartTime()
            if frame.playerClock then
                local myHasClock = (snapshotBoard:GetClock(myChessColor) or 0) > 0
                local myTime = myHasClock and snapshotBoard:TimeLeft(myChessColor, snapshotTime) or snapshotBoard:TimeThinking(myChessColor, snapshotTime)
                frame.playerClock:SetText(DeltaChess.UI:FormatTime(myTime or 0))
                frame.playerClock:Show()
            end
            if frame.opponentClock then
                local oppHasClock = (snapshotBoard:GetClock(opponentChessColor) or 0) > 0
                local oppTime = oppHasClock and snapshotBoard:TimeLeft(opponentChessColor, snapshotTime) or snapshotBoard:TimeThinking(opponentChessColor, snapshotTime)
                frame.opponentClock:SetText(DeltaChess.UI:FormatTime(oppTime or 0))
                frame.opponentClock:Show()
            end
        end
        
        -- Play move sound when advancing (same as game window)
        if animateMove then
            local wasCapture = animateMove:IsCapture()
            -- Snapshot is state after the move; current turn is the side that has to move next, so the side that just moved is the opposite
            local currentTurn = snapshotBoard:GetCurrentTurn()
            local movedColor = (currentTurn == COLOR.WHITE) and COLOR.BLACK or COLOR.WHITE
            local isPlayerMove = (movedColor == frame.myChessColor)
            DeltaChess.Sound:PlayMoveSound(snapshotBoard, isPlayerMove, wasCapture, snapshotBoard)
        end
        
        -- Animate the move if requested
        if animateMove then
            DeltaChess.UI:AnimateReplayMove(frame, animateMove)
        end
    end
    frame.RefreshReplayDisplay = UpdateReplayBoard
    
    -- Button handlers
    firstBtn:SetScript("OnClick", function()
        frame.currentMoveIndex = 0
        UpdateReplayBoard() -- No animation when going to start
    end)
    
    prevBtn:SetScript("OnClick", function()
        if frame.currentMoveIndex > 0 then
            frame.currentMoveIndex = frame.currentMoveIndex - 1
            UpdateReplayBoard() -- No animation when going backward
        end
    end)
    
    nextBtn:SetScript("OnClick", function()
        if frame.currentMoveIndex < #frame.moves then
            frame.currentMoveIndex = frame.currentMoveIndex + 1
            local moveToAnimate = frame.moves[frame.currentMoveIndex]
            UpdateReplayBoard(moveToAnimate) -- Animate the move forward
        end
    end)
    
    lastBtn:SetScript("OnClick", function()
        if frame.currentMoveIndex < #frame.moves then
            local lastMoveToAnimate = frame.moves[#frame.moves]
            frame.currentMoveIndex = #frame.moves
            UpdateReplayBoard(lastMoveToAnimate) -- Animate only the final move
        end
    end)
    
    -- Initial display
    UpdateReplayBoard()
    
    frame:Show()
end

--------------------------------------------------------------------------------
-- PGN WINDOW
--------------------------------------------------------------------------------
function DeltaChess:ShowPGNWindow(board)
    if not board or not board.GetPGN then return end
    local pgn = board:GetPGN()
    if not pgn or pgn == "" then pgn = "(no PGN)" end

    -- Create PGN window once and reuse
    if not self.frames.pgnWindow then
        local frame = CreateFrame("Frame", "ChessPGNFrame", UIParent, "BasicFrameTemplateWithInset")
        frame:SetSize(450, 380)
        frame:SetPoint("CENTER")
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        frame:SetFrameStrata("FULLSCREEN_DIALOG")
        frame:SetFrameLevel(300)  -- Above board (250) so PGN window stays on top
        frame.TitleText:SetText("PGN")

        -- Background behind the scroll area (ARTWORK layer so it draws above the frame's own background)
        local editBg = frame:CreateTexture(nil, "ARTWORK", nil, -1)
        editBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -32)
        editBg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -35, 10)
        editBg:SetColorTexture(0.1, 0.1, 0.15, 0.95)

        -- ScrollFrame = viewport; the EditBox IS the scroll child (standard WoW pattern)
        local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -32)
        scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -35, 10)

        local editBox = CreateFrame("EditBox", nil, scrollFrame)
        editBox:SetMultiLine(true)
        editBox:SetAutoFocus(false)
        editBox:SetFontObject(GameFontHighlightSmall)
        editBox:SetTextInsets(6, 6, 6, 6)
        editBox:SetMaxLetters(99999)
        editBox:SetWidth(400)
        editBox:SetScript("OnEscapePressed", function()
            frame:Hide()
        end)
        -- Update scroll range when text changes so scrollbar knows content height
        editBox:SetScript("OnTextChanged", function(self)
            local sf = self:GetParent()
            sf:UpdateScrollChildRect()
        end)
        -- Mouse wheel on EditBox forwards to ScrollFrame
        editBox:SetScript("OnCursorChanged", function(self, x, y, w, h)
            local sf = self:GetParent()
            local vs = sf:GetVerticalScroll()
            local sfHeight = sf:GetHeight()
            -- y is negative offset from top of editbox
            local cursorTop = -y
            local cursorBottom = cursorTop + h
            if cursorTop < vs then
                sf:SetVerticalScroll(cursorTop)
            elseif cursorBottom > vs + sfHeight then
                sf:SetVerticalScroll(cursorBottom - sfHeight)
            end
        end)

        scrollFrame:SetScrollChild(editBox)

        frame.pgnScrollFrame = scrollFrame
        frame.pgnEditBox = editBox
        self.frames.pgnWindow = frame
    end

    local frame = self.frames.pgnWindow
    frame:SetFrameLevel(300)  -- Ensure on top each time we show
    frame.pgnEditBox:SetText(pgn)
    frame.pgnEditBox:SetCursorPosition(0)
    frame.pgnScrollFrame:SetVerticalScroll(0)
    frame:Show()
    frame.pgnEditBox:HighlightText()
    frame.pgnEditBox:SetFocus()
end

--------------------------------------------------------------------------------
-- RECENT OPPONENTS
--------------------------------------------------------------------------------
function DeltaChess:GetRecentOpponents()
    local playerName = self:GetFullPlayerName(UnitName("player"))
    local opponents = {} -- fullName -> lastPlayed

    local function addOpponent(name, timestamp)
        if name and name ~= playerName and name ~= "Computer" then
            local existing = opponents[name]
            if not existing or timestamp > existing then
                opponents[name] = timestamp
            end
        end
    end

    -- Active games (board IS the game)
    for _, board in pairs(self.db.games) do
        local ts = board:GetStartTime() or 0
        addOpponent(board:GetWhitePlayerName(), ts)
        addOpponent(board:GetBlackPlayerName(), ts)
    end
    -- History games (deserialize to board)
    for _, entry in pairs(self.db.history) do
        local board = self:DeserializeHistoryEntry(entry)
        if board then
            local ts = board:GetStartTime() or 0
            addOpponent(board:GetWhitePlayerName(), ts)
            addOpponent(board:GetBlackPlayerName(), ts)
        end
    end

    local list = {}
    for fullName, lastPlayed in pairs(opponents) do
        table.insert(list, { fullName = fullName, lastPlayed = lastPlayed })
    end
    table.sort(list, function(a, b) return a.lastPlayed > b.lastPlayed end)

    local result = {}
    for i = 1, math.min(15, #list) do
        local name = list[i].fullName:match("^([^%-]+)") or list[i].fullName
        table.insert(result, { fullName = list[i].fullName, displayName = name })
    end
    return result
end

-- Get list of past opponent full names (for ping list)
-- Limit to 5 most recent to reduce "player not online" spam when pinging offline players
function DeltaChess:GetPastOpponentsFullNames()
    local recent = self:GetRecentOpponents()
    local out = {}
    local myName = self:GetFullPlayerName(UnitName("player"))
    for i = 1, math.min(5, #recent) do
        local opp = recent[i]
        if opp and opp.fullName and opp.fullName ~= myName then
            table.insert(out, opp.fullName)
        end
    end
    return out
end

-- Get list of online guild member full names
function DeltaChess:GetGuildOnlineFullNames()
    local out = {}
    local myName = self:GetFullPlayerName(UnitName("player"))
    if not IsInGuild() then return out end
    C_GuildInfo.GuildRoster()
    local num = GetNumGuildMembers()
    for i = 1, num do
        local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
        if name and online and name ~= myName then
            local fullName = name:find("-") and name or (name .. "-" .. GetRealmName())
            table.insert(out, fullName)
        end
    end
    return out
end

-- Get list of party/raid member full names (excludes self)
function DeltaChess:GetPartyFullNames()
    local out = {}
    local myName = self:GetFullPlayerName(UnitName("player"))
    local numGroup = GetNumGroupMembers()
    if numGroup <= 0 then return out end
    local prefix = IsInRaid() and "raid" or "party"
    local count = IsInRaid() and numGroup or (numGroup - 1) -- party units don't include "player"
    for i = 1, count do
        local unit = prefix .. i
        if UnitExists(unit) and UnitIsPlayer(unit) and UnitIsConnected(unit) then
            local name = UnitName(unit)
            if name then
                local fullName = self:GetFullPlayerName(name)
                if fullName ~= myName then
                    table.insert(out, fullName)
                end
            end
        end
    end
    return out
end

-- Get list of online friend full names (WoW + Battle.net friends)
function DeltaChess:GetFriendsOnlineFullNames()
    local out = {}
    local seen = {}
    local myName = self:GetFullPlayerName(UnitName("player"))
    
    -- WoW friend list
    if C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex then
        local num = C_FriendList.GetNumFriends()
        for i = 1, num do
            local info = C_FriendList.GetFriendInfoByIndex(i)
            if info and info.name and info.connected and info.name ~= myName then
                local fullName = self:GetFullPlayerName(info.name)
                if not seen[fullName] then
                    seen[fullName] = true
                    table.insert(out, fullName)
                end
            end
        end
    elseif GetNumFriends and GetFriendInfo then
        local num = GetNumFriends()
        for i = 1, num do
            local name, _, _, _, connected = GetFriendInfo(i)
            if name and connected and name ~= myName then
                local fullName = self:GetFullPlayerName(name)
                if not seen[fullName] then
                    seen[fullName] = true
                    table.insert(out, fullName)
                end
            end
        end
    end
    
    -- Battle.net friends (online in WoW, same region only - cross-region whisper causes "player not online" errors)
    if BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendNumGameAccounts and C_BattleNet.GetFriendGameAccountInfo then
        local wowClient = BNET_CLIENT_WOW or "WoW"
        for i = 1, BNGetNumFriends() do
            local numAccounts = C_BattleNet.GetFriendNumGameAccounts(i)
            for j = 1, numAccounts do
                local game = C_BattleNet.GetFriendGameAccountInfo(i, j)
                if game and game.isOnline and game.clientProgram == wowClient and game.characterName then
                    if game.isInCurrentRegion == false then
                        -- Skip cross-region: whisper would fail with "player not online"
                    else
                        local realm = game.realmDisplayName or game.realmName
                        local fullName = realm and (game.characterName .. "-" .. realm)
                            or self:GetFullPlayerName(game.characterName)
                        if fullName ~= myName and not seen[fullName] then
                            seen[fullName] = true
                            table.insert(out, fullName)
                        end
                    end
                end
            end
        end
    end
    
    return out
end

--------------------------------------------------------------------------------
-- PLAYER LIST POPUP (online + addon only)
--------------------------------------------------------------------------------
function DeltaChess:ShowPlayerListPopup(source, parentFrame, onSelect)
    -- source: "past", "guild", "friends", "party"
    local candidates = {}
    if source == "past" then
        candidates = self:GetPastOpponentsFullNames()
    elseif source == "guild" then
        candidates = self:GetGuildOnlineFullNames()
    elseif source == "friends" then
        candidates = self:GetFriendsOnlineFullNames()
    elseif source == "party" then
        candidates = self:GetPartyFullNames()
    end
    local myName = self:GetFullPlayerName(UnitName("player"))
    local filtered = {}
    for _, name in ipairs(candidates) do
        if name ~= myName then
            table.insert(filtered, name)
        end
    end
    candidates = filtered

    local popup = CreateFrame("Frame", nil, parentFrame, "BasicFrameTemplateWithInset")
    popup:SetSize(320, 380)
    popup:SetPoint("CENTER", parentFrame, "CENTER", 0, 0)
    popup:SetFrameStrata("DIALOG")
    popup:SetFrameLevel(parentFrame:GetFrameLevel() + 50)
    popup:SetMovable(true)
    popup:EnableMouse(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", popup.StartMoving)
    popup:SetScript("OnDragStop", popup.StopMovingOrSizing)
    local titleMap = { past = "Recent", guild = "Guild", friends = "Friends", party = "Party" }
    popup.TitleText:SetText(titleMap[source] or "Select Player")

    local statusText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statusText:SetPoint("TOPLEFT", popup, "TOPLEFT", 15, -35)
    statusText:SetText("Checking who has DeltaChess...")
    popup.statusText = statusText

    local scrollFrame = CreateFrame("ScrollFrame", nil, popup, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", statusText, "BOTTOMLEFT", 0, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -32, 10)
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(280, 1)
    scrollFrame:SetScrollChild(scrollChild)
    popup.scrollChild = scrollChild

    if #candidates == 0 then
        statusText:SetText("No players to show.")
        popup:Show()
        return
    end

    popup:Show()
    DeltaChess:PingPlayers(candidates, function(respondedList)
        statusText:SetText(string.format("%d player(s) with DeltaChess online.", #respondedList))
        
        -- If searching party/raid and no players responded, send message to chat
        if source == "party" and #respondedList == 0 and #candidates > 0 then
            local chatChannel = IsInRaid() and "RAID" or "PARTY"
            SendChatMessage("I want to challenge someone to a game of chess. Install Delta Chess from Curseforge so that we can play together: https://www.curseforge.com/wow/addons/deltachess", chatChannel)
        end
        
        for _, child in ipairs({ scrollChild:GetChildren() }) do
            child:Hide()
            child:SetParent(nil)
        end
        local y = 0
        for _, entry in ipairs(respondedList) do
            local fullName = entry.fullName
            local dnd = entry.dnd
            local displayName = fullName:match("^([^%-]+)") or fullName
            if dnd then
                displayName = displayName .. " |cFFFF6666(DND)|r"
            end
            local btn = CreateFrame("Button", nil, scrollChild)
            btn:SetSize(260, 24)
            btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
            btn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
            local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("LEFT", btn, "LEFT", 6, 0)
            label:SetText(displayName)
            btn:SetScript("OnClick", function()
                if onSelect then onSelect(fullName) end
                popup:Hide()
                popup:SetParent(nil)
                popup:ClearAllPoints()
            end)
            y = y + 26
        end
        scrollChild:SetHeight(y)
        popup:Show()
    end)
    popup:Show()
end

--------------------------------------------------------------------------------
-- CHALLENGE WINDOW
--------------------------------------------------------------------------------
function DeltaChess:ShowChallengeWindow(targetPlayer)
    -- Close existing window if open
    if self.frames.challengeWindow and self.frames.challengeWindow:IsShown() then
        self.frames.challengeWindow:Hide()
    end
    
    -- Create challenge window if it doesn't exist
    if not self.frames.challengeWindow then
        local frame = CreateFrame("Frame", "ChessChallengeWindow", UIParent, "BasicFrameTemplateWithInset")
        local BASE_CHALLENGE_HEIGHT = 320
        frame:SetSize(350, BASE_CHALLENGE_HEIGHT)
        frame:SetPoint("CENTER")
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        frame:SetFrameStrata("DIALOG")
        frame:SetFrameLevel(150)
        frame.TitleText:SetText("Challenge Player")
        
        local yPos = -35
        
        -- Opponent selection buttons
        local selectLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        selectLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, yPos)
        selectLabel:SetText("Select opponent:")
        
        yPos = yPos - 24
        
        local pastBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        pastBtn:SetSize(76, 24)
        pastBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, yPos)
        pastBtn:SetText("Recent")
        pastBtn:SetScript("OnClick", function()
            DeltaChess:ShowPlayerListPopup("past", frame, function(fullName)
                frame.nameInput:SetText(fullName)
            end)
        end)
        
        local guildBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        guildBtn:SetSize(76, 24)
        guildBtn:SetPoint("LEFT", pastBtn, "RIGHT", 5, 0)
        guildBtn:SetText("Guild")
        guildBtn:SetScript("OnClick", function()
            DeltaChess:ShowPlayerListPopup("guild", frame, function(fullName)
                frame.nameInput:SetText(fullName)
            end)
        end)
        
        local friendsBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        friendsBtn:SetSize(76, 24)
        friendsBtn:SetPoint("LEFT", guildBtn, "RIGHT", 5, 0)
        friendsBtn:SetText("Friends")
        friendsBtn:SetScript("OnClick", function()
            DeltaChess:ShowPlayerListPopup("friends", frame, function(fullName)
                frame.nameInput:SetText(fullName)
            end)
        end)
        
        local partyBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        partyBtn:SetSize(76, 24)
        partyBtn:SetPoint("LEFT", friendsBtn, "RIGHT", 5, 0)
        partyBtn:SetText("Party")
        partyBtn:SetScript("OnClick", function()
            DeltaChess:ShowPlayerListPopup("party", frame, function(fullName)
                frame.nameInput:SetText(fullName)
            end)
        end)
        
        yPos = yPos - 38
        
        -- Player name input
        local nameLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, yPos)
        nameLabel:SetText("Or enter name (Name-Realm):")
        
        yPos = yPos - 25
        
        local nameInput = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
        nameInput:SetSize(310, 25)
        nameInput:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, yPos)
        nameInput:SetAutoFocus(false)
        frame.nameInput = nameInput
        
        yPos = yPos - 45
        
        -- Color selection
        local colorLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        colorLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, yPos)
        colorLabel:SetText("Your Color:")
        
        yPos = yPos - 30
        
        -- Color buttons
        frame.selectedColor = "random"
        
        local whiteBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        whiteBtn:SetSize(102, 25)
        whiteBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, yPos)
        whiteBtn:SetText("White")
        
        local blackBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        blackBtn:SetSize(102, 25)
        blackBtn:SetPoint("LEFT", whiteBtn, "RIGHT", 5, 0)
        blackBtn:SetText("Black")
        
        local randomBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        randomBtn:SetSize(102, 25)
        randomBtn:SetPoint("LEFT", blackBtn, "RIGHT", 5, 0)
        randomBtn:SetText("Random")
        
        local function updateColorButtons()
            whiteBtn:SetEnabled(frame.selectedColor ~= COLOR.WHITE)
            blackBtn:SetEnabled(frame.selectedColor ~= COLOR.BLACK)
            randomBtn:SetEnabled(frame.selectedColor ~= "random")
        end
        
        whiteBtn:SetScript("OnClick", function()
            frame.selectedColor = COLOR.WHITE
            updateColorButtons()
        end)
        
        blackBtn:SetScript("OnClick", function()
            frame.selectedColor = COLOR.BLACK
            updateColorButtons()
        end)
        
        randomBtn:SetScript("OnClick", function()
            frame.selectedColor = "random"
            updateColorButtons()
        end)
        
        updateColorButtons()
        
        yPos = yPos - 45
        
        -- Clock config (shared panel with handicap)
        yPos = DeltaChess.UI:CreateClockConfigPanel(frame, {
            anchorFrame = frame,
            anchorPoint = "TOPLEFT",
            anchorRelPoint = "TOPLEFT",
            offsetX = 12,
            startY = yPos,
            showHandicap = true,
            onResize = function(extraHeight)
                frame:SetHeight(BASE_CHALLENGE_HEIGHT + extraHeight)
            end,
        })
        
        -- Buttons at bottom
        local sendBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        sendBtn:SetSize(140, 30)
        sendBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 15, 10)
        sendBtn:SetText("Send Challenge")
        sendBtn:SetScript("OnClick", function()
            local playerName = frame.nameInput:GetText()
            if not playerName or playerName == "" then
                DeltaChess:Print("Please enter a player name!")
                return
            end
            
            -- Add realm if not present
            if not playerName:find("-") then
                playerName = playerName .. "-" .. GetRealmName()
            end

            -- Cannot challenge yourself
            local myName = DeltaChess:GetFullPlayerName(UnitName("player"))
            if playerName == myName then
                DeltaChess:Print("You cannot challenge yourself!")
                return
            end
            
            sendBtn:SetEnabled(false)
            sendBtn:SetText("Checking...")
            
            DeltaChess:PingPlayer(playerName, function(hasAddon)
                sendBtn:SetEnabled(true)
                sendBtn:SetText("Send Challenge")
                if not hasAddon then
                    DeltaChess:Print("|cFFFF0000Player doesn't have DeltaChess installed or is offline.|r")
                    -- Extract player name without realm for whisper
                    local whisperName = playerName:match("^([^%-]+)") or playerName
                    SendChatMessage("I want to challenge you to a game of chess but you dont have Delta Chess installed :( Download from Curseforge so that we can play together: https://www.curseforge.com/wow/addons/deltachess", "WHISPER", nil, whisperName)
                    return
                end
                
                local wasRandom = frame.selectedColor == "random"
                local finalColor = frame.selectedColor
                if finalColor == "random" then
                    finalColor = math.random(2) == 1 and COLOR.WHITE or COLOR.BLACK
                end
                
                local handicapSeconds = (frame.handicapCheck and frame.handicapCheck:GetChecked() and frame.handicapSecondsSlider) and math.floor(frame.handicapSecondsSlider:GetValue()) or 0
                -- Resolve "challenger"/"opponent" to "white"/"black" based on the challenger's color
                local handicapSide = nil
                if frame.handicapSide == "challenger" then
                    handicapSide = finalColor  -- challenger's color gets less time
                elseif frame.handicapSide == "opponent" then
                    handicapSide = (finalColor == COLOR.WHITE) and COLOR.BLACK or COLOR.WHITE
                end
                local gameSettings = {
                    challenger = DeltaChess:GetFullPlayerName(UnitName("player")),
                    opponent = playerName,
                    challengerColor = finalColor,
                    isRandom = wasRandom,
                    useClock = frame.clockCheck:GetChecked(),
                    timeMinutes = math.floor(frame.timeSlider:GetValue()),
                    incrementSeconds = math.floor(frame.incSlider:GetValue()),
                    handicapSeconds = (handicapSeconds > 0) and handicapSeconds or nil,
                    handicapSide = handicapSide,
                }
                
                DeltaChess:SendChallenge(gameSettings)
                frame:Hide()
            end)
        end)
        
        local cancelBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        cancelBtn:SetSize(140, 30)
        cancelBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -15, 10)
        cancelBtn:SetText("Cancel")
        cancelBtn:SetScript("OnClick", function()
            frame:Hide()
        end)
        
        self.frames.challengeWindow = frame
    end
    
    -- Reset values (pre-fill with target if no player specified)
    if not targetPlayer or targetPlayer == "" then
        if UnitExists("target") and UnitIsPlayer("target") then
            local targetName = self:GetFullPlayerName(UnitName("target"))
            if targetName ~= self:GetFullPlayerName(UnitName("player")) then
                targetPlayer = targetName
            end
        end
    end
    self.frames.challengeWindow.nameInput:SetText(targetPlayer or "")
    self.frames.challengeWindow.selectedColor = "random"
    self.frames.challengeWindow.clockCheck:SetChecked(false)
    self.frames.challengeWindow.timeSlider:SetValue(10)
    self.frames.challengeWindow.incSlider:SetValue(0)
    if self.frames.challengeWindow.handicapCheck then
        self.frames.challengeWindow.handicapCheck:SetChecked(false)
        self.frames.challengeWindow.handicapSide = "challenger"
        UIDropDownMenu_SetText(self.frames.challengeWindow.handicapSideDropdown, "Challenger")
        self.frames.challengeWindow.handicapSecondsSlider:SetValue(0)
    end
    -- Update visibility and frame height to match reset checkbox states
    if self.frames.challengeWindow.UpdateClockLayout then
        self.frames.challengeWindow.UpdateClockLayout()
    end
    
    -- Update color buttons
    local frame = self.frames.challengeWindow
    for _, child in ipairs({frame:GetChildren()}) do
        if child:IsObjectType("Button") then
            local text = child:GetText()
            if text == "White" then child:SetEnabled(true)
            elseif text == "Black" then child:SetEnabled(true)
            elseif text == "Random" then child:SetEnabled(false)
            end
        end
    end
    
    self.frames.challengeWindow:Show()
end

-- For backwards compatibility
function DeltaChess:ShowChallengeDialog(targetPlayer)
    self:ShowChallengeWindow(targetPlayer)
end

--------------------------------------------------------------------------------
-- COMPUTER GAME WINDOW
--------------------------------------------------------------------------------
function DeltaChess:ShowComputerGameWindow()
    -- Close existing window if open
    if self.frames.computerWindow and self.frames.computerWindow:IsShown() then
        self.frames.computerWindow:Hide()
    end
    
    -- Create window if it doesn't exist
    if not self.frames.computerWindow then
        local frame = CreateFrame("Frame", "ChessComputerWindow", UIParent, "BasicFrameTemplateWithInset")
        frame:SetSize(320, 350)
        frame:SetPoint("CENTER")
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        frame:SetFrameStrata("DIALOG")
        frame:SetFrameLevel(150)
        frame.TitleText:SetText("Play vs Computer")
        
        local yPos = -35
        
        -- Color selection
        local colorLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        colorLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, yPos)
        colorLabel:SetText("Your Color:")
        
        yPos = yPos - 20
        
        -- Color buttons
        frame.selectedColor = COLOR.WHITE
        
        local whiteBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        whiteBtn:SetSize(92, 25)
        whiteBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, yPos)
        whiteBtn:SetText("White")
        whiteBtn:SetEnabled(false)
        
        local blackBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        blackBtn:SetSize(92, 25)
        blackBtn:SetPoint("LEFT", whiteBtn, "RIGHT", 5, 0)
        blackBtn:SetText("Black")
        
        local randomBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        randomBtn:SetSize(92, 25)
        randomBtn:SetPoint("LEFT", blackBtn, "RIGHT", 5, 0)
        randomBtn:SetText("Random")
        
        local function updateColorButtons()
            whiteBtn:SetEnabled(frame.selectedColor ~= COLOR.WHITE)
            blackBtn:SetEnabled(frame.selectedColor ~= COLOR.BLACK)
            randomBtn:SetEnabled(frame.selectedColor ~= "random")
        end
        
        whiteBtn:SetScript("OnClick", function()
            frame.selectedColor = COLOR.WHITE
            updateColorButtons()
        end)
        
        blackBtn:SetScript("OnClick", function()
            frame.selectedColor = COLOR.BLACK
            updateColorButtons()
        end)
        
        randomBtn:SetScript("OnClick", function()
            frame.selectedColor = "random"
            updateColorButtons()
        end)
        
        yPos = yPos - 40

        -- AI Strength slider (ELO) - moved above engine selection
        -- Uses global ELO range across all engines
        local globalRange = DeltaChess.Engines:GetGlobalEloRange()
        local hasEloEngines = (globalRange ~= nil)
        
        local diffLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        diffLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, yPos)
        diffLabel:SetText("AI Strength (ELO):")
        frame.diffLabel = diffLabel
        
        frame.selectedDifficulty = 1200
        
        local diffValue = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        diffValue:SetPoint("LEFT", diffLabel, "RIGHT", 10, 0)
        diffValue:SetText("1200")
        frame.diffValueText = diffValue
        
        yPos = yPos - 25
        
        local diffSlider = CreateFrame("Slider", nil, frame, "OptionsSliderTemplate")
        diffSlider:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, yPos)
        diffSlider:SetSize(275, 17)
        if hasEloEngines then
            diffSlider:SetMinMaxValues(globalRange[1], globalRange[2])
            diffSlider:SetValue(math.max(globalRange[1], math.min(globalRange[2], 1200)))
            diffSlider.Low:SetText(tostring(globalRange[1]))
            diffSlider.High:SetText(tostring(globalRange[2]))
        else
            diffSlider:SetMinMaxValues(100, 2500)
            diffSlider:SetValue(1200)
            diffSlider.Low:SetText("100")
            diffSlider.High:SetText("2500")
            diffSlider:Disable()
        end
        diffSlider:SetValueStep(100)
        diffSlider:SetObeyStepOnDrag(true)
        frame.diffSlider = diffSlider
        
        yPos = yPos - 35
        
        -- Difficulty description
        local diffDesc = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        diffDesc:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, yPos)
        diffDesc:SetWidth(260)
        diffDesc:SetJustifyH("LEFT")
        diffDesc:SetText("|cFF888888100-400: Beginner | 400-1000: Club | 1000-1600: Advanced | 1600+: Expert|r")
        frame.diffDesc = diffDesc

        yPos = yPos - 30

        -- Engine selection (below AI strength)
        local engineLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        engineLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, yPos)
        engineLabel:SetText("Engine:")
        frame.engineLabel = engineLabel

        yPos = yPos - 25

        frame.selectedEngine = DeltaChess.Engines:GetEffectiveDefaultId()

        local engineDropdown = CreateFrame("Frame", "ChessEngineDropdown", frame, "UIDropDownMenuTemplate")
        engineDropdown:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yPos)
        UIDropDownMenu_SetWidth(engineDropdown, 265)
        frame.engineDropdown = engineDropdown
        
        -- Engine description label (below dropdown)
        local engineDescLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        engineDescLabel:SetPoint("TOPLEFT", engineDropdown, "BOTTOMLEFT", 20, 0)
        engineDescLabel:SetWidth(250)
        engineDescLabel:SetJustifyH("LEFT")
        engineDescLabel:SetWordWrap(true)
        engineDescLabel:SetTextColor(0.7, 0.7, 0.7)
        frame.engineDescLabel = engineDescLabel
        
        -- Function to update engine description
        local function updateEngineDescription(engineId)
            local engine = DeltaChess.Engines:Get(engineId)
            if engine then
                local desc = engine.description or ""
                if engine.author then
                    desc = desc .. " (by " .. engine.author
                    if engine.portedBy then
                        desc = desc .. ", Lua port: " .. engine.portedBy
                    end
                    desc = desc .. ")"
                elseif engine.portedBy then
                    desc = desc .. " (Lua port: " .. engine.portedBy .. ")"
                end
                engineDescLabel:SetText(desc)
            else
                engineDescLabel:SetText("")
            end
        end
        frame.updateEngineDescription = updateEngineDescription
        
        -- Helper function to get display name with ELO range
        local function getEngineDisplayName(engineId)
            local engine = DeltaChess.Engines:Get(engineId)
            if not engine then return "Select Engine" end
            local range = DeltaChess.Engines:GetEloRange(engineId)
            if range then
                return engine.name .. " (" .. range[1] .. "-" .. range[2] .. ")"
            else
                return engine.name .. " (no ELO)"
            end
        end
        frame.getEngineDisplayName = getEngineDisplayName
        
        -- Function to update engine dropdown based on selected ELO
        local function updateEngineDropdownForElo(elo, startButton)
            local availableEngines = DeltaChess.Engines:GetEnginesForElo(elo)
            
            -- List is sorted by CPU efficiency (fastest first), then by ELO support
            -- Find the most efficient engine with ELO support
            local bestEngine = nil
            for _, eng in ipairs(availableEngines) do
                if eng.hasEloSupport then
                    bestEngine = eng
                    break  -- First ELO-supporting engine is most efficient
                end
            end
            
            -- If no ELO-supporting engine available, use first available (no-ELO engines)
            if not bestEngine and #availableEngines > 0 then
                bestEngine = availableEngines[1]
            end
            
            -- Always select the most efficient engine when slider changes
            if bestEngine then
                frame.selectedEngine = bestEngine.id
            else
                frame.selectedEngine = nil
            end
            
            -- Enable/disable dropdown and start button based on availability
            if #availableEngines == 0 then
                UIDropDownMenu_DisableDropDown(engineDropdown)
                UIDropDownMenu_SetText(engineDropdown, "No engine available")
                engineDescLabel:SetText("")
                if startButton then startButton:Disable() end
                if frame.engineLabel then frame.engineLabel:SetTextColor(0.5, 0.5, 0.5, 1) end
            else
                UIDropDownMenu_EnableDropDown(engineDropdown)
                UIDropDownMenu_SetSelectedValue(engineDropdown, frame.selectedEngine)
                UIDropDownMenu_SetText(engineDropdown, getEngineDisplayName(frame.selectedEngine))
                updateEngineDescription(frame.selectedEngine)
                if startButton then startButton:Enable() end
                if frame.engineLabel then frame.engineLabel:SetTextColor(1, 0.82, 0, 1) end
            end
            
            -- Re-initialize dropdown with filtered engines
            UIDropDownMenu_Initialize(engineDropdown, function(self, level)
                local info = UIDropDownMenu_CreateInfo()
                local filteredEngines = DeltaChess.Engines:GetEnginesForElo(frame.selectedDifficulty or 1200)
                for _, eng in ipairs(filteredEngines) do
                    local engineId = eng.id
                    local displayName = getEngineDisplayName(engineId)
                    info.text = displayName
                    info.value = engineId
                    info.checked = (frame.selectedEngine == engineId)
                    info.func = function()
                        UIDropDownMenu_SetSelectedValue(engineDropdown, engineId)
                        UIDropDownMenu_SetText(engineDropdown, displayName)
                        frame.selectedEngine = engineId
                        updateEngineDescription(engineId)
                    end
                    UIDropDownMenu_AddButton(info)
                end
            end)
        end
        frame.updateEngineDropdownForElo = updateEngineDropdownForElo
        
        -- Slider OnValueChanged handler
        diffSlider:SetScript("OnValueChanged", function(self, value)
            local gRange = DeltaChess.Engines:GetGlobalEloRange()
            if not gRange then return end
            local minVal, maxVal = gRange[1], gRange[2]
            local elo = math.floor((value + 50) / 100) * 100
            elo = math.max(minVal, math.min(maxVal, elo))
            frame.selectedDifficulty = elo
            frame.diffValueText:SetText(tostring(elo))
            -- Update engine dropdown based on new ELO
            if frame.updateEngineDropdownForElo then
                frame.updateEngineDropdownForElo(elo, frame.startButton)
            end
        end)
        
        -- Start button
        local startBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        startBtn:SetSize(120, 30)
        startBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 15, 10)
        startBtn:SetText("Start Game")
        startBtn:SetScript("OnClick", function()
            local color = frame.selectedColor
            if color == "random" then
                color = math.random(2) == 1 and COLOR.WHITE or COLOR.BLACK
            end
            local settings = { useClock = false }
            frame:Hide()
            DeltaChess:StartComputerGame(color, frame.selectedDifficulty, frame.selectedEngine, settings)
        end)
        frame.startButton = startBtn
        
        local cancelBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        cancelBtn:SetSize(120, 30)
        cancelBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -15, 10)
        cancelBtn:SetText("Cancel")
        cancelBtn:SetScript("OnClick", function()
            frame:Hide()
        end)
        
        self.frames.computerWindow = frame
    end
    
    -- Reset to defaults
    local frame = self.frames.computerWindow
    frame.selectedColor = COLOR.WHITE
    frame.selectedEngine = DeltaChess.Engines:GetEffectiveDefaultId()
    frame.selectedDifficulty = 1200
    
    -- Reset slider to global range and default value
    local globalRange = DeltaChess.Engines:GetGlobalEloRange()
    if globalRange and frame.diffSlider then
        frame.diffSlider:SetMinMaxValues(globalRange[1], globalRange[2])
        frame.diffSlider.Low:SetText(tostring(globalRange[1]))
        frame.diffSlider.High:SetText(tostring(globalRange[2]))
        frame.diffSlider:SetValue(math.max(globalRange[1], math.min(globalRange[2], 1200)))
        frame.diffSlider:Enable()
        frame.diffValueText:SetText(tostring(frame.selectedDifficulty))
        frame.diffValueText:SetTextColor(1, 1, 1, 1)
        if frame.diffLabel then frame.diffLabel:SetTextColor(1, 0.82, 0, 1) end
        if frame.diffDesc then frame.diffDesc:SetTextColor(0.5, 0.5, 0.5, 1) end
    elseif frame.diffSlider then
        -- No engines with ELO support
        frame.diffSlider:Disable()
        frame.diffValueText:SetText("N/A")
        frame.diffValueText:SetTextColor(0.5, 0.5, 0.5, 1)
        if frame.diffLabel then frame.diffLabel:SetTextColor(0.5, 0.5, 0.5, 1) end
        if frame.diffDesc then frame.diffDesc:SetTextColor(0.4, 0.4, 0.4, 1) end
        frame.selectedDifficulty = nil
    end
    
    -- Update engine dropdown based on selected ELO
    if frame.updateEngineDropdownForElo then
        frame.updateEngineDropdownForElo(frame.selectedDifficulty or 1200, frame.startButton)
    end
    
    -- Update color button states
    local frame = self.frames.computerWindow
    for _, child in ipairs({frame:GetChildren()}) do
        if child:IsObjectType("Button") then
            local text = child:GetText()
            if text == "White" then child:SetEnabled(false)
            elseif text == "Black" then child:SetEnabled(true)
            elseif text == "Random" then child:SetEnabled(true)
            end
        end
    end
    
    self.frames.computerWindow:Show()
end

--------------------------------------------------------------------------------
-- CHALLENGE RECEIVED POPUP
--------------------------------------------------------------------------------
StaticPopupDialogs["CHESS_CHALLENGE_RECEIVED"] = {
    text = "%s has challenged you to a game of chess!\n\n%s\n\nDo you accept?",
    button1 = "Accept",
    button2 = "Decline",
    OnAccept = function(self, data)
        DeltaChess:AcceptChallenge(data)
    end,
    OnCancel = function(self, data)
        DeltaChess:DeclineChallenge(data)
    end,
    timeout = 60,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CHESS_RESIGN_CONFIRM"] = {
    text = "%s\n\nAre you sure you want to resign?",
    button1 = "Resign",
    button2 = "Cancel",
    OnShow = function(dialog)
        -- Show above the board and PGN window
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetFrameLevel(350)
        DeltaChess._actionBlocked = (DeltaChess._actionBlocked or 0) + 1
        if DeltaChess.UI.activeFrame then
            DeltaChess.UI:UpdateBoard(DeltaChess.UI.activeFrame)
        end
    end,
    OnHide = function()
        local gameId = DeltaChess._resignConfirmGameId
        DeltaChess._resignConfirmGameId = nil
        DeltaChess._actionBlocked = math.max(0, (DeltaChess._actionBlocked or 0) - 1)
        if DeltaChess.UI.activeFrame then
            DeltaChess.UI:UpdateBoard(DeltaChess.UI.activeFrame)
        end
    end,
    OnAccept = function(self, gameId)
        if gameId then
            DeltaChess:ResignGame(gameId)
            -- Refresh history window to show game as completed
            DeltaChess:RefreshMainMenuContent()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CHESS_PAUSE_REQUEST"] = {
    text = "%s\n\nYour opponent wants to pause the game. Do you accept?",
    button1 = "Accept",
    button2 = "Decline",
    OnShow = function(dialog)
        -- Ensure popup appears above the board
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetFrameLevel(350)
    end,
    OnAccept = function(self, popupData)
        local board = DeltaChess.GetBoard(popupData.gameId)
        if board then
            board:PauseGame()
            board:SetGameMeta("pauseStartTime", DeltaChess.Util.TimeNow())
            board:SetGameMeta("_lastMoveCountWhenPaused", board:GetHalfMoveCount())
            DeltaChess:SendPauseResponse(popupData.gameId, true)
            DeltaChess:Print("Game paused.")
            if DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == popupData.gameId then
                DeltaChess.UI:UpdateBoard(DeltaChess.UI.activeFrame)
            end
            DeltaChess:RefreshMainMenuContent()
        end
    end,
    OnCancel = function(self, popupData)
        DeltaChess:SendPauseResponse(popupData.gameId, false)
    end,
    timeout = 30,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CHESS_UNPAUSE_REQUEST"] = {
    text = "%s\n\nYour opponent wants to resume the game. Do you accept?",
    button1 = "Accept",
    button2 = "Decline",
    OnShow = function(dialog)
        -- Ensure popup appears above the board
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetFrameLevel(350)
    end,
    OnAccept = function(self, popupData)
        local board = DeltaChess.GetBoard(popupData.gameId)
        if board then
            local pauseStartTime = board:GetGameMeta("pauseStartTime")
            local now = DeltaChess.Util.TimeNow()
            local increment = pauseStartTime and (now - pauseStartTime) or 0
            local timeSpentClosed = (board:GetGameMeta("timeSpentClosed") or 0) + increment
            board:SetGameMeta("timeSpentClosed", timeSpentClosed)
            board:ContinueGame()
            board:SetGameMeta("pauseStartTime", nil)
            DeltaChess:SendUnpauseResponse(popupData.gameId, true, increment)
            DeltaChess:Print("Game resumed.")
            if DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == popupData.gameId then
                DeltaChess.UI:UpdateBoard(DeltaChess.UI.activeFrame)
            end
            DeltaChess:RefreshMainMenuContent()
        end
    end,
    OnCancel = function(self, popupData)
        DeltaChess:SendUnpauseResponse(popupData.gameId, false)
    end,
    timeout = 30,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

--------------------------------------------------------------------------------
-- OTHER MENU FUNCTIONS
--------------------------------------------------------------------------------

-- Show active games
function DeltaChess:ShowActiveGames()
    local hasActiveGames = false
    self:Print("Active Games:")
    for gameId, board in pairs(self.db.games) do
        if board:IsActive() then
            hasActiveGames = true
            local white = board:GetWhitePlayerName()
            local black = board:GetBlackPlayerName()
            self:Print(string.format("  %s vs %s (ID: %s)", white, black, gameId))
        end
    end
    
    if not hasActiveGames then
        self:Print("  No active games")
    end
end

-- Show game history
function DeltaChess:ShowGameHistory()
    self:Print("Game History:")
    local list = {}
    for _, entry in pairs(self.db.history) do
        table.insert(list, entry)
    end
    if #list == 0 then
        self:Print("  No game history")
    else
        table.sort(list, function(a, b)
            return (a.endTime or a.startTime or 0) > (b.endTime or b.startTime or 0)
        end)
        local count = math.min(10, #list)
        for i = 1, count do
            local board = self:DeserializeHistoryEntry(list[i])
            if board then
                self:Print(string.format("  %s vs %s - %s (%s)",
                    board:GetWhitePlayerName() or "?",
                    board:GetBlackPlayerName() or "?",
                    board:GetGameResult() or "Unknown",
                    board:GetStartDateString() or "Unknown"))
            end
        end
        if #list > 10 then
            self:Print(string.format("  ... and %d more games", #list - 10))
        end
    end
end

-- Show settings
function DeltaChess:ShowSettings()
    self:Print("DeltaChess Settings:")
    self:Print(string.format("  Minimap Button: %s", self.db.settings.showMinimapButton and "Enabled" or "Disabled"))
    self:Print("  Use '/chess minimap' to toggle the minimap button")
end

-- Show game replay
function DeltaChess:ShowGameReplay(game)
    self:Print("Game replay feature coming soon!")
end
