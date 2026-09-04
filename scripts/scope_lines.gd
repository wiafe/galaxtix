class_name ScopeLines
extends MultiMeshInstance2D
## The beam renderer. All line art of a frame is batched here and drawn in one instanced call
## with additive blending. Each instance is a real 2D transform mapping a unit quad onto the
## segment (x axis = segment, y axis = normal * width, origin = start), so every renderer,
## including Compatibility/WebGL, treats it like any other MultiMesh. The oscillator bank that
## drives wobble and slop lives in the shader, indexed by the per-instance custom data.

const MAX_SEGS := 16000
const STRIDE := 16          # 8 transform + 4 color + 4 custom floats per instance

var buf := PackedFloat32Array()
var count := 0
var mod_cursor := 0
var offset := Vector2.ZERO   # screen shake, applied on the CPU
var zoom := Vector2.ONE      # whole-picture squash about zoom_center (CRT switch-off outro)
var zoom_center := Vector2(800, 450)

var lfo_speed := 1.0
var lfo_time := 0.0

var wobble := 0.45    # system baseline shimmer (FxSettings.wobble)
var slop := 0.10
var element_wobble := 0.35   # multiplier on per-call wobble values (FxSettings.element_wobble)
var element_slop := 0.5
var spike_mult := 0.5        # multiplier on hit spikes (FxSettings.spike_mult)
var fx_wobble := 0.0  # spike-then-decay on big events
var fx_slop := 0.0
var beam := 2.0
## Narrowest quad the renderer can resolve. Thinner beams are widened to this and dimmed by the
## same ratio, which reads the same but never drops out (no MSAA on the Compatibility renderer).
var min_width := 1.0
var mat: ShaderMaterial


func _ready() -> void:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1, 1)
	mesh.center_offset = Vector3(0.5, 0.5, 0)   # unit quad on 0..1 in both axes

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = MAX_SEGS
	mm.visible_instance_count = 0
	mm.custom_aabb = AABB(Vector3(-100000, -100000, -1), Vector3(200000, 200000, 2))
	multimesh = mm

	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/scope_line.gdshader")
	material = mat

	buf.resize(MAX_SEGS * STRIDE)


func tick(dt: float) -> void:
	# the oscillator bank lives in the shader; we only advance its clock (scaled by lfo_speed)
	lfo_time += dt * lfo_speed
	var k := exp(-dt * 4.0)
	fx_wobble *= k
	fx_slop *= k
	mat.set_shader_parameter("lfo_time", lfo_time)


func spike(w: float, s: float) -> void:
	fx_wobble = maxf(fx_wobble, w * spike_mult)
	fx_slop = maxf(fx_slop, s * spike_mult)


func begin() -> void:
	count = 0
	mod_cursor = 0


func seg(a: Vector2, b: Vector2, c: Color, wob := 0.0, sl := 0.0, thick := 1.0) -> void:
	if count >= MAX_SEGS:
		return
	var o := count * STRIDE
	var m1 := mod_cursor & 63
	var m2 := (mod_cursor + 2) & 63
	mod_cursor += 2
	var ax := zoom_center.x + (a.x + offset.x - zoom_center.x) * zoom.x
	var ay := zoom_center.y + (a.y + offset.y - zoom_center.y) * zoom.y
	var bx := zoom_center.x + (b.x + offset.x - zoom_center.x) * zoom.x
	var by := zoom_center.y + (b.y + offset.y - zoom_center.y) * zoom.y
	var dx := bx - ax
	var dy := by - ay
	var len := sqrt(dx * dx + dy * dy)
	if len < 0.001:
		dx = 0.001   # a resting beam is still a dot: give it a direction for the caps
		dy = 0.0
		len = 0.001
	# sub-pixel beams are widened to min_width and dimmed by the same ratio
	var w := beam * thick
	var alpha := c.a
	if w < min_width:
		alpha *= w / min_width
		w = min_width
	var ht := 0.5 * w
	var nx := -dy / len * ht
	var ny := dx / len * ht
	# rows: (x.x, y.x, 0, o.x), (x.y, y.y, 0, o.y); the quad's y runs 0..1 so the y axis is the
	# full width and the origin sits half a width back from the start point
	buf[o] = dx
	buf[o + 1] = nx * 2.0
	buf[o + 2] = 0.0
	buf[o + 3] = ax - nx
	buf[o + 4] = dy
	buf[o + 5] = ny * 2.0
	buf[o + 6] = 0.0
	buf[o + 7] = ay - ny
	buf[o + 8] = c.r
	buf[o + 9] = c.g
	buf[o + 10] = c.b
	buf[o + 11] = alpha
	buf[o + 12] = float(m1)
	buf[o + 13] = float(m2)
	buf[o + 14] = wobble + fx_wobble + wob * element_wobble
	buf[o + 15] = slop + fx_slop + sl * element_slop
	count += 1


func polyline(pts: PackedVector2Array, closed: bool, c: Color, wob := 0.0, sl := 0.0, thick := 1.0) -> void:
	var n := pts.size()
	if n < 2:
		if n == 1:
			seg(pts[0], pts[0], c, wob, sl, thick)
		return
	var last := n if closed else n - 1
	for i in last:
		seg(pts[i], pts[(i + 1) % n], c, wob, sl, thick)


func rect(r: Rect2, c: Color, wob := 0.0, sl := 0.0, thick := 1.0) -> void:
	polyline(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end,
		Vector2(r.position.x, r.end.y)]), true, c, wob, sl, thick)


func circle(center: Vector2, radius: float, c: Color, segments := 24, wob := 0.0, sl := 0.0, thick := 1.0) -> void:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * i / segments
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	polyline(pts, true, c, wob, sl, thick)


## Draw a set of polylines progressively, like a plotter: only the first `frac` of their total
## length, with a bright dot at the moving head.
func trace(paths: Array, frac: float, c: Color, wob := 0.0, sl := 0.0, thick := 1.0) -> void:
	if frac <= 0.0:
		return
	var total := 0.0
	for pts in paths:
		var pv: PackedVector2Array = pts
		for i in range(pv.size() - 1):
			total += pv[i].distance_to(pv[i + 1])
	var budget: float = total * frac
	for pts in paths:
		var pv: PackedVector2Array = pts
		for i in range(pv.size() - 1):
			var a: Vector2 = pv[i]
			var b: Vector2 = pv[i + 1]
			var L: float = a.distance_to(b)
			if budget >= L:
				seg(a, b, c, wob, sl, thick)
				budget -= L
			else:
				var head: Vector2 = a.lerp(b, budget / maxf(L, 0.001))
				seg(a, head, c, wob, sl, thick)
				seg(head, head, Color(0.94, 0.97, 1.0, 1.0), wob, sl, thick * 1.6)
				return


func end() -> void:
	multimesh.visible_instance_count = count
	multimesh.buffer = buf
