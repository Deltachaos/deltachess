-- Core.lua - Main addon initialization and slash commands

local DeltaChess = LibStub("DeltaChess-1.0")
local DeltaChessFramework = LibStub("DeltachessFramework-1.0")
DeltaChess.version = "1.0.0"

-- Local reference for constants (set after Constants loads)
local COLOR
local STATUS

-- Helper: create a repeating timer with Classic compatibility fallback
-- Returns the ticker handle (C_Timer ticker or a Frame for the OnUpdate fallback)
function DeltaChess.CreateTicker(intervalSeconds, callback)
    if C_Timer and C_Timer.NewTicker then
        return C_Timer.NewTicker(intervalSeconds, callback)
    end
    -- Classic fallback: use an OnUpdate frame
    local frame = CreateFrame("Frame")
    local elapsed = 0
    frame:SetScript("OnUpdate", function(self, delta)
        elapsed = elapsed + delta
        if elapsed >= intervalSeconds then
            elapsed = 0
            callback()
        end
    end)
    return frame
end

-- Frame for events
local eventFrame = CreateFrame("Frame")

-- UI Frames storage. Widget trees are declared in Frames/Templates.xml and Frames/Windows.xml.
DeltaChess.frames = {}

local function SetCheckLabel(check, text)
    local label = check.text or check.Text
    if label then
        label:SetText(text)
    end
end

-- Dragging is Widget API: SetMovable, EnableMouse, RegisterForDrag, StartMoving.
function DeltaChess:MakeDraggable(frame, onDragStop)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", onDragStop or frame.StopMovingOrSizing)
end

-- Initialize the addon
local function Initialize()
    -- Set local reference to constants now that all files are loaded
    COLOR = DeltaChessFramework.Constants.COLOR
    STATUS = {
        ACTIVE = DeltaChessFramework.Constants.STATUS_ACTIVE,
        PAUSED = DeltaChessFramework.Constants.STATUS_PAUSED,
        ENDED = DeltaChessFramework.Constants.STATUS_ENDED,
    }
    
    -- Initialize saved variables
    if not ChessDB then
        ChessDB = {
            games = {},
            history = {},
            settings = {
                showMinimapButton = true,
                dnd = false,
                boardMinimized = false,
                boardPosition = nil  -- { point, relativePoint, x, y } from GetPoint(1), relative to UIParent
            }
        }
    end
    if ChessDB.settings.dnd == nil then
        ChessDB.settings.dnd = false
    end
    if ChessDB.settings.boardMinimized == nil then
        ChessDB.settings.boardMinimized = false
    end
    
    -- Version check: if no version exists, clear games and history (old database format)
    if not ChessDB.version then
        ChessDB.games = {}
        ChessDB.history = {}
    end
    
    -- Save current addon version
    ChessDB.version = DeltaChess.version
    
    DeltaChess.db = ChessDB

    -- Register slash commands (slash names unchanged)
    SLASH_CHESS1 = "/chess"
    SlashCmdList["CHESS"] = function(msg)
        DeltaChess:SlashCommand(msg)
    end
    
    -- Register addon messages
    C_ChatInfo.RegisterAddonMessagePrefix("ChessChallenge")
    C_ChatInfo.RegisterAddonMessagePrefix("ChessMove")
    C_ChatInfo.RegisterAddonMessagePrefix("ChessResponse")
    C_ChatInfo.RegisterAddonMessagePrefix("ChessResign")
    C_ChatInfo.RegisterAddonMessagePrefix("ChessDraw")
    C_ChatInfo.RegisterAddonMessagePrefix("ChessAck")
    C_ChatInfo.RegisterAddonMessagePrefix("ChessPing")
    C_ChatInfo.RegisterAddonMessagePrefix("ChessPause")
    C_ChatInfo.RegisterAddonMessagePrefix("ChessUnpause")
    
    -- Register for addon messages
    eventFrame:RegisterEvent("CHAT_MSG_ADDON")
    eventFrame:RegisterEvent("CHAT_MSG_BN_WHISPER")
    eventFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "CHAT_MSG_ADDON" then
            DeltaChess:OnCommReceived(...)
        elseif event == "CHAT_MSG_BN_WHISPER" then
            DeltaChess:OnBNetWhisperReceived(...)
        end
    end)
    
    -- Restore metatables for saved games
    DeltaChess:RestoreSavedGames()

    -- Engine searches live in memory only. A reload during the computer's move
    -- leaves the game running on the computer's turn with no session; start it again.
    DeltaChess.AI:ResumeInterruptedComputerMoves()

    -- Premoves are stored on each board (and survive SavedVariables). Only the
    -- short play-timer is lost on reload; fire any that are already our turn.
    DeltaChess.ResumePendingPremoves()
    
    DeltaChess:Print("DeltaChess addon loaded! Use /chess to challenge a player or /chess menu to open settings.")
    
    -- Initialize minimap button after a short delay
    C_Timer.After(1, function()
        if DeltaChess.Minimap then
            DeltaChess.Minimap:Initialize()
        end
    end)

    -- Periodic ticker: archive ended games and update minimap highlight
    DeltaChess.CreateTicker(2, function()
        -- Move ended games from db.games to history
        if DeltaChess.db and DeltaChess.db.games then
            for gameId, board in pairs(DeltaChess.db.games) do
                if board:IsEnded() then
                    -- Update the frame before saving (which removes the board)
                    if DeltaChess.UI and DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId then
                        DeltaChess.UI:UpdateBoard(DeltaChess.UI.activeFrame)
                    end
                    DeltaChess:SaveGameToHistory(board)
                end
            end
        end

        -- Update minimap your-turn highlight
        if DeltaChess.Minimap and DeltaChess.Minimap.UpdateYourTurnHighlight then
            DeltaChess.Minimap:UpdateYourTurnHighlight()
        end
    end)
end

-- Restore board metatables for saved games after addon reload
function DeltaChess:RestoreSavedGames()
    if not self.db or not self.db.games then return end
    
    for gameId, board in pairs(self.db.games) do
        -- Board IS the game - restore metatable directly
        if board and not getmetatable(board) then
            -- Restore the board metatable using the Board prototype
            setmetatable(board, DeltaChessFramework.Board.Prototype)
            
            -- Ensure the board has all required data structures
            if not board.moves then
                board.moves = {}
            end
            if not board.gameMeta then
                board.gameMeta = {}
            end
            -- Ensure board has started (for old saved games)
            if not board:GetStartTime() then
                board:StartGame()
            end
            -- Ensure board has its ID stored
            if not board:GetGameMeta("id") then
                board:SetGameMeta("id", gameId)
            end
        end
    end
end

-- Print function
function DeltaChess:Print(msg)
    print("|cFF33FF99DeltaChess:|r " .. tostring(msg))
end

-- Debug logging for addon communication (/chess debug)
function DeltaChess:CommDebug(fmt, ...)
    if not self.debugComm then return end
    local ok, text = pcall(string.format, fmt, ...)
    local line = ok and text or tostring(fmt)
    print("|cFFFFAA00DeltaChess debug:|r " .. line)
    -- Also keep it in SavedVariables (written to WTF/.../SavedVariables/DeltaChess.lua on /reload or logout)
    if ChessDB then
        ChessDB.debugLog = ChessDB.debugLog or {}
        table.insert(ChessDB.debugLog, date("%H:%M:%S") .. " " .. line)
        while #ChessDB.debugLog > 300 do table.remove(ChessDB.debugLog, 1) end
    end
end

-- Send an addon message and log the result in debug mode
function DeltaChess:SendAddon(prefix, message, channel, target)
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, prefix, message, channel, target)
    self:CommDebug("OUT %s %q via %s to %s -> %s", prefix, tostring(message):sub(1, 40), channel,
        tostring(target), ok and tostring(result) or ("error: " .. tostring(result)))
    return ok
end

-- Load on player login
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        Initialize()
    end
end)

-- Slash command handler
function DeltaChess:SlashCommand(input)
    local command = strtrim(input or "")
    
    if command == "" then
        -- Challenge target
        if UnitExists("target") and UnitIsPlayer("target") then
            local targetName = self:GetUnitFullName("target")
            self:ShowChallengeWindow(targetName)
        else
            self:ShowMainMenu()
        end
    elseif command == "debug" then
        self.debugComm = not self.debugComm
        self:Print("Communication debug " .. (self.debugComm and "ON" or "OFF"))
        if self.debugComm and ChessDB then ChessDB.debugLog = {} end
        if self.debugComm then
            local n, r = UnitName("player")
            self:CommDebug("me: UnitName=%s realm=%s GetRealmName=%s normalized=%s", tostring(n), tostring(r),
                tostring(GetRealmName()), tostring(GetNormalizedRealmName and GetNormalizedRealmName()))
        end
    elseif command == "menu" or command == "help" then
        self:ShowMainMenu()
    elseif command == "games" or command == STATUS.ACTIVE then
        self:ShowActiveGames()
    elseif command == "history" then
        self:ShowGameHistory()
    elseif command == "settings" then
        self:ShowSettings()
    elseif command == "minimap" then
        self.db.settings.showMinimapButton = not self.db.settings.showMinimapButton
        if self.db.settings.showMinimapButton then
            DeltaChess.Minimap:Show()
            self:Print("Minimap button enabled")
        else
            DeltaChess.Minimap:Hide()
            self:Print("Minimap button disabled")
        end
    elseif command == "computer" or command == "ai" or command == "cpu" then
        self:ShowComputerGameWindow()
    elseif command:find("-") then
        -- Player-realm notation
        self:ShowChallengeWindow(self:NormalizePlayerName(command))
    else
        -- Try to find player on same realm
        local playerName = self:NormalizePlayerName(command)
        self:ShowChallengeWindow(playerName)
    end
end

-- Get the local realm in the same normalized form WoW uses for addon message senders
-- (no spaces/hyphens, e.g. "My Realm 2 PvP" -> "MyRealm2PvP")
function DeltaChess:GetMyRealm()
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not realm or realm == "" then
        realm = (GetRealmName() or ""):gsub("[%s%-]", "")
    end
    return realm
end

-- True if the given realm string is the player's own realm (ignoring spaces/hyphens/case)
function DeltaChess:IsMyRealm(realm)
    if not realm or realm == "" then return true end
    local r = realm:gsub("[%s%-]", ""):lower()
    if r == self:GetMyRealm():lower() then return true end
    local display = (GetRealmName() or ""):gsub("[%s%-]", ""):lower()
    return r == display
end

-- WoW Forever: players are addressed by "Firstname Surname" (that is the sender name
-- CHAT_MSG_ADDON reports and the only whisper target that works), but UnitName() and
-- typed names may be just "Firstname". Expand a bare first name to the full name using
-- the guild roster (only if exactly one guild member matches).
function DeltaChess:ExpandSurname(char)
    if char:find(" ") or not (IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo) then
        return char
    end
    local found
    for i = 1, (GetNumGuildMembers() or 0) do
        local n = GetGuildRosterInfo(i)
        if n then
            local base = n:match("^(.-)%-") or n
            if base ~= char and base:match("^(%S+)") == char then
                if found and found ~= base then return char end
                found = base
            end
        end
    end
    return found or char
end

-- Canonical player name used for addon messaging and name comparisons.
-- Same-realm players are just "Name" (realm stripped) - some servers (e.g. WoW Forever,
-- where names and realms contain spaces) reject "Name-Realm" whisper targets, and
-- GetRealmName() (with spaces) never matched the normalized realm in sender names.
-- Other-realm players are "Name-NormalizedRealm". BattleTags pass through.
function DeltaChess:NormalizePlayerName(name)
    if not name or name == "" or name:find("#") then return name end
    name = strtrim(name)
    local char, realm = name:match("^(.-)%-(.+)$")
    if not char or char == "" then
        char, realm = name, nil
    end
    if not realm or self:IsMyRealm(realm) then
        return self:ExpandSurname(char)
    end
    return char .. "-" .. (realm:gsub("[%s%-]", ""))
end

-- Get full player name with realm
function DeltaChess:GetFullPlayerName(name)
    return self:NormalizePlayerName(name)
end

-- WoW Forever: UnitName(unit) returns (firstName, surname) instead of (name, realm).
-- Detect it from the player unit, which never has a realm on regular WoW clients.
function DeltaChess:UsesForeverNames()
    if self._foreverNames == nil then
        local _, second = UnitName("player")
        self._foreverNames = (type(second) == "string" and second ~= "")
    end
    return self._foreverNames
end

-- Canonical name of a unit. Uses UnitName's second return value: the realm on regular
-- clients, the surname on WoW Forever ("Firstname Surname", the form senders use).
function DeltaChess:GetUnitFullName(unit)
    local name, second = UnitName(unit)
    if not name then return nil end
    if second and second ~= "" then
        if self:UsesForeverNames() then
            return self:NormalizePlayerName(name .. " " .. second)
        end
        return self:NormalizePlayerName(name .. "-" .. second)
    end
    return self:NormalizePlayerName(name)
end

-- Comparison key for a player name (never used for sending): the normalized name,
-- ignoring case, spaces and hyphens.
function DeltaChess:NormalizeNameKey(name)
    if type(name) ~= "string" or name == "" then return "" end
    if issecretvalue and issecretvalue(name) then return "" end
    local n = self:NormalizePlayerName(name) or name
    return (n:gsub("[%s%-]", "")):lower()
end

-- True if two names refer to the same character
function DeltaChess:IsSamePlayer(a, b)
    if a == b then return true end
    if type(a) ~= "string" or type(b) ~= "string" then return false end
    if a:find("#") or b:find("#") then return false end -- BattleTags must match exactly
    local ka = self:NormalizeNameKey(a)
    return ka ~= "" and ka == self:NormalizeNameKey(b)
end

-- True if the given name belongs to someone in our party/raid
function DeltaChess:IsGroupMember(name)
    local num = GetNumGroupMembers and GetNumGroupMembers() or 0
    if num <= 0 or type(name) ~= "string" or name:find("#") then return false end
    local prefix = IsInRaid() and "raid" or "party"
    local count = IsInRaid() and num or (num - 1)
    for i = 1, count do
        local unit = prefix .. i
        if UnitExists(unit) then
            local full = self:GetUnitFullName(unit)
            if full and self:IsSamePlayer(name, full) then
                return true
            end
        end
    end
    return false
end

-- Addon-message channel for the current group, or nil when not grouped
function DeltaChess:GetGroupAddonChannel()
    if LE_PARTY_CATEGORY_INSTANCE and LE_PARTY_CATEGORY_HOME and IsInGroup
        and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and not IsInGroup(LE_PARTY_CATEGORY_HOME) then
        return "INSTANCE_CHAT"
    end
    if IsInRaid and IsInRaid() then return "RAID" end
    if (IsInGroup and IsInGroup()) or (GetNumGroupMembers and GetNumGroupMembers() > 0) then
        return "PARTY"
    end
    return nil
end

-- Get local player's info (character name and preferred display name)
-- Returns: characterName, preferredName
-- characterName: always the character name with realm (CharName-Realm)
-- preferredName: BattleTag if available, otherwise character name (for display)
function DeltaChess:GetLocalPlayerInfo()
    local characterName = self:GetUnitFullName("player")
    local battleTag = DeltaChess.Bnet:GetMyBattleTag()
    local preferredName = battleTag or characterName
    return characterName, preferredName
end

-- True if it is this player's turn on the given board (active games only).
local function isPlayerTurnOnBoard(board, playerName)
    if not board or not board:IsActive() then return false end
    local currentTurn = board:GetCurrentTurn()
    if board:OneOpponentIsEngine() then
        local playerColor = board:GetPlayerColor() or COLOR.WHITE
        return currentTurn == playerColor
    end
    local white = board:GetWhitePlayerName()
    local black = board:GetBlackPlayerName()
    return (white == playerName and currentTurn == COLOR.WHITE) or
           (black == playerName and currentTurn == COLOR.BLACK)
end

-- Check if it's the player's turn in any active game
function DeltaChess:IsMyTurnInAnyGame()
    if not self.db or not self.db.games then return false end
    local _, playerName = self:GetLocalPlayerInfo()
    for _, board in pairs(self.db.games) do
        if isPlayerTurnOnBoard(board, playerName) then
            return true
        end
    end
    return false
end

-- Check if any active game is waiting on the opponent or computer to move
function DeltaChess:IsWaitingInAnyGame()
    if not self.db or not self.db.games then return false end
    local _, playerName = self:GetLocalPlayerInfo()
    for _, board in pairs(self.db.games) do
        if board:IsActive() and not isPlayerTurnOnBoard(board, playerName) then
            return true
        end
    end
    return false
end

-- Refresh the main-menu game list when it is open (turn, pause, ended, …).
function DeltaChess:RefreshGameListIfShown()
    local menu = self.frames and self.frames.mainMenu
    if menu and menu:IsShown() then
        self:RefreshMainMenuContent()
    end
end

-- Common: notify user that opponent moved and it's their turn (human or computer).
-- Called for computer games and player-vs-player, so this is the shared place to
-- refresh turn-dependent UI after an opponent move.
function DeltaChess:NotifyItIsYourTurn(gameId, opponentDisplayName)
    local board = DeltaChess.GetBoard(gameId)
    if not board then return end
    if not board:IsActive() then return end
    
    local lastMove = board:GetLastMove()
    local moveNotation = lastMove and DeltaChess.UI:FormatMoveAlgebraic(lastMove) or ""
    if moveNotation ~= "" then
        self:Print(opponentDisplayName .. " played " .. moveNotation .. " - it's your turn!")
    else
        self:Print(opponentDisplayName .. " made their move - it's your turn!")
    end

    if DeltaChess.Minimap and DeltaChess.Minimap.UpdateYourTurnHighlight then
        DeltaChess.Minimap:UpdateYourTurnHighlight()
    end
    self:RefreshGameListIfShown()
    
    -- Sound is now handled by the Sound module in HandleOpponentMove/ChessAI
end

--------------------------------------------------------------------------------
-- MAIN MENU WINDOW
--------------------------------------------------------------------------------
function DeltaChess:ShowMainMenu()
    -- Close existing menu if open
    if self.frames.mainMenu and self.frames.mainMenu:IsShown() then
        self.frames.mainMenu:Hide()
        return
    end
    
    -- Main menu layout is ChessMainMenu in Frames/Windows.xml.
    if not self.frames.mainMenu then
        local frame = ChessMainMenu
        frame:SetFrameStrata("DIALOG")
        frame:SetFrameLevel(100)
        self:MakeDraggable(frame)
        frame.TitleText:SetText("DeltaChess (by Deltachaos)")

        frame.supportBtn:SetScript("OnClick", function()
            DeltaChess:ShowSupportDialog()
        end)

        local scrollChild = frame.historyScroll.scrollChild or ChessMainMenuScrollChild
        if frame.historyScroll:GetScrollChild() ~= scrollChild then
            frame.historyScroll:SetScrollChild(scrollChild)
        end
        frame.scrollChild = scrollChild

        local dndCheck = frame.dndCheck
        SetCheckLabel(dndCheck, "Do Not Disturb (no challenge popups)")
        dndCheck:SetChecked(DeltaChess.db.settings.dnd)
        dndCheck:SetScript("OnClick", function(self)
            DeltaChess.db.settings.dnd = self:GetChecked()
            if DeltaChess.Minimap and DeltaChess.Minimap.UpdateDNDHighlight then
                DeltaChess.Minimap:UpdateDNDHighlight()
            end
        end)

        frame.challengeBtn:SetScript("OnClick", function()
            frame:Hide()
            DeltaChess:ShowChallengeWindow()
        end)
        frame.computerBtn:SetScript("OnClick", function()
            frame:Hide()
            DeltaChess:ShowComputerGameWindow()
        end)

        frame.blingtronBg:SetColorTexture(0.1, 0.15, 0.2, 0.8)
        frame.blingtronText:SetWidth(430)

        self.frames.mainMenu = frame
    end
    
    -- Refresh the content
    self:RefreshMainMenuContent()
    
    self.frames.mainMenu:Show()
end

-- Support dialog with copyable links
function DeltaChess:ShowSupportDialog()
    if not self.frames.supportDialog then
        local PATREON_URL = "https://patreon.com/c/blingtronapp"
        local GITHUB_URL = "https://github.com/Deltachaos/deltachess"

        local frame = ChessSupportDialog
        frame:SetFrameStrata("DIALOG")
        frame:SetFrameLevel(200)
        self:MakeDraggable(frame)
        frame.TitleText:SetText("DeltaChess - Support & License")
        frame.thankYou:SetWidth(400)
        frame.desc:SetWidth(400)
        frame.blingtron:SetWidth(400)

        local patreonEdit = frame.patreonEdit
        patreonEdit:SetAutoFocus(false)
        patreonEdit:SetText(PATREON_URL)
        patreonEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        patreonEdit:SetScript("OnEditFocusLost", function(self) self:SetText(PATREON_URL) end)
        patreonEdit:SetScript("OnChar", function(self) self:SetText(PATREON_URL) end)

        local githubEdit = frame.githubEdit
        githubEdit:SetAutoFocus(false)
        githubEdit:SetText(GITHUB_URL)
        githubEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        githubEdit:SetScript("OnEditFocusLost", function(self) self:SetText(GITHUB_URL) end)
        githubEdit:SetScript("OnChar", function(self) self:SetText(GITHUB_URL) end)

        local enginesCredits = frame.enginesCredits
        enginesCredits:SetWidth(400)
        enginesCredits:SetJustifyH("LEFT")

        local creditLines = {}
        for _, engine in pairs(DeltaChessFramework.Engines.Registry or {}) do
            local line = engine.name or engine.id
            if engine.author then
                line = line .. " by " .. engine.author
            end
            if engine.portedBy then
                line = line .. " (Lua port: " .. engine.portedBy .. ")"
            end
            if engine.license then
                line = line .. " - " .. engine.license
            end
            if engine.url then
                line = line .. "\n    " .. engine.url .. "\n"
            end
            table.insert(creditLines, line)
        end
        table.sort(creditLines)
        enginesCredits:SetText(table.concat(creditLines, "\n"))

        frame.okBtn:SetScript("OnClick", function()
            frame:Hide()
        end)

        frame:SetScript("OnHide", function()
            patreonEdit:ClearFocus()
            githubEdit:ClearFocus()
        end)
        frame:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                self:Hide()
            end
        end)
        frame:EnableKeyboard(true)

        self.frames.supportDialog = frame
    end
    
    self.frames.supportDialog:Show()
end

-- Refresh just the main menu content (without showing/hiding window)
function DeltaChess:RefreshMainMenuContent()
    if not self.frames.mainMenu then return end
    
    if self.frames.mainMenu.dndCheck then
        self.frames.mainMenu.dndCheck:SetChecked(self.db.settings.dnd)
    end
    
    -- Update history
    local scrollChild = self.frames.mainMenu.scrollChild
    
    -- Clear old entries (frames)
    for _, child in ipairs({scrollChild:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    
    -- Clear old FontStrings/textures (regions)
    for _, region in ipairs({scrollChild:GetRegions()}) do
        region:Hide()
        region:SetParent(nil)
    end
    
    -- Collect all boards (active + history deserialized)
    local allBoards = {}
    
    -- Add active game boards
    for _, board in pairs(self.db.games) do
        table.insert(allBoards, board)
    end
    
    -- Add history boards (deserialized; already have _endTime from serialization)
    for _, entry in pairs(self.db.history) do
        local board = self:DeserializeHistoryEntry(entry)
        if board then
            table.insert(allBoards, board)
        end
    end
    
    -- Sort by start time (newest first)
    table.sort(allBoards, function(a, b)
        return (a:GetStartTime() or 0) > (b:GetStartTime() or 0)
    end)
    
    -- Helper to compute player color and turn status
    local playerCharName, playerName = self:GetLocalPlayerInfo()
    local function getPlayerInfo(board)
        local isVsComputer = board:OneOpponentIsEngine()
        local white = board:GetWhitePlayerName()
        local black = board:GetBlackPlayerName()
        local storedPlayerColor = board:GetPlayerColor()
        local currentTurn = board:GetCurrentTurn()
        local playerColor
        
        if isVsComputer then
            playerColor = storedPlayerColor
        else
            if white == playerName then
                playerColor = COLOR.WHITE
            elseif black == playerName then
                playerColor = COLOR.BLACK
            end
        end
        
        local isPlayerTurn = (currentTurn == playerColor)
        return playerColor, isPlayerTurn, currentTurn
    end
    
    -- Add entries
    local yOffset = 0
    if #allBoards == 0 then
        local noHistory = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        noHistory:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
        noHistory:SetText("No games played yet")
        noHistory:SetTextColor(0.5, 0.5, 0.5)
    else
        local displayCount = math.min(#allBoards, 30)
        for i = 1, displayCount do
            local board = allBoards[i]
            local gameId = board:GetGameMeta("id")
            local isActive = board:IsActive()
            local isPaused = board:IsPaused()
            local isVsComputer = board:OneOpponentIsEngine()
            local white = board:GetWhitePlayerName()
            local black = board:GetBlackPlayerName()
            local settings = board:GetGameMeta("settings")
            local computerEngine = board:GetEngineId()
            local computerDifficulty = board:GetEngineElo()
            local moveCount = board:GetHalfMoveCount()
            local result = board:GetGameResult()
            local gameDate = board:GetStartDateString()
            
            local playerColor, isPlayerTurn, _ = getPlayerInfo(board)
            local windowShown = DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == gameId and DeltaChess.UI.activeFrame:IsShown()
            
            DeltaChess._historyEntrySeq = (DeltaChess._historyEntrySeq or 0) + 1
            local entry = CreateFrame("Button", "DeltaChessHistoryEntry" .. DeltaChess._historyEntrySeq, scrollChild, "DeltaChessHistoryEntryTemplate")
            entry:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)

            local bg = entry.bg
            if isActive or isPaused then
                if isPaused then
                    bg:SetColorTexture(0.2, 0.2, 0.0, 0.7) -- Yellow tint - paused
                elseif isPlayerTurn then
                    bg:SetColorTexture(0.0, 0.3, 0.0, 0.7) -- Bright green - your turn
                else
                    bg:SetColorTexture(0.1, 0.15, 0.1, 0.6) -- Dim green - waiting
                end
            elseif i % 2 == 0 then
                bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)
            else
                bg:SetColorTexture(0.15, 0.15, 0.15, 0.5)
            end

            entry.info:SetText(DeltaChess.UI:FormatGameTitle(board))
            entry.dateText:SetText("|cFFAAAAAADate: " .. (gameDate or "Unknown") .. "|r")

            local settingsText = entry.settingsText
            
            local settingsParts = {}
            if playerColor then
                table.insert(settingsParts, "You: " .. playerColor)
            end
            if isVsComputer and computerDifficulty then
                local d = computerDifficulty
                local diffStr = type(d) == "number" and (tostring(d) .. " ELO") or "~1200 ELO"
                table.insert(settingsParts, "AI: " .. diffStr)
            end
            if settings then
                if settings.useClock then
                    table.insert(settingsParts, string.format("Clock: %dm +%ds", 
                        settings.timeMinutes or 10, 
                        settings.incrementSeconds or 0))
                else
                    table.insert(settingsParts, "No clock")
                end
            end
            settingsText:SetText("|cFFAAAAAA" .. table.concat(settingsParts, " | ") .. "|r")

            local resultStr = DeltaChess.UI:GetGameStatusText(board, playerColor)
            entry.statusText:SetText(string.format("%s - %d moves", resultStr, moveCount))

            local pgnBtn = entry.pgnBtn
            pgnBtn:SetScript("OnClick", function()
                DeltaChess:ShowPGNWindow(board)
            end)

            if isActive or isPaused then
                local isHumanWindowHidden = not isVsComputer and not windowShown
                local btnText, btnAction
                if isPaused and not isVsComputer then
                    btnText = "Resume"
                    btnAction = function()
                        self.frames.mainMenu:Hide()
                        DeltaChess:RequestUnpause(gameId)
                        DeltaChess:ShowChessBoard(gameId)
                    end
                elseif isHumanWindowHidden and not isPaused then
                    btnText = "Open"
                    btnAction = function()
                        self.frames.mainMenu:Hide()
                        DeltaChess:ShowChessBoard(gameId)
                    end
                else
                    btnText = "Resume"
                    btnAction = function()
                        self.frames.mainMenu:Hide()
                        DeltaChess:ShowChessBoard(gameId)
                    end
                end
                entry.deleteBtn:Hide()
                entry.replayBtn:Hide()
                entry.resumeBtn:Show()
                entry.resignBtn:Show()
                pgnBtn:Show()
                entry.resumeBtn:SetText(btnText)
                entry.resumeBtn:SetScript("OnClick", btnAction)
                entry.resignBtn:SetScript("OnClick", function()
                    DeltaChess._resignConfirmGameId = gameId
                    DeltaChess.UI:ShowGamePopup(gameId, "CHESS_RESIGN_CONFIRM", nil, gameId)
                    DeltaChess:RefreshMainMenuContent()
                end)
                pgnBtn:ClearAllPoints()
                pgnBtn:SetPoint("RIGHT", entry.resignBtn, "LEFT", -3, 0)
            else
                entry.resumeBtn:Hide()
                entry.resignBtn:Hide()
                entry.deleteBtn:Show()
                entry.replayBtn:Show()
                pgnBtn:Show()
                entry.deleteBtn:SetScript("OnClick", function()
                    DeltaChess:DeleteFromHistory(gameId)
                    DeltaChess:RefreshMainMenuContent()
                end)
                entry.replayBtn:SetScript("OnClick", function()
                    self.frames.mainMenu:Hide()
                    DeltaChess:ShowReplayWindow(board)
                end)
                pgnBtn:ClearAllPoints()
                pgnBtn:SetPoint("RIGHT", entry.replayBtn, "LEFT", -3, 0)
            end
            
            yOffset = yOffset + 74
        end
    end
    
    scrollChild:SetHeight(math.max(yOffset, 100))
end

--------------------------------------------------------------------------------
-- REPLAY WINDOW
--------------------------------------------------------------------------------
function DeltaChess:ShowReplayWindow(board)
    -- Close existing replay window
    if self.frames.replayWindow then
        self.frames.replayWindow:Hide()
    end
    
    local SQUARE_SIZE = 50
    local BOARD_SIZE = SQUARE_SIZE * 8
    local LABEL_SIZE = 20
    local PLAYER_BAR_HEIGHT = 45
    local RIGHT_PANEL_WIDTH = 220
    
    -- Get participant info using shared helper
    local participants = DeltaChess.UI:GetBoardParticipants(board)
    local myName = participants.myName
    local opponentName = participants.opponentName
    local myChessColor = participants.myChessColor
    local opponentChessColor = participants.opponentChessColor
    local myClass = participants.myClass
    local opponentClass = participants.opponentClass
    local flipBoard = participants.flipBoard
    -- Replay always shows time per side: clock if that side has one, else thinking time
    
    -- Replay layout is ChessReplayFrame in Frames/Windows.xml.
    local frame = ChessReplayFrame
    if not frame._wired then
        frame:SetFrameStrata("FULLSCREEN_DIALOG")
        frame:SetFrameLevel(250)
        self:MakeDraggable(frame)
        frame.flipButton:SetScript("OnClick", function()
            frame.flipBoard = not frame.flipBoard
            DeltaChess.UI:RecreateBoardSquares(frame, false)
            DeltaChess.UI:UpdatePlayerBarLabels(frame)
            if frame.RefreshReplayDisplay then
                frame.RefreshReplayDisplay()
            end
        end)
        local historyHeight = PLAYER_BAR_HEIGHT + BOARD_SIZE + LABEL_SIZE + PLAYER_BAR_HEIGHT - 100
        local historyInfo = DeltaChess.UI:BindMoveHistory(frame.rightPanel.history, RIGHT_PANEL_WIDTH, historyHeight)
        frame.historyText = historyInfo.historyText
        frame.rightPanel.closeBtn:SetScript("OnClick", function()
            frame:Hide()
        end)
        frame._wired = true
    end
    frame.TitleText:SetText("Replay")
    self.frames.replayWindow = frame

    -- Store replay state: full board (for GetBoardAtIndex) and move list for history/animation
    frame.replayBoard = board
    frame.moves = {}
    for i, moveData in ipairs(board:GetMoveHistory() or {}) do
        frame.moves[i] = DeltaChessFramework.BoardMove.Wrap(moveData, nil, i)
    end
    frame.currentMoveIndex = 0
    frame.myChessColor = myChessColor
    frame.opponentChessColor = opponentChessColor
    frame.flipBoard = flipBoard

    -- ==================== OPPONENT BAR (TOP) ====================
    local opponentBarInfo = DeltaChess.UI:CreatePlayerBar({
        bar = frame.topBar,
        playerName = opponentName,
        playerClass = opponentClass,
        board = board,
        showClock = true,
        chessColor = opponentChessColor,
    })
    frame.topBarNameText = opponentBarInfo.nameText
    frame.topBarClock = opponentBarInfo.timeDisplay
    frame.topBarCapturedContainer = opponentBarInfo.capturedContainer
    frame.opponentCapturedContainer = opponentBarInfo.capturedContainer
    frame.opponentCapturedColor = myChessColor
    frame.opponentClock = opponentBarInfo.timeDisplay
    frame.opponentClockColor = opponentChessColor

    -- ==================== BOARD ====================
    DeltaChess.UI:RecreateBoardSquares(frame, false)

    -- ==================== PLAYER BAR (BOTTOM) ====================
    local playerBarInfo = DeltaChess.UI:CreatePlayerBar({
        bar = frame.bottomBar,
        playerName = myName,
        playerClass = myClass,
        board = board,
        showClock = true,
        chessColor = myChessColor,
    })
    frame.bottomBarNameText = playerBarInfo.nameText
    frame.bottomBarClock = playerBarInfo.timeDisplay
    frame.bottomBarCapturedContainer = playerBarInfo.capturedContainer
    frame.playerCapturedContainer = playerBarInfo.capturedContainer
    frame.playerCapturedColor = opponentChessColor
    frame.playerClock = playerBarInfo.timeDisplay
    frame.playerClockColor = myChessColor

    -- ==================== RIGHT PANEL ====================
    local rightPanel = frame.rightPanel
    frame.moveLabel = rightPanel.moveLabel
    frame.moveLabel:SetText("Move: 0 / " .. #frame.moves)

    local firstBtn = rightPanel.firstBtn
    local prevBtn = rightPanel.prevBtn
    local nextBtn = rightPanel.nextBtn
    local lastBtn = rightPanel.lastBtn
    
    -- Update display function (animateMove: optional move to animate after rendering)
    local function UpdateReplayBoard(animateMove)
        -- Get board state at current move index (paused snapshot with same opponents/startTime/moves up to index)
        local snapshotBoard = frame.replayBoard:GetBoardAtIndex(frame.currentMoveIndex)
        
        -- Render the field using the snapshot board like the normal board (same rendering path)
        local lastMove = snapshotBoard:GetLastMove()
        DeltaChess.UI:RenderPieces(frame.squares, snapshotBoard, lastMove)
        
        -- Update move counter
        frame.moveLabel:SetText(string.format("Move: %d / %d", frame.currentMoveIndex, #frame.moves))
        
        -- Update move history with highlighting for current move
        local historyStr = DeltaChess.UI:FormatMoveHistoryText(frame.moves, frame.currentMoveIndex)
        frame.historyText:SetText(historyStr)
        
        -- Update captured pieces display from snapshot board
        local myAdvantage = snapshotBoard:CalculateMaterialAdvantage(myChessColor)
        local capturedByWhite = snapshotBoard:GetCapturedPiecesWhite()
        local capturedByBlack = snapshotBoard:GetCapturedPiecesBlack()
        local myCaptured = myChessColor == COLOR.WHITE and capturedByWhite or capturedByBlack
        local opponentCaptured = opponentChessColor == COLOR.WHITE and capturedByWhite or capturedByBlack
        DeltaChess.UI:UpdateCapturedPieces(frame.playerCapturedContainer, myCaptured,
            frame.playerCapturedColor, myAdvantage > 0 and myAdvantage or nil)
        DeltaChess.UI:UpdateCapturedPieces(frame.opponentCapturedContainer, opponentCaptured,
            frame.opponentCapturedColor, (-myAdvantage) > 0 and (-myAdvantage) or nil)
        
        -- Update time per side: remaining clock if that side has a clock, else thinking time
        if frame.playerClock or frame.opponentClock then
            local snapshotTime = (frame.currentMoveIndex == 0) and snapshotBoard:GetStartTime()
                or (frame.moves[frame.currentMoveIndex] and frame.moves[frame.currentMoveIndex]:GetTimestamp())
                or snapshotBoard:GetStartTime()
            if frame.playerClock then
                local myHasClock = (snapshotBoard:GetClock(myChessColor) or 0) > 0
                local myTime = myHasClock and snapshotBoard:TimeLeft(myChessColor, snapshotTime) or snapshotBoard:TimeThinking(myChessColor, snapshotTime)
                frame.playerClock:SetText(DeltaChess.UI:FormatTime(myTime or 0))
                frame.playerClock:Show()
            end
            if frame.opponentClock then
                local oppHasClock = (snapshotBoard:GetClock(opponentChessColor) or 0) > 0
                local oppTime = oppHasClock and snapshotBoard:TimeLeft(opponentChessColor, snapshotTime) or snapshotBoard:TimeThinking(opponentChessColor, snapshotTime)
                frame.opponentClock:SetText(DeltaChess.UI:FormatTime(oppTime or 0))
                frame.opponentClock:Show()
            end
        end
        
        -- Play move sound when advancing (same as game window)
        if animateMove then
            local wasCapture = animateMove:IsCapture()
            -- Snapshot is state after the move; current turn is the side that has to move next, so the side that just moved is the opposite
            local currentTurn = snapshotBoard:GetCurrentTurn()
            local movedColor = (currentTurn == COLOR.WHITE) and COLOR.BLACK or COLOR.WHITE
            local isPlayerMove = (movedColor == frame.myChessColor)
            DeltaChess.Sound:PlayMoveSound(snapshotBoard, isPlayerMove, wasCapture, snapshotBoard)
        end
        
        -- Animate the move if requested
        if animateMove then
            DeltaChess.UI:AnimateReplayMove(frame, animateMove)
        end
    end
    frame.RefreshReplayDisplay = UpdateReplayBoard
    
    -- Button handlers
    firstBtn:SetScript("OnClick", function()
        frame.currentMoveIndex = 0
        UpdateReplayBoard() -- No animation when going to start
    end)
    
    prevBtn:SetScript("OnClick", function()
        if frame.currentMoveIndex > 0 then
            frame.currentMoveIndex = frame.currentMoveIndex - 1
            UpdateReplayBoard() -- No animation when going backward
        end
    end)
    
    nextBtn:SetScript("OnClick", function()
        if frame.currentMoveIndex < #frame.moves then
            frame.currentMoveIndex = frame.currentMoveIndex + 1
            local moveToAnimate = frame.moves[frame.currentMoveIndex]
            UpdateReplayBoard(moveToAnimate) -- Animate the move forward
        end
    end)
    
    lastBtn:SetScript("OnClick", function()
        if frame.currentMoveIndex < #frame.moves then
            local lastMoveToAnimate = frame.moves[#frame.moves]
            frame.currentMoveIndex = #frame.moves
            UpdateReplayBoard(lastMoveToAnimate) -- Animate only the final move
        end
    end)
    
    -- Initial display
    UpdateReplayBoard()
    
    frame:Show()
end

--------------------------------------------------------------------------------
-- PGN WINDOW
--------------------------------------------------------------------------------
function DeltaChess:ShowPGNWindow(board)
    if not board or not board.GetPGN then return end
    local pgn = board:GetPGN()
    if not pgn or pgn == "" then pgn = "(no PGN)" end

    -- PGN layout is ChessPGNFrame in Frames/Windows.xml. The edit box is the scroll child.
    if not self.frames.pgnWindow then
        local frame = ChessPGNFrame
        frame:SetFrameStrata("FULLSCREEN_DIALOG")
        frame:SetFrameLevel(300)  -- Above board (250) so PGN window stays on top
        self:MakeDraggable(frame)
        frame.TitleText:SetText("PGN")
        frame.editBg:SetColorTexture(0.1, 0.1, 0.15, 0.95)

        local scrollFrame = frame.pgnScrollFrame
        local editBox = ChessPGNFrameEditBox or scrollFrame:GetScrollChild()
        if scrollFrame:GetScrollChild() ~= editBox then
            scrollFrame:SetScrollChild(editBox)
        end
        editBox:SetAutoFocus(false)
        editBox:SetFontObject(GameFontHighlightSmall)
        editBox:SetTextInsets(6, 6, 6, 6)
        editBox:SetMaxLetters(99999)
        editBox:SetWidth(400)
        editBox:SetScript("OnEscapePressed", function()
            frame:Hide()
        end)
        editBox:SetScript("OnTextChanged", function(self)
            local sf = self:GetParent()
            sf:UpdateScrollChildRect()
        end)
        editBox:SetScript("OnCursorChanged", function(self, x, y, w, h)
            local sf = self:GetParent()
            local vs = sf:GetVerticalScroll()
            local sfHeight = sf:GetHeight()
            local cursorTop = -y
            local cursorBottom = cursorTop + h
            if cursorTop < vs then
                sf:SetVerticalScroll(cursorTop)
            elseif cursorBottom > vs + sfHeight then
                sf:SetVerticalScroll(cursorBottom - sfHeight)
            end
        end)

        frame.pgnScrollFrame = scrollFrame
        frame.pgnEditBox = editBox
        self.frames.pgnWindow = frame
    end

    local frame = self.frames.pgnWindow
    frame:SetFrameLevel(300)  -- Ensure on top each time we show
    frame.pgnEditBox:SetText(pgn)
    frame.pgnEditBox:SetCursorPosition(0)
    frame.pgnScrollFrame:SetVerticalScroll(0)
    frame:Show()
    frame.pgnEditBox:HighlightText()
    frame.pgnEditBox:SetFocus()
end

--------------------------------------------------------------------------------
-- RECENT OPPONENTS
--------------------------------------------------------------------------------
function DeltaChess:GetRecentOpponents()
    local playerCharName, playerName = self:GetLocalPlayerInfo()
    local opponents = {} -- name -> timestamp

    local function addOpponent(board, isWhite)
        local name = isWhite and board:GetWhitePlayerName() or board:GetBlackPlayerName()
        
        if name and name ~= playerName and name ~= "Computer" then
            local ts = board:GetStartTime() or 0
            if not opponents[name] or ts > opponents[name] then
                opponents[name] = ts
            end
        end
    end

    -- Active games (board IS the game)
    for _, board in pairs(self.db.games) do
        addOpponent(board, true)  -- white
        addOpponent(board, false) -- black
    end
    -- History games (deserialize to board)
    for _, entry in pairs(self.db.history) do
        local board = self:DeserializeHistoryEntry(entry)
        if board then
            addOpponent(board, true)  -- white
            addOpponent(board, false) -- black
        end
    end

    -- Convert to sorted list
    local list = {}
    for name, timestamp in pairs(opponents) do
        table.insert(list, { name = name, timestamp = timestamp })
    end
    table.sort(list, function(a, b) return a.timestamp > b.timestamp end)

    -- Return top 15
    local result = {}
    for i = 1, math.min(15, #list) do
        table.insert(result, list[i].name)
    end
    return result
end

-- Get list of past opponent full names (for ping list)
-- Limit to 5 most recent to reduce "player not online" spam when pinging offline players
function DeltaChess:GetPastOpponentsFullNames()
    local recent = self:GetRecentOpponents()
    local out = {}
    for i = 1, math.min(5, #recent) do
        table.insert(out, recent[i])
    end
    return out
end

-- Get list of online guild member full names
function DeltaChess:GetGuildOnlineFullNames()
    local out = {}
    local myCharName, myName = self:GetLocalPlayerInfo()
    if not IsInGuild() then return out end
    C_GuildInfo.GuildRoster()
    local num = GetNumGuildMembers()
    for i = 1, num do
        local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
        if name and online and name ~= myName then
            local fullName = self:NormalizePlayerName(name)
            table.insert(out, fullName)
        end
    end
    return out
end

-- Get list of party/raid member full names (excludes self)
function DeltaChess:GetPartyFullNames()
    local out = {}
    local myCharName, myName = self:GetLocalPlayerInfo()
    local numGroup = GetNumGroupMembers()
    if numGroup <= 0 then return out end
    local prefix = IsInRaid() and "raid" or "party"
    local count = IsInRaid() and numGroup or (numGroup - 1) -- party units don't include "player"
    for i = 1, count do
        local unit = prefix .. i
        if UnitExists(unit) and UnitIsPlayer(unit) and UnitIsConnected(unit) then
            local fullName = self:GetUnitFullName(unit)
            if fullName then
                if not self:IsSamePlayer(fullName, myName) and not self:IsSamePlayer(fullName, myCharName) then
                    table.insert(out, fullName)
                end
            end
        end
    end
    return out
end

-- Get list of online friends with BattleNet info
-- Returns array of { type="bnet", battleTag, characterName, fullName } or { type="wow", fullName }
function DeltaChess:GetFriendsOnline()
    local out = {}
    local seen = {}
    local myCharName, myName = self:GetLocalPlayerInfo()
    
    -- WoW friend list (non-BNet friends)
    if C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex then
        local num = C_FriendList.GetNumFriends()
        for i = 1, num do
            local info = C_FriendList.GetFriendInfoByIndex(i)
            if info and info.name and info.connected and info.name ~= myName then
                local fullName = self:GetFullPlayerName(info.name)
                if not seen[fullName] then
                    seen[fullName] = true
                    table.insert(out, {
                        type = "wow",
                        fullName = fullName
                    })
                end
            end
        end
    elseif GetNumFriends and GetFriendInfo then
        local num = GetNumFriends()
        for i = 1, num do
            local name, _, _, _, connected = GetFriendInfo(i)
            if name and connected and name ~= myName then
                local fullName = self:GetFullPlayerName(name)
                if not seen[fullName] then
                    seen[fullName] = true
                    table.insert(out, {
                        type = "wow",
                        fullName = fullName
                    })
                end
            end
        end
    end
    
    -- Battle.net friends (online in WoW, same region only)
    local bnetFriends = DeltaChess.Bnet:GetOnlineBattleNetFriends()
    for _, friend in ipairs(bnetFriends) do
        if not seen[friend.battleTag] then
            seen[friend.battleTag] = true
            table.insert(out, {
                type = "bnet",
                battleTag = friend.battleTag,
                characterName = friend.characterName,
                realmName = friend.realmName,
                fullName = friend.fullName
            })
        end
    end
    
    return out
end

-- Legacy function for backwards compatibility
function DeltaChess:GetFriendsOnlineFullNames()
    local friends = self:GetFriendsOnline()
    local out = {}
    for _, friend in ipairs(friends) do
        table.insert(out, friend.fullName)
    end
    return out
end

--------------------------------------------------------------------------------
-- Helper: Format player entry for challenge list (checks if BNet friend)
--------------------------------------------------------------------------------
-- Takes a character full name and returns display info
-- Returns: { displayName, selectValue, battleTag }
function DeltaChess:FormatPlayerEntry(characterFullName)
    if not characterFullName then return nil end
    
    -- Check if this character is a BattleNet friend
    local battleTag = DeltaChess.Bnet:GetBattleTagForCharacter(characterFullName)
    
    if battleTag then
        -- BattleNet friend: show "BattleTag (CharacterName-Realm)"
        local displayName = string.format("%s (%s)", battleTag, characterFullName)
        return {
            displayName = displayName,
            selectValue = battleTag,
            battleTag = battleTag
        }
    else
        -- Regular player: show character name with realm
        return {
            displayName = characterFullName,
            selectValue = characterFullName,
            battleTag = nil
        }
    end
end

--------------------------------------------------------------------------------
-- PLAYER LIST POPUP (online + addon only)
--------------------------------------------------------------------------------
function DeltaChess:ShowPlayerListPopup(source, parentFrame, onSelect)
    -- source: "past", "guild", "friends", "party"
    local candidates = {}
    
    if source == "past" then
        candidates = self:GetPastOpponentsFullNames()
    elseif source == "guild" then
        candidates = self:GetGuildOnlineFullNames()
    elseif source == "friends" then
        local friendsInfo = self:GetFriendsOnline()
        -- Use character full names for ping check, FormatPlayerEntry will convert to BattleTag display
        for _, friendInfo in ipairs(friendsInfo) do
            table.insert(candidates, friendInfo.fullName)
        end
    elseif source == "party" then
        candidates = self:GetPartyFullNames()
    end
    
    -- Filter out self
    local myCharName, myName = self:GetLocalPlayerInfo()
    local filtered = {}
    for _, name in ipairs(candidates) do
        if not self:IsSamePlayer(name, myCharName) and not self:IsSamePlayer(name, myName) then
            table.insert(filtered, name)
        end
    end
    candidates = filtered

    DeltaChess._playerListSeq = (DeltaChess._playerListSeq or 0) + 1
    local popup = CreateFrame("Frame", "DeltaChessPlayerList" .. DeltaChess._playerListSeq, parentFrame, "DeltaChessPlayerListTemplate")
    popup:SetPoint("CENTER", parentFrame, "CENTER", 0, 0)
    -- The template close button is kept well above the window's other children.
    -- A flat parent+50 still leaves that button drawn on top of this popup.
    local function RaiseAboveParentChrome()
        local level = parentFrame:GetFrameLevel() + 20
        local closeButton = parentFrame.CloseButton
        if closeButton then
            level = math.max(level, closeButton:GetFrameLevel() + 5)
        end
        if level > 10000 then
            popup:SetFrameStrata("FULLSCREEN_DIALOG")
            popup:SetFrameLevel(100)
        else
            popup:SetFrameStrata(parentFrame:GetFrameStrata() or "DIALOG")
            popup:SetFrameLevel(level)
        end
    end
    popup:HookScript("OnShow", RaiseAboveParentChrome)
    RaiseAboveParentChrome()
    self:MakeDraggable(popup)
    local titleMap = { past = "Recent", guild = "Guild", friends = "Friends", party = "Party" }
    popup.TitleText:SetText(titleMap[source] or "Select Player")

    local statusText = popup.statusText
    statusText:SetText("Checking who has DeltaChess...")

    local scrollFrame = popup.scrollFrame
    local scrollChild = scrollFrame:GetScrollChild() or scrollFrame.scrollChild or _G[popup:GetName() .. "ScrollScrollChild"]
    if scrollFrame:GetScrollChild() ~= scrollChild then
        scrollFrame:SetScrollChild(scrollChild)
    end
    popup.scrollChild = scrollChild

    if #candidates == 0 then
        statusText:SetText("No players to show.")
        popup:Show()
        return
    end

    popup:Show()
    
    -- Ping players (noBNet=true skips BNet whispers, only shows same-project players)
    -- Party/raid: broadcast one ping on the group channel and use the sender names the
    -- server reports instead of building a whisper target per member.
    local pingFn = function(cb, noBNet)
        if source == "party" and DeltaChess:GetGroupAddonChannel() then
            DeltaChess:PingGroup(cb)
        else
            DeltaChess:PingPlayers(candidates, cb, noBNet)
        end
    end
    pingFn(function(respondedList)
        statusText:SetText(string.format("%d player(s) with DeltaChess online.", #respondedList))
        
        -- If searching party/raid and no players responded, send message to chat
        if source == "party" and #respondedList == 0 and #candidates > 0 then
            local chatChannel = IsInRaid() and "RAID" or "PARTY"
            SendChatMessage("I want to challenge someone to a game of chess. Install Delta Chess from Curseforge so that we can play together: https://www.curseforge.com/wow/addons/deltachess", chatChannel)
        end
        
        for _, child in ipairs({ scrollChild:GetChildren() }) do
            child:Hide()
            child:SetParent(nil)
        end
        local y = 0
        for _, entry in ipairs(respondedList) do
            local fullName = entry.fullName
            local dnd = entry.dnd
            
            -- Format entry using shared helper (checks against BNet friends list)
            local entryInfo = self:FormatPlayerEntry(fullName)
            if not entryInfo then
                entryInfo = {
                    displayName = fullName,
                    selectValue = fullName
                }
            end
            
            local displayName = entryInfo.displayName
            local selectValue = entryInfo.selectValue
            
            if dnd then
                displayName = displayName .. " |cFFFF6666(DND)|r"
            end
            
            local btn = CreateFrame("Button", nil, scrollChild, "DeltaChessPlayerRowTemplate")
            btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
            btn.label:SetText(displayName)
            btn:SetScript("OnClick", function()
                if onSelect then onSelect(selectValue) end
                popup:Hide()
                popup:SetParent(nil)
                popup:ClearAllPoints()
            end)
            y = y + 26
        end
        scrollChild:SetHeight(y)
        popup:Show()
    end, true)
    popup:Show()
end

--------------------------------------------------------------------------------
-- CHALLENGE WINDOW
--------------------------------------------------------------------------------
function DeltaChess:ShowChallengeWindow(targetPlayer)
    -- Close existing window if open
    if self.frames.challengeWindow and self.frames.challengeWindow:IsShown() then
        self.frames.challengeWindow:Hide()
    end
    
    -- Challenge layout is ChessChallengeWindow in Frames/Windows.xml.
    if not self.frames.challengeWindow then
        local frame = ChessChallengeWindow
        local BASE_CHALLENGE_HEIGHT = 320
        frame:SetFrameStrata("DIALOG")
        frame:SetFrameLevel(150)
        self:MakeDraggable(frame)
        frame.TitleText:SetText("Challenge Player")
        frame.nameInput:SetAutoFocus(false)

        frame.pastBtn:SetScript("OnClick", function()
            DeltaChess:ShowPlayerListPopup("past", frame, function(fullName)
                frame.nameInput:SetText(fullName)
            end)
        end)
        frame.guildBtn:SetScript("OnClick", function()
            DeltaChess:ShowPlayerListPopup("guild", frame, function(fullName)
                frame.nameInput:SetText(fullName)
            end)
        end)
        frame.friendsBtn:SetScript("OnClick", function()
            DeltaChess:ShowPlayerListPopup("friends", frame, function(selectValue)
                frame.nameInput:SetText(selectValue)
            end)
        end)
        frame.partyBtn:SetScript("OnClick", function()
            DeltaChess:ShowPlayerListPopup("party", frame, function(fullName)
                frame.nameInput:SetText(fullName)
            end)
        end)

        frame.selectedColor = "random"
        local whiteBtn = frame.whiteBtn
        local blackBtn = frame.blackBtn
        local randomBtn = frame.randomBtn

        local function updateColorButtons()
            whiteBtn:SetEnabled(frame.selectedColor ~= COLOR.WHITE)
            blackBtn:SetEnabled(frame.selectedColor ~= COLOR.BLACK)
            randomBtn:SetEnabled(frame.selectedColor ~= "random")
        end

        whiteBtn:SetScript("OnClick", function()
            frame.selectedColor = COLOR.WHITE
            updateColorButtons()
        end)
        blackBtn:SetScript("OnClick", function()
            frame.selectedColor = COLOR.BLACK
            updateColorButtons()
        end)
        randomBtn:SetScript("OnClick", function()
            frame.selectedColor = "random"
            updateColorButtons()
        end)
        updateColorButtons()

        DeltaChess.UI:CreateClockConfigPanel(frame, {
            showHandicap = true,
            onResize = function(extraHeight)
                frame:SetHeight(BASE_CHALLENGE_HEIGHT + extraHeight)
            end,
        })

        local sendBtn = frame.sendBtn
        sendBtn:SetScript("OnClick", function()
            local input = frame.nameInput:GetText()
            if not input or input == "" then
                DeltaChess:Print("Please enter a player name!")
                return
            end
            
            local target = input
            local battleTag = nil
            
            -- Check if input is a BattleTag (contains #)
            if input:find("#") then
                battleTag = input
                target = input  -- Use BattleTag as target
            else
                -- Regular character name - normalize to the form used for addon messages
                target = DeltaChess:NormalizePlayerName(input)
                
                -- Cannot challenge yourself
                local myCharName, myName = DeltaChess:GetLocalPlayerInfo()
                if DeltaChess:IsSamePlayer(target, myCharName) or DeltaChess:IsSamePlayer(target, myName) then
                    DeltaChess:Print("You cannot challenge yourself!")
                    return
                end
                
                -- Check if this character is a BattleNet friend
                battleTag = DeltaChess.Bnet:GetBattleTagForCharacter(target)
            end
            
            sendBtn:SetEnabled(false)
            sendBtn:SetText("Checking...")
            
            -- PingPlayer will validate and handle BattleTag resolution automatically
            DeltaChess:PingPlayer(target, function(hasAddon)
                sendBtn:SetEnabled(true)
                sendBtn:SetText("Send Challenge")
                if not hasAddon then
                    DeltaChess:Print("|cFFFF0000Player doesn't have DeltaChess installed or is offline.|r")
                    -- Send chat whisper (handles both BattleTag and character name)
                    DeltaChess.Bnet:SendChatWhisper(
                        "I want to challenge you to a game of chess but you dont have Delta Chess installed :( Download from Curseforge so that we can play together: https://www.curseforge.com/wow/addons/deltachess",
                        target
                    )
                    return
                end
                
                local wasRandom = frame.selectedColor == "random"
                local finalColor = frame.selectedColor
                if finalColor == "random" then
                    finalColor = math.random(2) == 1 and COLOR.WHITE or COLOR.BLACK
                end
                
                local handicapSeconds = (frame.handicapCheck and frame.handicapCheck:GetChecked() and frame.handicapSecondsSlider) and math.floor(frame.handicapSecondsSlider:GetValue()) or 0
                -- Resolve "challenger"/"opponent" to "white"/"black" based on the challenger's color
                local handicapSide = nil
                if frame.handicapSide == "challenger" then
                    handicapSide = finalColor  -- challenger's color gets less time
                elseif frame.handicapSide == "opponent" then
                    handicapSide = (finalColor == COLOR.WHITE) and COLOR.BLACK or COLOR.WHITE
                end
                local gameSettings = {
                    -- challenger will be set from sender in OnCommReceived
                    opponent = target,  -- BattleTag or character name
                    opponentBattleTag = battleTag,  -- Store BattleTag if friend
                    challengerColor = finalColor,
                    isRandom = wasRandom,
                    useClock = frame.clockCheck:GetChecked(),
                    timeMinutes = math.floor(frame.timeSlider:GetValue()),
                    incrementSeconds = math.floor(frame.incSlider:GetValue()),
                    handicapSeconds = (handicapSeconds > 0) and handicapSeconds or nil,
                    handicapSide = handicapSide,
                }
                
                DeltaChess:SendChallenge(gameSettings)
                frame:Hide()
            end)
        end)
        
        frame.cancelBtn:SetScript("OnClick", function()
            frame:Hide()
        end)

        self.frames.challengeWindow = frame
    end
    
    -- Reset values (pre-fill with target if no player specified)
    if not targetPlayer or targetPlayer == "" then
        if UnitExists("target") and UnitIsPlayer("target") then
            local targetName = self:GetUnitFullName("target")
            local myCharName, myName = self:GetLocalPlayerInfo()
            if targetName ~= myCharName and targetName ~= myName then
                targetPlayer = targetName
            end
        end
    end
    
    -- If target is a BNet friend, use BattleTag instead of character name
    if targetPlayer and not targetPlayer:find("#") then
        local battleTag = DeltaChess.Bnet:GetBattleTagForCharacter(targetPlayer)
        if battleTag then
            targetPlayer = battleTag
        end
    end
    
    self.frames.challengeWindow.nameInput:SetText(targetPlayer or "")
    self.frames.challengeWindow.selectedColor = "random"
    self.frames.challengeWindow.clockCheck:SetChecked(false)
    self.frames.challengeWindow.timeSlider:SetValue(10)
    self.frames.challengeWindow.incSlider:SetValue(0)
    if self.frames.challengeWindow.handicapCheck then
        self.frames.challengeWindow.handicapCheck:SetChecked(false)
        self.frames.challengeWindow.handicapSide = "challenger"
        UIDropDownMenu_SetText(self.frames.challengeWindow.handicapSideDropdown, "Challenger")
        self.frames.challengeWindow.handicapSecondsSlider:SetValue(0)
    end
    -- Update visibility and frame height to match reset checkbox states
    if self.frames.challengeWindow.UpdateClockLayout then
        self.frames.challengeWindow.UpdateClockLayout()
    end
    
    -- Update color buttons
    local frame = self.frames.challengeWindow
    for _, child in ipairs({frame:GetChildren()}) do
        if child:IsObjectType("Button") then
            local text = child:GetText()
            if text == "White" then child:SetEnabled(true)
            elseif text == "Black" then child:SetEnabled(true)
            elseif text == "Random" then child:SetEnabled(false)
            end
        end
    end
    
    self.frames.challengeWindow:Show()
end

-- For backwards compatibility
function DeltaChess:ShowChallengeDialog(targetPlayer)
    self:ShowChallengeWindow(targetPlayer)
end

--------------------------------------------------------------------------------
-- COMPUTER GAME WINDOW
--------------------------------------------------------------------------------
function DeltaChess:ShowComputerGameWindow()
    -- Close existing window if open
    if self.frames.computerWindow and self.frames.computerWindow:IsShown() then
        self.frames.computerWindow:Hide()
    end
    
    -- Computer-game layout is ChessComputerWindow in Frames/Windows.xml.
    if not self.frames.computerWindow then
        local frame = ChessComputerWindow
        frame:SetFrameStrata("DIALOG")
        frame:SetFrameLevel(150)
        self:MakeDraggable(frame)
        frame.TitleText:SetText("Play vs Computer")

        frame.selectedColor = COLOR.WHITE
        local whiteBtn = frame.whiteBtn
        local blackBtn = frame.blackBtn
        local randomBtn = frame.randomBtn
        whiteBtn:SetEnabled(false)

        local function updateColorButtons()
            whiteBtn:SetEnabled(frame.selectedColor ~= COLOR.WHITE)
            blackBtn:SetEnabled(frame.selectedColor ~= COLOR.BLACK)
            randomBtn:SetEnabled(frame.selectedColor ~= "random")
        end

        whiteBtn:SetScript("OnClick", function()
            frame.selectedColor = COLOR.WHITE
            updateColorButtons()
        end)
        blackBtn:SetScript("OnClick", function()
            frame.selectedColor = COLOR.BLACK
            updateColorButtons()
        end)
        randomBtn:SetScript("OnClick", function()
            frame.selectedColor = "random"
            updateColorButtons()
        end)

        local globalRange = DeltaChessFramework.Engines:GetGlobalEloRange()
        local hasEloEngines = (globalRange ~= nil)

        frame.selectedDifficulty = 1200
        local diffValue = frame.diffValueText
        diffValue:SetText("1200")

        local diffSlider = frame.diffSlider
        if hasEloEngines then
            diffSlider:SetMinMaxValues(globalRange[1], globalRange[2])
            diffSlider:SetValue(math.max(globalRange[1], math.min(globalRange[2], 1200)))
            diffSlider.Low:SetText(tostring(globalRange[1]))
            diffSlider.High:SetText(tostring(globalRange[2]))
        else
            diffSlider:SetMinMaxValues(100, 2500)
            diffSlider:SetValue(1200)
            diffSlider.Low:SetText("100")
            diffSlider.High:SetText("2500")
            diffSlider:Disable()
        end
        diffSlider:SetValueStep(100)
        diffSlider:SetObeyStepOnDrag(true)

        local diffDesc = frame.diffDesc
        diffDesc:SetWidth(260)
        diffDesc:SetJustifyH("LEFT")
        diffDesc:SetWordWrap(true)

        frame.selectedEngine = DeltaChessFramework.Engines:GetEffectiveDefaultId()
        local engineDropdown = frame.engineDropdown
        UIDropDownMenu_SetWidth(engineDropdown, 265)

        local engineDescLabel = frame.engineDescLabel
        engineDescLabel:SetWidth(250)
        engineDescLabel:SetJustifyH("LEFT")
        engineDescLabel:SetWordWrap(true)
        engineDescLabel:SetTextColor(0.7, 0.7, 0.7)
        
        -- Function to update engine description
        local function updateEngineDescription(engineId)
            local engine = DeltaChessFramework.Engines:Get(engineId)
            if engine then
                local desc = engine.description or ""
                if engine.author then
                    desc = desc .. " (by " .. engine.author
                    if engine.portedBy then
                        desc = desc .. ", Lua port: " .. engine.portedBy
                    end
                    desc = desc .. ")"
                elseif engine.portedBy then
                    desc = desc .. " (Lua port: " .. engine.portedBy .. ")"
                end
                engineDescLabel:SetText(desc)
            else
                engineDescLabel:SetText("")
            end
        end
        frame.updateEngineDescription = updateEngineDescription
        
        -- Helper function to get display name with ELO range
        local function getEngineDisplayName(engineId)
            local engine = DeltaChessFramework.Engines:Get(engineId)
            if not engine then return "Select Engine" end
            local range = DeltaChessFramework.Engines:GetEloRange(engineId)
            if range then
                return engine.name .. " (" .. range[1] .. "-" .. range[2] .. ")"
            else
                return engine.name .. " (no ELO)"
            end
        end
        frame.getEngineDisplayName = getEngineDisplayName
        
        -- Function to update engine dropdown based on selected ELO
        local function updateEngineDropdownForElo(elo, startButton)
            local availableEngines = DeltaChessFramework.Engines:GetEnginesForElo(elo)
            
            -- List is sorted by CPU efficiency (fastest first), then by ELO support
            -- Find the most efficient engine with ELO support
            local bestEngine = nil
            for _, eng in ipairs(availableEngines) do
                if eng.hasEloSupport then
                    bestEngine = eng
                    break  -- First ELO-supporting engine is most efficient
                end
            end
            
            -- If no ELO-supporting engine available, use first available (no-ELO engines)
            if not bestEngine and #availableEngines > 0 then
                bestEngine = availableEngines[1]
            end
            
            -- Always select the most efficient engine when slider changes
            if bestEngine then
                frame.selectedEngine = bestEngine.id
            else
                frame.selectedEngine = nil
            end
            
            -- Enable/disable dropdown and start button based on availability
            if #availableEngines == 0 then
                UIDropDownMenu_DisableDropDown(engineDropdown)
                UIDropDownMenu_SetText(engineDropdown, "No engine available")
                engineDescLabel:SetText("")
                if startButton then startButton:Disable() end
                if frame.engineLabel then frame.engineLabel:SetTextColor(0.5, 0.5, 0.5, 1) end
            else
                UIDropDownMenu_EnableDropDown(engineDropdown)
                UIDropDownMenu_SetSelectedValue(engineDropdown, frame.selectedEngine)
                UIDropDownMenu_SetText(engineDropdown, getEngineDisplayName(frame.selectedEngine))
                updateEngineDescription(frame.selectedEngine)
                if startButton then startButton:Enable() end
                if frame.engineLabel then frame.engineLabel:SetTextColor(1, 0.82, 0, 1) end
            end
            
            -- Re-initialize dropdown with filtered engines
            UIDropDownMenu_Initialize(engineDropdown, function(self, level)
                local info = UIDropDownMenu_CreateInfo()
                local filteredEngines = DeltaChessFramework.Engines:GetEnginesForElo(frame.selectedDifficulty or 1200)
                for _, eng in ipairs(filteredEngines) do
                    local engineId = eng.id
                    local displayName = getEngineDisplayName(engineId)
                    info.text = displayName
                    info.value = engineId
                    info.checked = (frame.selectedEngine == engineId)
                    info.func = function()
                        UIDropDownMenu_SetSelectedValue(engineDropdown, engineId)
                        UIDropDownMenu_SetText(engineDropdown, displayName)
                        frame.selectedEngine = engineId
                        updateEngineDescription(engineId)
                    end
                    UIDropDownMenu_AddButton(info)
                end
            end)
        end
        frame.updateEngineDropdownForElo = updateEngineDropdownForElo

        local openingBookCheck = frame.openingBookCheck
        SetCheckLabel(openingBookCheck, "Use opening book")
        openingBookCheck:SetChecked(true)

        local openingBookList = frame.openingBookList
        openingBookList:ClearAllPoints()
        openingBookList:SetPoint("TOPLEFT", openingBookCheck, "BOTTOMLEFT", 5, 0)
        openingBookList:SetWidth(250)
        openingBookList:SetJustifyH("LEFT")
        openingBookList:SetJustifyV("TOP")
        openingBookList:SetWordWrap(true)
        openingBookList:SetTextColor(0.6, 0.6, 0.6)

        local function updateOpeningBookList(elo)
            local OpeningBook = DeltaChessFramework.OpeningBook
            if not OpeningBook or not OpeningBook.IsAvailable() then
                openingBookCheck:SetChecked(false)
                openingBookCheck:Disable()
                openingBookList:SetText("Opening book library not available")
                return
            end
            openingBookCheck:Enable()
            local books = OpeningBook.GetBooksForElo(elo)
            if not books or #books == 0 then
                openingBookList:SetText("No books for this ELO")
                return
            end
            local names = {}
            for i = 1, #books do
                names[i] = books[i].name or books[i].id
            end
            openingBookList:SetText(table.concat(names, ", "))
        end
        frame.updateOpeningBookList = updateOpeningBookList
        
        -- Slider OnValueChanged handler
        diffSlider:SetScript("OnValueChanged", function(self, value)
            local gRange = DeltaChessFramework.Engines:GetGlobalEloRange()
            if not gRange then return end
            local minVal, maxVal = gRange[1], gRange[2]
            local elo = math.floor((value + 50) / 100) * 100
            elo = math.max(minVal, math.min(maxVal, elo))
            frame.selectedDifficulty = elo
            frame.diffValueText:SetText(tostring(elo))
            -- Update engine dropdown based on new ELO
            if frame.updateEngineDropdownForElo then
                frame.updateEngineDropdownForElo(elo, frame.startButton)
            end
            if frame.updateOpeningBookList then
                frame.updateOpeningBookList(elo)
            end
        end)
        
        frame.startButton:SetScript("OnClick", function()
            local color = frame.selectedColor
            if color == "random" then
                color = math.random(2) == 1 and COLOR.WHITE or COLOR.BLACK
            end
            local settings = {
                useClock = false,
                useOpeningBook = openingBookCheck:GetChecked() and true or false,
            }
            frame:Hide()
            DeltaChess:StartComputerGame(color, frame.selectedDifficulty, frame.selectedEngine, settings)
        end)
        frame.cancelBtn:SetScript("OnClick", function()
            frame:Hide()
        end)
        
        self.frames.computerWindow = frame
    end
    
    -- Reset to defaults
    local frame = self.frames.computerWindow
    frame.selectedColor = COLOR.WHITE
    frame.selectedEngine = DeltaChessFramework.Engines:GetEffectiveDefaultId()
    frame.selectedDifficulty = 1200
    
    -- Reset slider to global range and default value
    local globalRange = DeltaChessFramework.Engines:GetGlobalEloRange()
    if globalRange and frame.diffSlider then
        frame.diffSlider:SetMinMaxValues(globalRange[1], globalRange[2])
        frame.diffSlider.Low:SetText(tostring(globalRange[1]))
        frame.diffSlider.High:SetText(tostring(globalRange[2]))
        frame.diffSlider:SetValue(math.max(globalRange[1], math.min(globalRange[2], 1200)))
        frame.diffSlider:Enable()
        frame.diffValueText:SetText(tostring(frame.selectedDifficulty))
        frame.diffValueText:SetTextColor(1, 1, 1, 1)
        if frame.diffLabel then frame.diffLabel:SetTextColor(1, 0.82, 0, 1) end
        if frame.diffDesc then frame.diffDesc:SetTextColor(0.5, 0.5, 0.5, 1) end
    elseif frame.diffSlider then
        -- No engines with ELO support
        frame.diffSlider:Disable()
        frame.diffValueText:SetText("N/A")
        frame.diffValueText:SetTextColor(0.5, 0.5, 0.5, 1)
        if frame.diffLabel then frame.diffLabel:SetTextColor(0.5, 0.5, 0.5, 1) end
        if frame.diffDesc then frame.diffDesc:SetTextColor(0.4, 0.4, 0.4, 1) end
        frame.selectedDifficulty = nil
    end
    
    -- Update engine dropdown based on selected ELO
    if frame.updateEngineDropdownForElo then
        frame.updateEngineDropdownForElo(frame.selectedDifficulty or 1200, frame.startButton)
    end

    if frame.openingBookCheck then
        local OpeningBook = DeltaChessFramework.OpeningBook
        local booksAvailable = OpeningBook and OpeningBook.IsAvailable()
        frame.openingBookCheck:SetChecked(booksAvailable and true or false)
        if booksAvailable then
            frame.openingBookCheck:Enable()
        else
            frame.openingBookCheck:Disable()
        end
    end
    if frame.updateOpeningBookList then
        frame.updateOpeningBookList(frame.selectedDifficulty or 1200)
    end
    
    -- Update color button states
    local frame = self.frames.computerWindow
    for _, child in ipairs({frame:GetChildren()}) do
        if child:IsObjectType("Button") then
            local text = child:GetText()
            if text == "White" then child:SetEnabled(false)
            elseif text == "Black" then child:SetEnabled(true)
            elseif text == "Random" then child:SetEnabled(true)
            end
        end
    end
    
    self.frames.computerWindow:Show()
end

--------------------------------------------------------------------------------
-- CHALLENGE RECEIVED POPUP
--------------------------------------------------------------------------------
StaticPopupDialogs["CHESS_CHALLENGE_RECEIVED"] = {
    text = "%s has challenged you to a game of chess!\n\n%s\n\nDo you accept?",
    button1 = "Accept",
    button2 = "Decline",
    OnAccept = function(self, data)
        DeltaChess:AcceptChallenge(data)
    end,
    OnCancel = function(self, data)
        DeltaChess:DeclineChallenge(data)
    end,
    timeout = 60,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CHESS_RESIGN_CONFIRM"] = {
    text = "%s\n\nAre you sure you want to resign?",
    button1 = "Resign",
    button2 = "Cancel",
    OnShow = function(dialog)
        -- Show above the board and PGN window
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetFrameLevel(350)
        DeltaChess._actionBlocked = (DeltaChess._actionBlocked or 0) + 1
        if DeltaChess.UI.activeFrame then
            DeltaChess.UI:UpdateBoard(DeltaChess.UI.activeFrame)
        end
    end,
    OnHide = function()
        local gameId = DeltaChess._resignConfirmGameId
        DeltaChess._resignConfirmGameId = nil
        DeltaChess._actionBlocked = math.max(0, (DeltaChess._actionBlocked or 0) - 1)
        if DeltaChess.UI.activeFrame then
            DeltaChess.UI:UpdateBoard(DeltaChess.UI.activeFrame)
        end
    end,
    OnAccept = function(self, gameId)
        if gameId then
            DeltaChess:ResignGame(gameId)
            -- Refresh history window to show game as completed
            DeltaChess:RefreshMainMenuContent()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CHESS_PAUSE_REQUEST"] = {
    text = "%s\n\nYour opponent wants to pause the game. Do you accept?",
    button1 = "Accept",
    button2 = "Decline",
    OnShow = function(dialog)
        -- Ensure popup appears above the board
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetFrameLevel(350)
    end,
    OnAccept = function(self, popupData)
        local board = DeltaChess.GetBoard(popupData.gameId)
        if board then
            board:PauseGame()
            board:SetGameMeta("pauseStartTime", DeltaChessFramework.Util.TimeNow())
            board:SetGameMeta("_lastMoveCountWhenPaused", board:GetHalfMoveCount())
            DeltaChess:SendPauseResponse(popupData.gameId, true)
            DeltaChess:Print("Game paused.")
            if DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == popupData.gameId then
                DeltaChess.UI:UpdateBoard(DeltaChess.UI.activeFrame)
            end
            DeltaChess:RefreshMainMenuContent()
        end
    end,
    OnCancel = function(self, popupData)
        DeltaChess:SendPauseResponse(popupData.gameId, false)
    end,
    timeout = 30,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CHESS_UNPAUSE_REQUEST"] = {
    text = "%s\n\nYour opponent wants to resume the game. Do you accept?",
    button1 = "Accept",
    button2 = "Decline",
    OnShow = function(dialog)
        -- Ensure popup appears above the board
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetFrameLevel(350)
    end,
    OnAccept = function(self, popupData)
        local board = DeltaChess.GetBoard(popupData.gameId)
        if board then
            local pauseStartTime = board:GetGameMeta("pauseStartTime")
            local now = DeltaChessFramework.Util.TimeNow()
            local increment = pauseStartTime and (now - pauseStartTime) or 0
            local timeSpentClosed = (board:GetGameMeta("timeSpentClosed") or 0) + increment
            board:SetGameMeta("timeSpentClosed", timeSpentClosed)
            board:ContinueGame()
            board:SetGameMeta("pauseStartTime", nil)
            DeltaChess:SendUnpauseResponse(popupData.gameId, true, increment)
            DeltaChess:Print("Game resumed.")
            if DeltaChess.UI.activeFrame and DeltaChess.UI.activeFrame.gameId == popupData.gameId then
                DeltaChess.UI:UpdateBoard(DeltaChess.UI.activeFrame)
            end
            DeltaChess:RefreshMainMenuContent()
        end
    end,
    OnCancel = function(self, popupData)
        DeltaChess:SendUnpauseResponse(popupData.gameId, false)
    end,
    timeout = 30,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

--------------------------------------------------------------------------------
-- OTHER MENU FUNCTIONS
--------------------------------------------------------------------------------

-- Show active games
function DeltaChess:ShowActiveGames()
    local hasActiveGames = false
    self:Print("Active Games:")
    for gameId, board in pairs(self.db.games) do
        if board:IsActive() then
            hasActiveGames = true
            local white = board:GetWhitePlayerName()
            local black = board:GetBlackPlayerName()
            self:Print(string.format("  %s vs %s (ID: %s)", white, black, gameId))
        end
    end
    
    if not hasActiveGames then
        self:Print("  No active games")
    end
end

-- Show game history
function DeltaChess:ShowGameHistory()
    self:Print("Game History:")
    local list = {}
    for _, entry in pairs(self.db.history) do
        table.insert(list, entry)
    end
    if #list == 0 then
        self:Print("  No game history")
    else
        table.sort(list, function(a, b)
            return (a.endTime or a.startTime or 0) > (b.endTime or b.startTime or 0)
        end)
        local count = math.min(10, #list)
        for i = 1, count do
            local board = self:DeserializeHistoryEntry(list[i])
            if board then
                self:Print(string.format("  %s vs %s - %s (%s)",
                    board:GetWhitePlayerName() or "?",
                    board:GetBlackPlayerName() or "?",
                    board:GetGameResult() or "Unknown",
                    board:GetStartDateString() or "Unknown"))
            end
        end
        if #list > 10 then
            self:Print(string.format("  ... and %d more games", #list - 10))
        end
    end
end

-- Show settings
function DeltaChess:ShowSettings()
    self:Print("DeltaChess Settings:")
    self:Print(string.format("  Minimap Button: %s", self.db.settings.showMinimapButton and "Enabled" or "Disabled"))
    self:Print("  Use '/chess minimap' to toggle the minimap button")
end

-- Show game replay
function DeltaChess:ShowGameReplay(game)
    self:Print("Game replay feature coming soon!")
end
