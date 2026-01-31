-- UI.lua - DeltaChess board user interface

DeltaChess.UI = {}

-- Shared constants
DeltaDeltaChess.UI.PIECE_TEXTURES = {
    white = {
        king = "Interface\\AddOns\\DeltaChess\\Textures\\white_king",
        queen = "Interface\\AddOns\\DeltaChess\\Textures\\white_queen",
        rook = "Interface\\AddOns\\DeltaChess\\Textures\\white_rook",
        bishop = "Interface\\AddOns\\DeltaChess\\Textures\\white_bishop",
        knight = "Interface\\AddOns\\DeltaChess\\Textures\\white_knight",
        pawn = "Interface\\AddOns\\DeltaChess\\Textures\\white_pawn",
    },
    black = {
        king = "Interface\\AddOns\\DeltaChess\\Textures\\black_king",
        queen = "Interface\\AddOns\\DeltaChess\\Textures\\black_queen",
        rook = "Interface\\AddOns\\DeltaChess\\Textures\\black_rook",
        bishop = "Interface\\AddOns\\DeltaChess\\Textures\\black_bishop",
        knight = "Interface\\AddOns\\DeltaChess\\Textures\\black_knight",
        pawn = "Interface\\AddOns\\DeltaChess\\Textures\\black_pawn",
    }
}

DeltaDeltaChess.UI.FILE_LABELS = {"a", "b", "c", "d", "e", "f", "g", "h"}

-- Local references for convenience
local PIECE_TEXTURES = DeltaDeltaChess.UI.PIECE_TEXTURES
local FILE_LABELS = DeltaDeltaChess.UI.FILE_LABELS

--------------------------------------------------------------------------------
-- CLOCK CALCULATION FUNCTIONS
--------------------------------------------------------------------------------

-- Calculate remaining time for a player based on move timestamps
function DeltaDeltaChess.UI:CalculateRemainingTime(game, color)
    if not game.settings.useClock then
        return nil
    end
    
    local clockData = game.clockData
    if not clockData then
        -- Fallback for old games without clockData
        return color == "white" and game.whiteTime or game.blackTime
    end
    
    local initialTime = clockData.initialTimeSeconds or 600
    local increment = clockData.incrementSeconds or 0
    local gameStartTime = clockData.gameStartTimestamp or game.startTime
    
    local moves = game.board.moves or {}
    local timeUsed = 0
    local moveCount = 0
    
    -- Calculate time used by this color
    -- White moves are at odd indices (1, 3, 5...), Black at even (2, 4, 6...)
    local startIndex = (color == "white") and 1 or 2
    
    for i = startIndex, #moves, 2 do
        local move = moves[i]
        if move and move.thinkTime then
            timeUsed = timeUsed + move.thinkTime
            moveCount = moveCount + 1
        elseif move and move.timestamp then
            -- Calculate think time from timestamps
            local prevTimestamp
            if i == 1 then
                prevTimestamp = gameStartTime
            elseif i == 2 then
                prevTimestamp = moves[1] and moves[1].timestamp or gameStartTime
            else
                prevTimestamp = moves[i - 2] and moves[i - 2].timestamp or gameStartTime
            end
            
            local thinkTime = move.timestamp - prevTimestamp
            timeUsed = timeUsed + math.max(0, thinkTime)
            moveCount = moveCount + 1
        end
    end
    
    -- Add time for current thinking if it's this color's turn
    if game.board.currentTurn == color and game.status == "active" then
        local lastMoveTimestamp
        if #moves == 0 then
            lastMoveTimestamp = gameStartTime
        else
            lastMoveTimestamp = moves[#moves].timestamp or gameStartTime
        end
        local currentThinkTime = time() - lastMoveTimestamp
        timeUsed = timeUsed + math.max(0, currentThinkTime)
    end
    
    -- Calculate total time with increments
    local totalIncrements = moveCount * increment
    local remainingTime = initialTime + totalIncrements - timeUsed
    
    return math.max(0, remainingTime)
end

-- Format time as MM:SS
function DeltaDeltaChess.UI:FormatTime(seconds)
    if not seconds then return "--:--" end
    seconds = math.floor(seconds)
    local mins = math.floor(seconds / 60)
    local secs = seconds % 60
    return string.format("%02d:%02d", mins, secs)
end

--------------------------------------------------------------------------------
-- SHARED BOARD RENDERING FUNCTIONS
--------------------------------------------------------------------------------

-- Create board squares and labels on a container frame
-- Returns a 2D table of square frames
function DeltaDeltaChess.UI:CreateBoardSquares(container, squareSize, labelSize, flipBoard, interactive)
    local squares = {}
    
    -- Create rank labels (1-8 on left side)
    for i = 1, 8 do
        local rank = flipBoard and i or (9 - i)
        local label = container:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        label:SetPoint("RIGHT", container, "TOPLEFT", labelSize - 3, -labelSize/2 - (i - 1) * squareSize - squareSize/2)
        label:SetText(tostring(rank))
    end
    
    -- Create file labels (a-h on bottom)
    for i = 1, 8 do
        local file = flipBoard and FILE_LABELS[9 - i] or FILE_LABELS[i]
        local label = container:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        label:SetPoint("TOP", container, "BOTTOMLEFT", labelSize + (i - 1) * squareSize + squareSize/2, labelSize - 3)
        label:SetText(file)
    end
    
    -- Create squares
    for row = 1, 8 do
        squares[row] = {}
        for col = 1, 8 do
            local frameType = interactive and "Button" or "Frame"
            local square = CreateFrame(frameType, nil, container)
            square:SetSize(squareSize, squareSize)
            
            -- Position based on board orientation
            local displayRow = flipBoard and row or (9 - row)
            local displayCol = flipBoard and (9 - col) or col
            
            square:SetPoint("TOPLEFT", container, "TOPLEFT", 
                labelSize + (displayCol - 1) * squareSize, -(displayRow - 1) * squareSize)
            
            -- Background
            square.bg = square:CreateTexture(nil, "BACKGROUND")
            square.bg:SetAllPoints()
            
            local isLightSquare = (row + col) % 2 == 0
            square.isLightSquare = isLightSquare
            if isLightSquare then
                square.bg:SetColorTexture(0.9, 0.9, 0.8, 1)
            else
                square.bg:SetColorTexture(0.6, 0.4, 0.2, 1)
            end
            
            -- Check indicator (for king in check) - only for interactive boards
            if interactive then
                square.checkIndicator = square:CreateTexture(nil, "BORDER")
                square.checkIndicator:SetAllPoints()
                square.checkIndicator:SetColorTexture(1, 0, 0, 0.5)
                square.checkIndicator:Hide()
            end
            
            -- Move highlight (for last move / selection)
            square.moveHighlight = square:CreateTexture(nil, "BORDER")
            square.moveHighlight:SetAllPoints()
            square.moveHighlight:SetColorTexture(1, 1, 0, 0.3)
            square.moveHighlight:Hide()
            
            -- Highlight texture (for selection) - only for interactive boards
            if interactive then
                square.highlight = square:CreateTexture(nil, "OVERLAY")
                square.highlight:SetAllPoints()
                square.highlight:SetColorTexture(0, 1, 0, 0.3)
                square.highlight:Hide()
            end
            
            -- Valid move indicator - only for interactive boards
            if interactive then
                square.validMove = square:CreateTexture(nil, "OVERLAY")
                square.validMove:SetSize(15, 15)
                square.validMove:SetPoint("CENTER")
                square.validMove:SetColorTexture(0, 1, 0, 0.6)
                square.validMove:Hide()
            end
            
            -- Piece texture
            square.pieceTexture = square:CreateTexture(nil, "ARTWORK")
            square.pieceTexture:SetSize(squareSize - 4, squareSize - 4)
            square.pieceTexture:SetPoint("CENTER")
            square.pieceTexture:Hide()
            
            square.row = row
            square.col = col
            squares[row][col] = square
        end
    end
    
    return squares
end

-- Update piece display on squares from a board state (2D array or DeltaChess.Board object)
function DeltaDeltaChess.UI:RenderPieces(squares, boardState, lastMove)
    for row = 1, 8 do
        for col = 1, 8 do
            local square = squares[row][col]
            local piece
            
            -- Support both raw 2D arrays and DeltaChess.Board objects
            if boardState.GetPiece then
                piece = boardState:GetPiece(row, col)
            elseif boardState[row] then
                piece = boardState[row][col]
            end
            
            -- Hide all highlights first
            if square.moveHighlight then square.moveHighlight:Hide() end
            if square.checkIndicator then square.checkIndicator:Hide() end
            if square.highlight then square.highlight:Hide() end
            if square.validMove then square.validMove:Hide() end
            
            -- Show last move highlight
            if lastMove then
                local fromRow = lastMove.fromRow or (lastMove.from and lastMove.from.row)
                local fromCol = lastMove.fromCol or (lastMove.from and lastMove.from.col)
                local toRow = lastMove.toRow or (lastMove.to and lastMove.to.row)
                local toCol = lastMove.toCol or (lastMove.to and lastMove.to.col)
                
                if (row == fromRow and col == fromCol) or (row == toRow and col == toCol) then
                    square.moveHighlight:Show()
                end
            end
            
            -- Update piece texture
            if piece then
                local texturePath = PIECE_TEXTURES[piece.color] and PIECE_TEXTURES[piece.color][piece.type]
                if texturePath then
                    square.pieceTexture:SetTexture(texturePath)
                    square.pieceTexture:Show()
                else
                    square.pieceTexture:Hide()
                end
            else
                square.pieceTexture:Hide()
            end
        end
    end
end

-- Get initial chess board state as 2D array
function DeltaDeltaChess.UI:GetInitialBoardState()
    local board = {}
    for row = 1, 8 do
        board[row] = {}
        for col = 1, 8 do
            board[row][col] = nil
        end
    end
    local backRow = {"rook", "knight", "bishop", "queen", "king", "bishop", "knight", "rook"}
    for col = 1, 8 do
        board[1][col] = {type = backRow[col], color = "black"}
        board[2][col] = {type = "pawn", color = "black"}
        board[7][col] = {type = "pawn", color = "white"}
        board[8][col] = {type = backRow[col], color = "white"}
    end
    return board
end

-- Apply moves to a board state (for replay)
function DeltaDeltaChess.UI:ApplyMovesToBoard(board, moves, upToIndex)
    for i = 1, upToIndex do
        local move = moves[i]
        if move then
            local fromRow = move.fromRow or (move.from and move.from.row)
            local fromCol = move.fromCol or (move.from and move.from.col)
            local toRow = move.toRow or (move.to and move.to.row)
            local toCol = move.toCol or (move.to and move.to.col)
            
            if move.castling then
                local row = fromRow
                if move.castling == "kingside" then
                    board[row][7] = board[row][5]
                    board[row][6] = board[row][8]
                    board[row][5] = nil
                    board[row][8] = nil
                else
                    board[row][3] = board[row][5]
                    board[row][4] = board[row][1]
                    board[row][5] = nil
                    board[row][1] = nil
                end
            elseif fromRow and fromCol and toRow and toCol then
                local piece = board[fromRow][fromCol]
                if piece then
                    if move.promotion then
                        piece = {type = move.promotion, color = piece.color}
                    end
                    board[toRow][toCol] = piece
                    board[fromRow][fromCol] = nil
                    
                    if move.enPassant then
                        board[fromRow][toCol] = nil
                    end
                end
            end
        end
    end
    return board
end

-- Format move as algebraic notation
function DeltaDeltaChess.UI:FormatMoveNotation(move)
    if not move then return "" end
    local pieceNames = {king = "K", queen = "Q", rook = "R", bishop = "B", knight = "N", pawn = ""}
    local fromRow = move.fromRow or (move.from and move.from.row) or 1
    local fromCol = move.fromCol or (move.from and move.from.col) or 1
    local toRow = move.toRow or (move.to and move.to.row) or 1
    local toCol = move.toCol or (move.to and move.to.col) or 1
    local pieceType = move.pieceType or move.piece or "pawn"
    
    local notation = pieceNames[pieceType] or ""
    notation = notation .. FILE_LABELS[fromCol] .. (9 - fromRow)
    notation = notation .. (move.captured and "x" or "-")
    notation = notation .. FILE_LABELS[toCol] .. (9 - toRow)
    return notation
end

--------------------------------------------------------------------------------
-- GAME BOARD (for active games)
--------------------------------------------------------------------------------

local SQUARE_SIZE = 50
local BOARD_SIZE = SQUARE_SIZE * 8
local LABEL_SIZE = 20
local PLAYER_BAR_HEIGHT = 45
local RIGHT_PANEL_WIDTH = 220

-- Piece values for material calculation
local PIECE_VALUES = {
    pawn = 1,
    knight = 3,
    bishop = 3,
    rook = 5,
    queen = 9,
    king = 0
}

-- Get class color for a player name (returns r, g, b)
-- savedClass: optional class token (e.g., "WARRIOR") for when player is offline
function DeltaDeltaChess.UI:GetPlayerColor(playerName, savedClass)
    if playerName == "Computer" then
        return 0.7, 0.7, 0.7 -- Gray for computer
    end
    
    -- If savedClass is provided, use it directly
    if savedClass and RAID_CLASS_COLORS[savedClass] then
        local color = RAID_CLASS_COLORS[savedClass]
        return color.r, color.g, color.b
    end
    
    -- Try to get class from name (only works if player is nearby/cached)
    local name = playerName:match("^([^%-]+)")
    if name then
        local _, class = UnitClass(name)
        if class and RAID_CLASS_COLORS[class] then
            local color = RAID_CLASS_COLORS[class]
            return color.r, color.g, color.b
        end
    end
    
    return 1, 0.82, 0 -- Gold default
end

-- Calculate material advantage
function DeltaDeltaChess.UI:CalculateMaterialAdvantage(capturedByWhite, capturedByBlack)
    local whitePoints = 0
    local blackPoints = 0
    
    -- Points white has captured (from black pieces)
    for _, piece in ipairs(capturedByWhite or {}) do
        whitePoints = whitePoints + (PIECE_VALUES[piece.type] or 0)
    end
    
    -- Points black has captured (from white pieces)
    for _, piece in ipairs(capturedByBlack or {}) do
        blackPoints = blackPoints + (PIECE_VALUES[piece.type] or 0)
    end
    
    return whitePoints - blackPoints -- Positive = white ahead
end

-- Size for captured piece icons
local CAPTURED_PIECE_SIZE = 18

-- Update captured pieces display with small icons
function DeltaDeltaChess.UI:UpdateCapturedPieces(container, capturedPieces, capturedColor, advantage)
    -- Clear existing textures
    for _, child in ipairs({container:GetRegions()}) do
        child:Hide()
    end
    
    if not capturedPieces or #capturedPieces == 0 then
        -- Just show advantage if any
        if advantage and advantage > 0 then
            local advText = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            advText:SetPoint("LEFT", container, "LEFT", 0, 0)
            advText:SetText("|cFF00FF00+" .. advantage .. "|r")
        end
        return
    end
    
    -- Sort by value (highest first)
    local sorted = {}
    for _, piece in ipairs(capturedPieces) do
        table.insert(sorted, piece)
    end
    table.sort(sorted, function(a, b)
        return (PIECE_VALUES[a.type] or 0) > (PIECE_VALUES[b.type] or 0)
    end)
    
    -- Create textures for each captured piece
    local xOffset = 0
    for i, piece in ipairs(sorted) do
        local texturePath = PIECE_TEXTURES[capturedColor][piece.type]
        if texturePath then
            local tex = container:CreateTexture(nil, "OVERLAY")
            tex:SetSize(CAPTURED_PIECE_SIZE, CAPTURED_PIECE_SIZE)
            tex:SetPoint("LEFT", container, "LEFT", xOffset, 0)
            tex:SetTexture(texturePath)
            tex:Show()
            xOffset = xOffset + CAPTURED_PIECE_SIZE - 4 -- Slight overlap for compact display
        end
    end
    
    -- Show advantage after the pieces
    if advantage and advantage > 0 then
        local advText = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        advText:SetPoint("LEFT", container, "LEFT", xOffset + 5, 0)
        advText:SetText("|cFF00FF00+" .. advantage .. "|r")
    end
end

-- Format move in standard algebraic notation
function DeltaDeltaChess.UI:FormatMoveAlgebraic(move)
    if not move then return "" end
    
    local pieceSymbols = {
        king = "K",
        queen = "Q", 
        rook = "R",
        bishop = "B",
        knight = "N",
        pawn = ""
    }
    
    -- Handle castling
    if move.castle == "kingside" then
        return "O-O"
    elseif move.castle == "queenside" then
        return "O-O-O"
    end
    
    local toRow = move.toRow or (move.to and move.to.row) or 1
    local toCol = move.toCol or (move.to and move.to.col) or 1
    local fromCol = move.fromCol or (move.from and move.from.col) or 1
    local pieceType = move.piece or move.pieceType or "pawn"
    
    local notation = pieceSymbols[pieceType] or ""
    
    -- For pawns, include file on capture
    if pieceType == "pawn" and move.captured then
        notation = FILE_LABELS[fromCol]
    end
    
    -- Add capture symbol
    if move.captured then
        notation = notation .. "x"
    end
    
    -- Destination square
    notation = notation .. FILE_LABELS[toCol] .. (9 - toRow)
    
    -- Promotion
    if move.promotion then
        notation = notation .. "=" .. (pieceSymbols[move.promotion] or "Q")
    end
    
    return notation
end

-- Show chess board for a game
function DeltaChess:ShowChessBoard(gameId)
    local game = self.db.games[gameId]
    if not game then
        self:Print("Game not found!")
        return
    end
    
    -- Close existing board if open
    if DeltaDeltaChess.UI.activeFrame then
        DeltaDeltaChess.UI.activeFrame:Hide()
    end
    
    -- Determine player's color for board orientation
    local playerName = self:GetFullPlayerName(UnitName("player"))
    local playerColor = "white" -- default
    if game.isVsComputer then
        playerColor = game.playerColor
    elseif game.black == playerName then
        playerColor = "black"
    elseif game.white == playerName then
        playerColor = "white"
    end
    
    -- Flip board if player is black (so their pieces are at bottom)
    local flipBoard = (playerColor == "black")
    
    -- Determine who is "us" and who is "opponent"
    local myName, opponentName, myChessColor, opponentChessColor, myClass, opponentClass
    if playerColor == "white" then
        myName = game.white
        opponentName = game.black
        myChessColor = "white"
        opponentChessColor = "black"
        myClass = game.whiteClass
        opponentClass = game.blackClass
    else
        myName = game.black
        opponentName = game.white
        myChessColor = "black"
        opponentChessColor = "white"
        myClass = game.blackClass
        opponentClass = game.whiteClass
    end
    
    -- Create main frame
    local totalWidth = LABEL_SIZE + BOARD_SIZE + 15 + RIGHT_PANEL_WIDTH + 15
    local totalHeight = 30 + PLAYER_BAR_HEIGHT + BOARD_SIZE + LABEL_SIZE + PLAYER_BAR_HEIGHT + 10
    
    local frame = CreateFrame("Frame", "ChessBoardFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(totalWidth, totalHeight)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(100)
    frame.TitleText:SetText("DeltaChess")
    
    -- Store references
    frame.gameId = gameId
    frame.game = game
    frame.board = game.board
    frame.selectedSquare = nil
    frame.validMoves = {}
    frame.flipBoard = flipBoard
    frame.playerColor = playerColor
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
    
    -- Opponent clock (if enabled)
    if game.settings.useClock then
        local opponentClock = opponentBar:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        opponentClock:SetPoint("RIGHT", opponentBar, "RIGHT", -10, 0)
        frame.opponentClock = opponentClock
        frame.opponentClockColor = opponentChessColor
    end
    
    -- Opponent captured pieces container (frame for icons)
    local opponentCapturedContainer = CreateFrame("Frame", nil, opponentBar)
    opponentCapturedContainer:SetSize(200, CAPTURED_PIECE_SIZE)
    opponentCapturedContainer:SetPoint("LEFT", opponentBar, "LEFT", 5, -10)
    frame.opponentCapturedContainer = opponentCapturedContainer
    frame.opponentCapturedColor = myChessColor  -- Opponent captures MY pieces
    
    -- ==================== BOARD ====================
    local boardContainer = CreateFrame("Frame", nil, frame)
    boardContainer:SetSize(BOARD_SIZE + LABEL_SIZE, BOARD_SIZE + LABEL_SIZE)
    boardContainer:SetPoint("TOPLEFT", opponentBar, "BOTTOMLEFT", 0, 0)
    frame.boardContainer = boardContainer
    
    -- Create squares
    frame.squares = DeltaChess.UI:CreateBoardSquares(boardContainer, SQUARE_SIZE, LABEL_SIZE, flipBoard, true)
    
    -- Add click handlers
    for row = 1, 8 do
        for col = 1, 8 do
            local square = frame.squares[row][col]
            square:SetScript("OnClick", function()
                DeltaChess.UI:OnSquareClick(frame, row, col)
            end)
        end
    end
    
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
    
    -- Player clock (if enabled)
    if game.settings.useClock then
        local playerClock = playerBar:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        playerClock:SetPoint("RIGHT", playerBar, "RIGHT", -10, 0)
        frame.playerClock = playerClock
        frame.playerClockColor = myChessColor
    end
    
    -- Player captured pieces container (frame for icons)
    local playerCapturedContainer = CreateFrame("Frame", nil, playerBar)
    playerCapturedContainer:SetSize(200, CAPTURED_PIECE_SIZE)
    playerCapturedContainer:SetPoint("LEFT", playerBar, "LEFT", 5, -10)
    frame.playerCapturedContainer = playerCapturedContainer
    frame.playerCapturedColor = opponentChessColor  -- Player captures OPPONENT pieces
    
    -- ==================== RIGHT PANEL ====================
    local rightPanel = CreateFrame("Frame", nil, frame)
    rightPanel:SetSize(RIGHT_PANEL_WIDTH, PLAYER_BAR_HEIGHT + BOARD_SIZE + LABEL_SIZE + PLAYER_BAR_HEIGHT)
    rightPanel:SetPoint("TOPLEFT", opponentBar, "TOPRIGHT", 10, 0)
    
    -- Move history scroll frame (top portion)
    local historyHeight = rightPanel:GetHeight() - 50
    
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
    frame.historyScrollChild = historyScrollChild
    
    -- Turn indicator
    local turnLabel = rightPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    turnLabel:SetPoint("BOTTOMLEFT", rightPanel, "BOTTOMLEFT", 0, 35)
    frame.turnLabel = turnLabel
    
    -- Action buttons (bottom row)
    local buttonWidth = 65
    local buttonSpacing = 5
    
    local resignButton = CreateFrame("Button", nil, rightPanel, "UIPanelButtonTemplate")
    resignButton:SetSize(buttonWidth, 25)
    resignButton:SetPoint("BOTTOMLEFT", rightPanel, "BOTTOMLEFT", 0, 5)
    resignButton:SetText("Resign")
    resignButton:SetScript("OnClick", function()
        DeltaChess:ResignGame(gameId)
    end)
    frame.resignButton = resignButton
    
    local drawButton = CreateFrame("Button", nil, rightPanel, "UIPanelButtonTemplate")
    drawButton:SetSize(buttonWidth, 25)
    drawButton:SetPoint("LEFT", resignButton, "RIGHT", buttonSpacing, 0)
    drawButton:SetText("Draw")
    drawButton:SetScript("OnClick", function()
        DeltaChess:OfferDraw(gameId)
    end)
    frame.drawButton = drawButton
    frame.isVsComputer = game.isVsComputer
    
    if game.isVsComputer then
        drawButton:Disable()
    end
    
    local closeButton = CreateFrame("Button", nil, rightPanel, "UIPanelButtonTemplate")
    closeButton:SetSize(buttonWidth, 25)
    closeButton:SetPoint("LEFT", drawButton, "RIGHT", buttonSpacing, 0)
    closeButton:SetText("Close")
    closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)
    
    -- Update the board display
    DeltaChess.UI:UpdateBoard(frame)
    
    -- Start clock if applicable
    if game.settings.useClock and game.status == "active" then
        DeltaChess.UI:StartClock(frame)
    end
    
    frame:Show()
    
    -- Store frame reference
    DeltaDeltaChess.UI.activeFrame = frame
    
    -- Check if there's a pending ACK for this game and show waiting overlay
    if not game.isVsComputer and DeltaChess:IsBoardLocked(gameId) then
        DeltaChess.UI:ShowWaitingOverlay(frame, true)
    end
end

-- Update board display
function DeltaDeltaChess.UI:UpdateBoard(frame)
    local board = frame.board
    local game = frame.game
    
    -- Find kings and check if in check
    local whiteKingPos, blackKingPos = nil, nil
    for row = 1, 8 do
        for col = 1, 8 do
            local piece = board:GetPiece(row, col)
            if piece and piece.type == "king" then
                if piece.color == "white" then
                    whiteKingPos = {row = row, col = col}
                else
                    blackKingPos = {row = row, col = col}
                end
            end
        end
    end
    
    local whiteInCheck = board:IsInCheck("white")
    local blackInCheck = board:IsInCheck("black")
    
    -- Update squares
    for row = 1, 8 do
        for col = 1, 8 do
            local square = frame.squares[row][col]
            local piece = board:GetPiece(row, col)
            
            -- Reset indicators
            if square.checkIndicator then square.checkIndicator:Hide() end
            if square.highlight then square.highlight:Hide() end
            if square.validMove then square.validMove:Hide() end
            
            -- Show check indicator on king's square
            if square.checkIndicator then
                if whiteInCheck and whiteKingPos and row == whiteKingPos.row and col == whiteKingPos.col then
                    square.checkIndicator:Show()
                elseif blackInCheck and blackKingPos and row == blackKingPos.row and col == blackKingPos.col then
                    square.checkIndicator:Show()
                end
            end
            
            if piece then
                local texturePath = PIECE_TEXTURES[piece.color][piece.type]
                if texturePath then
                    square.pieceTexture:SetTexture(texturePath)
                    square.pieceTexture:Show()
                end
            else
                square.pieceTexture:Hide()
            end
        end
    end
    
    -- Update turn indicator
    local turn = board.currentTurn
    local turnColor = turn == "white" and "|cFFFFFFFF" or "|cFF888888"
    if frame.turnLabel then
        frame.turnLabel:SetText(turnColor .. (turn == "white" and "White" or "Black") .. " to move|r")
    end
    
    -- Calculate material advantage
    local capturedByWhite = board.capturedPieces["white"] or {}  -- Pieces white captured (black pieces)
    local capturedByBlack = board.capturedPieces["black"] or {}  -- Pieces black captured (white pieces)
    local advantage = DeltaChess.UI:CalculateMaterialAdvantage(capturedByWhite, capturedByBlack)
    
    -- Update captured pieces display with icons
    local myColor = frame.myChessColor
    local opponentColor = frame.opponentChessColor
    local myAdvantage = myColor == "white" and advantage or -advantage
    
    -- My captured pieces (what I captured from opponent - show opponent's color pieces)
    local myCaptured = myColor == "white" and capturedByWhite or capturedByBlack
    if frame.playerCapturedContainer then
        DeltaChess.UI:UpdateCapturedPieces(frame.playerCapturedContainer, myCaptured, 
            frame.playerCapturedColor, myAdvantage > 0 and myAdvantage or nil)
    end
    
    -- Opponent captured pieces (what they captured from me - show my color pieces)
    local opponentCaptured = opponentColor == "white" and capturedByWhite or capturedByBlack
    local opponentAdvantage = -myAdvantage
    if frame.opponentCapturedContainer then
        DeltaChess.UI:UpdateCapturedPieces(frame.opponentCapturedContainer, opponentCaptured,
            frame.opponentCapturedColor, opponentAdvantage > 0 and opponentAdvantage or nil)
    end
    
    -- Update clocks
    if game.settings.useClock then
        local whiteTime = DeltaChess.UI:CalculateRemainingTime(game, "white")
        local blackTime = DeltaChess.UI:CalculateRemainingTime(game, "black")
        
        if frame.playerClock then
            local myTime = myColor == "white" and whiteTime or blackTime
            local myTurn = board.currentTurn == myColor
            local timeColor = myTurn and "|cFFFFFF00" or "|cFFFFFFFF"
            frame.playerClock:SetText(timeColor .. DeltaChess.UI:FormatTime(myTime) .. "|r")
        end
        
        if frame.opponentClock then
            local opponentTime = opponentColor == "white" and whiteTime or blackTime
            local opponentTurn = board.currentTurn == opponentColor
            local timeColor = opponentTurn and "|cFFFFFF00" or "|cFFFFFFFF"
            frame.opponentClock:SetText(timeColor .. DeltaChess.UI:FormatTime(opponentTime) .. "|r")
        end
    end
    
    -- Update move history in algebraic notation
    local historyStr = ""
    for i, move in ipairs(board.moves) do
        if i % 2 == 1 then
            historyStr = historyStr .. "|cFFAAAAAA" .. math.ceil(i / 2) .. ".|r "
        end
        
        local notation = DeltaChess.UI:FormatMoveAlgebraic(move)
        historyStr = historyStr .. notation .. " "
        
        if i % 2 == 0 then
            historyStr = historyStr .. "\n"
        end
    end
    
    if frame.historyText then
        frame.historyText:SetText(historyStr)
    end
    
    -- Check for game end
    if board.gameStatus ~= "active" then
        DeltaChess.UI:ShowGameEnd(frame)
    end
end

-- Show/hide waiting overlay when waiting for ACK
function DeltaDeltaChess.UI:ShowWaitingOverlay(frame, show)
    if not frame then return end
    
    if show then
        -- Create overlay if it doesn't exist
        if not frame.waitingOverlay then
            local overlay = CreateFrame("Frame", nil, frame)
            overlay:SetAllPoints(frame.boardContainer)
            overlay:SetFrameLevel(frame:GetFrameLevel() + 10)
            
            local bg = overlay:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0, 0, 0, 0.5)
            
            local text = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            text:SetPoint("CENTER")
            text:SetText("|cFFFFFF00Waiting for confirmation...|r")
            
            -- Spinning indicator
            local spinner = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
            spinner:SetPoint("CENTER", text, "TOP", 0, 20)
            spinner:SetText("|cFFFFFF00...|r")
            
            frame.waitingOverlay = overlay
        end
        
        frame.waitingOverlay:Show()
        
        -- Disable action buttons
        if frame.resignButton then
            frame.resignButton:Disable()
        end
        if frame.drawButton and not frame.isVsComputer then
            frame.drawButton:Disable()
        end
    else
        if frame.waitingOverlay then
            frame.waitingOverlay:Hide()
        end
        
        -- Re-enable action buttons
        if frame.resignButton then
            frame.resignButton:Enable()
        end
        if frame.drawButton and not frame.isVsComputer then
            frame.drawButton:Enable()
        end
    end
end

-- Handle square click
function DeltaDeltaChess.UI:OnSquareClick(frame, row, col)
    local board = frame.board
    local piece = board:GetPiece(row, col)
    local playerName = DeltaChess:GetFullPlayerName(UnitName("player"))
    local game = frame.game
    
    -- Check if board is locked (waiting for ACK)
    if not game.isVsComputer and DeltaChess:IsBoardLocked(frame.gameId) then
        DeltaChess:Print("Waiting for opponent to confirm previous move...")
        return
    end
    
    -- Check if it's player's turn
    local playerColor = nil
    if game.isVsComputer then
        -- In computer games, use stored player color
        playerColor = game.playerColor
    else
        -- In multiplayer, check by name
        if game.white == playerName then
            playerColor = "white"
        elseif game.black == playerName then
            playerColor = "black"
        end
    end
    
    if not playerColor or board.currentTurn ~= playerColor then
        if game.isVsComputer then
            DeltaChess:Print("Wait for the computer to move!")
        else
            DeltaChess:Print("It's not your turn!")
        end
        return
    end
    
    if board.gameStatus ~= "active" then
        DeltaChess:Print("Game has ended!")
        return
    end
    
    -- If no piece selected
    if not frame.selectedSquare then
        if piece and piece.color == board.currentTurn then
            -- Select piece
            frame.selectedSquare = {row = row, col = col}
            frame.validMoves = board:GetValidMoves(row, col)
            
            -- Highlight selected square
            frame.squares[row][col].highlight:Show()
            
            -- Show valid moves
            for _, move in ipairs(frame.validMoves) do
                frame.squares[move.row][move.col].validMove:Show()
            end
        end
    else
        -- Check if clicking on valid move
        local isValidMove = false
        for _, move in ipairs(frame.validMoves) do
            if move.row == row and move.col == col then
                isValidMove = true
                break
            end
        end
        
        if isValidMove then
            local fromRow, fromCol = frame.selectedSquare.row, frame.selectedSquare.col
            
            -- Handle based on game type
            if game.isVsComputer then
                -- Make the move immediately for computer games
                board:MakeMove(fromRow, fromCol, row, col)
                
                -- Clear selection
                frame.selectedSquare = nil
                frame.validMoves = {}
                
                -- Update display
                DeltaChess.UI:UpdateBoard(frame)
                
                -- Check for game end
                if board.gameStatus ~= "active" then
                    DeltaChess.UI:ShowGameEnd(frame)
                    return
                end
                
                -- Trigger AI move
                DeltaChess.AI:MakeMove(frame.gameId, 0.5)
            else
                -- For multiplayer: send move first, apply after ACK
                -- Clear selection visually
                frame.selectedSquare = nil
                frame.validMoves = {}
                for r = 1, 8 do
                    for c = 1, 8 do
                        frame.squares[r][c].highlight:Hide()
                        frame.squares[r][c].validMove:Hide()
                    end
                end
                
                -- Send move and wait for ACK (move will be applied when ACK received)
                DeltaChess:SendMoveWithConfirmation(frame.gameId, fromRow, fromCol, row, col)
            end
            
        elseif piece and piece.color == board.currentTurn then
            -- Select different piece
            frame.selectedSquare = {row = row, col = col}
            frame.validMoves = board:GetValidMoves(row, col)
            
            -- Clear previous highlights
            for r = 1, 8 do
                for c = 1, 8 do
                    frame.squares[r][c].highlight:Hide()
                    frame.squares[r][c].validMove:Hide()
                end
            end
            
            -- Highlight new selection
            frame.squares[row][col].highlight:Show()
            
            -- Show valid moves
            for _, move in ipairs(frame.validMoves) do
                frame.squares[move.row][move.col].validMove:Show()
            end
        else
            -- Deselect
            frame.selectedSquare = nil
            frame.validMoves = {}
            
            -- Clear highlights
            for r = 1, 8 do
                for c = 1, 8 do
                    frame.squares[r][c].highlight:Hide()
                    frame.squares[r][c].validMove:Hide()
                end
            end
        end
    end
end

-- Format time for clock display
function DeltaDeltaChess.UI:FormatTime(seconds)
    local mins = math.floor(seconds / 60)
    local secs = seconds % 60
    return string.format("%d:%02d", mins, secs)
end

-- Start clock (recalculates time from timestamps each tick)
function DeltaDeltaChess.UI:StartClock(frame)
    local game = frame.game
    local board = frame.board
    local myColor = frame.myChessColor
    local opponentColor = frame.opponentChessColor
    
    frame.clockTicker = C_Timer.NewTicker(1, function()
        if not frame:IsShown() or game.status ~= "active" or board.gameStatus ~= "active" then
            if frame.clockTicker then
                frame.clockTicker:Cancel()
            end
            return
        end
        
        -- Calculate remaining time from move timestamps
        local whiteTime = DeltaChess.UI:CalculateRemainingTime(game, "white")
        local blackTime = DeltaChess.UI:CalculateRemainingTime(game, "black")
        
        -- Update player clock
        if frame.playerClock then
            local myTime = myColor == "white" and whiteTime or blackTime
            local myTurn = board.currentTurn == myColor
            local timeColor = myTurn and "|cFFFFFF00" or "|cFFFFFFFF"
            frame.playerClock:SetText(timeColor .. DeltaChess.UI:FormatTime(myTime) .. "|r")
        end
        
        -- Update opponent clock
        if frame.opponentClock then
            local opponentTime = opponentColor == "white" and whiteTime or blackTime
            local opponentTurn = board.currentTurn == opponentColor
            local timeColor = opponentTurn and "|cFFFFFF00" or "|cFFFFFFFF"
            frame.opponentClock:SetText(timeColor .. DeltaChess.UI:FormatTime(opponentTime) .. "|r")
        end
        
        -- Check for timeout
        if whiteTime <= 0 and board.currentTurn == "white" then
            DeltaChess:TimeOut(frame.gameId, "white")
        elseif blackTime <= 0 and board.currentTurn == "black" then
            DeltaChess:TimeOut(frame.gameId, "black")
        end
    end)
end

-- Show game end screen
function DeltaDeltaChess.UI:ShowGameEnd(frame)
    local board = frame.board
    local game = frame.game
    local playerName = DeltaChess:GetFullPlayerName(UnitName("player"))
    
    local resultText = ""
    local playerResult = "draw" -- default
    
    if board.gameStatus == "checkmate" then
        local winner = board.currentTurn == "white" and "Black" or "White"
        local winnerName = board.currentTurn == "white" and game.black or game.white
        resultText = winner .. " wins by checkmate!"
        
        -- Determine result from player's perspective
        if game.isVsComputer then
            playerResult = (game.playerColor ~= board.currentTurn) and "won" or "lost"
        else
            playerResult = (winnerName == playerName) and "won" or "lost"
        end
    elseif board.gameStatus == "stalemate" then
        resultText = "Draw by stalemate!"
        playerResult = "draw"
    elseif board.gameStatus == "draw" then
        resultText = "Draw!"
        playerResult = "draw"
    elseif board.gameStatus == "resignation" then
        resultText = game.resignedPlayer .. " resigned. " .. 
                     (game.resignedPlayer == game.white and game.black or game.white) .. " wins!"
        playerResult = (game.resignedPlayer == playerName or 
                       (game.isVsComputer and game.resignedPlayer ~= "Computer")) and "resigned" or "won"
    elseif board.gameStatus == "timeout" then
        resultText = game.timeoutPlayer .. " ran out of time. " ..
                     (game.timeoutPlayer == game.white and game.black or game.white) .. " wins!"
        playerResult = (game.timeoutPlayer == playerName) and "lost" or "won"
    end
    
    -- Save the game to history (only if still in active games)
    if DeltaChess.db.games[frame.gameId] then
        game.endTime = time()
        DeltaChess:SaveGameToHistory(game, playerResult)
    end
    
    StaticPopup_Show("CHESS_GAME_END", resultText)
end

-- Game end popup
StaticPopupDialogs["CHESS_GAME_END"] = {
    text = "%s",
    button1 = "OK",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Draw offer popup
StaticPopupDialogs["CHESS_DRAW_OFFER"] = {
    text = "Your opponent offers a draw. Do you accept?",
    button1 = "Accept",
    button2 = "Decline",
    OnAccept = function(self, gameId)
        DeltaChess:AcceptDraw(gameId)
    end,
    OnCancel = function(self, gameId)
        DeltaChess:DeclineDraw(gameId)
    end,
    timeout = 30,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}
