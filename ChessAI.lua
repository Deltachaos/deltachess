-- ChessAI.lua - AI orchestrator for chess engine integration
-- Chess engine logic is fully decoupled; plug in engines via DeltaChess.Engines.

DeltaChess.AI = {}

local C = DeltaChess.Constants.COLOR
local PT = DeltaChess.Constants.PIECE_TYPE

local AI_INITIAL_DELAY_MS = 500

-- Get the engine for a game (or default)
local function getEngine(game)
    local engineId = game and game.computerEngine or DeltaChess.Engines:GetEffectiveDefaultId()
    return DeltaChess.Engines:Get(engineId)
end

-- Delegate to the active engine; engine must implement GetBestMoveAsync
function DeltaChess.AI:GetBestMoveAsync(board, color, difficulty, onComplete, engineId)
    local engine = DeltaChess.Engines:Get(engineId or DeltaChess.Engines:GetEffectiveDefaultId())
    if not engine or not engine.GetBestMoveAsync then
        onComplete(nil)
        return
    end
    local position = DeltaChess.Engines.CreateBoardAdapter(board)
    engine:GetBestMoveAsync(position, color, difficulty, onComplete)
end

-- Make AI move (game integration - calls engine and applies result)
function DeltaChess.AI:MakeMove(gameId, delayMs)
    local delaySec = (delayMs or AI_INITIAL_DELAY_MS) / 1000
    C_Timer.After(delaySec, function()
        local game = DeltaChess.db.games[gameId]
        if not game or game.status ~= "active" then return end
        if not game.isVsComputer then return end

        local aiColor = game.computerColor
        if game.board.currentTurn ~= aiColor then return end

        local engine = getEngine(game)
        if not engine or not engine.GetBestMoveAsync then
            DeltaChess:Print("No chess engine available!")
            return
        end

        local difficulty = game.computerDifficulty  -- nil if engine doesn't support ELO
        local position = DeltaChess.Engines.CreateBoardAdapter(game.board)
        local engineName = engine.name or engine.id
        local moveApplied = false  -- Flag to prevent double-moves from timeout vs callback race
        
        -- Function to apply a validated move
        local function applyMove(validMove)
            if moveApplied then return end
            if not game or game.status ~= "active" then return end
            if game.board.currentTurn ~= aiColor then return end
            
            moveApplied = true
            
            local piece = game.board:GetPiece(validMove.fromRow, validMove.fromCol)
            local promotion = validMove.promotion
            if piece and piece.type == PT.PAWN then
                local promotionRank = piece.color == C.WHITE and 8 or 1
                if validMove.toRow == promotionRank and not promotion then
                    promotion = PT.QUEEN
                end
            end

            game.board:MakeMove(validMove.fromRow, validMove.fromCol, validMove.toRow, validMove.toCol, promotion)

            DeltaChess:NotifyItIsYourTurn(gameId, "Computer")

            if game.board.gameStatus ~= "active" then
                DeltaChess.UI:ShowGameEnd(DeltaChess.UI.activeFrame)
            end
        end
        
        engine:GetBestMoveAsync(position, aiColor, difficulty, function(move)
            if moveApplied then return end
            if not game or game.status ~= "active" then return end
            if game.board.currentTurn ~= aiColor then return end

            if move then
                -- Validate the engine's move against DeltaChess game logic
                if DeltaChess.Engines:ValidateMove(game.board, move) then
                    applyMove(move)
                else
                    DeltaChess:Print("|cFFFF0000ERROR: Engine '" .. engineName .. "' returned invalid move: " .. 
                        move.fromRow .. "," .. move.fromCol .. " -> " .. move.toRow .. "," .. move.toCol .. "|r")
                end
            else
                DeltaChess:Print("|cFFFF0000ERROR: Engine '" .. engineName .. "' returned no move.|r")
            end
        end)
    end)
end

-- Start a game against the computer
function DeltaChess:StartComputerGame(playerColor, difficulty, engineId)
    local gameId = "computer_" .. tostring(time()) .. "_" .. math.random(1000, 9999)
    local playerName = self:GetFullPlayerName(UnitName("player"))
    local computerColor = playerColor == C.WHITE and C.BLACK or C.WHITE
    local engine = DeltaChess.Engines:Get(engineId or DeltaChess.Engines:GetEffectiveDefaultId())

    local game = {
        id = gameId,
        white = playerColor == C.WHITE and playerName or "Computer",
        black = playerColor == C.BLACK and playerName or "Computer",
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
        computerDifficulty = difficulty,  -- nil if engine doesn't support ELO
        computerEngine = engine and engine.id or DeltaChess.Engines:GetEffectiveDefaultId(),
        playerColor = playerColor
    }

    self.db.games[gameId] = game
    self:ShowChessBoard(gameId)

    if computerColor == C.WHITE then
        DeltaChess.AI:MakeMove(gameId, 1000)
    end

    return gameId
end
