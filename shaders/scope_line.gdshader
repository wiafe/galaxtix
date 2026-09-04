// Instanced "electron beam" line renderer.
// One MultiMesh instance = one line segment, encoded as a legitimate 2D transform so every
// renderer (Forward+, Mobile, Compatibility/WebGL) treats it the same way:
//   x axis = end - start          (the segment)
//   y axis = normal * half-thick  (the beam width)
//   origin = start
//   color  = rgba
//   custom = (lfo index for start, lfo index for end, wobble amp, slop amp)
// The unit quad (x in 0..1 along, y in -1..1 across) is mapped onto the line by the model
// matrix as usual; square caps and the per-endpoint wobble are added in local space.
//
// The 64-oscillator bank is generated in the shader from the index (7-11 Hz, random amp and
// phase) rather than uploaded as a uniform array: float uniform arrays are unreliable on the
// Compatibility / WebGL path, and this needs only one float uniform.
shader_type canvas_item;
render_mode blend_add, unshaded;

uniform float lfo_time = 0.0;   // seconds, already scaled by the LFO speed setting
uniform float layer_alpha = 1.0;

float hash1(float n) {
	return fract(sin(n * 12.9898 + 78.233) * 43758.5453);
}

float lfo(int i) {
	float fi = float(i & 63);
	float inc = (7.0 + 4.0 * hash1(fi)) * 6.28318530718;
	float amp = 1.0 + 0.2 * hash1(fi + 64.0);
	float phase = 6.28318530718 * hash1(fi + 128.0);
	return sin(lfo_time * inc + phase) * amp;
}

void vertex() {
	int m1 = int(INSTANCE_CUSTOM.x + 0.5) & 63;
	int m2 = int(INSTANCE_CUSTOM.y + 0.5) & 63;
	float wob = INSTANCE_CUSTOM.z;
	float slop = INSTANCE_CUSTOM.w;

	vec2 xa = MODEL_MATRIX[0].xy;   // segment vector (world)
	vec2 ya = MODEL_MATRIX[1].xy;   // normal * full thickness (world); the quad's y runs 0..1
	float len = max(length(xa), 0.0001);
	float ht = length(ya) * 0.5;

	// wobble: every endpoint shivers by its own oscillator sample (analog instability),
	// expressed in world px and converted to local space through the inverse 2x2
	vec2 w0 = vec2(lfo(m1), lfo(m1 + 1)) * wob;
	vec2 w1 = vec2(lfo(m2), lfo(m2 + 1)) * wob;
	float det = xa.x * ya.y - xa.y * ya.x;
	mat2 inv = mat2(vec2(ya.y, -xa.y), vec2(-ya.x, xa.x)) / (abs(det) > 1e-9 ? det : 1e-9);

	vec2 c = VERTEX;                                  // unit quad corner
	float capx = ht / len;                            // square caps, so dots still light up
	vec2 wob_local = mix(inv * w0, inv * w1, c.x);
	VERTEX = vec2(c.x + (c.x * 2.0 - 1.0) * capx, c.y) + wob_local;

	// slop: endpoint brightness breathes with an oscillator (phosphor over-exposure)
	float a = clamp(COLOR.a + slop * lfo(m1), 0.0, 1.0) * layer_alpha;
	COLOR = vec4(COLOR.rgb, a);
}

void fragment() {
	COLOR = COLOR;
}
