extends RefCounted
## Player preferences are separate from progression and the developer's FX defaults.
const PATH := "user://options.cfg"
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]
const EFFECTS := {
	"glow": ["glow_enabled"], "trails": ["trail_feedback"],
	"crt": ["crt_curve"], "scanlines": ["scan_depth"],
	"aberration": ["aberration"], "grain": ["grain"],
	"vignette": ["vignette"], "shake": ["shake_mult"],
	"flicker": ["wobble", "slop", "element_wobble", "element_slop", "spike_mult"],
}
var values := {"volume": 100, "fullscreen": false, "resolution": 1, "vsync": true}

func _init() -> void:
	for key in EFFECTS:
		values[key] = true

func read_settings(path := PATH) -> void:
	if path == PATH and OS.get_cmdline_user_args().has("--nosave"):
		return
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return
	for key in values:
		var value = config.get_value("options", key, values[key])
		if typeof(value) == typeof(values[key]):
			values[key] = value
	values.volume = clampi(values.volume, 0, 100)
	values.resolution = clampi(values.resolution, 0, RESOLUTIONS.size() - 1)

func write_settings(path := PATH) -> Error:
	if path == PATH and OS.get_cmdline_user_args().has("--nosave"):
		return OK
	var config := ConfigFile.new()
	for key in values:
		config.set_value("options", key, values[key])
	return config.save(path)

func apply_effects(display: ScopeDisplay, baseline: FxSettings) -> void:
	display.settings.copy_from(baseline)
	for key in EFFECTS:
		if not values[key]:
			for prop in EFFECTS[key]:
				display.settings.set(prop, false if prop == "glow_enabled" else 0.0)
	display.apply_settings()

func apply_audio() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(values.volume) / 100.0, 0.0001)))
	AudioServer.set_bus_mute(0, values.volume == 0)

func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if values.vsync else DisplayServer.VSYNC_DISABLED)
	if OS.has_feature("web"):
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if values.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	if not values.fullscreen:
		var usable := DisplayServer.screen_get_usable_rect()
		var requested: Vector2i = RESOLUTIONS[values.resolution]
		var scale_factor := minf(1.0, minf(float(usable.size.x) / requested.x, float(usable.size.y) / requested.y))
		var fitted := Vector2i(Vector2(requested) * scale_factor)
		DisplayServer.window_set_size(fitted)
		DisplayServer.window_set_position(usable.position + (usable.size - fitted) / 2)
