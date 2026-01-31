-- ChessBoard.lua - DeltaChess game logic

DeltaChess.Board = {}

-- Initialize a new chess board
function DeltaChess.Board:New()
    local board = {
        squares = {},
        currentTurn = "white",
        moves = {},
        capturedPieces = {white = {}, black = {}},
        gameStatus = "active",
        whiteKingMoved = false,
        blackKingMoved = false,
        whiteRookKingsideMoved = false,
        whiteRookQueensideMoved = false,
        blackRookKingsideMoved = false,
        blackRookQueensideMoved = false,
        enPassantSquare = nil,
        halfMoveClock = 0,
        fullMoveNumber = 1
    }
    
    setmetatable(board, {__index = self})
    board:InitializeBoard()
    
    return board
end

-- Initialize board with starting position
function DeltaChess.Board:InitializeBoard()
    -- Clear board
    for row = 1, 8 do
        self.squares[row] = {}
        for col = 1, 8 do
            self.squares[row][col] = nil
        end
    end
    
    -- Place pawns
    for col = 1, 8 do
        self.squares[2][col] = {type = "pawn", color = "white"}
        self.squares[7][col] = {type = "pawn", color = "black"}
    end
    
    -- Place pieces for white
    self.squares[1][1] = {type = "rook", color = "white"}
    self.squares[1][2] = {type = "knight", color = "white"}
    self.squares[1][3] = {type = "bishop", color = "white"}
    self.squares[1][4] = {type = "queen", color = "white"}
    self.squares[1][5] = {type = "king", color = "white"}
    self.squares[1][6] = {type = "bishop", color = "white"}
    self.squares[1][7] = {type = "knight", color = "white"}
    self.squares[1][8] = {type = "rook", color = "white"}
    
    -- Place pieces for black
    self.squares[8][1] = {type = "rook", color = "black"}
    self.squares[8][2] = {type = "knight", color = "black"}
    self.squares[8][3] = {type = "bishop", color = "black"}
    self.squares[8][4] = {type = "queen", color = "black"}
    self.squares[8][5] = {type = "king", color = "black"}
    self.squares[8][6] = {type = "bishop", color = "black"}
    self.squares[8][7] = {type = "knight", color = "black"}
    self.squares[8][8] = {type = "rook", color = "black"}
end

-- Get piece at position
function DeltaChess.Board:GetPiece(row, col)
    if row < 1 or row > 8 or col < 1 or col > 8 then
        return nil
    end
    return self.squares[row][col]
end

-- Check if square is valid
function DeltaChess.Board:IsValidSquare(row, col)
    return row >= 1 and row <= 8 and col >= 1 and col <= 8
end

-- Get valid moves for a piece
function DeltaChess.Board:GetValidMoves(row, col)
    local piece = self:GetPiece(row, col)
    if not piece then return {} end
    
    local moves = {}
    
    if piece.type == "pawn" then
        moves = self:GetPawnMoves(row, col, piece.color)
    elseif piece.type == "knight" then
        moves = self:GetKnightMoves(row, col, piece.color)
    elseif piece.type == "bishop" then
        moves = self:GetBishopMoves(row, col, piece.color)
    elseif piece.type == "rook" then
        moves = self:GetRookMoves(row, col, piece.color)
    elseif piece.type == "queen" then
        moves = self:GetQueenMoves(row, col, piece.color)
    elseif piece.type == "king" then
        moves = self:GetKingMoves(row, col, piece.color)
    end
    
    -- Filter out moves that would leave king in check
    local validMoves = {}
    for _, move in ipairs(moves) do
        if not self:WouldBeInCheck(row, col, move.row, move.col, piece.color) then
            table.insert(validMoves, move)
        end
    end
    
    return validMoves
end

-- Pawn moves
function DeltaChess.Board:GetPawnMoves(row, col, color)
    local moves = {}
    local direction = color == "white" and 1 or -1
    local startRow = color == "white" and 2 or 7
    local promotionRank = color == "white" and 8 or 1
    
    local function addMove(move)
        if move.row == promotionRank then
            move.promotion = true
        end
        table.insert(moves, move)
    end
    
    -- Forward move
    local newRow = row + direction
    if self:IsValidSquare(newRow, col) and not self:GetPiece(newRow, col) then
        addMove({row = newRow, col = col})
        
        -- Double move from start
        if row == startRow then
            local doubleRow = row + (direction * 2)
            if not self:GetPiece(doubleRow, col) then
                addMove({row = doubleRow, col = col})
            end
        end
    end
    
    -- Captures
    for _, colOffset in ipairs({-1, 1}) do
        local captureCol = col + colOffset
        if self:IsValidSquare(newRow, captureCol) then
            local target = self:GetPiece(newRow, captureCol)
            if target and target.color ~= color then
                addMove({row = newRow, col = captureCol})
            end
            
            -- En passant
            if self.enPassantSquare and 
               self.enPassantSquare.row == newRow and 
               self.enPassantSquare.col == captureCol then
                addMove({row = newRow, col = captureCol, enPassant = true})
            end
        end
    end
    
    return moves
end

-- Knight moves
function DeltaChess.Board:GetKnightMoves(row, col, color)
    local moves = {}
    local offsets = {
        {-2, -1}, {-2, 1}, {-1, -2}, {-1, 2},
        {1, -2}, {1, 2}, {2, -1}, {2, 1}
    }
    
    for _, offset in ipairs(offsets) do
        local newRow = row + offset[1]
        local newCol = col + offset[2]
        
        if self:IsValidSquare(newRow, newCol) then
            local target = self:GetPiece(newRow, newCol)
            if not target or target.color ~= color then
                table.insert(moves, {row = newRow, col = newCol})
            end
        end
    end
    
    return moves
end

-- Bishop moves
function DeltaChess.Board:GetBishopMoves(row, col, color)
    local moves = {}
    local directions = {{-1, -1}, {-1, 1}, {1, -1}, {1, 1}}
    
    for _, dir in ipairs(directions) do
        local newRow, newCol = row + dir[1], col + dir[2]
        
        while self:IsValidSquare(newRow, newCol) do
            local target = self:GetPiece(newRow, newCol)
            
            if not target then
                table.insert(moves, {row = newRow, col = newCol})
            elseif target.color ~= color then
                table.insert(moves, {row = newRow, col = newCol})
                break
            else
                break
            end
            
            newRow = newRow + dir[1]
            newCol = newCol + dir[2]
        end
    end
    
    return moves
end

-- Rook moves
function DeltaChess.Board:GetRookMoves(row, col, color)
    local moves = {}
    local directions = {{-1, 0}, {1, 0}, {0, -1}, {0, 1}}
    
    for _, dir in ipairs(directions) do
        local newRow, newCol = row + dir[1], col + dir[2]
        
        while self:IsValidSquare(newRow, newCol) do
            local target = self:GetPiece(newRow, newCol)
            
            if not target then
                table.insert(moves, {row = newRow, col = newCol})
            elseif target.color ~= color then
                table.insert(moves, {row = newRow, col = newCol})
                break
            else
                break
            end
            
            newRow = newRow + dir[1]
            newCol = newCol + dir[2]
        end
    end
    
    return moves
end

-- Queen moves (combination of rook and bishop)
function DeltaChess.Board:GetQueenMoves(row, col, color)
    local moves = {}
    local rookMoves = self:GetRookMoves(row, col, color)
    local bishopMoves = self:GetBishopMoves(row, col, color)
    
    for _, move in ipairs(rookMoves) do
        table.insert(moves, move)
    end
    for _, move in ipairs(bishopMoves) do
        table.insert(moves, move)
    end
    
    return moves
end

-- King moves
function DeltaChess.Board:GetKingMoves(row, col, color)
    local moves = {}
    local offsets = {
        {-1, -1}, {-1, 0}, {-1, 1},
        {0, -1}, {0, 1},
        {1, -1}, {1, 0}, {1, 1}
    }
    
    for _, offset in ipairs(offsets) do
        local newRow = row + offset[1]
        local newCol = col + offset[2]
        
        if self:IsValidSquare(newRow, newCol) then
            local target = self:GetPiece(newRow, newCol)
            if not target or target.color ~= color then
                table.insert(moves, {row = newRow, col = newCol})
            end
        end
    end
    
    -- Castling
    if not self:IsInCheck(color) then
        if color == "white" and not self.whiteKingMoved then
            -- Kingside
            if not self.whiteRookKingsideMoved and
               not self:GetPiece(1, 6) and not self:GetPiece(1, 7) then
                table.insert(moves, {row = 1, col = 7, castle = "kingside"})
            end
            -- Queenside
            if not self.whiteRookQueensideMoved and
               not self:GetPiece(1, 2) and not self:GetPiece(1, 3) and not self:GetPiece(1, 4) then
                table.insert(moves, {row = 1, col = 3, castle = "queenside"})
            end
        elseif color == "black" and not self.blackKingMoved then
            -- Kingside
            if not self.blackRookKingsideMoved and
               not self:GetPiece(8, 6) and not self:GetPiece(8, 7) then
                table.insert(moves, {row = 8, col = 7, castle = "kingside"})
            end
            -- Queenside
            if not self.blackRookQueensideMoved and
               not self:GetPiece(8, 2) and not self:GetPiece(8, 3) and not self:GetPiece(8, 4) then
                table.insert(moves, {row = 8, col = 3, castle = "queenside"})
            end
        end
    end
    
    return moves
end

-- Check if move would leave king in check
function DeltaChess.Board:WouldBeInCheck(fromRow, fromCol, toRow, toCol, color)
    -- Make temporary move
    local piece = self:GetPiece(fromRow, fromCol)
    local capturedPiece = self:GetPiece(toRow, toCol)
    
    self.squares[toRow][toCol] = piece
    self.squares[fromRow][fromCol] = nil
    
    local inCheck = self:IsInCheck(color)
    
    -- Undo move
    self.squares[fromRow][fromCol] = piece
    self.squares[toRow][toCol] = capturedPiece
    
    return inCheck
end

-- Check if king is in check
function DeltaChess.Board:IsInCheck(color)
    -- Find king position
    local kingRow, kingCol
    for row = 1, 8 do
        for col = 1, 8 do
            local piece = self:GetPiece(row, col)
            if piece and piece.type == "king" and piece.color == color then
                kingRow, kingCol = row, col
                break
            end
        end
        if kingRow then break end
    end
    
    if not kingRow then return false end
    
    -- Check if any opponent piece can capture the king
    local opponentColor = color == "white" and "black" or "white"
    
    for row = 1, 8 do
        for col = 1, 8 do
            local piece = self:GetPiece(row, col)
            if piece and piece.color == opponentColor then
                local moves = self:GetPseudoLegalMoves(row, col, piece)
                for _, move in ipairs(moves) do
                    if move.row == kingRow and move.col == kingCol then
                        return true
                    end
                end
            end
        end
    end
    
    return false
end

-- Get pseudo-legal moves (without checking for check)
function DeltaChess.Board:GetPseudoLegalMoves(row, col, piece)
    if piece.type == "pawn" then
        return self:GetPawnMoves(row, col, piece.color)
    elseif piece.type == "knight" then
        return self:GetKnightMoves(row, col, piece.color)
    elseif piece.type == "bishop" then
        return self:GetBishopMoves(row, col, piece.color)
    elseif piece.type == "rook" then
        return self:GetRookMoves(row, col, piece.color)
    elseif piece.type == "queen" then
        return self:GetQueenMoves(row, col, piece.color)
    elseif piece.type == "king" then
        -- For check detection, only return basic king moves without castling
        local moves = {}
        local offsets = {
            {-1, -1}, {-1, 0}, {-1, 1},
            {0, -1}, {0, 1},
            {1, -1}, {1, 0}, {1, 1}
        }
        
        for _, offset in ipairs(offsets) do
            local newRow = row + offset[1]
            local newCol = col + offset[2]
            
            if self:IsValidSquare(newRow, newCol) then
                local target = self:GetPiece(newRow, newCol)
                if not target or target.color ~= piece.color then
                    table.insert(moves, {row = newRow, col = newCol})
                end
            end
        end
        
        return moves
    end
    
    return {}
end

-- Make a move
function DeltaChess.Board:MakeMove(fromRow, fromCol, toRow, toCol, promotion)
    local piece = self:GetPiece(fromRow, fromCol)
    if not piece then return false end
    
    local capturedPiece = self:GetPiece(toRow, toCol)
    
    -- Store move
    local move = {
        from = {row = fromRow, col = fromCol},
        to = {row = toRow, col = toCol},
        piece = piece.type,
        color = piece.color,
        captured = capturedPiece,
        timestamp = time()
    }
    
    -- Handle special moves
    if piece.type == "pawn" then
        -- En passant capture
        if toCol ~= fromCol and not capturedPiece then
            local captureRow = piece.color == "white" and toRow - 1 or toRow + 1
            capturedPiece = self:GetPiece(captureRow, toCol)
            self.squares[captureRow][toCol] = nil
            move.enPassant = true
            move.captured = capturedPiece
        end
        
        -- Set en passant square
        if math.abs(toRow - fromRow) == 2 then
            self.enPassantSquare = {
                row = piece.color == "white" and fromRow + 1 or fromRow - 1,
                col = fromCol
            }
        else
            self.enPassantSquare = nil
        end
        
        -- Promotion
        if (piece.color == "white" and toRow == 8) or (piece.color == "black" and toRow == 1) then
            promotion = promotion or "queen"
            piece.type = promotion
            move.promotion = promotion
        end
    else
        self.enPassantSquare = nil
    end
    
    -- Handle castling
    if piece.type == "king" and math.abs(toCol - fromCol) == 2 then
        if toCol > fromCol then
            -- Kingside
            local rook = self:GetPiece(fromRow, 8)
            self.squares[fromRow][6] = rook
            self.squares[fromRow][8] = nil
            move.castle = "kingside"
        else
            -- Queenside
            local rook = self:GetPiece(fromRow, 1)
            self.squares[fromRow][4] = rook
            self.squares[fromRow][1] = nil
            move.castle = "queenside"
        end
    end
    
    -- Make the move
    self.squares[toRow][toCol] = piece
    self.squares[fromRow][fromCol] = nil
    
    -- Update castling rights
    if piece.type == "king" then
        if piece.color == "white" then
            self.whiteKingMoved = true
        else
            self.blackKingMoved = true
        end
    elseif piece.type == "rook" then
        if piece.color == "white" then
            if fromCol == 1 then
                self.whiteRookQueensideMoved = true
            elseif fromCol == 8 then
                self.whiteRookKingsideMoved = true
            end
        else
            if fromCol == 1 then
                self.blackRookQueensideMoved = true
            elseif fromCol == 8 then
                self.blackRookKingsideMoved = true
            end
        end
    end
    
    -- Store captured piece
    if capturedPiece then
        table.insert(self.capturedPieces[piece.color], capturedPiece)
    end
    
    -- Update move counters
    if piece.type == "pawn" or capturedPiece then
        self.halfMoveClock = 0
    else
        self.halfMoveClock = self.halfMoveClock + 1
    end
    
    if piece.color == "black" then
        self.fullMoveNumber = self.fullMoveNumber + 1
    end
    
    -- Switch turn
    self.currentTurn = self.currentTurn == "white" and "black" or "white"
    
    -- Add move to history
    table.insert(self.moves, move)
    
    -- Check for game end conditions
    self:CheckGameEnd()
    
    return true
end

-- Check if game has ended
function DeltaChess.Board:CheckGameEnd()
    -- Check for checkmate or stalemate
    local hasLegalMoves = false
    
    for row = 1, 8 do
        for col = 1, 8 do
            local piece = self:GetPiece(row, col)
            if piece and piece.color == self.currentTurn then
                local moves = self:GetValidMoves(row, col)
                if #moves > 0 then
                    hasLegalMoves = true
                    break
                end
            end
        end
        if hasLegalMoves then break end
    end
    
    if not hasLegalMoves then
        if self:IsInCheck(self.currentTurn) then
            self.gameStatus = "checkmate"
        else
            self.gameStatus = "stalemate"
        end
        return
    end
    
    -- Check for fifty-move rule
    if self.halfMoveClock >= 100 then
        self.gameStatus = "draw"
        return
    end
    
    -- Check for insufficient material
    if self:IsInsufficientMaterial() then
        self.gameStatus = "draw"
        return
    end
end

-- Check for insufficient material
function DeltaChess.Board:IsInsufficientMaterial()
    local pieces = {}
    
    for row = 1, 8 do
        for col = 1, 8 do
            local piece = self:GetPiece(row, col)
            if piece then
                table.insert(pieces, piece)
            end
        end
    end
    
    -- King vs King
    if #pieces == 2 then
        return true
    end
    
    -- King and Bishop/Knight vs King
    if #pieces == 3 then
        for _, piece in ipairs(pieces) do
            if piece.type == "bishop" or piece.type == "knight" then
                return true
            end
        end
    end
    
    return false
end

-- Convert to algebraic notation
function DeltaChess.Board:ToAlgebraic(row, col)
    local files = {"a", "b", "c", "d", "e", "f", "g", "h"}
    return files[col] .. tostring(row)
end

-- Convert from algebraic notation
function DeltaChess.Board:FromAlgebraic(notation)
    local files = {a=1, b=2, c=3, d=4, e=5, f=6, g=7, h=8}
    local file = notation:sub(1, 1)
    local rank = tonumber(notation:sub(2, 2))
    
    return rank, files[file]
end
