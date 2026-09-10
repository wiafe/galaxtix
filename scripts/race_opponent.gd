extends "res://scripts/roguelite_game.gd"
## An isolated copy of the real arena simulation, driven by a cutter planner.
## No keyboard/controller events, profile writes, drafts or rewards reach this pilot.
var brain = RivalCutter.new()
var think_delay := 0.0

func _exit_tree() -> void:
	# These sprites live in the display viewport, outside the simulation node.
	if is_instance_valid(fill): fill.queue_free()
	if is_instance_valid(battle_fill): battle_fill.queue_free()

func setup_race() -> void:
	pass # The opponent never creates another opponent.

func uses_race_palette() -> bool:
	return true

func accepts_player_input() -> bool:
	return false

func _input(_event: InputEvent) -> void:
	pass

func award_flux(_amount: float) -> void:
	pass

func level_clear() -> void:
	pass # The owning race decides when both simulations stop.

func end_run() -> void:
	pass

func take_starting_board(source: Game) -> void:
	progress = Progress.new()
	ship = Ships.get_ship("surveyor")
	gal = source.gal.duplicate(true)
	level = source.level
	active_destination = source.active_destination.duplicate(true)
	set_field_x(source.FX)
	start_level()
	# Clone runtime bodies as well as arrays: worm links and mite homes must refer to
	# their cloned bodies, never the player's. Map resources remain read-only inputs.
	var copies := {}
	for key in ["field_arena", "field_shape", "cells", "base_free", "free_count", "p", "anchor", "vis", "credited", "qixes", "authored_behaviors", "brood_eggs", "sparxes", "sparx_to_spawn", "sparx_spawn_t", "nodes", "node_spawn_t", "turrets", "bolts", "spawners", "mites", "islands", "seals", "boss_bond", "field_features"]:
		set(key, clone_value(source.get(key), copies))
	grid_changed()
	draft_capture.clear()
	opening_draft_pending = false
	phase = "run"
	state = State.PLAYING
	lives = 1000000 # Hits cost respawn time; only the human spends expedition hulls.
	rng.seed = hash("race:%d:%d" % [level, arena_stage(level)])
	brain.setup(Vector2i(grid_width, grid_height), rng, {
		"owner_of": owner_at, "is_solid": solid_at,
		"player_trail_at": func(_c): return false,
		"on_capture": func(_loop): pass,
		"on_cross_player_trail": func(_c): pass,
		"on_fail": func(): pass,
	})
	brain.aggression = clampf((level - 3) / 4.0, 0.0, 1.0)
	brain.loop_scale = 2.0
	brain.travel_cost = 1.5

func clone_value(value: Variant, copies: Dictionary) -> Variant:
	if value is Array:
		var result: Array = value.duplicate()
		for i in result.size(): result[i] = clone_value(value[i], copies)
		return result
	if value is Dictionary:
		var result := {}
		for key in value: result[clone_value(key, copies)] = clone_value(value[key], copies)
		return result
	if value is RefCounted and not value is Resource:
		if copies.has(value): return copies[value]
		var result: RefCounted = value.get_script().new()
		copies[value] = result
		for property in value.get_property_list():
			if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				result.set(property.name, clone_value(value.get(property.name), copies))
		return result
	if typeof(value) in [TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY]:
		return value.duplicate()
	return value

func owner_at(cell: Vector2i) -> int:
	if not in_bounds(cell): return -1
	var value := cells[idx(cell.x, cell.y)]
	return 1 if value == CLAIMED else (0 if value == FREE else -1)

func solid_at(cell: Vector2i) -> bool:
	return not in_bounds(cell) or cells[idx(cell.x, cell.y)] not in [FREE, CLAIMED]

func plan_direction() -> Vector2i:
	if brain.plan.is_empty() and think_delay <= 0.0:
		brain.pos = p
		brain.exposed = drawing
		brain.trail_mask.fill(0)
		brain.owned.clear()
		for i in cells.size():
			if cells[i] == CLAIMED and border[i] != 0: brain.owned.append(Vector2i(i % grid_width, i / grid_width))
			elif cells[i] == TRAIL: brain.trail_mask[i] = 1
		if drawing: brain.plan_route()
		else:
			plan_crosscut()
			if brain.plan.is_empty(): brain.plan_route()
		think_delay = 0.25
	if brain.plan.is_empty(): return Vector2i.ZERO
	var direction: Vector2i = brain.plan[0] - p
	if absi(direction.x) + absi(direction.y) != 1:
		brain.plan.clear()
		return Vector2i.ZERO
	return direction

func plan_crosscut() -> void:
	# Prefer useful coast-to-coast cuts over spending most of the race walking rails.
	# These are plans only: movement, enemy hits and the capture flood remain in Game.
	var parent: PackedInt32Array = brain.bfs_owned()
	var best := -1.0
	for attempt in mini(180, brain.owned.size()):
		var start: Vector2i = p if attempt == 0 else brain.owned[rng.randi_range(0, brain.owned.size() - 1)]
		if parent[idx(start.x, start.y)] < 0: continue
		for direction: Vector2i in RivalCutter.DIRS:
			var cell := start + direction
			var cut: Array[Vector2i] = []
			while owner_at(cell) == 0:
				cut.append(cell)
				cell += direction
			if cut.size() < 4 or cut.size() > 24 or owner_at(cell) != 1: continue
			cut.append(cell)
			var approach: Array[Vector2i] = brain.walk_back(parent, start)
			var value := float(cut.size() * cut.size()) / (cut.size() + 2.0 * approach.size()) * rng.randf_range(0.85, 1.15)
			if value > best:
				best = value
				brain.plan = approach
				brain.plan.append_array(cut)

func read_input() -> Dictionary:
	if not drawing: draw_armed = true
	return {"dir": plan_direction(), "draw": true, "slow": false, "abort": false, "special": false}

func try_step(_direction: Vector2i, _draw: bool, _slow: bool) -> bool:
	var direction := plan_direction()
	if direction == Vector2i.ZERO: return false
	var next := p + direction
	var moved := super.try_step(direction, true, false)
	if moved and p == next and not brain.plan.is_empty(): brain.plan.pop_front()
	elif not moved: brain.plan.clear()
	return moved

func movement_mult() -> float:
	return lerpf(0.85, 1.2, clampf((level - 3) / 4.0, 0.0, 1.0))

func on_claim(_gained: int, _caught: int) -> void:
	field_features.on_claim(self)
	capture_percent = (1.0 - float(free_count) / maxi(1, base_free)) * 100.0
	capture_count += 1
	brain.plan.clear()

func simulate(dt: float) -> void:
	time += dt
	frame += 1
	invuln -= dt
	think_delay = maxf(0.0, think_delay - dt)
	sparks.update(dt)
	if state == State.DYING:
		state_t += dt
		for q in qixes: update_qix(q, dt, qix_speed())
		if state_t > 1.3:
			p = respawn_cell
			vis = center(p)
			invuln = respawn_shield_duration()
			state = State.PLAYING
			brain.plan.clear()
		return
	super.update_play(dt)
