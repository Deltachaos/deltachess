-- GarboChessEngine.lua - Adapter for GarboChess engine
-- Wraps Engines/garbochess/garbochess.lua to implement DeltaChess engine interface.

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
    if difficulty <= 800 then return 2 end
    if difficulty <= 1200 then return 3 end
    if difficulty <= 1600 then return 3 end
    if difficulty <= 2000 then return 4 end
    return 4
end

function GarboChessEngine.GetEloRange(self)
    return { 800, 2000 }
end

local garboInitialized = false

function GarboChessEngine.GetBestMoveAsync(self, position, color, difficulty, onComplete)
    DeltaChess.Engines.YieldAfter(function()
        local Garbo = DeltaChess.GarboChess
        if not Garbo then
            onComplete(nil)
            return
        end

        local env = Garbo.env

        if not garboInitialized then
            Garbo.InitializeEval()
            Garbo.ResetGame()
            garboInitialized = true
        end

        -- Suppress GarboChess print output during search
        local oldPlyCb, oldMoveCb = env.finishPlyCallback, env.finishMoveCallback
        env.finishPlyCallback = function() end
        env.finishMoveCallback = function(bestMove, value, ply)
            if bestMove and bestMove ~= 0 then
                env.g_foundmove = bestMove
            end
        end

        local fen = positionToFen(position)
        Garbo.InitializeFromFen(fen)

        local ply = difficultyToPly(difficulty or 1200)

        Garbo.SearchAsync(ply, DeltaChess.Engines.YieldAfter, function()
            env.finishPlyCallback, env.finishMoveCallback = oldPlyCb, oldMoveCb

            local move = nil
            if env.g_foundmove and env.g_foundmove ~= 0 then
                local moveStr = Garbo.FormatMove(env.g_foundmove)
                move = parseMoveStr(moveStr)
            end
            onComplete(move)
        end)
    end)
end

DeltaChess.Engines:Register(GarboChessEngine)
