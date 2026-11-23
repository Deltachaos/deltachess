-- ChessAI.lua - AI orchestrator for chess engine integration
-- Uses EngineFramework's EngineRunner for async calculations

local DeltaChess = LibStub("DeltaChess-1.0")
local DeltaChessFramework = LibStub("DeltachessFramework-1.0")

DeltaChess.AI = {}

local COLOR = DeltaChessFramework.Constants.COLOR
local STATUS = {
    ACTIVE = DeltaChessFramework.Constants.STATUS_ACTIVE,
    PAUSED = DeltaChessFramework.Constants.STATUS_PAUSED,
    ENDED = DeltaChessFramework.Constants.STATUS_ENDED,
}

local AI_INITIAL_DELAY_MS = 500
local AI_AFTER_DELAY_MS = 500

-- Get the engine ID for a game (or default)
local function getEngineId(board)
    local engineId = board and board:GetEngineId()
    return engineId or DeltaChessFramework.Engines:GetEffectiveDefaultId()
end

-- gameId -> true from the moment a computer move is requested until it is
-- applied or abandoned. Engine sessions themselves live only in memory, so a
-- UI reload leaves this empty and the search must be started again.
local inFlight = {}

--- True when the engine side is the side to move.
function DeltaChess.AI:IsComputersTurn(board)
    if not board or not board:OneOpponentIsEngine() then return false end
    local aiColor = board:GetEnginePlayerColor()
    if not aiColor then return false end
    local currentTurn = board:IsWhiteToMove() and COLOR.WHITE or COLOR.BLACK
    return currentTurn == aiColor
end

--- Pause a computer game whose board window is closed, once it is the player's
--- turn. A running computer game on the computer's turn means that move has not
--- been applied yet (the search is still going, or it was lost in a UI reload).
--- Skips the pause while a queued premove is about to be played; that premove
--- decides whether the game continues.
function DeltaChess.AI:PauseIfBoardClosed(gameId)
    if not gameId then return end
    local board = DeltaChess.GetBoard(gameId)
    if not board or not board:OneOpponentIsEngine() or not board:IsActive() then return end
    if self:IsComputersTurn(board) then return end

    local frame = DeltaChess.UI and DeltaChess.UI.activeFrame
    if frame and frame.gameId == gameId and frame:IsShown() then return end
    if DeltaChess.UI and DeltaChess.UI.PremovePending and DeltaChess.UI:PremovePending(gameId) then
        return
    end

    board:PauseGame()
    if DeltaChess.Minimap and DeltaChess.Minimap.UpdateYourTurnHighlight then
        DeltaChess.Minimap:UpdateYourTurnHighlight()
    end
end

--- After a UI reload the in-memory engine sessions are gone. Any computer game
--- that is still running on the computer's turn never finished that move, so
--- start it again. Games already on the player's turn were paused when the
--- board was closed, and stay paused.
function DeltaChess.AI:ResumeInterruptedComputerMoves()
    if not DeltaChess.db or not DeltaChess.db.games then return end
    for gameId, board in pairs(DeltaChess.db.games) do
        if board and board.IsActive and board:IsActive() and self:IsComputersTurn(board) then
            self:MakeMove(gameId, AI_INITIAL_DELAY_MS)
        end
    end
end

-- Make AI move (game integration - calls engine and applies result)
function DeltaChess.AI:MakeMove(gameId, delayMs)
    if inFlight[gameId] then return end
    inFlight[gameId] = true

    local delaySec = (delayMs or AI_INITIAL_DELAY_MS) / 1000
    C_Timer.After(delaySec, function()
        local function abandon()
            inFlight[gameId] = nil
            DeltaChess.AI:PauseIfBoardClosed(gameId)
        end

        local board = DeltaChess.GetBoard(gameId)
        if not board or not board:IsActive() or not board:OneOpponentIsEngine()
            or not DeltaChess.AI:IsComputersTurn(board) then
            abandon()
            return
        end

        local engineId = getEngineId(board)
        local engine = DeltaChessFramework.Engines:Get(engineId)
        if not engine then
            DeltaChess:Print("No chess engine available!")
            abandon()
            return
        end

        local difficulty = board:GetEngineElo()
        local engineName = engine.name or engine.id
        local moveApplied = false

        -- Function to apply a validated move. Returns true if the move was accepted
        -- and a follow-up timer will apply it (inFlight stays set until then).
        local function applyMove(uci)
            if moveApplied then return true end

            -- Re-fetch board state (may have changed during async)
            local currentBoard = DeltaChess.GetBoard(gameId)
            if not currentBoard or not currentBoard:IsActive() then return false end
            if not DeltaChess.AI:IsComputersTurn(currentBoard) then return false end

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
                inFlight[gameId] = nil

                -- Re-fetch board again after delay
                local finalBoard = DeltaChess.GetBoard(gameId)
                if not finalBoard then return end

                -- Make the move using UCI notation
                local result, err = finalBoard:MakeMoveUci(uci, { timestamp = DeltaChessFramework.Util.TimeNow() })

                if not result then
                    DeltaChess:Print("|cFFFF0000ERROR: Failed to apply move " .. uci .. ": " .. (err or "unknown error") .. "|r")
                    return
                end

                -- Play sound for AI's move
                local lastMove = finalBoard.moves[#finalBoard.moves]
                local wasCapture = lastMove and lastMove.captured ~= nil
                DeltaChess.Sound:PlayMoveSound(finalBoard, false, wasCapture, finalBoard)

                if DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId then
                    DeltaChess.UI:UpdateBoardAnimated(DeltaChess.UI.activeFrame, true)
                end

                DeltaChess:NotifyItIsYourTurn(gameId, "Computer")

                -- Check if game ended
                if finalBoard:IsEnded() then
                    finalBoard:EndGame()
                    local frame = (DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId) and DeltaChess.UI.activeFrame or nil
                    DeltaChess.UI:ShowGameEnd(gameId, frame)
                    return
                end

                -- The premove lives on the game, so play it even when the window
                -- is showing a different game. Pause only if nothing continues.
                if DeltaChess.UI and DeltaChess.UI.SchedulePremove then
                    local premoveFrame = (DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId) and DeltaChess.UI.activeFrame or nil
                    DeltaChess.UI:SchedulePremove(gameId, premoveFrame)
                end
                DeltaChess.AI:PauseIfBoardClosed(gameId)
            end)
            return true
        end

        -- Use EngineRunner Start/Compute; the addon driver ticks sessions each frame.
        local session = DeltaChessFramework.EngineRunner.Create(engineId)
            :Fen(board:GetFen())
            :Elo(difficulty)
            :HandleError(function(err)
                DeltaChess:Print("|cFFFF0000Engine error: " .. tostring(err.message or err) .. "|r")
                return true  -- Return random legal move on error
            end)
            :OnComplete(function(result, err)
                if moveApplied then return end

                local function giveUp(message)
                    if message then
                        DeltaChess:Print(message)
                    end
                    inFlight[gameId] = nil
                    DeltaChess.AI:PauseIfBoardClosed(gameId)
                end

                -- Re-fetch board state
                local currentBoard = DeltaChess.GetBoard(gameId)
                if not currentBoard or not currentBoard:IsActive()
                    or not DeltaChess.AI:IsComputersTurn(currentBoard) then
                    giveUp()
                    return
                end

                if err then
                    giveUp("|cFFFF0000ERROR: Engine '" .. engineName .. "' error: " .. tostring(err.message or err) .. "|r")
                    return
                end

                if result and result.move then
                    if not applyMove(result.move) then
                        giveUp()
                    end
                else
                    giveUp("|cFFFF0000ERROR: Engine '" .. engineName .. "' returned no move.|r")
                end
            end)
            :Start()
        if not session and not moveApplied then
            abandon()
            return
        end
        DeltaChess.AddEngineSession(session)
    end)
end

-- Start a game against the computer
function DeltaChess:StartComputerGame(playerColor, difficulty, engineId, settings)
    settings = settings or {}
    local gameId = "computer_" .. tostring(DeltaChessFramework.Util.TimeNow()) .. "_" .. math.random(1000, 9999)
    local playerCharName, playerName = self:GetLocalPlayerInfo()
    local engineIdResolved = engineId or DeltaChessFramework.Engines:GetEffectiveDefaultId()
    local engine = DeltaChessFramework.Engines:Get(engineIdResolved)
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
            gameStartTimestamp = DeltaChessFramework.Util.TimeNow(),
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

    return gameId
end
