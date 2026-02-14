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

-- Send addon message with automatic BattleTag resolution (always uses WHISPER)
function DeltaChess:SendCommMessage(prefix, message, target, noBNet)
    if not target then return false end
    
    -- Use Bnet module to handle BattleTag resolution
    return DeltaChess.Bnet:SendMessage(prefix, message, target, noBNet)
end

-- Send message that requires acknowledgment
function DeltaChess:SendWithAck(prefix, data, target, gameId)
    local messageId = self:GenerateMessageId()
    data.messageId = messageId
    
    self:SendCommMessage(prefix, self:Serialize(data), target)
    self:LockBoard(gameId, messageId, prefix, data)
    
    return messageId
end

-- Send acknowledgment
function DeltaChess:SendAck(messageId, target)
    local ackData = {
        messageId = messageId,
        ackType = "ACK"
    }
    self:SendCommMessage("ChessAck", self:Serialize(ackData), target)
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

-- Compact challenge serialization using JSON with shorthand keys (within 255-byte addon message limit)
function DeltaChess:SerializeChallenge(gs)
    local data = {
        g = gs.gameId,
        cc = gs.challengerColor or "random",
        uc = gs.useClock or false,
        tm = gs.timeMinutes or 10,
        inc = gs.incrementSeconds or 0,
        ct = gs.challengerTimestamp or 0,
        ccl = gs.challengerClass,
        hsec = gs.handicapSeconds,
        hs = (gs.handicapSide == "white" or gs.handicapSide == "black") and gs.handicapSide or nil,
        ir = gs.isRandom or false
    }
    local json, err = DeltaChess.Util.SerializeJSON(data)
    return json or ""
end

function DeltaChess:DeserializeChallenge(str)
    if not str or str == "" then return nil, nil end
    local data, err = DeltaChess.Util.DeserializeJSON(str)
    if not data then return nil, nil end
    -- Map shorthand keys back to full property names
    local result = {
        gameId = data.g,
        -- challenger and opponent are set from sender/receiver in OnCommReceived
        challengerColor = data.cc,
        useClock = data.uc,
        timeMinutes = data.tm,
        incrementSeconds = data.inc,
        challengerTimestamp = data.ct,
        challengerClass = data.ccl,
        handicapSeconds = data.hsec,
        handicapSide = (data.hs == "white" or data.hs == "black") and data.hs or nil,
        isRandom = data.ir or false
    }
    return result, result
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
    
    -- If opponent BattleTag was provided (from friends list or detected), include it
    -- If not provided, check if opponent character is a BattleNet friend
    if not gameSettings.opponentBattleTag then
        local battleTag = DeltaChess.Bnet:GetBattleTagForCharacter(gameSettings.opponent)
        if battleTag then
            gameSettings.opponentBattleTag = battleTag
        end
    end
    
    local data = self:SerializeChallenge(gameSettings)
    
    -- Send message (SendCommMessage handles BattleTag resolution automatically)
    local success = self:SendCommMessage("ChessChallenge", data, gameSettings.opponent)
    
    if not success then
        self:Print("|cFFFF0000Failed to send challenge - opponent may be offline.|r")
        return
    end
    
    local displayName = gameSettings.opponentBattleTag or gameSettings.opponent
    self:Print("Challenge sent to " .. displayName)
    
    -- Store pending challenge
    self.pendingChallenge = gameSettings
end

-- Ping: track pending pings (sender -> { callback, timer })
DeltaChess.pendingPings = {}
DeltaChess.PING_TIMEOUT = 3

-- Reply to ping so others can detect we have the addon (include DND status)
function DeltaChess:ReplyToPing(sender)
    local msg = (self.db.settings.dnd and "PONG:DND") or "PONG"
    self:SendCommMessage("ChessPing", msg, sender)
end

-- Ping a single player; callback(hasAddon, isDND) after reply or timeout
-- @param targetName string Target (BattleTag or CharName-Realm)
-- @param callback function Callback(hasAddon, isDND)
-- @param noBNet boolean Optional: if true, skip BNet whispers (prevents cross-project pings)
function DeltaChess:PingPlayer(targetName, callback, noBNet)
    if not targetName or targetName == "" then
        if callback then callback(false, false) end
        return
    end
    local myCharName, myName = self:GetLocalPlayerInfo()
    if targetName == myCharName or targetName == myName then
        if callback then callback(true, self.db.settings.dnd) end
        return
    end
    
    if self.pendingPings[targetName] then
        if callback then callback(false, false) end
        return
    end
    
    -- Store pending ping with original target (BattleTag or character name)
    -- For BattleTags, responses may come back via BNet whisper with BattleTag as sender
    -- For character names, responses come back with character name as sender
    self.pendingPings[targetName] = { callback = callback, answered = false }
    
    -- If target is a BattleTag and friend is on same project, also track by character name
    -- (in case response comes back via addon message with character name)
    if targetName:find("#") then
        local currentChar = DeltaChess.Bnet:GetCurrentCharacterForBattleTag(targetName)
        if currentChar then
            self.pendingPings[currentChar] = { callback = callback, answered = false, battleTag = targetName }
        end
    end
    
    -- SendCommMessage handles BattleTag resolution and cross-project communication automatically
    local success = self:SendCommMessage("ChessPing", "PING", targetName, noBNet)
    if not success then
        -- Failed to send (friend offline)
        self.pendingPings[targetName] = nil
        if callback then callback(false, false) end
        return
    end
    
    C_Timer.After(self.PING_TIMEOUT, function()
        local pending = self.pendingPings[targetName]
        self.pendingPings[targetName] = nil
        if pending and not pending.answered and pending.callback then
            pending.callback(false, false)
        end
    end)
end

-- Ping multiple players; callback(respondedList) after timeout. respondedList = array of { fullName, dnd }.
-- @param listOfNames table Array of player names (BattleTag or CharName-Realm)
-- @param callback function Callback(respondedList)
-- @param noBNet boolean Optional: if true, skip BNet whispers (prevents cross-project pings)
function DeltaChess:PingPlayers(listOfNames, callback, noBNet)
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
        end, noBNet)
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
            
            -- If this was a response to a BattleTag ping, also clear the BattleTag entry
            if pending and pending.battleTag then
                self.pendingPings[pending.battleTag] = nil
            end
            
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
        
        -- Set challenger from sender (BattleTag or character name)
        data.challenger = sender
        
        -- Set opponent from local player info (use BattleTag if available)
        local myCharName, myName = self:GetLocalPlayerInfo()
        data.opponent = myName
        
        -- Do Not Disturb: auto-decline and do not show popup
        if self.db.settings.dnd then
            local response = { accepted = false }
            self:SendCommMessage("ChessResponse", self:Serialize(response), sender)
            return
        end
        
        -- Build class-colored challenger display name (show full name with realm)
        local challengerDisplay = data.challenger
        if data.challengerClass and RAID_CLASS_COLORS and RAID_CLASS_COLORS[data.challengerClass] then
            local cc = RAID_CLASS_COLORS[data.challengerClass]
            local hex = string.format("FF%02x%02x%02x", cc.r * 255, cc.g * 255, cc.b * 255)
            challengerDisplay = "|c" .. hex .. challengerDisplay .. "|r"
        end
        
        -- Build structured settings text for popup
        -- Side assignment
        local yourSide = data.challengerColor == COLOR.WHITE and "Black" or "White"
        local sideText
        if data.isRandom then
            sideText = string.format("|cFFFFD100Your Side:|r  %s  |cFF888888(randomly assigned)|r", yourSide)
        else
            sideText = string.format("|cFFFFD100Your Side:|r  %s", yourSide)
        end
        
        -- Clock section
        local clockText
        if data.useClock then
            local timeMin = data.timeMinutes or 10
            local incSec = data.incrementSeconds or 0
            if incSec > 0 then
                clockText = string.format("|cFFFFD100Clock:|r  %d min  |cFF888888+%ds/move|r", timeMin, incSec)
            else
                clockText = string.format("|cFFFFD100Clock:|r  %d min  |cFF888888(no increment)|r", timeMin)
            end
        else
            clockText = "|cFFFFD100Clock:|r  None"
        end
        
        -- Handicap section
        local handicapText = ""
        if data.handicapSeconds and data.handicapSide then
            local side = data.handicapSide == "white" and "White" or "Black"
            handicapText = string.format("\n|cFFFFD100Handicap:|r  %s gets %ds less", side, data.handicapSeconds)
        end
        
        local settingsText = string.format("%s\n%s%s", sideText, clockText, handicapText)
        
        -- Store challenge data for acceptance
        self.pendingReceivedChallenge = data
        
        -- Play sound to alert player
        DeltaChess.Sound:PlayChallengeReceived()
        
        StaticPopup_Show("CHESS_CHALLENGE_RECEIVED", challengerDisplay, settingsText, data)
        
    elseif prefix == "ChessResponse" then
        local success, data = self:Deserialize(message)
        if not success or not data then return end
        
        if data.accepted then
            self:Print(sender .. " accepted your challenge!")
            DeltaChess.Sound:PlayChallengeAccepted()
            
            -- Create the game on challenger's side
            if self.pendingChallenge then
                local challengeData = self.pendingChallenge
                local myCharName, myName = self:GetLocalPlayerInfo()
                local _, myClass = UnitClass("player")
                
                -- Determine names and classes based on colors
                local whiteName, blackName, whiteClass, blackClass
                if challengeData.challengerColor == COLOR.WHITE then
                    whiteName = myName
                    blackName = sender
                    whiteClass = myClass
                    blackClass = data.acceptorClass
                else
                    whiteName = sender
                    blackName = myName
                    whiteClass = data.acceptorClass
                    blackClass = myClass
                end
                
                -- Create board with names
                local extraMeta = {
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
                
                -- Create board with all metadata
                local board = DeltaChess.CreateGameBoard(
                    data.gameId,
                    whiteName,
                    blackName,
                    {  -- settings
                        useClock = challengeData.useClock,
                        timeMinutes = challengeData.timeMinutes,
                        incrementSeconds = challengeData.incrementSeconds
                    },
                    extraMeta
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
            local board = self:GetBoard(data.gameId)
            if board and board:IsThreefoldRepetitionDrawPossible() then
                -- Threefold repetition: accept draw immediately without asking
                self:AcceptDraw(data.gameId)
            else
                DeltaChess.UI:ShowGamePopup(data.gameId, "CHESS_DRAW_OFFER", nil, data.gameId)
            end
        elseif data.accepted then
            self:HandleDrawAccepted(data.gameId)
        else
            self:Print("Your opponent declined the remis offer.")
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

--- Handle BattleNet whisper messages (cross-project communication)
-- Event args for CHAT_MSG_BN_WHISPER: text, playerName, languageName, channelName, playerName2, specialFlags, zoneChannelID, channelIndex, channelBaseName, languageID, lineID, guid, bnSenderID, ...
function DeltaChess:OnBNetWhisperReceived(...)
    -- Extract the relevant arguments from CHAT_MSG_BN_WHISPER
    local text, playerName, languageName, channelName, playerName2, specialFlags, zoneChannelID, channelIndex, channelBaseName, languageID, lineID, guid, bnSenderID = ...
    if not text or not bnSenderID then
        return
    end
    
    -- Check if this is a DeltaChess encoded message
    if not text:match("^DeltaChess:") then
        return
    end
    
    -- Try to decode as DeltaChess message
    local decodedPrefix, decodedMessage, senderBattleTag = DeltaChess.Bnet:HandleBNetWhisper(bnSenderID, text)
    if not decodedPrefix or not decodedMessage or not senderBattleTag then
        return
    end
    
    -- Treat the decoded message as if it came via normal addon channel
    -- Use BattleTag as sender for all internal processing
    self:OnCommReceived(decodedPrefix, decodedMessage, "BN_WHISPER", senderBattleTag)
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
    end
    
    -- Check for game end (show dialog even if board window is closed)
    if board:IsEnded() then
        local frame = (DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId) and DeltaChess.UI.activeFrame or nil
        DeltaChess.UI:ShowGameEnd(gameId, frame)
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
    
    -- Block moves while the game is paused
    if board:IsPaused() then
        self:Print("Game is paused!")
        return false
    end
    
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
    
    self:SendCommMessage("ChessMove", self:Serialize(moveData), opponent)
    
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
    local myCharName, myName = self:GetLocalPlayerInfo()
    local myColor = challengeData.challengerColor == COLOR.WHITE and COLOR.BLACK or COLOR.WHITE
    
    -- Acceptor's timestamp and class
    local acceptorTimestamp = DeltaChess.Util.TimeNow()
    local _, acceptorClass = UnitClass("player")

    -- Determine names and classes based on colors
    -- challengeData.challenger is already the sender (BattleTag or character name)
    local whiteName, blackName, whiteClass, blackClass
    if challengeData.challengerColor == COLOR.WHITE then
        whiteName = challengeData.challenger
        blackName = myName
        whiteClass = challengeData.challengerClass
        blackClass = acceptorClass
    else
        whiteName = myName
        blackName = challengeData.challenger
        whiteClass = acceptorClass
        blackClass = challengeData.challengerClass
    end
    
    -- Create board with names
    local extraMeta = {
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
    
    local board = DeltaChess.CreateGameBoard(
        gameId,
        whiteName,
        blackName,
        {  -- settings
            useClock = challengeData.useClock,
            timeMinutes = challengeData.timeMinutes,
            incrementSeconds = challengeData.incrementSeconds
        },
        extraMeta
    )
    
    -- Store board directly
    DeltaChess.StoreBoard(gameId, board)
    
    -- Play sound for accepting challenge
    DeltaChess.Sound:PlayChallengeAccepted()

    -- Send response with the same game ID, our timestamp, class, and BattleTag
    local response = {
        accepted = true,
        gameId = gameId,
        acceptorTimestamp = acceptorTimestamp,
        acceptorClass = acceptorClass
    }

    -- Send response (target can be BattleTag or character name)
    self:SendCommMessage("ChessResponse", self:Serialize(response), challengeData.challenger)
    
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
    
    self:SendCommMessage("ChessResponse", self:Serialize(response), challengeData.challenger)
    
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
    
    -- Reject the move if the game is paused
    if board:IsPaused() then return end
    
    board:MakeMoveUci(moveData.uci, { timestamp = moveData.timestamp or DeltaChess.Util.TimeNow() })
    
    -- Play sound for opponent's move
    local lastMove = board:GetLastMove()
    local wasCapture = lastMove and lastMove:IsCapture()
    DeltaChess.Sound:PlayMoveSound(board, false, wasCapture, board)
    
    -- Update UI if board is open
    if DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == moveData.gameId then
        DeltaChess.UI:UpdateBoardAnimated(DeltaChess.UI.activeFrame, false)
    end
    
    -- Check for game end (show dialog even if board window is closed)
    if board:IsEnded() then
        local frame = (DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == moveData.gameId) and DeltaChess.UI.activeFrame or nil
        DeltaChess.UI:ShowGameEnd(moveData.gameId, frame)
        return
    end
    
    DeltaChess:NotifyItIsYourTurn(moveData.gameId, sender)
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
        if not board:GetStartTime() then
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
            self:SendCommMessage("ChessResign", self:Serialize(data), opponent)
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
    
    -- Update UI
    if DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId then
        DeltaChess.UI:UpdateBoard(DeltaChess.UI.activeFrame)
    end
    
    -- Save to history
    self:SaveGameToHistory(board)
    
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
    
    self:SendCommMessage("ChessDraw", self:Serialize(data), opponent)
    self:Print("Remis offer sent.")
end

-- Accept draw
function DeltaChess:AcceptDraw(gameId)
    local board = DeltaChess.GetBoard(gameId)
    if not board then return end
    
    local opponent = self:GetOpponent(gameId)
    if not opponent then return end
    
    -- Update game status (end reason derived from position, e.g. threefold if applicable)
    board:EndGame()

    -- Send acceptance
    local data = {
        gameId = gameId,
        accepted = true
    }
    
    self:SendCommMessage("ChessDraw", self:Serialize(data), opponent)
    
    -- Show game end (handles UI update, sound, and saving to history)
    local frame = (DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId) and DeltaChess.UI.activeFrame or nil
    DeltaChess.UI:ShowGameEnd(gameId, frame)
    
    self:Print("Remis accepted.")
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
    
    self:SendCommMessage("ChessDraw", self:Serialize(data), opponent)
end

-- Handle draw accepted
function DeltaChess:HandleDrawAccepted(gameId)
    local board = DeltaChess.GetBoard(gameId)
    if not board then return end
    
    board:EndGame()

    -- Show game end (handles UI update, sound, and saving to history)
    local frame = (DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId) and DeltaChess.UI.activeFrame or nil
    DeltaChess.UI:ShowGameEnd(gameId, frame)
    
    self:Print("Remis accepted by opponent.")
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
    if not board or board:OneOpponentIsEngine() or not board:IsActive() then return end
    local opponent = self:GetOpponent(gameId)
    if not opponent then return end
    self:SendCommMessage("ChessPause", self:Serialize({ gameId = gameId, accepted = nil }), opponent)
    self:Print("Pause request sent to opponent.")
end

-- Send pause response (accept/decline)
function DeltaChess:SendPauseResponse(gameId, accepted)
    local board = DeltaChess.GetBoard(gameId)
    if not board then return end
    local opponent = self:GetOpponent(gameId)
    if not opponent then return end
    self:SendCommMessage("ChessPause", self:Serialize({ gameId = gameId, accepted = accepted }), opponent)
end

-- Handle pause request/response
function DeltaChess:HandlePauseRequest(data)
    local gameId, sender = data.gameId, data.sender
    local board = DeltaChess.GetBoard(gameId)
    if not board or board:OneOpponentIsEngine() or not board:IsActive() then return end
    if data.accepted == nil then
        DeltaChess.UI:ShowGamePopup(gameId, "CHESS_PAUSE_REQUEST", nil, { gameId = gameId, sender = sender })
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
    if not board or board:OneOpponentIsEngine() or not board:IsPaused() then return end
    local opponent = self:GetOpponent(gameId)
    if not opponent then return end
    self:SendCommMessage("ChessUnpause", self:Serialize({ gameId = gameId, accepted = nil }), opponent)
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
    self:SendCommMessage("ChessUnpause", self:Serialize(payload), opponent)
end

-- Handle unpause request/response
function DeltaChess:HandleUnpauseRequest(data)
    local gameId, sender = data.gameId, data.sender
    local board = DeltaChess.GetBoard(gameId)
    if not board or board:OneOpponentIsEngine() or not board:IsPaused() then return end
    if data.accepted == nil then
        DeltaChess.UI:ShowGamePopup(gameId, "CHESS_UNPAUSE_REQUEST", nil, { gameId = gameId, sender = sender })
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

-- Get opponent target for messaging (BattleTag for BNet friends, CharName-Realm for regular players)
-- SendCommMessage will handle BattleTag resolution automatically
function DeltaChess:GetOpponent(gameId)
    local board = DeltaChess.GetBoard(gameId)
    if not board then return nil end
    
    local myCharName, myName = self:GetLocalPlayerInfo()
    local white = board:GetWhitePlayerName()
    local black = board:GetBlackPlayerName()
    
    -- Determine opponent name (BattleTag or character name)
    -- Check against both character name and BattleTag
    if black == myCharName or black == myName then
        return white
    elseif white == myCharName or white == myName then
        return black
    end
    
    return nil
end

-- Get player's color in game
function DeltaChess:GetMyColor(gameId)
    local board = DeltaChess.GetBoard(gameId)
    if not board then return nil end
    
    local myCharName, myName = self:GetLocalPlayerInfo()
    local white = board:GetWhitePlayerName()
    local black = board:GetBlackPlayerName()
    
    if white == myCharName or white == myName then
        return COLOR.WHITE
    elseif black == myCharName or black == myName then
        return COLOR.BLACK
    end
    
    return nil
end

-- JSON serialization using DeltaChess.Util
function DeltaChess:Serialize(data)
    local json, err = DeltaChess.Util.SerializeJSON(data)
    return json
end

function DeltaChess:Deserialize(str)
    if not str or str == "" then return false, nil end
    local data, err = DeltaChess.Util.DeserializeJSON(str)
    if data then
        return true, data
    else
        return false, nil
    end
end

