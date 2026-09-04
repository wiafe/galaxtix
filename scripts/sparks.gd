class_name Sparks
extends RefCounted
## One fixed ring-buffer pool for every particle (assets.js:2825). A spark is drawn as a line
## from its previous to its current position, so motion blur comes for free on the beam display.
## Ripples are expanding rings (assets.js:2863).

const MAX := 3000

var x := PackedFloat32Array()
var y := PackedFloat32Array()
var px := PackedFloat32Array()
var py := PackedFloat32Array()
var vx := PackedFloat32Array()
var vy := PackedFloat32Array()
var t := PackedFloat32Array()      # age (negative = not born yet, used for "spread")
var dur := PackedFloat32Array()    # lifetime; <= 0 means dead
var drag := PackedFloat32Array()
var cr := PackedFloat32Array()
var cg := PackedFloat32Array()
var cb := PackedFloat32Array()
var head := 0
var ripples: Array = []   # [center, radius, radial speed, age, dur, color]


func _init() -> void:
	for arr in [x, y, px, py, vx, vy, t, dur, drag, cr, cg, cb]:
		arr.resize(MAX)
		arr.fill(0.0)


func emit(pos: Vector2, vel: Vector2, lifetime: float, col: Color, p_drag := 0.8, delay := 0.0) -> void:
	var i := head
	head = (head + 1) % MAX
	x[i] = pos.x
	y[i] = pos.y
	px[i] = pos.x
	py[i] = pos.y
	vx[i] = vel.x
	vy[i] = vel.y
	t[i] = -delay
	dur[i] = lifetime
	drag[i] = p_drag
	cr[i] = col.r
	cg[i] = col.g
	cb[i] = col.b


## power = max speed, curve = speed distribution (1 uniform, 2 fireball, 8 mostly-slow smoke),
## spread = seconds over which the burst staggers, ring = emit on a ring instead of a point.
func burst(pos: Vector2, count: int, power: float, curve: float, lifetime: float, col: Color,
		spread := 0.0, inherit := Vector2.ZERO, p_drag := 1.0, ring := 0.0) -> void:
	for k in count:
		var ang := randf() * TAU
		var d := Vector2(cos(ang), sin(ang))
		var sp := power * pow(randf(), curve)
		var off := d * ring if ring > 0.0 else Vector2.ZERO
		emit(pos + off, d * sp + inherit, lifetime * (0.6 + 0.8 * randf()), col, p_drag, randf() * spread)


## Lightning-as-sparks (assets.js:3049): seed sparks every few px along a polyline with a
## start delay proportional to distance, so the bolt visibly travels.
func zap_polyline(pts: PackedVector2Array, col: Color, travel := 1400.0, step := 7.0) -> void:
	var dist := 0.0
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var L := a.distance_to(b)
		var n := int(maxf(1.0, L / step))
		for k in n:
			var p := a.lerp(b, float(k) / n)
			var fuzz := Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5))
			var vel := Vector2(randf_range(-25, 25), randf_range(-25, 25))
			emit(p + fuzz, vel, 0.35 + randf() * 0.25, col, 3.0, (dist + L * k / n) / travel)
		dist += L


func ripple(pos: Vector2, r0: float, speed: float, lifetime: float, col: Color) -> void:
	ripples.append([pos, r0, speed, 0.0, lifetime, col])


func update(dt: float) -> void:
	for i in MAX:
		if dur[i] <= 0.0:
			continue
		t[i] += dt
		if t[i] >= dur[i]:
			dur[i] = 0.0
			continue
		if t[i] < 0.0:
			continue
		px[i] = x[i]
		py[i] = y[i]
		x[i] += vx[i] * dt
		y[i] += vy[i] * dt
		var k := 1.0 - drag[i] * dt
		vx[i] *= k
		vy[i] *= k
		# crackle: a few embers randomly kick and live a little longer (assets.js:2850)
		if randf() < dt * 0.5:
			vx[i] += randf_range(-40, 40)
			vy[i] += randf_range(-40, 40)
			dur[i] += 0.08
	var j := ripples.size() - 1
	while j >= 0:
		var r: Array = ripples[j]
		r[3] += dt
		r[1] += r[2] * dt
		r[2] *= 1.0 - 1.5 * dt
		if r[3] >= r[4]:
			ripples.remove_at(j)
		j -= 1


func draw(lines: ScopeLines) -> void:
	for i in MAX:
		if dur[i] <= 0.0 or t[i] < 0.0:
			continue
		var f := 1.0 - t[i] / dur[i]
		var col := Color(cr[i], cg[i], cb[i], 0.15 + 0.75 * f)
		lines.seg(Vector2(px[i], py[i]), Vector2(x[i], y[i]), col, 0.8, 0.3, 0.9)
	for r in ripples:
		var f: float = 1.0 - r[3] / r[4]
		var col: Color = r[5]
		col.a = 0.9 * f
		lines.circle(r[0], r[1], col, 28, 1.5, 0.3, 0.8)
