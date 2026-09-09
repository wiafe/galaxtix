extends Node
## Shared keyboard/gamepad actions. Button names follow Godot's physical layout.
const DEADZONE := 0.35
const KEYS := {
	"move_left": [KEY_LEFT, KEY_A], "move_right": [KEY_RIGHT, KEY_D],
	"move_up": [KEY_UP, KEY_W], "move_down": [KEY_DOWN, KEY_S],
	"draw": [KEY_SPACE], "slow": [KEY_SHIFT],
	"confirm": [KEY_ENTER, KEY_KP_ENTER], "launch": [KEY_SPACE],
	"abort": [KEY_ESCAPE], "special": [KEY_E, KEY_CTRL], "tab": [KEY_TAB],
	"br_harden": [KEY_Q], "br_overdrive": [KEY_E],
	"br_host": [KEY_H], "br_join": [KEY_J], "br_invite": [KEY_I],
	"reroll": [KEY_R],
}
const BUTTONS := {
	"move_left": [JOY_BUTTON_DPAD_LEFT], "move_right": [JOY_BUTTON_DPAD_RIGHT],
	"move_up": [JOY_BUTTON_DPAD_UP], "move_down": [JOY_BUTTON_DPAD_DOWN],
	"draw": [JOY_BUTTON_A], "slow": [JOY_BUTTON_LEFT_SHOULDER],
	"confirm": [JOY_BUTTON_A], "launch": [JOY_BUTTON_A],
	"abort": [JOY_BUTTON_B, JOY_BUTTON_START],
	"special": [JOY_BUTTON_X, JOY_BUTTON_RIGHT_SHOULDER],
	"tab": [JOY_BUTTON_LEFT_SHOULDER],
	"br_harden": [JOY_BUTTON_Y], "br_overdrive": [JOY_BUTTON_X, JOY_BUTTON_RIGHT_SHOULDER],
	"br_host": [JOY_BUTTON_X], "br_join": [JOY_BUTTON_Y],
	"br_invite": [JOY_BUTTON_BACK], "reroll": [JOY_BUTTON_Y],
}
const AXES := {
	"move_left": [[JOY_AXIS_LEFT_X, -1.0]], "move_right": [[JOY_AXIS_LEFT_X, 1.0]],
	"move_up": [[JOY_AXIS_LEFT_Y, -1.0]], "move_down": [[JOY_AXIS_LEFT_Y, 1.0]],
	"draw": [[JOY_AXIS_TRIGGER_LEFT, 1.0], [JOY_AXIS_TRIGGER_RIGHT, 1.0]],
}
var using_controller := false
var controller_id := -1
var controller_family := "xbox"
var hint_pattern := RegEx.new()
var hint_cache := {}

func _ready() -> void:
	setup_actions()
	hint_pattern.compile("\\b(ENTER/SPACE|ARROWS / WASD|ARROWS|WASD|ENTER|SPACE|SHIFT|ESC|TAB)\\b")
	Input.joy_connection_changed.connect(_controller_connection_changed)
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		use_controller(pads[0])

func setup_actions() -> void:
	for action in KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, DEADZONE)
		for code in KEYS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = code
			_add_binding(action, event)
		for button in BUTTONS[action]:
			var event := InputEventJoypadButton.new()
			event.device = -1
			event.button_index = button
			_add_binding(action, event)
		for axis in AXES.get(action, []):
			var event := InputEventJoypadMotion.new()
			event.device = -1
			event.axis = axis[0]
			event.axis_value = axis[1]
			_add_binding(action, event)

func _add_binding(action: String, event: InputEvent) -> void:
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)

func _input(event: InputEvent) -> void:
	observe_input(event)

func observe_input(event: InputEvent) -> void:
	if (event is InputEventJoypadButton and event.pressed) or (event is InputEventJoypadMotion and absf(event.axis_value) > DEADZONE):
		use_controller(event.device)
	elif (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed) or (event is InputEventMouseMotion and event.relative.length() > 2.0):
		using_controller = false

func use_controller(device: int) -> void:
	using_controller = true
	controller_id = device
	controller_family = family_for_name(Input.get_joy_name(device))

func family_for_name(device_name: String) -> String:
	var lower := device_name.to_lower()
	if "playstation" in lower or "dualshock" in lower or "dualsense" in lower or "ps4" in lower or "ps5" in lower:
		return "playstation"
	if "switch" in lower or "nintendo" in lower or "joy-con" in lower:
		return "nintendo"
	return "xbox"

func _controller_connection_changed(device: int, connected: bool) -> void:
	if not connected and device == controller_id:
		controller_id = -1
		using_controller = false

func button_label(button: int) -> String:
	var labels := {
		JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
		JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
		JOY_BUTTON_BACK: "VIEW", JOY_BUTTON_START: "START",
	}
	if controller_family == "playstation":
		labels.merge({JOY_BUTTON_A: "CROSS", JOY_BUTTON_B: "CIRCLE", JOY_BUTTON_X: "SQUARE", JOY_BUTTON_Y: "TRIANGLE", JOY_BUTTON_LEFT_SHOULDER: "L1", JOY_BUTTON_RIGHT_SHOULDER: "R1", JOY_BUTTON_BACK: "SHARE", JOY_BUTTON_START: "OPTIONS"}, true)
	elif controller_family == "nintendo":
		labels.merge({JOY_BUTTON_A: "B", JOY_BUTTON_B: "A", JOY_BUTTON_X: "Y", JOY_BUTTON_Y: "X", JOY_BUTTON_LEFT_SHOULDER: "L", JOY_BUTTON_RIGHT_SHOULDER: "R", JOY_BUTTON_BACK: "MINUS", JOY_BUTTON_START: "PLUS"}, true)
	return labels.get(button, "PAD")

func action_label(action: String, keyboard: String) -> String:
	return button_label(BUTTONS[action][0]) if using_controller else keyboard

## Only pass control instructions here, never arbitrary narrative or player text.
func hint(text: String) -> String:
	if not using_controller:
		return text
	var cache_key := controller_family + ":" + text
	if hint_cache.has(cache_key):
		return hint_cache[cache_key]
	var replacements := {
		"ENTER/SPACE": action_label("confirm", "ENTER"), "ENTER": action_label("confirm", "ENTER"),
		"SPACE": action_label("draw", "SPACE"), "SHIFT": action_label("slow", "SHIFT"),
		"ESC": action_label("abort", "ESC"), "TAB": action_label("tab", "TAB"),
		"ARROWS / WASD": "D-PAD / STICK", "ARROWS": "D-PAD/STICK", "WASD": "STICK",
	}
	var matches := hint_pattern.search_all(text)
	for index in range(matches.size() - 1, -1, -1):
		var item: RegExMatch = matches[index]
		text = text.substr(0, item.get_start()) + replacements[item.get_string()] + text.substr(item.get_end())
	hint_cache[cache_key] = text
	return text

func direction() -> Vector2i:
	var movement := Input.get_vector("move_left", "move_right", "move_up", "move_down", DEADZONE)
	if movement == Vector2.ZERO:
		return Vector2i.ZERO
	# Grid movement stays cardinal; a mostly vertical stick must not turn sideways.
	if absf(movement.x) >= absf(movement.y):
		return Vector2i(int(signf(movement.x)), 0)
	return Vector2i(0, int(signf(movement.y)))

func event_pressed(event: InputEvent, action: String) -> bool:
	if event is InputEventJoypadMotion:
		return event.is_action_pressed(action, false, true) and Input.is_action_just_pressed_by_event(action, event, true)
	return event.is_action_pressed(action)
