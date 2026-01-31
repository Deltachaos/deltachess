-- Communication.lua - Network communication between players

-- Pending messages waiting for acknowledgment
DeltaChess.pendingAck = {}
DeltaChess.messageIdCounter = 0
DeltaChess.ACK_TIMEOUT = 10 -- seconds

-- Check if board is locked (waiting for ACK)
function DeltaChess:IsBoardLocked(gameId)
    return self.pendingAck[gameId] ~= nil
end

-- Lock board while waiting for ACK
function DeltaChess:LockBoard(gameId, messageId, messageType, moveData)
    self.pendingAck[gameId] = {
        messageId = messageId,
        messageType = messageType,
        moveData = moveData,
        timestamp = time()
    }
    
    -- Update UI to show waiting state
    if DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId then
        DeltaChess.UI:ShowWaitingOverlay(DeltaChess.UI.activeFrame, true)
    end
    
    -- Set timeout
    C_Timer.After(self.ACK_TIMEOUT, function()
        self:HandleAckTimeout(gameId, messageId)
    end)
end

-- Unlock board after ACK received
function DeltaChess:UnlockBoard(gameId)
    self.pendingAck[gameId] = nil
    
    -- Update UI to hide waiting state
    if DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId then
        DeltaChess.UI:ShowWaitingOverlay(DeltaChess.UI.activeFrame, false)
    end
end

-- Handle ACK timeout
function DeltaChess:HandleAckTimeout(gameId, messageId)
    local pending = self.pendingAck[gameId]
    if not pending or pending.messageId ~= messageId then
        return -- Already acknowledged or different message
    end
    
    self:Print("|cFFFF0000Move not confirmed. Opponent may be offline.|r")
    self:Print("|cFFFFFF00Your move was NOT applied. Try again when opponent is online.|r")
    
    -- Unlock without applying the move
    self:UnlockBoard(gameId)
    
    -- Refresh the board to show unchanged state
    if DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId then
        DeltaChess.UI:UpdateBoard(DeltaChess.UI.activeFrame)
    end
end

-- Generate unique message ID
function DeltaChess:GenerateMessageId()
    self.messageIdCounter = self.messageIdCounter + 1
    return string.format("%s_%d_%d", UnitName("player"), time(), self.messageIdCounter)
end

-- Send addon message with optional ACK requirement
function DeltaChess:SendCommMessage(prefix, message, channel, target)
    C_ChatInfo.SendAddonMessage(prefix, message, channel, target)
end

-- Send message that requires acknowledgment
function DeltaChess:SendWithAck(prefix, data, target, gameId)
    local messageId = self:GenerateMessageId()
    data.messageId = messageId
    
    self:SendCommMessage(prefix, self:Serialize(data), "WHISPER", target)
    self:LockBoard(gameId, messageId, prefix, data)
    
    return messageId
end

-- Send acknowledgment
function DeltaChess:SendAck(messageId, target)
    local ackData = {
        messageId = messageId,
        ackType = "ACK"
    }
    self:SendCommMessage("ChessAck", self:Serialize(ackData), "WHISPER", target)
end

-- Generate a unique game ID
function DeltaChess:GenerateGameId()
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    local uuid = ""
    for i = 1, 16 do
        local idx = math.random(1, #chars)
        uuid = uuid .. chars:sub(idx, idx)
    end
    return string.format("%s_%d_%s", UnitName("player"), time(), uuid)
end

-- Compact challenge serialization (within 255-byte addon message limit)
local function escapeForLua(s)
    return (tostring(s or ""):gsub("\\", "\\\\"):gsub('"', '\\"'))
end

function DeltaChess:SerializeChallenge(gs)
    return string.format('{g="%s",c="%s",o="%s",cc="%s",uc=%s,tm=%d,inc=%d,ct=%d,ccl="%s"}',
        escapeForLua(gs.gameId),
        escapeForLua(gs.challenger),
        escapeForLua(gs.opponent),
        gs.challengerColor or "random",
        tostring(gs.useClock or false),
        gs.timeMinutes or 10,
        gs.incrementSeconds or 0,
        gs.challengerTimestamp or 0,
        escapeForLua(gs.challengerClass))
end

function DeltaChess:DeserializeChallenge(str)
    local ok, result = pcall(function()
        local fn, err = loadstring("return " .. str)
        if not fn then error(err or "parse failed") end
        local t = fn()
        if not t then return nil end
        return {
            gameId = t.g,
            challenger = t.c,
            opponent = t.o,
            challengerColor = t.cc,
            useClock = t.uc,
            timeMinutes = t.tm,
            incrementSeconds = t.inc,
            challengerTimestamp = t.ct,
            challengerClass = t.ccl
        }
    end)
    return ok and result, ok and result or nil
end

-- Send challenge to another player
function DeltaChess:SendChallenge(gameSettings)
    -- Generate game ID upfront so both sides use the same ID
    gameSettings.gameId = self:GenerateGameId()
    -- Include challenger's timestamp for clock sync
    gameSettings.challengerTimestamp = time()
    -- Include challenger's class for color display
    local _, challengerClass = UnitClass("player")
    gameSettings.challengerClass = challengerClass
    
    local data = self:SerializeChallenge(gameSettings)
    
    self:SendCommMessage("ChessChallenge", data, "WHISPER", gameSettings.opponent)
    
    self:Print("Challenge sent to " .. gameSettings.opponent)
    
    -- Store pending challenge
    self.pendingChallenge = gameSettings
end

-- Ping: track pending pings (sender -> { callback, timer })
DeltaChess.pendingPings = {}
DeltaChess.PING_TIMEOUT = 3

-- Reply to ping so others can detect we have the addon (include DND status)
function DeltaChess:ReplyToPing(sender)
    local msg = (self.db.settings.dnd and "PONG:DND") or "PONG"
    self:SendCommMessage("ChessPing", msg, "WHISPER", sender)
end

-- Ping a single player; callback(hasAddon, isDND) after reply or timeout
function DeltaChess:PingPlayer(targetName, callback)
    if not targetName or targetName == "" then
        if callback then callback(false, false) end
        return
    end
    local myName = self:GetFullPlayerName(UnitName("player"))
    if targetName == myName then
        if callback then callback(true, self.db.settings.dnd) end
        return
    end
    if self.pendingPings[targetName] then
        if callback then callback(false, false) end
        return
    end
    self.pendingPings[targetName] = { callback = callback, answered = false }
    self:SendCommMessage("ChessPing", "PING", "WHISPER", targetName)
    C_Timer.After(self.PING_TIMEOUT, function()
        local pending = self.pendingPings[targetName]
        self.pendingPings[targetName] = nil
        if pending and not pending.answered and pending.callback then
            pending.callback(false, false)
        end
    end)
end

-- Ping multiple players; callback(respondedList) after timeout. respondedList = array of { fullName, dnd }.
function DeltaChess:PingPlayers(listOfNames, callback)
    if not listOfNames or #listOfNames == 0 then
        if callback then callback({}) end
        return
    end
    local responded = {}
    local expected = #listOfNames
    local done = 0
    local function checkDone()
        done = done + 1
        if done >= expected and callback then
            callback(responded)
        end
    end
    for _, name in ipairs(listOfNames) do
        self:PingPlayer(name, function(hasAddon, isDND)
            if hasAddon then
                table.insert(responded, { fullName = name, dnd = isDND })
            end
            checkDone()
        end)
    end
end

-- Handle received addon message
function DeltaChess:OnCommReceived(prefix, message, channel, sender)
    if prefix == "ChessPing" then
        if message == "PING" then
            self:ReplyToPing(sender)
        elseif message == "PONG" or message == "PONG:DND" then
            local pending = self.pendingPings[sender]
            self.pendingPings[sender] = nil
            if pending then
                pending.answered = true
                local isDND = (message == "PONG:DND")
                if pending.callback then pending.callback(true, isDND) end
            end
        end
        return
    end
    if prefix == "ChessChallenge" then
        local success, data = self:DeserializeChallenge(message)
        if not success or not data then 
            self:Print("Failed to parse challenge from " .. sender)
            return 
        end
        
        -- Do Not Disturb: auto-decline and do not show popup
        if self.db.settings.dnd then
            local response = { accepted = false }
            self:SendCommMessage("ChessResponse", self:Serialize(response), "WHISPER", sender)
            return
        end
        
        -- Build settings text for popup
        local colorText = data.challengerColor == "white" and "Black" or "White"
        local clockText = data.useClock and "Yes" or "No"
        local timeText = ""
        if data.useClock then
            timeText = string.format("\nTime: %d min + %d sec increment", 
                data.timeMinutes or 10, 
                data.incrementSeconds or 0)
        end
        
        local settingsText = string.format(
            "Your color: %s\nClock: %s%s",
            colorText, clockText, timeText
        )
        
        -- Store challenge data for acceptance
        self.pendingReceivedChallenge = data
        
        -- Play sound to alert player
        PlaySound(SOUNDKIT.READY_CHECK)
        
        StaticPopup_Show("CHESS_CHALLENGE_RECEIVED", sender, settingsText, data)
        
    elseif prefix == "ChessResponse" then
        local success, data = self:Deserialize(message)
        if not success or not data then return end
        
        if data.accepted then
            self:Print(sender .. " accepted your challenge!")
            
            -- Create the game on challenger's side
            if self.pendingChallenge then
                local challengeData = self.pendingChallenge
                local myName = self:GetFullPlayerName(UnitName("player"))
                local _, myClass = UnitClass("player")
                
                -- Determine class info based on colors
                local whiteClass, blackClass
                if challengeData.challengerColor == "white" then
                    whiteClass = myClass
                    blackClass = data.acceptorClass
                else
                    whiteClass = data.acceptorClass
                    blackClass = myClass
                end
                
                local game = {
                    id = data.gameId,
                    white = challengeData.challengerColor == "white" and myName or sender,
                    black = challengeData.challengerColor == "black" and myName or sender,
                    whiteClass = whiteClass,
                    blackClass = blackClass,
                    board = DeltaChess.Board:New(),
                    status = "active",
                    settings = {
                        useClock = challengeData.useClock,
                        timeMinutes = challengeData.timeMinutes,
                        incrementSeconds = challengeData.incrementSeconds
                    },
                    startTime = time(),
                    -- Store timestamps for clock calculation
                    clockData = {
                        challengerTimestamp = challengeData.challengerTimestamp,
                        acceptorTimestamp = data.acceptorTimestamp,
                        gameStartTimestamp = data.acceptorTimestamp, -- Game starts when accepted
                        initialTimeSeconds = (challengeData.timeMinutes or 10) * 60,
                        incrementSeconds = challengeData.incrementSeconds or 0
                    }
                }
                
                -- Save game
                self.db.games[data.gameId] = game
                self.pendingChallenge = nil
                
                -- Open game board
                self:ShowChessBoard(data.gameId)
            end
        else
            self:Print(sender .. " declined your challenge.")
            self.pendingChallenge = nil
        end
        
    elseif prefix == "ChessMove" then
        local success, data = self:Deserialize(message)
        if not success or not data then return end
        
        self:HandleOpponentMove(data, sender)
        
    elseif prefix == "ChessResign" then
        local success, data = self:Deserialize(message)
        if not success or not data then return end
        
        self:HandleResignation(data.gameId, sender)
        
    elseif prefix == "ChessDraw" then
        local success, data = self:Deserialize(message)
        if not success or not data then return end
        
        if data.offer then
            StaticPopup_Show("CHESS_DRAW_OFFER", nil, nil, data.gameId)
        elseif data.accepted then
            self:HandleDrawAccepted(data.gameId)
        else
            self:Print("Your opponent declined the draw offer.")
        end
        
    elseif prefix == "ChessAck" then
        local success, data = self:Deserialize(message)
        if not success or not data then return end
        
        self:HandleAckReceived(data.messageId, sender)
    end
end

-- Handle received acknowledgment
function DeltaChess:HandleAckReceived(messageId, sender)
    -- Find which game this ACK is for
    for gameId, pending in pairs(self.pendingAck) do
        if pending.messageId == messageId then
            -- Apply the move now that it's confirmed
            if pending.messageType == "ChessMove" and pending.moveData then
                self:ApplyConfirmedMove(gameId, pending.moveData)
            end
            
            self:UnlockBoard(gameId)
            return
        end
    end
end

-- Apply move after ACK confirmation
function DeltaChess:ApplyConfirmedMove(gameId, moveData)
    local game = self.db.games[gameId]
    if not game then return end
    
    -- Make the move on the board (timestamp is added automatically)
    game.board:MakeMove(moveData.fromRow, moveData.fromCol, moveData.toRow, moveData.toCol, moveData.promotion)
    
    -- Update UI if board is open
    if DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId then
        DeltaChess.UI:UpdateBoard(DeltaChess.UI.activeFrame)
        
        -- Check for game end
        if game.board.gameStatus ~= "active" then
            DeltaChess.UI:ShowGameEnd(DeltaChess.UI.activeFrame)
        end
    end
    
    -- Play sound
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end

-- Send move that requires confirmation before being applied locally
function DeltaChess:SendMoveWithConfirmation(gameId, fromRow, fromCol, toRow, toCol, promotion)
    local game = self.db.games[gameId]
    if not game then return end
    
    -- Check if already waiting for ACK
    if self:IsBoardLocked(gameId) then
        self:Print("Waiting for previous move to be acknowledged...")
        return false
    end
    
    local opponent = self:GetOpponent(gameId)
    if not opponent then return false end
    
    local moveData = {
        gameId = gameId,
        fromRow = fromRow,
        fromCol = fromCol,
        toRow = toRow,
        toCol = toCol,
        timestamp = time()
    }
    if promotion then
        moveData.promotion = promotion
    end
    
    -- Generate message ID and send
    local messageId = self:GenerateMessageId()
    moveData.messageId = messageId
    
    self:SendCommMessage("ChessMove", self:Serialize(moveData), "WHISPER", opponent)
    
    -- Lock board and store move data (move will be applied when ACK received)
    self:LockBoard(gameId, messageId, "ChessMove", moveData)
    
    return true
end

-- Accept challenge
function DeltaChess:AcceptChallenge(challengeData)
    -- Hide the popup dialog
    StaticPopup_Hide("CHESS_CHALLENGE_RECEIVED")
    
    -- Use the game ID from the challenger (shared ID)
    local gameId = challengeData.gameId or (tostring(time()) .. "_" .. math.random(1000, 9999))
    
    -- Determine colors - swap: if challenger is white, we are black
    local myName = self:GetFullPlayerName(UnitName("player"))
    local myColor = challengeData.challengerColor == "white" and "black" or "white"
    
    -- Acceptor's timestamp and class
    local acceptorTimestamp = time()
    local _, acceptorClass = UnitClass("player")
    
    -- Determine class info based on colors
    local whiteClass, blackClass
    if challengeData.challengerColor == "white" then
        whiteClass = challengeData.challengerClass
        blackClass = acceptorClass
    else
        whiteClass = acceptorClass
        blackClass = challengeData.challengerClass
    end
    
    -- Create game with timestamp-based clock tracking
    local game = {
        id = gameId,
        white = challengeData.challengerColor == "white" and challengeData.challenger or myName,
        black = challengeData.challengerColor == "black" and challengeData.challenger or myName,
        whiteClass = whiteClass,
        blackClass = blackClass,
        board = DeltaChess.Board:New(),
        status = "active",
        settings = {
            useClock = challengeData.useClock,
            timeMinutes = challengeData.timeMinutes,
            incrementSeconds = challengeData.incrementSeconds
        },
        startTime = time(),
        -- Store timestamps for clock calculation
        clockData = {
            challengerTimestamp = challengeData.challengerTimestamp,
            acceptorTimestamp = acceptorTimestamp,
            gameStartTimestamp = acceptorTimestamp, -- Game starts when accepted
            initialTimeSeconds = (challengeData.timeMinutes or 10) * 60,
            incrementSeconds = challengeData.incrementSeconds or 0
        }
    }
    
    -- Save game
    self.db.games[gameId] = game
    
    -- Send response with the same game ID, our timestamp, and our class
    local response = {
        accepted = true,
        gameId = gameId,
        acceptorTimestamp = acceptorTimestamp,
        acceptorClass = acceptorClass
    }
    
    self:SendCommMessage("ChessResponse", self:Serialize(response), "WHISPER", challengeData.challenger)
    
    -- Open game board
    self:ShowChessBoard(gameId)
end

-- Decline challenge
function DeltaChess:DeclineChallenge(challengeData)
    -- Hide the popup dialog
    StaticPopup_Hide("CHESS_CHALLENGE_RECEIVED")
    
    local response = {
        accepted = false
    }
    
    self:SendCommMessage("ChessResponse", self:Serialize(response), "WHISPER", challengeData.challenger)
    
    self:Print("Challenge declined.")
end

-- Start game (for challenger)
function DeltaChess:StartGame(gameId)
    self:ShowChessBoard(gameId)
end

-- Send move to opponent
function DeltaChess:SendMove(gameId, fromRow, fromCol, toRow, toCol)
    local game = self.db.games[gameId]
    if not game then return end
    
    -- Don't send moves in computer games
    if game.isVsComputer then return end
    
    -- Check if already waiting for ACK
    if self:IsBoardLocked(gameId) then
        self:Print("Waiting for previous move to be acknowledged...")
        return false
    end
    
    local opponent = self:GetOpponent(gameId)
    if not opponent then return end
    
    local moveData = {
        gameId = gameId,
        fromRow = fromRow,
        fromCol = fromCol,
        toRow = toRow,
        toCol = toCol,
        timestamp = time()
    }
    
    -- Send with ACK requirement
    self:SendWithAck("ChessMove", moveData, opponent, gameId)
    
    return true
end

-- Handle opponent's move
function DeltaChess:HandleOpponentMove(moveData, sender)
    local game = self.db.games[moveData.gameId]
    if not game then return end
    
    -- Send acknowledgment first
    if moveData.messageId and sender then
        self:SendAck(moveData.messageId, sender)
    end
    
    -- Make the move on our board (timestamp is added automatically)
    game.board:MakeMove(moveData.fromRow, moveData.fromCol, moveData.toRow, moveData.toCol, moveData.promotion)
    
    -- Notify with opponent name and move
    local opponentName = sender:match("^([^%-]+)") or sender
    local lastMove = game.board.moves[#game.board.moves]
    local moveNotation = lastMove and DeltaChess.UI:FormatMoveAlgebraic(lastMove) or ""
    if moveNotation ~= "" then
        self:Print(opponentName .. " played " .. moveNotation .. " - it's your turn!")
    else
        self:Print(opponentName .. " made their move - it's your turn!")
    end

    -- Update UI if board is open
    if DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == moveData.gameId then
        DeltaChess.UI:UpdateBoard(DeltaChess.UI.activeFrame)
    end

    -- Update minimap "your turn" highlight
    if DeltaChess.Minimap and DeltaChess.Minimap.UpdateYourTurnHighlight then
        DeltaChess.Minimap:UpdateYourTurnHighlight()
    end
    
    -- Play sound
    PlaySound(SOUNDKIT.ACHIEVEMENT_MENU_OPEN)
end

-- Resign game
function DeltaChess:ResignGame(gameId)
    local game = self.db.games[gameId]
    if not game then return end
    
    -- Update game status
    game.status = "ended"
    game.board.gameStatus = "resignation"
    game.resignedPlayer = self:GetFullPlayerName(UnitName("player"))
    game.endTime = time()
    
    -- Send resignation to opponent (skip for computer games)
    if not game.isVsComputer then
        local opponent = self:GetOpponent(gameId)
        if opponent then
            local data = {gameId = gameId}
            self:SendCommMessage("ChessResign", self:Serialize(data), "WHISPER", opponent)
        end
    end
    
    -- Save to history
    self:SaveGameToHistory(game, "resigned")
    
    -- Update UI
    if DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId then
        DeltaChess.UI:UpdateBoard(DeltaChess.UI.activeFrame)
    end
    
    self:Print("You resigned.")
end

-- Handle opponent resignation
function DeltaChess:HandleResignation(gameId, opponent)
    local game = self.db.games[gameId]
    if not game then return end
    
    game.status = "ended"
    game.board.gameStatus = "resignation"
    game.resignedPlayer = opponent
    game.endTime = time()
    
    -- Save to history
    self:SaveGameToHistory(game, "won")
    
    -- Update UI
    if DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId then
        DeltaChess.UI:UpdateBoard(DeltaChess.UI.activeFrame)
    end
    
    self:Print(opponent .. " resigned. You win!")
end

-- Offer draw
function DeltaChess:OfferDraw(gameId)
    local game = self.db.games[gameId]
    if not game then return end
    
    local opponent = self:GetOpponent(gameId)
    if not opponent then return end
    
    local data = {
        gameId = gameId,
        offer = true
    }
    
    self:SendCommMessage("ChessDraw", self:Serialize(data), "WHISPER", opponent)
    self:Print("Draw offer sent.")
end

-- Accept draw
function DeltaChess:AcceptDraw(gameId)
    local game = self.db.games[gameId]
    if not game then return end
    
    local opponent = self:GetOpponent(gameId)
    if not opponent then return end
    
    -- Update game status
    game.status = "ended"
    game.board.gameStatus = "draw"
    game.endTime = time()
    
    -- Send acceptance
    local data = {
        gameId = gameId,
        accepted = true
    }
    
    self:SendCommMessage("ChessDraw", self:Serialize(data), "WHISPER", opponent)
    
    -- Save to history
    self:SaveGameToHistory(game, "draw")
    
    -- Update UI
    if DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId then
        DeltaChess.UI:UpdateBoard(DeltaChess.UI.activeFrame)
    end
    
    self:Print("Draw accepted.")
end

-- Decline draw
function DeltaChess:DeclineDraw(gameId)
    local game = self.db.games[gameId]
    if not game then return end
    
    local opponent = self:GetOpponent(gameId)
    if not opponent then return end
    
    local data = {
        gameId = gameId,
        accepted = false
    }
    
    self:SendCommMessage("ChessDraw", self:Serialize(data), "WHISPER", opponent)
end

-- Handle draw accepted
function DeltaChess:HandleDrawAccepted(gameId)
    local game = self.db.games[gameId]
    if not game then return end
    
    game.status = "ended"
    game.board.gameStatus = "draw"
    game.endTime = time()
    
    -- Save to history
    self:SaveGameToHistory(game, "draw")
    
    -- Update UI
    if DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId then
        DeltaChess.UI:UpdateBoard(DeltaChess.UI.activeFrame)
    end
    
    self:Print("Draw accepted by opponent.")
end

-- Handle timeout
function DeltaChess:TimeOut(gameId, color)
    local game = self.db.games[gameId]
    if not game then return end
    
    game.status = "ended"
    game.board.gameStatus = "timeout"
    game.timeoutPlayer = color == "white" and game.white or game.black
    game.endTime = time()
    
    -- Determine result for this player
    local myColor = self:GetMyColor(gameId)
    local result = myColor == color and "lost" or "won"
    
    -- Save to history
    self:SaveGameToHistory(game, result)
    
    -- Update UI
    if DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId then
        DeltaChess.UI:UpdateBoard(DeltaChess.UI.activeFrame)
    end
end

-- Get opponent name
function DeltaChess:GetOpponent(gameId)
    local game = self.db.games[gameId]
    if not game then return nil end
    
    local myName = self:GetFullPlayerName(UnitName("player"))
    
    if game.white == myName then
        return game.black
    elseif game.black == myName then
        return game.white
    end
    
    return nil
end

-- Get player's color in game
function DeltaChess:GetMyColor(gameId)
    local game = self.db.games[gameId]
    if not game then return nil end
    
    local myName = self:GetFullPlayerName(UnitName("player"))
    
    if game.white == myName then
        return "white"
    elseif game.black == myName then
        return "black"
    end
    
    return nil
end

-- Simple serialization
function DeltaChess:Serialize(data)
    -- Convert table to string (simple implementation)
    -- In production, use a proper serialization library like AceSerializer
    return self:TableToString(data)
end

function DeltaChess:Deserialize(str)
    -- Convert string back to table
    -- In production, use a proper deserialization library
    local success, data = pcall(function() return self:StringToTable(str) end)
    return success, data
end

function DeltaChess:TableToString(tbl)
    local result = "{"
    for k, v in pairs(tbl) do
        local key = type(k) == "string" and string.format("%q", k) or tostring(k)
        local value
        if type(v) == "table" then
            value = self:TableToString(v)
        elseif type(v) == "string" then
            value = string.format("%q", v)
        else
            value = tostring(v)
        end
        result = result .. "[" .. key .. "]=" .. value .. ","
    end
    result = result .. "}"
    return result
end

function DeltaChess:StringToTable(str)
    -- Use loadstring (deprecated) or load depending on Lua version
    local func, err
    if loadstring then
        func, err = loadstring("return " .. str)
    else
        func, err = load("return " .. str)
    end
    
    if func then
        local success, result = pcall(func)
        if success then
            return result
        end
    end
    return nil
end
