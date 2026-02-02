-- Sound.lua - Sound system for chess events

DeltaChess.Sound = {}

-- Detect WoW version for compatibility
local isRetail = WOW_PROJECT_ID and WOW_PROJECT_MAINLINE and (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)

-- Sound IDs for different events
-- These can be customized for retail vs classic
-- Using SOUNDKIT constants where available, with fallback file IDs
local SoundConfig = {
    -- When the player makes a move
    playerMove = {
        retail = SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON,
        classic = SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON,
    },
    -- When the opponent makes a move
    opponentMove = {
        retail = SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF,
        classic = SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF,
    },
    -- When the player captures a piece
    playerCapture = {
        retail = 286130,
        classic = 286130,
    },
    -- When the opponent captures a piece
    opponentCapture = {
        retail = 316466,
        classic = 316466,
    },
    -- When the player is in check (king threatened)
    playerInCheck = {
        retail = 15262,
        classic = 15262
    },
    -- When the player puts opponent in check
    opponentInCheck = {
        retail = 3201,
        classic = 3201
    },

    -- Challenge received
    challengeReceived = {
        retail = 162940,
        classic = 162940
    },
    -- Challenge accepted
    challengeAccepted = {
        retail = 26905,
        classic = 26905
    },
    -- Challenge declined
    challengeDeclined = {
        retail = 882,
        classic = 882
    },
    -- When the player wins
    playerWin = {
        retail = 37656,
        classic = 37656
    },
    -- When the player loses
    playerLose = {
        retail = 43503,
        classic = 43503
    },
    -- Stalemate/Draw
    stalemate = {
        retail = SOUNDKIT.IG_QUEST_LOG_ABANDON_QUEST,
        classic = SOUNDKIT.IG_QUEST_LOG_ABANDON_QUEST
    },
    -- Invalid/illegal move attempted
    invalidMove = {
        retail = 47355,
        classic = 47355
    }
}

-- Core sound playing function with retail/classic support
-- @param soundType string - The type of sound event (e.g., "playerMove", "opponentMove")
-- @param forceFile string|nil - Optional specific file path to play instead of config
function DeltaChess.Sound:Play(soundType, forceFile)
    local config = SoundConfig[soundType]
    if not config and not forceFile then
        return
    end
    
    local soundId
    if forceFile then
        soundId = forceFile
    elseif isRetail then
        soundId = config.retail
    else
        soundId = config.classic
    end
    
    if soundId then
        PlaySound(soundId)
    end
end

-- Convenience functions for specific sound events

-- Play sound when the player makes a move
-- @param wasCapture boolean - Whether a piece was captured
function DeltaChess.Sound:PlayPlayerMove(wasCapture)
    if wasCapture then
        self:Play("playerCapture")
    else
        self:Play("playerMove")
    end
end

-- Play sound when the opponent makes a move
-- @param wasCapture boolean - Whether a piece was captured
function DeltaChess.Sound:PlayOpponentMove(wasCapture)
    if wasCapture then
        self:Play("opponentCapture")
    else
        self:Play("opponentMove")
    end
end

-- Play sound when the player's king is in check
function DeltaChess.Sound:PlayPlayerInCheck()
    self:Play("playerInCheck")
end

-- Play sound when the opponent's king is in check (player gave check)
function DeltaChess.Sound:PlayOpponentInCheck()
    self:Play("opponentInCheck")
end

-- Play sound when the player wins
function DeltaChess.Sound:PlayWin()
    self:Play("playerWin")
end

-- Play sound when the player loses
function DeltaChess.Sound:PlayLose()
    self:Play("playerLose")
end

-- Play sound for stalemate/draw
function DeltaChess.Sound:PlayStalemate()
    self:Play("stalemate")
end

-- Play sound when a challenge is received
function DeltaChess.Sound:PlayChallengeReceived()
    self:Play("challengeReceived")
end

-- Play sound when a challenge is accepted
function DeltaChess.Sound:PlayChallengeAccepted()
    self:Play("challengeAccepted")
end

-- Play sound for invalid/illegal move attempt
function DeltaChess.Sound:PlayInvalidMove()
    self:Play("invalidMove")
end

-- Play sound when a challenge is declined
function DeltaChess.Sound:PlayChallengeDeclined()
    self:Play("challengeDeclined")
end

-- Helper function to determine player color in a game
-- @param game table - The game object
-- @return string - "white" or "black"
local function GetPlayerColor(game)
    if game.isVsComputer then
        return game.playerColor
    else
        local playerName = DeltaChess:GetFullPlayerName(UnitName("player"))
        if game.white == playerName then
            return "white"
        else
            return "black"
        end
    end
end

-- Play appropriate sound after a move is made
-- @param game table - The game object
-- @param isPlayerMove boolean - Whether this was the player's move
-- @param wasCapture boolean - Whether a piece was captured
-- @param board table - The board object (for check detection)
function DeltaChess.Sound:PlayMoveSound(game, isPlayerMove, wasCapture, board)
    local playerColor = GetPlayerColor(game)
    local opponentColor = playerColor == "white" and "black" or "white"
    
    -- First, play the move/capture sound
    if isPlayerMove then
        self:PlayPlayerMove(wasCapture)
    else
        self:PlayOpponentMove(wasCapture)
    end
    
    -- Then check for check status (but not if game ended - let game end sound play instead)
    if board and board.gameStatus == "active" then
        local playerInCheck = board:IsInCheck(playerColor)
        local opponentInCheck = board:IsInCheck(opponentColor)
        
        if playerInCheck then
            -- Short delay so sounds don't overlap
            C_Timer.After(0.15, function()
                self:PlayPlayerInCheck()
            end)
        elseif opponentInCheck then
            -- Short delay so sounds don't overlap
            C_Timer.After(0.15, function()
                self:PlayOpponentInCheck()
            end)
        end
    end
end

-- Play appropriate sound for game end
-- @param game table - The game object
-- @param board table - The board object
function DeltaChess.Sound:PlayGameEndSound(game, board)
    local playerColor = GetPlayerColor(game)
    
    if board.gameStatus == "checkmate" then
        -- The player whose turn it is when checkmate is detected is the loser
        -- (they have no legal moves and are in check)
        local loserColor = board.currentTurn
        if playerColor == loserColor then
            self:PlayLose()
        else
            self:PlayWin()
        end
    elseif board.gameStatus == "stalemate" or board.gameStatus == "draw" then
        self:PlayStalemate()
    elseif board.gameStatus == "resignation" then
        local playerName = DeltaChess:GetFullPlayerName(UnitName("player"))
        if game.resignedPlayer == playerName or 
           (game.isVsComputer and game.resignedPlayer ~= "Computer") then
            self:PlayLose()
        else
            self:PlayWin()
        end
    elseif board.gameStatus == "timeout" then
        local playerName = DeltaChess:GetFullPlayerName(UnitName("player"))
        if game.timeoutPlayer == playerName then
            self:PlayLose()
        else
            self:PlayWin()
        end
    end
end

-- Allow users to customize sounds (can be expanded for settings UI)
-- @param soundType string - The sound type to configure
-- @param retailSound number|string - Sound ID or file path for retail
-- @param classicSound number|string - Sound ID or file path for classic
function DeltaChess.Sound:ConfigureSound(soundType, retailSound, classicSound)
    if SoundConfig[soundType] then
        SoundConfig[soundType].retail = retailSound
        SoundConfig[soundType].classic = classicSound or retailSound
    end
end
