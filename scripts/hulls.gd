class_name Hulls
## 3D wireframe hulls for the ship bay: a few points and edges per ship, spun and projected
## orthographically into beams. Elite-style, and cheap.

const HULLS := {
	"surveyor": {
		"pts": [Vector3(0, 0, 1.6), Vector3(0, 0, -1.0), Vector3(1.0, 0, -0.2), Vector3(-1.0, 0, -0.2),
			Vector3(0, 0.45, -0.1), Vector3(0, -0.45, -0.1), Vector3(0, 0.9, -0.9)],
		"edges": [[0, 2], [0, 3], [0, 4], [0, 5], [1, 2], [1, 3], [1, 4], [1, 5], [2, 4], [4, 3], [3, 5], [5, 2], [4, 6], [1, 6]],
	},
	"bulwark": {
		"pts": [Vector3(-1.1, -0.5, 0.9), Vector3(1.1, -0.5, 0.9), Vector3(1.1, 0.5, 0.9), Vector3(-1.1, 0.5, 0.9),
			Vector3(-0.6, -0.3, -1.1), Vector3(0.6, -0.3, -1.1), Vector3(0.6, 0.3, -1.1), Vector3(-0.6, 0.3, -1.1),
			Vector3(0, 0, 1.3)],
		"edges": [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4], [0, 4], [1, 5], [2, 6], [3, 7],
			[8, 0], [8, 1], [8, 2], [8, 3]],
	},
	"leaper": {
		"pts": [Vector3(0, 0, 1.2), Vector3(0, 0, -1.2), Vector3(0.6, 0, 0), Vector3(-0.6, 0, 0), Vector3(0, 0.6, 0), Vector3(0, -0.6, 0),
			Vector3(1.4, 0, 0), Vector3(0.99, 0, 0.99), Vector3(0, 0, 1.4), Vector3(-0.99, 0, 0.99), Vector3(-1.4, 0, 0),
			Vector3(-0.99, 0, -0.99), Vector3(0, 0, -1.4), Vector3(0.99, 0, -0.99)],
		"edges": [[0, 2], [0, 3], [0, 4], [0, 5], [1, 2], [1, 3], [1, 4], [1, 5], [2, 4], [4, 3], [3, 5], [5, 2],
			[6, 7], [7, 8], [8, 9], [9, 10], [10, 11], [11, 12], [12, 13], [13, 6], [2, 6], [3, 10]],
	},
	"lancer": {
		"pts": [Vector3(0, 0, 2.2), Vector3(0.5, -0.35, -1.0), Vector3(-0.5, -0.35, -1.0), Vector3(0, 0.45, -1.0),
			Vector3(0, 0, -1.4), Vector3(0, 0, 0.4), Vector3(1.3, 0, -0.9), Vector3(-1.3, 0, -0.9)],
		"edges": [[0, 1], [0, 2], [0, 3], [1, 2], [2, 3], [3, 1], [1, 4], [2, 4], [3, 4], [5, 6], [5, 7], [6, 1], [7, 2]],
	},
	"sapper": {
		"pts": [Vector3(1.0, 0.35, 0), Vector3(0.5, 0.35, 0.87), Vector3(-0.5, 0.35, 0.87), Vector3(-1.0, 0.35, 0), Vector3(-0.5, 0.35, -0.87), Vector3(0.5, 0.35, -0.87),
			Vector3(1.0, -0.35, 0), Vector3(0.5, -0.35, 0.87), Vector3(-0.5, -0.35, 0.87), Vector3(-1.0, -0.35, 0), Vector3(-0.5, -0.35, -0.87), Vector3(0.5, -0.35, -0.87),
			Vector3(0, 0.9, 0), Vector3(0, -0.9, 0)],
		"edges": [[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [5, 0], [6, 7], [7, 8], [8, 9], [9, 10], [10, 11], [11, 6],
			[0, 6], [1, 7], [2, 8], [3, 9], [4, 10], [5, 11], [12, 0], [12, 2], [12, 4], [13, 7], [13, 9], [13, 11]],
	},
}


static func project(p: Vector3, angle: float, tilt: float) -> Vector2:
	var ca := cos(angle)
	var sa := sin(angle)
	var x := p.x * ca - p.z * sa
	var z := p.x * sa + p.z * ca
	var ct := cos(tilt)
	var st := sin(tilt)
	var y := p.y * ct - z * st
	return Vector2(x, -y)


## Edge polylines of a hull in screen space, ready for ScopeLines.trace / polyline.
static func paths(id: String, center: Vector2, scale: float, angle: float, tilt: float) -> Array:
	var h: Dictionary = HULLS.get(id, HULLS["surveyor"])
	var out: Array = []
	var pts: Array = h.pts
	for e in h.edges:
		var a: Vector3 = pts[e[0]]
		var b: Vector3 = pts[e[1]]
		out.append(PackedVector2Array([center + project(a, angle, tilt) * scale, center + project(b, angle, tilt) * scale]))
	return out
