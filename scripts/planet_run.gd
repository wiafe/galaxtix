extends RefCounted
const Grid = preload("res://scripts/planet_grid.gd")
const SECTORS := ["LANDFALL", "BASALT COAST", "SUNKEN CITIES", "FAULT LINES", "NIGHT GARDEN", "POLAR REACH", "CROWN APPROACH", "HOMEWORLD"]
var grid := Grid.new()
var rng := RandomNumberGenerator.new()
var sector := 1
var hull := 3
var player := 0
var home := 0
var drawing := false
var draw_armed := false
var trail := PackedInt32Array()
var enemies: Array[Dictionary] = []
var salvage_cells := PackedInt32Array()
var salvage := 0
var initial_area := 0.0
var reclaimed_area := 0.0
var phase := "chart"
var notice := ""
var notice_time := 0.0
var invulnerable := 0.0
var dash_time := 0.0
var dash_cooldown := 0.0
var dash_recharge := 4.0
var speed := 7.0
var enemy_acc := 0.0
var cut_time := 0.0
var revision := 0

func start() -> void:
	grid.build()
	sector = 1
	hull = 3
	salvage = 0
	speed = 7.0
	dash_recharge = 4.0
	start_sector()

func start_sector() -> void:
	rng.seed = 4012026 + sector * 811
	grid.cells.fill(Grid.FREE)
	trail.clear()
	enemies.clear()
	salvage_cells.clear()
	drawing = false
	draw_armed = false
	cut_time = 0
	invulnerable = 1.2
	dash_time = 0
	dash_cooldown = 0
	enemy_acc = 0
	reclaimed_area = 0
	var landing := Vector3(0.18 * sin(sector), 0.12 * cos(sector), 1).normalized()
	var best := INF
	for i in grid.cells.size():
		var dot := grid.directions[i].dot(landing)
		if dot > 0.90:
			grid.cells[i] = Grid.CLAIMED
			if dot < best:
				best = dot
				player = i
	home = player
	# Small raised rock groups change local routes without artificial map edges.
	for crater in range(2 + sector):
		var seed_cell := rng.randi_range(0, grid.cells.size() - 1)
		if grid.directions[seed_cell].dot(landing) > 0.65: continue
		grid.cells[seed_cell] = Grid.ROCK
		for neighbour in grid.neighbours[seed_cell]:
			if grid.cells[neighbour] == Grid.FREE: grid.cells[neighbour] = Grid.ROCK
	initial_area = 0
	for i in grid.cells.size():
		if grid.cells[i] == Grid.FREE: initial_area += grid.weights[i]
	for i in range(3 + sector / 2):
		var cell := free_cell()
		if i < 2:
			for attempt in 500:
				var candidate := free_cell()
				var near := grid.directions[candidate].dot(landing)
				if near > 0.45 and near < 0.78:
					cell = candidate
					break
		enemies.append({"cell": cell, "previous": -1, "hunter": i == 0 and sector >= 3})
	while salvage_cells.size() < 12:
		var cell := free_cell()
		if not salvage_cells.has(cell): salvage_cells.append(cell)
	phase = "chart"
	notice = ""
	notice_time = 0
	revision += 1

func free_cell() -> int:
	for attempt in 10000:
		var i := rng.randi_range(0, grid.cells.size() - 1)
		if grid.cells[i] == Grid.FREE: return i
	return -1

func goal() -> float:
	return 30.0 + sector * 5.0

func percent() -> float:
	return 100.0 * reclaimed_area / maxf(initial_area, 0.001)

func begin() -> void:
	if phase == "chart":
		phase = "run"
		draw_armed = false

func move_to(next: int, draw_line: bool) -> bool:
	if phase != "run" or not grid.neighbours[player].has(next): return false
	var kind: int = grid.cells[next]
	if kind == Grid.ROCK or kind == Grid.TRAIL: return false
	if kind == Grid.FREE:
		# Invulnerability protects the ship, but never paints over a live enemy.
		for enemy in enemies:
			if enemy.cell == next:
				hurt()
				return false
		if not drawing:
			if not draw_line or not draw_armed: return false
			drawing = true
			home = player
			trail.clear()
			cut_time = 0
		grid.cells[next] = Grid.TRAIL
		trail.append(next)
		player = next
	else:
		player = next
		if drawing: close_cut()
	revision += 1
	return true

func close_cut() -> void:
	var seeds := PackedInt32Array()
	for enemy in enemies: seeds.append(enemy.cell)
	var region := grid.claimable(seeds)
	var area := grid.area(region) + grid.area(trail)
	for i in region: grid.cells[i] = Grid.CLAIMED
	for i in trail: grid.cells[i] = Grid.CLAIMED
	reclaimed_area += area
	for index in range(salvage_cells.size() - 1, -1, -1):
		if grid.cells[salvage_cells[index]] == Grid.CLAIMED:
			salvage_cells.remove_at(index)
			salvage += 1
	notice = "SPLIT / NEW COAST" if region.is_empty() else "+%d%% RECLAIMED" % roundi(100 * area / initial_area)
	notice_time = 1.4
	trail.clear()
	drawing = false
	draw_armed = false
	cut_time = 0
	if percent() >= goal(): phase = "complete" if sector == 8 else "draft"

func hurt() -> void:
	if invulnerable > 0: return
	hull -= 1
	for i in trail: grid.cells[i] = Grid.FREE
	trail.clear()
	drawing = false
	draw_armed = false
	player = home
	invulnerable = 2.0
	cut_time = 0
	notice = "HULL LOST"
	notice_time = 1.4
	revision += 1
	if hull <= 0: phase = "lost"

func dash() -> void:
	if phase == "run" and dash_cooldown <= 0:
		dash_time = 0.45
		dash_cooldown = dash_recharge

func tick(dt: float) -> void:
	if phase != "run": return
	notice_time = maxf(0, notice_time - dt)
	invulnerable = maxf(0, invulnerable - dt)
	dash_time = maxf(0, dash_time - dt)
	dash_cooldown = maxf(0, dash_cooldown - dt)
	if drawing:
		cut_time += dt
		if cut_time >= 25: hurt()
	enemy_acc += dt * (3.0 + sector * 0.15)
	while enemy_acc >= 1 and phase == "run":
		enemy_acc -= 1
		for enemy in enemies:
			var choices: Array[int] = []
			for next in grid.neighbours[enemy.cell]:
				if grid.cells[next] in [Grid.FREE, Grid.TRAIL]: choices.append(next)
			if choices.is_empty(): continue
			if choices.size() > 1: choices.erase(int(enemy.previous))
			var chosen: int = choices[rng.randi_range(0, choices.size() - 1)]
			if enemy.hunter and drawing:
				for next in choices:
					if grid.directions[next].dot(grid.directions[player]) > grid.directions[chosen].dot(grid.directions[player]): chosen = next
			if grid.cells[chosen] == Grid.TRAIL:
				hurt()
				if grid.cells[chosen] == Grid.TRAIL: continue
			if grid.cells[chosen] == Grid.FREE:
				enemy.previous = enemy.cell
				enemy.cell = chosen

func choose_upgrade(choice: int) -> void:
	if phase != "draft": return
	match choice:
		0: speed += 0.7
		1: hull = mini(6, hull + 1)
		2: dash_recharge = maxf(1.4, dash_recharge - 0.5)
	sector += 1
	start_sector()
