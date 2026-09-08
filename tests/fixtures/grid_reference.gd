extends Game
## Frozen pre-optimization algorithms used only as a parity oracle.

func recompute_border() -> void:
	border_cells.clear()
	for y in grid_height:
		for x in grid_width:
			var i := idx(x, y)
			var b := 0
			if cells[i] == CLAIMED:
				for o in OFFS8:
					var nx: int = x + o.x
					var ny: int = y + o.y
					if nx >= 0 and ny >= 0 and nx < grid_width and ny < grid_height and cells[idx(nx, ny)] != CLAIMED and cells[idx(nx, ny)] != ROCK:
						b = 1
						break
			border[i] = b
			if b == 1:
				border_cells.append(Vector2i(x, y))


func rebuild_coast() -> void:
	# coast = every grid edge between claimed and unclaimed cells, merged into runs
	coast = PackedVector2Array()
	for y in range(grid_height + 1):
		var run_start := -1
		for x in range(grid_width + 1):
			var b := false
			if x < grid_width:
				b = _open(x, y - 1) != _open(x, y)
			if b and run_start < 0:
				run_start = x
			elif not b and run_start >= 0:
				coast.append(Vector2(FX + run_start * CELL, FY + y * CELL))
				coast.append(Vector2(FX + x * CELL, FY + y * CELL))
				run_start = -1
	for x in range(grid_width + 1):
		var run_start := -1
		for y in range(grid_height + 1):
			var b := false
			if y < grid_height:
				b = _open(x - 1, y) != _open(x, y)
			if b and run_start < 0:
				run_start = y
			elif not b and run_start >= 0:
				coast.append(Vector2(FX + x * CELL, FY + run_start * CELL))
				coast.append(Vector2(FX + x * CELL, FY + y * CELL))
				run_start = -1


func update_fill() -> void:
	var dither := int(cur_gal().dither)
	for y in grid_height:
		for x in grid_width:
			if cells[idx(x, y)] == CLAIMED:
				var on := false
				match dither:
					0: on = ((x + y) & 1) == 0          # checker
					1: on = (y & 1) == 0                # scanline stripes
					_: on = (x & 1) == 0 and (y & 1) == 0   # dots
				var v := 1.0 if on else 0.5
				fill_img.set_pixel(x, y, Color(v, v, v, 1.0))
			else:
				fill_img.set_pixel(x, y, Color(0, 0, 0, 0))
	fill_tex.update(fill_img)
	fill.modulate = fill_color()
