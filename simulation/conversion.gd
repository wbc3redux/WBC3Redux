extends RefCounted
## Unit area-conversion lifecycle (0x51cbb0, 0x51e670, 0x520c90).
## Target selection is injected: original footprint/eligibility/order, NOT point distance.
const Entity = preload("res://simulation/entity_state.gd")
signal conversion_started(entity_id: int, finish_ms: int)
signal conversion_finished(entity_id: int)
signal conversion_cancelled(entity_id: int)
signal targets_converted(entity_id: int, owner: int, targets: Array)   # before conversion_finished (milestone 12)
var active: Dictionary = {}
## Milestone 12: the match's ownership transfer (0x532640 -> 0x4a6be0 -> 0x4a6cc0), called with the completion scan's
## targets and the new owner. Without it the targets' owner is set directly (the milestone 6 kernel behaviour).
var transfer: Callable

## role and effective values are resolved match inputs. No guessed hero stats.
## select_targets(owner, cell, radius) returns original-eligible Entity states in
## original scan order, at most eight. Re-evaluated at completion, as in the EXE.
func begin(actor: Entity, role: String, duration_seconds: int, radius: int,
		now_ms: int, select_targets: Callable) -> bool:
	if role not in ["hero", "general", "phoenix"]: return false
	if active.has(actor.entity_id) or duration_seconds < 1 or radius < 0: return false
	if not select_targets.is_valid(): return false
	var targets: Array = select_targets.call(actor.owner, actor.cell(), radius)
	if targets.is_empty(): return false
	# "targets": the buildings found at the start, which 0x51cbb0 marks (+0x14a) for the local player (presentation).
	active[actor.entity_id] = {"actor": actor, "owner": actor.owner, "radius": radius,
		"finish": now_ms + duration_seconds * 1000, "select": select_targets, "targets": targets.map(func(t): return t.entity_id)}
	conversion_started.emit(actor.entity_id, now_ms + duration_seconds * 1000)
	return true

func cancel(entity_id: int):
	if active.erase(entity_id): conversion_cancelled.emit(entity_id)

func update(now_ms: int):
	for id in active.keys():
		if not active.has(id): continue
		var job: Dictionary = active[id]
		var actor: Entity = job.actor
		if actor.owner != job.owner:
			cancel(id)
			continue
		# 0x51e670 checks finish < now, not <=.
		if now_ms <= job.finish: continue
		active.erase(id)
		var targets: Array = job.select.call(actor.owner, actor.cell(), job.radius).slice(0, 8)
		if transfer.is_valid(): transfer.call(targets, actor.owner)
		else:
			for target in targets: target.owner = actor.owner
		targets_converted.emit(id, actor.owner, targets)
		conversion_finished.emit(id)

# ------------------------------------------------------------------------------------------------ S-1 save / load
## SAVE_LOAD.md: a running job's actor is a shared entity (SaveGame.Refs); its target scan is the owner's select
## (MatchConversion.select), given back on load.
func save_state(refs) -> Dictionary:
	var jobs := {}
	for id in active:
		var job := {}
		for k in active[id]:
			if k == "select": continue
			job[k] = refs.ref(active[id][k]) if k == "actor" else preload("res://simulation/save_game.gd").copy(active[id][k])
		jobs[id] = job
	return {"active": jobs}

func load_state(state: Dictionary, refs, select_targets: Callable):
	active.clear()
	for id in state.active:
		var job := {}
		for k in state.active[id]:
			job[k] = refs.get_obj(int(state.active[id][k])) if k == "actor" else preload("res://simulation/save_game.gd").copy(state.active[id][k])
		job["select"] = select_targets
		active[id] = job
