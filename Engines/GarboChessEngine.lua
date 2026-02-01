-- GarboChessEngine.lua - Adapter for GarboChess engine
-- Wraps Engines/garbochess/garbochess.lua to implement DeltaChess engine interface.
-- The engine is now stateless/object-oriented, allowing parallel game analysis.

local PT = DeltaChess.Constants.PIECE_TYPE
local C = DeltaChess.Constants.COLOR

local GarboChessEngine = {
    id = "garbochess",
    name = "GarboChess",
    description = "Built around classic search algorithms, bitboard-based move generation, and a traditional, positional evaluation function",
    author = "Gary Linscott",
    portedBy = "Chessforeva",
    url = "https://github.com/glinscott/Garbochess-JS",
    license = "BSD-3-Clause"
}

local PIECE_TO_FEN = {
    [PT.PAWN]   = { [C.WHITE] = "P", [C.BLACK] = "p" },
    [PT.KNIGHT] = { [C.WHITE] = "N", [C.BLACK] = "n" },
    [PT.BISHOP] = { [C.WHITE] = "B", [C.BLACK] = "b" },
    [PT.ROOK]   = { [C.WHITE] = "R", [C.BLACK] = "r" },
    [PT.QUEEN]  = { [C.WHITE] = "Q", [C.BLACK] = "q" },
    [PT.KING]   = { [C.WHITE] = "K", [C.BLACK] = "k" },
}

-- Build FEN from DeltaChess position
local function positionToFen(position)
    local ranks = {}
    for fenRank = 8, 1, -1 do  -- FEN order: rank 8 first
        local row = fenRank
        local rankStr = ""
        local empty = 0
        for col = 1, 8 do
            local piece = position:GetPiece(row, col)
            if piece and piece.type and piece.color then
                if empty > 0 then
                    rankStr = rankStr .. tostring(empty)
                    empty = 0
                end
                local tbl = PIECE_TO_FEN[piece.type]
                if tbl then
                    rankStr = rankStr .. (tbl[piece.color] or "?")
                end
            else
                empty = empty + 1
            end
        end
        if empty > 0 then
            rankStr = rankStr .. tostring(empty)
        end
        table.insert(ranks, rankStr)
    end
    local fen = table.concat(ranks, "/")

    fen = fen .. " " .. (position.currentTurn == C.WHITE and "w" or "b") .. " "

    local castle = ""
    if not (position.whiteKingMoved or position.whiteRookKingsideMoved) then
        castle = castle .. "K"
    end
    if not (position.whiteKingMoved or position.whiteRookQueensideMoved) then
        castle = castle .. "Q"
    end
    if not (position.blackKingMoved or position.blackRookKingsideMoved) then
        castle = castle .. "k"
    end
    if not (position.blackKingMoved or position.blackRookQueensideMoved) then
        castle = castle .. "q"
    end
    fen = fen .. (#castle > 0 and castle or "-") .. " "

    if position.enPassantSquare then
        local file = string.char(string.byte("a") + position.enPassantSquare.col - 1)
        fen = fen .. file .. tostring(position.enPassantSquare.row)
    else
        fen = fen .. "-"
    end

    fen = fen .. " " .. tostring(position.halfMoveClock or 0) .. " " .. tostring(position.fullMoveNumber or 1)
    return fen
end

-- Parse "e2e4" style move to {fromRow, fromCol, toRow, toCol}
local function parseMoveStr(moveStr)
    if not moveStr or #moveStr < 4 then return nil end
    local fromFile = string.byte(moveStr:sub(1,1)) - string.byte("a") + 1
    local fromRank = tonumber(moveStr:sub(2,2))
    local toFile   = string.byte(moveStr:sub(3,3)) - string.byte("a") + 1
    local toRank   = tonumber(moveStr:sub(4,4))
    if fromFile and fromRank and toFile and toRank then
        return {
            fromRow = fromRank,
            fromCol = fromFile,
            toRow   = toRank,
            toCol   = toFile
        }
    end
    return nil
end

-- Map ELO difficulty to search ply (GarboChess uses ply for depth)
-- Reduced depths to prevent WoW script timeout
local function difficultyToPly(difficulty)
    if difficulty <= 1500 then return 1 end
    if difficulty <= 1600 then return 2 end
    if difficulty <= 1800 then return 3 end
    if difficulty <= 2000 then return 3 end
    if difficulty <= 2200 then return 4 end
    if difficulty <= 2400 then return 5 end
    if difficulty <= 2600 then return 6 end
    return 7
end

-- Map ELO difficulty to randomness factor (0.0-1.0)
-- Lower ELO = higher randomness = weaker play
-- This perturbs the alpha-beta search bounds to make the engine miss good moves
local function difficultyToRandomness(difficulty)
    local minElo = DeltaChess.Engines:GetGlobalEloRange()[1]
    local maxElo = math.max(1500, minElo)

    -- ELO range: 100 (weakest) to 1500+ (full strength, no randomness)
    -- Randomness: 0.5 at 100, 0.0 at 1500+
    if difficulty >= maxElo then return 0.0 end

    -- Linear interpolation between 1000 (0.5 randomness) and 1500 (0.0 randomness)
    local range = maxElo - minElo
    local normalized = (difficulty - minElo) / range  -- 0.0 at 100, 1.0 at 1500
    return 0.2 * (1.0 - normalized)
end

function GarboChessEngine.GetEloRange(self)
    return { 1000, 2600 }
end

-- Estimated average CPU time in milliseconds for a move at given ELO
-- GarboChess uses bitboards and is well-optimized
function GarboChessEngine.GetAverageCpuTime(self, elo)
    -- Based on ply depth at each ELO level (from difficultyToPly)
    -- GarboChess is faster than minimax at equivalent depth
    if elo <= 1500 then return 100 end     -- ply 1
    if elo <= 1600 then return 200 end     -- ply 2
    if elo <= 2000 then return 800 end     -- ply 3
    if elo <= 2200 then return 1000 end    -- ply 4
    if elo <= 2400 then return 2000 end    -- ply 5
    return 4000                            -- ply 6+
end

function GarboChessEngine.GetBestMoveAsync(self, position, color, difficulty, onComplete)
    DeltaChess.Engines.YieldAfter(function()
        local Garbo = DeltaChess.GarboChess
        if not Garbo then
            onComplete(nil)
            return
        end

        -- Create a fresh state object for this analysis (enables parallel games)
        local state = Garbo.createState()

        -- Initialize from current position
        local fen = positionToFen(position)
        Garbo.InitializeFromFen(state, fen)

        local ply = difficultyToPly(difficulty)
        local randomness = difficultyToRandomness(difficulty)

        Garbo.SearchAsync(state, ply, DeltaChess.Engines.YieldAfter, function()
            local move = nil
            if state.foundmove and state.foundmove ~= 0 then
                local moveStr = Garbo.FormatMove(state.foundmove)
                move = parseMoveStr(moveStr)
            end
            onComplete(move)
        end, randomness)
    end)
end

DeltaChess.Engines:Register(GarboChessEngine)
