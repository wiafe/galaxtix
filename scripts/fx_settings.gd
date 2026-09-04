class_name FxSettings
extends Resource
## Every tunable of the vector-display look, in one resource. The FX lab scene edits these live
## and saves them to PATH; the game loads the same file at startup.

const PATH := "res://fx_settings.tres"

@export_group("Beam")
@export var beam := 2.0            # line thickness in px
@export var wobble := 0.45         # baseline endpoint jitter in px (everything shivers this much)
@export var slop := 0.10           # baseline endpoint brightness flicker
@export var lfo_speed := 0.6       # multiplier on the 7-11 Hz oscillator bank
@export var element_wobble := 0.35 # multiplier on per-element wobble values set by game code
@export var element_slop := 0.5    # multiplier on per-element slop values set by game code
@export var spike_mult := 0.5      # multiplier on hit/claim/death distortion spikes
@export var shake_mult := 0.6      # multiplier on screen shake

@export_group("Glow")
@export var glow_enabled := true
@export var glow_intensity := 0.9
@export var glow_strength := 1.0
@export var glow_threshold := 0.45
@export var glow_bloom := 0.0

@export_group("Trails")
@export var trail_feedback := 0.86 # how much of last frame survives (persistence)
@export var trail_blur := 1.0      # how far trails soften per frame (px)
@export var trail_dry := 1.0       # live frame brightness in the composite

@export_group("CRT")
@export var crt_curve := 0.06
@export var scan_depth := 0.18
@export var scan_lines := 450.0
@export var vignette := 0.45
@export var aberration := 1.0
@export var grain := 0.035

@export_group("Type")
@export var font := "futural"      # res://fonts/<name>.json (Hershey stroke faces), HUD and body
@export var title_font := "futuram" # display face for the big titles (doubled strokes hold under glow)
@export var font_tracking := 1.0   # letter advance multiplier

@export_group("Grade")
@export var contrast := 1.15
@export var gamma := 1.25
@export var saturation := 1.15
@export var warmth := 0.0


static func load_or_default() -> FxSettings:
	if ResourceLoader.exists(PATH):
		var r = load(PATH)
		if r is FxSettings:
			return r
	return FxSettings.new()


func save() -> Error:
	return ResourceSaver.save(self, PATH)


func copy_from(other: FxSettings) -> void:
	for prop in other.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			set(prop.name, other.get(prop.name))
