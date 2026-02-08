# DeltaChess

Camping a rare spawn for the 47th time?
Waiting for that **one raid member** who *definitely* won't disconnect again (for real this time)?
Stuck in Valdrakken doing absolutely nothing?

**Play chess. In WoW.**

**DeltaChess** lets you play full chess games directly inside World of Warcraft—against other players (yes, cross-realm) or against the computer—so you finally have something to do while the game refuses to respect your time.

---

## Installation

Install via your preferred addon manager:

* **[CurseForge](https://www.curseforge.com/wow/addons/deltachess)**
* **[WoWUp (Wago)](https://addons.wago.io/addons/deltachess)**
* **[WoWInterface](https://www.wowinterface.com/downloads/info27027-DeltaChess.html)**

---

## Support Development ❤️

If you enjoy DeltaChess and want to support its development (or just prevent the author from also camping rare spawns for gold), you can do so by subscribing to my other WoW project [blingtron.app](https://blingtron.app)—a Discord bot for supporting raid leaders—on Patreon:

👉 **[https://www.patreon.com/c/blingtronapp](https://www.patreon.com/c/blingtronapp)**

Support is completely optional, but very much appreciated!

---

## What is DeltaChess?

DeltaChess is a lightweight but fully-featured chess addon. Open a board, challenge a friend, or start a single-player game and enjoy *real* chess rules without alt-tabbing, tab-crashing, or explaining to your raid why you're suddenly AFK.

Challenge players by:

* Targeting them and typing `/chess`
* Using `/chess PlayerName-RealmName`
* Clicking the minimap button when boredom strikes

---

## Yes, it's real chess

No "WoW-flavored almost chess" nonsense here. DeltaChess supports:

* Castling (both sides, because of course)
* En passant (yes, really)
* Pawn promotion
* Check, checkmate, stalemate
* Fifty-move rule
* Insufficient material

Valid moves are highlighted, so you won't embarrass yourself by trying to move a bishop like a warrior.

---

## Time pressure included (optional)

Want to simulate Mythic+ stress but with fewer repair bills?

* Optional **chess clocks**
* Configurable time per player (1–60 minutes)
* Optional increment per move (0–30 seconds)
* **Handicap clocks** — give one side less time for a balanced challenge between uneven players

Play as **white**, **black**, or let fate decide—just like raid loot.

---

## Pause without the drama

Need to answer a summon? Bio break? Boss pull?

* **Pause any game** — clocks stop, moves are blocked, nobody loses on time
* **Mutual agreement** — in human games, both players must accept the pause (no mid-checkmate stalling)
* **Instant pause** — vs the computer, just pause and resume whenever you want
* Close the board window against the AI and the game auto-pauses for you

---

## Export your brilliance (PGN)

Played an immortal game between trash pulls? Keep it forever.

* **Full PGN export** with standard tags (Date, Players, Result, TimeControl, FEN)
* Standard Algebraic Notation with check markers
* Clock annotations included when time controls are active
* One-click copy from a scrollable text window — paste it into Lichess, Chess.com, or brag in guild chat

---

## Games don't disappear (unlike your group)

* Games are **saved automatically**
* Disconnect? Crash? Rage quit? → Resume later
* Finished games are stored with full move history
* Track **wins, losses, draws**, and win rate to prove you're smarter than your raid leader

Inactive games are automatically archived, because even chess deserves cleanup.

---

## Pluggable engine framework

DeltaChess ships with a **pluggable chess engine framework**. Pick an engine, set an ELO, and play — or add your own.

* **4 built-in engines** spanning ELO 100–2600
* Select engine and difficulty from the "Play vs Computer" dialog
* Engines are filtered by your chosen ELO and sorted by efficiency
* The framework is fully async and WoW-compatible (no frame drops)
* Adding a custom engine is as simple as implementing a small interface and registering it

### Supported chess engines

| Engine | Style |
|--------|-------|
| **Dumb Goblin** | Greedy capture-first — perfect for your first game |
| **Sunfish** | MTD-bi search with iterative deepening and transposition tables |
| **GarboChess** | Alpha-beta with null-move pruning, killer moves, and SEE |
| **Fruit 2.1** | Elite-level engine — null-move pruning, LMR, history heuristics, tapered eval |

> Want to add your own engine? See the [Engine Framework](https://github.com/Deltachaos/deltachess-framework) for the full interface contract and examples.

---

## Features

* Play chess against other players **cross-realm**
* Single-player mode vs the computer
* Full standard chess rules implemented
* Optional chess clocks with increment
* **Handicap clocks** — asymmetric time controls
* **Game pausing** — stop the clock and resume when ready
* **PGN export** — copy your game in standard notation
* **Pluggable engines** — 4 built-in AI engines (ELO 100–2600), extensible
* Saved & resumable games
* Full move history and player statistics
* Clean board UI with highlighted moves
* Draggable minimap button for instant access

**DeltaChess** is perfect for:

* Rare camping
* Raid downtime
* Queue waiting
* That moment when someone says *"brb 2 min"* and you know it's a lie

Stop staring at your cooldowns.
Start checkmating people. ♟️

---

## Disclaimer

**This project was built approximately 99% with AI assistance.** Code, structure, and documentation were developed with generative AI tools. Use and review at your own discretion.

---

## Usage

### Slash commands

| Command | Description |
|--------|-------------|
| `/chess` | Challenge your current target |
| `/chess PlayerName-RealmName` | Challenge a specific player |
| `/chess menu` | Open the main menu |

### Challenge dialog

* **Your color:** White, black, or random
* **Chess clock:** On/off
* **Time:** Minutes per player (1–60)
* **Increment:** Seconds per move (0–30)
* **Handicap:** Optionally reduce one side's starting time (challenger or opponent)

### Minimap button

* **Left click** – Main menu
* **Right click** – Resume most recent game
* **Drag** – Move the button around the minimap

### Gameplay

* Click a piece to select it; valid moves are highlighted.
* Click a highlighted square to move.
* Castling, en passant, and promotion are supported.
* **Resign**, **Offer draw**, **Pause**, and **Close** are available from the board UI.
* **PGN** button lets you view and copy the game in standard notation.

---

## Data

* Stored in the `ChessDB` saved variable: active games, history, stats, settings.
* Games inactive for 7+ days are treated as abandoned and moved to history.
* Cleanup runs automatically (e.g. every hour).

---

## Known limitations

* Players must be online (cross-realm supported where WoW allows).
* Only the two players can view an active game (no spectators).

---

## Troubleshooting

| Issue | Check |
|-------|--------|
| Addon won't load | Correct folder, .toc Interface version, Lua errors enabled |
| Can't challenge | Player online, correct `PlayerName-RealmName` |
| Moves not syncing | Connection, both have addon, addon messages not blocked |
| Minimap button missing | Settings → "Show Minimap Button", then `/reload` |

---

## Chess piece artwork – thanks to Wikimedia Commons & Cburnett

The chess piece graphics **included in this repository** (in the `Textures/` folder) are derived from the wonderful SVG chess set by **[Cburnett](https://commons.wikimedia.org/wiki/User:Cburnett)** on **Wikimedia Commons**, created 27 December 2006. We are very grateful for this high-quality, freely licensed artwork—it makes the addon look great and would not be the same without it.

**Original sources (CC BY-SA 3.0):**

* [Category: SVG chess pieces](https://commons.wikimedia.org/wiki/Category:SVG_chess_pieces)

| Piece | Dark (black) | Light (white) |
|-------|------------------------------|------------------------------|
| King  | [Chess_kdt45.svg](https://commons.wikimedia.org/wiki/File:Chess_kdt45.svg) | [Chess_klt45.svg](https://commons.wikimedia.org/wiki/File:Chess_klt45.svg) |
| Queen | [Chess_qdt45.svg](https://commons.wikimedia.org/wiki/File:Chess_qdt45.svg) | [Chess_qlt45.svg](https://commons.wikimedia.org/wiki/File:Chess_qlt45.svg) |
| Rook  | [Chess_rdt45.svg](https://commons.wikimedia.org/wiki/File:Chess_rdt45.svg) | [Chess_rlt45.svg](https://commons.wikimedia.org/wiki/File:Chess_rlt45.svg) |
| Bishop| [Chess_bdt45.svg](https://commons.wikimedia.org/wiki/File:Chess_bdt45.svg) | [Chess_blt45.svg](https://commons.wikimedia.org/wiki/File:Chess_blt45.svg) |
| Knight| [Chess_ndt45.svg](https://commons.wikimedia.org/wiki/File:Chess_ndt45.svg) | [Chess_nlt45.svg](https://commons.wikimedia.org/wiki/File:Chess_nlt45.svg) |
| Pawn  | [Chess_pdt45.svg](https://commons.wikimedia.org/wiki/File:Chess_pdt45.svg) | [Chess_plt45.svg](https://commons.wikimedia.org/wiki/File:Chess_plt45.svg) |

These originals are licensed under **Creative Commons Attribution-ShareAlike 3.0 Unported (CC BY-SA 3.0)**. Thank you to Cburnett and to Wikimedia Commons for making these assets available to the world—we are happy to give credit and to keep our use in line with the license (attribution and share-alike).

---

## License

This addon is licensed under the **GNU General Public License v3.0 (GPL-3.0)**.

* You may use, modify, and distribute the code under the terms of the GPL-3.0.
* See the [LICENSE](LICENSE) file in this repository for the full text.

The chess piece artwork in `Textures/` is derived from the CC BY-SA 3.0 assets above; those assets remain under CC BY-SA 3.0. Attribution and share-alike conditions are described in the "Chess piece artwork" section above.

---

## Version

Current addon version: **1.1.0** (see `DeltaChess.toc`).

Enjoy chess in Azeroth.
