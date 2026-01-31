-- ChessAI.lua - Simple chess AI opponent

DeltaChess.AI = {}

-- Piece values for evaluation
local PIECE_VALUES = {
    pawn = 100,
    knight = 320,
    bishop = 330,
    rook = 500,
    queen = 900,
    king = 20000
}

-- Position bonuses for pieces (encourages good positioning)
-- Values are from white's perspective (flip for black)
local PAWN_TABLE = {
    {0,  0,  0,  0,  0,  0,  0,  0},
    {50, 50, 50, 50, 50, 50, 50, 50},
    {10, 10, 20, 30, 30, 20, 10, 10},
    {5,  5, 10, 25, 25, 10,  5,  5},
    {0,  0,  0, 20, 20,  0,  0,  0},
    {5, -5,-10,  0,  0,-10, -5,  5},
    {5, 10, 10,-20,-20, 10, 10,  5},
    {0,  0,  0,  0,  0,  0,  0,  0}
}

local KNIGHT_TABLE = {
    {-50,-40,-30,-30,-30,-30,-40,-50},
    {-40,-20,  0,  0,  0,  0,-20,-40},
    {-30,  0, 10, 15, 15, 10,  0,-30},
    {-30,  5, 15, 20, 20, 15,  5,-30},
    {-30,  0, 15, 20, 20, 15,  0,-30},
    {-30,  5, 10, 15, 15, 10,  5,-30},
    {-40,-20,  0,  5,  5,  0,-20,-40},
    {-50,-40,-30,-30,-30,-30,-40,-50}
}

local BISHOP_TABLE = {
    {-20,-10,-10,-10,-10,-10,-10,-20},
    {-10,  0,  0,  0,  0,  0,  0,-10},
    {-10,  0,  5, 10, 10,  5,  0,-10},
    {-10,  5,  5, 10, 10,  5,  5,-10},
    {-10,  0, 10, 10, 10, 10,  0,-10},
    {-10, 10, 10, 10, 10, 10, 10,-10},
    {-10,  5,  0,  0,  0,  0,  5,-10},
    {-20,-10,-10,-10,-10,-10,-10,-20}
}

local ROOK_TABLE = {
    {0,  0,  0,  0,  0,  0,  0,  0},
    {5, 10, 10, 10, 10, 10, 10,  5},
    {-5,  0,  0,  0,  0,  0,  0, -5},
    {-5,  0,  0,  0,  0,  0,  0, -5},
    {-5,  0,  0,  0,  0,  0,  0, -5},
    {-5,  0,  0,  0,  0,  0,  0, -5},
    {-5,  0,  0,  0,  0,  0,  0, -5},
    {0,  0,  0,  5,  5,  0,  0,  0}
}

local QUEEN_TABLE = {
    {-20,-10,-10, -5, -5,-10,-10,-20},
    {-10,  0,  0,  0,  0,  0,  0,-10},
    {-10,  0,  5,  5,  5,  5,  0,-10},
    {-5,  0,  5,  5,  5,  5,  0, -5},
    {0,  0,  5,  5,  5,  5,  0, -5},
    {-10,  5,  5,  5,  5,  5,  0,-10},
    {-10,  0,  5,  0,  0,  0,  0,-10},
    {-20,-10,-10, -5, -5,-10,-10,-20}
}

local KING_TABLE = {
    {-30,-40,-40,-50,-50,-40,-40,-30},
    {-30,-40,-40,-50,-50,-40,-40,-30},
    {-30,-40,-40,-50,-50,-40,-40,-30},
    {-30,-40,-40,-50,-50,-40,-40,-30},
    {-20,-30,-30,-40,-40,-30,-30,-20},
    {-10,-20,-20,-20,-20,-20,-20,-10},
    {20, 20,  0,  0,  0,  0, 20, 20},
    {20, 30, 10,  0,  0, 10, 30, 20}
}

local POSITION_TABLES = {
    pawn = PAWN_TABLE,
    knight = KNIGHT_TABLE,
    bishop = BISHOP_TABLE,
    rook = ROOK_TABLE,
    queen = QUEEN_TABLE,
    king = KING_TABLE
}

-- Evaluate board position
function DeltaChess.AI:EvaluateBoard(board)
    local score = 0
    
    for row = 1, 8 do
        for col = 1, 8 do
            local piece = board:GetPiece(row, col)
            if piece then
                local pieceValue = PIECE_VALUES[piece.type] or 0
                local positionBonus = 0
                
                -- Get position table for piece type
                local posTable = POSITION_TABLES[piece.type]
                if posTable then
                    if piece.color == "white" then
                        positionBonus = posTable[9 - row][col] or 0
                    else
                        positionBonus = posTable[row][col] or 0
                    end
                end
                
                local totalValue = pieceValue + positionBonus
                
                if piece.color == "white" then
                    score = score + totalValue
                else
                    score = score - totalValue
                end
            end
        end
    end
    
    return score
end

-- Get all possible moves for a color
function DeltaChess.AI:GetAllMoves(board, color)
    local moves = {}
    
    for row = 1, 8 do
        for col = 1, 8 do
            local piece = board:GetPiece(row, col)
            if piece and piece.color == color then
                local validMoves = board:GetValidMoves(row, col)
                for _, move in ipairs(validMoves) do
                    table.insert(moves, {
                        fromRow = row,
                        fromCol = col,
                        toRow = move.row,
                        toCol = move.col
                    })
                end
            end
        end
    end
    
    return moves
end

-- Make a temporary move and return captured piece (for undo)
function DeltaChess.AI:MakeTemporaryMove(board, move)
    local piece = board:GetPiece(move.fromRow, move.fromCol)
    local captured = board:GetPiece(move.toRow, move.toCol)
    
    board.squares[move.toRow][move.toCol] = piece
    board.squares[move.fromRow][move.fromCol] = nil
    
    return captured
end

-- Undo a temporary move
function DeltaChess.AI:UndoTemporaryMove(board, move, captured)
    local piece = board:GetPiece(move.toRow, move.toCol)
    
    board.squares[move.fromRow][move.fromCol] = piece
    board.squares[move.toRow][move.toCol] = captured
end

-- Minimax with alpha-beta pruning
function DeltaChess.AI:Minimax(board, depth, alpha, beta, maximizingPlayer)
    if depth == 0 then
        return self:EvaluateBoard(board), nil
    end
    
    local color = maximizingPlayer and "white" or "black"
    local moves = self:GetAllMoves(board, color)
    
    -- No moves available - checkmate or stalemate
    if #moves == 0 then
        if board:IsInCheck(color) then
            -- Checkmate
            return maximizingPlayer and -100000 or 100000, nil
        else
            -- Stalemate
            return 0, nil
        end
    end
    
    local bestMove = nil
    
    if maximizingPlayer then
        local maxEval = -math.huge
        for _, move in ipairs(moves) do
            local captured = self:MakeTemporaryMove(board, move)
            local eval = self:Minimax(board, depth - 1, alpha, beta, false)
            self:UndoTemporaryMove(board, move, captured)
            
            if eval > maxEval then
                maxEval = eval
                bestMove = move
            end
            
            alpha = math.max(alpha, eval)
            if beta <= alpha then
                break -- Beta cutoff
            end
        end
        return maxEval, bestMove
    else
        local minEval = math.huge
        for _, move in ipairs(moves) do
            local captured = self:MakeTemporaryMove(board, move)
            local eval = self:Minimax(board, depth - 1, alpha, beta, true)
            self:UndoTemporaryMove(board, move, captured)
            
            if eval < minEval then
                minEval = eval
                bestMove = move
            end
            
            beta = math.min(beta, eval)
            if beta <= alpha then
                break -- Alpha cutoff
            end
        end
        return minEval, bestMove
    end
end

-- Get best move for AI
function DeltaChess.AI:GetBestMove(board, color, difficulty)
    -- Difficulty determines search depth
    -- 1 = Easy (depth 1), 2 = Medium (depth 2), 3 = Hard (depth 3)
    local depth = difficulty or 2
    
    local maximizing = (color == "white")
    local _, bestMove = self:Minimax(board, depth, -math.huge, math.huge, maximizing)
    
    return bestMove
end

-- Make AI move with a small delay for better UX
function DeltaChess.AI:MakeMove(gameId, delay)
    delay = delay or 0.5
    
    C_Timer.After(delay, function()
        local game = DeltaChess.db.games[gameId]
        if not game or game.status ~= "active" then return end
        if not game.isVsComputer then return end
        
        -- Check if it's AI's turn
        local aiColor = game.computerColor
        if game.board.currentTurn ~= aiColor then return end
        
        -- Get best move
        local difficulty = game.computerDifficulty or 2
        local move = DeltaChess.AI:GetBestMove(game.board, aiColor, difficulty)
        
        if move then
            -- Make the move
            game.board:MakeMove(move.fromRow, move.fromCol, move.toRow, move.toCol)
            
            -- Update UI if board is open
            if DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId then
                DeltaChess.UI:UpdateBoard(DeltaChess.UI.activeFrame)
            end
            
            -- Play sound
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            
            -- Check for game end
            if game.board.gameStatus ~= "active" then
                DeltaChess.UI:ShowGameEnd(DeltaChess.UI.activeFrame)
            end
        else
            -- No valid moves - game should be over
            DeltaChess:Print("Computer has no valid moves!")
        end
    end)
end

-- Start a game against the computer
function DeltaChess:StartComputerGame(playerColor, difficulty)
    local gameId = "computer_" .. tostring(time()) .. "_" .. math.random(1000, 9999)
    local playerName = self:GetFullPlayerName(UnitName("player"))
    
    local computerColor = playerColor == "white" and "black" or "white"
    
    local game = {
        id = gameId,
        white = playerColor == "white" and playerName or "Computer",
        black = playerColor == "black" and playerName or "Computer",
        board = DeltaChess.Board:New(),
        status = "active",
        settings = {
            useClock = false,
            timeMinutes = 0,
            incrementSeconds = 0
        },
        startTime = time(),
        isVsComputer = true,
        computerColor = computerColor,
        computerDifficulty = difficulty or 2,
        playerColor = playerColor
    }
    
    -- Save game
    self.db.games[gameId] = game
    
    -- Show the board
    self:ShowChessBoard(gameId)
    
    -- If computer plays white, make first move
    if computerColor == "white" then
        DeltaChess.AI:MakeMove(gameId, 1.0)
    end
    
    return gameId
end
