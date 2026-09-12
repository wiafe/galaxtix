extends Node2D
## Act 4 traversal prototype. Launch through the Maps addon, or F6 this scene.
## The existing three-act run and its save schema are not changed by the test.
signal exited
const Run = preload("res://scripts/planet_run.gd")
const RADIUS := 10.0
var run := Run.new()
var display: ScopeDisplay
var world_view: SubViewport
var world: Node3D
var camera: Camera3D
var surface: MeshInstance3D
var surface_image: Image
var surface_texture: ImageTexture
var lines_3d: MeshInstance3D
var dynamic_mesh: ImmediateMesh
var planet_material: ShaderMaterial
var visual_up := Vector3.BACK
var camera_up := Vector3.UP
var move_acc := 0.0
var shown_revision := -1
var shown_sector := -1
var selection := 0
var elapsed := 0.0
var phase_time := 0.0
var previous_phase := ""
var previous_player := -1
var enemy_visual: Array[Vector3] = []
var enemy_beams: Array = []
var beam_clock := 0.0
var ship_direction := Vector3.RIGHT
var surface_cells := PackedByteArray()
var capture_pulses: Array[Dictionary] = []
var enabled := true

func _ready() -> void:
	Controls.setup_actions()
	display = ScopeDisplay.new()
	add_child(display)
	run.start()
	build_world()
	visual_up = run.grid.directions[run.player]
	update_camera(1.0)
	sync_surface()

func build_world() -> void:
	world_view = SubViewport.new()
	world_view.size = Vector2i(1600, 900)
	world_view.own_world_3d = true
	world_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	world_view.msaa_3d = Viewport.MSAA_4X
	add_child(world_view)
	world = Node3D.new()
	world_view.add_child(world)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.003, 0.003, 0.003)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = env
	world.add_child(environment)
	var image := Sprite2D.new()
	image.texture = world_view.get_texture()
	image.centered = false
	display.add_scene_child(image)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 28.0
	camera.near = 0.1
	camera.far = 150.0
	world.add_child(camera)
	var vertices := PackedVector3Array()
	var uv := PackedVector2Array()
	var normals := PackedVector3Array()
	var n: int = run.grid.size
	for face in 6:
		for y in n:
			for x in n:
				for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]:
					var point: Vector3 = run.grid.point(face, x + corner.x, y + corner.y)
					vertices.append(point * RADIUS)
					normals.append(point)
					uv.append(Vector2((face * n + x + corner.x) / (6.0 * n), (y + corner.y) / n))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	surface = MeshInstance3D.new()
	surface.mesh = mesh
	planet_material = ShaderMaterial.new()
	planet_material.shader = preload("res://shaders/planet_surface.gdshader")
	surface_image = Image.create(n * 6, n, false, Image.FORMAT_RGBAF)
	surface_texture = ImageTexture.create_from_image(surface_image)
	planet_material.set_shader_parameter("surface_map", surface_texture)
	planet_material.set_shader_parameter("resolution", float(n))
	surface.material_override = planet_material
	world.add_child(surface)
	var atmosphere := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = RADIUS + 0.16
	sphere.height = sphere.radius * 2
	sphere.radial_segments = 96
	sphere.rings = 48
	atmosphere.mesh = sphere
	var atmosphere_material := ShaderMaterial.new()
	atmosphere_material.shader = preload("res://shaders/planet_atmosphere.gdshader")
	atmosphere.material_override = atmosphere_material
	atmosphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(atmosphere)
	lines_3d = MeshInstance3D.new()
	dynamic_mesh = ImmediateMesh.new()
	lines_3d.mesh = dynamic_mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	lines_3d.material_override = material
	world.add_child(lines_3d)
	# Distant stars remain behind the globe as the camera orbits.
	var random := RandomNumberGenerator.new()
	random.seed = 421
	for i in 100:
		var star := MeshInstance3D.new()
		var dot := SphereMesh.new()
		dot.radius = random.randf_range(0.025, 0.065)
		dot.height = dot.radius * 2
		dot.radial_segments = 4
		dot.rings = 2
		star.mesh = dot
		star.position = Vector3(random.randf_range(-1, 1), random.randf_range(-1, 1), random.randf_range(-1, 1)).normalized() * 55
		var star_material := StandardMaterial3D.new()
		star_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		star_material.albedo_color = Color(0.15, 0.22, 0.28)
		star.material_override = star_material
		world.add_child(star)

func sync_surface() -> void:
	if shown_sector != run.sector:
		shown_sector = run.sector
		visual_up = run.grid.directions[run.player]
		camera_up = Vector3.UP
		enemy_visual.clear()
		enemy_beams.clear()
		capture_pulses.clear()
		surface_cells = run.grid.cells.duplicate()
		shown_revision = -1
		surface_image.fill(Color(0, 0, 0, 1))
		move_acc = 0
		update_camera(1.0)
	if shown_revision == run.revision: return
	shown_revision = run.revision
	var n: int = run.grid.size
	for i in run.grid.cells.size():
		var face: int = i / (n * n)
		var x: int = i % n
		var y: int = (i % (n * n)) / n
		var pixel := surface_image.get_pixel(face * n + x, y)
		if run.grid.cells[i] == Run.Grid.CLAIMED and surface_cells[i] != Run.Grid.CLAIMED:
			pixel.g = elapsed
			pixel.b = 1.0
			if capture_pulses.size() < 12 and surface_cells[i] == Run.Grid.FREE:
				capture_pulses.append({"up": run.grid.directions[i], "age": 0.0})
		pixel.r = float(run.grid.cells[i]) / 3.0
		surface_image.set_pixel(face * n + x, y, pixel)
	surface_cells = run.grid.cells.duplicate()
	surface_texture.update(surface_image)

func update_camera(dt: float) -> void:
	# Keep the old screen-up tangent to the globe. This parallel-transports the
	# view through poles instead of snapping to a fixed global up vector.
	var target_up: Vector3 = run.grid.directions[run.player]
	if previous_player >= 0 and target_up.dot(visual_up) < 0.45:
		visual_up = target_up # Respawn/landing, never orbit through the planet.
	else:
		visual_up = visual_up.slerp(target_up, 1.0 - exp(-20.0 * dt)).normalized()
	previous_player = run.player
	var view_normal := camera.position.normalized() if camera.position.length_squared() > 1 else visual_up
	view_normal = view_normal.slerp(visual_up, 1.0 - exp(-7.0 * dt)).normalized()
	camera_up = camera_up - view_normal * camera_up.dot(view_normal)
	if camera_up.length_squared() < 0.001: camera_up = camera.basis.x.cross(view_normal)
	camera_up = camera_up.normalized()
	camera.position = view_normal * 32.0
	camera.basis = Basis.looking_at(-view_normal, camera_up)

func _process(dt: float) -> void:
	if not enabled: return
	dt = minf(dt, 0.05)
	elapsed += dt
	phase_time += dt
	if run.phase != previous_phase:
		previous_phase = run.phase
		phase_time = 0
		selection = 0
		move_acc = 0
	if run.phase == "run":
		var draw_line := Input.is_action_pressed("draw")
		if not draw_line: run.draw_armed = true
		if Input.is_action_just_pressed("abort"): run.phase = "paused"
		if Input.is_action_just_pressed("special"): run.dash()
		var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if input.length() > 0.2:
			move_acc += dt * run.speed * (2.5 if run.dash_time > 0 else 1.0)
			while move_acc >= 1 and run.phase == "run":
				move_acc -= 1
				var up: Vector3 = run.grid.directions[run.player]
				var wish := camera.basis.x * input.x - camera.basis.y * input.y
				wish = (wish - up * wish.dot(up)).normalized()
				ship_direction = wish
				run.move_to(run.grid.neighbour_toward(run.player, wish), draw_line)
		else: move_acc = 0
		run.tick(dt)
	else:
		var count := 3 if run.phase == "draft" else (2 if run.phase == "paused" else 1)
		if Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("move_up"): selection = posmod(selection - 1, count)
		if Input.is_action_just_pressed("move_right") or Input.is_action_just_pressed("move_down"): selection = (selection + 1) % count
		if phase_time > 0.2 and Input.is_action_just_pressed("confirm"): activate(selection)
		if Input.is_action_just_pressed("abort"):
			if run.phase == "paused": run.phase = "run"
			else: leave()
	sync_surface()
	update_camera(dt)
	draw_entities(dt)
	display.tick(dt)
	display.begin_draw()
	draw_hud()
	display.end_draw()

func segment(a: Vector3, b: Vector3, color: Color, width := 1.0) -> void:
	# Camera-facing ribbons keep the familiar beam weight at any surface angle.
	if a.distance_squared_to(b) < 0.000001: return
	var side := (b - a).cross(camera.basis.z).normalized() * 0.023 * width
	var beam := Color(color.r * color.a, color.g * color.a, color.b * color.a, 1)
	for point in [a - side, a + side, b + side, a - side, b + side, b - side]:
		dynamic_mesh.surface_set_color(beam)
		dynamic_mesh.surface_add_vertex(point)

func surface_segment(a: Vector3, b: Vector3, color: Color, width := 1.0) -> void:
	# Project the beam onto the skin, including when it crosses a cube-face seam.
	var steps := maxi(2, ceili(a.angle_to(b) * RADIUS / 0.2))
	for i in steps:
		segment(a.slerp(b, float(i) / steps).normalized() * (RADIUS + 0.09), a.slerp(b, float(i + 1) / steps).normalized() * (RADIUS + 0.09), color, width)

func ring(up: Vector3, radius: float, color: Color, height := 0.12, sides := 16) -> void:
	var u := up.cross(Vector3.UP).normalized()
	if u.length_squared() < 0.1: u = up.cross(Vector3.RIGHT).normalized()
	var v := up.cross(u).normalized()
	var center := up * (RADIUS + height)
	for i in sides:
		var a := i * TAU / sides
		var b := (i + 1) * TAU / sides
		segment(center + radius * (u * cos(a) + v * sin(a)), center + radius * (u * cos(b) + v * sin(b)), color)

func draw_entities(dt: float) -> void:
	planet_material.set_shader_parameter("clock", elapsed)
	dynamic_mesh.clear_surfaces()
	dynamic_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	# Bright continuous coast; all segments follow shared cube-face boundaries.
	for i in run.grid.cells.size():
		if run.grid.cells[i] not in [Run.Grid.CLAIMED, Run.Grid.ROCK]: continue
		var n: int = run.grid.size
		var face: int = i / (n * n)
		var x: int = i % n
		var y: int = (i % (n * n)) / n
		var edges := [[Vector2(0, 0), Vector2(0, 1)], [Vector2(1, 0), Vector2(1, 1)], [Vector2(0, 0), Vector2(1, 0)], [Vector2(0, 1), Vector2(1, 1)]]
		for side in 4:
			var next: int = run.grid.neighbours[i][side]
			if run.grid.cells[next] not in [Run.Grid.FREE, Run.Grid.TRAIL]: continue
			var a: Vector2 = edges[side][0]
			var b: Vector2 = edges[side][1]
			var color := Palette.CYAN if run.grid.cells[i] == Run.Grid.CLAIMED else Color(Palette.DIM, 0.6)
			surface_segment(run.grid.point(face, x + a.x, y + a.y), run.grid.point(face, x + b.x, y + b.y), color)
	for cell in run.salvage_cells:
		ring(run.grid.directions[cell], 0.22 + 0.02 * sin(elapsed * 3 + cell), Palette.YELLOW, 0.14, 6)
		ring(run.grid.directions[cell], 0.09, Palette.YELLOW, 0.14, 6)
	if run.drawing:
		var start: Vector3 = run.grid.directions[run.home]
		for i in run.trail.size():
			var end: Vector3 = visual_up if i == run.trail.size() - 1 else run.grid.directions[run.trail[i]]
			surface_segment(start, end, Palette.MAGENTA, 1.3)
			start = end
		ring(run.grid.directions[run.home], 0.12, Palette.ORANGE, 0.12, 8)
	# Anomaly's spectrum and twelve-beam history, laid flat on the sphere.
	beam_clock += dt if run.phase == "run" else 0.0
	var record_beam := beam_clock >= 1.0 / 30.0
	if record_beam: beam_clock = fmod(beam_clock, 1.0 / 30.0)
	while enemy_visual.size() < run.enemies.size():
		enemy_visual.append(run.grid.directions[run.enemies[enemy_visual.size()].cell])
		enemy_beams.append([])
	for i in run.enemies.size():
		var enemy: Dictionary = run.enemies[i]
		enemy_visual[i] = enemy_visual[i].slerp(run.grid.directions[enemy.cell], 1.0 - exp(-16.0 * dt))
		var up := enemy_visual[i].normalized()
		var u := up.cross(Vector3.UP).normalized()
		if u.length_squared() < 0.1: u = up.cross(Vector3.RIGHT).normalized()
		var angle := elapsed * (1.9 if enemy.hunter else 1.2) + i * 2.4
		var axis := u * cos(angle) + up.cross(u) * sin(angle)
		var half_length := 0.32 + 0.08 * sin(elapsed * 1.7 + i)
		if record_beam or enemy_beams[i].is_empty():
			enemy_beams[i].push_front([(up * RADIUS - axis * half_length).normalized(), (up * RADIUS + axis * half_length).normalized()])
			if enemy_beams[i].size() > Game.QIX_HIST: enemy_beams[i].pop_back()
		for age in enemy_beams[i].size():
			var color: Color = Game.QIX_COLORS[(int(elapsed * 20) + i * 3 + age) % Game.QIX_COLORS.size()]
			color.a = 0.2 + 0.6 * (1.0 - float(age) / Game.QIX_HIST)
			surface_segment(enemy_beams[i][age][0], enemy_beams[i][age][1], color, 1.2 if age == 0 else 0.65)
		if enemy.hunter: ring(up, 0.10, Palette.RED, 0.14, 4)
	var right := (camera.basis.x - visual_up * camera.basis.x.dot(visual_up)).normalized()
	var forward := visual_up.cross(right).normalized()
	var center := visual_up * (RADIUS + 0.19)
	var ship_color := Palette.MAGENTA if run.drawing else Palette.FULLBRIGHT
	if run.invulnerable > 0 and fmod(elapsed, 0.2) < 0.1: ship_color *= 0.4
	# Same equal-sided Surveyor diamond and direction stroke as Game.draw_field.
	var points := [center + forward * 0.25, center + right * 0.25, center - forward * 0.25, center - right * 0.25]
	for i in 4: segment(points[i], points[(i + 1) % 4], ship_color, 1.3)
	var heading := (ship_direction - visual_up * ship_direction.dot(visual_up)).normalized()
	segment(center, center + heading * 0.40, ship_color)
	for i in range(capture_pulses.size() - 1, -1, -1):
		var pulse := capture_pulses[i]
		pulse.age += dt if run.phase != "paused" else 0.0
		if pulse.age >= 0.5:
			capture_pulses.remove_at(i)
			continue
		ring(pulse.up, 0.05 + pulse.age * 1.2, Color(Palette.CYAN, (1.0 - pulse.age / 0.5) * 0.65), 0.10, 16)
	dynamic_mesh.surface_end()

func text(value: String, position: Vector2, size: float, color := Palette.WHITE, align := 0) -> void:
	VectorFont.draw(display.lines, value, position, size, color, 0.0, 0.0, align)

func button_rect(index: int) -> Rect2:
	if run.phase == "draft": return Rect2(230 + index * 390, 570, 360, 105)
	if run.phase == "paused": return Rect2(330 + index * 510, 570, 450, 70)
	return Rect2(555, 650, 490, 64)

func draw_button(index: int, title: String, detail := "") -> void:
	var rect := button_rect(index)
	display.lines.rect(rect, Palette.CYAN if index == selection else Palette.DIM)
	text(("> " if index == selection else "") + title, rect.get_center() - Vector2(0, 11 if detail.is_empty() else 24), 20, Palette.WHITE, 1)
	if not detail.is_empty(): text(detail, rect.get_center() + Vector2(0, 16), 13, Palette.CYAN, 1)

func draw_hud() -> void:
	text("ACT 4 / HOMEWORLD", Vector2(80, 55), 26, Palette.CYAN)
	text("PLANET PROTOTYPE / SURVEYOR", Vector2(80, 99), 12, Palette.DIM)
	text("SURFACE %02d / 08" % run.sector, Vector2(1510, 55), 20, Palette.WHITE, 2)
	text("HULL %d   SALVAGE %d" % [run.hull, run.salvage], Vector2(1510, 91), 15, Palette.YELLOW, 2)
	text("%.1f%% / %d%%" % [run.percent(), int(run.goal())], Vector2(800, 108), 18, Palette.CYAN, 1)
	var meter := Rect2(550, 138, 500, 5)
	display.lines.rect(meter, Palette.DIM)
	display.lines.seg(meter.position, meter.position + Vector2(meter.size.x * clampf(run.percent() / run.goal(), 0, 1), 0), Palette.CYAN, 0, 0, 3)
	if run.phase == "run":
		text(Controls.hint("ARROWS / WASD: MOVE   SPACE: CUT   ESC: PAUSE"), Vector2(800, 817), 14, Palette.DIM, 1)
		text(("X / RB" if Controls.using_controller else "E") + (": DASH" if run.dash_cooldown <= 0 else ": %.1fS" % run.dash_cooldown), Vector2(800, 855), 15, Palette.CYAN, 1)
		if run.drawing and run.cut_time > 18: text("CLOSE THE CUT / %dS" % ceili(25 - run.cut_time), Vector2(800, 748), 16, Palette.ORANGE, 1)
		if run.notice_time > 0: text(run.notice, Vector2(800, 730), 21, Palette.YELLOW, 1)
		return
	display.lines.modal_start = display.lines.count
	match run.phase:
		"chart":
			text(Run.SECTORS[run.sector - 1], Vector2(800, 300), 42, Palette.CYAN, 1)
			text("RECLAIM %d%% OF THE PLANET" % int(run.goal()), Vector2(800, 385), 23, Palette.WHITE, 1)
			text("CLOSE LOOPS. THE CAMERA FOLLOWS YOU.", Vector2(800, 435), 16, Palette.DIM, 1)
			for i in 8:
				var at := Vector2(450 + i * 100, 550)
				display.lines.circle(at, 18 if i + 1 == run.sector else 9, Palette.CYAN if i + 1 <= run.sector else Palette.DIM, 24)
				if i < 7: display.lines.seg(at + Vector2(23, 0), at + Vector2(77, 0), Palette.DIM)
			draw_button(0, "LAND")
		"draft":
			text("SURFACE SECURED", Vector2(800, 300), 38, Palette.GREEN, 1)
			text("CHOOSE AN UPGRADE", Vector2(800, 390), 20, Palette.WHITE, 1)
			draw_button(0, "ENGINES", "+10% BASE SPEED")
			draw_button(1, "REPAIR", "+1 HULL / MAX 6")
			draw_button(2, "DASH", "0.5S FASTER RECHARGE")
		"paused":
			text("PAUSED", Vector2(800, 330), 40, Palette.CYAN, 1)
			draw_button(0, "RESUME")
			draw_button(1, "LEAVE PLANET")
		"lost":
			text("HULL LOST", Vector2(800, 330), 40, Palette.ORANGE, 1)
			draw_button(0, "RETRY PLANET ACT")
		"complete":
			text("HOMEWORLD RECLAIMED", Vector2(800, 330), 40, Palette.GREEN, 1)
			text("EIGHT SURFACES SECURED", Vector2(800, 415), 20, Palette.CYAN, 1)
			draw_button(0, "RETURN")

func activate(index: int) -> void:
	match run.phase:
		"chart": run.begin()
		"draft": run.choose_upgrade(index)
		"paused":
			if index == 0: run.phase = "run"
			else: leave()
		"lost":
			run.start()
			shown_sector = -1
		"complete": leave()

func _unhandled_input(event: InputEvent) -> void:
	if not enabled or run.phase == "run" or phase_time < 0.2: return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var count := 3 if run.phase == "draft" else (2 if run.phase == "paused" else 1)
		for index in count:
			if button_rect(index).has_point(event.position):
				activate(index)
				get_viewport().set_input_as_handled()
				return

func leave() -> void:
	if not enabled: return
	enabled = false
	if exited.get_connections().is_empty():
		get_tree().change_scene_to_file("res://scenes/main.tscn")
	else: exited.emit()
