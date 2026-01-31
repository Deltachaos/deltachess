-- Core.lua - Main addon initialization and slash commands

DeltaChess = {}
DeltaChess.version = "1.0.0"

-- Frame for events
local eventFrame = CreateFrame("Frame")

-- UI Frames storage
DeltaChess.frames = {}

-- Initialize the addon
local function Initialize()
    -- Initialize saved variables
    if not ChessDB then
        ChessDB = {
            games = {},
            history = {},
            settings = {
                showMinimapButton = true,
                dnd = false
            }
        }
    end
    if ChessDB.settings.dnd == nil then
        ChessDB.settings.dnd = false
    end
    
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
end

-- Restore board metatables for saved games after addon reload
function DeltaChess:RestoreSavedGames()
    if not self.db or not self.db.games then return end
    
    for gameId, game in pairs(self.db.games) do
        if game.board and not getmetatable(game.board) then
            -- Restore the board metatable
            setmetatable(game.board, {__index = DeltaChess.Board})
            
            -- Ensure the board has all required data structures
            if not game.board.squares then
                game.board.squares = {}
            end
            if not game.board.moves then
                game.board.moves = {}
            end
            if not game.board.capturedPieces then
                game.board.capturedPieces = {white = {}, black = {}}
            end
            if not game.board.currentTurn then
                game.board.currentTurn = "white"
            end
            if not game.board.gameStatus then
                game.board.gameStatus = "active"
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
    elseif command == "games" or command == "active" then
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
    for _, game in pairs(self.db.games) do
        if game.status == "active" and game.board then
            local currentTurn = game.board.currentTurn or "white"
            local isPlayerTurn
            if game.isVsComputer then
                isPlayerTurn = (currentTurn == (game.playerColor or "white"))
            else
                isPlayerTurn = (game.white == playerName and currentTurn == "white") or
                              (game.black == playerName and currentTurn == "black")
            end
            if isPlayerTurn then return true end
        end
    end
    return false
end

-- Common: notify user that opponent moved and it's their turn (human or computer)
function DeltaChess:NotifyItIsYourTurn(gameId, opponentDisplayName)
    local game = self.db.games[gameId]
    if not game or game.status ~= "active" then return end
    
    local lastMove = game.board.moves and game.board.moves[#game.board.moves]
    local moveNotation = lastMove and DeltaChess.UI:FormatMoveAlgebraic(lastMove) or ""
    if moveNotation ~= "" then
        self:Print(opponentDisplayName .. " played " .. moveNotation .. " - it's your turn!")
    else
        self:Print(opponentDisplayName .. " made their move - it's your turn!")
    end
    
    if DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId then
        DeltaChess.UI:UpdateBoard(DeltaChess.UI.activeFrame)
    end
    
    if DeltaChess.Minimap and DeltaChess.Minimap.UpdateYourTurnHighlight then
        DeltaChess.Minimap:UpdateYourTurnHighlight()
    end
    
    PlaySound(SOUNDKIT.ACHIEVEMENT_MENU_OPEN)
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
        frame:SetSize(400, 500)
        frame:SetPoint("CENTER")
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        frame:SetFrameStrata("FULLSCREEN_DIALOG") -- High z-index
        frame:SetFrameLevel(100)
        frame.TitleText:SetText("DeltaChess")
        
        -- Game History title
        local historyTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        historyTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -35)
        historyTitle:SetText("Game History")
        
        -- History scroll frame
        local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", historyTitle, "BOTTOMLEFT", 0, -10)
        scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -40, 55)
        
        local scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetSize(340, 1)
        scrollFrame:SetScrollChild(scrollChild)
        frame.scrollChild = scrollChild
        
        -- DND checkbox (above bottom buttons)
        local dndCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        dndCheck:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 48)
        dndCheck.text:SetText("Do Not Disturb (no challenge popups)")
        dndCheck:SetChecked(DeltaChess.db.settings.dnd)
        dndCheck:SetScript("OnClick", function(self)
            DeltaChess.db.settings.dnd = self:GetChecked()
            if DeltaChess.Minimap and DeltaChess.Minimap.UpdateDNDHighlight then
                DeltaChess.Minimap:UpdateDNDHighlight()
            end
        end)
        frame.dndCheck = dndCheck
        
        -- Challenge Player button (bottom left)
        local challengeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        challengeBtn:SetSize(170, 30)
        challengeBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 15, 10)
        challengeBtn:SetText("Challenge Player")
        challengeBtn:SetScript("OnClick", function()
            frame:Hide()
            DeltaChess:ShowChallengeWindow()
        end)
        
        -- Play vs Computer button (bottom right)
        local computerBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        computerBtn:SetSize(170, 30)
        computerBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -15, 10)
        computerBtn:SetText("Play vs Computer")
        computerBtn:SetScript("OnClick", function()
            frame:Hide()
            DeltaChess:ShowComputerGameWindow()
        end)
        
        self.frames.mainMenu = frame
    end
    
    -- Refresh the content
    self:RefreshMainMenuContent()
    
    self.frames.mainMenu:Show()
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
    
    -- Collect all games (active + history)
    local allGames = {}
    local playerName = self:GetFullPlayerName(UnitName("player"))
    
    -- Add active games first
    for gameId, game in pairs(self.db.games) do
        local currentTurn = game.board and game.board.currentTurn or "white"
        local isPlayerTurn = false
        local playerColor = nil
        
        if game.isVsComputer then
            playerColor = game.playerColor
            isPlayerTurn = (currentTurn == playerColor)
        else
            if game.white == playerName then
                playerColor = "white"
            elseif game.black == playerName then
                playerColor = "black"
            end
            isPlayerTurn = (currentTurn == playerColor)
        end
        
        local gameStatus = game.status or "active"
        local isPaused = (gameStatus == "paused")
        local windowShown = DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId and DeltaChess.UI.activeFrame:IsShown()
        table.insert(allGames, {
            id = gameId,
            white = game.white,
            black = game.black,
            whiteClass = game.whiteClass,
            blackClass = game.blackClass,
            status = gameStatus,
            startTime = game.startTime,
            isVsComputer = game.isVsComputer,
            moveCount = game.board and #game.board.moves or 0,
            currentTurn = currentTurn,
            isPlayerTurn = isPlayerTurn,
            playerColor = playerColor,
            settings = game.settings,
            computerDifficulty = game.computerDifficulty,
            pausedByClose = game.pausedByClose,
            windowShown = windowShown
        })
    end
    
    -- Add completed games from history
    for i, game in ipairs(self.db.history) do
        table.insert(allGames, {
            id = game.id,
            white = game.white,
            black = game.black,
            whiteClass = game.whiteClass,
            blackClass = game.blackClass,
            status = "completed",
            result = game.result,
            date = game.date,
            startTime = game.startTime or 0,
            moveCount = game.moves and #game.moves or 0,
            isVsComputer = game.isVsComputer,
            playerColor = game.playerColor,
            settings = game.settings,
            computerDifficulty = game.computerDifficulty,
            moves = game.moves
        })
    end
    
    -- Sort by start time (newest first)
    table.sort(allGames, function(a, b)
        return (a.startTime or 0) > (b.startTime or 0)
    end)
    
    -- Add entries
    local yOffset = 0
    if #allGames == 0 then
        local noHistory = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        noHistory:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
        noHistory:SetText("No games played yet")
        noHistory:SetTextColor(0.5, 0.5, 0.5)
    else
        local displayCount = math.min(#allGames, 30)
        for i = 1, displayCount do
            local game = allGames[i]
            
            local entry = CreateFrame("Button", nil, scrollChild)
            entry:SetSize(340, 60)
            entry:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
            
            -- Background
            local bg = entry:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            if game.status == "active" or game.status == "paused" then
                if game.status == "paused" then
                    bg:SetColorTexture(0.2, 0.2, 0.0, 0.7) -- Yellow tint - paused
                elseif game.isPlayerTurn then
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
            
            -- Get class colors for both players (use saved class if available)
            local whiteR, whiteG, whiteB = DeltaChess.UI:GetPlayerColor(game.white or "?", game.whiteClass)
            local blackR, blackG, blackB = DeltaChess.UI:GetPlayerColor(game.black or "?", game.blackClass)
            
            -- Convert to hex color codes
            local whiteHex = string.format("|cFF%02X%02X%02X", whiteR * 255, whiteG * 255, whiteB * 255)
            local blackHex = string.format("|cFF%02X%02X%02X", blackR * 255, blackG * 255, blackB * 255)
            
            -- Format names (remove realm for display)
            local whiteName = (game.white or "?"):match("^([^%-]+)") or game.white or "?"
            local blackName = (game.black or "?"):match("^([^%-]+)") or game.black or "?"
            
            info:SetText(string.format("%s%s|r vs %s%s|r", whiteHex, whiteName, blackHex, blackName))
            
            -- Settings line (color, clock, difficulty)
            local settingsText = entry:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            settingsText:SetPoint("TOPLEFT", info, "BOTTOMLEFT", 0, -1)
            
            local settingsParts = {}
            if game.playerColor then
                table.insert(settingsParts, "You: " .. game.playerColor)
            end
            if game.isVsComputer and game.computerDifficulty then
                local d = game.computerDifficulty
                local diffStr = (type(d) == "number" and d >= 100 and d <= 2500) and (tostring(d) .. " ELO") or "~1200 ELO"
                table.insert(settingsParts, "AI: " .. diffStr)
            end
            if game.settings then
                if game.settings.useClock then
                    table.insert(settingsParts, string.format("Clock: %dm +%ds", 
                        game.settings.timeMinutes or 10, 
                        game.settings.incrementSeconds or 0))
                else
                    table.insert(settingsParts, "No clock")
                end
            end
            settingsText:SetText("|cFFAAAAAA" .. table.concat(settingsParts, " | ") .. "|r")
            
            -- Status/Result line
            local statusText = entry:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            statusText:SetPoint("TOPLEFT", settingsText, "BOTTOMLEFT", 0, -1)
            
            if game.status == "active" or game.status == "paused" then
                if game.status == "paused" then
                    statusText:SetText("|cFFFFFF00Paused|r - " .. game.moveCount .. " moves")
                else
                    local turnText = game.isPlayerTurn and "|cFF00FF00YOUR TURN|r" or "|cFFFFFF00Waiting...|r"
                    statusText:SetText(string.format("%s - %d moves", turnText, game.moveCount))
                end
            else
                local resultColor = "|cFFFFFFFF"
                if game.result == "won" then
                    resultColor = "|cFF00FF00"
                elseif game.result == "lost" or game.result == "resigned" then
                    resultColor = "|cFFFF0000"
                elseif game.result == "draw" then
                    resultColor = "|cFFFFFF00"
                end
                statusText:SetText(string.format("%s%s|r - %d moves - %s", resultColor, game.result or "Unknown", game.moveCount, game.date or "Unknown"))
            end
            
            -- Buttons
            if game.status == "active" or game.status == "paused" then
                local isPaused = (game.status == "paused")
                local isHumanWindowHidden = not game.isVsComputer and not game.windowShown
                local btnText, btnAction
                if isPaused and not game.isVsComputer then
                    btnText = "Resume"
                    btnAction = function()
                        self.frames.mainMenu:Hide()
                        DeltaChess:RequestUnpause(game.id)
                        DeltaChess:ShowChessBoard(game.id)
                    end
                elseif isHumanWindowHidden and not isPaused then
                    btnText = "Open"
                    btnAction = function()
                        self.frames.mainMenu:Hide()
                        DeltaChess:ShowChessBoard(game.id)
                    end
                else
                    btnText = "Resume"
                    btnAction = function()
                        self.frames.mainMenu:Hide()
                        DeltaChess:ShowChessBoard(game.id)
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
                    DeltaChess:ResignGame(game.id)
                    DeltaChess:RefreshMainMenuContent()
                end)
            else
                -- Delete button for completed games
                local deleteBtn = CreateFrame("Button", nil, entry, "UIPanelButtonTemplate")
                deleteBtn:SetSize(22, 22)
                deleteBtn:SetPoint("RIGHT", entry, "RIGHT", -5, 0)
                deleteBtn:SetText("X")
                deleteBtn:SetScript("OnClick", function()
                    DeltaChess:DeleteFromHistory(game.id)
                    DeltaChess:RefreshMainMenuContent() -- Refresh without closing
                end)
                
                -- Replay button for completed games
                local replayBtn = CreateFrame("Button", nil, entry, "UIPanelButtonTemplate")
                replayBtn:SetSize(55, 22)
                replayBtn:SetPoint("RIGHT", deleteBtn, "LEFT", -3, 0)
                replayBtn:SetText("Replay")
                replayBtn:SetScript("OnClick", function()
                    self.frames.mainMenu:Hide()
                    DeltaChess:ShowReplayWindow(game)
                end)
            end
            
            yOffset = yOffset + 62
        end
    end
    
    scrollChild:SetHeight(math.max(yOffset, 100))
end

--------------------------------------------------------------------------------
-- REPLAY WINDOW
--------------------------------------------------------------------------------
function DeltaChess:ShowReplayWindow(gameData)
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
    
    -- Determine board orientation and player info
    local playerName = self:GetFullPlayerName(UnitName("player"))
    local flipBoard = (gameData.black == playerName) or (gameData.playerColor == "black")
    
    -- Determine who is "me" and who is "opponent"
    local myName, opponentName, myChessColor, opponentChessColor, myClass, opponentClass
    if flipBoard then
        myName = gameData.black or "Black"
        opponentName = gameData.white or "White"
        myChessColor = "black"
        opponentChessColor = "white"
        myClass = gameData.blackClass
        opponentClass = gameData.whiteClass
    else
        myName = gameData.white or "White"
        opponentName = gameData.black or "Black"
        myChessColor = "white"
        opponentChessColor = "black"
        myClass = gameData.whiteClass
        opponentClass = gameData.blackClass
    end
    
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
    frame:SetFrameLevel(100)
    frame.TitleText:SetText("Replay")
    
    self.frames.replayWindow = frame
    
    -- Store replay state
    frame.moves = gameData.moves or {}
    frame.currentMoveIndex = 0
    frame.myChessColor = myChessColor
    frame.opponentChessColor = opponentChessColor
    
    local leftMargin = 10
    local topOffset = -30
    
    -- ==================== OPPONENT BAR (TOP) ====================
    local opponentBar = CreateFrame("Frame", nil, frame)
    opponentBar:SetSize(LABEL_SIZE + BOARD_SIZE, PLAYER_BAR_HEIGHT)
    opponentBar:SetPoint("TOPLEFT", frame, "TOPLEFT", leftMargin, topOffset)
    
    local opponentBg = opponentBar:CreateTexture(nil, "BACKGROUND")
    opponentBg:SetAllPoints()
    opponentBg:SetColorTexture(0.15, 0.15, 0.15, 0.8)
    
    -- Opponent name with class color
    local opR, opG, opB = DeltaChess.UI:GetPlayerColor(opponentName, opponentClass)
    local opponentNameText = opponentBar:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    opponentNameText:SetPoint("LEFT", opponentBar, "LEFT", 5, 8)
    opponentNameText:SetTextColor(opR, opG, opB)
    opponentNameText:SetText(opponentName:match("^([^%-]+)") or opponentName)
    
    -- Opponent captured pieces container
    local opponentCapturedContainer = CreateFrame("Frame", nil, opponentBar)
    opponentCapturedContainer:SetSize(200, CAPTURED_PIECE_SIZE)
    opponentCapturedContainer:SetPoint("LEFT", opponentBar, "LEFT", 5, -10)
    frame.opponentCapturedContainer = opponentCapturedContainer
    frame.opponentCapturedColor = myChessColor
    
    -- ==================== BOARD ====================
    local boardContainer = CreateFrame("Frame", nil, frame)
    boardContainer:SetSize(BOARD_SIZE + LABEL_SIZE, BOARD_SIZE + LABEL_SIZE)
    boardContainer:SetPoint("TOPLEFT", opponentBar, "BOTTOMLEFT", 0, 0)
    
    -- Create squares using shared function (non-interactive)
    frame.squares = DeltaChess.UI:CreateBoardSquares(boardContainer, SQUARE_SIZE, LABEL_SIZE, flipBoard, false)
    
    -- ==================== PLAYER BAR (BOTTOM) ====================
    local playerBar = CreateFrame("Frame", nil, frame)
    playerBar:SetSize(LABEL_SIZE + BOARD_SIZE, PLAYER_BAR_HEIGHT)
    playerBar:SetPoint("TOPLEFT", boardContainer, "BOTTOMLEFT", 0, 0)
    
    local playerBg = playerBar:CreateTexture(nil, "BACKGROUND")
    playerBg:SetAllPoints()
    playerBg:SetColorTexture(0.15, 0.15, 0.15, 0.8)
    
    -- Player name with class color
    local plR, plG, plB = DeltaChess.UI:GetPlayerColor(myName, myClass)
    local playerNameText = playerBar:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    playerNameText:SetPoint("LEFT", playerBar, "LEFT", 5, 8)
    playerNameText:SetTextColor(plR, plG, plB)
    playerNameText:SetText(myName:match("^([^%-]+)") or myName)
    
    -- Player captured pieces container
    local playerCapturedContainer = CreateFrame("Frame", nil, playerBar)
    playerCapturedContainer:SetSize(200, CAPTURED_PIECE_SIZE)
    playerCapturedContainer:SetPoint("LEFT", playerBar, "LEFT", 5, -10)
    frame.playerCapturedContainer = playerCapturedContainer
    frame.playerCapturedColor = opponentChessColor
    
    -- ==================== RIGHT PANEL ====================
    local rightPanel = CreateFrame("Frame", nil, frame)
    rightPanel:SetSize(RIGHT_PANEL_WIDTH, PLAYER_BAR_HEIGHT + BOARD_SIZE + LABEL_SIZE + PLAYER_BAR_HEIGHT)
    rightPanel:SetPoint("TOPLEFT", opponentBar, "TOPRIGHT", 10, 0)
    
    -- Move history scroll frame
    local historyHeight = rightPanel:GetHeight() - 80
    
    local historyLabel = rightPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    historyLabel:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 0, 0)
    historyLabel:SetText("Moves")
    
    local historyBg = rightPanel:CreateTexture(nil, "BACKGROUND")
    historyBg:SetPoint("TOPLEFT", historyLabel, "BOTTOMLEFT", 0, -5)
    historyBg:SetSize(RIGHT_PANEL_WIDTH, historyHeight - 20)
    historyBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
    
    local historyScroll = CreateFrame("ScrollFrame", nil, rightPanel, "UIPanelScrollFrameTemplate")
    historyScroll:SetPoint("TOPLEFT", historyBg, "TOPLEFT", 5, -5)
    historyScroll:SetSize(RIGHT_PANEL_WIDTH - 30, historyHeight - 30)
    
    local historyScrollChild = CreateFrame("Frame", nil, historyScroll)
    historyScrollChild:SetSize(RIGHT_PANEL_WIDTH - 35, 500)
    historyScroll:SetScrollChild(historyScrollChild)
    
    local historyText = historyScrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    historyText:SetPoint("TOPLEFT", historyScrollChild, "TOPLEFT", 0, 0)
    historyText:SetWidth(RIGHT_PANEL_WIDTH - 40)
    historyText:SetJustifyH("LEFT")
    historyText:SetSpacing(2)
    frame.historyText = historyText
    
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
    
    -- Update display function
    local function UpdateReplayBoard()
        local board = DeltaChess.UI:GetInitialBoardState()
        local capturedByWhite = {}
        local capturedByBlack = {}
        
        -- Apply moves and track captures (use move data, not board state, to handle promotions correctly)
        for i = 1, frame.currentMoveIndex do
            local move = frame.moves[i]
            if move then
                local movingColor = move.color
                
                -- Track captured piece using move data (handles promoted pieces correctly)
                if move.captured or move.capturedType then
                    local capturedType = move.capturedType or "pawn"
                    local capturedColor = movingColor == "white" and "black" or "white"
                    local capturedPiece = {type = capturedType, color = capturedColor}
                    
                    if movingColor == "white" then
                        table.insert(capturedByWhite, capturedPiece)
                    else
                        table.insert(capturedByBlack, capturedPiece)
                    end
                end
            end
        end
        
        -- Apply moves to get current board state
        board = DeltaChess.UI:ApplyMovesToBoard(DeltaChess.UI:GetInitialBoardState(), frame.moves, frame.currentMoveIndex)
        
        local lastMove = frame.currentMoveIndex > 0 and frame.moves[frame.currentMoveIndex] or nil
        DeltaChess.UI:RenderPieces(frame.squares, board, lastMove)
        
        -- Update move counter
        frame.moveLabel:SetText(string.format("Move: %d / %d", frame.currentMoveIndex, #frame.moves))
        
        -- Update move history with highlighting for current move
        local historyStr = ""
        for i, move in ipairs(frame.moves) do
            if i % 2 == 1 then
                historyStr = historyStr .. "|cFFAAAAAA" .. math.ceil(i / 2) .. ".|r "
            end
            
            local notation = DeltaChess.UI:FormatMoveAlgebraic(move)
            
            -- Highlight current move
            if i == frame.currentMoveIndex then
                notation = "|cFFFFFF00[" .. notation .. "]|r"
            end
            
            historyStr = historyStr .. notation .. " "
            
            if i % 2 == 0 then
                historyStr = historyStr .. "\n"
            end
        end
        frame.historyText:SetText(historyStr)
        
        -- Update captured pieces display
        local advantage = DeltaChess.UI:CalculateMaterialAdvantage(capturedByWhite, capturedByBlack)
        local myAdvantage = myChessColor == "white" and advantage or -advantage
        
        -- My captured pieces (what I captured)
        local myCaptured = myChessColor == "white" and capturedByWhite or capturedByBlack
        DeltaChess.UI:UpdateCapturedPieces(frame.playerCapturedContainer, myCaptured,
            frame.playerCapturedColor, myAdvantage > 0 and myAdvantage or nil)
        
        -- Opponent captured pieces
        local opponentCaptured = opponentChessColor == "white" and capturedByWhite or capturedByBlack
        local opponentAdvantage = -myAdvantage
        DeltaChess.UI:UpdateCapturedPieces(frame.opponentCapturedContainer, opponentCaptured,
            frame.opponentCapturedColor, opponentAdvantage > 0 and opponentAdvantage or nil)
    end
    
    -- Button handlers
    firstBtn:SetScript("OnClick", function()
        frame.currentMoveIndex = 0
        UpdateReplayBoard()
    end)
    
    prevBtn:SetScript("OnClick", function()
        if frame.currentMoveIndex > 0 then
            frame.currentMoveIndex = frame.currentMoveIndex - 1
            UpdateReplayBoard()
        end
    end)
    
    nextBtn:SetScript("OnClick", function()
        if frame.currentMoveIndex < #frame.moves then
            frame.currentMoveIndex = frame.currentMoveIndex + 1
            UpdateReplayBoard()
        end
    end)
    
    lastBtn:SetScript("OnClick", function()
        frame.currentMoveIndex = #frame.moves
        UpdateReplayBoard()
    end)
    
    -- Initial display
    UpdateReplayBoard()
    
    frame:Show()
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

    for _, game in pairs(self.db.games) do
        local ts = game.startTime or 0
        addOpponent(game.white, ts)
        addOpponent(game.black, ts)
    end
    for _, game in ipairs(self.db.history) do
        local ts = game.startTime or 0
        addOpponent(game.white, ts)
        addOpponent(game.black, ts)
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
    -- source: "past", "guild", "friends"
    local candidates = {}
    if source == "past" then
        candidates = self:GetPastOpponentsFullNames()
    elseif source == "guild" then
        candidates = self:GetGuildOnlineFullNames()
    elseif source == "friends" then
        candidates = self:GetFriendsOnlineFullNames()
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
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(parentFrame:GetFrameLevel() + 50)
    popup:SetMovable(true)
    popup:EnableMouse(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", popup.StartMoving)
    popup:SetScript("OnDragStop", popup.StopMovingOrSizing)
    local titleMap = { past = "Recent", guild = "Guild", friends = "Friends" }
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
        frame:SetSize(350, 480)
        frame:SetPoint("CENTER")
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        frame:SetFrameStrata("FULLSCREEN_DIALOG")
        frame:SetFrameLevel(100)
        frame.TitleText:SetText("Challenge Player")
        
        local yPos = -35
        
        -- Opponent selection buttons
        local selectLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        selectLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, yPos)
        selectLabel:SetText("Select opponent:")
        
        yPos = yPos - 24
        
        local pastBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        pastBtn:SetSize(105, 24)
        pastBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, yPos)
        pastBtn:SetText("Recent")
        pastBtn:SetScript("OnClick", function()
            DeltaChess:ShowPlayerListPopup("past", frame, function(fullName)
                frame.nameInput:SetText(fullName)
            end)
        end)
        
        local guildBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        guildBtn:SetSize(105, 24)
        guildBtn:SetPoint("LEFT", pastBtn, "RIGHT", 5, 0)
        guildBtn:SetText("Guild")
        guildBtn:SetScript("OnClick", function()
            DeltaChess:ShowPlayerListPopup("guild", frame, function(fullName)
                frame.nameInput:SetText(fullName)
            end)
        end)
        
        local friendsBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        friendsBtn:SetSize(105, 24)
        friendsBtn:SetPoint("LEFT", guildBtn, "RIGHT", 5, 0)
        friendsBtn:SetText("Friends")
        friendsBtn:SetScript("OnClick", function()
            DeltaChess:ShowPlayerListPopup("friends", frame, function(fullName)
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
        whiteBtn:SetSize(100, 25)
        whiteBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, yPos)
        whiteBtn:SetText("White")
        
        local blackBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        blackBtn:SetSize(100, 25)
        blackBtn:SetPoint("LEFT", whiteBtn, "RIGHT", 5, 0)
        blackBtn:SetText("Black")
        
        local randomBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        randomBtn:SetSize(100, 25)
        randomBtn:SetPoint("LEFT", blackBtn, "RIGHT", 5, 0)
        randomBtn:SetText("Random")
        
        local function updateColorButtons()
            whiteBtn:SetEnabled(frame.selectedColor ~= "white")
            blackBtn:SetEnabled(frame.selectedColor ~= "black")
            randomBtn:SetEnabled(frame.selectedColor ~= "random")
        end
        
        whiteBtn:SetScript("OnClick", function()
            frame.selectedColor = "white"
            updateColorButtons()
        end)
        
        blackBtn:SetScript("OnClick", function()
            frame.selectedColor = "black"
            updateColorButtons()
        end)
        
        randomBtn:SetScript("OnClick", function()
            frame.selectedColor = "random"
            updateColorButtons()
        end)
        
        updateColorButtons()
        
        yPos = yPos - 45
        
        -- Use clock checkbox
        local clockCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        clockCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, yPos)
        clockCheck.text:SetText("Use Chess Clock")
        clockCheck:SetChecked(false)
        frame.clockCheck = clockCheck
        
        yPos = yPos - 40
        
        -- Time per player
        local timeLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        timeLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, yPos)
        timeLabel:SetText("Time per player (minutes):")
        
        local timeValue = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        timeValue:SetPoint("LEFT", timeLabel, "RIGHT", 10, 0)
        timeValue:SetText("10")
        
        yPos = yPos - 25
        
        local timeSlider = CreateFrame("Slider", nil, frame, "OptionsSliderTemplate")
        timeSlider:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, yPos)
        timeSlider:SetSize(300, 17)
        timeSlider:SetMinMaxValues(1, 60)
        timeSlider:SetValue(10)
        timeSlider:SetValueStep(1)
        timeSlider:SetObeyStepOnDrag(true)
        timeSlider.Low:SetText("1")
        timeSlider.High:SetText("60")
        timeSlider:SetScript("OnValueChanged", function(self, value)
            timeValue:SetText(tostring(math.floor(value)))
        end)
        frame.timeSlider = timeSlider
        
        yPos = yPos - 45
        
        -- Increment per move
        local incLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        incLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, yPos)
        incLabel:SetText("Increment per move (seconds):")
        
        local incValue = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        incValue:SetPoint("LEFT", incLabel, "RIGHT", 10, 0)
        incValue:SetText("0")
        
        yPos = yPos - 25
        
        local incSlider = CreateFrame("Slider", nil, frame, "OptionsSliderTemplate")
        incSlider:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, yPos)
        incSlider:SetSize(300, 17)
        incSlider:SetMinMaxValues(0, 30)
        incSlider:SetValue(0)
        incSlider:SetValueStep(1)
        incSlider:SetObeyStepOnDrag(true)
        incSlider.Low:SetText("0")
        incSlider.High:SetText("30")
        incSlider:SetScript("OnValueChanged", function(self, value)
            incValue:SetText(tostring(math.floor(value)))
        end)
        frame.incSlider = incSlider
        
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
                    return
                end
                
                local finalColor = frame.selectedColor
                if finalColor == "random" then
                    finalColor = math.random(2) == 1 and "white" or "black"
                end
                
                local gameSettings = {
                    challenger = DeltaChess:GetFullPlayerName(UnitName("player")),
                    opponent = playerName,
                    challengerColor = finalColor,
                    useClock = frame.clockCheck:GetChecked(),
                    timeMinutes = math.floor(frame.timeSlider:GetValue()),
                    incrementSeconds = math.floor(frame.incSlider:GetValue())
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
        frame:SetSize(300, 280)
        frame:SetPoint("CENTER")
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        frame:SetFrameStrata("FULLSCREEN_DIALOG")
        frame:SetFrameLevel(100)
        frame.TitleText:SetText("Play vs Computer")
        
        local yPos = -35
        
        -- Color selection
        local colorLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        colorLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, yPos)
        colorLabel:SetText("Your Color:")
        
        yPos = yPos - 30
        
        -- Color buttons
        frame.selectedColor = "white"
        
        local whiteBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        whiteBtn:SetSize(80, 25)
        whiteBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, yPos)
        whiteBtn:SetText("White")
        whiteBtn:SetEnabled(false)
        
        local blackBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        blackBtn:SetSize(80, 25)
        blackBtn:SetPoint("LEFT", whiteBtn, "RIGHT", 5, 0)
        blackBtn:SetText("Black")
        
        local randomBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        randomBtn:SetSize(80, 25)
        randomBtn:SetPoint("LEFT", blackBtn, "RIGHT", 5, 0)
        randomBtn:SetText("Random")
        
        local function updateColorButtons()
            whiteBtn:SetEnabled(frame.selectedColor ~= "white")
            blackBtn:SetEnabled(frame.selectedColor ~= "black")
            randomBtn:SetEnabled(frame.selectedColor ~= "random")
        end
        
        whiteBtn:SetScript("OnClick", function()
            frame.selectedColor = "white"
            updateColorButtons()
        end)
        
        blackBtn:SetScript("OnClick", function()
            frame.selectedColor = "black"
            updateColorButtons()
        end)
        
        randomBtn:SetScript("OnClick", function()
            frame.selectedColor = "random"
            updateColorButtons()
        end)
        
        yPos = yPos - 50
        
        -- Difficulty slider (ELO 100-2500)
        local diffLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        diffLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, yPos)
        diffLabel:SetText("AI Strength (ELO):")
        
        yPos = yPos - 25
        
        frame.selectedDifficulty = 1200
        
        local diffValue = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        diffValue:SetPoint("LEFT", diffLabel, "RIGHT", 10, 0)
        diffValue:SetText("1200")
        frame.diffValueText = diffValue
        
        local diffSlider = CreateFrame("Slider", nil, frame, "OptionsSliderTemplate")
        diffSlider:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, yPos)
        diffSlider:SetSize(250, 17)
        diffSlider:SetMinMaxValues(100, 2500)
        diffSlider:SetValue(1200)
        diffSlider:SetValueStep(100)
        diffSlider:SetObeyStepOnDrag(true)
        diffSlider.Low:SetText("100")
        diffSlider.High:SetText("2500")
        diffSlider:SetScript("OnValueChanged", function(self, value)
            local elo = math.floor((value + 50) / 100) * 100
            elo = math.max(100, math.min(2500, elo))
            frame.selectedDifficulty = elo
            diffValue:SetText(tostring(elo))
        end)
        frame.diffSlider = diffSlider
        
        yPos = yPos - 35
        
        -- Difficulty description
        local diffDesc = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        diffDesc:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, yPos)
        diffDesc:SetWidth(260)
        diffDesc:SetJustifyH("LEFT")
        diffDesc:SetText("|cFF888888100-400: Beginner | 400-1000: Club | 1000-1600: Advanced | 1600+: Expert|r")
        
        -- Start button
        local startBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        startBtn:SetSize(120, 30)
        startBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 15, 10)
        startBtn:SetText("Start Game")
        startBtn:SetScript("OnClick", function()
            local color = frame.selectedColor
            if color == "random" then
                color = math.random(2) == 1 and "white" or "black"
            end
            
            frame:Hide()
            DeltaChess:StartComputerGame(color, frame.selectedDifficulty or 1200)
        end)
        
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
    self.frames.computerWindow.selectedColor = "white"
    self.frames.computerWindow.selectedDifficulty = 1200
    if self.frames.computerWindow.diffSlider then
        self.frames.computerWindow.diffSlider:SetValue(1200)
    end
    if self.frames.computerWindow.diffValueText then
        self.frames.computerWindow.diffValueText:SetText("1200")
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

StaticPopupDialogs["CHESS_PAUSE_REQUEST"] = {
    text = "Your opponent wants to pause the game. Do you accept?",
    button1 = "Accept",
    button2 = "Decline",
    OnAccept = function(self, popupData)
        local game = DeltaChess.db.games[popupData.gameId]
        if game then
            game.status = "paused"
            game.pauseStartTime = time()
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
    text = "Your opponent wants to resume the game. Do you accept?",
    button1 = "Accept",
    button2 = "Decline",
    OnAccept = function(self, popupData)
        local game = DeltaChess.db.games[popupData.gameId]
        if game then
            game.status = "active"
            game.pauseStartTime = nil
            DeltaChess:SendUnpauseResponse(popupData.gameId, true)
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
    for gameId, game in pairs(self.db.games) do
        if game.status == "active" then
            hasActiveGames = true
            self:Print(string.format("  %s vs %s (ID: %s)", game.white, game.black, gameId))
        end
    end
    
    if not hasActiveGames then
        self:Print("  No active games")
    end
end

-- Show game history
function DeltaChess:ShowGameHistory()
    self:Print("Game History:")
    if #self.db.history == 0 then
        self:Print("  No game history")
    else
        local count = math.min(10, #self.db.history)
        for i = #self.db.history, #self.db.history - count + 1, -1 do
            local game = self.db.history[i]
            self:Print(string.format("  %s vs %s - %s (%s)", 
                game.white, game.black, game.result or "Unknown", game.date or "Unknown"))
        end
        if #self.db.history > 10 then
            self:Print(string.format("  ... and %d more games", #self.db.history - 10))
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
