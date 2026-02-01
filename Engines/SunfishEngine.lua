-- SunfishEngine.lua - Adapter for Lua4chess Sunfish engine
-- Wraps sunfish.lua to implement DeltaChess engine interface.

local PT = DeltaChess.Constants.PIECE_TYPE
local C = DeltaChess.Constants.COLOR

local SunfishEngine = {
    id = "sunfish",
    name = "Sunfish.lua",
    description = "Minimalist MTD-bi based chess engine, featuring a compact search algorithm with simple evaluation",
    author = "Thomas Ahle",
    portedBy = "Soumith Chintala",
    url = "https://github.com/soumith/sunfish.lua",
    license = "GPL-3.0"
}

function SunfishEngine.GetEloRange(self)
    return { 100, 1800 }
end

-- Estimated average CPU time in milliseconds for a move at given ELO
-- Sunfish uses node limits which correlate roughly to time
function SunfishEngine.GetAverageCpuTime(self, elo)
    if elo <= 400 then return 400 end      -- ~500-1000 nodes
    if elo <= 800 then return 600 end      -- ~1000-2000 nodes
    if elo <= 1200 then return 1200 end    -- ~2000-3500 nodes
    if elo <= 1500 then return 1800 end    -- ~3500-5000 nodes
    return 2500                             -- ~5000-6000 nodes
end

-- Map ELO difficulty to maxn (maximum nodes to search)
-- Lower ELO = fewer nodes = weaker play
-- Higher ELO = more nodes = stronger play
-- Sunfish is not very efficient, so we cap at 6000 nodes max
local function difficultyToMaxn(difficulty)
    -- ELO range: 100-1800
    -- Node range: 500 (weakest) to 6000 (strongest)
    if difficulty <= 100 then return 500 end
    if difficulty >= 1800 then return 6000 end

    -- Exponential scaling for more natural difficulty curve
    -- 100 ELO -> 500 nodes, 1800 ELO -> 6000 nodes
    local minElo, maxElo = 100, 1800
    local minNodes, maxNodes = 500, 6000

    local normalized = (difficulty - minElo) / (maxElo - minElo)  -- 0.0 to 1.0
    -- Use exponential interpolation for smoother difficulty curve
    local logMin = math.log(minNodes)
    local logMax = math.log(maxNodes)
    local logNodes = logMin + normalized * (logMax - logMin)
    return math.floor(math.exp(logNodes))
end

-- Sunfish board: 120-char string, 0-based indices A1=91, H1=98, A8=21, H8=28
-- Our row 1-8, col 1-8: row 1 = white back rank, row 8 = black back rank
local function rowColToIdx(row, col)
    return 91 + (col - 1) - 10 * (row - 1)
end

local function idxToRowCol(idx)
    local row = 8 - math.floor((idx - 21) / 10)
    local col = (idx - 21) % 10 + 1
    return row, col
end

local PIECE_TO_CHAR = {
    [PT.PAWN] = { [C.WHITE] = "P", [C.BLACK] = "p" },
    [PT.KNIGHT] = { [C.WHITE] = "N", [C.BLACK] = "n" },
    [PT.BISHOP] = { [C.WHITE] = "B", [C.BLACK] = "b" },
    [PT.ROOK] = { [C.WHITE] = "R", [C.BLACK] = "r" },
    [PT.QUEEN] = { [C.WHITE] = "Q", [C.BLACK] = "q" },
    [PT.KING] = { [C.WHITE] = "K", [C.BLACK] = "k" },
}

local INITIAL_BOARD = "         \n" .. "         \n" ..
    " ........\n" .. " ........\n" .. " ........\n" .. " ........\n" ..
    " ........\n" .. " ........\n" .. " ........\n" .. " ........\n" ..
    "         \n" .. "          "

local function positionToSunfishBoard(position)
    local board = {}
    for i = 1, 120 do
        board[i] = INITIAL_BOARD:sub(i, i)
    end
    for row = 1, 8 do
        for col = 1, 8 do
            local piece = position:GetPiece(row, col)
            if piece and piece.type and piece.color then
                local tbl = PIECE_TO_CHAR[piece.type]
                if tbl then
                    local ch = tbl[piece.color]
                    if ch then
                        local idx = rowColToIdx(row, col)
                        board[idx + 1] = ch  -- Lua 1-based
                    end
                end
            end
        end
    end
    return table.concat(board)
end

-- Get castling rights: Sunfish wc = {queenside, kingside} for white
local function getCastlingRights(position)
    local wc = {
        not (position.whiteKingMoved or position.whiteRookQueensideMoved),
        not (position.whiteKingMoved or position.whiteRookKingsideMoved)
    }
    local bc = {
        not (position.blackKingMoved or position.blackRookQueensideMoved),
        not (position.blackKingMoved or position.blackRookKingsideMoved)
    }
    return wc, bc
end

-- Get en passant and king square for Sunfish (0-based indices)
local function getEpKp(position)
    local ep, kp = 0, 0
    if position.enPassantSquare then
        ep = rowColToIdx(position.enPassantSquare.row, position.enPassantSquare.col)
    end
    for row = 1, 8 do
        for col = 1, 8 do
            local piece = position:GetPiece(row, col)
            if piece and piece.type == PT.KING and piece.color == C.WHITE then
                kp = rowColToIdx(row, col)
                break
            end
        end
    end
    return ep, kp
end

local function swapcase(s)
    local r = ""
    for i = 1, #s do
        local c = s:sub(i, i)
        if c:match("%u") then
            r = r .. c:lower()
        elseif c:match("%l") then
            r = r .. c:upper()
        else
            r = r .. c
        end
    end
    return r
end

-- Convert our position to Sunfish Position (side to move = white/uppercase)
-- When black to move, Sunfish expects rotated board per Position:rotate()
local function positionToSunfish(position, colorToMove)
    local Sunfish = DeltaChess.Sunfish
    if not Sunfish then return nil end

    local board = positionToSunfishBoard(position)
    local wc, bc = getCastlingRights(position)
    local ep, kp = getEpKp(position)
    if colorToMove == C.BLACK then
        board = swapcase(board:reverse())
        ep = ep > 0 and (119 - ep) or 0
        kp = kp > 0 and (119 - kp) or 0
        wc, bc = bc, wc
    end
    return Sunfish.Position.new(board, 0, wc, bc, ep, kp)
end

-- Convert Sunfish move {fromIdx, toIdx} (0-based indices) to our {fromRow, fromCol, toRow, toCol}
-- Sunfish returns move in rotated coords when black to move
local function sunfishMoveToOurs(move, colorToMove)
    if not move or #move < 2 then return nil end
    local i, j = move[1], move[2]
    if colorToMove == C.BLACK then
        i, j = 119 - i, 119 - j
    end
    local fromRow, fromCol = idxToRowCol(i)
    local toRow, toCol = idxToRowCol(j)
    if fromRow and fromCol and toRow and toCol then
        return { fromRow = fromRow, fromCol = fromCol, toRow = toRow, toCol = toCol }
    end
    return nil
end

function SunfishEngine.GetBestMoveAsync(self, position, color, difficulty, onComplete)
    DeltaChess.Engines.YieldAfter(function()
        local Sunfish = DeltaChess.Sunfish
        if not Sunfish then
            onComplete(nil)
            return
        end

        local sunfishPos = positionToSunfish(position, color)
        if not sunfishPos then
            onComplete(nil)
            return
        end

        local maxn = difficultyToMaxn(difficulty or 1200)

        Sunfish.searchAsync(sunfishPos, maxn, DeltaChess.Engines.YieldAfter, function(move, score)
            local ourMove = sunfishMoveToOurs(move, color)
            onComplete(ourMove)
        end)
    end)
end

DeltaChess.Engines:Register(SunfishEngine)
