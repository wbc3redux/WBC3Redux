extends Control
## The in-game interface for normal play (milestone 11-menus, UI_RESEARCH.md "Milestone 11"): the control panel at the
## bottom, the resource boxes, the in-game dialogs (game menu, options, yes/no message boxes), game speed and pause,
## and map scrolling. Presentational where the simulation already has the data; the actions call main.gd's existing
## order functions.
##
## Presentation (deliberate change, labelled): the original 1600x1200 layout of the control panel (0x4d6e00 with the
## 1600 branch, Panel_1600.bmp) on a 1600x900 virtual screen, i.e. 300 fewer world rows. Every 1600-mode coordinate below
## is used with y - 300.
## Native resolution (DELIBERATE MODERN CHANGE, display.gd / DISPLAY_SETTINGS.md): the virtual screen is drawn at the
## shared view scale (not the window width), its bottom on the window's bottom and the 1600 columns centred (panel_x);
## past the bitmap's ends the panel's stone is repeated, and a narrower window cuts the decorative ends. The army counter
## and the resource boxes keep to the world view's left and right edges.
##
## Read (0x4d6e00 geometry, 1600 mode): panel rect (0, 1050, 1600, 150); its bitmap starts at +4 - +8 = 1056 - 45 = 1011;
## strategic map (420, 1056) 128x128; hero portrait (585, 1056) 98x98 with bars at y 1155 / 1167 (98x11) and 1179 (98x4)
## from Panel_Bars.bmp; selection area (704, 1052) 342x144 with the single-unit icon centred at (803, 1125); command grid
## (1049, 1053) 134x134 from Panel_Buttons.bmp, cell k at +8 + 43 * (col, row), 38x38 frame, 32x32 icon (0x4dcdf0) from
## Panel_Icons.bmp (icon n at x (n - 1) * 32, rows 0 / 32 / 64); round buttons (550, 1107) / (550, 1147) / (1020, 1107) /
## (1020, 1145) 30x30 from Panel_Menu.bmp. Command icons for own units 1, 2, 3, 4, 5, 21 (0x4d2300 mode 3: Stop, Move,
## Attack, Patrol, ...). Resource boxes (0x497500, layout 4 set when the view starts, 0x41e320): 50x20 at (1375 + 55 i, 5)
## in 1600 mode (parity pass 3: 0x4978b0 points the layout table 0x60e2c8 at 0x60e268.. for 1600, 0x60e208.. for 1280,
## 0x60e1a8.. for 1024 (799 + 55 i, which the original's screenshot shows) and 0x60e148.. for 800), ERIX frames 0 / 2 / 1 / 3
## for gold, metal, stone, crystal (0x60e2e0), ERNX digits 7 px apart from x + 33 + n / 2. The army counter (0x497140,
## redrawn by 0x4974e0 when 0x533fb0 sees the population 0x709124 / limit 0x709108 change): ERIX frame 8 (60x20) at
## (5, 5) (0x60e144); the current count right to left from x + n * 7 / 2 + 14, ERNX frame 10 ('/') at x + 31, the limit
## right to left from x + m * 7 / 2 + 42, all at y + 5.
## Keys (English/KeyMap.txt order -> 0x427fb0): Alt+G game menu, F12 pause, = / + faster, - slower, Alt+O options,
## Alt+Q quit, Alt+R resign; Space pauses when SpacebarPauses is on. Game speed: 0x60c3ee = GameSpeed + 1 (1..5, 0 =
## paused), clock factor 1/2, 3/4, 1, 3/2, 2 (0x458dd0); the pause also silences the effects (0x429590). Scrolling: every
## 50 ms timer tick the arrows or the screen edge move the view ScrollRate cells (0x41e320 / 0x41e020).
##
## Milestone 13 (Read, UI_RESEARCH.md "Milestone 13"): a selected own building gets the mode-5 page of 0x4d2300 (cell 0
## Stop / Cancel icon 1, cell 1 Production icon 7, cell 2 Rally icon 19, cell 6 Repair icon 17, cell 7 the building's
## command: Market trade icon 29, cell 8 its power: Holy Word icon 51, Sword of Sirian icon 96); Production opens the
## production dialog 0x568290 (EMDP 610x450 at (880, 290), nine 107-pixel slots in four columns from (95, 58), 0x568ff0),
## units and buildings drawn from their 'i' sheet, research and upgrades from Powerups<race>.bmp (90x90, index 0x439050);
## the Market's command opens the trade dialog 0x5723a0 (EMDX 450x431 at (1000, 350)). Cells are filled through
## `building_cells`, one slot per original cell, so other buttons (the Keep conversion) can claim a free slot.
## Open / provisional: the builder's construction page (the rebuild opens the production dialog with the construction
## row, H0 for the hero, H0 / H1 for other builders as 0x4fd940 lists them); cells 3 to 5 of mode 5 (tower attack,
## garrison, formations) and the Repair command; the multi-selection layout; the hero area's other labels.
##
## Parity pass 3: Build (icon 0x1f, handler 0x4ce710, disassembled) opens the same dialog 0x568290 with the list of
## 0x4cdc30 and mode 1, so the construction dialog is the production dialog (Read). Its place in 1600 mode is (880, 290)
## (1280: (600, 190), 1024: (390, 90)): above the panel, about half way down the view. Presentation (deliberate, labelled):
## on the shorter 1600x900 view each dialog keeps its share of the free height, y = y1600 * (view - h) / (1050 - h), at
## least 0, so it is never cut off at the top (`dialog_origin`). Prices (0x569450, disassembled): per lane with a cost,
## crystal, stone, metal, gold, an ERIX frame 7 / 5 / 6 / 4 (small icon box) at the slot + (1, 0x45), stacking upward
## 0x15 per lane, its digits left to right from x + 16, 8 apart, y + 5.
##
## HUD pass (Read): the round buttons. 0x4d6e00 sets their hit areas, 0x4d6620 finds the left pair and 0x4d6790 the right
## pair (ids 0x28 / 0x29); the press sets the button's state to 2 (1 under the cursor) and 0x4d5d10 acts on the release:
## top left = Inventory (0x55e0e0), bottom left = Spellbook (0x56f910, only when the hero knows a spell: 0x4cde10), top
## right (0x29) = Game Menu (0x4d3080 -> 0x565670), bottom right (0x28) = Diplomacy (0x558810). Panel_Menu.bmp holds per
## row (diplomacy, menu, inventory, spellbook) the frames normal, under the cursor, pressed, disabled. The tooltips are
## Game.txt [0034] Item Inventory (i), [0011] Spellbook (s), [0095] Game Menu (Alt+G), [0211] Diplomacy.
## Diplomacy (0x558810, 'EMDA' 450x431 at (1000, 350) in 1600 mode): resources are sent to another player. Hit areas
## (0x558e20): amounts 50 / 100 / 200 / 300 / 400 / 500 (0x614e68) at x 0x4c..0x7a, rows 0x1b high from 0x81; the four
## carts gold, metal, stone, crystal at x 0x93..0xc6, rows 0x2e high from 0x79; player p (active, not the local player,
## not eliminated) at x 0xe4..0x16e, y 0x6b + 0x23 p .. + 0x23; Send at (0x5d..0x15a, 0x151..0x171); close (0xcd, 0x171).
## Send (0x559690) needs all three choices and the stock, takes the amount from the sender (0x43eb80) and messages the
## receiver (0x123), then clears the choices. Provisional: the receiver's credit (capped like any credit) and the drawing
## (0x558ec0.. is not decompiled): selection frames as in the trade dialog, the player gems ('ESHD', 25x20 per colour)
## and names on the sheet's diamonds, "Resources Sent" ([0299]) on the Send bar.
## Spellbook (0x56f910, 'EMDS' 613x445 at (494, 285)): one school per page; the arrows (0x33..0x79, 0x14..0x52) and
## (0x1df..0x225, 0x13..0x51) step to the previous / next school with a known spell; the ten spell rows at x 0x2d..0x10d,
## y 100 + 0x17 k (0x570510); close (0x120, 0x17e). Spell i (English/Spells.txt) is school i / 10's spell i % 10 and is
## known when i % 10 < the school level (0x40c6b0; levels from skills 10..22, HeroEffects.hero_unit). Spells are not
## simulated, so a click on a known spell only names it (Open: 0x5717e0 casting).
## Quest (0x56a150 mode 5, 'EMDQ' 430x417 at (970, 350)): the active quest's portrait, name, REPT text and progress;
## close (0x4f, 0x159). Opened by q. Q-2: draw_quest_sheet (0x56aff0, Read).
const Assets = preload("res://core/asset_store.gd")

const CombatRules = preload("res://simulation/combat_rules.gd")
const Settings = preload("res://simulation/game_settings.gd")
const DisplayConfig = preload("res://core/display.gd")
const OptionsScreen = preload("res://menus/options_screen.gd")
const UiCanvas = preload("res://core/ui_canvas.gd")
const MatchConversion = preload("res://simulation/match_conversion.gd")
const SaveGameFile = preload("res://simulation/save_game.gd")
# R-1: game_hud.gd's functions by area, in helper scripts that hold no state (README.md "Where things are").
const HudCells = preload("res://hud/hud_cells.gd")
const HudRoundButtons = preload("res://hud/hud_round_buttons.gd")
const HudDialogs = preload("res://hud/hud_dialogs.gd")
const HudPanel = preload("res://hud/hud_panel.gd")
const HudInfo = preload("res://hud/hud_info.gd")
const HudSites = preload("res://hud/hud_sites.gd")
var _cells := HudCells.new(self)
var _round := HudRoundButtons.new(self)
var _dialogs := HudDialogs.new(self)
var _panel := HudPanel.new(self)
var _info := HudInfo.new(self)
var _sites := HudSites.new(self)
const VIRTUAL_W := 1600.0
const Y_SHIFT := 300.0                       # 1600x1200 layout on a 1600x900 virtual screen
const PANEL_TOP := 1050.0 - Y_SHIFT
const BITMAP_TOP := 1011.0 - Y_SHIFT
const MAP_RECT := Rect2(420, 1056 - Y_SHIFT, 128, 128)
const PORTRAIT := Rect2(585, 1056 - Y_SHIFT, 98, 98)
const BARS := [Rect2(585, 1155 - Y_SHIFT, 98, 11), Rect2(585, 1167 - Y_SHIFT, 98, 11), Rect2(585, 1179 - Y_SHIFT, 98, 4)]
const INFO := Rect2(704, 1052 - Y_SHIFT, 342, 144)
const INFO_ICON_CENTRE := Vector2(803, 1125 - Y_SHIFT)
const GRID := Vector2(1049, 1053 - Y_SHIFT)
const ROUND := {"inventory": Rect2(550, 1107 - Y_SHIFT, 30, 30), "spellbook": Rect2(550, 1147 - Y_SHIFT, 30, 30),
	"menu": Rect2(1020, 1107 - Y_SHIFT, 30, 30), "diplomacy": Rect2(1020, 1145 - Y_SHIFT, 30, 30)}
const ROUND_ROW := {"diplomacy": 0, "menu": 1, "inventory": 2, "spellbook": 3}     # Panel_Menu.bmp rows
const ROUND_TIP := {"inventory": 34, "spellbook": 11, "menu": 95, "diplomacy": 211}
const SEND_AMOUNTS := [50, 100, 200, 300, 400, 500]                                  # 0x614e68
const SEND_LANE := [0, 1, 3, 2]              # diplomacy carts gold, metal, stone, crystal -> economy lanes
const RESOURCE_BOX := [Vector2(1375, 5), Vector2(1430, 5), Vector2(1485, 5), Vector2(1540, 5)]   # 0x60e2a8 (1600 mode)
const ARMY_BOX := Vector2(5, 5)              # 0x60e144
const END_MARGIN := 4                        # Panel_1600.bmp: the stone column repeated past the ends (modern change)
const END_STRIP := 48
const RESOURCE_LANE := [0, 1, 3, 2]          # gold 0x708fb4, metal fb6, stone fba, crystal fb8 (lanes: gold, metal, crystal, stone)
const RESOURCE_FRAME := [0, 2, 1, 3]         # 0x60e2e0
const DIALOG_AT := {"menu": Vector2(1024, 350), "options": Vector2(950, 350), "box": Vector2(500, 380), "load": Vector2(1025, 350),
	"production": Vector2(880, 290), "construct": Vector2(880, 290), "market": Vector2(1000, 350),
	"diplomacy": Vector2(1000, 350), "spellbook": Vector2(494, 285), "quest": Vector2(970, 350),
	"inventory": Vector2(800, 350), "shop": Vector2(1000, 350)}   # 1600-mode places (inventory: 0x55e0e0, shop: 0x56dc00)
const DIALOG_HEIGHT := {"menu": 431, "options": 431, "box": 300, "load": 431, "production": 450, "construct": 450, "market": 431,
	"diplomacy": 431, "spellbook": 445, "quest": 417, "inventory": 345, "shop": 431}
const PRICE_FRAME := [4, 6, 7, 5]            # 0x569450: ERIX frame per lane (gold, metal, crystal, stone)
const PRICE_ORDER := [2, 3, 1, 0]            # drawn crystal, stone, metal, gold, bottom up
## 0x439050: the Powerups column of each upgrade / research id, by the local player's race (16 tables 0x6089dc .. 0x609174,
## counts after each; read from the exe). 0x4d6e00 loads that race's Powerups<race>.bmp (0x1d1) and _Small (0x1d2).
const POWERUPS := {
	0: ["BKK1", "BKK2", "BKK3", "BKK4", "PORO", "POLI", "PWE0", "PWE1", "PAR0", "PAR1", "PWAR", "PFLE", "PBOW",
		"PFLA", "PIB0", "PIB1", "PIB2", "PTRA", "PHOC", "PFPA", "PROD", "PHOL", "PPAL", "PGRA", "POPE", "PORA",
		"POGL", "PODR", "BAV1", "BAV2", "PCR0", "PCR1", "PCR2", "PCR3", "PCR4", "PQKN", "PSWS"],   # Knight
	1: ["BKD1", "BKD2", "BKD3", "BKD4", "PMSG", "PMSR", "PWE0", "PWE1", "PAR0", "PAR1", "PMIT", "PFLE", "PBOW",
		"PSIE", "PIB0", "PIB1", "PIB2", "PTRA", "PDRU", "PMO0", "PMO1", "PMO2", "PENG", "PMAS", "BAV1", "BAV2"],   # Dwarf
	2: ["BKU1", "BKU2", "BKU3", "BKU4", "BAE1", "BAE2", "PWE0", "PWE1", "PANT", "PHAU", "PWAI", "PTOR", "PFAL",
		"PSLH", "PMR0", "PMR1", "PMR2", "PZOM", "PTOM", "PVAM", "PDKC", "PDKL", "PBUR", "PSPR", "PARR", "PSTA",
		"PLKG"],   # Undead
	3: ["BKB1", "BKB2", "BKB3", "BKB4", "BAN1", "BAN2", "PRA0", "PRA1", "PRA2", "PMR0", "PMR1", "PMR2", "PHOM",
		"PHOR", "PIB0", "PIB1", "PIB2", "PTRA", "PREA", "PTRM", "PHUN", "PMAG", "PBAR", "PSPE", "PTRN", "PGLA",
		"PJIH", "PTRK", "PFAN", "PHD0", "PHD1", "PHD2", "PHD3", "PHD4", "PHD5", "PHD6", "PHD7", "PHD8"],   # Barbarian
	4: ["BKH1", "BKH2", "BKH3", "BKH4", "BAV1", "BAV2", "PRA0", "PRA1", "PRA2", "PMR0", "PMR1", "PMR2", "PTRN",
		"PFAN", "PMO0", "PMO1", "PMO2", "PDRU", "PSH0", "PSH1", "PFAR", "PIR0", "PIR1", "PSHA", "PHAN", "PTHA",
		"PWIN", "PRSA", "PSPI"],   # Minotaur
	5: ["BKO1", "BKO2", "BKO3", "BKO4", "BAE1", "BAE2", "PRA0", "PRA1", "PRA2", "PHAG", "POGR", "PGIA", "PTRN",
		"PTHU", "PWF0", "PWF1", "PWF2", "PRAB", "PNOP", "PCOW", "PSLH", "PSHA"],   # Orc
	6: ["BKE1", "BKE2", "BKE3", "BKE4", "BAN1", "BAN2", "RCIE", "RANI", "RMAN", "RVIV", "PDK0", "PFLE", "PBOW",
		"PFLA", "PIB0", "PIB1", "PIB2", "PTRA", "PHOC", "PDK1", "PROD", "PHOL", "PDK2", "PWSP", "PDWA", "PUNI",
		"PME0", "PME1", "PME2", "PRG0", "PRG1", "PRG2", "PELC"],   # HighElf
	7: ["BKW1", "BKW2", "BKW3", "BKW4", "BAN1", "BAN2", "RCIE", "RANI", "RMAN", "RARB", "PBOM", "PFLE", "PBOW",
		"PFLA", "PMO0", "PMO1", "PMO2", "PTRA", "PRA0", "PRA1", "PRA2", "PFAR", "PTHO", "PWSP", "PIRB", "PMIG",
		"PME0", "PME1", "PME2", "PRG0", "PRG1", "PRG2", "PELC"],   # WoodElf
	8: ["BKT1", "BKT2", "BKT3", "BKT4", "BAE1", "BAE2", "RCIE", "RANI", "RMAN", "RMOR", "PSAC", "PFLE", "PBOW",
		"PFLA", "PRE0", "PRE1", "PRE2", "PBUR", "PSLH", "PBLP", "PDAO", "PSO0", "PSO1", "PWSP", "PDAR", "PHAG",
		"PME0", "PME1", "PME2", "PMR0", "PMR1", "PMR2"],   # DarkElf
	9: ["BKF1", "BKF2", "BKF3", "BKF4", "BAN1", "BAN2", "PFBL", "PFFI", "PFSI", "PFKN", "PZE0", "PZE1", "PZE2",
		"PPA0", "PPA1", "PLO0", "PLO1", "PLO2", "PLO3", "PLO4", "PLO5", "PLO6", "PLO7", "PLO8", "PRA0", "PRA1",
		"PRA2", "PFAR", "PUNI", "PIB0", "PIB1", "PIB2", "PIB3", "PME0", "PME1", "PMR0", "PMR1"],   # Fey
	10: ["BKA1", "BKA2", "BKA3", "BKA4", "BAV1", "BAV2", "PWE0", "PWE1", "PAR0", "PAR1", "PMIT", "PSHT", "PIRO",
		"PBRO", "PIB0", "PIB1", "PSPP", "PTRA", "PSIE", "PFOR", "PAF0", "PAF1", "PAS0", "PAS1", "PEPO", "PFP0",
		"PFP1", "PFP2", "PWYV"],   # DarkDwarf
	11: ["BKV1", "BKV2", "BKV3", "BKV4", "BAE1", "BAE2", "BWL1", "BAS1", "BAS2", "PBIN", "PCTH", "PDS0", "PDS1",
		"PIFU", "PDWI", "PSCL", "PHAG", "PBRD", "PSU0", "PSU1", "PGA0", "PGA1", "PIN0", "PIN1", "PMR0", "PDBT",
		"PHL0", "PHL1", "PHL2"],   # Daemon
	12: ["BKP1", "BKP2", "BKP3", "BKP4", "PPGU", "PRGU", "PWE0", "PWE1", "PAR0", "PAR1", "PIGU", "PFLE", "PBOW",
		"PFLA", "PIB0", "PIB1", "PTRA", "PSY0", "PSY1", "PSY2", "PSY3", "PMO0", "PMO1", "PMO2", "PSPR", "PARR",
		"PLI0", "PLI1", "BAV1", "BAV2", "PFM0", "PFM1", "PFM2", "POMA", "POMB", "POMC"],   # Empire
	13: ["BKL1", "BKL2", "BKL3", "BKL4", "BAN1", "BAN2", "PRA0", "PRA1", "PRA2", "PMR0", "PMR1", "PMR2", "PFAR",
		"PROD", "PRR0", "PRR1", "PRR2", "PWRM", "PSP0", "PSP1", "PSP2", "PBLE", "PPC0", "PPC1", "PPC2", "PCFA",
		"PCON", "PMLK", "PCWR", "PDEF"],   # Ssrathi
	14: ["BKR1", "BKR2", "BKR3", "BKR4", "BAE1", "BAE2", "PRA0", "PRA1", "PRA2", "PMR0", "PMR1", "PMR2", "PFAR",
		"PFER", "PFA0", "PFA1", "PFA2", "PFA3", "PMBL", "PMCU", "PMO0", "PMO1", "PMO2", "PIU0", "PIU1", "PIU2",
		"PIU3", "PIU4", "PIU5", "PIU6", "PIU7", "PIU8", "BAH1", "BAH2", "BAH3", "BAH4"],   # Swarm
	15: ["BKG1", "BKG2", "BKG3", "BKG4", "BAE1", "BAE2", "PCN0", "PCN1", "PCN2", "PCN3", "PCN4", "PAC0", "PAC1",
		"PAC2", "PFV0", "PFV1", "PFV2", "PMU0", "PMU1", "PMU2", "PANO", "PSPO", "PMR0", "PMR1", "PMR2", "BPIC",
		"PVI0", "PVI1", "PVI2", "PVI3", "PVI4", "PVI5", "BPFC"],   # Plaguelords
}
const POWERUP_SHEETS := ["Knight", "Dwarf", "Undead", "Barbarian", "Minotaur", "Orc", "HighElf", "WoodElf", "DarkElf", "Fey", "DarkDwarf", "Daemon", "Empire", "Ssrathi", "Swarm", "Plaguelords"]
const SLOT_ORIGIN := Vector2(0x5f, 0x3a)     # 0x568ff0: slot k at + 0x6b * (k % 4, k / 4), 0x6b square
const SLOT_STEP := 0x6b
const MARKET_FROM_X := [0x8f, 0xd5]          # 0x573010 hit areas (dialog-relative)
const MARKET_TO_X := [0xf4, 0x145]
const MARKET_ROWS := [0x78, 0xa6, 0xd4, 0x102, 0x130]
const MARKET_AMOUNT_X := [0x30, 0x78]
const MARKET_AMOUNT_ROWS := [0x82, 0x9e, 0xb9, 0xd4, 0xef, 0x10a, 0x125]
const CELL_LABEL := {1: 1, 2: 2, 3: 3, 4: 4}  # Game.txt tooltips [0001].. for the mode-3 icons whose meaning is certain

var main
var settings
var canvas := UiCanvas.new()                 # fonts and XCI strings
var textures := {}
var scale_factor := 1.0                      # the shared view scale (display.gd)
var panel_x := 0.0                           # virtual x of the 1600-mode column 0 (centred)
var bars := 0.0                              # window pixels of black bar on each side of the world view
var options_layer: CanvasLayer                # the options screen over the match (open_options)
var options_paused := false                  # the options screen paused the match (resumed on close)
var speed := 3                               # 0x60c3ee: 0 paused, 1..5
var speed_before_pause := 3
var volume_before_pause := 120
var page := "units"                          # "units", "build"
var cells: Array = []                        # 9 command cells {icon, sheet, enabled, action, tip}
var hovered_cell := -1
var dialog := ""                             # "", "menu", "options", "resign", "quit", "victory"
var dialog_hover := -1
var scroll_ms := 0.0
var message := ""
var message_ms := 0
var map_drag := false
var dialog_items: Array = []                 # production / construct dialog: nine entries {id, kind} or {}
var dialog_building := -1                    # the building whose production dialog is open
var dialog_slot := -1                        # hovered slot (0x568e30)
var market := {"from": -1, "to": -1, "amount": -1}
var round_hover := ""                        # the round button under the cursor (state 1)
var round_down := ""                         # the round button being pressed (state 2)
var diplomacy := {"amount": -1, "resource": -1, "player": -1, "sent": false}
var spell_school := 0                        # the spellbook's page (0x136)
var spell_hover := -1                        # hovered spell row (+0x140)

func _ready():
	settings = Settings.current()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.visible = false
	add_child(canvas)
	canvas.setup(Assets.json("ui_layout.json"))
	update_geometry()
	speed = settings.get_value("GameSpeed") + 1
	apply_speed()

func tex(name: String) -> Texture2D:
	if textures.has(name): return textures[name]
	var extra: Dictionary = canvas.layout.get("extra_bitmaps", {})
	var t: Texture2D = null
	if extra.has(name): t = Assets.texture(String(extra[name].file))
	else:                                        # an RS sheet the art import decodes as an effect (EMDD, the inventory)
		var effect: Dictionary = preload("res://core/art_data.gd").data().get("effects", {}).get(name, {})
		if effect.has("texture"): t = Assets.texture(String(effect.texture))
	textures[name] = t
	return t

func game_text(id: int) -> String:
	return String(canvas.layout.get("game_text", {}).get(str(id), ""))

# ------------------------------------------------------------------------------------------------ geometry
func virtual_height() -> float:
	return get_viewport_rect().size.y / scale_factor

func to_virtual(point: Vector2) -> Vector2:
	return point / scale_factor - Vector2(panel_x, 0)

## Window width in virtual pixels.
func virtual_width() -> float:
	return get_viewport_rect().size.x / scale_factor

## Recomputes the shared scale, the panel's centring and the world view's bars for the current window.
func update_geometry():
	var window := get_viewport_rect().size
	scale_factor = DisplayConfig.view_scale(window)
	panel_x = floorf((window.x / scale_factor - VIRTUAL_W) / 2.0)
	bars = DisplayConfig.view_bars(window, scale_factor)

## A window point in a world-view side bar (above the panel).
func in_bar(point: Vector2) -> bool:
	return bars > 0.0 and (point.x < bars or point.x >= get_viewport_rect().size.x - bars)

func over_panel(v: Vector2) -> bool:
	return v.y >= PANEL_TOP + (virtual_height() - 900.0)

## y of a 1600x900-virtual coordinate on the current window (the panel sits at the bottom).
func oy() -> float:
	return virtual_height() - 900.0

func _process(delta: float):
	update_geometry()
	if main == null: return
	scroll(delta)
	refresh_cells()
	if dialog == "shop":
		shop_check_ms += delta * 1000.0
		if shop_check_ms >= 1000.0:
			shop_check_ms = 0.0
			shop_check()
	queue_redraw()

# ------------------------------------------------------------------------------------------------ speed, pause, scroll
func apply_speed():
	if main == null: return
	main.time_scale = float(Settings.scaled_ms(1000, speed)) / 1000.0

## 0x429590: pause stores the speed and the effects volume and sets both to 0; resume restores them.
func toggle_pause():
	var audio = preload("res://core/audio_manager.gd").instance(get_tree())
	if speed == 0:
		speed = speed_before_pause
		audio.effects_volume = volume_before_pause
	else:
		speed_before_pause = speed
		speed = 0
		volume_before_pause = audio.effects_volume
		audio.effects_volume = 0
	audio.volumes = preload("res://simulation/audio_rules.gd").volume_table(audio.effects_volume)
	apply_speed()
	show_message(game_text(88 + speed))           # [0088] Game Paused, [0089 + n - 1] Game Speed: ...
	spell_pause_hook(speed == 0)

## 0x427fb0 '=' / '+': speed + 1 up to 5 (not while paused); '-': speed - 1 down to 1.
func change_speed(step: int):
	if speed <= 0: return
	var next := clampi(speed + step, 1, 5)
	if next == speed: return
	speed = next
	apply_speed()
	show_message(game_text(88 + speed))

func show_message(text: String):
	message = text
	message_ms = Time.get_ticks_msec() + 3000

## 0x41e320: every 50 ms tick, arrows or the window edge scroll ScrollRate cells (32 x 24 px each).
func scroll(delta: float):
	if dialog != "": return
	scroll_ms += delta * 1000.0
	while scroll_ms >= 50.0:
		scroll_ms -= 50.0
		var rate: int = settings.get_value("ScrollRate")
		var step := Vector2.ZERO
		var mouse := get_viewport().get_mouse_position()
		var size := get_viewport_rect().size
		var focused := DisplayServer.get_name() != "headless" and get_window().has_focus()
		if Input.is_key_pressed(KEY_LEFT) or (focused and mouse.x <= 0): step.x -= rate
		if Input.is_key_pressed(KEY_RIGHT) or (focused and mouse.x >= size.x - 1): step.x += rate
		if Input.is_key_pressed(KEY_UP) or (focused and mouse.y <= 0): step.y -= rate
		if Input.is_key_pressed(KEY_DOWN) or (focused and mouse.y >= size.y - 1): step.y += rate
		if step != Vector2.ZERO: scroll_by(step)

## One 50 ms tick of scrolling by `cells` (x 32, y 24 pixels per cell).
func scroll_by(cells_step: Vector2):
	main.set_view_top_left(main.view_top_left() + cells_step * Vector2(32, 24))     # clamped as 0x4907d0

# Command cells (R-1: the functions are in hud_cells.gd; these forward the ones called by name)
func icon_tip(icon: int) -> String: return _cells.icon_tip(icon)
func refresh_cells(): _cells.refresh_cells()
func press_icon(id: int) -> bool: return _cells.press_icon(id)
func building_cells(building) -> Array: return _cells.building_cells(building)
func open_production(building): _cells.open_production(building)
func open_market(): _cells.open_market()
func item_enabled(entry: Dictionary) -> bool: return _cells.item_enabled(entry)
func press_item(slot: int) -> bool: return _cells.press_item(slot)
func slot_at(local: Vector2) -> int: return _cells.slot_at(local)
func market_hit(local: Vector2) -> int: return _cells.market_hit(local)
func market_press(hit: int) -> bool: return _cells.market_press(hit)
func draw_converting(origin: Vector2, percent: int, unit: bool): _cells.draw_converting(origin, percent, unit)
func draw_production_bar(at: Vector2, percent: int): _cells.draw_production_bar(at, percent)
func affordable(item: String) -> bool: return _cells.affordable(item)
func display_name(type_id: String) -> String: return _cells.display_name(type_id)
func cell_rect(k: int) -> Rect2: return _cells.cell_rect(k)
func press_cell(k: int) -> bool: return _cells.press_cell(k)
func race_unit_cells(units: Array, next: int) -> int: return _cells.race_unit_cells(units, next)

## Tooltips by icon id (0x414ef0, Read): Game.txt line per icon; none while HelpLevel is 0 (0x608338).
const ICON_TIP := {1: 1, 2: 2, 3: 3, 4: 4, 5: 0x8d, 6: 5, 7: 10, 8: 11, 0x10: 14, 0x11: 7, 0x12: 6, 0x13: 13, 0x15: 0x47,
	0x1f: 8, 0x20: 9, 0x21: 12, 0x2a: 0x14, 0x2b: 0x13}

# ------------------------------------------------------------------------------------------------ input
func _input(event: InputEvent):
	if main == null or not visible: return
	if options_open(): return                                    # the options screen is modal
	if main.results_layer != null and main.results_layer.visible: return
	if event is InputEventKey and event.pressed and not event.echo:
		if handle_key(event): get_viewport().set_input_as_handled()
		return
	if not event is InputEventMouse: return
	var v := to_virtual(event.position)
	if dialog == "" and in_bar(event.position) and not over_panel(v):
		get_viewport().set_input_as_handled()      # the bars hide the world: no world clicks there
		return
	if dialog != "":
		dialog_mouse(event, v)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		hovered_cell = -1
		for k in 9:
			if cell_rect(k).has_point(v): hovered_cell = k
		round_hover = round_at(v)
		if map_drag: minimap_jump(v)
		if over_panel(v): get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			map_drag = false
			# 0x4d5d10: a round button acts when the button is released over it.
			var released := round_at(v)
			if released != "" and released == round_down: press_round(released)
			round_down = ""
			if over_panel(v): get_viewport().set_input_as_handled()
			return
		if over_panel(v):
			panel_click(v)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if MAP_RECT.has_point(v - Vector2(0, oy())):
			minimap_order(v, main.mods_of(event))
			get_viewport().set_input_as_handled()
		elif over_panel(v): get_viewport().set_input_as_handled()

## The strategic map with the right button (0x421190 event 1 over the panel, 0x4d64a0 maps the point to a cell): with own
## units selected a move to that place (the ground-move commands; Attack mode: attack-move, a move in the port; Patrol
## mode: a patrol point).
func minimap_order(v: Vector2, mods: Dictionary):
	var local := v - MAP_RECT.position - Vector2(0, oy())
	var world := minimap_cell(local) * Vector2(32, 24) + Vector2(16, 12)
	if not main.head_is_own_unit(): return
	if main.target_mode == 4:
		main.target_click(world, mods)
		return
	main.order_move(world, mods)
	main.target_mode = 0
	main.units_ordered.emit(main.own_selected().map(func(u): return u.unit_id))

## Numpad 1..9 (internal keys 501..509, 0x427fb0 -> 0x4d2210): the grid cell under the same position of the keypad.
const NUMPAD_CELL := {KEY_KP_1: 6, KEY_KP_2: 7, KEY_KP_3: 8, KEY_KP_4: 3, KEY_KP_5: 4, KEY_KP_6: 5, KEY_KP_7: 0, KEY_KP_8: 1, KEY_KP_9: 2}
## KeyMap.txt letters that press a grid icon (0x427fb0 cases 5..0x23 -> 0x4d2290). The spell lines that share these
## letters (KeyMap lines 0..14) are taken to apply only in the spellbook (table 0x74c4b0 not decoded, Provisional).
const KEY_ICON := {KEY_B: 0x1f, KEY_O: 0x20, KEY_W: 0x21, KEY_K: 7, KEY_E: 0x11, KEY_A: 3, KEY_F: 0x12, KEY_P: 4, KEY_V: 2,
	KEY_X: 0x13, KEY_G: 5}

func handle_key(event: InputEventKey) -> bool:
	if dialog == "spellbook" and spellbook_key(event): return true
	if dialog == "spell_choice" and event.keycode == KEY_ESCAPE:
		choose_spell_option(-1)
		return true
	if dialog in ["quest", "quest_offer"] and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		quest_confirm()                                     # 0x56abe0: Enter (0xd)
		return true
	if dialog != "":
		if event.keycode == KEY_ESCAPE:
			close_dialog()
			return true
		return event.alt_pressed
	if event.alt_pressed:
		match event.keycode:
			KEY_G: open_dialog("menu")
			KEY_O: open_options()
			KEY_Q: open_dialog("quit")
			KEY_R: open_dialog("resign")
			KEY_D: press_round("diplomacy")                  # KeyMap line 54 (0x558810)
			KEY_V: open_dialog("victory")                    # KeyMap line 56
			KEY_S:                                           # S-1: 0x427fb0 case 0x13, the quick save (no dialog open)
				if main.skirmish == null or main.skirmish.game_over or main.skirmish.over: return true
				save_now()
			KEY_L:                                           # S-1: case 0x14, the load sheet while a save exists
				if main.skirmish == null or main.skirmish.game_over or main.skirmish.over: return true
				if main.save_exists() or main.save_exists(true): open_load()
			KEY_H: cycle_help()
			_: return false
		return true
	var digit := -1
	if event.keycode >= KEY_0 and event.keycode <= KEY_9: digit = event.keycode - KEY_0
	if digit >= 0:
		if event.ctrl_pressed: main.assign_group(digit)       # internal keys 300..309 -> 0x425510
		else: main.recall_group(digit)                       # 0x30..0x39 -> 0x425700 / 0x4255f0 / 0x490850
		return true
	if NUMPAD_CELL.has(event.keycode):
		press_cell(int(NUMPAD_CELL[event.keycode]))
		return true
	if event.ctrl_pressed:
		match event.keycode:
			KEY_A: main.select_nearest(false, false)
			KEY_Z: main.select_nearest(true, false)
			KEY_S: main.select_nearest(false, true)
			KEY_T: main.select_nearest(true, true)
			KEY_H: main.select_hero_key(false)
			KEY_C: press_icon(6)
			KEY_TAB: main.cycle_building(not event.shift_pressed, true)   # 0x136 / 0x137 -> 0x425920(1) / 0x425a50(1)
			_: return false
		return true
	match event.keycode:
		KEY_F12: toggle_pause()
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD: change_speed(1)
		KEY_MINUS, KEY_KP_SUBTRACT: change_speed(-1)
		KEY_SPACE:
			if settings.get_value("SpacebarPauses") != 0: toggle_pause()
			else: main.alert_jump()                          # 0x427fb0: Space is the alert key when it does not pause
		KEY_PAGEUP: main.alert_jump()                        # KeyMap line 58 (0x74c4a8 = 0x104)
		KEY_TAB: main.cycle_building(not event.shift_pressed, false)   # 9 / 0xb -> 0x425920(0) / 0x425a50(0)
		KEY_QUOTELEFT: main.centre_on_head()                 # KeyMap line 28
		KEY_H:
			if not event.shift_pressed: return drink_hero_potion()   # h = Healing Potion (B1-6e: 0x561d80)
			main.select_hero_key(true)                       # H = add / remove hero (case 0xd)
		KEY_M:
			if event.shift_pressed: return false             # M = Drain Mana: a spellbook letter (KeyMap line 65)
			return drink_hero_mana_potion()                  # m = Mana Potion (KeyMap line 60, case 0x32 -> 0x561c30)
		KEY_I: press_round("inventory")                      # i = Inventory (0x55e0e0)
		KEY_S: press_round("spellbook")                      # s = Spellbook (KeyMap line 25)
		KEY_Q: press_round("quest")                          # q = Current Quest (KeyMap line 27)
		KEY_ESCAPE:
			# 0x427fb0: Esc presses Stop / Cancel (icon 1), else Cancel (icon 0x10); Shift+Esc (GetAsyncKeyState(0x10)) calls
			# 0x4296c0 instead: each selected unit with two or more orders loses its last one (G-2, Read).
			if event.shift_pressed: return main.remove_last_orders()
			if press_icon(1) or press_icon(0x10): return true
			if page == "units" and main.target_mode == 0: return false
			main.target_mode = 0
			page = "units"
		_:
			if KEY_ICON.has(event.keycode): press_icon(int(KEY_ICON[event.keycode]))
			else: return false
	return true

## Alt+H (KeyMap line 42, case 0x20): HelpLevel = (HelpLevel + 1) % 3 and the message line shows Game.txt [0067 + level].
func cycle_help():
	var level: int = (settings.get_value("HelpLevel") + 1) % 3
	settings.set_value("HelpLevel", level)
	settings.save()
	show_message(game_text(67 + level))

func panel_click(v: Vector2):
	if MAP_RECT.has_point(v - Vector2(0, oy())):
		map_drag = true
		minimap_jump(v)
		return
	if Rect2(PORTRAIT.position + Vector2(0, oy()), PORTRAIT.size).has_point(v):
		select_hero()
		return
	for k in 9:
		if cell_rect(k).has_point(v):
			press_cell(k)
			return
	round_down = round_at(v)                       # state 2 until the release (0x4d6620 / 0x4d6790)
	if round_down != "": return
	var building = main.selected_building()
	var hit := queue_hit(v, building) if building != null else -1
	if hit >= 0:
		queue_press(hit, building)
		return
	var info_rect := Rect2(INFO.position + Vector2(0, oy()), INFO.size)
	if info_rect.has_point(v):
		var units: Array = main.selected_units()
		if units.size() > 1:
			var index := info_index(v - info_rect.position)
			if index >= 0 and index < units.size():
				for u in main.units: u.selected = u == units[index]
				main.units_selected.emit([units[index].unit_id])

## Strategic map click (BUTT_CONTROLPANEL_STRAT): one map cell per pixel; the view centres on it (0x490850, clamped).
func minimap_jump(v: Vector2):
	var local := v - MAP_RECT.position - Vector2(0, oy())
	var at := minimap_cell(local)
	main.centre_view(at * Vector2(32, 24) + Vector2(16, 12))

## Game.txt [0036] "Left click selects hero (Ctrl+H)": select the hero and centre on it.
func select_hero():
	var hero = main.unit_by_id(main.hero_unit_id) if main.hero_unit_id >= 0 else null
	if hero == null or hero.dying or hero.removed: return
	main.pick_object(hero)
	main.centre_view(hero.position)
	main.units_selected.emit([hero.unit_id])

# Round buttons, spellbook, diplomacy, attitude and hero spells (R-1: the functions are in hud_round_buttons.gd; these forward the ones called by name)
func round_at(v: Vector2) -> String: return _round.round_at(v)
func press_round(kind: String) -> bool: return _round.press_round(kind)
func hero_schools() -> Array: return _round.hero_schools()
func hero_knows_spells() -> bool: return _round.hero_knows_spells()
func open_spellbook(): _round.open_spellbook()
func spell_row_at(local: Vector2) -> int: return _round.spell_row_at(local)
func spellbook_press(local: Vector2) -> bool: return _round.spellbook_press(local)
func spell_text(spell: int) -> Dictionary: return _round.spell_text(spell)
func diplomacy_hit(local: Vector2) -> int: return _round.diplomacy_hit(local)
func diplomacy_players() -> Array: return _round.diplomacy_players()
func diplomacy_press(hit: int) -> bool: return _round.diplomacy_press(hit)
func send_resources() -> bool: return _round.send_resources()
func player_label(p: int) -> String: return _round.player_label(p)
func quest(): return _round.quest()
func info_index(local: Vector2) -> int: return _round.info_index(local)
func attitude_rows() -> Array: return _round.attitude_rows()
func open_attitude(): _round.open_attitude()
func selection_attitude() -> int: return _round.selection_attitude()
func attitude_mouse(event: InputEventMouse, local: Vector2): _round.attitude_mouse(event, local)
func draw_attitude_dialog(at: Vector2): _round.draw_attitude_dialog(at)
func spell_affordable(spell: int) -> bool: return _round.spell_affordable(spell)
func spell_row_enabled(spell: int) -> bool: return _round.spell_row_enabled(spell)
func spell_request_shown(spell: int, result: Dictionary) -> Dictionary: return _round.spell_request_shown(spell, result)
func open_spell_trade(rate: int, title: String, close: bool): _round.open_spell_trade(rate, title, close)
func drink_hero_potion() -> bool: return _round.drink_hero_potion()
func drink_hero_mana_potion() -> bool: return _round.drink_hero_mana_potion()
func spellbook_key(event: InputEventKey) -> bool: return _round.spellbook_key(event)
func spell_choice_at(local: Vector2) -> int: return _round.spell_choice_at(local)
func spell_choice_press(local: Vector2): _round.spell_choice_press(local)
func choose_spell_option(i: int): _round.choose_spell_option(i)
func draw_spell_choice_dialog(at: Vector2): _round.draw_spell_choice_dialog(at)
func item_portraits() -> Texture2D: return _round.item_portraits()
func spell_pause_hook(paused: bool): _round.spell_pause_hook(paused)

## 0x40c6b0: spell i is known when i % 10 is below its school's level.
static func spell_known(schools: Array, spell: int) -> bool:
	var school := spell / 10
	return school < schools.size() and spell % 10 < int(schools[school])

# ------------------------------------------------------------------------------------------------ Attitude dialog (R-1)
## 0x559860 (Read): a list of the attitude scripts (0x585c30: all nine built-in ones) sorted by name (byte order), panel
## 0x17c wide, max(4, (n x 18 + 35) / 16) x 16 high, its top-left 100 left and 10 above the cursor, kept 8 pixels inside the
## view and 0x30 above its bottom. Rows are 18 apart from (10, 10): the script's icon of SkillIcons ((icon + 5) x 16, 0x28,
## 16 x 16) and its name in font 5 at +0x20. The selection's script (0x534140: -1 when mixed) is shaded, the row under the
## mouse framed (0xae x 0x12). A press on a row assigns the script (0x534070); any release closes (0x559e80).
## Provisional: the description of the hovered row (0x55a420's box) sits in the panel's free right part; a Guardian order's
## target cursor (0x507070 -> 0x425150(10)) is the Guard command's.
const ATTITUDE_WIDTH := 0x17c
const ATTITUDE_ROW := 0x12
const ATTITUDE_TOP := 10
var attitude_rect := Rect2()
var attitude_pressed := false

## 0x559860's placement: `cursor` and the view in the dialog's coordinates.
static func attitude_place(cursor: Vector2, count: int, view: Vector2) -> Rect2:
	var height: int = maxi(4, (count * ATTITUDE_ROW + 0x23) >> 4) << 4
	var x := cursor.x - 100.0
	var y := cursor.y - 10.0
	if x < 8: x = 8
	if view.x - 8 <= x + ATTITUDE_WIDTH: x = view.x - 8 - ATTITUDE_WIDTH
	if y < 8: y = 8
	if view.y - 0x30 <= y + height: y = view.y - 0x30 - height
	return Rect2(x, y, ATTITUDE_WIDTH, height)

# Dialogs: game menu, options, production, market, quest, load (R-1: the functions are in hud_dialogs.gd; these forward the ones called by name)
func open_dialog(kind: String): _dialogs.open_dialog(kind)
func close_dialog(): _dialogs.close_dialog()
func dialog_origin() -> Vector2: return _dialogs.dialog_origin()
func menu_row_enabled(row: int) -> bool: return _dialogs.menu_row_enabled(row)
func menu_row_at(local: Vector2) -> int: return _dialogs.menu_row_at(local)
func option_cell_at(local: Vector2) -> Vector2i: return _dialogs.option_cell_at(local)
func dialog_mouse(event: InputEventMouse, v: Vector2): _dialogs.dialog_mouse(event, v)
func menu_press(row: int) -> bool: return _dialogs.menu_press(row)
func open_options(): _dialogs.open_options()
func close_options(_saved: bool = false): _dialogs.close_options(_saved)
func options_open() -> bool: return _dialogs.options_open()
func options_screen(): return _dialogs.options_screen()
func option_press(row: int, column: int) -> bool: return _dialogs.option_press(row, column)
func box_button_at(local: Vector2) -> int: return _dialogs.box_button_at(local)
func box_press(button: int) -> bool: return _dialogs.box_press(button)
func draw_dialog(): _dialogs.draw_dialog()
func help_rows(desc: String, requ: String) -> Array: return _dialogs.help_rows(desc, requ)
func quest_lines(s: String, font_number: int) -> Array: return _dialogs.quest_lines(s, font_number)
func quest_progress_value(r: Dictionary, progress: int) -> int: return _dialogs.quest_progress_value(r, progress)
func draw_quest_sheet(at: Vector2, mode: String, r: Dictionary, progress: int): _dialogs.draw_quest_sheet(at, mode, r, progress)
func quest_hover_at(local: Vector2) -> int: return _dialogs.quest_hover_at(local)
func quest_confirm(): _dialogs.quest_confirm()
func open_load(): _dialogs.open_load()
func load_pick(choice: int): _dialogs.load_pick(choice)
func load_press() -> bool: return _dialogs.load_press()
func save_now(): await _dialogs.save_now()

## Presentation (labelled): the 1600-mode place `at` (view 1050 high) moved to a view `view_height` high, keeping the
## dialog's share of the free height; never above the top.
static func dialog_place(at: Vector2, height: int, view_height: float) -> Vector2:
	var y := floorf(at.y * maxf(0.0, view_height - height) / float(1050 - height))
	return Vector2(at.x, maxf(0.0, y))

## Game menu rows (0x566020): x 62..325, rows at 0x54.., 0x79.., 0x9e.., 0xc3.., 0xe8.., 0x10d.., 0x132.. (31 high).
const MENU_ROW_TOP := [0x54, 0x79, 0x9e, 0xc3, 0xe8, 0x10d, 0x132]
const MENU_ROW_TEXT := [306, 307, -1, 319, 320, 312, 321]      # Load Game, Save Game, Pause/Resume, Options, Victory Conditions, Resign, Quit
const OPTION_ROWS := [["ScrollRate", [328, 329, 330, 331, 332], [1, 2, 3, 4, 5]],
	["OverallVolume", [333, 334, 330, 335, 336], [0, 30, 60, 90, 120]],
	["MusicVolume", [333, 334, 330, 335, 336], [0, 1, 2, 3, 4]],
	["GammaCorrection", ["1", "2", "3", "4", "5"], [0, 1, 2, 3, 4]],
	["HelpLevel", [333, 337, 338], [0, 1, 2]]]                  # 0x566e40 captions; Game.txt ids
const OPTION_LABELS := [340, 341, 342, 344, 345]                # Scroll Rate, SFX Volume, Music Volume, Gamma (N/A), Popup Help

var quit_requested := false

# ------------------------------------------------------------------------------------------------ drawing
func _draw():
	if main == null: return
	var window := get_viewport_rect().size
	if bars > 0.0:
		draw_rect(Rect2(0, 0, bars, window.y), Color.BLACK)
		draw_rect(Rect2(window.x - bars, 0, bars, window.y), Color.BLACK)
	draw_set_transform(Vector2(panel_x * scale_factor, 0), 0.0, Vector2(scale_factor, scale_factor))
	var y := oy()
	draw_resources()
	draw_victory_status()
	var panel := tex("Panel_1600.bmp")
	if panel != null:
		draw_panel_ends(panel, y)
		draw_texture(panel, Vector2(0, BITMAP_TOP + y))
	draw_minimap(y)
	draw_hero(y)
	draw_info(y)
	draw_grid(y)
	draw_round_buttons(y)
	if message != "" and Time.get_ticks_msec() < message_ms:
		text(message, 1, Rect2(0, 120, VIRTUAL_W, 40), HORIZONTAL_ALIGNMENT_CENTER)
	draw_help_popup()
	if dialog != "": draw_dialog()

# Panel drawing: help, resources, army, minimap (R-1: the functions are in hud_panel.gd; these forward the ones called by name)
func help_lines(info: Dictionary) -> Array: return _panel.help_lines(info)
func draw_help_popup(): _panel.draw_help_popup()
func draw_round_buttons(y: float): _panel.draw_round_buttons(y)
func draw_panel_ends(panel: Texture2D, y: float): _panel.draw_panel_ends(panel, y)
func view_left() -> float: return _panel.view_left()
func draw_resources(): _panel.draw_resources()
func draw_minimap(y: float): _panel.draw_minimap(y)
func minimap_ornament() -> Texture2D: return _panel.minimap_ornament()
func minimap_cells_per_pixel() -> float: return _panel.minimap_cells_per_pixel()
func minimap_cell(local: Vector2) -> Vector2: return _panel.minimap_cell(local)

var _minimap: Texture2D
## The scenario's strategic-map image (SM24, assets/maps/<slug>/scenario_minimap.png: 128 x 128 in every scenario, so one
## pixel per cell on a 128 map), as an RGBA ImageTexture.
func minimap_texture() -> Texture2D:
	if _minimap == null and not preload("res://core/map_data.gd").is_generated():   # RM-3: a generated map has no image yet (black)
		var source: Texture2D = preload("res://core/map_data.gd").texture("scenario_minimap.png")
		if source != null:
			var image := source.get_image()
			image.convert(Image.FORMAT_RGBA8)
			_minimap = ImageTexture.create_from_image(image)
	return _minimap

## `s` cut with "..." so it fits `width` pixels in the font.
func fitted(s: String, font_number: int, width: float) -> String:
	var info: Dictionary = canvas.font(font_number)
	if info.is_empty() or info.font == null: return s
	var fits := func(t: String) -> bool: return info.font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, info.size).x <= width
	if fits.call(s): return s
	while s.length() > 0 and not fits.call(s + "..."): s = s.substr(0, s.length() - 1)
	return s.strip_edges() + "..."

## `s` broken into lines no wider than `width` pixels in the font.
func wrapped(s: String, font_number: int, width: float) -> Array:
	var info: Dictionary = canvas.font(font_number)
	if info.is_empty() or info.font == null: return [s]
	var lines: Array = []
	var line := ""
	for word in s.split(" ", false):
		var next := word if line == "" else line + " " + word
		if line != "" and info.font.get_string_size(next, HORIZONTAL_ALIGNMENT_LEFT, -1, info.size).x > width:
			lines.append(line)
			line = word
		else: line = next
	if line != "": lines.append(line)
	return lines

func text(s: String, font_number: int, rect: Rect2, align: int = HORIZONTAL_ALIGNMENT_LEFT, alpha: float = 1.0):
	var info: Dictionary = canvas.font(font_number)
	if s == "" or info.is_empty() or info.font == null: return
	var baseline: float = rect.position.y + int(info.baseline)
	var fade := Color(1, 1, 1, alpha)
	if info.shadow: draw_string(info.font, Vector2(rect.position.x + 1, baseline + 1), s, align, rect.size.x, info.size, Color.BLACK * fade)
	draw_string(info.font, Vector2(rect.position.x, baseline), s, align, rect.size.x, info.size, info.colour * fade)

class ArtTeams:
	static var _ramps: Array = []
	static func ramps() -> Array:
		if _ramps.is_empty():
			var art = Assets.json("art.json")
			_ramps = art.get("team", {}).get("ramps", []) if art is Dictionary else []
		return _ramps

# The info area: hero, units, buildings, towers, mines, queue (R-1: the functions are in hud_info.gd; these forward the ones called by name)
func team_colour(ramps: Array, owner: int) -> Color: return _info.team_colour(ramps, owner)
func draw_hero(y: float): _info.draw_hero(y)
func icon_sheet(type_id: String) -> Texture2D: return _info.icon_sheet(type_id)
func draw_info(y: float): _info.draw_info(y)
func draw_mine_info(mine_id: int, area: Rect2, y: float): _info.draw_mine_info(mine_id, area, y)
func draw_garrison_faces(building, y: float): _info.draw_garrison_faces(building, y)
func queue_view(building) -> bool: return _info.queue_view(building)
func local_race() -> int: return _info.local_race()
func powerup_columns() -> Array: return _info.powerup_columns()
func powerup_sheet() -> String: return _info.powerup_sheet()
func queue_hit(v: Vector2, building) -> int: return _info.queue_hit(v, building)
func queue_press(hit: int, building) -> bool: return _info.queue_press(hit, building)
func draw_unit_info(u, area: Rect2): _info.draw_unit_info(u, area)
func draw_grid(y: float): _info.draw_grid(y)

## The timer's digits as [{"x", "digit"}], right to left (C division of the milliseconds left by 1000).
static func quest_timer_digits(deadline_ms: int, now_ms: int) -> Array:
	var seconds: int = maxi(0, (deadline_ms - now_ms) / 1000)
	var digits := [seconds % 10, (seconds / 10) % 10, (seconds / 100) % 10]
	var n := 3 if digits[2] != 0 else (2 if digits[1] != 0 else 1)
	var out: Array = []
	var x := (n * 3 + 9) * 2
	for k in n:
		out.append({"x": x, "digit": digits[k]})
		x -= 6
	return out

## Playtest 2026-11-11: a mine in the info area (0x4d7710's resource-building branch, 0x52b050 true; Read, decompile
## 142655..142808). 1600-mode fields (0x4d6e00): +0x28 = 704, +0x46 = 0x23, +0x50 = 860, +0x52 = 0x23, +4 = 1056.
## The 'i' picture, the name (0x52afa0) in font 5 at (+0x50, +4 + +0x52); the reserve "%s: %d" (0x60f098) with Game.txt
## [0250] Gold / [0251] Metal / [0252] Stone / [0253] Crystal for the first non-empty of +0x8c / +0x8e / +0x92 / +0x90,
## or [0272] "Run Dry!" when all are empty, in font 2 at + (0x18, 0x2e); the workers: SkillIcons (0xca, 0x7d) 16 x 16
## at (+0x28 + 0xf, +4 + +0x46 + 0xc) and their count +0xca ("%d") 0x14 below, at x + 0x17.
## Not ported: the mine's hit points row (the rebuild's mines have none) and the recovery line [0273] with " (*)" while
## +0x115 is set (the rebuild's economy has no recovery). Provisional: the worker count's font (2).
const MINE_LANE_TEXT := [250, 251, 253, 252]       # economy lanes gold, metal, crystal, stone -> Game.txt line

## F9 (Read: 0x4d7710 mode 5, disassembly 0x4db5bf.. and its sibling branches; 1600-mode fields from 0x4d6e00: +4 = 1056,
## +0x50 = 860, +0x52 = 0x23): a building without the queue view shows its name (0x52afa0) in font 5 at (+0x50, +4 +
## +0x52), clipped to 0xa8 x 0x14, and "%d / %d" (0x60b64c, its hit points) in font 2 at + (0x24, 0x1a). The original has
## no "Life Points:" label there. The name is still cut with "..." before the horn (HUD pass). Provisional: the rows
## after the hit points (construction percent; another player's job), which the original fills per building kind
## (mines, towers, the 0x112 / 0x113 / 0x114 status lines) and which are not ported.
const BUILDING_NAME_AT := Vector2(860, 1091 - Y_SHIFT)

## P-2 (for the G-3 lane; Read, disassembly 0x4daa72..0x4dadd0, COMBAT_RESEARCH.md G-3 section 6): a tower's rows. The
## original draws right-aligned labels Game.txt [0258] Combat:, [0259] Hits:, [0260], [0261] and [0755] Range: 0x12 apart
## (0x46e380, font 2), their values 8 pixels right of the label column (0x46e350): Combat = 0x4ddeb0(0x52ae70(0),
## 0x52ae70(1)), "base +bonus" with the garrison's terms in the bonus; Hits "%d / %d" (BMFL: a fixed string). Ported here:
## those two rows. Provisional: the base is the BUI combat (Morph included) and the bonus everything building_block adds
## (difficulty term, garrison terms): which terms 0x52ae70(0) leaves out besides the garrison was not traced; the row
## positions follow the building rows (+0x24, 0x1a + 0x12 i). P-3 below: the Speed, Damage and Range rows.
## P-3 (Read: 0x52ae70, 0x52b0c0, 0x52e9e0 = building vtable +0x50, disassembly 0x4da917..0x4dadd0): 0x52ae70(0) is
## +0x68 alone (returns at once: no difficulty, no garrison term), so the Combat base is the BUI combat (Morph's word
## included) and the bonus 0x52ae70(1) - that: the computer's difficulty term and the garrison terms (building_block).
## Speed = 0x4ddeb0(0x52b0c0(0) = +0x6a, 0x52b0c0(1) = + Rules.garrison_rate). Damage / Range = 0x52e9e0(0) (+0x7c,
## +0x80) and 0x52e9e0(1): with a garrison each hero +20 damage, +2 range; each non-hero shooter (STATUS bit 18) +20 (bit
## 15) or +10 damage, +1 range. After the Damage value: DamageIcons.bmp (bitmap 0x189) 24 x 20 at x 24 type, the type the
## tower's own (+0x7e) or the best shooter's (bit 18, highest 0x51bd10(0) above -10), at value x + 4 + the text's width,
## 2 px above the row. Rows 0x14 + 0x12 i below the name (Read); x Provisional (P-2's +0x24); the occupants' faces
## (0x4ddd30, a 2 x 2 grid of 29 px at (+0x6e, +0x32) over Garrison.bmp 0x1df) are not drawn (Open).
## G-4 (Read, disassembly 0x4da94f..0x4dab83 with the 1600-mode fields of 0x4d6e00: +4 = 1056, +0x28 = 704, +0x2a = -4,
## +0x44 = 860, +0x46 = 0x23): the view's title is Game.txt [0126] "Tower" in font 5 at (+0x44, +4 + +0x46 - 0xa), not the
## building's name at +0x52; the labels end at x +0x44 + 0x54 (944, right-aligned, 0x46e380) on the rows 0x14 + 0x12 i
## below the title, the values start at +0x44 + 0x5c (952, 0x46e350). P-3 had the rows 10 pixels lower (below the name),
## so the fifth (Range) touched the panel's bottom edge at 1600 x 900. The occupants' faces: draw_garrison_faces.
const TOWER_TITLE_LINE := 126
const TOWER_LABEL_RIGHT := 944.0
const TOWER_VALUE_X := 952.0

## G-4 (Read, disassembly 0x4da9c4..0x4daa6c and 0x4ddd30): the occupants (+0xca count, +0xec ids) the registry finds
## (0x5322a0), at most four, each through 0x4ddd30 at (+0x28 + 2 + 0x6e + 29 (k & 1), +4 + +0x2a + 0x32 + 29 (k >> 1)):
## the SelectionRings.bmp frame by its life row and weight (+0xb2: 4 -> 56 x 56, 2 -> 28 x 56, else 28 x 28; column 1 for
## a hero or rank >= 4, as the selection list) and its 'i' sheet thumbnail at + 3. Open: Garrison.bmp (bitmap 0x1df,
## 309 x 129 at (+0x28 + 3, +4 + +0x2a + 1)) under them is not imported, and the original's small building picture
## (0x487f20 at (+0x28 + 9, +4 + +0x2a + 0x19)) where the rebuild keeps the large one.
const GARRISON_FACES := Vector2(816, 1102 - Y_SHIFT)

## F9 / F10 (Read: 0x4d7710 mode 5, disassembly 0x4dadd5..0x4db247; hit test 0x4d6790 mode 5; actions 0x4d54c0): an own
## building with a job (+0x9c set, pending included) shows its production instead of the name rows and the portrait.
## 1600 mode: ProductionSlots.bmp (bitmap 0xbe, 302 x 78) at (708, 1102); six 32 x 50 slots at x 715 + 41 k, y 1123
## (tables 0x60ea70 / 0x60ea7c), slot 0 the running job, slots 1..5 the first five type-2 orders of the order list (+0xbc);
## a unit shows its 'i' sheet frame 1 (32 x 50 at (0, 144), 0x487050 -> 0x487f20 frame 1), anything else
## PowerupsKnight_Small.bmp (bitmap 0x1d2) at x = 32 * 0x439050(id). Past the five, "+ %d" (0x60f0a0) of the order count
## less five (so "+ 0" with exactly five) in font 5 at (962, 1140) (0x60ea94). The Continuous Production box (+0x190): a
## 12 x 12 frame (0x46eb20, grey 200) at (790, 1078) (0x60eaa4), an 8 x 8 fill (0x46ed60, grey 180) at + 2 when set,
## Game.txt [0523] in font 2 at + (0xe, 1). ProductionBar.bmp (0xbf) at (719, 1064) with the job's percent (+0xaa), as in
## draw_converting. Clicks (0x4d6790 -> 0x4d54c0): the box's hit area, 0x80 x 0xe from its corner, flips +0x190 (id
## 0x36); slot k (32 x 50) cancels order k (ids 0x22.., 0x52d8a0: the running job refunded, a queued one dropped).
## Help (0x414940, HelpLevel > 1): over the box, Game.txt [0524] / [0525]. KeyMap.txt has no key for it.
## P-2 (Read, disassembly 0x4daf06..0x4daf29): a slot whose id is -1 (the pending job) shows SelectionRings.bmp (bitmap
## 0x66) at (0x188 + 32 f, 0x26b), 32 x 50, f = +0x458: the panel's event 9 (the 50 ms timer, 0x4d60f0) steps it
## (f + 1) & 7 every fifth event, so every 250 ms (pending_frame; the timer's phase is Provisional: the real-time clock).
const PENDING_SOURCE := Vector2(0x188, 0x26b)
const PENDING_STEP_MS := 250

static func pending_frame(ms: int) -> int:
	return (ms / PENDING_STEP_MS) & 7
const QUEUE_STRIP := Vector2(708, 1102 - Y_SHIFT)
const QUEUE_BAR := Vector2(719, 1064 - Y_SHIFT)
const QUEUE_SLOT_X := [715, 756, 797, 838, 879, 920]
const QUEUE_SLOT_Y := 1123 - Y_SHIFT
const QUEUE_SLOT := Vector2(0x20, 0x32)
const QUEUE_MORE := Vector2(962, 1140 - Y_SHIFT)
const REPEAT_BOX := Vector2(790, 1078 - Y_SHIFT)
const REPEAT_HIT := Vector2(0x80, 0xe)
const HIT_REPEAT := 0x36
const HIT_SLOT := 0x22

## The running job and the queued orders, one id per drawn slot (at most six).
static func queue_slots(building) -> Array:
	var ids := [String(building.job_item)]
	for q in building.queue:
		if ids.size() >= 6: break
		ids.append(String(q))
	return ids

## "+ %d" of the original: the order count less five, shown once it reaches zero (-1: nothing shown).
static func queue_more(building) -> int:
	return building.queue.size() - 5

## Parity pass 4: the multi-selection list of 0x4d7710 case 1 (Read, disassembly 0x4da352..). 32 slots, 8 x 4: x from the
## 1600 table 0x60ec4c (710 + 29 column), y = panel top + 0x60ec8c (12 + 29 row). The selection is walked three times:
## weight (+0xb2) 4 (2 x 2 slots, 56 x 56 frame, the next search starts 2 slots on), weight 2 (1 x 2, 28 x 56), then the
## rest (28 x 28); each takes the first free slot from where the last left off. Frames come from SelectionRings.bmp by
## life row r = 15 - life * 15 / max (0..15) and v = 1 for a hero or a unit with 0x526d80 >= 4: 56 x 56 at (((r >> 1) >> 2) + 3 + 2 v) * 56, ((r >> 1) & 3) * 56 + 0x1eb; 28 x 56 at
## (((r >> 1) >> 2) + 2 + 2 v) * 28, the same y; 28 x 28 at (28 v, (r >> 1) * 28 + 0x1eb). The unit's icon frame 5 (the
## 22 x 19 thumbnail of its 'i' sheet) is drawn at +3 in its own colours (0x487f20 colour -1).
const LIST_ORIGIN := Vector2(710, 12)
const LIST_STEP := 29

## R-1 (0x4da466, 0x4da60e, 0x4da7a6, 0x4ddd8c, Read): the frame column of a list slot: heroes and units of rank 4 or more.
static func list_frame(hero: bool, rank: int) -> int:
	return 1 if hero or rank >= 4 else 0

## 0x4d9793 (Read): the rank the rows show, at most 19 (0x12 < rank -> 0x13); [large medals, small medals] of it.
static func rank_medals(rank: int) -> Array:
	var level := mini(maxi(rank, 0), 19)
	return [level / 5, level % 5]

## P-2: 0x51bd10(0), the unit's raw combat +0x92 (combat.gd keeps it as the fighter's base block).
static func raw_combat(f) -> int:
	var base = f.get("base")
	return int(base.get("combat", f.stats.combat)) if base is Dictionary else int(f.stats.combat)

## 0x4ddeb0: "%d" when equal, "%d +%d" for a bonus, "%d %d" (a negative difference) for a malus.
static func bonus_text(base: int, effective: int) -> String:
	if base == effective: return str(base)
	return "%d +%d" % [base, effective - base] if effective > base else "%d %d" % [base, effective - base]

## HUD pass: where the panel's right horn and skull start to cover the info area at a 1600x900-virtual row (measured
## on Panel_1600.bmp, less a 4-pixel margin); text in the info area ends there instead of running under the art.
static func info_right_edge(row_top: float) -> float:
	var y1600 := row_top + Y_SHIFT
	if y1600 < 1080.0: return 978.0
	if y1600 < 1092.0: return 992.0
	return 1015.0

static func ProductionRules_is_building(type_id: String) -> bool:
	return type_id.begins_with("B")

## F8 (Read: 0x569450 disassembly, 0x568f50 -> 0x40aec0, 0x44f770): the hovered item's name in font 5 at (+0xd4, +0x116)
## and three rows in font 2 at (+0xde, +0x12b / +0x139 / +0x147), each a 100-byte string filled when the hovered slot
## changes. 0x40aec0 wraps Help.cfg's description (record +0x28) in font 2 to 0x10c pixels, at most three lines: one line
## leaves rows 2 and 3 to the requirements (record +0x8c) wrapped the same way; two lines leave row 3 to the requirements
## as they are; three lines fill every row. There is no build-time row (the rebuild's "60 s" row was its own). The
## y of the text call is used as the text's top + 4, as in draw_unit_info (checked there against the original).
const HELP_WRAP := 0x10c

# ------------------------------------------------------------------------------------------------ Q-2: the quest dialog
## QUESTS_RESEARCH.md "Q-2". 0x56aff0 (the dialog's draw, vtable 0x5eaa94 slot 7; disassembly, Read) for every mode of
## 0x56a150 (0 offer NEWQ, 1 continue CONT, 2 complete CMPL, 3 instant INST, 5 the q sheet REPT: the text slots
## +0xaa + 0x100 * mode that 0x52edb0 fills): the 'EMDQ' sheet; the close button 'EMDC' at (0x4f, 0x159), frame 1 under the
## mouse and 2 pressed; the record's portrait (image 0x184, "<portrait>.bmp" from Quest.xcr) 0x80 x 0xa0 at (0x4e, 0x4b);
## the name in font 0x18 centred on x 0xd5 at y 0x1c; the mode's text in font 0x13 over thirteen line slots (table
## 0x6152a4..0x615340: lines 0..8 x 0xd9 width 142, lines 9..12 x 0x46 width 290, y 72 + 20 * line; line 9 moves to x
## 0xd9 when it fits in 142); modes 1 and 5 add game line 325 (progress or, for type 0, the stockpile, of the count) in
## font 0x13 centred on x 0xd8 at y 0x13d; modes 0 and 3 add the button 'EMDE' (frame 1 under the mouse, 2 pressed) at
## (0x9c, 0x155) with game line 326 in font 5 centred on x 0xf6 at y 0x161 (0x162 pressed). Type 4 (a typed answer,
## Quest.cfg ANSW; no shipped record) draws an entry box instead and is not ported.
const QUEST_LINE_X := [0xd9, 0xd9, 0xd9, 0xd9, 0xd9, 0xd9, 0xd9, 0xd9, 0xd9, 0x46, 0x46, 0x46, 0x46]
const QUEST_LINE_W := [142, 142, 142, 142, 142, 142, 142, 142, 142, 290, 290, 290, 290]
const QUEST_LINE_Y0 := 72
const QUEST_LINE_STEP := 20
const QUEST_TEXT_KEYS := {"offer": "newq", "continue": "cont", "complete": "cmpl", "instant": "inst", "sheet": "rept"}
const QUEST_CLOSE := Rect2(0x4f, 0x159, 0x1e, 0x1e)            # 0x56a6f0 / 0x56a840: x 0x4f..0x6c, y 0x159..0x176
const QUEST_OKAY := Rect2(0x9c, 0x155, 0xb4, 0x24)             # x 0x9c..0x14f, y 0x155..0x178 (modes 0 and 3)
const QUEST_HOVER_CLOSE := 0
const QUEST_HOVER_OKAY := 1

# Victory status, quest offers, the shop, item lines and the inventory (R-1: the functions are in hud_sites.gd; these forward the ones called by name)
func victory_lines() -> Array: return _sites.victory_lines()
func draw_victory_status(): _sites.draw_victory_status()
func open_quest_offer(view: Dictionary): _sites.open_quest_offer(view)
func open_shop(building_id: int): _sites.open_shop(building_id)
func shop_hit(local: Vector2) -> int: return _sites.shop_hit(local)
func shop_flags() -> Array: return _sites.shop_flags()
func shop_mouse(event: InputEventMouse, local: Vector2): _sites.shop_mouse(event, local)
func shop_check(): _sites.shop_check()
func site_dialog_mouse(event: InputEventMouse, local: Vector2): _sites.site_dialog_mouse(event, local)
func draw_quest_offer(at: Vector2): _sites.draw_quest_offer(at)
func centred(s: String, font_number: int, x: float, y: float, width: float = 0x1c0): _sites.centred(s, font_number, x, y, width)
func draw_shop_dialog(at: Vector2): _sites.draw_shop_dialog(at)
func item_power_line(power: Dictionary) -> String: return _sites.item_power_line(power)
func draw_box_button(sheet: Texture2D, at: Vector2, index: int, caption: String, centre: Vector2): _sites.draw_box_button(sheet, at, index, caption, centre)
func draw_close(at: Vector2, frame: int = 0): _sites.draw_close(at, frame)
func inventory_mouse(event: InputEvent, local: Vector2): _sites.inventory_mouse(event, local)
func draw_inventory_dialog(at: Vector2): _sites.draw_inventory_dialog(at)

var quest_offer: Dictionary = {}
var score_rows: Array = []
var score_next_ms := 0
var shop_building := -1
var shop_close_state := 0                    # +0x128: the close button's frame (0 up, 1 under the cursor, 2 pressed)
var shop_close_armed := false                # +0x133: a press on the close button, acted on by the release
var shop_clicked := false                    # +0x135: a place was pressed; leaving the dialog now closes it
var shop_check_ms := 0.0                     # +0x138: the 1000 ms check (0x56e1a0 / 0x56e2e0)

# ------------------------------------------------------------------------------------------------ the shop (dialog 12)
## Dialog 12 (0x56dc00, vtable 0x5eab0c; the handlers are not in the decompile, Read from the disassembly): 'EMDK'
## 0x1c2 x 0x1af at (1000, 350) in 1600 mode (1280: (0x30c, 0xc3), 1024: (0x226, 0x5f)). The four places hold the
## Healing Potion (0xffff), the Mana Potion (0xfffe) and the shop's two items (0x408670(shop, 0 / 1)).
## * Hit (0x56e350): a place counts only while it holds a good; x 0x2f..0x89 / 0x8b..0xe5 / 0xe7..0x141 / 0x143..0x19d,
##   y 0x44..0x9e. Close x 0xcd..0xea, y 0x171..0x18e.
## * Press (+0x08, 0x56dfc0): on the close button it arms it (frame 2); on a place it buys at once (0x56e420) and marks
##   the dialog clicked; any press inside the dialog is taken. Release (+0x0c, 0x56e0b0): on the armed close button it
##   closes. Motion (+0x04, 0x56dde0): frame 1 over the close button (2 while armed), the place under the cursor
##   otherwise; once clicked, leaving the dialog's rectangle closes it. Every 1000 ms (+0x20, 0x56e2e0) the dialog closes
##   when the local hero is dead or the shop is gone (0x5322a0(id, 6)).
## * Draw (+0x1c, 0x56e8f0): the sheet; close (EMDC) at (0xcd, 0x171); [1125] "Shop" in font 1 centred at (0xda, 0x18);
##   each item's IDLG picture (row iconrow, column iconcol + 1) at (0x2f + 0x5c * place, 0x44), 0x14 lower for rows 5, 6,
##   7, 9, 10; an artifact (level 4) or set item (level 5) sparkles (SelectionRings.bmp, 0x28 x 0x2e at (0xf, 0x20) from
##   the picture's place, frames of the counter 0xbbf4d0 that the dialog's tick (+0x10) steps); the hovered place's
##   70 x 110 frame (SelectionRings.bmp (0x2d2, 0), red (0x2d2, 0xdc) when too expensive); "Too / Expensive" [1133 / 1134]
##   or, for a potion with 9 or more, "No / Room" [1135 / 1136] in font 20 centred at (0x52 + 0x5c * place, 0x6c / 0x80);
##   for the hovered good its name in font 5 centred at (0xdb, 0xc8) and in font 2 below: a potion's effect [1128 / 1131]
##   at 0xe4, its use [1129 / 1132] wrapped to 0x10e (three lines) from 0xf5 every 18, then "(You currently have %d)"
##   [1137]; an item's power lines (record +0x34, +0x12 of them) from 0xe4 every 18; the price in font 2 at (0x62 / 0xa7 /
##   0xea / 0x134, 0x12c) (gold, metal, stone, crystal: the same amount); a sold place "This item has been sold" [1124] in
##   font 5 at (0xdb, 0xe6); always "Click on an item to buy it" [1126] in font 2 centred at (0xd8, 0x151).
## Presentation (as the other dialogs): a call's y is the text's top + 4 (font 1: + 22). Provisional: the counter steps
## once per 25 ms update.
const SHOP_SIZE := Vector2(0x1c2, 0x1af)
const SHOP_CLOSE := Rect2(0xcd, 0x171, 0x1e, 0x1e)
const SHOP_LEFT := 0x2f
const SHOP_STEP := 0x5c
const SHOP_TOP := 0x44
const SHOP_PRICE_X := [0x62, 0xa7, 0xea, 0x134]       # gold, metal, stone, crystal
const SMALL_PICTURE_ROWS := [5, 6, 7, 9, 10]           # IDLG rows drawn 0x14 lower in a tall cell (0x56e8f0, 0x55fb90)

## 0x56e350: the four places of dialog 12 (x from the dialog's left, y 0x44..0x9e).
static func shop_place_at(local: Vector2) -> int:
	if local.y <= 0x43 or local.y >= 0x9f: return -1
	if local.x > 0x2e and local.x < 0x8a: return 0
	if local.x > 0x8a and local.x < 0xe6: return 1
	if local.x > 0xe6 and local.x < 0x142: return 2
	if local.x >= 0x143 and local.x <= 0x19d: return 3
	return -1

static func shop_close_hit(local: Vector2) -> bool:
	return local.x >= SHOP_CLOSE.position.x and local.x < SHOP_CLOSE.end.x and local.y >= SHOP_CLOSE.position.y and local.y < SHOP_CLOSE.end.y

## An item's IDLG cell: row iconrow, column iconcol + 1 (0x487f20(IDLG, row, col + 1) in 0x56e8f0 / 0x55fb90; column 0
## holds the small category icons).
static func item_cell(item: Dictionary) -> Rect2:
	return Rect2((int(item.get("iconcol", 0)) + 1) * 70, int(item.get("iconrow", 0)) * 110, 70, 110)

## The artifact (level 4) / set (level 5) sparkle frame `f` of SelectionRings.bmp (0x56e8f0 / 0x55fb90), or an empty rect.
static func sparkle_cell(level: int, f: int) -> Rect2:
	if level == 4: return Rect2(0x188 + 0x28 * (f & 7), 0x29d, 0x28, 0x2e)
	if level == 5: return Rect2(0x274 + 0x28 * (f & 3), 0x1e0 + 0x2e * ((f & 7) >> 2), 0x28, 0x2e)
	return Rect2()

# ------------------------------------------------------------------------------------------------ item power lines
## 0x403a90 (decompile, Read): an item power's line (record +0x34 + 100 * slot) is the Power element's own text when it
## has one, else Game.txt by type with the power's data: 1 [0435], 5 [0436], 6 [0447], 7 [0455], 10 [0470], 0x18 [0452],
## 0x1b [0461], 0x1c [0456], 0x20 [0457], 0x21 [0462], 0x22 [0459], 0x24 [0458], 0x2c [0463], 0x2d [0464], 0x2f [0437]
## (data x 10), 0x37 [0439] (x 10), 0x38 [0438], 0x39 [0465], 0x3a [0466], 0x3c [0460], 0x50 [0448], 0x51 [0451], 0x58
## [0449], 0x59 [0450], 0x5a [0442], 0x5b [0440], 0x5c [0441], 0x5d [0443], 0x5e [0444], 0x5f [0445], 0x60 [0446], 0x61
## [0453], 0xd nothing; 0xb the Merchant line [0692] / [0693] with 100 - 100 / (2 data + 100) x 100 percent; 0x62
## "Casts %s" [0454] with the spell's name and " (%d%% chance per hit)" [0469] with the chance; 99 (hero skill: data the
## skill, level its level) [0461 + skill] for the magic schools 10..22, else the skill's line of 0x556fc0.
## 0x556fc0 (decompile, Read): a skill's effect at a level: v = 0x556ea0(skill, level, 1) (HeroEffects.skill_term) into
## the Game.txt line of the table below ([id, multiplier, addend] of v; unlisted skills [0567]); 9 the Merchant line
## [0619]; 10..22 the school circles [0654] / [0650] / [0651] / [0652]; a negative level "No bonus".
const SKILL_TEXT := {1: [593, 1, 0], 2: [573, 1, 0], 3: [627, 1, 0], 4: [630, 1, 0], 5: [612, 1, 0], 6: [591, 1, 0], 
	7: [628, 1, 0], 8: [614, 1, 0], 23: [565, 1, 0], 24: [647, 1, 0], 25: [616, 1, 0], 26: [589, 1, 0], 27: [594, 1, 0], 
	28: [572, 1, 0], 29: [587, 1, 0], 30: [631, 1, 0], 31: [608, 1, 0], 32: [643, 1, 0], 33: [649, 1, 0], 
	34: [620, 1, 0], 35: [617, 1, 0], 36: [579, 1, 0], 37: [582, 1, 0], 38: [576, 1, 0], 39: [585, 1, 0], 
	40: [590, 1, 0], 41: [622, 1, 0], 42: [606, 1, 0], 43: [641, 1, 0], 44: [653, 1, 0], 45: [626, 1, 0], 
	46: [580, 1, 0], 47: [634, 1, 0], 48: [569, 1, 0], 49: [571, 1, 0], 51: [567, 1, 0], 52: [613, 1, 0], 
	53: [646, 1, 0], 54: [635, 1, 0], 55: [648, 15, 0], 56: [625, 15, 0], 57: [640, 15, 0], 58: [598, 15, 0], 
	59: [644, 1, 50], 60: [586, 1, 0], 61: [611, 1, 0], 62: [596, 1, 0], 63: [638, 1, 0], 64: [578, 1, 0], 
	65: [566, 1, 0], 66: [592, 1, 0], 67: [609, 1, 0], 68: [584, 1, 0], 69: [637, 1, 0], 70: [605, 1, 0], 
	71: [604, 1, 0], 72: [621, 1, 0], 73: [603, 1, 0], 74: [595, 1, 0], 75: [577, 1, 0], 76: [583, 1, 0], 
	77: [636, 1, 0], 78: [575, 1, 0], 79: [607, 1, 0], 80: [623, 1, 0], 81: [632, 1, 0], 82: [633, 1, 0], 
	83: [568, 1, 0], 84: [642, 1, 0], 85: [645, 1, 0], 86: [602, 1, 0], 87: [570, 1, 0], 88: [610, 1, 0], 
	89: [601, 1, 0], 90: [629, 1, 0], 91: [588, 1, 0], 92: [615, 1, 0], 93: [618, 1, 0], 94: [597, 1, 0], 
	95: [624, 1, 0], 96: [581, 1, 0], 97: [564, 1, 0], 98: [639, 1, 0], 99: [599, 1, 0], 100: [600, 1, 0], 
	101: [574, 1, 0]}

## C printf for Game.txt lines: %d, %+d, %s, %0.2f (any %.Nf), %%.
static func c_format(fmt: String, args: Array) -> String:
	var out := ""
	var i := 0
	var next := 0
	while i < fmt.length():
		var c := fmt[i]
		if c != "%" or i + 1 >= fmt.length():
			out += c
			i += 1
			continue
		var j := i + 1
		while j < fmt.length() and not fmt[j] in ["d", "s", "f", "%"]: j += 1
		if j >= fmt.length():
			out += fmt.substr(i)
			break
		var spec := fmt.substr(i + 1, j - i - 1)
		var kind := fmt[j]
		if kind == "%": out += "%"
		elif next < args.size():
			var a = args[next]
			next += 1
			if kind == "s": out += str(a)
			elif kind == "d": out += ("+" if spec.contains("+") and int(a) >= 0 else "") + str(int(a))
			else:
				var places := int(spec.get_slice(".", 1)) if spec.contains(".") else 6
				out += String.num(float(a), places).pad_decimals(places)
		i = j + 1
	return out

const POWER_TEXT := {1: 0x1b3, 5: 0x1b4, 6: 0x1bf, 7: 0x1c7, 10: 0x1d6, 0x18: 0x1c4, 0x1b: 0x1cd, 0x1c: 0x1c8, 0x20: 0x1c9,
	0x21: 0x1ce, 0x22: 0x1cb, 0x24: 0x1ca, 0x2c: 0x1cf, 0x2d: 0x1d0, 0x38: 0x1b6, 0x3c: 0x1cc, 0x50: 0x1c0, 0x51: 0x1c3,
	0x58: 0x1c1, 0x59: 0x1c2, 0x5a: 0x1ba, 0x5b: 0x1b8, 0x5c: 0x1b9, 0x5d: 0x1bb, 0x5e: 0x1bc, 0x5f: 0x1bd, 0x60: 0x1be,
	0x61: 0x1c5}

# ------------------------------------------------------------------------------------------------ the inventory
## The inventory dialog 0x55e0e0 (main.gd holds its rules): 'EMDD' 708 x 345 at (800, 350) in 1600 mode (1280: (400,
## 250), 1024: (0x9e, 0x82)). Hit areas (0x55eb50, table 0x6150f0, both edges inside): 0..6 the equipment (head, body,
## weapon, off hand, accessory right, accessory left, feet), 7..10 the backpack, 11..14 the ground, 15 / 16 the potions;
## close x 0x20e..0x22d, y 0x137..0x154 (0x55ea60 / 0x55ecc0, armed by the press, acting on the release). Read.
## The draw method 0x55fb90 (vtable +0x1c), read in part (UI gaps): each item is its IDLG cell (row iconrow, column
## iconcol + 1; rows 5, 6, 7, 9, 10 drawn 0x14 lower in a 110-high slot) with the artifact / set sparkle of the shop;
## "Backpack" [0871] / "Ground" [0870] in font 5 centred at (0x21c, 7) / (0x21c, 0xa2); the potion counts ("%d") in font
## 5 from (0x41, 0x3d) / (0x147, 0x3d). Provisional (not read yet): the slot frames from SelectionRings.bmp (the light
## frame here), the hovered item's text (name and description beside it, popup help, HelpLevel > 0).
const INVENTORY_SLOTS := [Rect2(140, 28, 70, 70), Rect2(140, 121, 70, 110), Rect2(234, 121, 70, 110), Rect2(46, 121, 70, 110),
	Rect2(271, 254, 70, 70), Rect2(9, 254, 70, 70), Rect2(140, 254, 70, 70),
	Rect2(393, 37, 70, 110), Rect2(468, 37, 70, 110), Rect2(543, 37, 70, 110), Rect2(618, 37, 70, 110),
	Rect2(393, 192, 70, 110), Rect2(468, 192, 70, 110), Rect2(543, 192, 70, 110), Rect2(618, 192, 70, 110),
	Rect2(7, 11, 70, 70), Rect2(270, 11, 70, 70)]
const INVENTORY_CLOSE := Rect2(0x20e, 0x137, 0x1e, 0x1e)
const INVENTORY_HOVER_CLOSE := 17
var inventory_close_armed := false

# ------------------------------------------------------------------------------------------------ B1-3: race powers
## B1-3 (B1_3_RESEARCH.md, Read / Emulated as noted in simulation/advancement.gd and race_powers.gd). The unit row of
## 0x4d3200 after Convert / Spellbook / Build: for a selection of one type without a hero, the Undead advancement buttons
## (race 2), the Zombie's scavenging (icon 10, PZOM) and the Dwarven Brew (icon 0x16); a mixed selection gets the Brew
## right after Convert. The tooltip is the 0x414ef0 line of the icon.
const RacePowers = preload("res://simulation/race_powers.gd")

# ------------------------------------------------------------------------------------------------ B1-6a: hero spells
## B1-6a (SPELLS_RESEARCH.md "B1-6a"): the book casts through simulation/hero_spells.gd (0x5717e0). A row is enabled when
## the spell is known (0x40c6b0) and affordable (0x570ed0: 0x529fa0 <= the pool, or the cheat). In the open book the
## digit keys 1..9, 0 cast row 0..9 of the page (0x56fd80, at most once per 150 ms) and F1..F8 put the hovered spell on
## that hot key slot (0x4258a0); outside the book F1..F8 cast the slots (spells.gd KeyHook). The placement of a Black
## Portal / Summon Guardian takes the next map click (left: place, right: cancel), the choice dialogs (Raise Champion,
## Rune Item: 0x55bc90, drawing Provisional) four icons.
var spell_key_ms := -1000                    # 0x56fd80: the digit keys wait 150 ms after the book opened (param_1[0x51])
const WEATHER_LABELS := ["Day", "Day", "Night", "Night"]   # B1-6c: Change Weather's picks 0..3 (Provisional captions)

## B1-6e (SPELLS_RESEARCH.md "B1-6e"): Transmute (61) and Morph Resources (96) open the Market's trade dialog 0x5723a0 with
## their rate and title; it closes after one trade (+0x165 = 1) and remembers the picks for the next one (0x61b78c..: give,
## get and the amount, first -1 / -1 / 200). The trade itself is simulation/market.gd's (0x5735e0 / 0x573750).
var spell_trade_memory := {"from": -1, "to": -1, "amount": 2}

# ------------------------------------------------------------------------------------------------ S-1 save / load
## S-1 (SAVE_LOAD.md). Save Game (menu row 1, 0x565bb6) and Alt+S (0x427fb0 case 0x13) save at once: 0x48fb80 redraws
## the view without the menu, 0x40d950 notes whether a save existed, 0x445c20 writes it; the message line shows [0753]
## (a save was replaced) or [0304], [0305] on failure (0x499120, Read / disassembled). The rebuild takes the picture of
## the view after the menu has closed (one drawn frame) for the load sheet.
## The load sheet 0x564c20 (Read): 'EMDL' 400 x 431 at (1025, 350) in 1600 mode, pausing the match while open (0x429590);
## title [0306] in font 1 centred at x + 0xc1, y + 0x19; the save's 242 x 173 picture at (+0x4b, +0x49); its two header
## lines (hero - map, the time) in font 2 centred at x + 0xc4, y + 0x105 / + 0x119; the Load Game button [0306] at
## (+0xc4, +0x149) in font 5 (6 under the cursor), hit x 0x84..0x104, y 0x13e..0x15f (0x5653b0); close at (+0xb6,
## +0x171). Load Game (0x565140) loads the save (0x446150).
## DELIBERATE MODERN CHANGE (F8): the rebuild keeps an autosave beside the hero's save; a line at y + 0x12d picks which
## of the two the sheet shows ("Saved game" / "Autosave", font 6 for the shown one, 7 when that file does not exist).
const LOAD_BUTTON := 0xc
const LOAD_CLOSE := 0xd
const LOAD_SAVED := 0xe
const LOAD_AUTOSAVE := 0xf
const LOAD_PICTURE := Vector2i(242, 173)
var load_choice := 0                         # 0 the hero's saved game, 1 the autosave (modern)
var load_view: Dictionary = {}               # the shown save's header: line_1, line_2, game_ms, path, error
var load_picture: Texture2D
var load_paused := false                     # the sheet paused the match (0x564c20 -> 0x429590(0)); resumed on close

