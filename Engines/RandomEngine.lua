-- RandomEngine.lua - Example engine that picks a random legal move
-- Demonstrates how to plug in a new chess engine (use as template).

local RandomEngine = {
    id = "random",
    name = "Random Move",
    description = "Picks a random legal move each turn"
}

function RandomEngine.GetEloRange(self)
    return nil  -- No ELO setting; strength is fixed
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

function RandomEngine.GetBestMoveAsync(self, board, color, difficulty, onComplete)
    -- Non-blocking: yield before computing to keep game responsive
    DeltaChess.Engines.YieldAfter(function()
        local moves = getAllMoves(board, color)
        if #moves == 0 then
            onComplete(nil)
            return
        end
        local chosen = moves[math.random(1, #moves)]
        onComplete(chosen)
    end)
end

DeltaChess.Engines:Register(RandomEngine)
