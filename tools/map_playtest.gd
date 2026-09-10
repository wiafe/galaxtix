extends Node
## The Maps plugin supplies --nosave before autoloads start. Direct F6 is also isolated
## before the first frame and before Main/Roguelite can read or write their profiles.
var main: Node

func _enter_tree() -> void:
	Save.enabled = false
	Save.data = Save.fresh()
	Save.offline_gain = 0.0
	Save.set_process(false)

func _ready() -> void:
	var config := ConfigFile.new()
	config.load("res://.godot/map_playtest.cfg")
	var stage := clampi(int(config.get_value("playtest", "stage", 1)), 1, 8)
	var depth := clampi(int(config.get_value("playtest", "depth", stage)), 1, 8)
	var encounter := String(config.get_value("playtest", "encounter", "survey"))
	var ship := String(config.get_value("playtest", "ship", "surveyor"))
	if encounter not in preload("res://scripts/roguelite_sectors.gd").KINDS: encounter = "survey"
	if ship == "sapper": ship = "bulwark"
	if ship not in ["surveyor", "lancer", "bulwark"]: ship = "surveyor"
	MapCatalog.read(stage, true)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.game.start_roguelite()
	var rogue = main.game.roguelite
	rogue.progress.apply_profile({"version": 6, "ships": {"surveyor": true, "lancer": true, "bulwark": true}, "selected_ship": ship})
	rogue.start_run()
	rogue.chart_depth = depth
	rogue.route_path.resize(depth - 1)
	rogue.route_path.fill(0)
	rogue.route[depth - 1] = [{"depth": depth, "stage": stage, "kind": encounter}]
	rogue.open_chart()
	rogue.transit_skip = true
	rogue.launch_destination(0)
	var hud := CanvasLayer.new()
	add_child(hud)
	var label := Label.new()
	label.text = "MAP PLAYTEST  |  Backspace: restart this map  |  Progress is not saved"
	label.position = Vector2(24, 866)
	label.add_theme_font_size_override("font_size", 16)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(label)
	var restart := Button.new()
	restart.text = "Restart map"
	restart.position = Vector2(1400, 860)
	restart.pressed.connect(func(): get_tree().reload_current_scene())
	hud.add_child(restart)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_BACKSPACE:
		get_tree().reload_current_scene()
