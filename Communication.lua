-- Communication.lua - Network communication between players

local COLOR = DeltaChess.Constants.COLOR
local STATUS = {
    ACTIVE = DeltaChess.Constants.STATUS_ACTIVE,
    PAUSED = DeltaChess.Constants.STATUS_PAUSED,
    ENDED = DeltaChess.Constants.STATUS_ENDED,
}

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
        timestamp = DeltaChess.Util.TimeNow()
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
    return string.format("%s_%d_%d", UnitName("player"), DeltaChess.Util.TimeNow(), self.messageIdCounter)
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
    return string.format("%s_%d_%s", UnitName("player"), DeltaChess.Util.TimeNow(), uuid)
end

-- Compact challenge serialization (within 255-byte addon message limit)
local function escapeForLua(s)
    return (tostring(s or ""):gsub("\\", "\\\\"):gsub('"', '\\"'))
end

function DeltaChess:SerializeChallenge(gs)
    return string.format('{g="%s",c="%s",o="%s",cc="%s",uc=%s,tm=%d,inc=%d,ct=%d,ccl="%s",hsec=%s,hs="%s"}',
        escapeForLua(gs.gameId),
        escapeForLua(gs.challenger),
        escapeForLua(gs.opponent),
        gs.challengerColor or "random",
        tostring(gs.useClock or false),
        gs.timeMinutes or 10,
        gs.incrementSeconds or 0,
        gs.challengerTimestamp or 0,
        escapeForLua(gs.challengerClass),
        gs.handicapSeconds and tostring(gs.handicapSeconds) or "nil",
        (gs.handicapSide == "white" or gs.handicapSide == "black") and gs.handicapSide or "")
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
            challengerClass = t.ccl,
            handicapSeconds = t.hsec,
            handicapSide = (t.hs == "white" or t.hs == "black") and t.hs or nil
        }
    end)
    return ok and result, ok and result or nil
end

-- Send challenge to another player
function DeltaChess:SendChallenge(gameSettings)
    -- Generate game ID upfront so both sides use the same ID
    gameSettings.gameId = self:GenerateGameId()
    -- Include challenger's timestamp for clock sync
    gameSettings.challengerTimestamp = DeltaChess.Util.TimeNow()
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
        local colorText = data.challengerColor == COLOR.WHITE and "Black" or "White"
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
        DeltaChess.Sound:PlayChallengeReceived()
        
        StaticPopup_Show("CHESS_CHALLENGE_RECEIVED", sender, settingsText, data)
        
    elseif prefix == "ChessResponse" then
        local success, data = self:Deserialize(message)
        if not success or not data then return end
        
        if data.accepted then
            self:Print(sender .. " accepted your challenge!")
            DeltaChess.Sound:PlayChallengeAccepted()
            
            -- Create the game on challenger's side
            if self.pendingChallenge then
                local challengeData = self.pendingChallenge
                local myName = self:GetFullPlayerName(UnitName("player"))
                local _, myClass = UnitClass("player")
                
                -- Determine class info based on colors
                local whiteClass, blackClass
                if challengeData.challengerColor == COLOR.WHITE then
                    whiteClass = myClass
                    blackClass = data.acceptorClass
                else
                    whiteClass = data.acceptorClass
                    blackClass = myClass
                end
                
                -- Create board with all metadata
                local board = DeltaChess.CreateGameBoard(
                    data.gameId,
                    challengeData.challengerColor == COLOR.WHITE and myName or sender,  -- white
                    challengeData.challengerColor == COLOR.BLACK and myName or sender,  -- black
                    {  -- settings
                        useClock = challengeData.useClock,
                        timeMinutes = challengeData.timeMinutes,
                        incrementSeconds = challengeData.incrementSeconds
                    },
                    {  -- extra metadata
                        whiteClass = whiteClass,
                        blackClass = blackClass,
                        clockData = {
                            challengerTimestamp = challengeData.challengerTimestamp,
                            acceptorTimestamp = data.acceptorTimestamp,
                            gameStartTimestamp = data.acceptorTimestamp,
                            initialTimeSeconds = (challengeData.timeMinutes or 10) * 60,
                            incrementSeconds = challengeData.incrementSeconds or 0,
                            handicapSeconds = challengeData.handicapSeconds,
                            handicapSide = challengeData.handicapSide
                        }
                    }
                )
                
                -- Store board directly
                DeltaChess.StoreBoard(data.gameId, board)
                self.pendingChallenge = nil
                
                -- Open game board
                self:ShowChessBoard(data.gameId)
            end
        else
            self:Print(sender .. " declined your challenge.")
            DeltaChess.Sound:PlayChallengeDeclined()
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
    elseif prefix == "ChessPause" then
        local success, data = self:Deserialize(message)
        if not success or not data then return end
        data.sender = sender
        self:HandlePauseRequest(data)
    elseif prefix == "ChessUnpause" then
        local success, data = self:Deserialize(message)
        if not success or not data then return end
        data.sender = sender
        self:HandleUnpauseRequest(data)
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
    local board = DeltaChess.GetBoard(gameId)
    if not board then return end
    
    board:MakeMoveUci(moveData.uci, { timestamp = moveData.timestamp or DeltaChess.Util.TimeNow() })
    
    -- Update UI if board is open (with animation for the player's move)
    if DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId then
        DeltaChess.UI:UpdateBoardAnimated(DeltaChess.UI.activeFrame, true)
        
        -- Check for game end
        if DeltaChess.GetGameStatus(board) ~= STATUS.ACTIVE then
            DeltaChess.UI:ShowGameEnd(DeltaChess.UI.activeFrame)
        end
    end
    
    -- Play sound based on move type (player's own move)
    local lastMove = board:GetLastMove()
    local wasCapture = lastMove and lastMove:IsCapture()
    DeltaChess.Sound:PlayMoveSound(board, true, wasCapture, board)
end

-- Send move that requires confirmation before being applied locally
-- uci: UCI move string (e.g., "e2e4", "e7e8q")
function DeltaChess:SendMoveWithConfirmation(gameId, uci)
    local board = DeltaChess.GetBoard(gameId)
    if not board then return end
    
    -- Check if already waiting for ACK
    if self:IsBoardLocked(gameId) then
        self:Print("Waiting for previous move to be acknowledged...")
        return false
    end
    
    local opponent = self:GetOpponent(gameId)
    if not opponent then return false end
    
    local moveData = {
        gameId = gameId,
        uci = uci,
        timestamp = DeltaChess.Util.TimeNow()
    }
    
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
    local gameId = challengeData.gameId or (tostring(DeltaChess.Util.TimeNow()) .. "_" .. math.random(1000, 9999))
    
    -- Determine colors - swap: if challenger is white, we are black
    local myName = self:GetFullPlayerName(UnitName("player"))
    local myColor = challengeData.challengerColor == COLOR.WHITE and COLOR.BLACK or COLOR.WHITE
    
    -- Acceptor's timestamp and class
    local acceptorTimestamp = DeltaChess.Util.TimeNow()
    local _, acceptorClass = UnitClass("player")
    
    -- Determine class info based on colors
    local whiteClass, blackClass
    if challengeData.challengerColor == COLOR.WHITE then
        whiteClass = challengeData.challengerClass
        blackClass = acceptorClass
    else
        whiteClass = acceptorClass
        blackClass = challengeData.challengerClass
    end
    
    -- Create board with all metadata
    local board = DeltaChess.CreateGameBoard(
        gameId,
        challengeData.challengerColor == COLOR.WHITE and challengeData.challenger or myName,  -- white
        challengeData.challengerColor == COLOR.BLACK and challengeData.challenger or myName,  -- black
        {  -- settings
            useClock = challengeData.useClock,
            timeMinutes = challengeData.timeMinutes,
            incrementSeconds = challengeData.incrementSeconds
        },
        {  -- extra metadata
            whiteClass = whiteClass,
            blackClass = blackClass,
            clockData = {
                challengerTimestamp = challengeData.challengerTimestamp,
                acceptorTimestamp = acceptorTimestamp,
                gameStartTimestamp = acceptorTimestamp,
                initialTimeSeconds = (challengeData.timeMinutes or 10) * 60,
                incrementSeconds = challengeData.incrementSeconds or 0,
                handicapSeconds = challengeData.handicapSeconds,
                handicapSide = challengeData.handicapSide
            }
        }
    )
    
    -- Store board directly
    DeltaChess.StoreBoard(gameId, board)
    
    -- Play sound for accepting challenge
    DeltaChess.Sound:PlayChallengeAccepted()
    
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
    
    -- Play sound for declining
    DeltaChess.Sound:PlayChallengeDeclined()
    
    self:Print("Challenge declined.")
end

-- Start game (for challenger)
function DeltaChess:StartGame(gameId)
    self:ShowChessBoard(gameId)
end

-- Send move to opponent
-- uci: UCI move string (e.g., "e2e4", "e7e8q")
function DeltaChess:SendMove(gameId, uci)
    local board = DeltaChess.GetBoard(gameId)
    if not board then return end
    
    -- Don't send moves in computer games
    if board:OneOpponentIsEngine() then return end
    
    -- Check if already waiting for ACK
    if self:IsBoardLocked(gameId) then
        self:Print("Waiting for previous move to be acknowledged...")
        return false
    end
    
    local opponent = self:GetOpponent(gameId)
    if not opponent then return end
    
    local moveData = {
        gameId = gameId,
        uci = uci,
        timestamp = DeltaChess.Util.TimeNow()
    }
    
    -- Send with ACK requirement
    self:SendWithAck("ChessMove", moveData, opponent, gameId)
    
    return true
end

-- Handle opponent's move
function DeltaChess:HandleOpponentMove(moveData, sender)
    local board = DeltaChess.GetBoard(moveData.gameId)
    if not board then return end
    
    -- Send acknowledgment first
    if moveData.messageId and sender then
        self:SendAck(moveData.messageId, sender)
    end
    
    board:MakeMoveUci(moveData.uci, { timestamp = moveData.timestamp or DeltaChess.Util.TimeNow() })
    
    -- Play sound for opponent's move
    local lastMove = board:GetLastMove()
    local wasCapture = lastMove and lastMove:IsCapture()
    DeltaChess.Sound:PlayMoveSound(board, false, wasCapture, board)
    
    local opponentName = sender:match("^([^%-]+)") or sender
    DeltaChess:NotifyItIsYourTurn(moveData.gameId, opponentName)
end

-- Restore game from history to active games
function DeltaChess:RestoreGameFromHistory(gameId)
    -- Check if game is already active
    if DeltaChess.GetBoard(gameId) then
        return DeltaChess.GetBoard(gameId)
    end
    
    -- Try to restore from UI frame if available
    if DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId then
        local frame = DeltaChess.UI.activeFrame
        local board = frame.board
        
        -- Ensure board has required metadata
        if not board:GetGameStatus() then
            board:StartGame()
        end
        if not board:GetGameMeta("id") then
            board:SetGameMeta("id", gameId)
        end
        
        -- Restore to active games
        DeltaChess.StoreBoard(gameId, board)
        
        -- Remove from history
        self.db.history[gameId] = nil
        
        return board
    end
    
    return nil
end

-- Take back move(s) vs computer: 1 move if player moved last, 2 if computer moved last.
-- Uses the same snapshot strategy as replay (GetBoardAtIndex).
function DeltaChess:TakeBackMove(gameId)
    local board = DeltaChess.GetBoard(gameId)
    
    -- If game was ended and saved to history, restore it
    if not board then
        board = self:RestoreGameFromHistory(gameId)
    end
    
    if not board or not board:OneOpponentIsEngine() then 
        self:Print("Cannot take back: not a computer game.")
        return 
    end
    
    local moves = board:GetMoveHistory()
    
    if #moves == 0 then
        self:Print("Not enough moves to take back.")
        return
    end
    
    -- Determine who made the last move based on move count and player color
    -- White moves on odd move numbers (1, 3, 5...), Black on even (2, 4, 6...)
    local lastMoveByWhite = (#moves % 2) == 1
    local playerColor = board:GetPlayerColor()
    local playerIsWhite = (playerColor == COLOR.WHITE)
    local playerMovedLast = (lastMoveByWhite == playerIsWhite)
    
    -- If player made the last move (e.g., stalemated computer): take back 1 move
    -- If computer made the last move (e.g., checkmated player): take back 2 moves
    -- This way the player can always try a different move
    local movesToRemove = playerMovedLast and 1 or 2
    movesToRemove = math.min(movesToRemove, #moves)
    local targetIndex = #moves - movesToRemove  -- 1-based: number of moves to keep
    
    -- Get board snapshot at that index (same strategy as replay)
    local newBoard = board:GetBoardAtIndex(targetIndex)
    if not newBoard then
        self:Print("Cannot take back: failed to get board snapshot.")
        return
    end
    
    -- Snapshot is paused (from GetBoardAtIndex); unpause, don't start
    newBoard:StartGame()

    -- Replace the board in storage
    DeltaChess.StoreBoard(gameId, newBoard)
    
    -- Update UI
    if DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId then
        local frame = DeltaChess.UI.activeFrame
        frame.board = newBoard
        frame.gameEndShown = false  -- Allow game end to show again if needed
        frame.selectedSquare = nil   -- Deselect picked piece
        frame.validMoves = {}
        DeltaChess.UI:UpdateBoard(frame)
    end
    
    self:Print("Took back last move.")
end

-- Resign game
function DeltaChess:ResignGame(gameId)
    local board = DeltaChess.GetBoard(gameId)
    if not board then return end
    
    local playerColor = board:GetPlayerColor() or COLOR.WHITE
    board:Resign(playerColor)

    -- Send resignation to opponent (skip for computer games)
    if not board:OneOpponentIsEngine() then
        local opponent = self:GetOpponent(gameId)
        if opponent then
            local data = {gameId = gameId}
            self:SendCommMessage("ChessResign", self:Serialize(data), "WHISPER", opponent)
        end
    end
    
    -- Update UI
    if DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId then
        DeltaChess.UI:UpdateBoard(DeltaChess.UI.activeFrame)
    end

    -- Save to history
    self:SaveGameToHistory(board)

    self:Print("You resigned.")
end

-- Handle opponent resignation
function DeltaChess:HandleResignation(gameId, opponent)
    local board = DeltaChess.GetBoard(gameId)
    if not board then return end
    
    local myColor = board:GetPlayerColor() or COLOR.WHITE
    local resigningColor = (myColor == COLOR.WHITE) and COLOR.BLACK or COLOR.WHITE
    board:Resign(resigningColor)
    
    -- Save to history
    self:SaveGameToHistory(board)
    
    -- Update UI
    if DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId then
        DeltaChess.UI:UpdateBoard(DeltaChess.UI.activeFrame)
    end
    
    self:Print(opponent .. " resigned. You win!")
end

-- Offer draw
function DeltaChess:OfferDraw(gameId)
    local board = DeltaChess.GetBoard(gameId)
    if not board then return end
    
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
    local board = DeltaChess.GetBoard(gameId)
    if not board then return end
    
    local opponent = self:GetOpponent(gameId)
    if not opponent then return end
    
    -- Update game status
    board:EndGame()

    -- Send acceptance
    local data = {
        gameId = gameId,
        accepted = true
    }
    
    self:SendCommMessage("ChessDraw", self:Serialize(data), "WHISPER", opponent)
    
    -- Save to history
    self:SaveGameToHistory(board)
    
    -- Update UI
    if DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId then
        DeltaChess.UI:UpdateBoard(DeltaChess.UI.activeFrame)
    end
    
    self:Print("Draw accepted.")
end

-- Decline draw
function DeltaChess:DeclineDraw(gameId)
    local board = DeltaChess.GetBoard(gameId)
    if not board then return end
    
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
    local board = DeltaChess.GetBoard(gameId)
    if not board then return end
    
    board:EndGame()

    -- Save to history
    self:SaveGameToHistory(board)
    
    -- Update UI
    if DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId then
        DeltaChess.UI:UpdateBoard(DeltaChess.UI.activeFrame)
    end
    
    self:Print("Draw accepted by opponent.")
end

-- Handle timeout
function DeltaChess:TimeOut(gameId, color)
    local board = DeltaChess.GetBoard(gameId)
    if not board then return end
    
    local white = board:GetWhitePlayerName()
    local black = board:GetBlackPlayerName()
    
    board:SetGameMeta("timeoutPlayer", color == COLOR.WHITE and white or black)
    board:EndGame()

    -- Save to history
    self:SaveGameToHistory(board)
    
    -- Update UI
    if DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId then
        DeltaChess.UI:UpdateBoard(DeltaChess.UI.activeFrame)
    end
end

-- Request pause (human vs human)
function DeltaChess:RequestPause(gameId)
    local board = DeltaChess.GetBoard(gameId)
    if not board or board:OneOpponentIsEngine() or board:GetGameStatus() ~= STATUS.ACTIVE then return end
    local opponent = self:GetOpponent(gameId)
    if not opponent then return end
    self:SendCommMessage("ChessPause", self:Serialize({ gameId = gameId, accepted = nil }), "WHISPER", opponent)
    self:Print("Pause request sent to opponent.")
end

-- Send pause response (accept/decline)
function DeltaChess:SendPauseResponse(gameId, accepted)
    local board = DeltaChess.GetBoard(gameId)
    if not board then return end
    local opponent = self:GetOpponent(gameId)
    if not opponent then return end
    self:SendCommMessage("ChessPause", self:Serialize({ gameId = gameId, accepted = accepted }), "WHISPER", opponent)
end

-- Handle pause request/response
function DeltaChess:HandlePauseRequest(data)
    local gameId, sender = data.gameId, data.sender
    local board = DeltaChess.GetBoard(gameId)
    if not board or board:OneOpponentIsEngine() or board:GetGameStatus() ~= STATUS.ACTIVE then return end
    if data.accepted == nil then
        StaticPopup_Show("CHESS_PAUSE_REQUEST", nil, nil, { gameId = gameId, sender = sender })
    else
        if data.accepted then
            board:PauseGame()
            board:SetGameMeta("pauseStartTime", DeltaChess.Util.TimeNow())
            board:SetGameMeta("_lastMoveCountWhenPaused", board:GetHalfMoveCount())
            self:Print("Opponent accepted. Game paused.")
        else
            self:Print("Opponent declined the pause request.")
        end
        if DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId then
            DeltaChess.UI:UpdateBoard(DeltaChess.UI.activeFrame)
        end
    end
end

-- Request unpause (human vs human)
function DeltaChess:RequestUnpause(gameId)
    local board = DeltaChess.GetBoard(gameId)
    if not board or board:OneOpponentIsEngine() or board:GetGameStatus() ~= STATUS.PAUSED then return end
    local opponent = self:GetOpponent(gameId)
    if not opponent then return end
    self:SendCommMessage("ChessUnpause", self:Serialize({ gameId = gameId, accepted = nil }), "WHISPER", opponent)
    self:Print("Unpause request sent to opponent.")
end

-- Send unpause response (caller should add timeSpentClosed before calling if accepting)
function DeltaChess:SendUnpauseResponse(gameId, accepted, timeSpentClosedIncrement)
    local board = DeltaChess.GetBoard(gameId)
    if not board then return end
    local opponent = self:GetOpponent(gameId)
    if not opponent then return end
    local payload = { gameId = gameId, accepted = accepted }
    if accepted and timeSpentClosedIncrement then
        payload.timeSpentClosedIncrement = timeSpentClosedIncrement
    end
    self:SendCommMessage("ChessUnpause", self:Serialize(payload), "WHISPER", opponent)
end

-- Handle unpause request/response
function DeltaChess:HandleUnpauseRequest(data)
    local gameId, sender = data.gameId, data.sender
    local board = DeltaChess.GetBoard(gameId)
    if not board or board:OneOpponentIsEngine() or board:GetGameStatus() ~= STATUS.PAUSED then return end
    if data.accepted == nil then
        StaticPopup_Show("CHESS_UNPAUSE_REQUEST", nil, nil, { gameId = gameId, sender = sender })
    else
        if data.accepted then
            local timeSpentClosed = board:GetGameMeta("timeSpentClosed") or 0
            if data.timeSpentClosedIncrement then
                timeSpentClosed = timeSpentClosed + data.timeSpentClosedIncrement
            else
                local pauseStartTime = board:GetGameMeta("pauseStartTime")
                if pauseStartTime then
                    timeSpentClosed = timeSpentClosed + (DeltaChess.Util.TimeNow() - pauseStartTime)
                end
            end
            board:SetGameMeta("timeSpentClosed", timeSpentClosed)
            board:ContinueGame()
            board:SetGameMeta("pauseStartTime", nil)
            self:Print("Opponent accepted. Game resumed.")
        else
            self:Print("Opponent declined the unpause request.")
        end
        if DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId then
            DeltaChess.UI:UpdateBoard(DeltaChess.UI.activeFrame)
        end
    end
end

-- Get opponent name
function DeltaChess:GetOpponent(gameId)
    local board = DeltaChess.GetBoard(gameId)
    if not board then return nil end
    
    local myName = self:GetFullPlayerName(UnitName("player"))
    local white = board:GetWhitePlayerName()
    local black = board:GetBlackPlayerName()
    
    if white == myName then
        return black
    elseif black == myName then
        return white
    end
    
    return nil
end

-- Get player's color in game
function DeltaChess:GetMyColor(gameId)
    local board = DeltaChess.GetBoard(gameId)
    if not board then return nil end
    
    local myName = self:GetFullPlayerName(UnitName("player"))
    local white = board:GetWhitePlayerName()
    local black = board:GetBlackPlayerName()
    
    if white == myName then
        return COLOR.WHITE
    elseif black == myName then
        return COLOR.BLACK
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
