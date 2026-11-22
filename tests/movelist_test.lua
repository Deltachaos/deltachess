--[[
  Move list tests: rows with the time each side spent on a move.
  Run with LibUnitWow from the addon root: lua5.1 Libs/LibUnitWow/run.lua --no-toc
]]

local Test = require("test")

-- Widget stub that remembers what the UI code sets on it
local function widget()
  local w = { shown = true, text = "", width = 0, height = 0 }
  function w:SetText(t) self.text = t end
  function w:SetWidth(v) self.width = v end
  function w:GetWidth() return self.width end
  function w:SetSize(x, y) self.width, self.height = x, y end
  function w:SetHeight(h) self.height = h end
  function w:Show() self.shown = true end
  function w:Hide() self.shown = false end
  function w:GetFont() return "Fonts\\FRIZQT__.TTF", 10, "" end
  function w:CreateTexture() return widget() end
  function w:CreateFontString() return widget() end
  return setmetatable(w, { __index = function() return function() end end })
end

C_Timer = { After = function(_, fn) fn() end }
StaticPopupDialogs = {}
CreateFrame = widget

Test.load("Libs/LibStub/LibStub.lua")
Test.loadXml("Libs/DeltachessFramework/lib.xml")
Test.load("DeltaChess.lua")
Test.load("EngineBridge.lua")
Test.load("UI.lua")

local DeltaChess = LibStub("DeltaChess-1.0")
local Framework = LibStub("DeltachessFramework-1.0")
local UI = DeltaChess.UI

-- 1.e4 (4.2s) e5 (0.8s) 2.Nf3 (7.5s)
local function timedBoard()
  local board = Framework.Board.New()
  board:StartGame(1000)
  board:MakeMoveUci("e2e4", { timestamp = 1004.2 })
  board:MakeMoveUci("e7e5", { timestamp = 1005.0 })
  board:MakeMoveUci("g1f3", { timestamp = 1012.5 })
  return board
end

local function newList()
  local child = widget()
  child:SetWidth(185)
  return { scrollChild = child, historyText = widget(), rows = {} }
end

local function render(info, board, highlight)
  UI:RenderMoveList(info, board:GetMoveHistory(), board:GetMoveDurations(), highlight)
end

Test.suite("Move list", "movelist")

Test.test("one row per full move, with each side's seconds", function()
  local info = newList()
  render(info, timedBoard())
  local r1, r2 = info.rows[1], info.rows[2]
  Test.assertEq(r1.number.text, "1.")
  Test.assertEq(r1.white.text, "e4")
  Test.assertEq(r1.black.text, "e5")
  Test.assertEq(r1.whiteTime.text.text, "4.2")
  Test.assertEq(r1.blackTime.text.text, "0.8")
  Test.assertEq(r2.white.text, "Nf3")
  Test.assertEq(r2.whiteTime.text.text, "7.5")
  Test.assertFalse(r2.blackTime.text.shown, "black hasn't moved yet")
  Test.assertFalse(r2.blackTime.bar.shown)
end)

Test.test("bars are scaled to the longest move", function()
  local info = newList()
  render(info, timedBoard())
  Test.assertEq(info.rows[2].whiteTime.bar.width, 40, "longest move fills the bar")
  Test.assertEq(info.rows[1].whiteTime.bar.width, 22, "4.2 of 7.5 seconds")
  Test.assertEq(info.rows[1].blackTime.bar.width, 4, "0.8 of 7.5 seconds")
end)

Test.test("rows are reused and extra rows hidden when the list gets shorter", function()
  local info = newList()
  local board = timedBoard()
  render(info, board)
  local first = info.rows[1]
  local short = Framework.Board.New()
  short:StartGame(1000)
  short:MakeMoveUci("d2d4", { timestamp = 1001 })
  render(info, short)
  Test.assertTrue(info.rows[1] == first, "same row frame")
  Test.assertEq(first.white.text, "d4")
  Test.assertFalse(info.rows[2].shown, "second row hidden")
end)

Test.test("replay highlight marks the current move", function()
  local info = newList()
  render(info, timedBoard(), 2)
  Test.assertEq(info.rows[1].black.text, "|cFFFFFF00[e5]|r")
  Test.assertEq(info.rows[1].white.text, "e4")
end)
