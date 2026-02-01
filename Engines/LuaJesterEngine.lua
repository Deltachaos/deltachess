-- LuaJesterEngine.lua - Adapter for LuaJester engine
-- Wraps Engines/luajester/LuaJester.lua to implement DeltaChess engine interface.

local PT = DeltaChess.Constants.PIECE_TYPE
local C = DeltaChess.Constants.COLOR

local LuaJesterEngine = {
    id = "luajester",
    name = "LuaJester",
    description = "Based on the TSCP engine, known for its straightforward design and historical participation in French computer chess tournaments in the late 1990s and early 2000s",
    author = "Stephane N.B. Nguyen",
    portedBy = "Chessforeva",
    url = "https://github.com/Chessforeva/Lua4chess",
    license = "Open Source"
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
    for fenRank = 8, 1, -1 do
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

-- LuaJester uses 0-63 square indices (0=a1, 63=h8). Convert to our {fromRow, fromCol, toRow, toCol}
local function idxToRowCol(idx)
    local row = math.floor(idx / 8) + 1
    local col = (idx % 8) + 1
    return row, col
end

function LuaJesterEngine.GetEloRange(self)
    return { 1000, 1800 }
end

function LuaJesterEngine.GetBestMoveAsync(self, position, color, difficulty, onComplete)
    DeltaChess.Engines.YieldAfter(function()
        if not InitGame or not SetFen or not ComputerMvtAsync then
            onComplete(nil)
            return
        end

        -- Suppress print output during search
        local oldPrint = print
        print = function() end

        -- Always reinitialize to ensure clean state
        InitGame()

        local fen = positionToFen(position)
        SetFen(fen)

        -- Set computer = side to move (the engine searches for this side)
        if color == C.WHITE then
            Js_computer = Js_white
            Js_player = Js_black
        else
            Js_computer = Js_black
            Js_player = Js_white
        end
        Js_enemy = Js_player

        ComputerMvtAsync(DeltaChess.Engines.YieldAfter, function()
            print = oldPrint

            -- LuaJester stores final move in Js_root.f and Js_root.t (0-63 indices)
            local move = nil
            if Js_root and Js_root.f and Js_root.t and Js_root.f ~= Js_root.t then
                local fromRow, fromCol = idxToRowCol(Js_root.f)
                local toRow, toCol = idxToRowCol(Js_root.t)
                move = {
                    fromRow = fromRow,
                    fromCol = fromCol,
                    toRow   = toRow,
                    toCol   = toCol
                }
            end
            onComplete(move)
        end)
    end)
end

DeltaChess.Engines:Register(LuaJesterEngine)
