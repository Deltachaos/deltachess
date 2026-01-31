-- ChessAI.lua - Simple chess AI opponent

DeltaChess.AI = {}

-- Timer constants (milliseconds); C_Timer.After uses seconds
local AI_YIELD_MS = 8          -- baseline ms between steps when FPS is good
local AI_TARGET_FPS = 40       -- try to keep at least this FPS during AI calculation
local AI_INITIAL_DELAY_MS = 500 -- ms before AI starts thinking

-- Yield delay in ms: longer when FPS is low to keep game responsive (uses GetFramerate())
local function getYieldDelayMs()
    local fps = GetFramerate() or 60
    if fps >= AI_TARGET_FPS then
        return AI_YIELD_MS
    end
    local msPerFrameAtTarget = 1000 / AI_TARGET_FPS
    return math.max(msPerFrameAtTarget, AI_YIELD_MS + (AI_TARGET_FPS - fps) * 2)
end

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

-- Make a temporary move and return state for undo
function DeltaChess.AI:MakeTemporaryMove(board, move)
    local piece = board:GetPiece(move.fromRow, move.fromCol)
    local captured = board:GetPiece(move.toRow, move.toCol)
    local originalType = piece and piece.type or nil
    
    board.squares[move.toRow][move.toCol] = piece
    board.squares[move.fromRow][move.fromCol] = nil
    
    -- Handle pawn promotion (always promote to queen for AI evaluation)
    local wasPromoted = false
    if piece and piece.type == "pawn" then
        local promotionRank = piece.color == "white" and 8 or 1
        if move.toRow == promotionRank then
            piece.type = "queen"
            wasPromoted = true
        end
    end
    
    return { captured = captured, originalType = originalType, wasPromoted = wasPromoted }
end

-- Undo a temporary move
function DeltaChess.AI:UndoTemporaryMove(board, move, state)
    local piece = board:GetPiece(move.toRow, move.toCol)
    
    -- Restore piece type if it was promoted
    if piece and state.wasPromoted then
        piece.type = state.originalType
    end
    
    board.squares[move.fromRow][move.fromCol] = piece
    board.squares[move.toRow][move.toCol] = state.captured
end

-- Minimax with alpha-beta pruning (synchronous, full search)
function DeltaChess.AI:Minimax(board, depth, alpha, beta, maximizingPlayer)
    if depth == 0 then
        return self:EvaluateBoard(board), nil
    end
    
    local color = maximizingPlayer and "white" or "black"
    local moves = self:GetAllMoves(board, color)
    
    if #moves == 0 then
        if board:IsInCheck(color) then
            return maximizingPlayer and -100000 or 100000, nil
        else
            return 0, nil
        end
    end
    
    local bestMove = nil
    
    if maximizingPlayer then
        local maxEval = -math.huge
        for _, move in ipairs(moves) do
            local state = self:MakeTemporaryMove(board, move)
            local eval = self:Minimax(board, depth - 1, alpha, beta, false)
            self:UndoTemporaryMove(board, move, state)
            if eval > maxEval then
                maxEval = eval
                bestMove = move
            end
            alpha = math.max(alpha, eval)
            if beta <= alpha then break end
        end
        return maxEval, bestMove
    else
        local minEval = math.huge
        for _, move in ipairs(moves) do
            local state = self:MakeTemporaryMove(board, move)
            local eval = self:Minimax(board, depth - 1, alpha, beta, true)
            self:UndoTemporaryMove(board, move, state)
            if eval < minEval then
                minEval = eval
                bestMove = move
            end
            beta = math.min(beta, eval)
            if beta <= alpha then break end
        end
        return minEval, bestMove
    end
end

-- Map ELO (100-2500) to search depth and mistake chance
local function eloToParams(difficulty)
    local elo = math.max(100, math.min(2500, tonumber(difficulty) or 1200))
    local depth = math.min(5, math.max(1, math.floor(1 + (elo - 100) / 600)))
    local mistakeChance = math.max(0, 0.55 - (elo - 100) / 4500)
    return depth, mistakeChance
end

-- Async: evaluate root moves one-by-one, yield between each to allow rendering
function DeltaChess.AI:GetBestMoveAsync(board, color, difficulty, onComplete)
    local depth, mistakeChance = eloToParams(difficulty or 1200)
    local maximizing = (color == "white")
    local moves = self:GetAllMoves(board, color)
    
    if #moves == 0 then
        onComplete(nil)
        return
    end
    
    local bestMove, bestEval = moves[1], maximizing and -math.huge or math.huge
    local alpha, beta = -math.huge, math.huge
    local moveIdx = 0
    
    local allEvals = {}  -- for mistake injection: {move, eval}
    
    local function evaluateNextMove()
        moveIdx = moveIdx + 1
        if moveIdx > #moves then
            local finalMove = bestMove
            if mistakeChance > 0 and math.random() < mistakeChance and #allEvals > 1 then
                table.sort(allEvals, function(a, b)
                    if not a then return false end
                    if not b then return true end
                    local ea, eb = a.eval or 0, b.eval or 0
                    return maximizing and ea > eb or ea < eb
                end)
                local worseStart = math.floor(#allEvals / 2) + 1
                local idx = math.random(worseStart, #allEvals)
                finalMove = allEvals[idx] and allEvals[idx].move or bestMove
            end
            onComplete(finalMove)
            return
        end
        
        local move = moves[moveIdx]
        local state = DeltaChess.AI:MakeTemporaryMove(board, move)
        local eval
        if depth <= 1 then
            eval = DeltaChess.AI:EvaluateBoard(board)
        else
            eval = DeltaChess.AI:Minimax(board, depth - 1, alpha, beta, not maximizing)
        end
        DeltaChess.AI:UndoTemporaryMove(board, move, state)
        
        table.insert(allEvals, {move = move, eval = eval})
        
        if maximizing then
            if eval > bestEval then
                bestEval = eval
                bestMove = move
            end
            alpha = math.max(alpha, eval)
        else
            if eval < bestEval then
                bestEval = eval
                bestMove = move
            end
            beta = math.min(beta, eval)
        end
        
        if beta <= alpha then
            local finalMove = bestMove
            if mistakeChance > 0 and math.random() < mistakeChance and #allEvals > 1 then
                table.sort(allEvals, function(a, b)
                    if not a then return false end
                    if not b then return true end
                    local ea, eb = a.eval or 0, b.eval or 0
                    return maximizing and ea > eb or ea < eb
                end)
                local worseStart = math.floor(#allEvals / 2) + 1
                local idx = math.random(worseStart, #allEvals)
                finalMove = allEvals[idx] and allEvals[idx].move or bestMove
            end
            onComplete(finalMove)
            return
        end
        
        C_Timer.After(getYieldDelayMs() / 1000, evaluateNextMove)
    end
    
    C_Timer.After(getYieldDelayMs() / 1000, evaluateNextMove)
end

-- Make AI move with a small delay for better UX (async search, non-blocking)
function DeltaChess.AI:MakeMove(gameId, delayMs)
    local delaySec = (delayMs or AI_INITIAL_DELAY_MS) / 1000
    C_Timer.After(delaySec, function()
        local game = DeltaChess.db.games[gameId]
        if not game or game.status ~= "active" then return end
        if not game.isVsComputer then return end
        
        local aiColor = game.computerColor
        if game.board.currentTurn ~= aiColor then return end
        
        local difficulty = game.computerDifficulty or 1200
        DeltaChess.AI:GetBestMoveAsync(game.board, aiColor, difficulty, function(move)
            if not game or game.status ~= "active" then return end
            if game.board.currentTurn ~= aiColor then return end
            
            if move then
                local piece = game.board:GetPiece(move.fromRow, move.fromCol)
                local promotion = nil
                if piece and piece.type == "pawn" then
                    local promotionRank = piece.color == "white" and 8 or 1
                    if move.toRow == promotionRank then
                        promotion = "queen"
                    end
                end
                
                game.board:MakeMove(move.fromRow, move.fromCol, move.toRow, move.toCol, promotion)
                
                DeltaChess:NotifyItIsYourTurn(gameId, "Computer")
                
                if game.board.gameStatus ~= "active" then
                    DeltaChess.UI:ShowGameEnd(DeltaChess.UI.activeFrame)
                end
            else
                DeltaChess:Print("Computer has no valid moves!")
            end
        end)
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
        computerDifficulty = difficulty or 1200,
        playerColor = playerColor
    }
    
    -- Save game
    self.db.games[gameId] = game
    
    -- Show the board
    self:ShowChessBoard(gameId)
    
    -- If computer plays white, make first move
    if computerColor == "white" then
        DeltaChess.AI:MakeMove(gameId, 1000)
    end
    
    return gameId
end
