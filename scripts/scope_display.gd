class_name ScopeDisplay
extends Node2D
## The vector display, shared by the game and the FX lab:
##   SceneVP (HDR 2D + glow)  ->  TrailA/TrailB (phosphor feedback ping-pong)  ->  Screen (CRT)
## Add world content with add_scene_child(); draw beams through `lines` between begin_draw/end_draw.

const W := 1600
const H := 900

var settings: FxSettings
var scene_vp: SubViewport
var trail_a: SubViewport
var trail_b: SubViewport
var screen: ColorRect
var env: Environment
var scene_root: Node2D
var lines: ScopeLines
var sparks: Sparks
var compat := false   # true on the Compatibility renderer (web builds)
var web := false      # true in browser builds (or with --webprofile): stripped-down effect profile
var t := 0.0


func _init(p_settings: FxSettings = null) -> void:
	settings = p_settings if p_settings != null else FxSettings.load_or_default()


func _ready() -> void:
	# --- the "tube": the game world, rendered additively into an HDR buffer with glow
	scene_vp = SubViewport.new()
	scene_vp.size = Vector2i(W, H)
	compat = RenderingServer.get_current_rendering_method() == "gl_compatibility"
	web = OS.has_feature("web") or OS.get_cmdline_user_args().has("--webprofile")
	scene_vp.use_hdr_2d = true
	if not compat:
		scene_vp.msaa_2d = Viewport.MSAA_4X
	scene_vp.own_world_3d = true
	scene_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	scene_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	add_child(scene_vp)

	env = Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_normalized = false
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_scale = 2.0
	env.glow_hdr_luminance_cap = 12.0
	var level_weights := [1.0, 0.9, 0.7, 0.5, 0.3, 0.15, 0.0]
	for i in 7:
		env.set_glow_level(i, level_weights[i])
	var we := WorldEnvironment.new()
	we.environment = env
	scene_vp.add_child(we)

	var bg := ColorRect.new()
	bg.color = Palette.BG
	bg.size = Vector2(W, H)
	scene_vp.add_child(bg)

	scene_root = Node2D.new()
	scene_vp.add_child(scene_root)

	lines = ScopeLines.new()
	# Forward+ has 4x MSAA to resolve sub-pixel beams; Compatibility has none, so widen and dim
	lines.min_width = 2.0 if web else (1.6 if compat else 1.0)
	scene_vp.add_child(lines)
	sparks = Sparks.new()

	# --- phosphor trails: two feedback buffers reading each other
	trail_a = _make_trail_vp()
	trail_b = _make_trail_vp()
	add_child(trail_a)
	add_child(trail_b)
	_trail_rect(trail_a).material.set_shader_parameter("prev_tex", trail_b.get_texture())
	_trail_rect(trail_b).material.set_shader_parameter("prev_tex", trail_a.get_texture())

	# --- the glass: composite + CRT to the window
	screen = ColorRect.new()
	screen.size = Vector2(W, H)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/crt_final.gdshader")
	sm.set_shader_parameter("scene_tex", scene_vp.get_texture())
	if web:
		# no phosphor trails on the web: two fewer full-screen passes per frame
		trail_a.render_target_update_mode = SubViewport.UPDATE_DISABLED
		trail_b.render_target_update_mode = SubViewport.UPDATE_DISABLED
		sm.set_shader_parameter("trail_tex", scene_vp.get_texture())
	else:
		sm.set_shader_parameter("trail_tex", trail_a.get_texture())
	sm.set_shader_parameter("pix", Vector2(1.0 / W, 1.0 / H))
	screen.material = sm
	add_child(screen)

	apply_settings()


func _make_trail_vp() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.use_hdr_2d = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var r := ColorRect.new()
	r.name = "Rect"
	r.size = Vector2(W, H)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/trail_feedback.gdshader")
	m.set_shader_parameter("scene_tex", scene_vp.get_texture())
	m.set_shader_parameter("texel", Vector2(1.0 / W, 1.0 / H))
	r.material = m
	vp.add_child(r)
	return vp


func _trail_rect(vp: SubViewport) -> ColorRect:
	return vp.get_node("Rect") as ColorRect


## Push every FxSettings value into the renderer, environment and shaders. Cheap; call on any change.
func apply_settings() -> void:
	var s := settings
	if web:
		# Web profile: the browser canvas is resampled to an arbitrary size and WebGL is slow, so
		# everything that shimmers, moirés, or costs a full-screen pass is stripped.
		s = FxSettings.new()
		s.copy_from(settings)
		s.crt_curve = 0.0
		s.scan_depth = 0.0
		s.aberration = 0.0
		s.grain = 0.0
		s.vignette = 0.3
		s.wobble = 0.0
		s.slop = 0.0
		s.element_wobble = 0.0
		s.element_slop = 0.0
		s.spike_mult = minf(s.spike_mult, 0.3)
		s.beam = maxf(s.beam, 2.0)
		s.trail_feedback = 0.0
		s.trail_blur = 0.0
		s.trail_dry = 1.0
		s.glow_enabled = false   # the ring-blur stand-in reads as a blocky halo once the browser scales it
	VectorFont.current = s.font
	VectorFont.display = s.title_font
	VectorFont.tracking = s.font_tracking
	lines.beam = s.beam
	lines.wobble = s.wobble
	lines.slop = s.slop
	lines.lfo_speed = s.lfo_speed
	lines.element_wobble = s.element_wobble
	lines.element_slop = s.element_slop
	lines.spike_mult = s.spike_mult

	env.glow_enabled = s.glow_enabled
	env.glow_intensity = s.glow_intensity
	env.glow_strength = s.glow_strength
	env.glow_hdr_threshold = s.glow_threshold
	env.glow_bloom = s.glow_bloom

	for vp in [trail_a, trail_b]:
		var m: ShaderMaterial = _trail_rect(vp).material
		m.set_shader_parameter("feedback", s.trail_feedback)
		m.set_shader_parameter("blur_radius", s.trail_blur)

	var cm: ShaderMaterial = screen.material
	var trails_enabled := not web and s.trail_feedback > 0.0
	for vp in [trail_a, trail_b]:
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if trails_enabled else SubViewport.UPDATE_DISABLED
	cm.set_shader_parameter("trail_tex", trail_a.get_texture() if trails_enabled else scene_vp.get_texture())
	cm.set_shader_parameter("dry", s.trail_dry)
	cm.set_shader_parameter("curve", s.crt_curve)
	cm.set_shader_parameter("scan_depth", s.scan_depth)
	cm.set_shader_parameter("scan_lines", s.scan_lines)
	cm.set_shader_parameter("vignette", s.vignette)
	cm.set_shader_parameter("aberr", s.aberration)
	cm.set_shader_parameter("grain", s.grain)
	cm.set_shader_parameter("contrast", s.contrast)
	cm.set_shader_parameter("gamma_adj", s.gamma)
	cm.set_shader_parameter("saturation", s.saturation)
	cm.set_shader_parameter("warmth", s.warmth)
	# Compatibility renderer (web builds): no HDR 2D, so the scene texture is already sRGB and
	# there is no environment glow; skip the gamma step and fake the bloom in the final pass.
	cm.set_shader_parameter("to_srgb", not compat)
	cm.set_shader_parameter("fake_bloom", (s.glow_intensity * 0.35) if (compat and s.glow_enabled) else 0.0)


## Content that should sit under the beams (fills, masks) goes here.
func add_scene_child(n: Node) -> void:
	scene_root.add_child(n)


func tick(dt: float) -> void:
	t += dt
	lines.tick(dt)


func begin_draw(shake: Vector2 = Vector2.ZERO) -> void:
	lines.offset = shake * settings.shake_mult
	scene_root.position = lines.offset
	lines.begin()


func end_draw() -> void:
	lines.end()
	screen.material.set_shader_parameter("time", t)


func screenshot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
