-- Communication.lua - Games on LibChessMultiplayer.
-- The only pre-1.2 protocol left is NoticeOldClient at the bottom of this file.

local DeltaChess = LibStub("DeltaChess-1.0")
local DeltaChessFramework = LibStub("DeltachessFramework-1.0")

local COLOR = DeltaChessFramework.Constants.COLOR
local REASON = DeltaChessFramework.Constants

local INSTALL_WHISPER = "I want to challenge you to a game of chess but you dont have Delta Chess installed :( Download from Curseforge so that we can play together: https://www.curseforge.com/wow/addons/deltachess"

DeltaChess.pendingAck = {}
DeltaChess.netGames = {}

function DeltaChess:Chess()
    if self.chess then return self.chess end
    local lib = LibStub:GetLibrary("LibChessMultiplayer-1.0", true)
    if not lib then
        self:Print("|cFFFF0000LibChessMultiplayer is not loaded.|r")
        return nil
    end
    local chess, err = lib:New({
        name = "DeltaChess",
        version = self.version or "1.2.0",
        options = { "clock", "draw", "pause" },
    })
    if not chess then
        self:Print("|cFFFF0000" .. tostring(err or "Could not start multiplayer.") .. "|r")
        return nil
    end
    self.chess = chess
    self.netGames = self.netGames or {}
    self:BindChess(chess)
    return chess
end

function DeltaChess:IsBoardLocked(gameId)
    return self.pendingAck[gameId] ~= nil
end

function DeltaChess:LockBoard(gameId)
    self.pendingAck[gameId] = true
    if DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId then
        DeltaChess.UI:ShowWaitingOverlay(DeltaChess.UI.activeFrame, true)
    end
end

function DeltaChess:UnlockBoard(gameId)
    self.pendingAck[gameId] = nil
    if DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId then
        DeltaChess.UI:ShowWaitingOverlay(DeltaChess.UI.activeFrame, false)
    end
end

function DeltaChess:NetworkGame(gameId)
    return self.netGames and self.netGames[gameId] or nil
end

function DeltaChess:HostColor(game)
    if game.isHost then return game.color end
    return game.opponentColor
end

function DeltaChess:NetworkTimes(game, board)
    if not game.clock then return nil end
    local host = self:HostColor(game)
    local guest = host == COLOR.WHITE and COLOR.BLACK or COLOR.WHITE
    local function minutes(color)
        return (board:TimeLeft(color) or 0) / 60
    end
    local hostMinutes = minutes(host)
    local guestMinutes = minutes(guest)
    local mover = board:GetCurrentTurn()
    local inc = (mover == host) and (game.clock.hostInc or 0) or (game.clock.opponentInc or 0)
    if mover == host then
        hostMinutes = hostMinutes + (inc / 60)
    else
        guestMinutes = guestMinutes + (inc / 60)
    end
    return { hostTime = hostMinutes, opponentTime = guestMinutes }
end

function DeltaChess:SyncNetworkClocks(board, game, times)
    if not times or not game.clock then return end
    local host = self:HostColor(game)
    local guest = host == COLOR.WHITE and COLOR.BLACK or COLOR.WHITE
    local function align(color, minutes)
        if type(minutes) ~= "number" then return end
        local current = board:TimeLeft(color)
        if current == nil then return end
        board:SetClock(color, board:GetClock(color) + (minutes * 60 - current))
    end
    align(host, times.hostTime)
    align(guest, times.opponentTime)
end

function DeltaChess:ShowNetworkEnd(gameId)
    local frame = (DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId) and DeltaChess.UI.activeFrame or nil
    if frame then
        DeltaChess.UI:UpdateBoard(frame)
    end
    DeltaChess.UI:ShowGameEnd(gameId, frame)
    if DeltaChess.Minimap and DeltaChess.Minimap.UpdateYourTurnHighlight then
        DeltaChess.Minimap:UpdateYourTurnHighlight()
    end
end

function DeltaChess:WireResult(board)
    local result = board:GetGameResult()
    if result == COLOR.WHITE or result == "white" then return "1-0" end
    if result == COLOR.BLACK or result == "black" then return "0-1" end
    return "1/2-1/2"
end

function DeltaChess:AnnounceNetworkEnd(game, board)
    if not game or game.over or not board or not board:IsEnded() then return end
    local reason = board:GetEndReason()
    if reason == REASON.REASON_RESIGNATION then return end
    if reason == REASON.REASON_TIMEOUT then
        local winner = board:GetGameResult()
        local loser = (winner == COLOR.WHITE or winner == "white") and COLOR.BLACK or COLOR.WHITE
        game:Flag(loser)
        return
    end
    game:Over(self:WireResult(board), reason or "mate")
end

function DeltaChess:ApplyNetworkResult(game, result, reason)
    local board = DeltaChess.GetBoard(game.id)
    if not board then return end
    if not board:IsEnded() then
        local loser = result == "1-0" and COLOR.BLACK or COLOR.WHITE
        if reason == "flag" or reason == "timeout" then
            board:SetClock(loser, 0)
            board:SetIncrement(loser, 0)
            board:SetGameMeta("timeoutPlayer", loser == COLOR.WHITE and board:GetWhitePlayerName() or board:GetBlackPlayerName())
            if not board:IsEnded() then
                board:EndGame()
            end
        elseif result == "1/2-1/2" then
            board:EndGame()
        else
            board:Resign(loser)
        end
    end
    self.netGames[game.id] = nil
    self:ShowNetworkEnd(game.id)
end

function DeltaChess:ApplyNetworkMove(game, uci, times, fromOpponent)
    local board = DeltaChess.GetBoard(game.id)
    if not board or board:IsPaused() or board:IsEnded() then return false end
    local coords = DeltaChess.UciToCoords(uci)
    if not coords or not DeltaChess.IsLegalMove(board, coords.fromRow, coords.fromCol, coords.toRow, coords.toCol, coords.promotion) then
        return false
    end
    if not board:MakeMoveUci(uci, { timestamp = DeltaChessFramework.Util.TimeNow() }) then
        return false
    end
    if times then self:SyncNetworkClocks(board, game, times) end
    local lastMove = board:GetLastMove()
    local wasCapture = lastMove and lastMove:IsCapture()
    DeltaChess.Sound:PlayMoveSound(board, not fromOpponent, wasCapture, board)
    local frame = DeltaChess.UI.activeFrame
    if frame and frame.gameId == game.id then
        DeltaChess.UI:UpdateBoardAnimated(frame, not fromOpponent)
    end
    if board:IsEnded() then
        self:AnnounceNetworkEnd(game, board)
        self:ShowNetworkEnd(game.id)
        return true
    end
    if fromOpponent then
        local name = (game.player and game.player.DisplayName) and game.player:DisplayName() or "Opponent"
        self:NotifyItIsYourTurn(game.id, name)
    end
    if DeltaChess.Minimap and DeltaChess.Minimap.UpdateYourTurnHighlight then
        DeltaChess.Minimap:UpdateYourTurnHighlight()
    end
    return true
end

function DeltaChess:WatchNetworkClocks()
    if not self.netGames then return end
    for gameId, game in pairs(self.netGames) do
        if game.over then
            self.netGames[gameId] = nil
        else
            local board = DeltaChess.GetBoard(gameId)
            if board and board:IsEnded() then
                self:AnnounceNetworkEnd(game, board)
                self:ShowNetworkEnd(gameId)
                if game.over then self.netGames[gameId] = nil end
            end
        end
    end
end

local function clockText(clock, yourColor)
    if not clock then return "None" end
    local function fmt(mins, inc)
        local shown = (mins == math.floor(mins)) and tostring(math.floor(mins)) or tostring(mins)
        if inc and inc > 0 then
            return shown .. " min +" .. tostring(inc) .. "s"
        end
        return shown .. " min"
    end
    local yours = clock.opponentTime
    local yourInc = clock.opponentInc or 0
    local theirs = clock.hostTime
    local theirInc = clock.hostInc or 0
    if yourColor == nil then
        yours, theirs = theirs, yours
        yourInc, theirInc = theirInc, yourInc
    end
    if yours == theirs and yourInc == theirInc then
        return fmt(yours, yourInc)
    end
    return "You " .. fmt(yours, yourInc) .. ", opponent " .. fmt(theirs, theirInc)
end

function DeltaChess:StartNetworkGame(game)
    local myColor = game.color
    local _, myName = self:GetLocalPlayerInfo()
    local opponent = (game.player and game.player.DisplayName) and game.player:DisplayName() or "Opponent"
    local whiteName = myColor == COLOR.WHITE and myName or opponent
    local blackName = myColor == COLOR.BLACK and myName or opponent
    local clock = game.clock
    local settings = {
        useClock = clock ~= nil,
        timeMinutes = clock and (clock.hostTime or 0) or 0,
        incrementSeconds = clock and (clock.hostInc or 0) or 0,
    }
    local _, myClass = UnitClass("player")
    local extra = { playerColor = myColor }
    if myColor == COLOR.WHITE then extra.whiteClass = myClass else extra.blackClass = myClass end
    if clock then
        local hostWhite = self:HostColor(game) == COLOR.WHITE
        local whiteSec = ((hostWhite and clock.hostTime or clock.opponentTime) or 0) * 60
        local blackSec = ((hostWhite and clock.opponentTime or clock.hostTime) or 0) * 60
        local whiteInc = (hostWhite and clock.hostInc or clock.opponentInc) or 0
        local blackInc = (hostWhite and clock.opponentInc or clock.hostInc) or 0
        extra.clockData = {
            gameStartTimestamp = DeltaChessFramework.Util.TimeNow(),
            initialTimeSeconds = math.max(whiteSec, blackSec),
            incrementSeconds = whiteInc,
            handicapSeconds = math.abs(whiteSec - blackSec),
            handicapSide = (whiteSec < blackSec) and COLOR.WHITE or ((blackSec < whiteSec) and COLOR.BLACK or nil),
        }
        settings.incrementSeconds = myColor == COLOR.WHITE and whiteInc or blackInc
    end
    local board = DeltaChess.CreateGameBoard(game.id, whiteName, blackName, settings, extra)
    if clock and extra.clockData then
        local hostWhite = self:HostColor(game) == COLOR.WHITE
        board:SetClock(COLOR.WHITE, ((hostWhite and clock.hostTime or clock.opponentTime) or 0) * 60)
        board:SetClock(COLOR.BLACK, ((hostWhite and clock.opponentTime or clock.hostTime) or 0) * 60)
        board:SetIncrement(COLOR.WHITE, (hostWhite and clock.hostInc or clock.opponentInc) or 0)
        board:SetIncrement(COLOR.BLACK, (hostWhite and clock.opponentInc or clock.hostInc) or 0)
    end
    DeltaChess.StoreBoard(game.id, board)
    self.netGames[game.id] = game
    if game.isHost then
        self:Print(opponent .. " accepted your challenge!")
    end
    DeltaChess.Sound:PlayChallengeAccepted()
    self:ShowChessBoard(game.id)
end

function DeltaChess:BindChess(chess)
    chess:OnChallenge(function(offer)
        if self.db and self.db.settings and self.db.settings.dnd then
            offer:Decline()
            return
        end
        local name = (offer.player and offer.player.DisplayName) and offer.player:DisplayName() or "Opponent"
        local side = offer.yourColor == COLOR.WHITE and "White" or "Black"
        local sideText = string.format("|cFFFFD100Your Side:|r  %s", side)
        local clockLine = "|cFFFFD100Clock:|r  " .. clockText(offer.clock, offer.yourColor)
        local ranked = offer.ranked and "\n|cFFFFD100Ranked|r" or ""
        local settingsText = sideText .. "\n" .. clockLine .. ranked
        DeltaChess.Sound:PlayChallengeReceived()
        StaticPopup_Show("CHESS_CHALLENGE_RECEIVED", name, settingsText, offer)
    end)

    chess:OnGame(function(game)
        self:BindNetworkGame(game)
        self:StartNetworkGame(game)
    end)
end

function DeltaChess:BindNetworkGame(game)
    game:OnMove(function(move)
        local board = DeltaChess.GetBoard(game.id)
        local coords = board and DeltaChess.UciToCoords(move.uci)
        local legal = board and coords and not board:IsPaused() and not board:IsEnded() and
            DeltaChess.IsLegalMove(board, coords.fromRow, coords.fromCol, coords.toRow, coords.toCol, coords.promotion)
        if not legal then
            move:Reject()
            return
        end
        -- Accept before applying so a mating move is confirmed before the result is sent.
        move:Accept()
        self:ApplyNetworkMove(game, move.uci, move.times, true)
    end)
    game:OnOver(function(result, reason)
        self:ApplyNetworkResult(game, result, reason)
    end)
    game:OnDrawOffer(function(offer)
        local board = DeltaChess.GetBoard(game.id)
        if not board then
            offer:Decline()
            return
        end
        if board:IsThreefoldRepetitionDrawPossible() then
            offer:Accept()
            return
        end
        self.pendingDraw = self.pendingDraw or {}
        self.pendingDraw[game.id] = offer
        DeltaChess.UI:ShowGamePopup(game.id, "CHESS_DRAW_OFFER", nil, offer)
    end)
    game:OnPauseOffer(function(offer)
        self.pendingPause = self.pendingPause or {}
        self.pendingPause[game.id] = offer
        DeltaChess.UI:ShowGamePopup(game.id, "CHESS_PAUSE_REQUEST", nil, { gameId = game.id, offer = offer })
    end)
    game:OnResumeOffer(function(offer)
        self.pendingResume = self.pendingResume or {}
        self.pendingResume[game.id] = offer
        DeltaChess.UI:ShowGamePopup(game.id, "CHESS_UNPAUSE_REQUEST", nil, { gameId = game.id })
    end)
    game:OnPause(function(paused)
        local board = DeltaChess.GetBoard(game.id)
        if not board then return end
        if paused then
            if not board:IsPaused() then
                board:PauseGame()
                board:SetGameMeta("pauseStartTime", DeltaChessFramework.Util.TimeNow())
                board:SetGameMeta("_lastMoveCountWhenPaused", board:GetHalfMoveCount())
                self:Print("Game paused.")
            end
        elseif board:IsPaused() then
            local pauseStart = board:GetGameMeta("pauseStartTime")
            if pauseStart then
                local spent = board:GetGameMeta("timeSpentClosed") or 0
                board:SetGameMeta("timeSpentClosed", spent + (DeltaChessFramework.Util.TimeNow() - pauseStart))
            end
            board:ContinueGame()
            board:SetGameMeta("pauseStartTime", nil)
            self:Print("Game resumed.")
        end
        if DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == game.id then
            DeltaChess.UI:UpdateBoard(DeltaChess.UI.activeFrame)
        end
        self:RefreshMainMenuContent()
    end)
end

function DeltaChess:UpdateFindMatchButton()
    local btn = self.frames and self.frames.mainMenu and self.frames.mainMenu.findMatchBtn
    if not btn then return end
    if self.matchmaking and not self.matchmaking.state then
        btn:SetText("Cancel search")
    else
        btn:SetText("Find match")
    end
end

function DeltaChess:FindMatch()
    local chess = self:Chess()
    if not chess then return end
    if self.matchmaking and not self.matchmaking.state then
        local pending = self.matchmaking
        self.matchmaking = nil
        if pending.Cancel then pending:Cancel() end
        self:Print("Matchmaking cancelled.")
        self:UpdateFindMatchButton()
        return
    end
    local pending = chess:Matchmake({
        color = "random",
        onFail = function(_, message)
            if self.matchmaking ~= pending then return end
            self.matchmaking = nil
            self:Print("|cFFFF0000" .. tostring(message or "Matchmaking failed.") .. "|r")
            self:UpdateFindMatchButton()
        end,
    })
    pending:resolve(function()
        self.matchmaking = nil
        self:UpdateFindMatchButton()
        if self.frames.mainMenu then self.frames.mainMenu:Hide() end
    end, function(_, message)
        if self.matchmaking ~= pending then return end
        self.matchmaking = nil
        self:Print("|cFFFF0000" .. tostring(message or "Matchmaking failed.") .. "|r")
        self:UpdateFindMatchButton()
    end)
    if pending.state == "err" then return end
    self.matchmaking = pending
    self:Print("Looking for a match...")
    self:UpdateFindMatchButton()
end

function DeltaChess:DiscoverPlayers(where, callback)
    local chess = self:Chess()
    if not chess then
        if callback then callback({}) end
        return
    end
    local delivered = false
    local function finish(list)
        if delivered or not callback then return end
        delivered = true
        local responded = {}
        for i = 1, #(list or {}) do
            local player = list[i]
            if player and not chess.session:IsMe(player) then
                table.insert(responded, {
                    fullName = player:Address() or player.name or player:DisplayName(),
                    dnd = false,
                })
            end
        end
        callback(responded)
    end
    local pending = chess:Discover({
        where = where,
        wait = 3,
        onDone = function(list) finish(list) end,
    })
    pending:resolve(nil, function() finish({}) end)
end

function DeltaChess:SendChallenge(gameSettings)
    local chess = self:Chess()
    if not chess then return end
    local target = gameSettings.opponent
    if not target or target == "" then
        self:Print("Please enter a player name!")
        return
    end
    local color = gameSettings.challengerColor
    if color ~= COLOR.WHITE and color ~= COLOR.BLACK then
        color = math.random(2) == 1 and COLOR.WHITE or COLOR.BLACK
    end
    local spec = { color = color }
    if gameSettings.useClock then
        local mine = gameSettings.timeMinutes or 10
        local theirs = mine
        local handicap = (gameSettings.handicapSeconds or 0) / 60
        if handicap > 0 and gameSettings.handicapSide == color then
            mine = math.max(mine - handicap, 1 / 60)
        elseif handicap > 0 and gameSettings.handicapSide then
            theirs = math.max(theirs - handicap, 1 / 60)
        end
        spec.clock = {
            hostTime = mine,
            hostInc = gameSettings.incrementSeconds or 0,
            opponentTime = theirs,
            opponentInc = gameSettings.incrementSeconds or 0,
        }
    end
    local watch = { done = false }
    local function fail(code, message)
        if watch.done then return end
        watch.done = true
        self:Print("|cFFFF0000" .. tostring(message or "Challenge failed.") .. "|r")
        if (code == "offline" or code == "no-route") and self.Bnet and self.Bnet.SendChatWhisper then
            self.Bnet:SendChatWhisper(INSTALL_WHISPER, target)
        end
    end
    local pending = chess:Challenge(target, spec, { onFail = fail })
    -- REMOVE WITH NoticeOldClient: pre-1.2 clients answer ChessPing.
    if pending.state ~= "err" and self.NoticeOldClient then
        self:NoticeOldClient(target, pending, watch)
    end
    pending:resolve(function()
        watch.done = true
    end, fail)
    if pending.state ~= "err" then
        local displayName = gameSettings.opponentBattleTag or target
        self:Print("Challenge sent to " .. displayName)
    end
end

function DeltaChess:AcceptChallenge(challengeData)
    StaticPopup_Hide("CHESS_CHALLENGE_RECEIVED")
    if not challengeData or not challengeData.Accept then return end
    challengeData:Accept({
        onFail = function(_, message)
            self:Print("|cFFFF0000" .. tostring(message or "Could not accept the challenge.") .. "|r")
        end,
    })
end

function DeltaChess:DeclineChallenge(challengeData)
    StaticPopup_Hide("CHESS_CHALLENGE_RECEIVED")
    if challengeData and challengeData.Decline then
        challengeData:Decline()
    end
    DeltaChess.Sound:PlayChallengeDeclined()
    self:Print("Challenge declined.")
end

function DeltaChess:SendMoveWithConfirmation(gameId, uci)
    local board = DeltaChess.GetBoard(gameId)
    if not board then return false end
    if board:OneOpponentIsEngine() then return false end
    if board:IsPaused() then
        self:Print("Game is paused!")
        return false
    end
    if self:IsBoardLocked(gameId) then
        self:Print("Waiting for previous move to be acknowledged...")
        return false
    end
    local game = self:NetworkGame(gameId)
    if not game then
        self:Print("|cFFFF0000This game is no longer connected.|r")
        return false
    end
    local times = self:NetworkTimes(game, board)
    self:LockBoard(gameId)
    local function done(ok, _, message)
        self:UnlockBoard(gameId)
        if not ok then
            self:Print("|cFFFF0000" .. tostring(message or "Move was not accepted.") .. "|r")
            if DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId then
                DeltaChess.UI:UpdateBoard(DeltaChess.UI.activeFrame)
            end
            return
        end
        if not self:ApplyNetworkMove(game, uci, times, false) then
            self:Print("|cFFFF0000Could not apply the move.|r")
        end
    end
    if times then
        game:Move(uci, times, done)
    else
        game:Move(uci, done)
    end
    return true
end

function DeltaChess:SendMove(gameId, uci)
    return self:SendMoveWithConfirmation(gameId, uci)
end

function DeltaChess:RestoreGameFromHistory(gameId)
    if DeltaChess.GetBoard(gameId) then
        return DeltaChess.GetBoard(gameId)
    end
    if DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId then
        local frame = DeltaChess.UI.activeFrame
        local board = frame.board
        if not board:GetStartTime() then
            board:StartGame()
        end
        if not board:GetGameMeta("id") then
            board:SetGameMeta("id", gameId)
        end
        DeltaChess.StoreBoard(gameId, board)
        self.db.history[gameId] = nil
        return board
    end
    return nil
end

function DeltaChess:TakeBackMove(gameId)
    local board = DeltaChess.GetBoard(gameId)
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
    local lastMoveByWhite = (#moves % 2) == 1
    local playerColor = board:GetPlayerColor()
    local playerIsWhite = (playerColor == COLOR.WHITE)
    local playerMovedLast = (lastMoveByWhite == playerIsWhite)
    local movesToRemove = playerMovedLast and 1 or 2
    movesToRemove = math.min(movesToRemove, #moves)
    local targetIndex = #moves - movesToRemove
    local newBoard = board:GetBoardAtIndex(targetIndex)
    if not newBoard then
        self:Print("Cannot take back: failed to get board snapshot.")
        return
    end
    newBoard:StartGame()
    DeltaChess.StoreBoard(gameId, newBoard)
    if DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId then
        local frame = DeltaChess.UI.activeFrame
        frame.board = newBoard
        frame.gameEndShown = false
        frame.selectedSquare = nil
        frame.validMoves = {}
        DeltaChess.UI:UpdateBoard(frame)
    end
    self:Print("Took back last move.")
end

function DeltaChess:ResignGame(gameId)
    local board = DeltaChess.GetBoard(gameId)
    if not board then return end
    if board:OneOpponentIsEngine() then
        board:Resign(board:GetPlayerColor() or COLOR.WHITE)
        if DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId then
            DeltaChess.UI:UpdateBoard(DeltaChess.UI.activeFrame)
        end
        self:SaveGameToHistory(board)
        self:Print("You resigned.")
        return
    end
    local game = self:NetworkGame(gameId)
    if not game then
        board:Resign(self:GetMyColor(gameId) or board:GetPlayerColor() or COLOR.WHITE)
        local frame = (DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId) and DeltaChess.UI.activeFrame or nil
        DeltaChess.UI:ShowGameEnd(gameId, frame)
        self:Print("You resigned. The opponent could not be reached.")
        return
    end
    game:Resign(function(ok, _, message)
        if not ok then
            self:Print("|cFFFF0000" .. tostring(message or "Could not resign.") .. "|r")
        end
    end)
end

function DeltaChess:OfferDraw(gameId)
    local game = self:NetworkGame(gameId)
    if not game then return end
    local pending = game:OfferDraw(function(ok, _, message)
        if not ok then
            self:Print(message or "Your opponent declined the remis offer.")
        end
    end)
    if pending.state ~= "err" then
        self:Print("Remis offer sent.")
    end
end

function DeltaChess:AcceptDraw(gameIdOrOffer)
    local offer = gameIdOrOffer
    if type(offer) ~= "table" or not offer.Accept then
        offer = self.pendingDraw and self.pendingDraw[gameIdOrOffer]
    end
    if offer and offer.Accept then
        offer:Accept()
    end
end

function DeltaChess:DeclineDraw(gameIdOrOffer)
    local offer = gameIdOrOffer
    if type(offer) ~= "table" or not offer.Decline then
        offer = self.pendingDraw and self.pendingDraw[gameIdOrOffer]
    end
    if offer and offer.Decline then
        offer:Decline()
    end
end

function DeltaChess:RequestPause(gameId)
    local board = DeltaChess.GetBoard(gameId)
    if not board or board:OneOpponentIsEngine() or not board:IsActive() then return end
    local game = self:NetworkGame(gameId)
    if not game then return end
    local pending = game:OfferPause(function(ok, _, message)
        if not ok then
            self:Print(message or "Opponent declined the pause request.")
        end
    end)
    if pending.state ~= "err" then
        self:Print("Pause request sent to opponent.")
    end
end

function DeltaChess:SendPauseResponse(gameId, accepted)
    local offer = self.pendingPause and self.pendingPause[gameId]
    if self.pendingPause then self.pendingPause[gameId] = nil end
    if not offer then return end
    if accepted then offer:Accept() else offer:Decline() end
end

function DeltaChess:RequestUnpause(gameId)
    local board = DeltaChess.GetBoard(gameId)
    if not board or board:OneOpponentIsEngine() or not board:IsPaused() then return end
    local game = self:NetworkGame(gameId)
    if not game then return end
    local pending = game:Resume(function(ok, _, message)
        if not ok then
            self:Print(message or "Opponent declined the resume request.")
        end
    end)
    if pending.state ~= "err" then
        self:Print("Resume request sent to opponent.")
    end
end

function DeltaChess:SendUnpauseResponse(gameId, accepted)
    local offer = self.pendingResume and self.pendingResume[gameId]
    if self.pendingResume then self.pendingResume[gameId] = nil end
    if not offer then return end
    if accepted then offer:Accept() else offer:Decline() end
end

function DeltaChess:TimeOut(gameId, color)
    local board = DeltaChess.GetBoard(gameId)
    if not board then return end
    local white = board:GetWhitePlayerName()
    local black = board:GetBlackPlayerName()
    board:SetGameMeta("timeoutPlayer", color == COLOR.WHITE and white or black)
    board:SetClock(color, 0)
    board:SetIncrement(color, 0)
    if not board:IsEnded() then
        board:EndGame()
    end
    local game = self:NetworkGame(gameId)
    if game then
        self:AnnounceNetworkEnd(game, board)
    end
    self:ShowNetworkEnd(gameId)
end

function DeltaChess:GetOpponent(gameId)
    local board = DeltaChess.GetBoard(gameId)
    if not board then return nil end
    local myColor = self:GetMyColor(gameId)
    if myColor == COLOR.WHITE then return board:GetBlackPlayerName() end
    if myColor == COLOR.BLACK then return board:GetWhitePlayerName() end
    return nil
end

function DeltaChess:GetMyColor(gameId)
    local board = DeltaChess.GetBoard(gameId)
    if not board then return nil end
    local stored = board:GetPlayerColor()
    if stored then return stored end
    local myCharName, myName = self:GetLocalPlayerInfo()
    local white = board:GetWhitePlayerName()
    local black = board:GetBlackPlayerName()
    if white == myCharName or white == myName then return COLOR.WHITE end
    if black == myCharName or black == myName then return COLOR.BLACK end
    return nil
end

--------------------------------------------------------------------------------
-- BEGIN REMOVE: pre-1.2 direct-challenge check
-- A direct challenge also sends the old ChessPing. A PONG means that client
-- does not speak LibChessMultiplayer. Delete this whole block, the
-- NoticeOldClient call in SendChallenge, and SendMessage/HandleBNetWhisper
-- in Bnet.lua once those clients no longer need an upgrade notice.
--------------------------------------------------------------------------------

local OLD_PING = "ChessPing"
local UPGRADE_TEXT = "Please upgrade to DeltaChess 1.2 so we can play. Download it from Curseforge: https://www.curseforge.com/wow/addons/deltachess"

function DeltaChess:NoticeOldClient(target, pending, watch)
    if not target or target == "" then return end
    local probe = { done = false }
    self.oldClientProbes = self.oldClientProbes or {}
    local function arm(key)
        if type(key) == "string" and key ~= "" then
            self.oldClientProbes[key] = probe
        end
    end
    arm(target)
    if self.NormalizePlayerName then arm(self:NormalizePlayerName(target)) end
    if self.Bnet and not tostring(target):find("#", 1, true) and self.Bnet.GetBattleTagForCharacter then
        arm(self.Bnet:GetBattleTagForCharacter(target))
    end
    if self.Bnet and tostring(target):find("#", 1, true) and self.Bnet.GetCurrentCharacterForBattleTag then
        arm(self.Bnet:GetCurrentCharacterForBattleTag(target))
    end
    probe.onOld = function(sender)
        if probe.done or (watch and watch.done) then return end
        probe.done = true
        if watch then watch.done = true end
        if pending and pending.Cancel then pending:Cancel() end
        local who = sender or target
        self:Print("|cFFFF0000" .. tostring(who) .. " needs to upgrade to DeltaChess 1.2.|r")
        if self.Bnet and self.Bnet.SendChatWhisper then
            self.Bnet:SendChatWhisper(UPGRADE_TEXT, target)
        end
    end
    if self.Bnet and self.Bnet.SendMessage then
        self.Bnet:SendMessage(OLD_PING, "PING", target)
    end
    if not tostring(target):find("#", 1, true) and self.IsGroupMember and self:IsGroupMember(target) then
        local channel = self.GetGroupAddonChannel and self:GetGroupAddonChannel()
        if channel then self:SendAddon(OLD_PING, "PING", channel) end
    end
    C_Timer.After(3, function()
        if not self.oldClientProbes then return end
        for key, pendingProbe in pairs(self.oldClientProbes) do
            if pendingProbe == probe then self.oldClientProbes[key] = nil end
        end
    end)
end

function DeltaChess:NoteOldClient(sender)
    if not sender or not self.oldClientProbes then return end
    local probe = self.oldClientProbes[sender]
    if not probe and self.NormalizePlayerName then
        probe = self.oldClientProbes[self:NormalizePlayerName(sender)]
    end
    if not probe and self.IsSamePlayer then
        for key, pendingProbe in pairs(self.oldClientProbes) do
            if self:IsSamePlayer(key, sender) then
                probe = pendingProbe
                break
            end
        end
    end
    if probe and probe.onOld then probe.onOld(sender) end
end

local oldClientFrame = CreateFrame("Frame")
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(OLD_PING)
end
oldClientFrame:RegisterEvent("CHAT_MSG_ADDON")
oldClientFrame:RegisterEvent("CHAT_MSG_BN_WHISPER")
oldClientFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
        local prefix, message, _, sender = ...
        if prefix == OLD_PING and (message == "PONG" or message == "PONG:DND") then
            DeltaChess:NoteOldClient(sender)
        end
        return
    end
    if not DeltaChess.Bnet or not DeltaChess.Bnet.HandleBNetWhisper then return end
    local text, _, _, _, _, _, _, _, _, _, _, _, bnSenderID = ...
    local prefix, message, tag = DeltaChess.Bnet:HandleBNetWhisper(bnSenderID, text)
    if prefix == OLD_PING and (message == "PONG" or message == "PONG:DND") then
        DeltaChess:NoteOldClient(tag)
    end
end)

-- END REMOVE: pre-1.2 direct-challenge check
