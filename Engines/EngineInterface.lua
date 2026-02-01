-- EngineInterface.lua - Chess engine interface and registry
-- Plug in different chess engines by implementing the interface below.

DeltaChess.Engines = DeltaChess.Engines or {}
DeltaChess.Engines.registry = DeltaChess.Engines.registry or {}
DeltaChess.Engines.defaultId = nil  -- No longer auto-set; default determined by highest ELO engine

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------
-- Use DeltaChess.Constants.COLOR (WHITE, BLACK) and DeltaChess.Constants.PIECE_TYPE
-- (PAWN, KNIGHT, BISHOP, ROOK, QUEEN, KING) for piece and color values.
--------------------------------------------------------------------------------
-- POSITION INTERFACE (contract for engines)
--------------------------------------------------------------------------------
-- Engines receive a position object (never the addon-specific board). It must support:
--
--   position:GetPiece(row, col) -> {type, color} | nil
--     row, col: 1-8. Piece uses Constants.PIECE_TYPE and Constants.COLOR.
--
--   position:GetValidMoves(row, col) -> {{row, col, [promotion]}, ...}
--     Returns legal moves for the piece at (row, col)
--
--   position:IsInCheck(color) -> boolean
--     Whether the king of given color is in check
--
--   position:GetSearchCopy() -> position
--     Returns a mutable copy for search. Engines MUST use this when making
--     temporary moves during search. Never mutate position.squares directly
--     on the original; mutate only on the search copy.
--
--   position.squares[row][col]
--     Direct access on the search copy for make/undo temporary moves.
--
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- ENGINE INTERFACE (contract engines must implement)
--------------------------------------------------------------------------------
-- Each engine must be a table with:
--
--   .id         (string)  - Unique identifier, e.g. "minimax"
--   .name       (string)  - Display name, e.g. "Minimax Alpha-Beta"
--   .description (string) - Optional short description
--
--   GetEloRange() -> {min, max} | nil  (optional)
--     Returns ELO range for difficulty slider, or nil to disable the slider.
--
--   GetBestMoveAsync(position, color, difficulty, onComplete)
--     position   - Position object (see above). Use position:GetSearchCopy() for search.
--     color      - Constants.COLOR.WHITE or Constants.COLOR.BLACK
--     difficulty - Number (e.g. ELO 100-2500), engine interprets as it likes
--     onComplete - function(move) callback. move = {fromRow, fromCol, toRow, toCol} or nil
--
--     Must be non-blocking (use C_Timer.After or similar). Call onComplete with nil if no moves.
--------------------------------------------------------------------------------
-- YIELD HELPERS (for non-blocking engine search)
--------------------------------------------------------------------------------
-- Engines should use these to keep the game responsive during computation:
--
--   DeltaChess.Engines.GetYieldDelayMs() -> number
--     Returns recommended ms between yields (FPS-adaptive; ~8ms baseline).
--
--   DeltaChess.Engines.YieldAfter(callback)
--     Schedules callback after yield delay via C_Timer.After. Replaces
--     C_Timer.After(GetYieldDelayMs()/1000, callback).
--------------------------------------------------------------------------------

local YIELD_MS = 8
local TARGET_FPS = 40

function DeltaChess.Engines.GetYieldDelayMs()
    local fps = GetFramerate() or 60
    if fps >= TARGET_FPS then
        return YIELD_MS
    end
    local msPerFrameAtTarget = 1000 / TARGET_FPS
    return math.max(msPerFrameAtTarget, YIELD_MS + (TARGET_FPS - fps) * 2)
end

function DeltaChess.Engines.YieldAfter(callback)
    C_Timer.After(DeltaChess.Engines.GetYieldDelayMs() / 1000, callback)
end

--------------------------------------------------------------------------------
-- Create a position adapter for engines (hides addon-specific board implementation)
--------------------------------------------------------------------------------
function DeltaChess.Engines.CreateBoardAdapter(source)
    if not source then return nil end
    local adapter = {}
    setmetatable(adapter, {
        __index = function(t, k)
            if k == "GetSearchCopy" then
                return function(self)
                    local copy = source.GetSearchCopy and source:GetSearchCopy() or source.GetSearchCopy(source)
                    return copy and DeltaChess.Engines.CreateBoardAdapter(copy) or nil
                end
            end
            local v = source[k]
            if type(v) == "function" then
                return function(self, ...) return v(source, ...) end
            end
            return v
        end
    })
    return adapter
end

--------------------------------------------------------------------------------

-- Register a chess engine
function DeltaChess.Engines:Register(engine)
    if not engine or not engine.id or not engine.GetBestMoveAsync then
        return false
    end
    self.registry[engine.id] = engine
    return true
end

-- Get engine by id
function DeltaChess.Engines:Get(id)
    return self.registry[id or self:GetEffectiveDefaultId()]
end

-- Get default engine id
function DeltaChess.Engines:GetDefaultId()
    return self.defaultId
end

-- Get effective default: defaultId if it exists, else the engine with the highest max ELO, else nil
function DeltaChess.Engines:GetEffectiveDefaultId()
    if self.defaultId and self.registry[self.defaultId] then
        return self.defaultId
    end
    -- GetEngineList returns engines sorted by max ELO descending (strongest first)
    local list = self:GetEngineList()
    if #list > 0 then
        return list[1].id
    end
    return nil
end

-- Set default engine id
function DeltaChess.Engines:SetDefaultId(id)
    if self.registry[id] then
        self.defaultId = id
        return true
    end
    return false
end

-- Get all registered engines as {id = engine, ...}
function DeltaChess.Engines:GetAll()
    return self.registry
end

-- Get ELO range for an engine, or nil if engine has no ELO setting
function DeltaChess.Engines:GetEloRange(engineId)
    local engine = self:Get(engineId)
    if not engine or type(engine.GetEloRange) ~= "function" then
        return nil
    end
    return engine:GetEloRange()
end

-- Validate a move against DeltaChess game logic
-- Returns true if the move is legal, false otherwise
function DeltaChess.Engines:ValidateMove(board, move)
    if not board or not move then return false end
    if not move.fromRow or not move.fromCol or not move.toRow or not move.toCol then return false end
    
    local piece = board:GetPiece(move.fromRow, move.fromCol)
    if not piece then return false end
    
    -- Get valid moves for this piece using DeltaChess's own logic
    local validMoves = board:GetValidMoves(move.fromRow, move.fromCol)
    if not validMoves then return false end
    
    -- Check if the engine's move is in the list of valid moves
    for _, vm in ipairs(validMoves) do
        if vm.row == move.toRow and vm.col == move.toCol then
            return true
        end
    end
    
    return false
end

-- Get list of engine ids and display names for UI (sorted by max ELO, strongest first)
function DeltaChess.Engines:GetEngineList()
    local list = {}
    for id, engine in pairs(self.registry) do
        local eloRange = engine.GetEloRange and engine:GetEloRange()
        local maxElo = eloRange and eloRange[2] or 0
        table.insert(list, {
            id = id,
            name = engine.name or id,
            description = engine.description or "",
            maxElo = maxElo
        })
    end
    -- Sort by max ELO descending (strongest first)
    table.sort(list, function(a, b)
        return a.maxElo > b.maxElo
    end)
    return list
end
