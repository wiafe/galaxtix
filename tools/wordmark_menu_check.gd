extends "res://tools/steam_capture.gd"
## Check menu entry/exit so the logo cannot remain over a game mode.
func _ready() -> void:
	call_deferred("check")

func check() -> void:
	setup_capture()
	main.game.go_title()
	main.game.title_t = 2.0
	main.game.draw()
	assert(main.game.title_wordmark.visible)
	var logo = main.game.title_wordmark
	main.game.title_sel = main.game.TITLE_ITEMS.find("ROGUELITE")
	main.game.activate_title_item()
	main.game.draw()
	assert(not logo.visible, "Exit must hide the filled title")
	main.game.update_title(0.6)
	main.game.draw()
	assert(main.game.state == Game.State.ROGUELITE and not logo.visible)
	main.game.go_title()
	main.game.draw()
	assert(not logo.visible, "Power-on starts with the logo hidden")
	main.game.title_t = 2.0
	main.game.draw()
	assert(main.game.title_wordmark == logo and logo.visible, "Returning reuses the logo")
	print("WORDMARK MENU PASS: enter, exit into roguelite, return, reuse")
	get_tree().quit()
