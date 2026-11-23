--[[
  Premove tests. Run with LibUnitWow from the addon root, once the packager
  (or a manual checkout) has filled Libs/:
    lua5.1 Libs/LibUnitWow/run.lua --no-toc

  Loads LibStub, the framework, EngineBridge.lua and UI.lua with a few WoW
  API stubs, then drives the premove flow against real board positions.
  --no-toc because the full TOC needs the WoW client (Core.lua).
]]

local Test = require("test")

-- WoW API stubs (only what loading UI.lua and the premove code touch)
C_Timer = { After = function(_, fn) fn() end }
StaticPopupDialogs = {}
function CreateFrame()
  return setmetatable({}, { __index = function() return function() end end })
end

Test.load("Libs/LibStub/LibStub.lua")
Test.loadXml("Libs/DeltachessFramework/lib.xml")
Test.load("DeltaChess.lua")
Test.load("EngineBridge.lua")
Test.load("UI.lua")

local DeltaChess = LibStub("DeltaChess-1.0")
local Framework = LibStub("DeltachessFramework-1.0")
local COLOR = Framework.Constants.COLOR

DeltaChess.Sound = { invalid = 0 }
function DeltaChess.Sound:PlayInvalidMove() self.invalid = self.invalid + 1 end
function DeltaChess.Sound:PlayMoveSound() end
function DeltaChess:IsBoardLocked() return false end
DeltaChess.AI = {
  MakeMove = function() end,
  PauseIfBoardClosed = function() end,
}

local function lastUci(board)
  local m = board:GetLastMove()
  return m and m:GetUci() or nil
end

local function newSquare()
  return {
    CreateTexture = function()
      local tex = { shown = false }
      function tex:Show() self.shown = true end
      function tex:Hide() self.shown = false end
      return setmetatable(tex, { __index = function() return function() end end })
    end,
  }
end

-- Computer game where we play white, starting from fen
local function setup(fen, gameId)
  gameId = gameId or "g1"
  local board = Framework.Board.FromFen(fen)
  board:SetGameMeta("isVsComputer", true)
  board:SetPlayerColor(COLOR.WHITE)
  board:StartGame()
  DeltaChess.StoreBoard(gameId, board)
  local frame = { gameId = gameId, squares = {} }
  function frame:IsShown() return true end
  for _, sq in ipairs(Framework.Board.AllSquares()) do
    frame.squares[sq] = newSquare()
  end
  DeltaChess.Sound.invalid = 0
  return board, frame
end

local function click(frame, uci)
  DeltaChess.UI:HandlePremoveClick(frame, uci)
end

-- Opponent replies, then the game layer plays any queued premove
local function opponentPlays(board, frame, uci)
  Test.assertTrue(board:MakeMoveUci(uci), "opponent move " .. uci .. " should be legal")
  DeltaChess.SchedulePremove(frame.gameId)
end

-- After 1.e4, black to move
local AFTER_E4 = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"

Test.suite("Premove", "premove")

Test.test("queued premove is played when it becomes our turn", function()
  local board, frame = setup(AFTER_E4)
  click(frame, "g1")
  click(frame, "f3")
  Test.assertTableEq(board:GetPremove(), { from = "g1", to = "f3" })
  opponentPlays(board, frame, "e7e5")
  Test.assertEq(lastUci(board), "g1f3")
  Test.assertNil(board:GetPremove(), "premove is used up")
end)

Test.test("squares the piece can't reach after any reply are refused", function()
  local board, frame = setup(AFTER_E4)
  click(frame, "g1")
  click(frame, "g4")  -- not a knight move
  Test.assertNil(board:GetPremove())
  click(frame, "f1")
  click(frame, "f3")  -- a bishop can't go straight up
  Test.assertNil(board:GetPremove())
end)

Test.test("premove that is illegal after the reply is dropped", function()
  local board, frame = setup(AFTER_E4)
  click(frame, "e4")
  click(frame, "e5")
  Test.assertTableEq(board:GetPremove(), { from = "e4", to = "e5" })
  opponentPlays(board, frame, "e7e5")  -- blocks the pawn
  Test.assertEq(lastUci(board), "e7e5", "only the opponent move was played")
  Test.assertNil(board:GetPremove(), "dropped premove is cleared")
end)

Test.test("recapture onto our own piece's square", function()
  local board, frame = setup("rn1qkbnr/ppp1pppp/8/3p4/6b1/5N2/PPPPPPPP/RNBQKB1R b KQkq - 0 1")
  click(frame, "g2")
  click(frame, "f3")
  Test.assertTableEq(board:GetPremove(), { from = "g2", to = "f3" })
  opponentPlays(board, frame, "g4f3")
  Test.assertEq(lastUci(board), "g2f3")
end)

Test.test("only one premove: a new piece replaces the queued move", function()
  local board, frame = setup(AFTER_E4)
  click(frame, "g1")
  click(frame, "f3")
  click(frame, "b1")
  Test.assertNil(board:GetPremove(), "clicking another piece cancels the queued move")
  Test.assertEq(board:GetPremoveFrom(), "b1")
  click(frame, "c3")
  opponentPlays(board, frame, "e7e5")
  Test.assertEq(lastUci(board), "b1c3")
end)

Test.test("each game keeps its own premove when the window switches", function()
  local boardA, frameA = setup(AFTER_E4, "g1")
  local boardB, frameB = setup(AFTER_E4, "g2")
  frameB.squares = frameA.squares

  click(frameA, "g1")
  click(frameA, "f3")
  click(frameB, "b1")
  click(frameB, "c3")
  Test.assertTableEq(boardA:GetPremove(), { from = "g1", to = "f3" })
  Test.assertTableEq(boardB:GetPremove(), { from = "b1", to = "c3" })

  opponentPlays(boardA, frameA, "e7e5")
  Test.assertEq(lastUci(boardA), "g1f3")
  Test.assertNil(boardA:GetPremove())
  Test.assertTableEq(boardB:GetPremove(), { from = "b1", to = "c3" }, "the other game's premove stays")
end)

Test.test("premove plays from board state without the window showing that game", function()
  local boardA, frameA = setup(AFTER_E4, "g1")
  local boardB, frameB = setup(AFTER_E4, "g2")
  frameB.squares = frameA.squares

  click(frameA, "g1")
  click(frameA, "f3")
  click(frameB, "b1")
  click(frameB, "c3")
  DeltaChess.UI.activeFrame = frameB

  Test.assertTrue(boardA:MakeMoveUci("e7e5"))
  DeltaChess.SchedulePremove("g1")
  Test.assertEq(lastUci(boardA), "g1f3")
  Test.assertNil(boardA:GetPremove())
  Test.assertTableEq(boardB:GetPremove(), { from = "b1", to = "c3" })
end)

Test.test("serialized premove survives and can be scheduled after restore", function()
  local board = Framework.Board.FromFen(AFTER_E4)
  board:SetGameMeta("isVsComputer", true)
  board:SetPlayerColor(COLOR.WHITE)
  board:StartGame()
  board:SetPremove("g1", "f3")
  local data = board:Serialize()
  local restored = Framework.Board.Deserialize(data)
  Test.assertTableEq(restored:GetPremove(), { from = "g1", to = "f3" })
  restored:MakeMoveUci("e7e5")
  DeltaChess.StoreBoard("g3", restored)
  DeltaChess.SchedulePremove("g3")
  Test.assertEq(lastUci(restored), "g1f3")
  Test.assertNil(restored:GetPremove())
end)
