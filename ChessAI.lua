-- ChessAI.lua - AI orchestrator for chess engine integration
-- Uses EngineFramework's EngineRunner for async calculations

DeltaChess.AI = {}

local COLOR = DeltaChess.Constants.COLOR
local STATUS = {
    ACTIVE = DeltaChess.Constants.STATUS_ACTIVE,
    PAUSED = DeltaChess.Constants.STATUS_PAUSED,
    ENDED = DeltaChess.Constants.STATUS_ENDED,
}

local AI_INITIAL_DELAY_MS = 500
local AI_AFTER_DELAY_MS = 500

-- Get the engine ID for a game (or default)
local function getEngineId(board)
    local engineId = board and board:GetEngineId()
    return engineId or DeltaChess.Engines:GetEffectiveDefaultId()
end

-- Make AI move (game integration - calls engine and applies result)
function DeltaChess.AI:MakeMove(gameId, delayMs)
    local delaySec = (delayMs or AI_INITIAL_DELAY_MS) / 1000
    C_Timer.After(delaySec, function()
        local board = DeltaChess.GetBoard(gameId)
        if not board then return end
        if not board:IsActive() then return end
        if not board:OneOpponentIsEngine() then return end

        local aiColor = board:GetEnginePlayerColor()
        local currentTurn = board:IsWhiteToMove() and COLOR.WHITE or COLOR.BLACK
        if currentTurn ~= aiColor then return end

        local engineId = getEngineId(board)
        local engine = DeltaChess.Engines:Get(engineId)
        if not engine then
            DeltaChess:Print("No chess engine available!")
            return
        end

        local difficulty = board:GetEngineElo()
        local engineName = engine.name or engine.id
        local moveApplied = false

        -- Function to apply a validated move
        local function applyMove(uci)
            if moveApplied then return end
            
            -- Re-fetch board state (may have changed during async)
            local currentBoard = DeltaChess.GetBoard(gameId)
            if not currentBoard then return end
            if not currentBoard:IsActive() then return end
            
            local currentTurnCheck = currentBoard:IsWhiteToMove() and COLOR.WHITE or COLOR.BLACK
            if currentTurnCheck ~= aiColor then return end
            
            moveApplied = true

            -- Dynamically calculate delay based on framerate
            local fps = GetFramerate() or 60
            local targetFps = 60
            local baseDelay = AI_AFTER_DELAY_MS / 1000
            local delay
            
            if fps >= targetFps then
                delay = baseDelay
            else
                local scaleFactor = targetFps / math.max(fps, 10)
                delay = baseDelay * scaleFactor
            end
            delay = math.max(0.1, math.min(delay, 2.0))

            C_Timer.After(delay, function()
                -- Re-fetch board again after delay
                local finalBoard = DeltaChess.GetBoard(gameId)
                if not finalBoard then return end
                
                -- Make the move using UCI notation
                local result, err = finalBoard:MakeMoveUci(uci, { timestamp = DeltaChess.Util.TimeNow() })
                
                if not result then
                    DeltaChess:Print("|cFFFF0000ERROR: Failed to apply move " .. uci .. ": " .. (err or "unknown error") .. "|r")
                    return
                end

                -- Play sound for AI's move
                local lastMove = finalBoard.moves[#finalBoard.moves]
                local wasCapture = lastMove and lastMove.captured ~= nil
                DeltaChess.Sound:PlayMoveSound(finalBoard, false, wasCapture, finalBoard)

                -- Update the UI with animation
                if DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId then
                    DeltaChess.UI:UpdateBoardAnimated(DeltaChess.UI.activeFrame, false)
                end

                DeltaChess:NotifyItIsYourTurn(gameId, "Computer")

                -- Check if game ended
                if finalBoard:IsEnded() then
                    finalBoard:EndGame()
                    if DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId then
                        DeltaChess.UI:ShowGameEnd(DeltaChess.UI.activeFrame)
                    end
                end
            end)
        end

        -- Use EngineRunner for async calculation
        DeltaChess.EngineRunner.Create(engineId)
            :Fen(board:GetFen())
            :Elo(difficulty)
            :LoopFn(DeltaChess.WowLoop)
            :HandleError(function(err)
                DeltaChess:Print("|cFFFF0000Engine error: " .. tostring(err.message or err) .. "|r")
                return true  -- Return random legal move on error
            end)
            :OnComplete(function(result, err)
                if moveApplied then return end
                
                -- Re-fetch board state
                local currentBoard = DeltaChess.GetBoard(gameId)
                if not currentBoard then return end
                if not currentBoard:IsActive() then return end
                
                local currentTurnCheck = currentBoard:IsWhiteToMove() and COLOR.WHITE or COLOR.BLACK
                if currentTurnCheck ~= aiColor then return end

                if err then
                    DeltaChess:Print("|cFFFF0000ERROR: Engine '" .. engineName .. "' error: " .. tostring(err.message or err) .. "|r")
                    return
                end

                if result and result.move then
                    applyMove(result.move)
                else
                    DeltaChess:Print("|cFFFF0000ERROR: Engine '" .. engineName .. "' returned no move.|r")
                end
            end)
            :Run()
    end)
end

-- Start a game against the computer
function DeltaChess:StartComputerGame(playerColor, difficulty, engineId, settings)
    settings = settings or {}
    local gameId = "computer_" .. tostring(DeltaChess.Util.TimeNow()) .. "_" .. math.random(1000, 9999)
    local playerName = self:GetFullPlayerName(UnitName("player"))
    local engineIdResolved = engineId or DeltaChess.Engines:GetEffectiveDefaultId()
    local engine = DeltaChess.Engines:Get(engineIdResolved)
    local computerPlayer = { name = "Computer", engine = { id = engine and engine.id or engineIdResolved, elo = difficulty } }

    local whitePlayer = (playerColor == COLOR.WHITE) and playerName or computerPlayer
    local blackPlayer = (playerColor == COLOR.BLACK) and playerName or computerPlayer

    local useClock = settings.useClock and true or false
    local timeMinutes = settings.timeMinutes or 10
    local incrementSeconds = settings.incrementSeconds or 0
    local handicapSeconds = (settings.handicapSeconds and settings.handicapSeconds > 0) and settings.handicapSeconds or nil
    local handicapSide = (settings.handicapSide == "white" or settings.handicapSide == "black") and settings.handicapSide or nil

    local clockData = nil
    if useClock then
        clockData = {
            gameStartTimestamp = DeltaChess.Util.TimeNow(),
            initialTimeSeconds = timeMinutes * 60,
            incrementSeconds = incrementSeconds,
            handicapSeconds = handicapSeconds,
            handicapSide = handicapSide,
        }
    end

    local board = DeltaChess.CreateGameBoard(
        gameId,
        whitePlayer,
        blackPlayer,
        { useClock = useClock, timeMinutes = timeMinutes, incrementSeconds = incrementSeconds },
        { playerColor = playerColor, clockData = clockData }
    )

    -- Store board directly in games database
    DeltaChess.StoreBoard(gameId, board)
    self:ShowChessBoard(gameId)

    if board:GetEnginePlayerColor() == COLOR.WHITE then
        DeltaChess.AI:MakeMove(gameId, 1000)
    end

    return gameId
end
