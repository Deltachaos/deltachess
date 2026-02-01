-- MinimaxEngine.lua - Alpha-beta minimax chess engine
-- Implements the DeltaChess engine interface for pluggable AI.

local PT = DeltaChess.Constants.PIECE_TYPE
local C = DeltaChess.Constants.COLOR

local MinimaxEngine = {
    id = "minimax",
    name = "Minimax Alpha-Beta",
    description = "Classic minimax with alpha-beta pruning, iterative deepening, and piece-square tables",
    author = "Deltachaos",
    url = "https://github.com/Deltachaos/deltachess",
    license = "GPL-3.0"
}

function MinimaxEngine.GetEloRange(self)
    return { 100, 1000 }
end

-- Estimated average CPU time in milliseconds for a move at given ELO
-- Minimax is relatively fast at low depths but scales poorly
function MinimaxEngine.GetAverageCpuTime(self, elo)
    -- Based on depth used at each ELO level (from eloToParams)
    -- depth 1: ~50ms, depth 2: ~200ms, depth 3: ~800ms, depth 4: ~3000ms
    if elo <= 400 then return 100 end      -- depth 1
    if elo <= 700 then return 200 end     -- depth 2
    if elo <= 850 then return 800 end     -- depth 3
    return 3000                            -- depth 4
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

-- Position bonuses (white's perspective; flip for black)
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

local function evaluateBoard(board)
    local score = 0
    for row = 1, 8 do
        for col = 1, 8 do
            local piece = board:GetPiece(row, col)
            if piece then
                local pieceValue = PIECE_VALUES[piece.type] or 0
                local posTable = POSITION_TABLES[piece.type]
                local positionBonus = 0
                if posTable then
                    positionBonus = piece.color == C.WHITE and (posTable[9 - row][col] or 0) or (posTable[row][col] or 0)
                end
                local totalValue = pieceValue + positionBonus
                score = score + (piece.color == C.WHITE and totalValue or -totalValue)
            end
        end
    end
    return score
end

local function getAllMoves(board, color)
    local moves = {}
    for row = 1, 8 do
        for col = 1, 8 do
            local piece = board:GetPiece(row, col)
            if piece and piece.color == color then
                for _, m in ipairs(board:GetValidMoves(row, col)) do
                    table.insert(moves, { fromRow = row, fromCol = col, toRow = m.row, toCol = m.col })
                end
            end
        end
    end
    return moves
end

local function orderMoves(board, moves)
    local function moveScore(m)
        local captured = board:GetPiece(m.toRow, m.toCol)
        local mover = board:GetPiece(m.fromRow, m.fromCol)
        if captured then
            local victimVal = PIECE_VALUES[captured.type] or 100
            local attackerVal = PIECE_VALUES[mover and mover.type or PT.PAWN] or 100
            return 10000 + victimVal * 10 - attackerVal
        end
        return 0
    end
    table.sort(moves, function(a, b) return moveScore(a) > moveScore(b) end)
    return moves
end

local function makeTemporaryMove(board, move)
    local piece = board:GetPiece(move.fromRow, move.fromCol)
    local captured = board:GetPiece(move.toRow, move.toCol)
    local originalType = piece and piece.type or nil
    board.squares[move.toRow][move.toCol] = piece
    board.squares[move.fromRow][move.fromCol] = nil
    local wasPromoted = false
    if piece and piece.type == PT.PAWN then
        local promotionRank = piece.color == C.WHITE and 8 or 1
        if move.toRow == promotionRank then
            piece.type = PT.QUEEN
            wasPromoted = true
        end
    end
    return { captured = captured, originalType = originalType, wasPromoted = wasPromoted }
end

local function undoTemporaryMove(board, move, state)
    local piece = board:GetPiece(move.toRow, move.toCol)
    if piece and state.wasPromoted then
        piece.type = state.originalType
    end
    board.squares[move.fromRow][move.fromCol] = piece
    board.squares[move.toRow][move.toCol] = state.captured
end

-- Node counter for limiting synchronous work
local nodeCounter = { count = 0, limit = 5000 }

local function minimax(board, depth, alpha, beta, maximizingPlayer)
    -- Increment node counter and check limit
    nodeCounter.count = nodeCounter.count + 1
    if nodeCounter.count > nodeCounter.limit then
        -- Return early with current evaluation to prevent script timeout
        return evaluateBoard(board), nil
    end
    
    if depth == 0 then
        return evaluateBoard(board), nil
    end
    local color = maximizingPlayer and C.WHITE or C.BLACK
    local moves = getAllMoves(board, color)
    orderMoves(board, moves)
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
            local state = makeTemporaryMove(board, move)
            local eval = minimax(board, depth - 1, alpha, beta, false)
            undoTemporaryMove(board, move, state)
            if eval > maxEval then maxEval, bestMove = eval, move end
            alpha = math.max(alpha, eval)
            if beta <= alpha then break end
        end
        return maxEval, bestMove
    else
        local minEval = math.huge
        for _, move in ipairs(moves) do
            local state = makeTemporaryMove(board, move)
            local eval = minimax(board, depth - 1, alpha, beta, true)
            undoTemporaryMove(board, move, state)
            if eval < minEval then minEval, bestMove = eval, move end
            beta = math.min(beta, eval)
            if beta <= alpha then break end
        end
        return minEval, bestMove
    end
end

local function eloToParams(difficulty)
    local maxElo = DeltaChess.Engines:GetGlobalEloRange()[2]
    local difficulty = difficulty * 3
    local elo = math.max(100, math.min(maxElo, tonumber(difficulty)))
    local depth = math.min(5, math.max(1, math.floor(1 + (elo - 100) / 650)))
    local mistakeChance = math.max(0, 0.10 - (elo - 100) / maxElo)
    return depth, mistakeChance
end

local function putFirst(moves, bestMove)
    if not bestMove then return moves end
    for i, m in ipairs(moves) do
        if m.fromRow == bestMove.fromRow and m.fromCol == bestMove.fromCol and
           m.toRow == bestMove.toRow and m.toCol == bestMove.toCol then
            table.remove(moves, i)
            table.insert(moves, 1, m)
            break
        end
    end
    return moves
end

function MinimaxEngine.GetBestMoveAsync(self, board, color, difficulty, onComplete)
    local searchBoard = board:GetSearchCopy()
    local maxDepth, mistakeChance = eloToParams(difficulty)
    local maximizing = (color == C.WHITE)
    local bestMoveSoFar = nil

    local function searchDepth(currentDepth)
        local moves = getAllMoves(searchBoard, color)
        if #moves == 0 then
            onComplete(nil)
            return
        end
        orderMoves(searchBoard, moves)
        putFirst(moves, bestMoveSoFar)
        local bestMove, bestEval = nil, maximizing and -math.huge or math.huge
        local alpha, beta = -math.huge, math.huge
        local allEvals = {}
        local moveIdx = 0

        local function evalNext()
            moveIdx = moveIdx + 1
            if moveIdx > #moves then
                if bestMove and mistakeChance > 0 and math.random() < mistakeChance and #allEvals > 1 then
                    table.sort(allEvals, function(a, b)
                        if not a then return false end
                        if not b then return true end
                        local ea, eb = a.eval or 0, b.eval or 0
                        return maximizing and (ea > eb) or (not maximizing and ea < eb)
                    end)
                    local worseStart = math.floor(#allEvals / 2) + 1
                    local idx = math.random(worseStart, #allEvals)
                    bestMove = allEvals[idx] and allEvals[idx].move or bestMove
                end
                bestMoveSoFar = bestMove
                if currentDepth >= maxDepth then
                    onComplete(bestMoveSoFar)
                    return
                end
                DeltaChess.Engines.YieldAfter(function() searchDepth(currentDepth + 1) end)
                return
            end

            local move = moves[moveIdx]
            local state = makeTemporaryMove(searchBoard, move)
            local eval
            if currentDepth <= 1 then
                eval = evaluateBoard(searchBoard)
            else
                -- Reset node counter before each minimax call to prevent timeout
                nodeCounter.count = 0
                eval = minimax(searchBoard, currentDepth - 1, alpha, beta, not maximizing)
            end
            undoTemporaryMove(searchBoard, move, state)
            table.insert(allEvals, { move = move, eval = eval })

            if maximizing then
                if eval > bestEval then bestEval, bestMove = eval, move end
                alpha = math.max(alpha, eval)
            else
                if eval < bestEval then bestEval, bestMove = eval, move end
                beta = math.min(beta, eval)
            end

            if beta <= alpha then
                bestMoveSoFar = bestMove
                if currentDepth >= maxDepth then
                    onComplete(bestMoveSoFar)
                    return
                end
                DeltaChess.Engines.YieldAfter(function() searchDepth(currentDepth + 1) end)
                return
            end
            DeltaChess.Engines.YieldAfter(evalNext)
        end
        DeltaChess.Engines.YieldAfter(evalNext)
    end

    DeltaChess.Engines.YieldAfter(function() searchDepth(1) end)
end

-- Register this engine when loaded
DeltaChess.Engines:Register(MinimaxEngine)
