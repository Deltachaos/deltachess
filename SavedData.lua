-- SavedData.lua - Save and load game data

local STATUS = {
    ACTIVE = DeltaChess.Constants.STATUS_ACTIVE,
    PAUSED = DeltaChess.Constants.STATUS_PAUSED,
    ENDED = DeltaChess.Constants.STATUS_ENDED,
}

-- Save game to history using Board serialization
function DeltaChess:SaveGameToHistory(board)
    -- Ensure the board has an end time set
    if not board:GetEndTime() then
        board:EndGame()
    end

    local gameId = board:GetGameMeta("id")
    if not gameId then
        self:Print("Cannot save to history: game has no id.")
        return
    end

    -- Check if already saved into history
    local alreadySaved = self.db.history[gameId] ~= nil

    -- Serialize the board state (contains ALL game data; result is derived in GetGameResult())
    local serializedBoard = board:Serialize()

    self.db.history[gameId] = serializedBoard

    -- Remove from active games
    DeltaChess.RemoveBoard(gameId)

    -- Only print message if this is a new entry
    if not alreadySaved then
        self:Print("Game saved to history.")
    end
end

-- Load game entry from history (raw serialized data)
function DeltaChess:LoadGameFromHistory(historyId)
    return self.db.history[historyId]
end

-- Reconstruct a Board object from a history entry
function DeltaChess:BoardFromHistory(historyId)
    local entry = self:LoadGameFromHistory(historyId)
    if not entry then
        return nil, "Game not found in history"
    end
    return DeltaChess.Board.Deserialize(entry)
end

-- Deserialize a history entry to a Board object
function DeltaChess:DeserializeHistoryEntry(entry)
    return DeltaChess.Board.Deserialize(entry)
end

-- Resume interrupted game
function DeltaChess:ResumeGame(gameId)
    local board = DeltaChess.GetBoard(gameId)
    if not board then
        self:Print("Game not found!")
        return
    end
    
    if not board:IsActive() then
        self:Print("Game has already ended!")
        return
    end
    
    -- Show the chess board
    self:ShowChessBoard(gameId)
end

-- Get all active games
function DeltaChess:GetActiveGames()
    local activeGames = {}
    
    for gameId, board in pairs(self.db.games) do
        if board:IsActive() then
            table.insert(activeGames, board)
        end
    end
    
    return activeGames
end

-- Clean up old games
function DeltaChess:CleanupOldGames()
    local currentTime = DeltaChess.Util.TimeNow()
    local sevenDaysAgo = currentTime - (7 * 24 * 60 * 60)
    
    for gameId, board in pairs(self.db.games) do
        local startTime = board:GetStartTime() or 0
        -- Remove games that haven't been updated in 7 days
        if startTime < sevenDaysAgo and board:IsActive() then
            -- Move to history as abandoned
            board:EndGame(currentTime)

            self:SaveGameToHistory(board)
        end
    end
end

-- Clear game history
function DeltaChess:ClearHistory()
    self.db.history = {}
    self:Print("Game history cleared.")
end

-- Delete a specific game from history
function DeltaChess:DeleteFromHistory(gameId)
    if self.db.history[gameId] then
        self.db.history[gameId] = nil
        self:Print("Game removed from history.")
        return true
    end
    return false
end

-- Get game count
function DeltaChess:GetGameCount()
    local active = 0
    local total = 0
    for _ in pairs(self.db.games) do active = active + 1 end
    for _ in pairs(self.db.history) do total = total + 1 end

    return {
        active = active,
        history = total,
        total = active + total
    }
end

-- Backup data
function DeltaChess:BackupData()
    -- Create a backup of the current database
    if not ChessDB_Backup then
        ChessDB_Backup = {}
    end
    
    ChessDB_Backup[tostring(DeltaChess.Util.TimeNow())] = {
        games = self.db.games,
        history = self.db.history,
        settings = self.db.settings
    }
    
    self:Print("Data backed up.")
end

-- Restore data from backup
function DeltaChess:RestoreData(backupTimestamp)
    if not ChessDB_Backup or not ChessDB_Backup[backupTimestamp] then
        self:Print("Backup not found!")
        return false
    end
    
    local backup = ChessDB_Backup[backupTimestamp]
    
    self.db.games = backup.games
    self.db.history = backup.history
    self.db.settings = backup.settings
    
    self:Print("Data restored from backup.")
    return true
end

-- Cleanup on addon load
function DeltaChess:CleanupOnLoad()
    -- Run cleanup tasks
    self:CleanupOldGames()
    
    -- Check for interrupted games
    local activeGames = self:GetActiveGames()
    if #activeGames > 0 then
        self:Print(string.format("You have %d active game(s). Use /chess menu to resume.", #activeGames))
    end
end

-- Schedule periodic cleanup
C_Timer.NewTicker(3600, function() -- Every hour
    if DeltaChess then
        DeltaChess:CleanupOldGames()
    end
end)
