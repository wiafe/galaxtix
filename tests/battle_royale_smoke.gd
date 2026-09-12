extends Node

func _ready() -> void:
	call_deferred("check")

func fixture() -> BattleRoyale:
	var b := BattleRoyale.new()
	b.start(123)
	b.owners.fill(-1)
	b.rails.fill(-1)
	b.trails.fill(-1)
	b.racers.resize(2)
	for i in 2:
		var r := b.racers[i]
		r.id = i
		r.rail.clear()
		for x in range(10, 17):
			var c := Vector2i(x, 0 if i == 0 else b.size.y - 1)
			r.rail.append(c)
			b.owners[b.index(c)] = i
			b.rails[b.index(c)] = i
		r.pos = r.rail[2]
		r.anchor = r.pos
	b.rebuild()
	return b

func check() -> void:
	var b := fixture()
	var p := b.racer(0)
	for d in [Vector2i.DOWN, Vector2i.DOWN, Vector2i.DOWN, Vector2i.RIGHT, Vector2i.RIGHT, Vector2i.UP, Vector2i.UP, Vector2i.UP]:
		assert(b.step(p, d))
	assert(not p.exposed and b.owner(Vector2i(13, 2)) == 0, "Closed excursion captures its interior")
	assert(p.score == 9)
	assert(b.step(p, Vector2i.RIGHT))
	var anchor := p.pos
	assert(b.step(p, Vector2i.DOWN))
	b.fail(p)
	assert(p.pos == anchor and not p.exposed and p.trail.is_empty())
	for c in p.rail: assert(b.owner(c) == 0)
	# Invalid anchors fall back to the nearest safe point, not the original spawn.
	p.anchor = Vector2i(14, 4)
	p.pos = Vector2i(20, 8)
	p.exposed = true
	b.fail(p)
	assert(p.pos == Vector2i(14, 3))
	b.ability(p, true)
	assert(not p.has_harden and p.harden == 4.0)
	assert(not b.step(p, Vector2i.DOWN), "Harden owner cannot leave")
	var other := b.racer(1)
	other.pos = Vector2i(14, 4)
	other.anchor = other.rail[0]
	other.exposed = true
	assert(not b.step(other, Vector2i.UP))
	assert(other.exposed and other.anchor == other.rail[0], "Harden wall does not reset excursions")
	b.ability(p, false)
	assert(not p.has_drive and p.drive == 4.0)
	# Harden appearing around an intruder pushes them out without failing their excursion.
	p.harden = 0.0
	p.has_harden = true
	other.pos = Vector2i(13, 2)
	other.trail.append(other.pos)
	b.trails[b.index(other.pos)] = other.id
	var old_anchor := other.anchor
	b.ability(p, true)
	assert(b.owner(other.pos) != p.id and other.exposed and other.anchor == old_anchor)
	assert(other.trail.is_empty())
	# Cutting the rail connection steals the cut itself, not the disconnected island.
	var islands := fixture()
	var defender := islands.racer(0)
	var attacker := islands.racer(1)
	for x in range(17, 32): islands.owners[islands.index(Vector2i(x, 0))] = 0
	for y in range(1, 10): islands.owners[islands.index(Vector2i(31, y))] = 0
	for y in range(10, 13):
		for x in range(30, 33): islands.owners[islands.index(Vector2i(x, y))] = 0
	islands.owners[islands.index(Vector2i(29, 8))] = 1
	islands.owners[islands.index(Vector2i(29, 9))] = 1
	attacker.pos = Vector2i(29, 8)
	defender.pos = Vector2i(31, 11)
	islands.rebuild()
	var score_before := defender.score
	for d in [Vector2i.RIGHT, Vector2i.RIGHT, Vector2i.RIGHT, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.LEFT, Vector2i.LEFT, Vector2i.LEFT]:
		assert(islands.step(attacker, d))
	assert(islands.owner(Vector2i(31, 8)) == 1)
	assert(islands.owner(Vector2i(31, 11)) == 0 and defender.pos == Vector2i(31, 11))
	assert(defender.score == score_before - 2, "Only directly captured cells are lost")
	assert(islands.safe_path(defender, defender.rail[0]).is_empty())
	# Reconnect into an island from outside; it remains a valid capture endpoint.
	defender.pos = Vector2i(30, 10)
	assert(islands.step(defender, Vector2i.LEFT))
	assert(islands.step(defender, Vector2i.DOWN))
	assert(islands.step(defender, Vector2i.RIGHT))
	assert(not defender.exposed and islands.owner(Vector2i(29, 10)) == 0)
	# A failed excursion can recover on the nearby island, even if its anchor was stolen.
	defender.anchor = Vector2i(30, 10)
	islands.owners[islands.index(defender.anchor)] = 1
	islands.rebuild()
	defender.exposed = true
	islands.fail(defender)
	assert(islands.owner(defender.pos) == 0 and defender.pos.y >= 10)
	for c in defender.rail: assert(islands.owner(c) == 0)
	# Real qualification path, elimination/replay, and the Final winner.
	b = BattleRoyale.new()
	b.start(42)
	for round_index in 3:
		b.racer(0).biggest = 999
		b.racer(0).has_drive = false
		b.finish_round()
		assert(b.qualified() and b.standings[0].id == 0)
		if round_index < 2:
			b.advance()
			assert(b.round_index == round_index + 1)
			assert(b.racer(0).score == 0 and not b.racer(0).has_drive)
	b.advance()
	assert(b.round_index == 0 and b.racers.size() == BattleRoyale.FIELD and b.racer(0).has_drive)
	b.racer(0).failures = 99
	b.finish_round()
	assert(not b.qualified())
	b.advance()
	assert(b.round_index == 0 and b.racers.size() == BattleRoyale.FIELD)
	# Whole matches: AI really moves/captures, qualifiers and charges survive fresh boards.
	for seed_value in [7, 22, 94]:
		b = BattleRoyale.new()
		b.start(seed_value)
		for round_index in 3:
			b.phase = "playing"
			var elapsed := Time.get_ticks_usec()
			for frame in int(BattleRoyale.TIMES[round_index] * 30) + 1:
				b.update(1.0 / 30.0, false)
			assert(b.phase == "results")
			assert(b.standings[0].score > 0, "Bots must earn real territory")
			for r in b.racers:
				for c in r.rail: assert(b.owner(c) == r.id)
				assert(b.inside(r.pos))
			print("seed %d round %d: leader %d cells, simulation %.2f ms/frame" % [seed_value, round_index + 1, b.standings[0].score, (Time.get_ticks_usec() - elapsed) / 1000.0 / (BattleRoyale.TIMES[round_index] * 30)])
			if round_index < 2:
				var survivors: Array[BattleRoyale.Racer] = []
				survivors.assign(b.standings.slice(0, BattleRoyale.CUTS[round_index]))
				var survivor := survivors[0]
				survivor.has_drive = false
				b.racers = survivors
				b.round_index += 1
				b.begin_round()
				assert(not survivor.has_drive and survivor.score == 0)
				assert(b.racers.size() == [6, 4][round_index])
	var main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	main.set_process(false)
	var game: Game = main.game
	var save = get_tree().root.get_node("Save")
	assert(not save.enabled)
	var saved: String = JSON.stringify(save.data)
	game.go_title()
	game.title_t = 3.0
	var royale_row := game.TITLE_ITEMS.find("BATTLE ROYALE")
	assert(royale_row >= 0)
	var click := InputEventMouseButton.new()
	click.position = game.title_item_rect(royale_row).get_center()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	game._input(click)
	game.update_title(0.6)
	assert(game.state == Game.State.BATTLE_ROYALE and game.battle.racers.size() == BattleRoyale.FIELD)
	game.battle.phase = "playing"
	var human := game.battle.racer(0)
	var start := human.pos
	var moved := false
	Input.action_press("draw")
	for action in ["move_up", "move_right", "move_down", "move_left"]:
		Input.action_press(action)
		game.battle.update(0.1)
		Input.action_release(action)
		if human.pos != start:
			moved = true
			break
	Input.action_release("draw")
	assert(moved, "Human movement reaches the shared simulation")
	main.display.begin_draw(Vector2.ZERO)
	game.draw()
	main.display.end_draw()
	assert(game.battle_fill.visible)
	game.go_title()
	main.display.begin_draw(Vector2.ZERO)
	game.draw()
	main.display.end_draw()
	assert(not game.battle_fill.visible and JSON.stringify(save.data) == saved)
	print("PASS: capture, anchor recovery, surviving islands, Harden, persistent abilities and nine simulated rounds")
	get_tree().quit()
