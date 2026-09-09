@tool
extends EditorPlugin
var panel: Control

func _enter_tree() -> void:
	panel = preload("res://addons/roguelite_maps/map_panel.gd").new()
	EditorInterface.get_editor_main_screen().add_child(panel)
	panel.hide()
	panel.saved.connect(func(): EditorInterface.get_resource_filesystem().scan())
	panel.play_requested.connect(play_map)

func _exit_tree() -> void:
	if panel != null: panel.queue_free()

func _has_main_screen() -> bool:
	return true

func _get_plugin_name() -> String:
	return "Maps"

func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_base_control().get_theme_icon("TileMap", "EditorIcons")

func _make_visible(visible: bool) -> void:
	if panel != null: panel.visible = visible

func _save_external_data() -> void:
	if panel != null: panel.save_all()

func _get_unsaved_status(for_scene: String) -> String:
	if for_scene.is_empty() and panel != null and not panel.dirty.is_empty():
		return "Roguelite Maps has unsaved changes. Return to Maps to resolve any validation errors before closing."
	return ""

func play_map(map: MapDefinition, depth: int, encounter: String, ship: String) -> void:
	var config := ConfigFile.new()
	config.set_value("playtest", "stage", map.sector)
	config.set_value("playtest", "depth", depth)
	config.set_value("playtest", "encounter", encounter)
	config.set_value("playtest", "ship", ship)
	if config.save("res://.godot/map_playtest.cfg") == OK:
		EditorInterface.play_custom_scene("res://tools/map_playtest.tscn")

func _run_scene(scene: String, args: PackedStringArray) -> PackedStringArray:
	if scene == "res://tools/map_playtest.tscn":
		if not args.has("--"): args.append("--")
		args.append("--nosave")
		args.append("--no-steam")
	return args
