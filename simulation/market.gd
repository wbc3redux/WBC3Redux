extends RefCounted
## The Market's trade (milestone 13, PRODUCTION_RESEARCH.md "Milestone 13"; Read). The Market page button (0x4d07e0:
## BPMA of the local player; a Knights player always sees it, other races need PTRA) is enabled after Trade (PTRA) and
## opens the trade dialog 0x5723a0 (EMDX 450x431) with the rate 0x4d1090 computes: 50 + the hero's Trade skill 0x3b term,
## at most 90. The dialog picks a resource to give, one to get and an amount (0x573010 hit areas); the Trade button
## (0x572a60) runs 0x5735e0 (the amount actually sold) and 0x573750 (debit message 0x1fe, credit 0x1fd).
## Dialog lanes are gold, metal, stone, crystal (0x708fb4 / fb6 / fba / fb8); economy lanes are gold, metal, crystal, stone.
const BASE_RATE := 50
const MAX_RATE := 90
const AMOUNTS := [50, 100, 200, 300, 400, 500]       # 0x5727f0 cases 8..13
const DIALOG_TO_LANE := [0, 1, 3, 2]
const SKILL_TRADE := 0x3b

## 0x4d1090: the exchange rate in percent; `skill_term` is 0x556ea0(0x3b, rank) of the local hero (0 without the skill).
static func rate(skill_term: int = 0) -> int:
	return mini(MAX_RATE, BASE_RATE + skill_term) if skill_term != 0 else BASE_RATE

static func _s16(v: int) -> int:
	v = v & 0xffff
	return v - 0x10000 if v >= 0x8000 else v

static func _tdiv(a: int, b: int) -> int:
	var q: int = absi(a) / absi(b)
	return q if (a >= 0) == (b >= 0) else -q

## 0x5735e0: the amount given for `amount` of dialog lane `from` into `to`: at most the stock; when the proceeds
## (amount * rate / 100) would overflow the stockpile limit of `to`, (limit - stock) * 100 / rate instead.
static func sale(stock: Array, limit: Array, from: int, to: int, amount: int, percent: int) -> int:
	var have: int = int(stock[DIALOG_TO_LANE[from]])
	var sell: int = amount if amount < have else have
	var proceeds: int = _tdiv(sell * percent, 100)
	var room: int = int(limit[DIALOG_TO_LANE[to]]) - int(stock[DIALOG_TO_LANE[to]])
	if proceeds + int(stock[DIALOG_TO_LANE[to]]) <= int(limit[DIALOG_TO_LANE[to]]): return _s16(sell)
	return _s16(_tdiv(room * 100, percent))

## 0x573750 with 0x5735e0's amount: refused when the stock is short; otherwise the given lane is debited and
## amount * rate / 100 credited (the economy clamps credits to the stockpile limit). Returns the [given, received] pair.
static func trade(economy, player: int, from: int, to: int, amount: int, percent: int) -> Array:
	var stock: Array = economy.resources(player)
	var sell := sale(stock, economy.capacity(player), from, to, amount, percent)
	if sell <= 0 or int(stock[DIALOG_TO_LANE[from]]) < sell: return [0, 0]
	var debit := [0, 0, 0, 0]
	debit[DIALOG_TO_LANE[from]] = sell
	if not economy.try_spend(player, debit): return [0, 0]
	var credit := [0, 0, 0, 0]
	var received: int = _s16(_tdiv(sell * percent, 100))
	credit[DIALOG_TO_LANE[to]] = received
	economy.credit(player, credit)
	return [sell, received]
