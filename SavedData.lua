-- SavedData.lua - Save and load game data

-- Save game to history
function DeltaChess:SaveGameToHistory(game, result)
    -- Create history entry
    local historyEntry = {
        id = game.id,
        white = game.white,
        black = game.black,
        whiteClass = game.whiteClass,
        blackClass = game.blackClass,
        result = result,
        moves = {},
        date = date("%Y-%m-%d %H:%M:%S", game.startTime),
        startTime = game.startTime,
        duration = game.endTime and (game.endTime - game.startTime) or 0,
        settings = game.settings,
        isVsComputer = game.isVsComputer,
        playerColor = game.playerColor,
        computerDifficulty = game.computerDifficulty,
        computerEngine = game.computerEngine
    }
    
    -- Copy moves in a format suitable for replay
    for _, move in ipairs(game.board.moves) do
        local moveEntry = {
            fromRow = move.from and move.from.row or move.fromRow,
            fromCol = move.from and move.from.col or move.fromCol,
            toRow = move.to and move.to.row or move.toRow,
            toCol = move.to and move.to.col or move.toCol,
            pieceType = move.piece or move.pieceType,
            color = move.color,
            captured = move.captured and true or false,
            capturedType = move.captured and (move.captured.type or move.capturedType) or nil,
            promotion = move.promotion,
            castle = move.castle,
            enPassant = move.enPassant,
            timestamp = move.timestamp
        }
        table.insert(historyEntry.moves, moveEntry)
    end
    
    -- Add to history
    table.insert(self.db.history, historyEntry)
    
    -- Remove from active games
    self.db.games[game.id] = nil
    
    self:Print("Game saved to history.")
end

-- Load game from history
function DeltaChess:LoadGameFromHistory(historyId)
    for _, entry in ipairs(self.db.history) do
        if entry.id == historyId then
            return entry
        end
    end
    return nil
end

-- Resume interrupted game
function DeltaChess:ResumeGame(gameId)
    local game = self.db.games[gameId]
    if not game then
        self:Print("Game not found!")
        return
    end
    
    if game.status ~= "active" then
        self:Print("Game has already ended!")
        return
    end
    
    -- Show the chess board
    self:ShowChessBoard(gameId)
end

-- Get all active games
function DeltaChess:GetActiveGames()
    local activeGames = {}
    
    for gameId, game in pairs(self.db.games) do
        if game.status == "active" then
            table.insert(activeGames, game)
        end
    end
    
    return activeGames
end

-- Clean up old games
function DeltaChess:CleanupOldGames()
    local currentTime = time()
    local sevenDaysAgo = currentTime - (7 * 24 * 60 * 60)
    
    for gameId, game in pairs(self.db.games) do
        -- Remove games that haven't been updated in 7 days
        if game.startTime < sevenDaysAgo and game.status == "active" then
            -- Move to history as abandoned
            game.status = "ended"
            game.board.gameStatus = "abandoned"
            game.endTime = currentTime
            
            self:SaveGameToHistory(game, "abandoned")
        end
    end
end

-- Export game to PGN format (Portable Game Notation)
function DeltaChess:ExportToPGN(historyId)
    local game = self:LoadGameFromHistory(historyId)
    if not game then
        self:Print("Game not found!")
        return nil
    end
    
    local pgn = ""
    
    -- Header
    pgn = pgn .. '[Event "WoW DeltaChess Game"]\n'
    pgn = pgn .. '[Site "World of Warcraft"]\n'
    pgn = pgn .. '[Date "' .. game.date .. '"]\n'
    pgn = pgn .. '[White "' .. game.white .. '"]\n'
    pgn = pgn .. '[Black "' .. game.black .. '"]\n'
    pgn = pgn .. '[Result "' .. (game.result or "*") .. '"]\n\n'
    
    -- Moves
    for i, move in ipairs(game.moves) do
        if i % 2 == 1 then
            pgn = pgn .. math.ceil(i / 2) .. ". "
        end
        
        local board = DeltaChess.Board:New() -- Temporary board for notation
        local fromNotation = board:ToAlgebraic(move.from.row, move.from.col)
        local toNotation = board:ToAlgebraic(move.to.row, move.to.col)
        
        pgn = pgn .. fromNotation .. toNotation .. " "
        
        if i % 2 == 0 then
            pgn = pgn .. "\n"
        end
    end
    
    return pgn
end

-- Import game from PGN format
function DeltaChess:ImportFromPGN(pgnString)
    -- Basic PGN parsing (simplified)
    -- In production, use a proper PGN parser
    
    local game = {
        white = "",
        black = "",
        date = "",
        moves = {}
    }
    
    -- Parse header
    for tag, value in pgnString:gmatch('%[(%w+)%s+"([^"]+)"%]') do
        if tag == "White" then
            game.white = value
        elseif tag == "Black" then
            game.black = value
        elseif tag == "Date" then
            game.date = value
        elseif tag == "Result" then
            game.result = value
        end
    end
    
    -- Parse moves (simplified - just extract algebraic notation)
    local movesSection = pgnString:match("\n\n(.+)$")
    if movesSection then
        for move in movesSection:gmatch("([a-h][1-8][a-h][1-8])") do
            table.insert(game.moves, move)
        end
    end
    
    return game
end

-- Clear game history
function DeltaChess:ClearHistory()
    self.db.history = {}
    self:Print("Game history cleared.")
end

-- Delete a specific game from history
function DeltaChess:DeleteFromHistory(gameId)
    for i, game in ipairs(self.db.history) do
        if game.id == gameId then
            table.remove(self.db.history, i)
            self:Print("Game removed from history.")
            return true
        end
    end
    return false
end

-- Get game count
function DeltaChess:GetGameCount()
    local active = 0
    local total = #self.db.history
    
    for _ in pairs(self.db.games) do
        active = active + 1
    end
    
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
    
    ChessDB_Backup[tostring(time())] = {
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
