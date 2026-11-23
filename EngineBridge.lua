-- EngineBridge.lua - WoW-specific bridge for EngineFramework
-- Provides per-frame engine session scheduling and coordinate conversion helpers

local DeltaChess = LibStub("DeltaChess-1.0")
local DeltaChessFramework = LibStub("DeltachessFramework-1.0")

local STATUS = {
    ACTIVE = DeltaChessFramework.Constants.STATUS_ACTIVE,
    PAUSED = DeltaChessFramework.Constants.STATUS_PAUSED,
    ENDED = DeltaChessFramework.Constants.STATUS_ENDED,
}

--------------------------------------------------------------------------------
-- Per-frame engine session scheduler
-- Independent of the board window so thinking continues while it is closed.
--------------------------------------------------------------------------------

local TARGET_FPS = 40
local TARGET_FPS_DOUBLE = TARGET_FPS * 2
local TARGET_FPS_HALF = TARGET_FPS / 2

local sessions = {}
local roundRobin = 1
local driver = CreateFrame("Frame", "DeltaChessEngineDriver", UIParent)
driver:Show()

local function GetComputeBudget()
    local fps = GetFramerate() or TARGET_FPS
    if fps >= TARGET_FPS_DOUBLE then
        return 64
    end
    if fps >= TARGET_FPS then
        return 32
    end
    if fps >= TARGET_FPS_HALF then
        return 16
    end
    return 8
end

local function StopDriver()
    driver:SetScript("OnUpdate", nil)
    roundRobin = 1
end

local function OnUpdate()
    if InCombatLockdown() then
        return
    end

    local n = #sessions
    if n == 0 then
        StopDriver()
        return
    end

    local budget = GetComputeBudget()
    local slice = math.floor(budget / n)
    -- print("compute frame " .. slice)

    if slice >= 1 then
        for i = n, 1, -1 do
            if not sessions[i]:Compute(slice) then
                table.remove(sessions, i)
            end
        end
    else
        if roundRobin > n then
            roundRobin = 1
        end
        if not sessions[roundRobin]:Compute(budget) then
            table.remove(sessions, roundRobin)
        else
            roundRobin = roundRobin + 1
        end
        if roundRobin > #sessions then
            roundRobin = 1
        end
    end

    if #sessions == 0 then
        StopDriver()
    end
end

--- Queue a framework engine session. Call session:Compute from OnUpdate until it finishes.
-- @param session table from EngineRunner:Start()
function DeltaChess.AddEngineSession(session)
    if not session then
        return
    end
    sessions[#sessions + 1] = session
    if not driver:GetScript("OnUpdate") then
        driver:SetScript("OnUpdate", OnUpdate)
    end
end


--------------------------------------------------------------------------------
-- Coordinate conversion helpers
--------------------------------------------------------------------------------

local FILES = "abcdefgh"
local FILE_TO_COL = {a=1, b=2, c=3, d=4, e=5, f=6, g=7, h=8}

--- Convert row/col coordinates to UCI notation.
-- @param fromRow number (1-8, where 1 is white's back rank)
-- @param fromCol number (1-8, where 1 is a-file)
-- @param toRow number (1-8)
-- @param toCol number (1-8)
-- @param promotion string|nil optional promotion piece (q, r, b, n)
-- @return string UCI move (e.g., "e2e4", "e7e8q")
function DeltaChess.CoordsToUci(fromRow, fromCol, toRow, toCol, promotion)
    local uci = FILES:sub(fromCol, fromCol) .. fromRow ..
                FILES:sub(toCol, toCol) .. toRow
    if promotion then
        uci = uci .. promotion:lower()
    end
    return uci
end

--- Convert UCI notation to row/col coordinates.
-- @param uci string UCI move (e.g., "e2e4", "e7e8q")
-- @return table with fromRow, fromCol, toRow, toCol, promotion (or nil if invalid)
function DeltaChess.UciToCoords(uci)
    if not uci or #uci < 4 then
        return nil
    end
    
    local fromFile = uci:sub(1, 1)
    local fromRank = uci:sub(2, 2)
    local toFile = uci:sub(3, 3)
    local toRank = uci:sub(4, 4)
    
    local fromCol = FILE_TO_COL[fromFile]
    local toCol = FILE_TO_COL[toFile]
    local fromRow = tonumber(fromRank)
    local toRow = tonumber(toRank)
    
    if not fromCol or not toCol or not fromRow or not toRow then
        return nil
    end
    
    return {
        fromRow = fromRow,
        fromCol = fromCol,
        toRow = toRow,
        toCol = toCol,
        promotion = #uci > 4 and uci:sub(5, 5) or nil
    }
end

--- Convert UCI square to row/col.
-- @param sq string UCI square (e.g., "e4")
-- @return number, number row and col (or nil, nil if invalid)
function DeltaChess.UciSquareToCoords(sq)
    if not sq or #sq < 2 then
        return nil, nil
    end
    local file = sq:sub(1, 1)
    local rank = sq:sub(2, 2)
    local col = FILE_TO_COL[file]
    local row = tonumber(rank)
    return row, col
end

--- Convert row/col to UCI square.
-- @param row number (1-8)
-- @param col number (1-8)
-- @return string UCI square (e.g., "e4")
function DeltaChess.CoordsToUciSquare(row, col)
    if row < 1 or row > 8 or col < 1 or col > 8 then
        return nil
    end
    return FILES:sub(col, col) .. row
end

--------------------------------------------------------------------------------
-- Piece conversion helpers
--------------------------------------------------------------------------------

--- Convert single-char piece to type string (lowercase).
-- @param char string single character (P, N, B, R, Q, K, or lowercase)
-- @return string piece type (p, n, b, r, q, k)
function DeltaChess.PieceCharToType(char)
    return char and char:lower()
end

--- Convert piece type string to single char.
-- @param pieceType string (p, n, b, r, q, k)
-- @param isWhite boolean true for uppercase, false for lowercase
-- @return string single character
function DeltaChess.PieceTypeToChar(pieceType, isWhite)
    if not pieceType then return nil end
    return isWhite and pieceType:upper() or pieceType
end

--- Check if a piece char is white.
-- @param char string single piece character
-- @return boolean true if white (uppercase)
function DeltaChess.IsPieceWhite(char)
    return char and char:upper() == char and char:lower() ~= char
end

--------------------------------------------------------------------------------
-- Board position helpers for UI
--------------------------------------------------------------------------------

--- Get piece at a square from framework board position.
-- @param board Board object from framework
-- @param square string UCI square (e.g., "e2")
-- @return string|nil Piece character (K, Q, R, B, N, P or lowercase) or nil
function DeltaChess.GetPieceAt(board, square)
    local row, col = DeltaChessFramework.Board.FromSquare(square)
    if not row then return nil end
    
    local pos = board:GetPos()
    if not pos or not pos.board then
        return nil
    end
    
    -- Convert row/col to square index (1-64)
    -- Framework uses: sq = (rank-1)*8 + file, where rank 1 = row 1, file 1 = col 1
    local sq = (row - 1) * 8 + col
    local piece = pos.board[sq]
    
    if not piece or piece == "." then
        return nil
    end
    
    return piece  -- Return piece character directly
end

--- Get all legal moves for a piece at a square.
-- @param board Board object from framework
-- @param fromSquare string UCI square (e.g., "e2")
-- @return table array of {square, promotion} targets
function DeltaChess.GetLegalMovesAt(board, fromSquare)
    local fromRow, fromCol = DeltaChessFramework.Board.FromSquare(fromSquare)
    if not fromRow then return {} end
    
    local fromSq = (fromRow - 1) * 8 + fromCol
    local legalMoves = board:LegalMoves()
    local moves = {}
    
    for _, mv in ipairs(legalMoves) do
        if mv.from == fromSq then
            local toRow = math.floor((mv.to - 1) / 8) + 1
            local toCol = (mv.to - 1) % 8 + 1
            table.insert(moves, {
                square = DeltaChessFramework.Board.ToSquare(toRow, toCol),
                promotion = mv.prom
            })
        end
    end
    
    return moves
end

--- Get premove targets for a piece: squares it could move to once the opponent
-- has made their next move (see MoveGen.SemiLegalMoves).
-- @param board Board object from framework
-- @param fromSquare string UCI square, e.g. "e2"
-- @param color COLOR.WHITE or COLOR.BLACK (the premoving side)
-- @return array of {square = "e4", promotion = "q"|nil}
function DeltaChess.GetPremoveMovesAt(board, fromSquare, color)
    local fromRow, fromCol = DeltaChessFramework.Board.FromSquare(fromSquare)
    if not fromRow then return {} end

    local fromSq = (fromRow - 1) * 8 + fromCol
    local moves, seen = {}, {}
    for _, mv in ipairs(board:SemiLegalMoves(color == DeltaChessFramework.Constants.COLOR.WHITE and "w" or "b")) do
        if mv.from == fromSq and not seen[mv.to] then
            seen[mv.to] = true
            local toRow = math.floor((mv.to - 1) / 8) + 1
            local toCol = (mv.to - 1) % 8 + 1
            table.insert(moves, {
                square = DeltaChessFramework.Board.ToSquare(toRow, toCol),
                promotion = mv.prom
            })
        end
    end
    return moves
end

--------------------------------------------------------------------------------
-- Premove execution (queue lives on Board; timers are per gameId)
--------------------------------------------------------------------------------

local premoveTimers = {}

local function myPremoveColor(board, gameId)
    if board:OneOpponentIsEngine() then
        return board:GetPlayerColor()
    end
    if DeltaChess.GetMyColor then
        return DeltaChess:GetMyColor(gameId)
    end
    return nil
end

local function refreshPremoveUi(gameId)
    local frame = DeltaChess.UI and DeltaChess.UI.activeFrame
    if not frame or frame.gameId ~= gameId then return end
    if DeltaChess.UI.RefreshPremoveMarkers then
        DeltaChess.UI:RefreshPremoveMarkers(frame)
    elseif DeltaChess.UI.UpdateBoard then
        DeltaChess.UI:UpdateBoard(frame)
    end
end

local function afterLocalMove(gameId, board, wasPlayerMove)
    local lastMove = board:GetLastMove()
    local wasCapture = lastMove and lastMove.IsCapture and lastMove:IsCapture()
        or (lastMove and lastMove.captured ~= nil)
    if DeltaChess.Sound and DeltaChess.Sound.PlayMoveSound then
        DeltaChess.Sound:PlayMoveSound(board, wasPlayerMove, wasCapture, board)
    end
    local frame = DeltaChess.UI and DeltaChess.UI.activeFrame
    if frame and frame.gameId == gameId and DeltaChess.UI.UpdateBoardAnimated then
        DeltaChess.UI:UpdateBoardAnimated(frame, true)
    end
    if DeltaChess.Minimap and DeltaChess.Minimap.UpdateYourTurnHighlight then
        DeltaChess.Minimap:UpdateYourTurnHighlight()
    end
    if board:IsEnded() then
        local endFrame = (frame and frame.gameId == gameId) and frame or nil
        if DeltaChess.UI and DeltaChess.UI.ShowGameEnd then
            DeltaChess.UI:ShowGameEnd(gameId, endFrame)
        end
        return true
    end
    return false
end

-- Apply a queued premove from board state. Promotion defaults to queen.
-- Returns true if a legal move was played.
local function applyQueuedPremove(gameId, board, pm)
    local match
    for _, move in ipairs(DeltaChess.GetLegalMovesAt(board, pm.from)) do
        if move.square == pm.to then
            match = move
            break
        end
    end
    if not match then return false end

    local uci = pm.from .. pm.to .. (match.promotion and "q" or "")
    if board:OneOpponentIsEngine() then
        DeltaChess.MakeMove(board, uci)
        if afterLocalMove(gameId, board, true) then
            return true
        end
        if DeltaChess.AI and DeltaChess.AI.MakeMove then
            DeltaChess.AI:MakeMove(gameId, 500)
        end
        return true
    end
    if DeltaChess.SendMoveWithConfirmation then
        return DeltaChess:SendMoveWithConfirmation(gameId, uci) ~= false
    end
    return false
end

local function tryPlayPremove(gameId)
    premoveTimers[gameId] = nil
    local board = DeltaChess.GetBoard(gameId)
    local pm = board and board:GetPremove()
    if not board or not pm then
        if DeltaChess.AI and DeltaChess.AI.PauseIfBoardClosed then
            DeltaChess.AI:PauseIfBoardClosed(gameId)
        end
        return
    end
    if board:IsEnded() or board:IsPaused() then
        board:ClearPremove()
        refreshPremoveUi(gameId)
        return
    end
    if board:GetCurrentTurn() ~= myPremoveColor(board, gameId) then
        return
    end
    local locked = false
    if not board:OneOpponentIsEngine() and type(DeltaChess.IsBoardLocked) == "function" then
        locked = DeltaChess:IsBoardLocked(gameId)
    end
    if (DeltaChess._actionBlocked or 0) > 0 or locked then
        premoveTimers[gameId] = true
        C_Timer.After(0.1, function() tryPlayPremove(gameId) end)
        return
    end

    board:ClearPremove()
    refreshPremoveUi(gameId)
    applyQueuedPremove(gameId, board, pm)
    if DeltaChess.AI and DeltaChess.AI.PauseIfBoardClosed then
        DeltaChess.AI:PauseIfBoardClosed(gameId)
    end
end

--- True while a short timer is waiting to play this game's queued premove.
function DeltaChess.IsPremovePending(gameId)
    return premoveTimers[gameId] == true
end

--- Play this game's board-stored premove once it is that side's turn.
-- Independent of which game the board window is showing.
function DeltaChess.SchedulePremove(gameId)
    local board = DeltaChess.GetBoard(gameId)
    if not board or not board:GetPremove() then return end
    if board:IsEnded() or board:IsPaused() then return end
    if board:GetCurrentTurn() ~= myPremoveColor(board, gameId) then return end
    if premoveTimers[gameId] then return end
    premoveTimers[gameId] = true
    C_Timer.After(0.1, function() tryPlayPremove(gameId) end)
end

--- After a reload, play any queued premoves that are already the player's turn.
-- Premoves are serialized with the board; only the in-memory timer is lost.
function DeltaChess.ResumePendingPremoves()
    if not DeltaChess.db or not DeltaChess.db.games then return end
    for gameId, board in pairs(DeltaChess.db.games) do
        if board and board.IsActive and board:IsActive() and board:GetPremove()
            and board:GetCurrentTurn() == myPremoveColor(board, gameId) then
            DeltaChess.SchedulePremove(gameId)
        end
    end
end

--- Check if a move is legal.
-- @param board Board object from framework
-- @param fromRow number
-- @param fromCol number
-- @param toRow number
-- @param toCol number
-- @param promotion string|nil
-- @return boolean
function DeltaChess.IsLegalMove(board, fromRow, fromCol, toRow, toCol, promotion)
    local uci = DeltaChess.CoordsToUci(fromRow, fromCol, toRow, toCol, promotion)
    return DeltaChessFramework.MoveGen.IsLegalMove(board:GetFen(), uci)
end

--------------------------------------------------------------------------------
-- Board state helpers (compatibility layer)
--------------------------------------------------------------------------------

--- Get current turn as "white" or "black" (delegates to board).
-- @param board Board object from framework
-- @return string "white" or "black"
function DeltaChess.GetCurrentTurn(board)
    return board:GetCurrentTurn()
end

-- (GetGameStatus wrapper removed — use board:IsActive(), board:IsPaused(),
--  board:IsEnded(), and board:GetEndReason() directly instead.)

--- Make a move using UCI string.
-- @param board Board object from framework
-- @param uci string UCI move (e.g., "e2e4", "e7e8q")
-- @return Board or nil, error message
function DeltaChess.MakeMove(board, uci)
    local result, err = board:MakeMoveUci(uci, { timestamp = DeltaChessFramework.Util.TimeNow() })
    -- Local player moves (vs computer / premoves) do not go through NotifyItIsYourTurn.
    if result and DeltaChess.RefreshGameListIfShown then
        DeltaChess:RefreshGameListIfShown()
    end
    return result, err
end

--------------------------------------------------------------------------------
-- Game/Board accessor helpers
-- Board IS the game - all metadata stored in board.gameMeta
--------------------------------------------------------------------------------

--- Get board (game) by gameId from the database.
-- @param gameId string the game identifier
-- @return Board|nil the board object, or nil if not found
function DeltaChess.GetBoard(gameId)
    if not DeltaChess.db or not DeltaChess.db.games then
        return nil
    end
    return DeltaChess.db.games[gameId]
end

--- Store a board in the games database.
-- @param gameId string the game identifier
-- @param board Board the board object to store
function DeltaChess.StoreBoard(gameId, board)
    if not DeltaChess.db then
        DeltaChess.db = {}
    end
    if not DeltaChess.db.games then
        DeltaChess.db.games = {}
    end
    DeltaChess.db.games[gameId] = board
end

--- Remove a board from the games database.
-- @param gameId string the game identifier
function DeltaChess.RemoveBoard(gameId)
    if DeltaChess.db and DeltaChess.db.games then
        DeltaChess.db.games[gameId] = nil
    end
end

--- Create a new board with standard game metadata initialized.
-- @param gameId string the game identifier
-- @param white string white player name
-- @param black string black player name
-- @param settings table clock settings {useClock, timeMinutes, incrementSeconds}
-- @param extraMeta table|nil additional metadata to set
-- @return Board the new board object
function DeltaChess.CreateGameBoard(gameId, white, black, settings, extraMeta)
    local board = DeltaChessFramework.Board.New()
    local Constants = DeltaChessFramework.Constants

    -- Core game metadata
    board:SetGameMeta("id", gameId)
    -- Set any additional metadata first so clockData is available for clock setup
    if extraMeta then
        for key, value in pairs(extraMeta) do
            if key == "playerColor" then
                board:SetPlayerColor(value)
            else
                board:SetGameMeta(key, value)
            end
        end
    end
    -- Start game and sync Board clock from clockData when using clock
    local startTs = DeltaChessFramework.Util.TimeNow()
    local clockData = extraMeta and extraMeta.clockData
    if clockData and clockData.gameStartTimestamp then
        startTs = clockData.gameStartTimestamp
    end
    board:StartGame(startTs)
    if settings and settings.useClock and clockData then
        local baseSec = clockData.initialTimeSeconds or (10 * 60)
        local inc = clockData.incrementSeconds or 0
        local handicapSec = (clockData.handicapSeconds and clockData.handicapSeconds > 0) and clockData.handicapSeconds or 0
        local sideWithLess = clockData.handicapSide
        local whiteSec = baseSec
        local blackSec = baseSec
        if handicapSec > 0 and sideWithLess == "white" then
            whiteSec = math.max(60, baseSec - handicapSec)
        elseif handicapSec > 0 and sideWithLess == "black" then
            blackSec = math.max(60, baseSec - handicapSec)
        end
        board:SetClock(Constants.COLOR.WHITE, whiteSec)
        board:SetClock(Constants.COLOR.BLACK, blackSec)
        board:SetIncrement(Constants.COLOR.WHITE, inc)
        board:SetIncrement(Constants.COLOR.BLACK, inc)
    end
    -- white/black can be string (name) or table { name, class?, engine? }
    local wp = (type(white) == "table") and white or ((extraMeta and extraMeta.whiteClass) and { name = white, class = extraMeta.whiteClass } or white)
    local bp = (type(black) == "table") and black or ((extraMeta and extraMeta.blackClass) and { name = black, class = extraMeta.blackClass } or black)
    board:SetWhitePlayer(wp)
    board:SetBlackPlayer(bp)
    board:SetGameMeta("settings", settings or {
        useClock = false,
        timeMinutes = 0,
        incrementSeconds = 0
    })

    return board
end

--- Get all active game IDs.
-- @return table array of gameId strings for active games
function DeltaChess.GetActiveGameIds()
    local ids = {}
    if DeltaChess.db and DeltaChess.db.games then
        for gameId, board in pairs(DeltaChess.db.games) do
            if board:IsActive() then
                table.insert(ids, gameId)
            end
        end
    end
    return ids
end

--- Check if a game exists.
-- @param gameId string
-- @return boolean
function DeltaChess.GameExists(gameId)
    return DeltaChess.GetBoard(gameId) ~= nil
end
