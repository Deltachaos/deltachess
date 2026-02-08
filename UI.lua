-- UI.lua - DeltaChess board user interface

DeltaChess.UI = {}

-- Piece textures indexed by UCI piece character (uppercase = white, lowercase = black)
DeltaChess.UI.PIECE_TEXTURES = {
    K = "Interface\\AddOns\\DeltaChess\\Textures\\white\\K",
    Q = "Interface\\AddOns\\DeltaChess\\Textures\\white\\Q",
    R = "Interface\\AddOns\\DeltaChess\\Textures\\white\\R",
    B = "Interface\\AddOns\\DeltaChess\\Textures\\white\\B",
    N = "Interface\\AddOns\\DeltaChess\\Textures\\white\\N",
    P = "Interface\\AddOns\\DeltaChess\\Textures\\white\\P",
    k = "Interface\\AddOns\\DeltaChess\\Textures\\black\\k",
    q = "Interface\\AddOns\\DeltaChess\\Textures\\black\\q",
    r = "Interface\\AddOns\\DeltaChess\\Textures\\black\\r",
    b = "Interface\\AddOns\\DeltaChess\\Textures\\black\\b",
    n = "Interface\\AddOns\\DeltaChess\\Textures\\black\\n",
    p = "Interface\\AddOns\\DeltaChess\\Textures\\black\\p",
}

-- Get texture path for a piece character
function DeltaChess.UI:GetPieceTexture(piece)
    return self.PIECE_TEXTURES[piece]
end

DeltaChess.UI.FILE_LABELS = {"a", "b", "c", "d", "e", "f", "g", "h"}

-- Local references for convenience
local PIECE_TEXTURES = DeltaChess.UI.PIECE_TEXTURES
local FILE_LABELS = DeltaChess.UI.FILE_LABELS
local Constants = DeltaChess.Constants
local STATUS = {
    ACTIVE = Constants.STATUS_ACTIVE,
    PAUSED = Constants.STATUS_PAUSED,
    ENDED = Constants.STATUS_ENDED,
}
local COLOR = DeltaChess.Constants.COLOR

--- Get a colored status text string for a board's current game state.
-- Returns a WoW color-coded string like "|cFFFF4444Checkmate — White wins|r"
-- @param board Board object
-- @param playerColor string|nil Optional player color (COLOR.WHITE or COLOR.BLACK) to show "YOUR TURN" / "Waiting..." for active games
-- @return string colored status text
function DeltaChess.UI:GetGameStatusText(board, playerColor)
    if board:IsPaused() then
        return "|cFFFFFF00Game Paused|r"
    elseif board:IsActive() then
        local turn = board:GetCurrentTurn()
        if playerColor then
            if turn == playerColor then
                return "|cFF00FF00YOUR TURN|r"
            else
                return "|cFF888888Waiting...|r"
            end
        end
        local turnColor = turn == COLOR.WHITE and "|cFFFFFFFF" or "|cFF888888"
        return turnColor .. (turn == COLOR.WHITE and "White" or "Black") .. " to move|r"
    end
    -- Game has ended
    local reason = board:GetEndReason()
    local result = board:GetResult()
    local winnerLabel = result == Constants.WHITE and "White" or (result == Constants.BLACK and "Black" or nil)
    if reason == Constants.REASON_CHECKMATE then
        return "|cFFFF4444Checkmate - " .. (winnerLabel or "???") .. " wins|r"
    elseif reason == Constants.REASON_STALEMATE then
        return "|cFFFFFF00Stalemate - Draw|r"
    elseif reason == Constants.REASON_FIFTY_MOVE then
        local drawDetail = " (50-move rule)"
        return "|cFFFFFF00Draw" .. drawDetail .. "|r"
    elseif reason == Constants.REASON_RESIGNATION then
        return "|cFFFF4444Resignation - " .. (winnerLabel or "???") .. " wins|r"
    elseif reason == Constants.REASON_TIMEOUT then
        return "|cFFFF4444Timeout - " .. (winnerLabel or "???") .. " wins|r"
    else
        return "|cFFFF4444Game Over|r"
    end
end

-- Square coordinate conversions
local FILE_TO_COL = { a = 1, b = 2, c = 3, d = 4, e = 5, f = 6, g = 7, h = 8 }

--- Parse a square string (e.g., "e2") into its components.
-- @param square string like "e2"
-- @return file string (e.g., "e"), rank number (e.g., 2), col number (1-8), row number (1-8)
-- @return nil, nil, nil, nil if invalid
local function ParseSquare(square)
    if not square or #square < 2 then
        return nil, nil, nil, nil
    end
    local file = square:sub(1, 1)
    local rank = tonumber(square:sub(2, 2))
    local col = FILE_TO_COL[file]
    if not col or not rank then
        return nil, nil, nil, nil
    end
    return file, rank, col, rank
end

-- Board layout constants (shared across functions)
local SQUARE_SIZE = 50
local BOARD_SIZE = SQUARE_SIZE * 8
local LABEL_SIZE = 20
local PLAYER_BAR_HEIGHT = 45
local RIGHT_PANEL_WIDTH = 220
local CAPTURED_PIECE_SIZE = 18

-- Animation settings
DeltaChess.UI.ANIMATION_DURATION = 0.2 -- seconds for piece movement animation
DeltaChess.UI.animatingPiece = nil -- currently animating piece frame

--------------------------------------------------------------------------------
-- CLOCK CALCULATION FUNCTIONS (delegate to Board:TimeLeft / Board:TimeThinking)
--------------------------------------------------------------------------------

-- Calculate remaining time for a player (uses board:TimeLeft when clock is enabled).
function DeltaChess.UI:CalculateRemainingTime(board, color)
    local settings = board:GetGameMeta("settings")
    if not settings or not settings.useClock then
        return nil
    end
    return board:TimeLeft(color)
end

-- Format time as MM:SS
function DeltaChess.UI:FormatTime(seconds)
    if not seconds then return "--:--" end
    seconds = math.floor(seconds)
    local mins = math.floor(seconds / 60)
    local secs = seconds % 60
    return string.format("%02d:%02d", mins, secs)
end

-- Calculate total thinking time for a color (uses board:TimeThinking).
function DeltaChess.UI:CalculateTotalThinkingTime(board, color)
    if not board then return 0 end
    return board:TimeThinking(color) or 0
end

--------------------------------------------------------------------------------
-- SHARED BOARD RENDERING FUNCTIONS
--------------------------------------------------------------------------------

-- Create board squares and labels on a container frame
-- Returns a table keyed by UCI square notation (e.g., squares.e4, squares.a1)
function DeltaChess.UI:CreateBoardSquares(container, squareSize, labelSize, flipBoard, interactive)
    local squares = {}
    local Board = DeltaChess.Board
    
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
    
    -- Create squares keyed by UCI notation
    for row = 1, 8 do
        for col = 1, 8 do
            local uci = Board.ToSquare(row, col)
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
            
            -- Check indicator (for king in check) - game and replay boards
            square.checkIndicator = square:CreateTexture(nil, "BORDER")
            square.checkIndicator:SetAllPoints()
            square.checkIndicator:SetColorTexture(1, 0, 0, 0.5)
            square.checkIndicator:Hide()
            
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
            
            square.uci = uci
            squares[uci] = square
        end
    end
    
    return squares
end

-- Update piece display on squares from a board state (2D array or DeltaChess.Board object)
-- lastMove can be a BoardMove object or have fromSquare/toSquare UCI strings
function DeltaChess.UI:RenderPieces(squares, boardState, lastMove)
    local Board = DeltaChess.Board
    
    -- Get last move squares for highlighting
    local lastMoveFrom, lastMoveTo
    if lastMove then
        if lastMove.GetFromSquare then
            lastMoveFrom = lastMove:GetFromSquare()
            lastMoveTo = lastMove:GetToSquare()
        elseif lastMove.fromSquare then
            lastMoveFrom = lastMove.fromSquare
            lastMoveTo = lastMove.toSquare
        end
    end
    
    for row = 1, 8 do
        for col = 1, 8 do
            local uci = Board.ToSquare(row, col)
            local square = squares[uci]
            local piece
            
            -- Support both raw 2D arrays and DeltaChess.Board objects
            if boardState.GetPiece then
                piece = boardState:GetPiece(row, col)
            elseif boardState[row] then
                piece = boardState[row][col]
            end
            
            -- Hide all highlights first
            if square.checkIndicator then square.checkIndicator:Hide() end
            if square.highlight then square.highlight:Hide() end
            if square.validMove then square.validMove:Hide() end
            
            -- Last move: highlight via background color (always visible, not covered by pieces)
            local isLastMoveSquare = (uci == lastMoveFrom or uci == lastMoveTo)
            if isLastMoveSquare then
                -- Subtle yellow highlight, respecting light/dark squares
                if square.isLightSquare then
                    square.bg:SetColorTexture(0.96, 0.94, 0.72, 1)
                else
                    square.bg:SetColorTexture(0.72, 0.6, 0.28, 1)
                end
            else
                if square.isLightSquare then
                    square.bg:SetColorTexture(0.9, 0.9, 0.8, 1)
                else
                    square.bg:SetColorTexture(0.6, 0.4, 0.2, 1)
                end
            end
            
            -- Show check indicator on king's square when board is in check (game and replay)
            if square.checkIndicator and boardState.InCheck and boardState.GetCurrentTurn and boardState:InCheck() then
                local currentTurn = boardState:GetCurrentTurn()
                local kingPiece = (currentTurn == COLOR.WHITE) and "K" or "k"
                if piece == kingPiece then
                    square.checkIndicator:Show()
                end
            end
            
            -- Update piece texture
            if piece then
                local texturePath = DeltaChess.UI:GetPieceTexture(piece)
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
function DeltaChess.UI:GetInitialBoardState()
    local board = {}
    for row = 1, 8 do
        board[row] = {}
        for col = 1, 8 do
            board[row][col] = nil
        end
    end
    -- Use piece characters: R, N, B, Q, K for white; r, n, b, q, k for black
    local whiteBackRow = {"R", "N", "B", "Q", "K", "B", "N", "R"}
    local blackBackRow = {"r", "n", "b", "q", "k", "b", "n", "r"}
    for col = 1, 8 do
        -- Row 1 = white back rank, Row 2 = white pawns
        -- Row 7 = black pawns, Row 8 = black back rank
        board[1][col] = whiteBackRow[col]
        board[2][col] = "P"
        board[7][col] = "p"
        board[8][col] = blackBackRow[col]
    end
    return board
end

-- Apply moves to a board state (for replay)
function DeltaChess.UI:ApplyMovesToBoard(board, moves, upToIndex)
    for i = 1, upToIndex do
        local move = moves[i]
        if move then
            local _, fromRow, fromCol = ParseSquare(move:GetFromSquare())
            local _, toRow, toCol = ParseSquare(move:GetToSquare())
            local castle = move:GetCastle()
            local promotion = move:GetPromotion()
            local enPassant = move:IsEnPassant()
            
            if castle and fromRow then
                local row = fromRow
                if move:IsKingsideCastle() then
                    board[row][7] = board[row][5]
                    board[row][6] = board[row][8]
                    board[row][5] = nil
                    board[row][8] = nil
                elseif move:IsQueensideCastle() then
                    board[row][3] = board[row][5]
                    board[row][4] = board[row][1]
                    board[row][5] = nil
                    board[row][1] = nil
                end
            elseif fromRow and fromCol and toRow and toCol then
                local piece = board[fromRow][fromCol]
                if piece then
                    if promotion then
                        -- Convert promotion char to correct case based on piece color
                        local isWhite = DeltaChess.Board.IsPieceColor(piece, COLOR.WHITE)
                        piece = isWhite and promotion:upper() or promotion:lower()
                    end
                    board[toRow][toCol] = piece
                    board[fromRow][fromCol] = nil
                    
                    if enPassant then
                        board[fromRow][toCol] = nil
                    end
                end
            end
        end
    end
    return board
end

--------------------------------------------------------------------------------
-- PIECE MOVEMENT ANIMATION
--------------------------------------------------------------------------------

-- Animate a piece moving from one square to another
-- frame: the chess board frame
-- fromUci, toUci: UCI square notation (e.g., "e2", "e4")
-- piece: the piece character (e.g., "P", "n")
-- onComplete: optional callback when animation finishes
function DeltaChess.UI:AnimatePieceMove(frame, fromUci, toUci, piece, onComplete)
    if not frame or not frame.squares then
        if onComplete then onComplete() end
        return
    end
    
    local fromSquare = frame.squares[fromUci]
    local toSquare = frame.squares[toUci]
    
    if not fromSquare or not toSquare then
        if onComplete then onComplete() end
        return
    end
    
    -- Get the texture path for the piece
    local texturePath = DeltaChess.UI:GetPieceTexture(piece)
    if not texturePath then
        if onComplete then onComplete() end
        return
    end
    
    -- Create or reuse the floating animation frame
    if not self.animatingPiece then
        local animFrame = CreateFrame("Frame", "DeltaChessAnimatingPiece", UIParent)
        animFrame:SetFrameStrata("TOOLTIP") -- Above everything
        animFrame:SetSize(SQUARE_SIZE - 4, SQUARE_SIZE - 4)
        
        local tex = animFrame:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        animFrame.texture = tex
        
        self.animatingPiece = animFrame
    end
    
    local animFrame = self.animatingPiece
    
    -- Stop any existing animation and hide immediately
    if animFrame.animGroup then
        animFrame.animGroup:Stop()
    end
    animFrame:Hide()
    
    -- Set up the piece texture
    animFrame.texture:SetTexture(texturePath)
    
    -- Apply the same scale as the board frame (for minimized mode)
    local frameScale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    animFrame:SetScale(frameScale)
    animFrame:SetSize(SQUARE_SIZE - 4, SQUARE_SIZE - 4)
    
    -- Calculate positions (get center of each square)
    local fromX, fromY = fromSquare:GetCenter()
    local toX, toY = toSquare:GetCenter()
    
    if not fromX or not toX then
        if onComplete then onComplete() end
        return
    end
    
    -- Position at source (adjust for scale)
    animFrame:ClearAllPoints()
    animFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", fromX, fromY)
    animFrame:Show()
    
    -- Hide the piece at destination during animation (it will be shown by UpdateBoard after)
    -- Note: source piece is already gone from board state, so no need to hide it
    
    -- Create animation group
    if not animFrame.animGroup then
        animFrame.animGroup = animFrame:CreateAnimationGroup()
        
        local move = animFrame.animGroup:CreateAnimation("Translation")
        move:SetOrder(1)
        move:SetSmoothing("IN_OUT")
        animFrame.moveAnim = move
    end
    
    -- Calculate offset from current position to target
    local offsetX = toX - fromX
    local offsetY = toY - fromY
    
    -- Configure animation
    animFrame.moveAnim:SetOffset(offsetX, offsetY)
    animFrame.moveAnim:SetDuration(self.ANIMATION_DURATION)
    
    -- Store callback and destination info
    animFrame.onComplete = onComplete
    animFrame.destSquare = toSquare
    
    -- Set up completion handler
    animFrame.animGroup:SetScript("OnFinished", function()
        animFrame:Hide()
        if animFrame.onComplete then
            animFrame.onComplete()
        end
    end)
    
    -- Start animation
    animFrame.animGroup:Play()
end

-- Animate a piece move on a replay board (or any board using RenderPieces)
-- Uses BoardMove methods for UCI squares
function DeltaChess.UI:AnimateReplayMove(frame, move, onComplete)
    if not frame or not frame.squares or not move then
        if onComplete then onComplete() end
        return
    end
    
    -- Restore any pieces that were hidden by a previous interrupted animation
    if frame._hiddenPieces then
        for _, info in ipairs(frame._hiddenPieces) do
            if info.texture then
                info.texture:SetAlpha(1)
            end
        end
    end
    frame._hiddenPieces = {} -- Reset for this animation
    
    -- Extract move squares using BoardMove methods
    local fromSquare = move:GetFromSquare()
    local toSquare = move:GetToSquare()
    local castle = move:GetCastle()
    local pieceChar = move:GetPiece() or "P"
    local promotion = move:GetPromotion()
    
    if not fromSquare or fromSquare == "" or not toSquare or toSquare == "" then
        if onComplete then onComplete() end
        return
    end
    
    -- For promotion, use the promoted piece (with correct case for color)
    if promotion then
        local isWhite = DeltaChess.Board.IsPieceColor(pieceChar, COLOR.WHITE)
        pieceChar = isWhite and promotion:upper() or promotion:lower()
    end
    local destSquare = frame.squares[toSquare]
    
    -- Hide destination piece during animation using alpha (prevents flicker)
    if destSquare and destSquare.pieceTexture then
        destSquare.pieceTexture:SetAlpha(0)
        table.insert(frame._hiddenPieces, {texture = destSquare.pieceTexture})
    end
    
    if castle then
        -- Castling animation - determine rook squares based on piece color
        local isWhite = DeltaChess.Board.IsPieceColor(pieceChar, COLOR.WHITE)
        local rookFromSquare, rookToSquare
        if move:IsKingsideCastle() then
            rookFromSquare = isWhite and "h1" or "h8"
            rookToSquare = isWhite and "f1" or "f8"
        else
            rookFromSquare = isWhite and "a1" or "a8"
            rookToSquare = isWhite and "d1" or "d8"
        end
        
        -- Rook character: R for white, r for black
        local rookChar = isWhite and "R" or "r"
        local rookDestSquareFrame = frame.squares[rookToSquare]
        
        if rookDestSquareFrame and rookDestSquareFrame.pieceTexture then
            rookDestSquareFrame.pieceTexture:SetAlpha(0)
            table.insert(frame._hiddenPieces, {texture = rookDestSquareFrame.pieceTexture})
        end
        
        self:AnimateCastling(frame, fromSquare, toSquare,
            rookFromSquare, rookToSquare,
            pieceChar, rookChar,
            function()
                -- Restore alpha after animation (also clears tracking)
                if destSquare and destSquare.pieceTexture then
                    destSquare.pieceTexture:SetAlpha(1)
                end
                if rookDestSquareFrame and rookDestSquareFrame.pieceTexture then
                    rookDestSquareFrame.pieceTexture:SetAlpha(1)
                end
                frame._hiddenPieces = nil
                if onComplete then onComplete() end
            end)
    else
        -- Regular move animation
        self:AnimatePieceMove(frame, fromSquare, toSquare, pieceChar,
            function()
                -- Restore alpha after animation (also clears tracking)
                if destSquare and destSquare.pieceTexture then
                    destSquare.pieceTexture:SetAlpha(1)
                end
                frame._hiddenPieces = nil
                if onComplete then onComplete() end
            end)
    end
end

-- Animate a castling move (king + rook)
-- Uses UCI square notation
function DeltaChess.UI:AnimateCastling(frame, kingFromSquare, kingToSquare, rookFromSquare, rookToSquare, kingPiece, rookPiece, onComplete)
    -- Animate both pieces simultaneously
    local completed = 0
    local totalPieces = 2
    
    local function checkComplete()
        completed = completed + 1
        if completed >= totalPieces and onComplete then
            onComplete()
        end
    end
    
    -- Create a second animation frame for the rook
    if not self.animatingPiece2 then
        local animFrame = CreateFrame("Frame", "DeltaChessAnimatingPiece2", UIParent)
        animFrame:SetFrameStrata("TOOLTIP")
        animFrame:SetSize(SQUARE_SIZE - 4, SQUARE_SIZE - 4)
        
        local tex = animFrame:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        animFrame.texture = tex
        
        self.animatingPiece2 = animFrame
    end
    
    -- Animate king using primary animation frame
    self:AnimatePieceMove(frame, kingFromSquare, kingToSquare, kingPiece, checkComplete)
    
    -- Animate rook using secondary frame
    local rookFrame = self.animatingPiece2
    local fromSquare = frame.squares[rookFromSquare]
    local toSquare = frame.squares[rookToSquare]
    
    if fromSquare and toSquare then
        local texturePath = DeltaChess.UI:GetPieceTexture(rookPiece)
        if texturePath then
            if rookFrame.animGroup then
                rookFrame.animGroup:Stop()
            end
            rookFrame:Hide()
            
            rookFrame.texture:SetTexture(texturePath)
            
            -- Apply the same scale as the board frame (for minimized mode)
            local frameScale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
            rookFrame:SetScale(frameScale)
            rookFrame:SetSize(SQUARE_SIZE - 4, SQUARE_SIZE - 4)
            
            local fromX, fromY = fromSquare:GetCenter()
            local toX, toY = toSquare:GetCenter()
            
            if fromX and toX then
                rookFrame:ClearAllPoints()
                rookFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", fromX, fromY)
                rookFrame:Show()
                
                if not rookFrame.animGroup then
                    rookFrame.animGroup = rookFrame:CreateAnimationGroup()
                    local move = rookFrame.animGroup:CreateAnimation("Translation")
                    move:SetOrder(1)
                    move:SetSmoothing("IN_OUT")
                    rookFrame.moveAnim = move
                end
                
                local offsetX = toX - fromX
                local offsetY = toY - fromY
                
                rookFrame.moveAnim:SetOffset(offsetX, offsetY)
                rookFrame.moveAnim:SetDuration(self.ANIMATION_DURATION)
                
                rookFrame.animGroup:SetScript("OnFinished", function()
                    rookFrame:Hide()
                    checkComplete()
                end)
                
                rookFrame.animGroup:Play()
                return
            end
        end
    end
    
    -- If rook animation failed, still call checkComplete
    checkComplete()
end

-- Format move as algebraic notation (verbose style: Ke1-e2 or Qd1xd7)
function DeltaChess.UI:FormatMoveNotation(move)
    if not move then return "" end
    
    local fromSquare = move:GetFromSquare()
    local toSquare = move:GetToSquare()
    local pieceChar = move:GetPiece() or "P"
    local isCapture = move:IsCapture()
    
    -- Get piece letter (uppercase, empty for pawn)
    local pieceLetter = pieceChar:upper()
    if pieceLetter == "P" then pieceLetter = "" end
    
    local notation = pieceLetter
    notation = notation .. fromSquare
    notation = notation .. (isCapture and "x" or "-")
    notation = notation .. toSquare
    return notation
end

--------------------------------------------------------------------------------
-- SHARED UI COMPONENT CREATION FUNCTIONS
--------------------------------------------------------------------------------

-- Get board participant info (who is "me" vs "opponent", colors, classes, flip)
-- Returns a table with: myName, opponentName, myChessColor, opponentChessColor, myClass, opponentClass, flipBoard
function DeltaChess.UI:GetBoardParticipants(board)
    local playerName = DeltaChess:GetFullPlayerName(UnitName("player"))
    local isVsComputer = board:OneOpponentIsEngine()
    local white = board:GetWhitePlayerName()
    local black = board:GetBlackPlayerName()
    local whiteClass = board:GetWhitePlayerClass()
    local blackClass = board:GetBlackPlayerClass()
    
    -- Determine player color
    local playerColor
    if isVsComputer then
        playerColor = board:GetPlayerColor()
    else
        if white == playerName then
            playerColor = COLOR.WHITE
        elseif black == playerName then
            playerColor = COLOR.BLACK
        end
    end
    
    -- Flip board if player is black
    local flipBoard = (playerColor == COLOR.BLACK) or (black == playerName)
    
    -- Determine who is "me" and who is "opponent"
    local myName, opponentName, myChessColor, opponentChessColor, myClass, opponentClass
    if flipBoard then
        myName = black or "Black"
        opponentName = white or "White"
        myChessColor = COLOR.BLACK
        opponentChessColor = COLOR.WHITE
        myClass = blackClass
        opponentClass = whiteClass
    else
        myName = white or "White"
        opponentName = black or "Black"
        myChessColor = COLOR.WHITE
        opponentChessColor = COLOR.BLACK
        myClass = whiteClass
        opponentClass = blackClass
    end
    
    return {
        myName = myName,
        opponentName = opponentName,
        myChessColor = myChessColor,
        opponentChessColor = opponentChessColor,
        myClass = myClass,
        opponentClass = opponentClass,
        flipBoard = flipBoard,
        playerColor = playerColor,
    }
end

-- Format display name (handles "Computer (engine - ELO)" format)
function DeltaChess.UI:FormatDisplayName(name, board)
    local displayName = (name or "?"):match("^([^%-]+)") or name or "?"
    
    local isVsComputer = board:OneOpponentIsEngine()
    local computerEngine = board:GetEngineId()
    local computerDifficulty = board:GetEngineElo()
    
    if isVsComputer and displayName == "Computer" and computerEngine then
        local engine = DeltaChess.Engines:Get(computerEngine)
        local engineName = engine and engine.name or computerEngine
        local eloStr = computerDifficulty and (" - " .. computerDifficulty .. " ELO") or ""
        displayName = "Computer (" .. engineName .. eloStr .. ")"
    end
    
    return displayName
end

-- Create a player info bar (for top opponent bar or bottom player bar)
-- config: { parent, anchorFrame, anchorPoint, playerName, playerClass, chessColor, board, showClock, isTop }
-- Returns: { bar, nameText, capturedContainer, clock/thinkTime (if applicable) }
function DeltaChess.UI:CreatePlayerBar(config)
    local bar = CreateFrame("Frame", nil, config.parent)
    bar:SetSize(LABEL_SIZE + BOARD_SIZE, PLAYER_BAR_HEIGHT)
    bar:SetPoint(config.anchorPoint or "TOPLEFT", config.anchorFrame, config.anchorRelPoint or "TOPLEFT", config.offsetX or 0, config.offsetY or 0)
    
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.15, 0.15, 0.15, 0.8)
    
    -- Name with class color
    local displayName = DeltaChess.UI:FormatDisplayName(config.playerName, config.board)
    local r, g, b = DeltaChess.UI:GetPlayerColor(config.playerName, config.playerClass)
    local nameText = bar:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    nameText:SetPoint("LEFT", bar, "LEFT", 5, 8)
    nameText:SetTextColor(r, g, b)
    nameText:SetText(displayName)
    
    -- Clock or thinking time (if requested). Same font/size for both so label and sizing are consistent.
    local timeDisplay = nil
    if config.showClock then
        timeDisplay = bar:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        timeDisplay:SetPoint("RIGHT", bar, "RIGHT", -10, 0)
    end
    
    -- Captured pieces container
    local capturedContainer = CreateFrame("Frame", nil, bar)
    capturedContainer:SetSize(200, CAPTURED_PIECE_SIZE)
    capturedContainer:SetPoint("LEFT", bar, "LEFT", 5, -10)
    
    return {
        bar = bar,
        nameText = nameText,
        capturedContainer = capturedContainer,
        timeDisplay = timeDisplay,
    }
end

-- Create clock configuration panel (use clock checkbox, time slider, increment, optional handicap).
-- config: { parent, anchorFrame (optional), anchorPoint, anchorRelPoint, offsetX, startY, showHandicap }
-- Sets on parent: clockCheck, timeSlider, timeValue, incSlider, incValue, and if showHandicap: handicapCheck, handicapSide, handicapSecondsSlider, handicapSecondsValue.
-- handicapSide is "challenger" or "opponent" (the side that gets less time).
-- Returns: endY (for placing content below).
function DeltaChess.UI:CreateClockConfigPanel(parent, config)
    local anchorFrame = config.anchorFrame or parent
    local anchorPoint = config.anchorPoint or "TOPLEFT"
    local anchorRelPoint = config.anchorRelPoint or "TOPLEFT"
    local offsetX = config.offsetX or 0
    local yPos = config.startY or -35
    local showHandicap = config.showHandicap and true or false

    local function addY(delta)
        yPos = yPos + (delta or 0)
        return yPos
    end

    -- Use clock checkbox
    local clockCheck = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    clockCheck:SetPoint(anchorPoint, anchorFrame, anchorRelPoint, offsetX, addY(0))
    clockCheck.text:SetText("Use Chess Clock")
    clockCheck:SetChecked(false)
    parent.clockCheck = clockCheck
    addY(-40)

    -- Clock settings container (hidden until checkbox is checked)
    local clockElements = {}

    -- Time per player
    local timeLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    timeLabel:SetPoint(anchorPoint, anchorFrame, anchorRelPoint, offsetX + 3, addY(0))
    timeLabel:SetText("Time per player (minutes):")
    local timeValue = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    timeValue:SetPoint("LEFT", timeLabel, "RIGHT", 10, 0)
    timeValue:SetText("10")
    parent.timeValue = timeValue
    table.insert(clockElements, timeLabel)
    table.insert(clockElements, timeValue)
    addY(-25)

    local timeSlider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    timeSlider:SetPoint(anchorPoint, anchorFrame, anchorRelPoint, offsetX + 8, addY(5))
    timeSlider:SetSize(305, 17)
    timeSlider:SetMinMaxValues(1, 60)
    timeSlider:SetValue(10)
    timeSlider:SetValueStep(1)
    timeSlider:SetObeyStepOnDrag(true)
    timeSlider.Low:SetText("1")
    timeSlider.High:SetText("60")
    timeSlider:SetScript("OnValueChanged", function(self, value)
        local minutes = math.floor(value)
        timeValue:SetText(tostring(minutes))
        -- Dynamically update handicap seconds slider max to match clock time
        if parent.handicapSecondsSlider then
            local maxSec = minutes * 60
            parent.handicapSecondsSlider:SetMinMaxValues(0, maxSec)
            parent.handicapSecondsSlider.High:SetText(tostring(maxSec))
            if parent.handicapSecondsSlider:GetValue() > maxSec then
                parent.handicapSecondsSlider:SetValue(maxSec)
            end
        end
    end)
    parent.timeSlider = timeSlider
    table.insert(clockElements, timeSlider)
    addY(-45)

    -- Increment per move
    local incLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    incLabel:SetPoint(anchorPoint, anchorFrame, anchorRelPoint, offsetX + 3, addY(0))
    incLabel:SetText("Increment per move (seconds):")
    local incValue = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    incValue:SetPoint("LEFT", incLabel, "RIGHT", 10, 0)
    incValue:SetText("0")
    parent.incValue = incValue
    table.insert(clockElements, incLabel)
    table.insert(clockElements, incValue)
    addY(-25)

    local incSlider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    incSlider:SetPoint(anchorPoint, anchorFrame, anchorRelPoint, offsetX + 8, addY(5))
    incSlider:SetSize(305, 17)
    incSlider:SetMinMaxValues(0, 30)
    incSlider:SetValue(0)
    incSlider:SetValueStep(1)
    incSlider:SetObeyStepOnDrag(true)
    incSlider.Low:SetText("0")
    incSlider.High:SetText("30")
    incSlider:SetScript("OnValueChanged", function(self, value)
        incValue:SetText(tostring(math.floor(value)))
    end)
    parent.incSlider = incSlider
    table.insert(clockElements, incSlider)
    addY(-45)

    -- Handicap elements (only when clock is enabled AND handicap is checked)
    local handicapElements = {}
    local handicapCheck

    if showHandicap then
        -- Handicap: one side gets less time
        handicapCheck = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        handicapCheck:SetPoint(anchorPoint, anchorFrame, anchorRelPoint, offsetX, addY(0))
        handicapCheck.text:SetText("Handicap (one side gets less time)")
        handicapCheck:SetChecked(false)
        parent.handicapCheck = handicapCheck
        -- Handicap checkbox is part of clockElements (only visible when clock is enabled)
        table.insert(clockElements, handicapCheck)
        addY(-30)

        local handicapSideLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        handicapSideLabel:SetPoint(anchorPoint, anchorFrame, anchorRelPoint, offsetX + 3, addY(-10))
        handicapSideLabel:SetText("Player with less time:")
        table.insert(handicapElements, handicapSideLabel)
        addY(-25)

        parent.handicapSide = "challenger"
        local handicapDropdown = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
        handicapDropdown:SetPoint(anchorPoint, anchorFrame, anchorRelPoint, offsetX - 15, addY(5))
        UIDropDownMenu_SetWidth(handicapDropdown, 300)
        UIDropDownMenu_Initialize(handicapDropdown, function(self, level)
            local info = UIDropDownMenu_CreateInfo()
            for _, side in ipairs({ "challenger", "opponent" }) do
                info.text = side:sub(1, 1):upper() .. side:sub(2)
                info.value = side
                info.checked = (parent.handicapSide == side)
                info.func = function()
                    parent.handicapSide = side
                    UIDropDownMenu_SetText(handicapDropdown, side:sub(1, 1):upper() .. side:sub(2))
                end
                UIDropDownMenu_AddButton(info)
            end
        end)
        UIDropDownMenu_SetText(handicapDropdown, "Challenger")
        parent.handicapSideDropdown = handicapDropdown
        table.insert(handicapElements, handicapDropdown)
        addY(-30)

        local handicapSecLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        handicapSecLabel:SetPoint(anchorPoint, anchorFrame, anchorRelPoint, offsetX + 3, addY(-10))
        handicapSecLabel:SetText("Seconds less:")
        local handicapSecondsValue = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        handicapSecondsValue:SetPoint("LEFT", handicapSecLabel, "RIGHT", 10, 0)
        handicapSecondsValue:SetText("0")
        parent.handicapSecondsValue = handicapSecondsValue
        table.insert(handicapElements, handicapSecLabel)
        table.insert(handicapElements, handicapSecondsValue)
        addY(-25)

        local initialMaxSec = math.floor(timeSlider:GetValue()) * 60
        local handicapSecondsSlider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
        handicapSecondsSlider:SetPoint(anchorPoint, anchorFrame, anchorRelPoint, offsetX + 8, addY(5))
        handicapSecondsSlider:SetSize(305, 17)
        handicapSecondsSlider:SetMinMaxValues(0, initialMaxSec)
        handicapSecondsSlider:SetValue(0)
        handicapSecondsSlider:SetValueStep(1)
        handicapSecondsSlider:SetObeyStepOnDrag(true)
        handicapSecondsSlider.Low:SetText("0")
        handicapSecondsSlider.High:SetText(tostring(initialMaxSec))
        handicapSecondsSlider:SetScript("OnValueChanged", function(self, value)
            handicapSecondsValue:SetText(tostring(math.floor(value)))
        end)
        parent.handicapSecondsSlider = handicapSecondsSlider
        table.insert(handicapElements, handicapSecondsSlider)
        addY(-45)
    end

    -- Helper to show/hide a list of elements
    local function setElementsShown(elements, shown)
        for _, el in ipairs(elements) do
            if el.SetShown then
                el:SetShown(shown)
            elseif shown then
                el:Show()
            else
                el:Hide()
            end
        end
    end

    -- Height contributions for each collapsible section (sum of addY calls)
    -- Clock settings: 40 (gap) + 25 (timeLabel) + 45 (timeSlider) + 25 (incLabel) + 45 (incSlider) = 180
    local clockSettingsH = 150
    -- Handicap checkbox row (part of clockElements): 30
    if showHandicap then clockSettingsH = clockSettingsH + 30 end
    -- Handicap settings: 25 (sideLabel) + 30 (dropdown) + 25 (minLabel) + 45 (minutesSlider) = 125
    local handicapSettingsH = showHandicap and 115 or 0

    local onResize = config.onResize  -- optional callback: function(extraHeight)

    -- Unified layout update: shows/hides elements and calls onResize with total extra height
    parent.UpdateClockLayout = function()
        local clockChecked = clockCheck:GetChecked()
        setElementsShown(clockElements, clockChecked)

        local handicapChecked = false
        if not clockChecked then
            setElementsShown(handicapElements, false)
        elseif handicapCheck then
            handicapChecked = handicapCheck:GetChecked()
            setElementsShown(handicapElements, handicapChecked)
        end

        if onResize then
            local extra = 0
            if clockChecked then
                extra = extra + clockSettingsH
                if handicapChecked then
                    extra = extra + handicapSettingsH
                end
            end
            onResize(extra)
        end
    end

    clockCheck:SetScript("OnClick", function() parent.UpdateClockLayout() end)
    if handicapCheck then
        handicapCheck:SetScript("OnClick", function() parent.UpdateClockLayout() end)
    end

    -- Start with everything hidden (checkboxes default to unchecked)
    parent.UpdateClockLayout()

    return yPos
end

-- Create move history scroll frame within a parent panel
-- config: { parent, anchorFrame (optional), width, height, includeLabel }
-- Returns: { scrollFrame, scrollChild, historyText, label (if includeLabel), historyBg }
function DeltaChess.UI:CreateMoveHistoryScroller(config)
    local parent = config.parent
    local width = config.width or RIGHT_PANEL_WIDTH
    local height = config.height
    local anchorFrame = config.anchorFrame or parent
    local anchorPoint = config.anchorPoint or "TOPLEFT"
    local yOffset = config.yOffset or 0
    
    local label = nil
    if config.includeLabel then
        label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        label:SetPoint(anchorPoint, anchorFrame, anchorPoint, 0, yOffset)
        label:SetText("Moves")
        -- Anchor bg to bottom of label
        anchorFrame = label
        anchorPoint = "BOTTOMLEFT"
        yOffset = -5
    end
    
    local historyBg = parent:CreateTexture(nil, "BACKGROUND")
    historyBg:SetPoint("TOPLEFT", anchorFrame, anchorPoint, 0, yOffset)
    historyBg:SetSize(width, height)
    historyBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
    
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", historyBg, "TOPLEFT", 5, -5)
    scrollFrame:SetSize(width - 30, height - 10)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(width - 35, 500)
    scrollFrame:SetScrollChild(scrollChild)
    
    local historyText = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    historyText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
    historyText:SetWidth(width - 40)
    historyText:SetJustifyH("LEFT")
    historyText:SetSpacing(2)
    
    return {
        scrollFrame = scrollFrame,
        scrollChild = scrollChild,
        historyText = historyText,
        label = label,
        historyBg = historyBg,
    }
end

-- Format move history text from moves array
function DeltaChess.UI:FormatMoveHistoryText(moves, highlightIndex)
    local historyStr = ""
    for i, move in ipairs(moves) do
        if i % 2 == 1 then
            historyStr = historyStr .. "|cFFAAAAAA" .. math.ceil(i / 2) .. ".|r "
        end
        
        local notation = DeltaChess.UI:FormatMoveAlgebraic(move)
        
        -- Highlight current move if specified
        if highlightIndex and i == highlightIndex then
            notation = "|cFFFFFF00[" .. notation .. "]|r"
        end
        
        historyStr = historyStr .. notation .. " "
        
        if i % 2 == 0 then
            historyStr = historyStr .. "\n"
        end
    end
    return historyStr
end

--------------------------------------------------------------------------------
-- GAME BOARD (for active games)
--------------------------------------------------------------------------------

-- Piece values for material calculation (from framework)
local PIECE_VALUES = DeltaChess.Board.PIECE_VALUES

-- Get class color for a player name (returns r, g, b)
-- savedClass: optional class token (e.g., "WARRIOR") for when player is offline
function DeltaChess.UI:GetPlayerColor(playerName, savedClass)
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

-- Update captured pieces display with small icons
-- Reuses regions to avoid accumulation and recursive layout updates
function DeltaChess.UI:UpdateCapturedPieces(container, capturedPieces, capturedColor, advantage)
    container._capturedTextures = container._capturedTextures or {}
    container._capturedFontStrings = container._capturedFontStrings or {}
    local texPool = container._capturedTextures
    local strPool = container._capturedFontStrings
    for _, r in ipairs(texPool) do if r and r.Hide then r:Hide() end end
    for _, r in ipairs(strPool) do if r and r.Hide then r:Hide() end end
    
    local texIdx, strIdx = 1, 1
    local function getTex()
        local r = texPool[texIdx]
        if not r then r = container:CreateTexture(nil, "OVERLAY"); texPool[texIdx] = r end
        texIdx = texIdx + 1
        return r
    end
    local function getStr()
        local r = strPool[strIdx]
        if not r then r = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); strPool[strIdx] = r end
        strIdx = strIdx + 1
        return r
    end
    
    if not capturedPieces or #capturedPieces == 0 then
        if advantage and advantage > 0 then
            local advText = getStr()
            advText:ClearAllPoints()
            advText:SetPoint("LEFT", container, "LEFT", 0, 0)
            advText:SetText("|cFF00FF00+" .. advantage .. "|r")
            advText:Show()
        end
        return
    end
    
    -- capturedPieces is now an array of piece characters
    local sorted = {}
    for _, pieceChar in ipairs(capturedPieces) do table.insert(sorted, pieceChar) end
    table.sort(sorted, function(a, b) return (PIECE_VALUES[a] or 0) > (PIECE_VALUES[b] or 0) end)
    
    local xOffset = 0
    for _, pieceChar in ipairs(sorted) do
        local texturePath = DeltaChess.UI:GetPieceTexture(pieceChar)
        if texturePath then
            local tex = getTex()
            tex:ClearAllPoints()
            tex:SetSize(CAPTURED_PIECE_SIZE, CAPTURED_PIECE_SIZE)
            tex:SetPoint("LEFT", container, "LEFT", xOffset, 0)
            tex:SetTexture(texturePath)
            tex:Show()
            xOffset = xOffset + CAPTURED_PIECE_SIZE - 4
        end
    end
    
    if advantage and advantage > 0 then
        local advText = getStr()
        advText:ClearAllPoints()
        advText:SetPoint("LEFT", container, "LEFT", xOffset + 5, 0)
        advText:SetText("|cFF00FF00+" .. advantage .. "|r")
        advText:Show()
    end
end

-- Format move in standard algebraic notation
-- Supports both BoardMove objects (with methods) and raw move tables
function DeltaChess.UI:FormatMoveAlgebraic(move)
    if not move then return "" end
    
    -- Handle castling
    local isCheck = move:IsCheck()
    
    if move:IsKingsideCastle() then
        local notation = "O-O"
        if isCheck then notation = notation .. "+" end
        return notation
    elseif move:IsQueensideCastle() then
        local notation = "O-O-O"
        if isCheck then notation = notation .. "+" end
        return notation
    end
    
    -- Get squares
    local fromSquare = move:GetFromSquare()
    local toSquare = move:GetToSquare()
    
    -- Build notation
    local notation = ""
    
    -- Get piece symbol
    local pieceChar = move:GetPiece()
    if pieceChar then
        local pieceSymbols = { K = "K", Q = "Q", R = "R", B = "B", N = "N", k = "K", q = "Q", r = "R", b = "B", n = "N" }
        notation = pieceSymbols[pieceChar] or ""
    end
    
    -- Check if capture
    local isCapture = move:IsCapture()
    
    -- For pawn captures, include the from-file
    if notation == "" and isCapture then
        notation = fromSquare:sub(1, 1)
    end
    
    -- Add capture symbol
    if isCapture then
        notation = notation .. "x"
    end
    
    -- Destination square
    notation = notation .. toSquare
    
    -- Promotion
    local promotion = move:GetPromotion()
    if promotion then
        local promSymbols = { q = "Q", r = "R", b = "B", n = "N" }
        notation = notation .. "=" .. (promSymbols[promotion] or "Q")
    end
    
    -- Check indicator
    if isCheck then
        notation = notation .. "+"
    end
    
    return notation
end

-- Show chess board for a game
function DeltaChess:ShowChessBoard(gameId)
    local board = DeltaChess.GetBoard(gameId)
    if not board then
        self:Print("Game not found!")
        return
    end
    
    -- Resume counting for computer game when opening
    local isVsComputer = board:OneOpponentIsEngine()
    if isVsComputer and board:IsPaused() then
        board:ContinueGame()
    end
    
    -- Close existing board if open
    if DeltaChess.UI.activeFrame then
        DeltaChess.UI.activeFrame:Hide()
    end
    
    -- Get participant info using shared helper
    local participants = DeltaChess.UI:GetBoardParticipants(board)
    local myName = participants.myName
    local opponentName = participants.opponentName
    local myChessColor = participants.myChessColor
    local opponentChessColor = participants.opponentChessColor
    local myClass = participants.myClass
    local opponentClass = participants.opponentClass
    local flipBoard = participants.flipBoard
    local playerColor = participants.playerColor
    local white = board:GetWhitePlayerName()
    local black = board:GetBlackPlayerName()
    
    -- Create main frame
    local totalWidth = LABEL_SIZE + BOARD_SIZE + 15 + RIGHT_PANEL_WIDTH + 15
    local totalHeight = 30 + PLAYER_BAR_HEIGHT + BOARD_SIZE + LABEL_SIZE + PLAYER_BAR_HEIGHT + 10
    
    local frame = CreateFrame("Frame", "ChessBoardFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(totalWidth, totalHeight)
    -- Restore saved position or center
    local pos = DeltaChess.db and DeltaChess.db.settings and DeltaChess.db.settings.boardPosition
    if pos and pos.point and pos.relativePoint and pos.x and pos.y then
        frame:ClearAllPoints()
        frame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
    else
        frame:SetPoint("CENTER")
    end
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if DeltaChess.db and DeltaChess.db.settings then
            local point, _, relativePoint, xOfs, yOfs = self:GetPoint(1)
            if point then
                DeltaChess.db.settings.boardPosition = { point = point, relativePoint = relativePoint, x = xOfs, y = yOfs }
            end
        end
    end)
    -- Pause timer when closing via X (vs computer only)
    frame:SetScript("OnHide", function(self)
        local brd = DeltaChess.GetBoard(self.gameId)
        if brd and brd:OneOpponentIsEngine() and brd:IsActive() then
            brd:PauseGame()
        end
    end)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(250)
    frame.TitleText:SetText("DeltaChess")
    
    -- Override the template's close button to avoid taint issues
    if frame.CloseButton then
        frame.CloseButton:SetScript("OnClick", function()
            frame:Hide()
        end)
    end
    
    -- Compact width when minimized (board + margins, no right panel)
    local compactWidth = LABEL_SIZE + BOARD_SIZE + 15
    frame.isMinimized = false
    
    -- Minimize button in title bar (to the left of the close button)
    local minimizeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    minimizeBtn:SetSize(28, 22)
    minimizeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -20,0)
    minimizeBtn:SetText("−")
    minimizeBtn:SetScript("OnClick", function()
        frame.isMinimized = not frame.isMinimized
        if DeltaChess.db and DeltaChess.db.settings then
            DeltaChess.db.settings.boardMinimized = frame.isMinimized
        end
        if frame.isMinimized then
            frame.rightPanel:Hide()
            frame:SetSize(compactWidth, totalHeight)
            frame:SetScale(0.75)
            minimizeBtn:SetText("+")
        else
            frame.rightPanel:Show()
            frame:SetSize(totalWidth, totalHeight)
            frame:SetScale(1)
            minimizeBtn:SetText("−")
        end
    end)
    frame.minimizeBtn = minimizeBtn
    
    -- Store references
    frame.gameId = gameId
    frame.board = board
    frame.selectedSquare = nil
    frame.validMoves = {}
    frame.flipBoard = flipBoard
    frame.playerColor = playerColor
    frame.myChessColor = myChessColor
    frame.opponentChessColor = opponentChessColor
    frame.gameEndShown = false  -- Reset so game-end popup can fire for this game
    
    -- Store game data for potential restoration after game end
    frame.isVsComputer = isVsComputer
    frame.white = white
    frame.black = black
    
    local leftMargin = 10
    local topOffset = -30
    local settings = board:GetGameMeta("settings") or {}
    
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
    frame.opponentCapturedContainer = opponentBarInfo.capturedContainer
    frame.opponentCapturedColor = myChessColor  -- Opponent captures MY pieces
    frame.opponentClock = opponentBarInfo.timeDisplay
    frame.opponentClockColor = opponentChessColor
    
    -- ==================== BOARD ====================
    local boardContainer = CreateFrame("Frame", nil, frame)
    boardContainer:SetSize(BOARD_SIZE + LABEL_SIZE, BOARD_SIZE + LABEL_SIZE)
    boardContainer:SetPoint("TOPLEFT", opponentBar, "BOTTOMLEFT", 0, 0)
    frame.boardContainer = boardContainer
    
    -- Create squares (keyed by UCI notation)
    frame.squares = DeltaChess.UI:CreateBoardSquares(boardContainer, SQUARE_SIZE, LABEL_SIZE, flipBoard, true)
    
    -- Add click handlers
    for uci, square in pairs(frame.squares) do
        square:SetScript("OnClick", function()
            DeltaChess.UI:OnSquareClick(frame, uci)
        end)
    end
    
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
    frame.playerCapturedContainer = playerBarInfo.capturedContainer
    frame.playerCapturedColor = opponentChessColor  -- Player captures OPPONENT pieces
    frame.playerClock = playerBarInfo.timeDisplay
    frame.playerClockColor = myChessColor
    
    -- ==================== RIGHT PANEL ====================
    local rightPanel = CreateFrame("Frame", nil, frame)
    rightPanel:SetSize(RIGHT_PANEL_WIDTH, PLAYER_BAR_HEIGHT + BOARD_SIZE + LABEL_SIZE + PLAYER_BAR_HEIGHT)
    rightPanel:SetPoint("TOPLEFT", opponentBar, "TOPRIGHT", 10, 0)
    frame.rightPanel = rightPanel
    
    -- Move history scroll frame (top portion)
    local historyHeight = rightPanel:GetHeight() - 70
    local historyInfo = DeltaChess.UI:CreateMoveHistoryScroller({
        parent = rightPanel,
        width = RIGHT_PANEL_WIDTH,
        height = historyHeight,
        includeLabel = true,
    })
    frame.historyText = historyInfo.historyText
    frame.historyScrollChild = historyInfo.scrollChild
    frame.historyScroll = historyInfo.scrollFrame
    
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
        local board = DeltaChess.GetBoard(gameId)
        if not board or not board:IsActive() then return end
        DeltaChess._resignConfirmGameId = gameId
        StaticPopup_Show("CHESS_RESIGN_CONFIRM", nil, nil, gameId)
    end)
    frame.resignButton = resignButton
    
    local drawButton = CreateFrame("Button", nil, rightPanel, "UIPanelButtonTemplate")
    drawButton:SetSize(buttonWidth, 25)
    drawButton:SetPoint("LEFT", resignButton, "RIGHT", buttonSpacing, 0)
    frame.drawButton = drawButton
    
    if isVsComputer then
        drawButton:SetText("Back")
        drawButton:SetScript("OnClick", function()
            DeltaChess:TakeBackMove(gameId)
        end)
    else
        drawButton:SetText("Draw")
        drawButton:SetScript("OnClick", function()
            DeltaChess:OfferDraw(gameId)
        end)
    end
    
    local closeButton = CreateFrame("Button", nil, rightPanel, "UIPanelButtonTemplate")
    closeButton:SetSize(buttonWidth, 25)
    closeButton:SetPoint("LEFT", drawButton, "RIGHT", buttonSpacing, 0)
    frame.closeButton = closeButton
    if isVsComputer then
        closeButton:SetText("Pause")
        closeButton:SetScript("OnClick", function()
            local board = DeltaChess.GetBoard(gameId)
            if board then
                board:PauseGame()
            end
            frame:Hide()
        end)
    else
        closeButton:SetText("Pause")
        closeButton:SetScript("OnClick", function()
            DeltaChess:RequestPause(gameId)
        end)
    end
    
    -- Restore saved minimized state when opening the board
    frame.isMinimized = (DeltaChess.db and DeltaChess.db.settings and DeltaChess.db.settings.boardMinimized) or false
    if frame.isMinimized then
        frame.rightPanel:Hide()
        frame:SetSize(compactWidth, totalHeight)
        frame:SetScale(0.75)
        frame.minimizeBtn:SetText("+")
    else
        frame.rightPanel:Show()
        frame:SetSize(totalWidth, totalHeight)
        frame:SetScale(1)
        frame.minimizeBtn:SetText("−")
    end
    
    -- Update the board display
    DeltaChess.UI:UpdateBoard(frame)

    frame:Show()
    
    -- Store frame reference
    DeltaChess.UI.activeFrame = frame
    
    -- Check if there's a pending ACK for this game and show waiting overlay
    if not isVsComputer and DeltaChess:IsBoardLocked(gameId) then
        DeltaChess.UI:ShowWaitingOverlay(frame, true)
    end
end

-- Update board with optional animation for the last move
-- If animateLastMove is true and there's a last move, animate the piece movement
function DeltaChess.UI:UpdateBoardAnimated(frame, animateLastMove)
    if not animateLastMove then
        self:UpdateBoard(frame)
        return
    end
    
    -- Restore any pieces that were hidden by a previous interrupted animation
    if frame._hiddenPieces then
        for _, info in ipairs(frame._hiddenPieces) do
            if info.texture then
                info.texture:SetAlpha(1)
            end
        end
    end
    frame._hiddenPieces = {} -- Reset for this animation
    
    local board = DeltaChess.GetBoard(frame.gameId)
    if not board then
        self:UpdateBoard(frame)
        return
    end
    local lastMove = board:GetLastMove()
    
    if not lastMove then
        self:UpdateBoard(frame)
        return
    end
    
    -- Extract move squares using BoardMove methods
    local fromSquare = lastMove:GetFromSquare()
    local toSquare = lastMove:GetToSquare()
    
    if not fromSquare or fromSquare == "" or not toSquare or toSquare == "" then
        self:UpdateBoard(frame)
        return
    end
    
    -- Get the piece that was moved (it's now at the destination)
    local piece = DeltaChess.GetPieceAt(board, toSquare)
    if not piece then
        self:UpdateBoard(frame)
        return
    end
    
    -- Store current piece positions for animation
    -- We need to show the board state BEFORE the move for animation
    local destSquareFrame = frame.squares[toSquare]
    
    -- For castling, also get rook positions
    local rookFromSquare, rookToSquare, rookPiece
    if lastMove:IsCastle() then
        local isWhite = DeltaChess.Board.IsPieceColor(piece, COLOR.WHITE)
        if lastMove:IsKingsideCastle() then
            rookFromSquare = isWhite and "h1" or "h8"
            rookToSquare = isWhite and "f1" or "f8"
        else -- queenside
            rookFromSquare = isWhite and "a1" or "a8"
            rookToSquare = isWhite and "d1" or "d8"
        end
        rookPiece = DeltaChess.GetPieceAt(board, rookToSquare)
    end
    
    -- Hide destination pieces BEFORE updating board (set alpha to 0)
    -- This prevents the brief flash of the piece at destination
    if destSquareFrame and destSquareFrame.pieceTexture then
        destSquareFrame.pieceTexture:SetAlpha(0)
        table.insert(frame._hiddenPieces, {texture = destSquareFrame.pieceTexture})
    end
    
    local rookDestSquareFrame
    if lastMove:IsCastle() and rookToSquare then
        rookDestSquareFrame = frame.squares[rookToSquare]
        if rookDestSquareFrame and rookDestSquareFrame.pieceTexture then
            rookDestSquareFrame.pieceTexture:SetAlpha(0)
            table.insert(frame._hiddenPieces, {texture = rookDestSquareFrame.pieceTexture})
        end
    end
    
    -- Update the board display (destination pieces are invisible due to alpha=0)
    self:UpdateBoard(frame)
    
    -- Ensure alpha is still 0 after UpdateBoard (in case it reset)
    if destSquareFrame and destSquareFrame.pieceTexture then
        destSquareFrame.pieceTexture:SetAlpha(0)
    end
    if rookDestSquareFrame and rookDestSquareFrame.pieceTexture then
        rookDestSquareFrame.pieceTexture:SetAlpha(0)
    end
    
    if lastMove:IsCastle() and rookPiece then
        -- Animate castling (both king and rook)
        self:AnimateCastling(frame, fromSquare, toSquare,
            rookFromSquare, rookToSquare,
            piece, rookPiece,
            function()
                -- Restore alpha after animation (also clears tracking)
                if destSquareFrame and destSquareFrame.pieceTexture then
                    destSquareFrame.pieceTexture:SetAlpha(1)
                end
                if rookDestSquareFrame and rookDestSquareFrame.pieceTexture then
                    rookDestSquareFrame.pieceTexture:SetAlpha(1)
                end
                frame._hiddenPieces = nil
            end)
    elseif lastMove:IsCastle() then
        -- Fallback: just restore alpha
        if destSquareFrame and destSquareFrame.pieceTexture then
            destSquareFrame.pieceTexture:SetAlpha(1)
        end
        if rookDestSquareFrame and rookDestSquareFrame.pieceTexture then
            rookDestSquareFrame.pieceTexture:SetAlpha(1)
        end
        frame._hiddenPieces = nil
    else
        -- Regular move animation
        self:AnimatePieceMove(frame, fromSquare, toSquare, piece,
            function()
                -- Restore alpha after animation (also clears tracking)
                if destSquareFrame and destSquareFrame.pieceTexture then
                    destSquareFrame.pieceTexture:SetAlpha(1)
                end
                frame._hiddenPieces = nil
            end)
    end
end

-- Update board display
function DeltaChess.UI:UpdateBoard(frame)
    local board = DeltaChess.GetBoard(frame.gameId)
    if not board then return end

    frame.board = board  -- keep frame in sync with current board instance
    local Board = DeltaChess.Board
    
    -- Find kings and check if in check
    local whiteKingSquare, blackKingSquare = nil, nil
    for row = 1, 8 do
        for col = 1, 8 do
            local uci = Board.ToSquare(row, col)
            local piece = DeltaChess.GetPieceAt(board, uci)
            if piece == "K" then
                whiteKingSquare = uci
            elseif piece == "k" then
                blackKingSquare = uci
            end
        end
    end
    
    -- Check detection - only current side can be in check
    local currentTurn = board:GetCurrentTurn()
    local whiteInCheck = (currentTurn == COLOR.WHITE) and board:InCheck()
    local blackInCheck = (currentTurn == COLOR.BLACK) and board:InCheck()
    
    -- Last move for highlight (from/to squares)
    local lastMove = board:GetLastMove()
    local lastMoveFrom, lastMoveTo
    if lastMove then
        lastMoveFrom = lastMove:GetFromSquare()
        lastMoveTo = lastMove:GetToSquare()
    end
    
    -- Update squares
    for row = 1, 8 do
        for col = 1, 8 do
            local uci = Board.ToSquare(row, col)
            local square = frame.squares[uci]
            local piece = DeltaChess.GetPieceAt(board, uci)
            
            -- Reset indicators
            if square.checkIndicator then square.checkIndicator:Hide() end
            if square.highlight then square.highlight:Hide() end
            if square.validMove then square.validMove:Hide() end
            
            -- Last move: subtle yellow highlight, respecting light/dark squares
            local isLastMoveSquare = (uci == lastMoveFrom or uci == lastMoveTo)
            if isLastMoveSquare then
                if square.isLightSquare then
                    square.bg:SetColorTexture(0.96, 0.94, 0.72, 1)
                else
                    square.bg:SetColorTexture(0.72, 0.6, 0.28, 1)
                end
            else
                if square.isLightSquare then
                    square.bg:SetColorTexture(0.9, 0.9, 0.8, 1)
                else
                    square.bg:SetColorTexture(0.6, 0.4, 0.2, 1)
                end
            end
            
            -- Show check indicator on king's square
            if square.checkIndicator then
                if whiteInCheck and uci == whiteKingSquare then
                    square.checkIndicator:Show()
                elseif blackInCheck and uci == blackKingSquare then
                    square.checkIndicator:Show()
                end
            end
            
            if piece then
                local texturePath = DeltaChess.UI:GetPieceTexture(piece)
                if texturePath then
                    square.pieceTexture:SetTexture(texturePath)
                    square.pieceTexture:Show()
                end
            else
                square.pieceTexture:Hide()
            end
        end
    end

    -- Restore selection highlight and valid moves (UpdateBoard clears them above)
    -- Don't restore when game has ended - no moves to make
    if not board:IsEnded() and frame.selectedSquare and frame.validMoves then
        local selectedSquareFrame = frame.squares[frame.selectedSquare]
        if selectedSquareFrame and selectedSquareFrame.highlight then
            selectedSquareFrame.highlight:Show()
            for _, move in ipairs(frame.validMoves) do
                local moveSquareFrame = frame.squares[move.square]
                if moveSquareFrame and moveSquareFrame.validMove then
                    moveSquareFrame.validMove:Show()
                end
            end
        end
    end
    
    -- Get game metadata
    local isVsComputer = board:OneOpponentIsEngine()
    local settings = board:GetGameMeta("settings") or {}
    local white = board:GetWhitePlayerName()
    local black = board:GetBlackPlayerName()
    
    -- Update Pause/Unpause button state for human games (skip when game has ended)
    if frame.closeButton and not isVsComputer and not board:IsEnded() then
        if board:IsPaused() then
            frame.closeButton:SetText("Unpause")
            frame.closeButton:Enable()
            frame.closeButton:SetScript("OnClick", function()
                DeltaChess:RequestUnpause(frame.gameId)
            end)
        else
            frame.closeButton:SetText("Pause")
            frame.closeButton:Enable()
            frame.closeButton:SetScript("OnClick", function()
                DeltaChess:RequestPause(frame.gameId)
            end)
        end
    end
    
    -- Update turn indicator
    if frame.turnLabel then
        frame.turnLabel:SetText(DeltaChess.UI:GetGameStatusText(board))
    end
    
    -- Calculate material advantage
    local myColor = frame.myChessColor
    local opponentColor = frame.opponentChessColor
    local myAdvantage = board:CalculateMaterialAdvantage(myColor)
    local capturedByWhite = board:GetCapturedPiecesWhite()
    local capturedByBlack = board:GetCapturedPiecesBlack()
    
    -- Update captured pieces display with icons
    
    -- My captured pieces (what I captured from opponent - show opponent's color pieces)
    local myCaptured = myColor == COLOR.WHITE and capturedByWhite or capturedByBlack
    if frame.playerCapturedContainer then
        DeltaChess.UI:UpdateCapturedPieces(frame.playerCapturedContainer, myCaptured, 
            frame.playerCapturedColor, myAdvantage > 0 and myAdvantage or nil)
    end
    
    -- Opponent captured pieces (what they captured from me - show my color pieces)
    local opponentCaptured = opponentColor == COLOR.WHITE and capturedByWhite or capturedByBlack
    local opponentAdvantage = board:CalculateMaterialAdvantage(opponentColor)
    if frame.opponentCapturedContainer then
        DeltaChess.UI:UpdateCapturedPieces(frame.opponentCapturedContainer, opponentCaptured,
            frame.opponentCapturedColor, opponentAdvantage > 0 and opponentAdvantage or nil)
    end
    
    -- Update time display per side: remaining clock if that side has a clock, else thinking time
    local currentTurn = board:GetCurrentTurn()
    if frame.playerClock then
        local myHasClock = (board:GetClock(myColor) or 0) > 0
        local myTime = myHasClock and board:TimeLeft(myColor) or board:TimeThinking(myColor)
        local myTurn = currentTurn == myColor
        local timeColor = myTurn and "|cFFFFFF00" or "|cFFFFFFFF"
        frame.playerClock:SetText(timeColor .. DeltaChess.UI:FormatTime(myTime or 0) .. "|r")
        frame.playerClock:Show()
    end
    if frame.opponentClock then
        local opponentHasClock = (board:GetClock(opponentColor) or 0) > 0
        local opponentTime = opponentHasClock and board:TimeLeft(opponentColor) or board:TimeThinking(opponentColor)
        local opponentTurn = currentTurn == opponentColor
        local timeColor = opponentTurn and "|cFFFFFF00" or "|cFFFFFFFF"
        frame.opponentClock:SetText(timeColor .. DeltaChess.UI:FormatTime(opponentTime or 0) .. "|r")
        frame.opponentClock:Show()
    end
    -- Refresh time every second while game is active (not when paused or ended)
    if board:IsActive() and not board:IsPaused() and frame:IsShown() then
        C_Timer.After(1, function()
            local board = DeltaChess.GetBoard(frame.gameId)
            DeltaChess.UI:UpdateBoard(frame)
        end)
    end
    
    -- Update move history in algebraic notation
    local historyStr = DeltaChess.UI:FormatMoveHistoryText(board:GetMoveHistory())
    
    if frame.historyText then
        frame.historyText:SetText(historyStr)
        -- Size scroll child to text so scroll range is correct
        local textHeight = frame.historyText:GetStringHeight()
        if frame.historyScrollChild then
            frame.historyScrollChild:SetHeight(math.max(100, textHeight))
        end
        -- Auto-scroll to bottom only when the move history text changed (new move added), not on every clock tick
        if frame.historyScroll then
            local lastStr = frame._lastHistoryStr
            if lastStr ~= historyStr then
                frame._lastHistoryStr = historyStr
                -- Defer scroll to next frame so layout/height is updated before we read scroll range
                C_Timer.After(0, function()
                    if frame.historyScroll and frame.historyScroll:GetParent() then
                        frame.historyScroll:SetVerticalScroll(frame.historyScroll:GetVerticalScrollRange())
                    end
                end)
            end
        end
    end
    
    -- Apply game-over UI state or re-enable buttons when game is active
    if board:IsEnded() then
        DeltaChess.UI:ApplyGameEndUIState(frame)
    else
        -- When a user action is pending (resign confirm or promotion), disable action buttons; otherwise re-enable
        local actionBlocked = (DeltaChess._actionBlocked or 0) > 0
        local currentTurn = board:GetCurrentTurn()
        local myColor = frame.myChessColor
        if actionBlocked then
            if frame.resignButton then frame.resignButton:Disable() end
            if frame.drawButton then frame.drawButton:Disable() end
            if frame.closeButton then frame.closeButton:Disable() end
        elseif board:IsPaused() then
            -- When paused, disable resign and draw but keep pause/unpause button active
            if frame.resignButton then frame.resignButton:Disable() end
            if frame.drawButton then frame.drawButton:Disable() end
        else
            if frame.resignButton then
                frame.resignButton:Enable()
            end
            if frame.drawButton then
                if isVsComputer then
                    frame.drawButton:SetText("Back")
                    frame.drawButton:SetScript("OnClick", function()
                        DeltaChess:TakeBackMove(frame.gameId)
                    end)
                    -- Back (takeback) only when it's the player's turn and there are moves to take back
                    local moveHistory = board:GetMoveHistory()
                    if currentTurn == myColor and #moveHistory > 0 then
                        frame.drawButton:Enable()
                    else
                        frame.drawButton:Disable()
                    end
                else
                    frame.drawButton:Enable()
                end
            end
        end
        if frame.closeButton and not actionBlocked then
            frame.closeButton:Enable()
            if isVsComputer then
                frame.closeButton:SetText("Pause")
                frame.closeButton:SetScript("OnClick", function()
                    local board = DeltaChess.GetBoard(frame.gameId)
                    if board then
                        board:PauseGame()
                    end
                    frame:Hide()
                end)
            else
                if board:IsPaused() then
                    frame.closeButton:SetText("Unpause")
                    frame.closeButton:SetScript("OnClick", function()
                        DeltaChess:RequestUnpause(frame.gameId)
                    end)
                else
                    frame.closeButton:SetText("Pause")
                    frame.closeButton:SetScript("OnClick", function()
                        DeltaChess:RequestPause(frame.gameId)
                    end)
                end
            end
        end
    end
    
    -- Check for game end
    if board:IsEnded() then
        DeltaChess.UI:ShowGameEnd(frame.gameId, frame)
    end
end

-- Show/hide waiting overlay when waiting for ACK
function DeltaChess.UI:ShowWaitingOverlay(frame, show)
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
        
        -- Re-enable action buttons only if game is still active
        local board = DeltaChess.GetBoard(frame.gameId)
        if board and board:IsActive() then
            if frame.resignButton then
                frame.resignButton:Enable()
            end
            if frame.drawButton and not frame.isVsComputer then
                frame.drawButton:Enable()
            end
        end
    end
end

-- Show promotion piece selection dialog
-- fromSquare, toSquare: UCI notation (e.g., "e7", "e8")
function DeltaChess.UI:ShowPromotionDialog(frame, fromSquare, toSquare, isVsComputer)
    -- Close existing promotion dialog
    if DeltaChess.frames.promotionDialog and DeltaChess.frames.promotionDialog:IsShown() then
        DeltaChess.frames.promotionDialog:Hide()
    end

    DeltaChess._actionBlocked = (DeltaChess._actionBlocked or 0) + 1
    if DeltaChess.UI.activeFrame then
        DeltaChess.UI:UpdateBoard(DeltaChess.UI.activeFrame)
    end

    local board = DeltaChess.GetBoard(frame.gameId)
    if not board then return end
    local playerColor = board:GetCurrentTurn()
    local pieceSize = 36
    local padding = 8
    local btnSpacing = 6
    local dialogWidth = (pieceSize + padding * 2) * 4 + btnSpacing * 3 + 30
    local titleAreaHeight = 50
    local dialogHeight = titleAreaHeight + (pieceSize + padding * 2) + 20

    if not DeltaChess.frames.promotionDialog then
        local dialog = CreateFrame("Frame", "ChessPromotionDialog", UIParent, "BasicFrameTemplateWithInset")
        dialog:SetSize(dialogWidth, dialogHeight)
        dialog:SetPoint("CENTER")
        dialog:SetMovable(false)
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetFrameLevel(350)
        dialog.TitleText:SetText("Promote pawn to:")

        local pieceTypes = {"q", "r", "b", "n"}
        for i, pieceType in ipairs(pieceTypes) do
            local btn = CreateFrame("Button", nil, dialog)
            btn:SetSize(pieceSize + padding * 2, pieceSize + padding * 2)
            btn:SetPoint("TOPLEFT", dialog, "TOPLEFT", 15 + (i - 1) * (pieceSize + padding * 2 + btnSpacing), -titleAreaHeight)

            -- Light background so black pieces are visible
            local bg = btn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.85, 0.8, 0.7, 1)
            btn.bg = bg

            local tex = btn:CreateTexture(nil, "ARTWORK")
            tex:SetSize(pieceSize, pieceSize)
            tex:SetPoint("CENTER")
            tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            btn.texture = tex

            local hl = btn:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.4)
            btn:SetHighlightTexture(hl)

            dialog["pieceBtn_" .. pieceType] = btn
        end

        DeltaChess.frames.promotionDialog = dialog
    end

    local dialog = DeltaChess.frames.promotionDialog
    
    -- Helper to clear all highlights
    local function clearHighlights()
        for sq, sqFrame in pairs(frame.squares) do
            if sqFrame.highlight then sqFrame.highlight:Hide() end
            if sqFrame.validMove then sqFrame.validMove:Hide() end
        end
    end
    
    -- Store move info for default promotion if closed without selecting (do not store board; get current via GetBoard in callback)
    dialog.pendingMove = {
        frame = frame,
        fromSquare = fromSquare,
        toSquare = toSquare,
        isVsComputer = isVsComputer
    }
    
    -- Default to queen if dialog is closed without selecting (e.g. via X button)
    dialog:SetScript("OnHide", function(self)
        DeltaChess._actionBlocked = math.max(0, (DeltaChess._actionBlocked or 0) - 1)
        if DeltaChess.UI.activeFrame then
            DeltaChess.UI:UpdateBoard(DeltaChess.UI.activeFrame)
        end
        local pm = self.pendingMove
        if pm and pm.frame.promotionPending then
            pm.frame.promotionPending = nil
            self.pendingMove = nil
            
            -- Clear selection
            pm.frame.selectedSquare = nil
            pm.frame.validMoves = {}
            for sq, sqFrame in pairs(pm.frame.squares) do
                if sqFrame.highlight then sqFrame.highlight:Hide() end
                if sqFrame.validMove then sqFrame.validMove:Hide() end
            end
            
            local board = DeltaChess.GetBoard(pm.frame.gameId)
            if not board then return end
            -- Default to queen promotion
            local uci = pm.fromSquare .. pm.toSquare .. "q"
            if pm.isVsComputer then
                DeltaChess.MakeMove(board, uci)
                
                -- Play sound for player's promotion move
                local lastMove = board:GetLastMove()
                local wasCapture = lastMove and lastMove:IsCapture()
                DeltaChess.Sound:PlayMoveSound(board, true, wasCapture, board)
                
                DeltaChess.UI:UpdateBoardAnimated(pm.frame, true)
                if DeltaChess.Minimap and DeltaChess.Minimap.UpdateYourTurnHighlight then
                    DeltaChess.Minimap:UpdateYourTurnHighlight()
                end
                if board:IsEnded() then
                    DeltaChess.UI:ShowGameEnd(pm.frame.gameId, pm.frame)
                    return
                end
                DeltaChess.AI:MakeMove(pm.frame.gameId, 500)
            else
                DeltaChess:SendMoveWithConfirmation(pm.frame.gameId, uci)
            end
        end
    end)
    
    -- Map piece types to UCI characters, and get proper texture character for player color
    local pieceTypes = {"q", "r", "b", "n"}

    for _, pieceType in ipairs(pieceTypes) do
        local btn = dialog["pieceBtn_" .. pieceType]
        local texChar = playerColor == COLOR.WHITE and pieceType:upper() or pieceType
        btn.texture:SetTexture(DeltaChess.UI:GetPieceTexture(texChar))
        btn:SetScript("OnClick", function()
            frame.promotionPending = nil
            dialog.pendingMove = nil  -- Clear so OnHide doesn't also make a move
            dialog:Hide()

            local board = DeltaChess.GetBoard(frame.gameId)
            if not board then return end
            -- Clear selection
            frame.selectedSquare = nil
            frame.validMoves = {}
            clearHighlights()

            -- Build UCI string with promotion
            local uci = fromSquare .. toSquare .. pieceType
            
            if isVsComputer then
                DeltaChess.MakeMove(board, uci)
                
                -- Play sound for player's promotion move
                local lastMove = board:GetLastMove()
                local wasCapture = lastMove and lastMove:IsCapture()
                DeltaChess.Sound:PlayMoveSound(board, true, wasCapture, board)
                
                DeltaChess.UI:UpdateBoardAnimated(frame, true)
                if DeltaChess.Minimap and DeltaChess.Minimap.UpdateYourTurnHighlight then
                    DeltaChess.Minimap:UpdateYourTurnHighlight()
                end
                if board:IsEnded() then
                    DeltaChess.UI:ShowGameEnd(frame.gameId, frame)
                    return
                end
                DeltaChess.AI:MakeMove(frame.gameId, 500)
            else
                DeltaChess:SendMoveWithConfirmation(frame.gameId, uci)
            end
        end)
    end

    dialog:Show()
end

-- Handle square click (uci is the UCI square notation like "e4")
function DeltaChess.UI:OnSquareClick(frame, uci)
    local board = DeltaChess.GetBoard(frame.gameId)
    if not board then return end
    local piece = DeltaChess.GetPieceAt(board, uci)
    local playerName = DeltaChess:GetFullPlayerName(UnitName("player"))
    
    -- Block moves while a user action is pending (resign confirm or promotion dialog)
    if (DeltaChess._actionBlocked or 0) > 0 then
        return
    end
    
    -- Block moves while the game is paused
    if board:IsPaused() then
        DeltaChess:Print("Game is paused!")
        DeltaChess.Sound:PlayInvalidMove()
        return
    end
    
    -- Get game metadata
    local isVsComputer = board:OneOpponentIsEngine()
    local white = board:GetWhitePlayerName()
    local black = board:GetBlackPlayerName()
    local storedPlayerColor = board:GetPlayerColor()
    
    -- Check if board is locked (waiting for ACK)
    if not isVsComputer and DeltaChess:IsBoardLocked(frame.gameId) then
        DeltaChess:Print("Waiting for opponent to confirm previous move...")
        return
    end
    
    -- Check if it's player's turn
    local playerColor = nil
    if isVsComputer then
        -- In computer games, use stored player color
        playerColor = storedPlayerColor
    else
        -- In multiplayer, check by name
        if white == playerName then
            playerColor = COLOR.WHITE
        elseif black == playerName then
            playerColor = COLOR.BLACK
        end
    end
    
    local currentTurn = board:GetCurrentTurn()
    if not playerColor or currentTurn ~= playerColor then
        if isVsComputer then
            DeltaChess:Print("Wait for the computer to move!")
        else
            DeltaChess:Print("It's not your turn!")
        end
        DeltaChess.Sound:PlayInvalidMove()
        return
    end
    
    if board:IsEnded() then
        DeltaChess:Print("Game has ended!")
        DeltaChess.Sound:PlayInvalidMove()
        return
    end
    
    -- Helper to clear all highlights
    local function clearHighlights()
        for sq, sqFrame in pairs(frame.squares) do
            if sqFrame.highlight then sqFrame.highlight:Hide() end
            if sqFrame.validMove then sqFrame.validMove:Hide() end
        end
    end
    
    -- If no piece selected
    if not frame.selectedSquare then
        if piece and DeltaChess.Board.IsPieceColor(piece, currentTurn) then
            -- Select piece
            frame.selectedSquare = uci
            frame.validMoves = DeltaChess.GetLegalMovesAt(board, uci)
            
            -- Highlight selected square
            frame.squares[uci].highlight:Show()
            
            -- Show valid moves
            for _, move in ipairs(frame.validMoves) do
                frame.squares[move.square].validMove:Show()
            end
        end
    else
        -- Check if clicking on valid move
        local clickedMove = nil
        for _, move in ipairs(frame.validMoves) do
            if move.square == uci then
                clickedMove = move
                break
            end
        end
        
        if clickedMove then
            local fromSquare = frame.selectedSquare
            local toSquare = uci  -- uci parameter is the clicked target square
            local moveUci = fromSquare .. toSquare  -- Build UCI string

            -- Promotion move: show piece selection first
            if clickedMove.promotion then
                frame.promotionPending = true
                DeltaChess.UI:ShowPromotionDialog(frame, fromSquare, toSquare, isVsComputer)
                return
            end
            
            -- Handle based on game type
            if isVsComputer then
                -- Make the move immediately for computer games
                DeltaChess.MakeMove(board, moveUci)
                
                -- Play sound for player's move
                local lastMove = board:GetLastMove()
                local wasCapture = lastMove and lastMove:IsCapture()
                DeltaChess.Sound:PlayMoveSound(board, true, wasCapture, board)
                
                -- Clear selection
                frame.selectedSquare = nil
                frame.validMoves = {}
                
                -- Update display with animation
                DeltaChess.UI:UpdateBoardAnimated(frame, true)
                
                -- Update minimap (now computer's turn, icon should be normal)
                if DeltaChess.Minimap and DeltaChess.Minimap.UpdateYourTurnHighlight then
                    DeltaChess.Minimap:UpdateYourTurnHighlight()
                end
                
                -- Check for game end
                if board:IsEnded() then
                    DeltaChess.UI:ShowGameEnd(frame.gameId, frame)
                    return
                end
                
                -- Trigger AI move
                DeltaChess.AI:MakeMove(frame.gameId, 500)
            else
                -- For multiplayer: send move first, apply after ACK
                -- Clear selection visually
                frame.selectedSquare = nil
                frame.validMoves = {}
                clearHighlights()
                
                -- Send move and wait for ACK (move will be applied when ACK received)
                DeltaChess:SendMoveWithConfirmation(frame.gameId, moveUci)
            end
            
        elseif piece and DeltaChess.Board.IsPieceColor(piece, currentTurn) then
            -- Select different piece
            frame.selectedSquare = uci
            frame.validMoves = DeltaChess.GetLegalMovesAt(board, uci)
            
            -- Clear previous highlights
            clearHighlights()
            
            -- Highlight new selection
            frame.squares[uci].highlight:Show()
            
            -- Show valid moves
            for _, move in ipairs(frame.validMoves) do
                frame.squares[move.square].validMove:Show()
            end
        else
            -- Clicked on invalid square (not a valid move, not own piece)
            -- Play invalid move sound if clicking on opponent piece or occupied square
            if piece then
                DeltaChess.Sound:PlayInvalidMove()
            end
            
            -- Deselect
            frame.selectedSquare = nil
            frame.validMoves = {}
            
            -- Clear highlights
            clearHighlights()
        end
    end
end

-- Apply game-over UI state (clock stopped, buttons disabled). Idempotent; safe to call whenever game is ended.
-- Does not show dialog, play sound, or save to history.
function DeltaChess.UI:ApplyGameEndUIState(frame)
    if not frame or not frame.gameId then return end
    local board = DeltaChess.GetBoard(frame.gameId)
    if not board then return end
    if frame.clockTicker then
        frame.clockTicker:Cancel()
        frame.clockTicker = nil
    end
    if frame.resignButton then
        frame.resignButton:Disable()
    end
    if frame.drawButton then
        if board:OneOpponentIsEngine() and #board:GetMoveHistory() > 0 then
            frame.drawButton:Enable()
        else
            frame.drawButton:Disable()
        end
    end
    if frame.closeButton then
        frame.closeButton:Disable()
    end
end

-- Show game end screen (dialog, sound, save to history). Can be called with or without a board frame.
-- @param gameId string The game ID
-- @param frame table|nil Optional board frame (if open)
function DeltaChess.UI:ShowGameEnd(gameId, frame)
    -- Apply frame UI state if a frame is provided
    if frame then
        self:ApplyGameEndUIState(frame)
    end
    
    local board = DeltaChess.GetBoard(gameId)
    if not board then return end
    
    -- Guard against showing the dialog more than once per game (stored on the board)
    if board:GetGameMeta("_gameEndShown") then return end
    board:SetGameMeta("_gameEndShown", true)
    
    -- Also mark the frame so legacy checks still work
    if frame then
        frame.gameEndShown = true
    end
    
    -- Get game metadata
    local white = board:GetWhitePlayerName()
    local black = board:GetBlackPlayerName()
    local resignedPlayer = board:GetResignedPlayer()
    
    -- Build title: "Player1 vs Player2"
    local titleText = (white or "White") .. " vs " .. (black or "Black")

    local resultText = ""

    local reason = board:GetEndReason()
    local result = board:GetResult()
    
    local winnerName = result == Constants.WHITE and white or (result == Constants.BLACK and black or nil)
    local loserName = result == Constants.WHITE and black or (result == Constants.BLACK and white or nil)
    
    if reason == Constants.REASON_CHECKMATE then
        resultText = (winnerName or "Someone") .. " wins by checkmate!"
    elseif reason == Constants.REASON_STALEMATE then
        resultText = "Draw by stalemate!"
    elseif reason == Constants.REASON_FIFTY_MOVE then
        resultText = "Draw!"
    elseif reason == Constants.REASON_RESIGNATION or resignedPlayer then
        resultText = (resignedPlayer or loserName or "Someone") .. " resigned. " .. 
                     (resignedPlayer and ((resignedPlayer == white) and black or white) or winnerName or "Someone") .. " wins!"
    elseif reason == Constants.REASON_TIMEOUT then
        resultText = (loserName or "Someone") .. " ran out of time. " .. (winnerName or "Someone") .. " wins!"
    end
    
    -- Play game end sound
    DeltaChess.Sound:PlayGameEndSound(board, board)
    
    -- Save the game to history (only if still in active games) — use current board instance
    local boardToSave = DeltaChess.GetBoard(gameId)
    if boardToSave then
        boardToSave:SetEndTime(DeltaChess.Util.TimeNow())
        DeltaChess:SaveGameToHistory(boardToSave)
    end
    
    StaticPopup_Show("CHESS_GAME_END", titleText, resultText)
end

-- Game end popup
StaticPopupDialogs["CHESS_GAME_END"] = {
    text = "%s\n\n%s",
    button1 = "OK",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnShow = function(dialog)
        -- Ensure popup appears above the board and PGN window
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetFrameLevel(350)
    end,
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
    OnShow = function(dialog)
        -- Ensure popup appears above the board
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetFrameLevel(350)
    end,
    timeout = 30,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}
