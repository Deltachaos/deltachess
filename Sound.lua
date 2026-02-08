-- Sound.lua - Sound system for chess events

DeltaChess.Sound = {}

local COLOR = DeltaChess.Constants.COLOR
local STATUS = {
    ACTIVE = DeltaChess.Constants.STATUS_ACTIVE,
    PAUSED = DeltaChess.Constants.STATUS_PAUSED,
}

local SOUND_FILES = {
    MOVE = "Interface\\AddOns\\DeltaChess\\Sounds\\move.mp3",
}

-- Detect WoW version for compatibility
local isRetail = WOW_PROJECT_ID and WOW_PROJECT_MAINLINE and (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)

-- Sound IDs for different events
-- These can be customized for retail vs classic
-- Using SOUNDKIT constants where available, with fallback file IDs
local SoundConfig = {
    -- When the player makes a move
    playerMove = {
        retail = SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON,
        classic = SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
    },
    -- When the opponent makes a move
    opponentMove = {
        retail = SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF,
        classic = SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF
    },
    -- When the player captures a piece
    playerCapture = {
        retail = 867,
        classic = 867
    },
    -- When the opponent captures a piece
    opponentCapture = {
        retail = 868,
        classic = 868
    },
    -- When the player is in check (king threatened)
    playerInCheck = {
        retail = 15262,
        classic = 8959
    },
    -- When the player puts opponent in check
    opponentInCheck = {
        retail = 3201,
        classic = 3201
    },
    -- Challenge received
    challengeReceived = {
        retail = 162940,
        classic = 881
    },
    -- Challenge accepted
    challengeAccepted = {
        retail = 26905,
        classic = 3486
    },
    -- Challenge declined
    challengeDeclined = {
        retail = 882,
        classic = 882
    },
    -- When the player wins
    playerWin = {
        retail = 37656,
        classic = 8173
    },
    -- When the player loses
    playerLose = {
        retail = 43503,
        classic = 18871
    },
    -- Stalemate/Draw
    stalemate = {
        retail = SOUNDKIT.IG_QUEST_LOG_ABANDON_QUEST,
        classic = SOUNDKIT.IG_QUEST_LOG_ABANDON_QUEST
    },
    -- Invalid/illegal move attempted
    invalidMove = {
        retail = 47355,
        classic = 853
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
        PlaySoundFile(SOUND_FILES.MOVE)
        self:Play("playerMove")
    end
end

-- Play sound when the opponent makes a move
-- @param wasCapture boolean - Whether a piece was captured
function DeltaChess.Sound:PlayOpponentMove(wasCapture)
    if wasCapture then
        self:Play("opponentCapture")
    else
        PlaySoundFile(SOUND_FILES.MOVE)
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

-- Helper function to determine player color in a game (board IS the game now)
-- @param board table - The board object
-- @return string - COLOR.WHITE or COLOR.BLACK
local function GetPlayerColor(board)
    local isVsComputer = board:OneOpponentIsEngine()
    if isVsComputer then
        return board:GetPlayerColor()
    else
        local playerName = DeltaChess:GetFullPlayerName(UnitName("player"))
        local white = board:GetWhitePlayerName()
        if white == playerName then
            return COLOR.WHITE
        else
            return COLOR.BLACK
        end
    end
end

-- Play appropriate sound after a move is made
-- @param board table - The board object (board IS the game now)
-- @param isPlayerMove boolean - Whether this was the player's move
-- @param wasCapture boolean - Whether a piece was captured
-- @param boardForCheck table - The board object for check detection (same as board)
function DeltaChess.Sound:PlayMoveSound(board, isPlayerMove, wasCapture, boardForCheck)
    local playerColor = GetPlayerColor(board)
    local opponentColor = playerColor == COLOR.WHITE and COLOR.BLACK or COLOR.WHITE
    
    -- First, play the move/capture sound
    if isPlayerMove then
        self:PlayPlayerMove(wasCapture)
    else
        self:PlayOpponentMove(wasCapture)
    end
    
    -- Then check for check status (but not if game ended - let game end sound play instead).
    -- Allow when ACTIVE (live game) or PAUSED (replay snapshot) so check plays in replay too.
    local checkBoard = boardForCheck or board
    if checkBoard and not checkBoard:IsEnded() then
        -- Only current side to move can be in check
        local currentTurn = checkBoard:GetCurrentTurn()
        local inCheck = checkBoard:InCheck()
        
        if inCheck then
            -- Short delay so sounds don't overlap
            C_Timer.After(0.15, function()
                if currentTurn == playerColor then
                    self:PlayPlayerInCheck()
                else
                    self:PlayOpponentInCheck()
                end
            end)
        end
    end
end

-- Play appropriate sound for game end
-- @param board table - The board object (board IS the game now)
-- @param boardUnused table - Unused parameter (kept for compatibility)
function DeltaChess.Sound:PlayGameEndSound(board, boardUnused)
    local playerColor = GetPlayerColor(board)
    local reason = board:GetEndReason()
    
    if reason == DeltaChess.Constants.REASON_CHECKMATE then
        -- The player whose turn it is when checkmate is detected is the loser
        -- (they have no legal moves and are in check)
        local loserColor = board:GetCurrentTurn()
        if playerColor == loserColor then
            self:PlayLose()
        else
            self:PlayWin()
        end
    elseif reason == DeltaChess.Constants.REASON_STALEMATE or reason == DeltaChess.Constants.REASON_FIFTY_MOVE then
        self:PlayStalemate()
    elseif reason == DeltaChess.Constants.REASON_RESIGNATION then
        local playerName = DeltaChess:GetFullPlayerName(UnitName("player"))
        local resignedPlayer = board:GetResignedPlayer()
        local isVsComputer = board:OneOpponentIsEngine()
        if resignedPlayer == playerName or 
           (isVsComputer and resignedPlayer ~= "Computer") then
            self:PlayLose()
        else
            self:PlayWin()
        end
    elseif reason == DeltaChess.Constants.REASON_TIMEOUT then
        local playerName = DeltaChess:GetFullPlayerName(UnitName("player"))
        local timeoutPlayer = board:GetGameMeta("timeoutPlayer")
        if timeoutPlayer == playerName then
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
