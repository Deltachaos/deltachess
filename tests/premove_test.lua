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
function DeltaChess:IsBoardLocked() return false end

-- OnSquareClick stand-in: premove handling first (as in the real function),
-- otherwise record the move the UI tried to make and play it on the board.
local played
function DeltaChess.UI:OnSquareClick(frame, uci)
  if self:HandlePremoveClick(frame, uci) then return end
  played = frame.selectedSquare .. uci
  frame.selectedSquare = nil
  DeltaChess.GetBoard(frame.gameId):MakeMoveUci(played)
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
local function setup(fen)
  local board = Framework.Board.FromFen(fen)
  board:SetGameMeta("isVsComputer", true)
  board:SetPlayerColor(COLOR.WHITE)
  DeltaChess.StoreBoard("g1", board)
  local frame = { gameId = "g1", squares = {} }
  function frame:IsShown() return true end
  for _, sq in ipairs(Framework.Board.AllSquares()) do
    frame.squares[sq] = newSquare()
  end
  played = nil
  DeltaChess.Sound.invalid = 0
  return board, frame
end

local function click(frame, uci) DeltaChess.UI:OnSquareClick(frame, uci) end

-- Opponent replies, then the board redraws (as UpdateBoard does)
local function opponentPlays(board, frame, uci)
  Test.assertTrue(board:MakeMoveUci(uci), "opponent move " .. uci .. " should be legal")
  DeltaChess.UI:RefreshPremove(frame, board)
end

-- After 1.e4, black to move
local AFTER_E4 = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"

Test.suite("Premove", "premove")

Test.test("queued premove is played when it becomes our turn", function()
  local board, frame = setup(AFTER_E4)
  click(frame, "g1")
  click(frame, "f3")
  Test.assertTableEq(board:GetPremove(), { from = "g1", to = "f3" })
  Test.assertNil(played, "nothing is played on the opponent's turn")
  opponentPlays(board, frame, "e7e5")
  Test.assertEq(played, "g1f3")
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
  Test.assertNil(played, "blocked pawn push must not be played")
  Test.assertNil(board:GetPremove(), "dropped premove is cleared")
end)

Test.test("recapture onto our own piece's square", function()
  -- Black bishop g4 can take the knight on f3; we premove gxf3
  local board, frame = setup("rn1qkbnr/ppp1pppp/8/3p4/6b1/5N2/PPPPPPPP/RNBQKB1R b KQkq - 0 1")
  click(frame, "g2")
  click(frame, "f3")
  Test.assertTableEq(board:GetPremove(), { from = "g2", to = "f3" })
  opponentPlays(board, frame, "g4f3")
  Test.assertEq(played, "g2f3")
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
  Test.assertEq(played, "b1c3")
end)

Test.test("each game keeps its own premove when the window switches", function()
  local boardA, frameA = setup(AFTER_E4)
  local boardB = Framework.Board.FromFen(AFTER_E4)
  boardB:SetGameMeta("isVsComputer", true)
  boardB:SetPlayerColor(COLOR.WHITE)
  DeltaChess.StoreBoard("g2", boardB)
  local frameB = { gameId = "g2", squares = frameA.squares }
  function frameB:IsShown() return true end

  click(frameA, "g1")
  click(frameA, "f3")
  click(frameB, "b1")
  click(frameB, "c3")
  Test.assertTableEq(boardA:GetPremove(), { from = "g1", to = "f3" })
  Test.assertTableEq(boardB:GetPremove(), { from = "b1", to = "c3" })

  opponentPlays(boardA, frameA, "e7e5")
  Test.assertEq(played, "g1f3")
  Test.assertNil(boardA:GetPremove())
  Test.assertTableEq(boardB:GetPremove(), { from = "b1", to = "c3" }, "the other game's premove stays")
end)

Test.test("leaving a game on screen does not drop or play the other game's premove early", function()
  local boardA, frameA = setup(AFTER_E4)
  local boardB = Framework.Board.FromFen(AFTER_E4)
  boardB:SetGameMeta("isVsComputer", true)
  boardB:SetPlayerColor(COLOR.WHITE)
  DeltaChess.StoreBoard("g2", boardB)
  local frameB = { gameId = "g2", squares = frameA.squares }
  function frameB:IsShown() return true end

  click(frameA, "g1")
  click(frameA, "f3")
  click(frameB, "b1")
  click(frameB, "c3")
  DeltaChess.UI.activeFrame = frameB

  Test.assertTrue(boardA:MakeMoveUci("e7e5"))
  DeltaChess.UI:SchedulePremove("g1", nil)
  Test.assertEq(boardA:GetLastMove():GetUci(), "g1f3")
  Test.assertNil(boardA:GetPremove())
  Test.assertTableEq(boardB:GetPremove(), { from = "b1", to = "c3" })
  Test.assertNil(played, "the move is applied on the game, not as a click on the window")
end)

