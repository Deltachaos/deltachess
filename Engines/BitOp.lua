-- BitOp.lua - Bit operations for WoW
-- WoW has a native bit library; this file ensures it's available as _G.bit
-- Required by GarboChess and LuaJester engines.

-- WoW's native bit library is already available as 'bit'
-- Just ensure it exists in the global scope
if not _G.bit then
    -- Fallback should never be needed in WoW, but provide minimal stubs
    -- that will error clearly if actually called
    _G.bit = {
        band = function() error("bit.band not available") end,
        bor = function() error("bit.bor not available") end,
        bxor = function() error("bit.bxor not available") end,
        bnot = function() error("bit.bnot not available") end,
        lshift = function() error("bit.lshift not available") end,
        rshift = function() error("bit.rshift not available") end,
    }
end
