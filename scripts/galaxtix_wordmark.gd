extends Node2D
## Filled, angular lettering drawn as geometry through the game's CRT pipeline.
## Based on the capsule's broad strokes, clipped corners and triangular A counters.
const GLYPHS := {
	"G": {"width": 92, "parts": [[[28,0],[92,0],[92,26],[40,26],[25,41],[25,62],[39,76],[68,76],[68,62],[47,62],[47,40],[92,40],[92,100],[27,100],[0,73],[0,28]]]},
	"A": {"width": 100, "parts": [[[50,0],[0,55],[0,100],[26,100],[26,66],[50,34]], [[50,0],[100,55],[100,100],[74,100],[74,66],[50,34]], [[22,62],[78,62],[78,82],[22,82]]]},
	"L": {"width": 76, "parts": [[[0,0],[28,0],[28,74],[76,74],[76,100],[0,100]]]},
	"X": {"width": 100, "parts": [[[0,0],[32,0],[50,28],[68,0],[100,0],[67,50],[100,100],[68,100],[50,72],[32,100],[0,100],[33,50]]]},
	"T": {"width": 98, "parts": [[[0,0],[98,0],[98,28],[63,28],[63,100],[35,100],[35,28],[0,28]]]},
	"I": {"width": 28, "parts": [[[0,0],[28,0],[28,100],[0,100]]]},
}

var ink := Color(0.72, 0.9, 1.0):
	set(value):
		ink = value
		queue_redraw()

static func paths(rect: Rect2) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var cursor := 0.0
	for letter in "GALAXTIX":
		var glyph: Dictionary = GLYPHS[letter]
		for part in glyph.parts:
			var polygon := PackedVector2Array()
			for point in part:
				polygon.append(rect.position + Vector2((point[0] + cursor) / 750.0 * rect.size.x, point[1] / 100.0 * rect.size.y))
			result.append(polygon)
		cursor += float(glyph.width) + 8.0
	return result

func _draw() -> void:
	for polygon in paths(Rect2(0, 0, 750, 100)):
		draw_colored_polygon(polygon, ink)
