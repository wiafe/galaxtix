class_name VectorFont
## Stroke fonts loaded from res://fonts/<name>.json (Hershey-derived: public domain, drawn for
## vector displays). Text is rendered through ScopeLines so it glows and wobbles like everything else.
## JSON shape: { "cap": 21, "base": 9, "glyphs": { "A": { "adv": 18, "left": -9, "strokes": [[[x,y],...],...] } } }
## Glyph coordinates have y down, baseline at `base`, cap top at `base - cap`.

static var current := "futural"   # FxSettings.font (HUD and body)
static var display := "futuram"   # FxSettings.title_font (big titles)
static var tracking := 1.0        # FxSettings.font_tracking (advance multiplier)
static var _cache := {}
# Bounded cache of local outlines; moving text reuses the same geometry.
const DRAW_CACHE_LIMIT := 512
static var _draw_cache := {}


static func get_font(name: String) -> Dictionary:
	if _cache.has(name):
		return _cache[name]
	var path := "res://fonts/%s.json" % name
	var font := {"cap": 21.0, "base": 9.0, "glyphs": {}}
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			font.cap = float(parsed.get("cap", 21))
			font.base = float(parsed.get("base", 9))
			# convert to packed arrays once so drawing is cheap
			for ch in parsed.glyphs:
				var g: Dictionary = parsed.glyphs[ch]
				var strokes: Array[PackedVector2Array] = []
				for stroke in g.strokes:
					var pts := PackedVector2Array()
					for p in stroke:
						pts.append(Vector2(p[0], p[1]))
					strokes.append(pts)
				font.glyphs[ch] = {"adv": float(g.adv), "left": float(g.left), "strokes": strokes}
	else:
		push_warning("VectorFont: missing font file " + path)
	_cache[name] = font
	return font


static func _glyph(font: Dictionary, ch: String) -> Dictionary:
	var g = font.glyphs.get(ch)
	if g == null:
		g = font.glyphs.get(ch.to_upper())
	if g == null:
		g = font.glyphs.get(ch.to_lower())
	return g if g != null else {}


static func width(text: String, size: float, name := "") -> float:
	var font := get_font(name if name != "" else current)
	var s: float = size / font.cap
	var w := 0.0
	for ch in text:
		var g := _glyph(font, ch)
		w += (g.adv if not g.is_empty() else font.cap * 0.5) * s * tracking
	return w


## The stroke polylines of a string in screen space (for drawing, tracing, or zapping).
## pos.y is the cap top (text top). size = cap height in pixels. align: 0 left, 1 center, 2 right.
static func paths(text: String, pos: Vector2, size: float, align := 0, name := "") -> Array[PackedVector2Array]:
	var font := get_font(name if name != "" else current)
	var s: float = size / font.cap
	var cap_top: float = font.base - font.cap
	var x := pos.x
	if align == 1:
		x -= width(text, size, name) * 0.5
	elif align == 2:
		x -= width(text, size, name)
	var out: Array[PackedVector2Array] = []
	for ch in text:
		var g := _glyph(font, ch)
		if g.is_empty():
			x += font.cap * 0.5 * s * tracking
			continue
		var left: float = g.left
		for stroke in g.strokes:
			var pts := PackedVector2Array()
			for p in stroke:
				pts.append(Vector2(x + (p.x - left) * s, pos.y + (p.y - cap_top) * s))
			out.append(pts)
		x += g.adv * s * tracking
	return out


static func draw(lines: ScopeLines, text: String, pos: Vector2, size: float, color: Color,
		wob := 0.0, sl := 0.0, align := 0, thick := 1.0, name := "") -> void:
	var font_name := name if name != "" else current
	var key := [font_name, text, size, align, tracking]
	if not _draw_cache.has(key):
		if _draw_cache.size() >= DRAW_CACHE_LIMIT:
			_draw_cache.erase(_draw_cache.keys()[0])
		_draw_cache[key] = paths(text, Vector2.ZERO, size, align, font_name)
	for stroke in _draw_cache[key]:
		var pts: PackedVector2Array = stroke
		if pts.size() == 1:
			lines.seg(pts[0] + pos, pts[0] + pos, color, wob, sl, thick)
		for i in range(pts.size() - 1):
			lines.seg(pts[i] + pos, pts[i + 1] + pos, color, wob, sl, thick)
