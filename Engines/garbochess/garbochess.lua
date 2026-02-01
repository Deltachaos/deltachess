-- # Credits
--
-- Name: GarboChess
-- Author: Gary Linscott (http://forwardcoding.com)
-- Source: https://github.com/glinscott/Garbochess-JS
-- License: BSD-3-Clause
--
-- ## LUA Port
-- Author: Chessforeva
-- Source: https://github.com/Chessforeva/Lua4chess
--
-- Adjustments have been made to make it compatible for use
-- in this World of Warcraft Addon. Redistributed under the
-- same terms and conditions as the original Author.
--
-- Just because this is absolutely brilliant code for
-- interpreted chess - the optimal AI for videogames :)
-- Very needed for scripting. Just could not find better.
--
-- Refactored to be object-oriented for parallel game analysis.

-- Sandbox environment to avoid global namespace pollution
local _ENV = setmetatable({}, {__index = _G})
setfenv(1, _ENV)

-- Use DeltaChess namespaced bit operations
local bit = DeltaChess.BitOp

--------------------------------------------------------------------------------
-- CONSTANTS (module-level, shared across all instances)
--------------------------------------------------------------------------------

local colorBlack = 0x10
local colorWhite = 0x08

local pieceEmpty = 0x00
local piecePawn = 0x01
local pieceKnight = 0x02
local pieceBishop = 0x03
local pieceRook = 0x04
local pieceQueen = 0x05
local pieceKing = 0x06

local g_bishopDeltas = {-15, -17, 15, 17}
local g_knightDeltas = {31, 33, 14, -14, -31, -33, 18, -18}
local g_rookDeltas = {-1, 1, -16, 16}
local g_queenDeltas = {-1, 1, -15, 15, -17, 17, -16, 16}

local g_seeValues = {0, 1, 3, 3, 5, 9, 900, 0, 0, 1, 3, 3, 5, 9, 900, 0}

local g_castleRightsMask = {
0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
0, 0, 0, 0, 7,15,15,15, 3,15,15,11, 0, 0, 0, 0,
0, 0, 0, 0,15,15,15,15,15,15,15,15, 0, 0, 0, 0,
0, 0, 0, 0,15,15,15,15,15,15,15,15, 0, 0, 0, 0,
0, 0, 0, 0,15,15,15,15,15,15,15,15, 0, 0, 0, 0,
0, 0, 0, 0,15,15,15,15,15,15,15,15, 0, 0, 0, 0,
0, 0, 0, 0,15,15,15,15,15,15,15,15, 0, 0, 0, 0,
0, 0, 0, 0,15,15,15,15,15,15,15,15, 0, 0, 0, 0,
0, 0, 0, 0,13,15,15,15,12,15,15,14, 0, 0, 0, 0,
0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }

local moveflagEPC = bit.lshift(0x2, 16)
local moveflagCastleKing = bit.lshift(0x4, 16)
local moveflagCastleQueen = bit.lshift(0x8, 16)
local moveflagPromotion = bit.lshift(0x10, 16)
local moveflagPromoteKnight = bit.lshift(0x20, 16)
local moveflagPromoteQueen = bit.lshift(0x40, 16)
local moveflagPromoteBishop = bit.lshift(0x80, 16)

local hashflagAlpha = 1
local hashflagBeta = 2
local hashflagExact = 3

local minEval = -2000000
local maxEval = 2000000

local minMateBuffer = minEval + 2000
local maxMateBuffer = maxEval - 2000

local materialTable = {0, 800, 3350, 3450, 5000, 9750, 600000}

local pawnAdj = {
  0, 0, 0, 0, 0, 0, 0, 0,
  -25, 105, 135, 270, 270, 135, 105, -25,
  -80, 0, 30, 176, 176, 30, 0, -80,
  -85, -5, 25, 175, 175, 25, -5, -85,
  -90, -10, 20, 125, 125, 20, -10, -90,
  -95, -15, 15, 75, 75, 15, -15, -95,
  -100, -20, 10, 70, 70, 10, -20, -100,
  0, 0, 0, 0, 0, 0, 0, 0
}

local knightAdj = {
    -200, -100, -50, -50, -50, -50, -100, -200,
      -100, 0, 0, 0, 0, 0, 0, -100,
      -50, 0, 60, 60, 60, 60, 0, -50,
      -50, 0, 30, 60, 60, 30, 0, -50,
      -50, 0, 30, 60, 60, 30, 0, -50,
      -50, 0, 30, 30, 30, 30, 0, -50,
      -100, 0, 0, 0, 0, 0, 0, -100,
      -200, -50, -25, -25, -25, -25, -50, -200
}

local bishopAdj = {
    -50,-50,-25,-10,-10,-25,-50,-50,
      -50,-25,-10,  0,  0,-10,-25,-50,
      -25,-10,  0, 25, 25,  0,-10,-25,
      -10,  0, 25, 40, 40, 25,  0,-10,
      -10,  0, 25, 40, 40, 25,  0,-10,
      -25,-10,  0, 25, 25,  0,-10,-25,
      -50,-25,-10,  0,  0,-10,-25,-50,
      -50,-50,-25,-10,-10,-25,-50,-50
}

local rookAdj = {
    -60, -30, -10, 20, 20, -10, -30, -60,
       40,  70,  90,120,120,  90,  70,  40,
      -60, -30, -10, 20, 20, -10, -30, -60,
      -60, -30, -10, 20, 20, -10, -30, -60,
      -60, -30, -10, 20, 20, -10, -30, -60,
      -60, -30, -10, 20, 20, -10, -30, -60,
      -60, -30, -10, 20, 20, -10, -30, -60,
      -60, -30, -10, 20, 20, -10, -30, -60
}

local kingAdj = {
    50, 150, -25, -125, -125, -25, 150, 50,
       50, 150, -25, -125, -125, -25, 150, 50,
       50, 150, -25, -125, -125, -25, 150, 50,
       50, 150, -25, -125, -125, -25, 150, 50,
       50, 150, -25, -125, -125, -25, 150, 50,
       50, 150, -25, -125, -125, -25, 150, 50,
       50, 150, -25, -125, -125, -25, 150, 50,
      150, 250, 75, -25, -25, 75, 250, 150
}

local emptyAdj = {
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
}

local PieceCharList = {" ", "p", "n", "b", "r", "q", "k", " "}

--------------------------------------------------------------------------------
-- STATIC MODULE DATA (initialized once, shared across all instances)
--------------------------------------------------------------------------------

local g_vectorDelta = {}
local pieceSquareAdj = {}
local flipTable = {}
local g_zobristLow = {}
local g_zobristHigh = {}
local g_zobristBlackLow = 0
local g_zobristBlackHigh = 0
local g_mobUnit = {}
local g_hashSize = bit.lshift(1, 22)
local g_hashMask = g_hashSize - 1

local moduleInitialized = false

--------------------------------------------------------------------------------
-- UTILITY FUNCTIONS
--------------------------------------------------------------------------------

local function iif(ask, ontrue, onfalse)
    if (ask) then
        return ontrue
    end
    return onfalse
end

local function MakeSquare(row, column)
    return bit.bor(bit.lshift((row + 2), 4), (column + 4))
end

local function FormatSquare(square)
    return string.char(string.byte("a", 1) + bit.band(square, 0xF) - 4) ..
        string.format("%d", (9 - bit.rshift(square, 4)) + 1)
end

local function deFormatSquare(at)
    local h = string.byte(at, 1) - string.byte("a", 1) + 4
    local v = 9 - (string.byte(at, 2) - string.byte("0", 1) - 1)
    return bit.bor(h, bit.lshift(v, 4))
end

local function MakeTable(tbl)
    local result = {}
    for i = 0, 255, 1 do
        result[1 + i] = 0
    end
    for row = 0, 7, 1 do
        for col = 0, 7, 1 do
            result[1 + MakeSquare(row, col)] = tbl[1 + ((row * 8) + col)]
        end
    end
    return result
end

local function GenerateMove(from, to)
    return bit.bor(from, bit.lshift(to, 8))
end

local function GenerateMove2(from, to, flags)
    return bit.bor(from, bit.bor(bit.lshift(to, 8), flags))
end

--------------------------------------------------------------------------------
-- MERSENNE TWISTER (for Zobrist key generation)
--------------------------------------------------------------------------------

local mt = {}
mt.N = 624
mt.M = 397
mt.MAG01 = {0x0, 0x9908b0df}
mt.mt = {}
mt.mti = mt.N + 1

mt.setSeed = function(N0)
    mt.mt[1] = N0
    for i = 1, mt.N - 1, 1 do
        local s = bit.bxor(mt.mt[1 + (i - 1)], bit.rshift(mt.mt[1 + (i - 1)], 30))
        mt.mt[1 + i] =
            bit.lshift((1812433253 * bit.rshift(bit.band(s, 0xffff0000), 16)), 16) +
            1812433253 * bit.band(s, 0x0000ffff) +
            i
    end
    mt.mti = mt.N
end

mt.next = function(bits)
    local x, y, k = 0, 0, 0

    if (mt.mti >= mt.N) then
        for k = 0, (mt.N - mt.M) - 1, 1 do
            x = bit.bor(bit.band(mt.mt[1 + k], 0x80000000), bit.band(mt.mt[1 + (k + 1)], 0x7fffffff))
            mt.mt[1 + k] = bit.bxor(bit.bxor(mt.mt[1 + (k + mt.M)], bit.rshift(x, 1), mt.MAG01[1 + bit.band(x, 0x1)]))
        end

        for k = mt.N - mt.M, (mt.N - 1) - 1, 1 do
            x = bit.bor(bit.band(mt.mt[1 + k], 0x80000000), bit.band(mt.mt[1 + (k + 1)], 0x7fffffff))
            mt.mt[1 + k] =
                bit.bxor(bit.bxor(mt.mt[1 + k + (mt.M - mt.N)], bit.rshift(x, 1), mt.MAG01[1 + bit.band(x, 0x1)]))
        end
        x = bit.bor(bit.band(mt.mt[1 + (mt.N - 1)], 0x80000000), bit.band(mt.mt[1], 0x7fffffff))
        mt.mt[1 + (mt.N - 1)] =
            bit.bxor(bit.bxor(mt.mt[1 + (mt.M - 1)], bit.rshift(x, 1), mt.MAG01[1 + bit.band(x, 0x1)]))
        mt.mti = 0
    end

    y = mt.mt[1 + mt.mti]
    mt.mti = mt.mti + 1
    y = bit.bxor(y, bit.rshift(y, 11))
    y = bit.bxor(y, bit.band(bit.lshift(y, 7), 0x9d2c5680))
    y = bit.bxor(y, bit.band(bit.lshift(y, 15), 0xefc60000))
    y = bit.bxor(y, bit.rshift(y, 18))
    y = bit.band(bit.rshift(y, (32 - bits)), 0xFFFFFFFF)
    return y
end

--------------------------------------------------------------------------------
-- MODULE INITIALIZATION (called once to set up static data)
--------------------------------------------------------------------------------

local function InitializeModule()
    if moduleInitialized then return end

    mt.setSeed(0x1BADF00D)

    -- Initialize Zobrist keys
    for i = 0, 255, 1 do
        g_zobristLow[1 + i] = {}
        g_zobristHigh[1 + i] = {}
        for j = 0, 15, 1 do
            g_zobristLow[1 + i][1 + j] = mt.next(32)
            g_zobristHigh[1 + i][1 + j] = mt.next(32)
        end
    end
    g_zobristBlackLow = mt.next(32)
    g_zobristBlackHigh = mt.next(32)

    -- Initialize flip table
    for row = 0, 7, 1 do
        for col = 0, 7, 1 do
            local square = MakeSquare(row, col)
            flipTable[1 + square] = MakeSquare(7 - row, col)
        end
    end

    -- Initialize piece square adjustment tables
    pieceSquareAdj[1 + piecePawn] = MakeTable(pawnAdj)
    pieceSquareAdj[1 + pieceKnight] = MakeTable(knightAdj)
    pieceSquareAdj[1 + pieceBishop] = MakeTable(bishopAdj)
    pieceSquareAdj[1 + pieceRook] = MakeTable(rookAdj)
    pieceSquareAdj[1 + pieceQueen] = MakeTable(emptyAdj)
    pieceSquareAdj[1 + pieceKing] = MakeTable(kingAdj)

    -- Initialize vector delta table
    local pieceDeltas = {{}, {}, g_knightDeltas, g_bishopDeltas, g_rookDeltas, g_queenDeltas, g_queenDeltas}

    for i = 0, 255, 1 do
        g_vectorDelta[1 + i] = {}
        g_vectorDelta[1 + i].delta = 0
        g_vectorDelta[1 + i].pieceMask = {}
        g_vectorDelta[1 + i].pieceMask[1 + 0] = 0
        g_vectorDelta[1 + i].pieceMask[1 + 1] = 0
    end

    local row = 0
    while (row < 0x80) do
        local col = 0
        while (col < 0x8) do
            local square = bit.bor(row, col)

            -- Pawn moves
            local index = square - (square - 17) + 128
            g_vectorDelta[1 + index].pieceMask[1 + bit.rshift(colorWhite, 3)] =
                bit.bor(g_vectorDelta[1 + index].pieceMask[1 + bit.rshift(colorWhite, 3)], bit.lshift(1, piecePawn))
            index = square - (square - 15) + 128
            g_vectorDelta[1 + index].pieceMask[1 + bit.rshift(colorWhite, 3)] =
                bit.bor(g_vectorDelta[1 + index].pieceMask[1 + bit.rshift(colorWhite, 3)], bit.lshift(1, piecePawn))

            index = square - (square + 17) + 128
            g_vectorDelta[1 + index].pieceMask[1] =
                bit.bor(g_vectorDelta[1 + index].pieceMask[1], bit.lshift(1, piecePawn))
            index = square - (square + 15) + 128
            g_vectorDelta[1 + index].pieceMask[1] =
                bit.bor(g_vectorDelta[1 + index].pieceMask[1], bit.lshift(1, piecePawn))

            for i = pieceKnight, pieceKing, 1 do
                local dir = 0
                while (dir < table.getn(pieceDeltas[1 + i])) do
                    local target = square + pieceDeltas[1 + i][1 + dir]
                    while (bit.band(target, 0x88) == 0) do
                        index = square - target + 128

                        g_vectorDelta[1 + index].pieceMask[1 + bit.rshift(colorWhite, 3)] =
                            bit.bor(g_vectorDelta[1 + index].pieceMask[1 + bit.rshift(colorWhite, 3)], bit.lshift(1, i))
                        g_vectorDelta[1 + index].pieceMask[1] =
                            bit.bor(g_vectorDelta[1 + index].pieceMask[1 + 0], bit.lshift(1, i))

                        local flip = -1
                        if (square < target) then
                            flip = 1
                        end
                        if (bit.band(square, 0xF0) == bit.band(target, 0xF0)) then
                            g_vectorDelta[1 + index].delta = flip * 1
                        elseif (bit.band(square, 0x0F) == bit.band(target, 0x0F)) then
                            g_vectorDelta[1 + index].delta = flip * 16
                        elseif ((square % 15) == (target % 15)) then
                            g_vectorDelta[1 + index].delta = flip * 15
                        elseif ((square % 17) == (target % 17)) then
                            g_vectorDelta[1 + index].delta = flip * 17
                        end

                        if (i == pieceKnight) then
                            g_vectorDelta[1 + index].delta = pieceDeltas[1 + i][1 + dir]
                            break
                        end

                        if (i == pieceKing) then
                            break
                        end

                        target = target + pieceDeltas[1 + i][1 + dir]
                    end

                    dir = dir + 1
                end
            end
            col = col + 1
        end
        row = row + 0x10
    end

    -- Initialize mobility unit tables
    for i = 0, 1, 1 do
        g_mobUnit[1 + i] = {}
        local enemy = iif(i == 0, 0x10, 8)
        local friend = iif(i == 0, 8, 0x10)
        g_mobUnit[1 + i][1] = 1
        g_mobUnit[1 + i][1 + 0x80] = 0
        g_mobUnit[1 + i][1 + bit.bor(enemy, piecePawn)] = 1
        g_mobUnit[1 + i][1 + bit.bor(enemy, pieceBishop)] = 1
        g_mobUnit[1 + i][1 + bit.bor(enemy, pieceKnight)] = 1
        g_mobUnit[1 + i][1 + bit.bor(enemy, pieceRook)] = 1
        g_mobUnit[1 + i][1 + bit.bor(enemy, pieceQueen)] = 1
        g_mobUnit[1 + i][1 + bit.bor(enemy, pieceKing)] = 1
        g_mobUnit[1 + i][1 + bit.bor(friend, piecePawn)] = 0
        g_mobUnit[1 + i][1 + bit.bor(friend, pieceBishop)] = 0
        g_mobUnit[1 + i][1 + bit.bor(friend, pieceKnight)] = 0
        g_mobUnit[1 + i][1 + bit.bor(friend, pieceRook)] = 0
        g_mobUnit[1 + i][1 + bit.bor(friend, pieceQueen)] = 0
        g_mobUnit[1 + i][1 + bit.bor(friend, pieceKing)] = 0
    end

    moduleInitialized = true
end

--------------------------------------------------------------------------------
-- GAME STATE OBJECT
--------------------------------------------------------------------------------

local function createState()
    InitializeModule()

    local state = {
        -- Configuration
        timeout = 5,
        maxfinCnt = 20000,

        -- Board state
        board = {},
        toMove = 0,
        castleRights = 0,
        enPassentSquare = 0,
        baseEval = 0,
        hashKeyLow = 0,
        hashKeyHigh = 0,
        inCheck = false,

        -- Move tracking
        moveCount = 0,
        moveUndoStack = {},
        move50 = 0,
        repMoveStack = {},

        -- Search state
        hashTable = {},
        killers = {},
        historyTable = {},
        pieceIndex = {},
        pieceList = {},
        pieceCount = {},

        -- Search counters
        nodeCount = 0,
        qNodeCount = 0,
        searchValid = true,
        globalPly = 0,
        startTime = 0,
        finCnt = 0,
        foundmove = 0,
    }

    -- Initialize killers
    for i = 0, 127, 1 do
        state.killers[1 + i] = {0, 0}
    end

    -- Initialize history table
    for i = 0, 31, 1 do
        state.historyTable[1 + i] = {}
        for j = 0, 255, 1 do
            state.historyTable[1 + i][1 + j] = 0
        end
    end

    return state
end

--------------------------------------------------------------------------------
-- HASH FUNCTIONS
--------------------------------------------------------------------------------

local function HashEntry(lock, value, flags, hashDepth, bestMove, globalPly)
    return {
        lock = lock,
        value = value,
        flags = flags,
        hashDepth = hashDepth,
        bestMove = bestMove
    }
end

local function StoreHash(state, value, flags, ply, move, depth)
    local val = value
    if (val >= maxMateBuffer) then
        val = val + depth
    elseif (val <= minMateBuffer) then
        val = val - depth
    end
    state.hashTable[1 + bit.band(state.hashKeyLow, g_hashMask)] = HashEntry(state.hashKeyHigh, val, flags, ply, move)
end

local function SetHash(state)
    local result = { hashKeyLow = 0, hashKeyHigh = 0 }

    for i = 0, 255, 1 do
        local piece = state.board[1 + i]
        if (bit.band(piece, 0x18) > 0) then
            result.hashKeyLow = bit.bxor(result.hashKeyLow, g_zobristLow[1 + i][1 + bit.band(piece, 0xF)])
            result.hashKeyHigh = bit.bxor(result.hashKeyHigh, g_zobristHigh[1 + i][1 + bit.band(piece, 0xF)])
        end
    end

    if (state.toMove == 0) then
        result.hashKeyLow = bit.bxor(result.hashKeyLow, g_zobristBlackLow)
        result.hashKeyHigh = bit.bxor(result.hashKeyHigh, g_zobristBlackHigh)
    end

    return result
end

--------------------------------------------------------------------------------
-- PIECE LIST FUNCTIONS
--------------------------------------------------------------------------------

local function InitializePieceList(state)
    for i = 0, 15, 1 do
        state.pieceCount[1 + i] = 0
        for j = 0, 15, 1 do
            state.pieceList[1 + bit.bor(bit.lshift(i, 4), j)] = 0
        end
    end

    for i = 0, 255, 1 do
        state.pieceIndex[1 + i] = 0
        if (bit.band(state.board[1 + i], bit.bor(colorWhite, colorBlack)) > 0) then
            local piece = bit.band(state.board[1 + i], 0xF)
            state.pieceList[1 + bit.bor(bit.lshift(piece, 4), state.pieceCount[1 + piece])] = i
            state.pieceIndex[1 + i] = state.pieceCount[1 + piece]
            state.pieceCount[1 + piece] = state.pieceCount[1 + piece] + 1
        end
    end
end

--------------------------------------------------------------------------------
-- ATTACK DETECTION
--------------------------------------------------------------------------------

local function IsSquareAttackableFrom(state, target, from)
    local index = from - target + 128
    local piece = state.board[1 + from]

    if (bit.band(
            g_vectorDelta[1 + index].pieceMask[1 + bit.band(bit.rshift(piece, 3), 1)],
            bit.lshift(1, bit.band(piece, 0x7))
        ) > 0) then
        local inc = g_vectorDelta[1 + index].delta
        local pos = from
        while (true) do
            pos = pos + inc
            if (pos == target) then
                return true
            end
            if (state.board[1 + pos] ~= 0) then
                break
            end
        end
    end

    return false
end

local function IsSquareAttackable(state, target, color)
    local inc = iif(color > 0, -16, 16)
    local pawn = bit.bor(iif(color > 0, colorWhite, colorBlack), 1)

    if (state.board[1 + target - (inc - 1)] == pawn) then
        return true
    end
    if (state.board[1 + target - (inc + 1)] == pawn) then
        return true
    end

    for i = 2, 6, 1 do
        local index = bit.lshift(bit.bor(color, i), 4)
        local square = state.pieceList[1 + index]
        while (square ~= 0) do
            if (IsSquareAttackableFrom(state, target, square)) then
                return true
            end
            index = index + 1
            square = state.pieceList[1 + index]
        end
    end
    return false
end

local function ExposesCheck(state, from, kingPos)
    local index = kingPos - from + 128
    if (bit.band(g_vectorDelta[1 + index].pieceMask[1], bit.lshift(1, pieceQueen)) ~= 0) then
        local delta = g_vectorDelta[1 + index].delta
        local pos = kingPos + delta
        while (state.board[1 + pos] == 0) do
            pos = pos + delta
        end

        local piece = state.board[1 + pos]
        if (bit.band(bit.band(piece, bit.bxor(state.board[1 + kingPos], 0x18)), 0x18) == 0) then
            return false
        end

        local backwardIndex = pos - kingPos + 128
        return (bit.band(
            g_vectorDelta[1 + backwardIndex].pieceMask[1 + bit.band(bit.rshift(piece, 3), 1)],
            bit.lshift(1, bit.band(piece, 0x7))
        ) ~= 0)
    end
    return false
end

local function IsSquareOnPieceLine(state, target, from)
    local index = from - target + 128
    local piece = state.board[1 + from]
    return (bit.band(
        g_vectorDelta[1 + index].pieceMask[1 + bit.band(bit.rshift(piece, 3), 1)],
        bit.lshift(1, bit.band(piece, 0x7))
    ) > 0)
end

--------------------------------------------------------------------------------
-- HASH MOVE VALIDATION
--------------------------------------------------------------------------------

local function IsHashMoveValid(state, hashMove)
    local from = bit.band(hashMove, 0xFF)
    local to = bit.band(bit.rshift(hashMove, 8), 0xFF)
    local dir = to - from
    local ourPiece = state.board[1 + from]
    local pieceType = bit.band(ourPiece, 0x7)

    if (pieceType < piecePawn or pieceType > pieceKing) then
        return false
    end

    if (state.toMove ~= bit.band(ourPiece, 0x8)) then
        return false
    end

    if (state.board[1 + to] ~= 0 and (state.toMove == bit.band(state.board[1 + to], 0x8))) then
        return false
    end

    if (pieceType == piecePawn) then
        if (bit.band(hashMove, moveflagEPC) > 0) then
            return false
        end

        if ((state.toMove == colorWhite) ~= (dir < 0)) then
            return false
        end

        local row = bit.band(to, 0xF0)
        if (((row == 0x90 and (state.toMove == 0)) or (row == 0x20 and state.toMove > 0)) ~=
                (bit.band(hashMove, moveflagPromotion) > 0)) then
            return false
        end

        if (dir == -16 or dir == 16) then
            return (state.board[1 + to] == 0)
        elseif (dir == -15 or dir == -17 or dir == 15 or dir == 17) then
            return (state.board[1 + to] ~= 0)
        elseif (dir == -32) then
            if (row ~= 0x60) then return false end
            if (state.board[1 + to] ~= 0) then return false end
            if (state.board[1 + (from - 16)] ~= 0) then return false end
        elseif (dir == 32) then
            if (row ~= 0x50) then return false end
            if (state.board[1 + to] ~= 0) then return false end
            if (state.board[1 + (from + 16)] ~= 0) then return false end
        else
            return false
        end

        return true
    else
        if (bit.rshift(hashMove, 16) > 0) then
            return false
        end
        return IsSquareAttackableFrom(state, to, from)
    end
end

--------------------------------------------------------------------------------
-- REPETITION DETECTION
--------------------------------------------------------------------------------

local function IsRepDraw(state)
    local i = state.moveCount - 5
    local stop = state.moveCount - 1 - state.move50
    stop = iif(stop < 0, 0, stop)

    while (i >= stop) do
        if (state.repMoveStack[1 + i] == state.hashKeyLow) then
            return true
        end
        i = i - 2
    end
    return false
end

--------------------------------------------------------------------------------
-- UNDO HISTORY
--------------------------------------------------------------------------------

local function UndoHistory(ep, castleRights, inCheck, baseEval, hashKeyLow, hashKeyHigh, move50, captured)
    return {
        ep = ep,
        castleRights = castleRights,
        inCheck = inCheck,
        baseEval = baseEval,
        hashKeyLow = hashKeyLow,
        hashKeyHigh = hashKeyHigh,
        move50 = move50,
        captured = captured
    }
end

--------------------------------------------------------------------------------
-- MOVE GENERATION HELPERS
--------------------------------------------------------------------------------

local function MSt(state, moveStack, usage, from, dt, enemy)
    local to = from + dt
    if (usage == 1) then
        if ((enemy == nil and state.board[1 + to] == 0) or (enemy ~= nil and bit.band(state.board[1 + to], enemy) > 0)) then
            moveStack[1 + table.getn(moveStack)] = GenerateMove(from, to)
        end
    elseif (usage == 2) then
        while (state.board[1 + to] == 0) do
            moveStack[1 + table.getn(moveStack)] = GenerateMove(from, to)
            to = to + dt
        end
    elseif (usage == 3) then
        while (state.board[1 + to] == 0) do
            to = to + dt
        end
        if (bit.band(state.board[1 + to], enemy) > 0) then
            moveStack[1 + table.getn(moveStack)] = GenerateMove(from, to)
        end
    end
end

local function MovePawnTo(moveStack, start, square)
    local row = bit.band(square, 0xF0)
    if ((row == 0x90) or (row == 0x20)) then
        moveStack[1 + table.getn(moveStack)] = GenerateMove2(start, square, bit.bor(moveflagPromotion, moveflagPromoteQueen))
        moveStack[1 + table.getn(moveStack)] = GenerateMove2(start, square, bit.bor(moveflagPromotion, moveflagPromoteKnight))
        moveStack[1 + table.getn(moveStack)] = GenerateMove2(start, square, bit.bor(moveflagPromotion, moveflagPromoteBishop))
        moveStack[1 + table.getn(moveStack)] = GenerateMove2(start, square, moveflagPromotion)
    else
        moveStack[1 + table.getn(moveStack)] = GenerateMove2(start, square, 0)
    end
end

local function GeneratePawnMoves(state, moveStack, from)
    local piece = state.board[1 + from]
    local color = bit.band(piece, colorWhite)
    local inc = iif((color == colorWhite), -16, 16)
    local to = from + inc

    if (state.board[1 + to] == 0) then
        MovePawnTo(moveStack, from, to, pieceEmpty)

        if (((bit.band(from, 0xF0) == 0x30) and color ~= colorWhite) or
                ((bit.band(from, 0xF0) == 0x80) and color == colorWhite)) then
            to = to + inc
            if (state.board[1 + to] == 0) then
                moveStack[1 + table.getn(moveStack)] = GenerateMove(from, to)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- FORWARD DECLARATIONS FOR MUTUALLY RECURSIVE FUNCTIONS
--------------------------------------------------------------------------------

local MakeMove, UnmakeMove

--------------------------------------------------------------------------------
-- MOVE GENERATION
--------------------------------------------------------------------------------

local function GenerateCaptureMoves(state, moveStack)
    local inc = iif((state.toMove == 8), -16, 16)
    local enemy = iif(state.toMove == 8, 0x10, 0x8)

    -- Pawn captures
    local pieceIdx = bit.lshift(bit.bor(state.toMove, 1), 4)
    local from = state.pieceList[1 + pieceIdx]
    pieceIdx = pieceIdx + 1
    while (from ~= 0) do
        local to = from + inc - 1
        if (bit.band(state.board[1 + to], enemy) > 0) then
            MovePawnTo(moveStack, from, to)
        end

        to = from + inc + 1
        if (bit.band(state.board[1 + to], enemy) > 0) then
            MovePawnTo(moveStack, from, to)
        end

        from = state.pieceList[1 + pieceIdx]
        pieceIdx = pieceIdx + 1
    end

    if (state.enPassentSquare ~= -1) then
        inc = iif((state.toMove == colorWhite), -16, 16)
        local pawn = bit.bor(state.toMove, piecePawn)

        from = state.enPassentSquare - (inc + 1)
        if (bit.band(state.board[1 + from], 0xF) == pawn) then
            moveStack[1 + table.getn(moveStack)] = GenerateMove2(from, state.enPassentSquare, moveflagEPC)
        end

        from = state.enPassentSquare - (inc - 1)
        if (bit.band(state.board[1 + from], 0xF) == pawn) then
            moveStack[1 + table.getn(moveStack)] = GenerateMove2(from, state.enPassentSquare, moveflagEPC)
        end
    end

    -- Knight captures
    pieceIdx = bit.lshift(bit.bor(state.toMove, 2), 4)
    from = state.pieceList[1 + pieceIdx]
    pieceIdx = pieceIdx + 1
    while (from ~= 0) do
        MSt(state, moveStack, 1, from, 31, enemy)
        MSt(state, moveStack, 1, from, 33, enemy)
        MSt(state, moveStack, 1, from, 14, enemy)
        MSt(state, moveStack, 1, from, -14, enemy)
        MSt(state, moveStack, 1, from, -31, enemy)
        MSt(state, moveStack, 1, from, -33, enemy)
        MSt(state, moveStack, 1, from, 18, enemy)
        MSt(state, moveStack, 1, from, -18, enemy)
        from = state.pieceList[1 + pieceIdx]
        pieceIdx = pieceIdx + 1
    end

    -- Bishop captures
    pieceIdx = bit.lshift(bit.bor(state.toMove, 3), 4)
    from = state.pieceList[1 + pieceIdx]
    pieceIdx = pieceIdx + 1
    while (from ~= 0) do
        MSt(state, moveStack, 3, from, -15, enemy)
        MSt(state, moveStack, 3, from, -17, enemy)
        MSt(state, moveStack, 3, from, 15, enemy)
        MSt(state, moveStack, 3, from, 17, enemy)
        from = state.pieceList[1 + pieceIdx]
        pieceIdx = pieceIdx + 1
    end

    -- Rook captures
    pieceIdx = bit.lshift(bit.bor(state.toMove, 4), 4)
    from = state.pieceList[1 + pieceIdx]
    pieceIdx = pieceIdx + 1
    while (from ~= 0) do
        MSt(state, moveStack, 3, from, -1, enemy)
        MSt(state, moveStack, 3, from, 1, enemy)
        MSt(state, moveStack, 3, from, -16, enemy)
        MSt(state, moveStack, 3, from, 16, enemy)
        from = state.pieceList[1 + pieceIdx]
        pieceIdx = pieceIdx + 1
    end

    -- Queen captures
    pieceIdx = bit.lshift(bit.bor(state.toMove, 5), 4)
    from = state.pieceList[1 + pieceIdx]
    pieceIdx = pieceIdx + 1
    while (from ~= 0) do
        MSt(state, moveStack, 3, from, -15, enemy)
        MSt(state, moveStack, 3, from, -17, enemy)
        MSt(state, moveStack, 3, from, 15, enemy)
        MSt(state, moveStack, 3, from, 17, enemy)
        MSt(state, moveStack, 3, from, -1, enemy)
        MSt(state, moveStack, 3, from, 1, enemy)
        MSt(state, moveStack, 3, from, -16, enemy)
        MSt(state, moveStack, 3, from, 16, enemy)
        from = state.pieceList[1 + pieceIdx]
        pieceIdx = pieceIdx + 1
    end

    -- King captures
    pieceIdx = bit.lshift(bit.bor(state.toMove, 6), 4)
    from = state.pieceList[1 + pieceIdx]
    MSt(state, moveStack, 1, from, -15, enemy)
    MSt(state, moveStack, 1, from, -17, enemy)
    MSt(state, moveStack, 1, from, 15, enemy)
    MSt(state, moveStack, 1, from, 17, enemy)
    MSt(state, moveStack, 1, from, -1, enemy)
    MSt(state, moveStack, 1, from, 1, enemy)
    MSt(state, moveStack, 1, from, -16, enemy)
    MSt(state, moveStack, 1, from, 16, enemy)
end

local function GenerateAllMoves(state, moveStack)
    -- Pawn quiet moves
    local pieceIdx = bit.lshift(bit.bor(state.toMove, 1), 4)
    local from = state.pieceList[1 + pieceIdx]
    pieceIdx = pieceIdx + 1
    while (from ~= 0) do
        GeneratePawnMoves(state, moveStack, from)
        from = state.pieceList[1 + pieceIdx]
        pieceIdx = pieceIdx + 1
    end

    -- Knight quiet moves
    pieceIdx = bit.lshift(bit.bor(state.toMove, 2), 4)
    from = state.pieceList[1 + pieceIdx]
    pieceIdx = pieceIdx + 1
    while (from ~= 0) do
        MSt(state, moveStack, 1, from, 31, nil)
        MSt(state, moveStack, 1, from, 33, nil)
        MSt(state, moveStack, 1, from, 14, nil)
        MSt(state, moveStack, 1, from, -14, nil)
        MSt(state, moveStack, 1, from, -31, nil)
        MSt(state, moveStack, 1, from, -33, nil)
        MSt(state, moveStack, 1, from, 18, nil)
        MSt(state, moveStack, 1, from, -18, nil)
        from = state.pieceList[1 + pieceIdx]
        pieceIdx = pieceIdx + 1
    end

    -- Bishop quiet moves
    pieceIdx = bit.lshift(bit.bor(state.toMove, 3), 4)
    from = state.pieceList[1 + pieceIdx]
    pieceIdx = pieceIdx + 1
    while (from ~= 0) do
        MSt(state, moveStack, 2, from, -15, nil)
        MSt(state, moveStack, 2, from, -17, nil)
        MSt(state, moveStack, 2, from, 15, nil)
        MSt(state, moveStack, 2, from, 17, nil)
        from = state.pieceList[1 + pieceIdx]
        pieceIdx = pieceIdx + 1
    end

    -- Rook quiet moves
    pieceIdx = bit.lshift(bit.bor(state.toMove, 4), 4)
    from = state.pieceList[1 + pieceIdx]
    pieceIdx = pieceIdx + 1
    while (from ~= 0) do
        MSt(state, moveStack, 2, from, -1, nil)
        MSt(state, moveStack, 2, from, 1, nil)
        MSt(state, moveStack, 2, from, 16, nil)
        MSt(state, moveStack, 2, from, -16, nil)
        from = state.pieceList[1 + pieceIdx]
        pieceIdx = pieceIdx + 1
    end

    -- Queen quiet moves
    pieceIdx = bit.lshift(bit.bor(state.toMove, 5), 4)
    from = state.pieceList[1 + pieceIdx]
    pieceIdx = pieceIdx + 1
    while (from ~= 0) do
        MSt(state, moveStack, 2, from, -15, nil)
        MSt(state, moveStack, 2, from, -17, nil)
        MSt(state, moveStack, 2, from, 15, nil)
        MSt(state, moveStack, 2, from, 17, nil)
        MSt(state, moveStack, 2, from, -1, nil)
        MSt(state, moveStack, 2, from, 1, nil)
        MSt(state, moveStack, 2, from, 16, nil)
        MSt(state, moveStack, 2, from, -16, nil)
        from = state.pieceList[1 + pieceIdx]
        pieceIdx = pieceIdx + 1
    end

    -- King quiet moves
    pieceIdx = bit.lshift(bit.bor(state.toMove, 6), 4)
    from = state.pieceList[1 + pieceIdx]
    MSt(state, moveStack, 1, from, -15, nil)
    MSt(state, moveStack, 1, from, -17, nil)
    MSt(state, moveStack, 1, from, 15, nil)
    MSt(state, moveStack, 1, from, 17, nil)
    MSt(state, moveStack, 1, from, -1, nil)
    MSt(state, moveStack, 1, from, 1, nil)
    MSt(state, moveStack, 1, from, -16, nil)
    MSt(state, moveStack, 1, from, 16, nil)

    if (not state.inCheck) then
        local castleRights = state.castleRights
        if (state.toMove == 0) then
            castleRights = bit.rshift(castleRights, 2)
        end
        if (bit.band(castleRights, 1) > 0) then
            if (state.board[1 + (from + 1)] == pieceEmpty and state.board[1 + (from + 2)] == pieceEmpty) then
                moveStack[1 + table.getn(moveStack)] = GenerateMove2(from, from + 0x02, moveflagCastleKing)
            end
        end
        if (bit.band(castleRights, 2) > 0) then
            if (state.board[1 + (from - 1)] == pieceEmpty and state.board[1 + (from - 2)] == pieceEmpty and
                    state.board[1 + (from - 3)] == pieceEmpty) then
                moveStack[1 + table.getn(moveStack)] = GenerateMove2(from, from - 0x02, moveflagCastleQueen)
            end
        end
    end
end

local function GenerateValidMoves(state)
    local moveList = {}
    local allMoves = {}
    GenerateCaptureMoves(state, allMoves)
    GenerateAllMoves(state, allMoves)

    for i = table.getn(allMoves) - 1, 0, -1 do
        if (MakeMove(state, allMoves[1 + i])) then
            moveList[1 + table.getn(moveList)] = allMoves[1 + i]
            UnmakeMove(state, allMoves[1 + i])
        end
    end

    return moveList
end

--------------------------------------------------------------------------------
-- MAKE/UNMAKE MOVE
--------------------------------------------------------------------------------

MakeMove = function(state, move)
    local me = bit.rshift(state.toMove, 3)
    local otherColor = 8 - state.toMove

    local flags = bit.band(move, 0xFF0000)
    local to = bit.band(bit.rshift(move, 8), 0xFF)
    local from = bit.band(move, 0xFF)
    local diff = to - from
    local captured = state.board[1 + to]
    local piece = state.board[1 + from]
    local epcEnd = to

    state.finCnt = state.finCnt + 1

    if (bit.band(flags, moveflagEPC) > 0) then
        epcEnd = iif(me > 0, (to + 0x10), (to - 0x10))
        captured = state.board[1 + epcEnd]
        state.board[1 + epcEnd] = pieceEmpty
    end

    state.moveUndoStack[1 + state.moveCount] = UndoHistory(
        state.enPassentSquare,
        state.castleRights,
        state.inCheck,
        state.baseEval,
        state.hashKeyLow,
        state.hashKeyHigh,
        state.move50,
        captured
    )
    state.moveCount = state.moveCount + 1

    state.enPassentSquare = -1

    if (flags > 0) then
        if (bit.band(flags, moveflagCastleKing) > 0) then
            if (IsSquareAttackable(state, from + 1, otherColor) or IsSquareAttackable(state, from + 2, otherColor)) then
                state.moveCount = state.moveCount - 1
                return false
            end

            local rook = state.board[1 + (to + 1)]

            state.hashKeyLow = bit.bxor(state.hashKeyLow, g_zobristLow[1 + (to + 1)][1 + bit.band(rook, 0xF)])
            state.hashKeyHigh = bit.bxor(state.hashKeyHigh, g_zobristHigh[1 + (to + 1)][1 + bit.band(rook, 0xF)])
            state.hashKeyLow = bit.bxor(state.hashKeyLow, g_zobristLow[1 + (to - 1)][1 + bit.band(rook, 0xF)])
            state.hashKeyHigh = bit.bxor(state.hashKeyHigh, g_zobristHigh[1 + (to - 1)][1 + bit.band(rook, 0xF)])

            state.board[1 + (to - 1)] = rook
            state.board[1 + (to + 1)] = pieceEmpty

            state.baseEval = state.baseEval - pieceSquareAdj[1 + bit.band(rook, 0x7)][1 + iif(me == 0, flipTable[1 + (to + 1)], (to + 1))]
            state.baseEval = state.baseEval + pieceSquareAdj[1 + bit.band(rook, 0x7)][1 + iif(me == 0, flipTable[1 + (to - 1)], (to - 1))]

            local rookIndex = state.pieceIndex[1 + (to + 1)]
            state.pieceIndex[1 + (to - 1)] = rookIndex
            state.pieceList[1 + bit.bor(bit.lshift(bit.band(rook, 0xF), 4), rookIndex)] = to - 1
        elseif (bit.band(flags, moveflagCastleQueen) > 0) then
            if (IsSquareAttackable(state, from - 1, otherColor) or IsSquareAttackable(state, from - 2, otherColor)) then
                state.moveCount = state.moveCount - 1
                return false
            end

            local rook = state.board[1 + (to - 2)]

            state.hashKeyLow = bit.bxor(state.hashKeyLow, g_zobristLow[1 + (to - 2)][1 + bit.band(rook, 0xF)])
            state.hashKeyHigh = bit.bxor(state.hashKeyHigh, g_zobristHigh[1 + (to - 2)][1 + bit.band(rook, 0xF)])
            state.hashKeyLow = bit.bxor(state.hashKeyLow, g_zobristLow[1 + (to + 1)][1 + bit.band(rook, 0xF)])
            state.hashKeyHigh = bit.bxor(state.hashKeyHigh, g_zobristHigh[1 + (to + 1)][1 + bit.band(rook, 0xF)])

            state.board[1 + (to + 1)] = rook
            state.board[1 + (to - 2)] = pieceEmpty

            state.baseEval = state.baseEval - pieceSquareAdj[1 + bit.band(rook, 0x7)][1 + iif(me == 0, flipTable[1 + (to - 2)], (to - 2))]
            state.baseEval = state.baseEval + pieceSquareAdj[1 + bit.band(rook, 0x7)][1 + iif(me == 0, flipTable[1 + (to + 1)], (to + 1))]

            local rookIndex = state.pieceIndex[1 + (to - 2)]
            state.pieceIndex[1 + (to + 1)] = rookIndex
            state.pieceList[1 + bit.bor(bit.lshift(bit.band(rook, 0xF), 4), rookIndex)] = to + 1
        end
    end

    if (captured > 0) then
        local capturedType = bit.band(captured, 0xF)

        state.pieceCount[1 + capturedType] = state.pieceCount[1 + capturedType] - 1
        local lastPieceSquare = state.pieceList[1 + bit.bor(bit.lshift(capturedType, 4), state.pieceCount[1 + capturedType])]

        state.pieceIndex[1 + lastPieceSquare] = state.pieceIndex[1 + epcEnd]
        state.pieceList[1 + bit.bor(bit.lshift(capturedType, 4), state.pieceIndex[1 + lastPieceSquare])] = lastPieceSquare
        state.pieceList[1 + bit.bor(bit.lshift(capturedType, 4), state.pieceCount[1 + capturedType])] = 0

        state.baseEval = state.baseEval + materialTable[1 + bit.band(captured, 0x7)]
        state.baseEval = state.baseEval + pieceSquareAdj[1 + bit.band(captured, 0x7)][1 + iif(me > 0, flipTable[1 + epcEnd], epcEnd)]

        state.hashKeyLow = bit.bxor(state.hashKeyLow, g_zobristLow[1 + epcEnd][1 + capturedType])
        state.hashKeyHigh = bit.bxor(state.hashKeyHigh, g_zobristHigh[1 + epcEnd][1 + capturedType])
        state.move50 = 0
    else
        if (bit.band(piece, 0x7) == piecePawn) then
            local absDiff = diff
            if (absDiff < 0) then absDiff = -absDiff end
            if (absDiff > 16) then
                state.enPassentSquare = iif(me > 0, (to + 0x10), (to - 0x10))
            end
            state.move50 = 0
        end
    end

    state.hashKeyLow = bit.bxor(state.hashKeyLow, g_zobristLow[1 + from][1 + bit.band(piece, 0xF)])
    state.hashKeyHigh = bit.bxor(state.hashKeyHigh, g_zobristHigh[1 + from][1 + bit.band(piece, 0xF)])
    state.hashKeyLow = bit.bxor(state.hashKeyLow, g_zobristLow[1 + to][1 + bit.band(piece, 0xF)])
    state.hashKeyHigh = bit.bxor(state.hashKeyHigh, g_zobristHigh[1 + to][1 + bit.band(piece, 0xF)])
    state.hashKeyLow = bit.bxor(state.hashKeyLow, g_zobristBlackLow)
    state.hashKeyHigh = bit.bxor(state.hashKeyHigh, g_zobristBlackHigh)

    state.castleRights = bit.band(state.castleRights, bit.band(g_castleRightsMask[1 + from], g_castleRightsMask[1 + to]))

    state.baseEval = state.baseEval - pieceSquareAdj[1 + bit.band(piece, 0x7)][1 + iif(me == 0, flipTable[1 + from], from)]

    state.pieceIndex[1 + to] = state.pieceIndex[1 + from]
    state.pieceList[1 + bit.bor(bit.lshift(bit.band(piece, 0xF), 4), state.pieceIndex[1 + to])] = to

    if (bit.band(flags, moveflagPromotion) > 0) then
        local newPiece = bit.band(piece, bit.bnot(0x7))
        if (bit.band(flags, moveflagPromoteKnight) > 0) then
            newPiece = bit.bor(newPiece, pieceKnight)
        elseif (bit.band(flags, moveflagPromoteQueen) > 0) then
            newPiece = bit.bor(newPiece, pieceQueen)
        elseif (bit.band(flags, moveflagPromoteBishop) > 0) then
            newPiece = bit.bor(newPiece, pieceBishop)
        else
            newPiece = bit.bor(newPiece, pieceRook)
        end

        state.hashKeyLow = bit.bxor(state.hashKeyLow, g_zobristLow[1 + to][1 + bit.band(piece, 0xF)])
        state.hashKeyHigh = bit.bxor(state.hashKeyHigh, g_zobristHigh[1 + to][1 + bit.band(piece, 0xF)])
        state.board[1 + to] = newPiece
        state.hashKeyLow = bit.bxor(state.hashKeyLow, g_zobristLow[1 + to][1 + bit.band(newPiece, 0xF)])
        state.hashKeyHigh = bit.bxor(state.hashKeyHigh, g_zobristHigh[1 + to][1 + bit.band(newPiece, 0xF)])

        state.baseEval = state.baseEval + pieceSquareAdj[1 + bit.band(newPiece, 0x7)][1 + iif(me == 0, flipTable[1 + to], to)]
        state.baseEval = state.baseEval - materialTable[1 + piecePawn]
        state.baseEval = state.baseEval + materialTable[1 + bit.band(newPiece, 0x7)]

        local pawnType = bit.band(piece, 0xF)
        local promoteType = bit.band(newPiece, 0xF)

        state.pieceCount[1 + pawnType] = state.pieceCount[1 + pawnType] - 1

        local lastPawnSquare = state.pieceList[1 + bit.bor(bit.lshift(pawnType, 4), state.pieceCount[1 + pawnType])]
        state.pieceIndex[1 + lastPawnSquare] = state.pieceIndex[1 + to]
        state.pieceList[1 + bit.bor(bit.lshift(pawnType, 4), state.pieceIndex[1 + lastPawnSquare])] = lastPawnSquare
        state.pieceList[1 + bit.bor(bit.lshift(pawnType, 4), state.pieceCount[1 + pawnType])] = 0
        state.pieceIndex[1 + to] = state.pieceCount[1 + promoteType]
        state.pieceList[1 + bit.bor(bit.lshift(promoteType, 4), state.pieceIndex[1 + to])] = to
        state.pieceCount[1 + promoteType] = state.pieceCount[1 + promoteType] + 1
    else
        state.board[1 + to] = state.board[1 + from]
        state.baseEval = state.baseEval + pieceSquareAdj[1 + bit.band(piece, 0x7)][1 + iif(me == 0, flipTable[1 + to], to)]
    end
    state.board[1 + from] = pieceEmpty

    state.toMove = otherColor
    state.baseEval = -state.baseEval

    if ((bit.band(piece, 0x7) > 0) == ((pieceKing > 0) or state.inCheck)) then
        if (IsSquareAttackable(state, state.pieceList[1 + bit.lshift(bit.bor(pieceKing, (8 - state.toMove)), 4)], otherColor)) then
            UnmakeMove(state, move)
            return false
        end
    else
        local kingPos = state.pieceList[1 + bit.lshift(bit.bor(pieceKing, (8 - state.toMove)), 4)]

        if (ExposesCheck(state, from, kingPos)) then
            UnmakeMove(state, move)
            return false
        end

        if (epcEnd ~= to) then
            if (ExposesCheck(state, epcEnd, kingPos)) then
                UnmakeMove(state, move)
                return false
            end
        end
    end

    state.inCheck = false

    if (flags <= moveflagEPC) then
        local theirKingPos = state.pieceList[1 + bit.lshift(bit.bor(pieceKing, state.toMove), 4)]

        state.inCheck = IsSquareAttackableFrom(state, theirKingPos, to)

        if (not state.inCheck) then
            state.inCheck = ExposesCheck(state, from, theirKingPos)

            if (not state.inCheck) then
                if (epcEnd ~= to) then
                    state.inCheck = ExposesCheck(state, epcEnd, theirKingPos)
                end
            end
        end
    else
        state.inCheck = IsSquareAttackable(state, state.pieceList[1 + bit.lshift(bit.bor(pieceKing, state.toMove), 4)], 8 - state.toMove)
    end

    state.repMoveStack[1 + (state.moveCount - 1)] = state.hashKeyLow
    state.move50 = state.move50 + 1

    return true
end

UnmakeMove = function(state, move)
    state.toMove = 8 - state.toMove
    state.baseEval = -state.baseEval

    state.moveCount = state.moveCount - 1

    local otherColor = 8 - state.toMove
    local me = bit.rshift(state.toMove, 3)

    local flags = bit.band(move, 0xFF0000)
    local captured = state.moveUndoStack[1 + state.moveCount].captured
    local to = bit.band(bit.rshift(move, 8), 0xFF)
    local from = bit.band(move, 0xFF)

    local piece = state.board[1 + to]

    state.enPassentSquare = state.moveUndoStack[1 + state.moveCount].ep
    state.castleRights = state.moveUndoStack[1 + state.moveCount].castleRights
    state.inCheck = state.moveUndoStack[1 + state.moveCount].inCheck
    state.baseEval = state.moveUndoStack[1 + state.moveCount].baseEval
    state.hashKeyLow = state.moveUndoStack[1 + state.moveCount].hashKeyLow
    state.hashKeyHigh = state.moveUndoStack[1 + state.moveCount].hashKeyHigh
    state.move50 = state.moveUndoStack[1 + state.moveCount].move50

    if (flags > 0) then
        if (bit.band(flags, moveflagCastleKing) > 0) then
            local rook = state.board[1 + (to - 1)]
            state.board[1 + (to + 1)] = rook
            state.board[1 + (to - 1)] = pieceEmpty

            local rookIndex = state.pieceIndex[1 + (to - 1)]
            state.pieceIndex[1 + (to + 1)] = rookIndex
            state.pieceList[1 + bit.bor(bit.lshift(bit.band(rook, 0xF), 4), rookIndex)] = to + 1
        elseif (bit.band(flags, moveflagCastleQueen) > 0) then
            local rook = state.board[1 + (to + 1)]
            state.board[1 + (to - 2)] = rook
            state.board[1 + (to + 1)] = pieceEmpty

            local rookIndex = state.pieceIndex[1 + (to + 1)]
            state.pieceIndex[1 + (to - 2)] = rookIndex
            state.pieceList[1 + bit.bor(bit.lshift(bit.band(rook, 0xF), 4), rookIndex)] = to - 2
        end
    end

    if (bit.band(flags, moveflagPromotion) > 0) then
        piece = bit.bor(bit.band(state.board[1 + to], bit.bnot(0x7)), piecePawn)
        state.board[1 + from] = piece

        local pawnType = bit.band(state.board[1 + from], 0xF)
        local promoteType = bit.band(state.board[1 + to], 0xF)

        state.pieceCount[1 + promoteType] = state.pieceCount[1 + promoteType] - 1

        local lastPromoteSquare = state.pieceList[1 + bit.bor(bit.lshift(promoteType, 4), state.pieceCount[1 + promoteType])]
        state.pieceIndex[1 + lastPromoteSquare] = state.pieceIndex[1 + to]
        state.pieceList[1 + bit.bor(bit.lshift(promoteType, 4), state.pieceIndex[1 + lastPromoteSquare])] = lastPromoteSquare
        state.pieceList[1 + bit.bor(bit.lshift(promoteType, 4), state.pieceCount[1 + promoteType])] = 0
        state.pieceIndex[1 + to] = state.pieceCount[1 + pawnType]
        state.pieceList[1 + bit.bor(bit.lshift(pawnType, 4), state.pieceIndex[1 + to])] = to
        state.pieceCount[1 + pawnType] = state.pieceCount[1 + pawnType] + 1
    else
        state.board[1 + from] = state.board[1 + to]
    end

    local epcEnd = to
    if (bit.band(flags, moveflagEPC) > 0) then
        if (state.toMove == colorWhite) then
            epcEnd = to + 0x10
        else
            epcEnd = to - 0x10
        end
        state.board[1 + to] = pieceEmpty
    end

    state.board[1 + epcEnd] = captured

    state.pieceIndex[1 + from] = state.pieceIndex[1 + to]
    state.pieceList[1 + bit.bor(bit.lshift(bit.band(piece, 0xF), 4), state.pieceIndex[1 + from])] = from

    if (captured > 0) then
        local captureType = bit.band(captured, 0xF)
        state.pieceIndex[1 + epcEnd] = state.pieceCount[1 + captureType]
        state.pieceList[1 + bit.bor(bit.lshift(captureType, 4), state.pieceCount[1 + captureType])] = epcEnd
        state.pieceCount[1 + captureType] = state.pieceCount[1 + captureType] + 1
    end
end

--------------------------------------------------------------------------------
-- EVALUATION
--------------------------------------------------------------------------------

local function AdjMob(state, from, dto, mob, enemy)
    local to = from + dto
    local mb = mob
    while (state.board[1 + to] == 0) do
        to = to + dto
        mb = mb + 1
    end
    if (bit.band(state.board[1 + to], enemy) > 0) then
        mb = mb + 1
    end
    return mb
end

local function Mobility(state, color)
    local result = 0
    local enemy = iif(color == 8, 0x10, 0x8)
    local mobUnit = iif(color == 8, g_mobUnit[1], g_mobUnit[1 + 1])

    -- Knight mobility
    local mob = -3
    local pieceIdx = bit.lshift(bit.bor(color, 2), 4)
    local from = state.pieceList[1 + pieceIdx]
    pieceIdx = pieceIdx + 1

    while (from ~= 0) do
        mob = mob + mobUnit[1 + state.board[1 + (from + 31)]]
        mob = mob + mobUnit[1 + state.board[1 + (from + 33)]]
        mob = mob + mobUnit[1 + state.board[1 + (from + 14)]]
        mob = mob + mobUnit[1 + state.board[1 + (from - 14)]]
        mob = mob + mobUnit[1 + state.board[1 + (from - 31)]]
        mob = mob + mobUnit[1 + state.board[1 + (from - 33)]]
        mob = mob + mobUnit[1 + state.board[1 + (from + 18)]]
        mob = mob + mobUnit[1 + state.board[1 + (from - 18)]]
        from = state.pieceList[1 + pieceIdx]
        pieceIdx = pieceIdx + 1
    end
    result = result + (65 * mob)

    -- Bishop mobility
    mob = -4
    pieceIdx = bit.lshift(bit.bor(color, 3), 4)
    from = state.pieceList[1 + pieceIdx]
    pieceIdx = pieceIdx + 1
    while (from ~= 0) do
        mob = AdjMob(state, from, -15, mob, enemy)
        mob = AdjMob(state, from, -17, mob, enemy)
        mob = AdjMob(state, from, 15, mob, enemy)
        mob = AdjMob(state, from, 17, mob, enemy)
        from = state.pieceList[1 + pieceIdx]
        pieceIdx = pieceIdx + 1
    end
    result = result + (50 * mob)

    -- Rook mobility
    mob = -4
    pieceIdx = bit.lshift(bit.bor(color, 4), 4)
    from = state.pieceList[1 + pieceIdx]
    pieceIdx = pieceIdx + 1
    while (from ~= 0) do
        mob = AdjMob(state, from, -1, mob, enemy)
        mob = AdjMob(state, from, 1, mob, enemy)
        mob = AdjMob(state, from, -16, mob, enemy)
        mob = AdjMob(state, from, 16, mob, enemy)
        from = state.pieceList[1 + pieceIdx]
        pieceIdx = pieceIdx + 1
    end
    result = result + (25 * mob)

    -- Queen mobility
    mob = -2
    pieceIdx = bit.lshift(bit.bor(color, 5), 4)
    from = state.pieceList[1 + pieceIdx]
    pieceIdx = pieceIdx + 1
    while (from ~= 0) do
        mob = AdjMob(state, from, -15, mob, enemy)
        mob = AdjMob(state, from, -17, mob, enemy)
        mob = AdjMob(state, from, 15, mob, enemy)
        mob = AdjMob(state, from, 17, mob, enemy)
        mob = AdjMob(state, from, -1, mob, enemy)
        mob = AdjMob(state, from, 1, mob, enemy)
        mob = AdjMob(state, from, -16, mob, enemy)
        mob = AdjMob(state, from, 16, mob, enemy)
        from = state.pieceList[1 + pieceIdx]
        pieceIdx = pieceIdx + 1
    end
    result = result + (22 * mob)

    return result
end

local function Evaluate(state)
    local curEval = state.baseEval
    local mobility = Mobility(state, 8) - Mobility(state, 0)

    local evalAdjust = 0
    if (state.pieceList[1 + bit.lshift(pieceQueen, 4)] == 0) then
        evalAdjust = evalAdjust - pieceSquareAdj[1 + pieceKing][1 + state.pieceList[1 + bit.lshift(bit.bor(colorWhite, pieceKing), 4)]]
    end
    if (state.pieceList[1 + bit.lshift(bit.bor(colorWhite, pieceQueen), 4)] == 0) then
        evalAdjust = evalAdjust + pieceSquareAdj[1 + pieceKing][1 + flipTable[1 + state.pieceList[1 + bit.lshift(pieceKing, 4)]]]
    end

    if (state.pieceCount[1 + pieceBishop] >= 2) then
        evalAdjust = evalAdjust - 500
    end
    if (state.pieceCount[1 + bit.bor(pieceBishop, colorWhite)] >= 2) then
        evalAdjust = evalAdjust + 500
    end

    if (state.toMove == 0) then
        curEval = curEval - mobility
        curEval = curEval - evalAdjust
    else
        curEval = curEval + mobility
        curEval = curEval + evalAdjust
    end

    return curEval
end

local function ScoreMove(state, move)
    local moveTo = bit.band(bit.rshift(move, 8), 0xFF)
    local captured = bit.band(state.board[1 + moveTo], 0x7)
    local piece = state.board[1 + bit.band(move, 0xFF)]
    local score = 0
    local pieceType = bit.band(piece, 0x7)
    if (captured ~= 0) then
        score = bit.lshift(captured, 5) - pieceType
    else
        score = state.historyTable[1 + bit.band(piece, 0xF)][1 + moveTo]
    end
    return score
end

--------------------------------------------------------------------------------
-- SEE (Static Exchange Evaluation)
--------------------------------------------------------------------------------

local function SeeAddKnightAttacks(state, target, us, attacks)
    local pieceIdx = bit.lshift(bit.bor(us, pieceKnight), 4)
    local attackerSq = state.pieceList[1 + pieceIdx]
    pieceIdx = pieceIdx + 1

    while (attackerSq ~= 0) do
        if (IsSquareOnPieceLine(state, target, attackerSq)) then
            attacks[1 + table.getn(attacks)] = attackerSq
        end
        attackerSq = state.pieceList[1 + pieceIdx]
        pieceIdx = pieceIdx + 1
    end
end

local function SeeAddSliderAttacks(state, target, us, attacks, pieceType)
    local pieceIdx = bit.lshift(bit.bor(us, pieceType), 4)
    local attackerSq = state.pieceList[1 + pieceIdx]

    local hit = false
    pieceIdx = pieceIdx + 1

    while (attackerSq ~= 0) do
        if (IsSquareAttackableFrom(state, target, attackerSq)) then
            attacks[1 + table.getn(attacks)] = attackerSq
            hit = true
        end
        attackerSq = state.pieceList[1 + pieceIdx]
        pieceIdx = pieceIdx + 1
    end

    return hit
end

local function SeeAddXrayAttack(state, target, square, us, usAttacks, themAttacks)
    local index = square - target + 128
    local delta = -g_vectorDelta[1 + index].delta
    if (delta == 0) then
        return
    end
    local sq = square + delta
    while (state.board[1 + sq] == 0) do
        sq = sq + delta
    end

    if ((bit.band(state.board[1 + sq], 0x18) > 0) and IsSquareOnPieceLine(state, target, sq)) then
        if (bit.band(state.board[1 + sq], 8) == us) then
            usAttacks[1 + table.getn(usAttacks)] = sq
        else
            themAttacks[1 + table.getn(themAttacks)] = sq
        end
    end
end

local function See(state, move)
    local from = bit.band(move, 0xFF)
    local to = bit.band(bit.rshift(move, 8), 0xFF)

    local fromPiece = state.board[1 + from]
    local us = iif(bit.band(fromPiece, colorWhite) > 0, colorWhite, 0)
    local them = 8 - us
    local themAttacks = {}
    local usAttacks = {}

    local fromValue = g_seeValues[1 + bit.band(fromPiece, 0xF)]
    local toValue = g_seeValues[1 + bit.band(state.board[1 + to], 0xF)]
    local seeValue = toValue - fromValue
    local inc = iif(bit.band(fromPiece, colorWhite) > 0, -16, 16)
    local captureDeficit = fromValue - toValue

    if (fromValue <= toValue) then
        return true
    end

    if (bit.rshift(move, 16) > 0) then
        return true
    end

    if ((bit.band(state.board[1 + (to + inc + 1)], 0xF) == bit.bor(piecePawn, them)) or
            (bit.band(state.board[1 + (to + inc - 1)], 0xF) == bit.bor(piecePawn, them))) then
        return false
    end

    SeeAddKnightAttacks(state, to, them, themAttacks)
    if ((table.getn(themAttacks) ~= 0) and (captureDeficit > g_seeValues[1 + pieceKnight])) then
        return false
    end

    state.board[1 + from] = 0
    for pt = pieceBishop, pieceQueen, 1 do
        if (SeeAddSliderAttacks(state, to, them, themAttacks, pt)) then
            if (captureDeficit > g_seeValues[1 + pt]) then
                state.board[1 + from] = fromPiece
                return false
            end
        end
    end

    if ((bit.band(state.board[1 + (to - inc + 1)], 0xF) == bit.bor(piecePawn, us)) or
            (bit.band(state.board[1 + (to - inc - 1)], 0xF) == bit.bor(piecePawn, us))) then
        state.board[1 + from] = fromPiece
        return true
    end

    SeeAddSliderAttacks(state, to, them, themAttacks, pieceKing)

    SeeAddKnightAttacks(state, to, us, usAttacks)
    for pt = pieceBishop, pieceKing, 1 do
        SeeAddSliderAttacks(state, to, us, usAttacks, pt)
    end

    state.board[1 + from] = fromPiece

    while (true) do
        local capturingPieceValue = 1000
        local capturingPieceIndex = -1

        for i = 0, table.getn(themAttacks) - 1, 1 do
            if (themAttacks[1 + i] ~= 0) then
                local pieceValue = g_seeValues[1 + bit.band(state.board[1 + themAttacks[1 + i]], 0x7)]
                if (pieceValue < capturingPieceValue) then
                    capturingPieceValue = pieceValue
                    capturingPieceIndex = i
                end
            end
        end

        if (capturingPieceIndex == -1) then
            return true
        end

        seeValue = seeValue + capturingPieceValue
        if (seeValue < 0) then
            return false
        end

        local capturingPieceSquare = themAttacks[1 + capturingPieceIndex]
        themAttacks[1 + capturingPieceIndex] = 0

        SeeAddXrayAttack(state, to, capturingPieceSquare, us, usAttacks, themAttacks)

        capturingPieceValue = 1000
        capturingPieceIndex = -1

        for i = 0, table.getn(usAttacks) - 1, 1 do
            if (usAttacks[1 + i] ~= 0) then
                local pieceValue = g_seeValues[1 + bit.band(state.board[1 + usAttacks[1 + i]], 0x7)]
                if (pieceValue < capturingPieceValue) then
                    capturingPieceValue = pieceValue
                    capturingPieceIndex = i
                end
            end
        end

        if (capturingPieceIndex == -1) then
            return false
        end

        seeValue = seeValue - capturingPieceValue
        if (seeValue >= 0) then
            return true
        end

        capturingPieceSquare = usAttacks[1 + capturingPieceIndex]
        usAttacks[1 + capturingPieceIndex] = 0

        SeeAddXrayAttack(state, to, capturingPieceSquare, us, usAttacks, themAttacks)
    end
end

--------------------------------------------------------------------------------
-- MOVE PICKER
--------------------------------------------------------------------------------

local function MovePicker(state, hashMove, depth, killer1, killer2)
    return {
        state = state,
        hashMove = hashMove,
        depth = depth,
        killer1 = killer1,
        killer2 = killer2,
        moves = {},
        losingCaptures = nil,
        moveCount = 0,
        atMove = -1,
        moveScores = nil,
        stage = 0
    }
end

local function nextMove(mp)
    local state = mp.state

    mp.atMove = mp.atMove + 1

    if (mp.atMove == mp.moveCount) then
        mp.stage = mp.stage + 1
        if (mp.stage == 1) then
            if ((mp.hashMove ~= nil) and IsHashMoveValid(state, mp.hashMove)) then
                mp.moves[1] = mp.hashMove
                mp.moveCount = 1
            end
            if (mp.moveCount ~= 1) then
                mp.hashMove = nil
                mp.stage = mp.stage + 1
            end
        end

        if (mp.stage == 2) then
            GenerateCaptureMoves(state, mp.moves)

            mp.moveCount = table.getn(mp.moves)
            mp.moveScores = {}
            for i = mp.atMove, mp.moveCount - 1, 1 do
                local captured = bit.band(state.board[1 + bit.band(bit.rshift(mp.moves[1 + i], 8), 0xFF)], 0x7)
                local pieceType = bit.band(state.board[1 + bit.band(mp.moves[1 + i], 0xFF)], 0x7)
                mp.moveScores[1 + i] = bit.lshift(captured, 5) - pieceType
            end
            if (mp.atMove == mp.moveCount) then
                mp.stage = mp.stage + 1
            end
        end

        if (mp.stage == 3) then
            if (IsHashMoveValid(state, mp.killer1) and (mp.killer1 ~= mp.hashMove)) then
                mp.moves[1 + table.getn(mp.moves)] = mp.killer1
                mp.moveCount = table.getn(mp.moves)
            else
                mp.killer1 = 0
                mp.stage = mp.stage + 1
            end
        end

        if (mp.stage == 4) then
            if (IsHashMoveValid(state, mp.killer2) and (mp.killer2 ~= mp.hashMove)) then
                mp.moves[1 + table.getn(mp.moves)] = mp.killer2
                mp.moveCount = table.getn(mp.moves)
            else
                mp.killer2 = 0
                mp.stage = mp.stage + 1
            end
        end

        if (mp.stage == 5) then
            GenerateAllMoves(state, mp.moves)
            mp.moveCount = table.getn(mp.moves)
            for i = mp.atMove, mp.moveCount - 1, 1 do
                mp.moveScores[1 + i] = ScoreMove(state, mp.moves[1 + i])
            end
            if (mp.atMove == mp.moveCount) then
                mp.stage = mp.stage + 1
            end
        end

        if (mp.stage == 6) then
            if (mp.losingCaptures ~= nil) then
                for i = 0, table.getn(mp.losingCaptures) - 1, 1 do
                    mp.moves[1 + table.getn(mp.moves)] = mp.losingCaptures[1 + i]
                end
                for i = mp.atMove, mp.moveCount - 1, 1 do
                    mp.moveScores[1 + i] = ScoreMove(state, mp.moves[1 + i])
                end
                mp.moveCount = table.getn(mp.moves)
            end
            if (mp.atMove == mp.moveCount) then
                mp.stage = mp.stage + 1
            end
        end

        if (mp.stage == 7) then
            return 0
        end
    end

    local bestMove = mp.atMove
    for j = mp.atMove + 1, mp.moveCount - 1, 1 do
        if (mp.moveScores[1 + j] == nil) then
            break
        end
        if (mp.moveScores[1 + j] > mp.moveScores[1 + bestMove]) then
            bestMove = j
        end
    end

    if (bestMove ~= mp.atMove) then
        local tmpMove = mp.moves[1 + mp.atMove]
        mp.moves[1 + mp.atMove] = mp.moves[1 + bestMove]
        mp.moves[1 + bestMove] = tmpMove

        local tmpScore = mp.moveScores[1 + mp.atMove]
        mp.moveScores[1 + mp.atMove] = mp.moveScores[1 + bestMove]
        mp.moveScores[1 + bestMove] = tmpScore
    end

    local candidateMove = mp.moves[1 + mp.atMove]
    if ((mp.stage > 1 and candidateMove == mp.hashMove) or
            (mp.stage > 3 and candidateMove == mp.killer1) or
            (mp.stage > 4 and candidateMove == mp.killer2)) then
        return nextMove(mp)
    end

    if (mp.stage == 2 and (not See(state, candidateMove))) then
        if (mp.losingCaptures == nil) then
            mp.losingCaptures = {}
        end
        mp.losingCaptures[1 + table.getn(mp.losingCaptures)] = candidateMove
        return nextMove(mp)
    end
    return mp.moves[1 + mp.atMove]
end

--------------------------------------------------------------------------------
-- QUIESCENCE SEARCH
--------------------------------------------------------------------------------

local function QSearch(state, alpha, beta, ply)
    state.qNodeCount = state.qNodeCount + 1

    local realEval = iif(state.inCheck, (minEval + 1), Evaluate(state))

    if (realEval >= beta) then
        return realEval
    end

    if (realEval > alpha) then
        alpha = realEval
    end

    local moves = {}
    local moveScores = {}
    local wasInCheck = state.inCheck

    if (wasInCheck) then
        GenerateCaptureMoves(state, moves)
        GenerateAllMoves(state, moves)

        for i = 0, table.getn(moves) - 1, 1 do
            moveScores[1 + i] = ScoreMove(state, moves[1 + i])
        end
    else
        GenerateCaptureMoves(state, moves)

        for i = 0, table.getn(moves) - 1, 1 do
            local captured = bit.band(state.board[1 + bit.band(bit.rshift(moves[1 + i], 8), 0xFF)], 0x7)
            local pieceType = bit.band(state.board[1 + bit.band(moves[1 + i], 0xFF)], 0x7)
            moveScores[1 + i] = bit.lshift(captured, 5) - pieceType
        end
    end

    for i = 0, table.getn(moves) - 1, 1 do
        local bestMoveIdx = i
        for j = table.getn(moves) - 1, i + 1, -1 do
            if (moveScores[1 + j] > moveScores[1 + bestMoveIdx]) then
                bestMoveIdx = j
            end
        end

        local tmpMove = moves[1 + i]
        moves[1 + i] = moves[1 + bestMoveIdx]
        moves[1 + bestMoveIdx] = tmpMove

        local tmpScore = moveScores[1 + i]
        moveScores[1 + i] = moveScores[1 + bestMoveIdx]
        moveScores[1 + bestMoveIdx] = tmpScore

        if ((wasInCheck or See(state, moves[1 + i])) and MakeMove(state, moves[1 + i])) then
            local value = -QSearch(state, -beta, -alpha, ply - 1)

            UnmakeMove(state, moves[1 + i])

            if (value > realEval) then
                if (value >= beta) then
                    return value
                end
                if (value > alpha) then
                    alpha = value
                end
                realEval = value
            end
        end
    end

    if ((ply == 0) and (not wasInCheck)) then
        moves = {}
        GenerateAllMoves(state, moves)

        for i = 0, table.getn(moves) - 1, 1 do
            moveScores[1 + i] = ScoreMove(state, moves[1 + i])
        end

        for i = 0, table.getn(moves) - 1, 1 do
            local bestMoveIdx = i
            for j = table.getn(moves) - 1, i + 1, -1 do
                if (moveScores[1 + j] > moveScores[1 + bestMoveIdx]) then
                    bestMoveIdx = j
                end
            end

            local tmpMove = moves[1 + i]
            moves[1 + i] = moves[1 + bestMoveIdx]
            moves[1 + bestMoveIdx] = tmpMove

            local tmpScore = moveScores[1 + i]
            moveScores[1 + i] = moveScores[1 + bestMoveIdx]
            moveScores[1 + bestMoveIdx] = tmpScore

            local brk = false

            if (not MakeMove(state, moves[1 + i])) then
                brk = true
            else
                local checking = state.inCheck
                UnmakeMove(state, moves[1 + i])

                if (not checking) then
                    brk = true
                elseif (not See(state, moves[1 + i])) then
                    brk = true
                end
            end

            if (not brk) then
                MakeMove(state, moves[1 + i])

                local value = -QSearch(state, -beta, -alpha, ply - 1)

                UnmakeMove(state, moves[1 + i])

                if (value > realEval) then
                    if (value >= beta) then
                        return value
                    end

                    if (value > alpha) then
                        alpha = value
                    end

                    realEval = value
                end
            end
        end
    end

    return realEval
end

--------------------------------------------------------------------------------
-- ALPHA-BETA SEARCH
--------------------------------------------------------------------------------

local function AllCutNode(state, ply, depth, beta, allowNull)
    if (ply <= 0) then
        return QSearch(state, beta - 1, beta, 0)
    end

    if (GetTime() - state.startTime > state.timeout) then
        state.searchValid = false
        return beta - 1
    end

    if (state.finCnt > state.maxfinCnt) then
        state.searchValid = false
        return beta - 1
    end

    state.nodeCount = state.nodeCount + 1

    if (IsRepDraw(state)) then
        return 0
    end

    if (minEval + depth >= beta) then
        return beta
    end

    if ((maxEval - (depth + 1)) < beta) then
        return (beta - 1)
    end

    local hashMove = nil
    local hashNode = state.hashTable[1 + bit.band(state.hashKeyLow, g_hashMask)]

    if ((hashNode ~= nil) and (hashNode.lock == state.hashKeyHigh)) then
        hashMove = hashNode.bestMove

        if (hashNode.hashDepth >= ply) then
            local hashValue = hashNode.value

            if (hashValue >= maxMateBuffer) then
                hashValue = hashValue - depth
            elseif (hashValue <= minMateBuffer) then
                hashValue = hashValue + depth
            end

            if (hashNode.flags == hashflagExact) then
                return hashValue
            end
            if (hashNode.flags == hashflagAlpha and hashValue < beta) then
                return hashValue
            end
            if (hashNode.flags == hashflagBeta and hashValue >= beta) then
                return hashValue
            end
        end
    end

    local razorMargin = 2500 + 200 * ply

    if ((not state.inCheck) and allowNull and (beta > minMateBuffer) and (beta < maxMateBuffer)) then
        if (hashMove == nil and ply < 4) then
            if (state.baseEval < beta - razorMargin) then
                local razorBeta = beta - razorMargin
                local v = QSearch(state, razorBeta - 1, razorBeta, 0)
                if (v < razorBeta) then
                    return v
                end
            end
        end

        if (ply > 1 and state.baseEval >= beta - iif(ply >= 4, 2500, 0) and
                (state.pieceCount[1 + bit.bor(pieceBishop, state.toMove)] ~= 0 or
                    state.pieceCount[1 + bit.bor(pieceKnight, state.toMove)] ~= 0 or
                    state.pieceCount[1 + bit.bor(pieceRook, state.toMove)] ~= 0 or
                    state.pieceCount[1 + bit.bor(pieceQueen, state.toMove)] ~= 0)) then
            local r = 3 + iif(ply >= 5, 1, ply / 4)
            if (state.baseEval - beta > 1500) then
                r = r + 1
            end

            state.toMove = 8 - state.toMove
            state.baseEval = -state.baseEval
            state.hashKeyLow = bit.bxor(state.hashKeyLow, g_zobristBlackLow)
            state.hashKeyHigh = bit.bxor(state.hashKeyHigh, g_zobristBlackHigh)

            local value = -AllCutNode(state, ply - r, depth + 1, -(beta - 1), false)

            state.hashKeyLow = bit.bxor(state.hashKeyLow, g_zobristBlackLow)
            state.hashKeyHigh = bit.bxor(state.hashKeyHigh, g_zobristBlackHigh)
            state.toMove = 8 - state.toMove
            state.baseEval = -state.baseEval

            if (value >= beta) then
                return beta
            end
        end
    end

    local moveMade = false
    local realEval = minEval
    local inCheck = state.inCheck

    local mp = MovePicker(state, hashMove, depth, state.killers[1 + depth][1], state.killers[1 + depth][1 + 1])

    while (true) do
        local currentMove = nextMove(mp)
        if (currentMove == 0) then
            break
        end

        local plyToSearch = ply - 1

        if (MakeMove(state, currentMove)) then
            local doFullSearch = true
            local value

            if (state.inCheck) then
                plyToSearch = plyToSearch + 1
            else
                if (mp.stage == 5 and mp.atMove > 5 and ply >= 3) then
                    local reduced = plyToSearch - iif(mp.atMove > 14, 2, 1)
                    value = -AllCutNode(state, reduced, depth + 1, -(beta - 1), true)
                    doFullSearch = (value >= beta)
                end
            end

            if (doFullSearch) then
                value = -AllCutNode(state, plyToSearch, depth + 1, -(beta - 1), true)
            end

            moveMade = true

            UnmakeMove(state, currentMove)

            if (not state.searchValid) then
                return beta - 1
            end

            if (value > realEval) then
                if (value >= beta) then
                    local histTo = bit.band(bit.rshift(currentMove, 8), 0xFF)
                    if (state.board[1 + histTo] == 0) then
                        local histPiece = bit.band(state.board[1 + bit.band(currentMove, 0xFF)], 0xF)
                        local h = state.historyTable[1 + histPiece][1 + histTo]
                        h = h + (ply * ply)
                        if (h > 32767) then
                            h = bit.rshift(h, 1)
                        end
                        state.historyTable[1 + histPiece][1 + histTo] = h

                        if (state.killers[1 + depth][1] ~= currentMove) then
                            state.killers[1 + depth][1 + 1] = state.killers[1 + depth][1]
                            state.killers[1 + depth][1] = currentMove
                        end
                    end

                    StoreHash(state, value, hashflagBeta, ply, currentMove, depth)
                    return value
                end

                realEval = value
                hashMove = currentMove
            end
        end
    end

    if (not moveMade) then
        if (state.inCheck) then
            return (minEval + depth)
        else
            return 0
        end
    end

    StoreHash(state, realEval, hashflagAlpha, ply, hashMove, depth)

    return realEval
end

local function AlphaBeta(state, ply, depth, alpha, beta)
    if (ply <= 0) then
        return QSearch(state, alpha, beta, 0)
    end

    state.nodeCount = state.nodeCount + 1

    if (depth > 0 and IsRepDraw(state)) then
        return 0
    end

    local oldAlpha = alpha
    alpha = iif((alpha < minEval + depth), alpha, minEval + depth)
    beta = iif((beta > maxEval - (depth + 1)), beta, maxEval - (depth + 1))
    if (alpha >= beta) then
        return alpha
    end

    local hashMove = nil
    local hashNode = state.hashTable[1 + bit.band(state.hashKeyLow, g_hashMask)]
    if (hashNode ~= nil and hashNode.lock == state.hashKeyHigh) then
        hashMove = hashNode.bestMove
    end

    local inCheck = state.inCheck
    local moveMade = false
    local realEval = minEval
    local hashFlag = hashflagAlpha

    local mp = MovePicker(state, hashMove, depth, state.killers[1 + depth][1], state.killers[1 + depth][1 + 1])

    while (true) do
        local currentMove = nextMove(mp)

        if (currentMove == 0) then
            break
        end

        local plyToSearch = ply - 1

        if (MakeMove(state, currentMove)) then
            if (state.inCheck) then
                plyToSearch = plyToSearch + 1
            end

            local value
            if (moveMade) then
                value = -AllCutNode(state, plyToSearch, depth + 1, -alpha, true)

                if (value > alpha) then
                    value = -AlphaBeta(state, plyToSearch, depth + 1, -beta, -alpha)
                end
            else
                value = -AlphaBeta(state, plyToSearch, depth + 1, -beta, -alpha)
            end

            moveMade = true

            UnmakeMove(state, currentMove)

            if (not state.searchValid) then
                return alpha
            end

            if (value > realEval) then
                if (value >= beta) then
                    local histTo = bit.band(bit.rshift(currentMove, 8), 0xFF)
                    if (state.board[1 + histTo] == 0) then
                        local histPiece = bit.band(state.board[1 + bit.band(currentMove, 0xFF)], 0xF)
                        local h = state.historyTable[1 + histPiece][1 + histTo]
                        h = h + (ply * ply)
                        if (h > 32767) then
                            h = bit.rshift(h, 1)
                        end
                        state.historyTable[1 + histPiece][1 + histTo] = h

                        if (state.killers[1 + depth][1] ~= currentMove) then
                            state.killers[1 + depth][1 + 1] = state.killers[1 + depth][1]
                            state.killers[1 + depth][1] = currentMove
                        end
                    end

                    StoreHash(state, value, hashflagBeta, ply, currentMove, depth)
                    return value
                end

                if (value > oldAlpha) then
                    hashFlag = hashflagExact
                    alpha = value
                end

                realEval = value
                hashMove = currentMove
            end
        end
    end

    if (not moveMade) then
        if (inCheck) then
            return (minEval + depth)
        else
            return 0
        end
    end

    StoreHash(state, realEval, hashFlag, ply, hashMove, depth)

    return realEval
end

--------------------------------------------------------------------------------
-- SEARCH ASYNC
--------------------------------------------------------------------------------

local function SearchAsync(state, maxPly, yieldFn, onComplete)
    local alpha = minEval
    local beta = maxEval

    local bestMove = 0
    local value = 0
    local i = 1

    state.globalPly = state.globalPly + 1
    state.nodeCount = 0
    state.qNodeCount = 0
    state.searchValid = true
    state.foundmove = 0

    state.finCnt = 0
    state.startTime = GetTime()

    local function searchNextPly()
        if not (i <= maxPly and state.searchValid) then
            if (bestMove ~= nil and bestMove ~= 0) then
                MakeMove(state, bestMove)
                state.foundmove = bestMove
            end
            if onComplete then
                onComplete(bestMove)
            end
            return
        end

        local tmp = AlphaBeta(state, i, 0, alpha, beta)
        if (not state.searchValid) then
            if (bestMove ~= nil and bestMove ~= 0) then
                MakeMove(state, bestMove)
                state.foundmove = bestMove
            end
            if onComplete then
                onComplete(bestMove)
            end
            return
        end

        value = tmp

        if (value > alpha and value < beta) then
            alpha = value - 500
            beta = value + 500

            if (alpha < minEval) then
                alpha = minEval
            end
            if (beta > maxEval) then
                beta = maxEval
            end
        else
            if (alpha ~= minEval) then
                alpha = minEval
                beta = maxEval
                i = i - 1
            end
        end

        if (state.hashTable[1 + bit.band(state.hashKeyLow, g_hashMask)] ~= nil) then
            bestMove = state.hashTable[1 + bit.band(state.hashKeyLow, g_hashMask)].bestMove
        end

        i = i + 1
        yieldFn(searchNextPly)
    end

    yieldFn(searchNextPly)
end

--------------------------------------------------------------------------------
-- FEN INITIALIZATION
--------------------------------------------------------------------------------

local function InitializeFromFen(state, fen)
    local chunks = {}
    local fen2 = fen

    while (string.len(fen2) > 0) do
        local s1 = string.find(fen2, " ")
        if (s1 == nil) then
            table.insert(chunks, fen2)
            fen2 = ""
        else
            table.insert(chunks, string.sub(fen2, 1, s1 - 1))
            fen2 = string.sub(fen2, s1 + 1)
        end
    end

    for i = 0, 255, 1 do
        state.board[1 + i] = 0x80
    end

    local row = 0
    local col = 0
    local pieces = chunks[1]

    for i = 0, string.len(pieces) - 1, 1 do
        local c = string.sub(pieces, i + 1, i + 1)

        if (c == "/") then
            row = row + 1
            col = 0
        elseif (c >= "0" and c <= "9") then
            for j = 0, tonumber(c) - 1, 1 do
                state.board[1 + ((row + 2) * 0x10) + (col + 4)] = 0
                col = col + 1
            end
        else
            local isBlack = (c >= "a" and c <= "z")
            local piece = iif(isBlack, colorBlack, colorWhite)

            if (not isBlack) then
                c = string.sub(string.lower(pieces), i + 1, i + 1)
            end
            if (c == "p") then piece = bit.bor(piece, piecePawn) end
            if (c == "b") then piece = bit.bor(piece, pieceBishop) end
            if (c == "n") then piece = bit.bor(piece, pieceKnight) end
            if (c == "r") then piece = bit.bor(piece, pieceRook) end
            if (c == "q") then piece = bit.bor(piece, pieceQueen) end
            if (c == "k") then piece = bit.bor(piece, pieceKing) end

            state.board[1 + ((row + 2) * 0x10) + (col + 4)] = piece
            col = col + 1
        end
    end

    InitializePieceList(state)

    state.toMove = iif(chunks[1 + 1] == "w", colorWhite, 0)

    state.castleRights = 0
    if (string.find(chunks[1 + 2], "K") ~= nil) then
        state.castleRights = bit.bor(state.castleRights, 1)
    end
    if (string.find(chunks[1 + 2], "Q") ~= nil) then
        state.castleRights = bit.bor(state.castleRights, 2)
    end
    if (string.find(chunks[1 + 2], "k") ~= nil) then
        state.castleRights = bit.bor(state.castleRights, 4)
    end
    if (string.find(chunks[1 + 2], "q") ~= nil) then
        state.castleRights = bit.bor(state.castleRights, 8)
    end
    state.enPassentSquare = -1
    if (string.find(chunks[1 + 3], "-") == nil) then
        state.enPassentSquare = deFormatSquare(chunks[1 + 3])
    end

    local hashResult = SetHash(state)
    state.hashKeyLow = hashResult.hashKeyLow
    state.hashKeyHigh = hashResult.hashKeyHigh

    state.baseEval = 0

    for i = 0, 255, 1 do
        if (bit.band(state.board[1 + i], colorWhite) > 0) then
            state.baseEval = state.baseEval + pieceSquareAdj[1 + bit.band(state.board[1 + i], 0x7)][1 + i]
            state.baseEval = state.baseEval + materialTable[1 + bit.band(state.board[1 + i], 0x7)]
        elseif (bit.band(state.board[1 + i], colorBlack) > 0) then
            state.baseEval = state.baseEval - pieceSquareAdj[1 + bit.band(state.board[1 + i], 0x7)][1 + flipTable[1 + i]]
            state.baseEval = state.baseEval - materialTable[1 + bit.band(state.board[1 + i], 0x7)]
        end
    end
    if (state.toMove == 0) then
        state.baseEval = -state.baseEval
    end

    state.move50 = 0

    state.inCheck = IsSquareAttackable(state, state.pieceList[1 + bit.lshift(bit.bor(state.toMove, pieceKing), 4)], 8 - state.toMove)
end

--------------------------------------------------------------------------------
-- MOVE FORMATTING
--------------------------------------------------------------------------------

local function FormatMoveStr(move)
    local result = FormatSquare(bit.band(move, 0xFF)) .. FormatSquare(bit.band(bit.rshift(move, 8), 0xFF))
    if (bit.band(move, moveflagPromotion) > 0) then
        if (bit.band(move, moveflagPromoteBishop) > 0) then
            result = result .. "b"
        elseif (bit.band(move, moveflagPromoteKnight) > 0) then
            result = result .. "n"
        elseif (bit.band(move, moveflagPromoteQueen) > 0) then
            result = result .. "q"
        else
            result = result .. "r"
        end
    end
    return result
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

DeltaChess.GarboChess = {
    -- Create a new game state object
    createState = createState,

    -- Initialize a state from FEN string
    InitializeFromFen = InitializeFromFen,

    -- Run async search on a state
    SearchAsync = SearchAsync,

    -- Format a move to string (e.g., "e2e4")
    FormatMove = FormatMoveStr,

    -- Module initialization (called automatically by createState)
    InitializeModule = InitializeModule,
}
