extends "res://scripts/roguelite_game.gd"
## Arcade rules over the shared arena/ability engine. No profile writes or drafts.
const ROUND_SECONDS := 90.0
const MAP_GOALS := [50, 55, 55, 60, 60, 65, 70, 75]
const PICKUP_NAMES := {"charge": "CHARGE", "hardening": "HARDEN", "leap": "LEAP", "lance": "LANCE", "dash": "DASH", "health": "+1 LIFE"}
var remaining := ROUND_SECONDS
var elapsed := 0.0
var pickups: Array[Dictionary] = []
var equipped := ""
var round_result := {}
var tally_settled := false
var health_spent := false
var arcade_score := 0

func map_goal() -> int:
	return MAP_GOALS[clampi(level - 1, 0, MAP_GOALS.size() - 1)]

func capture_target() -> float:
	return 2.0 # No capture, even 100%, ends the countdown early.

func objective_complete() -> bool:
	return false

func level_clear() -> void:
	pass # Only the final tally advances Arcade.

func secondary_ability() -> String:
	return "" # E cycles the captured abilities; Q activates the selected one.

func setup(p_lines: ScopeLines, p_sparks: Sparks, p_fill: Sprite2D) -> void:
	super.setup(p_lines, p_sparks, p_fill)
	progress = Progress.new() # Arcade never inherits permanent upgrades or unlocks.
	cooldowns["lance"] = 0.0

func go_dock() -> void:
	phase = "arcade_menu"
	state = State.DOCK
	selection = 0
	ui_time = 0.0
	fill.visible = false
	lines.zoom = Vector2.ONE

func open_chart() -> void:
	pass # Arcade advances through arenas in order.

func start_run(_retry_sector := 0) -> void:
	super.start_run()
	lives = 0 # Game counts spare hulls; zero means one remaining life.
	opening_draft_pending = false
	equipped = ""
	elapsed = 0.0
	arcade_score = 0
	health_spent = false
	begin_transit(false)

func start_level() -> void:
	super.start_level()
	draft_capture.clear()
	opening_draft_pending = false
	corruption_active = false
	corruption.fill(0)
	remaining = ROUND_SECONDS
	round_result.clear()
	tally_settled = false
	equipped = ""
	owned_cards.clear()
	card_ranks.clear()
	for key in cooldowns: cooldowns[key] = 0.0
	reset_movement_module()
	boost_time = 0.0
	hardlight_time = 0.0
	freeze_time = 0.0
	containment_time = 0.0
	safe_motion = 0.0
	hot_entry = false
	spawn_pickups()

func seed_corruption() -> void:
	pass

func update_surge_clock(_dt: float) -> void:
	pass

func award_flux(_amount: float) -> void:
	pass

func spawn_pickups() -> void:
	pickups.clear()
	nodes.clear() # All floating rewards in Arcade are usable pickups.
	var candidates: Array = field_arena.free_cells.duplicate()
	var placement := RandomNumberGenerator.new()
	placement.seed = hash("arcade-pickups:%d" % level)
	for i in range(candidates.size() - 1, 0, -1):
		var j := placement.randi_range(0, i)
		var swap = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = swap
	for id in PICKUP_NAMES:
		for c: Vector2i in candidates:
			if cells[idx(c.x, c.y)] != FREE: continue
			var clear := true
			for pickup in pickups:
				if Vector2(c - pickup.cell).length() < 8.0: clear = false
			for turret in turrets:
				if Vector2(c - turret.cell).length() < 4.0: clear = false
			if not clear: continue
			pickups.append({"id": id, "cell": c, "taken": id == "health" and health_spent})
			break

func collect_pickups() -> void:
	if state != State.PLAYING or phase != "run": return
	for pickup in pickups:
		if pickup.taken or cells[idx(pickup.cell.x, pickup.cell.y)] != CLAIMED: continue
		var id: String = pickup.id
		if id == "health":
			if lives >= 2: continue
			lives += 1
			health_spent = true
		else:
			if not owned_cards.has(id): owned_cards.append(id)
			if equipped.is_empty(): equipped = id
			cooldowns[id] = 0.0
		pickup.taken = true
		set_msg(PICKUP_NAMES[id], 1.2)
		sparks.ripple(center(pickup.cell), 4.0, 220.0, 0.5, Palette.GREEN)

func on_claim(_gained: int, _caught: int) -> void:
	update_brood_eggs(0.0)
	field_features.on_claim(self)
	for i in cells.size():
		if cells[i] == CLAIMED and credited[i] == 0:
			credited[i] = 1
			first_claims += 1
	capture_percent = live_percent()
	capture_count += 1
	set_msg("TERRITORY CAPTURED", 0.8)
	collect_pickups()

func live_claims() -> int:
	var count := 0
	for i in cells.size():
		if field_arena.mask[i] == 2 and cells[i] == CLAIMED: count += 1
	return count

func live_percent() -> float:
	return live_claims() * 100.0 / maxi(1, base_free)

func cycle_ability() -> void:
	if owned_cards.size() < 2 or sap_live or tether_active or leap_building or wall_building or hardening_time > 0.0 or dash_time > 0.0: return
	equipped = owned_cards[(owned_cards.find(equipped) + 1) % owned_cards.size()]

func try_step(dir: Vector2i, draw_line: bool, slow: bool) -> bool:
	var moved := super.try_step(dir, draw_line, slow)
	collect_pickups()
	return moved

func ride_step() -> void:
	super.ride_step()
	collect_pickups()

func movement_module() -> String:
	return equipped

func activate_ability(id: String) -> void:
	if id != equipped: return
	if id != "lance":
		super.activate_ability(id)
		return
	if phase != "run" or state != State.PLAYING or equipped != id or cooldowns.lance > 0.0: return
	if drawing or sap_live or leap_building or wall_building or cells[idx(p.x, p.y)] != CLAIMED: return
	fire_lance()
	if tether_active: cooldowns.lance = 8.0

func update(dt: float) -> void:
	if phase == "arcade_tally":
		ui_time += dt
		if ui_time >= tally_duration() and not tally_settled: settle_tally()
		update_choices()
		return
	if phase == "run" and state == State.PLAYING and remaining <= 0.0:
		finish_round()
		return
	super.update(dt)

func update_play(dt: float) -> void:
	if remaining <= 0.0:
		finish_round()
		return
	dt = minf(dt, remaining)
	remaining = maxf(0.0, remaining - dt)
	elapsed += dt
	if Input.is_action_just_pressed("special"): cycle_ability()
	super.update_play(dt)
	collect_pickups()
	if phase == "run" and state == State.PLAYING and remaining <= 0.0: finish_round()

func finish_round() -> void:
	if phase != "run" or remaining > 0.0 or not round_result.is_empty(): return
	var count := live_claims()
	var percent := count * 100.0 / maxi(1, base_free)
	round_result = {"cells": count, "percent": percent, "target": map_goal(), "passed": count * 100 >= map_goal() * base_free, "bonus": maxi(0, floori(percent - map_goal() + 0.000001))}
	phase = "arcade_tally"
	state = State.PLAYING
	ui_time = 0.0
	selection = 0
	msg_t = 0.0
	capture_flights.clear()
	shake_off = Vector2.ZERO

func tally_duration() -> float:
	return 3.2 if absf(float(round_result.get("percent", 0.0)) - map_goal()) <= 12.0 else 1.8

func tally_percent() -> float:
	var t := clampf((ui_time - 0.35) / (tally_duration() - 0.35), 0.0, 1.0)
	var close := tally_duration() > 2.0
	return float(round_result.percent) * (1.0 - pow(1.0 - t, 3.0) if close else t)

func settle_tally() -> void:
	if phase != "arcade_tally" or tally_settled: return
	tally_settled = true
	if round_result.passed:
		arcade_score += int(round_result.bonus)
		run_sectors = level
		run_victory = level >= sector_limit
		reward_audio.stream = victory_cue
	else:
		lives -= 1
		reward_audio.stream = install_cue
	reward_audio.play()

func accept_tally() -> void:
	if not tally_settled or phase != "arcade_tally" or ui_time < choice_delay(): return
	if run_victory or lives < 0:
		end_run()
		return
	if round_result.passed:
		level += 1
		health_spent = false
	phase = "run"
	pending_clear = false
	begin_transit(false)

func end_run() -> void:
	if settled: return
	settled = true
	last_result = "ALL SECTORS CLEAR" if run_victory else ("GAME OVER" if lives < 0 else "RUN ENDED")
	phase = "result"
	state = State.RUN_OVER
	selection = 0
	ui_time = 0.0
	msg_t = 0.0
	capture_flights.clear()
	lines.zoom = Vector2.ONE

func choice_delay() -> float:
	if phase == "arcade_tally": return tally_duration() + 0.5
	return 1.0 if phase == "result" else 0.2

func choice_count() -> int:
	return 2 if phase in ["arcade_menu", "paused", "result"] else 1

func update_choices() -> void:
	if ui_time < choice_delay(): return
	if Input.is_action_just_pressed("move_up") or Input.is_action_just_pressed("move_left"):
		selection = posmod(selection - 1, choice_count())
	if Input.is_action_just_pressed("move_down") or Input.is_action_just_pressed("move_right"):
		selection = (selection + 1) % choice_count()
	if Input.is_action_just_pressed("confirm"): activate_choice(selection)
	elif Input.is_action_just_pressed("abort"):
		if phase == "paused": resume_run()
		elif phase == "arcade_menu": leave_mode()
		elif phase == "result": go_dock()

func activate_choice(index: int) -> void:
	if ui_time < choice_delay(): return
	match phase:
		"arcade_menu":
			if index == 0: start_run()
			else: leave_mode()
		"briefing": begin_sector()
		"paused":
			if index == 0: resume_run()
			else: end_run()
		"arcade_tally": accept_tally()
		"result":
			if index == 0: start_run()
			else: go_dock()

func choice_rect(index: int) -> Rect2:
	if phase == "arcade_tally": return Rect2(580, 610, 440, 64)
	if phase == "briefing": return super.choice_rect(index)
	return Rect2(550, 470 + index * 88, 500, 64)

func _input(event: InputEvent) -> void:
	var host := get_parent() as Game
	if host == null or host.state != State.ARCADE or phase in ["run", "reward"] or ui_time < choice_delay(): return
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		for i in choice_count():
			if choice_rect(i).has_point(event.position):
				selection = i
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT: activate_choice(i)
				get_viewport().set_input_as_handled()
				return

func draw() -> void:
	if phase == "arcade_tally":
		draw_arena()
		lines.modal_start = lines.count
		lines.offset = Vector2.ZERO
		lines.zoom = Vector2.ONE
		draw_tally()
		return
	if phase not in ["arcade_menu", "result"]:
		super.draw()
		return
	fill.visible = false
	lines.zoom = Vector2.ONE
	label("ARCADE", Vector2(800, 210), 42, Palette.CYAN, 1)
	if phase == "arcade_menu":
		label("ONE LIFE. 90 SECONDS. BEAT THE TARGET.", Vector2(800, 310), 18, Palette.WHITE, 1)
		label("CAPTURE PICKUPS FOR ABILITIES AND EXTRA LIVES", Vector2(800, 355), 13, Palette.GREEN, 1)
		button(0, "START")
		button(1, "BACK")
	else:
		label(last_result, Vector2(800, 310), 26, Palette.GREEN if run_victory else Palette.YELLOW, 1)
		label("%d / %d MAPS  /  SCORE %d" % [run_sectors, sector_limit, arcade_score], Vector2(800, 370), 15, Palette.DIM, 1)
		if ui_time >= choice_delay():
			button(0, "RETRY")
			button(1, "MENU")

func draw_tally() -> void:
	lines.rect(Rect2(380, 220, 840, 490), Palette.CYAN)
	label("MAP %02d" % level, Vector2(800, 270), 20, Palette.DIM, 1)
	label("TARGET %d%%" % round_result.target, Vector2(800, 322), 20, Palette.YELLOW, 1)
	# Never round a narrow miss up to the displayed target.
	label("%.1f%%" % (floorf(tally_percent() * 10.0 + 0.000001) / 10.0), Vector2(800, 395), 52, Palette.WHITE, 1)
	if not tally_settled:
		label("COUNTING...", Vector2(800, 510), 18, Palette.DIM, 1)
	else:
		label("CLEAR" if round_result.passed else "SHORT OF TARGET", Vector2(800, 500), 24, Palette.GREEN if round_result.passed else Palette.YELLOW, 1)
		label("+%d SCORE" % round_result.bonus if round_result.passed else "-1 LIFE", Vector2(800, 552), 16, Palette.DIM, 1)
		if ui_time >= choice_delay():
			button(0, "RESULTS" if run_victory or lives < 0 else ("NEXT MAP" if round_result.passed else "RETRY MAP"))

func draw_briefing() -> void:
	lines.rect(BRIEFING_PANEL, Palette.CYAN)
	label("TARGET %d%% / 90 SECONDS" % map_goal(), Vector2(800, 363), 24, Palette.WHITE, 1)
	button(0, "START")

func draw_intro() -> void:
	var paths: Array = []
	for i in range(0, coast.size(), 2): paths.append(PackedVector2Array([coast[i], coast[i + 1]]))
	lines.trace(paths, clampf((seq_t - 0.2) / 0.6, 0.0, 1.0), coast_color(), 0.7, 0.15, 1.0)
	if seq_t < 2.3: label("MAP %02d" % level, Vector2(800, 410), 36, Palette.CYAN, 1)
	if seq_t >= INTRO_QIX_T:
		for q in qixes: draw_qix(q)
	draw_play()

func draw_pause() -> void:
	label("PAUSED", Vector2(800, 240), 34, Palette.CYAN, 1)
	label("TARGET %d%% AT THE BUZZER" % map_goal(), Vector2(800, 285), 17, Palette.YELLOW, 1)
	label(Controls.hint("SPACE: DRAW  /  ") + Controls.action_label("br_harden", "Q") + ": PICKUP ABILITY", Vector2(800, 330), 17, Palette.WHITE, 1)
	button(0, "RESUME")
	button(1, "END RUN")

func draw_hud() -> void:
	hud_label("ARCADE / %02d-%02d" % [level, sector_limit], Vector2(FIELD_X, 61), 18)
	draw_hull_icons(Vector2(1254, 70), maxi(0, lives + 1))
	hud_label("%02d:%02d" % [ceili(remaining) / 60, ceili(remaining) % 60], Vector2(1370, 62), 16, Palette.YELLOW if remaining <= 10 else Palette.WHITE)
	hud_label("TARGET %d%%" % map_goal(), Vector2(FIELD_X, 104), 13, Palette.DIM)
	hud_label(Controls.hint("SPACE: DRAW  /  ESC: PAUSE"), Vector2(FIELD_X, 794), 12, Palette.DIM)
	var ability: String = "FIND AN ABILITY" if equipped.is_empty() else Controls.action_label("br_harden", "Q") + ": " + PICKUP_NAMES[equipped]
	if not equipped.is_empty() and cooldowns[equipped] > 0.0: ability += "  %.1fS" % cooldowns[equipped]
	label(ability, Vector2(1100, 800), 16, Palette.CYAN, 1)
	if owned_cards.size() > 1:
		label(Controls.action_label("special", "E") + ": NEXT ABILITY", Vector2(1100, 831), 12, Palette.DIM, 1)

func draw_play() -> void:
	super.draw_play()
	for pickup in pickups:
		if pickup.taken: continue
		var pos := center(pickup.cell)
		var color := Palette.GREEN if pickup.id == "health" else Palette.CYAN
		lines.circle(pos, 11, color, 6)
		if pickup.id == "health":
			lines.seg(pos - Vector2(5, 0), pos + Vector2(5, 0), color)
			lines.seg(pos - Vector2(0, 5), pos + Vector2(0, 5), color)
		else:
			label(PICKUP_NAMES[pickup.id].substr(0, 1), pos - Vector2(0, 4), 9, color, 1)
		label(PICKUP_NAMES[pickup.id], pos + Vector2(0, 17), 9, color, 1)
