extends "res://tools/steam_capture.gd"
## Refresh only the two contest screenshots without replacing the original six.
func capture_all() -> void:
	setup_capture()
	await capture_encounters()
	print("STEAM ENCOUNTER CAPTURE PASS: race and rival at 1920x1080")
	get_tree().quit()
