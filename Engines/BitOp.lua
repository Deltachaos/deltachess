-- BitOp.lua - Bit operations for WoW
-- WoW has a native bit library; this provides it under the DeltaChess namespace.
-- Required by GarboChess and LuaJester engines.

-- WoW's native bit library is available as 'bit'
-- We namespace it under DeltaChess to avoid global pollution
DeltaChess.BitOp = _G.bit or {
    -- Fallback should never be needed in WoW, but provide minimal stubs
    -- that will error clearly if actually called
    band = function() error("bit.band not available") end,
    bor = function() error("bit.bor not available") end,
    bxor = function() error("bit.bxor not available") end,
    bnot = function() error("bit.bnot not available") end,
    lshift = function() error("bit.lshift not available") end,
    rshift = function() error("bit.rshift not available") end,
}
