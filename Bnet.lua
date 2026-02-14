-- Bnet.lua - BattleNet friend management and communication helpers

DeltaChess.Bnet = DeltaChess.Bnet or {}

--------------------------------------------------------------------------------
-- BattleNet Friend Lookup Functions
--------------------------------------------------------------------------------

--- Get player's own BattleTag
-- @return string|nil Player's BattleTag (e.g., "PlayerName#1234") or nil if not available
function DeltaChess.Bnet:GetMyBattleTag()
    if not BNGetInfo then
        return nil
     end
     
     local presenceID, toonID = BNGetInfo()
     
     if not toonID then
        return nil
     end
     
     return toonID
end

--- Get current online character name for a BattleTag (for display purposes)
-- Returns character name regardless of WoW project ID (Classic, Retail, etc.)
-- @param battleTag string BattleTag (e.g., "FriendName#1234")
-- @return string|nil Current character full name (CharName-Realm) or nil if offline
function DeltaChess.Bnet:GetCurrentCharacterForDisplay(battleTag)
    if not battleTag or battleTag == "" then return nil end
    
    if not (BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo and C_BattleNet.GetFriendGameAccountInfo) then
        return nil
    end
    
    local wowClient = BNET_CLIENT_WOW or "WoW"
    local numFriends = BNGetNumFriends()
    
    for i = 1, numFriends do
        local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
        if accountInfo and accountInfo.battleTag == battleTag then
            -- Found the friend, now get their current WoW character
            local numGameAccounts = C_BattleNet.GetFriendNumGameAccounts(i) or 0
            for j = 1, numGameAccounts do
                local gameAccountInfo = C_BattleNet.GetFriendGameAccountInfo(i, j)
                if gameAccountInfo and gameAccountInfo.isOnline and gameAccountInfo.clientProgram == wowClient and gameAccountInfo.characterName then
                    local realm = gameAccountInfo.realmDisplayName or gameAccountInfo.realmName
                    local fullName = realm and (gameAccountInfo.characterName .. "-" .. realm) or DeltaChess:GetFullPlayerName(gameAccountInfo.characterName)
                    return fullName
                end
            end
            -- Friend found but not online in WoW or in a different region
            return nil
        end
    end
    
    -- Friend not found in friends list
    return nil
end

--- Get current online character name for a BattleTag (for addon communication)
-- Only returns character if they're on the same WoW project ID (Retail, Classic, etc.)
-- @param battleTag string BattleTag (e.g., "FriendName#1234")
-- @return string|nil Current character full name (CharName-Realm) or nil if offline/different project
function DeltaChess.Bnet:GetCurrentCharacterForBattleTag(battleTag)
    if not battleTag or battleTag == "" then return nil end
    
    if not (BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo and C_BattleNet.GetFriendGameAccountInfo) then
        return nil
    end
    
    local wowClient = BNET_CLIENT_WOW or "WoW"
    local myProjectID = WOW_PROJECT_ID or 1
    local numFriends = BNGetNumFriends()
    
    for i = 1, numFriends do
        local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
        if accountInfo and accountInfo.battleTag == battleTag then
            -- Found the friend, now get their current WoW character
            local numGameAccounts = C_BattleNet.GetFriendNumGameAccounts(i) or 0
            for j = 1, numGameAccounts do
                local gameAccountInfo = C_BattleNet.GetFriendGameAccountInfo(i, j)
                if gameAccountInfo and gameAccountInfo.isOnline and gameAccountInfo.clientProgram == wowClient and gameAccountInfo.characterName then
                    if gameAccountInfo.isInCurrentRegion == false then
                        -- Skip cross-region characters
                    elseif gameAccountInfo.wowProjectID and gameAccountInfo.wowProjectID ~= myProjectID then
                        -- Skip different WoW project (e.g., friend is on Classic, we're on Retail)
                    else
                        local realm = gameAccountInfo.realmDisplayName or gameAccountInfo.realmName
                        local fullName = realm and (gameAccountInfo.characterName .. "-" .. realm) or DeltaChess:GetFullPlayerName(gameAccountInfo.characterName)
                        return fullName
                    end
                end
            end
            -- Friend found but not online in same WoW project or in a different region
            return nil
        end
    end
    
    -- Friend not found in friends list
    return nil
end

--- Get BattleNet account ID for a BattleTag
-- @param battleTag string BattleTag (e.g., "FriendName#1234")
-- @return number|nil BattleNet account ID or nil if not found
function DeltaChess.Bnet:GetBNetAccountIDForBattleTag(battleTag)
    if not battleTag or battleTag == "" then return nil end
    
    if not (BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo) then
        return nil
    end
    
    local numFriends = BNGetNumFriends()
    for i = 1, numFriends do
        local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
        if accountInfo and accountInfo.battleTag == battleTag then
            return accountInfo.bnetAccountID
        end
    end
    
    return nil
end

--- Get BattleTag for a BattleNet sender ID
-- @param bnSenderID number BattleNet sender ID from CHAT_MSG_BN_WHISPER event
-- @return string|nil BattleTag (FriendName#1234) or nil if not found
function DeltaChess.Bnet:GetBattleTagForBNSenderID(bnSenderID)
    if not bnSenderID then return nil end
    
    if not (C_BattleNet and C_BattleNet.GetAccountInfoByID) then
        return nil
    end
    
    -- C_BattleNet.GetFriendAccountInfo can take bnetAccountID directly
    local accountInfo = C_BattleNet.GetAccountInfoByID(bnSenderID)
    if accountInfo and accountInfo.battleTag then
        return accountInfo.battleTag
    end
    
    return nil
end

--- Get BattleTag for a character name (if they are a BNet friend)
-- @param characterFullName string Character full name (CharName-Realm)
-- @return string|nil BattleTag (FriendName#1234) or nil if not a BNet friend
function DeltaChess.Bnet:GetBattleTagForCharacter(characterFullName)
    if not characterFullName then return nil end
    
    if not (BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo and C_BattleNet.GetFriendGameAccountInfo) then
        return nil
    end
    
    local numFriends = BNGetNumFriends()
    for i = 1, numFriends do
        local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
        if accountInfo then
            local numGameAccounts = C_BattleNet.GetFriendNumGameAccounts(i) or 0
            for j = 1, numGameAccounts do
                local gameAccountInfo = C_BattleNet.GetFriendGameAccountInfo(i, j)
                if gameAccountInfo and gameAccountInfo.characterName then
                    local realm = gameAccountInfo.realmDisplayName or gameAccountInfo.realmName
                    local fullName = realm and (gameAccountInfo.characterName .. "-" .. realm) or DeltaChess:GetFullPlayerName(gameAccountInfo.characterName)
                    if fullName == characterFullName then
                        return accountInfo.battleTag
                    end
                end
            end
        end
    end
    
    return nil
end

--- Check if a BattleTag exists in friends list
-- @param battleTag string BattleTag (e.g., "FriendName#1234")
-- @return boolean True if friend exists
function DeltaChess.Bnet:IsBattleNetFriend(battleTag)
    if not battleTag or battleTag == "" then return false end
    
    if not (BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo) then
        return false
    end
    
    local numFriends = BNGetNumFriends()
    for i = 1, numFriends do
        local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
        if accountInfo and accountInfo.battleTag == battleTag then
            return true
        end
    end
    
    return false
end

--- Get list of all online BattleNet friends playing WoW
-- @return table Array of { battleTag, characterName, realmName, fullName }
function DeltaChess.Bnet:GetOnlineBattleNetFriends()
    local out = {}
    local seen = {}
    
    if not (BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo and C_BattleNet.GetFriendNumGameAccounts and C_BattleNet.GetFriendGameAccountInfo) then
        return out
    end
    
    local wowClient = BNET_CLIENT_WOW or "WoW"
    local myCharName, myName = DeltaChess:GetLocalPlayerInfo()
    
    for i = 1, BNGetNumFriends() do
        local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
        if accountInfo and accountInfo.battleTag then
            local numGameAccounts = C_BattleNet.GetFriendNumGameAccounts(i) or 0
            for j = 1, numGameAccounts do
                local gameAccountInfo = C_BattleNet.GetFriendGameAccountInfo(i, j)
                if gameAccountInfo and gameAccountInfo.isOnline and gameAccountInfo.clientProgram == wowClient and gameAccountInfo.characterName then
                    if gameAccountInfo.isInCurrentRegion == false then
                        -- Skip cross-region
                    else
                        local realm = gameAccountInfo.realmDisplayName or gameAccountInfo.realmName
                        local fullName = realm and (gameAccountInfo.characterName .. "-" .. realm) or DeltaChess:GetFullPlayerName(gameAccountInfo.characterName)
                        if fullName ~= myName and not seen[accountInfo.battleTag] then
                            seen[accountInfo.battleTag] = true
                            table.insert(out, {
                                battleTag = accountInfo.battleTag,
                                characterName = gameAccountInfo.characterName,
                                realmName = realm,
                                fullName = fullName
                            })
                            break  -- Only add once per BNet account
                        end
                    end
                end
            end
        end
    end
    
    return out
end

--------------------------------------------------------------------------------
-- Communication Helpers
--------------------------------------------------------------------------------

--- Encode message for BattleNet whisper
-- Format: "DeltaChess:base64:checksum"
-- @param prefix string Message prefix
-- @param message string Message content
-- @return string Encoded message
local function EncodeBNetMessage(prefix, message)
    local fullMessage = prefix .. ":" .. message
    -- Simple base64 encoding (WoW doesn't have built-in base64, so we use a simple encoding)
    -- For now, just use the message directly with a marker
    local encoded = DeltaChess.Util.Base64Encode(fullMessage)
    -- Simple checksum (sum of byte values mod 256)
    local checksum = 0
    for i = 1, #fullMessage do
        checksum = (checksum + string.byte(fullMessage, i)) % 256
    end
    return string.format("DeltaChess:%s:%02x", encoded, checksum)
end

--- Decode message from BattleNet whisper
-- @param encodedMessage string Encoded message
-- @return string|nil prefix, string|nil message
local function DecodeBNetMessage(encodedMessage)
    -- Trim whitespaces from start and end
    encodedMessage = encodedMessage:match("^%s*(.-)%s*$")
    
    if not encodedMessage or not encodedMessage:match("^DeltaChess:") then
        return nil, nil
    end
    
    local encoded, checksumStr = encodedMessage:match("^DeltaChess:([^:]+):([0-9a-fA-F]+)$")
    if not encoded or not checksumStr then
        return nil, nil
    end
    
    -- Decode the message
    local fullMessage = DeltaChess.Util.Base64Decode(encoded)
    if not fullMessage then
        return nil, nil
    end
    
    -- Verify checksum
    local checksum = 0
    for i = 1, #fullMessage do
        checksum = (checksum + string.byte(fullMessage, i)) % 256
    end
    
    local expectedChecksum = tonumber(checksumStr, 16)
    if checksum ~= expectedChecksum then
        return nil, nil  -- Checksum mismatch
    end
    
    -- Split prefix and message
    local prefix, message = fullMessage:match("^([^:]+):(.*)$")
    return prefix, message
end

--- Send addon message with automatic BattleTag resolution
-- If target is a BattleTag (contains #), resolves to current character
-- If friend is on different WoW project, uses BNet whisper (unless noBNet is true)
-- @param prefix string Message prefix (ChessPing, ChessChallenge, etc.)
-- @param message string Message content
-- @param target string Target (BattleTag or CharName-Realm)
-- @param noBNet boolean Optional: if true, skip BNet whispers (same-project only)
-- @return boolean Success
function DeltaChess.Bnet:SendMessage(prefix, message, target, noBNet)
    if not target then return false end

    -- Check if target is a BattleTag (contains #)
    if target:find("#") then
        -- Try to resolve to current character (same project ID)
        local currentChar = self:GetCurrentCharacterForBattleTag(target)
        if currentChar then
            -- Friend is online on same WoW project, use addon message
            C_ChatInfo.SendAddonMessage(prefix, message, "WHISPER", currentChar)
            return true
        else
            -- Friend is offline or on different WoW project
            -- If noBNet is true, don't try BNet whispers
            if noBNet then
                return false
            end
            
            -- Check if they're online at all (any WoW project)
            local displayChar = self:GetCurrentCharacterForDisplay(target)
            if displayChar then
                -- Friend is online but on different WoW project
                -- Use BattleNet whisper
                local bnetAccountID = self:GetBNetAccountIDForBattleTag(target)
                if bnetAccountID and BNSendWhisper then
                    local encodedMessage = EncodeBNetMessage(prefix, message)
                    BNSendWhisper(bnetAccountID, encodedMessage)
                    return true
                end
            end
            -- Friend is offline or not in WoW
            return false
        end
    end
    
    -- Send to character name (regular player)
    C_ChatInfo.SendAddonMessage(prefix, message, "WHISPER", target)
    return true
end

--- Handle incoming BattleNet whisper (to be called from event handler)
-- @param bnetAccountID number Sender's BattleNet account ID
-- @param message string Message content
-- @return string|nil prefix, string|nil decodedMessage, string|nil senderBattleTag
function DeltaChess.Bnet:HandleBNetWhisper(bnetAccountID, message)
    -- Check if this is a DeltaChess message
    if not message:match("^DeltaChess:") then
        return nil, nil, nil
    end
    
    -- Decode the message
    local prefix, decodedMessage = DecodeBNetMessage(message)
    if not prefix or not decodedMessage then
        return nil, nil, nil
    end
    
    -- Get sender's BattleTag using helper
    local senderBattleTag = self:GetBattleTagForBNSenderID(bnetAccountID)
    
    return prefix, decodedMessage, senderBattleTag
end

--- Send regular chat whisper (not addon message) to BattleTag or character name
-- @param message string Chat message to send
-- @param target string Target (BattleTag or CharName-Realm)
-- @return boolean Success
function DeltaChess.Bnet:SendChatWhisper(message, target)
    if not target or not message then return false end
    
    -- Check if target is a BattleTag (contains #)
    if target:find("#") then
        local bnetAccountID = self:GetBNetAccountIDForBattleTag(target)
        if bnetAccountID and BNSendWhisper then
            BNSendWhisper(bnetAccountID, message)
            return true
        else
            -- Friend not found or offline
            return false
        end
    else
        -- Regular character name - strip realm for whisper
        local whisperName = target:match("^([^%-]+)") or target
        SendChatMessage(message, "WHISPER", nil, whisperName)
        return true
    end
end
