-- UI.lua - DeltaChess board user interface

DeltaChess.UI = {}

-- Shared constants
DeltaChess.UI.PIECE_TEXTURES = {
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

DeltaChess.UI.FILE_LABELS = {"a", "b", "c", "d", "e", "f", "g", "h"}

-- Local references for convenience
local PIECE_TEXTURES = DeltaChess.UI.PIECE_TEXTURES
local FILE_LABELS = DeltaChess.UI.FILE_LABELS

-- Board layout constants (shared across functions)
local SQUARE_SIZE = 50
local BOARD_SIZE = SQUARE_SIZE * 8
local LABEL_SIZE = 20
local PLAYER_BAR_HEIGHT = 45
local RIGHT_PANEL_WIDTH = 220

-- Animation settings
DeltaChess.UI.ANIMATION_DURATION = 0.2 -- seconds for piece movement animation
DeltaChess.UI.animatingPiece = nil -- currently animating piece frame

--------------------------------------------------------------------------------
-- CLOCK CALCULATION FUNCTIONS
--------------------------------------------------------------------------------

-- Calculate remaining time for a player based on move timestamps
function DeltaChess.UI:CalculateRemainingTime(game, color)
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
    if game.board.currentTurn == color and (game.status == "active" or game.status == "paused") then
        if game._lastMoveCountWhenPaused and #moves > game._lastMoveCountWhenPaused then
            game.timeSpentClosed = nil
            game._lastMoveCountWhenPaused = nil
        end
        local lastMoveTimestamp
        if #moves == 0 then
            lastMoveTimestamp = gameStartTime
        else
            lastMoveTimestamp = moves[#moves].timestamp or gameStartTime
        end
        local currentThinkTime
        if game.status == "paused" and game.pauseStartTime then
            -- Freeze at pause moment
            currentThinkTime = math.max(0, game.pauseStartTime - lastMoveTimestamp)
        elseif game.pausedByClose and game.pauseClosedAt then
            currentThinkTime = math.max(0, game.pauseClosedAt - lastMoveTimestamp)
        else
            currentThinkTime = time() - lastMoveTimestamp
            if game.timeSpentClosed and game.timeSpentClosed > 0 then
                currentThinkTime = math.max(0, currentThinkTime - game.timeSpentClosed)
            end
        end
        timeUsed = timeUsed + math.max(0, currentThinkTime)
    end
    
    -- Calculate total time with increments
    local totalIncrements = moveCount * increment
    local remainingTime = initialTime + totalIncrements - timeUsed
    
    return math.max(0, remainingTime)
end

-- Format time as MM:SS
function DeltaChess.UI:FormatTime(seconds)
    if not seconds then return "--:--" end
    seconds = math.floor(seconds)
    local mins = math.floor(seconds / 60)
    local secs = seconds % 60
    return string.format("%02d:%02d", mins, secs)
end

-- Calculate total thinking time for a color (all moves + current if their turn)
function DeltaChess.UI:CalculateTotalThinkingTime(game, color)
    if not game then return 0 end
    local gameStartTime = game.startTime or (game.clockData and game.clockData.gameStartTimestamp) or time()
    local moves = game.board.moves or {}
    local totalSec = 0
    
    -- Use move.color to attribute each move (prevTimestamp = last move by anyone)
    local prevTimestamp = gameStartTime
    for i = 1, #moves do
        local move = moves[i]
        local moveColor = (move and move.color) or (i % 2 == 1 and "white" or "black")
        if move and moveColor == color then
            if move.thinkTime then
                totalSec = totalSec + move.thinkTime
            elseif move.timestamp then
                totalSec = totalSec + math.max(0, move.timestamp - prevTimestamp)
            end
        end
        if move and move.timestamp then
            prevTimestamp = move.timestamp
        end
    end
    
    -- Add current thinking time if it's this color's turn
    if game.board.currentTurn == color and (game.status == "active" or game.status == "paused") then
        local lastMoveTimestamp = (#moves == 0) and gameStartTime or (moves[#moves].timestamp or gameStartTime)
        local elapsed
        if game.status == "paused" and game.pauseStartTime then
            elapsed = math.max(0, game.pauseStartTime - lastMoveTimestamp)
        elseif game.pausedByClose and game.pauseClosedAt then
            elapsed = math.max(0, game.pauseClosedAt - lastMoveTimestamp)
        else
            elapsed = time() - lastMoveTimestamp
            if game.timeSpentClosed and game.timeSpentClosed > 0 then
                elapsed = math.max(0, elapsed - game.timeSpentClosed)
            end
        end
        -- Reset timeSpentClosed when a new move has been made since we paused
        if game._lastMoveCountWhenPaused and #moves > game._lastMoveCountWhenPaused then
            game.timeSpentClosed = nil
            game._lastMoveCountWhenPaused = nil
        end
        totalSec = totalSec + elapsed
    end
    
    return totalSec
end

--------------------------------------------------------------------------------
-- SHARED BOARD RENDERING FUNCTIONS
--------------------------------------------------------------------------------

-- Create board squares and labels on a container frame
-- Returns a 2D table of square frames
function DeltaChess.UI:CreateBoardSquares(container, squareSize, labelSize, flipBoard, interactive)
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
function DeltaChess.UI:RenderPieces(squares, boardState, lastMove)
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
            if square.checkIndicator then square.checkIndicator:Hide() end
            if square.highlight then square.highlight:Hide() end
            if square.validMove then square.validMove:Hide() end
            
            -- Last move: highlight via background color (always visible, not covered by pieces)
            local isLastMoveSquare = false
            if lastMove then
                local fromRow = lastMove.fromRow or (lastMove.from and lastMove.from.row)
                local fromCol = lastMove.fromCol or (lastMove.from and lastMove.from.col)
                local toRow = lastMove.toRow or (lastMove.to and lastMove.to.row)
                local toCol = lastMove.toCol or (lastMove.to and lastMove.to.col)
                isLastMoveSquare = (row == fromRow and col == fromCol) or (row == toRow and col == toCol)
            end
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
function DeltaChess.UI:GetInitialBoardState()
    local board = {}
    for row = 1, 8 do
        board[row] = {}
        for col = 1, 8 do
            board[row][col] = nil
        end
    end
    local backRow = {"rook", "knight", "bishop", "queen", "king", "bishop", "knight", "rook"}
    for col = 1, 8 do
        -- Row 1 = white back rank, Row 2 = white pawns
        -- Row 7 = black pawns, Row 8 = black back rank
        board[1][col] = {type = backRow[col], color = "white"}
        board[2][col] = {type = "pawn", color = "white"}
        board[7][col] = {type = "pawn", color = "black"}
        board[8][col] = {type = backRow[col], color = "black"}
    end
    return board
end

-- Apply moves to a board state (for replay)
function DeltaChess.UI:ApplyMovesToBoard(board, moves, upToIndex)
    for i = 1, upToIndex do
        local move = moves[i]
        if move then
            local fromRow = move.fromRow or (move.from and move.from.row)
            local fromCol = move.fromCol or (move.from and move.from.col)
            local toRow = move.toRow or (move.to and move.to.row)
            local toCol = move.toCol or (move.to and move.to.col)
            
            -- Accept both .castle and .castling for backwards compatibility with old saved games
            local castle = move.castle or move.castling
            if castle and fromRow then
                local row = fromRow
                if castle == "kingside" then
                    board[row][7] = board[row][5]
                    board[row][6] = board[row][8]
                    board[row][5] = nil
                    board[row][8] = nil
                elseif castle == "queenside" then
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

--------------------------------------------------------------------------------
-- PIECE MOVEMENT ANIMATION
--------------------------------------------------------------------------------

-- Animate a piece moving from one square to another
-- frame: the chess board frame
-- fromRow, fromCol: source square coordinates
-- toRow, toCol: destination square coordinates
-- piece: the piece data {type, color}
-- onComplete: optional callback when animation finishes
function DeltaChess.UI:AnimatePieceMove(frame, fromRow, fromCol, toRow, toCol, piece, onComplete)
    if not frame or not frame.squares then
        if onComplete then onComplete() end
        return
    end
    
    local fromSquare = frame.squares[fromRow] and frame.squares[fromRow][fromCol]
    local toSquare = frame.squares[toRow] and frame.squares[toRow][toCol]
    
    if not fromSquare or not toSquare then
        if onComplete then onComplete() end
        return
    end
    
    -- Get the texture path for the piece
    local texturePath = PIECE_TEXTURES[piece.color] and PIECE_TEXTURES[piece.color][piece.type]
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
-- This version takes move data directly rather than reading from board.moves
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
    
    -- Extract move coordinates
    local fromRow = move.fromRow or (move.from and move.from.row)
    local fromCol = move.fromCol or (move.from and move.from.col)
    local toRow = move.toRow or (move.to and move.to.row)
    local toCol = move.toCol or (move.to and move.to.col)
    local castle = move.castle or move.castling
    local pieceType = move.piece or move.pieceType or "pawn"
    local pieceColor = move.color or "white"
    
    if not fromRow or not fromCol or not toRow or not toCol then
        if onComplete then onComplete() end
        return
    end
    
    -- For promotion, use the promoted piece type for the animation
    if move.promotion then
        pieceType = move.promotion
    end
    
    local piece = {type = pieceType, color = pieceColor}
    local destSquare = frame.squares[toRow] and frame.squares[toRow][toCol]
    
    -- Hide destination piece during animation using alpha (prevents flicker)
    if destSquare and destSquare.pieceTexture then
        destSquare.pieceTexture:SetAlpha(0)
        table.insert(frame._hiddenPieces, {texture = destSquare.pieceTexture})
    end
    
    if castle then
        -- Castling animation
        local rookFromRow = fromRow
        local rookToRow = fromRow
        local rookFromCol, rookToCol
        if castle == "kingside" then
            rookFromCol = 8
            rookToCol = 6
        else
            rookFromCol = 1
            rookToCol = 4
        end
        
        local rookPiece = {type = "rook", color = pieceColor}
        local rookDestSquare = frame.squares[rookToRow] and frame.squares[rookToRow][rookToCol]
        
        if rookDestSquare and rookDestSquare.pieceTexture then
            rookDestSquare.pieceTexture:SetAlpha(0)
            table.insert(frame._hiddenPieces, {texture = rookDestSquare.pieceTexture})
        end
        
        self:AnimateCastling(frame, fromRow, fromCol, toRow, toCol,
            rookFromRow, rookFromCol, rookToRow, rookToCol,
            piece, rookPiece,
            function()
                -- Restore alpha after animation (also clears tracking)
                if destSquare and destSquare.pieceTexture then
                    destSquare.pieceTexture:SetAlpha(1)
                end
                if rookDestSquare and rookDestSquare.pieceTexture then
                    rookDestSquare.pieceTexture:SetAlpha(1)
                end
                frame._hiddenPieces = nil
                if onComplete then onComplete() end
            end)
    else
        -- Regular move animation
        self:AnimatePieceMove(frame, fromRow, fromCol, toRow, toCol, piece,
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
function DeltaChess.UI:AnimateCastling(frame, kingFromRow, kingFromCol, kingToRow, kingToCol, rookFromRow, rookFromCol, rookToRow, rookToCol, kingPiece, rookPiece, onComplete)
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
    self:AnimatePieceMove(frame, kingFromRow, kingFromCol, kingToRow, kingToCol, kingPiece, checkComplete)
    
    -- Animate rook using secondary frame
    local rookFrame = self.animatingPiece2
    local fromSquare = frame.squares[rookFromRow] and frame.squares[rookFromRow][rookFromCol]
    local toSquare = frame.squares[rookToRow] and frame.squares[rookToRow][rookToCol]
    
    if fromSquare and toSquare then
        local texturePath = PIECE_TEXTURES[rookPiece.color] and PIECE_TEXTURES[rookPiece.color][rookPiece.type]
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

-- Format move as algebraic notation
function DeltaChess.UI:FormatMoveNotation(move)
    if not move then return "" end
    local pieceNames = {king = "K", queen = "Q", rook = "R", bishop = "B", knight = "N", pawn = ""}
    local fromRow = move.fromRow or (move.from and move.from.row) or 1
    local fromCol = move.fromCol or (move.from and move.from.col) or 1
    local toRow = move.toRow or (move.to and move.to.row) or 1
    local toCol = move.toCol or (move.to and move.to.col) or 1
    local pieceType = move.pieceType or move.piece or "pawn"
    
    local notation = pieceNames[pieceType] or ""
    notation = notation .. FILE_LABELS[fromCol] .. fromRow
    notation = notation .. (move.captured and "x" or "-")
    notation = notation .. FILE_LABELS[toCol] .. toRow
    return notation
end

--------------------------------------------------------------------------------
-- GAME BOARD (for active games)
--------------------------------------------------------------------------------

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

-- Calculate material advantage
function DeltaChess.UI:CalculateMaterialAdvantage(capturedByWhite, capturedByBlack)
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
    
    local sorted = {}
    for _, piece in ipairs(capturedPieces) do table.insert(sorted, piece) end
    table.sort(sorted, function(a, b) return (PIECE_VALUES[a.type] or 0) > (PIECE_VALUES[b.type] or 0) end)
    
    local xOffset = 0
    for _, piece in ipairs(sorted) do
        -- Use piece's own color for texture (captured pieces display in their actual color)
        local pieceColor = piece.color or capturedColor
        local texturePath = PIECE_TEXTURES[pieceColor] and PIECE_TEXTURES[pieceColor][piece.type]
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
function DeltaChess.UI:FormatMoveAlgebraic(move)
    if not move then return "" end
    
    local pieceSymbols = {
        king = "K",
        queen = "Q", 
        rook = "R",
        bishop = "B",
        knight = "N",
        pawn = ""
    }
    
    -- Handle castling (accept .castle or .castling for history/replay moves)
    local castle = move.castle or move.castling
    if castle == "kingside" then
        return "O-O"
    elseif castle == "queenside" then
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
    notation = notation .. FILE_LABELS[toCol] .. toRow
    
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
    
    -- Resume counting for computer game when opening
    if game.isVsComputer and game.pausedByClose then
        if game.pauseClosedAt then
            game.timeSpentClosed = (game.timeSpentClosed or 0) + (time() - game.pauseClosedAt)
        end
        game.pausedByClose = nil
        game.pauseClosedAt = nil
    end
    
    -- Close existing board if open
    if DeltaChess.UI.activeFrame then
        DeltaChess.UI.activeFrame:Hide()
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
        local g = self.game
        if g and g.isVsComputer and g.status == "active" then
            g.pausedByClose = true
            g.pauseClosedAt = time()
            g._lastMoveCountWhenPaused = #g.board.moves
        end
    end)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(100)
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
    frame.game = game
    frame.board = game.board
    frame.selectedSquare = nil
    frame.validMoves = {}
    frame.flipBoard = flipBoard
    frame.playerColor = playerColor
    frame.myChessColor = myChessColor
    frame.opponentChessColor = opponentChessColor
    frame.gameEndShown = false  -- Reset so game-end popup can fire for this game
    
    -- Store game data for potential restoration after game end
    frame.isVsComputer = game.isVsComputer
    frame.white = game.white
    frame.black = game.black
    frame.settings = game.settings
    frame.computerDifficulty = game.computerDifficulty
    frame.computerEngine = game.computerEngine
    frame.startTime = game.startTime
    
    local leftMargin = 10
    local topOffset = -30
    
    -- ==================== OPPONENT BAR (TOP) ====================
    local opponentBar = CreateFrame("Frame", nil, frame)
    opponentBar:SetSize(LABEL_SIZE + BOARD_SIZE, PLAYER_BAR_HEIGHT)
    opponentBar:SetPoint("TOPLEFT", frame, "TOPLEFT", leftMargin, topOffset)
    
    local opponentBg = opponentBar:CreateTexture(nil, "BACKGROUND")
    opponentBg:SetAllPoints()
    opponentBg:SetColorTexture(0.15, 0.15, 0.15, 0.8)
    
    -- Opponent name with class color (show "Computer (engine - ELO)" for computer games)
    local displayOpponentName = opponentName:match("^([^%-]+)") or opponentName
    if game.isVsComputer and opponentName == "Computer" and game.computerEngine then
        local engine = DeltaChess.Engines:Get(game.computerEngine)
        local engineName = engine and engine.name or game.computerEngine
        local eloStr = game.computerDifficulty and (" - " .. game.computerDifficulty .. " ELO") or ""
        displayOpponentName = "Computer (" .. engineName .. eloStr .. ")"
    end
    local opR, opG, opB = DeltaChess.UI:GetPlayerColor(opponentName, opponentClass)
    local opponentNameText = opponentBar:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    opponentNameText:SetPoint("LEFT", opponentBar, "LEFT", 5, 8)
    opponentNameText:SetTextColor(opR, opG, opB)
    opponentNameText:SetText(displayOpponentName)
    
    -- Opponent clock (if enabled) or thinking time (when no clock)
    if game.settings.useClock then
        local opponentClock = opponentBar:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        opponentClock:SetPoint("RIGHT", opponentBar, "RIGHT", -10, 0)
        frame.opponentClock = opponentClock
        frame.opponentClockColor = opponentChessColor
    else
        local opponentThinkTime = opponentBar:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        opponentThinkTime:SetPoint("RIGHT", opponentBar, "RIGHT", -10, 0)
        frame.opponentThinkTime = opponentThinkTime
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
    
    -- Player clock (if enabled) or thinking time (when no clock)
    if game.settings.useClock then
        local playerClock = playerBar:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        playerClock:SetPoint("RIGHT", playerBar, "RIGHT", -10, 0)
        frame.playerClock = playerClock
        frame.playerClockColor = myChessColor
    else
        local playerThinkTime = playerBar:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        playerThinkTime:SetPoint("RIGHT", playerBar, "RIGHT", -10, 0)
        frame.playerThinkTime = playerThinkTime
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
    frame.rightPanel = rightPanel
    
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
    frame.historyScroll = historyScroll
    
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
        DeltaChess._resignConfirmGameId = gameId
        StaticPopup_Show("CHESS_RESIGN_CONFIRM", nil, nil, gameId)
    end)
    frame.resignButton = resignButton
    
    local drawButton = CreateFrame("Button", nil, rightPanel, "UIPanelButtonTemplate")
    drawButton:SetSize(buttonWidth, 25)
    drawButton:SetPoint("LEFT", resignButton, "RIGHT", buttonSpacing, 0)
    frame.drawButton = drawButton
    frame.isVsComputer = game.isVsComputer
    
    if game.isVsComputer then
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
    if game.isVsComputer then
        closeButton:SetText("Pause")
        closeButton:SetScript("OnClick", function()
            game.pausedByClose = true
            game.pauseClosedAt = time()
            game._lastMoveCountWhenPaused = #game.board.moves
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
    
    -- Start clock if applicable
    if game.settings.useClock and game.status == "active" then
        DeltaChess.UI:StartClock(frame)
    end
    
    frame:Show()
    
    -- Store frame reference
    DeltaChess.UI.activeFrame = frame
    
    -- Check if there's a pending ACK for this game and show waiting overlay
    if not game.isVsComputer and DeltaChess:IsBoardLocked(gameId) then
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
    
    local board = frame.board
    local moves = board.moves
    local lastMove = moves and moves[#moves]
    
    if not lastMove then
        self:UpdateBoard(frame)
        return
    end
    
    -- Extract move coordinates
    local fromRow = lastMove.fromRow or (lastMove.from and lastMove.from.row)
    local fromCol = lastMove.fromCol or (lastMove.from and lastMove.from.col)
    local toRow = lastMove.toRow or (lastMove.to and lastMove.to.row)
    local toCol = lastMove.toCol or (lastMove.to and lastMove.to.col)
    local castle = lastMove.castle or lastMove.castling
    
    if not fromRow or not fromCol or not toRow or not toCol then
        self:UpdateBoard(frame)
        return
    end
    
    -- Get the piece that was moved (it's now at the destination)
    local piece = board:GetPiece(toRow, toCol)
    if not piece then
        self:UpdateBoard(frame)
        return
    end
    
    -- Store current piece positions for animation
    -- We need to show the board state BEFORE the move for animation
    local destSquare = frame.squares[toRow] and frame.squares[toRow][toCol]
    
    -- For castling, also get rook positions
    local rookFromRow, rookFromCol, rookToRow, rookToCol, rookPiece
    if castle then
        rookFromRow = fromRow
        rookToRow = fromRow
        if castle == "kingside" then
            rookFromCol = 8
            rookToCol = 6
        else -- queenside
            rookFromCol = 1
            rookToCol = 4
        end
        rookPiece = board:GetPiece(rookToRow, rookToCol)
    end
    
    -- Hide destination pieces BEFORE updating board (set alpha to 0)
    -- This prevents the brief flash of the piece at destination
    if destSquare and destSquare.pieceTexture then
        destSquare.pieceTexture:SetAlpha(0)
        table.insert(frame._hiddenPieces, {texture = destSquare.pieceTexture})
    end
    
    local rookDestSquare
    if castle and rookToRow and rookToCol then
        rookDestSquare = frame.squares[rookToRow] and frame.squares[rookToRow][rookToCol]
        if rookDestSquare and rookDestSquare.pieceTexture then
            rookDestSquare.pieceTexture:SetAlpha(0)
            table.insert(frame._hiddenPieces, {texture = rookDestSquare.pieceTexture})
        end
    end
    
    -- Update the board display (destination pieces are invisible due to alpha=0)
    self:UpdateBoard(frame)
    
    -- Ensure alpha is still 0 after UpdateBoard (in case it reset)
    if destSquare and destSquare.pieceTexture then
        destSquare.pieceTexture:SetAlpha(0)
    end
    if rookDestSquare and rookDestSquare.pieceTexture then
        rookDestSquare.pieceTexture:SetAlpha(0)
    end
    
    if castle and rookPiece then
        -- Animate castling (both king and rook)
        self:AnimateCastling(frame, fromRow, fromCol, toRow, toCol, 
            rookFromRow, rookFromCol, rookToRow, rookToCol,
            piece, rookPiece,
            function()
                -- Restore alpha after animation (also clears tracking)
                if destSquare and destSquare.pieceTexture then
                    destSquare.pieceTexture:SetAlpha(1)
                end
                if rookDestSquare and rookDestSquare.pieceTexture then
                    rookDestSquare.pieceTexture:SetAlpha(1)
                end
                frame._hiddenPieces = nil
            end)
    elseif castle then
        -- Fallback: just restore alpha
        if destSquare and destSquare.pieceTexture then
            destSquare.pieceTexture:SetAlpha(1)
        end
        if rookDestSquare and rookDestSquare.pieceTexture then
            rookDestSquare.pieceTexture:SetAlpha(1)
        end
        frame._hiddenPieces = nil
    else
        -- Regular move animation
        self:AnimatePieceMove(frame, fromRow, fromCol, toRow, toCol, piece,
            function()
                -- Restore alpha after animation (also clears tracking)
                if destSquare and destSquare.pieceTexture then
                    destSquare.pieceTexture:SetAlpha(1)
                end
                frame._hiddenPieces = nil
            end)
    end
end

-- Update board display
function DeltaChess.UI:UpdateBoard(frame)
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
    
    -- Last move for highlight (from/to squares)
    local lastMove = board.moves and board.moves[#board.moves] or nil
    local fromRow = lastMove and (lastMove.fromRow or (lastMove.from and lastMove.from.row))
    local fromCol = lastMove and (lastMove.fromCol or (lastMove.from and lastMove.from.col))
    local toRow = lastMove and (lastMove.toRow or (lastMove.to and lastMove.to.row))
    local toCol = lastMove and (lastMove.toCol or (lastMove.to and lastMove.to.col))
    
    -- Update squares
    for row = 1, 8 do
        for col = 1, 8 do
            local square = frame.squares[row][col]
            local piece = board:GetPiece(row, col)
            
            -- Reset indicators
            if square.checkIndicator then square.checkIndicator:Hide() end
            if square.highlight then square.highlight:Hide() end
            if square.validMove then square.validMove:Hide() end
            
            -- Last move: subtle yellow highlight, respecting light/dark squares
            local isLastMoveSquare = lastMove and ((row == fromRow and col == fromCol) or (row == toRow and col == toCol))
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
    
    -- Restore selection highlight and valid moves (UpdateBoard clears them above)
    if frame.selectedSquare and frame.validMoves then
        local row, col = frame.selectedSquare.row, frame.selectedSquare.col
        if frame.squares[row] and frame.squares[row][col] and frame.squares[row][col].highlight then
            frame.squares[row][col].highlight:Show()
            for _, move in ipairs(frame.validMoves) do
                if frame.squares[move.row] and frame.squares[move.row][move.col] and frame.squares[move.row][move.col].validMove then
                    frame.squares[move.row][move.col].validMove:Show()
                end
            end
        end
    end
    
    -- Update Pause/Unpause button state for human games
    if frame.closeButton and not game.isVsComputer then
        if game.status == "paused" then
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
        if game.status == "paused" then
            frame.turnLabel:SetText("|cFFFFFF00Game Paused|r")
        else
            local turn = board.currentTurn
            local turnColor = turn == "white" and "|cFFFFFFFF" or "|cFF888888"
            frame.turnLabel:SetText(turnColor .. (turn == "white" and "White" or "Black") .. " to move|r")
        end
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
    
    -- Update clocks or thinking time
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
    else
        -- Show total thinking time for both sides (vs human or computer)
        local myTotalSec = DeltaChess.UI:CalculateTotalThinkingTime(game, myColor)
        local opponentTotalSec = DeltaChess.UI:CalculateTotalThinkingTime(game, opponentColor)
        local myTurn = board.currentTurn == myColor
        
        if frame.playerThinkTime then
            local timeColor = myTurn and "|cFFFFFF00" or "|cFFFFFFFF"
            frame.playerThinkTime:SetText(timeColor .. DeltaChess.UI:FormatTime(myTotalSec) .. "|r")
            frame.playerThinkTime:Show()
        end
        
        if frame.opponentThinkTime then
            local timeColor = not myTurn and "|cFFFFFF00" or "|cFFFFFFFF"
            frame.opponentThinkTime:SetText(timeColor .. DeltaChess.UI:FormatTime(opponentTotalSec) .. "|r")
            frame.opponentThinkTime:Show()
        end
        
        -- Refresh thinking time every second while game is active (not when paused or ended)
        if game.status == "active" and board.gameStatus == "active" and not game.pausedByClose and frame:IsShown() then
            C_Timer.After(1, function()
                if frame.game and frame.gameId and DeltaChess.UI.activeFrame == frame and frame:IsShown() 
                   and frame.board.gameStatus == "active" then
                    DeltaChess.UI:UpdateBoard(frame)
                end
            end)
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
    
    -- Disable resign/draw/pause when game is over (but keep Back enabled for vs computer)
    if board.gameStatus ~= "active" then
        if frame.resignButton then
            frame.resignButton:Disable()
        end
        if frame.drawButton then
            if game.isVsComputer then
                -- Keep Back button enabled even when game ends
                frame.drawButton:Enable()
            else
                frame.drawButton:Disable()
            end
        end
        if frame.closeButton then
            frame.closeButton:Disable()
        end
    else
        -- Re-enable resign, pause, and draw when game is active (e.g. after takeback)
        if frame.resignButton then
            frame.resignButton:Enable()
        end
        if frame.drawButton then
            if game.isVsComputer then
                frame.drawButton:SetText("Back")
                frame.drawButton:SetScript("OnClick", function()
                    DeltaChess:TakeBackMove(frame.gameId)
                end)
            end
            frame.drawButton:Enable()
        end
        if frame.closeButton then
            frame.closeButton:Enable()
            if game.isVsComputer then
                frame.closeButton:SetText("Pause")
                frame.closeButton:SetScript("OnClick", function()
                    game.pausedByClose = true
                    game.pauseClosedAt = time()
                    game._lastMoveCountWhenPaused = #game.board.moves
                    frame:Hide()
                end)
            else
                if game.status == "paused" then
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
    if board.gameStatus ~= "active" then
        DeltaChess.UI:ShowGameEnd(frame)
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
        if frame.board and frame.board.gameStatus == "active" then
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
function DeltaChess.UI:ShowPromotionDialog(frame, fromRow, fromCol, toRow, toCol, isVsComputer)
    -- Close existing promotion dialog
    if DeltaChess.frames.promotionDialog and DeltaChess.frames.promotionDialog:IsShown() then
        DeltaChess.frames.promotionDialog:Hide()
    end

    local board = frame.board
    local playerColor = board.currentTurn
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
        dialog:SetFrameLevel(200)
        dialog.TitleText:SetText("Promote pawn to:")

        local pieceTypes = {"queen", "rook", "bishop", "knight"}
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
    
    -- Store move info for default promotion if closed without selecting
    dialog.pendingMove = {
        frame = frame,
        board = board,
        fromRow = fromRow,
        fromCol = fromCol,
        toRow = toRow,
        toCol = toCol,
        isVsComputer = isVsComputer
    }
    
    -- Default to queen if dialog is closed without selecting (e.g. via X button)
    dialog:SetScript("OnHide", function(self)
        local pm = self.pendingMove
        if pm and pm.frame.promotionPending then
            pm.frame.promotionPending = nil
            self.pendingMove = nil
            
            -- Clear selection
            pm.frame.selectedSquare = nil
            pm.frame.validMoves = {}
            for r = 1, 8 do
                for c = 1, 8 do
                    pm.frame.squares[r][c].highlight:Hide()
                    pm.frame.squares[r][c].validMove:Hide()
                end
            end
            
            -- Default to queen promotion
            if pm.isVsComputer then
                pm.board:MakeMove(pm.fromRow, pm.fromCol, pm.toRow, pm.toCol, "queen")
                
                -- Play sound for player's promotion move
                local lastMove = pm.board.moves and pm.board.moves[#pm.board.moves]
                local wasCapture = lastMove and lastMove.captured ~= nil
                local game = pm.frame.game
                if game then
                    DeltaChess.Sound:PlayMoveSound(game, true, wasCapture, pm.board)
                end
                
                DeltaChess.UI:UpdateBoardAnimated(pm.frame, true)
                if DeltaChess.Minimap and DeltaChess.Minimap.UpdateYourTurnHighlight then
                    DeltaChess.Minimap:UpdateYourTurnHighlight()
                end
                if pm.board.gameStatus ~= "active" then
                    DeltaChess.UI:ShowGameEnd(pm.frame)
                    return
                end
                DeltaChess.AI:MakeMove(pm.frame.gameId, 500)
            else
                DeltaChess:SendMoveWithConfirmation(pm.frame.gameId, pm.fromRow, pm.fromCol, pm.toRow, pm.toCol, "queen")
            end
        end
    end)
    local pieceTypes = {"queen", "rook", "bishop", "knight"}
    local textures = PIECE_TEXTURES[playerColor]

    for _, pieceType in ipairs(pieceTypes) do
        local btn = dialog["pieceBtn_" .. pieceType]
        btn.texture:SetTexture(textures[pieceType])
        btn:SetScript("OnClick", function()
            frame.promotionPending = nil
            dialog.pendingMove = nil  -- Clear so OnHide doesn't also make a move
            dialog:Hide()

            -- Clear selection
            frame.selectedSquare = nil
            frame.validMoves = {}
            for r = 1, 8 do
                for c = 1, 8 do
                    frame.squares[r][c].highlight:Hide()
                    frame.squares[r][c].validMove:Hide()
                end
            end

            if isVsComputer then
                board:MakeMove(fromRow, fromCol, toRow, toCol, pieceType)
                
                -- Play sound for player's promotion move
                local lastMove = board.moves and board.moves[#board.moves]
                local wasCapture = lastMove and lastMove.captured ~= nil
                local game = frame.game
                if game then
                    DeltaChess.Sound:PlayMoveSound(game, true, wasCapture, board)
                end
                
                DeltaChess.UI:UpdateBoardAnimated(frame, true)
                if DeltaChess.Minimap and DeltaChess.Minimap.UpdateYourTurnHighlight then
                    DeltaChess.Minimap:UpdateYourTurnHighlight()
                end
                if board.gameStatus ~= "active" then
                    DeltaChess.UI:ShowGameEnd(frame)
                    return
                end
                DeltaChess.AI:MakeMove(frame.gameId, 500)
            else
                DeltaChess:SendMoveWithConfirmation(frame.gameId, fromRow, fromCol, toRow, toCol, pieceType)
            end
        end)
    end

    dialog:Show()
end

-- Handle square click
function DeltaChess.UI:OnSquareClick(frame, row, col)
    local board = frame.board
    local piece = board:GetPiece(row, col)
    local playerName = DeltaChess:GetFullPlayerName(UnitName("player"))
    local game = frame.game
    
    -- Check if board is locked for promotion selection
    if frame.promotionPending then
        return
    end
    
    -- Block moves while resign confirmation dialog is open
    if DeltaChess._resignConfirmGameId and frame.gameId == DeltaChess._resignConfirmGameId then
        return
    end
    
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
        DeltaChess.Sound:PlayInvalidMove()
        return
    end
    
    if board.gameStatus ~= "active" then
        DeltaChess:Print("Game has ended!")
        DeltaChess.Sound:PlayInvalidMove()
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
            local clickedMove = nil
            for _, m in ipairs(frame.validMoves) do
                if m.row == row and m.col == col then
                    clickedMove = m
                    break
                end
            end

            -- Promotion move: show piece selection first
            if clickedMove and clickedMove.promotion then
                frame.promotionPending = true
                DeltaChess.UI:ShowPromotionDialog(frame, fromRow, fromCol, row, col, game.isVsComputer)
                return
            end
            
            -- Handle based on game type
            if game.isVsComputer then
                -- Make the move immediately for computer games
                board:MakeMove(fromRow, fromCol, row, col)
                
                -- Play sound for player's move
                local lastMove = board.moves and board.moves[#board.moves]
                local wasCapture = lastMove and lastMove.captured ~= nil
                DeltaChess.Sound:PlayMoveSound(game, true, wasCapture, board)
                
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
                if board.gameStatus ~= "active" then
                    DeltaChess.UI:ShowGameEnd(frame)
                    return
                end
                
                -- Trigger AI move
                DeltaChess.AI:MakeMove(frame.gameId, 500)
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
            -- Clicked on invalid square (not a valid move, not own piece)
            -- Play invalid move sound if clicking on opponent piece or occupied square
            if piece then
                DeltaChess.Sound:PlayInvalidMove()
            end
            
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
function DeltaChess.UI:FormatTime(seconds)
    local mins = math.floor(seconds / 60)
    local secs = seconds % 60
    return string.format("%d:%02d", mins, secs)
end

-- Start clock (recalculates time from timestamps each tick)
function DeltaChess.UI:StartClock(frame)
    local game = frame.game
    local board = frame.board
    local myColor = frame.myChessColor
    local opponentColor = frame.opponentChessColor
    
    frame.clockTicker = C_Timer.NewTicker(1, function()
        if not frame:IsShown() or game.status ~= "active" or game.pausedByClose or board.gameStatus ~= "active" then
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
function DeltaChess.UI:ShowGameEnd(frame)
    -- Prevent showing multiple times
    if frame.gameEndShown then
        return
    end
    frame.gameEndShown = true
    
    -- Stop the clock ticker immediately
    if frame.clockTicker then
        frame.clockTicker:Cancel()
        frame.clockTicker = nil
    end
    
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
    
    -- Play game end sound
    DeltaChess.Sound:PlayGameEndSound(game, board)
    
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
    OnShow = function(dialog)
        -- Ensure popup appears above the board (FULLSCREEN_DIALOG level 100)
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetFrameLevel(200)
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
    timeout = 30,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}
